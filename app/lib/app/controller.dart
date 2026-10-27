/// The app's state and everything it can do. Screens read from here and
/// call its methods; it talks to the lock, the sync engine, the library and
/// the markdown folder.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import '../core/crypto.dart';
import '../data/library.dart';
import '../data/models.dart';
import '../data/task_body.dart';
import '../data/views.dart';
import '../security/app_lock.dart';
import '../sync/engine.dart';
import '../sync/engine_files.dart';
import '../sync/folder_mirror.dart';
import '../sync/state.dart';
import 'prefs.dart';

enum Phase { loading, setup, locked, ready }

enum NavView { inbox, today, upcoming, calendar, matrix, board, notes, review, space, search }

enum SyncStatus { idle, syncing, synced, offline, signedOut, error }

class AppController extends ChangeNotifier {
  AppController({
    required this.appDir,
    required this.lock,
    this.httpClient,
    this.syncEvery = const Duration(seconds: 20),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Directory appDir;
  final AppLock lock;
  final http.Client? httpClient;
  final Duration syncEvery;
  final DateTime Function() _clock;

  Phase phase = Phase.loading;
  Prefs prefs = Prefs();

  VaultKey? _key;
  late final StateStore _store = StateStore(Directory('${appDir.path}/data'));
  SyncEngine? engine;
  Library? library;
  FolderMirror? mirror;
  EngineFiles? _files;

  // What the person is looking at.
  NavView view = NavView.today;
  String? spaceId;
  Set<String>? filterIds;
  String? selectedTaskPath;
  String? selectedNotePath;
  String searchQuery = '';

  SyncStatus syncStatus = SyncStatus.idle;
  String? syncMessage;

  Timer? _syncTimer;
  Timer? _syncSoon;
  Timer? _diskSoon;
  final Set<String> _diskPending = {};
  DateTime? _backgroundSince;
  bool quickUnlockAvailable = false;

  Views get views => Views(library!, filter: SpaceFilter(filterIds));
  Connection? get connection => engine?.state.connection;
  DateTime get now => _clock();

  // ------------------------------------------------------------ start

  Future<void> start() async {
    prefs = await Prefs.load(appDir);
    if (!lock.isSetUp || !_store.exists) {
      phase = Phase.setup;
    } else {
      quickUnlockAvailable = await lock.canQuickUnlock();
      phase = Phase.locked;
    }
    notifyListeners();
  }

  Future<void> savePrefs() async {
    await prefs.save(appDir);
    notifyListeners();
  }

  // ------------------------------------------------------------ unlock

  Future<bool> unlockQuick() async {
    final key = await lock.quickUnlock();
    if (key == null) return false;
    await _open(key);
    return true;
  }

  Future<void> unlockWithPassword(String password) async {
    final key = await lock.unlockWithPassword(password);
    await _open(key);
  }

  /// Leaving the app for longer than the chosen time locks it again.
  void onBackground() => _backgroundSince = _clock();

  Future<void> onForeground() async {
    final since = _backgroundSince;
    _backgroundSince = null;
    if (phase != Phase.ready || since == null || !lock.isSetUp) return;
    final away = _clock().difference(since);
    if (away >= lock.settings.relock.duration) {
      await lockNow();
    } else {
      unawaited(syncNow());
    }
  }

  Future<void> lockNow() async {
    await _close();
    quickUnlockAvailable = await lock.canQuickUnlock();
    phase = Phase.locked;
    notifyListeners();
  }

  // ------------------------------------------------------------ setup

  VaultKey? _pendingKey;
  VaultState? _pendingState;
  String? setupRecoveryKey;

  CombApi _api(String url, {String? token}) => CombApi(url, client: httpClient, token: token);

  Future<void> checkServer(String url) async {
    final h = await _api(url).health();
    if (h['status'] != 'ok') throw ApiException(500, 'That address did not answer like a Comb server.');
  }

  Future<bool> serverIsNew(String url) async => (await _api(url).health())['initialised'] != true;

  /// First device: turns the server's one-time setup code into an account
  /// and makes the key. Returns the recovery key to show once.
  Future<String> createAccount({required String serverUrl, required String setupCode, required String deviceName}) async {
    final creds = await _api(serverUrl).setup(setupCode.trim(), deviceName.trim());
    final key = VaultKey.generate();
    final state = VaultState(
      connection: Connection(serverUrl: serverUrl, token: creds.token, deviceId: creds.deviceId, deviceName: deviceName.trim()),
    );
    final engine = SyncEngine(
      api: _api(serverUrl, token: creds.token),
      key: key,
      state: state,
      store: _store,
    );
    engine.writeKeycheck();
    await _store.save(key, state);
    _pendingKey = key;
    _pendingState = state;
    setupRecoveryKey = key.recoveryKey();
    return setupRecoveryKey!;
  }

  /// Another device: joins with the link from an existing device's QR code.
  Future<void> joinWithLink({required String link, required String deviceName}) async {
    final p = parsePairingLink(link);
    await joinWithCode(serverUrl: p.server, code: p.code, recoveryKey: p.recoveryKey, deviceName: deviceName);
  }

  Future<void> joinWithCode({
    required String serverUrl,
    required String code,
    required String recoveryKey,
    required String deviceName,
  }) async {
    final key = VaultKey.fromRecoveryKey(recoveryKey);
    final creds = await _api(serverUrl).claimPairing(code.trim(), deviceName.trim());
    final state = VaultState(
      connection: Connection(serverUrl: serverUrl, token: creds.token, deviceId: creds.deviceId, deviceName: deviceName.trim()),
    );
    final engine = SyncEngine(
      api: _api(serverUrl, token: creds.token),
      key: key,
      state: state,
      store: _store,
    );
    if (!await engine.verifyKey()) {
      await _api(serverUrl, token: creds.token).revokeDevice(creds.deviceId).catchError((_) {});
      throw const FormatException('That recovery key does not match this account.');
    }
    await _store.save(key, state);
    _pendingKey = key;
    _pendingState = state;
  }

  Future<void> setupPassword(String password, {required bool useBiometrics}) async {
    await lock.setPassword(_pendingKey!, password, useBiometrics: useBiometrics);
  }

  Future<bool> biometricsAvailable() => lock.biometrics.available();

  /// Opens the account at the end of setup (before Spaces are made).
  Future<void> finishSetupOpen() async {
    await _open(_pendingKey!, initialState: _pendingState, keepSetupPhase: true);
    _pendingKey = null;
    _pendingState = null;
  }

  void completeSetup() {
    setupRecoveryKey = null;
    phase = Phase.ready;
    notifyListeners();
  }

  /// Opens an account directly (tests and screenshots only).
  @visibleForTesting
  Future<void> debugOpen(VaultKey key, VaultState state) => _open(key, initialState: state);

  // ------------------------------------------------------------ open / close

  Future<void> _open(VaultKey key, {VaultState? initialState, bool keepSetupPhase = false}) async {
    _key = key;
    final state = initialState ?? await _store.load(key);
    final conn = state.connection!;
    engine = SyncEngine(
      api: _api(conn.serverUrl, token: conn.token),
      key: key,
      state: state,
      store: _store,
      clock: _clock,
    );
    _files = EngineFiles(engine!, onChanged: _onLocalChange);
    library = Library(_files!, clock: _clock);
    // The folder is mirrored in the background: a slow or broken folder
    // must never keep the app from opening.
    _mirrorStart = _startMirror();
    unawaited(_mirrorStart);
    if (!keepSetupPhase) phase = Phase.ready;
    notifyListeners();
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(syncEvery, (_) => syncNow());
    unawaited(syncNow());
  }

  /// Why the markdown folder isn't being kept up to date, if it isn't.
  String? mirrorError;

  /// True while the markdown folder is being read for the first time.
  bool mirrorStarting = false;

  /// How long the first read of the markdown folder may take.
  @visibleForTesting
  Duration mirrorStartTimeout = const Duration(minutes: 2);

  int _mirrorGeneration = 0;
  Future<void>? _mirrorStart;

  /// Completes once the markdown folder has been read (or given up on).
  @visibleForTesting
  Future<void> get mirrorSettled => _mirrorStart ?? Future.value();

  Future<void> _startMirror() async {
    final generation = ++_mirrorGeneration;
    final old = mirror;
    mirror = null;
    await old?.stop();
    mirrorError = null;
    final path = prefs.folderPath;
    if (path == null || _files == null) {
      mirrorStarting = false;
      if (!_disposed) notifyListeners();
      return;
    }
    mirrorStarting = true;
    if (!_disposed) notifyListeners();
    final m = FolderMirror(Directory(path), _files!, deviceName: connection?.deviceName ?? 'this device');
    m.onImported = _onImported;
    try {
      final imported = await m.reconcileAll().timeout(mirrorStartTimeout);
      if (generation != _mirrorGeneration || _files == null) {
        await m.stop();
        return;
      }
      mirror = m;
      if (imported.isNotEmpty) _onImported(imported);
      m.startWatching();
    } catch (e) {
      await m.stop();
      if (generation != _mirrorGeneration) return;
      mirrorError = e is TimeoutException
          ? 'The markdown folder took too long to read, so Comb stopped using it. Cloud folders that download files on demand often do this. Choose a folder on this Mac in Settings → Sync and folder.'
          : 'Comb couldn\'t use the markdown folder: ${_plain(e)}. Choose another folder in Settings → Sync and folder.';
    } finally {
      if (generation == _mirrorGeneration) mirrorStarting = false;
      if (!_disposed) notifyListeners();
    }
  }

  static String _plain(Object e) {
    if (e is FileSystemException) return e.osError?.message ?? e.message;
    return e.toString();
  }

  Future<void> _close() async {
    _mirrorGeneration++;
    mirrorStarting = false;
    _syncTimer?.cancel();
    _syncSoon?.cancel();
    _diskSoon?.cancel();
    if (engine != null && _key != null) await _store.save(_key!, engine!.state);
    await mirror?.stop();
    mirror = null;
    engine = null;
    library = null;
    _files = null;
    _key = null;
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _syncSoon?.cancel();
    _diskSoon?.cancel();
    mirror?.stop();
    super.dispose();
  }

  // ------------------------------------------------------------ changes

  void _onLocalChange(Set<String> paths) {
    _diskPending.addAll(paths);
    _diskSoon?.cancel();
    _diskSoon = Timer(const Duration(milliseconds: 300), _flushDisk);
    _syncSoon?.cancel();
    _syncSoon = Timer(const Duration(seconds: 2), syncNow);
    if (engine != null && _key != null) unawaited(_store.save(_key!, engine!.state));
  }

  Future<void> _flushDisk() async {
    final paths = Set.of(_diskPending);
    _diskPending.clear();
    await mirror?.pushToDisk(paths);
  }

  void _onImported(Set<String> paths) {
    final lib = library;
    if (lib == null) return;
    lib.reload();
    for (final p in paths) {
      final n = lib.notes.where((n) => n.path == p).firstOrNull;
      if (n != null) lib.syncTicksFromNote(n);
    }
    notifyListeners();
    _syncSoon?.cancel();
    _syncSoon = Timer(const Duration(seconds: 1), syncNow);
  }

  Future<void> syncNow() async {
    final e = engine;
    if (e == null) return;
    syncStatus = SyncStatus.syncing;
    notifyListeners();
    final report = await e.sync();
    if (engine != e || _disposed) return; // locked or closed meanwhile
    if (report.ok) {
      syncStatus = SyncStatus.synced;
      syncMessage = report.conflicts.isEmpty ? null : 'Edited on two devices at once: both versions kept.';
    } else if (report.error!.isAuth) {
      syncStatus = SyncStatus.signedOut;
      syncMessage = 'This device was removed from your account.';
    } else if (report.error!.isOffline) {
      syncStatus = SyncStatus.offline;
      syncMessage = null;
    } else {
      syncStatus = SyncStatus.error;
      syncMessage = report.error!.message;
    }
    if (report.changedPaths.isNotEmpty) {
      library?.reload();
      await mirror?.pushToDisk(report.changedPaths);
    }
    notifyListeners();
  }

  String get syncLabel => switch (syncStatus) {
    SyncStatus.idle || SyncStatus.syncing => 'Syncing · end-to-end encrypted',
    SyncStatus.synced => 'Synced · end-to-end encrypted',
    SyncStatus.offline => 'Offline · changes are saved',
    SyncStatus.signedOut => 'Signed out of the server',
    SyncStatus.error => 'Sync problem: ${syncMessage ?? ''}',
  };

  // ------------------------------------------------------------ navigation

  void go(NavView v, {String? space}) {
    view = v;
    spaceId = space;
    // Moving to another view closes the open note or task.
    selectedNotePath = null;
    selectedTaskPath = null;
    if (v != NavView.search) searchQuery = '';
    notifyListeners();
  }

  void setFilter(Set<String>? ids) {
    filterIds = ids;
    notifyListeners();
  }

  void selectTask(Task? t) {
    selectedTaskPath = t?.path;
    selectedNotePath = null;
    notifyListeners();
  }

  void selectNote(Note? n) {
    selectedNotePath = n?.path;
    selectedTaskPath = null;
    notifyListeners();
  }

  Task? get selectedTask => selectedTaskPath == null ? null : library?.tasks.where((t) => t.path == selectedTaskPath).firstOrNull;
  Note? get selectedNote => selectedNotePath == null ? null : library?.notes.where((n) => n.path == selectedNotePath).firstOrNull;

  void search(String q) {
    searchQuery = q;
    view = q.trim().isEmpty ? NavView.today : NavView.search;
    notifyListeners();
  }

  /// Wraps a library edit so screens refresh and the change syncs.
  T edit<T>(T Function(Library lib) change) {
    final result = change(library!);
    notifyListeners();
    return result;
  }

  // ------------------------------------------------------------ tasks and notes helpers

  Task quickAdd(String text) {
    final defaultSpace = view == NavView.space ? library!.spaceById(spaceId) : null;
    final t = edit((lib) => lib.createFromQuickAdd(text, defaultSpace: defaultSpace, source: 'manual'));
    return t;
  }

  void saveTask(Task t, {String? newTitle}) {
    final wasSelected = selectedTaskPath == t.path;
    edit((lib) => lib.saveTask(t, newTitle: newTitle));
    if (wasSelected) selectedTaskPath = t.path;
    notifyListeners();
  }

  void saveNote(Note n, {String? newTitle}) {
    final wasSelected = selectedNotePath == n.path;
    edit((lib) => lib.saveNote(n, newTitle: newTitle));
    if (wasSelected) selectedNotePath = n.path;
    notifyListeners();
  }

  Future<String> attachFile(Task t, String fileName, List<int> bytes) async {
    final d = now;
    final folder = 'Attachments/${d.year}-${d.month.toString().padLeft(2, '0')}';
    final path = '$folder/${safeName(fileName.replaceAll(RegExp(r'\.[^.]+$'), ''))}${RegExp(r'\.[^.]+$').stringMatch(fileName) ?? ''}';
    await engine!.addAttachment(path, bytes);
    t.body = (TaskBody.parse(t.body)..files.add(path)).compose();
    saveTask(t);
    _onLocalChange({path});
    return path;
  }

  Future<Uint8List?> readAttachment(String path) async {
    final rec = engine?.state.records.values.where((r) => r.path == path && r.kind == RecordKind.attachment && !r.deleted).firstOrNull;
    if (rec == null) return null;
    return engine!.readAttachment(rec.id);
  }

  // ------------------------------------------------------------ settings

  Future<void> chooseFolder(String? path) async {
    prefs.folderPath = path;
    await prefs.save(appDir);
    if (engine != null) {
      _mirrorStart = _startMirror();
      await _mirrorStart;
    }
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) async {
    final key = await lock.verifyPassword(current);
    await lock.setPassword(key, next);
  }

  Future<List<RemoteDevice>> devices() => engine!.api.devices();

  Future<void> removeDevice(String id) => engine!.api.revokeDevice(id);

  /// A QR link for adding a device. Contains the recovery key: show it only
  /// on this screen, never send it anywhere.
  Future<({String link, DateTime expires})> startPairing() async {
    final p = await engine!.api.startPairing();
    return (link: pairingLink(connection!.serverUrl, p.code, _key!.recoveryKey()), expires: p.expires);
  }

  String revealRecoveryKey() => _key!.recoveryKey();

  /// Writes tasks.csv and comb-export.json (every task, note and Space)
  /// into [folder]. Returns the files written.
  Future<List<String>> exportTo(String folder) async {
    final lib = library!;
    String cell(Object? v) {
      final s = v?.toString() ?? '';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = <String>['title,space,category,project,priority,urgent,status,due,repeat,people,created,completed,file'];
    for (final t in lib.tasks) {
      rows.add(
        [
          t.title,
          t.spaceName,
          t.category,
          t.project,
          t.priority.name,
          views.isUrgent(t),
          t.status.name,
          t.due?.serialize(),
          t.repeat?.name,
          t.people.join('; '),
          t.created,
          t.completed,
          t.path,
        ].map(cell).join(','),
      );
    }
    final stamp = isoDay(now);
    final csv = File('$folder/comb-tasks-$stamp.csv');
    await csv.writeAsString('${rows.join('\n')}\n');
    final json = File('$folder/comb-export-$stamp.json');
    await json.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'exported': now.toIso8601String(), 'spaces': lib.spaces.map((s) => s.toJson()).toList(), 'files': lib.source.snapshot()}),
    );
    return [csv.path, json.path];
  }

  /// Signs this device out and deletes its local copy (not the markdown
  /// folder, and nothing on other devices).
  Future<void> forgetThisDevice() async {
    await _close();
    await _store.wipe();
    await lock.reset();
    phase = Phase.setup;
    notifyListeners();
  }
}
