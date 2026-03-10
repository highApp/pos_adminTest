import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show debugPrint;

/// Urdu/Arabic font family (must be registered in pubspec.yaml).
const String _urduFontFamily = 'Noto Nastaliq Urdu';

/// Renders text (e.g. Urdu) to a 1-bit raster image for thermal printers that
/// don't support UTF-8. Returns ESC/POS GS v 0 command + image data, or null on failure.
Future<List<int>?> textToEscPosRaster(
  String text, {
  int maxWidthPixels = 256,
  double fontSize = 14.0,
}) async {
  if (text.isEmpty) return null;
  try {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: fontSize,
        fontFamily: _urduFontFamily,
        fontWeight: ui.FontWeight.normal,
        textDirection: ui.TextDirection.rtl,
      ),
    );
    builder.addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: maxWidthPixels.toDouble()));

    final width = paragraph.width.ceil();
    final height = paragraph.height.ceil();
    if (width <= 0 || height <= 0) return null;

    // Width must be multiple of 8 for ESC/POS
    final w = ((width + 7) ~/ 8) * 8;
    final h = height;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    // White background, black text (thermal: 1 = print)
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (byteData == null) return null;

    // Convert RGBA to 1-bit: dark pixel -> 1, light -> 0. Pack 8 horizontal pixels per byte (MSB = left).
    final bytesPerRow = w ~/ 8;
    final raster = <int>[];
    final rgba = byteData.buffer.asUint8List();
    for (int y = 0; y < h; y++) {
      for (int byteIndex = 0; byteIndex < bytesPerRow; byteIndex++) {
        int byte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final px = (y * w + byteIndex * 8 + bit) * 4;
          if (px + 3 < rgba.length) {
            final r = rgba[px];
            final g = rgba[px + 1];
            final b = rgba[px + 2];
            final a = rgba[px + 3];
            final luminance = (0.299 * r + 0.587 * g + 0.114 * b) * (a / 255);
            if (luminance < 180) byte |= (0x80 >> bit); // dark = print
          }
        }
        raster.add(byte);
      }
    }

    // ESC/POS GS v 0: 1D 76 30 m xL xH yL yH [data]
    // m=0 normal, width in bytes = bytesPerRow, height = h
    final xL = bytesPerRow & 0xFF;
    final xH = (bytesPerRow >> 8) & 0xFF;
    final yL = h & 0xFF;
    final yH = (h >> 8) & 0xFF;
    final cmd = [0x1D, 0x76, 0x30, 0, xL, xH, yL, yH];
    return [...cmd, ...raster];
  } catch (e) {
    debugPrint('receipt_text_to_image: $e');
    return null;
  }
}

/// Renders text (e.g. Urdu) to PNG image bytes for PDF. Uses RTL and Urdu font when available.
/// Returns null on failure.
Future<Uint8List?> textToPngBytes(
  String text, {
  int maxWidthPixels = 400,
  double fontSize = 14.0,
}) async {
  if (text.isEmpty) return null;
  try {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: fontSize,
        fontFamily: _urduFontFamily,
        fontWeight: ui.FontWeight.normal,
        textDirection: ui.TextDirection.rtl,
      ),
    );
    builder.addText(text);
    final paragraph = builder.build();
    paragraph.layout(ui.ParagraphConstraints(width: maxWidthPixels.toDouble()));

    final w = paragraph.width.ceil();
    final h = paragraph.height.ceil();
    // Treat tiny layout as failed (e.g. font not rendering on Android) so caller can show English fallback.
    if (w <= 0 || h <= 0 || h < 10) return null;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return null;
    return byteData.buffer.asUint8List();
  } catch (e) {
    debugPrint('receipt_text_to_image (PNG): $e');
    return null;
  }
}

/// Returns true if [text] contains non-ASCII (e.g. Urdu, Arabic).
bool containsNonAscii(String text) {
  return text.runes.any((r) => r > 127);
}
