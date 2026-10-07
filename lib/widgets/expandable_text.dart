import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text/content_en.dart';
import '../features/settings/settings_controller.dart';
import '../features/translate/ensure_model.dart';
import '../features/translate/translation_line.dart';
import '../features/translate/translator.dart';
import '../l10n/l10n.dart';
import 'external_link.dart';

/// Longer Persian prose (a poet's biography, a section's description): selectable, folded
/// after a few lines, and — in the English interface — translatable on request.
class ExpandableText extends ConsumerStatefulWidget {
  const ExpandableText(this.text, {super.key, this.maxLines = 4});

  final String text;
  final int maxLines;

  @override
  ConsumerState<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends ConsumerState<ExpandableText> {
  bool _open = false;
  Future<String>? _translation;

  Future<void> _translate() async {
    final t = ref.read(translatorProvider);
    final to = ref.read(settingsProvider).translateTo;
    if (!t.inApp) return _openInBrowser(to);
    if (!await ensureTranslationModel(context, t, to) || !mounted) return;
    setState(() {
      _translation = t.translate(widget.text, to);
    });
  }

  Future<void> _openInBrowser(String to) =>
      openExternal(context, googleTranslateUri(widget.text, to).toString(), launcher: ref.read(urlLauncherProvider));

  @override
  Widget build(BuildContext context) {
    final to = ref.watch(settingsProvider).translateTo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionArea(
          child: Text(
            widget.text,
            maxLines: _open ? null : widget.maxLines,
            overflow: _open ? null : TextOverflow.ellipsis,
            textAlign: TextAlign.justify,
            textDirection: TextDirection.rtl,
            style: const TextStyle(height: 1.9),
          ),
        ),
        if (_translation case final f?)
          SelectionArea(
            child: TranslationLine(future: f, to: to, onOpenInBrowser: () => _openInBrowser(to)),
          ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => setState(() => _open = !_open),
              child: Text(_open ? context.l10n.less : context.l10n.more),
            ),
            if (englishContent != null && _translation == null)
              TextButton.icon(
                onPressed: _translate,
                icon: const Icon(Icons.translate, size: 18),
                label: Text(context.l10n.translate),
              ),
          ],
        ),
      ],
    );
  }
}
