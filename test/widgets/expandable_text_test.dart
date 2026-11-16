import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/widgets/expandable_text.dart';

import '../support/test_app.dart';

/// Ganjoor's description of عماد خراسانی (poet 247) as served: blank lines and a lone
/// no-break space before the text.
const emad =
    '\r\n\r\n \r\n\r\n\r\nسید عمادالدین حسنی برقعی (۱۳۰۰ – ۲۸ بهمن ۱۳۸۲) مشهور به عماد خراسانی، '
    'شاعر، غزل‌سرا و قصیده‌سرای مشهور خراسانی بود.\r\nدیوان او در گنجور در دسترس قرار گرفته است.';

void main() {
  test('blank lines at the start and end are dropped, runs of them shortened', () {
    expect(ExpandableText.tidyProse(emad), startsWith('سید عمادالدین'));
    expect(ExpandableText.tidyProse(emad), isNot(contains('\r')));
    expect(ExpandableText.tidyProse('الف\n\n \n\n\nب\n \n'), 'الف\n\nب');
    expect(ExpandableText.tidyProse('الف\nب'), 'الف\nب');
  });

  Future<void> pump(WidgetTester tester, String text) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        Scaffold(body: SingleChildScrollView(child: ExpandableText(text))),
        prefs: prefs,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a short description shows in full, with no «بیشتر»', (tester) async {
    await pump(tester, emad);
    expect(find.textContaining('سید عمادالدین'), findsOneWidget);
    expect(find.byKey(const ValueKey('expandable-more')), findsNothing);
  });

  testWidgets('a long description folds, and «بیشتر» opens it', (tester) async {
    await pump(tester, List.filled(40, 'خواجه شمس‌الدین محمد شیرازی متخلص به حافظ').join('\n'));
    final more = find.byKey(const ValueKey('expandable-more'));
    expect(more, findsOneWidget);
    expect(tester.widget<Text>(find.byType(Text).first).maxLines, 4);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byType(Text).first).maxLines, isNull);
    expect(more, findsOneWidget, reason: '«کمتر» folds it again');
  });
}
