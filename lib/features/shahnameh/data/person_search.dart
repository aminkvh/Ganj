import '../../../core/text/persian_normalize.dart';
import 'models.dart';

String _key(String s) => normalizePersian(s).replaceAll('‌', '').replaceAll(' ', '').toLowerCase();

/// People whose name, alias or English name matches [query]: names starting with it first,
/// then names containing it; within each, the greater figures first.
List<ShPerson> searchPeople(ShWorld w, String query) {
  final q = _key(query.trim());
  if (q.isEmpty) return const [];
  final hits = <(int rank, ShPerson p)>[];
  for (final p in w.people.values) {
    var rank = 9;
    for (final n in [p.name, ...p.aliases, ?p.en]) {
      final k = _key(n);
      if (k == q) {
        rank = 0;
      } else if (k.startsWith(q)) {
        rank = rank < 1 ? rank : 1;
      } else if (k.contains(q)) {
        rank = rank < 2 ? rank : 2;
      }
    }
    if (rank < 9) hits.add((rank, p));
  }
  hits.sort((a, b) {
    final r = a.$1.compareTo(b.$1);
    if (r != 0) return r;
    final i = b.$2.importance.compareTo(a.$2.importance);
    if (i != 0) return i;
    final pa = (w.presence[a.$2.id]?.length ?? 0), pb = (w.presence[b.$2.id]?.length ?? 0);
    return pb.compareTo(pa);
  });
  return [for (final h in hits) h.$2];
}
