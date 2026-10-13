import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/ui/pin_clusters.dart';

void main() {
  test('pins far apart stay where they are', () {
    final c = clusterPins({'a': const Offset(0, 0), 'b': const Offset(100, 0)});
    expect(c, hasLength(2));
    expect(c.every((g) => g.ids.length == 1 && g.offsets.single == Offset.zero), isTrue);
  });

  test('a few close pins fan out in a small ring around them', () {
    final c = clusterPins({'a': const Offset(0, 0), 'b': const Offset(5, 0), 'c': const Offset(0, 5)});
    expect(c, hasLength(1));
    final g = c.single;
    expect(g.isBubble, isFalse);
    expect(g.ids, hasLength(3));
    for (final o in g.offsets) {
      expect(o.distance, lessThan(60), reason: 'the ring stays near its place');
    }
  });

  test('many close pins become one bubble, not a ring around the world', () {
    final c = clusterPins({for (var i = 0; i < 40; i++) 'p$i': Offset(i * 0.5, i * 0.25)});
    expect(c, hasLength(1));
    expect(c.single.isBubble, isTrue);
    expect(c.single.ids, hasLength(40));
  });

  test('a bubble sits at the middle of its pins', () {
    final c = clusterPins({for (var i = 0; i < 10; i++) 'p$i': Offset(i * 2.0, 0)});
    expect(c.single.centre.dx, closeTo(9, 0.01));
  });
}
