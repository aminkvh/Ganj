/// A person's "lifeline" on the river timeline: the story orders where they appear, joined
/// into runs. Runs separated by at most [maxGap] missing sections are joined — a hero who
/// skips one story hasn't left the book.
List<(int from, int to)> lifelineSegments(List<int> sections, {int maxGap = 1}) {
  if (sections.isEmpty) return const [];
  final s = sections.toSet().toList()..sort();
  final out = <(int, int)>[];
  var from = s.first, to = s.first;
  for (final o in s.skip(1)) {
    if (o - to <= maxGap + 1) {
      to = o;
    } else {
      out.add((from, to));
      from = to = o;
    }
  }
  out.add((from, to));
  return out;
}
