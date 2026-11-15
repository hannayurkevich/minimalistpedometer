import 'package:flutter_test/flutter_test.dart';
import 'package:minipedometer/src/ui/swipe_pager.dart';

void main() {
  const w = 393.0;
  int target(double start, double current, {double velocity = 0}) =>
      swipeTarget(
        start: start,
        current: current,
        velocity: velocity,
        width: w,
        pageCount: 2,
      );

  test('a short drag (≥ 7 % of the width) commits', () {
    expect(target(0, 0.08), 1);
    expect(target(1, 0.92), 0);
  });

  test('a tiny drag springs back', () {
    expect(target(0, 0.04), 0);
    expect(target(1, 0.97), 1);
  });

  test('a quick flick commits however short', () {
    expect(target(0, 0.02, velocity: 1.0), 1); // 393 px/s
    expect(target(1, 0.99, velocity: -1.0), 0);
  });

  test('a flick against the drag wins (change of mind)', () {
    expect(target(0, 0.3, velocity: -1.0), 0);
  });

  test('never goes past the first or last page', () {
    expect(target(0, 0, velocity: -5), 0);
    expect(target(1, 1, velocity: 5), 1);
  });

  test('grabbing mid-settle continues sensibly', () {
    expect(target(0.6, 0.7), 1); // pushed on towards page 2
    expect(target(0.6, 0.5), 0); // pulled back
    expect(target(0.6, 0.62), 1); // just let go: nearest
  });
}
