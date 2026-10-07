import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../core/theme/ganj_theme.dart';
import '../../data/api/dto/book.dart';
import '../../data/providers.dart';
import '../../l10n/l10n.dart';
import '../../core/text/content_en.dart';

final bookCatalogProvider = FutureProvider<List<Book>>((ref) => ref.watch(ganjoorApiProvider).bookCatalog());

/// Spine hue, as ganjoor.net's hashBookColorHue(): a 32-bit Java-style string hash of the id.
int bookHue(int id) {
  var hash = 0;
  for (final c in '$id'.codeUnits) {
    hash = (hash * 31 + c).toSigned(32);
  }
  return hash.abs() % 360;
}

const _paper = Color(0xFFFDF8EE);
const _spineW = 56.0, _spineH = 230.0, _coverW = 170.0, _coverH = 262.0;

/// «قفسهٔ کتاب‌ها»: book spines like the site's home page. A tap opens a spine to its
/// cover; a tap on the cover opens the book. Hidden when the list can't be loaded.
class BookShelf extends ConsumerStatefulWidget {
  const BookShelf({super.key});

  @override
  ConsumerState<BookShelf> createState() => _BookShelfState();
}

class _BookShelfState extends ConsumerState<BookShelf> {
  int? _open;

  void _openBook(Book b) => context.push('/cat/${b.id}');

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(bookCatalogProvider).value;
    if (books == null || books.isEmpty) return const SizedBox.shrink();
    final c = context.ganj;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(context.l10n.bookShelf, style: nastaliqOf(context, 22).copyWith(color: c.lapis)),
        ),
        SizedBox(
          height: _coverH + 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
            itemCount: books.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final b = books[i];
              return Align(
                alignment: Alignment.bottomCenter,
                child: _Spine(
                  book: b,
                  open: _open == b.id,
                  onTap: () => _open == b.id ? _openBook(b) : setState(() => _open = b.id),
                  onClose: () => setState(() => _open = null),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Spine extends StatefulWidget {
  const _Spine({required this.book, required this.open, required this.onTap, required this.onClose});

  final Book book;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_Spine> createState() => _SpineState();
}

class _SpineState extends State<_Spine> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.book;
    final color = HSLColor.fromAHSL(1, bookHue(b.id).toDouble(), 0.42, 0.30).toColor();
    final lift = _hover ? (widget.open ? -6.0 : -12.0) : 0.0;
    return Semantics(
      button: true,
      label: '${b.name} - ${b.poetName}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          key: ValueKey(widget.open ? 'book-cover-${b.id}' : 'book-${b.id}'),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, lift, 0),
            width: widget.open ? _coverW : _spineW,
            height: widget.open ? _coverH : _spineH,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4), bottom: Radius.circular(3)),
              // Shadowed left edge, lit right edge over the spine colour: the site's gradient.
              // (A gradient replaces `color`, so the colour is blended into its stops.)
              gradient: LinearGradient(
                colors: [
                  Color.alphaBlend(Colors.black.withValues(alpha: .22), color),
                  color,
                  color,
                  Color.alphaBlend(Colors.white.withValues(alpha: .12), color),
                ],
                stops: const [0, .12, .88, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _hover ? .4 : .28),
                  offset: _hover ? const Offset(4, 12) : const Offset(2, 3),
                  blurRadius: _hover ? 20 : 8,
                ),
              ],
            ),
            child: ClipRect(child: widget.open ? _cover(context, b) : _compact(context, b)),
          ),
        ),
      ),
    );
  }

  // Each line is laid out horizontally first (so Persian letters join), then turned as a
  // whole to read bottom-to-top, exactly as the site does it.
  Widget _compact(BuildContext context, Book b) => Stack(
    children: [
      Positioned(
        top: 95 - 75,
        height: 150,
        left: 0,
        right: 0,
        child: Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: SizedBox(
              width: 150,
              child: Text(
                b.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: nastaliqOf(context, 17).copyWith(color: _paper, height: 1.2, shadows: _shadow),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 200 - 25,
        height: 50,
        left: 0,
        right: 0,
        child: Center(
          child: RotatedBox(
            quarterTurns: 3,
            child: SizedBox(
              width: 50,
              child: Text(
                b.poetName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(color: _paper.withValues(alpha: .85), fontSize: 10.5, shadows: _shadow),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _cover(BuildContext context, Book b) => Stack(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                b.name,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: nastaliqOf(context, 22).copyWith(color: _paper, height: 1.5, shadows: _shadow),
              ),
              const SizedBox(height: 10),
              Text(
                b.poetName,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(color: _paper.withValues(alpha: .9), fontSize: 13.5),
              ),
            ],
          ),
        ),
      ),
      PositionedDirectional(
        top: 6,
        end: 6,
        child: Material(
          color: Colors.black.withValues(alpha: .25),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onClose,
            child: Tooltip(
              message: context.l10n.close,
              child: const SizedBox(width: 22, height: 22, child: Icon(Icons.close, size: 14, color: _paper)),
            ),
          ),
        ),
      ),
    ],
  );
}

const _shadow = [Shadow(color: Color(0x59000000), offset: Offset(0, 1), blurRadius: 2)];

/// Books whose title or poet matches [query] (English poet names too, in English).
List<Book> matchingBooks(List<Book> books, String query) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  return [
    for (final b in books)
      if (matchesQuery(b.name, q) ||
          matchesQuery(b.poetName, q) ||
          localPoet(b.poetId, '').toLowerCase().contains(q.toLowerCase()))
        b,
  ];
}

/// Books matching the home search (by title or poet), as small covers like the site's.
class BookResults extends ConsumerWidget {
  const BookResults({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(bookCatalogProvider).value ?? const <Book>[];
    final q = query.trim();
    final hits = matchingBooks(books, q);
    if (hits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [for (final b in hits) _BookResult(book: b)],
      ),
    );
  }
}

class _BookResult extends StatelessWidget {
  const _BookResult({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final color = HSLColor.fromAHSL(1, bookHue(book.id).toDouble(), 0.42, 0.30).toColor();
    return InkWell(
      key: ValueKey('book-result-${book.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/cat/${book.id}'),
      child: SizedBox(
        width: 110,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 96,
                padding: const EdgeInsets.all(6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(color: c.gold, spreadRadius: 2),
                    BoxShadow(color: c.page, spreadRadius: 5),
                    BoxShadow(color: c.goldLight, spreadRadius: 7),
                  ],
                ),
                child: Text(
                  book.name,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: nastaliqOf(context, 13).copyWith(color: _paper, height: 1.35),
                ),
              ),
              const SizedBox(height: 11),
              Text(
                localPoet(book.poetId, book.poetName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
