import 'package:flutter_test/flutter_test.dart';
import 'package:mal_sanau/gate_counter.dart';

GateCounter gate() => GateCounter(ax: 0, ay: 100, bx: 100, by: 100);

void run(GateCounter g, Map<int, List<(double, double)>> paths) {
  final n = paths.values.map((p) => p.length).reduce((a, b) => a > b ? a : b);
  for (var i = 0; i < n; i++) {
    g.update({
      for (final e in paths.entries)
        if (i < e.value.length) e.key: e.value[i],
    });
  }
}

void main() {
  test('update reports the crossings it counted', () {
    final g = gate();
    expect(g.update({1: (50, 80)}), isEmpty);
    expect(g.update({1: (50, 120)}), [(1, 1)]);
    expect(g.update({1: (50, 130)}), isEmpty);
    expect(g.update({1: (50, 80)}), [(1, -1)]);
  });

  test('in and out', () {
    final g = gate();
    run(g, {
      1: [(50, 80), (50, 95), (50, 120)],
      2: [(60, 130), (60, 105), (60, 80)],
    });
    expect((g.nIn, g.nOut, g.balance), (1, 1, 0));
  });

  test('leave and return keeps net balance', () {
    final g = gate();
    run(g, {1: [(50, 130), (50, 80), (50, 130)]});
    expect((g.nIn, g.nOut, g.balance), (1, 1, 0));
  });

  test('jitter on the line is not counted', () {
    final g = gate();
    run(g, {1: [(50, 80), (50, 98), (50, 102), (50, 99), (50, 101), (50, 85)]});
    expect((g.nIn, g.nOut), (0, 0));
  });

  test('group of five', () {
    final g = gate();
    run(g, {
      for (var i = 0; i < 5; i++)
        i: [(10.0 * i, 70), (10.0 * i, 95), (10.0 * i, 125)],
    });
    expect((g.nIn, g.balance), (5, 5));
  });

  test('vertical line counts left-right crossings', () {
    // a=(100,0) -> b=(100,100): side +1 is the left (x < 100).
    final g = GateCounter(ax: 100, ay: 0, bx: 100, by: 100);
    run(g, {
      1: [(130, 50), (110, 50), (80, 50)],
      2: [(70, 20), (90, 20), (120, 20)],
    });
    expect((g.nIn, g.nOut), (1, 1));
  });

  test('diagonal line counts both directions', () {
    // a=(0,0) -> b=(100,100); side +1 is below/left of the diagonal.
    final g = GateCounter(ax: 0, ay: 0, bx: 100, by: 100);
    run(g, {
      1: [(80, 40), (60, 60.0 + 10), (40, 90)],
      2: [(30, 90), (50, 60), (90, 30)],
    });
    expect((g.nIn, g.nOut, g.balance), (1, 1, 0));
  });

  test('diagonal jitter on the line is not counted', () {
    final g = GateCounter(ax: 0, ay: 0, bx: 100, by: 100);
    run(g, {1: [(70, 40), (50, 49), (50, 51), (51, 50), (70, 40)]});
    expect((g.nIn, g.nOut), (0, 0));
  });

  test('swapping endpoints swaps in and out', () {
    final g = GateCounter(ax: 100, ay: 100, bx: 0, by: 100);
    run(g, {1: [(50, 80), (50, 95), (50, 120)]});
    expect((g.nIn, g.nOut), (0, 1));
  });

  test('crossing beyond the segment end is ignored when limited', () {
    final free = GateCounter(ax: 0, ay: 100, bx: 100, by: 100);
    final limited = GateCounter(
        ax: 0, ay: 100, bx: 100, by: 100, limitToSegment: true);
    for (final g in [free, limited]) {
      run(g, {1: [(300, 80), (300, 120)], 2: [(50, 80), (50, 120)]});
    }
    expect(free.nIn, 2);
    expect(limited.nIn, 1);
  });

  test('fast crossing that lands outside the segment span still counts', () {
    // Gate is the short segment x 40..60; the animal crosses at x=50 and
    // lands at x=150 within one step.
    final g = GateCounter(
        ax: 40, ay: 100, bx: 60, by: 100, limitToSegment: true);
    run(g, {1: [(45, 70), (55, 140)]});
    expect(g.nIn, 1);
  });
}
