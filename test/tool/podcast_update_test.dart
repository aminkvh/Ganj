import 'package:flutter_test/flutter_test.dart';

import '../../tool/podcast_update.dart';

void main() {
  test("Saadia's unedited archive files are ignored, however the title is spaced", () {
    for (final t in ['بدون تدوین-غزل‌ 91 تا 100', 'بدون تدوین-غزل81 تا 90', 'بدون تدوین غزل-1 تا 10']) {
      expect(ignored('saadia', t), isTrue, reason: t);
    }
  });

  test('its regular episodes, and other podcasts, are not', () {
    expect(ignored('saadia', 'ای پیکِ پی‌خجسته که داری نشانِ دوست-غزل 101'), isFalse);
    expect(ignored('sarv', 'بدون تدوین'), isFalse);
  });
}
