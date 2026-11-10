import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../post/clean.dart';
import '../post/pause_trim.dart';
import '../reading/reading.dart';
import 'g2p_onnx.dart';
import 'ort.dart';
import 'voice_settings.dart';

export 'voice_settings.dart';

/// The files of the downloaded voice, all in one folder.
class VoiceFiles {
  const VoiceFiles(this.dir);

  final String dir;

  /// The 8-bit encoder and decoder when the folder has them (text_encoder_int8.onnx, fm_decoder_int8.onnx), else the
  /// full ones; the download carries only the pair that ships.
  String get encoder => _either('text_encoder');
  String get decoder => _either('fm_decoder');

  String _either(String name) {
    final int8 = '$dir/${name}_int8.onnx';
    return File(int8).existsSync() ? int8 : '$dir/$name.onnx';
  }

  String get vocoder => '$dir/vocos_24khz_despike.onnx';
  String get tokens => '$dir/tokens.txt';

  /// The voice prompt at 24 kHz (resampled once by the voice side with torchaudio, as ZipVoice does).
  String get promptWav => '$dir/prompt.wav';

  /// Steps, guidance, the sherpa settings and the clean-up values (optional; defaults otherwise).
  String get phoneJson => '$dir/phone.json';
  String get promptPhonemes => '$dir/prompt_phonemes.txt';
  String get g2pEncoder => '$dir/g2p_encoder.onnx';
  String get g2pDecoder => '$dir/g2p_decoder.onnx';

  List<String> get all => [encoder, decoder, vocoder, tokens, promptWav, promptPhonemes, g2pEncoder, g2pDecoder];

  bool get complete => all.every((p) => File(p).existsSync());
}

/// One beyt (or prose sentence) read aloud: 24 kHz mono samples and the phonemes the voice read.
class VoiceLine {
  const VoiceLine(this.samples, this.sampleRate, this.target, {this.onsetsMs = const []});

  final Float32List samples;
  final int sampleRate;
  final String target;

  /// Where each hemistich after the first starts in [samples], in ms (see [hemistichOnsetsMs]); empty when the
  /// line is one hemistich or its breaks were not found.
  final List<int> onsetsMs;

  Duration get duration => Duration(microseconds: samples.length * 1000000 ~/ sampleRate);
}

/// Reads Persian verse with the Ganj voice, entirely on the device: the reading rules and the letters-to-phonemes
/// model make the phonemes, sherpa-onnx runs ZipVoice with the voice prompt (the vocoder file has the mel despike
/// built in), and the high-pass and de-ess clean the result.
///
/// Synchronous and slow (seconds per beyt): run it on a background isolate. Call `sherpa.initBindings()` in that
/// isolate first.
class VoiceEngine {
  VoiceEngine._(this._tts, this._g2pModel, this._g2p, this._ort, this._prompt, this._promptTokens, this.settings);

  /// The voice's phone.json (or the defaults when the folder has none).
  final VoiceSettings settings;

  final sherpa.OfflineTts _tts;
  final OnnxG2pModel _g2pModel;
  final G2P _g2p;
  final Ort _ort;
  final sherpa.WaveData _prompt;
  final List<String> _promptTokens;

  static VoiceEngine load(VoiceFiles f, {int threads = 4, String? onnxruntimePath}) {
    final st = VoiceSettings.load(f.phoneJson);
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          zipvoice: sherpa.OfflineTtsZipVoiceModelConfig(
            tokens: f.tokens,
            encoder: f.encoder,
            decoder: f.decoder,
            vocoder: f.vocoder,
            featScale: st.featScale,
            tShift: st.tShift,
            targetRms: st.targetRms,
            guidanceScale: st.guidanceScale,
          ),
          numThreads: threads,
        ),
      ),
    );
    final ort = Ort.open(onnxruntimePath);
    final model = OnnxG2pModel(ort, File(f.g2pEncoder).readAsBytesSync(), File(f.g2pDecoder).readAsBytesSync());
    final prompt = sherpa.readWave(f.promptWav);
    final promptPh = File(f.promptPhonemes).readAsStringSync().replaceAll('\n', '');
    return VoiceEngine._(tts, model, G2P(model), ort, prompt, _chars(promptPh), st);
  }

  /// The phonemes the voice reads for [lines] (a beyt's two hemistichs, or one prose sentence).
  String target(List<String> lines, {String kind = 'verse', String? metre}) =>
      readingTarget(_g2p, lines, kind: kind, metre: metre);

  /// Reads [lines] aloud; [steps] overrides phone.json's flow-matching steps (more is slower and cleaner).
  VoiceLine read(List<String> lines, {String kind = 'verse', String? metre, int? steps}) {
    final t = target(lines, kind: kind, metre: metre);
    final audio = _tts.generateWithConfig(
      text: '',
      config: sherpa.OfflineTtsGenerationConfig(
        speed: settings.speed,
        // sherpa's default 0.2 shortens every pause over 0.2 s to a fifth; the voice side uses 1.0.
        silenceScale: settings.silenceScale,
        referenceAudio: _prompt.samples,
        referenceSampleRate: _prompt.sampleRate,
        referenceText: _promptTokens.join(),
        numSteps: steps ?? settings.numSteps,
        // sherpa splits a token list at , . ! ? ; : and reads the pieces apart; the voice writes ژ as ";". One
        // beyt is one utterance, so the pieces are always merged back.
        extra: {'min_words_in_sentence': settings.minWordsInSentence},
        tokens: [_promptTokens, _chars(t)],
      ),
    );
    if (audio.samples.isEmpty) throw StateError('the voice produced no audio for "$t"');
    final hemistichs = lines.where((l) => l.trim().isNotEmpty).length;
    final out = finish(audio.samples, audio.sampleRate, hemistichs: hemistichs);
    return VoiceLine(
      out,
      audio.sampleRate,
      t,
      // Found again in the trimmed audio, so the times are those the listener hears.
      onsetsMs: hemistichOnsetsMs(out, audio.sampleRate, hemistichs: hemistichs, capS: settings.pauseCapS),
    );
  }

  /// After sherpa, in the voice's order (voice/phonepost.py): gain, clamp, 70 Hz high-pass, 6 dB de-ess, inner stops
  /// cut to 0.30 s with the hemistich breaks kept, clamp.
  Float32List finish(Float32List raw, int sr, {required int hemistichs}) => finishLine(
    raw,
    sr,
    gain: settings.gain,
    nBreaks: math.max(hemistichs - 1, 0),
    highpassHz: settings.highpassHz,
    deessDb: settings.deessDb,
    pauseCapS: settings.pauseCapS,
  );

  static List<String> _chars(String s) => [for (final r in s.runes) String.fromCharCode(r)];

  void dispose() {
    _tts.free();
    _g2pModel.dispose();
    _ort.dispose();
  }
}
