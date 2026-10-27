import 'dart:io';

import 'package:comb/app/controller.dart';
import 'package:comb/core/crypto.dart';
import 'package:comb/data/models.dart';
import 'package:comb/main.dart';
import 'package:comb/security/app_lock.dart';
import 'package:comb/sync/folder_check.dart';
import 'package:comb/sync/state.dart';
import 'package:comb/ui/editor/checklist_editor.dart';
import 'package:comb/ui/folder_picker.dart';
import 'package:comb/ui/home/home_shell.dart';
import 'package:comb/ui/settings/settings_screen.dart';
import 'package:comb/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../security/app_lock_test.dart' show FakeBiometrics, MemoryCache;

/// An app opened on an account whose server can't be reached: everything
/// works offline, which is what these screen tests need.
Future<AppController> offlineApp(WidgetTester tester, Directory dir, {bool seed = true}) async {
  final c = AppController(
    appDir: dir,
    lock: AppLock(
      dir: dir,
      cache: MemoryCache(),
      biometrics: FakeBiometrics(),
      params: const KdfParams(memoryKib: 256, iterations: 1),
      bootId: () async => 'b',
    ),
    syncEvery: const Duration(hours: 1),
    clock: () => DateTime(2026, 10, 26, 13),
  );
  await tester.runAsync(() async {
    final key = VaultKey.generate();
    await c.lock.setPassword(key, 'correct horse');
    await c.debugOpen(
      key,
      VaultState(
        connection: Connection(serverUrl: 'http://127.0.0.1:9', token: 't', deviceId: 'd', deviceName: 'MacBook'),
      ),
    );
    final lib = c.library!;
    if (!seed) return;
    final cax = lib.addSpace('CAX', color: 'blue');
    final c4b = lib.addSpace('Crypt4Bits', color: 'violet');
    lib.addSpace('Gridnova', parent: c4b);
    lib.addSpace('Personal', color: 'green');
    lib.createTask(
      title: 'Send revised vault drawings to GCD',
      space: cax,
      priority: Priority.high,
      due: Due(DateTime(2026, 10, 26, 16), hasTime: true),
      project: 'HCL Museum',
    );
    lib.createTask(title: 'Review Wayfinder demo build', space: cax, due: Due(DateTime(2026, 10, 29)));
    lib.createTask(title: 'Pick a domain for Comb', priority: Priority.high);
    lib.createNote(title: 'HCL review call', kind: NoteKind.call, space: cax, body: 'Notes\n- [ ] Email GCD the PDFs');
    await c.syncNow(); // let the first (offline) sync finish before the test runs
  });
  return c;
}

Future<void> pumpApp(WidgetTester tester, AppController c) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(CombApp(controller: c));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('comb-ui-'));
  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  testWidgets('Today shows tasks, quick add adds one with its Space and date', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Send revised vault drawings to GCD'), findsOneWidget);
    expect(find.byIcon(Icons.bolt), findsWidgets, reason: 'urgent tasks show a bolt');

    await tester.enterText(find.widgetWithText(TextField, 'Add a task: Call GCD tomorrow 4pm #CAX !h'), 'Call Ravi today 5pm #CAX');
    await tester.pump();
    expect(find.text('Will add:'), findsOneWidget);
    await tester.tap(find.text('Add ↵'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Call Ravi'), findsOneWidget);
    final added = c.library!.tasks.firstWhere((t) => t.title == 'Call Ravi');
    expect(c.library!.spaceOf(added)?.name, 'CAX');
    c.dispose();
  });

  testWidgets('opening a task shows its details and editing fields saves', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    await tester.tap(find.text('Send revised vault drawings to GCD'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('- [ ]'), findsNothing);
    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Low').last);
    await tester.pumpAndSettle();
    expect(c.library!.tasks.firstWhere((t) => t.title.startsWith('Send')).priority, Priority.low);
    await tester.tap(find.text('To do'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Waiting').last);
    await tester.pumpAndSettle();
    expect(find.text('Waiting on'), findsOneWidget);

    // A checklist in the task's notes shows as checkboxes and counts on the row.
    await tester.enterText(find.widgetWithText(TextField, 'Add an item'), 'Print the PDFs');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(seconds: 1));
    final task = c.library!.tasks.firstWhere((t) => t.title.startsWith('Send'));
    expect(task.body.trim(), '- [ ] Print the PDFs');
    expect(task.subtasks.single.text, 'Print the PDFs');
    expect(find.text('- [ ] Print the PDFs'), findsNothing);
    expect(find.text('0/1'), findsWidgets, reason: 'on the row and in the panel');
    c.dispose();
  });

  testWidgets('every view renders: inbox, upcoming, matrix, board, notes, a Space, search', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    for (final (label, expectText) in const [
      ('Inbox', 'Pick a domain for Comb'),
      ('Upcoming', 'Review Wayfinder demo build'),
      ('Matrix', 'Do now'),
      ('Board', 'To do'),
      ('Notes', 'HCL review call'),
      ('Calendar', 'Mon'),
      ('Weekly review', 'High priority with no date · 1'),
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(expectText), findsWidgets, reason: label);
    }
    await tester.tap(find.text('Gridnova'));
    await tester.pump();
    expect(find.text('No open tasks here yet.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Search (⌘F)'), 'wayfinder');
    await tester.pump();
    expect(find.text('Review Wayfinder demo build'), findsOneWidget);
    c.dispose();
  });

  testWidgets('matrix drag moves a task to another box', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    c.go(NavView.matrix);
    await tester.pump();
    final card = find.text('Send revised vault drawings to GCD');
    final target = find.text('Drop or later');
    final g = await tester.startGesture(tester.getCenter(card));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveTo(tester.getCenter(target) + const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await tester.pump(const Duration(milliseconds: 100));
    final t = c.library!.tasks.firstWhere((x) => x.title.startsWith('Send'));
    expect(t.priority, Priority.low);
    expect(c.views.isUrgent(t), isFalse);
    c.dispose();
  });

  testWidgets('a note opens, and Make task turns a line into a linked task', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    c.go(NavView.notes);
    await tester.pump();
    await tester.tap(find.text('HCL review call'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('- [ ] Email GCD the PDFs'), findsNothing, reason: 'checklists show as checkboxes');
    final line = tester.widgetList<TextField>(find.byType(TextField)).firstWhere((f) => f.controller?.text == 'Email GCD the PDFs');
    line.focusNode!.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Make task'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.library!.taskByTitle('Email GCD the PDFs')?.fromNote, 'HCL review call');
    expect(find.text('Tasks from this note · 1'), findsOneWidget);
    c.dispose();
  });

  testWidgets('settings: every tab renders', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    final ctx = tester.element(find.byType(HomeShell));
    showSettings(ctx, c);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Settings'), findsOneWidget);
    for (final tab in ['Spaces', 'App lock', 'Sync and folder', 'About', 'Look and feel']) {
      await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text(tab)).first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.descendant(of: find.byType(SettingsScreen), matching: find.text(tab)),
        findsNWidgets(2),
        reason: '$tab is open',
      );
    }
    await tester.tap(find.descendant(of: find.byType(SettingsScreen), matching: find.text('Dark')));
    await tester.pump();
    expect(c.prefs.themeMode, ThemeMode.dark);
    c.dispose();
  });

  testWidgets('dark mode and compact density render', (tester) async {
    final c = await offlineApp(tester, dir);
    c.prefs.themeMode = ThemeMode.dark;
    await pumpApp(tester, c);
    expect(find.text('Send revised vault drawings to GCD'), findsOneWidget);
    c.dispose();
  });

  testWidgets('setup starts with the welcome screen and moves to the server step', (tester) async {
    final c = AppController(
      appDir: dir,
      lock: AppLock(dir: dir, cache: MemoryCache(), biometrics: FakeBiometrics(), bootId: () async => 'b'),
    );
    await tester.runAsync(c.start);
    await pumpApp(tester, c);
    expect(find.text('Welcome to Comb'), findsOneWidget);
    await tester.tap(find.text('Set up Comb'));
    await tester.pump();
    expect(find.text('Your Comb server'), findsOneWidget);
    c.dispose();
  });

  testWidgets('lock screen asks for the password', (tester) async {
    final c = await offlineApp(tester, dir);
    await tester.runAsync(() async {
      await c.lock.lockHard(); // as after a restart: no fingerprint shortcut
      await c.lockNow();
    });
    await pumpApp(tester, c);
    expect(find.text('Comb is locked'), findsOneWidget);
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(find.text('Enter your app password.'), findsOneWidget);
    c.dispose();
  });

  testWidgets('a narrower window with the task panel open still fits', (tester) async {
    final c = await offlineApp(tester, dir);
    tester.view.physicalSize = const Size(1000, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(CombApp(controller: c));
    await tester.pump();
    await tester.tap(find.text('Send revised vault drawings to GCD'));
    await tester.pump(const Duration(milliseconds: 100));
    final task = c.library!.tasks.firstWhere((t) => t.title.startsWith('Send'));
    for (final v in [NavView.today, NavView.matrix, NavView.board, NavView.calendar, NavView.review, NavView.upcoming]) {
      c.go(v);
      c.selectTask(task);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Repeat'), findsOneWidget);
    c.dispose();
  });

  testWidgets('export writes a CSV and a JSON file', (tester) async {
    final c = await offlineApp(tester, dir);
    final out = Directory('${dir.path}/export')..createSync();
    final files = await tester.runAsync(() => c.exportTo(out.path));
    expect(files, hasLength(2));
    final csv = File(files!.first).readAsStringSync();
    expect(csv, contains('Send revised vault drawings to GCD'));
    expect(csv.split('\n').first, startsWith('title,space'));
    c.dispose();
  });

  testWidgets('an account without Spaces says so on Home and offers to add them', (tester) async {
    final c = await offlineApp(tester, dir, seed: false);
    await pumpApp(tester, c);
    expect(find.byKey(const Key('banner-spaces')), findsOneWidget);
    await tester.tap(find.text('Add Spaces'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SettingsScreen), findsOneWidget);
    c.dispose();
  });

  testWidgets('a markdown folder that fails shows a warning instead of freezing', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    expect(find.byKey(const Key('banner-spaces')), findsNothing);
    expect(find.byKey(const Key('banner-folder')), findsNothing);
    final file = File('${dir.path}/plain-file')..writeAsStringSync('x');
    await tester.runAsync(() => c.chooseFolder('${file.path}/Vault'));
    await tester.pump();
    expect(find.byKey(const Key('banner-folder')), findsOneWidget);
    c.dispose();
  });

  group('choosing a markdown folder', () {
    Future<String?> pick(WidgetTester tester, FolderCheck result, {String? tapAfter}) async {
      String? picked = 'not finished';
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(
            CombTokens.of(dark: false, accent: Accent.values.first, density: Density.values.first, font: FontChoice.values.first),
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await pickMarkdownFolder(context, choose: () async => result.path, check: (_) async => result),
              child: const Text('pick'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();
      if (tapAfter != null) {
        await tester.tap(find.text(tapAfter));
        await tester.pumpAndSettle();
      }
      return picked;
    }

    testWidgets('a good folder is used straight away', (tester) async {
      expect(await pick(tester, FolderCheck(path: '/Users/b/Documents/Comb Vault', writable: true)), '/Users/b/Documents/Comb Vault');
    });

    testWidgets('a Google Drive folder warns that notes would be unencrypted there', (tester) async {
      const path = '/Users/b/Library/CloudStorage/GoogleDrive-b/My Drive/Comb';
      final check = FolderCheck(path: path, writable: true, cloud: cloudServiceFor(path));
      expect(await pick(tester, check, tapAfter: 'Choose another'), isNull);
      expect(await pick(tester, check), 'not finished');
      expect(find.textContaining('unencrypted'), findsOneWidget);
      await tester.tap(find.text('Use it anyway'));
      await tester.pumpAndSettle();
    });

    testWidgets('a folder that is too slow to read is refused', (tester) async {
      expect(await pick(tester, FolderCheck(path: '/x', writable: true, tooSlow: true), tapAfter: 'OK'), isNull);
    });
  });

  testWidgets('the sidebar still works while a note is open', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    c.go(NavView.notes);
    await tester.pump();
    await tester.tap(find.text('HCL review call'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.selectedNote, isNotNull);
    await tester.tap(find.text('Matrix'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.selectedNote, isNull);
    expect(find.text('Do now'), findsOneWidget);
    c.dispose();
  });

  testWidgets('the "Added" message goes away by itself', (tester) async {
    final c = await offlineApp(tester, dir);
    await pumpApp(tester, c);
    await tester.enterText(find.byType(TextField).at(1), 'Call the printer');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Added "Call the printer"'), findsOneWidget);
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Added "Call the printer"'), findsNothing);
    c.dispose();
  });

  testWidgets('the task panel keeps checklist, notes and files apart', (tester) async {
    final c = await offlineApp(tester, dir);
    final task = c.library!.tasks.firstWhere((t) => t.title.startsWith('Send'));
    task.body = '- [ ] Finish the document\n- [ ] Call with HCL\n- [ ] \n\n![[Attachments/2026-10/Affidavit.pdf]]\n- [ ] ';
    c.saveTask(task);
    await pumpApp(tester, c);
    c.selectTask(task);
    await tester.pump(const Duration(milliseconds: 100));
    final boxes = find.descendant(
      of: find.byType(ChecklistEditor),
      matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.checked != null),
    );
    expect(boxes, findsNWidgets(2), reason: 'no empty checkboxes');
    expect(find.text('Affidavit.pdf'), findsOneWidget);
    expect(find.text('0/2'), findsWidgets);

    await tester.tap(boxes.first);
    await tester.pump(const Duration(milliseconds: 100));
    final saved = c.library!.tasks.firstWhere((t) => t.title.startsWith('Send')).body;
    expect(saved, '- [x] Finish the document\n- [ ] Call with HCL\n\n![[Attachments/2026-10/Affidavit.pdf]]\n');

    await tester.enterText(find.widgetWithText(TextField, 'Details, links to notes or people…'), 'Ask Ravi for the stamp paper');
    await tester.pump(const Duration(seconds: 1));
    expect(
      c.library!.tasks.firstWhere((t) => t.title.startsWith('Send')).body,
      'Ask Ravi for the stamp paper\n\n- [x] Finish the document\n- [ ] Call with HCL\n\n![[Attachments/2026-10/Affidavit.pdf]]\n',
    );
    c.dispose();
  });
}
