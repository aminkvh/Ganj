// Builds assets/seed/shahnameh/generated.json: the Shahnameh's people, their ties, the story
// sections with their poems, who appears where, and Ganjoor's place tags, distilled from
// api.ganjoor.net so «جهان شاهنامه» opens offline. Re-run before a release:
//
//   dart run tool/shahnameh_snapshot.dart
//
// It downloads every section's tags once (≈30 MB in total); the app never does.
import 'dart:convert';
import 'dart:io';

const _api = 'https://api.ganjoor.net';
const _book = 33; // شاهنامه
const _prologue = 34; // «آغاز کتاب» — not a story section
const _out = 'assets/seed/shahnameh/generated.json';

final _client = HttpClient()..userAgent = 'Ganj snapshot tool (io.github.aminkvh.ganj)';

Future<dynamic> _json(String path) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final req = await _client.getUrl(Uri.parse('$_api$path'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw HttpException('${res.statusCode} for $path');
      return jsonDecode(body);
    } catch (e) {
      if (attempt == 3) rethrow;
      stderr.writeln('retrying $path ($e)');
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
    }
  }
}

/// The poems of a section in reading order, descending into sub-sections.
Future<List<List<Object>>> _poems(int catId) async {
  final cat = (await _json('/api/ganjoor/cat/$catId?poems=true&mainSections=false') as Map)['cat'] as Map;
  return [
    for (final p in (cat['poems'] as List? ?? const [])) [p['id'] as int, p['title'] as String, p['urlSlug'] as String],
    for (final c in (cat['children'] as List? ?? const [])) ...await _poems(c['id'] as int),
  ];
}

/// Ganjoor's mark on AI-written summaries (the app shows a badge instead).
const _aiSummary = 'هوش مصنوعی:';

/// Ganjoor's note on a tag its AI suggested (and a volunteer then approved), e.g.
/// «پیشنهاد هوش مصنوعی (claude-…): [description]».
final _aiTagNote = RegExp(r'^پیشنهاد هوش مصنوعی \([^)]*\):\s*');

/// First sentence of a Ganjoor poem summary, for one-line story cards.
String? _firstSentence(String? s) {
  if (s == null) return null;
  var t = s.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.startsWith(_aiSummary)) t = t.substring(_aiSummary.length).trim();
  if (t.isEmpty) return null;
  final end = t.indexOf(RegExp(r'[.؛!؟]'));
  final cut = end > 20 ? t.substring(0, end + 1) : t;
  return cut.length <= 160 ? cut : '${cut.substring(0, 159)}…';
}

Future<void> main() async {
  final book = (await _json('/api/ganjoor/cat/$_book?poems=false&mainSections=false') as Map)['cat'] as Map;
  final sectionCats = [
    for (final c in book['children'] as List)
      if (c['id'] != _prologue) c as Map,
  ];

  final locations = {for (final l in await _json('/api/locations') as List) l['id'] as int: l as Map};

  final sections = <Map<String, Object?>>[];
  final summaries = <String, String>{};
  final aiSummaries = <int>{};
  final presence = <int, Set<int>>{};
  final passing = <int, Set<int>>{};
  final poemPeople = <int, Map<int, int>>{};
  // Poem → people whose tag there the AI suggested.
  final aiTags = <int, Set<int>>{};
  // Person → descriptions the AI wrote in its tag notes.
  final aiNotes = <int, Set<String>>{};
  final places = <Map<String, Object?>>[];

  for (final (order, c) in sectionCats.indexed) {
    final id = c['id'] as int;
    stdout.writeln('section ${order + 1}/${sectionCats.length}: ${c['title']}');
    sections.add({'catId': id, 'title': c['title'], 'slug': c['urlSlug'], 'poems': await _poems(id)});
    for (final t in await _json('/api/ganjoor/cat/$id/geotag') as List) {
      final poem = t['poem'] as Map?;
      final poemId = t['poemId'] as int;
      final raw = poem?['poemSummary'] as String?;
      final summary = _firstSentence(raw);
      if (summary != null && !summaries.containsKey('$poemId')) {
        summaries['$poemId'] = summary;
        if (raw!.trim().startsWith(_aiSummary)) aiSummaries.add(poemId);
      }
      if (t['ignoreInCategory'] == true) continue;
      final person = t['personId'] as int?;
      final note = (t['note'] as String?) ?? '';
      if (person != null && _aiTagNote.hasMatch(note)) {
        aiTags.putIfAbsent(poemId, () => {}).add(person);
        aiNotes.putIfAbsent(person, () => {}).add(note.replaceFirst(_aiTagNote, '').trim());
      }
      if (person != null) {
        final mention = (t['personMention'] as int?) ?? 0;
        (mention == 0 ? presence : passing).putIfAbsent(person, () => {}).add(order);
        final inPoem = poemPeople.putIfAbsent(poemId, () => {});
        // In the story beats a passing mention.
        inPoem[person] = inPoem.containsKey(person) && inPoem[person]! < mention ? inPoem[person]! : mention;
      }
      final loc = locations[t['locationId']];
      if (loc != null) {
        places.add({
          'loc': loc['id'],
          'name': loc['name'],
          'lat': loc['latitude'],
          'lng': loc['longitude'],
          'poemId': poemId,
          'c': t['coupletIndex'],
        });
      }
    }
  }
  // Passing mentions only where the person never appears in the story itself.
  for (final e in passing.entries) {
    e.value.removeAll(presence[e.key] ?? const <int>{});
  }
  passing.removeWhere((_, v) => v.isEmpty);

  final graph = await _json('/api/ganjoor/cat/$_book/persongraph') as Map;
  final edges = [
    for (final e in graph['edges'] as List)
      [e['person1Id'], e['person2Id'], e['category'] == 'Relation' ? 'R' : 'A', e['typeValue'], e['degreeHint']],
  ];
  final wanted = <int>{for (final n in graph['nodes'] as List) n['id'] as int, ...presence.keys, ...passing.keys};
  final treeRoots = [for (final p in await _json('/api/people/familytrees') as List) p['id'] as int];
  final people = [
    for (final p in await _json('/api/people') as List)
      if (wanted.contains(p['id']))
        {
          'id': p['id'],
          'name': p['name'],
          // One string, «،»-separated.
          if ((p['aliases'] as String?)?.trim().isNotEmpty ?? false)
            'aliases': [
              for (final a in (p['aliases'] as String).split(RegExp('[،,]')))
                if (a.trim().isNotEmpty) a.trim(),
            ],
          if (p['description'] != null) 'description': p['description'],
          // The description is word for word one the AI wrote when suggesting a tag.
          if (aiNotes[p['id']]?.contains((p['description'] as String?)?.trim()) ?? false) 'aiDescription': true,
          'importance': p['importance'] ?? 0,
          'gender': p['gender'] ?? 0,
          if (p['familyTreeCaption'] != null) 'tree': p['familyTreeCaption'],
        },
  ];

  List<int> sorted(Set<int> s) => s.toList()..sort();
  final snapshot = {
    // The app's kShahnamehDataSchema: bump both when the shape below changes incompatibly.
    'schema': 1,
    'builtAt': '${DateTime.now().toUtc().toIso8601String().substring(0, 19)}Z',
    'masterCatId': _book,
    'people': people,
    'edges': edges,
    'treeRoots': treeRoots,
    'sections': sections,
    'summaries': summaries,
    'aiSummaries': aiSummaries.toList()..sort(),
    'aiTags': {for (final e in aiTags.entries) '${e.key}': sorted(e.value)},
    'presence': {for (final e in presence.entries) '${e.key}': sorted(e.value)},
    'passing': {for (final e in passing.entries) '${e.key}': sorted(e.value)},
    'poemPeople': {
      for (final e in poemPeople.entries)
        '${e.key}': [
          for (final p in e.value.entries) [p.key, p.value],
        ],
    },
    'places': places,
  };
  final file = File(_out)..createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(snapshot));
  stdout.writeln(
    'wrote $_out: ${file.lengthSync() ~/ 1024} KB — ${sections.length} sections, ${people.length} people, '
    '${edges.length} edges, ${presence.length} present, ${poemPeople.length} tagged poems, ${places.length} place tags',
  );
  _client.close();
}
