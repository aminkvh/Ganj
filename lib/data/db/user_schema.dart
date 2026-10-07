/// Device-only reader data. Keyed by Ganjoor poem id (+ couplet index, -1 = whole poem),
/// so installing, updating or removing packs never touches it.
const userSchema = [
  '''CREATE TABLE IF NOT EXISTS bookmarks (
       poem_id INTEGER NOT NULL, couplet_index INTEGER NOT NULL DEFAULT -1, poem_title TEXT NOT NULL,
       full_title TEXT NOT NULL, created INTEGER NOT NULL, PRIMARY KEY (poem_id, couplet_index))''',
  '''CREATE TABLE IF NOT EXISTS history (
       poem_id INTEGER PRIMARY KEY, poem_title TEXT NOT NULL, full_title TEXT NOT NULL,
       visited INTEGER NOT NULL, scroll_offset REAL NOT NULL DEFAULT 0, couplet_index INTEGER NOT NULL DEFAULT -1)''',
  '''CREATE TABLE IF NOT EXISTS notes (
       poem_id INTEGER NOT NULL, couplet_index INTEGER NOT NULL, text TEXT NOT NULL, poem_title TEXT NOT NULL,
       full_title TEXT NOT NULL, updated INTEGER NOT NULL, PRIMARY KEY (poem_id, couplet_index))''',
];
