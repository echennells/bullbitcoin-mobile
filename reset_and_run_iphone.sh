#!/bin/bash

# Reset and run script for Bull Bitcoin Mobile on physical iPhone

echo "🧹 Cleaning up..."

# Kill any running flutter processes
pkill -f "flutter run" 2>/dev/null || true

# Wait a moment for processes to die
sleep 2

# Your iPhone device ID
DEVICE_ID="00008120-001A10C10250A01E"

echo "🗑️  Cleaning Flutter build..."
fvm flutter clean

echo "📦 Installing CocoaPods dependencies..."
cd ios
pod install
cd ..

echo "🔨 Building and running on iPhone..."

# Run on the physical device
fvm flutter run -d "$DEVICE_ID"
