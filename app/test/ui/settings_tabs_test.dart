import 'dart:io';

import 'package:comb/ui/home/home_shell.dart';
import 'package:comb/ui/settings/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'screens_test.dart' show offlineApp, pumpApp;

void main() {
  for (final tab in SettingsTab.values) {
    testWidgets('settings tab $tab', (tester) async {
      final dir = Directory.systemTemp.createTempSync('comb-ui-');
      final c = await offlineApp(tester, dir);
      await pumpApp(tester, c);
      showSettings(tester.element(find.byType(HomeShell)), c, tab: tab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      c.dispose();
    });
  }
}
