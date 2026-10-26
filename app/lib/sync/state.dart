/// What one device knows: its records, its outbox of unsent changes and how
/// far through the server's change feed it has read.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/crypto.dart';

enum RecordKind { file, attachment, keycheck, other }

class LocalRecord {
  LocalRecord({
    required this.id,
    required this.kind,
    this.path,
    this.content,
    this.blobId,
    this.size,
    this.version = 0,
    this.deleted = false,
  });

  final String id;
  RecordKind kind;
  String? path;
  String? content;
  String? blobId;
  int? size;

  /// Version the server last confirmed (0 = never pushed).
  int version;
  bool deleted;

  Map<String, Object?> payload() {
    switch (kind) {
      case RecordKind.file:
        return deleted ? {'type': 'deleted', 'path': path} : {'type': 'file', 'path': path, 'content': content};
      case RecordKind.attachment:
        return deleted ? {'type': 'deleted', 'path': path} : {'type': 'attachment', 'path': path, 'blob': blobId, 'size': size};
      case RecordKind.keycheck:
        return keycheckPayload;
      case RecordKind.other:
        return {'type': 'other'};
    }
  }

  static LocalRecord fromPayload(String id, Map<String, Object?> p, {required int version, required bool deleted}) {
    final type = p['type'];
    final kind = switch (type) {
      'file' => RecordKind.file,
      'attachment' => RecordKind.attachment,
      'keycheck' => RecordKind.keycheck,
      'deleted' => RecordKind.file,
      _ => RecordKind.other,
    };
    return LocalRecord(
      id: id,
      kind: kind,
      path: p['path'] as String?,
      content: p['content'] as String?,
      blobId: p['blob'] as String?,
      size: (p['size'] as num?)?.toInt(),
      version: version,
      deleted: deleted || type == 'deleted',
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'path': path,
    'content': content,
    'blob': blobId,
    'size': size,
    'version': version,
    'deleted': deleted,
  };

  static LocalRecord fromJson(Map<String, dynamic> j) => LocalRecord(
    id: j['id'] as String,
    kind: RecordKind.values.byName(j['kind'] as String),
    path: j['path'] as String?,
    content: j['content'] as String?,
    blobId: j['blob'] as String?,
    size: j['size'] as int?,
    version: j['version'] as int,
    deleted: j['deleted'] as bool,
  );
}

class PendingChange {
  PendingChange({
    required this.changeId,
    required this.recordId,
    required this.payload,
    required this.deleted,
    this.base,
    this.attempted = false,
  });

  final String changeId;
  final String recordId;
  Map<String, Object?> payload;
  bool deleted;

  /// Version this edit was made from. Null means "after the change queued
  /// before it for the same record", filled in once that one is confirmed.
  int? base;

  /// Sent at least once. A sent change is never altered: the server may
  /// already have applied it, and a retry must mean the same thing.
  bool attempted;

  Map<String, Object?> toJson() => {
    'change_id': changeId,
    'record_id': recordId,
    'payload': payload,
    'deleted': deleted,
    'base': base,
    'attempted': attempted,
  };

  static PendingChange fromJson(Map<String, dynamic> j) => PendingChange(
    changeId: j['change_id'] as String,
    recordId: j['record_id'] as String,
    payload: Map<String, Object?>.from(j['payload'] as Map),
    deleted: j['deleted'] as bool,
    base: j['base'] as int?,
    attempted: j['attempted'] as bool,
  );
}

class Connection {
  Connection({required this.serverUrl, required this.token, required this.deviceId, required this.deviceName});
  final String serverUrl;
  final String token;
  final String deviceId;
  final String deviceName;

  Map<String, Object?> toJson() => {'server': serverUrl, 'token': token, 'device_id': deviceId, 'device_name': deviceName};
  static Connection fromJson(Map<String, dynamic> j) => Connection(
    serverUrl: j['server'] as String,
    token: j['token'] as String,
    deviceId: j['device_id'] as String,
    deviceName: j['device_name'] as String,
  );
}

class VaultState {
  VaultState({this.connection});

  Connection? connection;
  final Map<String, LocalRecord> records = {};
  final List<PendingChange> outbox = [];

  /// Attachment ids whose encrypted bytes still need uploading.
  final Set<String> pendingBlobs = {};
  int since = 0;
  DateTime? lastSync;

  Iterable<LocalRecord> get liveFiles => records.values.where((r) => !r.deleted && r.kind == RecordKind.file && r.path != null);

  LocalRecord? byPath(String path) {
    for (final r in records.values) {
      if (!r.deleted && r.path == path) return r;
    }
    return null;
  }

  bool hasPending(String recordId) => outbox.any((c) => c.recordId == recordId);

  Map<String, Object?> toJson() => {
    'v': 1,
    'connection': connection?.toJson(),
    'records': records.values.map((r) => r.toJson()).toList(),
    'outbox': outbox.map((c) => c.toJson()).toList(),
    'pending_blobs': pendingBlobs.toList(),
    'since': since,
    'last_sync': lastSync?.toIso8601String(),
  };

  static VaultState fromJson(Map<String, dynamic> j) {
    final s = VaultState(connection: j['connection'] == null ? null : Connection.fromJson(j['connection'] as Map<String, dynamic>));
    for (final r in j['records'] as List) {
      final rec = LocalRecord.fromJson(r as Map<String, dynamic>);
      s.records[rec.id] = rec;
    }
    s.outbox.addAll((j['outbox'] as List).map((c) => PendingChange.fromJson(c as Map<String, dynamic>)));
    s.pendingBlobs.addAll((j['pending_blobs'] as List? ?? const []).cast<String>());
    s.since = j['since'] as int;
    final last = j['last_sync'] as String?;
    s.lastSync = last == null ? null : DateTime.parse(last);
    return s;
  }
}

/// Saves the device state encrypted with the vault key, atomically.
class StateStore {
  StateStore(this.dir);
  final Directory dir;

  File get _file => File('${dir.path}/state.comb');
  Directory get blobCache => Directory('${dir.path}/blobs');

  bool get exists => _file.existsSync();

  Future<VaultState> load(VaultKey key) async {
    if (!_file.existsSync()) return VaultState();
    final clear = await openLocal(key, Uint8List.fromList(await _file.readAsBytes()));
    return VaultState.fromJson(jsonDecode(utf8.decode(clear)) as Map<String, dynamic>);
  }

  Future<void> _queue = Future.value();

  /// Saves are queued, so two saves never overlap. Each one writes the
  /// state as it is when its turn comes, so the newest state always wins.
  Future<void> save(VaultKey key, VaultState state) {
    final next = _queue.then((_) => _write(key, state));
    _queue = next.catchError((_) {});
    return next;
  }

  Future<void> _write(VaultKey key, VaultState state) async {
    await dir.create(recursive: true);
    final sealed = await sealLocal(key, utf8.encode(jsonEncode(state.toJson())));
    // A unique temporary name, so even two app instances never clash.
    final tmp = File('${_file.path}.${newChangeId()}.tmp');
    await tmp.writeAsBytes(sealed, flush: true);
    await tmp.rename(_file.path);
  }

  Future<void> putBlob(String id, List<int> encrypted) async {
    await blobCache.create(recursive: true);
    await File('${blobCache.path}/$id').writeAsBytes(encrypted, flush: true);
  }

  Future<Uint8List?> getBlob(String id) async {
    final f = File('${blobCache.path}/$id');
    return f.existsSync() ? f.readAsBytes() : null;
  }

  Future<void> wipe() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
