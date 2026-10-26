import 'dart:typed_data';

import '../sync/folder_mirror.dart';
import 'engine.dart';
import 'state.dart';

/// Lets the [Library] and the [FolderMirror] read and write files through
/// the sync engine, and tells the app which paths changed.
class EngineFiles implements MirrorSide {
  EngineFiles(this.engine, {this.onChanged});

  final SyncEngine engine;
  void Function(Set<String> paths)? onChanged;

  VaultState get _state => engine.state;

  @override
  Map<String, String> snapshot() => {
        for (final r in _state.liveFiles)
          if (r.content != null) r.path!: r.content!,
      };

  @override
  void write(String path, String content) {
    engine.writeFile(path, content);
    onChanged?.call({path});
  }

  @override
  void rename(String from, String to) {
    engine.renameFile(from, to);
    onChanged?.call({from, to});
  }

  @override
  void delete(String path) {
    engine.deleteFile(path);
    onChanged?.call({path});
  }

  @override
  Map<String, String> attachments() => {
        for (final r in _state.records.values)
          if (!r.deleted && r.kind == RecordKind.attachment && r.path != null) r.path!: r.id,
      };

  @override
  Future<Uint8List?> readAttachment(String recordId) => engine.readAttachment(recordId);
}
