import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../core/theme/ganj_theme.dart';
import '../../data/providers.dart';
import '../library/library_providers.dart';
import '../translate/translator.dart';
import 'licenses.dart';
import 'settings_controller.dart';
import '../../l10n/l10n.dart';

/// Public source repository; set once the project is published (the link is hidden while empty).
const kSourceUrl = 'https://github.com/aminkvh/Ganj';

/// Reading preferences, cache management, credits and licenses.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int? _cacheBytes;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    PackageInfo.fromPlatform()
        .then((i) {
          if (mounted) setState(() => _version = i.version);
        })
        .catchError((_) {});
  }

  Future<void> _loadCacheSize() async {
    final r = await ref
        .read(appDbProvider)
        .customSelect('SELECT coalesce(sum(length(body)), 0) AS b FROM api_cache')
        .getSingle();
    if (mounted) setState(() => _cacheBytes = r.read<int>('b'));
  }

  /// Only the API response cache: installed packs, downloaded audio and user data stay.
  Future<void> _clearCache() async {
    final db = ref.read(appDbProvider);
    try {
      await db.customStatement('DELETE FROM api_cache');
      await db.customStatement('VACUUM'); // give the space back to the disk
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.clearFailed)));
      return;
    }
    await _loadCacheSize();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.cacheCleared)));
  }

  Future<void> _removeModel(Translator t, String to) async {
    final l = context.l10n;
    try {
      await t.remove(to);
      _say(l.modelRemoved);
    } catch (_) {
      _say(l.clearFailed);
    }
  }

  void _say(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ganj;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final translator = ref.watch(translatorProvider);
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        t,
        style: TextStyle(color: c.gold, fontWeight: FontWeight.w700),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsAndAbout)),
      body: ListView(
        children: [
          header(context.l10n.display),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(context.l10n.themeSystem)),
                ButtonSegment(value: ThemeMode.light, label: Text(context.l10n.themeLight)),
                ButtonSegment(value: ThemeMode.dark, label: Text(context.l10n.themeDark)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => ctrl.setThemeMode(v.first),
            ),
          ),
          ListTile(
            title: Text(context.l10n.language),
            trailing: SegmentedButton<String>(
              // Each language is named in its own script, so it can be found from either one.
              segments: const [
                ButtonSegment(value: 'fa', label: Text('فارسی')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.language},
              onSelectionChanged: (v) => ctrl.setLanguage(v.first),
            ),
          ),
          ListTile(
            title: Text(context.l10n.verseTextSize),
            subtitle: Slider(
              value: s.fontScale,
              min: 0.8,
              max: 1.8,
              divisions: 10,
              label: localDecimal(s.fontScale.toStringAsFixed(1)),
              onChanged: ctrl.setFontScale,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'اَلا یا اَیُّهَا السّاقی اَدِرْ کَأساً و ناوِلْها',
              textAlign: TextAlign.center,
              style: verseStyle(c, s.fontScale),
            ),
          ),
          SwitchListTile(
            title: Text(context.l10n.showMeaningsDefault),
            value: s.showMeaning,
            onChanged: (_) => ctrl.toggleMeaning(),
          ),
          SwitchListTile(
            title: Text(context.l10n.useIranNastaliq),
            subtitle: Text(context.l10n.iranNastaliqNote, style: TextStyle(color: c.muted, fontSize: 12)),
            value: s.iranNastaliq,
            onChanged: ctrl.setIranNastaliq,
          ),
          header(context.l10n.translate),
          ListTile(
            title: Text(context.l10n.translateTo),
            subtitle: translator.inApp
                ? null
                : Text(context.l10n.translateInBrowser, style: TextStyle(color: c.muted, fontSize: 12)),
            trailing: DropdownButton<String>(
              key: const ValueKey('translate-to'),
              value: s.translateTo,
              underline: const SizedBox.shrink(),
              items: [for (final e in kTranslateTargets.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => v == null ? null : ctrl.setTranslateTo(v),
            ),
          ),
          if (translator.needsModel)
            ListTile(
              key: const ValueKey('translate-remove'),
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.removeModel),
              onTap: () => _removeModel(translator, s.translateTo),
            ),
          header(context.l10n.storage),
          ListTile(
            title: Text(context.l10n.cacheSize),
            subtitle: Text(_cacheBytes == null ? '…' : formatBytes(_cacheBytes!), style: TextStyle(color: c.muted)),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(context.l10n.clearCache),
            subtitle: Text(context.l10n.clearCacheNote, style: TextStyle(color: c.muted, fontSize: 12)),
            onTap: _clearCache,
          ),
          header(context.l10n.about),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.l10n.aboutText, textAlign: TextAlign.justify, style: const TextStyle(height: 1.9)),
          ),
          ListTile(
            key: const ValueKey('made-by'),
            leading: const Icon(Icons.favorite_outline),
            title: Text(context.l10n.madeBy),
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: Text(context.l10n.ganjoor),
            subtitle: const Text('ganjoor.net', textDirection: TextDirection.ltr),
            onTap: () => launchUrl(Uri.parse('https://ganjoor.net'), mode: LaunchMode.externalApplication),
          ),
          if (kSourceUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(context.l10n.sourceCode),
              onTap: () => launchUrl(Uri.parse(kSourceUrl), mode: LaunchMode.externalApplication),
            ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(context.l10n.licenses),
            onTap: () {
              registerLicenses();
              showLicensePage(context: context, applicationName: context.l10n.appName, applicationVersion: _version);
            },
          ),
          if (_version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.versionN(localDigits(_version)),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
            ),
        ],
      ),
    );
  }
}
