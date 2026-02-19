import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../models/seller.dart';
import 'seller_service.dart';

// Imports for mobile sharing
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

class CsvExportService {
  final SellerService _sellerService = SellerService();
  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');
  final NumberFormat _currencyFormatter = NumberFormat.currency(symbol: 'Rs. ');

  /// Export sellers to CSV file
  /// Returns true if export was successful, false otherwise
  Future<bool> exportSellersToCsv({
    required List<Seller> sellers,
    required BuildContext context,
    String? searchQuery,
  }) async {
    try {
      // Fetch due, reference from seller_history, and credit balance for each seller
      final List<Map<String, dynamic>> sellersWithDueAndCredit = [];
      
      for (final seller in sellers) {
        final (totalDue, refFromHistory) = await _sellerService.getTotalDueAndReferenceForSeller(seller.id);
        final creditBalance = await _sellerService.getCreditBalance(seller.id);
        
        sellersWithDueAndCredit.add({
          'seller': seller,
          'totalDue': totalDue,
          'reference': refFromHistory ?? seller.reference ?? '',
          'creditBalance': creditBalance,
        });
      }

      // Create CSV data
      final List<List<dynamic>> csvData = [];
      
      // Add header row - "Location, Reference, Due" as one column (e.g. JAHANIAN,DFS,500.00)
      csvData.add([
        'No.',
        'Seller Name',
        'Phone Number',
        'Location, Reference, Due',
        'Credit Balance (Rs.)',
        'Status',
        'Created Date',
      ]);

      // Add data rows and calculate totals
      double grandTotalDue = 0.0;
      double grandTotalCredit = 0.0;
      for (int i = 0; i < sellersWithDueAndCredit.length; i++) {
        final seller = sellersWithDueAndCredit[i]['seller'] as Seller;
        final totalDue = sellersWithDueAndCredit[i]['totalDue'] as double;
        final creditBalance = sellersWithDueAndCredit[i]['creditBalance'] as double;
        grandTotalDue += totalDue;
        grandTotalCredit += creditBalance;
        final ref = sellersWithDueAndCredit[i]['reference'] as String;
        final locationRefDue = '${seller.location ?? ''},$ref,${totalDue.toStringAsFixed(2)}';
        csvData.add([
          i + 1, // Serial number
          seller.name,
          seller.phone ?? 'N/A',
          locationRefDue,
          creditBalance.toStringAsFixed(2),
          seller.isActive ? 'Active' : 'Inactive',
          _dateFormatter.format(seller.createdAt),
        ]);
      }

      // Add total row at the end
      csvData.add([]); // Empty row for spacing
      csvData.add([
        'TOTAL',
        '',
        '',
        '',
        grandTotalDue.toStringAsFixed(2),
        grandTotalCredit.toStringAsFixed(2),
        '',
        '',
      ]);

      // Convert to CSV string with proper formatting
      const converter = ListToCsvConverter(
        fieldDelimiter: ',',
        textDelimiter: '"',
        eol: '\n',
      );
      // Add UTF-8 BOM for Excel compatibility (ensures proper column separation)
      final csvString = '\uFEFF${converter.convert(csvData)}';

      // Generate filename with timestamp
      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final filename = searchQuery != null && searchQuery.isNotEmpty
          ? 'sellers_export_${searchQuery.replaceAll(' ', '_')}_$timestamp.csv'
          : 'sellers_export_$timestamp.csv';

      // Export based on platform
      if (kIsWeb) {
        // Web: Download file
        await _downloadCsvWeb(csvString, filename);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sellers exported successfully: $filename'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return true;
      } else {
        // Mobile: Share directly using XFile.fromData
        try {
          final bytes = utf8.encode(csvString);
          final xFile = XFile.fromData(
            bytes,
            mimeType: 'text/csv',
            name: filename,
          );
          
          await Share.shareXFiles(
            [xFile],
            text: 'Sellers Export - $filename',
            subject: 'Sellers CSV Export',
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Sellers exported successfully'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return true;
        } catch (e) {
          debugPrint('Error sharing CSV file: $e');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error sharing file: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return false;
        }
      }
    } catch (e) {
      debugPrint('Error exporting sellers to CSV: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting sellers: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }

  /// Download CSV file on web
  Future<void> _downloadCsvWeb(String csvString, String filename) async {
    if (kIsWeb) {
      // For web, return the CSV string and filename
      // The actual download will be triggered in the UI using html package
      // This method is kept for consistency but the actual download happens in UI
      return;
    }
  }


  /// Get CSV string for sellers (useful for web download)
  Future<String> getSellersCsvString({
    required List<Seller> sellers,
    String? searchQuery,
  }) async {
    try {
      // Fetch due, reference from seller_history, and credit balance for each seller
      final List<Map<String, dynamic>> sellersWithDueAndCredit = [];
      
      for (final seller in sellers) {
        final (totalDue, refFromHistory) = await _sellerService.getTotalDueAndReferenceForSeller(seller.id);
        final creditBalance = await _sellerService.getCreditBalance(seller.id);
        
        sellersWithDueAndCredit.add({
          'seller': seller,
          'totalDue': totalDue,
          'reference': refFromHistory ?? seller.reference ?? '',
          'creditBalance': creditBalance,
        });
      }

      // Create CSV data
      final List<List<dynamic>> csvData = [];
      
      // Add header row - "Location, Reference, Due" as one column (e.g. JAHANIAN,DFS,500.00)
      csvData.add([
        'No.',
        'Seller Name',
        'Phone Number',
        'Location, Reference, Due',
        'Credit Balance (Rs.)',
        'Status',
        'Created Date',
      ]);

      // Add data rows and calculate totals
      double grandTotalDue = 0.0;
      double grandTotalCredit = 0.0;
      for (int i = 0; i < sellersWithDueAndCredit.length; i++) {
        final seller = sellersWithDueAndCredit[i]['seller'] as Seller;
        final totalDue = sellersWithDueAndCredit[i]['totalDue'] as double;
        final creditBalance = sellersWithDueAndCredit[i]['creditBalance'] as double;
        grandTotalDue += totalDue;
        grandTotalCredit += creditBalance;
        final ref = sellersWithDueAndCredit[i]['reference'] as String;
        final locationRefDue = '${seller.location ?? ''},$ref,${totalDue.toStringAsFixed(2)}';
        csvData.add([
          i + 1,
          seller.name,
          seller.phone ?? 'N/A',
          locationRefDue,
          creditBalance.toStringAsFixed(2),
          seller.isActive ? 'Active' : 'Inactive',
          _dateFormatter.format(seller.createdAt),
        ]);
      }

      // Add total row at the end
      csvData.add([]);
      csvData.add([
        'TOTAL',
        '',
        '',
        '',
        grandTotalDue.toStringAsFixed(2),
        grandTotalCredit.toStringAsFixed(2),
        '',
        '',
      ]);

      // Convert to CSV string with proper formatting
      const converter = ListToCsvConverter(
        fieldDelimiter: ',',
        textDelimiter: '"',
        eol: '\n',
      );
      // Add UTF-8 BOM for Excel compatibility (ensures proper column separation)
      return '\uFEFF${converter.convert(csvData)}';
    } catch (e) {
      debugPrint('Error generating CSV string: $e');
      rethrow;
    }
  }
}

