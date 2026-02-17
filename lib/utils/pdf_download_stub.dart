import 'dart:typed_data';

/// Stub for non-web platforms - use Printing.sharePdf instead
void downloadPdf(Uint8List bytes, String filename) {
  // No-op; caller should use Printing.sharePdf on mobile
}
