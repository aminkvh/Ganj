import 'package:flutter/material.dart';

/// Ganjoor's palette (ganjoor.net css p8), light and dark.
@immutable
class GanjColors extends ThemeExtension<GanjColors> {
  const GanjColors({
    required this.page,
    required this.paper,
    required this.poem,
    required this.inner,
    required this.ink,
    required this.muted,
    required this.lapis,
    required this.gold,
    required this.goldLight,
    required this.brandRed,
    required this.borderGold,
  });

  final Color page, paper, poem, inner, ink, muted, lapis, gold, goldLight, brandRed, borderGold;

  static const light = GanjColors(
    page: Color(0xFFFBF6EA),
    paper: Color(0xFFFFFDF7),
    poem: Color(0xFFF3E9D0),
    inner: Color(0xFFF6EFE3),
    ink: Color(0xFF17130F),
    muted: Color(0xFF635543),
    lapis: Color(0xFF0D1D30),
    gold: Color(0xFFB88828),
    goldLight: Color(0xFFDFCD9F),
    brandRed: Color(0xFFBF3F2A),
    borderGold: Color(0xFFB8A78C),
  );

  static const dark = GanjColors(
    page: Color(0xFF14120F),
    paper: Color(0xFF181510),
    poem: Color(0xFF1C1916),
    inner: Color(0xFF242019),
    ink: Color(0xFFE7DED0),
    muted: Color(0xFF9E9185),
    lapis: Color(0xFFF0F6FC),
    gold: Color(0xFFC9A050),
    goldLight: Color(0xFF3A322B),
    brandRed: Color(0xFFD4553A),
    borderGold: Color(0xFF9B7332),
  );

  @override
  GanjColors copyWith({
    Color? page,
    Color? paper,
    Color? poem,
    Color? inner,
    Color? ink,
    Color? muted,
    Color? lapis,
    Color? gold,
    Color? goldLight,
    Color? brandRed,
    Color? borderGold,
  }) => GanjColors(
    page: page ?? this.page,
    paper: paper ?? this.paper,
    poem: poem ?? this.poem,
    inner: inner ?? this.inner,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    lapis: lapis ?? this.lapis,
    gold: gold ?? this.gold,
    goldLight: goldLight ?? this.goldLight,
    brandRed: brandRed ?? this.brandRed,
    borderGold: borderGold ?? this.borderGold,
  );

  @override
  GanjColors lerp(ThemeExtension<GanjColors>? other, double t) {
    if (other is! GanjColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return GanjColors(
      page: l(page, other.page),
      paper: l(paper, other.paper),
      poem: l(poem, other.poem),
      inner: l(inner, other.inner),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      lapis: l(lapis, other.lapis),
      gold: l(gold, other.gold),
      goldLight: l(goldLight, other.goldLight),
      brandRed: l(brandRed, other.brandRed),
      borderGold: l(borderGold, other.borderGold),
    );
  }
}

extension GanjColorsX on BuildContext {
  GanjColors get ganj => Theme.of(this).extension<GanjColors>()!;
}
