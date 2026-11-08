#!/usr/bin/env bash
set -u

# ============================================================
# MSI GF63 THIN 11SC / MS-16R6
# AUTOMATIC MULTI-STAGE FAN CONTROLLER
# ============================================================

EC_HELPER="${EC_HELPER:-ec_helper}"

BOOST_ADDR=0x98
FAN_MODE_ADDR=0xd4
CPU_TEMP_ADDR=0x68
GPU_TEMP_ADDR=0x80

AUTO_MODE=13
ADVANCED_MODE=141

# ============================================================
# FAN SPEED-UP THRESHOLDS
# ============================================================

CPU_50=60
GPU_50=60

CPU_75=70
GPU_75=70

CPU_90=75
GPU_90=72

CPU_100=80
GPU_100=75

# ============================================================
# FAN SPEED-DOWN THRESHOLDS
# ============================================================

CPU_100_DOWN=77
GPU_100_DOWN=72

CPU_90_DOWN=72
GPU_90_DOWN=68

CPU_75_DOWN=65
GPU_75_DOWN=65

CPU_AUTO=45
GPU_AUTO=45

POLL_SECONDS=5

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

STATE="AUTO"

CPU_ORIGINAL=()
GPU_ORIGINAL=()

ORIGINAL_MODE=""
ORIGINAL_BOOST=""

# ============================================================
# HELPERS
# ============================================================

read_ec() {
    "$EC_HELPER" read "$1" 2>/dev/null
}

write_ec() {
    "$EC_HELPER" write "$1" "$2"
}

valid_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# ============================================================
# BACKUP ORIGINAL MSI SETTINGS
# ============================================================

backup_original_settings() {
    ORIGINAL_MODE=$(read_ec "$FAN_MODE_ADDR")
    ORIGINAL_BOOST=$(read_ec "$BOOST_ADDR")

    CPU_ORIGINAL=()
    GPU_ORIGINAL=()

    for addr in "${CPU_SPEED_REGS[@]}"; do
        CPU_ORIGINAL+=("$(read_ec "$addr")")
    done

    for addr in "${GPU_SPEED_REGS[@]}"; do
        GPU_ORIGINAL+=("$(read_ec "$addr")")
    done

    echo "[BACKUP] Original MSI fan settings saved."
    echo "[BACKUP] Fan mode: $ORIGINAL_MODE"
    echo "[BACKUP] Boost register: $ORIGINAL_BOOST"
}

# ============================================================
# COOLER BOOST
# ============================================================

boost_on() {
    cur=$(read_ec "$BOOST_ADDR")

    if ! valid_number "$cur"; then
        echo "[ERROR] Cannot read Cooler Boost register."
        return
    fi

    new=$((cur | 128))

    write_ec "$BOOST_ADDR" "$new"

    echo "$(date '+%H:%M:%S') Cooler Boost ON ($cur -> $new)"
}

boost_off() {
    cur=$(read_ec "$BOOST_ADDR")

    if ! valid_number "$cur"; then
        echo "[ERROR] Cannot read Cooler Boost register."
        return
    fi

    new=$((cur & 127))

    write_ec "$BOOST_ADDR" "$new"
}

# ============================================================
# FIXED FAN SPEED
# ============================================================

set_fixed_speed() {
    speed=$1

    boost_off

    for addr in "${CPU_SPEED_REGS[@]}"; do
        write_ec "$addr" "$speed"
    done

    for addr in "${GPU_SPEED_REGS[@]}"; do
        write_ec "$addr" "$speed"
    done

    write_ec "$FAN_MODE_ADDR" "$ADVANCED_MODE"
}

# ============================================================
# AUTO MODE
# ============================================================

set_auto() {
    if [ "$STATE" = "AUTO" ]; then
        return
    fi

    boost_off

    for i in "${!CPU_SPEED_REGS[@]}"; do
        write_ec \
            "${CPU_SPEED_REGS[$i]}" \
            "${CPU_ORIGINAL[$i]}"
    done

    for i in "${!GPU_SPEED_REGS[@]}"; do
        write_ec \
            "${GPU_SPEED_REGS[$i]}" \
            "${GPU_ORIGINAL[$i]}"
    done

    write_ec "$FAN_MODE_ADDR" "$AUTO_MODE"

    STATE="AUTO"

    echo "$(date '+%H:%M:%S') FAN -> AUTO"
}

# ============================================================
# 50%
# ============================================================

set_50() {
    if [ "$STATE" = "50" ]; then
        return
    fi

    set_fixed_speed 50

    STATE="50"

    echo "$(date '+%H:%M:%S') FAN -> 50%"
}

# ============================================================
# 75%
# ============================================================

set_75() {
    if [ "$STATE" = "75" ]; then
        return
    fi

    set_fixed_speed 75

    STATE="75"

    echo "$(date '+%H:%M:%S') FAN -> 75%"
}

# ============================================================
# 90%
# ============================================================

set_90() {
    if [ "$STATE" = "90" ]; then
        return
    fi

    set_fixed_speed 90

    STATE="90"

    echo "$(date '+%H:%M:%S') FAN -> 90%"
}

# ============================================================
# 100% COOLER BOOST
# ============================================================

set_100() {
    if [ "$STATE" = "100" ]; then
        return
    fi

    boost_on

    STATE="100"

    echo "$(date '+%H:%M:%S') FAN -> 100% COOLER BOOST"
}

# ============================================================
# RESTORE ORIGINAL SETTINGS
# ============================================================

restore_original_settings() {
    echo ""
    echo "[STOP] Restoring original MSI fan settings..."

    if [ "${#CPU_ORIGINAL[@]}" -eq "${#CPU_SPEED_REGS[@]}" ]; then
        for i in "${!CPU_SPEED_REGS[@]}"; do
            write_ec \
                "${CPU_SPEED_REGS[$i]}" \
                "${CPU_ORIGINAL[$i]}"
        done
    fi

    if [ "${#GPU_ORIGINAL[@]}" -eq "${#GPU_SPEED_REGS[@]}" ]; then
        for i in "${!GPU_SPEED_REGS[@]}"; do
            write_ec \
                "${GPU_SPEED_REGS[$i]}" \
                "${GPU_ORIGINAL[$i]}"
        done
    fi

    if valid_number "$ORIGINAL_MODE"; then
        write_ec "$FAN_MODE_ADDR" "$ORIGINAL_MODE"
    fi

    if valid_number "$ORIGINAL_BOOST"; then
        write_ec "$BOOST_ADDR" "$ORIGINAL_BOOST"
    fi

    echo "[RESTORE] Original settings restored."
}

cleanup() {
    restore_original_settings
    exit 0
}

trap cleanup INT TERM

# ============================================================
# START
# ============================================================

if ! command -v "$EC_HELPER" >/dev/null 2>&1; then
    echo "[ERROR] ec_helper not found."
    exit 1
fi

backup_original_settings

boost_off
write_ec "$FAN_MODE_ADDR" "$AUTO_MODE"

echo ""
echo "============================================================"
echo "MSI GF63 THIN 11SC AUTOMATIC FAN CONTROL"
echo "============================================================"
echo "AUTO : CPU <= 45°C AND GPU <= 45°C"
echo "50%  : CPU >= 60°C OR GPU >= 60°C"
echo "75%  : CPU >= 70°C OR GPU >= 70°C"
echo "90%  : CPU >= 75°C OR GPU >= 72°C"
echo "100% : CPU >= 80°C OR GPU >= 75°C"
echo "------------------------------------------------------------"
echo "100 -> 90 : CPU <= 77°C AND GPU <= 72°C"
echo "90  -> 75 : CPU <= 72°C AND GPU <= 68°C"
echo "75  -> 50 : CPU <= 65°C AND GPU <= 65°C"
echo "50  -> AUTO: CPU <= 45°C AND GPU <= 45°C"
echo "------------------------------------------------------------"
echo "Polling every ${POLL_SECONDS} seconds"
echo "============================================================"
echo ""

# ============================================================
# MAIN LOOP
# ============================================================

while true; do

    CPU=$(read_ec "$CPU_TEMP_ADDR")
    GPU=$(read_ec "$GPU_TEMP_ADDR")

    if ! valid_number "$CPU"; then
        echo "[WARNING] Invalid CPU temperature: $CPU"
        sleep "$POLL_SECONDS"
        continue
    fi

    if ! valid_number "$GPU"; then
        echo "[WARNING] Invalid GPU temperature: $GPU"
        sleep "$POLL_SECONDS"
        continue
    fi

    echo "$(date '+%H:%M:%S') CPU=${CPU}°C GPU=${GPU}°C FAN=${STATE}"

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
