import '../../core/text/labeled_text.dart';
import '../../data/api/dto/poem.dart';

enum CoupletKind { beyt, band, single, comment, paragraph }

class Couplet {
  Couplet({required this.index, required this.kind, required this.verses});

  final int index;
  final CoupletKind kind;
  final List<Verse> verses;

  LabeledText? get summary {
    for (final v in verses) {
      if (v.summary != null) return v.summary;
    }
    return null;
  }

  String get text => verses.map((v) => v.text).join('\n');
}

CoupletKind _kindOf(int position) => switch (position) {
  VersePosition.centered1 || VersePosition.centered2 => CoupletKind.band,
  VersePosition.single => CoupletKind.single,
  VersePosition.comment => CoupletKind.comment,
  VersePosition.paragraph => CoupletKind.paragraph,
  _ => CoupletKind.beyt,
};

bool _continuesCouplet(int position) => position == VersePosition.left || position == VersePosition.centered2;

/// Groups verses into couplets by the API's coupletIndex; when it is missing,
/// a new couplet starts on every position except left (1) and centered2 (3).
List<Couplet> groupCouplets(List<Verse> verses) {
  final sorted = [...verses]..sort((a, b) => a.vOrder.compareTo(b.vOrder));
  // Verses without a coupletIndex get synthetic indexes; when the poem also has real ones, the
  // synthetic range starts far above them so the two can never collide (or merge couplets).
  final anyExplicit = sorted.any((v) => v.coupletIndex != null);
  var nextSynthetic = anyExplicit ? 100000 : 0;
  final out = <Couplet>[];
  final synthetic = <bool>[];
  for (final v in sorted) {
    final explicit = v.coupletIndex;
    final joinsLast =
        out.isNotEmpty &&
        (explicit != null
            ? !synthetic.last && out.last.index == explicit
            : synthetic.last && _continuesCouplet(v.position));
    if (joinsLast) {
      out.last.verses.add(v);
      continue;
    }
    out.add(Couplet(index: explicit ?? nextSynthetic++, kind: _kindOf(v.position), verses: [v]));
    synthetic.add(explicit == null);
  }
  return out;
}
