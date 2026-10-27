/// This device's own settings: look and feel, and where things are. Not
/// synced and not secret (no notes, keys or tokens live here).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;

import '../ui/theme.dart';

class Prefs {
  Prefs({
    this.themeMode = ThemeMode.system,
    this.accent = Accent.honey,
    this.density = Density.comfortable,
    this.font = FontChoice.inter,
    this.folderPath,
    this.hideInWidgets = false,
  });

  ThemeMode themeMode;
  Accent accent;
  Density density;
  FontChoice font;

  /// The markdown folder on this computer, if one is chosen.
  String? folderPath;
  bool hideInWidgets;

  Map<String, Object?> toJson() => {
    'theme': themeMode.name,
    'accent': accent.name,
    'density': density.name,
    'font': font.name,
    'folder': folderPath,
    'hide_in_widgets': hideInWidgets,
  };

  static Prefs fromJson(Map<String, dynamic> j) => Prefs(
    themeMode: ThemeMode.values.firstWhere((m) => m.name == j['theme'], orElse: () => ThemeMode.system),
    accent: Accent.values.firstWhere((a) => a.name == j['accent'], orElse: () => Accent.honey),
    density: Density.values.firstWhere((d) => d.name == j['density'], orElse: () => Density.comfortable),
    font: FontChoice.values.firstWhere((f) => f.name == j['font'], orElse: () => FontChoice.inter),
    folderPath: j['folder'] as String?,
    hideInWidgets: (j['hide_in_widgets'] as bool?) ?? false,
  );

  static Future<Prefs> load(Directory dir) async {
    final f = File('${dir.path}/prefs.json');
    if (!f.existsSync()) return Prefs();
    try {
      return Prefs.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return Prefs();
    }
  }

  Future<void> save(Directory dir) async {
    await dir.create(recursive: true);
    await File('${dir.path}/prefs.json').writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
  }
}
