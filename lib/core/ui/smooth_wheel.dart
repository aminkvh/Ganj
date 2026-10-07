import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Spreads a mouse-wheel jump over a few frames with an ease-out, like a browser does.
class WheelSmoother {
  /// Time constant of the ease-out: about 90% of a notch lands within ~80 ms.
  static const _tau = 35.0; // ms
  double _remaining = 0;

  bool get active => _remaining != 0;

  /// A new notch adds to what is still to come; turning the wheel back starts over.
  void add(double delta) {
    _remaining = _remaining.sign == delta.sign ? _remaining + delta : delta;
  }

  /// The distance to scroll in a frame that took [dt].
  double step(Duration dt) {
    final ms = math.max(dt.inMicroseconds / 1000, 1.0);
    var s = _remaining * (1 - math.exp(-ms / _tau));
    if ((_remaining - s).abs() < 0.5) s = _remaining;
    _remaining -= s;
    return s;
  }
}

/// App binding that makes mouse-wheel scrolling smooth on Windows and Linux, for every
/// scrollable at once: Flutter itself jumps the whole notch in one frame there. Trackpads,
/// touch and sideways (Shift+wheel) scrolling pass through untouched.
class SmoothWheelBinding extends WidgetsFlutterBinding {
  /// Must be the first binding created: call it at the very start of `main`.
  SmoothWheelBinding();

  final _smoother = WheelSmoother();
  PointerScrollEvent? _last;
  Duration? _lastFrame;
  bool _scheduled = false;

  static bool get _enabled =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux);

  @override
  void handlePointerEvent(PointerEvent event) {
    if (_enabled &&
        event is PointerScrollEvent &&
        event.kind == PointerDeviceKind.mouse &&
        event.scrollDelta.dx == 0 &&
        event.scrollDelta.dy != 0) {
      _last = event;
      _smoother.add(event.scrollDelta.dy);
      _schedule();
      return;
    }
    super.handlePointerEvent(event);
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleFrameCallback(_tick);
    scheduleFrame();
  }

  void _tick(Duration now) {
    _scheduled = false;
    final dt = _lastFrame == null ? const Duration(microseconds: 16667) : now - _lastFrame!;
    final e = _last;
    if (e == null || !_smoother.active) {
      _lastFrame = null;
      return;
    }
    final dy = _smoother.step(dt > const Duration(milliseconds: 50) ? const Duration(microseconds: 16667) : dt);
    super.handlePointerEvent(
      PointerScrollEvent(
        timeStamp: e.timeStamp,
        kind: e.kind,
        device: e.device,
        position: e.position,
        viewId: e.viewId,
        scrollDelta: Offset(0, dy),
      ),
    );
    if (_smoother.active) {
      _lastFrame = now;
      _schedule();
    } else {
      _lastFrame = null;
    }
  }
}
