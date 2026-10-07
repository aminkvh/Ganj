import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/core/theme/ganj_colors.dart';
import 'package:ganj/core/theme/ganj_theme.dart';

void main() {
  test('themes carry Ganjoor tokens', () {
    final light = buildGanjTheme(Brightness.light);
    final dark = buildGanjTheme(Brightness.dark);
    expect(light.extension<GanjColors>()!.page, const Color(0xFFFBF6EA));
    expect(light.scaffoldBackgroundColor, const Color(0xFFFBF6EA));
    expect(dark.extension<GanjColors>()!.brandRed, const Color(0xFFD4553A));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF14120F));
    expect(light.textTheme.bodyMedium!.fontFamily, kBodyFont);
  });

  test('lerp blends every token', () {
    final mid = GanjColors.light.lerp(GanjColors.dark, 0.5);
    expect(mid.gold, Color.lerp(GanjColors.light.gold, GanjColors.dark.gold, 0.5));
  });

  test('verse style uses weight 300 and line height 2.2, scaled', () {
    final s = verseStyle(GanjColors.light, 1.5);
    expect(s.height, 2.2);
    expect(s.fontWeight, FontWeight.w300);
    expect(s.fontSize, closeTo(19 * 1.5, 0.001));
  });
}
