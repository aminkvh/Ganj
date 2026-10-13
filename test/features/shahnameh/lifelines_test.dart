import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/features/shahnameh/data/lifelines.dart';

void main() {
  test('consecutive sections join into one segment', () {
    expect(lifelineSegments([3, 4, 5]), [(3, 5)]);
  });

  test('a one-section gap is bridged, a longer one splits', () {
    expect(lifelineSegments([3, 5]), [(3, 5)]);
    expect(lifelineSegments([3, 6]), [(3, 3), (6, 6)]);
  });

  test('unsorted and repeated input', () {
    expect(lifelineSegments([9, 2, 3, 9]), [(2, 3), (9, 9)]);
  });

  test('a single appearance is a one-section segment', () {
    expect(lifelineSegments([7]), [(7, 7)]);
  });

  test('nothing in, nothing out', () => expect(lifelineSegments([]), isEmpty));

  test('maxGap 0 bridges nothing', () {
    expect(lifelineSegments([1, 3], maxGap: 0), [(1, 1), (3, 3)]);
  });
}
