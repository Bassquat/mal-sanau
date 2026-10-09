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
  final Map<int, (double, double)> _lastOnSide = {};

  int get balance => nIn - nOut;

  double _signedDist(double x, double y) {
    final dx = bx - ax;
    final dy = by - ay;
    final length = math.sqrt(dx * dx + dy * dy);
    return (dx * (y - ay) - dy * (x - ax)) / length;
  }

  /// Does the step from [p] to [q] cross the line inside the a-b segment
  /// (10% tolerance at each end)? The crossing point itself is tested, not the
  /// landing point, so a fast animal that ends up far from the line still
  /// counts if it crossed within the gate.
  bool _crossesSegment((double, double) p, (double, double) q) {
    final dp = _signedDist(p.$1, p.$2), dq = _signedDist(q.$1, q.$2);
    final k = dp / (dp - dq);
    final x = p.$1 + (q.$1 - p.$1) * k, y = p.$2 + (q.$2 - p.$2) * k;
    final dx = bx - ax, dy = by - ay;
    final t = ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy);
    return t >= -0.1 && t <= 1.1;
  }

  /// [tracks] maps track id -> (x, y) centroid for the current frame.
  /// Returns the crossings counted in this frame as (track id, +1 in / -1 out).
  List<(int, int)> update(Map<int, (double, double)> tracks) {
    final events = <(int, int)>[];
    tracks.forEach((id, p) {
      final d = _signedDist(p.$1, p.$2);
      if (d.abs() < margin) return;
      final side = d > 0 ? 1 : -1;
      final prev = _side[id];
      if (prev != null && prev != side) {
        final from = _lastOnSide[id];
        if (!limitToSegment || from == null || _crossesSegment(from, p)) {
          if (side > 0) {
            nIn++;
          } else {
            nOut++;
          }
          events.add((id, side));
        }
      }
      _side[id] = side;
      _lastOnSide[id] = p;
    });
    return events;
  }
}
