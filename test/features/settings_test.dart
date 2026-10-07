import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganj/data/providers.dart';
import 'package:ganj/features/settings/settings_controller.dart';

import '../support/test_app.dart';

void main() {
  test('defaults, zoom clamping and persistence', () async {
    final prefs = await mockPrefs();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).fontScale, 1.0);
    expect(c.read(settingsProvider).themeMode, ThemeMode.system);
    final ctrl = c.read(settingsProvider.notifier);
    for (var i = 0; i < 20; i++) {
      ctrl.zoom(0.1);
    }
    expect(c.read(settingsProvider).fontScale, 1.8);
    ctrl.toggleTheme(Brightness.light);
    ctrl.toggleMeaning();
    expect(prefs.getDouble('fontScale'), 1.8);
    expect(prefs.getInt('theme'), ThemeMode.dark.index);
    expect(prefs.getBool('showMeaning'), isTrue);
  });

  test('restores saved values', () async {
    final prefs = await mockPrefs({'fontScale': 1.3, 'theme': ThemeMode.light.index, 'showMeaning': true});
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    final s = c.read(settingsProvider);
    expect(s.fontScale, 1.3);
    expect(s.themeMode, ThemeMode.light);
    expect(s.showMeaning, isTrue);
  });
}
