import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/text/persian_normalize.dart';
import '../../core/theme/ganj_colors.dart';
import '../../core/theme/ganj_theme.dart';
import '../../data/providers.dart';
import '../library/library_providers.dart';
import '../voice/app/voice_cache.dart' show VoiceCache;
import '../voice/app/voice_manifest.dart' show kFastVariant;
import '../voice/app/voice_providers.dart';
import '../translate/translator.dart';
import 'licenses.dart';
import 'settings_controller.dart';
import '../../l10n/l10n.dart';
import '../../core/net/disk_image.dart';
import '../../version.dart';
import '../update/update_check.dart';
import '../update/update_notice.dart';

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

  /// Bytes on disk under the voice root (installed voice or a partial download); the remove row shows when > 0.
  int _voiceBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    _loadVoiceBytes();
  }

  /// True where the voice is set up (its providers are wired: every platform in main.dart; null in tests).
  bool get _hasVoice => ref.read(voiceCacheBaseProvider) != null;

  /// The machine-reading cache; null where the voice is not set up.
  VoiceCache? get _voiceCache => _hasVoice ? ref.read(voiceCacheProvider) : null;

  void _loadVoiceBytes() {
    if (!_hasVoice) return;
    final n = voiceRootBytes(ref.read(voiceRootProvider));
    if (mounted && n != _voiceBytes) setState(() => _voiceBytes = n);
  }

  Future<void> _loadCacheSize() async {
    final r = await ref
        .read(appDbProvider)
        .customSelect('SELECT coalesce(sum(length(body)), 0) AS b FROM api_cache')
        .getSingle();
    final voiceBytes = await _voiceCache?.sizeBytes() ?? 0;
    if (mounted) setState(() => _cacheBytes = r.read<int>('b') + voiceBytes);
  }

  /// Only the API response cache: installed packs, downloaded audio and user data stay.
  Future<void> _clearCache() async {
    final db = ref.read(appDbProvider);
    try {
      await db.customStatement('DELETE FROM api_cache');
      await db.customStatement('VACUUM'); // give the space back to the disk
      await DiskImage.clear();
      // Finished machine readings; the voice itself stays, and so do the parts of a prepare still running and
      // the beyt items of a reading still being streamed.
      await _voiceCache?.clear(keep: _hasVoice ? ref.read(voicePreparesProvider).keepParts : const {});
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

  /// Deletes the on-device voice (and its readings) after a confirmation.
  Future<void> _removeVoice() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.voiceRowTitle),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(voiceProvider.notifier).remove();
    } catch (_) {
      _say(l.clearFailed);
      _loadVoiceBytes();
      return;
    }
    _loadVoiceBytes();
    await _loadCacheSize();
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
    // The voice's folders exist only where the app sets them up (main.dart, every platform).
    final voice = ref.watch(voiceCacheBaseProvider) == null ? null : ref.watch(voiceProvider);
    // A download that ends (installed, failed, cancelled) while this page is open changes what is on disk.
    if (voice != null) ref.listen(voiceProvider, (_, s) => _loadVoiceBytes());
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
            leading: const Icon(Icons.language),
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
            leading: const Icon(Icons.format_size),
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
            secondary: const Icon(Icons.lightbulb_outline),
            title: Text(context.l10n.showMeaningsDefault),
            value: s.showMeaning,
            onChanged: (_) => ctrl.toggleMeaning(),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.map_outlined),
            title: Text(context.l10n.mapStartsOnAll),
            value: s.mapStartsOnAll,
            onChanged: ctrl.setMapStartsOnAll,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.abc),
            title: Text(context.l10n.tajikScript),
            subtitle: Text(context.l10n.tajikScriptNote, style: TextStyle(color: c.muted, fontSize: 12)),
            value: s.showTajik,
            onChanged: ctrl.setShowTajik,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.font_download_outlined),
            title: Text(context.l10n.useIranNastaliq),
            subtitle: Text(context.l10n.iranNastaliqNote, style: TextStyle(color: c.muted, fontSize: 12)),
            value: s.iranNastaliq,
            onChanged: ctrl.setIranNastaliq,
          ),
          header(context.l10n.translate),
          ListTile(
            leading: const Icon(Icons.translate),
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
            leading: const Icon(Icons.storage_outlined),
            title: Text(context.l10n.cacheSize),
            subtitle: Text(_cacheBytes == null ? '…' : formatBytes(_cacheBytes!), style: TextStyle(color: c.muted)),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(context.l10n.clearCache),
            subtitle: Text(context.l10n.clearCacheNote, style: TextStyle(color: c.muted, fontSize: 12)),
            onTap: _clearCache,
          ),
          // Any bytes under the voice root: an installed voice, or a partial download to give back.
          if (voice != null && _voiceBytes > 0)
            ListTile(
              key: const ValueKey('voice-remove'),
              leading: const Icon(Icons.delete_outline),
              title: Text(switch (voice) {
                // Only the (dormant) fast variant is named; the single quality voice has the plain label.
                VoiceReady(:final variant) when variant == kFastVariant => context.l10n.voiceRemoveVariant(
                  context.l10n.voiceFast,
                  formatBytes(_voiceBytes),
                ),
                _ => context.l10n.voiceRemove(formatBytes(_voiceBytes)),
              }),
              onTap: _removeVoice,
            ),
          header(context.l10n.about),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
              showLicensePage(context: context, applicationName: context.l10n.appName, applicationVersion: kAppVersion);
            },
          ),
          if (kAppVersion.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(context.l10n.versionN(localDigits(kAppVersion))),
            ),
          if (ref.watch(updateProvider).value case final u?)
            ListTile(
              key: const ValueKey('update-row'),
              leading: const Icon(Icons.system_update_alt),
              title: Text(context.l10n.appUpdateInSettings(localDigits(u.version))),
              subtitle: Text(context.l10n.download),
              onTap: () => openUpdatePage(u),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
