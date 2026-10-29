import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Desktop keys for the whole app: Escape, Backspace and Alt+← go back; the arrow keys start
/// walking the controls on a screen when nothing is focused yet (afterwards the framework's
/// directional focus takes over). Typing in a field and open dialogs/menus are left alone.
class KeyboardNav extends StatefulWidget {
  const KeyboardNav({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  State<KeyboardNav> createState() => _KeyboardNavState();
}

class _KeyboardNavState extends State<KeyboardNav> {
  static final _arrows = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    final key = e.logicalKey;
    final typing = ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
    final onPopup = ctx != null && ModalRoute.of(ctx) is PopupRoute;
    if (onPopup) return KeyEventResult.ignored; // dialogs and menus handle their own keys

    if (typing) {
      if (key == LogicalKeyboardKey.escape) {
        focus!.unfocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final alt = HardwareKeyboard.instance.isAltPressed;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.browserBack ||
        (alt && key == LogicalKeyboardKey.arrowLeft)) {
      return _back() ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (_arrows.contains(key) && (focus == null || focus is FocusScopeNode)) {
      // Nothing is focused yet: land on the first control of the screen.
      (focus as FocusScopeNode? ?? FocusManager.instance.rootScope).nextFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _back() {
    final r = widget.router;
    if (r.canPop()) {
      r.pop();
      return true;
    }
    if (r.routerDelegate.currentConfiguration.uri.path != '/') {
      r.go('/');
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: widget.child);
}
