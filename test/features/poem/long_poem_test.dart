import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/user/user_repository.dart';
import 'package:ganj/features/poem/widgets/beyt_view.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/features/player/player_controller.dart';

import '../../support/fake_audio_backend.dart';

import '../../support/fixture_repository.dart';
import '../../support/test_app.dart';

/// A synthetic masnavi section: [n] two-line couplets with unique words.
Poem longPoem(int n) => Poem(
  id: 999,
  title: 'مثنوی آزمایشی',
  fullTitle: 'آزمون » مثنوی آزمایشی',
  fullUrl: '/test/long',
  plainText: '',
  verses: [
    for (var i = 0; i < n; i++) ...[
      Verse(vOrder: 2 * i + 1, position: VersePosition.right, text: 'مصراع نخست بیت $i', coupletIndex: i),
      Verse(vOrder: 2 * i + 2, position: VersePosition.left, text: 'مصراع دوم بیت $i', coupletIndex: i),
    ],
  ],
);

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> open(WidgetTester tester, {AppDb? db, int? couplet}) async {
    final repo = FixtureRepository()..poems[999] = longPoem(1500);
    final prefs = await mockPrefs();
    await tester.pumpWidget(
      testApp(
        PoemScreen(id: 999, couplet: couplet),
        prefs: prefs,
        repo: repo,
        db: db,
      ),
    );
    await settle(tester);
  }

  bool onScreen(WidgetTester tester, String text) {
    final f = find.text(text);
    if (f.evaluate().isEmpty) return false;
    final top = tester.getRect(f).top;
    return top >= 0 && top <= 600;
  }

  testWidgets('a 1500-couplet poem builds only what is on screen', (tester) async {
    await open(tester);
    expect(find.text('مصراع نخست بیت 0'), findsOneWidget);
    expect(find.byType(BeytView, skipOffstage: false).evaluate().length, lessThan(200));
  });

  testWidgets('find-in-poem jumps to the last couplet', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('جستجو در شعر'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('find-field')), 'دوم بیت 1499');
    for (var i = 0; i < 8; i++) {
      await tester.pumpAndSettle();
    }
    expect(find.text('مصراع دوم بیت 1499'), findsOneWidget);
    expect(tester.getRect(find.text('مصراع دوم بیت 1499')).top, inInclusiveRange(0, 600));
  });

  testWidgets('opening a poem records the visit right away', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    await open(tester, db: db);
    final h = await tester.runAsync(() => UserRepository(db).history());
    expect(h!.single.poemId, 999);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('reopening returns to the couplet where the reader left', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    await tester.runAsync(() => UserRepository(db).recordVisit(999, 't', 'T', couplet: 1200));
    await open(tester, db: db);
    expect(onScreen(tester, 'مصراع نخست بیت 1200'), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('a beyt link (?c=) opens at that beyt', (tester) async {
    await open(tester, couplet: 1400);
    expect(onScreen(tester, 'مصراع نخست بیت 1400'), isTrue);
  });

  testWidgets('going to the background saves the current couplet', (tester) async {
    final db = AppDb(NativeDatabase.memory());
    await open(tester, db: db);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    final c = await tester.runAsync(() => UserRepository(db).lastCouplet(999));
    expect(c, greaterThan(5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  group('couplets of different heights (realistic text)', () {
    // Some hemistichs wrap to several lines on a phone, so heights vary a lot.
    Poem varied(int n) => Poem(
      id: 999,
      title: 'مثنوی آزمایشی',
      fullTitle: 'آزمون » مثنوی آزمایشی',
      fullUrl: '/test/long',
      plainText: '',
      verses: [
        for (var i = 0; i < n; i++) ...[
          Verse(
            vOrder: 2 * i + 1,
            position: VersePosition.right,
            text: 'مصراع نخست بیت $i ${List.filled((i * 7) % 23, 'واژه').join(' ')}',
            coupletIndex: i,
          ),
          Verse(vOrder: 2 * i + 2, position: VersePosition.left, text: 'مصراع دوم بیت $i', coupletIndex: i),
        ],
      ],
    );

    Future<void> openVaried(WidgetTester tester, {AppDb? db, int? couplet}) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = FixtureRepository()..poems[999] = varied(1500);
      final prefs = await mockPrefs();
      await tester.pumpWidget(
        testApp(
          PoemScreen(id: 999, couplet: couplet),
          prefs: prefs,
          repo: repo,
          db: db,
        ),
      );
      await settle(tester);
    }

    bool visible(WidgetTester tester, String text) {
      final f = find.text(text);
      if (f.evaluate().isEmpty) return false;
      final r = tester.getRect(f);
      return r.top >= 0 && r.top <= 720;
    }

    for (final target in [300, 800, 1200]) {
      testWidgets('a beyt link reaches couplet $target exactly', (tester) async {
        await openVaried(tester, couplet: target);
        expect(visible(tester, 'مصراع دوم بیت $target'), isTrue);
      });
    }

    testWidgets('find-in-poem reaches a far couplet', (tester) async {
      await openVaried(tester);
      await tester.tap(find.byTooltip('جستجو در شعر'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('find-field')), 'دوم بیت 800');
      await settle(tester);
      expect(visible(tester, 'مصراع دوم بیت 800'), isTrue);
    });

    testWidgets('audio follow brings a far couplet into view', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const rec = Recitation(
        id: 777,
        poemId: 999,
        title: 't',
        artist: 'a',
        artistUrl: '',
        mp3Url: 'https://i.ganjoor.net/a/777.mp3',
        mp3Size: 1,
        audioOrder: 1,
        inSync: true,
      );
      final poem = varied(1500).copyWith(recitations: [rec]);
      final repo = FixtureRepository()..poems[999] = poem;
      repo.syncs[777] = [for (var v = 1; v <= 3000; v++) SyncPoint(v, v * 1000)];
      final backend = FakeAudioBackend();
      final prefs = await mockPrefs();
      await tester.pumpWidget(testApp(const PoemScreen(id: 999), prefs: prefs, repo: repo, backend: backend));
      await settle(tester);
      final c = ProviderScope.containerOf(tester.element(find.byType(PoemScreen)));
      await c.read(playerProvider.notifier).play(poem, rec);
      backend.emitPosition(const Duration(seconds: 2401)); // vOrder 2401 = first line of couplet 1200
      await settle(tester);
      expect(visible(tester, 'مصراع دوم بیت 1200'), isTrue);
    });

    testWidgets('the resume point is not overwritten right after opening', (tester) async {
      final db = AppDb(NativeDatabase.memory());
      await tester.runAsync(() => UserRepository(db).recordVisit(999, 't', 'T', couplet: 1200));
      await openVaried(tester, db: db);
      expect(await tester.runAsync(() => UserRepository(db).lastCouplet(999)), 1200);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(db.close);
    });
  });
}
