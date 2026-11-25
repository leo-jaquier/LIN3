#!/usr/bin/env bash
set -euo pipefail

NTP_PRIMARY="10.0.1.10"
NTP_FALLBACK="10.0.1.11"
MINPOLL=2
MAXPOLL=2
CONF="/etc/chrony/chrony.conf"
LOG_DIR="/var/log/chrony"
ERR_LOG="/var/log/chrony-errors.log"
RSYSLOG_RULE="/etc/rsyslog.d/30-chrony-errors.conf"
LOGROTATE_RULE="/etc/logrotate.d/chrony-errors"
BACKUP="/var/backups/chrony-etc-$(date +%Y%m%d-%H%M%S).tar.gz"

if [[ $EUID -ne 0 ]]; then
    echo "Run as root (sudo $0)" >&2
    exit 1
fi

echo "==> Updating system"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get -y install chrony rsyslog

echo "==> Setting timezone"
timedatectl set-timezone Europe/Zurich

echo "==> Backing up /etc/chrony to $BACKUP"
tar czf "$BACKUP" -C /etc chrony

echo "==> Removing old sources, snippets and backups"
rm -f /etc/chrony/conf.d/*.conf /etc/chrony/sources.d/*.sources /etc/chrony/*.bak.*

echo "==> Writing clean $CONF"
cat > "$CONF" <<EOF
server ${NTP_PRIMARY}  iburst prefer minpoll ${MINPOLL} maxpoll ${MAXPOLL}
server ${NTP_FALLBACK} iburst minpoll ${MINPOLL} maxpoll ${MAXPOLL}

keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony

logdir ${LOG_DIR}
log tracking measurements statistics
logchange 0.5

maxupdateskew 100.0
rtcsync
makestep 1 -1
leapsectz right/UTC
EOF

mkdir -p "$LOG_DIR"

echo "==> Setting up filtered error log $ERR_LOG"
cat > "$RSYSLOG_RULE" <<EOF
if \$programname == 'chronyd' and \$syslogseverity <= 4 then ${ERR_LOG}
EOF

cat > "$LOGROTATE_RULE" <<EOF
${ERR_LOG} {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF

systemctl enable rsyslog
systemctl restart rsyslog

echo "==> Restarting chrony"
systemctl enable chrony
systemctl restart chrony

sleep 3
chronyc burst 4/4 >/dev/null
sleep 3
chronyc makestep

echo "==> Status"
cat "$CONF"
ls -l /etc/chrony /etc/chrony/conf.d /etc/chrony/sources.d
chronyc sources -v
chronyc tracking
ls -l "$LOG_DIR"
ls -l "$ERR_LOG" 2>/dev/null || echo "$ERR_LOG not created yet (no warnings so far)"
