import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../core/theme/ganj_theme.dart';
import '../../data/api/dto/poem.dart';
import '../../data/providers.dart';
import '../../data/user/user_repository.dart';
import '../../widgets/ai_badge.dart';
import '../../widgets/breadcrumb.dart';
import '../../widgets/error_retry.dart';
import '../../widgets/gold_card.dart';
import '../../widgets/ornament_separator.dart';
import '../player/player_controller.dart';
import '../player/recitation_list.dart';
import '../settings/settings_controller.dart';
import 'couplets.dart';
import 'widgets/beyt_view.dart';
import 'widgets/extras_panels.dart';
import '../../l10n/l10n.dart';
import '../../widgets/external_link.dart';
import '../translate/ensure_model.dart';
import '../translate/translator.dart';
import '../translate/translation_line.dart';
import '../../core/text/content_en.dart';
import '../tajik/tajik_text.dart';
import '../../widgets/home_button.dart';

class PoemScreen extends ConsumerStatefulWidget {
  const PoemScreen({super.key, required this.id, this.couplet, this.verse});

  final int id;

  /// Opens at this beyt (from a bookmark or note) instead of where the reader left off.
  final int? couplet;

  /// Open at the beyt holding this verse (vOrder), e.g. a semantic-search match.
  final int? verse;

  @override
  ConsumerState<PoemScreen> createState() => _PoemScreenState();
}

class _PoemScreenState extends ConsumerState<PoemScreen> with WidgetsBindingObserver {
  final _keys = <int, GlobalKey>{};
  final _findCtrl = TextEditingController();
  bool _finding = false;
  List<int> _hits = const []; // vOrders
  int _hit = 0;
  bool _scrollLocked = false;
  DateTime _userScrolledAt = DateTime(2000);

  // Machine translation shown under each beyt (on-device translators only).
  bool _translating = false;
  final _translations = <int, Future<String>>{};
  String? _translatedTo;

  // Device-only reader data for this poem.
  final _scroll = ScrollController();
  late final UserRepository _user;
  Poem? _poem;
  List<Couplet> _couplets = const [];

  /// The couplet at the top of the screen — what "where I left off" means, independent of
  /// font size, layout or meanings (a pixel offset would land on another beyt after those change).
  int _topCouplet = -1;
  int _scrollGeneration = 0;
  bool _userLoaded = false;
  bool _bookmarked = false;
  Set<int> _bookmarkedCouplets = const {};
  Map<int, String> _notes = const {};

  @override
  void initState() {
    super.initState();
    _user = ref.read(userRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS may kill a backgrounded app without disposing anything: save now.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) _saveVisit();
  }

  void _saveVisit({int? couplet}) {
    final p = _poem;
    if (p == null) return;
    if (couplet == null && mounted) _trackTopCouplet();
    _user
        .recordVisit(p.id, p.title, p.fullTitle, couplet: couplet ?? (_topCouplet >= 0 ? _topCouplet : null))
        .catchError((Object _) {}); // best effort: never crash on leaving
  }

  /// Finds the couplet whose row is at the top of the visible area.
  void _trackTopCouplet() {
    var best = -1;
    var bestTop = double.infinity;
    final viewport = _scroll.hasClients
        ? _scroll.position.context.notificationContext?.findRenderObject() as RenderBox?
        : null;
    final viewportTop = viewport != null && viewport.attached ? viewport.localToGlobal(Offset.zero).dy : kToolbarHeight;
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top + box.size.height > viewportTop + 24 && top < bestTop) {
        bestTop = top;
        best = e.key;
      }
    }
    if (best >= 0) _topCouplet = best;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveVisit();
    _findCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Loads bookmarks/notes and returns to where the reader left off.
  Future<void> _loadUser(Poem p) async {
    final bookmarked = await _user.isBookmarked(p.id);
    final couplets = await _user.bookmarkedCouplets(p.id);
    final notes = await _user.notesFor(p.id);
    final resume = widget.couplet ?? _coupletOfVerse(p, widget.verse) ?? await _user.lastCouplet(p.id);
    if (!mounted) return;
    if (resume != null) _topCouplet = resume;
    _saveVisit(couplet: resume); // the visit counts as soon as the poem is open
    setState(() {
      _bookmarked = bookmarked;
      _bookmarkedCouplets = couplets;
      _notes = notes;
    });
    final i = resume == null ? -1 : _couplets.indexWhere((c) => c.index == resume);
    if (i > 0) {
      _topCouplet = resume!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCouplet(_couplets, i, 0.05));
    }
  }

  Future<void> _toggleBookmark(Poem p, {int couplet = -1}) async {
    final on = await _user.toggleBookmark(p.id, p.title, p.fullTitle, couplet: couplet);
    final couplets = await _user.bookmarkedCouplets(p.id);
    if (!mounted) return;
    setState(() {
      if (couplet < 0) _bookmarked = on;
      _bookmarkedCouplets = couplets;
    });
  }

  Future<void> _editNote(Poem p, Couplet couplet) async {
    final ctrl = TextEditingController(text: _notes[couplet.index] ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.note),
        content: TextField(
          key: const ValueKey('note-field'),
          controller: ctrl,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
          decoration: InputDecoration(hintText: context.l10n.noteHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(context.l10n.save)),
        ],
      ),
    );
    if (text == null) return;
    await _user.setNote(p.id, couplet.index, text, p.title, p.fullTitle);
    final notes = await _user.notesFor(p.id);
    if (mounted) setState(() => _notes = notes);
  }

  GlobalKey _keyFor(int coupletIndex) => _keys.putIfAbsent(coupletIndex, GlobalKey.new);

  void _runFind(Poem poem, List<Couplet> couplets, String q) {
    final hits = q.trim().length < 2
        ? <int>[]
        : [
            for (final v in poem.verses)
              if (matchesQuery(v.text, q)) v.vOrder,
          ];
    setState(() {
      _hits = hits;
      _hit = 0;
    });
    _scrollToHit(couplets);
  }

  void _step(List<Couplet> couplets, int delta) {
    if (_hits.isEmpty) return;
    setState(() => _hit = (_hit + delta) % _hits.length);
    _scrollToHit(couplets);
  }

  void _scrollToHit(List<Couplet> couplets) {
    if (_hits.isEmpty) return;
    final target = _hits[_hit];
    final i = couplets.indexWhere((c) => c.verses.any((v) => v.vOrder == target));
    if (i >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCouplet(couplets, i, 0.3));
  }

  /// Brings couplet [i] into view. Couplets are built lazily, so when it isn't built yet we jump
  /// to an estimated offset (proportional to its index) and refine until it is, then align it.
  Future<void> _scrollToCouplet(List<Couplet> couplets, int i, double alignment) async {
    final gen = ++_scrollGeneration; // a newer jump (next find hit, next verse) cancels this one
    final indexOf = {for (var k = 0; k < couplets.length; k++) couplets[k].index: k};
    for (var attempt = 0; attempt < 16 && mounted && gen == _scrollGeneration; attempt++) {
      final ctx = _keyFor(couplets[i].index).currentContext;
      if (ctx != null) {
        if (!ctx.mounted) return;
        await Scrollable.ensureVisible(ctx, alignment: alignment, duration: const Duration(milliseconds: 250));
        return;
      }
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      // Couplets differ in height, so steer from the nearest built couplet using the
      // measured average height instead of a proportional guess over the whole poem.
      int? nearest;
      double nearestTop = 0, total = 0;
      var built = 0;
      for (final e in _keys.entries) {
        final box = e.value.currentContext?.findRenderObject() as RenderBox?;
        final k = indexOf[e.key];
        if (box == null || !box.attached || !box.hasSize || k == null) continue;
        built++;
        total += box.size.height;
        if (nearest == null || (k - i).abs() < (nearest - i).abs()) {
          nearest = k;
          nearestTop = box.localToGlobal(Offset.zero).dy;
        }
      }
      final target = nearest == null || built == 0
          ? pos.maxScrollExtent * (i + 0.5) / couplets.length
          : pos.pixels + nearestTop - kToolbarHeight + (i - nearest) * (total / built);
      _scroll.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Follow the recitation: scroll the playing couplet into view unless the
  /// reader scrolled in the last 4 s or locked auto-scroll.
  void _follow(List<Couplet> couplets, int vOrder) {
    if (_scrollLocked || DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 4)) return;
    final i = couplets.indexWhere((c) => c.verses.any((v) => v.vOrder == vOrder));
    if (i < 0) return;
    final ctx = _keyFor(couplets[i].index).currentContext;
    if (ctx == null) {
      _scrollToCouplet(couplets, i, 0.35); // not built yet (long poem)
      return;
    }
    final box = ctx.findRenderObject() as RenderBox?;
    final viewport = MediaQuery.sizeOf(context).height;
    final top = box?.localToGlobal(Offset.zero).dy ?? 0;
    if (top > 80 && top + (box?.size.height ?? 0) < viewport - 80) return; // already visible
    Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 300));
  }

  Future<void> _playFrom(Poem p, Couplet couplet) async {
    final player = ref.read(playerProvider.notifier);
    final st = ref.read(playerProvider);
    if (st.poem?.id != p.id || st.recitation == null) {
      final synced = p.recitations.where((r) => r.inSync);
      await player.play(p, synced.isNotEmpty ? synced.first : p.recitations.first);
    } else if (st.status == PlayerStatus.error) {
      await player.retry();
    }
    final ok = await player.seekToVOrder(couplet.verses.first.vOrder);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.lineNotRead)));
    }
  }

  void _openSimilar(Poem p, {required bool withRhyme}) => context.push(
    '/similar?metre=${Uri.encodeComponent(p.metre!)}'
    '${withRhyme && p.rhyme != null ? '&rhyme=${Uri.encodeComponent(p.rhyme!)}' : ''}',
  );

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.copied)));
  }

  void _share(String text) => SharePlus.instance.share(ShareParams(text: text));

  String _withSource(Poem p, String body) => '$body\n\n${p.fullTitle}\n${p.siteUrl}';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(poemProvider(widget.id));
    final settings = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final poem = async.value;
    if (poem != null && (!_userLoaded || _poem?.id != poem.id)) {
      _poem = poem;
      _userLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUser(poem));
    }
    final couplets = poem == null ? const <Couplet>[] : groupCouplets(poem.verses);
    _couplets = couplets;
    final wide = MediaQuery.sizeOf(context).width >= 950;
    final playingVOrder = ref.watch(playerProvider.select((p) => p.poem?.id == widget.id ? p.currentVOrder : null));
    ref.listen(playerProvider.select((p) => p.poem?.id == widget.id ? p.currentVOrder : null), (_, v) {
      if (v != null) WidgetsBinding.instance.addPostFrameCallback((_) => _follow(couplets, v));
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(localTitle(poem?.title ?? ''), overflow: TextOverflow.ellipsis),
        actions: [
          const HomeButton(),
          if (poem != null)
            IconButton(
              tooltip: context.l10n.bookmark,
              icon: Icon(_bookmarked ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () => _toggleBookmark(poem),
            ),
          IconButton(
            tooltip: context.l10n.findInPoem,
            icon: const Icon(Icons.search),
            onPressed: () => setState(() {
              _finding = !_finding;
              if (!_finding) {
                _findCtrl.clear();
                _hits = const [];
              }
            }),
          ),
          IconButton(
            tooltip: context.l10n.translate,
            isSelected: _translating,
            icon: const Icon(Icons.translate),
            onPressed: poem == null ? null : () => _toggleTranslation(couplets),
          ),
          IconButton(
            tooltip: context.l10n.meanings,
            isSelected: settings.showMeaning,
            icon: const Icon(Icons.lightbulb_outline),
            selectedIcon: const Icon(Icons.lightbulb),
            onPressed: ctrl.toggleMeaning,
          ),
          PopupMenuButton<String>(
            tooltip: context.l10n.more,
            onSelected: (v) {
              switch (v) {
                case 'zoomIn':
                  ctrl.zoom(0.1);
                case 'zoomOut':
                  ctrl.zoom(-0.1);
                case 'theme':
                  ctrl.toggleTheme(Theme.of(context).brightness);
                case 'copy':
                  if (poem != null) _copy(_withSource(poem, couplets.map((c) => c.text).join('\n')));
                case 'share':
                  if (poem != null) _share(_withSource(poem, couplets.map((c) => c.text).join('\n')));
                case 'tajik':
                  ctrl.setShowTajik(!settings.showTajik);
                case 'site':
                  if (poem != null) {
                    openExternal(context, ganjoorSiteUrl(poem.fullUrl), launcher: ref.read(urlLauncherProvider));
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'zoomIn', child: Text(context.l10n.zoomIn)),
              PopupMenuItem(value: 'zoomOut', child: Text(context.l10n.zoomOut)),
              PopupMenuItem(value: 'theme', child: Text(context.l10n.switchTheme)),
              PopupMenuItem(value: 'copy', child: Text(context.l10n.copyPoem)),
              PopupMenuItem(value: 'share', child: Text(context.l10n.share)),
              CheckedPopupMenuItem(value: 'tajik', checked: settings.showTajik, child: Text(context.l10n.tajikScript)),
              PopupMenuItem(value: 'site', child: Text(context.l10n.openOnGanjoor)),
            ],
          ),
        ],
        bottom: _finding && poem != null
            ? PreferredSize(preferredSize: const Size.fromHeight(56), child: _findBar(poem, couplets))
            : null,
      ),
      body: async.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(poemProvider(widget.id))),
        data: (p) => _body(p, couplets, settings, wide, playingVOrder),
      ),
      bottomNavigationBar: poem == null ? null : _navBar(poem),
    );
  }

  Widget _findBar(Poem poem, List<Couplet> couplets) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('find-field'),
            controller: _findCtrl,
            autofocus: true,
            decoration: InputDecoration(hintText: context.l10n.findInThisPoem, isDense: true),
            onChanged: (q) => _runFind(poem, couplets, q),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _hits.isEmpty ? '' : context.l10n.nOfM(localDigits(_hit + 1), localDigits(_hits.length)),
          key: const ValueKey('find-count'),
        ),
        IconButton(icon: const Icon(Icons.keyboard_arrow_up), onPressed: () => _step(couplets, -1)),
        IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => _step(couplets, 1)),
      ],
    ),
  );

  Widget _body(Poem p, List<Couplet> couplets, Settings s, bool wide, int? playingVOrder) {
    final c = context.ganj;
    final highlights = {..._hits, ?playingVOrder};
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is UserScrollNotification) _userScrolledAt = DateTime.now();
        // Positions update on the next layout, so measure after the frame.
        if (n is ScrollEndNotification) WidgetsBinding.instance.addPostFrameCallback((_) => _trackTopCouplet());
        return false;
      },
      // Verses, meanings and the summary can be selected and copied.
      child: SelectionArea(
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  if (p.category != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Breadcrumb(crumbsFor(p.category!, includeSelf: true)),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Text(
                      p.title,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: nastaliqOf(context, 30),
                    ),
                  ),
                  if (p.metre != null || p.rhyme != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.center,
                        children: [
                          if (p.metre != null)
                            _InfoChip(
                              label: context.l10n.metre,
                              value: p.metre!,
                              onTap: () => _openSimilar(p, withRhyme: false),
                            ),
                          if (p.rhyme != null)
                            _InfoChip(
                              label: context.l10n.rhyme,
                              value: p.rhyme!,
                              onTap: () => _openSimilar(p, withRhyme: true),
                            ),
                        ],
                      ),
                    ),
                  if (p.summary != null)
                    GoldCard(
                      color: c.inner,
                      padding: EdgeInsets.zero,
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        title: Row(
                          children: [
                            Text(context.l10n.summary),
                            if (p.summary!.isAi) ...[const SizedBox(width: 8), const AiBadge()],
                          ],
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [Text(p.summary!.text, style: TextStyle(height: 1.9, color: c.muted))],
                      ),
                    ),
                  if (p.recitations.isNotEmpty)
                    RecitationList(
                      poem: p,
                      scrollLocked: _scrollLocked,
                      onToggleLock: () => setState(() => _scrollLocked = !_scrollLocked),
                    ),
                ],
              ),
            ),
            // The poem card: couplets are built lazily so long masnavi sections stay smooth.
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final side = ((constraints.crossAxisExtent - 752) / 2).clamp(0.0, double.infinity) + 12;
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 8, side, 8),
                  sliver: DecoratedSliver(
                    decoration: BoxDecoration(
                      color: c.poem,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: c.gold, width: 2),
                    ),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverList.builder(
                        itemCount: couplets.length,
                        itemBuilder: (context, i) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BeytView(
                              key: _keyFor(couplets[i].index),
                              couplet: couplets[i],
                              wide: wide,
                              scale: s.fontScale,
                              showMeaning: s.showMeaning,
                              highlightVOrders: highlights,
                              hasNote: _notes.containsKey(couplets[i].index),
                              bookmarked: _bookmarkedCouplets.contains(couplets[i].index),
                              onMenu: (at) => _beytMenu(p, couplets[i], at),
                            ),
                            if (s.showTajik) _TajikLines(fullUrl: p.fullUrl, couplet: couplets[i]),
                            if (_translating)
                              TranslationLine(
                                future: _translationOf(couplets[i], s.translateTo),
                                to: s.translateTo,
                                onOpenInBrowser: () => _openTranslation(couplets[i].text, s.translateTo),
                              ),
                            if (i < couplets.length - 1) wide ? const OrnamentSeparator() : const DashedDivider(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            SliverToBoxAdapter(child: PoemExtras(poem: p)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// Toolbar "translate": on a phone, toggles translations under each beyt (after the reader
  /// agrees to download the model); on a computer, opens the poem in Google Translate.
  Future<void> _toggleTranslation(List<Couplet> couplets) async {
    final t = ref.read(translatorProvider);
    final to = ref.read(settingsProvider).translateTo;
    if (!t.inApp) {
      await _openTranslation(couplets.map((c) => c.text).join('\n'), to);
      return;
    }
    if (_translating) {
      setState(() => _translating = false);
      return;
    }
    if (await _ensureModel(t, to) && mounted) setState(() => _translating = true);
  }

  Future<void> _openTranslation(String text, String to) =>
      openExternal(context, googleTranslateUri(text, to).toString(), launcher: ref.read(urlLauncherProvider));

  int? _coupletOfVerse(Poem p, int? vOrder) {
    if (vOrder == null) return null;
    for (final c in groupCouplets(p.verses)) {
      if (c.verses.any((v) => v.vOrder == vOrder)) return c.index;
    }
    return null;
  }

  Future<bool> _ensureModel(Translator t, String to) => ensureTranslationModel(context, t, to);

  /// One request per beyt, kept while the target language stays the same.
  Future<String> _translationOf(Couplet c, String to) {
    if (_translatedTo != to) {
      _translations.clear();
      _translatedTo = to;
    }
    return _translations.putIfAbsent(c.index, () => ref.read(translatorProvider).translate(c.text, to));
  }

  Future<void> _translateBeyt(Couplet couplet) async {
    final t = ref.read(translatorProvider);
    final to = ref.read(settingsProvider).translateTo;
    if (!t.inApp) return _openTranslation(couplet.text, to);
    if (!await _ensureModel(t, to) || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(couplet.text, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 15)),
        content: TranslationLine(
          future: _translationOf(couplet, to),
          to: to,
          onOpenInBrowser: () => _openTranslation(couplet.text, to),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.l10n.close))],
      ),
    );
  }

  /// A beyt's actions: a bottom sheet after a tap on phones, a menu at the pointer after a
  /// right-click (or the hover ⋮) on computers.
  void _beytMenu(Poem p, Couplet couplet, Offset? at) {
    final l = context.l10n;
    final text = _withSource(p, couplet.text);
    final marked = _bookmarkedCouplets.contains(couplet.index);
    final actions = <(IconData, String, VoidCallback)>[
      if (p.recitations.isNotEmpty) (Icons.play_arrow, l.playFromBeyt, () => _playFrom(p, couplet)),
      (
        marked ? Icons.bookmark_remove : Icons.bookmark_add,
        marked ? l.unbookmarkBeyt : l.bookmarkBeyt,
        () => _toggleBookmark(p, couplet: couplet.index),
      ),
      (Icons.sticky_note_2_outlined, l.note, () => _editNote(p, couplet)),
      (Icons.translate, l.translateBeyt, () => _translateBeyt(couplet)),
      (Icons.copy, l.copyBeyt, () => _copy(text)),
      (Icons.share, l.shareBeyt, () => _share(text)),
    ];
    if (at != null) {
      final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
      showMenu<VoidCallback>(
        context: context,
        position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
        items: [
          for (final (icon, label, run) in actions)
            PopupMenuItem(
              value: run,
              child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]),
            ),
        ],
      ).then((run) => run?.call());
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (icon, label, run) in actions)
                ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: () {
                    Navigator.pop(ctx);
                    run();
                  },
                ),
              if (couplet.summary != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: MeaningBox(summary: couplet.summary!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBar(Poem p) => SafeArea(
    child: Row(
      children: [
        Expanded(
          child: p.previous == null
              ? const SizedBox()
              : TextButton.icon(
                  key: const ValueKey('nav-prev'),
                  onPressed: () => context.pushReplacement('/poem/${p.previous!.id}'),
                  icon: const Icon(Icons.chevron_left /* mirrors in RTL → points right (back) */),
                  label: Text(localTitle(p.previous!.title), overflow: TextOverflow.ellipsis),
                ),
        ),
        Expanded(
          child: p.next == null
              ? const SizedBox()
              : TextButton.icon(
                  key: const ValueKey('nav-next'),
                  onPressed: () => context.pushReplacement('/poem/${p.next!.id}'),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right /* mirrors in RTL → points left (forward) */),
                  label: Text(localTitle(p.next!.title), overflow: TextOverflow.ellipsis),
                ),
        ),
      ],
    ),
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: c.paper,
          border: Border.all(color: c.borderGold),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label: ',
                style: TextStyle(color: c.muted),
              ),
              TextSpan(
                text: value,
                style: TextStyle(color: c.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The beyt's Tajik (Cyrillic) text, under it, when the option is on and Ganjoor has it.
class _TajikLines extends ConsumerWidget {
  const _TajikLines({required this.fullUrl, required this.couplet});

  final String fullUrl;
  final Couplet couplet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final texts = ref.watch(tajikPoemProvider(fullUrl)).value;
    final lines = [for (final v in couplet.verses) ?texts?[v.vOrder]];
    if (lines.isEmpty) return const SizedBox.shrink();
    final c = context.ganj;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        lines.join('\n'),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        // Vazirmatn has no Cyrillic: fall back to Roboto (Android), else the system's font.
        style: TextStyle(color: c.lapis, fontSize: 14, height: 1.7, fontFamilyFallback: const ['Roboto']),
      ),
    );
  }
}
