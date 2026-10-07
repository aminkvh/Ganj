import 'package:flutter/material.dart';

const _essential = {ContextMenuButtonType.copy, ContextMenuButtonType.selectAll};

/// Only Copy and Select all. Android otherwise adds every installed app that handles selected
/// text ("Ask Claude", "ChatGPT", translators…) to the menu, which crowds it for poetry.
List<ContextMenuButtonItem> essentialSelectionItems(List<ContextMenuButtonItem> items) => [
  for (final b in items)
    if (_essential.contains(b.type)) b,
];

/// The text-selection menu used wherever Ganj lets you select text.
Widget ganjSelectionMenu(BuildContext context, SelectableRegionState state) => AdaptiveTextSelectionToolbar.buttonItems(
  anchors: state.contextMenuAnchors,
  buttonItems: essentialSelectionItems(state.contextMenuButtonItems),
);
