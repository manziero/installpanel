#!/usr/bin/env bash
set -Eeuo pipefail
set +H

# ============================================================
# PTERODACTYL AUTO INSTALLER
# Panel + Optional Wings
#
# INPUT SEMUA DI AWAL
#
# Supported:
# Ubuntu     22.04 / 24.04 / 26.04
# Debian     10 / 11 / 12 / 13
# Rocky      8
# AlmaLinux  8 / 9
#
# Anonymous telemetry: NO
# ============================================================

INSTALLER_URL="https://pterodactyl-installer.se"
LOG_FILE="/var/log/pterodactyl-auto-installer.log"
TMP_INSTALLER="/tmp/pterodactyl-installer.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

ok() {
    echo -e "${GREEN}[✓]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

die() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

# ============================================================
# ROOT
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    die "Jalankan sebagai root."
fi

# ============================================================
# OS
# ============================================================

[[ -f /etc/os-release ]] || die "Tidak dapat mendeteksi OS."

source /etc/os-release

OS="${ID:-}"
VERSION="${VERSION_ID:-}"
PRETTY="${PRETTY_NAME:-$OS $VERSION}"

case "${OS}:${VERSION}" in
    ubuntu:22.04|ubuntu:24.04|ubuntu:26.04)
        ;;
    debian:10|debian:11|debian:12|debian:13)
        ;;
    rocky:8)
        ;;
    almalinux:8|almalinux:9)
        ;;
    *)
        die "OS tidak didukung: ${PRETTY}"
        ;;
esac

# ============================================================
# ARCH
# ============================================================

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64|aarch64|arm64)
        ;;
    *)
        die "Architecture tidak didukung: ${ARCH}"
        ;;
esac

# ============================================================
# DOMAIN VALIDATION
# ============================================================

valid_domain() {
    local d
    d="$(printf '%s' "$1" | tr -d '\r' | xargs)"

    [[ "$d" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

# ============================================================
# HEADER
# ============================================================

clear

echo
echo "============================================================"
echo "              PTERODACTYL AUTO INSTALLER"
echo "============================================================"
echo
echo "OS          : ${PRETTY}"
echo "Architecture: ${ARCH}"
echo
echo "Anonymous telemetry : NO"
echo "SSL                  : YES"
echo
echo "============================================================"
echo

# ============================================================
# PANEL DOMAIN
# ============================================================

while true; do

    read -rp "Panel domain: " PANEL_DOMAIN

    PANEL_DOMAIN="$(printf '%s' "$PANEL_DOMAIN" | tr -d '\r' | xargs)"

    if valid_domain "$PANEL_DOMAIN"; then
        break
    fi

    warn "Domain tidak valid. Contoh: panel.example.com"

done

# ============================================================
# WINGS Y/N
# ============================================================

while true; do

    read -rp "Install Wings/Node? [Y/n]: " INSTALL_WINGS

    INSTALL_WINGS="${INSTALL_WINGS:-y}"

    case "$INSTALL_WINGS" in
        y|Y|n|N)
            break
            ;;
        *)
            warn "Masukkan Y atau N."
            ;;
    esac

done

# ============================================================
# NODE DOMAIN
# ============================================================

NODE_DOMAIN=""

if [[ "$INSTALL_WINGS" =~ ^[Yy]$ ]]; then

    while true; do

        read -rp "Node domain: " NODE_DOMAIN

        NODE_DOMAIN="$(printf '%s' "$NODE_DOMAIN" | tr -d '\r' | xargs)"

        if valid_domain "$NODE_DOMAIN"; then
            break
        fi

        warn "Domain tidak valid. Contoh: node.example.com"

    done

fi

# ============================================================
# ADMIN EMAIL
# ============================================================

while true; do

    read -rp "Admin email/Gmail: " ADMIN_EMAIL

    ADMIN_EMAIL="$(printf '%s' "$ADMIN_EMAIL" | tr -d '\r' | xargs)"

    if [[ "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
        break
    fi

    warn "Email tidak valid."

done

# ============================================================
# ADMIN USERNAME
# ============================================================

while true; do

    read -rp "Admin username: " ADMIN_USERNAME

    ADMIN_USERNAME="$(printf '%s' "$ADMIN_USERNAME" | tr -d '\r' | xargs)"

    if [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
        break
    fi

    warn "Username tidak valid."

done

# ============================================================
# ADMIN NAME
# ============================================================

read -rp "Admin first name [Admin]: " ADMIN_FIRSTNAME
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-Admin}"

read -rp "Admin last name [User]: " ADMIN_LASTNAME
ADMIN_LASTNAME="${ADMIN_LASTNAME:-User}"

# ============================================================
# ADMIN PASSWORD
# ============================================================

while true; do

    read -rsp "Admin password: " ADMIN_PASSWORD
    echo

    if [[ ${#ADMIN_PASSWORD} -lt 8 ]]; then
        warn "Password minimal 8 karakter."
        continue
    fi

    read -rsp "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
    echo

    if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
        warn "Password tidak sama."
        continue
    fi

    break

done

# ============================================================
# WINGS AUTO DEPLOY COMMAND
# ============================================================

WINGS_COMMAND=""

if [[ "$INSTALL_WINGS" =~ ^[Yy]$ ]]; then

    echo
    echo "============================================================"
    echo "                 WINGS AUTO DEPLOY"
    echo "============================================================"
    echo
    echo "Paste command Auto-Deploy dari:"
    echo
    echo "Admin -> Nodes -> pilih Node -> Configuration"
    echo
    echo "Jika belum punya command, tekan ENTER untuk skip."
    echo

    read -rsp "Wings Auto-Deploy command/token: " WINGS_COMMAND
    echo

fi

# ============================================================
# SUMMARY
# ============================================================

echo
echo "============================================================"
echo "                    KONFIGURASI"
echo "============================================================"
echo
echo "Panel domain : https://${PANEL_DOMAIN}"
echo "Wings        : ${INSTALL_WINGS}"
echo

if [[ -n "$NODE_DOMAIN" ]]; then
    echo "Node domain  : ${NODE_DOMAIN}"
fi

echo "Admin email  : ${ADMIN_EMAIL}"
echo "Admin user   : ${ADMIN_USERNAME}"
echo "Anonymous    : NO"
echo "SSL          : YES"
echo
echo "============================================================"
echo

read -rp "Mulai instalasi? [y/N]: " START

if [[ ! "$START" =~ ^[Yy]$ ]]; then
    warn "Instalasi dibatalkan."
    exit 0
fi

# ============================================================
# LOG
# ============================================================

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# CURL
# ============================================================

if ! command -v curl >/dev/null 2>&1; then

    info "Installing curl..."

    case "$OS" in
        ubuntu|debian)

            export DEBIAN_FRONTEND=noninteractive

            apt-get update

            apt-get install -y \
                curl \
                ca-certificates

            ;;

        rocky|almalinux)

            dnf install -y \
                curl \
                ca-certificates

            ;;

    esac

fi

command -v curl >/dev/null 2>&1 || die "curl gagal diinstall."

# ============================================================
# SERVER IP
# ============================================================

SERVER_IP="$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || true)"

echo
info "VPS IP: ${SERVER_IP:-unknown}"

if [[ -n "$SERVER_IP" ]]; then

    echo
    echo "DNS yang harus diarahkan:"
    echo
    echo "  ${PANEL_DOMAIN} -> ${SERVER_IP}"

    if [[ -n "$NODE_DOMAIN" ]]; then
        echo "  ${NODE_DOMAIN}  -> ${SERVER_IP}"
    fi

    echo

fi

read -rp "DNS sudah diarahkan? [y/N]: " DNS_OK

if [[ ! "$DNS_OK" =~ ^[Yy]$ ]]; then
    warn "Instalasi dihentikan sampai DNS diarahkan."
    exit 0
fi

# ============================================================
# DOWNLOAD UPSTREAM INSTALLER
# ============================================================

info "Downloading Pterodactyl installer..."

rm -f "$TMP_INSTALLER"

curl -fsSL \
    "$INSTALLER_URL" \
    -o "$TMP_INSTALLER"

[[ -s "$TMP_INSTALLER" ]] || die "Gagal download installer."

chmod +x "$TMP_INSTALLER"

ok "Installer downloaded."

# ============================================================
# PANEL VARIABLES
# ============================================================

export FQDN="$PANEL_DOMAIN"
export EMAIL="$ADMIN_EMAIL"

export user_email="$ADMIN_EMAIL"
export user_username="$ADMIN_USERNAME"
export user_firstname="$ADMIN_FIRSTNAME"
export user_lastname="$ADMIN_LASTNAME"
export user_password="$ADMIN_PASSWORD"

export timezone="Asia/Jakarta"

# ============================================================
# TELEMETRY OFF
# ============================================================

export ANONYMOUS_TELEMETRY="false"
export SEND_TELEMETRY="false"
export TELEMETRY="false"

# ============================================================
# SSL
# ============================================================

export CONFIGURE_LETSENCRYPT="true"

# ============================================================
# FIREWALL
# ============================================================

export CONFIGURE_FIREWALL="false"

# ============================================================
# INSTALL PANEL
# ============================================================

echo
echo "============================================================"
echo "                  INSTALLING PANEL"
echo "============================================================"
echo

info "Installing Pterodactyl Panel..."

printf '0\n' | bash "$TMP_INSTALLER"

PANEL_RESULT=$?

if [[ "$PANEL_RESULT" -ne 0 ]]; then
    die "Instalasi Panel gagal. Cek ${LOG_FILE}"
fi

# ============================================================
# PANEL DONE
# ============================================================

echo
echo "============================================================"
echo "                 PANEL INSTALLATION DONE"
echo "============================================================"
echo

ok "Panel berhasil diinstall."

echo
echo "Panel:"
echo "https://${PANEL_DOMAIN}"
echo
echo "Admin:"
echo "${ADMIN_USERNAME}"
echo
echo "Email:"
echo "${ADMIN_EMAIL}"
echo

# ============================================================
# WINGS SKIP
# ============================================================

if [[ ! "$INSTALL_WINGS" =~ ^[Yy]$ ]]; then

    echo
    warn "Wings tidak diinstall."

    rm -f "$TMP_INSTALLER"

    unset ADMIN_PASSWORD
    unset ADMIN_PASSWORD_CONFIRM
    unset user_password

    echo
    ok "Instalasi selesai."
    exit 0

fi

# ============================================================
# INSTALL WINGS
# ============================================================

echo
echo "============================================================"
echo "                  INSTALLING WINGS"
echo "============================================================"
echo

export FQDN="$NODE_DOMAIN"
export EMAIL="$ADMIN_EMAIL"

export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_FIREWALL="false"

info "Installing Wings..."

printf '1\n' | bash "$TMP_INSTALLER"

WINGS_RESULT=$?

if [[ "$WINGS_RESULT" -ne 0 ]]; then
    die "Instalasi Wings gagal. Cek ${LOG_FILE}"
fi

ok "Wings berhasil diinstall."

# ============================================================
# AUTO DEPLOY
# ============================================================

if [[ -n "$WINGS_COMMAND" ]]; then

    echo
    echo "============================================================"
    echo "                APPLY WINGS CONFIG"
    echo "============================================================"
    echo

    info "Applying Node configuration..."

    bash -c "$WINGS_COMMAND"

    DEPLOY_RESULT=$?

    if [[ "$DEPLOY_RESULT" -ne 0 ]]; then
        warn "Auto-Deploy command gagal."
        warn "Cek konfigurasi Node dari Panel."
        exit "$DEPLOY_RESULT"
    fi

    ok "Node configuration applied."

else

    warn "Auto-Deploy command kosong."
    warn "Wings belum mempunyai konfigurasi Node."

fi

# ============================================================
# CONFIG CHECK
# ============================================================

echo
info "Checking Wings configuration..."

if [[ -f /etc/pterodactyl/config.yml ]]; then
    ok "config.yml ditemukan."
else
    warn "config.yml tidak ditemukan."
fi

# ============================================================
# SYSTEMD
# ============================================================

if systemctl list-unit-files 2>/dev/null | grep -q '^wings.service'; then

    echo
    echo "============================================================"
    echo "                  STARTING WINGS"
    echo "============================================================"
    echo

    info "systemctl daemon-reload"
    systemctl daemon-reload

    ok "daemon-reload selesai."

    info "systemctl enable wings"
    systemctl enable wings

    ok "Wings enabled."

    if [[ -f /etc/pterodactyl/config.yml ]]; then

        info "systemctl start wings"
        systemctl start wings

        sleep 2

        if systemctl is-active --quiet wings; then
            ok "Wings RUNNING."
        else
            warn "Wings tidak running."

            echo
            echo "Wings status:"
            systemctl status wings --no-pager || true

            echo
            echo "Wings log:"
            journalctl -u wings -n 50 --no-pager || true
        fi

    else

        warn "Wings tidak distart karena config.yml belum ada."

    fi

else

    warn "wings.service tidak ditemukan."

fi

# ============================================================
# CLEANUP
# ============================================================

rm -f "$TMP_INSTALLER"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset user_password
unset WINGS_COMMAND

# ============================================================
# FINAL
# ============================================================

echo
echo "============================================================"
echo "              PTERODACTYL INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Panel:"
echo "  https://${PANEL_DOMAIN}"
echo

if [[ -n "$NODE_DOMAIN" ]]; then
    echo "Node:"
    echo "  ${NODE_DOMAIN}"
    echo
fi

echo "Admin:"
echo "  ${ADMIN_USERNAME}"
echo "  ${ADMIN_EMAIL}"
echo
echo "Anonymous telemetry:"
echo "  NO"
echo

if systemctl is-active --quiet wings 2>/dev/null; then
    echo "Wings:"
    echo "  RUNNING"
else
    if [[ "$INSTALL_WINGS" =~ ^[Yy]$ ]]; then
        echo "Wings:"
        echo "  NOT RUNNING / NOT CONFIGURED"
    fi
fi

echo
echo "Log:"
echo "  ${LOG_FILE}"
echo
echo "============================================================"
echo

ok " LXJR OFFC Selesai."