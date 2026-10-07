import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'ganj_colors.dart';

const kBodyFont = 'Vazirmatn';
const kNastaliqFont = 'NotoNastaliqUrdu';

/// Which Nastaliq face headings use: the bundled Noto, or IranNastaliq when the reader opted in
/// (falls back to Noto if IranNastaliq isn't installed).
@immutable
class GanjFonts extends ThemeExtension<GanjFonts> {
  const GanjFonts({this.nastaliq = kNastaliqFont});

  final String nastaliq;

  @override
  GanjFonts copyWith({String? nastaliq}) => GanjFonts(nastaliq: nastaliq ?? this.nastaliq);

  @override
  GanjFonts lerp(ThemeExtension<GanjFonts>? other, double t) => t < 0.5 ? this : (other as GanjFonts? ?? this);
}

ThemeData buildGanjTheme(Brightness brightness, {bool iranNastaliq = false}) {
  final c = brightness == Brightness.light ? GanjColors.light : GanjColors.dark;
  final scheme = ColorScheme.fromSeed(seedColor: c.gold, brightness: brightness).copyWith(
    surface: c.paper,
    onSurface: c.ink,
    primary: c.lapis,
    onPrimary: c.page,
    secondary: c.gold,
    error: c.brandRed,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: kBodyFont,
    scaffoldBackgroundColor: c.page,
    dividerColor: c.borderGold,
    // Desktop: a quick fade. The default zoom snapshots the whole page first, which hitches
    // when opening a screen (most visibly Settings) on Windows.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: _QuickFadeTransitions(),
        TargetPlatform.windows: _QuickFadeTransitions(),
        TargetPlatform.linux: _QuickFadeTransitions(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.page,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    extensions: [
      c,
      GanjFonts(nastaliq: iranNastaliq ? 'IranNastaliq' : kNastaliqFont),
    ],
  );
}

/// Verse text: Vazirmatn at weight 300, line-height 2.2 (ganjoor.net).
TextStyle verseStyle(GanjColors c, double scale) => TextStyle(
  fontFamily: kBodyFont,
  fontSize: 19 * scale,
  height: 2.2,
  fontWeight: FontWeight.w300,
  fontVariations: const [FontVariation('wght', 300)],
  color: c.ink,
);

/// Heading style honouring the reader's Nastaliq choice.
TextStyle nastaliqStyleFor(ThemeData theme, double size) =>
    nastaliqStyle(theme.extension<GanjColors>()!, size).copyWith(
      fontFamily: theme.extension<GanjFonts>()?.nastaliq ?? kNastaliqFont,
      fontFamilyFallback: const [kNastaliqFont],
    );

TextStyle nastaliqOf(BuildContext context, double size) => nastaliqStyleFor(Theme.of(context), size);

TextStyle nastaliqStyle(GanjColors c, double size) =>
    TextStyle(fontFamily: kNastaliqFont, fontSize: size, height: 1.9, color: c.ink);

class _QuickFadeTransitions extends PageTransitionsBuilder {
  const _QuickFadeTransitions();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
}
