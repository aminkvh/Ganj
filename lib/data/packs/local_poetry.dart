import 'package:drift/drift.dart';

import '../api/dto/cat.dart';
import '../api/dto/poem.dart';
import '../api/dto/poet.dart';
import '../db/app_db.dart';

/// Reads installed packs back as the same DTOs the API produces, so screens don't care where data came from.
class LocalPoetry {
  LocalPoetry(this._db);

  final AppDb _db;

  Future<QueryRow?> _one(String sql, List<Object> args) =>
      _db.customSelect(sql, variables: [for (final a in args) Variable(a)]).getSingleOrNull();

  Future<List<QueryRow>> _all(String sql, List<Object> args) =>
      _db.customSelect(sql, variables: [for (final a in args) Variable(a)]).get();

  Future<Poet?> _poet(int id) async {
    final r = await _one(
      'SELECT p.id, p.name, p.root_cat_id, p.description, c.full_url FROM poets p '
      'LEFT JOIN cats c ON c.id = p.root_cat_id WHERE p.id = ?',
      [id],
    );
    if (r == null) return null;
    return Poet(
      id: r.read<int>('id'),
      name: r.read<String>('name'),
      nickname: r.read<String>('name'),
      fullUrl: r.read<String?>('full_url') ?? '',
      rootCatId: r.read<int>('root_cat_id'),
      description: r.read<String?>('description'),
    );
  }

  CatRef _ref(QueryRow r) => CatRef(
    id: r.read<int>('id'),
    title: r.read<String>('title'),
    urlSlug: r.read<String>('full_url').split('/').last,
    fullUrl: r.read<String>('full_url'),
  );

  /// Root-first chain of ancestors of [catId] (excluding itself).
  Future<List<CatRef>> _ancestors(int? parentId) async {
    final chain = <CatRef>[];
    var next = parentId;
    while (next != null) {
      final r = await _one('SELECT id, parent_id, title, full_url FROM cats WHERE id = ?', [next]);
      if (r == null) break;
      chain.insert(0, _ref(r));
      next = r.read<int?>('parent_id');
    }
    return chain;
  }

  Future<PoetCat?> cat(int id, {bool withContent = true}) async {
    final r = await _one('SELECT id, poet_id, parent_id, title, full_url FROM cats WHERE id = ?', [id]);
    if (r == null) return null;
    final poet = await _poet(r.read<int>('poet_id'));
    if (poet == null) return null;
    final children = withContent
        ? [
            for (final c in await _all('SELECT id, title, full_url FROM cats WHERE parent_id = ? ORDER BY id', [id]))
              _ref(c),
          ]
        : <CatRef>[];
    final poems = withContent
        ? [
            for (final p in await _all(
              'SELECT p.id, p.title, p.full_url, (SELECT text FROM verses v WHERE v.poem_id = p.id ORDER BY vorder LIMIT 1) '
              'AS excerpt FROM poems p WHERE p.cat_id = ? ORDER BY p.id',
              [id],
            ))
              PoemRef(
                id: p.read<int>('id'),
                title: p.read<String>('title'),
                urlSlug: p.read<String>('full_url').split('/').last,
                excerpt: p.read<String?>('excerpt') ?? '',
              ),
          ]
        : <PoemRef>[];
    return PoetCat(
      poet: poet,
      cat: Cat(
        id: id,
        title: r.read<String>('title'),
        fullUrl: r.read<String>('full_url'),
        ancestors: await _ancestors(r.read<int?>('parent_id')),
        children: children,
        poems: poems,
      ),
    );
  }

  Future<PoetCat?> poet(int id) async {
    final p = await _poet(id);
    return p == null ? null : cat(p.rootCatId);
  }

  Future<Poem?> poem(int id) async {
    final r = await _one('SELECT id, cat_id, title, full_url FROM poems WHERE id = ?', [id]);
    if (r == null) return null;
    final catId = r.read<int>('cat_id');
    final category = await cat(catId, withContent: false);
    final verses = [
      for (final v in await _all(
        'SELECT vorder, position, text, couplet_index FROM verses WHERE poem_id = ? ORDER BY vorder',
        [id],
      ))
        Verse(
          vOrder: v.read<int>('vorder'),
          position: v.read<int>('position'),
          text: v.read<String>('text'),
          coupletIndex: v.read<int>('couplet_index'),
        ),
    ];
    Future<PoemRef?> neighbour(String cmp, String order) async {
      final n = await _one(
        'SELECT id, title, full_url FROM poems WHERE cat_id = ? AND id $cmp ? ORDER BY id $order LIMIT 1',
        [catId, id],
      );
      return n == null
          ? null
          : PoemRef(
              id: n.read<int>('id'),
              title: n.read<String>('title'),
              urlSlug: n.read<String>('full_url').split('/').last,
              excerpt: '',
            );
    }

    final title = r.read<String>('title');
    final crumbs = [...?category?.cat.ancestors.map((a) => a.title), ?category?.cat.title, title];
    return Poem(
      id: id,
      title: title,
      fullTitle: crumbs.join(' » '),
      fullUrl: r.read<String>('full_url'),
      plainText: verses.map((v) => v.text).join('\n'),
      verses: verses,
      category: category,
      next: await neighbour('>', 'ASC'),
      previous: await neighbour('<', 'DESC'),
    );
  }
}
