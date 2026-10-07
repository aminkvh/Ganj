import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/ui/smooth_wheel.dart';

void main() {
  const frame = Duration(microseconds: 16667);

  List<double> run(WheelSmoother s, {int frames = 60}) => [for (var i = 0; i < frames && s.active; i++) s.step(frame)];

  test('one wheel notch is spread over several frames, easing out, and adds up exactly', () {
    final s = WheelSmoother()..add(100);
    final steps = run(s);
    expect(steps.length, inInclusiveRange(4, 20));
    expect(steps.first, lessThan(100));
    expect(steps.first, greaterThan(steps[1])); // eases out
    expect(steps.fold<double>(0, (a, b) => a + b), closeTo(100, 1e-9));
    expect(s.active, isFalse);
  });

  test('notches that arrive while scrolling add up instead of restarting', () {
    final s = WheelSmoother()..add(100);
    final first = s.step(frame);
    s.add(100);
    final rest = run(s);
    expect(first + rest.fold<double>(0, (a, b) => a + b), closeTo(200, 1e-9));
  });

  test('turning the wheel back cancels what is left', () {
    final s = WheelSmoother()..add(100);
    s.step(frame);
    s.add(-50);
    final total = run(s).fold<double>(0, (a, b) => a + b);
    expect(total, closeTo(-50, 1e-9));
  });

  test('settles within a quarter second', () {
    final s = WheelSmoother()..add(300);
    expect(run(s, frames: 15).length, lessThanOrEqualTo(15));
    expect(s.active, isFalse);
  });
}
