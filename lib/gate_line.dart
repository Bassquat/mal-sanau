import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Gate line in normalized video coordinates (0..1), any angle.
/// The arrow drawn on the line points to the "in" side.
class GateLine {
  const GateLine(this.p1, this.p2, {this.invert = false});

  final Offset p1, p2;
  final bool invert;

  static const initial = GateLine(Offset(0.1, 0.5), Offset(0.9, 0.5));

  GateLine copyWith({Offset? p1, Offset? p2, bool? invert}) =>
      GateLine(p1 ?? this.p1, p2 ?? this.p2, invert: invert ?? this.invert);

  /// Endpoints in counting order. With the default order, moving to the side
  /// that [normal] points to (for a left-to-right line: downwards) is "in".
  /// [invert] swaps the endpoints, which flips in/out.
  (Offset, Offset) get ordered => invert ? (p2, p1) : (p1, p2);

  /// Unit vector pointing to the "in" side.
  Offset get normal {
    final (a, b) = ordered;
    final d = b - a;
    final len = math.sqrt(d.dx * d.dx + d.dy * d.dy);
    if (len == 0) return Offset.zero;
    return Offset(-d.dy / len, d.dx / len);
  }
}

/// Video overlay: draws the gate line with an arrow to the "in" side and two
/// draggable end handles.
class GateLineEditor extends StatelessWidget {
  const GateLineEditor({super.key, required this.line, required this.onChanged});

  final GateLine line;
  final ValueChanged<GateLine> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        int? active;
        Offset toN(Offset o) => Offset(
            (o.dx / size.width).clamp(0.0, 1.0),
            (o.dy / size.height).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final a = Offset(line.p1.dx * size.width, line.p1.dy * size.height);
            final b = Offset(line.p2.dx * size.width, line.p2.dy * size.height);
            final da = (d.localPosition - a).distance;
            final db = (d.localPosition - b).distance;
            active = da <= db ? 1 : 2;
          },
          onPanUpdate: (d) {
            final p = toN(d.localPosition);
            onChanged(active == 1 ? line.copyWith(p1: p) : line.copyWith(p2: p));
          },
          child: CustomPaint(size: size, painter: _LinePainter(line)),
        );
      });
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.line);
  final GateLine line;

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(Offset n) => Offset(n.dx * size.width, n.dy * size.height);
    final a = px(line.p1), b = px(line.p2);
    final paint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 3;
    canvas.drawLine(a, b, paint);

    // Arrow from the middle of the line towards the "in" side.
    final mid = (a + b) / 2;
    final n = line.normal;
    final tip = mid + n * 36;
    canvas.drawLine(mid, tip, paint);
    final left = Offset(-n.dy, n.dx), right = Offset(n.dy, -n.dx);
    canvas.drawLine(tip, tip - n * 10 + left * 7, paint);
    canvas.drawLine(tip, tip - n * 10 + right * 7, paint);

    final fill = Paint()..color = Colors.white;
    for (final p in [a, b]) {
      canvas.drawCircle(p, 11, fill);
      canvas.drawCircle(p, 11, paint..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.line != line;
}
