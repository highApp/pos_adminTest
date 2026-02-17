import 'dart:typed_data';
import 'dart:html' as html;

/// Download PDF on web (Chrome, etc.)
void downloadPdf(Uint8List bytes, String filename) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  Future.delayed(const Duration(milliseconds: 200), () {
    anchor.remove();
    html.Url.revokeObjectUrl(url);
  });
}
