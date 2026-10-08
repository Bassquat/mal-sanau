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
/// large draggable end handles. Pointer events are read raw and [onDragging]
/// tells the parent to freeze page scrolling, so dragging a handle never
/// scrolls the page instead.
class GateLineEditor extends StatefulWidget {
  const GateLineEditor({
    super.key,
    required this.line,
    required this.onChanged,
    required this.onDragging,
  });

  final GateLine line;
  final ValueChanged<GateLine> onChanged;
  final ValueChanged<bool> onDragging;

  @override
  State<GateLineEditor> createState() => _GateLineEditorState();
}

class _GateLineEditorState extends State<GateLineEditor> {
  static const _grab = 44.0; // touch radius around a handle, in pixels
  int? _active;
  Size _size = Size.zero;

  Offset _px(Offset n) => Offset(n.dx * _size.width, n.dy * _size.height);
  Offset _norm(Offset o) => Offset((o.dx / _size.width).clamp(0.0, 1.0),
      (o.dy / _size.height).clamp(0.0, 1.0));

  void _down(PointerDownEvent e) {
    final d1 = (e.localPosition - _px(widget.line.p1)).distance;
    final d2 = (e.localPosition - _px(widget.line.p2)).distance;
    if (d1 > _grab && d2 > _grab) return;
    _active = d1 < d2 ? 1 : 2;
    widget.onDragging(true);
  }

  void _move(PointerMoveEvent e) {
    final a = _active;
    if (a == null) return;
    final p = _norm(e.localPosition);
    widget.onChanged(
        a == 1 ? widget.line.copyWith(p1: p) : widget.line.copyWith(p2: p));
  }

  void _end(PointerEvent e) {
    if (_active == null) return;
    _active = null;
    widget.onDragging(false);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        _size = Size(c.maxWidth, c.maxHeight);
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _end,
          onPointerCancel: _end,
          child: CustomPaint(size: _size, painter: _LinePainter(widget.line)),
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
    final ring = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    var n1 = 1;
    for (final p in [a, b]) {
      canvas.drawCircle(p, 18, fill);
      canvas.drawCircle(p, 18, ring);
      final tp = TextPainter(
        text: TextSpan(
            text: '${n1++}',
            style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.line != line;
}
