import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/extras.dart';
import '../../data/providers.dart';
import '../../widgets/error_retry.dart';
import '../../l10n/l10n.dart';
import '../../core/text/content_en.dart';

/// Poems in a metre (and optionally a rhyme), across all poets, paged.
class SimilarScreen extends ConsumerStatefulWidget {
  const SimilarScreen({super.key, required this.metre, this.rhyme});

  final String metre;
  final String? rhyme;

  @override
  ConsumerState<SimilarScreen> createState() => _SimilarScreenState();
}

class _SimilarScreenState extends ConsumerState<SimilarScreen> {
  final _poems = <PoemHit>[];
  int _page = 0;
  int _total = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await ref.read(ganjoorApiProvider).similar(metre: widget.metre, rhyme: widget.rhyme, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _poems.addAll(r.poems);
        _page++;
        _total = r.total;
        _hasMore = r.hasNext;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    if (_failed && _poems.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: ErrorRetry(onRetry: _more),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.rhyme == null ? context.l10n.sameMetre : context.l10n.sameMetreRhyme)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              [
                widget.metre,
                if (widget.rhyme != null) context.l10n.rhymeIs(widget.rhyme!),
                context.l10n.poemCount(localDigits(_total)),
              ].join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _poems.length + 1,
              itemBuilder: (_, i) {
                if (i == _poems.length) {
                  if (_loading) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (!_hasMore) return const SizedBox(height: 24);
                  return Center(
                    child: TextButton(
                      onPressed: _more,
                      child: Text(_failed ? context.l10n.moreResultsFailed : context.l10n.moreResults),
                    ),
                  );
                }
                final p = _poems[i];
                return ListTile(
                  title: Text(p.excerpt.isEmpty ? p.title : p.excerpt, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(localPath(p.fullTitle), style: TextStyle(color: c.muted)),
                  onTap: () => context.push('/poem/${p.id}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
