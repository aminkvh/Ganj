import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/translate/translator.dart';
import 'package:ganj/widgets/external_link.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

import '../support/fixture_repository.dart';
import '../support/test_app.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

/// ML Kit's model manager without a phone: which models are "on the device", and whether a
/// download succeeds (ML Kit reports a failed download by returning false).
class FakeModels extends ModelManager {
  FakeModels({this.present = const {}, this.downloadsWork = true})
    : super(channel: const MethodChannel('fake'), method: 'fake');

  final Set<String> present;
  final bool downloadsWork;
  final downloaded = <String>[];

  @override
  Future<bool> isModelDownloaded(String model) async => present.contains(model) || downloaded.contains(model);

  @override
  Future<bool> downloadModel(String model, {bool isWifiRequired = true}) async {
    if (!downloadsWork) return false;
    downloaded.add(model);
    return true;
  }

  @override
  Future<bool> deleteModel(String model) async => true;
}

class FailingDeviceTranslator implements Translator {
  @override
  bool get inApp => true;
  @override
  bool get needsModel => true;
  @override
  Future<bool> isReady(String to) async => false;
  @override
  Future<void> prepare(String to) async => throw Exception('model download blocked');
  @override
  Future<void> remove(String to) async {}
  @override
  Future<String> translate(String text, String to) async => throw Exception('no model');
}

void main() {
  group('phone translation models', () {
    test('Persian and English are both made sure of, not assumed', () async {
      final models = FakeModels();
      final t = MlKitTranslator(models: models);
      expect(await t.isReady('en'), isFalse);
      await t.prepare('en');
      expect(models.downloaded, containsAll(['fa', 'en']));
      expect(await t.isReady('en'), isTrue);
    });

    test('a download ML Kit reports as failed is a failure, not "ready"', () async {
      final t = MlKitTranslator(models: FakeModels(downloadsWork: false));
      await expectLater(t.prepare('en'), throwsA(anything));
      expect(await t.isReady('en'), isFalse);
    });

    test('models already on the phone are not downloaded again', () async {
      final models = FakeModels(present: {'fa', 'en'});
      await MlKitTranslator(models: models).prepare('en');
      expect(models.downloaded, isEmpty);
    });
  });

  testWidgets('when the translation model cannot be downloaded, Google Translate is offered instead', (tester) async {
    final opened = <Uri>[];
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        const PoemScreen(id: 2130),
        prefs: prefs,
        repo: FixtureRepository(),
        overrides: [
          translatorProvider.overrideWithValue(FailingDeviceTranslator()),
          urlLauncherProvider.overrideWithValue((u) async {
            opened.add(u);
            return true;
          }),
        ],
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('ترجمه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بارگیری'));
    await settle(tester);
    final action = find.widgetWithText(SnackBarAction, 'باز کردن در Google Translate');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await settle(tester);
    expect(opened.single.host, 'translate.google.com');
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('every item in the poem menu lines up, the Tajik switch too', (tester) async {
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository()));
    await settle(tester);
    await tester.tap(find.byTooltip('بیشتر'));
    await tester.pumpAndSettle();
    final start = tester.getTopRight(find.text('بزرگ‌نمایی')).dx; // RTL: text starts on the right
    expect(tester.getTopRight(find.text('خط تاجیکی (سیریلیک)')).dx, moreOrLessEquals(start, epsilon: 1));
    expect(tester.getTopRight(find.text('مشاهده در گنجور')).dx, moreOrLessEquals(start, epsilon: 1));
    await tester.tapAt(Offset.zero);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('on a phone the top bar has no squeezed title (it is on the page already)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository()));
    await settle(tester);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('غزل شمارهٔ ۱')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('on a wide screen the title stays in the top bar', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await mockPrefs();
    await tester.pumpWidget(testApp(const PoemScreen(id: 2130), prefs: prefs, repo: FixtureRepository()));
    await settle(tester);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('غزل شمارهٔ ۱')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
