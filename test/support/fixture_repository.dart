import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ganj/data/api/dto/cat.dart';
import 'package:ganj/data/api/dto/poem.dart';
import 'package:ganj/data/api/dto/poet.dart';
import 'package:ganj/data/api/dto/recitation.dart';
import 'package:ganj/data/repo/poetry_repository.dart';

import 'fixtures.dart';

/// Fixture-backed repository for widget tests (no dio, no drift).
class FixtureRepository implements PoetryRepository {
  bool fail = false;

  @override
  Duration get packTimeout => Duration.zero;

  @override
  bool centuriesFromSeed = false;

  /// Holds recitationSync for these ids until completed (simulates a slow network).
  final syncGates = <int, Completer<void>>{};

  /// Verse timings served instead of the fixture files.
  final syncs = <int, List<SyncPoint>>{};

  /// Poems served instead of the fixture files (e.g. a poem without recitations).
  final poems = <int, Poem>{};

  void _check() {
    if (fail) throw StateError('offline');
  }

  Map<String, dynamic> _j(String name) => jsonDecode(fx(name)) as Map<String, dynamic>;

  @override
  Future<List<Century>> centuries() async {
    _check();
    return [for (final c in jsonDecode(fx('centuries')) as List) Century.fromJson(c as Map<String, dynamic>)];
  }

  @override
  Future<PoetCat> poet(int id) async {
    _check();
    return PoetCat.fromJson(_j('poet_$id'));
  }

  @override
  Future<PoetCat> cat(int id) async {
    _check();
    return PoetCat.fromJson(_j('cat_$id'));
  }

  @override
  Future<Poem> poem(int id) async {
    _check();
    return poems[id] ?? Poem.fromJson(_j('poem_$id'));
  }

  @override
  Future<List<SyncPoint>> recitationSync(int recitationId) async {
    await syncGates[recitationId]?.future;
    _check();
    final custom = syncs[recitationId];
    if (custom != null) return custom;
    final file = File('test/fixtures/audio/verses_$recitationId.json');
    return file.existsSync() ? parseSyncJson(file.readAsStringSync()) : const [];
  }
}
