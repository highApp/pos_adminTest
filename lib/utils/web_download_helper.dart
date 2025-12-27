import 'dart:convert';
import 'dart:html' as html;

/// Helper class for web file downloads
class WebDownloadHelper {
  /// Download a CSV file on web
  static void downloadCsv(String csvContent, String filename) {
    try {
      final bytes = utf8.encode(csvContent);
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      
      // Create anchor element
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..style.display = 'none';
      
      // Add to DOM, click, then remove
      html.document.body?.append(anchor);
      anchor.click();
      
      // Clean up after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        html.document.body?.removeChild(anchor);
        html.Url.revokeObjectUrl(url);
      });
    } catch (e) {
      print('Error downloading CSV: $e');
      rethrow;
    }
  }

  /// Download any text file on web
  static void downloadText(String content, String filename, String mimeType) {
    final bytes = utf8.encode(content);
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

