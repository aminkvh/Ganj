import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/category/category_screen.dart';
import 'package:ganj/features/poet/poet_screen.dart';

import '../support/fixture_repository.dart';
import '../support/test_app.dart';

void main() {
  testWidgets('poet screen: name, bio and sections', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoetScreen(id: 2), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    expect(find.text('حافظ شیرازی'), findsOneWidget);
    expect(find.text('غزلیات'), findsOneWidget);
    expect(find.textContaining('خواجه شمس‌الدین'), findsOneWidget);
    expect(find.text('بیشتر'), findsOneWidget);
  });

  testWidgets('category screen: breadcrumb and poems with excerpts', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const CategoryScreen(id: 24), prefs: prefs, repo: FixtureRepository()));
    await tester.pumpAndSettle();
    expect(find.text('حافظ'), findsOneWidget); // breadcrumb
    expect(find.text('غزل شمارهٔ ۱'), findsOneWidget);
    expect(find.textContaining('اَلا یا'), findsOneWidget);
  });

  testWidgets('category screen offline shows retry', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(const CategoryScreen(id: 24), prefs: prefs, repo: FixtureRepository()..fail = true),
    );
    await tester.pumpAndSettle();
    expect(find.text('تلاش دوباره'), findsOneWidget);
  });
}
