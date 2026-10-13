import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/ganj_colors.dart';
import '../../../l10n/l10n.dart';
import '../../../version.dart';
import '../../../widgets/external_link.dart';
import '../data/models.dart';
import '../data/relation_kinds.dart';

/// The one visual code of «جهان شاهنامه»: every age has a tint (timeline bands, map pins,
/// person headers) and every family of ties a colour and a line style.
bool isEn(BuildContext context) => Localizations.localeOf(context).languageCode == 'en';

/// Pishdadians gold, Kayanians lapis, Alexander & Ashkanians bronze, Sasanians red.
Color ageTint(BuildContext context, int age) {
  final c = context.ganj;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (age) {
    0 => c.gold,
    1 => dark ? const Color(0xFF7FA6D6) : const Color(0xFF2E5C8A),
    2 => Color.lerp(c.gold, c.brandRed, 0.45)!,
    _ => c.brandRed,
  };
}

Color familyColor(BuildContext context, RelationFamily f) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (f) {
    RelationFamily.kin => dark ? const Color(0xFFC9A26B) : const Color(0xFF7A4A2A),
    RelationFamily.conflict => dark ? const Color(0xFFE0705E) : const Color(0xFFB0352A),
    RelationFamily.service => dark ? const Color(0xFF7FA6D6) : const Color(0xFF3A6EA5),
    RelationFamily.alliance => dark ? const Color(0xFF7CC08A) : const Color(0xFF3A8A4A),
  };
}

/// Dash pattern (on, off) for a family's lines; null = solid.
List<double>? familyDash(RelationFamily f) => switch (f) {
  RelationFamily.kin || RelationFamily.conflict => null,
  RelationFamily.service => const [6, 4],
  RelationFamily.alliance => const [2, 3],
};

String familyLabel(L10n l, RelationFamily f) => switch (f) {
  RelationFamily.kin => l.shKin,
  RelationFamily.conflict => l.shConflict,
  RelationFamily.service => l.shService,
  RelationFamily.alliance => l.shAlliance,
};

String personName(BuildContext context, ShWorld w, int id) => w.displayName(id, english: isEn(context));

String ageName(BuildContext context, ShAge a) => isEn(context) ? a.en : a.fa;
String storyName(BuildContext context, ShStory s) => isEn(context) ? s.en : s.fa;
String placeName(BuildContext context, ShPlace p) => isEn(context) ? p.en : p.fa;

String regionName(BuildContext context, String key) {
  final r = kRegions[key] ?? kRegions['other']!;
  return isEn(context) ? r.en : r.fa;
}

/// Marks what AI wrote for Ganj (not from Ganjoor, not yet reviewed): the ages and stories,
/// the places, the English names. Ganjoor's own AI writing keeps the app's [AiBadge].
class GanjAiBadge extends StatelessWidget {
  const GanjAiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    return Tooltip(
      message: context.l10n.shGanjAiNote,
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: c.lapis.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(context.l10n.shGanjAi, style: TextStyle(fontSize: 11, color: c.lapis)),
      ),
    );
  }
}

/// Where readers' «گزارش خطا» go: the reader's own email app, pre-filled.
const kReportEmail = 'Ganj_app@protonmail.com';

/// Opens an email to Ganj about one item of «جهان شاهنامه» ([path] is its in-app link).
/// Without an email app (common on computers) the report is copied, with the address to send it to.
Future<void> reportProblem(BuildContext context, WidgetRef ref, {required String what, required String path}) async {
  final l = context.l10n;
  final lang = Localizations.localeOf(context).languageCode;
  final subject = '[Ganj] ${l.shahnamehWorld}: $what';
  final body = '${l.shReportWhat}\n\n\n\n—\n$what\n$path\nGanj $kAppVersion ($lang)\n';
  // Spaces as %20: some mail apps show a '+' literally. (openExternal takes web links only.)
  final uri = Uri.parse(
    'mailto:$kReportEmail?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );
  var sent = false;
  try {
    sent = await ref.read(urlLauncherProvider)(uri);
  } catch (_) {}
  if (sent || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: '$kReportEmail\n$subject\n\n$body'));
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.shReportCopied(kReportEmail)), duration: const Duration(seconds: 8)));
  }
}

/// «People and tags from ganjoor.net; places and timeline by Ganj».
class ShCredit extends StatelessWidget {
  const ShCredit({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
    child: Text(
      context.l10n.shDataCredit,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.ganj.muted, fontSize: 12),
    ),
  );
}

/// Where in the book a person appears: 60 slots in story order, tinted by age; passing
/// mentions faint. Runs right to left in the Persian interface, like the book.
class PresenceBar extends StatelessWidget {
  const PresenceBar({
    super.key,
    required this.world,
    required this.person,
    this.height = 6,
    this.onTapSection,
    this.present,
  });

  final ShWorld world;
  final int person;

  /// Where the person appears, when known fresher than the bundled data.
  final List<int>? present;
  final double height;
  final ValueChanged<int>? onTapSection;

  @override
  Widget build(BuildContext context) {
    final n = world.sections.length;
    final present = this.present ?? world.presence[person] ?? const [];
    final passing = world.passing[person] ?? const [];
    final tints = [for (var i = 0; i < world.ages.length; i++) ageTint(context, i)];
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final paint = CustomPaint(
      size: Size(double.infinity, height),
      painter: _PresencePainter(
        n: n,
        present: present.toSet(),
        passing: passing.toSet(),
        tintOf: (o) => tints[world.ageOfSection(o).index],
        track: context.ganj.goldLight.withValues(alpha: 0.5),
      ),
    );
    final bar = rtl ? Transform.flip(flipX: true, child: paint) : paint;
    if (onTapSection == null) return SizedBox(height: height, child: bar);
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          var slot = (d.localPosition.dx / box.maxWidth * n).floor().clamp(0, n - 1);
          if (rtl) slot = n - 1 - slot;
          onTapSection!(slot);
        },
        child: SizedBox(
          height: height + 12,
          child: Center(
            child: SizedBox(height: height, child: bar),
          ),
        ),
      ),
    );
  }
}

class _PresencePainter extends CustomPainter {
  _PresencePainter({
    required this.n,
    required this.present,
    required this.passing,
    required this.tintOf,
    required this.track,
  });

  final int n;
  final Set<int> present, passing;
  final Color Function(int) tintOf;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    final w = size.width / n;
    for (var o = 0; o < n; o++) {
      final on = present.contains(o), faint = passing.contains(o);
      if (!on && !faint) continue;
      // Painted left to right; [PresenceBar] mirrors it for right-to-left reading.
      final rect = Rect.fromLTWH(o * w, 0, w + 0.5, size.height);
      canvas.drawRect(rect, Paint()..color = tintOf(o).withValues(alpha: on ? 1 : 0.35));
    }
  }

  @override
  bool shouldRepaint(_PresencePainter old) => old.present != present || old.passing != passing;
}
