// Reports looksArabic's precision and recall on a labelled sample of hemistichs.
//
// Usage: dart run tool/language_guess_eval.dart <sample.jsonl | test/fixtures/voice/language_sample.json> [--show]
// JSONL: one JSON object per line with "text" and either "label" ("ar", "fa" or "other") or Ganjoor's "lang"
// (2 = Arabic, null or 1 = Persian, anything else = other). Other languages are counted and left out.
// The fixture: {"items": [{"t": text, "ar": 1 or 0}]}.
import 'dart:convert';
import 'dart:io';

import 'package:ganj/features/voice/app/language_guess.dart';

void main(List<String> args) {
  final show = args.contains('--show');
  var tp = 0, fn = 0, fp = 0, tn = 0, other = 0;
  final missed = <String>[], wrong = <String>[];
  final src = File(args.first).readAsStringSync();
  // The committed fixture (one JSON object with items [{t, ar}]) or JSONL.
  final List<Map<String, dynamic>> rows = src.trimLeft().startsWith('{') && args.first.endsWith('.json')
      ? [for (final e in (jsonDecode(src) as Map)['items'] as List) (e as Map).cast<String, dynamic>()]
      : [
          for (final line in src.split('\n'))
            if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
        ];
  for (final r in rows) {
    final text = (r['text'] ?? r['t']) as String;
    final String label;
    if (r.containsKey('ar')) {
      label = r['ar'] == 1 ? 'ar' : 'fa';
    } else if (r.containsKey('label')) {
      label = r['label'] as String;
    } else {
      final lang = r['lang'] as int?;
      label = lang == 2 ? 'ar' : (lang == null || lang == 1 ? 'fa' : 'other');
    }
    if (label == 'other') {
      other++;
      continue;
    }
    final guess = looksArabic(text);
    if (label == 'ar') {
      guess ? tp++ : fn++;
      if (!guess) missed.add(text);
    } else {
      guess ? fp++ : tn++;
      if (guess) wrong.add(text);
    }
  }
  final precision = tp + fp == 0 ? 1.0 : tp / (tp + fp);
  final recall = tp + fn == 0 ? 0.0 : tp / (tp + fn);
  stdout
    ..writeln('arabic ${tp + fn}, persian ${fp + tn}, other languages $other')
    ..writeln('tp $tp  fn $fn  fp $fp  tn $tn')
    ..writeln('precision ${precision.toStringAsFixed(4)}  recall ${recall.toStringAsFixed(4)}');
  if (show) {
    stdout.writeln('--- Persian flagged:');
    wrong.forEach(stdout.writeln);
    stdout.writeln('--- Arabic missed:');
    missed.forEach(stdout.writeln);
  }
}
