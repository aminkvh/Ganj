import 'package:flutter/material.dart';

import '../../../core/text/persian_normalize.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../l10n/l10n.dart';
import '../data/models.dart';
import 'person_sheet.dart';
import 'sh_style.dart';
import 'story_card.dart';

/// The stories in order: a spine per age (in its tint), reigns as nodes on it, story cards
/// under each reign. A bar on top shows the four ages and jumps between them.
class TimelineVertical extends StatefulWidget {
  const TimelineVertical({super.key, required this.world, this.section});

  final ShWorld world;

  /// A story order to bring into view (from a person's presence strip).
  final int? section;

  @override
  State<TimelineVertical> createState() => _TimelineVerticalState();
}

class _TimelineVerticalState extends State<TimelineVertical> {
  late final _ageKeys = [for (final _ in widget.world.ages) GlobalKey()];
  late final _storyKeys = {for (final s in widget.world.stories) s.id: GlobalKey()};
  late final _reignKeys = {
    for (final a in widget.world.ages)
      for (final r in a.reigns) r: GlobalKey(),
  };
  final _scroll = ScrollController();
  int _current = 0;

  ShWorld get w => widget.world;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_track);
    if (widget.section != null) WidgetsBinding.instance.addPostFrameCallback((_) => _focus(widget.section!));
  }

  @override
  void didUpdateWidget(TimelineVertical old) {
    super.didUpdateWidget(old);
    if (widget.section != null && widget.section != old.section) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus(widget.section!));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  ShStory? _storyAt(int section) {
    for (final s in w.stories) {
      if (s.sections.contains(section)) return s;
    }
    for (final s in w.stories) {
      if (s.from <= section && section <= s.to) return s;
    }
    return null;
  }

  void _focus(int section) {
    final story = _storyAt(section);
    final key = story != null
        ? _storyKeys[story.id]
        : _reignKeys.entries.where((e) => e.key.from <= section && section <= e.key.to).firstOrNull?.value;
    final ctx = (key ?? _ageKeys[w.ageOfSection(section).index]).currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.1, duration: const Duration(milliseconds: 300));
  }

  void _jump(int age) {
    final ctx = _ageKeys[age].currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350));
  }

  /// Which age is at the top of the view, for the age bar.
  void _track() {
    for (var i = w.ages.length - 1; i >= 0; i--) {
      final box = _ageKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final viewport = context.findRenderObject() as RenderBox?;
      final y = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (y <= 80) {
        if (_current != i) setState(() => _current = i);
        return;
      }
    }
    if (_current != 0) setState(() => _current = 0);
  }

  @override
  Widget build(BuildContext context) {
    final focusStory = widget.section == null ? null : _storyAt(widget.section!);
    return Column(
      children: [
        _AgeBar(world: w, current: _current, onJump: _jump),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final a in w.ages)
                      _AgeBlock(
                        key: _ageKeys[a.index],
                        world: w,
                        age: a,
                        storyKeys: _storyKeys,
                        reignKeys: _reignKeys,
                        focusStory: focusStory?.id,
                      ),
                    const ShCredit(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AgeBar extends StatelessWidget {
  const _AgeBar({required this.world, required this.current, required this.onJump});

  final ShWorld world;
  final int current;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (final a in world.ages)
            Expanded(
              flex: a.to - a.from + 1 + 4, // room for a name even for short ages
              child: InkWell(
                key: ValueKey('age-bar-${a.id}'),
                onTap: () => onJump(a.index),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: current == a.index ? 8 : 5,
                        decoration: BoxDecoration(
                          color: ageTint(context, a.index).withValues(alpha: current == a.index ? 1 : 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        ageName(context, a),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: current == a.index ? ageTint(context, a.index) : c.muted,
                          fontWeight: current == a.index ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgeBlock extends StatelessWidget {
  const _AgeBlock({
    super.key,
    required this.world,
    required this.age,
    required this.storyKeys,
    required this.reignKeys,
    this.focusStory,
  });

  final ShWorld world;
  final ShAge age;
  final Map<String, GlobalKey> storyKeys;
  final Map<ShReign, GlobalKey> reignKeys;
  final String? focusStory;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final tint = ageTint(context, age.index);
    final placed = <String>{};
    final rows = <Widget>[];
    for (final r in age.reigns) {
      rows.add(_ReignNode(key: reignKeys[r], world: world, reign: r, tint: tint));
      for (final s in age.stories) {
        if (s.from >= r.from && s.from <= r.to && placed.add(s.id)) {
          rows.add(
            KeyedSubtree(
              key: ValueKey('story-${s.id}'),
              child: StoryCard(key: storyKeys[s.id], world: world, story: s, highlight: s.id == focusStory),
            ),
          );
        }
      }
    }
    for (final s in age.stories) {
      if (placed.add(s.id)) {
        rows.add(
          KeyedSubtree(
            key: ValueKey('story-${s.id}'),
            child: StoryCard(key: storyKeys[s.id], world: world, story: s, highlight: s.id == focusStory),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: ValueKey('age-header-${age.id}'),
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(ageName(context, age), style: nastaliqOf(context, 26).copyWith(color: tint)),
              ),
              Text(
                context.l10n.shSections(localDigits(age.to - age.from + 1)),
                style: TextStyle(color: c.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsetsDirectional.only(start: 6),
          padding: const EdgeInsetsDirectional.only(start: 16),
          decoration: BoxDecoration(
            border: BorderDirectional(start: BorderSide(color: tint.withValues(alpha: 0.6), width: 2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
        ),
      ],
    );
  }
}

class _ReignNode extends StatelessWidget {
  const _ReignNode({super.key, required this.world, required this.reign, required this.tint});

  final ShWorld world;
  final ShReign reign;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final king = reign.king;
    final n = reign.to - reign.from + 1;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          Transform.translate(
            offset: Offset(Directionality.of(context) == TextDirection.rtl ? 22 : -22, 0),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: c.page,
                shape: BoxShape.circle,
                border: Border.all(color: tint, width: 2),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: king == null || !world.people.containsKey(king) ? null : () => openPerson(context, king),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: isEn(context) ? reign.en : reign.fa,
                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                    if (n > 1)
                      TextSpan(
                        text: '  ·  ${context.l10n.shSections(localDigits(n))}',
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
