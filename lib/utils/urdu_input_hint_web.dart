import 'dart:html' as html;

/// On web: set lang=ur and dir=rtl on the currently focused element
/// so the OS/browser may suggest the Urdu keyboard when the user focuses the Urdu field.
void setUrduInputHint() {
  try {
    final el = html.document.activeElement;
    if (el != null) {
      el.setAttribute('lang', 'ur');
      el.setAttribute('dir', 'rtl');
    }
  } catch (_) {}
}
