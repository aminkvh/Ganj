// Builds the podcast data Ganj downloads between releases, so new episodes show up without an app
// update (the "podcasts-data" workflow runs it every day and publishes the result):
//
//   dart run tool/podcast_update.dart [out dir, default build/podcasts]
//
// It starts from the bundled catalogs (assets/seed/shahnameh/podcasts.json, assets/seed/podcasts.json),
// which hold every match made and checked by hand, and adds the new episodes of the podcasts whose
// titles say exactly which poem they read (a ghazal number, a verse range) — and only when the title
// also agrees with Ganjoor: the first line matches, the poem exists, the numbering carries on from the
// last episode. Everything else new is listed in unmatched.md for matching by hand.
//
// Writes <out>/podcasts.json ({schema, builtAt, shahnameh, poems}) and <out>/unmatched.md.
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

const _shCatalog = 'assets/seed/shahnameh/podcasts.json';
const _poemCatalog = 'assets/seed/podcasts.json';
const _skippedFiles = ['tool/podcast_skipped.json', 'tool/poem_podcast_skipped.json'];
const _masnaviTable = 'tool/data/masnavi_nicholson.tsv';

final _client = HttpClient()..userAgent = 'Ganj podcast update tool (+https://github.com/aminkvh/Ganj)';

Future<String> _get(String url) async {
  final req = await _client.getUrl(Uri.parse(url));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) throw HttpException('${res.statusCode} for $url');
  return body;
}

/// A feed item: guid, title, publication date.
typedef Item = ({String guid, String title, String date});

/// The feed's playable items, oldest first.
Future<List<Item>> _items(String feed) async {
  final doc = XmlDocument.parse(await _get(feed));
  return [
    for (final i in doc.findAllElements('item'))
      if ((i.findElements('guid').firstOrNull?.innerText.trim() ?? '') case final g when g.isNotEmpty)
        if (i.findElements('enclosure').firstOrNull?.getAttribute('url')?.isNotEmpty ?? false)
          (
            guid: g,
            title: i.findElements('title').firstOrNull?.innerText.trim() ?? '',
            date: i.findElements('pubDate').firstOrNull?.innerText.trim() ?? '',
          ),
  ].reversed.toList();
}

String latinDigits(String s) => s.replaceAllMapped(RegExp('[۰-۹٠-٩]'), (m) {
  final c = m[0]!.codeUnitAt(0);
  return '${c >= 0x06F0 ? c - 0x06F0 : c - 0x0660}';
});

/// Letters only, one spelling: for comparing a title with Ganjoor's first line.
String plain(String s) => s
    .replaceAll(RegExp('[ً-ٰٟٕٔ]'), '')
    .replaceAll('ي', 'ی')
    .replaceAll('ى', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ۀ', 'ه')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'[‌‏‎\s\p{P}]+', unicode: true), '');

/// Ganjoor's poems in a category: slug → first hemistich (fetched once per run).
final _cats = <String, Future<Map<String, String>>>{};

Future<Map<String, String>> ganjoorCat(String url) => _cats[url] ??= () async {
  final j = jsonDecode(
    await _get('https://api.ganjoor.net/api/ganjoor/cat?url=${Uri.encodeQueryComponent(url)}&poems=true'),
  );
  return {for (final p in (j['cat']['poems'] as List)) p['urlSlug'] as String: (p['excerpt'] as String?) ?? ''};
}();

/// Does the poem at [path] exist on Ganjoor, and (when [title] is given) does the title quote its first line?
Future<bool> confirmPoem(String path, {String? title}) async {
  final i = path.lastIndexOf('/');
  final poems = await ganjoorCat(path.substring(0, i));
  final excerpt = poems[path.substring(i + 1)];
  if (excerpt == null) return false;
  if (title == null) return true;
  // The first four words of the first line, as letters only, must be in the title.
  final words = excerpt.split(RegExp(r'\s+')).where((w) => plain(w).isNotEmpty).take(4).join(' ');
  return plain(words).isNotEmpty && plain(title).contains(plain(words));
}

/// How a podcast's new episodes are matched: the poems [item]'s title names, given the episodes already
/// matched ([last] is the highest number reached so far); null when the title doesn't say, or disagrees.
typedef Rule = Future<List<String>?> Function(Item item, int last);

/// A ghazal number in the title (`(\d+)`), optionally checked against the first line quoted there.
Rule numbered(RegExp re, String category, {bool quotesFirstLine = false}) => (item, last) async {
  final m = re.firstMatch(latinDigits(item.title));
  if (m == null) return null;
  final path = '$category/sh${int.parse(m[1]!)}';
  return await confirmPoem(path, title: quotesFirstLine ? item.title : null) ? [path] : null;
};

/// A range of ghazals ("غزل A تا B") that carries on right after the last one matched.
Rule ranged(RegExp re, String category) => (item, last) async {
  final m = re.firstMatch(latinDigits(item.title));
  if (m == null) return null;
  final a = int.parse(m[1]!), b = int.parse(m[2]!);
  if (a != last + 1 || b < a || b - a > 20) return null;
  final paths = [for (var n = a; n <= b; n++) '$category/sh$n'];
  for (final p in paths) {
    if (!await confirmPoem(p)) return null;
  }
  return paths;
};

/// A verse range in Nicholson's numbering across the six daftars ("ابیات A تا B") that carries on
/// right after the last one matched: every Ganjoor section it overlaps.
Rule masnaviVerses(RegExp re, List<({String url, int first, int last})> table) => (item, last) async {
  final m = re.firstMatch(latinDigits(item.title));
  if (m == null) return null;
  final a = int.parse(m[1]!), b = int.parse(m[2]!);
  if (a != last + 1 || b < a || b - a > 600) return null;
  final paths = [
    for (final s in table)
      if (s.first <= b && s.last >= a) s.url,
  ];
  return paths.isEmpty ? null : paths;
};

/// The highest number the titles of [matched] items reach, read with [re] (its last group).
int lastNumber(Iterable<Item> matched, RegExp re) {
  var n = 0;
  for (final i in matched) {
    final m = re.firstMatch(latinDigits(i.title));
    if (m != null) n = [n, int.parse(m[m.groupCount]!)].reduce((a, b) => a > b ? a : b);
  }
  return n;
}

Future<void> main(List<String> args) async {
  final out = Directory(args.isNotEmpty ? args.first : 'build/podcasts')..createSync(recursive: true);
  final sh = jsonDecode(File(_shCatalog).readAsStringSync()) as Map<String, dynamic>;
  final poems = jsonDecode(File(_poemCatalog).readAsStringSync()) as Map<String, dynamic>;
  final skipped = <String, Set<String>>{};
  for (final f in _skippedFiles) {
    if (!File(f).existsSync()) continue;
    for (final e in (jsonDecode(File(f).readAsStringSync()) as Map<String, dynamic>).entries) {
      skipped.putIfAbsent(e.key, () => {}).addAll([for (final g in e.value as List) g as String]);
    }
  }
  final table = [
    for (final l in File(_masnaviTable).readAsLinesSync().skip(3))
      if (l.split('\t') case [final url, final f, final t]) (url: url, first: int.parse(f), last: int.parse(t)),
  ];

  final hafez = RegExp(r'(?:^|\D)(\d{1,3})\s*$|^\s*(\d{3})\s');
  final rules = <String, (Rule, RegExp?)>{
    // Titles end (rarely start) with the ghazal number and quote its first line.
    'ravaq': (
      (item, last) async {
        final m = hafez.firstMatch(latinDigits(item.title));
        if (m == null) return null;
        final path = '/hafez/ghazal/sh${int.parse(m[1] ?? m[2]!)}';
        return await confirmPoem(path, title: item.title) ? [path] : null;
      },
      null,
    ),
    'hafez-razavi': (numbered(RegExp(r'غزل شماره\s*(\d+)'), '/hafez/ghazal'), null),
    'saadia': (numbered(RegExp(r'غزل\s*(\d+)\s*$'), '/saadi/divan/ghazals', quotesFirstLine: true), null),
    'sarv': (ranged(RegExp(r'غزل\s*(\d+)\s*تا\s*(\d+)'), '/saadi/divan/ghazals'), RegExp(r'غزل\s*(\d+)\s*تا\s*(\d+)')),
    'masnavi-erfanian': (
      masnaviVerses(RegExp(r'ابیات\s*(\d+)\s*تا\s*(\d+)'), table),
      RegExp(r'ابیات\s*(\d+)\s*تا\s*(\d+)'),
    ),
  };

  final report = StringBuffer();
  var added = 0, unmatched = 0, failed = 0;
  Future<void> run(Map<String, dynamic> catalog, String key) async {
    for (final p in catalog['podcasts'] as List) {
      final id = p['id'] as String;
      final map = p[key] as Map<String, dynamic>;
      final mapped = {for (final gs in map.values) ...(gs as List).cast<String>()};
      final List<Item> items;
      try {
        items = await _items(p['feed'] as String);
      } catch (e) {
        failed++;
        report.writeln('- **${p['fa']}** (`$id`): the feed could not be read ($e)');
        continue;
      }
      final rule = rules[id];
      var last = rule?.$2 == null ? 0 : lastNumber(items.where((i) => mapped.contains(i.guid)), rule!.$2!);
      final open = <Item>[];
      for (final item in items) {
        if (mapped.contains(item.guid) || (skipped[id]?.contains(item.guid) ?? false)) continue;
        final paths = rule == null ? null : await rule.$1(item, last);
        if (paths == null) {
          open.add(item);
          continue;
        }
        for (final path in paths) {
          (map[path] ??= <dynamic>[]) as List;
          (map[path] as List).add(item.guid);
        }
        mapped.add(item.guid);
        added++;
        if (rule!.$2 != null) last = lastNumber([item], rule.$2!);
        stdout.writeln('+ $id ${item.guid} → ${paths.join(', ')}  (${item.title})');
      }
      if (open.isEmpty) continue;
      unmatched += open.length;
      report.writeln('- **${p['fa']}** (`$id`, ${key == 'stories' ? 'Shahnameh stories' : 'poems'}):');
      for (final i in open) {
        report.writeln('  - `${i.guid}` ${i.date} — ${i.title}');
      }
    }
  }

  await run(sh, 'stories');
  await run(poems, 'poems');
  _client.close();

  final builtAt = DateTime.now().toUtc().toIso8601String();
  File('${out.path}/podcasts.json').writeAsStringSync(
    jsonEncode({
      'schema': 1,
      'builtAt': builtAt,
      'shahnameh': {...sh, 'builtAt': builtAt},
      'poems': {...poems, 'builtAt': builtAt},
    }),
  );
  File('${out.path}/unmatched.md').writeAsStringSync(
    report.isEmpty
        ? ''
        : 'New podcast episodes that need matching by hand (add them to the catalogs in `assets/seed/`, '
              'or to `tool/podcast_skipped.json` / `tool/poem_podcast_skipped.json`):\n\n$report',
  );
  stdout.writeln('\n$added episode(s) matched by their titles; $unmatched to match by hand; $failed feed(s) failed.');
}
