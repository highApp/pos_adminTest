#!/bin/bash

# Build APK Script for AR Karayana Store
# This script builds an APK for testing on Android devices

echo "========================================="
echo "Building APK for AR Karayana Store"
echo "========================================="

# Clean previous builds
echo "Cleaning previous builds..."
flutter clean

# Get dependencies
echo "Getting Flutter dependencies..."
flutter pub get

# Build APK (debug version for testing)
echo "Building APK..."
flutter build apk --debug

# Check if build was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "✓ APK built successfully!"
    echo "========================================="
    echo ""
    echo "APK location:"
    echo "build/app/outputs/flutter-apk/app-debug.apk"
    echo ""
    echo "To install on your Android device:"
    echo "1. Transfer the APK file to your Android phone/tablet"
    echo "2. Enable 'Install from Unknown Sources' in Settings"
    echo "3. Open the APK file and install"
    echo ""
    echo "Or use ADB to install directly:"
    echo "adb install build/app/outputs/flutter-apk/app-debug.apk"
    echo ""
else
    echo ""
    echo "========================================="
    echo "✗ Build failed!"
    echo "========================================="
    echo "Please check the error messages above."
    exit 1
fi

