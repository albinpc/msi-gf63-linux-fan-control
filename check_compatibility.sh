#!/usr/bin/env bash

EXPECTED_PRODUCT="GF63 Thin 11SC"
EXPECTED_BOARD="MS-16R6"

PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
BOARD=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
BIOS=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)

echo "========================================"
echo "MSI GF63 Compatibility Check"
echo "========================================"
echo "Product : $PRODUCT"
echo "Board   : $BOARD"
echo "BIOS    : $BIOS"
echo

if [ "$PRODUCT" != "$EXPECTED_PRODUCT" ]; then
    echo "[FAIL] Unsupported product."
    echo "Expected: $EXPECTED_PRODUCT"
    echo "Found   : $PRODUCT"
    exit 1
fi

if [ "$BOARD" != "$EXPECTED_BOARD" ]; then
    echo "[FAIL] Unsupported board."
    echo "Expected: $EXPECTED_BOARD"
    echo "Found   : $BOARD"
    exit 1
fi

if ! command -v ec_helper >/dev/null 2>&1; then
    echo "[FAIL] ec_helper was not found."
    exit 1
fi

echo "[OK] Hardware matches tested configuration."
echo

echo "Reading EC registers..."
echo

echo "CPU temperature : $(ec_helper read 0x68)"
echo "GPU temperature : $(ec_helper read 0x80)"
echo "CPU fan         : $(ec_helper read 0x71)"
echo "GPU fan         : $(ec_helper read 0x89)"
echo "Fan mode        : $(ec_helper read 0xd4)"
echo "Cooler Boost    : $(ec_helper read 0x98)"

echo
echo "[PASS] Compatibility check completed."
echo
echo "This script performed READS ONLY."
