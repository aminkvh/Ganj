import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/text/persian_normalize.dart';
import '../../data/api/ganjoor_api.dart';
import '../../data/db/app_db.dart';
import '../../data/providers.dart';

class SearchHit {
  const SearchHit({
    required this.poemId,
    required this.poemTitle,
    required this.poetName,
    required this.snippet,
    required this.local,
    this.poetId,
  });

  final int poemId;
  final int? poetId;
  final String poemTitle;
  final String poetName;
  final String snippet;
  final bool local;
}

class SearchPage {
  const SearchPage(
    this.hits, {
    this.total = 0,
    this.hasMore = false,
    this.offline = false,
    this.totalKnown = true,
    this.soundAlike = false,
  });

  final List<SearchHit> hits;
  final int total;
  final bool hasMore;
  final bool offline;

  /// False when only installed packs answered: [total] then counts this page, not all matches.
  final bool totalKnown;

  /// Nothing matched as typed, so these are installed poems that match with sound-alike letters
  /// swapped (س/ص/ث, ز/ذ/ض/ظ…). Only installed packs are searched this way: other spellings are
  /// never sent to Ganjoor's server, to spare it extra requests.
  final bool soundAlike;
}

const _pageSize = 20;

/// Local full-text search over installed packs, merged with Ganjoor's online search.
class SearchService {
  SearchService(this._db, this._api, {this.onlineTimeout = const Duration(seconds: 6)});

  /// Online results that take longer are dropped; local hits are shown anyway.
  final Duration onlineTimeout;

  final AppDb _db;
  final GanjoorApi _api;

  /// Normalized search words with FTS syntax characters removed.
  static List<String> tokens(String term) =>
      normalizeForIndex(term).replaceAll(RegExp(r'["*():^+\-]'), ' ').split(' ').where((t) => t.isNotEmpty).toList();

  /// Trigram FTS query: every word must occur as a substring, like ganjoor.net's search.
  /// Words shorter than 3 letters can't use trigrams and are matched with LIKE instead.
  /// With [soundAlike], each word may also be spelled with sound-alike letters.
  static String? ftsQuery(String term, {bool soundAlike = false}) {
    final long = tokens(term).where((t) => t.length >= 3).toList();
    if (long.isEmpty) return null;
    return long
        .map((t) => soundAlike ? '(${soundAlikeSpellings(t).map((v) => '"$v"').join(' OR ')})' : '"$t"')
        .join(' ');
  }

  Future<SearchPage> searchLocal(
    String term, {
    int? poetId,
    Set<int> exclude = const {},
    int page = 1,
    bool soundAlike = false,
  }) async {
    final words = tokens(term);
    if (words.isEmpty) return const SearchPage([]);
    final q = ftsQuery(term, soundAlike: soundAlike);
    final short = [
      for (final t in words.where((t) => t.length < 3)) soundAlike ? soundAlikeSpellings(t) : [t],
    ];
    final where = [
      if (q != null) 'verse_fts MATCH ?',
      for (final vs in short) '(${vs.map((_) => "f.norm LIKE ? ESCAPE '\\'").join(' OR ')})',
      if (poetId != null) 'f.poet_id = ?',
      if (exclude.isNotEmpty) 'f.poet_id NOT IN (${exclude.map((_) => '?').join(',')})',
    ].join(' AND ');
    final args = [
      if (q != null) Variable<String>(q),
      // % and _ typed by the reader are literal characters, not wildcards.
      for (final vs in short)
        for (final s in vs)
          Variable<String>('%${s.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%'),
      if (poetId != null) Variable<int>(poetId),
      for (final id in exclude) Variable<int>(id),
    ];
    final rows = await _db
        .customSelect(
          'SELECT m.poem_id, v.text, p.title, pt.name, pt.id AS poet_id FROM ('
          '  SELECT f.poem_id AS poem_id, min(f.vorder) AS vorder FROM verse_fts f'
          '  WHERE $where GROUP BY f.poem_id ORDER BY f.poem_id LIMIT ? OFFSET ?) m '
          'JOIN verses v ON v.poem_id = m.poem_id AND v.vorder = m.vorder '
          'JOIN poems p ON p.id = m.poem_id JOIN poets pt ON pt.id = p.poet_id ORDER BY m.poem_id',
          variables: [...args, Variable<int>(_pageSize + 1), Variable<int>((page - 1) * _pageSize)],
        )
        .get();
    final hits = [
      for (final r in rows.take(_pageSize))
        SearchHit(
          poemId: r.read<int>('poem_id'),
          poemTitle: r.read<String>('title'),
          poetName: r.read<String>('name'),
          snippet: r.read<String>('text'),
          local: true,
          poetId: r.read<int>('poet_id'),
        ),
    ];
    return SearchPage(hits, total: hits.length, hasMore: rows.length > _pageSize, totalKnown: false);
  }

  Future<SearchPage> searchOnline(String term, {int? poetId, Set<int> exclude = const {}, int page = 1}) async {
    final r = await _api.searchPoems(term.trim(), poetId: poetId, exclude: exclude, page: page, pageSize: _pageSize);
    return SearchPage(
      [
        for (final p in r.poems)
          SearchHit(
            poemId: p['id'] as int,
            poemTitle: (p['title'] as String?) ?? '',
            poetName: ((p['fullTitle'] as String?) ?? '').split(' » ').first,
            snippet: _snippet((p['plainText'] as String?) ?? '', term),
            local: false,
            poetId: ((p['category'] as Map<String, dynamic>?)?['poet'] as Map<String, dynamic>?)?['id'] as int?,
          ),
      ],
      total: r.total,
      hasMore: r.hasNext,
    );
  }

  /// Local hits first, then online ones not already shown; offline → local only. [exclude]:
  /// poets whose poems are left out («حذف آثار یک شاعر از نتایج»). When nothing matches as typed,
  /// the first page tries sound-alike spellings in the installed packs ([SearchPage.soundAlike]);
  /// later pages of such a search pass [soundAlike] back. Neither sends anything more online.
  Future<SearchPage> search(
    String term, {
    int? poetId,
    Set<int> exclude = const {},
    int page = 1,
    bool soundAlike = false,
  }) async {
    if (soundAlike) return _soundAlike(term, poetId: poetId, exclude: exclude, page: page);
    // Local and online run together; a slow network never holds back offline hits.
    final r = await _merge(
      searchLocal(term, poetId: poetId, exclude: exclude, page: page),
      searchOnline(term, poetId: poetId, exclude: exclude, page: page).timeout(onlineTimeout),
    );
    if (page != 1 || r.hits.isNotEmpty) return r;
    final alike = await _soundAlike(term, poetId: poetId, exclude: exclude, offline: r.offline);
    return alike.hits.isEmpty ? r : alike;
  }

  /// Installed poems matching [term] with sound-alike letters swapped; never asks Ganjoor's server.
  Future<SearchPage> _soundAlike(
    String term, {
    int? poetId,
    Set<int> exclude = const {},
    int page = 1,
    bool offline = false,
  }) async {
    final l = await searchLocal(term, poetId: poetId, exclude: exclude, page: page, soundAlike: true);
    return SearchPage(
      l.hits,
      total: l.total,
      hasMore: l.hasMore,
      offline: offline,
      totalKnown: false,
      soundAlike: true,
    );
  }

  Future<SearchPage> _merge(Future<SearchPage> localFuture, Future<SearchPage> onlineFuture) async {
    // Started before awaiting the local search, so its failure is handled here, not unhandled.
    onlineFuture.ignore();
    final local = await localFuture;
    try {
      final online = await onlineFuture;
      final seen = {for (final h in local.hits) h.poemId};
      return SearchPage(
        [...local.hits, ...online.hits.where((h) => seen.add(h.poemId))],
        total: online.total > local.total ? online.total : local.total,
        hasMore: local.hasMore || online.hasMore,
      );
    } catch (_) {
      return SearchPage(local.hits, total: local.total, hasMore: local.hasMore, offline: true, totalKnown: false);
    }
  }

  static String _snippet(String plain, String term) {
    final lines = plain.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty);
    for (final l in lines) {
      if (matchesQuery(l, term)) return l.trim();
    }
    return lines.isEmpty ? '' : lines.first.trim();
  }
}

final searchServiceProvider = Provider<SearchService>(
  (ref) => SearchService(ref.watch(appDbProvider), ref.watch(ganjoorApiProvider)),
);
