import 'dart:math' as math;

/// Direction-aware gate line counter with net balance.
///
/// Feed it tracked object centroids per frame. A track is counted once per
/// clear crossing of the line a->b; a dead band (margin) around the line
/// stops jitter from double counting. Side +1 is "in", side -1 is "out".
class GateCounter {
  GateCounter({
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    this.margin = 6.0,
    this.limitToSegment = false,
  });

  final double ax, ay, bx, by;
  final double margin;

  /// Count only crossings whose point projects onto the a-b segment
  /// (with a 10% tolerance at each end), so animals walking past the end of
  /// the drawn line are not counted.
  final bool limitToSegment;

  int nIn = 0;
  int nOut = 0;
  final Map<int, int> _side = {};

  int get balance => nIn - nOut;

  double _signedDist(double x, double y) {
    final dx = bx - ax;
    final dy = by - ay;
    final length = math.sqrt(dx * dx + dy * dy);
    return (dx * (y - ay) - dy * (x - ax)) / length;
  }

  bool _withinSegment(double x, double y) {
    final dx = bx - ax, dy = by - ay;
    final t = ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy);
    return t >= -0.1 && t <= 1.1;
  }

  /// [tracks] maps track id -> (x, y) centroid for the current frame.
  void update(Map<int, (double, double)> tracks) {
    tracks.forEach((id, p) {
      final d = _signedDist(p.$1, p.$2);
      if (d.abs() < margin) return;
      final side = d > 0 ? 1 : -1;
      final prev = _side[id];
      if (prev != null &&
          prev != side &&
          (!limitToSegment || _withinSegment(p.$1, p.$2))) {
        if (side > 0) {
          nIn++;
        } else {
          nOut++;
        }
      }
      _side[id] = side;
    });
  }
}
