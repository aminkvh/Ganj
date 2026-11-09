/// When a streamed reading may start playing: once what is left to make will be ready before playback reaches it,
/// with a 10% margin.
///
/// `(T − made) / speed ≤ (T − beyt0) / playbackRate × 0.9`, where [totalEstS] (T) is the estimated audio of the
/// whole poem, [madeS] the audio made so far, [firstBeytS] beyt 0's audio, [speed] the audio seconds made per wall
/// second and [playbackRate] the player's speed setting. An unknown speed (≤ 0) never starts.
bool shouldStart({
  required double totalEstS,
  required double madeS,
  required double firstBeytS,
  required double speed,
  required double playbackRate,
}) {
  if (speed <= 0 || playbackRate <= 0) return false;
  final left = totalEstS - madeS;
  if (left <= 0) return true;
  return left / speed <= (totalEstS - firstBeytS) / playbackRate * 0.9;
}

/// The poem's estimated total audio, in seconds: the beyts made so far ([audioSByIndex], by beyt index) as they
/// are, plus the remaining beyts' characters ([charsPerBeyt], by index) at the seconds per character measured on
/// the made ones. Zero while nothing is made.
double estimateTotal(List<int> charsPerBeyt, Map<int, double> audioSByIndex) {
  var made = 0.0;
  var madeChars = 0;
  var leftChars = 0;
  for (var i = 0; i < charsPerBeyt.length; i++) {
    final a = audioSByIndex[i];
    if (a != null) {
      made += a;
      madeChars += charsPerBeyt[i];
    } else {
      leftChars += charsPerBeyt[i];
    }
  }
  if (audioSByIndex.isEmpty || madeChars <= 0) return made;
  return made + made / madeChars * leftChars;
}
