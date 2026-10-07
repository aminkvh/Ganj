import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../data/user/user_repository.dart';
import '../../l10n/l10n.dart';
import '../../core/text/content_en.dart';

/// Where an entry leads: its beyt when it has one.
String poemRoute(UserEntry e) => e.coupletIndex >= 0 ? '/poem/${e.poemId}?c=${e.coupletIndex}' : '/poem/${e.poemId}';

/// Bookmarks, reading history and notes kept on this device, with JSON backup.
class UserScreen extends ConsumerStatefulWidget {
  const UserScreen({super.key});

  @override
  ConsumerState<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends ConsumerState<UserScreen> {
  late final UserRepository _user = ref.read(userRepositoryProvider);
  List<UserEntry> _bookmarks = const [], _history = const [], _notes = const [];
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<UserEntry> b, h, n;
    try {
      b = await _user.bookmarks();
      h = await _user.history();
      n = await _user.notes();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _failed = false;
      _bookmarks = b;
      _history = h;
      _notes = n;
      _loaded = true;
    });
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _export() async {
    final l = context.l10n;
    final json = await _user.exportJson();
    await Clipboard.setData(ClipboardData(text: json));
    _snack(l.backupCopied);
    await SharePlus.instance.share(ShareParams(text: json, subject: l.backupSubject));
  }

  Future<void> _import() async {
    final l = context.l10n;
    final ctrl = TextEditingController();
    final json = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.importBackup),
        content: TextField(
          key: const ValueKey('import-field'),
          controller: ctrl,
          maxLines: 6,
          minLines: 3,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(hintText: l.pasteBackup),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(l.importAction)),
        ],
      ),
    );
    if (json == null || json.trim().isEmpty) return;
    try {
      final n = await _user.importJson(json);
      _snack(l.itemsImported(localDigits(n)));
      await _reload();
    } catch (_) {
      _snack(l.backupInvalid);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.bookmarksAndNotes),
        actions: [
          PopupMenuButton<String>(
            tooltip: context.l10n.more,
            onSelected: (v) => v == 'export' ? _export() : _import(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'export', child: Text(context.l10n.exportBackup)),
              PopupMenuItem(value: 'import', child: Text(context.l10n.importBackup)),
            ],
          ),
        ],
        bottom: TabBar(
          tabs: [
            Tab(text: context.l10n.bookmarksTab),
            Tab(text: context.l10n.historyTab),
            Tab(text: context.l10n.notesTab),
          ],
        ),
      ),
      body: _failed
          ? Center(child: Text(context.l10n.userDataFailed))
          : !_loaded
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                _list(
                  _bookmarks,
                  context.l10n.noBookmarks,
                  onDelete: (e) async {
                    await _user.removeBookmark(e.poemId, e.coupletIndex);
                    await _reload();
                  },
                  deleteKey: (e) => 'del-bookmark-${e.poemId}-${e.coupletIndex}',
                ),
                _list(_history, context.l10n.noHistory),
                _list(
                  _notes,
                  context.l10n.noNotes,
                  onDelete: (e) async {
                    await _user.setNote(e.poemId, e.coupletIndex, '', e.title, e.fullTitle);
                    await _reload();
                  },
                  deleteKey: (e) => 'del-note-${e.poemId}-${e.coupletIndex}',
                ),
              ],
            ),
    ),
  );

  Widget _list(
    List<UserEntry> items,
    String empty, {
    Future<void> Function(UserEntry)? onDelete,
    String Function(UserEntry)? deleteKey,
  }) {
    final c = context.ganj;
    if (items.isEmpty) {
      return Center(
        child: Text(empty, style: TextStyle(color: c.muted)),
      );
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final e = items[i];
        final where = e.coupletIndex >= 0 ? context.l10n.beytN(localDigits(e.coupletIndex + 1)) : null;
        return ListTile(
          title: Text(
            e.text.isNotEmpty ? e.text : localPath(e.fullTitle),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [if (e.text.isNotEmpty) localPath(e.fullTitle), ?where].join(' · '),
            style: TextStyle(color: c.muted, fontSize: 12),
          ),
          onTap: () async {
            await context.push(poemRoute(e));
            _reload(); // reading may have added history or bookmarks
          },
          trailing: onDelete == null
              ? null
              : IconButton(
                  key: ValueKey(deleteKey!(e)),
                  tooltip: context.l10n.delete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(e),
                ),
        );
      },
    );
  }
}
