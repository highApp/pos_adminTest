// Web USB API for thermal printer support
// This file provides USB printing functionality for web browsers

let usbDevice = null;

// Check if Web USB API is available
window.isUsbAvailable = function() {
  return navigator.usb !== undefined;
};

// Request USB device (callback-based for better Dart interop)
window.requestUsbDeviceWithCallback = function(onSuccess, onError) {
  try {
    if (!navigator.usb) {
      if (onError) onError('Web USB API is not supported in this browser. Please use Chrome, Edge, or Opera.');
      return;
    }

    // Request access to USB device
    // For thermal printers, we typically look for devices with vendor/product IDs
    // or use a filter. For SpeedX SP-90A, we'll request any USB device and let user select
    navigator.usb.requestDevice({
      filters: [
        // Common thermal printer vendor IDs (add more as needed)
        { classCode: 7 }, // Printer class
        { classCode: 255 }, // Vendor specific
      ]
    })
    .then(device => {
      usbDevice = device;
      console.log('=== USB Device Selected ===');
      console.log('Device:', device);
      console.log('Vendor ID:', device.vendorId);
      console.log('Product ID:', device.productId);
      console.log('Product Name:', device.productName);
      
      // Pass device info as separate parameters
      const deviceId = `${device.vendorId}-${device.productId}`;
      const deviceName = device.productName || `USB Printer (${device.vendorId}:${device.productId})`;
      
      if (onSuccess) onSuccess(deviceId, deviceName);
    })
    .catch(error => {
      console.error('Error requesting USB device:', error);
      if (error.name === 'NotFoundError' || error.message.includes('cancelled')) {
        console.log('User cancelled device selection');
        if (onSuccess) onSuccess(null, null); // Call success with null for cancellation
      } else {
        if (onError) onError(error.toString());
      }
    });
  } catch (error) {
    console.error('Error in requestUsbDeviceWithCallback:', error);
    if (onError) onError(error.toString());
  }
};

// Connect to USB device (callback-based)
window.connectUsbDevice = function(deviceId, onSuccess, onError) {
  try {
    if (!usbDevice) {
      if (onError) onError('Device not selected. Please select a device first.');
      return;
    }

    console.log('Connecting to USB device:', usbDevice.productName);
    
    // Open the device
    usbDevice.open()
      .then(() => {
        console.log('USB device opened');
        
        // Select configuration (most devices use configuration 1)
        return usbDevice.selectConfiguration(1);
      })
      .then(() => {
        console.log('Configuration selected');
        
        // Claim interface (most thermal printers use interface 0)
        return usbDevice.claimInterface(0);
      })
      .then(() => {
        console.log('Interface claimed');
        
        // Find the bulk OUT endpoint (for sending data to printer)
        const interfaces = usbDevice.configuration.interfaces;
        let bulkOutEndpoint = null;
        
        for (const iface of interfaces) {
          for (const alternate of iface.alternates) {
            for (const endpoint of alternate.endpoints) {
              if (endpoint.direction === 'out' && endpoint.type === 'bulk') {
                bulkOutEndpoint = endpoint;
                console.log('Found bulk OUT endpoint:', endpoint.endpointNumber);
                break;
              }
            }
            if (bulkOutEndpoint) break;
          }
          if (bulkOutEndpoint) break;
        }
        
        if (!bulkOutEndpoint) {
          // Try default endpoint 1 (common for printers)
          console.log('No bulk OUT endpoint found, using default endpoint 1');
          if (onSuccess) onSuccess(true);
        } else {
          // Store endpoint for later use
          usbDevice.bulkOutEndpoint = bulkOutEndpoint.endpointNumber;
          console.log('Using endpoint:', bulkOutEndpoint.endpointNumber);
          if (onSuccess) onSuccess(true);
        }
      })
      .catch(error => {
        console.error('Error connecting to USB device:', error);
        if (onError) onError(error.toString());
      });
  } catch (error) {
    console.error('Error in connectUsbDevice:', error);
    if (onError) onError(error.toString());
  }
};

// Send data to USB printer (callback-based)
window.sendUsbData = function(data, onSuccess, onError) {
  try {
    if (!usbDevice || !usbDevice.opened) {
      if (onError) onError('USB device not connected');
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

    // Use the stored endpoint or default to 1
    const endpoint = usbDevice.bulkOutEndpoint || 1;
    
    console.log('Sending data to USB printer:', uint8Array.length, 'bytes via endpoint', endpoint);
    
    // Send data via bulk transfer
    usbDevice.transferOut(endpoint, uint8Array.buffer)
      .then(result => {
        console.log('Data sent successfully:', result.bytesWritten, 'bytes');
        if (onSuccess) onSuccess(true);
      })
      .catch(error => {
        console.error('Error sending data:', error);
        if (onError) onError(error.toString());
      });
  } catch (error) {
    console.error('Error in sendUsbData:', error);
    if (onError) onError(error.toString());
  }
};

// Disconnect USB device
window.disconnectUsbDevice = function() {
  try {
    if (usbDevice && usbDevice.opened) {
      usbDevice.close();
      console.log('USB device disconnected');
    }
    usbDevice = null;
  } catch (error) {
    console.error('Error disconnecting USB device:', error);
  }
};

