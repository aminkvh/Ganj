import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../widgets/error_retry.dart';
import '../../l10n/l10n.dart';

/// Resolves a ganjoor.net path (links that carry only a url) to a poem page.
class UrlScreen extends ConsumerStatefulWidget {
  const UrlScreen({super.key, required this.url});

  final String url;

  @override
  ConsumerState<UrlScreen> createState() => _UrlScreenState();
}

class _UrlScreenState extends ConsumerState<UrlScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() => _error = null);
    try {
      final id = await ref.read(ganjoorApiProvider).poemIdForUrl(widget.url);
      if (mounted) context.pushReplacement('/poem/$id');
    } catch (e) {
      // No response at all means no connection; any answer from Ganjoor means the link is unknown.
      final offline = e is DioException && e.response == null;
      if (mounted) setState(() => _error = offline ? context.l10n.offline : context.l10n.poemNotFound);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: _error != null
        ? ErrorRetry(message: _error!, onRetry: _resolve)
        : const Center(child: CircularProgressIndicator()),
  );
}
