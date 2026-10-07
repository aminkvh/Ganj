import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../library/library_providers.dart' show formatBytes;
import 'translator.dart';

/// Makes sure [t] can translate Persian → [to]. A download (ML Kit, ~30 MB per language)
/// happens only after the reader agrees; returns false when they decline or it fails.
/// When the download fails (Google's servers can be unreachable from some networks),
/// [fallback] — opening the text in Google Translate — is offered instead.
Future<bool> ensureTranslationModel(BuildContext context, Translator t, String to, {VoidCallback? fallback}) async {
  if (await t.isReady(to)) return true;
  if (!context.mounted) return false;
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.modelTitle),
      content: Text(l.modelBody(formatBytes(30 * 1024 * 1024))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.download)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context)..showSnackBar(SnackBar(content: Text(l.modelDownloading)));
  try {
    await t.prepare(to);
    messenger.hideCurrentSnackBar();
    return true;
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l.modelFailed),
          duration: const Duration(seconds: 8),
          action: fallback == null ? null : SnackBarAction(label: l.openInGoogleTranslate, onPressed: fallback),
        ),
      );
    return false;
  }
}
