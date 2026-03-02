import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/seller.dart';

/// Generates a PDF listing sellers with their due amounts (e.g. for filtered list view and download).
class SellersListPdfService {
  static final NumberFormat _currency = NumberFormat.currency(symbol: 'Rs. ');
  static final DateFormat _dateFormat = DateFormat('MMM d, y • HH:mm');

  /// [sellers] and [dueAmounts] must be in the same order (dueAmounts[i] = total due for sellers[i]).
  static Future<Uint8List> generatePdf({
    required List<Seller> sellers,
    required List<double> dueAmounts,
    String? searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final pdf = pw.Document();
    final generatedAt = _dateFormat.format(DateTime.now());
    final dateRangeStr = (startDate != null && endDate != null)
        ? '${DateFormat('MMM d, y').format(startDate)} - ${DateFormat('MMM d, y').format(endDate)}'
        : null;

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          _cell('No.', bold: true),
          _cell('Name', bold: true),
          _cell('Code', bold: true),
          _cell('Phone', bold: true),
          _cell('Location', bold: true),
          _cell('Due', bold: true),
        ],
      ),
    ];

    for (int i = 0; i < sellers.length; i++) {
      final s = sellers[i];
      final due = i < dueAmounts.length ? dueAmounts[i] : 0.0;
      tableRows.add(
        pw.TableRow(
          decoration: i.isEven ? null : const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _cell('${i + 1}'),
            _cell(s.name),
            _cell(s.code ?? '-'),
            _cell(s.phone ?? '-'),
            _cell(s.location ?? '-'),
            _cell(_currency.format(due)),
          ],
        ),
      );
    }

    double totalDue = 0.0;
    for (final d in dueAmounts) {
      totalDue += d;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Sellers List',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Generated: $generatedAt',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
                if (searchQuery != null && searchQuery.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      'Filter: "$searchQuery"',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ),
                if (dateRangeStr != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      'Period: $dateRangeStr',
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                  ),
                pw.SizedBox(height: 8),
                pw.Divider(thickness: 1, color: PdfColors.grey400),
              ],
            ),
          ),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(0.8),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.8),
              4: const pw.FlexColumnWidth(2),
              5: const pw.FlexColumnWidth(1.5),
            },
            children: tableRows,
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'Total sellers: ${sellers.length}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 24),
              pw.Text(
                'Total due: ${_currency.format(totalDue)}',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        maxLines: 2,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }
}
