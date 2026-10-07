/// Poetry content imported from Ganjoor packs (and later API caches), keyed by Ganjoor ids.
/// Raw SQL because the importer copies rows with ATTACH + INSERT…SELECT.
const contentSchema = [
  '''CREATE TABLE IF NOT EXISTS poets (
       id INTEGER PRIMARY KEY, name TEXT NOT NULL, root_cat_id INTEGER NOT NULL, description TEXT)''',
  '''CREATE TABLE IF NOT EXISTS cats (
       id INTEGER PRIMARY KEY, poet_id INTEGER NOT NULL, parent_id INTEGER, title TEXT NOT NULL,
       full_url TEXT NOT NULL)''',
  'CREATE INDEX IF NOT EXISTS cats_parent ON cats(parent_id)',
  'CREATE INDEX IF NOT EXISTS cats_poet ON cats(poet_id)',
  '''CREATE TABLE IF NOT EXISTS poems (
       id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL, poet_id INTEGER NOT NULL, title TEXT NOT NULL,
       full_url TEXT NOT NULL)''',
  'CREATE INDEX IF NOT EXISTS poems_cat ON poems(cat_id)',
  'CREATE INDEX IF NOT EXISTS poems_poet ON poems(poet_id)',
  '''CREATE TABLE IF NOT EXISTS verses (
       poem_id INTEGER NOT NULL, vorder INTEGER NOT NULL, position INTEGER NOT NULL, text TEXT NOT NULL,
       couplet_index INTEGER NOT NULL, PRIMARY KEY (poem_id, vorder)) WITHOUT ROWID''',
  '''CREATE TABLE IF NOT EXISTS packs (
       poet_id INTEGER PRIMARY KEY, cat_id INTEGER NOT NULL, name TEXT NOT NULL, pub_date TEXT NOT NULL,
       size INTEGER NOT NULL, installed_at INTEGER NOT NULL)''',
  '''CREATE VIRTUAL TABLE IF NOT EXISTS verse_fts USING fts5(
       norm, poem_id UNINDEXED, vorder UNINDEXED, poet_id UNINDEXED,
       tokenize = 'trigram')''', // substring search like ganjoor.net; text is pre-normalized
];
