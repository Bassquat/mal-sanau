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
}
