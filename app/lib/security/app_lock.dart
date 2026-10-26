/// App lock.
///
/// The vault key is stored only wrapped by a key derived from the person's
/// app password (Argon2id). After the device restarts, the password is
/// needed (plus the fingerprint when that is turned on). Until the next
/// restart the unwrapped key is kept in the system's secure storage, and the
/// fingerprint (or the password) unlocks the app when it re-locks.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../core/crypto.dart';

class WrongPassword implements Exception {
  @override
  String toString() => 'That password is not right.';
}

class BiometricsFailed implements Exception {
  @override
  String toString() => 'Fingerprint was not confirmed.';
}

enum RelockAfter { always, oneMinute, fiveMinutes, fifteenMinutes }

extension RelockDuration on RelockAfter {
  Duration get duration => switch (this) {
        RelockAfter.always => Duration.zero,
        RelockAfter.oneMinute => const Duration(minutes: 1),
        RelockAfter.fiveMinutes => const Duration(minutes: 5),
        RelockAfter.fifteenMinutes => const Duration(minutes: 15),
      };
  String get label => switch (this) {
        RelockAfter.always => 'Every time the app opens',
        RelockAfter.oneMinute => 'After 1 minute away',
        RelockAfter.fiveMinutes => 'After 5 minutes away',
        RelockAfter.fifteenMinutes => 'After 15 minutes away',
      };
}

class KdfParams {
  const KdfParams({this.memoryKib = 19456, this.iterations = 2, this.parallelism = 1});
  final int memoryKib;
  final int iterations;
  final int parallelism;
  Map<String, Object?> toJson() => {'alg': 'argon2id', 'm': memoryKib, 't': iterations, 'p': parallelism};
  static KdfParams fromJson(Map<String, dynamic> j) =>
      KdfParams(memoryKib: j['m'] as int, iterations: j['t'] as int, parallelism: j['p'] as int);
}

Future<Uint8List> deriveKey(String password, List<int> salt, KdfParams p) async {
  final kdf = DartArgon2id(parallelism: p.parallelism, memory: p.memoryKib, iterations: p.iterations, hashLength: 32);
  final k = await kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  return Uint8List.fromList(await k.extractBytes());
}

/// Where the unlocked key waits between restarts.
abstract class SessionCache {
  Future<void> save(String bootId, Uint8List key);
  Future<Uint8List?> load(String bootId);
  Future<void> clear();
}

/// Android Keystore / iOS Keychain.
class SecureStorageCache implements SessionCache {
  final _storage = const FlutterSecureStorage();
  static const _k = 'comb.session';

  @override
  Future<void> save(String bootId, Uint8List key) => _storage.write(key: _k, value: jsonEncode({'boot': bootId, 'key': base64.encode(key)}));

  @override
  Future<Uint8List?> load(String bootId) async {
    final raw = await _storage.read(key: _k);
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['boot'] != bootId) {
      await clear();
      return null;
    }
    return base64.decode(j['key'] as String);
  }

  @override
  Future<void> clear() => _storage.delete(key: _k);
}

/// Mac until the app is signed with the Apple Developer account: a file
/// readable only by you, on FileVault-encrypted disk, cleared on restart.
/// Moves into the Keychain once the app is signed.
class FileSessionCache implements SessionCache {
  FileSessionCache(this.dir);
  final Directory dir;
  File get _f => File('${dir.path}/session.json');

  @override
  Future<void> save(String bootId, Uint8List key) async {
    await dir.create(recursive: true);
    await _f.writeAsString(jsonEncode({'boot': bootId, 'key': base64.encode(key)}), flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', _f.path]);
  }

  @override
  Future<Uint8List?> load(String bootId) async {
    if (!_f.existsSync()) return null;
    final j = jsonDecode(await _f.readAsString()) as Map<String, dynamic>;
    if (j['boot'] != bootId) {
      await clear();
      return null;
    }
    return base64.decode(j['key'] as String);
  }

  @override
  Future<void> clear() async {
    if (_f.existsSync()) await _f.delete();
  }
}

abstract class Biometrics {
  Future<bool> available();
  Future<bool> authenticate(String reason);
}

class SystemBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      return false;
    }
  }
}

/// Changes on every restart of the device. Null if unknown, in which case
/// the password is asked every time the app starts (the safe choice).
Future<String?> currentBootId() async {
  try {
    if (Platform.isLinux || Platform.isAndroid) {
      final f = File('/proc/sys/kernel/random/boot_id');
      if (f.existsSync()) return (await f.readAsString()).trim();
    }
    if (Platform.isMacOS) {
      final r = await Process.run('sysctl', ['-n', 'kern.boottime']);
      final out = (r.stdout as String).trim();
      final m = RegExp(r'sec = (\d+)').firstMatch(out);
      if (m != null) return 'mac-${m.group(1)}';
    }
  } catch (_) {}
  return null;
}

class LockSettings {
  LockSettings({required this.salt, required this.params, required this.wrapped, this.biometrics = true, this.relock = RelockAfter.fiveMinutes});
  Uint8List salt;
  KdfParams params;
  Uint8List wrapped;
  bool biometrics;
  RelockAfter relock;

  Map<String, Object?> toJson() => {
        'v': 1,
        'salt': base64.encode(salt),
        'kdf': params.toJson(),
        'wrapped': base64.encode(wrapped),
        'biometrics': biometrics,
        'relock': relock.name,
      };

  static LockSettings fromJson(Map<String, dynamic> j) => LockSettings(
        salt: base64.decode(j['salt'] as String),
        params: KdfParams.fromJson(j['kdf'] as Map<String, dynamic>),
        wrapped: base64.decode(j['wrapped'] as String),
        biometrics: j['biometrics'] as bool,
        relock: RelockAfter.values.byName(j['relock'] as String),
      );
}

class AppLock {
  AppLock({required this.dir, required this.cache, required this.biometrics, this.params = const KdfParams(), Future<String?> Function()? bootId})
      : _bootId = bootId ?? currentBootId;

  final Directory dir;
  final SessionCache cache;
  final Biometrics biometrics;
  final KdfParams params;
  final Future<String?> Function() _bootId;

  File get _file => File('${dir.path}/lock.json');
  bool get isSetUp => _file.existsSync();

  LockSettings? _settings;
  LockSettings get settings => _settings ??= LockSettings.fromJson(jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>);

  Future<void> _write() async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await tmp.rename(_file.path);
  }

  /// First setup, or changing the password.
  Future<void> setPassword(VaultKey key, String password, {bool? useBiometrics}) async {
    if (password.length < 6) throw ArgumentError('Use at least 6 characters.');
    final salt = randomBytes(16);
    final kek = await deriveKey(password, salt, params);
    final wrapped = await sealWithKey(kek, key.raw, 'lock:v1');
    _settings = LockSettings(
      salt: salt,
      params: params,
      wrapped: wrapped,
      biometrics: useBiometrics ?? _settings?.biometrics ?? true,
      relock: _settings?.relock ?? RelockAfter.fiveMinutes,
    );
    await _write();
    await _remember(key);
  }

  Future<void> updatePreferences({bool? useBiometrics, RelockAfter? relock}) async {
    if (useBiometrics != null) settings.biometrics = useBiometrics;
    if (relock != null) settings.relock = relock;
    await _write();
  }

  /// After a restart: the password, then the fingerprint too when it is on.
  Future<VaultKey> unlockWithPassword(String password) async {
    final key = await _keyFromPassword(password);
    if (await quickUnlockNeedsBiometrics() && !await biometrics.authenticate('Confirm it is you')) {
      throw BiometricsFailed();
    }
    await _remember(key);
    return key;
  }

  /// Checks the password only (used when changing it).
  Future<VaultKey> verifyPassword(String password) => _keyFromPassword(password);

  Future<VaultKey> _keyFromPassword(String password) async {
    final s = settings;
    final kek = await deriveKey(password, s.salt, s.params);
    try {
      final raw = await openWithKey(kek, s.wrapped, 'lock:v1');
      return VaultKey(raw);
    } on DecryptError {
      throw WrongPassword();
    }
  }

  Future<void> _remember(VaultKey key) async {
    final boot = await _bootId();
    if (boot != null) await cache.save(boot, key.raw);
  }

  /// True when the device has not restarted since the password was last
  /// entered, so a fingerprint is enough.
  Future<bool> canQuickUnlock() async {
    final boot = await _bootId();
    if (boot == null) return false;
    return (await cache.load(boot)) != null;
  }

  Future<bool> quickUnlockNeedsBiometrics() async => settings.biometrics && await biometrics.available();

  /// Fingerprint (if on), then the cached key. Null if not possible.
  Future<VaultKey?> quickUnlock() async {
    final boot = await _bootId();
    if (boot == null) return null;
    final raw = await cache.load(boot);
    if (raw == null) return null;
    if (await quickUnlockNeedsBiometrics()) {
      if (!await biometrics.authenticate('Unlock Comb')) return null;
    }
    return VaultKey(raw);
  }

  /// Forget the cached key (lock until the password is entered again).
  Future<void> lockHard() => cache.clear();

  Future<void> reset() async {
    await cache.clear();
    if (_file.existsSync()) await _file.delete();
    _settings = null;
  }
}
