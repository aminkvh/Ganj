import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/poet.dart';
import '../../widgets/poet_portrait.dart';
import '../../l10n/l10n.dart';
import '../../core/text/content_en.dart';

String poetYears(L10n l, Poet p) {
  final b = p.birthYear, d = p.deathYear;
  if (b != null && d != null) return '${localDigits(b)} – ${localDigits(d)}';
  if (d != null) return l.diedYear(localDigits(d));
  return '';
}

class PoetTile extends StatelessWidget {
  const PoetTile({super.key, required this.poet});

  final Poet poet;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return InkWell(
      key: ValueKey('poet-${poet.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/poet/${poet.id}'),
      child: SizedBox(
        width: 110,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PoetPortrait(url: poet.imageAbsoluteUrl),
              const SizedBox(height: 6),
              Text(
                localPoet(poet.id, poet.nickname),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w500, color: c.ink),
              ),
              Text(poetYears(context.l10n, poet), style: TextStyle(fontSize: 11, color: c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class PoetGrid extends StatelessWidget {
  const PoetGrid({super.key, required this.poets, this.header, this.footer});

  final List<Poet> poets;

  /// Shown above / below the poets, scrolling with them.
  final Widget? header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      if (header != null) SliverToBoxAdapter(child: header),
      SliverPadding(
        padding: const EdgeInsets.all(12),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisExtent: 190),
          itemCount: poets.length,
          itemBuilder: (_, i) => PoetTile(poet: poets[i]),
        ),
      ),
      if (footer != null) SliverToBoxAdapter(child: footer),
    ],
  );
}
