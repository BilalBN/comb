import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The Comb mark: a hexagon with a filled cell, in the accent colour.
class CombMark extends StatelessWidget {
  const CombMark({super.key, this.size = 22});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Comb',
    child: CustomPaint(size: Size.square(size), painter: _HexPainter(context.comb.accent)),
  );
}

class _HexPainter extends CustomPainter {
  _HexPainter(this.color);
  final Color color;

  Path _hex(Size s, double inset) {
    final cx = s.width / 2, cy = s.height / 2;
    final r = (s.width / 2) - inset;
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = (60 * i - 90) * math.pi / 180;
      final x = cx + r * math.cos(a), y = cy + r * math.sin(a);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _hex(size, size.width * 0.08),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.085
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(_hex(size, size.width * 0.33), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.color != color;
}
