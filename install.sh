#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "Please run:"
    echo "sudo ./install.sh"
    exit 1
fi

echo "========================================"
echo "MSI GF63 Fan Controller Installer"
echo "========================================"

echo "[1/5] Checking hardware compatibility..."

"$SCRIPT_DIR/check_compatibility.sh"

echo "[2/5] Installing fan controller..."

install -m 0755 \
    "$SCRIPT_DIR/fan_auto.sh" \
    /usr/local/sbin/msi-gf63-fan-control

echo "[3/5] Installing configuration..."

if [ ! -f /etc/default/msi-gf63-fan-control ]; then

    install -m 0644 \
        "$SCRIPT_DIR/config.example" \
        /etc/default/msi-gf63-fan-control

else
    echo "Existing configuration preserved."
fi

echo "[4/5] Installing systemd service..."

install -m 0644 \
    "$SCRIPT_DIR/msi-gf63-fan-control.service" \
    /etc/systemd/system/msi-gf63-fan-control.service

systemctl daemon-reload

echo "[5/5] Enabling service..."

systemctl enable --now msi-gf63-fan-control.service

echo
echo "Installation completed."
echo
echo "Check status:"
echo "systemctl status msi-gf63-fan-control"
echo
echo "Watch logs:"
echo "sudo journalctl -u msi-gf63-fan-control -f"
