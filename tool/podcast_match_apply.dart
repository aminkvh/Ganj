// Applies the podcast matches Claude proposed in the podcast-match workflow, after checking each one.
// Claude never edits the catalogs itself: it only writes a decisions file, and this script — run from
// a clean checkout — decides what of it may go in.
//
//   dart run tool/podcast_match_apply.dart <unmatched.json> <decisions.json> <summary.md>
//
// decisions.json: {"episodes": [{"podcast": id, "guid": g, "poems": [paths]} |
//                               {"podcast": id, "guid": g, "stories": [story ids]} |
//                               {"podcast": id, "guid": g, "skip": true}, each with a short "reason"]}
//
// A decision is applied only when: the episode is one waiting to be matched (unmatched.json, written by
// tool/podcast_update.dart from the live feeds), it is decided once, Shahnameh episodes name real story
// ids (assets/seed/shahnameh/ages.json) and poem episodes name poems that exist on Ganjoor. Anything
// else is rejected and listed. Existing matches are never changed or removed. Writes a summary for the
// pull request; exits 0 with "applied N" on stdout (N may be 0).
import 'dart:convert';
import 'dart:io';

import 'podcast_update.dart' show confirmPoem;

const _shCatalog = 'assets/seed/shahnameh/podcasts.json';
const _poemCatalog = 'assets/seed/podcasts.json';
const _shSkipped = 'tool/podcast_skipped.json';
const _poemSkipped = 'tool/poem_podcast_skipped.json';

Map<String, dynamic> _read(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Writes [data] in the same layout as the file it replaces: one line, or one-space indents.
void _write(String path, Object data) {
  final old = File(path).readAsStringSync();
  final oneLine = !old.substring(0, old.length.clamp(0, 200)).contains('\n');
  final text = oneLine ? jsonEncode(data) : const JsonEncoder.withIndent(' ').convert(data);
  File(path).writeAsStringSync(old.endsWith('\n') ? '$text\n' : text);
}

/// Feed and model text shown in the pull request: one line, no @mentions, no markdown that could
/// turn into links or tables.
String _safe(Object? s, {int max = 300}) {
  var t = '${s ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll('@', '＠').replaceAll(RegExp(r'[|<>\[\]`*_#]'), ' ');
  return t.length > max ? '${t.substring(0, max)}…' : t;
}

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('Usage: dart run tool/podcast_match_apply.dart <unmatched.json> <decisions.json> <summary.md>');
    exit(2);
  }
  final waiting = {
    for (final w in (jsonDecode(File(args[0]).readAsStringSync()) as List).cast<Map<String, dynamic>>())
      '${w['podcast']} ${w['guid']}': w,
  };
  final decisionsFile = File(args[1]);
  final decisions = decisionsFile.existsSync()
      ? ((jsonDecode(decisionsFile.readAsStringSync()) as Map<String, dynamic>)['episodes'] as List? ?? const [])
      : const [];

  final stories = {
    for (final age in (_read('assets/seed/shahnameh/ages.json')['ages'] as List))
      for (final s in (age['stories'] as List)) s['id'] as String,
  };
  final sh = _read(_shCatalog), poems = _read(_poemCatalog);
  final shSkip = _read(_shSkipped), poemSkip = _read(_poemSkipped);
  Map<String, dynamic> podcast(Map<String, dynamic> catalog, String id) =>
      (catalog['podcasts'] as List).cast<Map<String, dynamic>>().firstWhere((p) => p['id'] == id);

  final applied = <String>[], rejected = <String>[];
  final seen = <String>{};
  for (final raw in decisions) {
    String? why;
    final d = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
    final key = '${d['podcast']} ${d['guid']}';
    final w = waiting[key];
    final targets = [...?(d['poems'] ?? d['stories']) as List?].map((t) => '$t').toList();
    final skip = d['skip'] == true;
    if (w == null) {
      why = 'not an episode waiting to be matched';
    } else if (!seen.add(key)) {
      why = 'decided twice';
    } else if (skip == targets.isNotEmpty) {
      why = 'needs either targets or "skip", not both';
    } else if (!skip && w['catalog'] == 'shahnameh') {
      if (d['stories'] == null || targets.length > 6) why = 'a Shahnameh episode needs 1–6 "stories"';
      for (final t in targets) {
        if (!stories.contains(t)) why ??= 'no story "$t"';
      }
    } else if (!skip) {
      if (d['poems'] == null || targets.length > 40) why = 'a poem episode needs 1–40 "poems"';
      for (final t in targets) {
        if (why != null) break;
        if (!RegExp(r'^/[a-z0-9\-]+(/[a-z0-9\-]+)+$').hasMatch(t) || !await confirmPoem(t)) {
          why = 'no poem $t on Ganjoor';
        }
      }
    }
    final label =
        '**${_safe(w?['podcastFa'] ?? d['podcast'], max: 60)}** — ${_safe(w?['title'] ?? d['guid'], max: 120)}';
    if (why != null) {
      rejected.add('- $label: rejected, $why.');
      continue;
    }
    final id = w!['podcast'] as String;
    if (skip) {
      ((w['catalog'] == 'shahnameh' ? shSkip : poemSkip)[id] ??= <dynamic>[]) as List;
      ((w['catalog'] == 'shahnameh' ? shSkip : poemSkip)[id] as List).add(w['guid']);
    } else {
      final map =
          podcast(w['catalog'] == 'shahnameh' ? sh : poems, id)[w['catalog'] == 'shahnameh' ? 'stories' : 'poems']
              as Map<String, dynamic>;
      for (final t in targets) {
        ((map[t] ??= <dynamic>[]) as List).add(w['guid']);
      }
    }
    applied.add('- $label → ${skip ? 'skipped' : targets.map((t) => '`$t`').join(', ')}  \n  _${_safe(d['reason'])}_');
  }

  if (applied.isNotEmpty) {
    _write(_shCatalog, sh);
    _write(_poemCatalog, poems);
    _write(_shSkipped, shSkip);
    _write(_poemSkipped, poemSkip);
  }
  final left = waiting.length - applied.length;
  File(args[2]).writeAsStringSync(
    [
      'Episodes matched by Claude in the podcast-match workflow. Each one was checked by '
          '`tool/podcast_match_apply.dart`: it was waiting in the feeds, and its poems exist on Ganjoor '
          '(or its stories in the app). **Check the matches, then merge**; the next daily run publishes them.',
      '',
      '### Matched or skipped (${applied.length})',
      ...applied,
      if (rejected.isNotEmpty) ...['', '### Rejected by the check (${rejected.length})', ...rejected],
      '',
      '$left episode(s) are still waiting and stay in the "Podcast episodes to match" issue.',
    ].join('\n'),
  );
  stdout.writeln('applied ${applied.length}');
  exit(0);
}
