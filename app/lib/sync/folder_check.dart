/// Checks a folder before Comb uses it as the markdown folder, so a slow,
/// unwritable or cloud-synced folder is caught with a clear message instead
/// of freezing the app or quietly copying notes somewhere unexpected.
library;

import 'dart:async';
import 'dart:io';

class FolderCheck {
  FolderCheck({
    required this.path,
    this.writable = false,
    this.cloud,
    this.markdownFiles = 0,
    this.otherFiles = 0,
    this.usedByComb = false,
    this.tooSlow = false,
    this.tooBig = false,
  });

  final String path;
  final bool writable;

  /// The cloud service the folder syncs to, if any ("Google Drive").
  final String? cloud;
  final int markdownFiles;
  final int otherFiles;

  /// Comb has used this folder before (it has Comb's index in it).
  final bool usedByComb;
  final bool tooSlow;
  final bool tooBig;

  bool get empty => markdownFiles == 0 && otherFiles == 0;

  /// Problems that mean the folder can't be used.
  String? get blocker {
    if (tooSlow) {
      return 'This folder takes too long to read. Cloud folders that download files on demand often do this. Choose a folder on this Mac.';
    }
    if (tooBig) return 'This folder has a very large number of files. Choose an empty folder just for Comb.';
    if (!writable) return 'Comb can\'t write to this folder. Choose one in your home folder, for example in Documents.';
    return null;
  }

  /// Things to confirm before using it.
  List<String> get warnings => [
    if (cloud != null)
      'This folder is in $cloud. Your notes would be copied there as plain, unencrypted files that $cloud can read. Comb already syncs your devices with encryption, so a folder on this Mac is recommended.',
    if (!usedByComb && markdownFiles > 0)
      'This folder already has $markdownFiles markdown file${markdownFiles == 1 ? '' : 's'}. Comb will bring every one of them in as notes.',
    if (!usedByComb && markdownFiles == 0 && otherFiles > 20)
      'This folder already has $otherFiles other files. An empty folder just for Comb is easier to keep tidy.',
  ];
}

String? cloudServiceFor(String path) {
  final p = path.toLowerCase();
  if (p.contains('/library/cloudstorage/googledrive') || p.contains('/google drive')) return 'Google Drive';
  if (p.contains('/library/mobile documents') || p.contains('/icloud drive')) return 'iCloud Drive';
  if (p.contains('/library/cloudstorage/dropbox') || p.contains('/dropbox')) return 'Dropbox';
  if (p.contains('/library/cloudstorage/onedrive') || p.contains('/onedrive')) return 'OneDrive';
  if (p.contains('/library/cloudstorage/box') || p.contains('/box sync')) return 'Box';
  if (p.contains('/library/cloudstorage/')) return 'a cloud service';
  return null;
}

Future<FolderCheck> checkFolder(String path, {Duration timeout = const Duration(seconds: 6), int sampleLimit = 5000}) async {
  final dir = Directory(path);
  final cloud = cloudServiceFor(path);

  var writable = false;
  try {
    await dir.create(recursive: true);
    final probe = File('${dir.path}/.comb-write-check');
    await probe.writeAsString('ok', flush: true).timeout(timeout);
    await probe.delete();
    writable = true;
  } catch (_) {}

  var md = 0, other = 0;
  var tooSlow = false, tooBig = false;
  final usedByComb = File('${dir.path}/.comb/mirror-index.json').existsSync();
  try {
    await () async {
      final pending = <Directory>[dir];
      var seen = 0;
      while (pending.isNotEmpty) {
        final d = pending.removeLast();
        await for (final e in d.list(followLinks: false)) {
          final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
          if (name.startsWith('.')) continue;
          if (++seen > sampleLimit) {
            tooBig = true;
            return;
          }
          if (e is Directory) {
            pending.add(e);
          } else if (name.toLowerCase().endsWith('.md')) {
            md++;
          } else {
            other++;
          }
        }
      }
    }().timeout(timeout);
  } on TimeoutException {
    tooSlow = true;
  } catch (_) {}

  return FolderCheck(
    path: path,
    writable: writable,
    cloud: cloud,
    markdownFiles: md,
    otherFiles: other,
    usedByComb: usedByComb,
    tooSlow: tooSlow,
    tooBig: tooBig,
  );
}
