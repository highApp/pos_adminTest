import 'dart:typed_data';
import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/product.dart';
import '../models/sale.dart';
import '../models/seller.dart';
import '../constants/receipt_branding.dart';
import '../utils/receipt_text_to_image.dart';
import '../utils/receipt_urdu_widget_render.dart';
import 'product_service.dart';

/// Generates a sale receipt PDF for viewing or downloading.
class ReceiptPdfService {
  static final ProductService _productService = ProductService();

  /// Generates PDF bytes for the given sale. Optional [seller] is shown as customer when present.
  /// [existingDueTotal] is the seller's due balance before this sale (shown as "Existing Due" on receipt).
  /// [contextForUrduRendering] When set (e.g. on Android), Urdu product names are rendered
  /// via the widget tree so the font displays correctly; otherwise uses ParagraphBuilder.
  static Future<Uint8List> generateSaleReceiptPdf(
    Sale sale, {
    Seller? seller,
    String languageCode = 'en',
    double existingDueTotal = 0,
    BuildContext? contextForUrduRendering,
  }) async {
    try {
      final pdf = pw.Document();
      final formatter = NumberFormat.currency(symbol: 'Rs. ', decimalDigits: 2);
      final dateFormatter = DateFormat('MMM dd, yyyy - hh:mm a');
      final printableItems = sale.items
          .where((item) => item.remainingQuantity > 0)
          .toList();

      final productNamesMap = await _getProductNames(sale, languageCode);
      // English names for fallback when Urdu image fails or for non-Urdu display.
      final Map<String, String>? productNamesMapEn =
          languageCode != 'en' ? await _getProductNames(sale, 'en') : null;
      // For Urdu/Arabic product names, render as image so PDF shows them (Courier has no Urdu glyphs).
      // On Android, use widget-based render so the app font is used; otherwise ParagraphBuilder.
      final Map<String, Uint8List?> productNameImageBytes = {};
      for (var item in printableItems) {
        final name = (productNamesMap[item.productId] ?? item.productName ?? '').trim();
        if (name.isNotEmpty && containsNonAscii(name)) {
          final Uint8List? pngBytes;
          if (contextForUrduRendering != null && contextForUrduRendering.mounted) {
            pngBytes = await renderUrduTextToImageWithContext(
              contextForUrduRendering,
              text: name,
              fontSize: 18,
              maxWidth: 480,
            );
          } else {
            pngBytes = await textToPngBytes(
              name,
              maxWidthPixels: 480,
              fontSize: 18,
            );
          }
          if (pngBytes != null && pngBytes.isNotEmpty) {
            productNameImageBytes[item.productId] = pngBytes;
          }
        }
      }

      final font = pw.Font.courier();

      pw.TextStyle textStyle({
        double fontSize = 6,
        pw.FontWeight? fontWeight,
      }) {
        return pw.TextStyle(
          font: font,
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      }

      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
            80 * PdfPageFormat.mm,
            double.infinity,
            marginAll: 3 * PdfPageFormat.mm,
          ),
          build: (pw.Context context) {
            // Total owed = existing due + current sale (after credit). Then subtract amount paid.
            double netCreditUsed = sale.creditUsed;
            if (sale.returnedAmount > 0 && sale.total > 0 && sale.creditUsed > 0) {
              final creditRestoreRatio =
                  (sale.returnedAmount / sale.total).clamp(0.0, 1.0);
              final creditRestored = sale.creditUsed * creditRestoreRatio;
              netCreditUsed =
                  (sale.creditUsed - creditRestored).clamp(0.0, sale.creditUsed);
            }
            final netSaleAmount =
                (sale.netTotal - netCreditUsed).clamp(0.0, double.infinity);
            final totalOwedBeforePayment = existingDueTotal + netSaleAmount;
            final totalDueBalance = (totalOwedBeforePayment - sale.amountPaid).clamp(0.0, double.infinity);
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Header
                pw.Text(
                  ReceiptBranding.storeName,
                  style: textStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Divider(thickness: 0.5, color: PdfColors.grey700),
                pw.SizedBox(height: 4),
                // Customer / Bill To — clean lines, no box
                if (seller != null) ...[
                  pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Bill To:',
                          style: textStyle(
                            fontSize: 5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          seller.name.toUpperCase(),
                          style: textStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                        ),
                        if (seller.phone != null &&
                            seller.phone!.isNotEmpty) ...[
                          pw.SizedBox(height: 1),
                          pw.Text(
                            'Phone: ${seller.phone!}',
                            style: textStyle(fontSize: 6),
                          ),
                        ],
                        if (seller.location != null &&
                            seller.location!.isNotEmpty) ...[
                          pw.SizedBox(height: 1),
                          pw.Text(
                            'Address: ${seller.location!}',
                            style: textStyle(fontSize: 6),
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey600),
                  pw.SizedBox(height: 4),
                ],
                // Items table header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      flex: 1,
                      child: pw.Text(
                        'No.',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Text(
                        'Item',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                    pw.Expanded(
                      flex: 1,
                      child: pw.Text(
                        'Qty',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'Price',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Text(
                        'Amount',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
                pw.Divider(thickness: 0.5, color: PdfColors.grey700),
                pw.SizedBox(height: 2),
                ...printableItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  final itemNumber = (index + 1).toString().padLeft(2, '0');
                  return pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            flex: 1,
                            child: pw.Text(
                              itemNumber,
                              style: textStyle(fontSize: 6),
                              textAlign: pw.TextAlign.left,
                            ),
                          ),
                          pw.Expanded(
                            flex: 4,
                            child: _productNameWidget(
                              productNamesMap: productNamesMap,
                              productNamesMapEn: productNamesMapEn,
                              item: item,
                              productNameImageBytes: productNameImageBytes,
                              textStyle: textStyle(fontSize: 6),
                            ),
                          ),
                          pw.Expanded(
                            flex: 1,
                            child: pw.Text(
                              item.quantity.toStringAsFixed(
                                  item.remainingQuantity % 1 == 0 ? 0 : 2),
                              style: textStyle(fontSize: 6),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              formatter.format(item.price),
                              style: textStyle(fontSize: 6),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              formatter.format(item.remainingSubtotal),
                              style: textStyle(fontSize: 6),
                              textAlign: pw.TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                    ],
                  );
                }).toList(),
                pw.Divider(thickness: 0.5, color: PdfColors.grey600),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total Items: ${printableItems.length}',
                      style: textStyle(
                          fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'Total Qty: ${printableItems.fold<double>(0, (sum, item) => sum + item.remainingQuantity).toStringAsFixed(printableItems.any((item) => item.remainingQuantity % 1 != 0) ? 2 : 0)}',
                      style: textStyle(
                          fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.5, color: PdfColors.grey700),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Sale Amount:',
                      style: textStyle(
                          fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      formatter.format(sale.total),
                      style: textStyle(
                          fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                if (existingDueTotal > 0.01) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Existing Due:',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        formatter.format(existingDueTotal),
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                if (sale.creditUsed > 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Credit Applied:',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        formatter.format(sale.creditUsed),
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                if (sale.recoveryBalance > 0) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Applied to Dues:',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        formatter.format(sale.recoveryBalance),
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Previous Due:',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        formatter.format(existingDueTotal),
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Remaining Balance:',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        formatter.format((existingDueTotal - sale.recoveryBalance).clamp(0.0, double.infinity)),
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Amount Paid:',
                      style: textStyle(
                          fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      formatter.format(sale.amountPaid),
                      style: textStyle(
                          fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Change:',
                      style: textStyle(
                          fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      formatter.format(sale.change),
                      style: textStyle(
                          fontSize: 6, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
                // Due Balance = Existing Due + remaining from current sale (if not fully paid)
                if (totalDueBalance > 0.01) ...[
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Due Balance:',
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        formatter.format(totalDueBalance),
                        style: textStyle(
                            fontSize: 6, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 0.5, color: PdfColors.grey600),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Order ID: ${sale.id.substring(0, 8).toUpperCase()}',
                  style: textStyle(
                      fontSize: 7, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  dateFormatter.format(sale.createdAt),
                  style: textStyle(fontSize: 6),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Thank you for your business',
                  style: textStyle(
                      fontSize: 7, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 0.5, color: PdfColors.grey500),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          '03017826712',
                          style: textStyle(fontSize: 6),
                          textAlign: pw.TextAlign.center,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'M.Irfan',
                          style: textStyle(fontSize: 6),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          '03015384952',
                          style: textStyle(fontSize: 6),
                          textAlign: pw.TextAlign.center,
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'M.Usman',
                          style: textStyle(fontSize: 6),
                          textAlign: pw.TextAlign.center,
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Software Developed by:',
                  style: textStyle(fontSize: 6),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'HighApp Solution 0301-5384952',
                  style: textStyle(
                      fontSize: 6, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      debugPrint(
          'Receipt PDF generated successfully, size: ${pdfBytes.length} bytes');
      return pdfBytes;
    } catch (e, stackTrace) {
      debugPrint('Error generating receipt PDF: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Item name cell: use image for Urdu/non-ASCII so it displays; otherwise text.
  /// When image is missing and name is non-ASCII, show English fallback so PDF never shows squares.
  static pw.Widget _productNameWidget({
    required Map<String, String> productNamesMap,
    Map<String, String>? productNamesMapEn,
    required dynamic item,
    required Map<String, Uint8List?> productNameImageBytes,
    required pw.TextStyle textStyle,
  }) {
    final name = (productNamesMap[item.productId] ?? item.productName ?? '').trim();
    final imageBytes = productNameImageBytes[item.productId];
    if (imageBytes != null && imageBytes.isNotEmpty) {
      // FittedBox ensures the image fits within the Expanded(flex: 4) cell;
      // fixed width/height caused "childSize <= maxChildExtent" assertion.
      return pw.FittedBox(
        fit: pw.BoxFit.contain,
        child: pw.Image(pw.MemoryImage(imageBytes)),
      );
    }
    // Show English name when we have no image and name is Urdu/non-ASCII (avoids squares in PDF).
    final String displayName = name.isEmpty
        ? 'Item'
        : (containsNonAscii(name)
            ? (productNamesMapEn?[item.productId] ?? item.productName ?? 'Item').trim()
            : name);
    return pw.Text(
      displayName.isEmpty ? 'Item' : displayName,
      style: textStyle,
      maxLines: 2,
      textAlign: pw.TextAlign.left,
    );
  }

  static Future<Map<String, String>> _getProductNames(
      Sale sale, String languageCode) async {
    final Map<String, String> productNamesMap = {};
    for (var item in sale.items) {
      try {
        final product = await _productService.getProductById(item.productId);
        if (product != null) {
          final name = product.getName(languageCode) ??
              (languageCode == 'en'
                  ? product.name
                  : product.getName('en')) ??
              product.name;
          productNamesMap[item.productId] = name;
        } else {
          productNamesMap[item.productId] = item.productName;
        }
      } catch (e) {
        debugPrint('Error fetching product ${item.productId}: $e');
        productNamesMap[item.productId] = item.productName;
      }
    }
    return productNamesMap;
  }
}
