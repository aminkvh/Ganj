// When a match Claude proposed may be merged without the maintainer's review. These rules read the
// episode's title themselves; what Claude says about it ("reason") plays no part. Anything they are
// not sure of waits for review.
import 'podcast_update.dart' show latinDigits, plain;

final _range = RegExp(r'غزل[^\d]{0,12}(\d+)\s*تا\s*(\d+)');
// Story names that are chapter headings in the titles, not what the episode tells (found by checking
// the rule against every match made by hand).
const _headings = {'shahpod'};

// The episode runs from one story into another.
final _runsOn = RegExp('آغاز|پایان|ادامه');

final _number = RegExp(r'^(.+)/sh(\d+)$');

/// A category's poems: slug → first line.
typedef FirstLines = Future<Map<String, String>> Function(String category);

/// Why a person has to look at this match, or null when it may be merged as it is.
/// [current] is what the podcast is matched to now (target → guids), the title rules' matches included.
Future<String?> whyReview({
  required String catalog,
  required String podcast,
  required String title,
  required List<String> targets,
  required Map<String, dynamic> current,
  required Map<String, String> storyNames,
  required FirstLines firstLines,
}) async {
  if (targets.isEmpty) return 'nothing is matched';
  if (catalog == 'shahnameh') return _story(podcast, title, targets, storyNames);
  if (targets.any(current.containsKey)) return 'the podcast already has an episode on one of these poems';
  return targets.length == 1
      ? _onePoem(title, targets.single, current, firstLines)
      : _poemRange(title, targets, current);
}

/// The story's full name is in the title, and no other story's is.
String? _story(String podcast, String title, List<String> targets, Map<String, String> names) {
  if (_headings.contains(podcast)) return 'this podcast names stories as chapter headings';
  if (_runsOn.hasMatch(title)) return 'the episode may run on into another story';
  final t = plain(title);
  final named = [
    for (final e in names.entries)
      if (t.contains(plain(e.value))) e.key,
  ];
  return targets.length == 1 && named.length == 1 && named.single == targets.single
      ? null
      : 'the title does not give exactly one story by its full name';
}

/// The title quotes the poem's first line (four words), which no other poem of the section shares.
Future<String?> _onePoem(String title, String path, Map<String, dynamic> current, FirstLines firstLines) async {
  final i = path.lastIndexOf('/');
  final category = path.substring(0, i), slug = path.substring(i + 1);
  if (!current.keys.any((k) => k.substring(0, k.lastIndexOf('/')) == category)) {
    return 'the podcast has not read from this section before';
  }
  final t = plain(title);
  // Poems that open the same way are all quoted, so a shared opening is refused too.
  final quoted = [
    for (final e in (await firstLines(category)).entries)
      if (_opening(e.value) case final o? when t.contains(o)) e.key,
  ];
  if (!quoted.contains(slug)) return 'the title does not quote the first line of the poem';
  return quoted.length == 1 ? null : 'the title fits more than one poem';
}

String? _opening(String line) {
  final words = line.split(RegExp(r'\s+')).where((w) => plain(w).isNotEmpty).take(4).toList();
  return words.length < 4 ? null : plain(words.join(' '));
}

/// The title says "غزل A تا B", the poems are exactly those, and A follows the last one matched.
String? _poemRange(String title, List<String> targets, Map<String, dynamic> current) {
  final m = _range.firstMatch(latinDigits(title));
  final first = _number.firstMatch(targets.first);
  if (m == null || first == null) return 'the title does not state the range';
  final a = int.parse(m[1]!), b = int.parse(m[2]!), category = first[1]!;
  if (b <= a || b - a > 20) return 'the range is too long or runs backwards';
  final expected = [for (var n = a; n <= b; n++) '$category/sh$n'];
  if (expected.join(' ') != targets.join(' ')) return 'the poems are not the range in the title';
  var last = 0;
  for (final k in current.keys) {
    final n = _number.firstMatch(k);
    if (n != null && n[1] == category && int.parse(n[2]!) > last) last = int.parse(n[2]!);
  }
  return last > 0 && a == last + 1 ? null : 'the range does not carry on from the last episode';
}
