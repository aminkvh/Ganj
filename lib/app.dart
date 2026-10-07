import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/text/content_en.dart';
import 'core/text/persian_normalize.dart';
import 'data/providers.dart';
import 'core/theme/ganj_theme.dart';
import 'features/settings/settings_controller.dart';
import 'l10n/l10n.dart';
import 'router.dart';

class GanjApp extends ConsumerWidget {
  const GanjApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    latinNumbers = s.language == 'en';
    englishContent = s.language == 'en' ? ref.watch(englishContentProvider) : null;
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appName,
      debugShowCheckedModeBanner: false,
      theme: buildGanjTheme(Brightness.light, iranNastaliq: s.iranNastaliq),
      darkTheme: buildGanjTheme(Brightness.dark, iranNastaliq: s.iranNastaliq),
      themeMode: s.themeMode,
      locale: Locale(s.language),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
