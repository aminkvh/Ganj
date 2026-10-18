import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/words/word_frequency.dart';

import '../../data/extras_test.dart' show ex;
import '../../support/fake_adapter.dart';
import '../../support/scroll.dart';
import '../../support/test_app.dart';

void main() {
  Future<FakeAdapter> open(WidgetTester tester, {String language = 'fa'}) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final adapter = FakeAdapter({
      '/api/ganjoor/wordsums/9': ex('wordsums_9.json'),
      '/api/ganjoor/wordcounts/9': ex('wordcounts_9.json'),
    });
    await tester.pumpWidget(
      testApp(
        const Scaffold(body: WordFrequencySheet(catId: 9, poetId: 2)),
        prefs: await mockPrefs(),
        db: db,
        language: language,
        overrides: [
          ganjoorApiProvider.overrideWithValue(
            GanjoorApi(
              dio: createDio(adapter: adapter),
              cache: HttpCache(db),
            ),
          ),
        ],
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
    return adapter;
  }

  testWidgets('totals and the most frequent words', (tester) async {
    await open(tester);
    expect(find.text('۸۱٬۸۰۶ واژه، ۹٬۵۰۰ واژهٔ یکتا'), findsOneWidget);
    expect(find.text('که'), findsOneWidget);
    expect(find.text('۲٬۹۴۰'), findsOneWidget);
    await bringIntoView(tester, find.text('بیشتر')); // a full page: there may be more
  });

  testWidgets('English numbers in the English interface', (tester) async {
    await open(tester, language: 'en');
    expect(find.text('81,806 words, 9,500 distinct'), findsOneWidget);
  });

  testWidgets('typing a word asks Ganjoor for words starting with it', (tester) async {
    final adapter = await open(tester);
    adapter.routes['/api/ganjoor/wordcounts/9'] = ex('wordcounts_9_eshgh.json');
    await tester.enterText(find.byKey(const ValueKey('word-field')), 'عشق');
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
    expect(adapter.requests.last.queryParameters['term'], 'عشق');
    expect(find.text('عشقت'), findsOneWidget);
    expect(find.text('بیشتر'), findsNothing);
  });
}
