#!/bin/bash

# Complete reset and run script for Bull Bitcoin Mobile

echo "🧹 Cleaning up..."

# Kill any running flutter processes
pkill -f "flutter run" 2>/dev/null || true

# Kill Simulator
killall Simulator 2>/dev/null || true

# Wait a moment for processes to die
sleep 2

echo "🗑️  Deleting old simulator..."

# Delete the iPhone 16e simulator if it exists
xcrun simctl delete "iPhone 16e" 2>/dev/null || true

echo "📱 Creating fresh simulator..."

# Create a new iPhone 16e simulator
UDID=$(xcrun simctl create "iPhone 16e" "iPhone 16")
echo "Created simulator with UDID: $UDID"

echo "🚀 Opening Simulator..."

# Open Simulator app
open -a Simulator

# Wait for Simulator to fully open
sleep 3

echo "⚡ Booting simulator..."

# Boot the new simulator
xcrun simctl boot "iPhone 16e"

# Wait for boot to complete
sleep 3

echo "🔨 Running Flutter..."

# Run flutter
fvm flutter run
