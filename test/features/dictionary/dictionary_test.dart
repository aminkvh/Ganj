import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/theme/ganj_theme.dart';
import 'package:ganj/features/dictionary/dictionary.dart';
import 'package:ganj/l10n/l10n.dart';

class _Stub implements HttpClientAdapter {
  _Stub(this.body);
  final String body;
  Uri? asked;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    asked = o.uri;
    calls++;
    return ResponseBody.fromString(body, 200);
  }

  @override
  void close({bool force = false}) {}
}

String page(String extract) => jsonEncode({
  'query': {
    'pages': [
      {'title': 'x', 'extract': extract},
    ],
  },
});

const dil = '''
== فارسی ==


=== ریشه لغت ===
گیرش‌شده از بهاری: دَل


=== آوایش ===
/دِل/


=== اسم ===
دل

(جانوری): قلب. جایگاه عواطف و احساسات در انسان.


=== عامیانه ===
شکم.
خاطر، ضمیر.


=== ریشه شناسی۲ ===
دَل

در گویش گنابادی یعنی ماده سگ.


== عربی ==
/دَلّ/
ناز، کرشمه.


==== منابع ====
فرهنگ لغت معین
''';

void main() {
  test('clean drops vowel marks, tatweel and punctuation, and unifies Arabic letters', () {
    expect(Dictionary.clean('سَاقِی،'), 'ساقی');
    expect(Dictionary.clean('عليّ'), 'علی');
    expect(Dictionary.clean('  ‌ '), '');
  });

  test('an entry keeps only the Persian meanings, under their headings, without the noise', () {
    final groups = Dictionary.parse(dil);
    expect([for (final g in groups) g.heading], ['اسم', 'عامیانه']);
    expect(groups[0].lines, ['دل', '(جانوری): قلب. جایگاه عواطف و احساسات در انسان.']);
    expect(groups[1].lines, ['شکم.', 'خاطر، ضمیر.']);
    expect(groups.expand((g) => g.lines).join(), isNot(contains(r'$')));
    expect(groups.expand((g) => g.lines).join(), isNot(contains('عربی')));
  });

  test('Moein\'s lines under the sources heading join the page\'s own, without the dictionary\'s name', () {
    final groups = Dictionary.parse(
      '== عربی ==\n(اِ\n\n== فارسی ==\nکسی که آب یا شراب به دیگران دهد.\n\n==== منابع ====\nفرهنگ لغت معین\nآب دهنده، کسی که به دیگران آب یا شراب دهد.\n',
    );
    expect(groups.length, 1);
    expect(groups.single.heading, isNull);
    expect(groups.single.lines, ['کسی که آب یا شراب به دیگران دهد.', 'آب دهنده، کسی که به دیگران آب یا شراب دهد.']);
  });

  test('lookup asks Wiktionary for the cleaned word; a missing page or several words is null', () async {
    final stub = _Stub(page(dil));
    final d = Dictionary(Dio()..httpClientAdapter = stub);
    final m = await d.lookup('دَلِ');
    expect(m!.groups.first.heading, 'اسم');
    expect(stub.asked!.queryParameters['titles'], 'دل');
    expect(
      await Dictionary(Dio()..httpClientAdapter = _Stub('{"query":{"pages":[{"title":"x","missing":true}]}}'))
          .lookup('زوزو'),
      isNull,
    );
    expect(await d.lookup('دو واژه'), isNull);
  });

  testWidgets('the sheet asks once, however often it is rebuilt or touched', (tester) async {
    final stub = _Stub(page(dil));
    final dictionary = Dictionary(Dio()..httpClientAdapter = stub);
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dictionaryProvider.overrideWithValue(dictionary)],
        child: MaterialApp(
          theme: buildGanjTheme(Brightness.dark, iranNastaliq: false),
          locale: const Locale('fa'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return Scaffold(
                body: Builder(
                  builder: (ctx) =>
                      TextButton(onPressed: () => showWordMeaning(ctx, ref, 'دل'), child: const Text('open')),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('اسم'), findsOneWidget);
    expect(find.text('عامیانه'), findsOneWidget);
    // Touching, scrolling and a changed keyboard/inset all rebuild the sheet.
    await tester.tap(find.text('شکم.'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(stub.calls, 1);
    expect(captured, isNotNull);
  });
}
