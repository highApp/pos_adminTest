import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sale.dart';
import '../models/seller.dart';
import '../models/product.dart';
import 'product_service.dart';

// Web-specific imports for JavaScript interop
// Note: Conditional imports don't work well for dart:js on mobile
// All js.* usage is guarded with kIsWeb checks, so this code won't execute on mobile
import '../utils/js_stub.dart' as js;

// Mobile-specific imports for native Bluetooth
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as bt;
import 'package:permission_handler/permission_handler.dart';

enum PrinterConnectionType {
  wifi,
  bluetooth,
  usb,
}

class PrinterService {
  static const String _printerIpKey = 'printer_ip';
  static const String _printerPortKey = 'printer_port';
  static const String _connectionTypeKey = 'printer_connection_type';
  static const String _bluetoothDeviceIdKey = 'bluetooth_device_id';
  static const String _bluetoothDeviceNameKey = 'bluetooth_device_name';
  static const String _usbDeviceIdKey = 'usb_device_id';
  static const String _usbDeviceNameKey = 'usb_device_name';
  static const String _receiptLanguageKey = 'receipt_language';
  static const String _defaultPort = '9100';
  static const Duration _connectionTimeout = Duration(seconds: 5);
  
  // ESC/POS Command Constants for SpeedX SP-90A
  static const int esc = 0x1B;
  static const int gs = 0x1D;
  static const int lf = 0x0A;
  
  // Native Bluetooth printer instance (for mobile)
  bt.BlueThermalPrinter? _bluetoothPrinter;

  // Helper method to safely check Bluetooth connection status
  Future<bool> _isBluetoothConnected() async {
    try {
      if (_bluetoothPrinter == null) return false;
      final connected = await _bluetoothPrinter!.isConnected;
      // isConnected returns Future<bool?>, so after await it's bool?
      return connected ?? false;
    } catch (e) {
      debugPrint('Error checking Bluetooth connection: $e');
      return false;
    }
  }

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

  // Get connection type
  Future<PrinterConnectionType> getConnectionType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final typeStr = prefs.getString(_connectionTypeKey) ?? 'wifi';
      switch (typeStr) {
        case 'bluetooth':
          return PrinterConnectionType.bluetooth;
        case 'usb':
          return PrinterConnectionType.usb;
        default:
          return PrinterConnectionType.wifi;
      }
    } catch (e) {
      debugPrint('Error getting connection type: $e');
      return PrinterConnectionType.wifi;
    }
  }

  // Set connection type
  Future<void> setConnectionType(PrinterConnectionType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String typeStr;
      switch (type) {
        case PrinterConnectionType.bluetooth:
          typeStr = 'bluetooth';
          break;
        case PrinterConnectionType.usb:
          typeStr = 'usb';
          break;
        default:
          typeStr = 'wifi';
      }
      await prefs.setString(_connectionTypeKey, typeStr);
      debugPrint('Connection type saved: $type');
    } catch (e) {
      debugPrint('Error saving connection type: $e');
      rethrow;
    }
  }

  // Get Bluetooth device ID
  Future<String?> getBluetoothDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_bluetoothDeviceIdKey);
    } catch (e) {
      debugPrint('Error getting Bluetooth device ID: $e');
      return null;
    }
  }

  // Set Bluetooth device ID and name
  Future<void> setBluetoothDevice(String deviceId, String deviceName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_bluetoothDeviceIdKey, deviceId);
      await prefs.setString(_bluetoothDeviceNameKey, deviceName);
      debugPrint('Bluetooth device saved: $deviceName ($deviceId)');
    } catch (e) {
      debugPrint('Error saving Bluetooth device: $e');
      rethrow;
    }
  }

  // Get Bluetooth device name
  Future<String?> getBluetoothDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_bluetoothDeviceNameKey);
    } catch (e) {
      debugPrint('Error getting Bluetooth device name: $e');
      return null;
    }
  }

  // Get USB device ID
  Future<String?> getUsbDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_usbDeviceIdKey);
    } catch (e) {
      debugPrint('Error getting USB device ID: $e');
      return null;
    }
  }

  // Get USB device name
  Future<String?> getUsbDeviceName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_usbDeviceNameKey);
    } catch (e) {
      debugPrint('Error getting USB device name: $e');
      return null;
    }
  }

  // Set USB device ID and name
  Future<void> setUsbDevice(String deviceId, String deviceName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_usbDeviceIdKey, deviceId);
      await prefs.setString(_usbDeviceNameKey, deviceName);
      debugPrint('USB device saved: $deviceName ($deviceId)');
    } catch (e) {
      debugPrint('Error saving USB device: $e');
      rethrow;
    }
  }

  // Get receipt language preference
  Future<String> getReceiptLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_receiptLanguageKey) ?? 'en';
    } catch (e) {
      debugPrint('Error getting receipt language: $e');
      return 'en';
    }
  }

  // Set receipt language preference
  Future<void> setReceiptLanguage(String languageCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_receiptLanguageKey, languageCode);
      debugPrint('Receipt language saved: $languageCode');
    } catch (e) {
      debugPrint('Error saving receipt language: $e');
      rethrow;
    }
  }

  // Reset all printer settings
  Future<void> resetPrinterSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_printerIpKey);
      await prefs.remove(_printerPortKey);
      await prefs.remove(_connectionTypeKey);
      await prefs.remove(_bluetoothDeviceIdKey);
      await prefs.remove(_bluetoothDeviceNameKey);
      await prefs.remove(_usbDeviceIdKey);
      await prefs.remove(_usbDeviceNameKey);
      debugPrint('All printer settings have been reset');
    } catch (e) {
      debugPrint('Error resetting printer settings: $e');
      rethrow;
    }
  }

  // Request Bluetooth device (web and mobile)
  Future<Map<String, dynamic>?> requestBluetoothDevice() async {
    if (kIsWeb) {
      // Web: Use Web Bluetooth API

    try {
      // Check if Web Bluetooth is available by calling the function
      final isAvailableResult = js.context.callMethod('isBluetoothAvailable', []);
      final isAvailable = isAvailableResult is bool ? isAvailableResult : false;
      
      if (!isAvailable) {
        throw Exception('Web Bluetooth API is not supported in this browser. Please use Chrome, Edge, or Opera.');
      }

      // Request device - use callback-based approach to avoid promise conversion issues
      final completer = Completer<Map<String, dynamic>?>();
      
      // Create callback - now receives two separate string parameters
      final onSuccess = js.allowInterop((dynamic deviceIdParam, dynamic deviceNameParam) {
        debugPrint('Device selection callback - success');
        debugPrint('Received deviceIdParam: $deviceIdParam (${deviceIdParam.runtimeType})');
        debugPrint('Received deviceNameParam: $deviceNameParam (${deviceNameParam.runtimeType})');
        try {
          // Handle null/undefined for cancellation
          if (deviceIdParam == null || deviceNameParam == null) {
            debugPrint('User cancelled device selection (null parameters)');
            completer.complete(null);
            return;
          }
          
          // Convert to strings
          final deviceId = deviceIdParam.toString();
          final deviceName = deviceNameParam.toString();
          
          debugPrint('Converted to strings: id=$deviceId, name=$deviceName');
          
          if (deviceId.isEmpty || deviceName.isEmpty) {
            debugPrint('Device info incomplete: id=$deviceId, name=$deviceName');
            completer.complete(null);
            return;
          }
          
          debugPrint('Bluetooth device selected: $deviceName ($deviceId)');
          
          // Save device info
          setBluetoothDevice(deviceId, deviceName).then((_) {
            return setConnectionType(PrinterConnectionType.bluetooth);
          }).then((_) {
            debugPrint('Device saved successfully: $deviceName ($deviceId)');
            completer.complete({
              'id': deviceId,
              'name': deviceName,
            });
          }).catchError((e) {
            debugPrint('Error saving device: $e');
            // Complete anyway with device info
            completer.complete({
              'id': deviceId,
              'name': deviceName,
            });
          });
        } catch (e, stackTrace) {
          debugPrint('Error processing device result: $e');
          debugPrint('Stack trace: $stackTrace');
          completer.completeError(e);
        }
      });
      
      final onError = js.allowInterop((dynamic error) {
        debugPrint('Device selection callback - error: $error');
        completer.completeError(Exception(error.toString()));
      });
      
      // Call the callback-based function
      try {
        // Try to access the function - use different methods
        dynamic func;
        
        // Method 1: Direct property access
        try {
          func = js.context['requestBluetoothDeviceWithCallback'];
          debugPrint('Method 1: Direct access result: ${func != null}');
        } catch (e) {
          debugPrint('Method 1 failed: $e');
        }
        
        // Method 2: Try via callMethod (this will fail if function doesn't exist, but we'll catch it)
        if (func == null) {
          try {
            // Check if it exists by trying to get it
            final hasFunc = js.context.hasProperty('requestBluetoothDeviceWithCallback');
            debugPrint('Function exists check: $hasFunc');
            if (hasFunc) {
              func = js.context['requestBluetoothDeviceWithCallback'];
            }
          } catch (e) {
            debugPrint('Method 2 failed: $e');
          }
        }
        
        if (func == null) {
          throw Exception('requestBluetoothDeviceWithCallback not found. Please:\n1. Refresh the page (hard refresh: Ctrl+Shift+R or Cmd+Shift+R)\n2. Check browser console for script loading errors\n3. Verify bluetooth_printer.js is accessible at http://localhost:56439/bluetooth_printer.js');
        }
        
        debugPrint('Found function, calling it...');
        
        // Call the function
        if (func is js.JsFunction) {
          func.apply([onSuccess, onError], thisArg: js.context);
        } else {
          // Fallback: use callMethod
          js.context.callMethod('requestBluetoothDeviceWithCallback', [onSuccess, onError]);
        }
        
        debugPrint('Function called, waiting for callback...');
        
        // Wait for the result with a timeout
        return await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            debugPrint('Timeout waiting for Bluetooth device selection');
            return null;
          },
        );
      } catch (e) {
        debugPrint('Error calling requestBluetoothDeviceWithCallback: $e');
        rethrow;
      }
    } catch (e) {
      debugPrint('Error requesting Bluetooth device: $e');
      rethrow;
    }
    } else {
      // Mobile: Use native Bluetooth (blue_thermal_printer)
      try {
        // Request Bluetooth permissions
        final bluetoothStatus = await Permission.bluetooth.request();
        final locationStatus = await Permission.location.request();
        
        if (!bluetoothStatus.isGranted) {
          throw Exception('Bluetooth permission denied. Please grant Bluetooth permission in app settings.');
        }
        
        if (!locationStatus.isGranted) {
          debugPrint('Location permission not granted - some devices may require this for Bluetooth scanning');
        }
        
        // Initialize Bluetooth printer
        _bluetoothPrinter = bt.BlueThermalPrinter.instance;
        
        // Get paired devices
        List<bt.BluetoothDevice> devices = await _bluetoothPrinter!.getBondedDevices();
        
        if (devices.isEmpty) {
          throw Exception('No Bluetooth printers found. Please pair your printer in Android Bluetooth settings first.');
        }
        
        // Find SpeedX printer or use first available
        bt.BluetoothDevice? selectedDevice;
        for (var device in devices) {
          if (device.name?.toLowerCase().contains('bluetooth') == true || 
              device.name?.toLowerCase().contains('speedx') == true ||
              device.name?.toLowerCase().contains('sp-90a') == true) {
            selectedDevice = device;
            break;
          }
        }
        
        // If no SpeedX found, use first printer
        selectedDevice ??= devices.first;
        
        final deviceId = selectedDevice.address ?? '';
        final deviceName = selectedDevice.name ?? 'Bluetooth Printer';
        
        debugPrint('Bluetooth device selected: $deviceName ($deviceId)');
        
        // Save device info
        await setBluetoothDevice(deviceId, deviceName);
        await setConnectionType(PrinterConnectionType.bluetooth);
        
        return {
          'id': deviceId,
          'name': deviceName,
        };
      } catch (e) {
        debugPrint('Error requesting Bluetooth device (mobile): $e');
        rethrow;
      }
    }
  }

  // Connect to Bluetooth device (web and mobile)
  Future<bool> connectBluetoothDevice() async {
    if (kIsWeb) {
      // Web: Use Web Bluetooth API
      try {
      final deviceId = await getBluetoothDeviceId();
      if (deviceId == null) {
        throw Exception('No Bluetooth device selected');
      }

      // Use callback-based approach for connection too
      final completer = Completer<bool>();
      
      final onSuccess = js.allowInterop((dynamic result) {
        debugPrint('Bluetooth connection callback - success: $result');
        completer.complete(true);
      });
      
      final onError = js.allowInterop((dynamic error) {
        debugPrint('Bluetooth connection callback - error: $error');
        completer.completeError(Exception(error.toString()));
      });
      
      // Call the callback-based function
      final func = js.context['connectBluetoothDevice'];
      if (func == null || func is! js.JsFunction) {
        throw Exception('connectBluetoothDevice function not found');
      }
      
      func.apply([deviceId, onSuccess, onError], thisArg: js.context);
      
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Timeout connecting to Bluetooth device');
          return false;
        },
      );
    } catch (e) {
      debugPrint('Error connecting to Bluetooth device: $e');
      final errorMsg = e.toString();
      // Check if it's the unsupported device error
      if (errorMsg.contains('Unsupported device') || 
          errorMsg.contains('classic Bluetooth') ||
          errorMsg.contains('SPP') ||
          errorMsg.contains('No Services found')) {
        debugPrint('Device uses classic Bluetooth (SPP) which is not supported by Web Bluetooth API');
        debugPrint('Recommendation: Use WiFi connection instead, or use a BLE-compatible printer');
      }
      return false;
    }
    } else {
      // Mobile: Use native Bluetooth
      try {
        final deviceId = await getBluetoothDeviceId();
        if (deviceId == null) {
          throw Exception('No Bluetooth device selected');
        }
        
        // Initialize Bluetooth printer if not already done
        _bluetoothPrinter ??= bt.BlueThermalPrinter.instance;
        
        // Check if already connected to the same device
        if (await _isBluetoothConnected()) {
          debugPrint('Bluetooth printer already connected');
          return true;
        }
        
        // Get paired devices and find the one with matching address
        List<bt.BluetoothDevice> devices = await _bluetoothPrinter!.getBondedDevices();
        bt.BluetoothDevice? device;
        
        for (var d in devices) {
          if (d.address == deviceId) {
            device = d;
            break;
          }
        }
        
        if (device == null) {
          throw Exception('Bluetooth device not found. Please pair the printer again.');
        }
        
        // Disconnect if connected to a different device
        try {
          if (await _isBluetoothConnected()) {
            await _bluetoothPrinter!.disconnect();
            // Wait a bit before reconnecting
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          debugPrint('Error disconnecting previous connection: $e');
        }
        
        // Connect to printer
        await _bluetoothPrinter!.connect(device);
        
        // Wait a bit to ensure connection is stable
        await Future.delayed(const Duration(milliseconds: 300));
        
        debugPrint('Connected to Bluetooth printer: ${device.name}');
        return true;
      } catch (e) {
        debugPrint('Error connecting to Bluetooth device (mobile): $e');
        // Reset printer instance on error to allow retry
        try {
          if (_bluetoothPrinter != null) {
            await _bluetoothPrinter!.disconnect();
          }
        } catch (disconnectError) {
          debugPrint('Error during disconnect: $disconnectError');
        }
        _bluetoothPrinter = null;
        return false;
      }
    }
  }

  // Send data via Bluetooth (web and mobile)
  Future<bool> sendBluetoothData(Uint8List data) async {
    if (kIsWeb) {
      // Web: Use Web Bluetooth API

    try {
      // Convert Uint8List to JavaScript array
      final jsArray = js.JsArray<dynamic>.from(data.toList());
      
      // Use callback-based approach
      final completer = Completer<bool>();
      
      final onSuccess = js.allowInterop((dynamic result) {
        debugPrint('Data sent successfully');
        completer.complete(true);
      });
      
      final onError = js.allowInterop((dynamic error) {
        debugPrint('Error sending data: $error');
        completer.completeError(Exception(error.toString()));
      });
      
      // Call the callback-based function
      final func = js.context['sendBluetoothData'];
      if (func == null || func is! js.JsFunction) {
        throw Exception('sendBluetoothData function not found');
      }
      
      func.apply([jsArray, onSuccess, onError], thisArg: js.context);
      
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Timeout sending data to Bluetooth printer');
          return false;
        },
      );
      
      debugPrint('Data sent to Bluetooth printer: ${data.length} bytes');
      return result;
    } catch (e) {
      debugPrint('Error sending data to Bluetooth printer: $e');
      return false;
    }
    } else {
      // Mobile: Use native Bluetooth
      try {
        if (_bluetoothPrinter == null) {
          throw Exception('Bluetooth not connected. Please connect first.');
        }
        
        // Send data using the Bluetooth printer
        await _bluetoothPrinter!.writeBytes(data);
        
        debugPrint('Data sent to Bluetooth printer (mobile): ${data.length} bytes');
        return true;
      } catch (e) {
        debugPrint('Error sending data to Bluetooth printer (mobile): $e');
        return false;
      }
    }
  }

  // Request USB device (web only)
  Future<Map<String, dynamic>?> requestUsbDevice() async {
    if (!kIsWeb) {
      debugPrint('USB device request only available on web');
      return null;
    }

    try {
      // Check if Web USB is available
      final isAvailableResult = js.context.callMethod('isUsbAvailable', []);
      final isAvailable = isAvailableResult is bool ? isAvailableResult : false;
      
      if (!isAvailable) {
        throw Exception('Web USB API is not supported in this browser. Please use Chrome, Edge, or Opera.');
      }

      // Request device - use callback-based approach
      final completer = Completer<Map<String, dynamic>?>();
      
      final onSuccess = js.allowInterop((dynamic deviceIdParam, dynamic deviceNameParam) {
        debugPrint('Received USB deviceIdParam: $deviceIdParam (type: ${deviceIdParam.runtimeType})');
        debugPrint('Received USB deviceNameParam: $deviceNameParam (type: ${deviceNameParam.runtimeType})');

        try {
          if (deviceIdParam == null || deviceNameParam == null) {
            debugPrint('User cancelled device selection or device info incomplete');
            completer.complete(null);
            return;
          }

          final deviceId = deviceIdParam.toString();
          final deviceName = deviceNameParam.toString();
          
          debugPrint('USB device selected: $deviceName ($deviceId)');
          
          // Save device info
          setUsbDevice(deviceId, deviceName).then((_) {
            return setConnectionType(PrinterConnectionType.usb);
          }).then((_) {
            debugPrint('USB device saved successfully: $deviceName ($deviceId)');
            completer.complete({
              'id': deviceId,
              'name': deviceName,
            });
          }).catchError((e) {
            debugPrint('Error saving USB device: $e');
            // Complete anyway with device info
            completer.complete({
              'id': deviceId,
              'name': deviceName,
            });
          });
        } catch (e) {
          debugPrint('Error processing USB device result in Dart: $e');
          completer.completeError(e);
        }
      });
      
      final onError = js.allowInterop((dynamic error) {
        debugPrint('USB device selection callback - error: $error');
        completer.completeError(Exception(error.toString()));
      });
      
      // Call the callback-based function
      try {
        js.context.callMethod('requestUsbDeviceWithCallback', [onSuccess, onError]);
        
        // Wait for the result
        return await completer.future;
      } catch (e) {
        debugPrint('Error calling requestUsbDeviceWithCallback: $e');
        rethrow;
      }
    } catch (e) {
      debugPrint('Error requesting USB device: $e');
      rethrow;
    }
  }

  // Connect to USB device (web only)
  Future<bool> connectUsbDevice() async {
    if (!kIsWeb) {
      return false;
    }

    try {
      final deviceId = await getUsbDeviceId();
      if (deviceId == null) {
        throw Exception('No USB device selected');
      }

      // Use callback-based approach
      final completer = Completer<bool>();
      
      final onSuccess = js.allowInterop((dynamic result) {
        debugPrint('USB connection callback - success: $result');
        completer.complete(true);
      });
      
      final onError = js.allowInterop((dynamic error) {
        debugPrint('USB connection callback - error: $error');
        completer.completeError(Exception(error.toString()));
      });
      
      // Call the callback-based function
      final func = js.context['connectUsbDevice'];
      if (func == null || func is! js.JsFunction) {
        throw Exception('connectUsbDevice function not found');
      }
      
      func.apply([deviceId, onSuccess, onError], thisArg: js.context);
      
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Timeout connecting to USB device');
          return false;
        },
      );
    } catch (e) {
      debugPrint('Error connecting to USB device: $e');
      return false;
    }
  }

  // Send data via USB (web only)
  Future<bool> sendUsbData(Uint8List data) async {
    if (!kIsWeb) {
      return false;
    }

    try {
      // Convert Uint8List to JavaScript array
      final jsArray = js.JsArray<dynamic>.from(data.toList());
      
      // Use callback-based approach
      final completer = Completer<bool>();
      
      final onSuccess = js.allowInterop((dynamic result) {
        debugPrint('USB data sent successfully');
        completer.complete(true);
      });
      
      final onError = js.allowInterop((dynamic error) {
        debugPrint('Error sending USB data: $error');
        completer.completeError(Exception(error.toString()));
      });
      
      // Call the callback-based function
      final func = js.context['sendUsbData'];
      if (func == null || func is! js.JsFunction) {
        throw Exception('sendUsbData function not found');
      }
      
      func.apply([jsArray, onSuccess, onError], thisArg: js.context);
      
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('Timeout sending data to USB printer');
          return false;
        },
      );
      
      debugPrint('Data sent to USB printer: ${data.length} bytes');
      return result;
    } catch (e) {
      debugPrint('Error sending data to USB printer: $e');
      return false;
    }
  }

  // Check if USB is available (web only)
  bool isUsbAvailable() {
    if (!kIsWeb) {
      return false;
    }
    try {
      if (js.context.hasProperty('isUsbAvailable')) {
        final result = js.context.callMethod('isUsbAvailable', []);
        if (result is bool) {
          return result;
        }
      }
      return false;
    } catch (e) {
      debugPrint('Error checking USB availability: $e');
      return false;
    }
  }

  // Check if Bluetooth is available (web and mobile)
  bool isBluetoothAvailable() {
    if (kIsWeb) {
      // Web: Check Web Bluetooth API
    try {
      // Check if the JavaScript function exists and call it
      if (js.context.hasProperty('isBluetoothAvailable')) {
        final result = js.context.callMethod('isBluetoothAvailable', []);
        // The result should be a boolean
        if (result is bool) {
          debugPrint('Bluetooth availability check: $result');
          return result;
        } else {
          debugPrint('isBluetoothAvailable returned non-boolean: $result');
          // If navigator.bluetooth exists, assume it's available
          return true;
        }
      } else {
        debugPrint('isBluetoothAvailable JavaScript function not found - script may not be loaded');
        // Return true anyway to allow the user to try (will show error if not available)
        return true;
      }
    } catch (e) {
      debugPrint('Error checking Bluetooth availability: $e');
      // Return true to allow user to try - will show proper error when attempting to connect
      return true;
    }
    } else {
      // Mobile: Native Bluetooth is always available (with permissions)
      return true;
    }
  }

  // Test printer connection
  Future<bool> testConnection() async {
    try {
      if (kIsWeb) {
        // Web: Test connection based on type
        final connectionType = await getConnectionType();
        
        if (connectionType == PrinterConnectionType.bluetooth) {
          final deviceId = await getBluetoothDeviceId();
          if (deviceId == null) {
            debugPrint('Bluetooth device not configured');
            return false;
          }

          // Connect to Bluetooth device
          final connected = await connectBluetoothDevice();
          if (!connected) {
            return false;
          }

          // Send a simple test command
          final testCommands = Uint8List.fromList([
            esc, 0x40, // Initialize printer
            esc, 0x61, 0x01, // Center align
            ...'SpeedX SP-90A Test\n'.codeUnits,
            esc, 0x61, 0x00, // Left align
            ...'Connection OK!\n'.codeUnits,
            lf, lf,
            gs, 0x56, 0x41, 0x03, // Cut paper
          ]);

          final success = await sendBluetoothData(testCommands);
          if (success) {
            debugPrint('Bluetooth printer connection test successful');
          }
          return success;
        } else if (connectionType == PrinterConnectionType.usb) {
          final deviceId = await getUsbDeviceId();
          if (deviceId == null) {
            debugPrint('USB device not configured');
            return false;
          }

          // Connect to USB device
          final connected = await connectUsbDevice();
          if (!connected) {
            return false;
          }

          // Send a simple test command
          final testCommands = Uint8List.fromList([
            esc, 0x40, // Initialize printer
            esc, 0x61, 0x01, // Center align
            ...'SpeedX SP-90A Test\n'.codeUnits,
            esc, 0x61, 0x00, // Left align
            ...'Connection OK!\n'.codeUnits,
            lf, lf,
            gs, 0x56, 0x41, 0x03, // Cut paper
          ]);

          final success = await sendUsbData(testCommands);
          if (success) {
            debugPrint('USB printer connection test successful');
          }
          return success;
        } else {
          debugPrint('WiFi printing not supported on web platform');
          return false;
        }
      } else {
        // Mobile/Desktop: Test connection based on type
        final connectionType = await getConnectionType();
        
        if (connectionType == PrinterConnectionType.bluetooth) {
          final deviceId = await getBluetoothDeviceId();
          if (deviceId == null) {
            debugPrint('Bluetooth device not configured');
            return false;
          }

          // Connect to Bluetooth device
          final connected = await connectBluetoothDevice();
          if (!connected) {
            return false;
          }

          // Send a simple test command
          final testCommands = Uint8List.fromList([
            esc, 0x40, // Initialize printer
            esc, 0x61, 0x01, // Center align
            ...'SpeedX SP-90A Test\n'.codeUnits,
            esc, 0x61, 0x00, // Left align
            ...'Connection OK!\n'.codeUnits,
            lf, lf,
            gs, 0x56, 0x41, 0x03, // Cut paper
          ]);

          final success = await sendBluetoothData(testCommands);
          if (success) {
            debugPrint('Bluetooth printer connection test successful');
          }
          return success;
        } else {
          // WiFi connection
      final printerIp = await getPrinterIp();
      final printerPort = await getPrinterPort();

      if (printerIp == null || printerIp.isEmpty) {
        debugPrint('Printer IP not configured');
        return false;
      }

          // Try to connect with timeout
          final socket = await Socket.connect(printerIp, int.parse(printerPort))
              .timeout(_connectionTimeout);
          
          // Send a simple test command
          final testCommands = <int>[
            esc, 0x40, // Initialize printer
            esc, 0x61, 0x01, // Center align
            ...'SpeedX SP-90A Test\n'.codeUnits,
            esc, 0x61, 0x00, // Left align
            ...'Connection OK!\n'.codeUnits,
            lf, lf,
            gs, 0x56, 0x41, 0x03, // Cut paper
          ];
          
          socket.add(Uint8List.fromList(testCommands));
          await socket.flush();
          await socket.close();

          debugPrint('Printer connection test successful');
          return true;
        }
      }
    } catch (e) {
      debugPrint('Printer connection test failed: $e');
      return false;
    }
  }

  // Print receipt to thermal printer
  Future<bool> printReceipt(Sale sale, double existingDueTotal, Seller? seller, {String? languageCode}) async {
    try {
      // Get language preference if not provided
      final lang = languageCode ?? await getReceiptLanguage();
      
      // Generate ESC/POS commands for thermal printer
      final receiptData = await _generateReceiptData(sale, existingDueTotal, seller, languageCode: lang);

      if (kIsWeb) {
        // Web platform: Use Bluetooth or USB
        final connectionType = await getConnectionType();
        
        if (connectionType == PrinterConnectionType.bluetooth) {
          // Connect to Bluetooth device if not already connected
          final connected = await connectBluetoothDevice();
          if (!connected) {
            debugPrint('Failed to connect to Bluetooth device');
            return false;
          }

          // Send data via Bluetooth
          final success = await sendBluetoothData(receiptData);
          if (success) {
            debugPrint('Receipt printed successfully via Bluetooth');
          }
          return success;
        } else if (connectionType == PrinterConnectionType.usb) {
          // Connect to USB device if not already connected
          final connected = await connectUsbDevice();
          if (!connected) {
            debugPrint('Failed to connect to USB device');
            return false;
          }

          // Send data via USB
          final success = await sendUsbData(receiptData);
          if (success) {
            debugPrint('Receipt printed successfully via USB');
          }
          return success;
        } else {
          debugPrint('WiFi printing not supported on web platform. Please use Bluetooth or USB.');
          return false;
        }
      } else {
        // Mobile/Desktop platform: Use Bluetooth or WiFi/Network
        final connectionType = await getConnectionType();
        
        if (connectionType == PrinterConnectionType.bluetooth) {
          // Check if already connected, if not, connect
          bool isConnected = false;
          try {
            if (_bluetoothPrinter != null) {
              // Check if printer is already connected
              isConnected = await _isBluetoothConnected();
            }
          } catch (e) {
            debugPrint('Connection check failed, will reconnect: $e');
            isConnected = false;
          }
          
          // Connect only if not already connected
          if (!isConnected) {
            debugPrint('Bluetooth not connected, connecting...');
          final connected = await connectBluetoothDevice();
          if (!connected) {
            debugPrint('Failed to connect to Bluetooth device');
            return false;
            }
          } else {
            debugPrint('Bluetooth already connected, reusing connection');
          }

          // Send data via Bluetooth
          final success = await sendBluetoothData(receiptData);
          if (success) {
            debugPrint('Receipt printed successfully via Bluetooth');
          } else {
            // If send failed, try reconnecting and sending again
            debugPrint('First send attempt failed, trying to reconnect...');
            try {
              if (_bluetoothPrinter != null && await _isBluetoothConnected()) {
                await _bluetoothPrinter!.disconnect();
              }
            } catch (e) {
              debugPrint('Error disconnecting: $e');
            }
            
            final reconnected = await connectBluetoothDevice();
            if (reconnected) {
              debugPrint('Reconnected, trying to send again...');
              final retrySuccess = await sendBluetoothData(receiptData);
              if (retrySuccess) {
                debugPrint('Receipt printed successfully via Bluetooth after reconnect');
                return true;
              }
            }
          }
          return success;
        } else {
          // WiFi connection
          final printerIp = await getPrinterIp();
          final printerPort = await getPrinterPort();

          if (printerIp == null || printerIp.isEmpty) {
            debugPrint('Printer IP not configured');
        return false;
      }

          // Connect to printer with timeout
          final socket = await Socket.connect(printerIp, int.parse(printerPort))
              .timeout(_connectionTimeout);
          
      socket.add(receiptData);
      await socket.flush();
      await socket.close();

      debugPrint('Receipt printed successfully to $printerIp:$printerPort');
      return true;
        }
      }
    } on SocketException catch (e) {
      debugPrint('Network error printing receipt: $e');
      return false;
    } on TimeoutException catch (e) {
      debugPrint('Connection timeout: $e');
      return false;
    } catch (e) {
      debugPrint('Error printing receipt: $e');
      return false;
    }
  }

  // Generate ESC/POS receipt data optimized for SpeedX SP-90A
  Future<Uint8List> _generateReceiptData(Sale sale, double existingDueTotal, Seller? seller, {String languageCode = 'en'}) async {
    final List<int> commands = [];
    
    // Fetch products to get language-specific names
    final productService = ProductService();
    final Map<String, String> productNamesMap = {};
    
    // Fetch all products for this sale
    for (var item in sale.items) {
      try {
        final product = await productService.getProductById(item.productId);
        if (product != null) {
          // Get name in selected language, fallback to English or displayName
          final name = product.getName(languageCode) ?? 
                      (languageCode == 'en' ? product.name : product.getName('en')) ?? 
                      product.name;
          productNamesMap[item.productId] = name;
        } else {
          // Fallback to stored productName if product not found
          productNamesMap[item.productId] = item.productName;
        }
      } catch (e) {
        debugPrint('Error fetching product ${item.productId}: $e');
        // Fallback to stored productName
        productNamesMap[item.productId] = item.productName;
      }
    }

    // Initialize printer (ESC @)
    commands.addAll([esc, 0x40]);

    // Set character code table (UTF-8 compatible)
    // SpeedX SP-90A supports multiple code pages, using Page0 (OEM437) as default
    commands.addAll([esc, 0x74, 0x00]); // ESC t 0 - Select character code table 0

    // Note: Print density is typically set via printer hardware settings
    // SpeedX SP-90A default is Level-2 as shown in self-test

    // Set alignment to center
    commands.addAll([esc, 0x61, 0x01]); // ESC a 1 - Center align

    // Set text size to normal (smaller than previous double size)
    commands.addAll([gs, 0x21, 0x00]); // GS ! 00 - Normal size
    
    // Enable condensed mode for smaller text
    commands.addAll([esc, 0x21, 0x01]); // ESC ! 1 - Condensed mode

    // Print header
    _addText(commands, 'AR\'S TRADERS\n');
    _addText(commands, '${_repeatChar('-', 32)}\n');

    // Set alignment to left
    commands.addAll([esc, 0x61, 0x00]); // ESC a 0 - Left align

    // Print date and time
    final dateTime = sale.createdAt;
    final dateStr = '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    _addText(commands, 'Date: $dateStr\n');
    _addText(commands, 'Bill No: ${sale.id.substring(0, 8)}\n');
    
    // Print seller info if available
    if (seller != null) {
      _addText(commands, 'Customer: ${seller.name}\n');
      if (seller.phone != null && seller.phone!.isNotEmpty) {
        _addText(commands, 'Phone: ${seller.phone}\n');
      }
    }
    
    _addText(commands, '${_repeatChar('-', 32)}\n');

    // Print items with better formatting
    int itemNumber = 1;
    for (var item in sale.items) {
      // Product name with item number, qty, price, and subtotal on one line
      // Use language-specific name if available, otherwise fallback to stored name
      final productName = productNamesMap[item.productId] ?? item.productName;
      // Format quantity: show decimals if needed (e.g., 0.100), otherwise whole number
      final qty = item.quantity % 1 == 0 
          ? item.quantity.toStringAsFixed(0) 
          : item.quantity.toStringAsFixed(3);
      final price = item.price.toStringAsFixed(2);
      final subtotal = item.subtotal.toStringAsFixed(2);
      final itemLine = '$itemNumber. $productName $qty*$price = $subtotal';
      _addText(commands, '$itemLine\n');
      itemNumber++;
    }

    _addText(commands, '${_repeatChar('-', 32)}\n');
    // Total items count
    _addText(commands, _formatLine('Total Items:', sale.items.length.toString()));
    _addText(commands, '${_repeatChar('-', 32)}\n');

    // Print totals with right alignment for amounts
    _addText(commands, _formatLine('Subtotal:', sale.total.toStringAsFixed(2)));
    
    if (sale.creditUsed > 0) {
      _addText(commands, _formatLine('Credit Used:', sale.creditUsed.toStringAsFixed(2)));
    }
    
    if (sale.recoveryBalance > 0) {
      _addText(commands, _formatLine('Recovery:', sale.recoveryBalance.toStringAsFixed(2)));
    }

    _addText(commands, _formatLine('Paid:', sale.amountPaid.toStringAsFixed(2)));
    
    if (sale.change > 0) {
      _addText(commands, _formatLine('Change:', sale.change.toStringAsFixed(2)));
    }

    if (seller != null && existingDueTotal > 0) {
      _addText(commands, '${_repeatChar('-', 32)}\n');
      _addText(commands, _formatLine('Previous Due:', existingDueTotal.toStringAsFixed(2)));
    }

    _addText(commands, '${_repeatChar('-', 32)}\n');
    
    // Center align for footer
    commands.addAll([esc, 0x61, 0x01]); // Center align
    _addText(commands, 'Thank You!\n');
    _addText(commands, 'Visit Again\n');
    // Developer info (condensed mode already enabled)
    _addText(commands, 'Software developed by HighApp Solution\n');
    _addText(commands, '+923015384952, +923234471436\n');
    commands.addAll([esc, 0x61, 0x00]); // Left align

    // Feed paper (multiple line feeds for better spacing)
    commands.addAll([lf, lf, lf]);

    // Cut paper (GS V A 3 - Full cut)
    // SpeedX SP-90A has cutter enabled, this will cut the paper
    commands.addAll([gs, 0x56, 0x41, 0x03]);

    // Optional: Beep (if enabled on printer)
    // commands.addAll([esc, 0x42, 0x01, 0x01]); // ESC B - Beep (1 time, 1 duration)

    return Uint8List.fromList(commands);
  }

  // Helper method to format a line with label and value (right-aligned value)
  String _formatLine(String label, String value) {
    const lineWidth = 32;
    final labelLength = label.length;
    final valueLength = value.length;
    final spaces = lineWidth - labelLength - valueLength;
    return '$label${_repeatChar(' ', spaces > 0 ? spaces : 1)}$value\n';
  }

  // Helper method to repeat a character
  String _repeatChar(String char, int count) {
    return char * count;
  }

  // Helper method to add text to commands list
  void _addText(List<int> commands, String text) {
    commands.addAll(text.codeUnits);
  }
}

