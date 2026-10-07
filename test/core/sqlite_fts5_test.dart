import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('bundled SQLite is compiled with FTS5 and tokenizes Persian', () {
    final db = sqlite3.openInMemory();
    final opt = db.select("SELECT sqlite_compileoption_used('ENABLE_FTS5') AS fts5");
    expect(opt.first['fts5'], 1);
    db.execute("CREATE VIRTUAL TABLE t USING fts5(x, tokenize='unicode61 remove_diacritics 2')");
    db.execute("INSERT INTO t VALUES ('الا یا ایها الساقی ادر کاسا و ناولها')");
    final hit = db.select("SELECT count(*) AS c FROM t WHERE t MATCH 'الساقی'");
    expect(hit.first['c'], 1);
  });
}
