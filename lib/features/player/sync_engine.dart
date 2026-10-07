import '../../data/api/dto/recitation.dart';

/// Verse-start timeline of one recitation; answers "which verse is playing?" by binary search.
class SyncTimeline {
  SyncTimeline(List<SyncPoint> points, {Set<int>? validVOrders}) {
    final sorted = [...points]..sort((a, b) => a.ms.compareTo(b.ms));
    final seen = <int>{};
    for (final p in sorted) {
      if (p.vOrder == -2) {
        _end ??= Duration(milliseconds: p.ms);
        continue;
      }
      if (p.vOrder <= 0) continue; // title / other markers
      if (validVOrders != null && !validVOrders.contains(p.vOrder)) continue;
      if (!seen.add(p.vOrder)) continue; // keep the earliest duplicate
      _starts.add(p.ms);
      _orders.add(p.vOrder);
    }
  }

  final _starts = <int>[];
  final _orders = <int>[];
  Duration? _end;

  bool get isEmpty => _starts.isEmpty;
  Duration? get end => _end;

  /// The verse whose start is the latest one ≤ [pos]; null before the first verse or after the end marker.
  int? vOrderAt(Duration pos) {
    final ms = pos.inMilliseconds;
    if (_starts.isEmpty || ms < _starts.first) return null;
    if (_end != null && ms >= _end!.inMilliseconds) return null;
    var lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return _orders[lo];
  }

  Duration? startOf(int vOrder) {
    final i = _orders.indexOf(vOrder);
    return i < 0 ? null : Duration(milliseconds: _starts[i]);
  }
}
