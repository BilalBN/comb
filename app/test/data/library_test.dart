import 'package:comb/data/frontmatter.dart';
import 'package:comb/data/library.dart';
import 'package:comb/data/models.dart';
import 'package:comb/data/views.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryFiles files;
  late Library lib;
  final now = DateTime(2026, 10, 26, 13);

  setUp(() {
    files = MemoryFiles();
    lib = Library(files, clock: () => now);
  });

  group('markdown', () {
    test('a task file reads well in Obsidian and round-trips', () {
      final cax = lib.addSpace('CAX');
      final t = lib.createTask(
        title: 'Send revised vault drawings to GCD',
        space: cax,
        project: 'HCL Museum',
        priority: Priority.high,
        due: Due(DateTime(2026, 10, 26, 16), hasTime: true),
        people: ['Ravi'],
        source: 'whatsapp',
      );
      final text = files.files[t.path]!;
      expect(t.path, 'Tasks/Send revised vault drawings to GCD.md');
      expect(text, contains('project: "[[HCL Museum]]"'));
      expect(text, contains('due: 2026-10-26T16:00'));
      expect(text, contains('  - "[[Ravi]]"'));
      expect(text, contains('created: "[[2026-10-26]]"'));
      final back = Task.fromMarkdown(t.path, text);
      expect(back.project, 'HCL Museum');
      expect(back.people, ['Ravi']);
      expect(back.due, t.due);
      expect(back.priority, Priority.high);
    });

    test('fields added in Obsidian are kept', () {
      files.files['Tasks/Mine.md'] = '---\ntype: task\nstatus: todo\nmood: calm\ntags:\n  - x\n---\nBody\n';
      lib.reload();
      final t = lib.tasks.single;
      lib.setTaskDone(t, true);
      final text = files.files['Tasks/Mine.md']!;
      expect(text, contains('mood: calm'));
      expect(text, contains('  - x'));
      expect(text, contains('status: done'));
      expect(text, endsWith('Body\n'));
    });

    test('a plain markdown file made in Obsidian is a note', () {
      files.files['CAX/Notes/Ideas.md'] = '# Ideas\nSome text';
      lib.reload();
      expect(lib.notes.single.title, 'Ideas');
      expect(lib.notes.single.body, '# Ideas\nSome text');
    });

    test('values that YAML would misread are quoted', () {
      final doc = MarkdownDoc({'a': 'yes', 'b': '12', 'c': 'x: y', 'd': '2026-10-26'}, '');
      final text = doc.render();
      expect(MarkdownDoc.parse(text).fields, {'a': 'yes', 'b': '12', 'c': 'x: y', 'd': '2026-10-26'});
    });
  });

  group('Spaces', () {
    test('moving Crypt4Bits under Personal moves its notes and updates its tasks', () {
      final personal = lib.addSpace('Personal');
      final c4b = lib.addSpace('Crypt4Bits');
      final gridnova = lib.addSpace('Gridnova', parent: c4b);
      final note = lib.createNote(title: 'Brand ideas', space: gridnova);
      final task = lib.createTask(title: 'Logo feedback', space: gridnova);
      expect(note.path, 'Crypt4Bits/Gridnova/Notes/Brand ideas.md');

      lib.updateSpace(c4b, parent: personal);
      expect(note.path, 'Personal/Crypt4Bits/Gridnova/Notes/Brand ideas.md');
      expect(files.files.containsKey('Personal/Crypt4Bits/Gridnova/Notes/Brand ideas.md'), isTrue);
      expect(files.files.containsKey('Crypt4Bits/Gridnova/Notes/Brand ideas.md'), isFalse);
      expect(task.spaceName, 'Personal/Crypt4Bits/Gridnova');

      lib.reload();
      expect(lib.spaceOf(lib.tasks.single)?.name, 'Gridnova');
    });

    test('a Space cannot move inside itself', () {
      final a = lib.addSpace('A');
      final b = lib.addSpace('B', parent: a);
      expect(() => lib.updateSpace(a, parent: b), throwsArgumentError);
    });

    test('renaming a Space survives a reload', () {
      final s = lib.addSpace('Work');
      lib.createTask(title: 'x', space: s);
      lib.updateSpace(s, name: 'CAX');
      lib.reload();
      expect(lib.spaces.single.name, 'CAX');
      expect(lib.spaceOf(lib.tasks.single)?.name, 'CAX');
    });
  });

  group('notes and tasks', () {
    test('Make task turns a note line into a linked task', () {
      final cax = lib.addSpace('CAX');
      final n = lib.createNote(title: 'HCL review call', kind: NoteKind.call, space: cax, project: 'HCL Museum',
          body: 'Discussed drawings\n- [ ] Send drawings to GCD tomorrow !h\n- plain item');
      final t = lib.makeTaskFromLine(n, 1);
      expect(t.title, 'Send drawings to GCD');
      expect(t.fromNote, 'HCL review call');
      expect(t.project, 'HCL Museum');
      expect(lib.spaceOf(t)?.name, 'CAX');
      expect(t.priority, Priority.high);
      expect(n.body.split('\n')[1], '- [ ] [[Send drawings to GCD]]');

      final t2 = lib.makeTaskFromLine(n, 2);
      expect(t2.title, 'plain item');
      expect(n.body.split('\n')[2], '- [ ] [[plain item]]');
    });

    test('ticking stays in sync both ways', () {
      final n = lib.createNote(title: 'Call', body: '- [ ] Send drawings');
      final t = lib.makeTaskFromLine(n, 0);

      lib.setTaskDone(t, true);
      expect(n.body, '- [x] [[Send drawings]]');

      n.body = '- [ ] [[Send drawings]]';
      lib.saveNote(n);
      expect(t.done, isFalse);

      n.body = '- [x] [[Send drawings]]';
      lib.saveNote(n);
      expect(t.done, isTrue);
      expect(Task.fromMarkdown(t.path, files.files[t.path]!).done, isTrue);
    });

    test('renaming a task updates links to it', () {
      final n = lib.createNote(title: 'Call', body: '- [ ] Send drawings');
      final t = lib.makeTaskFromLine(n, 0);
      lib.saveTask(t, newTitle: 'Send revised drawings');
      expect(t.path, 'Tasks/Send revised drawings.md');
      expect(n.body, '- [ ] [[Send revised drawings]]');
      expect(files.files.containsKey('Tasks/Send drawings.md'), isFalse);
    });

    test('same titles get distinct files', () {
      final a = lib.createTask(title: 'Call GCD');
      final b = lib.createTask(title: 'Call GCD');
      expect(a.path, isNot(b.path));
    });

    test('daily note is made once', () {
      final a = lib.dailyNote(now);
      final b = lib.dailyNote(now);
      expect(a, same(b));
      expect(a.path, 'Daily/2026-10-26.md');
    });

    test('backlinks find notes and tasks pointing at a project', () {
      lib.createNote(title: 'HCL Museum', kind: NoteKind.project);
      lib.createTask(title: 'Drawings', project: 'HCL Museum');
      lib.createNote(title: 'Visit', body: 'Met at [[HCL Museum]] site');
      final b = lib.backlinks('HCL Museum');
      expect(b.tasks.map((t) => t.title), ['Drawings']);
      expect(b.notes.map((n) => n.title), ['Visit']);
    });
  });

  group('views', () {
    test('urgent is automatic within the window, and can be set by hand', () {
      final v = Views(lib);
      final soon = lib.createTask(title: 'Soon', due: Due(DateTime(2026, 10, 28)));
      final later = lib.createTask(title: 'Later', due: Due(DateTime(2026, 11, 10)));
      final none = lib.createTask(title: 'No date');
      expect(v.isUrgent(soon), isTrue);
      expect(v.isUrgent(later), isFalse);
      expect(v.isUrgent(none), isFalse);
      none.urgentOverride = true;
      expect(v.isUrgent(none), isTrue);
    });

    test('matrix quadrants and moving between them', () {
      final v = Views(lib);
      final t = lib.createTask(title: 'Drawings', priority: Priority.high, due: Due(DateTime(2026, 10, 26)));
      expect(v.quadrantOf(t), Quadrant.doNow);
      v.moveToQuadrant(t, Quadrant.later);
      expect(t.priority, Priority.low);
      expect(t.urgentOverride, isFalse, reason: 'it is due today, so "not urgent" must be set by hand');
      expect(v.quadrantOf(t), Quadrant.later);
      v.moveToQuadrant(t, Quadrant.delegate);
      expect(t.urgentOverride, isNull, reason: 'automatic rule already says urgent');
    });

    test('today, upcoming, inbox and space filter', () {
      final cax = lib.addSpace('CAX');
      final me = lib.addSpace('Personal');
      lib.createTask(title: 'Overdue', space: cax, due: Due(DateTime(2026, 10, 20)));
      lib.createTask(title: 'Today', space: me, due: Due(DateTime(2026, 10, 26)));
      lib.createTask(title: 'Friday', space: cax, due: Due(DateTime(2026, 10, 30)));
      lib.createTask(title: 'Loose');
      final all = Views(lib);
      expect(all.today().map((t) => t.title), ['Overdue', 'Today']);
      expect(all.upcoming().values.expand((l) => l).map((t) => t.title), ['Friday']);
      expect(all.inbox().map((t) => t.title), ['Loose']);
      final caxOnly = Views(lib, filter: SpaceFilter(lib.subtreeIds(cax)));
      expect(caxOnly.today().map((t) => t.title), ['Overdue']);
      expect(all.openCount(cax), 2);
    });

    test('board moves change status', () {
      final v = Views(lib);
      final t = lib.createTask(title: 'x');
      v.moveToStatus(t, TaskStatus.waiting);
      expect(t.status, TaskStatus.waiting);
      v.moveToStatus(t, TaskStatus.done);
      expect(t.done, isTrue);
      expect(v.doneToday(), [t]);
    });
  });
}
