import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/ganj_colors.dart';
import '../data/api/dto/cat.dart';
import '../core/text/content_en.dart';

Widget _constrain(Widget child) => Center(
  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 752), child: child),
);

class CatTile extends StatelessWidget {
  const CatTile({super.key, required this.cat});

  final CatRef cat;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return _constrain(
      ListTile(
        leading: Icon(Icons.menu_book_outlined, color: c.gold),
        title: Text(localTitle(cat.title)),
        trailing: Icon(Icons.chevron_right, color: c.muted), // mirrors in RTL → points forward
        onTap: () => context.push('/cat/${cat.id}'),
      ),
    );
  }
}

class PoemTile extends StatelessWidget {
  const PoemTile({super.key, required this.poem});

  final PoemRef poem;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return _constrain(
      ListTile(
        title: Text(localTitle(poem.title)),
        subtitle: poem.excerpt.isEmpty
            ? null
            : Text(
                poem.excerpt,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted),
              ),
        onTap: () => context.push('/poem/${poem.id}'),
      ),
    );
  }
}

/// Sub-categories then poems of [cat], lazily built.
List<Widget> catContentSlivers(Cat cat) => [
  if (cat.children.isNotEmpty)
    SliverList.builder(
      itemCount: cat.children.length,
      itemBuilder: (_, i) => CatTile(cat: cat.children[i]),
    ),
  if (cat.poems.isNotEmpty)
    SliverList.builder(
      itemCount: cat.poems.length,
      itemBuilder: (_, i) => PoemTile(poem: cat.poems[i]),
    ),
  const SliverToBoxAdapter(child: SizedBox(height: 24)),
];
