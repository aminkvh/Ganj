import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/voice/app/steps_rule.dart';

void main() {
  group('stepCost', () {
    test('t(k) = t8 × (0.1 + 0.9 × k / 8)', () {
      expect(stepCost(t8: 1.82, steps: 8), closeTo(1.82, 1e-9));
      expect(stepCost(t8: 1.82, steps: 6), closeTo(1.82 * 0.775, 1e-9));
      expect(stepCost(t8: 1.82, steps: 4), closeTo(1.82 * 0.55, 1e-9));
    });

    test('matches the Pixel within 5%: 1.82 s at 8 steps predicts about 0.95–0.98 s at 4', () {
      // Measured at 4 steps: 1.02–1.06× real time, i.e. 0.94–0.98 s per audio second.
      final t4 = stepCost(t8: 1.82, steps: 4);
      expect(t4, inInclusiveRange(0.94 * 0.95, 0.98 * 1.05));
    });

    test('matches the laptop: 0.73 s at 8 steps, 0.54 at 6, 0.37 at 4 (within 6%)', () {
      expect(stepCost(t8: 0.73, steps: 6), closeTo(0.54, 0.54 * 0.06));
      expect(stepCost(t8: 0.73, steps: 4), closeTo(0.37, 0.37 * 0.10));
    });
  });

  group('t8From', () {
    test('normalizes a measurement to 8 steps', () {
      expect(t8From(secondsPerAudioSecond: 1.82, steps: 8), closeTo(1.82, 1e-9));
      expect(t8From(secondsPerAudioSecond: 1.001, steps: 4), closeTo(1.82, 1e-9));
      expect(t8From(secondsPerAudioSecond: 0.5, steps: 4), closeTo(0.5 / 0.55, 1e-9));
    });

    test('is the inverse of stepCost', () {
      for (final k in [4, 6, 8]) {
        expect(
          t8From(
            secondsPerAudioSecond: stepCost(t8: 0.9, steps: k),
            steps: k,
          ),
          closeTo(0.9, 1e-9),
        );
      }
    });
  });

  group('chooseSteps', () {
    // (t8, playbackRate, maxSteps) → steps. The target: speed(k) = 1 / t(k) ≥ 1.15 × playbackRate.
    final table = <(double?, double, int, int, String)>[
      (null, 1, 8, 4, 'first reading on a device: no measurement'),
      (null, 1.5, 8, 4, 'first reading at ×1.5'),
      (1.82, 1, 8, 4, 'Pixel fp32: 8 steps 0.55×, 6 steps 0.71×, 4 steps 1.0× — none reach 1.15, so 4'),
      (0.9, 1, 8, 6, 't8 0.9: 8 steps 1.11× (short), 6 steps 1.43×'),
      (0.9, 1.5, 8, 4, 't8 0.9 at ×1.5 needs 1.725×: 6 steps 1.43× (short), 4 steps 2.02×'),
      (0.73, 1, 8, 8, 'laptop: 8 steps 1.37×'),
      (0.73, 1.5, 8, 6, 'laptop at ×1.5: 8 steps 1.37× (short), 6 steps 1.77×'),
      (1.82, 1.5, 8, 4, 'Pixel at ×1.5: nothing qualifies, so 4'),
      (0.5, 1, 8, 8, 'a fast device'),
      (0.5, 1, 6, 6, 'never above phone.json\'s num_steps'),
      (0.5, 1, 7, 6, 'only 8, 6 or 4'),
      (0.5, 1, 4, 4, 'phone.json at 4'),
      (null, 1, 6, 4, 'no measurement, phone.json at 6'),
      (1.0, 1, 8, 6, 't8 1.0: 8 steps 1.0× (short), 6 steps 1.29×'),
      (5.0, 0.75, 8, 4, 'a very slow device, slowed playback: still 4'),
      (0.9, 0.75, 8, 8, 'slowed playback ×0.75 needs only 0.86×'),
    ];
    for (final (t8, rate, max, want, why) in table) {
      test('t8 $t8, rate $rate, max $max → $want ($why)', () {
        expect(chooseSteps(t8: t8, playbackRate: rate, maxSteps: max), want);
      });
    }

    test('a nonsense t8 (zero, negative, NaN) counts as no measurement', () {
      expect(chooseSteps(t8: 0, playbackRate: 1, maxSteps: 8), 4);
      expect(chooseSteps(t8: -1, playbackRate: 1, maxSteps: 8), 4);
      expect(chooseSteps(t8: double.nan, playbackRate: 1, maxSteps: 8), 4);
    });

    test('a phone.json below 4 steps is followed as it is', () {
      expect(chooseSteps(t8: 0.1, playbackRate: 1, maxSteps: 3), 3);
      expect(chooseSteps(t8: null, playbackRate: 1, maxSteps: 2), 2);
    });
  });
}
