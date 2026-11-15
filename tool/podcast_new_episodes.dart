// Lists the episodes of the Shahnameh podcasts (assets/seed/shahnameh/podcasts.json) that are not
// matched to a story yet, so new episodes can be added by hand before a release:
//
//   dart run tool/podcast_new_episodes.dart
//
// Episodes already left out on purpose (specials, other books, talks) are listed in
// tool/podcast_skipped.json and not reported again. It also reports matched episodes that have
// left a feed. It only reads; it never edits podcasts.json.
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

const _catalog = 'assets/seed/shahnameh/podcasts.json';
const _skippedFile = 'tool/podcast_skipped.json';

final _client = HttpClient()..userAgent = 'Ganj podcast check tool (io.github.aminkvh.ganj)';

Future<String> _get(String url) async {
  final req = await _client.getUrl(Uri.parse(url));
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) throw HttpException('${res.statusCode} for $url');
  return body;
}

Future<void> main() async {
  final catalog = jsonDecode(File(_catalog).readAsStringSync()) as Map<String, dynamic>;
  final skippedAll = File(_skippedFile).existsSync()
      ? jsonDecode(File(_skippedFile).readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  var newTotal = 0;
  for (final p in catalog['podcasts'] as List) {
    final id = p['id'] as String;
    final mapped = {
      for (final gs in (p['stories'] as Map<String, dynamic>).values)
        for (final g in gs as List) g as String,
    };
    final skipped = {for (final g in (skippedAll[id] as List?) ?? const []) g as String};
    stdout.writeln('== $id (${p['fa']})');
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(await _get(p['feed'] as String));
    } catch (e) {
      stdout.writeln('   feed failed: $e');
      continue;
    }
    final inFeed = <String>{};
    var latest = '';
    for (final item in doc.findAllElements('item')) {
      final guid = item.findElements('guid').firstOrNull?.innerText.trim() ?? '';
      if (guid.isEmpty) continue;
      inFeed.add(guid);
      final date = item.findElements('pubDate').firstOrNull?.innerText.trim() ?? '';
      if (latest.isEmpty) latest = date;
      if (mapped.contains(guid) || skipped.contains(guid)) continue;
      newTotal++;
      final title = item.findElements('title').firstOrNull?.innerText.trim() ?? '';
      stdout.writeln('   NEW  $guid\n        $date  $title');
    }
    final gone = mapped.difference(inFeed);
    if (gone.isNotEmpty) stdout.writeln('   gone from the feed: ${gone.join(', ')}');
    stdout.writeln('   ${inFeed.length} in feed, ${mapped.length} matched; newest: $latest');
  }
  stdout.writeln(newTotal == 0 ? '\nNothing new.' : '\n$newTotal episode(s) to match or skip.');
  _client.close();
}
