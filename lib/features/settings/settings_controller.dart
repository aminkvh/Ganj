import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

class Settings {
  const Settings({
    this.themeMode = ThemeMode.system,
    this.fontScale = 1.0,
    this.showMeaning = false,
    this.iranNastaliq = false,
    this.language = 'fa',
    this.translateTo = 'en',
  });

  final ThemeMode themeMode;
  final double fontScale;
  final bool showMeaning;
  final bool iranNastaliq;

  /// Interface language: 'fa' or 'en'. Poems are always shown in Persian.
  final String language;

  /// Target language of machine translation (a key of `kTranslateTargets`).
  final String translateTo;

  Settings copyWith({
    ThemeMode? themeMode,
    double? fontScale,
    bool? showMeaning,
    bool? iranNastaliq,
    String? language,
    String? translateTo,
  }) => Settings(
    themeMode: themeMode ?? this.themeMode,
    fontScale: fontScale ?? this.fontScale,
    showMeaning: showMeaning ?? this.showMeaning,
    iranNastaliq: iranNastaliq ?? this.iranNastaliq,
    language: language ?? this.language,
    translateTo: translateTo ?? this.translateTo,
  );
}

class SettingsController extends Notifier<Settings> {
  static const _kTheme = 'theme',
      _kScale = 'fontScale',
      _kMeaning = 'showMeaning',
      _kIran = 'iranNastaliq',
      _kLanguage = 'language',
      _kTranslateTo = 'translateTo';

  @override
  Settings build() {
    final p = ref.watch(sharedPrefsProvider);
    return Settings(
      themeMode: ThemeMode.values[p.getInt(_kTheme) ?? 0],
      fontScale: p.getDouble(_kScale) ?? 1.0,
      showMeaning: p.getBool(_kMeaning) ?? false,
      iranNastaliq: p.getBool(_kIran) ?? false,
      language: p.getString(_kLanguage) == 'en' ? 'en' : 'fa',
      translateTo: p.getString(_kTranslateTo) ?? 'en',
    );
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

  void toggleMeaning() {
    state = state.copyWith(showMeaning: !state.showMeaning);
    ref.read(sharedPrefsProvider).setBool(_kMeaning, state.showMeaning);
  }
}

final settingsProvider = NotifierProvider<SettingsController, Settings>(SettingsController.new);
