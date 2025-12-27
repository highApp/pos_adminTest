#!/bin/bash

# AR Traders - Firebase Deployment Script
# This script builds and deploys the Flutter web app to Firebase Hosting

# Set Flutter path
FLUTTER_PATH="/Users/muhammadusman/flutter/bin/flutter"

echo "🚀 Starting deployment process..."
echo ""

# Navigate to project directory
cd "$(dirname "$0")"

# Step 1: Clean previous builds
echo "🧹 Cleaning previous builds..."
$FLUTTER_PATH clean
if [ $? -ne 0 ]; then
    echo "❌ Error: Flutter clean failed"
    exit 1
fi
echo "✅ Clean completed"
echo ""

# Step 2: Get dependencies
echo "📦 Getting dependencies..."
$FLUTTER_PATH pub get
if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to get dependencies"
    exit 1
fi
echo "✅ Dependencies installed"
echo ""

# Step 3: Build for web
echo "🔨 Building Flutter web app (this may take a few minutes)..."
$FLUTTER_PATH build web --release
if [ $? -ne 0 ]; then
    echo "❌ Error: Flutter build failed"
    exit 1
fi
echo "✅ Build completed successfully"
echo ""

# Step 4: Deploy to Firebase
echo "🚀 Deploying to Firebase Hosting..."
firebase deploy --only hosting
if [ $? -ne 0 ]; then
    echo "❌ Error: Firebase deployment failed"
    echo "💡 Make sure you're logged in: firebase login"
    exit 1
fi

echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "🎉 Your app is now live on Firebase!"
echo ""
echo "📝 Changes deployed:"
echo "   • CSV Export functionality for Sellers module"
echo "   • Export sellers data with due amounts to CSV"
echo "   • Total amount calculation at end of CSV"
echo "   • Column-wise CSV format with proper headers"
echo "   • Web download support with fallback options"
echo ""
