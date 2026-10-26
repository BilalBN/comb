import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:comb/core/blake2b.dart';
import 'package:comb/core/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/test-vectors.json is produced by the Python reference client
/// (libsodium). Matching it byte for byte proves the app and the
/// reference speak the same protocol.
Map<String, dynamic> loadVectors() {
  final file = File('../docs/test-vectors.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final v = loadVectors();
  final key = VaultKey(base64.decode(v['vault_key_b64'] as String));

  test('BLAKE2b matches RFC 7693 test vector for "abc"', () {
    final out = Blake2bP.hash(ascii.encode('abc'), outLength: 64);
    final hex = out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(
      hex,
      'ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1'
      '7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923',
    );
  });

  test('keyed, personalised BLAKE2b over several blocks matches libsodium', () {
    final person = Uint8List(16)..setRange(0, 12, ascii.encode('comb-test-v1'));
    final out = Blake2bP.hash(List<int>.filled(300, 0x61), outLength: 32, key: key.raw, person: person);
    final hex = out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(hex, v['blake2b_long_hex']);
  });

  test('subkeys match libsodium', () {
    expect(base64.encode(key.recordKey), v['record_key_b64']);
    expect(base64.encode(key.blobKey), v['blob_key_b64']);
  });

  test('recovery key matches and round-trips with typo detection', () {
    expect(key.recoveryKey(), v['recovery_key']);
    expect(VaultKey.fromRecoveryKey((v['recovery_key'] as String).toLowerCase()), key);
    final text = v['recovery_key'] as String;
    final typo = '${text[0] == 'B' ? 'C' : 'B'}${text.substring(1)}';
    expect(() => VaultKey.fromRecoveryKey(typo), throwsFormatException);
  });

  test('sealing a record with a fixed nonce gives the reference bytes', () async {
    final r = v['record'] as Map<String, dynamic>;
    final nonce = base64.decode(r['nonce_b64'] as String);
    final payload = jsonDecode(r['plaintext_utf8'] as String) as Map<String, Object?>;
    final blob = await sealRecord(key, r['record_id'] as String, payload, nonce: nonce);
    expect(base64.encode(blob), r['blob_b64']);
  });

  test('opening the reference record gives back Malayalam and Hindi text', () async {
    final r = v['record'] as Map<String, dynamic>;
    final opened = await openRecord(key, r['record_id'] as String, base64.decode(r['blob_b64'] as String));
    expect(opened['content'], contains('ഹലോ नमस्ते'));
  });

  test('a record cannot be opened under another id', () async {
    final r = v['record'] as Map<String, dynamic>;
    expect(
      () => openRecord(key, 'BBBBBBBBBBBBBBBBBBBBBB', base64.decode(r['blob_b64'] as String)),
      throwsA(isA<DecryptError>()),
    );
  });

  test('wrong key cannot open a record', () async {
    final r = v['record'] as Map<String, dynamic>;
    expect(
      () => openRecord(VaultKey.generate(), r['record_id'] as String, base64.decode(r['blob_b64'] as String)),
      throwsA(isA<DecryptError>()),
    );
  });

  test('attachments match the reference and its id is the ciphertext hash', () async {
    final a = v['attachment'] as Map<String, dynamic>;
    final sealed = await sealBlob(key, base64.decode(a['plaintext_b64'] as String), nonce: base64.decode(a['nonce_b64'] as String));
    expect(base64.encode(sealed.blob), a['blob_b64']);
    expect(sealed.id, a['blob_id']);
    expect(await openBlob(key, Uint8List.fromList(sealed.blob)), base64.decode(a['plaintext_b64'] as String));
  });

  test('the reference keycheck record opens', () async {
    final k = v['keycheck'] as Map<String, dynamic>;
    final opened = await openRecord(key, k['record_id'] as String, base64.decode(k['blob_b64'] as String));
    expect(opened, keycheckPayload);
  });

  test('random ids look like the server expects', () {
    final id = newRecordId();
    expect(RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(id), isTrue);
  });
}
