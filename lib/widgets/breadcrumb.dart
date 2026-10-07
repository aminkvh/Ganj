import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/ganj_colors.dart';
import '../data/api/dto/cat.dart';
import '../core/text/content_en.dart';

class Crumb {
  const Crumb(this.title, this.route);

  final String title;
  final String? route;
}

String _routeFor(PoetCat pc, int catId) => catId == pc.poet.rootCatId ? '/poet/${pc.poet.id}' : '/cat/$catId';

List<Crumb> crumbsFor(PoetCat pc, {required bool includeSelf}) => [
  for (final a in pc.cat.ancestors) Crumb(a.title, _routeFor(pc, a.id)),
  if (includeSelf) Crumb(pc.cat.title, _routeFor(pc, pc.cat.id)),
];

class Breadcrumb extends StatelessWidget {
  const Breadcrumb(this.crumbs, {super.key});

  final List<Crumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0) Text(' » ', style: TextStyle(color: c.muted)),
          InkWell(
            onTap: crumbs[i].route == null ? null : () => context.push(crumbs[i].route!),
            child: Text(
              localTitle(crumbs[i].title),
              style: TextStyle(color: crumbs[i].route == null ? c.muted : c.lapis),
            ),
          ),
        ],
      ],
    );
  }
}
