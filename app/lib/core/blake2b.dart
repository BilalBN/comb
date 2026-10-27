import 'dart:typed_data';

/// BLAKE2b (RFC 7693) with key, salt and personalisation, as libsodium's
/// `crypto_generichash_blake2b_salt_personal`.
///
/// The `cryptography` package's BLAKE2b has no personalisation parameter,
/// which protocol v1 uses to derive subkeys, so this small implementation
/// fills the gap. It is checked against libsodium's output in the tests.
/// Native 64-bit integers only (not for the web).
class Blake2bP {
  static const _iv = <int>[
    0x6a09e667f3bcc908,
    -0x4498517a7b3558c5,
    0x3c6ef372fe94f82b,
    -0x5ab00ac5a0e2c90f,
    0x510e527fade682d1,
    -0x64fa9773d4c193e1,
    0x1f83d9abfb41bd6b,
    0x5be0cd19137e2179,
  ];

  static const _sigma = <List<int>>[
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
  ];

  /// Hashes [message] to [outLength] bytes (1..64).
  /// [key] up to 64 bytes; [salt] and [person] exactly 16 bytes when given.
  static Uint8List hash(List<int> message, {int outLength = 32, List<int>? key, List<int>? salt, List<int>? person}) {
    if (outLength < 1 || outLength > 64) throw ArgumentError('outLength must be 1..64');
    final keyLen = key?.length ?? 0;
    if (keyLen > 64) throw ArgumentError('key must be at most 64 bytes');
    if (salt != null && salt.length != 16) throw ArgumentError('salt must be 16 bytes');
    if (person != null && person.length != 16) throw ArgumentError('person must be 16 bytes');

    final h = List<int>.from(_iv);
    h[0] ^= 0x01010000 ^ (keyLen << 8) ^ outLength;
    if (salt != null) {
      h[4] ^= _load64(salt, 0);
      h[5] ^= _load64(salt, 8);
    }
    if (person != null) {
      h[6] ^= _load64(person, 0);
      h[7] ^= _load64(person, 8);
    }

    final input = BytesBuilder(copy: false);
    if (keyLen > 0) {
      final block = Uint8List(128)..setRange(0, keyLen, key!);
      input.add(block);
    }
    input.add(message);
    final data = input.toBytes();

    var counter = 0;
    if (data.isEmpty) {
      _compress(h, Uint8List(128), 0, true);
    } else {
      var offset = 0;
      while (data.length - offset > 128) {
        counter += 128;
        _compress(h, Uint8List.sublistView(data, offset, offset + 128), counter, false);
        offset += 128;
      }
      final last = Uint8List(128)..setRange(0, data.length - offset, data, offset);
      counter += data.length - offset;
      _compress(h, last, counter, true);
    }

    final out = Uint8List(64);
    for (var i = 0; i < 8; i++) {
      _store64(out, i * 8, h[i]);
    }
    return Uint8List.fromList(out.sublist(0, outLength));
  }

  static void _compress(List<int> h, Uint8List block, int counter, bool last) {
    final m = List<int>.generate(16, (i) => _load64(block, i * 8));
    final v = List<int>.filled(16, 0);
    for (var i = 0; i < 8; i++) {
      v[i] = h[i];
      v[i + 8] = _iv[i];
    }
    v[12] ^= counter; // low 64 bits of the byte counter (messages here are small)
    if (last) v[14] = ~v[14];

    for (var r = 0; r < 12; r++) {
      final s = _sigma[r % 10];
      _g(v, 0, 4, 8, 12, m[s[0]], m[s[1]]);
      _g(v, 1, 5, 9, 13, m[s[2]], m[s[3]]);
      _g(v, 2, 6, 10, 14, m[s[4]], m[s[5]]);
      _g(v, 3, 7, 11, 15, m[s[6]], m[s[7]]);
      _g(v, 0, 5, 10, 15, m[s[8]], m[s[9]]);
      _g(v, 1, 6, 11, 12, m[s[10]], m[s[11]]);
      _g(v, 2, 7, 8, 13, m[s[12]], m[s[13]]);
      _g(v, 3, 4, 9, 14, m[s[14]], m[s[15]]);
    }
    for (var i = 0; i < 8; i++) {
      h[i] ^= v[i] ^ v[i + 8];
    }
  }

  static void _g(List<int> v, int a, int b, int c, int d, int x, int y) {
    v[a] = v[a] + v[b] + x;
    v[d] = _rotr(v[d] ^ v[a], 32);
    v[c] = v[c] + v[d];
    v[b] = _rotr(v[b] ^ v[c], 24);
    v[a] = v[a] + v[b] + y;
    v[d] = _rotr(v[d] ^ v[a], 16);
    v[c] = v[c] + v[d];
    v[b] = _rotr(v[b] ^ v[c], 63);
  }

  static int _rotr(int x, int n) => (x >>> n) | (x << (64 - n));

  static int _load64(List<int> b, int o) {
    var x = 0;
    for (var i = 7; i >= 0; i--) {
      x = (x << 8) | (b[o + i] & 0xff);
    }
    return x;
  }

  static void _store64(Uint8List b, int o, int x) {
    for (var i = 0; i < 8; i++) {
      b[o + i] = (x >>> (8 * i)) & 0xff;
    }
  }
}
