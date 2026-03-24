#!/bin/bash

# Wireless ADB Setup Script
# This script helps you connect to an Android device over Wi-Fi

echo "🔌 Wireless ADB Setup Script"
echo "============================"
echo ""

# Check if device is connected via USB
echo "📱 Checking for USB-connected devices..."
USB_DEVICE=$(adb devices | grep -v "List" | grep "device" | awk '{print $1}')

if [ -z "$USB_DEVICE" ]; then
    echo "❌ No USB device found!"
    echo ""
    echo "Please connect your device via USB and enable USB debugging."
    echo "Then run this script again."
    exit 1
fi

echo "✅ Found device: $USB_DEVICE"
echo ""

# Get device IP address
echo "🌐 Getting device IP address..."
DEVICE_IP=$(adb shell ip addr show wlan0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

if [ -z "$DEVICE_IP" ]; then
    echo "❌ Could not get device IP address"
    echo "Please ensure your device is connected to Wi-Fi"
    exit 1
fi

echo "✅ Device IP: $DEVICE_IP"
echo ""

# Enable TCP/IP mode
echo "🔧 Enabling TCP/IP mode on port 5555..."
adb tcpip 5555

if [ $? -eq 0 ]; then
    echo "✅ TCP/IP mode enabled"
    echo ""
    
    # Wait a moment for the port to be ready
    sleep 2
    
    # Connect wirelessly
    echo "📡 Connecting wirelessly..."
    adb connect $DEVICE_IP:5555
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Successfully connected to $DEVICE_IP:5555"
        echo ""
        echo "📋 Connected devices:"
        adb devices -l
    else
        echo "❌ Failed to connect wirelessly"
        exit 1
    fi
else
    echo "❌ Failed to enable TCP/IP mode"
    exit 1
fi

