import 'package:comb/ui/setup/setup_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a bare domain becomes an https address', () {
    expect(normaliseServerAddress(' comb.crypt4bits.com/ '), 'https://comb.crypt4bits.com');
    expect(normaliseServerAddress('https://comb.crypt4bits.com'), 'https://comb.crypt4bits.com');
  });
  test('a server on this computer or the home network stays http', () {
    expect(normaliseServerAddress('127.0.0.1:8080'), 'http://127.0.0.1:8080');
    expect(normaliseServerAddress('192.168.1.20:8080'), 'http://192.168.1.20:8080');
    expect(normaliseServerAddress('http://127.0.0.1:8080/'), 'http://127.0.0.1:8080');
  });
  test('nothing typed stays empty', () => expect(normaliseServerAddress('  '), ''));
}
