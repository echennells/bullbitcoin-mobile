#!/bin/bash

# Reset and run script for Bull Bitcoin Mobile on iOS Simulator

echo "🧹 Cleaning up..."

# Kill any running flutter processes
pkill -f "flutter run" 2>/dev/null || true

# Kill all simulators
killall Simulator 2>/dev/null || true

# Wait a moment for processes to die
sleep 2

# Use the iPhone 16e simulator
SIMULATOR_ID="BBD1D25C-9D56-4EB1-BFFA-83010550210F"

echo "🗑️  Erasing simulator (this clears ALL data including Keychain)..."
xcrun simctl shutdown "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl erase "$SIMULATOR_ID"

echo "🚀 Booting simulator..."

# Boot the simulator
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || echo "Simulator already booted or boot failed"

# Open Simulator app
open -a Simulator

# Wait for simulator to be ready
sleep 5

echo "🔨 Running Flutter on simulator..."

# Run on the booted simulator (use device name instead of ID to avoid issues)
fvm flutter run -d "iPhone 16e"
