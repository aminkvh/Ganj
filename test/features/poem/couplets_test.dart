import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/features/poem/couplets.dart';

import '../../support/fixtures.dart';

Verse v(int order, int pos, {int? ci}) => Verse(vOrder: order, position: pos, text: 't$order', coupletIndex: ci);

void main() {
  test('ghazal 1: seven two-line beyts', () {
    final cs = groupCouplets(poem2130().verses);
    expect(cs, hasLength(7));
    expect(cs.every((c) => c.kind == CoupletKind.beyt && c.verses.length == 2), isTrue);
    expect(cs.first.summary, isNotNull);
  });

  test('trailing paragraph is its own couplet', () {
    final cs = groupCouplets(poem77000().verses);
    expect(cs, hasLength(7));
    expect(cs.last.kind, CoupletKind.paragraph);
    expect(cs.last.verses, hasLength(1));
  });

  test('band lines (2 then 3) form one centred couplet', () {
    final cs = groupCouplets([
      v(1, VersePosition.right, ci: 0),
      v(2, VersePosition.left, ci: 0),
      v(3, VersePosition.centered1, ci: 1),
      v(4, VersePosition.centered2, ci: 1),
    ]);
    expect(cs.map((c) => c.kind), [CoupletKind.beyt, CoupletKind.band]);
    expect(cs.last.verses.map((x) => x.vOrder), [3, 4]);
  });

  test('missing coupletIndex is rebuilt from positions instead of merging everything', () {
    final cs = groupCouplets([
      v(1, VersePosition.right),
      v(2, VersePosition.left),
      v(3, VersePosition.single),
      v(4, VersePosition.right),
      v(5, VersePosition.left),
      v(6, VersePosition.comment),
    ]);
    expect(cs.map((c) => c.kind), [CoupletKind.beyt, CoupletKind.single, CoupletKind.beyt, CoupletKind.comment]);
    expect(cs.map((c) => c.index), [0, 1, 2, 3]);
  });

  test('out-of-order verses are sorted by vOrder', () {
    final cs = groupCouplets([v(2, VersePosition.left, ci: 0), v(1, VersePosition.right, ci: 0)]);
    expect(cs.single.verses.map((x) => x.vOrder), [1, 2]);
  });
}
