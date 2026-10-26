import 'dart:io';

import 'package:comb/app/controller.dart';
import 'package:comb/data/models.dart';
import 'package:comb/security/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../security/app_lock_test.dart' show FakeBiometrics, MemoryCache;
import '../support/live_server.dart';

AppController makeController(Directory dir, {String boot = 'b1'}) => AppController(
  appDir: dir,
  lock: AppLock(
    dir: dir,
    cache: MemoryCache(),
    biometrics: FakeBiometrics(),
    params: const KdfParams(memoryKib: 256, iterations: 1),
    bootId: () async => boot,
  ),
  syncEvery: const Duration(hours: 1),
);

void main() {
  final skip = LiveServer.python == null ? 'set COMB_SERVER_PYTHON to run against the real server' : null;

  group('the whole app flow against the real server', () {
    late LiveServer server;
    late Directory macDir, phoneDir, folder;

    setUp(() async {
      server = await LiveServer.start();
      macDir = await Directory.systemTemp.createTemp('comb-mac-');
      phoneDir = await Directory.systemTemp.createTemp('comb-phone-');
      folder = await Directory.systemTemp.createTemp('comb-vault-');
    });
    tearDown(() async {
      await server.stop();
      for (final d in [macDir, phoneDir, folder]) {
        if (d.existsSync()) await d.delete(recursive: true);
      }
    });

    test('set up the Mac, add Spaces and a task, pair a phone, both see it, the folder fills', () async {
      final mac = makeController(macDir);
      await mac.start();
      expect(mac.phase, Phase.setup);
      expect(await mac.serverIsNew(server.url), isTrue);

      final recovery = await mac.createAccount(serverUrl: server.url, setupCode: server.setupCode, deviceName: 'MacBook');
      expect(recovery, isNotEmpty);
      await mac.setupPassword('correct horse', useBiometrics: true);
      await mac.chooseFolder(folder.path);
      await mac.finishSetupOpen();
      final cax = mac.library!.addSpace('CAX', color: 'blue');
      mac.library!.addSpace('Crypt4Bits', color: 'violet');
      mac.completeSetup();
      expect(mac.phase, Phase.ready);

      mac.go(NavView.space, space: cax.id);
      final task = mac.quickAdd('Send revised vault drawings to GCD tomorrow 4pm !h');
      expect(mac.library!.spaceOf(task)?.name, 'CAX', reason: 'adding inside a Space uses that Space');
      await mac.syncNow();
      expect(mac.syncStatus, SyncStatus.synced);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(File('${folder.path}/Tasks/Send revised vault drawings to GCD.md').existsSync(), isTrue);

      final pair = await mac.startPairing();
      final phone = makeController(phoneDir);
      await phone.start();
      expect(await phone.serverIsNew(server.url), isFalse);
      await phone.joinWithLink(link: pair.link, deviceName: 'Nothing Phone');
      await phone.setupPassword('phone password', useBiometrics: true);
      await phone.finishSetupOpen();
      await phone.syncNow();
      phone.completeSetup();

      final seen = phone.library!.tasks.single;
      expect(seen.title, 'Send revised vault drawings to GCD');
      expect(seen.priority, Priority.high);
      expect(phone.library!.spaces.map((s) => s.name), containsAll(['CAX', 'Crypt4Bits']));

      phone.edit((lib) => lib.setTaskDone(seen, true));
      await phone.syncNow();
      await mac.syncNow();
      expect(mac.library!.tasks.single.done, isTrue);

      final devices = await mac.devices();
      expect(devices.map((d) => d.name), containsAll(['MacBook', 'Nothing Phone']));

      mac.dispose();
      phone.dispose();
    });

    test('lock and unlock: fingerprint until restart, password after', () async {
      final mac = makeController(macDir);
      await mac.start();
      await mac.createAccount(serverUrl: server.url, setupCode: server.setupCode, deviceName: 'MacBook');
      await mac.setupPassword('correct horse', useBiometrics: true);
      await mac.finishSetupOpen();
      mac.completeSetup();
      mac.quickAdd('A task');
      await mac.lockNow();
      expect(mac.phase, Phase.locked);
      expect(mac.quickUnlockAvailable, isTrue);
      expect(await mac.unlockQuick(), isTrue);
      expect(mac.library!.tasks.single.title, 'A task');
      mac.dispose();

      final afterRestart = AppController(
        appDir: macDir,
        lock: AppLock(
          dir: macDir,
          cache: MemoryCache(),
          biometrics: FakeBiometrics(),
          params: const KdfParams(memoryKib: 256, iterations: 1),
          bootId: () async => 'b2',
        ),
        syncEvery: const Duration(hours: 1),
      );
      await afterRestart.start();
      expect(afterRestart.phase, Phase.locked);
      expect(afterRestart.quickUnlockAvailable, isFalse);
      await expectLater(afterRestart.unlockWithPassword('wrong one'), throwsA(isA<WrongPassword>()));
      await afterRestart.unlockWithPassword('correct horse');
      expect(afterRestart.library!.tasks.single.title, 'A task');
      afterRestart.dispose();
    });

    test('an edit made in Obsidian syncs to the other device', () async {
      final mac = makeController(macDir);
      await mac.start();
      await mac.createAccount(serverUrl: server.url, setupCode: server.setupCode, deviceName: 'MacBook');
      await mac.setupPassword('correct horse', useBiometrics: false);
      await mac.chooseFolder(folder.path);
      await mac.finishSetupOpen();
      await mac.mirrorSettled;
      mac.completeSetup();
      final note = mac.edit((lib) => lib.createNote(title: 'Call with GCD', body: '- [ ] Send drawings'));
      final t = mac.edit((lib) => lib.makeTaskFromLine(note, 0));
      await mac.syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final file = File('${folder.path}/${note.path}');
      expect(file.readAsStringSync(), contains('- [ ] [[Send drawings]]'));
      file.writeAsStringSync(file.readAsStringSync().replaceFirst('- [ ] [[Send drawings]]', '- [x] [[Send drawings]]'));
      await mac.mirror!.reconcileAll().then((imported) {
        mac.library!.reload();
        for (final p in imported) {
          final n = mac.library!.notes.where((n) => n.path == p).firstOrNull;
          if (n != null) mac.library!.syncTicksFromNote(n);
        }
      });
      expect(mac.library!.tasks.firstWhere((x) => x.title == t.title).done, isTrue, reason: 'ticking in Obsidian completes the task');
      mac.dispose();
    });

    test('a folder that cannot be used never stops the app from opening', () async {
      final notAFolder = File('${folder.path}/plain-file.txt')..writeAsStringSync('x');
      final mac = makeController(macDir);
      await mac.start();
      await mac.createAccount(serverUrl: server.url, setupCode: server.setupCode, deviceName: 'MacBook');
      await mac.setupPassword('correct horse', useBiometrics: false);
      await mac.chooseFolder('${notAFolder.path}/Comb Vault');
      await mac.finishSetupOpen();
      mac.completeSetup();
      expect(mac.phase, Phase.ready);
      await mac.mirrorSettled;
      expect(mac.mirror, isNull);
      expect(mac.mirrorError, contains('markdown folder'));
      expect(mac.mirrorStarting, isFalse);

      await mac.chooseFolder(folder.path);
      expect(mac.mirrorError, isNull, reason: 'choosing a good folder clears the problem');
      expect(mac.mirror, isNotNull);
      mac.dispose();
    });
  }, skip: skip);
}
