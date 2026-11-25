#!/usr/bin/env bash
# =============================================================================
# Installation automatique d'un serveur NTP (Chrony) sur Debian 13
# - Sources : 0..3.ie.pool.ntp.org (déclarées comme "server", pas "pool")
# - Pas d'iburst, accès restreint au sous-réseau, logs activés
# Usage : sudo ./setup-ntp.sh [SOUS_RESEAU_CIDR]
# Exemple : sudo ./setup-ntp.sh 10.0.1.0/24
# =============================================================================
set -euo pipefail

ALLOW_NET="${1:-10.0.1.0/28}"
TIMEZONE="Europe/Zurich"
CONF="/etc/chrony/chrony.conf"
BACKUP_DIR="/var/backups"

if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être lancé en root : sudo $0" >&2
    exit 1
fi

echo "==> [1/7] Mise à jour des paquets"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "==> [2/7] Installation de chrony"
DEBIAN_FRONTEND=noninteractive apt-get install -y chrony

echo "==> [3/7] Fuseau horaire : ${TIMEZONE}"
timedatectl set-timezone "${TIMEZONE}"

# Un seul démon de synchronisation à la fois
if systemctl list-unit-files | grep -q '^systemd-timesyncd'; then
    systemctl disable --now systemd-timesyncd 2>/dev/null || true
fi

echo "==> [4/7] Sauvegarde et écriture de la configuration"
# Le DNS est nécessaire pour résoudre les serveurs NTP
if ! getent hosts 0.ie.pool.ntp.org >/dev/null; then
    echo "ATTENTION : 0.ie.pool.ntp.org n'est pas résolu, vérifier le DNS (/etc/resolv.conf)" >&2
fi

# Sauvegarde HORS de /etc/chrony pour ne pas laisser de trace dans la conf
if [[ -f "${CONF}" ]]; then
    cp "${CONF}" "${BACKUP_DIR}/chrony.conf.orig-$(date +%Y%m%d-%H%M%S)"
fi

# Configuration minimale : uniquement les directives nécessaires, sans commentaires
cat > "${CONF}" <<EOF
server 0.ie.pool.ntp.org
server 1.ie.pool.ntp.org
server 2.ie.pool.ntp.org
server 3.ie.pool.ntp.org
allow ${ALLOW_NET}
driftfile /var/lib/chrony/chrony.drift
makestep 1 3
rtcsync
logdir /var/log/chrony
log tracking measurements statistics
EOF

echo "==> [5/7] Pare-feu : ouverture UDP 123 pour ${ALLOW_NET} (si ufw actif)"
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow from "${ALLOW_NET}" to any port 123 proto udp
else
    echo "    ufw absent ou inactif, rien à faire."
fi

echo "==> [6/7] Redémarrage et activation du service"
systemctl restart chrony
systemctl enable chrony
sleep 5
systemctl --no-pager status chrony || true
echo "==> En attente de la synchronisation (5 min)"
sleep 300

echo "==> [7/7] Vérifications"
echo "--- Sources ---"
chronyc sources -v || true
echo "--- Tracking (stratum attendu : 2, une fois synchronisé) ---"
chronyc tracking | grep -E 'Reference ID|Stratum|Leap status' || true
echo "--- Port en écoute ---"
ss -ulnp | grep ':123 ' || echo "ATTENTION : rien n'écoute sur UDP 123"
echo "--- allow ---"
grep -rn '^allow' /etc/chrony/ || echo "ATTENTION : aucune directive allow"
echo "--- iburst actif (attendu : aucun résultat) ---"
grep -rnE '^[^#]*iburst' /etc/chrony/ || echo "OK : aucun iburst"
echo "--- Fuseau horaire ---"
timedatectl | grep -E 'Time zone|synchronized'

echo
echo "Terminé. Les logs seront dans /var/log/chrony/ après environ 1 minute."
