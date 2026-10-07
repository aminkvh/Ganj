import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n.dart';

/// Back to the home page in one tap, from however deep the reader has gone.
class HomeButton extends StatelessWidget {
  const HomeButton({super.key});

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: context.l10n.home, icon: const Icon(Icons.home_outlined), onPressed: () => context.go('/'));
}
