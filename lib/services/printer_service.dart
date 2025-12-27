import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sale.dart';
import '../models/seller.dart';

class PrinterService {
  static const String _printerIpKey = 'printer_ip';
  static const String _printerPortKey = 'printer_port';
  static const String _defaultPort = '9100';

  // Get printer IP from SharedPreferences
  Future<String?> getPrinterIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_printerIpKey);
    } catch (e) {
      debugPrint('Error getting printer IP: $e');
      return null;
    }
  }

  // Get printer port from SharedPreferences
  Future<String> getPrinterPort() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_printerPortKey) ?? _defaultPort;
    } catch (e) {
      debugPrint('Error getting printer port: $e');
      return _defaultPort;
    }
  }

  // Set printer IP in SharedPreferences
  Future<void> setPrinterIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_printerIpKey, ip);
      debugPrint('Printer IP saved: $ip');
    } catch (e) {
      debugPrint('Error saving printer IP: $e');
      rethrow;
    }
  }

  // Set printer port in SharedPreferences
  Future<void> setPrinterPort(String port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_printerPortKey, port);
      debugPrint('Printer port saved: $port');
    } catch (e) {
      debugPrint('Error saving printer port: $e');
      rethrow;
    }
  }

  // Print receipt to thermal printer
  Future<bool> printReceipt(Sale sale, double existingDueTotal, Seller? seller) async {
    try {
      final printerIp = await getPrinterIp();
      final printerPort = await getPrinterPort();

      if (printerIp == null || printerIp.isEmpty) {
        debugPrint('Printer IP not configured');
        return false;
      }

      // Generate ESC/POS commands for thermal printer
      final receiptData = _generateReceiptData(sale, existingDueTotal, seller);

      // Connect to printer and send data (only works on mobile/desktop, not web)
      if (kIsWeb) {
        debugPrint('Network printing not supported on web platform');
        return false;
      }

      // Connect to printer and send data
      final socket = await Socket.connect(printerIp, int.parse(printerPort));
      socket.add(receiptData);
      await socket.flush();
      await socket.close();

      debugPrint('Receipt printed successfully to $printerIp:$printerPort');
      return true;
    } catch (e) {
      debugPrint('Error printing receipt: $e');
      return false;
    }
  }

  // Generate ESC/POS receipt data
  Uint8List _generateReceiptData(Sale sale, double existingDueTotal, Seller? seller) {
    final List<int> commands = [];

    // Initialize printer
    commands.addAll([0x1B, 0x40]); // ESC @ - Initialize printer

    // Set alignment to center
    commands.addAll([0x1B, 0x61, 0x01]); // ESC a 1 - Center align

    // Set text size (double width and height)
    commands.addAll([0x1D, 0x21, 0x11]); // GS ! 11 - Double width and height

    // Print header
    _addText(commands, 'AR KARAYANA STORE\n');
    _addText(commands, '-------------------\n');

    // Reset text size
    commands.addAll([0x1D, 0x21, 0x00]); // GS ! 00 - Normal size

    // Set alignment to left
    commands.addAll([0x1B, 0x61, 0x00]); // ESC a 0 - Left align

    // Print date and time
    final dateTime = sale.createdAt;
    final dateStr = '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    _addText(commands, 'Date: $dateStr\n');
    _addText(commands, 'Bill No: ${sale.id.substring(0, 8)}\n');
    _addText(commands, '-------------------\n');

    // Print items
    for (var item in sale.items) {
      _addText(commands, '${item.productName}\n');
      _addText(commands, '  ${item.quantity} x ${item.price.toStringAsFixed(2)} = ${item.subtotal.toStringAsFixed(2)}\n');
    }

    _addText(commands, '-------------------\n');

    // Print totals
    _addText(commands, 'Subtotal: ${sale.total.toStringAsFixed(2)}\n');
    
    if (sale.creditUsed > 0) {
      _addText(commands, 'Credit Used: ${sale.creditUsed.toStringAsFixed(2)}\n');
    }
    
    if (sale.recoveryBalance > 0) {
      _addText(commands, 'Recovery: ${sale.recoveryBalance.toStringAsFixed(2)}\n');
    }

    _addText(commands, 'Paid: ${sale.amountPaid.toStringAsFixed(2)}\n');
    
    if (sale.change > 0) {
      _addText(commands, 'Change: ${sale.change.toStringAsFixed(2)}\n');
    }

    if (seller != null) {
      _addText(commands, '-------------------\n');
      _addText(commands, 'Seller: ${seller.name}\n');
      if (existingDueTotal > 0) {
        _addText(commands, 'Previous Due: ${existingDueTotal.toStringAsFixed(2)}\n');
      }
    }

    _addText(commands, '-------------------\n');
    _addText(commands, 'Thank You!\n');
    _addText(commands, 'Visit Again\n');

    // Feed paper and cut
    commands.addAll([0x0A, 0x0A, 0x0A]); // Line feeds
    commands.addAll([0x1D, 0x56, 0x41, 0x03]); // GS V A 3 - Cut paper

    return Uint8List.fromList(commands);
  }

  // Helper method to add text to commands list
  void _addText(List<int> commands, String text) {
    commands.addAll(text.codeUnits);
  }
}

