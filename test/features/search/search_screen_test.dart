import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/search/search_screen.dart';
import 'package:ganj/features/search/search_service.dart';

import '../../support/fixture_repository.dart';
import '../../support/test_app.dart';

class FakeSearch implements SearchService {
  FakeSearch(this.result);

  SearchPage result;

  /// Per-term responses held until completed (slow network).
  final slow = <String, Completer<SearchPage>>{};
  final calls = <(String, int?, int)>[];

  @override
  Future<SearchPage> search(String term, {int? poetId, int page = 1}) async {
    calls.add((term, poetId, page));
    final gate = slow[term];
    if (gate != null) return gate.future;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const hit = SearchHit(
  poemId: 2130,
  poemTitle: 'غزل شمارهٔ ۱',
  poetName: 'حافظ',
  snippet: 'اَلا یا اَیُّهَا السّاقی',
  local: true,
);
const hit2 = SearchHit(
  poemId: 2073,
  poemTitle: 'رباعی شمارهٔ ۲۳',
  poetName: 'حافظ',
  snippet: 'ز ساقی کوثر پرس',
  local: false,
);

void main() {
  Future<FakeSearch> pump(WidgetTester tester, SearchPage page) async {
    final fake = FakeSearch(page);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [searchServiceProvider.overrideWithValue(fake)],
        child: testApp(const SearchScreen(), prefs: prefs, repo: FixtureRepository()),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  Future<void> submit(WidgetTester tester, String q) async {
    await tester.enterText(find.byKey(const ValueKey('search-field')), q);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('shows hits with poet and poem, local ones marked offline', (tester) async {
    final fake = await pump(tester, const SearchPage([hit, hit2], total: 2));
    await submit(tester, 'ساقی');
    expect(fake.calls.single.$1, 'ساقی');
    expect(find.byKey(const ValueKey('hit-2130')), findsOneWidget);
    expect(find.byKey(const ValueKey('hit-2073')), findsOneWidget);
    expect(find.textContaining('حافظ » غزل شمارهٔ ۱'), findsOneWidget);
    expect(find.byIcon(Icons.offline_pin), findsOneWidget);
  });

  testWidgets('offline results show a banner', (tester) async {
    await pump(tester, const SearchPage([hit], total: 1, offline: true));
    await submit(tester, 'ساقی');
    expect(find.textContaining('آفلاین'), findsOneWidget);
  });

  testWidgets('no results message', (tester) async {
    await pump(tester, const SearchPage([]));
    await submit(tester, 'ناموجود');
    expect(find.text('چیزی یافت نشد'), findsOneWidget);
  });

  testWidgets('load more requests the next page', (tester) async {
    final fake = await pump(tester, const SearchPage([hit], total: 40, hasMore: true));
    await submit(tester, 'ساقی');
    fake.result = const SearchPage([hit2], total: 40);
    await tester.tap(find.text('نتایج بیشتر'));
    await tester.pumpAndSettle();
    expect(fake.calls.last.$3, 2);
    expect(find.byKey(const ValueKey('hit-2073')), findsOneWidget);
    expect(find.byKey(const ValueKey('hit-2130')), findsOneWidget);
  });

  testWidgets('a slow earlier search does not overwrite a newer one', (tester) async {
    final fake = await pump(tester, const SearchPage([hit2], total: 1));
    final first = fake.slow['ساقی'] = Completer<SearchPage>();
    await tester.enterText(find.byKey(const ValueKey('search-field')), 'ساقی');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump(); // first request still in flight (spinner showing)
    await submit(tester, 'کوثر');
    first.complete(const SearchPage([hit], total: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hit-2073')), findsOneWidget);
    expect(find.byKey(const ValueKey('hit-2130')), findsNothing);
  });

  testWidgets('an offline count that is not exact shows a plus', (tester) async {
    await pump(tester, const SearchPage([hit], total: 1, hasMore: true, offline: true, totalKnown: false));
    await submit(tester, 'ساقی');
    expect(find.text('۱+ نتیجه'), findsOneWidget);
  });
}
