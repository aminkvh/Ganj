import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/features/poem/couplets.dart';
import 'package:ganj/features/translate/translation_source.dart';

import '../support/fixtures.dart';

/// Machine translation of a 14th-century verse is poor; Ganjoor's plain-Persian meaning of
/// the beyt is modern prose, which translates well. So translate the meaning when there is one.
void main() {
  test('a beyt with a plain-Persian meaning is translated from that meaning, not the verse', () {
    final first = groupCouplets(poem2130().verses).first;
    expect(first.summary, isNotNull, reason: 'the fixture beyt has a meaning');
    final s = translationSource(first);
    expect(s.text, first.summary!.text);
    expect(s.fromMeaning, isTrue);
  });

  test('a beyt without a meaning is translated from its verses', () {
    final c = Couplet(
      index: 0,
      kind: CoupletKind.beyt,
      verses: [Verse(vOrder: 1, position: VersePosition.right, text: 'الف', coupletIndex: 0)],
    );
    final s = translationSource(c);
    expect(s.text, 'الف');
    expect(s.fromMeaning, isFalse);
  });

  test('the whole poem (for Google Translate) uses meanings where they exist, verses elsewhere', () {
    final cs = groupCouplets(poem2130().verses);
    final text = translationSourceForPoem(cs);
    expect(text, contains(cs.first.summary!.text));
    expect(text.split('\n\n'), hasLength(cs.length));
  });
}
