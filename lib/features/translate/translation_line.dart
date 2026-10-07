import 'package:flutter/material.dart';

import '../../core/theme/ganj_colors.dart';
import '../../l10n/l10n.dart';

const _rtlTargets = {'ar', 'ur'};

/// A beyt's machine translation, under the beyt, marked as machine-made.
class TranslationLine extends StatelessWidget {
  const TranslationLine({super.key, required this.future, required this.to, this.onOpenInBrowser});

  final Future<String> future;

  /// Target language code; Arabic and Urdu read right to left.
  final String to;

  /// Offered when translating in the app fails: the same text in Google Translate.
  final VoidCallback? onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: FutureBuilder<String>(
        future: future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(context.l10n.translateFailed, style: TextStyle(color: c.muted, fontSize: 12)),
                if (onOpenInBrowser != null)
                  TextButton.icon(
                    onPressed: onOpenInBrowser,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(context.l10n.openInGoogleTranslate),
                  ),
              ],
            );
          }
          if (!snap.hasData) return const LinearProgressIndicator(minHeight: 1);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                snap.data!,
                textAlign: TextAlign.center,
                textDirection: _rtlTargets.contains(to) ? TextDirection.rtl : TextDirection.ltr,
                style: TextStyle(color: c.lapis, fontStyle: FontStyle.italic, height: 1.6),
              ),
              Text(
                context.l10n.machineTranslation,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.gold, fontSize: 10.5),
              ),
            ],
          );
        },
      ),
    );
  }
}
