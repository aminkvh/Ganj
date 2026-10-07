import '../api/dto/poem.dart';

/// Rebuilds Ganjoor's couplet indexes from verse positions (packs don't store them):
/// every line starts a new couplet except a left hemistich (1) or the second band line (3).
List<int> coupletIndexes(List<int> positions) {
  var index = -1;
  return [
    for (final p in positions)
      (p == VersePosition.left || p == VersePosition.centered2) && index >= 0 ? index : ++index,
  ];
}
