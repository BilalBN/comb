import 'package:comb/data/models.dart';
import 'package:comb/data/quick_add.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Monday 26 October 2026, 13:00.
  final now = DateTime(2026, 10, 26, 13);
  final spaces = [
    Space(id: 'p', name: 'Personal'),
    Space(id: 'c', name: 'CAX'),
    Space(id: 'b', name: 'Crypt4Bits'),
    Space(id: 'g', name: 'Gridnova', parentId: 'b'),
  ];
  QuickAdd parse(String s) => parseQuickAdd(s, spaces: spaces, now: now);

  test('the example from the app', () {
    final q = parse('Call GCD tomorrow 4pm #CAX !h');
    expect(q.title, 'Call GCD');
    expect(q.space?.name, 'CAX');
    expect(q.priority, Priority.high);
    expect(q.due, Due(DateTime(2026, 10, 27, 16), hasTime: true));
  });

  test('urgent, people and sub-spaces', () {
    final q = parse('Logo feedback @Ravi #Crypt4Bits/Gridnova !u');
    expect(q.title, 'Logo feedback');
    expect(q.space?.name, 'Gridnova');
    expect(q.urgent, isTrue);
    expect(q.people, ['Ravi']);
  });

  test('space names are matched in any case and unknown tags stay in the title', () {
    final q = parse('Plan #cax review #later');
    expect(q.space?.name, 'CAX');
    expect(q.title, 'Plan review #later');
  });

  test('dates', () {
    expect(parse('x today').due, Due(DateTime(2026, 10, 26)));
    expect(parse('x tmr').due, Due(DateTime(2026, 10, 27)));
    expect(parse('x friday').due, Due(DateTime(2026, 10, 30)));
    expect(parse('x monday').due, Due(DateTime(2026, 11, 2)), reason: 'today is Monday: the next one');
    expect(parse('x next week').due, Due(DateTime(2026, 11, 2)));
    expect(parse('x in 3 days').due, Due(DateTime(2026, 10, 29)));
    expect(parse('x 28 oct').due, Due(DateTime(2026, 10, 28)));
    expect(parse('x oct 28').due, Due(DateTime(2026, 10, 28)));
    expect(parse('x 28/10').due, Due(DateTime(2026, 10, 28)), reason: 'day first');
    expect(parse('x 5 jan').due, Due(DateTime(2027, 1, 5)), reason: 'past dates mean next year');
    expect(parse('x 2026-12-01').due, Due(DateTime(2026, 12, 1)));
  });

  test('times', () {
    expect(parse('x tomorrow 16:30').due, Due(DateTime(2026, 10, 27, 16, 30), hasTime: true));
    expect(parse('x friday at 9').due, Due(DateTime(2026, 10, 30, 9), hasTime: true));
    expect(parse('x 4:15pm').due, Due(DateTime(2026, 10, 26, 16, 15), hasTime: true), reason: 'later today');
    expect(parse('x 9am').due, Due(DateTime(2026, 10, 27, 9), hasTime: true), reason: '9am has passed: tomorrow');
  });

  test('Malayalam and Hindi titles are kept as typed', () {
    final q = parse('ഡ്രോയിംഗ് അയക്കുക कल tomorrow #CAX');
    expect(q.title, 'ഡ്രോയിംഗ് അയക്കുക कल');
    expect(q.space?.name, 'CAX');
  });

  test('plain text is just a title', () {
    final q = parse('Buy milk');
    expect(q.title, 'Buy milk');
    expect(q.due, isNull);
    expect(q.space, isNull);
  });
}
