import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/translate/translator.dart';
import 'package:ganj/widgets/selection_menu.dart';

/// A translator double that can fail at any step, like ML Kit on a phone without working
/// Google Play services or with Google's servers out of reach.
class Scripted implements Translator {
  Scripted(this.tag, {this.readyThrows = false, this.prepareThrows = false, this.translateThrows = false});

  final String tag;
  final bool readyThrows;
  final bool prepareThrows;
  final bool translateThrows;
  int translations = 0;

  @override
  bool get inApp => true;
  @override
  bool get needsModel => true;
  @override
  Future<bool> isReady(String to) async {
    if (readyThrows) throw Exception('$tag: no Play services');
    return false;
  }

  @override
  Future<void> prepare(String to) async {
    if (prepareThrows) throw Exception('$tag: download blocked');
  }

  @override
  Future<void> remove(String to) async {}
  @override
  Future<String> translate(String text, String to) async {
    translations++;
    if (translateThrows) throw Exception('$tag: cannot translate');
    return '$tag:$text';
  }
}

void main() {
  group('phone translation never just fails silently', () {
    test('when ML Kit cannot even be asked, translation goes online', () async {
      final t = ResilientTranslator(primary: Scripted('mlkit', readyThrows: true), backup: Scripted('web'));
      expect(await t.isReady('en'), isTrue); // nothing to download: online works now
      expect(await t.translate('سلام', 'en'), 'web:سلام');
    });

    test('when the model download fails, translation goes online', () async {
      final t = ResilientTranslator(primary: Scripted('mlkit', prepareThrows: true), backup: Scripted('web'));
      expect(await t.isReady('en'), isFalse);
      await t.prepare('en'); // no exception reaches the screen
      expect(await t.translate('سلام', 'en'), 'web:سلام');
    });

    test('when ML Kit fails while translating, that beyt and later ones go online', () async {
      final mlkit = Scripted('mlkit', translateThrows: true);
      final t = ResilientTranslator(primary: mlkit, backup: Scripted('web'));
      expect(await t.translate('یک', 'en'), 'web:یک');
      expect(await t.translate('دو', 'en'), 'web:دو');
      expect(mlkit.translations, 1); // not retried for every beyt
    });

    test('when ML Kit works, it is used (on the device, offline)', () async {
      final web = Scripted('web');
      final t = ResilientTranslator(primary: Scripted('mlkit'), backup: web);
      expect(await t.translate('سلام', 'en'), 'mlkit:سلام');
      expect(web.translations, 0);
    });

    test('if online fails too, the error reaches the line (which offers the browser)', () async {
      final t = ResilientTranslator(
        primary: Scripted('mlkit', translateThrows: true),
        backup: Scripted('web', translateThrows: true),
      );
      await expectLater(t.translate('سلام', 'en'), throwsA(anything));
    });
  });

  test('the selection menu keeps only Copy and Select all (no "Ask Claude", "ChatGPT"…)', () {
    void noop() {}
    final items = [
      ContextMenuButtonItem(type: ContextMenuButtonType.copy, onPressed: noop),
      ContextMenuButtonItem(type: ContextMenuButtonType.selectAll, onPressed: noop),
      ContextMenuButtonItem(type: ContextMenuButtonType.share, onPressed: noop),
      ContextMenuButtonItem(type: ContextMenuButtonType.lookUp, onPressed: noop),
      ContextMenuButtonItem(type: ContextMenuButtonType.searchWeb, onPressed: noop),
      ContextMenuButtonItem(label: 'Ask Claude', onPressed: noop), // Android "process text" app
      ContextMenuButtonItem(label: 'ChatGPT', onPressed: noop),
    ];
    expect(essentialSelectionItems(items).map((b) => b.type), [
      ContextMenuButtonType.copy,
      ContextMenuButtonType.selectAll,
    ]);
  });
}
