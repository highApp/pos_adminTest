# Building APK for Android Testing

## Quick Build Commands

### Option 1: Using the Build Script
```bash
chmod +x build_apk.sh
./build_apk.sh
```

### Option 2: Manual Build Commands

1. **Clean previous builds:**
   ```bash
   flutter clean
   ```

2. **Get dependencies:**
   ```bash
   flutter pub get
   ```

3. **Build Debug APK (for testing):**
   ```bash
   flutter build apk --debug
   ```

4. **Build Release APK (optimized, for production):**
   ```bash
   flutter build apk --release
   ```

## APK Location

After building, the APK will be located at:
- **Debug APK:** `build/app/outputs/flutter-apk/app-debug.apk`
- **Release APK:** `build/app/outputs/flutter-apk/app-release.apk`

## Installing on Android Device

### Method 1: Direct Transfer
1. Copy the APK file to your Android phone/tablet (via USB, email, or cloud storage)
2. On your Android device, go to **Settings > Security**
3. Enable **"Install from Unknown Sources"** or **"Install Unknown Apps"**
4. Open the APK file using a file manager
5. Tap **Install**

### Method 2: Using ADB (Android Debug Bridge)
1. Connect your Android device via USB
2. Enable **USB Debugging** in Developer Options
3. Run:
   ```bash
   adb install build/app/outputs/flutter-apk/app-debug.apk
   ```

### Method 3: Using ADB Wireless
1. Connect device and computer to same WiFi
2. Enable **Wireless Debugging** in Developer Options
3. Connect via ADB:
   ```bash
   adb connect <device-ip>:5555
   adb install build/app/outputs/flutter-apk/app-debug.apk
   ```

## Troubleshooting

### If Flutter command not found:
1. Make sure Flutter is installed and in your PATH
2. Or use the full path to Flutter:
   ```bash
   /path/to/flutter/bin/flutter build apk --debug
   ```

### If build fails:
1. Check that you have Android SDK installed
2. Verify `ANDROID_HOME` environment variable is set
3. Run `flutter doctor` to check for issues

### For Release Build:
If you want to build a release APK (smaller size, optimized), you may need to set up signing:
1. Create a keystore file
2. Configure signing in `android/app/build.gradle.kts`

## Notes

- **Debug APK** is larger but easier to debug
- **Release APK** is optimized and smaller, but requires signing for distribution
- For testing purposes, use the debug APK

