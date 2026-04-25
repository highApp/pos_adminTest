// Web Bluetooth API wrapper for SpeedX SP-90A thermal printer
// This file provides functions to connect and print via Bluetooth on web

// Bluetooth printer service UUIDs (Serial Port Profile - SPP)
const BLUETOOTH_SERVICE_UUID = '00001101-0000-1000-8000-00805f9b34fb'; // Standard Serial Port Profile
const BLUETOOTH_CHARACTERISTIC_UUID = '00001101-0000-1000-8000-00805f9b34fb';

let bluetoothDevice = null;
let bluetoothCharacteristic = null;

// Request Bluetooth device (user must select from available devices)
// Returns a Promise that resolves with device info
window.requestBluetoothDevice = function() {
  return new Promise((resolve, reject) => {
    try {
      if (!navigator.bluetooth) {
        reject(new Error('Web Bluetooth API is not supported in this browser. Please use Chrome, Edge, or Opera.'));
        return;
      }

      // Request device with Serial Port Profile service
      // SpeedX SP-90A default name: "BlueTooth Printer"
      // Bluetooth Pin: 1234 (handled automatically by browser)
      // Bluetooth Mac: 66:32:1D:10:AB:83
      navigator.bluetooth.requestDevice({
        filters: [
          { services: [BLUETOOTH_SERVICE_UUID] },
          { name: 'BlueTooth Printer' }, // Exact match for SpeedX SP-90A
          { namePrefix: 'BlueTooth' }, // Fallback for name variations
        ],
        optionalServices: [BLUETOOTH_SERVICE_UUID]
      })
      .then(device => {
        bluetoothDevice = device;
        console.log('Bluetooth device selected:', bluetoothDevice.name);
        
        // Listen for disconnection
        bluetoothDevice.addEventListener('gattserverdisconnected', () => {
          console.log('Bluetooth device disconnected');
          bluetoothDevice = null;
          bluetoothCharacteristic = null;
        });

        // Return a plain object that Dart can easily convert
        const result = {
          id: bluetoothDevice.id,
          name: bluetoothDevice.name,
          connected: false
        };
        console.log('Resolving with device:', result);
        resolve(result);
      })
      .catch(error => {
        console.error('Error requesting Bluetooth device:', error);
        // Handle user cancellation gracefully
        if (error.name === 'NotFoundError' || error.message.includes('cancelled')) {
          console.log('User cancelled device selection');
          resolve(null); // Resolve with null instead of rejecting
        } else {
          reject(error);
        }
      });
    } catch (error) {
      console.error('Error in requestBluetoothDevice:', error);
      reject(error);
    }
  });
};

// Alternative callback-based function for better Dart interop
window.requestBluetoothDeviceWithCallback = function(onSuccess, onError) {
  try {
    if (!navigator.bluetooth) {
      if (onError) onError('Web Bluetooth API is not supported in this browser. Please use Chrome, Edge, or Opera.');
      return;
    }

    // Request device - don't filter by service, just by name
    // This allows us to discover services after connection
    navigator.bluetooth.requestDevice({
      filters: [
        { name: 'BlueTooth Printer' },
        { namePrefix: 'BlueTooth' },
      ],
      // Request SPP service as optional - we'll discover it after connection
      optionalServices: [
        BLUETOOTH_SERVICE_UUID,
        '00001101-0000-1000-8000-00805f9b34fb', // Standard SPP UUID
      ]
    })
    .then(device => {
      bluetoothDevice = device;
      console.log('=== Bluetooth Device Selected ===');
      console.log('Device object:', device);
      console.log('Device type:', typeof device);
      console.log('Device constructor:', device.constructor.name);
      
      // Extract device properties - capture from the loop since they show up there
      let deviceId = '';
      let deviceName = '';
      
      // Log and capture properties from the loop
      console.log('All device properties:');
      for (let prop in device) {
        try {
          const value = device[prop];
          console.log(`  ${prop}: ${value} (${typeof value})`);
          
          // Capture id and name when we see them
          if (prop === 'id' && value) {
            deviceId = String(value);
          }
          if (prop === 'name' && value) {
            deviceName = String(value);
          }
        } catch (e) {
          console.log(`  ${prop}: [error accessing]`);
        }
      }
      
      // Also try direct access
      if (!deviceId) {
        try {
          deviceId = String(device.id || '');
          console.log('Direct access device.id:', deviceId);
        } catch (e) {
          console.log('Error accessing device.id:', e);
        }
      }
      
      if (!deviceName) {
        try {
          deviceName = String(device.name || '');
          console.log('Direct access device.name:', deviceName);
        } catch (e) {
          console.log('Error accessing device.name:', e);
        }
      }
      
      // Use fallback if still empty
      if (!deviceId || deviceId === '') {
        deviceId = 'bt-device-' + Date.now();
        console.log('Using generated device ID:', deviceId);
      }
      
      if (!deviceName || deviceName === '') {
        deviceName = 'BlueTooth Printer';
        console.log('Using default device name:', deviceName);
      }
      
      console.log('Final Device ID:', deviceId);
      console.log('Final Device name:', deviceName);
      
      bluetoothDevice.addEventListener('gattserverdisconnected', () => {
        console.log('Bluetooth device disconnected');
        bluetoothDevice = null;
        bluetoothCharacteristic = null;
      });

      // Convert to strings
      const deviceIdStr = String(deviceId);
      const deviceNameStr = String(deviceName);
      
      console.log('=== Passing to Dart ===');
      console.log('Device ID string:', deviceIdStr);
      console.log('Device name string:', deviceNameStr);
      console.log('Calling onSuccess with 2 parameters:');
      console.log('  Parameter 1 (id): "' + deviceIdStr + '"');
      console.log('  Parameter 2 (name): "' + deviceNameStr + '"');
      
      if (onSuccess) {
        // CRITICAL: Pass as TWO SEPARATE STRING PARAMETERS
        onSuccess(deviceIdStr, deviceNameStr);
        console.log('onSuccess callback called with 2 parameters');
      }
    })
    .catch(error => {
      console.error('Error requesting Bluetooth device:', error);
      if (error.name === 'NotFoundError' || error.message.includes('cancelled')) {
        console.log('User cancelled device selection');
        if (onSuccess) onSuccess(null); // Call success with null for cancellation
      } else {
        if (onError) onError(error.toString());
      }
    });
  } catch (error) {
    console.error('Error in requestBluetoothDeviceWithCallback:', error);
    if (onError) onError(error.toString());
  }
};

// Connect to the selected Bluetooth device (callback-based)
window.connectBluetoothDevice = function(deviceId, onSuccess, onError) {
  try {
    if (!bluetoothDevice) {
      if (onError) onError('Device not selected. Please select a device first.');
      return;
    }

    console.log('Connecting to Bluetooth device:', bluetoothDevice.name);
    console.log('Device GATT available:', !!bluetoothDevice.gatt);
    
    // Check if device supports GATT
    if (!bluetoothDevice.gatt) {
      const errorMsg = 'This device does not support GATT (Bluetooth Low Energy). Web Bluetooth API requires BLE devices. Your printer may use classic Bluetooth (SPP) which is not supported by web browsers. Please use WiFi connection instead, or use a BLE-compatible printer.';
      console.error(errorMsg);
      if (onError) onError(errorMsg);
      return;
    }
    
    // Connect to GATT server first
    if (!bluetoothDevice.gatt.connected) {
      console.log('Attempting GATT connection...');
      bluetoothDevice.gatt.connect()
        .then(() => {
          console.log('GATT connected to device:', bluetoothDevice.name);
          
          // Discover all services - don't filter, get everything
          console.log('Discovering all services...');
          return bluetoothDevice.gatt.getPrimaryServices();
        })
        .then(services => {
          console.log('Found', services.length, 'services');
          services.forEach((service, index) => {
            console.log(`Service ${index}: UUID=${service.uuid}`);
          });
          
          // Try to find Serial Port Profile service with various UUID formats
          let targetService = null;
          
          // Try exact match first
          targetService = services.find(s => 
            s.uuid === BLUETOOTH_SERVICE_UUID || 
            s.uuid.toLowerCase() === BLUETOOTH_SERVICE_UUID.toLowerCase()
          );
          
          if (!targetService) {
            // Try standard SPP UUID
            const standardSPP = '00001101-0000-1000-8000-00805f9b34fb';
            targetService = services.find(s => 
              s.uuid === standardSPP || 
              s.uuid.toLowerCase() === standardSPP.toLowerCase() ||
              s.uuid.includes('1101') || 
              s.uuid.includes('00001101')
            );
          }
          
          if (!targetService && services.length > 0) {
            // Use first available service as fallback
            console.log('SPP service not found, using first available service');
            targetService = services[0];
          }
          
          if (!targetService) {
            throw new Error('No services found on device. Make sure the printer is in Bluetooth mode and paired.');
          }
          
          console.log('Using service:', targetService.uuid);
          
          // Get characteristics from the service
          return targetService.getCharacteristics();
        })
        .then(characteristics => {
          console.log('Found', characteristics.length, 'characteristics');
          characteristics.forEach((char, index) => {
            console.log(`Characteristic ${index}: UUID=${char.uuid}, write=${char.properties.write}, writeWithoutResponse=${char.properties.writeWithoutResponse}`);
          });
          
          // Find a writable characteristic (prefer writeWithoutResponse for thermal printers)
          let writableChar = characteristics.find(char => 
            char.properties.writeWithoutResponse
          );
          
          if (!writableChar) {
            writableChar = characteristics.find(char => 
              char.properties.write
            );
          }
          
          if (writableChar) {
            bluetoothCharacteristic = writableChar;
            console.log('Using characteristic:', writableChar.uuid);
            if (onSuccess) onSuccess(true);
          } else if (characteristics.length > 0) {
            // Use first characteristic as last resort
            bluetoothCharacteristic = characteristics[0];
            console.log('Using first characteristic as fallback:', characteristics[0].uuid);
            if (onSuccess) onSuccess(true);
          } else {
            throw new Error('No characteristics found in service');
          }
        })
        .catch(error => {
          console.error('Error connecting to Bluetooth device:', error);
          console.error('Error name:', error.name);
          console.error('Error message:', error.message);
          
          // Provide helpful error messages
          let errorMessage = error.toString();
          if (error.name === 'NetworkError' && error.message.includes('Unsupported device')) {
            errorMessage = 'This printer uses classic Bluetooth (SPP) which is not supported by Web Bluetooth API. Web browsers only support Bluetooth Low Energy (BLE) devices. Please use WiFi connection instead, or ensure your printer supports BLE/GATT.';
          } else if (error.name === 'NetworkError') {
            errorMessage = 'Network error connecting to device. Make sure the printer is powered on, in Bluetooth mode, and try pairing it with your computer first through system settings.';
          } else if (error.message.includes('GATT Server')) {
            errorMessage = 'GATT server connection failed. This device may not support Bluetooth Low Energy. Please use WiFi connection instead.';
          }
          
          if (onError) onError(errorMessage);
        });
    } else {
      // Already connected, check if characteristic exists
      console.log('Device already connected');
      if (bluetoothCharacteristic) {
        if (onSuccess) onSuccess(true);
      } else {
        // Need to get characteristic
        bluetoothDevice.gatt.getPrimaryServices()
          .then(services => {
            if (services.length > 0) {
              return services[0].getCharacteristics();
            }
            throw new Error('No services available');
          })
          .then(characteristics => {
            if (characteristics.length > 0) {
              bluetoothCharacteristic = characteristics.find(c => c.properties.writeWithoutResponse) || characteristics[0];
              if (onSuccess) onSuccess(true);
            } else {
              throw new Error('No characteristics found');
            }
          })
          .catch(error => {
            if (onError) onError(error.toString());
          });
      }
    }
  } catch (error) {
    console.error('Error in connectBluetoothDevice:', error);
    if (onError) onError(error.toString());
  }
};

// Send data to Bluetooth printer (callback-based)
window.sendBluetoothData = function(data, onSuccess, onError) {
  try {
    if (!bluetoothCharacteristic) {
      if (onError) onError('Not connected to Bluetooth device');
      return;
    }

    // Convert array to Uint8Array
    let uint8Array;
    if (Array.isArray(data)) {
      uint8Array = new Uint8Array(data);
    } else if (data instanceof Uint8Array) {
      uint8Array = data;
    } else {
      if (onError) onError('Invalid data type');
      return;
    }

    // Write data to characteristic
    const writePromise = bluetoothCharacteristic.properties.writeWithoutResponse
      ? bluetoothCharacteristic.writeValueWithoutResponse(uint8Array.buffer)
      : bluetoothCharacteristic.writeValue(uint8Array.buffer);
    
    writePromise
      .then(() => {
        console.log('Data sent to Bluetooth printer:', uint8Array.length, 'bytes');
        if (onSuccess) onSuccess(true);
      })
      .catch(error => {
        console.error('Error writing to characteristic:', error);
        if (onError) onError(error.toString());
      });
  } catch (error) {
    console.error('Error sending data to Bluetooth printer:', error);
    if (onError) onError(error.toString());
  }
};

// Disconnect from Bluetooth device
window.disconnectBluetoothDevice = async function() {
  try {
    if (bluetoothDevice && bluetoothDevice.gatt.connected) {
      bluetoothDevice.gatt.disconnect();
      console.log('Disconnected from Bluetooth device');
    }
    bluetoothDevice = null;
    bluetoothCharacteristic = null;
    return true;
  } catch (error) {
    console.error('Error disconnecting from Bluetooth device:', error);
    throw error;
  }
};

// Check if Bluetooth is available
window.isBluetoothAvailable = function() {
  return typeof navigator !== 'undefined' && navigator.bluetooth !== undefined;
};

// Get connected device info
window.getBluetoothDeviceInfo = function() {
  if (!bluetoothDevice) {
    return null;
  }
  return {
    id: bluetoothDevice.id,
    name: bluetoothDevice.name,
    connected: bluetoothDevice.gatt.connected
  };
};

