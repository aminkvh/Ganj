import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../l10n/l10n.dart';
import 'update_check.dart';

void openUpdatePage(UpdateInfo u) => launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);

/// A quiet line under the home title when a newer Ganj is on GitHub: Download, or close it for this version.
class UpdateNotice extends ConsumerWidget {
  const UpdateNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(updateProvider).value;
    if (u == null || ref.watch(updateDismissedProvider) == u.version) return const SizedBox.shrink();
    final c = context.ganj;
    return Padding(
      key: const ValueKey('update-notice'),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              context.l10n.appUpdateAvailable(localDigits(u.version)),
              style: TextStyle(color: c.muted),
            ),
          ),
          TextButton(onPressed: () => openUpdatePage(u), child: Text(context.l10n.download)),
          IconButton(
            tooltip: context.l10n.close,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: c.muted),
            onPressed: () => ref.read(updateDismissedProvider.notifier).dismiss(u.version),
          ),
        ],
      ),
    );
  }
}
