// Ported from Ganj voice (github.com/aminkvh/Ganj_voice, same author), packages/ganj-voice/ganj_voice/glue.py.

import 'tokens.dart';

/// What the model reads. Only the target the model reads changes; labels, pause rules and the draw checks keep one
/// label word per text word.
///
/// - A standalone «و» (label o) after a consonant-final word is written onto that word
///   (bord/nd o s/@y -> bord/ndo s/@y). Written apart, the voice drops it in some contexts in nearly every draw.
/// - A voice trained with the pause tokens gets a long pause before the line: straight after the prompt, the line's
///   first word is often lost.
const String _consonants = 'bcdfghjklmnpqrstvwxyzš@;';
const String _long = '\uE101'; // the long pause token (pauses.dart pauseLong)

/// Style and metre tokens, which open a label.
final String _prefix = styleTokens.join() + metreTokens.join();

String glueVav(String label) {
  final out = <String>[];
  for (final tok in label.split(' ')) {
    if (tok == 'o' && out.isNotEmpty && out.last.isNotEmpty && _consonants.contains(out.last[out.last.length - 1])) {
      out[out.length - 1] += 'o';
    } else {
      out.add(tok);
    }
  }
  return out.join(' ');
}

/// The long pause token before the first word, after the style and metre marks.
String leadPause(String label) {
  var k = 0;
  while (k < label.length && _prefix.contains(label[k])) {
    k++;
  }
  return label.substring(k).startsWith(_long) ? label : '${label.substring(0, k)}$_long ${label.substring(k)}';
}
