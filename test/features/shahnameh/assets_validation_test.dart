import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/data/models.dart';
import 'package:ganj/features/shahnameh/data/shahnameh_data.dart';
import 'package:ganj/features/shahnameh/data/world_loader.dart';

/// The real bundled world: curated files must agree with Ganjoor's snapshot.
ShWorld bundledWorld() {
  String f(String name) => File('assets/seed/shahnameh/$name').readAsStringSync();
  return loadWorld(
    generated: f('generated.json'),
    ages: f('ages.json'),
    places: f('places.json'),
    namesEn: f('names_en.json'),
  );
}

void main() {
  final w = bundledWorld();
  final last = w.sections.length - 1;

  test('the snapshot has the 60 story sections', () => expect(w.sections, hasLength(60)));

  test('ages cover every section once, in order', () {
    expect(w.ages.first.from, 0);
    expect(w.ages.last.to, last);
    for (var i = 1; i < w.ages.length; i++) {
      expect(w.ages[i].from, w.ages[i - 1].to + 1, reason: w.ages[i].id);
    }
  });

  test('reigns fall inside their age and name real kings', () {
    for (final a in w.ages) {
      for (final r in a.reigns) {
        expect(a.contains(r.from) && a.contains(r.to), isTrue, reason: r.en);
        if (r.king != null) expect(w.people, contains(r.king), reason: r.en);
      }
    }
  });

  test('stories point at real sections, people and places', () {
    final ids = <String>{};
    for (final s in w.stories) {
      expect(ids.add(s.id), isTrue, reason: 'duplicate story ${s.id}');
      expect(s.sections, isNotEmpty, reason: s.id);
      for (final o in s.sections) {
        expect(o, inInclusiveRange(0, last), reason: s.id);
      }
      for (final p in s.people) {
        expect(w.people, contains(p), reason: '${s.id} → person $p');
      }
      for (final p in s.places) {
        expect(w.placeById(p), isNotNull, reason: '${s.id} → place $p');
      }
    }
  });

  test('places are on the globe, in a known region, and linked to real stories', () {
    final ids = <String>{};
    for (final p in w.places) {
      expect(ids.add(p.id), isTrue, reason: 'duplicate place ${p.id}');
      expect(p.lat, inInclusiveRange(-90, 90), reason: p.id);
      expect(p.lng, inInclusiveRange(-180, 180), reason: p.id);
      expect(kRegions, contains(p.region), reason: p.id);
      for (final s in p.stories) {
        expect(w.storyById(s), isNotNull, reason: '${p.id} → story $s');
      }
    }
  });

  test('routes run through real places of a real story', () {
    for (final r in w.routes) {
      expect(w.storyById(r.story), isNotNull, reason: r.id);
      expect(r.places.length, greaterThan(1), reason: r.id);
      for (final p in r.places) {
        expect(w.placeById(p), isNotNull, reason: '${r.id} → $p');
      }
    }
  });

  test('English names belong to people in the snapshot', () {
    final en = jsonDecode(File('assets/seed/shahnameh/names_en.json').readAsStringSync()) as Map<String, dynamic>;
    expect(en.length, greaterThanOrEqualTo(100));
    for (final id in en.keys) {
      expect(w.people, contains(int.parse(id)), reason: 'names_en $id');
    }
  });

  test('every king of a reign and every story protagonist has an English name', () {
    for (final a in w.ages) {
      for (final r in a.reigns) {
        if (r.king != null) expect(w.people[r.king]!.en, isNotNull, reason: r.en);
      }
    }
    for (final s in w.stories) {
      for (final p in s.people) {
        expect(w.people[p]!.en, isNotNull, reason: '${s.id} → ${w.people[p]!.name}');
      }
    }
  });

  test("the bundled data passes the app's own check for published data", () {
    expect(usableShahnamehData(File('assets/seed/shahnameh/generated.json').readAsStringSync()), isTrue);
  });
}
