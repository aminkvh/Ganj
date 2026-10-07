import 'package:flutter/material.dart';

import '../../../core/text/labeled_text.dart';
import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../data/api/dto/poem.dart';
import '../../../widgets/ai_badge.dart';
import '../couplets.dart';
import '../../../l10n/l10n.dart';

/// One couplet, laid out like ganjoor.net: hemistichs meet at the centre
/// when [wide], stack centred otherwise. Separators are drawn by the parent.
class BeytView extends StatelessWidget {
  const BeytView({
    super.key,
    required this.couplet,
    required this.wide,
    required this.scale,
    this.showMeaning = false,
    this.highlightVOrders = const {},
    this.onMenu,
    this.hasNote = false,
    this.bookmarked = false,
  });

  final Couplet couplet;
  final bool wide;
  final double scale;
  final bool showMeaning;
  final Set<int> highlightVOrders;

  /// Opens the beyt's actions: with no position after a tap (phones), at the pointer after a
  /// right-click or the hover ⋮ (computers). Long-press / drag stay free for selecting text.
  final ValueChanged<Offset?>? onMenu;
  final bool hasNote;
  final bool bookmarked;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final style = verseStyle(c, scale);
    final verses = couplet.verses;

    Widget line(Verse v, TextAlign align, [TextStyle? s]) => Container(
      decoration: highlightVOrders.contains(v.vOrder)
          ? BoxDecoration(color: c.goldLight, borderRadius: BorderRadius.circular(6))
          : null,
      child: Text(v.text, textAlign: align, style: s ?? style),
    );

    // Wide hemistichs stay on one line like ganjoor.net, shrinking slightly if needed.
    Widget half(Verse v, Alignment towardCentre) => Container(
      decoration: highlightVOrders.contains(v.vOrder)
          ? BoxDecoration(color: c.goldLight, borderRadius: BorderRadius.circular(6))
          : null,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: towardCentre,
        child: Text(v.text, maxLines: 1, softWrap: false, style: style),
      ),
    );

    final Widget body = switch (couplet.kind) {
      // Two hemistichs side by side; a couplet with more lines falls back to the stacked layout.
      CoupletKind.beyt when wide && verses.length <= 2 => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // RTL: first child is on the right; both halves hug the centre.
          Expanded(flex: 45, child: half(verses[0], Alignment.centerLeft)),
          const Spacer(flex: 10),
          Expanded(flex: 45, child: verses.length > 1 ? half(verses[1], Alignment.centerRight) : const SizedBox()),
        ],
      ),
      CoupletKind.beyt || CoupletKind.band => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final v in verses) line(v, TextAlign.center)],
      ),
      CoupletKind.single => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final v in verses) line(v, TextAlign.center)],
      ),
      CoupletKind.comment => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in verses)
            line(v, TextAlign.center, style.copyWith(color: c.muted, fontSize: style.fontSize! * 0.85)),
        ],
      ),
      CoupletKind.paragraph => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final v in verses) line(v, TextAlign.justify, style.copyWith(height: 1.9))],
      ),
    };

    final language = verseLanguageLabel(context.l10n, verses.first.languageId);
    final summary = couplet.summary;
    // Screen readers get one node per beyt: language, hemistichs in order, the meaning when shown,
    // and the marks a sighted reader sees (bookmark, note).
    final spoken = [
      ?language,
      couplet.text,
      if (showMeaning && summary != null) context.l10n.meaningPrefix(summary.text),
      if (bookmarked) context.l10n.bookmarked,
      if (hasNote) context.l10n.hasNote,
    ].join('\n');
    // Verses read right to left even when the interface is in English.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Semantics(
        container: true,
        label: spoken,
        excludeSemantics: true,
        onTapHint: context.l10n.beytOptions,
        onTap: onMenu == null ? null : () => onMenu!(null),
        child: _BeytGestures(
          onMenu: onMenu,
          tooltip: context.l10n.beytOptions,
          moreKey: ValueKey('beyt-more-${couplet.index}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasNote || bookmarked)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (bookmarked) Icon(Icons.bookmark, size: 14, color: c.brandRed),
                        if (hasNote) Icon(Icons.sticky_note_2, size: 14, color: c.gold),
                      ],
                    ),
                  ),
                if (language != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.borderGold),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(language, style: TextStyle(fontSize: 11, color: c.muted)),
                    ),
                  ),
                body,
                if (showMeaning && summary != null) MeaningBox(summary: summary, scale: scale),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain-Persian meaning of a couplet (Ganjoor coupletSummary).
class MeaningBox extends StatelessWidget {
  const MeaningBox({super.key, required this.summary, this.scale = 1});

  final LabeledText summary;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.inner, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.isAi) const Padding(padding: EdgeInsets.only(bottom: 4), child: AiBadge()),
          Text(
            summary.text,
            style: TextStyle(fontSize: 14 * scale, height: 1.8, color: c.muted),
          ),
        ],
      ),
    );
  }
}

/// Phones: a tap opens the actions. Computers: right-click, or the ⋮ that fades in on hover.
class _BeytGestures extends StatefulWidget {
  const _BeytGestures({required this.onMenu, required this.tooltip, required this.moreKey, required this.child});

  final ValueChanged<Offset?>? onMenu;
  final String tooltip;
  final Key moreKey;
  final Widget child;

  @override
  State<_BeytGestures> createState() => _BeytGesturesState();
}

class _BeytGesturesState extends State<_BeytGestures> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final onMenu = widget.onMenu;
    if (onMenu == null) return widget.child;
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
      _ => false,
    };
    if (!desktop) {
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => onMenu(null), child: widget.child);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        child: Stack(
          children: [
            Padding(padding: const EdgeInsetsDirectional.only(end: 28), child: widget.child),
            PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Builder(
                    builder: (ctx) => IconButton(
                      key: widget.moreKey,
                      tooltip: widget.tooltip,
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      icon: Icon(Icons.more_vert, color: context.ganj.muted),
                      onPressed: () {
                        final box = ctx.findRenderObject()! as RenderBox;
                        onMenu(box.localToGlobal(box.size.center(Offset.zero)));
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
