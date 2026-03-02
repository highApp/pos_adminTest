import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Intents for app-wide and dialog keyboard shortcuts.
/// Arrow keys use Flutter's [DirectionalFocusIntent] / [DirectionalFocusAction] for focus movement.
/// Named to avoid conflict with Flutter's built-in [DismissIntent].
class CloseIntent extends Intent {
  const CloseIntent();
}

class SubmitIntent extends Intent {
  const SubmitIntent();
}

class KeyboardHelpIntent extends Intent {
  const KeyboardHelpIntent();
}

class SwitchTabIntent extends Intent {
  const SwitchTabIntent(this.index);
  final int index;
}

/// Shows a dialog listing keyboard shortcuts (Chrome / desktop).
void showKeyboardShortcutsHelp(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.keyboard, color: Colors.blue),
          SizedBox(width: 10),
          Text('Keyboard shortcuts'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _shortcutRow('Escape', 'Close dialog / Go back'),
            _shortcutRow('Enter', 'Submit form / Confirm (in dialogs)'),
            _shortcutRow('↑ ↓ ← → (Arrow keys)', 'Move focus between buttons, fields, list items'),
            _shortcutRow('Tab', 'Move to next field'),
            _shortcutRow('Shift + Tab', 'Move to previous field'),
            const Divider(),
            _shortcutRow('? or F1', 'Show this help'),
            _shortcutRow('Ctrl + Alt + S (Win)\nCmd + Option + S (Mac)', 'Sellers quick access'),
            _shortcutRow('Ctrl + 1 … 5 (Win)\nCmd + 1 … 5 (Mac)', 'Switch screen (Dashboard, Products, POS, Buyer, Sales)'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _shortcutRow(String keys, String action) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          child: Text(
            keys,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(action, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

/// Default shortcut map for dialogs: Escape = close, Enter = submit.
Map<ShortcutActivator, Intent> get dialogShortcuts => {
      const SingleActivator(LogicalKeyboardKey.escape): const CloseIntent(),
      const SingleActivator(LogicalKeyboardKey.enter): const SubmitIntent(),
    };
