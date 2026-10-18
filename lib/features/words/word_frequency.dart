import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/extras.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';

/// App-bar action of a poet or section page: its «بسامد واژگان» in a sheet.
class WordFrequencyButton extends StatelessWidget {
  const WordFrequencyButton({super.key, required this.catId, required this.poetId});

  final int catId, poetId;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.l10n.wordFrequency,
    icon: const Icon(Icons.bar_chart),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => WordFrequencySheet(catId: catId, poetId: poetId, scroll: scroll),
      ),
    ),
  );
}

/// «۸۱٬۸۰۶» in Persian, "81,806" in English.
String _count(int n) =>
    localDigits('$n'.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => latinNumbers ? ',' : '٬'));

class WordFrequencySheet extends ConsumerStatefulWidget {
  const WordFrequencySheet({super.key, required this.catId, required this.poetId, this.scroll});

  final int catId, poetId;
  final ScrollController? scroll;

  @override
  ConsumerState<WordFrequencySheet> createState() => _WordFrequencySheetState();
}

class _WordFrequencySheetState extends ConsumerState<WordFrequencySheet> {
  static const _pageSize = 30;

  late final Future<({int total, int unique})> _sums = ref.read(ganjoorApiProvider).wordSums(widget.catId);
  final _words = <WordCount>[];
  String _term = '';
  int _page = 0;
  bool _loading = false, _more = false, _failed = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    final term = _term;
    final page = next ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _failed = false;
      if (!next) _words.clear();
    });
    try {
      final got = await ref
          .read(ganjoorApiProvider)
          .wordCounts(widget.catId, term: term, page: page, pageSize: _pageSize);
      if (!mounted || term != _term) return;
      setState(() {
        _words.addAll(got);
        _page = page;
        _more = got.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted && term == _term) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _term = q.trim();
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(l.wordFrequency, style: Theme.of(context).textTheme.titleMedium),
        FutureBuilder(
          future: _sums,
          builder: (context, snap) => Text(switch (snap.data) {
            final s? when s.total > 0 => l.wordTotals(_count(s.total), _count(s.unique)),
            _ => '',
          }, style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('word-field'),
          decoration: InputDecoration(hintText: l.findWord, isDense: true, prefixIcon: const Icon(Icons.search)),
          onChanged: _search,
        ),
        const SizedBox(height: 8),
        for (final w in _words)
          InkWell(
            onTap: () {
              Navigator.pop(context);
              context.push('/search?poet=${widget.poetId}&q=${Uri.encodeComponent(w.word)}');
            },
            child: Tooltip(
              message: l.searchThisWord,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(localDigits(w.rank), style: TextStyle(color: c.muted, fontSize: 12)),
                    ),
                    Expanded(child: Text(w.word)),
                    Text(_count(w.count), style: TextStyle(color: c.muted)),
                  ],
                ),
              ),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_failed)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(l.notLoaded, style: TextStyle(color: c.muted)),
              TextButton(
                onPressed: () => _load(next: _words.isNotEmpty),
                child: Text(l.retry),
              ),
            ],
          )
        else if (_words.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l.nothingHere,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted),
            ),
          )
        else if (_more)
          TextButton(onPressed: () => _load(next: true), child: Text(l.moreWords)),
      ],
    );
  }
}
