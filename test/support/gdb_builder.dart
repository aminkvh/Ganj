import 'dart:io';

import 'package:ganj/data/api/dto/poem.dart';
import 'package:sqlite3/sqlite3.dart';

import 'fixtures.dart';

/// Builds a small Desktop-Ganjoor-format pack (same schema as i.ganjoor.net gdbs) for Hafez,
/// containing the fixture poems 2130 (ghazal) and 77000 (montasab), with absolute urls like the real files.
File buildHafezGdb(Directory dir, {List<Poem>? poems}) {
  final file = File('${dir.path}/hafez.gdb');
  if (file.existsSync()) file.deleteSync();
  final db = sqlite3.open(file.path);
  db
    ..execute(
      'CREATE TABLE [cat] ([id] INTEGER PRIMARY KEY NOT NULL,[poet_id] INTEGER NULL,[text] NVARCHAR(100) NULL,'
      '[parent_id] INTEGER NULL,[url] NVARCHAR(255) NULL)',
    )
    ..execute('CREATE TABLE [poem] (id INTEGER PRIMARY KEY, cat_id INTEGER, title NVARCHAR(255), url NVARCHAR(255))')
    ..execute(
      'CREATE TABLE [poet] ([id] INTEGER PRIMARY KEY NOT NULL,[name] NVARCHAR(20) NULL,[cat_id] INTEGER NULL,'
      ' [description] TEXT)',
    )
    ..execute(
      'CREATE TABLE [verse] ([poem_id] INTEGER NULL,[vorder] INTEGER NULL,[position] INTEGER NULL,[text] TEXT NULL)',
    )
    ..execute("INSERT INTO poet VALUES (2, 'حافظ', 9, 'خواجه شمس‌الدین محمد شیرازی')")
    ..execute("INSERT INTO cat VALUES (9, 2, 'حافظ', 0, 'https://ganjoor.net/hafez')")
    ..execute("INSERT INTO cat VALUES (24, 2, 'غزلیات', 9, 'https://ganjoor.net/hafez/ghazal')")
    ..execute("INSERT INTO cat VALUES (674, 2, 'اشعار منتسب', 9, 'https://ganjoor.net/hafez/montasab')");
  final cats = {2130: 24, 77000: 674};
  for (final p in poems ?? [poem2130(), poem77000()]) {
    db.execute('INSERT INTO poem VALUES (?, ?, ?, ?)', [
      p.id,
      cats[p.id] ?? 24,
      p.title,
      'https://ganjoor.net${p.fullUrl}',
    ]);
    for (final v in p.verses) {
      db.execute('INSERT INTO verse VALUES (?, ?, ?, ?)', [p.id, v.vOrder, v.position, v.text]);
    }
  }
  db.close();
  return file;
}
