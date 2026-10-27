import 'dart:io';
import 'dart:typed_data';

import 'package:comb/core/crypto.dart';
import 'package:comb/security/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryCache implements SessionCache {
  String? boot;
  Uint8List? key;
  @override
  Future<void> save(String bootId, Uint8List k) async {
    boot = bootId;
    key = k;
  }

  @override
  Future<Uint8List?> load(String bootId) async => boot == bootId ? key : null;
  @override
  Future<void> clear() async {
    boot = null;
    key = null;
  }
}

class FakeBiometrics implements Biometrics {
  bool has = true;
  bool approve = true;
  int asked = 0;
  @override
  Future<bool> available() async => has;
  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return approve;
  }
}

void main() {
  late Directory dir;
  late MemoryCache cache;
  late FakeBiometrics bio;
  var boot = 'boot-1';
  const fast = KdfParams(memoryKib: 256, iterations: 1);

  AppLock lock() => AppLock(dir: dir, cache: cache, biometrics: bio, params: fast, bootId: () async => boot);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('comb-lock-');
    cache = MemoryCache();
    bio = FakeBiometrics();
    boot = 'boot-1';
  });
  tearDown(() => dir.delete(recursive: true));

  test('password unlocks the key; a wrong one does not', () async {
    final key = VaultKey.generate();
    await lock().setPassword(key, 'correct horse');
    final fresh = lock();
    expect(await fresh.unlockWithPassword('correct horse'), key);
    await expectLater(fresh.unlockWithPassword('wrong password'), throwsA(isA<WrongPassword>()));
  });

  test('the saved lock file does not contain the key', () async {
    final key = VaultKey.generate();
    await lock().setPassword(key, 'correct horse');
    final text = File('${dir.path}/lock.json').readAsStringSync();
    expect(text.contains(String.fromCharCodes(key.raw)), isFalse);
  });

  test('until a restart, the fingerprint is enough', () async {
    final key = VaultKey.generate();
    await lock().setPassword(key, 'correct horse');
    final l = lock();
    expect(await l.canQuickUnlock(), isTrue);
    expect(await l.quickUnlock(), key);
    expect(bio.asked, 1);
  });

  test('after a restart the password is needed, and the fingerprint too', () async {
    final key = VaultKey.generate();
    await lock().setPassword(key, 'correct horse');
    boot = 'boot-2';
    final l = lock();
    expect(await l.canQuickUnlock(), isFalse);
    expect(await l.quickUnlock(), isNull);
    bio.approve = false;
    await expectLater(l.unlockWithPassword('correct horse'), throwsA(isA<BiometricsFailed>()));
    bio.approve = true;
    expect(await l.unlockWithPassword('correct horse'), key);
    expect(await l.canQuickUnlock(), isTrue);
  });

  test('a refused fingerprint does not unlock', () async {
    await lock().setPassword(VaultKey.generate(), 'correct horse');
    bio.approve = false;
    expect(await lock().quickUnlock(), isNull);
  });

  test('without fingerprint hardware the cached key still works until restart', () async {
    final key = VaultKey.generate();
    bio.has = false;
    await lock().setPassword(key, 'correct horse');
    expect(await lock().quickUnlock(), key);
    expect(bio.asked, 0);
  });

  test('changing the password keeps the same key', () async {
    final key = VaultKey.generate();
    final l = lock();
    await l.setPassword(key, 'first password');
    await l.setPassword(await l.verifyPassword('first password'), 'second password');
    expect(await lock().unlockWithPassword('second password'), key);
    await expectLater(lock().unlockWithPassword('first password'), throwsA(isA<WrongPassword>()));
  });

  test('passwords shorter than 6 characters are refused', () async {
    await expectLater(lock().setPassword(VaultKey.generate(), '12345'), throwsArgumentError);
  });
}
