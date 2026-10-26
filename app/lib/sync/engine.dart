/// Sync engine: queues local edits, pushes them encrypted, pulls and
/// decrypts other devices' changes, and resolves conflicts without ever
/// discarding either side.
library;

import 'dart:async';
import 'dart:typed_data';

import '../core/api.dart';
import '../core/crypto.dart';
import 'state.dart';

class SyncReport {
  SyncReport({this.changedPaths = const {}, this.conflicts = const [], this.error});
  final Set<String> changedPaths;
  final List<String> conflicts;
  final ApiException? error;
  bool get ok => error == null;
}

class SyncEngine {
  SyncEngine({required this.api, required this.key, required this.state, required this.store, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final CombApi api;
  final VaultKey key;
  final VaultState state;
  final StateStore store;
  final DateTime Function() _clock;

  bool _running = false;
  Completer<SyncReport>? _inFlight;

  String get deviceName => state.connection?.deviceName ?? 'this device';

  // ------------------------------------------------------------ local edits

  /// Writes a file (creating its record if new) and queues the change.
  String writeFile(String path, String content) {
    final existing = state.byPath(path);
    final rec = existing ?? LocalRecord(id: newRecordId(), kind: RecordKind.file, path: path);
    if (existing != null && existing.content == content) return existing.id;
    rec
      ..content = content
      ..deleted = false;
    state.records[rec.id] = rec;
    _queue(rec);
    return rec.id;
  }

  void renameFile(String oldPath, String newPath) {
    final rec = state.byPath(oldPath);
    if (rec == null || oldPath == newPath) return;
    rec.path = newPath;
    _queue(rec);
  }

  void deleteFile(String path) {
    final rec = state.byPath(path);
    if (rec == null) return;
    rec.deleted = true;
    _queue(rec);
  }

  /// Encrypts an attachment, keeps the ciphertext locally until uploaded,
  /// and records where it lives in the folder.
  Future<String> addAttachment(String path, List<int> bytes) async {
    final sealed = await sealBlob(key, bytes);
    await store.putBlob(sealed.id, sealed.blob);
    state.pendingBlobs.add(sealed.id);
    final rec = LocalRecord(id: newRecordId(), kind: RecordKind.attachment, path: path, blobId: sealed.id, size: bytes.length);
    state.records[rec.id] = rec;
    _queue(rec);
    return rec.id;
  }

  Future<Uint8List?> readAttachment(String recordId) async {
    final rec = state.records[recordId];
    if (rec?.blobId == null) return null;
    var encrypted = await store.getBlob(rec!.blobId!);
    if (encrypted == null) {
      encrypted = await api.getBlob(rec.blobId!);
      await store.putBlob(rec.blobId!, encrypted);
    }
    return openBlob(key, encrypted);
  }

  /// The first device writes the keycheck record so later devices can
  /// confirm they were given the right key.
  void writeKeycheck() {
    final rec = LocalRecord(id: keycheckRecordId, kind: RecordKind.keycheck);
    state.records[rec.id] = rec;
    _queue(rec);
  }

  void _queue(LocalRecord rec) {
    final payload = rec.payload();
    final forRecord = state.outbox.where((c) => c.recordId == rec.id).toList();
    if (forRecord.isNotEmpty && !forRecord.last.attempted) {
      forRecord.last
        ..payload = payload
        ..deleted = rec.deleted;
      return;
    }
    state.outbox.add(
      PendingChange(
        changeId: newChangeId(),
        recordId: rec.id,
        payload: payload,
        deleted: rec.deleted,
        base: forRecord.isEmpty ? rec.version : null,
      ),
    );
  }

  // ------------------------------------------------------------ sync

  /// Push, then pull. Safe to call often; overlapping calls share one run.
  Future<SyncReport> sync() {
    if (_running) return _inFlight!.future;
    _running = true;
    _inFlight = Completer<SyncReport>();
    _run().then(_inFlight!.complete, onError: _inFlight!.completeError).whenComplete(() => _running = false);
    return _inFlight!.future;
  }

  Future<SyncReport> _run() async {
    final changed = <String>{};
    final conflicts = <String>[];
    try {
      await _uploadBlobs();
      await _push(changed, conflicts);
      await _pull(changed);
      state.lastSync = _clock();
      await store.save(key, state);
      return SyncReport(changedPaths: changed, conflicts: conflicts);
    } on ApiException catch (e) {
      await store.save(key, state);
      return SyncReport(changedPaths: changed, conflicts: conflicts, error: e);
    }
  }

  Future<void> _uploadBlobs() async {
    for (final id in state.pendingBlobs.toList()) {
      final data = await store.getBlob(id);
      if (data != null) await api.putBlob(id, data);
      state.pendingBlobs.remove(id);
    }
  }

  Future<void> _push(Set<String> changed, List<String> conflicts) async {
    while (true) {
      // One change per record per round, so chained edits get their base
      // from the result of the one before.
      final batch = <PendingChange>[];
      final seen = <String>{};
      for (final c in state.outbox) {
        if (seen.add(c.recordId) && c.base != null) batch.add(c);
        if (batch.length >= 200) break;
      }
      if (batch.isEmpty) return;

      final ins = <ChangeIn>[];
      for (final c in batch) {
        c.attempted = true;
        ins.add(
          ChangeIn(
            changeId: c.changeId,
            recordId: c.recordId,
            baseVersion: c.base!,
            blob: await sealRecord(key, c.recordId, c.payload),
            deleted: c.deleted,
          ),
        );
      }
      await store.save(key, state); // remember "attempted" before the network call
      final results = await api.push(ins);

      for (final r in results) {
        final change = state.outbox.firstWhere((c) => c.changeId == r.changeId);
        state.outbox.remove(change);
        if (r.ok) {
          final rec = state.records[r.recordId];
          if (rec != null) rec.version = r.version!;
          for (final next in state.outbox.where((c) => c.recordId == r.recordId)) {
            next.base = r.version;
            break;
          }
        } else {
          final name = await _resolveConflict(change, r.current, changed);
          if (name != null) conflicts.add(name);
        }
      }
    }
  }

  /// The server has a newer version. Keep the server's copy under the
  /// original name and save this device's edit beside it as a conflict copy.
  Future<String?> _resolveConflict(PendingChange change, StoredRecord? current, Set<String> changed) async {
    final mine = state.outbox.where((c) => c.recordId == change.recordId).fold<PendingChange>(change, (_, c) => c);
    state.outbox.removeWhere((c) => c.recordId == change.recordId);

    if (current != null) {
      final payload = await openRecord(key, current.recordId, current.blob);
      final rec = LocalRecord.fromPayload(current.recordId, payload, version: current.version, deleted: current.deleted);
      final old = state.records[current.recordId];
      if (old?.path != null) changed.add(old!.path!);
      state.records[rec.id] = rec;
      if (rec.path != null) changed.add(rec.path!);
    } else {
      state.records.remove(change.recordId);
    }

    final myPath = mine.payload['path'] as String?;
    final myContent = mine.payload['content'] as String?;
    if (mine.deleted || myPath == null || myContent == null) return null;
    final serverContent = current == null ? null : state.records[current.recordId]?.content;
    if (serverContent == myContent) return null;

    final copyPath = _conflictPath(myPath);
    writeFile(copyPath, myContent);
    changed.add(copyPath);
    return copyPath;
  }

  String _conflictPath(String path) {
    final now = _clock();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dot = path.lastIndexOf('.');
    final stem = dot > 0 ? path.substring(0, dot) : path;
    final ext = dot > 0 ? path.substring(dot) : '';
    var candidate = '$stem (conflict $deviceName $date)$ext';
    var n = 2;
    while (state.byPath(candidate) != null) {
      candidate = '$stem (conflict $deviceName $date $n)$ext';
      n++;
    }
    return candidate;
  }

  Future<void> _pull(Set<String> changed) async {
    while (true) {
      final page = await api.pull(state.since);
      for (final remote in page.changes) {
        if (state.hasPending(remote.recordId)) continue; // our push resolves it
        final local = state.records[remote.recordId];
        if (local != null && local.version >= remote.version) continue;
        final Map<String, Object?> payload;
        try {
          payload = await openRecord(key, remote.recordId, remote.blob);
        } on DecryptError {
          continue; // not ours to read (should not happen); never crash sync
        }
        final rec = LocalRecord.fromPayload(remote.recordId, payload, version: remote.version, deleted: remote.deleted);
        if (local?.path != null) changed.add(local!.path!);
        if (rec.path != null) changed.add(rec.path!);
        state.records[rec.id] = rec;
      }
      state.since = page.nextSince;
      if (!page.hasMore) return;
    }
  }

  /// A newly paired device checks it holds the right key before trusting it.
  Future<bool> verifyKey() async {
    var since = 0;
    while (true) {
      final page = await api.pull(since);
      for (final r in page.changes) {
        if (r.recordId == keycheckRecordId) {
          try {
            final p = await openRecord(key, r.recordId, r.blob);
            return p['type'] == 'keycheck' && p['value'] == keycheckPayload['value'];
          } on DecryptError {
            return false;
          }
        }
      }
      since = page.nextSince;
      if (!page.hasMore) return false;
    }
  }
}
