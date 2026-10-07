import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/net/api_client.dart';
import '../../../core/text/jalali.dart';
import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../data/api/dto/extras.dart';
import '../../../data/api/dto/poem.dart';
import '../../../data/api/ganjoor_api.dart';
import '../../../data/providers.dart';
import '../../../widgets/external_link.dart';
import '../../../widgets/gold_card.dart';
import '../../../l10n/l10n.dart';
import '../../../core/text/content_en.dart';
import '../../../core/net/disk_image.dart';

/// Collapsible section that loads its list only when first opened.
class LazyPanel<T> extends StatefulWidget {
  const LazyPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.load,
    required this.itemBuilder,
    this.emptyText,
  });

  final String title;
  final IconData icon;
  final Future<List<T>> Function() load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String? emptyText;

  @override
  State<LazyPanel<T>> createState() => _LazyPanelState<T>();
}

class _LazyPanelState<T> extends State<LazyPanel<T>> {
  Future<List<T>>? _future;

  void _reload() {
    final f = widget.load();
    setState(() {
      _future = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return GoldCard(
      color: c.inner,
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(widget.icon, color: c.gold),
        title: Text(widget.title),
        onExpansionChanged: (open) {
          if (open && _future == null) _reload();
        },
        children: [
          if (_future != null)
            FutureBuilder<List<T>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(context.l10n.notLoaded, style: TextStyle(color: c.muted)),
                        TextButton(onPressed: _reload, child: Text(context.l10n.retry)),
                      ],
                    ),
                  );
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(widget.emptyText ?? context.l10n.nothingHere, style: TextStyle(color: c.muted)),
                  );
                }
                return Column(children: [for (final i in items) widget.itemBuilder(context, i)]);
              },
            ),
        ],
      ),
    );
  }
}

String _faDate(DateTime? d) => d == null ? '' : faDate(d);

/// All extra sections of a poem page; each fetches its own lean endpoint lazily.
class PoemExtras extends ConsumerWidget {
  const PoemExtras({super.key, required this.poem});

  final Poem poem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read lazily: the API is only needed once a panel is opened.
    GanjoorApi api() => ref.read(ganjoorApiProvider);
    final c = context.ganj;
    final id = poem.id;
    return Column(
      children: [
        LazyPanel<Related>(
          key: const ValueKey('panel-related'),
          title: context.l10n.relatedPanel,
          icon: Icons.compare_arrows,
          load: () => api().related(id, 0),
          itemBuilder: (context, r) => ListTile(
            leading: CircleAvatar(
              backgroundColor: c.goldLight,
              backgroundImage: r.poetImageUrl.isEmpty ? null : DiskImage('$kApiBase${r.poetImageUrl}'),
              onBackgroundImageError: r.poetImageUrl.isEmpty ? null : (_, _) {},
            ),
            title: Text(localPath(r.fullTitle), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              r.excerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted),
            ),
            onTap: () => context.push('/url?u=${Uri.encodeComponent(r.fullUrl)}'),
          ),
        ),
        LazyPanel<Quoted>(
          key: const ValueKey('panel-quoted'),
          title: context.l10n.quotedPanel,
          icon: Icons.format_quote,
          load: () => api().quoteds(id),
          itemBuilder: (context, q) => ListTile(
            title: Text([q.relatedVerse1, q.relatedVerse2].where((s) => s.isNotEmpty).join(' / ')),
            subtitle: Text(localPath(q.fullTitle), style: TextStyle(color: c.muted)),
            onTap: () => q.relatedPoemId != null
                ? context.push('/poem/${q.relatedPoemId}')
                : context.push('/url?u=${Uri.encodeComponent(q.fullUrl)}'),
          ),
        ),
        LazyPanel<PoemImage>(
          key: const ValueKey('panel-images'),
          title: context.l10n.imagesPanel,
          icon: Icons.image_outlined,
          load: () => api().images(id),
          itemBuilder: (context, im) => ListTile(
            leading: SizedBox(
              width: 48,
              height: 64,
              child: Image(
                image: DiskImage(im.thumb),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(Icons.image_not_supported, color: c.muted),
              ),
            ),
            title: Text(im.alt, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Icon(Icons.open_in_new, color: c.muted, size: 18),
            onTap: () => openExternal(context, im.target),
          ),
        ),
        LazyPanel<Song>(
          key: const ValueKey('panel-songs'),
          title: context.l10n.songsPanel,
          icon: Icons.music_note_outlined,
          load: () => api().songs(id),
          itemBuilder: (context, s) => ListTile(
            leading: Icon(Icons.music_note, color: c.brandRed),
            title: Text(s.artist),
            subtitle: Text([s.track, s.album].where((x) => x.isNotEmpty).join(' — '), style: TextStyle(color: c.muted)),
            trailing: Icon(Icons.open_in_new, color: c.muted, size: 18),
            onTap: () => openExternal(context, s.url),
          ),
        ),
        LazyPanel<Comment>(
          key: const ValueKey('panel-comments'),
          title: context.l10n.commentsPanel,
          icon: Icons.forum_outlined,
          load: () => api().comments(id),
          itemBuilder: (context, cm) => _CommentTile(comment: cm),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, this.depth = 0});

  final Comment comment;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16.0 + depth * 20, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                comment.author,
                style: TextStyle(fontWeight: FontWeight.w700, color: c.lapis),
              ),
              const SizedBox(width: 8),
              Text(_faDate(comment.date), style: TextStyle(color: c.muted, fontSize: 11)),
              if (comment.coupletIndex >= 0) ...[
                const SizedBox(width: 8),
                Text(
                  context.l10n.beytN(localDigits(comment.coupletIndex + 1)),
                  style: TextStyle(color: c.gold, fontSize: 11),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SelectionArea(child: Text(comment.text, style: const TextStyle(height: 1.8))),
          for (final r in comment.replies) _CommentTile(comment: r, depth: depth + 1),
          if (depth == 0) Divider(color: c.goldLight),
        ],
      ),
    );
  }
}
