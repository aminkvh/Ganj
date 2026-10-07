import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_db.dart';
import '../providers.dart';

/// One bookmark, history row or note.
class UserEntry {
  const UserEntry({
    required this.poemId,
    required this.coupletIndex,
    required this.title,
    required this.fullTitle,
    required this.time,
    this.text = '',
  });

  final int poemId;
  final int coupletIndex;
  final String title;
  final String fullTitle;
  final DateTime time;
  final String text;
}

/// Bookmarks, reading history and per-beyt notes — stored only on this device.
class UserRepository {
  UserRepository(this._db);

  final AppDb _db;

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<List<QueryRow>> _q(String sql, [List<Object> args = const []]) =>
      _db.customSelect(sql, variables: [for (final a in args) Variable(a)]).get();

  // ---- bookmarks ----

  /// Returns true when the poem (or beyt) is now bookmarked.
  /// Check and write in one transaction, so two quick taps toggle twice instead of racing.
  Future<bool> toggleBookmark(int poemId, String title, String fullTitle, {int couplet = -1}) =>
      _db.transaction(() async {
        if (await isBookmarked(poemId, couplet: couplet)) {
          await _db.customStatement('DELETE FROM bookmarks WHERE poem_id = ? AND couplet_index = ?', [poemId, couplet]);
          return false;
        }
        await _db.customStatement(
          'INSERT OR REPLACE INTO bookmarks (poem_id, couplet_index, poem_title, full_title, created) VALUES (?, ?, ?, ?, ?)',
          [poemId, couplet, title, fullTitle, _now],
        );
        return true;
      });

  Future<bool> isBookmarked(int poemId, {int couplet = -1}) async =>
      (await _q('SELECT 1 FROM bookmarks WHERE poem_id = ? AND couplet_index = ?', [poemId, couplet])).isNotEmpty;

  Future<Set<int>> bookmarkedCouplets(int poemId) async => {
    for (final r in await _q('SELECT couplet_index FROM bookmarks WHERE poem_id = ? AND couplet_index >= 0', [poemId]))
      r.read<int>('couplet_index'),
  };

  Future<List<UserEntry>> bookmarks() async => [
    for (final r in await _q('SELECT * FROM bookmarks ORDER BY created DESC'))
      UserEntry(
        poemId: r.read<int>('poem_id'),
        coupletIndex: r.read<int>('couplet_index'),
        title: r.read<String>('poem_title'),
        fullTitle: r.read<String>('full_title'),
        time: DateTime.fromMillisecondsSinceEpoch(r.read<int>('created')),
      ),
  ];

  Future<void> removeBookmark(int poemId, int couplet) =>
      _db.customStatement('DELETE FROM bookmarks WHERE poem_id = ? AND couplet_index = ?', [poemId, couplet]);

  // ---- history ----

  /// Records a visit now; [couplet] is the beyt on screen (omit to keep the previously saved one).
  /// History keeps the [historyCap] most recent poems.
  Future<void> recordVisit(int poemId, String title, String fullTitle, {int? couplet}) => _db.transaction(() async {
    await _db.customStatement(
      'INSERT INTO history (poem_id, poem_title, full_title, visited, couplet_index) VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(poem_id) DO UPDATE SET poem_title = excluded.poem_title, full_title = excluded.full_title, '
      'visited = excluded.visited, couplet_index = CASE WHEN excluded.couplet_index >= 0 '
      'THEN excluded.couplet_index ELSE history.couplet_index END',
      [poemId, title, fullTitle, _now, couplet ?? -1],
    );
    // The poem just visited always stays, whatever the clock says.
    await _db.customStatement(
      'DELETE FROM history WHERE poem_id != ? AND poem_id NOT IN '
      '(SELECT poem_id FROM history WHERE poem_id != ? ORDER BY visited DESC LIMIT ?)',
      [poemId, poemId, historyCap - 1],
    );
  });

  static const historyCap = 500;

  Future<List<UserEntry>> history({int limit = 200}) async => [
    for (final r in await _q('SELECT * FROM history ORDER BY visited DESC LIMIT ?', [limit]))
      UserEntry(
        poemId: r.read<int>('poem_id'),
        coupletIndex: -1,
        title: r.read<String>('poem_title'),
        fullTitle: r.read<String>('full_title'),
        time: DateTime.fromMillisecondsSinceEpoch(r.read<int>('visited')),
      ),
  ];

  /// The couplet the reader was on when they last left [poemId], if any.
  Future<int?> lastCouplet(int poemId) async {
    final rows = await _q('SELECT couplet_index FROM history WHERE poem_id = ?', [poemId]);
    final v = rows.isEmpty ? -1 : rows.first.read<int>('couplet_index');
    return v < 0 ? null : v;
  }

  Future<void> clearHistory() => _db.customStatement('DELETE FROM history');

  // ---- notes ----

  /// Saves a note for a beyt; blank text deletes it.
  Future<void> setNote(int poemId, int couplet, String text, String title, String fullTitle) async {
    if (text.trim().isEmpty) {
      await _db.customStatement('DELETE FROM notes WHERE poem_id = ? AND couplet_index = ?', [poemId, couplet]);
      return;
    }
    await _db.customStatement(
      'INSERT OR REPLACE INTO notes (poem_id, couplet_index, text, poem_title, full_title, updated) VALUES (?, ?, ?, ?, ?, ?)',
      [poemId, couplet, text.trim(), title, fullTitle, _now],
    );
  }

  Future<Map<int, String>> notesFor(int poemId) async => {
    for (final r in await _q('SELECT couplet_index, text FROM notes WHERE poem_id = ?', [poemId]))
      r.read<int>('couplet_index'): r.read<String>('text'),
  };

  Future<List<UserEntry>> notes() async => [
    for (final r in await _q('SELECT * FROM notes ORDER BY updated DESC'))
      UserEntry(
        poemId: r.read<int>('poem_id'),
        coupletIndex: r.read<int>('couplet_index'),
        title: r.read<String>('poem_title'),
        fullTitle: r.read<String>('full_title'),
        time: DateTime.fromMillisecondsSinceEpoch(r.read<int>('updated')),
        text: r.read<String>('text'),
      ),
  ];

  // ---- export / import ----

  Future<String> exportJson() async {
    Future<List<Map<String, Object?>>> rows(String table) async => [
      for (final r in await _q('SELECT * FROM $table')) r.data,
    ];
    return const JsonEncoder.withIndent(' ').convert({
      'app': 'ganj',
      'version': 1,
      'bookmarks': await rows('bookmarks'),
      'history': await rows('history'),
      'notes': await rows('notes'),
    });
  }

  /// Merges an export into this device; returns the number of rows read. A row already
  /// here is replaced only by a newer one, so restoring an old backup never loses edits.
  Future<int> importJson(String json) async {
    final data = jsonDecode(json);
    if (data is! Map<String, dynamic>) throw const FormatException('not a Ganj backup');
    // Validate every row first: a wrongly typed value must never reach the tables.
    final rows = <(String, Map<String, Object?>)>[];
    for (final table in const ['bookmarks', 'history', 'notes']) {
      final list = data[table];
      if (list == null) continue;
      if (list is! List) throw FormatException('$table is not a list');
      for (final row in list) {
        if (row is! Map) throw FormatException('$table row is not an object');
        final m = row.cast<String, Object?>();
        final spec = _columns[table]!;
        for (final k in m.keys) {
          final type = spec[k];
          if (type == null) throw FormatException('unknown column $table.$k');
          final v = m[k];
          final ok = switch (type) {
            _Col.integer => v is int,
            _Col.real => v is num,
            _Col.text => v is String,
          };
          if (!ok) throw FormatException('bad value for $table.$k');
        }
        rows.add((table, m));
      }
    }
    var n = 0;
    await _db.transaction(() async {
      for (final (table, m) in rows) {
        {
          final cols = m.keys.toList();
          final (keys, stamp) = _merge[table]!;
          final updates = [
            for (final c in cols)
              if (!keys.contains(c)) '$c = excluded.$c',
          ];
          await _db.customStatement(
            'INSERT INTO $table (${cols.join(', ')}) VALUES (${List.filled(cols.length, '?').join(', ')}) '
            'ON CONFLICT(${keys.join(', ')}) DO '
            '${updates.isEmpty ? 'NOTHING' : 'UPDATE SET ${updates.join(', ')} WHERE excluded.$stamp > $table.$stamp'}',
            [for (final c in cols) m[c]],
          );
          n++;
        }
      }
    });
    return n;
  }
}

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository(ref.watch(appDbProvider)));

enum _Col { integer, real, text }

/// Per table: its key columns and the timestamp that decides which copy is newer.
const _merge = {
  'bookmarks': (['poem_id', 'couplet_index'], 'created'),
  'history': (['poem_id'], 'visited'),
  'notes': (['poem_id', 'couplet_index'], 'updated'),
};

const _columns = {
  'bookmarks': {
    'poem_id': _Col.integer,
    'couplet_index': _Col.integer,
    'poem_title': _Col.text,
    'full_title': _Col.text,
    'created': _Col.integer,
  },
  'history': {
    'poem_id': _Col.integer,
    'poem_title': _Col.text,
    'full_title': _Col.text,
    'visited': _Col.integer,
    'scroll_offset': _Col.real,
    'couplet_index': _Col.integer,
  },
  'notes': {
    'poem_id': _Col.integer,
    'couplet_index': _Col.integer,
    'text': _Col.text,
    'poem_title': _Col.text,
    'full_title': _Col.text,
    'updated': _Col.integer,
  },
};
