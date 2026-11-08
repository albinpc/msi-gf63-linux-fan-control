#!/usr/bin/env bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Please run:"
    echo "sudo ./uninstall.sh"
    exit 1
fi

echo "Stopping MSI GF63 fan controller..."

systemctl disable --now msi-gf63-fan-control.service 2>/dev/null || true

rm -f /etc/systemd/system/msi-gf63-fan-control.service
rm -f /usr/local/sbin/msi-gf63-fan-control

systemctl daemon-reload

echo
echo "MSI GF63 fan controller removed."
echo
echo "Configuration was preserved at:"
echo "/etc/default/msi-gf63-fan-control"
