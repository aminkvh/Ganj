import 'package:flutter/material.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../l10n/l10n.dart';
import '../data/models.dart';
import 'sh_style.dart';

/// Who someone is, at a glance — shown when a mouse rests on them (network, trees, river).
class PersonHoverCard extends StatelessWidget {
  const PersonHoverCard({super.key, required this.world, required this.id});

  final ShWorld world;
  final int id;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final l = context.l10n;
    final p = world.people[id];
    if (p == null) return const SizedBox.shrink();
    final first = world.firstSection(id);
    final tint = first == null ? c.borderGold : ageTint(context, world.ageOfSection(first).index);
    final ties = world.edgesOf(id).length;
    return Material(
      color: c.paper,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: tint, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.name,
                style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              if (p.en != null) Text(p.en!, style: TextStyle(color: c.muted, fontSize: 12.5)),
              if (first != null)
                Text(ageName(context, world.ageOfSection(first)), style: TextStyle(color: tint, fontSize: 12)),
              if (p.description case final d? when d.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    d,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.ink, fontSize: 12.5, height: 1.6),
                  ),
                ),
              if (first != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 240,
                    child: PresenceBar(world: world, person: id, height: 5),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [
                    if (world.presence[id] case final s?) l.shSections(localDigits(s.length)),
                    l.shTiesCount(localDigits(ties)),
                  ].join(' · '),
                  style: TextStyle(color: c.muted, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fades and grows in slightly as it appears.
class FadeInCard extends StatelessWidget {
  const FadeInCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    builder: (_, t, child) => Opacity(
      opacity: t,
      child: Transform.scale(scale: 0.96 + 0.04 * t, alignment: AlignmentDirectional.topStart, child: child),
    ),
    child: child,
  );
}

/// Shows [PersonHoverCard] when a mouse rests on [child]; nothing changes on touch screens.
class PersonHover extends StatelessWidget {
  const PersonHover({super.key, required this.world, required this.id, required this.child});

  final ShWorld world;
  final int id;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    richMessage: WidgetSpan(
      child: PersonHoverCard(world: world, id: id),
    ),
    decoration: const BoxDecoration(color: Colors.transparent),
    padding: EdgeInsets.zero,
    waitDuration: const Duration(milliseconds: 350),
    triggerMode: TooltipTriggerMode.manual,
    excludeFromSemantics: true,
    child: child,
  );
}
