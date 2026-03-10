# Running the Seller App (separate build)

The **Seller App** uses the same project but a different entry point: `lib/main_seller.dart`.

## Run from terminal

**Admin app (default):**
```bash
flutter run
```

**Seller app:**
```bash
flutter run -t lib/main_seller.dart
```

To run on a specific device (e.g. your phone) when multiple devices are connected:
```bash
flutter devices
flutter run -t lib/main_seller.dart -d <device_id>
```

---

## Run on your phone (Android)

### 1. Prepare your phone
- Enable **Developer options**: Settings → About phone → tap "Build number" 7 times.
- Enable **USB debugging**: Settings → Developer options → USB debugging.
- Connect the phone with a USB cable. Accept "Allow USB debugging" on the phone.

### 2. From terminal
```bash
cd /path/to/pos_adminTest
flutter run -t lib/main_seller.dart
```
If only the phone is connected, Flutter will use it. Otherwise run `flutter devices` and use `-d <device_id>`.

### 3. From Android Studio
1. **Open the project**: File → Open → select the `pos_adminTest` folder.
2. **Select the seller entry point**:  
   - Open **Run → Edit Configurations**.  
   - Add a **Flutter** configuration (or duplicate the existing one).  
   - Set **Dart entrypoint** to: `lib/main_seller.dart`.  
   - Name it e.g. "Seller App" and save.
3. **Select your phone** in the device dropdown (top toolbar).
4. Click **Run** (green play). The seller app will install and launch on your phone.

### 4. From VS Code / Cursor
- If you have the Dart/Flutter extension and `.vscode/launch.json` with the "Seller App" config, choose **Seller App** from the Run and Debug dropdown and press F5 (or Run → Start Debugging).
- Select your Android device when prompted.

---

## Build APK for seller app (install without USB)

```bash
flutter build apk -t lib/main_seller.dart
```
The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`. Copy it to your phone and install (you may need to allow "Install from unknown sources" for the file manager).

To build a separate output name so you can have both admin and seller APKs with different names, you can use:
```bash
flutter build apk -t lib/main_seller.dart --build-name=1.0.0 --build-number=1
# Output: build/app/outputs/flutter-apk/app-release.apk
# Rename to seller-app.apk before distributing if needed.
```
