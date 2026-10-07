import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/text/html_text.dart';
import 'package:ganj/core/text/jalali.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/library/poet_audio.dart';
import 'package:ganj/features/player/audio_store.dart';
import 'package:ganj/features/player/player_controller.dart';

import '../support/fake_audio_backend.dart';
import '../support/fixture_repository.dart';
import '../support/fixtures.dart';

class FlakyStore implements AudioStore {
  final done = <int>[];

  @override
  Future<void> download(Recitation r, {void Function(double)? onProgress}) async {
    if (r.id == 2) throw StateError('network');
    done.add(r.id);
  }

  @override
  bool isDownloaded(int id) => done.contains(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Recitation rec(int id) => Recitation.fromJson({'id': id, 'poemId': id, 'mp3Url': 'https://i.ganjoor.net/a/$id.mp3'});

void main() {
  group('htmlToText edge cases', () {
    test('hex and named direction entities', () {
      expect(htmlToText('می&#x200c;خواهم&rlm;'), 'می‌خواهم‏');
      expect(htmlToText('a&shy;b&lrm;'), 'a­b‎');
    });
    test('out-of-range numeric entity does not throw', () {
      expect(htmlToText('x&#99999999;y'), 'xy');
    });
    test('div and li become lines', () {
      expect(htmlToText('<div>یک</div><ul><li>دو</li><li>سه</li></ul>'), 'یک\nدو\nسه');
    });
  });

  test('Jalali dates', () {
    expect(toJalali(DateTime(2012, 12, 30)), (1391, 10, 10));
    expect(toJalali(DateTime(2026, 3, 21)), (1405, 1, 1));
    expect(faDate(DateTime(2026, 10, 6)), '۱۴۰۵/۷/۱۴');
  });

  test('bulk download continues past a failed item', () async {
    final store = FlakyStore();
    var failures = 0;
    await downloadPlan(PoetAudioPlan([rec(1), rec(2), rec(3)]), store, onFailure: (_) => failures++);
    expect(store.done, [1, 3]);
    expect(failures, 1);
  });

  test('a position event after the recitation finished does not re-light a verse', () async {
    final backend = FakeAudioBackend();
    final c = ProviderContainer(
      overrides: [
        audioBackendProvider.overrideWithValue(backend),
        poetryRepositoryProvider.overrideWithValue(FixtureRepository()),
      ],
    );
    addTearDown(c.dispose);
    final poem = poem2130();
    await c.read(playerProvider.notifier).play(poem, poem.recitations.first);
    backend.emitCompleted();
    await Future<void>.delayed(Duration.zero);
    backend.emitPosition(const Duration(seconds: 90));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(playerProvider).currentVOrder, isNull);
  });
}
