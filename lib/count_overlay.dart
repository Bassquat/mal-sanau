import 'package:flutter/material.dart';

import 'analyzer.dart';

/// Tracked animals and freshly counted ones drawn over the playing video.
/// Counted animals get a badge with their running number for a moment.
class CountOverlay extends StatelessWidget {
  const CountOverlay({
    super.key,
    required this.frames,
    required this.events,
    required this.positionMs,
  });

  final List<FrameInfo> frames;
  final List<CountEvent> events;
  final int positionMs;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _OverlayPainter(frames, events, positionMs),
        ),
      );
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.frames, this.events, this.pos);
  final List<FrameInfo> frames;
  final List<CountEvent> events;
  final int pos;

  static const _showMs = 1500;

  @override
  void paint(Canvas canvas, Size size) {
    FrameInfo? cur;
    for (var i = frames.length - 1; i >= 0; i--) {
      if (frames[i].timeMs <= pos) {
        cur = frames[i];
        break;
      }
    }
    if (cur != null && pos - cur.timeMs < 600) {
      final dot = Paint()..color = Colors.white70;
      for (final t in cur.tracks) {
        canvas.drawCircle(Offset(t.x * size.width, t.y * size.height), 4, dot);
      }
    }
    for (final e in events) {
      final age = pos - e.timeMs;
      if (age < 0 || age > _showMs) continue;
      final color = e.dir > 0 ? Colors.green : Colors.red;
      final c = Offset(e.x * size.width, e.y * size.height);
      canvas.drawCircle(c, 13, Paint()..color = color.withValues(alpha: 0.9));
      final tp = TextPainter(
        text: TextSpan(
          text: '${e.seq}',
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}

/// Counts drawn as tally marks: four strokes crossed by a fifth. Shows the
/// last [maxGroups] groups and "…" when older ones were left out.
class TallyMarks extends StatelessWidget {
  const TallyMarks({super.key, required this.count, required this.color, this.maxGroups = 8});
  final int count;
  final Color color;
  final int maxGroups;

  @override
  Widget build(BuildContext context) {
    final groups = (count + 4) ~/ 5;
    final shown = groups < maxGroups ? groups : maxGroups;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (groups > shown) Text('…', style: TextStyle(color: color)),
        for (var g = groups - shown; g < groups; g++)
          CustomPaint(
            size: const Size(26, 22),
            painter: _TallyPainter(
                (count - g * 5) >= 5 ? 5 : count - g * 5, color),
          ),
      ],
    );
  }
}

class _TallyPainter extends CustomPainter {
  _TallyPainter(this.n, this.color);
  final int n;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final strokes = n > 4 ? 4 : n;
    for (var i = 0; i < strokes; i++) {
      final x = 3.0 + i * 5;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), p);
    }
    if (n >= 5) {
      canvas.drawLine(Offset(0, size.height - 4), Offset(size.width - 4, 4), p);
    }
  }

  @override
  bool shouldRepaint(_TallyPainter old) => old.n != n || old.color != color;
}
