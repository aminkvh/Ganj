import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/app/start_rule.dart';

/// How many of [n] equal 1 s beyts must be made before the rule lets playback start.
int startsAfter(int n, {required double speed, double rate = 1}) {
  for (var made = 1; made <= n; made++) {
    if (shouldStart(totalEstS: n.toDouble(), madeS: made.toDouble(), firstBeytS: 1, speed: speed, playbackRate: rate)) {
      return made;
    }
  }
  return n + 1;
}

void main() {
  group('start rule uses playbackRate', () {
    test('speed 1.5, rate 1: starts after beyt 0', () {
      expect(startsAfter(7, speed: 1.5), 1);
    });

    test('speed 1.04, rate 1, 7 equal beyts: starts once about one beyt of margin is made', () {
      expect(startsAfter(7, speed: 1.04), 2);
    });

    test('speed 0.5: only near the end', () {
      expect(startsAfter(7, speed: 0.5), 5);
    });

    test('rate 1.5 starts later than rate 1', () {
      final at1 = startsAfter(7, speed: 1.04);
      final at15 = startsAfter(7, speed: 1.04, rate: 1.5);
      expect(at15, greaterThan(at1));
      expect(at15, 4);
    });

    test('a device too slow even for the last beyt never starts early', () {
      expect(startsAfter(7, speed: 0.1), 7); // only once everything is made
    });

    test('no speed known yet: never starts', () {
      expect(shouldStart(totalEstS: 7, madeS: 1, firstBeytS: 1, speed: 0, playbackRate: 1), isFalse);
    });
  });

  group('estimateTotal from chars', () {
    test('scales the measured seconds per character over the remaining beyts', () {
      // Beyts 0 and 1 made: 30 chars → 3 s, so 0.1 s a char; 40 + 10 chars remain → 5 s more.
      expect(estimateTotal([10, 20, 40, 10], {0: 1.0, 1: 2.0}), closeTo(8.0, 1e-9));
    });

    test('made beyts count as they are, whatever their place', () {
      expect(estimateTotal([10, 10, 10], {2: 1.5}), closeTo(4.5, 1e-9));
    });

    test('everything made: the sum', () {
      expect(estimateTotal([5, 7], {0: 0.5, 1: 0.9}), closeTo(1.4, 1e-9));
    });

    test('nothing made: zero', () {
      expect(estimateTotal([5, 7], {}), 0);
    });
  });
}
