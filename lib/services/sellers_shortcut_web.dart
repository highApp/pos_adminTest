import 'dart:html' as html;

/// Web: index.html script catches Cmd+Option+S and dispatches 'sellers-quick-access'; we listen here.
void initSellersShortcut(void Function() onTrigger) {
  _callback = onTrigger;
  html.window.addEventListener('sellers-quick-access', _handler);
}

void disposeSellersShortcut() {
  html.window.removeEventListener('sellers-quick-access', _handler);
  _callback = null;
}

void Function()? _callback;

void _handler(html.Event e) {
  _callback?.call();
}
