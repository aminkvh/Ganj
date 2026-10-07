import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/ganj_colors.dart';
import 'features/category/category_screen.dart';
import 'features/extras/faal_screen.dart';
import 'features/extras/url_screen.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/map/poets_map_screen.dart';
import 'features/metre/metre_screen.dart';
import 'features/metre/similar_screen.dart';
import 'features/player/mini_player.dart';
import 'features/player/player_controller.dart';
import 'features/poem/poem_screen.dart';
import 'features/poet/poet_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/user/user_screen.dart';
import 'l10n/l10n.dart';

/// Where the app opens (tests start elsewhere).
final initialLocationProvider = Provider<String>((ref) => '/');

/// Builds [screen] for a numeric `:id`, or the not-found page for links like `/poem/abc`.
Widget _withId(GoRouterState s, Widget Function(int id) screen) {
  final id = int.tryParse(s.pathParameters['id'] ?? '');
  return id == null ? const NotFoundScreen() : screen(id);
}

/// Every screen lives inside a shell that keeps the mini-player docked at the bottom.
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: ref.watch(initialLocationProvider),
    errorBuilder: (_, _) => const NotFoundScreen(),
    routes: [
      ShellRoute(
        builder: (_, _, child) => _PlayerShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/poet/:id',
            builder: (_, s) => _withId(s, (id) => PoetScreen(id: id)),
          ),
          GoRoute(
            path: '/cat/:id',
            builder: (_, s) => _withId(s, (id) => CategoryScreen(id: id)),
          ),
          GoRoute(
            path: '/poem/:id',
            builder: (_, s) =>
                _withId(s, (id) => PoemScreen(id: id, couplet: int.tryParse(s.uri.queryParameters['c'] ?? ''))),
          ),
          GoRoute(path: '/faal', builder: (_, _) => const FaalScreen()),
          GoRoute(
            path: '/url',
            builder: (_, s) => UrlScreen(url: s.uri.queryParameters['u'] ?? ''),
          ),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(path: '/me', builder: (_, _) => const UserScreen()),
          GoRoute(path: '/metres', builder: (_, _) => const MetreScreen()),
          GoRoute(
            path: '/similar',
            builder: (_, s) =>
                SimilarScreen(metre: s.uri.queryParameters['metre'] ?? '', rhyme: s.uri.queryParameters['rhyme']),
          ),
          GoRoute(path: '/library', builder: (_, _) => const LibraryScreen()),
          GoRoute(path: '/map', builder: (_, _) => const PoetsMapScreen()),
          GoRoute(
            path: '/search',
            builder: (_, s) => SearchScreen(poetId: int.tryParse(s.uri.queryParameters['poet'] ?? '')),
          ),
        ],
      ),
    ],
  ),
);

/// Screens above, mini-player below. While the mini-player shows, it owns the bottom safe
/// area, so the screens above must not pad for it again (double inset on iPhones).
class _PlayerShell extends ConsumerWidget {
  const _PlayerShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerShown = ref.watch(playerProvider.select((s) => s.status != PlayerStatus.idle && s.poem != null));
    return Column(
      children: [
        Expanded(
          child: playerShown ? MediaQuery.removePadding(context: context, removeBottom: true, child: child) : child,
        ),
        const MiniPlayer(),
      ],
    );
  }
}

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore, size: 48, color: c.muted),
            const SizedBox(height: 12),
            Text(context.l10n.notFoundPage),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => context.go('/'), child: Text(context.l10n.backHome)),
          ],
        ),
      ),
    );
  }
}
