# Troubleshooting Android Device Connection (Lenovo IdeaTab Pro)

## Quick Checks

### 1. Enable Developer Options on Your Tablet

1. Go to **Settings** > **About Tablet**
2. Find **Build Number** (might be under "Software Information" or "System")
3. Tap **Build Number** 7 times until you see "You are now a developer!"

### 2. Enable USB Debugging

1. Go to **Settings** > **Developer Options** (or **System** > **Developer Options**)
2. Enable **USB Debugging**
3. Optionally enable **USB Debugging (Security Settings)** if available

### 3. Check USB Connection Mode

On your tablet, when connected:
- Swipe down from notification bar
- Look for "USB" or "USB for file transfer" notification
- Tap it and select **File Transfer (MTP)** or **PTP** mode
- Avoid "Charging only" mode

### 4. Trust Computer (First Time Connection)

When you first connect:
- A popup will appear on your tablet: **"Allow USB debugging?"**
- Check **"Always allow from this computer"**
- Tap **"OK" or "Allow"**

### 5. Check USB Cable and Port

- Try a different USB cable (preferably the original or a data cable, not just charging)
- Try a different USB port on your computer
- Some USB ports (especially USB 3.0) may have better compatibility

## Using ADB to Check Connection

### Find ADB Location

If you have Android Studio installed, ADB is usually at:
```bash
~/Library/Android/sdk/platform-tools/adb
```

Or add to PATH:
```bash
export PATH=$PATH:~/Library/Android/sdk/platform-tools
```

### Check if Device is Detected

1. Connect your tablet via USB
2. Open Terminal and run:
   ```bash
   adb devices
   ```

You should see:
```
List of devices attached
XXXXXXXX    device
```

If you see `unauthorized`, go back to step 4 (trust computer).

If you see `offline`, try:
```bash
adb kill-server
adb start-server
adb devices
```

## Lenovo-Specific Issues

### Install Lenovo USB Drivers

Lenovo tablets may need specific drivers:
1. Visit Lenovo support website
2. Search for "IdeaTab Pro USB drivers"
3. Download and install drivers for your specific model

### Alternative: Wireless Debugging (Android 11+)

If USB doesn't work, try wireless debugging:

1. On your tablet:
   - Go to **Settings** > **Developer Options**
   - Enable **Wireless debugging**
   - Tap on it to see IP address and port

2. On your computer:
   ```bash
   adb connect <tablet-ip>:<port>
   ```

## Common Solutions

### Solution 1: Restart ADB Server
```bash
adb kill-server
adb start-server
adb devices
```

### Solution 2: Revoke USB Debugging Authorizations
On your tablet:
- Settings > Developer Options
- Tap **"Revoke USB debugging authorizations"**
- Disconnect and reconnect USB
- Accept the authorization popup again

### Solution 3: Update ADB
```bash
cd ~/Library/Android/sdk/platform-tools
# Or check Android Studio > SDK Manager > SDK Tools > Android SDK Platform-Tools
```

### Solution 4: Check USB Selective Suspend (Windows/Mac)
- **Mac**: Usually not an issue
- **Windows**: Disable USB selective suspend in Power Options

## Verify Connection

After following the steps, verify:

```bash
# Check devices
adb devices

# If device shows, try installing the APK directly
adb install /path/to/your/app-debug.apk
```

## If Still Not Working

1. Check Android Studio > Preferences > Appearance & Behavior > System Settings > Android SDK
   - Ensure "Android SDK Platform-Tools" is installed
   
2. Try different USB connection modes on tablet

3. Check if tablet appears in System Information (Mac) or Device Manager (Windows)

4. Try connecting to a different computer to isolate if it's a computer or tablet issue

5. Update tablet's software if available

