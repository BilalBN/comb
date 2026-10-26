import 'dart:io';

import 'package:comb/sync/folder_check.dart';
import 'package:comb/sync/folder_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('comb-check-'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('cloud folders are recognised', () {
    test('by their macOS locations', () {
      expect(cloudServiceFor('/Users/b/Library/CloudStorage/GoogleDrive-b@gmail.com/My Drive/Comb'), 'Google Drive');
      expect(cloudServiceFor('/Users/b/Library/Mobile Documents/com~apple~CloudDocs/Comb'), 'iCloud Drive');
      expect(cloudServiceFor('/Users/b/Library/CloudStorage/Dropbox/Comb'), 'Dropbox');
      expect(cloudServiceFor('/Users/b/Library/CloudStorage/OneDrive-Personal/Comb'), 'OneDrive');
      expect(cloudServiceFor('/Users/b/Library/CloudStorage/pCloud/Comb'), 'a cloud service');
    });
    test('and a normal folder is not one', () {
      expect(cloudServiceFor('/Users/b/Documents/Comb Vault'), isNull);
      expect(cloudServiceFor('/Volumes/Hard Drive/C4B/Comb Vault'), isNull);
    });
  });

  test('an empty local folder passes with nothing to confirm', () async {
    final r = await checkFolder(dir.path);
    expect(r.writable, isTrue);
    expect(r.empty, isTrue);
    expect(r.blocker, isNull);
    expect(r.warnings, isEmpty);
    expect(Directory(dir.path).listSync(), isEmpty, reason: 'the write check cleans up after itself');
  });

  test('a folder that already has notes asks first, unless Comb used it before', () async {
    File('${dir.path}/a.md').writeAsStringSync('# A');
    Directory('${dir.path}/sub').createSync();
    File('${dir.path}/sub/b.md').writeAsStringSync('# B');
    Directory('${dir.path}/.obsidian').createSync();
    File('${dir.path}/.obsidian/x.md').writeAsStringSync('hidden');
    var r = await checkFolder(dir.path);
    expect(r.markdownFiles, 2, reason: 'hidden folders are skipped');
    expect(r.warnings.single, contains('2 markdown files'));

    Directory('${dir.path}/.comb').createSync();
    File('${dir.path}/.comb/mirror-index.json').writeAsStringSync('{}');
    r = await checkFolder(dir.path);
    expect(r.usedByComb, isTrue);
    expect(r.warnings, isEmpty);
  });

  test('a folder that cannot be created is refused', () async {
    final file = File('${dir.path}/file')..writeAsStringSync('x');
    final r = await checkFolder('${file.path}/Comb');
    expect(r.writable, isFalse);
    expect(r.blocker, contains("can't write"));
  });

  test('a very large folder is refused', () async {
    for (var i = 0; i < 30; i++) {
      File('${dir.path}/$i.txt').writeAsStringSync('x');
    }
    final r = await checkFolder(dir.path, sampleLimit: 20);
    expect(r.tooBig, isTrue);
    expect(r.blocker, isNotNull);
  });

  test('the mirror lists markdown files without opening hidden folders, and stops on huge folders', () async {
    File('${dir.path}/a.md').writeAsStringSync('# A');
    Directory('${dir.path}/Notes/Deep').createSync(recursive: true);
    File('${dir.path}/Notes/Deep/b.MD').writeAsStringSync('# B');
    File('${dir.path}/Notes/pic.png').writeAsBytesSync([1]);
    Directory('${dir.path}/.trash').createSync();
    File('${dir.path}/.trash/c.md').writeAsStringSync('# C');
    expect(await FolderMirror.markdownFilesIn(dir), {'a.md', 'Notes/Deep/b.MD'});
    expect(() => FolderMirror.markdownFilesIn(dir, maxEntries: 3), throwsA(isA<FolderTooLarge>()));
  });
}
