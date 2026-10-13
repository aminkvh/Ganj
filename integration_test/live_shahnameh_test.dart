import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/app.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/player/player_controller.dart';
import 'package:ganj/features/poem/poem_screen.dart';
import 'package:ganj/features/settings/settings_controller.dart';
import 'package:ganj/features/shahnameh/ui/network_view.dart';
import 'package:ganj/features/shahnameh/ui/people_tab.dart';
import 'package:ganj/features/shahnameh/ui/person_sheet.dart';
import 'package:ganj/features/shahnameh/ui/reader_chips.dart';
import 'package:ganj/features/shahnameh/ui/timeline_river.dart';
import 'package:ganj/features/shahnameh/ui/tree_view.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_audio_backend.dart';

/// Live end-to-end check of «جهان شاهنامه» against api.ganjoor.net: the bundled world loads
/// through the real asset bundle, live evidence couplets and tagged poems arrive, and a real
/// Shahnameh poem carries its people.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final shots = Directory('build/e2e_shots/shahnameh')..createSync(recursive: true);
  final boundary = GlobalKey();

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await tester.runAsync(() => ro.toImage(pixelRatio: 1));
    final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
    File('${shots.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  /// Real time passes (network, isolates) until [f] shows.
  Future<void> waitFor(WidgetTester tester, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 5 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(f, findsWidgets);
  }

  testWidgets('live: the World of the Shahnameh', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'theme': ThemeMode.light.index});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDb(NativeDatabase.memory());
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            appDbProvider.overrideWithValue(db),
            audioBackendProvider.overrideWithValue(FakeAudioBackend()),
            ganjoorApiProvider.overrideWithValue(GanjoorApi(dio: createDio(), cache: HttpCache(db))),
          ],
          child: const GanjApp(),
        ),
      ),
    );
    await waitFor(tester, find.byKey(const ValueKey('poet-filter')));

    // Home → menu → the hub (wide window: the river first).
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'جهان شاهنامه'));
    await waitFor(tester, find.byType(TimelineRiver));
    await shot(tester, '01_river');

    // People → Rostam, with live evidence couplets.
    DefaultTabController.of(tester.element(find.byType(TabBarView))).animateTo(2);
    await waitFor(tester, find.byType(PeopleTab));
    await tester.enterText(find.byType(TextField).first, 'تهمتن');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PersonRow).first);
    await waitFor(tester, find.byType(PersonPanel));
    await waitFor(tester, find.textContaining('مستند'));
    await shot(tester, '02_rostam');
    await tester.tap(find.textContaining('مستند').first);
    await tester.pumpAndSettle();
    await shot(tester, '03_rostam_evidence');

    // His tagged couplets → a real Shahnameh poem, with its people under it.
    final panelScroll = find.descendant(of: find.byType(PersonPanel), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('اشعار برچسب‌خورده'), 400, scrollable: panelScroll);
    final tagged = find.descendant(of: find.byType(PersonPanel), matching: find.byType(ListTile));
    await waitFor(tester, tagged);
    await tester.scrollUntilVisible(tagged.first, 200, scrollable: panelScroll);
    await tester.pumpAndSettle();
    await tester.tap(tagged.first);
    // The poem opens at the tagged couplet; its people sit above the verses.
    await waitFor(tester, find.byType(PoemScreen));
    await tester.scrollUntilVisible(
      find.byType(ShahnamehPeopleChips),
      -400,
      scrollable: find.descendant(of: find.byType(PoemScreen), matching: find.byType(Scrollable)).first,
    );
    await waitFor(tester, find.widgetWithText(ActionChip, 'زال'));
    await shot(tester, '04_poem_chips');

    // Back to the hub: the network, the map, a tree; then the English interface.
    Navigator.of(tester.element(find.byType(PoemScreen))).pop();
    await tester.pumpAndSettle();
    final sheetNetwork = find.text('نمایش در شبکه');
    await tester.scrollUntilVisible(
      sheetNetwork,
      -400,
      scrollable: find.descendant(of: find.byType(PersonPanel), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(sheetNetwork);
    await waitFor(tester, find.byType(NetworkView));
    await shot(tester, '05_network');

    DefaultTabController.of(tester.element(find.byType(TabBarView))).animateTo(1);
    await waitFor(tester, find.byKey(const ValueKey('pin-damavand')));
    await shot(tester, '06_map');

    DefaultTabController.of(tester.element(find.byType(TabBarView))).animateTo(3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('خاندان رستم'));
    await waitFor(tester, find.byType(FamilyTreeView));
    await shot(tester, '07_tree');
    Navigator.of(tester.element(find.byType(FamilyTreeView))).pop();
    await tester.pumpAndSettle();

    ProviderScope.containerOf(tester.element(find.byType(TabBarView))).read(settingsProvider.notifier).setLanguage('en');
    await tester.pumpAndSettle();
    DefaultTabController.of(tester.element(find.byType(TabBarView))).animateTo(0);
    await waitFor(tester, find.text('World of the Shahnameh'));
    await shot(tester, '08_river_en');
  });
}
