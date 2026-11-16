// Reads Ganjoor for the podcast-matching workflow (.github/workflows/podcast-match.yml): the only
// command Claude may run there, so it can only read, and only from api.ganjoor.net.
//
//   dart run tool/ganjoor_lookup.dart cat <url>     a section: its sub-sections and poems (with first lines)
//   dart run tool/ganjoor_lookup.dart poem <url>    a poem: its full title and text
//
// <url> is a Ganjoor path such as /nezami/5ganj/leyli or /hafez/ghazal/sh1. To spare Ganjoor's
// server, one workflow run may make at most [_maxLookups] lookups (counted in build/podcasts/).
import 'dart:convert';
import 'dart:io';

const _maxLookups = 150;
const _counter = 'build/podcasts/lookups.count';

Future<Map<String, dynamic>> _get(String path, Map<String, String> query) async {
  final client = HttpClient()..userAgent = 'Ganj podcast matching (+https://github.com/aminkvh/Ganj)';
  try {
    final req = await client.getUrl(Uri.https('api.ganjoor.net', path, query));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 404) throw const FormatException('Not on Ganjoor (404).');
    if (res.statusCode != 200) throw HttpException('Ganjoor answered ${res.statusCode}.');
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 2 || !{'cat', 'poem'}.contains(args[0]) || !RegExp(r'^/[a-z0-9\-/]+$').hasMatch(args[1])) {
    stderr.writeln('Usage: dart run tool/ganjoor_lookup.dart cat|poem /a/ganjoor/path');
    exitCode = 2;
    return;
  }
  final count = File(_counter)..createSync(recursive: true);
  final used = int.tryParse(count.readAsStringSync().trim()) ?? 0;
  if (used >= _maxLookups) {
    stderr.writeln('No lookups left in this run ($_maxLookups used). Skip the episodes still unsure.');
    exitCode = 3;
    return;
  }
  count.writeAsStringSync('${used + 1}');
  final url = args[1];
  try {
    if (args[0] == 'cat') {
      final c = (await _get('/api/ganjoor/cat', {'url': url, 'poems': 'true', 'mainSections': 'false'}))['cat'];
      stdout.writeln('# ${c['title']}  (${c['fullUrl']})');
      for (final s in (c['children'] as List?) ?? const []) {
        stdout.writeln('section  ${s['fullUrl']}  ${s['title']}');
      }
      for (final p in (c['poems'] as List?) ?? const []) {
        stdout.writeln('poem  ${c['fullUrl']}/${p['urlSlug']}  ${p['title']}  — ${p['excerpt'] ?? ''}');
      }
    } else {
      final p = await _get('/api/ganjoor/poem', {
        'url': url,
        for (final k in ['catInfo', 'catPoems', 'rhymes', 'recitations', 'images', 'songs', 'comments', 'navigation'])
          k: 'false',
        'verseDetails': 'false',
      });
      stdout.writeln('# ${p['fullTitle']}  (${p['fullUrl']})');
      final text = (p['plainText'] as String? ?? '').trim();
      // Long sections are cut: the opening and closing lines are enough to place an episode.
      final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
      if (lines.length <= 60) {
        stdout.writeln(lines.join('\n'));
      } else {
        stdout.writeln(
          '${lines.take(40).join('\n')}\n… (${lines.length - 50} lines left out) …\n'
          '${lines.skip(lines.length - 10).join('\n')}',
        );
      }
    }
  } on Object catch (e) {
    stderr.writeln('$e');
    exitCode = 1;
  }
}
