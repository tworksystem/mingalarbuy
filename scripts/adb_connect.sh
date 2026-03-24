#!/bin/bash

##############################################################################
# Professional ADB Wireless Connection Helper Script
# Simplified wrapper for common ADB wireless connection tasks
##############################################################################

set -e

# Default IP (can be overridden with argument)
TARGET_IP="${1:-192.168.0.115}"
PORT="${2:-5555}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}ADB Wireless Connection Helper${NC}\n"

# Function to check connectivity
check_connectivity() {
    if ping -c 1 -W 2 "$TARGET_IP" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Device at $TARGET_IP is reachable${NC}"
        return 0
    else
        echo -e "${RED}✗ Device at $TARGET_IP is not reachable${NC}"
        return 1
    fi
}

# Function to ensure ADB server is running
ensure_adb_server() {
    if ! adb start-server > /dev/null 2>&1; then
        echo -e "${RED}✗ Failed to start ADB server${NC}"
        exit 1
    fi
}

# Function to connect via TCP/IP
connect_tcpip() {
    echo -e "${YELLOW}Connecting to $TARGET_IP:$PORT...${NC}"
    
    if ! check_connectivity; then
        echo -e "\n${YELLOW}→ Make sure your device and computer are on the same WiFi network${NC}"
        exit 1
    fi
    
    ensure_adb_server
    
    # Try to connect
    RESULT=$(adb connect "$TARGET_IP:$PORT" 2>&1)
    
    if echo "$RESULT" | grep -q "connected"; then
        echo -e "${GREEN}✓ Successfully connected!${NC}"
    elif echo "$RESULT" | grep -q "already connected"; then
        echo -e "${GREEN}✓ Already connected${NC}"
    elif echo "$RESULT" | grep -q "Connection refused"; then
        echo -e "${RED}✗ Connection refused${NC}"
        echo -e "\n${YELLOW}Troubleshooting steps:${NC}"
        echo -e "  1. Enable 'USB debugging' on your device"
        echo -e "  2. Connect device via USB first, then run:"
        echo -e "     ${BLUE}adb tcpip $PORT${NC}"
        echo -e "     ${BLUE}adb disconnect${NC}  (optional)"
        echo -e "  3. Then reconnect wirelessly:"
        echo -e "     ${BLUE}adb connect $TARGET_IP:$PORT${NC}"
        echo -e "\n${YELLOW}For Android 11+:${NC}"
        echo -e "  Use 'Wireless Debugging' in Developer Options"
        echo -e "  and follow the pairing process"
        exit 1
    else
        echo -e "${YELLOW}⚠ $RESULT${NC}"
    fi
    
    echo -e "\n${BLUE}Connected devices:${NC}"
    adb devices -l
}

# Function to enable TCP/IP mode (requires USB connection first)
enable_tcpip() {
    if [ -z "$PORT" ]; then
        PORT=5555
    fi
    
    echo -e "${YELLOW}Enabling TCP/IP mode on port $PORT...${NC}"
    echo -e "${YELLOW}⚠ This requires the device to be connected via USB first${NC}\n"
    
    ensure_adb_server
    
    # Check if any device is connected
    DEVICES=$(adb devices | grep -v "List of devices" | grep "device" | grep -v "no permissions" | wc -l | tr -d ' ')
    
    if [ "$DEVICES" -eq 0 ]; then
        echo -e "${RED}✗ No devices connected via USB${NC}"
        echo -e "\n${YELLOW}Please:${NC}"
        echo -e "  1. Connect your device via USB"
        echo -e "  2. Enable 'USB debugging'"
        echo -e "  3. Accept the USB debugging prompt on your device"
        echo -e "  4. Run this script again"
        exit 1
    fi
    
    if adb tcpip "$PORT" 2>&1 | grep -q "restarting"; then
        echo -e "${GREEN}✓ TCP/IP mode enabled on port $PORT${NC}"
        echo -e "${YELLOW}→ You can now disconnect USB and connect wirelessly${NC}"
    else
        echo -e "${RED}✗ Failed to enable TCP/IP mode${NC}"
        exit 1
    fi
}

# Function to disconnect
disconnect() {
    echo -e "${YELLOW}Disconnecting from $TARGET_IP:$PORT...${NC}"
    
    if adb disconnect "$TARGET_IP:$PORT" 2>&1 | grep -q "disconnected"; then
        echo -e "${GREEN}✓ Disconnected${NC}"
    else
        echo -e "${YELLOW}⚠ No active connection to disconnect${NC}"
    fi
}

# Function to show status
show_status() {
    echo -e "${BLUE}ADB Connection Status${NC}\n"
    
    ensure_adb_server
    
    echo -e "${BLUE}Connected devices:${NC}"
    adb devices -l
    
    echo -e "\n${BLUE}Network check for $TARGET_IP:${NC}"
    if check_connectivity; then
        echo -e "${BLUE}Port $PORT check:${NC}"
        if command -v nc &> /dev/null; then
            if nc -z -v -w 2 "$TARGET_IP" "$PORT" 2>&1 | grep -q "succeeded"; then
                echo -e "${GREEN}✓ Port $PORT is open${NC}"
            else
                echo -e "${RED}✗ Port $PORT is closed or filtered${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ 'nc' not available for port check${NC}"
        fi
    fi
}

# Main menu
case "${3:-connect}" in
    connect)
        connect_tcpip
        ;;
    enable)
        enable_tcpip
        ;;
    disconnect)
        disconnect
        ;;
    status)
        show_status
        ;;
    *)
        echo -e "${BLUE}Usage:${NC}"
        echo -e "  $0 [IP] [PORT] [command]"
        echo -e "\n${BLUE}Commands:${NC}"
        echo -e "  connect    - Connect wirelessly (default)"
        echo -e "  enable     - Enable TCP/IP mode (requires USB)"
        echo -e "  disconnect - Disconnect wireless connection"
        echo -e "  status     - Show connection status"
        echo -e "\n${BLUE}Examples:${NC}"
        echo -e "  $0                          # Connect to default IP (192.168.0.115:5555)"
        echo -e "  $0 192.168.1.100            # Connect to custom IP"
        echo -e "  $0 192.168.1.100 5555 enable   # Enable TCP/IP mode"
        echo -e "  $0 192.168.1.100 5555 status   # Check status"
        exit 1
        ;;
esac
