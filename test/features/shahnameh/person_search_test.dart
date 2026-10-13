import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/data/person_search.dart';

import 'sh_support.dart';

void main() {
  final w = realWorld;

  test('Persian name finds the person first', () {
    expect(searchPeople(w, 'رستم').first.id, 60);
  });

  test('an alias finds the person', () {
    expect(searchPeople(w, 'تهمتن').map((p) => p.id), contains(60));
  });

  test('English names, case-insensitively', () {
    expect(searchPeople(w, 'rostam').first.id, 60);
    expect(searchPeople(w, 'SIAVASH').first.id, 121);
  });

  test('Arabic letter forms and zero-width joiners are normalized', () {
    // ي / ك instead of ی / ک.
    expect(searchPeople(w, 'كيخسرو').first.id, 153);
  });

  test('prefix matches rank above inner matches, then importance', () {
    final r = searchPeople(w, 'رست');
    expect(r.first.id, 60, reason: 'Rostam (importance 2) leads the رست… names');
  });

  test('empty query finds nothing', () => expect(searchPeople(w, '  '), isEmpty));

  test('no match', () => expect(searchPeople(w, 'zzzz'), isEmpty));
}
