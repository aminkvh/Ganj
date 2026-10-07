import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/poem/poem_screen.dart';

import '../data/extras_test.dart' show ex;
import '../support/fake_adapter.dart';
import '../support/fixture_repository.dart';
import '../support/test_app.dart';
import 'poem/long_poem_test.dart' show longPoem;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const path = '/api/ganjoor/search/semantic';

  GanjoorApi api(FakeAdapter a) => GanjoorApi(
    dio: createDio(adapter: a),
    cache: HttpCache(AppDb(NativeDatabase.memory())),
  );

  test('meaning search asks Ganjoor\'s semantic service and reads poems, verses and scope', () async {
    final adapter = FakeAdapter({path: ex('semantic.json')});
    final r = await api(adapter).semanticSearch('ساقی و می در شعر حافظ');
    expect(adapter.requests.single.host, 'ganjgah.ir');
    expect(adapter.bodies.single, {'query': 'ساقی و می در شعر حافظ', 'topK': 20, 'disableScopeDetection': false});
    expect(r.results.map((h) => h.poemId), [2446, 2130, 2329]);
    expect(r.results.first.verses.map((v) => v.vOrder), [17, 18]);
    expect(r.results.first.fullTitle, 'حافظ » غزلیات » غزل شمارهٔ ۳۱۷');
    expect(r.detectedPoet, 'حافظ');
    expect(r.logId, 8050);
  });

  Future<FakeAdapter> pumpSearch(WidgetTester tester, FakeAdapter adapter) async {
    final prefs = await mockPrefs();
    final db = AppDb(NativeDatabase.memory());
    await tester.pumpWidget(
      testAppRouted(
        '/search?mode=meaning',
        prefs: prefs,
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
    await settle(tester);
    return adapter;
  }

  Future<void> ask(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const ValueKey('search-field')), q);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
  }

  testWidgets('search by meaning shows poems with the verses that match', (tester) async {
    final adapter = await pumpSearch(tester, FakeAdapter({path: ex('semantic.json')}));
    expect(find.text('معنا'), findsOneWidget); // the mode is on
    await ask(tester, 'ساقی و می در شعر حافظ');
    expect(find.text('حافظ » غزلیات » غزل شمارهٔ ۳۱۷'), findsOneWidget);
    expect(find.textContaining('پاک کن چهرهٔ حافظ'), findsOneWidget);
    expect(adapter.requests.single.path, path);
  });

  testWidgets('a guessed poet can be lifted to search all of Ganjoor', (tester) async {
    final adapter = await pumpSearch(tester, FakeAdapter({path: ex('semantic.json')}));
    await ask(tester, 'ساقی و می در شعر حافظ');
    expect(find.textContaining('حافظ', findRichText: true), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('semantic-global')));
    await settle(tester);
    expect((adapter.bodies.last as Map)['disableScopeDetection'], isTrue);
  });

  testWidgets('a result opens the poem at the matching beyt and tells Ganjoor which was useful', (tester) async {
    final adapter = await pumpSearch(tester, FakeAdapter({path: ex('semantic.json'), '$path/click': '{}'}));
    await ask(tester, 'ساقی و می در شعر حافظ');
    await tester.tap(find.text('حافظ » غزلیات » غزل شمارهٔ ۱'));
    await settle(tester);
    final screen = tester.widget<PoemScreen>(find.byType(PoemScreen));
    expect(screen.id, 2130);
    expect(screen.verse, 1);
    expect(adapter.requests.last.path, '$path/click');
    expect(adapter.bodies.last, {'logId': 8050, 'poemId': 2130, 'rank': 2});
  });

  testWidgets('when the service is resting, the reader is told so', (tester) async {
    final adapter = FakeAdapter({})..status[path] = 503;
    await pumpSearch(tester, adapter);
    await ask(tester, 'غم');
    expect(find.text('جستجوی معنایی اکنون در دسترس نیست؛ کمی بعد دوباره امتحان کنید'), findsOneWidget);
  });

  testWidgets('offline, meaning search says it needs the internet', (tester) async {
    await pumpSearch(tester, FakeAdapter({})..offline = true);
    await ask(tester, 'غم');
    expect(find.text('جستجوی معنایی به اینترنت نیاز دارد'), findsOneWidget);
  });

  testWidgets('opening a poem at a verse shows that verse', (tester) async {
    final repo = FixtureRepository()..poems[999] = longPoem(1500);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 999, verse: 1201), prefs: prefs, repo: repo));
    await settle(tester);
    final target = find.text('مصراع نخست بیت 600'); // vOrder 1201 = first hemistich of beyt 600
    expect(target, findsOneWidget);
    final rect = tester.getRect(target);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio));
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
