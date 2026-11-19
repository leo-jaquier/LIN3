#!/usr/bin/env bash
# Update Ubuntu, set timezone to Europe/Zurich, point chrony at internal NTP servers only.
set -euo pipefail

NTP_PRIMARY="10.0.1.10"
NTP_FALLBACK="10.0.1.11"
CONF="/etc/chrony/chrony.conf"
SRC_DIR="/etc/chrony/sources.d"
CONF_DIR="/etc/chrony/conf.d"
SRC_FILE="$SRC_DIR/local-ntp.sources"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo $0)" >&2
    exit 1
fi

echo "==> Updating system"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade

echo "==> Setting timezone"
timedatectl set-timezone Europe/Zurich

echo "==> Configuring chrony"
mkdir -p "$SRC_DIR"
cp -a "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"

# Disable every other time source: pools, servers, and extra sourcedirs (DHCP/cloud-provided NTP)
disable_sources() {
    sed -i -E 's/^(pool|server|peer|sourcedir)[[:space:]]/#&/' "$1"
}
disable_sources "$CONF"
for f in "$SRC_DIR"/*.sources "$CONF_DIR"/*.conf; do
    [[ -e "$f" && "$f" != "$SRC_FILE" ]] && disable_sources "$f"
done

# Only read our own sources directory
grep -q "^sourcedir $SRC_DIR" "$CONF" || echo "sourcedir $SRC_DIR" >> "$CONF"

cat > "$SRC_FILE" <<EOF
server ${NTP_PRIMARY}  iburst prefer minpoll 4 maxpoll 6
server ${NTP_FALLBACK} iburst minpoll 4 maxpoll 6
EOF

echo "==> Restarting chrony"
systemctl enable chrony
systemctl restart chrony

sleep 3
chronyc burst 4/4 >/dev/null
sleep 3
chronyc makestep

echo "==> Status"
chronyc sources -v
chronyc tracking
