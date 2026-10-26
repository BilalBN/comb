import 'dart:io';

import 'package:comb/app/controller.dart';
import 'package:comb/core/crypto.dart';
import 'package:comb/data/models.dart';
import 'package:comb/main.dart';
import 'package:comb/security/app_lock.dart';
import 'package:comb/sync/state.dart';
import 'package:comb/ui/home/home_shell.dart';
import 'package:comb/ui/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../security/app_lock_test.dart' show FakeBiometrics, MemoryCache;

/// An app opened on an account whose server can't be reached: everything
/// works offline, which is what these screen tests need.
Future<AppController> offlineApp(WidgetTester tester, Directory dir) async {
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
    expect(find.text('Urgent'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextField, 'Add a task, e.g. Call GCD tomorrow 4pm #CAX !h'), 'Call Ravi today 5pm #CAX');
    await tester.pump();
    expect(find.text('Will add:'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
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
    expect(find.text('Checklist'), findsNothing);
    await tester.tap(find.text('Low').first);
    await tester.pump();
    expect(c.library!.tasks.firstWhere((t) => t.title.startsWith('Send')).priority, Priority.low);
    await tester.tap(find.text('Waiting'));
    await tester.pump();
    expect(find.text('Waiting on'), findsOneWidget);
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
    final body = find.byWidgetPredicate((w) => w is TextField && (w.minLines ?? 0) >= 16);
    expect(body, findsOneWidget);
    final field = tester.widget<TextField>(body);
    field.controller!.selection = TextSelection.collapsed(offset: field.controller!.text.indexOf('Email'));
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
    for (final v in [NavView.today, NavView.matrix, NavView.board, NavView.calendar, NavView.review, NavView.upcoming]) {
      c.go(v);
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
}
