import 'dart:convert';
import 'dart:io';

/// The voice's phone.json: the sherpa settings and the clean-up after it ("sherpa" and "after"). Values missing from
/// the file keep the defaults below, which are the voice side's settings as of 2026-11-08 (ganj-zip-distill).
class VoiceSettings {
  const VoiceSettings({
    this.numSteps = 8,
    this.guidanceScale = 2.0,
    this.tShift = 0.5,
    this.featScale = 0.1,
    this.targetRms = 0.1,
    this.speed = 1.004,
    this.silenceScale = 1.0,
    this.minWordsInSentence = 1000000,
    this.gain = 0.6482, // the final prompt's (ganj-zip-distill)
    this.clamp = 1.0,
    this.highpassHz = 70,
    this.highpassOrder = 8,
    this.deessDb = 6,
    this.pauseCapS = 0.30,
  });

  final int numSteps;
  final double guidanceScale;
  final double tShift;
  final double featScale;
  final double targetRms;
  final double speed;
  final double silenceScale;
  final int minWordsInSentence;

  final double gain;
  final double clamp;
  final double highpassHz;
  final int highpassOrder;
  final double deessDb;
  final double pauseCapS;

  static VoiceSettings load(String path) {
    final f = File(path);
    return f.existsSync() ? fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>) : const VoiceSettings();
  }

  static VoiceSettings fromJson(Map<String, dynamic> j) {
    const d = VoiceSettings();
    final s = (j['sherpa'] as Map?)?.cast<String, dynamic>() ?? const {};
    final a = (j['after'] as Map?)?.cast<String, dynamic>() ?? const {};
    double num_(Map<String, dynamic> m, List<String> keys, double def) {
      for (final k in keys) {
        final v = m[k];
        if (v is num) return v.toDouble();
        if (v is String && double.tryParse(v) != null) return double.parse(v);
      }
      return def;
    }

    final extra = (s['extra'] as Map?)?.cast<String, dynamic>() ?? const {};
    return VoiceSettings(
      numSteps: num_(s, ['num_steps', 'steps'], d.numSteps.toDouble()).round(),
      guidanceScale: num_(s, ['guidance_scale', 'guidance'], d.guidanceScale),
      tShift: num_(s, ['t_shift'], d.tShift),
      featScale: num_(s, ['feat_scale'], d.featScale),
      targetRms: num_(s, ['target_rms'], d.targetRms),
      speed: num_(s, ['speed'], d.speed),
      silenceScale: num_(s, ['silence_scale'], d.silenceScale),
      minWordsInSentence: num_({...extra, ...s}, ['min_words_in_sentence'], d.minWordsInSentence.toDouble()).round(),
      gain: num_(a, ['gain'], d.gain),
      clamp: num_(a, ['clamp'], d.clamp),
      highpassHz: num_(a, ['highpass_hz'], d.highpassHz),
      highpassOrder: num_(a, ['highpass_order'], d.highpassOrder.toDouble()).round(),
      deessDb: num_(a, ['deess_db'], d.deessDb),
      pauseCapS: num_(a, ['pause_cap_s'], d.pauseCapS),
    );
  }
}
