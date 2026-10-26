import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Starts the real Python sync server for tests. Skipped unless the
/// COMB_SERVER_PYTHON environment variable points at a Python that has
/// comb_server installed (CI sets it; locally:
///   COMB_SERVER_PYTHON=../server/.venv/bin/python flutter test).
class LiveServer {
  LiveServer._(this._process, this.url, this.dataDir);

  final Process _process;
  final String url;
  final Directory dataDir;

  static String? get python => Platform.environment['COMB_SERVER_PYTHON'];

  String get setupCode => File('${dataDir.path}/SETUP_CODE.txt').readAsStringSync().trim();

  static Future<LiveServer> start() async {
    final dataDir = await Directory.systemTemp.createTemp('comb-server-');
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    final process = await Process.start(
      python!,
      ['-m', 'comb_server', 'serve', '--port', '$port'],
      environment: {'COMB_DATA_DIR': dataDir.path},
    );
    process.stdout.transform(utf8.decoder).listen((_) {});
    process.stderr.transform(utf8.decoder).listen((_) {});
    final url = 'http://127.0.0.1:$port';
    final client = HttpClient();
    for (var i = 0; i < 100; i++) {
      try {
        final req = await client.getUrl(Uri.parse('$url/v1/health'));
        final resp = await req.close();
        await resp.drain<void>();
        if (resp.statusCode == 200) {
          client.close();
          return LiveServer._(process, url, dataDir);
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    process.kill();
    throw StateError('server did not start');
  }

  Future<void> stop() async {
    _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    await dataDir.delete(recursive: true);
  }

  /// Every byte the server has stored, for "it never holds plaintext" checks.
  List<int> storedBytes() {
    final out = <int>[];
    for (final f in dataDir.listSync(recursive: true).whereType<File>()) {
      out.addAll(f.readAsBytesSync());
    }
    return out;
  }
}
