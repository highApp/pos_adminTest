import 'package:flutter/services.dart';

/// VM (mobile/desktop): use Flutter's hardware keyboard handler.
void initSellersShortcut(void Function() onTrigger) {
  _callback = onTrigger;
  HardwareKeyboard.instance.addHandler(_keyHandler);
}

void disposeSellersShortcut() {
  HardwareKeyboard.instance.removeHandler(_keyHandler);
  _callback = null;
}

void Function()? _callback;

bool _keyHandler(KeyEvent event) {
  if (_callback == null) return false;
  if (event is! KeyDownEvent) return false;
  if (event.logicalKey != LogicalKeyboardKey.keyS) return false;
  final k = HardwareKeyboard.instance;
  final mac = k.isMetaPressed && k.isAltPressed;
  final win = k.isControlPressed && k.isAltPressed;
  if (!mac && !win) return false;
  _callback!();
  return true;
}
