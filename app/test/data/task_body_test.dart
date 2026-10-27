import 'package:comb/data/task_body.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a mixed-up task body is split into notes, checklist and files', () {
    const body =
        '- [ ] Finish the document\n- [ ] Call with HCL\n- [ ] \n\n![[Attachments/2026-10/Affidavit.pdf]]\n- [ ]\nSee [[HCL Museum]] first.';
    final b = TaskBody.parse(body);
    expect(b.notes, 'See [[HCL Museum]] first.');
    expect(b.checklist.map((c) => c.text), ['Finish the document', 'Call with HCL', '', '']);
    expect(b.files, ['Attachments/2026-10/Affidavit.pdf']);
    expect(
      b.compose(),
      'See [[HCL Museum]] first.\n\n- [ ] Finish the document\n- [ ] Call with HCL\n\n![[Attachments/2026-10/Affidavit.pdf]]\n',
      reason: 'empty items are dropped and files go last',
    );
  });

  test('ticks, indents and an empty body survive', () {
    final b = TaskBody.parse('* [X] Done thing\n  - [ ] Nested');
    expect(b.checklist.first.done, isTrue);
    expect(b.checklist.last.indent, '  ');
    expect(b.compose(), '- [x] Done thing\n  - [ ] Nested\n');
    expect(TaskBody.parse('').compose(), '');
    expect(TaskBody.parse(b.compose()).compose(), b.compose(), reason: 'reading what we wrote changes nothing');
  });
}
