import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../core/theme/ganj_theme.dart';
import '../../../l10n/l10n.dart';
import '../data/lifelines.dart';
import '../data/models.dart';
import 'person_hover.dart';
import 'person_picker.dart';
import 'person_sheet.dart';
import 'sh_style.dart';
import 'story_card.dart';

const _gutter = 124.0, _ageH = 22.0, _reignH = 28.0, _storyH = 63.0, _rowH = 28.0;
const _bandsH = _ageH + _reignH + _storyH;

/// The river: story order along the axis (right to left in Persian, like the book), the
/// ages behind, reigns and stories on top, and below them a lifeline for each chosen person —
/// where in the book they appear. Pick a person to light up their kin.
class TimelineRiver extends ConsumerStatefulWidget {
  const TimelineRiver({super.key, required this.world});

  final ShWorld world;

  @override
  ConsumerState<TimelineRiver> createState() => _TimelineRiverState();
}

class _TimelineRiverState extends ConsumerState<TimelineRiver> {
  double _col = 30;

  // Two-finger pinch, read from raw pointers: inside the sideways scroll a scale gesture
  // would lose the gesture arena to the scroll.
  final _fingers = <int, Offset>{};
  double? _pinchSpan, _pinchCol;

  void _finger(PointerEvent e) {
    if (e is PointerUpEvent || e is PointerCancelEvent) {
      _fingers.remove(e.pointer);
    } else {
      _fingers[e.pointer] = e.position;
    }
    if (_fingers.length != 2) {
      _pinchSpan = null;
      return;
    }
    final [a, b] = _fingers.values.toList();
    final span = (a.dx - b.dx).abs();
    if (_pinchSpan == null) {
      _pinchSpan = span;
      _pinchCol = _col;
    } else if (_pinchSpan! > 8) {
      setState(() => _col = (_pinchCol! * span / _pinchSpan!).clamp(14, 90));
    }
  }

  late final List<int> _people = _defaults();
  int? _selected;

  /// Under the mouse: a story order, and the lifeline's person when over one.
  int? _hoverSection, _hoverPerson;

  void _hover(int? section, [int? person]) {
    if (section == _hoverSection && person == _hoverPerson) return;
    setState(() {
      _hoverSection = section;
      _hoverPerson = person;
    });
  }

  /// What the mouse rests on, in words: the story order's title and what the person does there.
  String? _hoverText(BuildContext context) {
    final o = _hoverSection;
    if (o == null) return null;
    final l = context.l10n;
    final title = w.sections[o].title;
    final id = _hoverPerson;
    if (id == null) return title;
    final role = (w.presence[id] ?? const []).contains(o)
        ? l.shTakesPart
        : (w.passing[id] ?? const []).contains(o)
        ? l.shPassing
        : null;
    return [personName(context, w, id), ?role, title].join(' · ');
  }

  ShWorld get w => widget.world;

  /// The stories' protagonists, up to 18, in order of first appearance.
  List<int> _defaults() {
    // The leading figure of each curated story — Ganjoor's tags alone would pick up generic
    // names («شاپور», «قیصر») that recur across the whole book.
    final lead = <int>{for (final s in w.stories) ?s.people.where((p) => w.presence.containsKey(p)).firstOrNull};
    return lead.take(18).toList()..sort((a, b) => w.firstSection(a)!.compareTo(w.firstSection(b)!));
  }

  Set<int> get _lit {
    final s = _selected;
    if (s == null) return const {};
    return {
      s,
      for (final e in w.edgesOf(s))
        if (e.kind.isKin) e.other(s),
    };
  }

  Future<void> _add() async {
    final id = await pickPerson(context, w, where: (p) => w.presence.containsKey(p.id));
    if (id != null && !_people.contains(id)) setState(() => _people.add(id));
  }

  void _openStoryAt(int section) {
    final stories = [
      for (final s in w.stories)
        if (s.from <= section && section <= s.to) s,
    ]..sort((a, b) => (a.to - a.from).compareTo(b.to - b.from));
    if (stories.isEmpty) return;
    final hub = context;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: StoryCard(
          world: w,
          story: stories.first,
          onMap: ({story, place}) {
            Navigator.of(sheet).pop();
            showOnMap(hub, ref, story: story, place: place);
          },
        ),
      ),
    );
  }

  void _openReignAt(int section) {
    for (final a in w.ages) {
      for (final r in a.reigns) {
        if (r.from <= section && section <= r.to && r.king != null && w.people.containsKey(r.king)) {
          openPerson(context, r.king!);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.ganj;
    final n = w.sections.length;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final width = n * _col;
    final lit = _lit;
    final tints = [for (final a in w.ages) ageTint(context, a.index)];
    double xOf(int o) => (rtl ? n - 1 - o : o) * _col;
    int sectionAt(double x) => (rtl ? n - 1 - (x / _col).floor() : (x / _col).floor()).clamp(0, n - 1);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: Row(
            children: [
              // Mirrors itself in RTL: right to left in Persian, like the book.
              Icon(Icons.arrow_forward, size: 16, color: c.muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _hoverText(context) ?? l.shStoryOrder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _hoverSection == null ? c.muted : c.ink, fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: '−',
                icon: const Icon(Icons.zoom_out),
                onPressed: _col > 14 ? () => setState(() => _col = math.max(14, _col / 1.3)) : null,
              ),
              IconButton(
                tooltip: '+',
                icon: const Icon(Icons.zoom_in),
                onPressed: _col < 90 ? () => setState(() => _col = math.min(90, _col * 1.3)) : null,
              ),
              if (MediaQuery.sizeOf(context).width >= 520)
                TextButton.icon(icon: const Icon(Icons.person_add_alt), label: Text(l.shAddPerson), onPressed: _add)
              else
                IconButton(tooltip: l.shAddPerson, icon: const Icon(Icons.person_add_alt), onPressed: _add),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Names stay put while the river scrolls sideways.
                SizedBox(
                  width: _gutter,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: _bandsH),
                      for (final id in _people)
                        SizedBox(
                          key: ValueKey('lifeline-$id'),
                          height: _rowH,
                          child: PersonHover(
                            world: w,
                            id: id,
                            child: InkWell(
                              onTap: () => setState(() => _selected = _selected == id ? null : id),
                              onLongPress: () => openPerson(context, id),
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        personName(context, w, id),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: lit.isEmpty || lit.contains(id)
                                              ? c.ink
                                              : c.muted.withValues(alpha: 0.5),
                                          fontWeight: id == _selected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => setState(() {
                                        _people.remove(id);
                                        if (_selected == id) _selected = null;
                                      }),
                                      child: Icon(Icons.close, size: 14, color: c.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Listener(
                      onPointerDown: _finger,
                      onPointerMove: _finger,
                      onPointerUp: _finger,
                      onPointerCancel: _finger,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MouseRegion(
                            onHover: (e) => _hover(sectionAt(e.localPosition.dx)),
                            onExit: (_) => _hover(null),
                            child: GestureDetector(
                              onTapUp: (d) {
                                final o = sectionAt(d.localPosition.dx);
                                d.localPosition.dy < _ageH + _reignH ? _openReignAt(o) : _openStoryAt(o);
                              },
                              child: CustomPaint(
                                size: Size(width, _bandsH),
                                painter: _BandsPainter(
                                  world: w,
                                  xOf: xOf,
                                  col: _col,
                                  tints: tints,
                                  english: isEn(context),
                                  ink: c.ink,
                                  muted: c.muted,
                                  paper: c.paper,
                                  line: c.borderGold,
                                  textDirection: Directionality.of(context),
                                ),
                              ),
                            ),
                          ),
                          for (final id in _people)
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              onHover: (e) => _hover(sectionAt(e.localPosition.dx), id),
                              onExit: (_) => _hover(null),
                              child: GestureDetector(
                                onTap: () => openPerson(context, id),
                                child: CustomPaint(
                                  size: Size(width, _rowH),
                                  painter: _LifelinePainter(
                                    hover: _hoverPerson == id ? _hoverSection : null,
                                    segments: lifelineSegments(w.presence[id] ?? const []),
                                    passing: w.passing[id] ?? const [],
                                    xOf: xOf,
                                    col: _col,
                                    tintOf: (o) => tints[w.ageOfSection(o).index],
                                    dim: lit.isNotEmpty && !lit.contains(id),
                                    grid: c.goldLight.withValues(alpha: 0.35),
                                    ageStarts: [for (final a in w.ages.skip(1)) a.from],
                                    rtl: rtl,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // What the marks on a lifeline are.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          child: Wrap(
            spacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (bar, text) in [(true, l.shTakesPart), (false, l.shPassing)])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bar
                        ? Container(
                            width: 18,
                            height: 8,
                            decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(4)),
                          )
                        : Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(color: c.muted.withValues(alpha: 0.5), shape: BoxShape.circle),
                          ),
                    const SizedBox(width: 6),
                    Text(text, style: TextStyle(color: c.muted, fontSize: 11.5)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BandsPainter extends CustomPainter {
  _BandsPainter({
    required this.world,
    required this.xOf,
    required this.col,
    required this.tints,
    required this.english,
    required this.ink,
    required this.muted,
    required this.paper,
    required this.line,
    required this.textDirection,
  });

  final ShWorld world;
  final double Function(int) xOf;
  final double col;
  final List<Color> tints;
  final bool english;
  final Color ink, muted, paper, line;
  final TextDirection textDirection;

  /// The span of story orders [from]..[to] on the canvas, whichever way the river runs.
  Rect _span(int from, int to, double top, double height) {
    final a = xOf(from), b = xOf(to);
    return Rect.fromLTWH(math.min(a, b), top, (to - from + 1) * col, height);
  }

  void _label(Canvas canvas, String text, Rect r, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, r.width - 4));
    if (tp.width < 12) return;
    tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final body = TextStyle(fontFamily: kBodyFont, fontSize: 11, color: ink);
    for (final a in world.ages) {
      final r = _span(a.from, a.to, 0, _ageH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(4)),
        Paint()..color = tints[a.index].withValues(alpha: 0.85),
      );
      _label(canvas, english ? a.en : a.fa, r, body.copyWith(color: paper, fontWeight: FontWeight.bold));
    }
    for (final a in world.ages) {
      for (final (i, rg) in a.reigns.indexed) {
        final r = _span(rg.from, rg.to, _ageH + 2, _reignH - 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(3)),
          Paint()..color = tints[a.index].withValues(alpha: i.isEven ? 0.18 : 0.30),
        );
        _label(canvas, english ? rg.en : rg.fa, r, body);
      }
    }
    // Stories in three lanes, placed greedily left to right: a story takes the first lane
    // where its bar and name fit; where none has room it keeps the bar and drops the name.
    const lanes = 3, laneH = _storyH / lanes;
    final ends = List<double>.filled(lanes, double.negativeInfinity);
    final style = body.copyWith(fontSize: 10.5);
    final placed = [for (final s in world.stories) (s, _span(s.from, s.to, 0, 0))]
      ..sort((a, b) => a.$2.left.compareTo(b.$2.left));
    for (final (s, span) in placed) {
      final tp = TextPainter(
        text: TextSpan(text: english ? s.en : s.fa, style: style),
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      final left = math.min(span.left, span.center.dx - tp.width / 2),
          right = math.max(span.right, span.center.dx + tp.width / 2);
      var lane = ends.indexWhere((e) => e + 6 <= left);
      final labelled = lane >= 0;
      if (!labelled) {
        lane = 0;
        for (var i = 1; i < lanes; i++) {
          if (ends[i] < ends[lane]) lane = i;
        }
      }
      ends[lane] = math.max(ends[lane], labelled ? right : span.right);
      final top = _ageH + _reignH + lane * laneH;
      final bar = Rect.fromLTWH(span.left + 1, top + laneH - 6, span.width - 2, 4);
      canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(2)), Paint()..color = tints[s.age]);
      if (labelled) tp.paint(canvas, Offset(span.center.dx - tp.width / 2, top + laneH - 7 - tp.height));
    }
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5), Paint()..color = line);
  }

  @override
  bool shouldRepaint(_BandsPainter old) => old.col != col || old.english != english || old.ink != ink;
}

class _LifelinePainter extends CustomPainter {
  _LifelinePainter({
    required this.hover,
    required this.segments,
    required this.passing,
    required this.xOf,
    required this.col,
    required this.tintOf,
    required this.dim,
    required this.grid,
    required this.ageStarts,
    required this.rtl,
  });

  /// The story order under the mouse on this row, if any.
  final int? hover;
  final List<(int, int)> segments;
  final List<int> passing;
  final double Function(int) xOf;
  final double col;
  final Color Function(int) tintOf;
  final bool dim;
  final Color grid;
  final List<int> ageStarts;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), Paint()..color = grid);
    if (hover case final o?) {
      canvas.drawRect(Rect.fromLTWH(xOf(o), 0, col, size.height), Paint()..color = tintOf(o).withValues(alpha: 0.16));
    }
    for (final s in ageStarts) {
      final x = rtl ? xOf(s) + col : xOf(s);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = grid);
    }
    final alpha = dim ? 0.18 : 1.0;
    for (final (from, to) in segments) {
      // One run may cross an age boundary: colour each section by its own age.
      for (var o = from; o <= to; o++) {
        final x = xOf(o);
        final round = Radius.circular(size.height * 0.22);
        final r = Rect.fromLTWH(x, mid - size.height * 0.22, col, size.height * 0.44);
        final leftEnd = rtl ? o == to : o == from, rightEnd = rtl ? o == from : o == to;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            r,
            topLeft: leftEnd ? round : Radius.zero,
            bottomLeft: leftEnd ? round : Radius.zero,
            topRight: rightEnd ? round : Radius.zero,
            bottomRight: rightEnd ? round : Radius.zero,
          ),
          Paint()..color = tintOf(o).withValues(alpha: alpha),
        );
      }
    }
    for (final o in passing) {
      canvas.drawCircle(Offset(xOf(o) + col / 2, mid), 3, Paint()..color = tintOf(o).withValues(alpha: 0.4 * alpha));
    }
  }

  @override
  bool shouldRepaint(_LifelinePainter old) =>
      old.col != col || old.dim != dim || old.segments != segments || old.hover != hover;
}
