import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/metre/metre_screen.dart';
import 'package:ganj/features/metre/similar_screen.dart';
import 'package:ganj/features/poem/poem_screen.dart';

import '../../data/extras_test.dart' show ex;
import '../../support/fake_adapter.dart';
import '../../support/fixture_repository.dart';
import '../extras/extras_screens_test.dart' show pumpRouted, settle;

void main() {
  testWidgets('metre list is sorted by popularity and filterable', (tester) async {
    await pumpRouted(tester, const MetreScreen(), FakeAdapter({'/api/ganjoor/rhythms': ex('rhythms.json')}));
    await settle(tester);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles, isNotEmpty);
    await tester.enterText(find.byKey(const ValueKey('metre-filter')), 'هزج مثمن سالم');
    await settle(tester);
    expect(find.textContaining('هزج مثمن سالم'), findsWidgets);
  });

  testWidgets('similar poems list pages and opens poems', (tester) async {
    final adapter = FakeAdapter({'/api/ganjoor/poems/similar': ex('similar.json')});
    adapter.headers['/api/ganjoor/poems/similar'] = {
      'paging-headers': '{"totalCount":46,"pageSize":20,"currentPage":1,"totalPages":3,"hasNextPage":true}',
    };
    await pumpRouted(tester, const SimilarScreen(metre: 'مفاعیلن مفاعیلن مفاعیلن مفاعیلن', rhyme: 'لها'), adapter);
    await settle(tester);
    expect(find.byType(ListTile), findsNWidgets(3));
    await tester.tap(find.text('نتایج بیشتر'));
    await settle(tester);
    expect(adapter.requests.last.queryParameters['PageNumber'], '2');
    await tester.tap(find.byType(ListTile).first);
    await settle(tester);
    expect(find.textContaining('poem '), findsOneWidget);
  });

  testWidgets('the metre chip opens poems in that metre; the rhyme chip adds the rhyme', (tester) async {
    await pumpRouted(tester, const PoemScreen(id: 2130), FakeAdapter({}), repo: FixtureRepository());
    await settle(tester);
    await tester.tap(find.textContaining('مفاعیلن', findRichText: true));
    await settle(tester);
    expect(find.textContaining('similar مفاعیلن'), findsOneWidget);
    expect(find.textContaining('| null'), findsOneWidget);
    await tester.binding.handlePopRoute(); // system back
    await settle(tester);
    await tester.tap(find.textContaining('لها', findRichText: true).first);
    await settle(tester);
    expect(find.textContaining('| لها'), findsOneWidget);
  });
}
