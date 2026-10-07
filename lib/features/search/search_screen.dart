import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/poet.dart';
import '../../data/providers.dart';
import 'search_service.dart';
import '../../l10n/l10n.dart';
import '../../core/text/content_en.dart';

/// Search poems by words, optionally within one poet; installed packs answer offline.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.poetId});

  final int? poetId;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _field = TextEditingController();
  late int? _poetId = widget.poetId;
  final _hits = <SearchHit>[];
  String? _term;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = false;
  bool _offline = false;
  int _total = 0;
  bool _totalKnown = true;

  /// Only the newest request may update the list.
  int _request = 0;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _run({bool more = false}) async {
    final term = more ? _term : _field.text.trim();
    if (term == null || term.isEmpty) return;
    setState(() {
      _loading = true;
      if (!more) {
        _hits.clear();
        _page = 1;
        _term = term;
      }
    });
    final page = more ? _page + 1 : 1;
    final request = ++_request;
    try {
      final r = await ref.read(searchServiceProvider).search(term, poetId: _poetId, page: page);
      if (!mounted || request != _request) return;
      final seen = {for (final h in _hits) h.poemId};
      setState(() {
        _hits.addAll(r.hits.where((h) => seen.add(h.poemId)));
        _page = page;
        _hasMore = r.hasMore;
        _offline = r.offline;
        _total = r.total;
        _totalKnown = r.totalKnown;
      });
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  List<Poet> _poets() {
    final seen = <int>{};
    final all = [
      for (final c in ref.watch(centuriesProvider).value ?? const <Century>[])
        for (final p in c.poets)
          if (seen.add(p.id)) p,
    ]..sort((a, b) => a.nickname.compareTo(b.nickname));
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final poets = _poets();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          key: const ValueKey('search-field'),
          controller: _field,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(hintText: context.l10n.searchPoems, border: InputBorder.none),
          onSubmitted: (_) => _run(),
        ),
        actions: [IconButton(tooltip: context.l10n.search, icon: const Icon(Icons.search), onPressed: _run)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(context.l10n.poetLabel, style: TextStyle(color: c.muted)),
                Expanded(
                  child: DropdownButton<int?>(
                    key: const ValueKey('poet-picker'),
                    isExpanded: true,
                    value: poets.any((p) => p.id == _poetId) ? _poetId : null,
                    items: [
                      DropdownMenuItem<int?>(value: null, child: Text(context.l10n.allPoets)),
                      for (final p in poets)
                        DropdownMenuItem<int?>(value: p.id, child: Text(localPoet(p.id, p.nickname))),
                    ],
                    onChanged: (v) {
                      setState(() => _poetId = v);
                      if (_term != null) _run();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_offline)
            Container(
              width: double.infinity,
              color: c.goldLight,
              padding: const EdgeInsets.all(8),
              child: Text(context.l10n.offlineResults, textAlign: TextAlign.center),
            ),
          if (_term != null && !_loading && _hits.isEmpty)
            Padding(padding: EdgeInsets.all(32), child: Text(context.l10n.nothingFound)),
          if (_hits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                // Offline we only know this page's matches; say so instead of a precise-looking number.
                context.l10n.resultCount(
                  '${localDigits(_totalKnown ? _total : _hits.length)}${!_totalKnown && _hasMore ? '+' : ''}',
                ),
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _hits.length + 1,
              itemBuilder: (context, i) {
                if (i == _hits.length) {
                  if (_loading) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!_hasMore) return const SizedBox(height: 24);
                  return Center(
                    child: TextButton(onPressed: () => _run(more: true), child: Text(context.l10n.moreResults)),
                  );
                }
                final h = _hits[i];
                return ListTile(
                  key: ValueKey('hit-${h.poemId}'),
                  title: Text(h.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(localPath('${h.poetName} » ${h.poemTitle}'), style: TextStyle(color: c.muted)),
                  trailing: h.local ? Icon(Icons.offline_pin, color: c.gold, size: 18) : null,
                  onTap: () => context.push('/poem/${h.poemId}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
