/// Comb's design tokens: the colours, type and spacing from the approved
/// screens. Every widget reads these, so a theme change reaches everything.
library;

import 'package:flutter/material.dart';

enum Accent { honey, blue, teal, violet, graphite }

enum Density { comfortable, compact }

enum FontChoice { inter, system }

extension AccentLabel on Accent {
  String get label => switch (this) {
    Accent.honey => 'Honey',
    Accent.blue => 'Blue',
    Accent.teal => 'Teal',
    Accent.violet => 'Violet',
    Accent.graphite => 'Graphite',
  };
}

class _AccentSet {
  const _AccentSet(this.light, this.lightTint, this.dark, this.darkTint);
  final Color light, lightTint, dark, darkTint;
}

const _accents = {
  Accent.honey: _AccentSet(Color(0xFF8A5200), Color(0xFFFFF1D9), Color(0xFFF5C46B), Color(0xFF3A2C12)),
  Accent.blue: _AccentSet(Color(0xFF2563EB), Color(0xFFEEF3FE), Color(0xFF7AA7FF), Color(0xFF17233D)),
  Accent.teal: _AccentSet(Color(0xFF0F766E), Color(0xFFE6F4F2), Color(0xFF5EC4B6), Color(0xFF10302C)),
  Accent.violet: _AccentSet(Color(0xFF7C3AED), Color(0xFFF3EEFE), Color(0xFFB79CFF), Color(0xFF2A2140)),
  Accent.graphite: _AccentSet(Color(0xFF3F3F46), Color(0xFFF0F0F1), Color(0xFFD4D4D8), Color(0xFF2A2A2E)),
};

/// Space colours by name; each has a light and a dark shade.
const spacePalette = <String, (Color, Color)>{
  'green': (Color(0xFF2F855A), Color(0xFF5CC98D)),
  'blue': (Color(0xFF2563EB), Color(0xFF7AA7FF)),
  'violet': (Color(0xFF7C3AED), Color(0xFFB79CFF)),
  'teal': (Color(0xFF0F766E), Color(0xFF5EC4B6)),
  'orange': (Color(0xFFC2410C), Color(0xFFFB923C)),
  'pink': (Color(0xFFBE185D), Color(0xFFF472B6)),
  'graphite': (Color(0xFF52525B), Color(0xFFA1A1AA)),
};

@immutable
class CombTokens extends ThemeExtension<CombTokens> {
  const CombTokens({
    required this.dark,
    required this.bg,
    required this.side,
    required this.line,
    required this.ink,
    required this.sub,
    required this.faint,
    required this.select,
    required this.accent,
    required this.accentTint,
    required this.urgentBg,
    required this.urgentInk,
    required this.density,
    required this.fontFamily,
  });

  factory CombTokens.of({required bool dark, required Accent accent, required Density density, required FontChoice font}) {
    final a = _accents[accent]!;
    return dark
        ? CombTokens(
            dark: true,
            bg: const Color(0xFF141416),
            side: const Color(0xFF1B1B1E),
            line: const Color(0xFF2A2A2E),
            ink: const Color(0xFFF2F2F0),
            sub: const Color(0xFFA6A6A0),
            faint: const Color(0xFF7E7E78),
            select: const Color(0xFF26221A),
            accent: a.dark,
            accentTint: a.darkTint,
            urgentBg: const Color(0xFF3A1814),
            urgentInk: const Color(0xFFFF9B8C),
            density: density,
            fontFamily: font == FontChoice.inter ? 'Inter' : null,
          )
        : CombTokens(
            dark: false,
            bg: const Color(0xFFFFFFFF),
            side: const Color(0xFFF6F6F4),
            line: const Color(0xFFE6E6E2),
            ink: const Color(0xFF18181A),
            sub: const Color(0xFF5F5F5A),
            faint: const Color(0xFF9A9A94),
            select: const Color(0xFFFFF6E6),
            accent: a.light,
            accentTint: a.lightTint,
            urgentBg: const Color(0xFFFDEDEA),
            urgentInk: const Color(0xFFA3271A),
            density: density,
            fontFamily: font == FontChoice.inter ? 'Inter' : null,
          );
  }

  final bool dark;
  final Color bg, side, line, ink, sub, faint, select, accent, accentTint, urgentBg, urgentInk;
  final Density density;
  final String? fontFamily;

  double get rowPad => density == Density.compact ? 7 : 12;
  double get gap => density == Density.compact ? 6 : 10;

  Color space(String? name) {
    final pair = spacePalette[name] ?? spacePalette['graphite']!;
    return dark ? pair.$2 : pair.$1;
  }

  /// Text in Comb's type scale. Inter is a variable font, so the weight is
  /// set on its axis as well.
  TextStyle text(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height}) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    fontWeight: weight,
    fontVariations: fontFamily == null ? null : [FontVariation('wght', weight.value.toDouble())],
    color: color ?? ink,
    height: height ?? 1.45,
    letterSpacing: size >= 22 ? -0.4 : (size >= 16 ? -0.15 : 0),
  );

  TextStyle get title => text(26, weight: FontWeight.w600, height: 1.2);
  TextStyle get heading => text(18, weight: FontWeight.w600, height: 1.3);
  TextStyle get body => text(14);
  TextStyle get bodyStrong => text(14, weight: FontWeight.w500);
  TextStyle get small => text(12, color: sub);
  TextStyle get label => text(12, weight: FontWeight.w500, color: sub);

  @override
  CombTokens copyWith() => this;

  @override
  CombTokens lerp(ThemeExtension<CombTokens>? other, double t) => (other is CombTokens && t > 0.5) ? other : this;
}

extension CombContext on BuildContext {
  CombTokens get comb => Theme.of(this).extension<CombTokens>()!;
}

ThemeData buildTheme(CombTokens t) {
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: t.dark ? Brightness.dark : Brightness.light,
  ).copyWith(primary: t.accent, surface: t.bg, onSurface: t.ink, outline: t.line);
  final base = t.dark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    textTheme: base.textTheme.apply(fontFamily: t.fontFamily, bodyColor: t.ink, displayColor: t.ink),
    extensions: [t],
    splashFactory: NoSplash.splashFactory,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: t.side,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: t.text(14, color: t.faint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: t.accent, width: 1.5),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      side: BorderSide(color: t.faint, width: 1.5),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: t.text(12, color: t.bg),
      decoration: BoxDecoration(color: t.ink, borderRadius: BorderRadius.circular(6)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.bg,
      textStyle: t.body,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: t.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: t.text(14, color: t.bg),
      behavior: SnackBarBehavior.floating,
    ),
    scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStatePropertyAll(t.faint.withValues(alpha: 0.5))),
  );
}
