// Renders real screenshots with the Inter font, for checking the look.
// Run with: COMB_SCREENSHOTS=<folder> flutter test test/ui/screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:comb/app/controller.dart';
import 'package:comb/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screens_test.dart' show offlineApp;

final _out = Platform.environment['COMB_SCREENSHOTS'];

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter')..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
  await inter.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 100));
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
  final image = await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1);
    return img.toByteData(format: ui.ImageByteFormat.png);
  });
  File('$_out/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(image!.buffer.asUint8List());
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('comb-shot-'));

  testWidgets('screenshots', (tester) async {
    await tester.runAsync(_loadFonts);
    final c = await offlineApp(tester, dir);
    c.syncStatus = SyncStatus.synced;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: CombApp(controller: c),
      ),
    );
    await tester.pump();

    await _shot(tester, '01-today');
    await tester.tap(find.text('Send revised vault drawings to GCD'));
    await _shot(tester, '02-today-task');
    c.selectTask(null);
    c.go(NavView.matrix);
    await _shot(tester, '03-matrix');
    c.go(NavView.board);
    await _shot(tester, '04-board');
    c.go(NavView.notes);
    await tester.pump();
    await tester.tap(find.text('HCL review call'));
    await _shot(tester, '05-note');
    c.selectNote(null);
    c.go(NavView.calendar);
    await _shot(tester, '06-calendar');
    c.prefs.themeMode = ThemeMode.dark;
    await tester.runAsync(c.savePrefs);
    c.go(NavView.matrix);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, '07-matrix-dark');
    c.dispose();
  }, skip: _out == null);
}
