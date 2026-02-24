import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:whatsapp_share2/whatsapp_share2.dart';

Future<bool> sharePdfToWhatsAppContact(
  String phone,
  Uint8List pdfBytes,
  String filename,
  String sellerName, {
  String? reportLabel,
}) async {
  final installed = await WhatsappShare.isInstalled(package: Package.whatsapp);
  if (installed != true) return false;

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(pdfBytes);
  final text = reportLabel != null ? '$reportLabel - $sellerName' : 'Seller History Report - $sellerName';
  await WhatsappShare.shareFile(
    phone: phone,
    filePath: [file.path],
    text: text,
  );
  return true;
}
