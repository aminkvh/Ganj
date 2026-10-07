import 'dart:async';
import 'dart:collection';

/// Caps concurrent requests; a finished task hands its slot straight to the next waiter.
class RequestPool {
  RequestPool(this.maxConcurrent);

  final int maxConcurrent;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active < maxConcurrent) {
      _active++;
    } else {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future; // slot transferred by the finishing task
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
