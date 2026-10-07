import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../core/theme/ganj_theme.dart';
import '../../data/api/dto/poet.dart';
import '../../data/providers.dart';
import '../../widgets/error_retry.dart';
import '../extras/random_poem.dart';
import 'book_shelf.dart';
import 'poet_tile.dart';
import '../../l10n/l10n.dart';
import '../../core/text/content_en.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back in the app after starting offline: try for the full, current poet list again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ref.read(poetryRepositoryProvider).centuriesFromSeed) {
      ref.invalidate(centuriesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final centuries = ref.watch(centuriesProvider);
    return Scaffold(
      body: SafeArea(
        child: centuries.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(centuriesProvider)),
          data: _content,
        ),
      ),
    );
  }

  Widget _content(List<Century> cs) {
    final c = context.ganj;
    final header = Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: context.l10n.searchPoems,
              icon: Icon(Icons.search, color: c.ink),
              onPressed: () => context.push('/search'),
            ),
            const Spacer(),
            IconButton(
              tooltip: context.l10n.offlineLibrary,
              icon: Icon(Icons.download_for_offline_outlined, color: c.ink),
              onPressed: () => context.push('/library'),
            ),
            PopupMenuButton<String>(
              tooltip: context.l10n.menu,
              icon: Icon(Icons.more_vert, color: c.ink),
              onSelected: (v) => v == 'random' ? openRandomPoem(context, ref) : context.push(v),
              itemBuilder: (_) => [
                PopupMenuItem(value: '/faal', child: Text(context.l10n.faalTitle)),
                PopupMenuItem(value: 'random', child: Text(context.l10n.randomPoem)),
                PopupMenuItem(value: '/metres', child: Text(context.l10n.metres)),
                PopupMenuItem(value: '/map', child: Text(context.l10n.birthplaceMap)),
                PopupMenuItem(value: '/me', child: Text(context.l10n.bookmarksAndNotes)),
                PopupMenuItem(value: '/settings', child: Text(context.l10n.settingsAndAbout)),
              ],
            ),
          ],
        ),
        Text(context.l10n.appName, style: nastaliqOf(context, 44).copyWith(color: c.brandRed)),
        Text(context.l10n.tributeLine, style: TextStyle(color: c.muted)),
        if (ref.read(poetryRepositoryProvider).centuriesFromSeed)
          TextButton.icon(
            key: const ValueKey('seed-refresh'),
            onPressed: () => ref.invalidate(centuriesProvider),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(context.l10n.seedRefresh),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            key: const ValueKey('poet-filter'),
            controller: _search,
            // Typing filters poets and books; Enter searches the poems themselves (as on ganjoor.net).
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) context.push('/search?q=${Uri.encodeQueryComponent(v.trim())}');
            },
            decoration: InputDecoration(
              hintText: context.l10n.homeSearchHint,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.l10n.clear,
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: c.paper,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.borderGold),
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
      ],
    );

    // Header + pinned row scroll away (NestedScrollView) so short screens, landscape
    // and an open keyboard never overflow.
    final typed = _query.trim().isNotEmpty;
    final seen = <int>{};
    final matches = [
      if (typed)
        for (final cen in cs)
          for (final p in cen.poets)
            if (seen.add(p.id) &&
                (matchesQuery(p.name, _query) || matchesQuery(p.nickname, _query) || _matchesEnglish(p.id, _query)))
              p,
    ];
    // Nothing matched? Keep the home page as it was rather than an empty screen.
    final books = matchingBooks(ref.watch(bookCatalogProvider).value ?? const [], _query);
    final searching = typed && (matches.isNotEmpty || books.isNotEmpty);
    final pinned = [
      for (final cen in cs)
        if (cen.id == 0) ...cen.poets,
    ]..sort((a, b) => a.pinOrder.compareTo(b.pinOrder));
    final eras = [
      for (final cen in cs)
        if (cen.id != 0 && cen.poets.isNotEmpty) cen,
    ];
    return DefaultTabController(
      length: eras.length,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(child: header),
          if (!searching && pinned.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 190,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [for (final p in pinned) PoetTile(poet: p)],
                ),
              ),
            ),
          if (!searching)
            SliverToBoxAdapter(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: c.lapis,
                unselectedLabelColor: c.muted,
                indicatorColor: c.gold,
                tabs: [for (final e in eras) Tab(text: localCentury(e.name))],
              ),
            ),
        ],
        body: searching
            ? PoetGrid(
                poets: matches,
                header: BookResults(query: _query),
              )
            // Like the site's home page, the map and the bookshelf come after the poets.
            : TabBarView(
                children: [for (final e in eras) PoetGrid(poets: e.poets, footer: const _HomeEnd())],
              ),
      ),
    );
  }
}

/// After the poets: «نقشهٔ خاستگاه سخنوران» and «قفسهٔ کتاب‌ها», as on ganjoor.net.
class _HomeEnd extends StatelessWidget {
  const _HomeEnd();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Divider(height: 32, indent: 32, endIndent: 32),
      Text(context.l10n.birthplaceMap, style: nastaliqOf(context, 22).copyWith(color: context.ganj.lapis)),
      const _MapTile(),
      const BookShelf(),
      const SizedBox(height: 24),
    ],
  );
}

class _MapTile extends StatelessWidget {
  const _MapTile();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: InkWell(
      key: const ValueKey('home-map'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/map'),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Image.asset('assets/images/map.gif', width: 120, semanticLabel: context.l10n.birthplaceMap),
      ),
    ),
  );
}

/// In the English interface, «Hafez» finds حافظ too.
bool _matchesEnglish(int id, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || englishContent == null) return false;
  return '${englishContent!.poetNickname(id)} ${englishContent!.poetName(id)}'.toLowerCase().contains(q);
}
