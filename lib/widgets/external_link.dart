import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';

Future<bool> _launch(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens a link outside the app (tests swap it out).
final urlLauncherProvider = Provider<Future<bool> Function(Uri)>((ref) => _launch);

/// The same page on ganjoor.net, for an API `fullUrl` like `/hafez/ghazal/sh1`.
String ganjoorSiteUrl(String fullUrl) => 'https://ganjoor.net$fullUrl';

/// App-bar button that opens this page on the original Ganjoor site.
class OpenOnGanjoorButton extends ConsumerWidget {
  const OpenOnGanjoorButton({super.key, required this.fullUrl});

  final String fullUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: context.l10n.openOnGanjoor,
    icon: const Icon(Icons.open_in_new),
    onPressed: () => openExternal(context, ganjoorSiteUrl(fullUrl), launcher: ref.read(urlLauncherProvider)),
  );
}

/// Opens an http(s) link in the browser; anything else (empty, javascript:, file:) is refused,
/// and a failure tells the reader instead of silently doing nothing.
Future<void> openExternal(BuildContext context, String url, {Future<bool> Function(Uri)? launcher}) async {
  final l = context.l10n;
  void say(String text) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  final uri = Uri.tryParse(url.trim());
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
    say(l.invalidLink);
    return;
  }
  try {
    if (!await (launcher ?? _launch)(uri)) say(l.linkFailed);
  } catch (_) {
    say(l.linkFailed);
  }
}
