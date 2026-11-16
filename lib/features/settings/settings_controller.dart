import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// The Tajik (Cyrillic) text of the verses, where Ganjoor has it: not shown, under each verse, or
/// in place of the Persian (for readers of Tajik who don't read the Persian script).
enum TajikScript { off, below, only }

class Settings {
  const Settings({
    this.themeMode = ThemeMode.system,
    this.fontScale = 1.0,
    this.showMeaning = false,
    this.iranNastaliq = false,
    this.language = 'fa',
    this.translateTo = 'en',
    this.tajikScript = TajikScript.off,
    this.mapStartsOnAll = true,
    this.excludedPoets = const {},
  });

  final ThemeMode themeMode;
  final double fontScale;
  final bool showMeaning;
  final bool iranNastaliq;

  /// Interface language: 'fa' or 'en'. Poems are always shown in Persian.
  final String language;

  /// Target language of machine translation (a key of `kTranslateTargets`).
  final String translateTo;

  final TajikScript tajikScript;

  /// Tajik text is shown in some way.
  bool get showTajik => tajikScript != TajikScript.off;

  /// The poets' map opens on every century at once (otherwise on the first century).
  final bool mapStartsOnAll;

  /// Poets whose poems are left out of word search, until the reader brings them back.
  final Set<int> excludedPoets;

  Settings copyWith({
    ThemeMode? themeMode,
    double? fontScale,
    bool? showMeaning,
    bool? iranNastaliq,
    String? language,
    String? translateTo,
    TajikScript? tajikScript,
    bool? mapStartsOnAll,
    Set<int>? excludedPoets,
  }) => Settings(
    themeMode: themeMode ?? this.themeMode,
    fontScale: fontScale ?? this.fontScale,
    showMeaning: showMeaning ?? this.showMeaning,
    iranNastaliq: iranNastaliq ?? this.iranNastaliq,
    language: language ?? this.language,
    translateTo: translateTo ?? this.translateTo,
    tajikScript: tajikScript ?? this.tajikScript,
    mapStartsOnAll: mapStartsOnAll ?? this.mapStartsOnAll,
    excludedPoets: excludedPoets ?? this.excludedPoets,
  );
}

class SettingsController extends Notifier<Settings> {
  static const _kTheme = 'theme',
      _kScale = 'fontScale',
      _kMeaning = 'showMeaning',
      _kIran = 'iranNastaliq',
      _kLanguage = 'language',
      _kTranslateTo = 'translateTo',
      _kTajikOld = 'showTajik',
      _kTajik = 'tajikScript',
      _kMapAll = 'mapStartsOnAll',
      _kExcluded = 'excludedPoets';

  @override
  Settings build() {
    final p = ref.watch(sharedPrefsProvider);
    final saved = TajikScript.values.asNameMap()[p.getString(_kTajik)];
    if (saved != null && saved != TajikScript.off) _lastTajik = saved;
    return Settings(
      themeMode: ThemeMode.values[p.getInt(_kTheme) ?? 0],
      fontScale: p.getDouble(_kScale) ?? 1.0,
      showMeaning: p.getBool(_kMeaning) ?? false,
      iranNastaliq: p.getBool(_kIran) ?? false,
      language: p.getString(_kLanguage) == 'en' ? 'en' : 'fa',
      translateTo: p.getString(_kTranslateTo) ?? 'en',
      // Before 1.6.3 the option was a switch: on meant under each verse.
      tajikScript: saved ?? ((p.getBool(_kTajikOld) ?? false) ? TajikScript.below : TajikScript.off),
      mapStartsOnAll: p.getBool(_kMapAll) ?? true,
      excludedPoets: {for (final s in p.getStringList(_kExcluded) ?? const []) ?int.tryParse(s)},
    );
  }

  void setExcludedPoets(Set<int> ids) {
    state = state.copyWith(excludedPoets: ids);
    ref.read(sharedPrefsProvider).setStringList(_kExcluded, [for (final id in ids) '$id']);
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    ref.read(sharedPrefsProvider).setInt(_kTheme, mode.index);
  }

  void toggleTheme(Brightness current) => setThemeMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  void zoom(double delta) {
    final next = double.parse((state.fontScale + delta).clamp(0.8, 1.8).toStringAsFixed(1));
    state = state.copyWith(fontScale: next);
    ref.read(sharedPrefsProvider).setDouble(_kScale, next);
  }

  void setFontScale(double v) {
    final next = double.parse(v.clamp(0.8, 1.8).toStringAsFixed(1));
    state = state.copyWith(fontScale: next);
    ref.read(sharedPrefsProvider).setDouble(_kScale, next);
  }

  void setIranNastaliq(bool on) {
    state = state.copyWith(iranNastaliq: on);
    ref.read(sharedPrefsProvider).setBool(_kIran, on);
  }

  void setLanguage(String language) {
    state = state.copyWith(language: language);
    ref.read(sharedPrefsProvider).setString(_kLanguage, language);
  }

  void setTranslateTo(String to) {
    state = state.copyWith(translateTo: to);
    ref.read(sharedPrefsProvider).setString(_kTranslateTo, to);
  }

  void setTajikScript(TajikScript v) {
    if (v != TajikScript.off) _lastTajik = v;
    state = state.copyWith(tajikScript: v);
    ref.read(sharedPrefsProvider).setString(_kTajik, v.name);
  }

  /// The poem menu's switch: off, or back to how Tajik was last shown (under the verses at first).
  void toggleTajik() => setTajikScript(state.showTajik ? TajikScript.off : _lastTajik);

  TajikScript _lastTajik = TajikScript.below;

  void setMapStartsOnAll(bool on) {
    state = state.copyWith(mapStartsOnAll: on);
    ref.read(sharedPrefsProvider).setBool(_kMapAll, on);
  }

  void toggleMeaning() {
    state = state.copyWith(showMeaning: !state.showMeaning);
    ref.read(sharedPrefsProvider).setBool(_kMeaning, state.showMeaning);
  }
}

final settingsProvider = NotifierProvider<SettingsController, Settings>(SettingsController.new);
