import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/content_en.dart';
import '../../core/theme/ganj_colors.dart';
import '../../core/theme/ganj_theme.dart';
import '../../data/api/dto/semantic.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';

/// Results of Ganjoor's search by meaning: each poem with the verses that matched best.
/// Opening one jumps to the matching beyt and reports the click to Ganjoor, like its site.
class SemanticResults extends ConsumerWidget {
  const SemanticResults({super.key, required this.future, required this.global, required this.onSearchAll});

  final Future<SemanticResult> future;

  /// True when the poet/book guess was turned off.
  final bool global;
  final VoidCallback onSearchAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    final l = context.l10n;
    return FutureBuilder<SemanticResult>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          final offline = e is DioException && e.response == null;
          return _Message(offline ? l.semanticOffline : l.semanticResting);
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final r = snap.data!;
        if (r.results.isEmpty) return _Message(l.nothingFound);
        final scope = [?r.detectedPoet, ?r.detectedCategory].join(' » ');
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (scope.isNotEmpty && !global)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(l.semanticScope(localPath(scope)), style: TextStyle(color: c.muted)),
                    TextButton(
                      key: const ValueKey('semantic-global'),
                      onPressed: onSearchAll,
                      child: Text(l.semanticGlobal),
                    ),
                  ],
                ),
              ),
            for (var i = 0; i < r.results.length; i++) _Hit(hit: r.results[i], rank: i + 1, logId: r.logId),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l.semanticCredit,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.gold, fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Hit extends ConsumerWidget {
  const _Hit({required this.hit, required this.rank, required this.logId});

  final SemanticHit hit;
  final int rank;
  final int? logId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ganj;
    return InkWell(
      key: ValueKey('semantic-${hit.poemId}'),
      onTap: () {
        final id = logId;
        if (id != null) ref.read(ganjoorApiProvider).semanticClick(logId: id, poemId: hit.poemId, rank: rank);
        final v = hit.verses.isEmpty ? '' : '?v=${hit.verses.first.vOrder}';
        context.push('/poem/${hit.poemId}$v');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              localPath(hit.fullTitle),
              style: TextStyle(color: c.lapis, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            for (final v in hit.verses)
              Text(v.text, textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: verseStyle(c, 0.9)),
            const Divider(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Text(text, textAlign: TextAlign.center),
  );
}
