#!/bin/bash

##############################################################################
# Professional ADB Wireless Connection Fix Script
# Handles both modern (Android 11+) and legacy wireless ADB connections
##############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ADB Wireless Connection Diagnostic Tool${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Step 1: Check ADB server
echo -e "${YELLOW}[1/6]${NC} Checking ADB server status..."
if ! command -v adb &> /dev/null; then
    echo -e "${RED}✗ ADB not found in PATH${NC}"
    exit 1
fi

adb start-server > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ ADB server is running${NC}"
else
    echo -e "${RED}✗ Failed to start ADB server${NC}"
    exit 1
fi

# Step 2: Check current connections
echo -e "\n${YELLOW}[2/6]${NC} Checking current ADB connections..."
DEVICES=$(adb devices | grep -v "List of devices" | grep "device" | wc -l | tr -d ' ')
echo -e "  Currently connected devices: ${GREEN}$DEVICES${NC}"
adb devices -l

# Step 3: Get target IP address
echo -e "\n${YELLOW}[3/6]${NC} Network connectivity check..."
if [ -z "$1" ]; then
    TARGET_IP="192.168.0.115"
    echo -e "  Using default IP: ${BLUE}$TARGET_IP${NC}"
else
    TARGET_IP="$1"
    echo -e "  Using provided IP: ${BLUE}$TARGET_IP${NC}"
fi

# Ping test
if ping -c 1 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓ Device is reachable${NC}"
else
    echo -e "  ${RED}✗ Device is not reachable at $TARGET_IP${NC}"
    echo -e "  ${YELLOW}→ Check if device and computer are on the same network${NC}"
    exit 1
fi

# Step 4: Try legacy TCP/IP connection method
echo -e "\n${YELLOW}[4/6]${NC} Attempting legacy TCP/IP connection (port 5555)..."
if adb connect "$TARGET_IP:5555" 2>&1 | grep -q "connected"; then
    echo -e "  ${GREEN}✓ Successfully connected via TCP/IP!${NC}"
    exit 0
elif adb connect "$TARGET_IP:5555" 2>&1 | grep -q "already connected"; then
    echo -e "  ${GREEN}✓ Device already connected${NC}"
    exit 0
else
    echo -e "  ${YELLOW}⚠ TCP/IP connection refused${NC}"
    echo -e "  ${YELLOW}→ This is normal for modern Android devices (Android 11+)${NC}"
fi

# Step 5: Check if device needs to be paired (Modern Android Wireless Debugging)
echo -e "\n${YELLOW}[5/6]${NC} Checking for Wireless Debugging support..."
echo -e "  ${BLUE}For Android 11+ devices, use Wireless Debugging:${NC}"
echo -e "  ${BLUE}1. Go to: Settings > Developer Options > Wireless Debugging${NC}"
echo -e "  ${BLUE}2. Tap 'Pair device with pairing code'${NC}"
echo -e "  ${BLUE}3. Note the IP address and port (e.g., 192.168.0.115:XXXXX)${NC}"
echo -e "  ${BLUE}4. Note the pairing code${NC}"
echo -e "  ${BLUE}5. Run: adb pair $TARGET_IP:XXXXX${NC}"

# Step 6: Try alternative methods
echo -e "\n${YELLOW}[6/6]${NC} Alternative connection methods..."

# Method 1: Try connecting if USB was previously used to enable TCP/IP
echo -e "\n  ${BLUE}Method 1: Enable TCP/IP via USB (if available)${NC}"
echo -e "    Connect device via USB, then run:"
echo -e "    ${YELLOW}adb tcpip 5555${NC}"
echo -e "    ${YELLOW}adb connect $TARGET_IP:5555${NC}"

# Method 2: Check if port 5555 is blocked
echo -e "\n  ${BLUE}Method 2: Check firewall settings${NC}"
if command -v nc &> /dev/null; then
    if nc -z -v -w 2 "$TARGET_IP" 5555 2>&1 | grep -q "succeeded"; then
        echo -e "    ${GREEN}✓ Port 5555 is open${NC}"
    else
        echo -e "    ${RED}✗ Port 5555 is closed or filtered${NC}"
        echo -e "    ${YELLOW}→ Check firewall on both device and computer${NC}"
    fi
else
    echo -e "    ${YELLOW}⚠ 'nc' command not available for port check${NC}"
fi

# Method 3: Wireless Debugging (Modern)
echo -e "\n  ${BLUE}Method 3: Wireless Debugging (Android 11+)${NC}"
echo -e "    This requires pairing first:"
echo -e "    ${YELLOW}adb pair $TARGET_IP:<pairing_port>${NC}"
echo -e "    Then connect:"
echo -e "    ${YELLOW}adb connect $TARGET_IP:<debugging_port>${NC}"

# Final summary
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Summary & Next Steps${NC}"
echo -e "${BLUE}========================================${NC}\n"

if [ "$DEVICES" -gt 0 ]; then
    echo -e "${GREEN}✓ You already have $DEVICES device(s) connected${NC}"
    echo -e "  Run ${YELLOW}adb devices${NC} to see all connected devices"
else
    echo -e "${YELLOW}⚠ No devices currently connected via ADB${NC}\n"
    echo -e "${BLUE}Recommended steps:${NC}"
    echo -e "  1. Enable Developer Options on your Android device"
    echo -e "  2. For Android 10 or earlier:"
    echo -e "     - Enable 'USB debugging'"
    echo -e "     - Enable 'USB debugging (Security settings)'"
    echo -e "     - Connect via USB once, run: ${YELLOW}adb tcpip 5555${NC}"
    echo -e "     - Then: ${YELLOW}adb connect $TARGET_IP:5555${NC}"
    echo -e "  3. For Android 11 or later:"
    echo -e "     - Enable 'Wireless Debugging' in Developer Options"
    echo -e "     - Use the pairing method (see instructions above)"
fi

echo -e "\n${BLUE}Current device status:${NC}"
adb devices

echo -e "\n${GREEN}Done!${NC}\n"
