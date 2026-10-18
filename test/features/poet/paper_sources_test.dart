import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/poet/poet_screen.dart';

import '../../data/extras_test.dart' show ex;
import '../../support/fake_adapter.dart';
import '../../support/fixture_repository.dart';
import '../../support/scroll.dart';
import '../../support/test_app.dart';

void main() {
  Future<void> open(WidgetTester tester, {bool any = true}) async {
    final db = AppDb(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final adapter = FakeAdapter({'/api/ganjoor/cat/9/papersources': any ? ex('papersources_9.json') : '[]'});
    await tester.pumpWidget(
      testApp(
        const PoetScreen(id: 2),
        prefs: await mockPrefs(),
        repo: FixtureRepository(),
        db: db,
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
  }

  testWidgets('the poet page names the edition the text follows, and opens to all sources', (tester) async {
    await open(tester);
    final panel = find.byKey(const ValueKey('panel-sources'));
    await bringIntoView(tester, panel);
    expect(find.textContaining('منبع متن گنجور: دیوان حافظ به اهتمام محمد قزوینی'), findsOneWidget);
    await tester.tap(find.text('منابع کاغذی'));
    await tester.pumpAndSettle();
    expect(find.textContaining('پرویز ناتل خانلری'), findsWidgets);
    expect(find.text('کتاب چاپی'), findsNWidgets(2));
    expect(find.text('نسخهٔ خطی'), findsNWidgets(2));
    expect(find.text('نسخهٔ خطی · منبع متن گنجور'), findsOneWidget);
    // The text's source leads the list.
    final first = find.descendant(of: find.byType(ListTile).first, matching: find.textContaining('قزوینی'));
    expect(first, findsOneWidget);
  });

  testWidgets('poets without sources show no panel', (tester) async {
    await open(tester, any: false);
    expect(find.byKey(const ValueKey('panel-sources')), findsNothing);
    expect(find.text('غزلیات'), findsOneWidget);
  });
}
