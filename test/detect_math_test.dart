import 'package:flutter_test/flutter_test.dart';
import 'package:mal_sanau/detect_math.dart';

void main() {
  test('anchors match the reference implementation', () {
    final a = buildAnchors();
    expect(a.length ~/ 4, 19206);
    void check(int i, List<double> want) {
      for (var k = 0; k < 4; k++) {
        expect(a[i * 4 + k], closeTo(want[k], 1e-2), reason: 'anchor $i/$k');
      }
    }

    check(0, [4.0, 4.0, 32.0, 32.0]);
    check(1, [4.0, 4.0, 22.4, 44.8]);
    check(3, [4.0, 4.0, 40.3175, 40.3175]);
    check(9, [4.0, 12.0, 32.0, 32.0]);
    check(14399, [316.0, 316.0, 71.1156, 35.5578]);
    check(14400, [8.0, 8.0, 64.0, 64.0]);
    check(19205, [320.0, 320.0, 1137.8491, 568.9246]);
  });

  test('nms keeps the best of overlapping boxes', () {
    final kept = nms([
      Detection(50, 50, 40, 40, 0.9),
      Detection(52, 52, 40, 40, 0.8),
      Detection(200, 200, 40, 40, 0.7),
    ]);
    expect(kept.length, 2);
    expect(kept.first.score, 0.9);
  });

  test('tracker keeps ids for moving objects', () {
    final t = CentroidTracker();
    final f1 = t.update([Detection(50, 50, 40, 40, 0.9)]);
    final f2 = t.update([Detection(60, 55, 40, 40, 0.9)]);
    expect(f1.keys.single, f2.keys.single);
    final f3 = t.update([Detection(60, 55, 40, 40, 0.9), Detection(300, 300, 40, 40, 0.9)]);
    expect(f3.length, 2);
  });

  test('tracker keeps the id of an accelerating object', () {
    final t = CentroidTracker();
    final ids = <int>{};
    for (final x in <double>[50, 80, 120, 170]) {
      ids.addAll(t.update([Detection(x, 50, 40, 40, 0.9)]).keys);
    }
    expect(ids.length, 1);
  });
}
