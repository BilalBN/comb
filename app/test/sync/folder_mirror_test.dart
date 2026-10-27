import 'dart:io';
import 'dart:typed_data';

import 'package:comb/data/library.dart';
import 'package:comb/sync/folder_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySide extends MemoryFiles implements MirrorSide {
  final Map<String, String> atts = {};
  final Map<String, Uint8List> bytes = {};
  @override
  Map<String, String> attachments() => atts;
  @override
  Future<Uint8List?> readAttachment(String recordId) async => bytes[recordId];
}

void main() {
  late Directory root;
  late MemorySide side;
  late FolderMirror mirror;

  File f(String rel) => File('${root.path}/$rel');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('comb-folder-');
    side = MemorySide();
    mirror = FolderMirror(root, side, deviceName: 'MacBook');
  });
  tearDown(() async {
    await mirror.stop();
    await root.delete(recursive: true);
  });

  test('Comb files appear in the folder', () async {
    side.files['Tasks/Call GCD.md'] = 'call';
    side.files['.comb/workspace.json'] = '{}';
    await mirror.reconcileAll();
    expect(f('Tasks/Call GCD.md').readAsStringSync(), 'call');
    expect(f('.comb/workspace.json').existsSync(), isFalse, reason: 'internal files stay out of the folder');
  });

  test('a note written in Obsidian comes into Comb', () async {
    await mirror.reconcileAll();
    f('CAX/Notes/Ideas.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('# Ideas');
    final imported = await mirror.reconcileAll();
    expect(imported, {'CAX/Notes/Ideas.md'});
    expect(side.files['CAX/Notes/Ideas.md'], '# Ideas');
  });

  test('edits flow each way, and deletes follow', () async {
    side.files['Notes/a.md'] = 'one';
    await mirror.reconcileAll();
    f('Notes/a.md').writeAsStringSync('edited in Obsidian');
    await mirror.reconcileAll();
    expect(side.files['Notes/a.md'], 'edited in Obsidian');

    side.files['Notes/a.md'] = 'edited in Comb';
    await mirror.pushToDisk({'Notes/a.md'});
    expect(f('Notes/a.md').readAsStringSync(), 'edited in Comb');

    f('Notes/a.md').deleteSync();
    await mirror.reconcileAll();
    expect(side.files.containsKey('Notes/a.md'), isFalse);

    side.files['Notes/b.md'] = 'b';
    await mirror.reconcileAll();
    side.files.remove('Notes/b.md');
    await mirror.pushToDisk({'Notes/b.md'});
    expect(f('Notes/b.md').existsSync(), isFalse);
    expect(Directory('${root.path}/Notes').existsSync(), isFalse, reason: 'empty folders are tidied');
  });

  test('edited on both sides: both versions kept', () async {
    side.files['Notes/a.md'] = 'one';
    await mirror.reconcileAll();
    side.files['Notes/a.md'] = 'Comb version';
    f('Notes/a.md').writeAsStringSync('Obsidian version');
    await mirror.reconcileAll();
    expect(f('Notes/a.md').readAsStringSync(), 'Comb version');
    final copies = side.files.keys.where((k) => k.contains('(conflict MacBook')).toList();
    expect(copies, hasLength(1));
    expect(side.files[copies.single], 'Obsidian version');
    expect(f(copies.single).readAsStringSync(), 'Obsidian version');
  });

  test('Obsidian settings and hidden files are left alone', () async {
    f('.obsidian/app.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{}');
    await mirror.reconcileAll();
    expect(side.files, isEmpty);
    expect(f('.obsidian/app.json').existsSync(), isTrue);
  });

  test('attachments are written into the folder', () async {
    side.atts['Attachments/2026-10/photo.jpg'] = 'r1';
    side.bytes['r1'] = Uint8List.fromList([1, 2, 3]);
    await mirror.reconcileAll();
    expect(f('Attachments/2026-10/photo.jpg').readAsBytesSync(), [1, 2, 3]);
  });

  test('restarting the app with the folder unchanged changes nothing', () async {
    side.files['Notes/a.md'] = 'one';
    await mirror.reconcileAll();
    final again = FolderMirror(root, side, deviceName: 'MacBook');
    expect(await again.reconcileAll(), isEmpty);
    expect(side.files, {'Notes/a.md': 'one'});
  });

  test('the watcher picks up an edit made while Comb runs', () async {
    side.files['Notes/a.md'] = 'one';
    await mirror.reconcileAll();
    final seen = <String>{};
    mirror.onImported = seen.addAll;
    mirror.startWatching(pollEvery: const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    f('Notes/a.md').writeAsStringSync('typed in Obsidian');
    for (var i = 0; i < 40 && seen.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(seen, {'Notes/a.md'});
    expect(side.files['Notes/a.md'], 'typed in Obsidian');
  });
}
