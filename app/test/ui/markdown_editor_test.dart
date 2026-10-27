import 'package:comb/data/library.dart';
import 'package:comb/ui/editor/markdown_editor.dart';
import 'package:comb/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class Harness {
  String text;
  int? madeTaskOn;
  String? opened;
  final key = GlobalKey<MarkdownEditorState>();
  Harness(this.text);
}

Future<Harness> pumpEditor(WidgetTester tester, String text, {Library? lib}) async {
  final h = Harness(text);
  final library = lib ?? Library(MemoryFiles(), clock: () => DateTime(2026, 10, 27));
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(
        CombTokens.of(dark: false, accent: Accent.values.first, density: Density.values.first, font: FontChoice.values.first),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarkdownEditor(
            key: h.key,
            text: text,
            lib: library,
            onChanged: (s) => h.text = s,
            onMakeTask: (i) => h.madeTaskOn = i,
            onOpenLink: (s) => h.opened = s,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return h;
}

TextField fieldWith(WidgetTester tester, String text) =>
    tester.widgetList<TextField>(find.byType(TextField)).firstWhere((f) => f.controller!.text == text);

Future<void> focusAt(WidgetTester tester, String text, int offset) async {
  final f = fieldWith(tester, text);
  f.focusNode!.requestFocus();
  await tester.pump();
  f.controller!.selection = TextSelection.collapsed(offset: offset);
  await tester.pump();
}

void main() {
  testWidgets('a checklist shows real checkboxes, never "- [ ]"', (tester) async {
    final h = await pumpEditor(tester, 'Notes\n- [ ] Email GCD the PDFs\n- [x] Book the venue');
    expect(find.text('- [ ] Email GCD the PDFs'), findsNothing);
    expect(fieldWith(tester, 'Email GCD the PDFs'), isNotNull);
    final boxes = find.byWidgetPredicate((w) => w is Semantics && w.properties.checked != null);
    expect(boxes, findsNWidgets(2));
    await tester.tap(boxes.first);
    await tester.pump();
    expect(h.text, 'Notes\n- [x] Email GCD the PDFs\n- [x] Book the venue');
  });

  testWidgets('Enter continues a checklist; Enter on an empty item ends it', (tester) async {
    final h = await pumpEditor(tester, '- [ ] First');
    await focusAt(tester, 'First', 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(h.text, '- [ ] First\n- [ ] ');
    await tester.enterText(find.byType(TextField).last, 'Second');
    await tester.pump();
    expect(h.text, '- [ ] First\n- [ ] Second');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(h.text, '- [ ] First\n- [ ] Second\n', reason: 'the empty item became a plain line');
  });

  testWidgets('Backspace at the start removes the checkbox, then joins lines', (tester) async {
    final h = await pumpEditor(tester, 'Hello\n- [ ] world');
    await focusAt(tester, 'world', 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(h.text, 'Hello\nworld');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(h.text, 'Helloworld');
  });

  testWidgets('the Checklist button turns the current line into an item', (tester) async {
    final h = await pumpEditor(tester, 'Buy paint');
    await focusAt(tester, 'Buy paint', 3);
    await tester.tap(find.text('Checklist'));
    await tester.pump();
    expect(h.text, '- [ ] Buy paint');
  });

  testWidgets('pasting several lines makes several blocks', (tester) async {
    final h = await pumpEditor(tester, '');
    await tester.enterText(find.byType(TextField).first, 'One\n- [ ] Two\nThree');
    await tester.pump();
    await tester.pump();
    expect(h.text, 'One\n- [ ] Two\nThree');
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.checked != null), findsOneWidget);
  });

  testWidgets('the Link button lists notes and inserts [[link]] without typing it', (tester) async {
    final lib = Library(MemoryFiles(), clock: () => DateTime(2026, 10, 27));
    lib.createNote(title: 'HCL Museum');
    lib.createNote(title: 'Rahul');
    final h = await pumpEditor(tester, 'Talk to ', lib: lib);
    await focusAt(tester, 'Talk to ', 8);
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Link to a note, task or person'), 'rah');
    await tester.pump();
    await tester.tap(find.text('Rahul').last);
    await tester.pumpAndSettle();
    expect(h.text, 'Talk to [[Rahul]]');
  });

  testWidgets('typing [[ opens the link list', (tester) async {
    final lib = Library(MemoryFiles(), clock: () => DateTime(2026, 10, 27));
    lib.createNote(title: 'Wayfinder');
    final h = await pumpEditor(tester, 'See ', lib: lib);
    await focusAt(tester, 'See ', 4);
    final f = fieldWith(tester, 'See ');
    f.controller!.value = const TextEditingValue(text: 'See [[', selection: TextSelection.collapsed(offset: 6));
    await tester.pumpAndSettle();
    expect(find.text('Wayfinder'), findsOneWidget);
    await tester.tap(find.text('Wayfinder'));
    await tester.pumpAndSettle();
    expect(h.text, 'See [[Wayfinder]]');
  });

  testWidgets('⌘↩ asks to make a task from the current line', (tester) async {
    final h = await pumpEditor(tester, 'Intro\nSend drawings to GCD');
    await focusAt(tester, 'Send drawings to GCD', 4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(h.madeTaskOn, 1);
  });

  testWidgets('links show without brackets until the line is edited', (tester) async {
    await pumpEditor(tester, 'Ask [[Rahul]] today');
    final f = fieldWith(tester, 'Ask [[Rahul]] today');
    final ctl = f.controller! as LinkTextController;
    expect(ctl.showMarks, isFalse);
    f.focusNode!.requestFocus();
    await tester.pump();
    expect(ctl.showMarks, isTrue);
  });
}
