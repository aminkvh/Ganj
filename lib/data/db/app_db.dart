import 'package:drift/drift.dart';

import '../../core/text/persian_normalize.dart';
import 'content_schema.dart';
import 'user_schema.dart';

part 'app_db.g.dart';

/// Raw API responses (gzipped UTF-8), keyed by request path + sorted query.
class ApiCache extends Table {
  TextColumn get key => text()();
  BlobColumn get body => blob()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [ApiCache])
class AppDb extends _$AppDb {
  AppDb(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createContent();
      await _run(userSchema);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await _createContent();
      if (from < 3) await _run(userSchema);
      // v4: history remembers the couplet the reader was on (not a pixel offset).
      if (from == 3) await customStatement('ALTER TABLE history ADD COLUMN couplet_index INTEGER NOT NULL DEFAULT -1');
      // v5: the search index ignores half-spaces; rebuild it for packs installed earlier.
      if (from >= 2 && from < 5) await _reindexSearch();
    },
  );

  Future<void> _createContent() => _run(contentSchema);

  /// Rebuilds `verse_fts` from the imported verses, in chunks to keep memory flat.
  Future<void> _reindexSearch() async {
    await customStatement('DELETE FROM verse_fts');
    const chunk = 5000;
    for (var offset = 0; ; offset += chunk) {
      final rows = await customSelect(
        'SELECT v.poem_id, v.vorder, v.text, p.poet_id FROM verses v JOIN poems p ON p.id = v.poem_id '
        'ORDER BY v.poem_id, v.vorder LIMIT ? OFFSET ?',
        variables: [Variable<int>(chunk), Variable<int>(offset)],
      ).get();
      if (rows.isEmpty) return;
      await batch((b) {
        for (final r in rows) {
          b.customStatement('INSERT INTO verse_fts (norm, poem_id, vorder, poet_id) VALUES (?, ?, ?, ?)', [
            normalizeForIndex(r.read<String>('text')),
            r.read<int>('poem_id'),
            r.read<int>('vorder'),
            r.read<int>('poet_id'),
          ]);
        }
      });
    }
  }

  Future<void> _run(List<String> statements) async {
    for (final sql in statements) {
      await customStatement(sql);
    }
  }
}
