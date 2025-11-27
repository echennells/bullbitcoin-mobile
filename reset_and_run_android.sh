#!/bin/bash

# Complete reset and run script for Bull Bitcoin Mobile on Android

echo "🧹 Cleaning up..."

# Kill any running flutter processes
pkill -f "flutter run" 2>/dev/null || true

# Kill Android emulator
killall qemu-system-aarch64 2>/dev/null || true
killall emulator 2>/dev/null || true

# Wait a moment for processes to die
sleep 2

echo "📱 Starting Android emulator..."

# Check if emulator is already running and kill it for a clean wipe
if ~/Library/Android/sdk/platform-tools/adb devices | grep -q "emulator-5554"; then
    echo "🗑️  Killing existing emulator for clean wipe..."
    ~/Library/Android/sdk/platform-tools/adb -s emulator-5554 emu kill
    sleep 3
fi

echo "🗑️  Starting emulator with wiped data (clears ALL data including secure storage)..."
# Start the emulator with -wipe-data to completely reset it
~/Library/Android/sdk/emulator/emulator -avd Pixel_API_35 -wipe-data -no-snapshot-load 2>&1 | grep -i "error" &

echo "⏳ Waiting for emulator to boot..."

# Wait for the emulator to be detected (with timeout)
timeout=90
elapsed=0
while [ $elapsed -lt $timeout ]; do
    if ~/Library/Android/sdk/platform-tools/adb devices | grep -q "emulator-5554"; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ $elapsed -ge $timeout ]; then
    echo "❌ Timeout waiting for emulator to start!"
    exit 1
fi

# Wait for boot to complete
~/Library/Android/sdk/platform-tools/adb wait-for-device

# Give it a few more seconds to fully initialize
sleep 5

echo "✅ Emulator ready!"

echo "🔨 Running Flutter..."

# Run flutter
fvm flutter run -d emulator-5554
