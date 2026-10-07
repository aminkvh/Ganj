import 'persian_normalize.dart';

/// Gregorian → Solar Hijri (Jalali) date, the calendar Persian readers expect.
(int, int, int) toJalali(DateTime d) {
  const g = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy = d.year, gm = d.month, gd = d.day;
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + 365 * gy + (gy2 + 3) ~/ 4 - (gy2 + 99) ~/ 100 + (gy2 + 399) ~/ 400 + gd + g[gm - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  return days < 186 ? (jy, 1 + days ~/ 31, 1 + days % 31) : (jy, 7 + (days - 186) ~/ 30, 1 + (days - 186) % 30);
}

/// «۱۴۰۵/۷/۱۴»
String faDate(DateTime d) {
  final (y, m, day) = toJalali(d);
  return localDigits('$y/$m/$day');
}
