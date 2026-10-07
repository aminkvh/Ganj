import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/ganj_colors.dart';
import '../../core/theme/ganj_theme.dart';
import '../../data/providers.dart';
import '../../widgets/gold_card.dart';
import '../../l10n/l10n.dart';

/// Faal-e Hafez: the traditional invocation, then a ghazal chosen by Ganjoor.
class FaalScreen extends ConsumerStatefulWidget {
  const FaalScreen({super.key});

  @override
  ConsumerState<FaalScreen> createState() => _FaalScreenState();
}

class _FaalScreenState extends ConsumerState<FaalScreen> {
  bool _opening = false;

  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      final poem = await ref.read(ganjoorApiProvider).faal();
      if (mounted) context.pushReplacement('/poem/${poem.id}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.offline)));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.faalTitle)),
      body: Center(
        child: SingleChildScrollView(
          child: GoldCard(
            color: c.poem,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.faalTitle, style: nastaliqOf(context, 40).copyWith(color: c.brandRed)),
                const SizedBox(height: 16),
                Text(
                  context.l10n.faalInvocation,
                  textAlign: TextAlign.center,
                  style: verseStyle(c, 1).copyWith(height: 2.2),
                ),
                const SizedBox(height: 12),
                Text(context.l10n.faalIntention, style: TextStyle(color: c.muted)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _opening ? null : _open,
                  icon: _opening
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(context.l10n.faalOpen),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
