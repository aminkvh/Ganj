import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/net/request_pool.dart';

void main() {
  test('never runs more than max tasks at once', () async {
    final pool = RequestPool(2);
    var running = 0, peak = 0;
    final gates = List.generate(5, (_) => Completer<void>());
    final futures = [
      for (final g in gates)
        pool.run(() async {
          running++;
          peak = max(peak, running);
          await g.future;
          running--;
        }),
    ];
    await Future<void>.delayed(Duration.zero);
    expect(running, 2);
    for (final g in gates) {
      g.complete();
      await Future<void>.delayed(Duration.zero);
    }
    await Future.wait(futures);
    expect(peak, 2);
  });

  test('a failing task releases its slot', () async {
    final pool = RequestPool(1);
    await expectLater(pool.run<void>(() async => throw StateError('x')), throwsStateError);
    expect(await pool.run(() async => 7), 7);
  });
}
