import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../l10n/l10n.dart';

bool _opening = false;

/// Opens a random poem (of [poetId], or of any poet). Taps while one is loading are ignored.
Future<void> openRandomPoem(BuildContext context, WidgetRef ref, {int? poetId}) async {
  if (_opening) return;
  _opening = true;
  try {
    final poem = await ref.read(ganjoorApiProvider).randomPoem(poetId: poetId);
    if (context.mounted) context.push('/poem/${poem.id}');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.offline)));
    }
  } finally {
    _opening = false;
  }
}
