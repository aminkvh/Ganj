import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/api_client.dart';
import 'package:ganj/core/net/http_cache.dart';
import 'package:ganj/data/api/ganjoor_api.dart';
import 'package:ganj/data/db/app_db.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:ganj/data/providers.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:ganj/features/map/poets_map_screen.dart';
import 'package:ganj/features/shahnameh/data/models.dart';
import 'package:ganj/features/shahnameh/data/shahnameh_providers.dart';
import 'package:ganj/features/shahnameh/data/world_loader.dart';
import 'package:drift/native.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_adapter.dart';

/// The real bundled world, read from disk once (rootBundle is slow in widget tests).
final ShWorld realWorld = () {
  String f(String name) => File('assets/seed/shahnameh/$name').readAsStringSync();
  return loadWorld(
    generated: f('generated.json'),
    ages: f('ages.json'),
    places: f('places.json'),
    namesEn: f('names_en.json'),
  );
}();

String shFx(String name) => File('test/fixtures/shahnameh/$name').readAsStringSync();

/// World from disk, live people API from fixtures (or offline), blank map tiles.
List<Override> shOverrides({FakeAdapter? adapter, ShWorld? world, bool brokenWorld = false}) {
  final a =
      adapter ??
      FakeAdapter({
        '/api/people/60/relations': shFx('relations_60.json'),
        '/api/people/60/poems': shFx('poems_60.json'),
        '/api/ganjoor/cat/39/geotag': shFx('geotag_39.json'),
        '/api/locations': '[]',
      });
  return [
    shahnamehWorldProvider.overrideWith(() => _FixedWorld(brokenWorld ? null : (world ?? realWorld))),
    ganjoorApiProvider.overrideWithValue(
      GanjoorApi(
        dio: createDio(adapter: a),
        cache: HttpCache(AppDb(NativeDatabase.memory())),
      ),
    ),
    mapTileLayerProvider.overrideWithValue(const SizedBox()),
  ];
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void wide(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A small phone (360 dp), where overflows show first.
void narrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Taps the crowd bubble nearest to a place until its own pin shows, like a reader zooming in.
Future<Finder> revealPin(WidgetTester tester, String id) async {
  final pin = find.byKey(ValueKey('pin-$id'));
  final place = realWorld.placeById(id)!;
  for (var i = 0; i < 6 && pin.evaluate().isEmpty; i++) {
    final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));
    final origin = tester.getTopLeft(find.byType(FlutterMap));
    final target = origin + camera.latLngToScreenOffset(LatLng(place.lat, place.lng));
    final bubbles = find.byWidgetPredicate(
      (w) => w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('cluster-'),
    );
    if (bubbles.evaluate().isEmpty) break;
    final nearest = bubbles
        .evaluate()
        .map((e) => find.byWidget(e.widget))
        .reduce((a, b) => (tester.getCenter(a) - target).distance <= (tester.getCenter(b) - target).distance ? a : b);
    await tester.tap(nearest);
    await settle(tester);
  }
  return pin;
}

/// A world that is simply there (or broken), without the bundle or the published data.
class _FixedWorld extends ShahnamehWorldNotifier {
  _FixedWorld(this.world);

  final ShWorld? world;

  @override
  Future<ShWorld> build() async => world ?? (throw const FormatException('broken bundle'));
}
