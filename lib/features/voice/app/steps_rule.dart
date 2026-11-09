/// How many flow steps a device reads with: 8, 6 or 4, never above phone.json's `num_steps`. Fewer steps read
/// faster, so a slower device can still start playing early without waiting between beyts.
library;

/// The step counts a device may use, most first.
const kVoiceSteps = [8, 6, 4];

/// The reading must be this much faster than playback for a step count to be chosen.
const kStepsSpeedMargin = 1.15;

/// The predicted wall seconds per audio second at [steps], from [t8], the measured time at 8 steps:
/// `t(k) = t8 × (0.1 + 0.9 × k / 8)` (a fixed part, then a part that grows with the steps). On the Pixel 10 Pro
/// (fp32) 1.82 s at 8 steps predicts 1.00 s at 4, against 0.94–0.98 measured.
double stepCost({required double t8, required int steps}) => t8 * (0.1 + 0.9 * steps / 8);

/// A measured [secondsPerAudioSecond] at [steps], normalized to 8 steps (the inverse of [stepCost]).
double t8From({required double secondsPerAudioSecond, required int steps}) =>
    secondsPerAudioSecond / (0.1 + 0.9 * steps / 8);

/// The largest allowed step count whose predicted speed (`1 / t(k)`, audio seconds per wall second) is at least
/// [kStepsSpeedMargin] × [playbackRate]; 4 when none qualifies or when [t8] is unknown (a device's first reading).
/// Only 8, 6 and 4 are used, and none above [maxSteps]; a [maxSteps] below 4 is used as it is.
int chooseSteps({double? t8, required double playbackRate, required int maxSteps}) {
  final allowed = [
    for (final k in kVoiceSteps)
      if (k <= maxSteps) k,
  ];
  if (allowed.isEmpty) return maxSteps < 1 ? 1 : maxSteps;
  final fewest = allowed.last;
  if (t8 == null || !t8.isFinite || t8 <= 0) return fewest;
  final rate = playbackRate > 0 ? playbackRate : 1.0;
  for (final k in allowed) {
    if (1 / stepCost(t8: t8, steps: k) >= kStepsSpeedMargin * rate) return k;
  }
  return fewest;
}
