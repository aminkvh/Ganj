import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/api_client.dart';
import '../../core/theme/ganj_colors.dart';
import '../../l10n/l10n.dart';
import '../../widgets/external_link.dart';

/// Persian Wiktionary (CC BY-SA), which carries Moein's definitions: Ganjoor has no dictionary
/// API of its own. Tests replace this with a fake.
final dictionaryProvider = Provider<Dictionary>((ref) => Dictionary(createDio()));

/// One part of an entry: a heading such as «اسم» or «عامیانه» and its definitions, in order.
class MeaningGroup {
  const MeaningGroup(this.heading, this.lines);

  final String? heading;
  final List<String> lines;
}

class WordMeaning {
  const WordMeaning(this.word, this.groups);

  final String word;
  final List<MeaningGroup> groups;

  String get pageUrl => 'https://fa.wiktionary.org/wiki/${Uri.encodeComponent(word)}';
}

class Dictionary {
  Dictionary(this._dio);

  final Dio _dio;

  static const _maxGroups = 6, _maxLines = 8, _maxLine = 240;

  /// Sections that say where a word comes from or how it sounds, not what it means.
  static bool _isNoise(String heading) =>
      heading.startsWith('ریشه') ||
      heading.startsWith('آوا') ||
      heading.startsWith('تلفظ') ||
      heading.startsWith('برگردان') ||
      heading.startsWith('ترجمه') ||
      heading.startsWith('همچنین') ||
      heading.startsWith('پیوند');

  /// Dictionary names that Wiktionary prints above the definitions it copied from them.
  static bool _isSourceName(String line) =>
      line.startsWith('فرهنگ ') || line.startsWith('لغت‌نامه') || line.startsWith('لغتنامه');

  /// Strips vowel marks, tatweel and punctuation, and unifies Arabic yeh/kaf, so «سَاقِی» finds «ساقی».
  static String clean(String raw) {
    final buf = StringBuffer();
    for (final r in raw.runes) {
      if ((r >= 0x064B && r <= 0x065F) || r == 0x0670 || r == 0x0640 || r == 0x200c) continue;
      final ch = switch (r) {
        0x064A || 0x0649 => 0x06CC, // ي ى → ی
        0x0643 => 0x06A9, // ك → ک
        _ => r,
      };
      final s = String.fromCharCode(ch);
      if (RegExp(r'[\p{L}\p{N} ]', unicode: true).hasMatch(s)) buf.write(s);
    }
    return buf.toString().trim();
  }

  /// The Persian entry of [raw] (one word), or null when the dictionary has none.
  Future<WordMeaning?> lookup(String raw) async {
    final word = clean(raw);
    if (word.isEmpty || word.contains(' ')) return null;
    final res = await _dio.get<String>(
      'https://fa.wiktionary.org/w/api.php',
      queryParameters: {
        'action': 'query',
        'prop': 'extracts',
        'explaintext': 1,
        'redirects': 1,
        'titles': word,
        'format': 'json',
        'formatversion': 2,
        'utf8': 1,
      },
    );
    final extract = _extract(res.data ?? '');
    final groups = extract == null ? const <MeaningGroup>[] : parse(extract);
    return groups.isEmpty ? null : WordMeaning(word, groups);
  }

  static String? _extract(String body) {
    try {
      final pages = (jsonDecode(body) as Map)['query']['pages'] as List;
      return pages.isEmpty ? null : (pages.first as Map)['extract'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// The «فارسی» part of a page as headed groups of short definition lines.
  static List<MeaningGroup> parse(String extract) {
    final heading = RegExp(r'^(=+)\s*(.+?)\s*=+\s*$');
    String? language;
    String? current;
    var skipping = false;
    final groups = <MeaningGroup>[];
    var lines = <String>[];
    void flush() {
      if (lines.isNotEmpty) groups.add(MeaningGroup(current, lines));
      lines = [];
    }

    for (final raw in extract.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final m = heading.firstMatch(line);
      if (m != null) {
        final level = m.group(1)!.length;
        final title = m.group(2)!;
        if (level == 2) {
          flush();
          language = title;
          current = null;
          skipping = false;
        } else {
          flush();
          skipping = _isNoise(title);
          current = skipping ? null : title.replaceAll(RegExp(r'[۰-۹0-9]+$'), '').trim();
          // The sources section also holds definitions copied from a named dictionary.
          if (title.startsWith('منبع') || title.startsWith('منابع')) {
            skipping = false;
            current = null;
          }
        }
        continue;
      }
      if (language != 'فارسی' || skipping || _isSourceName(line)) continue;
      lines.add(line.length > _maxLine ? '${line.substring(0, _maxLine).trimRight()}…' : line);
    }
    flush();

    // Neighbouring groups with the same heading (the definitions copied from Moein follow the
    // page's own) read as one.
    final tidy = <MeaningGroup>[];
    for (final g in groups) {
      if (tidy.isNotEmpty && tidy.last.heading == g.heading) {
        tidy[tidy.length - 1] = MeaningGroup(g.heading, [...tidy.last.lines, ...g.lines]);
      } else {
        tidy.add(g);
      }
    }
    for (var i = 0; i < tidy.length; i++) {
      if (tidy[i].lines.length > _maxLines) {
        tidy[i] = MeaningGroup(tidy[i].heading, tidy[i].lines.take(_maxLines).toList());
      }
    }
    return tidy.take(_maxGroups).toList();
  }
}

/// «معنی»: the selected word's dictionary entry in a sheet.
Future<void> showWordMeaning(BuildContext context, WidgetRef ref, String selected) {
  final dictionary = ref.read(dictionaryProvider);
  final launcher = ref.read(urlLauncherProvider);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _MeaningSheet(word: Dictionary.clean(selected), dictionary: dictionary, launcher: launcher),
  );
}

class _MeaningSheet extends StatefulWidget {
  const _MeaningSheet({required this.word, required this.dictionary, required this.launcher});

  final String word;
  final Dictionary dictionary;
  final Future<bool> Function(Uri) launcher;

  @override
  State<_MeaningSheet> createState() => _MeaningSheetState();
}

class _MeaningSheetState extends State<_MeaningSheet> {
  // Asked once: the sheet rebuilds while it is touched, and must not ask again each time.
  late final Future<WordMeaning?> _meaning = widget.dictionary.lookup(widget.word);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ganj;
    return FutureBuilder<WordMeaning?>(
      future: _meaning,
      builder: (ctx, snap) {
        final m = snap.data;
        final Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (snap.hasError) {
          body = Text(l.meaningOffline, style: TextStyle(color: c.muted, height: 1.8));
        } else if (m == null) {
          body = Text(l.meaningNotFound, style: TextStyle(color: c.muted, height: 1.8));
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final g in m.groups) ...[
                if (g.heading != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      g.heading!,
                      style: TextStyle(color: c.gold, fontWeight: FontWeight.w700),
                    ),
                  ),
                for (final line in g.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('•  ', style: TextStyle(color: c.muted, height: 1.8)),
                        Expanded(child: Text(line, style: const TextStyle(height: 1.8))),
                      ],
                    ),
                  ),
              ],
            ],
          );
        }
        return SingleChildScrollView(
          key: const ValueKey('word-meaning'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.word,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.lapis),
              ),
              body,
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.meaningSource),
                onPressed: () => openExternal(
                  ctx,
                  m?.pageUrl ?? 'https://fa.wiktionary.org/wiki/${Uri.encodeComponent(widget.word)}',
                  launcher: widget.launcher,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
