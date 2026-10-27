/// Keeps a plain markdown folder on the computer in step with Comb, both
/// ways: Comb's changes are written as files, and edits made in Obsidian
/// (or any editor) come back into Comb.
///
/// For each file it remembers the hash last seen on both sides, so it can
/// tell who changed what:
///   disk unchanged, Comb changed  -> write the file
///   Comb unchanged, disk changed  -> update Comb
///   both changed                  -> Comb's version keeps the name, the
///                                    disk version is saved as a conflict copy
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

import '../data/library.dart' show FileSource;

String contentHash(String s) => hash.sha256.convert(utf8.encode(s)).toString();

/// What the mirror needs from Comb's side.
abstract class MirrorSide implements FileSource {
  /// Attachments: folder path -> record id.
  Map<String, String> attachments();
  Future<Uint8List?> readAttachment(String recordId);
}

class FolderMirror {
  FolderMirror(this.root, this.side, {this.deviceName = 'this device'});

  final Directory root;
  final MirrorSide side;
  final String deviceName;

  /// path -> hash of the content both sides agreed on last time.
  final Map<String, String> _index = {};
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;
  Timer? _poll;
  bool _busy = false;
  final Set<String> _dirty = {};
  void Function(Set<String> changed)? onImported;

  File get _indexFile => File('${root.path}/.comb/mirror-index.json');

  static bool ignored(String rel) {
    final parts = rel.split('/');
    if (parts.any((p) => p.startsWith('.'))) return true; // .obsidian, .trash, .comb, hidden files
    return rel.endsWith('.comb-tmp');
  }

  Future<void> _loadIndex() async {
    _index.clear();
    if (_indexFile.existsSync()) {
      try {
        final j = jsonDecode(await _indexFile.readAsString()) as Map<String, dynamic>;
        j.forEach((k, v) => _index[k] = v as String);
      } catch (_) {}
    }
  }

  Future<void> _saveIndex() async {
    await _indexFile.parent.create(recursive: true);
    await _indexFile.writeAsString(jsonEncode(_index));
  }

  File _file(String rel) => File('${root.path}/$rel');

  Future<void> _writeDisk(String rel, String content) async {
    final f = _file(rel);
    await f.parent.create(recursive: true);
    final tmp = File('${f.parent.path}/.${f.uri.pathSegments.last}.comb-tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(f.path);
  }

  Future<void> _deleteDisk(String rel) async {
    final f = _file(rel);
    if (f.existsSync()) {
      await f.delete();
      await _pruneEmptyDirs(f.parent);
    }
  }

  Future<void> _pruneEmptyDirs(Directory d) async {
    var dir = d;
    while (dir.path.length > root.path.length && dir.existsSync() && dir.listSync().isEmpty) {
      await dir.delete();
      dir = dir.parent;
    }
  }

  /// Full reconcile: run at start, and whenever Comb's side changed a lot.
  Future<Set<String>> reconcileAll() async {
    await root.create(recursive: true);
    await _loadIndex();
    final paths = <String>{...side.snapshot().keys.where((p) => p.toLowerCase().endsWith('.md') && !ignored(p)), ..._index.keys};
    if (root.existsSync()) paths.addAll((await markdownFilesIn(root)).where((p) => !ignored(p)));
    if (_stopped) return {};
    final imported = await _reconcile(paths);
    await _writeAttachments();
    await _saveIndex();
    return imported;
  }

  /// Every markdown file under [dir], as paths relative to it. Hidden
  /// folders (.obsidian, .trash, .comb) are skipped without being opened.
  /// Lists asynchronously so the app never freezes on a slow folder, and
  /// stops with [FolderTooLarge] past [maxEntries] (a folder that big is
  /// not a notes folder).
  static Future<Set<String>> markdownFilesIn(Directory dir, {int maxEntries = 50000}) async {
    final out = <String>{};
    var seen = 0;
    final pending = <Directory>[dir];
    while (pending.isNotEmpty) {
      final d = pending.removeLast();
      await for (final e in d.list(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name.startsWith('.')) continue;
        if (++seen > maxEntries) throw FolderTooLarge(maxEntries);
        if (e is Directory) {
          pending.add(e);
        } else if (e is File && name.toLowerCase().endsWith('.md')) {
          out.add(e.path.substring(dir.path.length + 1).replaceAll(r'\', '/'));
        }
      }
    }
    return out;
  }

  /// Comb changed these paths (a local edit or a sync); bring the disk along.
  Future<void> pushToDisk(Set<String> paths) async {
    await _reconcile(paths.where((p) => p.toLowerCase().endsWith('.md') && !ignored(p)).toSet());
    await _writeAttachments();
    await _saveIndex();
  }

  Future<Set<String>> _reconcile(Set<String> paths) async {
    final snapshot = side.snapshot();
    final imported = <String>{};
    for (final rel in paths) {
      if (_stopped) break;
      final combText = snapshot[rel];
      final f = _file(rel);
      final diskText = f.existsSync() ? await f.readAsString() : null;
      final last = _index[rel];
      final combHash = combText == null ? null : contentHash(combText);
      final diskHash = diskText == null ? null : contentHash(diskText);

      if (combHash == diskHash) {
        if (combHash == null) {
          _index.remove(rel);
        } else {
          _index[rel] = combHash;
        }
        continue;
      }
      final combChanged = combHash != last;
      final diskChanged = diskHash != last;

      if (combChanged && !diskChanged) {
        if (combText == null) {
          await _deleteDisk(rel);
          _index.remove(rel);
        } else {
          await _writeDisk(rel, combText);
          _index[rel] = combHash!;
        }
      } else if (diskChanged && !combChanged) {
        if (diskText == null) {
          side.delete(rel);
          _index.remove(rel);
        } else {
          side.write(rel, diskText);
          _index[rel] = diskHash!;
        }
        imported.add(rel);
      } else {
        // Both sides changed since they last agreed.
        if (diskText != null && combText != null) {
          final copy = _conflictName(rel, snapshot);
          side.write(copy, diskText);
          await _writeDisk(copy, diskText);
          _index[copy] = diskHash!;
          await _writeDisk(rel, combText);
          _index[rel] = combHash!;
          imported.add(copy);
        } else if (diskText != null) {
          side.write(rel, diskText); // deleted in Comb, edited on disk: keep the edit
          _index[rel] = diskHash!;
          imported.add(rel);
        } else {
          await _writeDisk(rel, combText!); // deleted on disk, edited in Comb: keep the edit
          _index[rel] = combHash!;
        }
      }
    }
    return imported;
  }

  String _conflictName(String rel, Map<String, String> snapshot) {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final stem = rel.substring(0, rel.length - 3);
    var candidate = '$stem (conflict $deviceName $date).md';
    var n = 2;
    while (snapshot.containsKey(candidate) || _file(candidate).existsSync()) {
      candidate = '$stem (conflict $deviceName $date $n).md';
      n++;
    }
    return candidate;
  }

  Future<void> _writeAttachments() async {
    for (final entry in side.attachments().entries) {
      final f = _file(entry.key);
      if (f.existsSync()) continue;
      final bytes = await side.readAttachment(entry.value);
      if (bytes == null) continue;
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
    }
  }

  /// Watches the folder for edits made outside Comb. macOS and Windows
  /// report changes anywhere in the folder at once; where the system can't
  /// watch a whole folder tree (Linux, Android) it re-checks on a timer.
  /// The timer also catches anything a watcher misses.
  void startWatching({Duration pollEvery = const Duration(seconds: 30)}) {
    _watch?.cancel();
    _poll?.cancel();
    if (!root.existsSync()) return;
    _poll = Timer.periodic(pollEvery, (_) async {
      if (_busy) return;
      _busy = true;
      try {
        final imported = await reconcileAll();
        if (imported.isNotEmpty) onImported?.call(imported);
      } finally {
        _busy = false;
      }
    });
    if (Platform.isLinux || Platform.isAndroid) return;
    final realRoot = root.resolveSymbolicLinksSync();
    // Reconciling is idempotent (it compares hashes), so events caused by
    // Comb's own writes are harmless and need no special handling. Editors
    // that save by renaming a temporary file report the real name as the
    // move's destination, so both ends are checked.
    _watch = root.watch(recursive: true).listen((event) {
      final candidates = [event.path, if (event is FileSystemMoveEvent && event.destination != null) event.destination!];
      var added = false;
      for (final abs in candidates) {
        // macOS may report /private/var/... for a folder opened as /var/...
        final base = abs.startsWith('${root.path}/') ? root.path : (abs.startsWith('$realRoot/') ? realRoot : null);
        if (base == null) continue;
        final rel = abs.substring(base.length + 1).replaceAll(r'\', '/');
        if (ignored(rel) || !rel.toLowerCase().endsWith('.md')) continue;
        _dirty.add(rel);
        added = true;
      }
      if (!added) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _flushDirty);
    }, onError: (_) {});
  }

  Future<void> _flushDirty() async {
    final paths = Set.of(_dirty);
    _dirty.clear();
    final imported = await _reconcile(paths);
    await _saveIndex();
    if (imported.isNotEmpty) onImported?.call(imported);
  }

  bool _stopped = false;

  Future<void> stop() async {
    _stopped = true;
    _debounce?.cancel();
    _poll?.cancel();
    await _watch?.cancel();
    _watch = null;
  }
}

class FolderTooLarge implements Exception {
  FolderTooLarge(this.limit);
  final int limit;
  @override
  String toString() => 'This folder has more than $limit files. Choose an empty folder just for Comb.';
}
