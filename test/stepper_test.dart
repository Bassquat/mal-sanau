import 'package:flutter_test/flutter_test.dart';
import 'package:mal_sanau/stepper.dart';

void main() {
  test('hold step speeds up and never shrinks', () {
    var prev = 0;
    for (var t = 1; t < 80; t++) {
      final s = stepForTick(t);
      expect(s, greaterThanOrEqualTo(prev));
      prev = s;
    }
    expect(stepForTick(1), 1);
    expect(stepForTick(100), 100);
  });
}
