import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app/controller.dart';
import 'security/app_lock.dart';
import 'ui/home/home_shell.dart';
import 'ui/lock_screen.dart';
import 'ui/setup/setup_flow.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/Comb');
  final lock = AppLock(
    dir: dir,
    cache: Platform.isMacOS || Platform.isWindows || Platform.isLinux ? FileSessionCache(dir) : SecureStorageCache(),
    biometrics: SystemBiometrics(),
  );
  final controller = AppController(appDir: dir, lock: lock);
  await controller.start();
  runApp(CombApp(controller: controller));
}

class CombApp extends StatefulWidget {
  const CombApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<CombApp> createState() => _CombAppState();
}

class _CombAppState extends State<CombApp> {
  late final AppLifecycleListener _life;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onHide: c.onBackground, onShow: c.onForeground);
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final p = c.prefs;
        CombTokens tokens(bool dark) => CombTokens.of(dark: dark, accent: p.accent, density: p.density, font: p.font);
        return MaterialApp(
          title: 'Comb',
          debugShowCheckedModeBanner: false,
          themeMode: p.themeMode,
          theme: buildTheme(tokens(false)),
          darkTheme: buildTheme(tokens(true)),
          home: switch (c.phase) {
            Phase.loading => const Scaffold(body: SizedBox.shrink()),
            Phase.setup => SetupFlow(controller: c),
            Phase.locked => LockScreen(controller: c),
            Phase.ready => HomeShell(controller: c),
          },
        );
      },
    );
  }
}
