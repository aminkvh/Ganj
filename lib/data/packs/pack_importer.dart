import 'dart:io';

import 'package:drift/drift.dart';

import '../../core/text/persian_normalize.dart';
import '../db/app_db.dart';
import 'couplet_index.dart';
import 'pack_catalog.dart';

class ImportResult {
  const ImportResult(this.poems, this.verses);

  final int poems;
  final int verses;
}

const _stripHost = "replace(replace(url, 'https://ganjoor.net', ''), 'http://ganjoor.net', '')";

/// Poems per verse-read chunk: keeps big packs (Molavi: 100k+ lines) out of memory at once.
const _poemsPerChunk = 400;

/// Copies a Desktop-Ganjoor `.gdb` pack into the app DB: ATTACH + INSERT…SELECT for
/// structure, then couplet indexes and the normalized FTS rows computed in Dart.
/// Idempotent and atomic: the poet's previous rows are replaced inside the same
/// transaction, so a failed import leaves an already-installed pack untouched.
Future<ImportResult> importGdb(AppDb db, File gdb, PackInfo info) async {
  await db.customStatement('ATTACH DATABASE ? AS g', [gdb.path]);
  try {
    return await db.transaction(() async {
      await _deletePoet(db, info.poetId);
      await db.customStatement(
        'INSERT OR REPLACE INTO poets (id, name, root_cat_id, description) SELECT id, name, cat_id, description FROM g.poet',
      );
      await db.customStatement(
        'INSERT OR REPLACE INTO cats (id, poet_id, parent_id, title, full_url) '
        'SELECT id, poet_id, NULLIF(parent_id, 0), text, $_stripHost FROM g.cat',
      );
      await db.customStatement(
        'INSERT OR REPLACE INTO poems (id, cat_id, poet_id, title, full_url) '
        'SELECT p.id, p.cat_id, c.poet_id, p.title, replace(replace(p.url, \'https://ganjoor.net\', \'\'), '
        '\'http://ganjoor.net\', \'\') FROM g.poem p JOIN g.cat c ON c.id = p.cat_id',
      );

      final poemIds = [
        for (final r in await db.customSelect('SELECT id FROM g.poem ORDER BY id').get()) r.read<int>('id'),
      ];
      var verses = 0;
      for (var start = 0; start < poemIds.length; start += _poemsPerChunk) {
        final end = start + _poemsPerChunk < poemIds.length ? start + _poemsPerChunk : poemIds.length;
        verses += await _importVerses(db, poemIds[start], poemIds[end - 1]);
      }

      await db.customStatement(
        'INSERT OR REPLACE INTO packs (poet_id, cat_id, name, pub_date, size, installed_at) VALUES (?, ?, ?, ?, ?, ?)',
        [info.poetId, info.catId, info.name, info.pubDate, info.size, DateTime.now().millisecondsSinceEpoch],
      );
      return ImportResult(poemIds.length, verses);
    });
  } finally {
    await db.customStatement('DETACH DATABASE g');
  }
}

/// Imports verses of poems with ids in [from]..[to] (inclusive), with couplet indexes and FTS rows.
Future<int> _importVerses(AppDb db, int from, int to) async {
  final rows = await db
      .customSelect(
        'SELECT v.poem_id, v.vorder, v.position, v.text, c.poet_id FROM g.verse v '
        'JOIN g.poem p ON p.id = v.poem_id JOIN g.cat c ON c.id = p.cat_id '
        'WHERE v.poem_id BETWEEN ? AND ? ORDER BY v.poem_id, v.vorder',
        variables: [Variable<int>(from), Variable<int>(to)],
      )
      .get();
  var i = 0;
  while (i < rows.length) {
    final poemId = rows[i].read<int>('poem_id');
    var j = i;
    while (j < rows.length && rows[j].read<int>('poem_id') == poemId) {
      j++;
    }
    final poemRows = rows.sublist(i, j);
    final couplets = coupletIndexes([for (final r in poemRows) r.read<int>('position')]);
    await db.batch((b) {
      for (var k = 0; k < poemRows.length; k++) {
        final r = poemRows[k];
        final text = r.read<String?>('text') ?? '';
        b.customStatement(
          'INSERT OR REPLACE INTO verses (poem_id, vorder, position, text, couplet_index) VALUES (?, ?, ?, ?, ?)',
          [poemId, r.read<int>('vorder'), r.read<int>('position'), text, couplets[k]],
        );
        b.customStatement('INSERT INTO verse_fts (norm, poem_id, vorder, poet_id) VALUES (?, ?, ?, ?)', [
          normalizeForIndex(text),
          poemId,
          r.read<int>('vorder'),
          r.read<int>('poet_id'),
        ]);
      }
    });
    i = j;
  }
  return rows.length;
}

Future<void> _deletePoet(AppDb db, int poetId) async {
  await db.customStatement('DELETE FROM verse_fts WHERE poet_id = ?', [poetId]);
  await db.customStatement('DELETE FROM verses WHERE poem_id IN (SELECT id FROM poems WHERE poet_id = ?)', [poetId]);
  await db.customStatement('DELETE FROM poems WHERE poet_id = ?', [poetId]);
  await db.customStatement('DELETE FROM cats WHERE poet_id = ?', [poetId]);
  await db.customStatement('DELETE FROM poets WHERE id = ?', [poetId]);
  await db.customStatement('DELETE FROM packs WHERE poet_id = ?', [poetId]);
}

/// Removes everything a pack brought in for [poetId]; user data and API cache are untouched.
Future<void> uninstall(AppDb db, int poetId) => db.transaction(() => _deletePoet(db, poetId));

Future<Set<int>> installedPoets(AppDb db) async => {
  for (final r in await db.customSelect('SELECT poet_id FROM packs').get()) r.read<int>('poet_id'),
};

/// Download size of every installed pack, including ones no longer in the catalog.
Future<int> installedPacksBytes(AppDb db) async =>
    (await db.customSelect('SELECT COALESCE(SUM(size), 0) AS s FROM packs').getSingle()).read<int>('s');

Future<Map<int, String>> installedPackDates(AppDb db) async => {
  for (final r in await db.customSelect('SELECT poet_id, pub_date FROM packs').get())
    r.read<int>('poet_id'): r.read<String>('pub_date'),
};
