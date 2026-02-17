import 'dart:typed_data';

Future<bool> sharePdfToWhatsAppContact(
  String phone,
  Uint8List pdfBytes,
  String filename,
  String sellerName, {
  String? reportLabel,
}) async {
  throw UnsupportedError('WhatsApp direct share is only supported on Android and iOS');
}
