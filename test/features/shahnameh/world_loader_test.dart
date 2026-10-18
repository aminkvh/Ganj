import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/data/models.dart';
import 'package:ganj/features/shahnameh/data/relation_kinds.dart';
import 'package:ganj/features/shahnameh/data/world_loader.dart';

/// The tiny hand-made world in test/fixtures/shahnameh.
ShWorld fixtureWorld() {
  String f(String name) => File('test/fixtures/shahnameh/$name').readAsStringSync();
  return loadWorld(
    generated: f('generated.json'),
    ages: f('ages.json'),
    places: f('places.json'),
    namesEn: f('names_en.json'),
  );
}

void main() {
  final w = fixtureWorld();

  test('people carry aliases, descriptions and English names', () {
    expect(w.people[30]!.aliases, ['تهمتن', 'پور زال']);
    expect(w.people[30]!.en, 'Rostam');
    expect(w.people[8]!.description, 'شاه ماردوش');
    expect(w.people[2]!.en, isNull);
  });

  test('displayName falls back to Persian in English', () {
    expect(w.displayName(30, english: true), 'Rostam');
    expect(w.displayName(2, english: true), 'سیامک');
    expect(w.displayName(30, english: false), 'رستم');
  });

  test('edgesOf finds a person on either end', () {
    expect(w.edgesOf(2).map((e) => (e.a, e.b)).toSet(), {(1, 2), (2, 4), (40, 2)});
  });

  test('ties another book alone states are left out; Shahnameh and unsourced ties stay', () {
    // Edge [30, 8, A:14] is attested only in the Khamse (111); [30, 8, A:77] (an unknown kind, shown as A:99) has no source.
    expect(w.edgesOf(8).map((e) => e.kind.key).toSet(), {'A:5', 'A:99'});
    expect(w.edgesOf(1).firstWhere((e) => e.b == 2).books, [33]);
    expect(w.edgesOf(8).firstWhere((e) => e.kind.key == 'A:5').books, [33, 111]);
    expect(w.edgesOf(8).firstWhere((e) => e.kind.key == 'A:99').books, isEmpty);
  });

  test('relation kinds follow ganjoor.net', () {
    expect(relationKind('A', 14).fa, 'قاتل');
    expect(relationKind('A', 14).family, RelationFamily.conflict);
    expect(relationKind('R', 0).family, RelationFamily.kin);
    expect(relationKind('A', 0).family, RelationFamily.service);
    expect(relationKind('A', 4).family, RelationFamily.alliance);
  });

  test('an unknown kind reads as «سایر» instead of failing', () {
    final e = w.edgesOf(30).firstWhere((e) => e.b == 8);
    expect(e.kind.fa, 'سایر');
  });

  test('ancestor edges keep the generation gap', () {
    expect(w.edgesOf(33).single.degree, 2);
  });

  test('sections, poems and summaries', () {
    expect(w.sections.map((s) => s.catId), [35, 36, 39]);
    expect(w.sections[0].poems.map((p) => p.id), [100, 103]);
    expect(w.sectionOfPoem(102)!.order, 2);
    expect(w.sectionOfPoem(999), isNull);
    expect(w.summaries[100], 'کیومرث نخستین شاه جهان شد.');
  });

  test('presence, passing mentions and poem people', () {
    expect(w.presence[4], [0, 1]);
    expect(w.passing[30], [2]);
    expect(w.firstSection(4), 0);
    expect(w.firstSection(30), 2, reason: 'a passing mention still places a person');
    expect(w.firstSection(32), isNull);
    expect(w.poemPeople[102], [(8, 0), (30, 1)]);
  });

  test('ages, reigns and stories', () {
    expect(w.ages.map((a) => a.id), ['pishdadian', 'kayanian']);
    expect(w.ageOfSection(1).id, 'pishdadian');
    expect(w.ageOfSection(2).id, 'kayanian');
    expect(w.ages[0].reigns[1].king, 4);
    expect(w.stories.map((s) => s.id), ['kayumars', 'zahhak']);
    expect(w.storyById('zahhak')!.places, ['damavand', 'amol']);
    expect(w.stories[0].age, 0);
  });

  test('curated places, routes and Ganjoor place tags', () {
    expect(w.places.map((p) => p.id), ['alborz', 'damavand', 'amol']);
    expect(w.places[0].precision, PlacePrecision.mythic);
    expect(w.places[2].ganjoorId, 91);
    expect(w.routes.single.places, ['damavand', 'amol']);
    expect(w.ganjoorTags.single.locationId, 91);
    expect(w.ganjoorTags.single.poemId, 102);
  });

  test('tree roots', () => expect(w.treeRoots, [1, 30]));

  test("Ganjoor's AI marks: summaries, tags and descriptions", () {
    expect(w.aiSummaries, {100});
    expect(w.isAiTag(100, 1), isTrue);
    expect(w.isAiTag(100, 2), isFalse);
    expect(w.people[8]!.aiDescription, isTrue);
    expect(w.people[30]!.aiDescription, isFalse);
    expect(w.hasAiTags(1), isTrue);
    expect(w.hasAiTags(2), isFalse);
  });
}
