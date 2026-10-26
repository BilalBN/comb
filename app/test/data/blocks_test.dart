import 'package:comb/data/blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every kind of line is read and written back exactly as it was', () {
    const body =
        '# Call with GCD\n\nNotes\n- [ ] Email GCD the PDFs\n  * [X] Nested, done\n- a bullet\n![[Attachments/plan.pdf]]\n## Next\n1. numbered stays text\n- [ ]\n';
    final blocks = parseBlocks(body);
    expect(blocks.map((b) => b.kind), [
      BlockKind.heading,
      BlockKind.text,
      BlockKind.text,
      BlockKind.check,
      BlockKind.check,
      BlockKind.bullet,
      BlockKind.embed,
      BlockKind.heading,
      BlockKind.text,
      BlockKind.check,
      BlockKind.text,
    ]);
    expect(blocks[4].done, isTrue);
    expect(blocks[4].indent, '  ');
    expect(blocks[3].text, 'Email GCD the PDFs');
    expect(blocks[6].text, 'Attachments/plan.pdf');
    expect(serializeBlocks(blocks), body);
  });

  test('an edited block is written from its parts', () {
    final b = Block.parse('* [ ] Call Rahul');
    b
      ..done = true
      ..text = 'Call Rahul back'
      ..touch();
    expect(b.toLine(), '* [x] Call Rahul back');
    b
      ..kind = BlockKind.text
      ..indent = ''
      ..touch();
    expect(b.toLine(), 'Call Rahul back');
  });

  test('links are found with their targets and labels', () {
    final spans = linkSpans('Ask [[Rahul]] about [[HCL Museum|the museum]]');
    expect(spans.map((s) => s.target), ['Rahul', 'HCL Museum']);
    expect(spans.last.label, 'the museum');
    expect(spans.first.start, 4);
    expect(spans.first.end, 13);
  });
}
