// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-reading/ganj_reading/tokens.py.

import 'lexicon_data.dart';
import 'pystr.dart';

/// The token contract: one character per token, fixed for the life of the voice.
///
/// GE2PE writes š as '$', which collides with the voice's EOS, so its output is remapped (remapGe2pe).
/// Style tokens are private-use code points so the character frontend sees one token each.
const String tokVerse = '\uE000';
const String tokProse = '\uE001';
const String tokHemi = '\uE002';
const String tokBeyt = '\uE003';
const List<String> styleTokens = [tokVerse, tokProse, tokHemi, tokBeyt];
const String tokSh = 'š'; // š

/// First private-use code point of the metre tokens: one token per metre, appended after every older symbol.
const int metreBase = 0xE010;

/// One token per metre in [ganjMetres].
final List<String> metreTokens = [for (var i = 0; i < ganjMetres.length; i++) String.fromCharCode(metreBase + i)];

final Map<String, int> _metreIndex = {for (var i = 0; i < ganjMetres.length; i++) ganjMetres[i]: i};

/// The token for a poem's metre (the bracketed family name is ignored); '' for a metre not in the list.
String metreToken(String? metre) {
  final i = _metreIndex[pyStrip((metre ?? '').split('(')[0])];
  return i != null ? metreTokens[i] : '';
}

String remapGe2pe(String s) => s.replaceAll(r'$', tokSh);
