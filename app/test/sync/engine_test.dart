import 'dart:convert';
import 'dart:io';

import 'package:comb/core/api.dart';
import 'package:comb/core/crypto.dart';
import 'package:comb/sync/engine.dart';
import 'package:comb/sync/state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_server.dart';

class Device {
  Device(this.engine, this.dir);
  final SyncEngine engine;
  final Directory dir;
  VaultState get state => engine.state;
  String? content(String path) => state.byPath(path)?.content;
}

Future<Device> makeDevice(String url, VaultKey key, DeviceCredentials creds, String name) async {
  final dir = await Directory.systemTemp.createTemp('comb-device-');
  final state = VaultState(connection: Connection(serverUrl: url, token: creds.token, deviceId: creds.deviceId, deviceName: name));
  final engine = SyncEngine(api: CombApi(url, token: creds.token), key: key, state: state, store: StateStore(dir));
  return Device(engine, dir);
}

void main() {
  final skip = LiveServer.python == null ? 'set COMB_SERVER_PYTHON to run against the real server' : null;

  group('against the real sync server', () {
    late LiveServer server;
    late VaultKey key;
    late Device mac;
    late Device phone;

    setUp(() async {
      server = await LiveServer.start();
      key = VaultKey.generate();
      final api = CombApi(server.url);
      final macCreds = await api.setup(server.setupCode, 'MacBook');
      mac = await makeDevice(server.url, key, macCreds, 'MacBook');
      mac.engine.writeKeycheck();
      expect((await mac.engine.sync()).ok, isTrue);

      final code = (await CombApi(server.url, token: macCreds.token).startPairing()).code;
      final link = pairingLink(server.url, code, key.recoveryKey());
      final parsed = parsePairingLink(link);
      final phoneCreds = await CombApi(parsed.server).claimPairing(parsed.code, 'Nothing Phone');
      phone = await makeDevice(server.url, VaultKey.fromRecoveryKey(parsed.recoveryKey), phoneCreds, 'Nothing Phone');
    });

    tearDown(() async {
      await server.stop();
      await mac.dir.delete(recursive: true);
      await phone.dir.delete(recursive: true);
    });

    test('a paired device confirms it has the right key', () async {
      expect(await phone.engine.verifyKey(), isTrue);
    });

    test('a task made on the phone reaches the Mac; the server holds no plaintext', () async {
      const task = '---\ntype: task\nspace: CAX\n---\nSend revised HCL vault drawings to GCD\nരവി नमस्ते\n';
      phone.engine.writeFile('Tasks/Send revised HCL vault drawings.md', task);
      expect((await phone.engine.sync()).ok, isTrue);
      final report = await mac.engine.sync();
      expect(report.changedPaths, contains('Tasks/Send revised HCL vault drawings.md'));
      expect(mac.content('Tasks/Send revised HCL vault drawings.md'), task);

      final stored = server.storedBytes();
      for (final secret in ['HCL', 'GCD', 'Tasks/', 'രവി']) {
        final needle = utf8.encode(secret);
        expect(_contains(stored, needle), isFalse, reason: '$secret readable on the server');
      }
    });

    test('edits, renames and deletes follow', () async {
      mac.engine.writeFile('Notes/a.md', 'one');
      await mac.engine.sync();
      await phone.engine.sync();
      phone.engine.writeFile('Notes/a.md', 'two');
      phone.engine.renameFile('Notes/a.md', 'Notes/b.md');
      await phone.engine.sync();
      await mac.engine.sync();
      expect(mac.content('Notes/a.md'), isNull);
      expect(mac.content('Notes/b.md'), 'two');
      mac.engine.deleteFile('Notes/b.md');
      await mac.engine.sync();
      await phone.engine.sync();
      expect(phone.content('Notes/b.md'), isNull);
    });

    test('edits queued offline are pushed later, once each', () async {
      mac.engine.writeFile('Notes/x.md', 'v1');
      mac.engine.writeFile('Notes/x.md', 'v2');
      expect(mac.state.outbox.length, 1, reason: 'unsent edits to one file merge');
      await mac.engine.sync();
      mac.engine.writeFile('Notes/x.md', 'v3');
      await mac.engine.sync();
      await phone.engine.sync();
      expect(phone.content('Notes/x.md'), 'v3');
      expect(mac.state.outbox, isEmpty);
    });

    test('simultaneous edits keep both versions', () async {
      mac.engine.writeFile('Tasks/t.md', 'original');
      await mac.engine.sync();
      await phone.engine.sync();
      mac.engine.writeFile('Tasks/t.md', 'edited on mac');
      phone.engine.writeFile('Tasks/t.md', 'edited on phone');
      await mac.engine.sync();
      final report = await phone.engine.sync();
      expect(report.conflicts, hasLength(1));
      expect(phone.content('Tasks/t.md'), 'edited on mac');
      expect(phone.content(report.conflicts.single), 'edited on phone');
      await mac.engine.sync();
      expect(mac.content(report.conflicts.single), 'edited on phone');
    });

    test('attachments are encrypted, uploaded and readable on the other device', () async {
      final id = await phone.engine.addAttachment('Attachments/2026-10/photo.jpg', utf8.encode('jpeg bytes of the HCL wall'));
      await phone.engine.sync();
      await mac.engine.sync();
      expect(mac.state.records[id]?.kind, RecordKind.attachment);
      expect(utf8.decode((await mac.engine.readAttachment(id))!), 'jpeg bytes of the HCL wall');
    });

    test('state saved on disk is encrypted and reloads', () async {
      mac.engine.writeFile('Notes/secret.md', 'GCD drawings');
      await mac.engine.sync();
      final raw = File('${mac.dir.path}/state.comb').readAsBytesSync();
      expect(_contains(raw, utf8.encode('GCD drawings')), isFalse);
      final reloaded = await StateStore(mac.dir).load(key);
      expect(reloaded.byPath('Notes/secret.md')?.content, 'GCD drawings');
    });
  }, skip: skip);

  test('an unreachable server keeps changes queued', () async {
    final dir = await Directory.systemTemp.createTemp('comb-device-');
    final engine = SyncEngine(
      api: CombApi('http://127.0.0.1:9', token: 't'),
      key: VaultKey.generate(),
      state: VaultState(),
      store: StateStore(dir),
    );
    engine.writeFile('Notes/offline.md', 'saved while offline');
    final report = await engine.sync();
    expect(report.ok, isFalse);
    expect(report.error!.isOffline, isTrue);
    expect(engine.state.outbox, hasLength(1));
    await dir.delete(recursive: true);
  });
}

bool _contains(List<int> hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
