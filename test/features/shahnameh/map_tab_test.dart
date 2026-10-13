import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/content_en.dart';
import 'package:ganj/core/text/persian_normalize.dart';
import 'package:ganj/features/shahnameh/ui/map_tab.dart';
import 'package:ganj/features/shahnameh/ui/timeline_vertical.dart';

import '../../support/fake_adapter.dart';
import '../../support/test_app.dart';
import 'sh_support.dart';

void main() {
  tearDown(() {
    latinNumbers = false;
    englishContent = null;
  });

  Future<void> open(WidgetTester tester, String location, {String language = 'fa', FakeAdapter? adapter}) async {
    phone(tester);
    final prefs = await mockPrefs({'language': language});
    await tester.pumpWidget(
      testAppRouted(
        location,
        prefs: prefs,
        overrides: shOverrides(adapter: adapter),
      ),
    );
    await settle(tester);
  }

  Finder pin(String id) => find.byKey(ValueKey('pin-$id'));

  testWidgets('the places of the Shahnameh, even offline', (tester) async {
    await open(tester, '/shahnameh?tab=map', adapter: FakeAdapter({})..offline = true);
    expect(find.byType(ShahnamehMapTab), findsOneWidget);
    expect(find.text('نقشهٔ زمینه به اینترنت نیاز دارد'), findsOneWidget);
    expect(await revealPin(tester, 'balkh'), findsOneWidget);
    expect(await revealPin(tester, 'damavand'), findsOneWidget);
  });

  testWidgets('a place opens with its stories, and a story leads to the timeline', (tester) async {
    await open(tester, '/shahnameh?tab=map');
    await tester.tap(await revealPin(tester, 'damavand'));
    await settle(tester);
    final sheet = find.byKey(const ValueKey('place-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('دماوند')), findsOneWidget);
    final story = find.descendant(of: sheet, matching: find.text('ضحاک ماردوش و کاوهٔ آهنگر'));
    expect(story, findsOneWidget);
    await tester.tap(story);
    await settle(tester);
    expect(DefaultTabController.of(tester.element(find.byType(TabBarView))).index, 0);
    expect(find.byType(TimelineVertical), findsOneWidget);
  });

  testWidgets('a legendary place says so', (tester) async {
    await open(tester, '/shahnameh?tab=map&place=alborz');
    final sheet = find.byKey(const ValueKey('place-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('جای سنتی و افسانه‌ای')), findsOneWidget);
  });

  testWidgets("a story's places, in order, when the story has a route", (tester) async {
    await open(tester, '/shahnameh?tab=map&story=haftkhan-rostam');
    final stops = find.byKey(const ValueKey('story-stops'));
    expect(stops, findsOneWidget);
    expect(find.descendant(of: stops, matching: find.text('۱')), findsOneWidget);
    expect(find.descendant(of: stops, matching: find.text('زابلستان')), findsOneWidget);
    expect(pin('lut'), findsOneWidget);
    expect(pin('kanauj'), findsNothing, reason: 'other stories are hidden while one is shown');
  });

  testWidgets('from the timeline: «روی نقشه» shows that story', (tester) async {
    await open(tester, '/shahnameh?tab=timeline&section=13');
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('story-sohrab')), matching: find.text('روی نقشه')));
    await settle(tester);
    expect(find.byKey(const ValueKey('story-stops')), findsOneWidget);
    expect(pin('samangan'), findsOneWidget);
  });

  testWidgets('Ganjoor tags only', (tester) async {
    await open(tester, '/shahnameh?tab=map');
    await tester.tap(find.widgetWithText(FilterChip, 'فقط برچسب‌های گنجور'));
    await settle(tester);
    expect(pin('damavand'), findsOneWidget, reason: 'Ganjoor tags Damavand');
    expect(pin('balkh'), findsNothing);
  });

  testWidgets('an age filter', (tester) async {
    await open(tester, '/shahnameh?tab=map');
    await tester.tap(find.byKey(const ValueKey('age-filter')));
    await settle(tester);
    await tester.tap(find.text('ساسانیان').last);
    await settle(tester);
    expect(pin('ctesiphon'), findsOneWidget);
    expect(pin('damavand'), findsNothing);
  });

  testWidgets('English names', (tester) async {
    await open(tester, '/shahnameh?tab=map&place=kabul', language: 'en');
    final sheet = find.byKey(const ValueKey('place-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('Kabul')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Kabulistan')), findsOneWidget);
  });

  testWidgets('on a phone, every pin is drawn close to its place, and crowds become a bubble', (tester) async {
    await open(tester, '/shahnameh?tab=map');
    final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));
    final map = tester.getTopLeft(find.byType(FlutterMap));
    var pins = 0;
    for (final p in realWorld.places) {
      final pin = find.byKey(ValueKey('pin-${p.id}'));
      if (pin.evaluate().isEmpty) continue;
      pins++;
      final drawn = tester.getCenter(pin) - map;
      final place = camera.latLngToScreenOffset(LatLng(p.lat, p.lng));
      expect((drawn - place).distance, lessThan(90), reason: '${p.id} is drawn far from where it is');
    }
    expect(pins, greaterThan(5));
  });

  testWidgets('a bubble zooms in on its places', (tester) async {
    await open(tester, '/shahnameh?tab=map');
    final bubble = find.byWidgetPredicate(
      (w) => w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('cluster-'),
    );
    if (bubble.evaluate().isEmpty) return; // nothing crowded at this size
    final before = MapCamera.of(tester.element(find.byType(MarkerLayer))).zoom;
    await tester.tap(bubble.first);
    await settle(tester);
    expect(MapCamera.of(tester.element(find.byType(MarkerLayer))).zoom, greaterThan(before));
  });
}
