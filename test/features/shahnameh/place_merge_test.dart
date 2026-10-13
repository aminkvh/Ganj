import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/data/models.dart';
import 'package:ganj/features/shahnameh/data/place_merge.dart';

const _amol = ShPlace(id: 'amol', fa: 'آمل', en: 'Amol', lat: 36.47, lng: 52.35, region: 'iran', ganjoorId: 91);
const _rey = ShPlace(id: 'rey', fa: 'ری', en: 'Rey', lat: 35.59, lng: 51.43, region: 'iran');

ShPlaceTag tag(int loc, String name, double lat, double lng, {int poem = 1, int c = 0}) =>
    ShPlaceTag(locationId: loc, name: name, lat: lat, lng: lng, poemId: poem, couplet: c);

void main() {
  test('distance', () {
    expect(haversineKm(35.69, 51.39, 32.65, 51.67), closeTo(339, 5), reason: 'Tehran–Isfahan');
  });

  test("a tag joins the curated place with Ganjoor's location id", () {
    final m = mergePlaces([_amol], [tag(91, 'آمل', 36.43, 52.21, poem: 7, c: 3)]);
    expect(m, hasLength(1));
    expect(m.single.id, 'amol');
    expect(m.single.tags.single.poemId, 7);
    expect(m.single.fromGanjoor, isFalse);
  });

  test('or the curated place of the same name within 20 km', () {
    final m = mergePlaces([_rey], [tag(500, 'ری', 35.6, 51.45)]);
    expect(m.single.id, 'rey');
    expect(m.single.tags, hasLength(1));
  });

  test('the same name far away is a different place', () {
    final m = mergePlaces([_rey], [tag(500, 'ری', 30.0, 60.0)]);
    expect(m, hasLength(2));
    expect(m.last.id, 'g500');
    expect(m.last.fromGanjoor, isTrue);
  });

  test("a place only Ganjoor knows becomes its own, with every couplet that names it", () {
    final m = mergePlaces([], [tag(8, 'بلخ', 36.7, 66.9, poem: 1), tag(8, 'بلخ', 36.7, 66.9, poem: 2)]);
    expect(m.single.id, 'g8');
    expect(m.single.fa, 'بلخ');
    expect(m.single.tags.map((t) => t.poemId), [1, 2]);
  });

  test('the same couplet tagged twice counts once', () {
    final t = tag(91, 'آمل', 36.43, 52.21, poem: 7, c: 3);
    expect(mergePlaces([_amol], [t, t]).single.tags, hasLength(1));
  });

  test('Ganjoor-only places learn their stories from the poems', () {
    final m = mergePlaces([], [tag(8, 'بلخ', 36.7, 66.9, poem: 1)], storiesOfPoem: (p) => p == 1 ? ['s1'] : []);
    expect(m.single.stories, ['s1']);
  });
}
