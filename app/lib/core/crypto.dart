/// Comb protocol v1 cryptography (see docs/protocol.md).
///
/// Everything a device encrypts or decrypts goes through here. The server
/// never sees the vault key or any plaintext.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'blake2b.dart';

const formatV1 = 0x01;
const keycheckRecordId = '0000keycheck0000';
const keycheckPayload = {'type': 'keycheck', 'value': 'comb-keycheck-v1'};

class DecryptError implements Exception {
  DecryptError(this.message);
  final String message;
  @override
  String toString() => message;
}

final _rng = Random.secure();

Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// 16 random bytes, base64url: never derived from a file name.
String newRecordId() => _b64url(randomBytes(16));

String newChangeId() => _b64url(randomBytes(16));

const _cipherOverhead = 1 + 24 + 16;

final DartXchacha20 _aead = DartXchacha20.poly1305Aead();

class VaultKey {
  VaultKey(List<int> raw) : raw = Uint8List.fromList(raw) {
    if (raw.length != 32) throw ArgumentError('vault key must be 32 bytes');
  }

  factory VaultKey.generate() => VaultKey(randomBytes(32));

  final Uint8List raw;

  Uint8List _subkey(String purpose) {
    final person = Uint8List(16)..setRange(0, purpose.length, ascii.encode(purpose));
    return Blake2bP.hash(const [], outLength: 32, key: raw, person: person);
  }

  late final Uint8List recordKey = _subkey('comb-record-v1');
  late final Uint8List blobKey = _subkey('comb-blob-v1');

  /// Encrypts this device's own saved state at rest. Never leaves the device.
  late final Uint8List localKey = _subkey('comb-local-v1');

  /// Base32 of key + 2-byte checksum, in dash-separated groups of five.
  String recoveryKey() {
    final check = Blake2bP.hash(raw, outLength: 2);
    final text = _base32Encode([...raw, ...check]);
    final groups = <String>[];
    for (var i = 0; i < text.length; i += 5) {
      groups.add(text.substring(i, min(i + 5, text.length)));
    }
    return groups.join('-');
  }

  static VaultKey fromRecoveryKey(String text) {
    final cleaned = text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final Uint8List data;
    try {
      data = _base32Decode(cleaned);
    } on FormatException {
      throw const FormatException('That recovery key is not valid.');
    }
    if (data.length < 34) throw const FormatException('That recovery key is too short.');
    final raw = data.sublist(0, 32);
    final check = data.sublist(32, 34);
    final expected = Blake2bP.hash(raw, outLength: 2);
    if (expected[0] != check[0] || expected[1] != check[1]) {
      throw const FormatException('That recovery key has a typo.');
    }
    return VaultKey(raw);
  }

  @override
  bool operator ==(Object other) => other is VaultKey && _equal(other.raw, raw);

  @override
  int get hashCode => Object.hashAll(raw);
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

List<int> _aad(String kind, String ident) => ascii.encode('comb:$kind:$ident');

Future<Uint8List> _seal(Uint8List key, List<int> nonce, List<int> aad, List<int> plaintext) async {
  final box = await _aead.encrypt(plaintext, secretKey: SecretKey(key), nonce: nonce, aad: aad);
  return Uint8List.fromList([formatV1, ...nonce, ...box.cipherText, ...box.mac.bytes]);
}

Future<Uint8List> _open(Uint8List key, Uint8List blob, List<int> aad, String what) async {
  if (blob.length < _cipherOverhead || blob[0] != formatV1) {
    throw DecryptError('Unknown $what format.');
  }
  final nonce = blob.sublist(1, 25);
  final ct = blob.sublist(25, blob.length - 16);
  final mac = Mac(blob.sublist(blob.length - 16));
  try {
    final clear = await _aead.decrypt(SecretBox(ct, nonce: nonce, mac: mac), secretKey: SecretKey(key), aad: aad);
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw DecryptError('Could not decrypt this $what.');
  }
}

String canonicalJson(Map<String, Object?> payload) => jsonEncode(_sortKeys(payload));

Object? _sortKeys(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sortKeys(v[k])};
  }
  if (v is List) return v.map(_sortKeys).toList();
  return v;
}

Future<Uint8List> sealRecord(VaultKey key, String recordId, Map<String, Object?> payload, {List<int>? nonce}) {
  final plaintext = utf8.encode(canonicalJson(payload));
  return _seal(key.recordKey, nonce ?? randomBytes(24), _aad('record', recordId), plaintext);
}

Future<Map<String, Object?>> openRecord(VaultKey key, String recordId, Uint8List blob) async {
  final clear = await _open(key.recordKey, blob, _aad('record', recordId), 'record');
  final decoded = jsonDecode(utf8.decode(clear));
  if (decoded is! Map<String, Object?>) throw DecryptError('Record is not an object.');
  return decoded;
}

/// Returns the attachment's id (SHA-256 hex of the ciphertext) and ciphertext.
Future<({String id, Uint8List blob})> sealBlob(VaultKey key, List<int> data, {List<int>? nonce}) async {
  final blob = await _seal(key.blobKey, nonce ?? randomBytes(24), _aad('blob', 'v1'), data);
  return (id: await sha256Hex(blob), blob: blob);
}

Future<Uint8List> openBlob(VaultKey key, Uint8List blob) => _open(key.blobKey, blob, _aad('blob', 'v1'), 'attachment');

Future<String> sha256Hex(List<int> data) async {
  final digest = await const DartSha256().hash(data);
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ---------------------------------------------------------------- base32

const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String _base32Encode(List<int> data) {
  final out = StringBuffer();
  var buffer = 0, bits = 0;
  for (final byte in data) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_b32[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_b32[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List _base32Decode(String text) {
  final out = <int>[];
  var buffer = 0, bits = 0;
  for (final ch in text.split('')) {
    final v = _b32.indexOf(ch);
    if (v < 0) throw const FormatException('bad base32');
    buffer = ((buffer << 5) | v) & 0xffffffff;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out);
}

/// Encrypts data kept on this device (its saved state), so a copy of the
/// app's storage is unreadable without the vault key.
Future<Uint8List> sealLocal(VaultKey key, List<int> data) =>
    _seal(key.localKey, randomBytes(24), ascii.encode('comb:local:v1'), data);

Future<Uint8List> openLocal(VaultKey key, Uint8List blob) =>
    _open(key.localKey, blob, ascii.encode('comb:local:v1'), 'saved state');

/// Wraps the vault key with a key derived from the person's app password.
Future<Uint8List> sealWithKey(List<int> keyBytes, List<int> data, String context) =>
    _seal(Uint8List.fromList(keyBytes), randomBytes(24), ascii.encode('comb:$context'), data);

Future<Uint8List> openWithKey(List<int> keyBytes, Uint8List blob, String context) =>
    _open(Uint8List.fromList(keyBytes), blob, ascii.encode('comb:$context'), context);

