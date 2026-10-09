import 'dart:math' as math;
import 'dart:typed_data';

/// Counts a dense stream of animals that cannot be told apart one by one
/// (a crowd of sheep) by measuring how much picture moves across the gate
/// line. Around the line a thin strip is sampled; for several pieces of the
/// strip the shift of the picture along the line's normal between two frames
/// is found by block matching. Shift x piece length is the area that crossed;
/// the animal count is that area divided by the area one animal covers.
class FlowCounter {
  FlowCounter({
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    this.segments = 6,
    this.window = 12,
    this.maxShift = 24,
  }) {
    final dx = bx - ax, dy = by - ay;
    _len = math.sqrt(dx * dx + dy * dy);
    ux = dx / _len;
    uy = dy / _len;
    // Same normal as GateLine: points to the "in" side.
    nx = -dy / _len;
    ny = dx / _len;
    _cols = _len.floor();
    _rows = 2 * (window + maxShift) + 1;
    _prev = Uint8List(_cols * _rows);
    _cur = Uint8List(_cols * _rows);
  }

  final double ax, ay, bx, by;
  final int segments, window, maxShift;
  late final double ux, uy, nx, ny;
  late final double _len;
  late final int _cols, _rows;
  late Uint8List _prev, _cur;
  bool _hasPrev = false;

  /// Picture area (px^2) that moved to the "in" / "out" side so far.
  double areaIn = 0, areaOut = 0;

  /// [gray] returns brightness 0..255 at pixel (x, y) of a [w] x [h] frame.
  void update(int w, int h, int Function(int x, int y) gray) {
    if (_cols < segments * 4) return;
    final half = window + maxShift;
    for (var r = 0; r < _rows; r++) {
      final c = (r - half).toDouble();
      for (var l = 0; l < _cols; l++) {
        final x = (ax + ux * l + nx * c).round().clamp(0, w - 1);
        final y = (ay + uy * l + ny * c).round().clamp(0, h - 1);
        _cur[r * _cols + l] = gray(x, y);
      }
    }
    if (_hasPrev) {
      final segLen = _cols / segments;
      for (var k = 0; k < segments; k++) {
        final x0 = (k * segLen).floor(), x1 = ((k + 1) * segLen).floor();
        var bestSad = 1 << 30, best = 0;
        // Ordered by distance from 0 so ties (flat ground) mean "no motion".
        for (var i = 0; i <= 2 * maxShift; i++) {
          final s = (i.isOdd ? 1 : -1) * ((i + 1) ~/ 2);
          if (s.abs() > maxShift) continue;
          var sad = 0;
          for (var r = -window; r <= window; r++) {
            final pr = (half + r) * _cols, cr = (half + r + s) * _cols;
            for (var l = x0; l < x1; l++) {
              final d = _prev[pr + l] - _cur[cr + l];
              sad += d < 0 ? -d : d;
            }
          }
          if (sad < bestSad) {
            bestSad = sad;
            best = s;
          }
        }
        // The content that was at the line moved by `best` along the normal.
        if (best > 0) {
          areaIn += best * (x1 - x0);
        } else if (best < 0) {
          areaOut += -best * (x1 - x0);
        }
      }
    }
    final t = _prev;
    _prev = _cur;
    _cur = t;
    _hasPrev = true;
  }

  /// Animals counted so far, given the share of the frame one animal covers.
  int countIn(double frameArea, double animalShare) =>
      (areaIn / (frameArea * animalShare)).round();
  int countOut(double frameArea, double animalShare) =>
      (areaOut / (frameArea * animalShare)).round();
}
