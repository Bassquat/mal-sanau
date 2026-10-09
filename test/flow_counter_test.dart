import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mal_sanau/flow_counter.dart';

/// A fixed random texture that can be sampled shifted in y.
class Texture {
  Texture() {
    final r = math.Random(1);
    for (var i = 0; i < 400 * 400; i++) {
      _v[i] = r.nextInt(256);
    }
  }
  final _v = List<int>.filled(400 * 400, 0);
  int at(int x, int y) => _v[(y.clamp(0, 399)) * 400 + x.clamp(0, 399)];
}

void main() {
  test('picture moving across the line is measured as area', () {
    final t = Texture();
    // Horizontal line at y=200, x 50..250 (200 px); normal points to +y.
    final f = FlowCounter(ax: 50, ay: 200, bx: 250, by: 200);
    for (var step = 0; step < 6; step++) {
      final shift = step * 5; // content moves +y by 5 px per frame
      f.update(400, 400, (x, y) => t.at(x, y - shift));
    }
    // 5 frame pairs x 5 px x 200 px of line.
    expect(f.areaIn, closeTo(5 * 5 * 200, 5 * 200 * 0.5));
    expect(f.areaOut, lessThan(500));
  });

  test('motion towards the other side counts as out', () {
    final t = Texture();
    final f = FlowCounter(ax: 50, ay: 200, bx: 250, by: 200);
    for (var step = 0; step < 4; step++) {
      f.update(400, 400, (x, y) => t.at(x, y + step * 4));
    }
    expect(f.areaOut, closeTo(3 * 4 * 200, 3 * 200 * 0.5));
    expect(f.areaIn, lessThan(500));
  });

  test('still picture counts nothing', () {
    final t = Texture();
    final f = FlowCounter(ax: 50, ay: 200, bx: 250, by: 200);
    for (var i = 0; i < 4; i++) {
      f.update(400, 400, t.at);
    }
    expect(f.areaIn + f.areaOut, 0);
  });

  test('count from area and the animal share of the frame', () {
    final f = FlowCounter(ax: 0, ay: 0, bx: 100, by: 0);
    f.areaIn = 2780 * 400.0;
    expect(f.countIn(57600, 2780 / 57600), 400);
  });
}
