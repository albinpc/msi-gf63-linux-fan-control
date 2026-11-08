#!/usr/bin/env bash
set -u

# ============================================================
# MSI GF63 THIN 11SC / MS-16R6
# AUTOMATIC MULTI-STAGE FAN CONTROLLER
# ============================================================

# ------------------------------------------------------------
# LOAD CONFIGURATION
# ------------------------------------------------------------

CONFIG_FILE="${CONFIG_FILE:-/etc/default/msi-gf63-fan-control}"

if [ -r "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# ------------------------------------------------------------
# DEFAULT CONFIGURATION
# Values from config file override these defaults
# ------------------------------------------------------------

EC_HELPER="${EC_HELPER:-ec_helper}"

EXPECTED_PRODUCT="${EXPECTED_PRODUCT:-GF63 Thin 11SC}"
EXPECTED_BOARD="${EXPECTED_BOARD:-MS-16R6}"
ALLOW_UNTESTED="${ALLOW_UNTESTED:-0}"

CPU_50="${CPU_50:-60}"
GPU_50="${GPU_50:-60}"

CPU_75="${CPU_75:-70}"
GPU_75="${GPU_75:-70}"

CPU_90="${CPU_90:-75}"
GPU_90="${GPU_90:-72}"

CPU_100="${CPU_100:-80}"
GPU_100="${GPU_100:-75}"

CPU_100_DOWN="${CPU_100_DOWN:-77}"
GPU_100_DOWN="${GPU_100_DOWN:-72}"

CPU_90_DOWN="${CPU_90_DOWN:-72}"
GPU_90_DOWN="${GPU_90_DOWN:-68}"

CPU_75_DOWN="${CPU_75_DOWN:-65}"
GPU_75_DOWN="${GPU_75_DOWN:-65}"

CPU_AUTO="${CPU_AUTO:-45}"
GPU_AUTO="${GPU_AUTO:-45}"

POLL_SECONDS="${POLL_SECONDS:-5}"

# ============================================================
# EC REGISTERS
# ============================================================

BOOST_ADDR=0x98
FAN_MODE_ADDR=0xd4

CPU_TEMP_ADDR=0x68
GPU_TEMP_ADDR=0x80

AUTO_MODE=13
ADVANCED_MODE=141

# ============================================================
# FAN CURVE REGISTERS
# ============================================================

CPU_SPEED_REGS=(
    0x72
    0x73
    0x74
    0x75
    0x76
    0x77
    0x78
)

GPU_SPEED_REGS=(
    0x8a
    0x8b
    0x8c
    0x8d
    0x8e
    0x8f
    0x90
)

# ============================================================
# STATE
# ============================================================

STATE="AUTO"

CPU_ORIGINAL=()
GPU_ORIGINAL=()

ORIGINAL_MODE=""
ORIGINAL_BOOST=""

SETTINGS_BACKED_UP=0

# ============================================================
# LOGGING
# ============================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# ============================================================
# HARDWARE CHECK
# ============================================================

PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
BOARD=$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)

echo "============================================================"
echo "MSI GF63 THIN 11SC AUTOMATIC FAN CONTROL"
echo "============================================================"
echo "Detected product: $PRODUCT"
echo "Detected board  : $BOARD"
echo "============================================================"

if [ "$ALLOW_UNTESTED" != "1" ]; then

    if [ "$PRODUCT" != "$EXPECTED_PRODUCT" ]; then
        echo
        echo "[ERROR] Unsupported laptop."
        echo
        echo "Expected product:"
        echo "$EXPECTED_PRODUCT"
        echo
        echo "Detected product:"
        echo "$PRODUCT"
        echo
        echo "No EC writes were performed."
        exit 1
    fi

    if [ "$BOARD" != "$EXPECTED_BOARD" ]; then
        echo
        echo "[ERROR] Unsupported motherboard."
        echo
        echo "Expected board:"
        echo "$EXPECTED_BOARD"
        echo
        echo "Detected board:"
        echo "$BOARD"
        echo
        echo "No EC writes were performed."
        exit 1
    fi

fi

# ============================================================
# CHECK EC HELPER
# ============================================================

if [[ "$EC_HELPER" == */* ]]; then

    if [ ! -x "$EC_HELPER" ]; then
        echo "[ERROR] ec_helper not executable:"
        echo "$EC_HELPER"
        exit 1
    fi

else

    if ! command -v "$EC_HELPER" >/dev/null 2>&1; then
        echo "[ERROR] ec_helper not found."
        echo
        echo "Install ec_helper before running this controller."
        exit 1
    fi

    EC_HELPER=$(command -v "$EC_HELPER")

fi

echo "ec_helper: $EC_HELPER"

# ============================================================
# VALIDATION
# ============================================================

valid_byte() {
    local value="$1"

    [[ "$value" =~ ^[0-9]+$ ]] &&
    [ "$value" -ge 0 ] &&
    [ "$value" -le 255 ]
}

valid_temperature() {
    local value="$1"

    [[ "$value" =~ ^[0-9]+$ ]] &&
    [ "$value" -ge 0 ] &&
    [ "$value" -le 120 ]
}

# ============================================================
# EC READ / WRITE
# ============================================================

read_ec() {
    "$EC_HELPER" read "$1" 2>/dev/null
}

write_ec() {
    local address="$1"
    local value="$2"

    "$EC_HELPER" write "$address" "$value"
}

# ============================================================
# BACKUP ORIGINAL SETTINGS
# ============================================================

backup_original_settings() {

    ORIGINAL_MODE=$(read_ec "$FAN_MODE_ADDR")
    ORIGINAL_BOOST=$(read_ec "$BOOST_ADDR")

    if ! valid_byte "$ORIGINAL_MODE"; then
        echo "[ERROR] Invalid original fan mode:"
        echo "$ORIGINAL_MODE"
        exit 1
    fi

    if ! valid_byte "$ORIGINAL_BOOST"; then
        echo "[ERROR] Invalid Cooler Boost register:"
        echo "$ORIGINAL_BOOST"
        exit 1
    fi

    CPU_ORIGINAL=()
    GPU_ORIGINAL=()

    local addr
    local value

    for addr in "${CPU_SPEED_REGS[@]}"; do

        value=$(read_ec "$addr")

        if ! valid_byte "$value"; then
            echo "[ERROR] Could not read CPU fan curve register $addr"
            exit 1
        fi

        CPU_ORIGINAL+=("$value")

    done

    for addr in "${GPU_SPEED_REGS[@]}"; do

        value=$(read_ec "$addr")

        if ! valid_byte "$value"; then
            echo "[ERROR] Could not read GPU fan curve register $addr"
            exit 1
        fi

        GPU_ORIGINAL+=("$value")

    done

    SETTINGS_BACKED_UP=1

    echo
    echo "[BACKUP] Original MSI fan settings saved."
    echo "[BACKUP] Fan mode      : $ORIGINAL_MODE"
    echo "[BACKUP] Boost register: $ORIGINAL_BOOST"
}

# ============================================================
# COOLER BOOST OFF
# ============================================================

boost_off() {

    local cur
    local new

    cur=$(read_ec "$BOOST_ADDR")

    if ! valid_byte "$cur"; then
        log "[ERROR] Cannot read Cooler Boost register."
        return 1
    fi

    new=$((cur & 127))

    if [ "$new" -ne "$cur" ]; then
        write_ec "$BOOST_ADDR" "$new" >/dev/null
    fi
}

# ============================================================
# COOLER BOOST ON
# ============================================================

boost_on() {

    local cur
    local new
    local verify

    cur=$(read_ec "$BOOST_ADDR")

    if ! valid_byte "$cur"; then
        log "[ERROR] Cannot read Cooler Boost register."
        return 1
    fi

    new=$((cur | 128))

    write_ec "$BOOST_ADDR" "$new" >/dev/null

    verify=$(read_ec "$BOOST_ADDR")

    if ! valid_byte "$verify"; then
        log "[ERROR] Could not verify Cooler Boost."
        return 1
    fi

    if [ $((verify & 128)) -eq 0 ]; then
        log "[ERROR] Cooler Boost verification failed."
        return 1
    fi

    log "Cooler Boost ON ($cur -> $verify)"
}

# ============================================================
# SET FIXED FAN SPEED
# ============================================================

set_fixed_speed() {

    local speed="$1"
    local addr

    boost_off || return 1

    for addr in "${CPU_SPEED_REGS[@]}"; do
        write_ec "$addr" "$speed" >/dev/null
    done

    for addr in "${GPU_SPEED_REGS[@]}"; do
        write_ec "$addr" "$speed" >/dev/null
    done

    write_ec "$FAN_MODE_ADDR" "$ADVANCED_MODE" >/dev/null
}

# ============================================================
# AUTO MODE
# ============================================================

set_auto() {

    if [ "$STATE" = "AUTO" ]; then
        return
    fi

    boost_off || return

    local i

    for i in "${!CPU_SPEED_REGS[@]}"; do

        write_ec \
            "${CPU_SPEED_REGS[$i]}" \
            "${CPU_ORIGINAL[$i]}" \
            >/dev/null

    done

    for i in "${!GPU_SPEED_REGS[@]}"; do

        write_ec \
            "${GPU_SPEED_REGS[$i]}" \
            "${GPU_ORIGINAL[$i]}" \
            >/dev/null

    done

    write_ec "$FAN_MODE_ADDR" "$AUTO_MODE" >/dev/null

    STATE="AUTO"

    log "FAN -> AUTO"
}

# ============================================================
# 50%
# ============================================================

set_50() {

    if [ "$STATE" = "50" ]; then
        return
    fi

    if set_fixed_speed 50; then

        STATE="50"

        log "FAN -> 50%"

    fi
}

# ============================================================
# 75%
# ============================================================

set_75() {

    if [ "$STATE" = "75" ]; then
        return
    fi

    if set_fixed_speed 75; then

        STATE="75"

        log "FAN -> 75%"

    fi
}

# ============================================================
# 90%
# ============================================================

set_90() {

    if [ "$STATE" = "90" ]; then
        return
    fi

    if set_fixed_speed 90; then

        STATE="90"

        log "FAN -> 90%"

    fi
}

# ============================================================
# 100% COOLER BOOST
# ============================================================

set_100() {

    if [ "$STATE" = "100" ]; then
        return
    fi

    if boost_on; then

        STATE="100"

        log "FAN -> 100% COOLER BOOST"

    fi
}

# ============================================================
# RESTORE ORIGINAL MSI SETTINGS
# ============================================================

restore_original_settings() {

    if [ "$SETTINGS_BACKED_UP" -ne 1 ]; then
        return
    fi

    echo
    echo "[STOP] Restoring original MSI fan settings..."

    local i

    for i in "${!CPU_SPEED_REGS[@]}"; do

        write_ec \
            "${CPU_SPEED_REGS[$i]}" \
            "${CPU_ORIGINAL[$i]}" \
            >/dev/null 2>&1 || true

    done

    for i in "${!GPU_SPEED_REGS[@]}"; do

        write_ec \
            "${GPU_SPEED_REGS[$i]}" \
            "${GPU_ORIGINAL[$i]}" \
            >/dev/null 2>&1 || true

    done

    if valid_byte "$ORIGINAL_MODE"; then

        write_ec \
            "$FAN_MODE_ADDR" \
            "$ORIGINAL_MODE" \
            >/dev/null 2>&1 || true

    fi

    if valid_byte "$ORIGINAL_BOOST"; then

        write_ec \
            "$BOOST_ADDR" \
            "$ORIGINAL_BOOST" \
            >/dev/null 2>&1 || true

    fi

    SETTINGS_BACKED_UP=0

    echo "[RESTORE] Original settings restored."
}

# ============================================================
# CLEANUP
# ============================================================

cleanup() {

    trap - EXIT INT TERM

    restore_original_settings
}

trap cleanup EXIT INT TERM

# ============================================================
# START
# ============================================================

backup_original_settings

boost_off

write_ec "$FAN_MODE_ADDR" "$AUTO_MODE" >/dev/null

STATE="AUTO"

echo
echo "============================================================"
echo "MSI GF63 THIN 11SC AUTOMATIC FAN CONTROL"
echo "============================================================"
echo
echo "Hardware:"
echo "Product : $PRODUCT"
echo "Board   : $BOARD"
echo
echo "Fan speed-up thresholds:"
echo
echo "AUTO"
echo "50%  : CPU >= ${CPU_50}°C OR GPU >= ${GPU_50}°C"
echo "75%  : CPU >= ${CPU_75}°C OR GPU >= ${GPU_75}°C"
echo "90%  : CPU >= ${CPU_90}°C OR GPU >= ${GPU_90}°C"
echo "100% : CPU >= ${CPU_100}°C OR GPU >= ${GPU_100}°C"
echo
echo "Fan speed-down thresholds:"
echo
echo "100 -> 90 : CPU <= ${CPU_100_DOWN}°C AND GPU <= ${GPU_100_DOWN}°C"
echo "90  -> 75 : CPU <= ${CPU_90_DOWN}°C AND GPU <= ${GPU_90_DOWN}°C"
echo "75  -> 50 : CPU <= ${CPU_75_DOWN}°C AND GPU <= ${GPU_75_DOWN}°C"
echo "50  -> AUTO: CPU <= ${CPU_AUTO}°C AND GPU <= ${GPU_AUTO}°C"
echo
echo "Polling interval: ${POLL_SECONDS}s"
echo "Configuration   : $CONFIG_FILE"
echo
echo "============================================================"
echo

# ============================================================
# MAIN LOOP
# ============================================================

while true; do

    CPU=$(read_ec "$CPU_TEMP_ADDR")
    GPU=$(read_ec "$GPU_TEMP_ADDR")

    # --------------------------------------------------------
    # VALIDATE TEMPERATURE READINGS
    # --------------------------------------------------------

    if ! valid_temperature "$CPU"; then

        log "[WARNING] Invalid CPU temperature: '$CPU'"

        sleep "$POLL_SECONDS"

        continue
    fi

    if ! valid_temperature "$GPU"; then

        log "[WARNING] Invalid GPU temperature: '$GPU'"

        sleep "$POLL_SECONDS"

        continue
    fi

    log "CPU=${CPU}°C GPU=${GPU}°C FAN=${STATE}"

    # ========================================================
    # TEMPERATURE RISING
    # ========================================================

    if [ "$CPU" -ge "$CPU_100" ] || \
       [ "$GPU" -ge "$GPU_100" ]; then

        set_100

    elif [ "$CPU" -ge "$CPU_90" ] || \
         [ "$GPU" -ge "$GPU_90" ]; then

        if [ "$STATE" != "100" ]; then
            set_90
        fi

    elif [ "$CPU" -ge "$CPU_75" ] || \
         [ "$GPU" -ge "$GPU_75" ]; then

        if [ "$STATE" != "90" ] && \
           [ "$STATE" != "100" ]; then

            set_75

        fi

    elif [ "$CPU" -ge "$CPU_50" ] || \
         [ "$GPU" -ge "$GPU_50" ]; then

        if [ "$STATE" = "AUTO" ]; then
            set_50
        fi

    fi

    # ========================================================
    # TEMPERATURE FALLING
    # ========================================================

    if [ "$STATE" = "100" ]; then

        if [ "$CPU" -le "$CPU_100_DOWN" ] && \
           [ "$GPU" -le "$GPU_100_DOWN" ]; then

            set_90

        fi

    elif [ "$STATE" = "90" ]; then

        if [ "$CPU" -le "$CPU_90_DOWN" ] && \
           [ "$GPU" -le "$GPU_90_DOWN" ]; then

            set_75

        fi

    elif [ "$STATE" = "75" ]; then

        if [ "$CPU" -le "$CPU_75_DOWN" ] && \
           [ "$GPU" -le "$GPU_75_DOWN" ]; then

            set_50

        fi

    elif [ "$STATE" = "50" ]; then

        if [ "$CPU" -le "$CPU_AUTO" ] && \
           [ "$GPU" -le "$GPU_AUTO" ]; then

            set_auto

        fi

    fi

    sleep "$POLL_SECONDS"

done
