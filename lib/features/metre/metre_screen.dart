import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/api/dto/extras.dart';
import '../../data/providers.dart';
import '../../widgets/error_retry.dart';
import '../../l10n/l10n.dart';

final rhythmsProvider = FutureProvider<List<Rhythm>>(
  (ref) async => (await ref.watch(ganjoorApiProvider).rhythms())..sort((a, b) => b.verseCount.compareTo(a.verseCount)),
  retry: noAutoRetry,
);

/// Browse Ganjoor's metres (اوزان عروضی), most used first.
class MetreScreen extends ConsumerStatefulWidget {
  const MetreScreen({super.key});

  @override
  ConsumerState<MetreScreen> createState() => _MetreScreenState();
}

class _MetreScreenState extends ConsumerState<MetreScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.metres)),
      body: ref
          .watch(rhythmsProvider)
          .when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => ErrorRetry(onRetry: () => ref.invalidate(rhythmsProvider)),
            data: (all) {
              final shown = [
                for (final r in all)
                  if (r.rhythm.isNotEmpty && (_filter.isEmpty || matchesQuery(r.rhythm, _filter))) r,
              ];
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      key: const ValueKey('metre-filter'),
                      decoration: InputDecoration(
                        hintText: context.l10n.searchMetre,
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final r = shown[i];
                        return ListTile(
                          title: Text(r.rhythm),
                          subtitle: Text(
                            context.l10n.hemistichCount(localDigits(r.verseCount)),
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                          onTap: () => context.push('/similar?metre=${Uri.encodeComponent(r.rhythm)}'),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }
}
