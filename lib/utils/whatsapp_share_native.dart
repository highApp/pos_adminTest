import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:whatsapp_share2/whatsapp_share2.dart';

Future<bool> sharePdfToWhatsAppContact(
  String phone,
  Uint8List pdfBytes,
  String filename,
  String sellerName,
) async {
  final installed = await WhatsappShare.isInstalled(package: Package.whatsapp);
  if (!installed) return false;

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(pdfBytes);
  await WhatsappShare.shareFile(
    phone: phone,
    filePath: [file.path],
    text: 'Seller History Report - $sellerName',
  );
  return true;
}
