// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), the beyt pipeline of ganj_reading/ganj_corpus/ganj_voice.

import 'g2p.dart';
import 'glue.dart';
import 'pauses.dart';

export 'g2p.dart' show G2P, G2pModel, PhonemizeError;

/// The text the voice model reads for a beyt (or a prose passage).
///
/// [kind] is 'verse' or 'prose'; [metre] is the Ganjoor rhythm string (verse only, may be null). Throws
/// [PhonemizeError] when a line has no words or the model gives nothing usable.
String readingTarget(G2P g2p, List<String> lines, {required String kind, String? metre}) {
  final label = g2p.phonemizeUnit(lines, kind, metre);
  final reading = readingLabel(label, lines, prose: kind == 'prose', pauses: true, va: false);
  return leadPause(glueVav(reading));
}
