import 'package:flutter/material.dart';

/// Shown when the app fails before its first screen (e.g. the database or a folder can't be
/// opened), instead of an empty white window. Bilingual on purpose: the language setting may be
/// what failed to load. Uses no app fonts, theme or assets, so it can always draw.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error, this.logPath});

  final Object error;

  /// Where the full details were written, if anywhere.
  final String? logPath;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'گنج نتوانست باز شود.',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Text('Ganj could not start.', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 16),
                const Text('Please send this message to https://github.com/aminkvh/Ganj/issues'),
                const SizedBox(height: 12),
                Text('$error', style: const TextStyle(fontFamily: 'monospace')),
                if (logPath != null) ...[const SizedBox(height: 12), Text('Log: $logPath')],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
