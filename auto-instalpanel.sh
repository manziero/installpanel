#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# PTERODACTYL AUTO INSTALLER
# PANEL + OPTIONAL WINGS
#
# Flow:
#   1. Check OS
#   2. Ask Panel domain
#   3. Ask admin email / username / password
#   4. Install Panel
#   5. Ask: Install Wings? [Y/n]
#   6. If YES:
#        - Ask Node domain
#        - Install Wings
#        - Ask for Wings Auto-Deploy command
#        - Apply config
#        - systemctl enable --now wings
#        - Check status
#
# Anonymous telemetry: NO
# SSL: YES
#
# ============================================================

set +H

INSTALLER_URL="https://pterodactyl-installer.se"
LOG_FILE="/var/log/pterodactyl-auto-installer.log"
TMP_INSTALLER="/tmp/pterodactyl-installer.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${CYAN}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

die() {
    error "$*"
    exit 1
}

# ============================================================
# ROOT
# ============================================================

if [[ "$EUID" -ne 0 ]]; then
    die "Jalankan script sebagai root."
fi

# ============================================================
# OS DETECTION
# ============================================================

if [[ ! -f /etc/os-release ]]; then
    die "File /etc/os-release tidak ditemukan."
fi

source /etc/os-release

OS="${ID:-}"
VERSION="${VERSION_ID:-}"
PRETTY="${PRETTY_NAME:-$OS $VERSION}"

case "${OS}:${VERSION}" in

    ubuntu:22.04)
        ;;

    ubuntu:24.04)
        ;;

    ubuntu:26.04)
        ;;

    debian:10)
        ;;

    debian:11)
        ;;

    debian:12)
        ;;

    debian:13)
        ;;

    rocky:8)
        ;;

    rocky:9)
        ;;

    almalinux:8)
        ;;

    almalinux:9)
        ;;

    *)
        die "OS tidak didukung: ${PRETTY}"
        ;;
esac

# ============================================================
# ARCHITECTURE
# ============================================================

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)
        ;;
    aarch64|arm64)
        ;;
    *)
        die "Architecture tidak didukung: ${ARCH}"
        ;;
esac

# ============================================================
# HEADER
# ============================================================

clear

echo
echo "============================================================"
echo "              PTERODACTYL AUTO INSTALLER"
echo "============================================================"
echo
echo "OS           : ${PRETTY}"
echo "Architecture : ${ARCH}"
echo
echo "Anonymous    : NO"
echo "SSL          : YES"
echo
echo "============================================================"
echo

# ============================================================
# DOMAIN VALIDATION
# ============================================================

valid_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

# ============================================================
# PANEL DOMAIN
# ============================================================

while true; do

    read -rp "Panel subdomain: " PANEL_DOMAIN

    if valid_domain "$PANEL_DOMAIN"; then
        break
    fi

    warn "Domain tidak valid."

done

# ============================================================
# ADMIN EMAIL
# ============================================================

while true; do

    read -rp "Admin email: " ADMIN_EMAIL

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

    if [[ "$ADMIN_USERNAME" =~ ^[a-zA-Z0-9._-]{3,32}$ ]]; then
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

    read -rsp "Ulangi password: " ADMIN_PASSWORD_CONFIRM
    echo

    if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
        warn "Password tidak sama."
        continue
    fi

    break

done

# ============================================================
# SUMMARY
# ============================================================

echo
echo "============================================================"
echo "                  PANEL CONFIGURATION"
echo "============================================================"
echo
echo "Panel domain : https://${PANEL_DOMAIN}"
echo "Admin email  : ${ADMIN_EMAIL}"
echo "Admin user   : ${ADMIN_USERNAME}"
echo "Anonymous    : NO"
echo "SSL          : YES"
echo
echo "============================================================"
echo

read -rp "Lanjut install Panel? [y/N]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    warn "Instalasi dibatalkan."
    exit 0
fi

# ============================================================
# LOGGING
# ============================================================

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Save normal output to log.
# Password is never deliberately printed.
exec > >(tee -a "$LOG_FILE") 2>&1

# ============================================================
# INSTALL CURL
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
# PUBLIC IP
# ============================================================

SERVER_IP="$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || true)"

echo
info "IP VPS: ${SERVER_IP:-unknown}"
echo

if [[ -n "$SERVER_IP" ]]; then

    echo "Pastikan DNS berikut:"
    echo
    echo "  ${PANEL_DOMAIN} -> ${SERVER_IP}"
    echo

fi

read -rp "DNS Panel sudah benar? [y/N]: " DNS_CONFIRM

if [[ ! "$DNS_CONFIRM" =~ ^[Yy]$ ]]; then

    warn "DNS belum dikonfirmasi."

    echo
    echo "Arahkan:"
    echo
    echo "  ${PANEL_DOMAIN} -> ${SERVER_IP}"
    echo

    exit 0

fi

# ============================================================
# DOWNLOAD INSTALLER
# ============================================================

info "Downloading Pterodactyl installer..."

rm -f "$TMP_INSTALLER"

curl -fsSL \
    "$INSTALLER_URL" \
    -o "$TMP_INSTALLER"

if [[ ! -s "$TMP_INSTALLER" ]]; then
    die "Gagal download installer Pterodactyl."
fi

chmod +x "$TMP_INSTALLER"

success "Installer downloaded."

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
# ANONYMOUS TELEMETRY OFF
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
echo "                 INSTALLING PANEL"
echo "============================================================"
echo

info "Memulai installer Panel..."

printf '0\n' | bash "$TMP_INSTALLER"

PANEL_RESULT=$?

if [[ "$PANEL_RESULT" -ne 0 ]]; then

    die "Instalasi Panel gagal."

fi

# ============================================================
# PANEL DONE
# ============================================================

echo
echo "============================================================"
echo "                 PANEL SELESAI"
echo "============================================================"
echo

success "Pterodactyl Panel berhasil diinstall."

echo
echo "Panel:"
echo "https://${PANEL_DOMAIN}"
echo
echo "Username:"
echo "${ADMIN_USERNAME}"
echo
echo "Email:"
echo "${ADMIN_EMAIL}"
echo

# ============================================================
# ASK INSTALL WINGS
# ============================================================

echo "============================================================"
echo "                    WINGS / NODE"
echo "============================================================"
echo

read -rp "Mau install Wings/Node sekarang? [Y/n]: " INSTALL_WINGS

# ENTER = YES

if [[ -z "$INSTALL_WINGS" ]]; then
    INSTALL_WINGS="y"
fi

# ============================================================
# IF WINGS NO
# ============================================================

if [[ ! "$INSTALL_WINGS" =~ ^[Yy]$ ]]; then

    echo
    success "Wings dilewati."

    echo
    echo "Panel:"
    echo "https://${PANEL_DOMAIN}"
    echo

    rm -f "$TMP_INSTALLER"

    unset ADMIN_PASSWORD
    unset ADMIN_PASSWORD_CONFIRM
    unset user_password

    exit 0

fi

# ============================================================
# NODE DOMAIN
# ============================================================

echo
echo "============================================================"
echo "                  NODE CONFIGURATION"
echo "============================================================"
echo

while true; do

    read -rp "Node subdomain: " NODE_DOMAIN

    if valid_domain "$NODE_DOMAIN"; then
        break
    fi

    warn "Node domain tidak valid."

done

# ============================================================
# NODE DNS
# ============================================================

echo

if [[ -n "$SERVER_IP" ]]; then

    echo "Pastikan DNS:"
    echo
    echo "  ${NODE_DOMAIN} -> ${SERVER_IP}"
    echo

fi

read -rp "DNS Node sudah benar? [y/N]: " NODE_DNS

if [[ ! "$NODE_DNS" =~ ^[Yy]$ ]]; then

    warn "Wings dibatalkan karena DNS Node belum dikonfirmasi."

    rm -f "$TMP_INSTALLER"

    unset ADMIN_PASSWORD
    unset ADMIN_PASSWORD_CONFIRM
    unset user_password

    exit 0

fi

# ============================================================
# WINGS VARIABLES
# ============================================================

export FQDN="$NODE_DOMAIN"
export EMAIL="$ADMIN_EMAIL"

export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_FIREWALL="false"

# ============================================================
# INSTALL WINGS
# ============================================================

echo
echo "============================================================"
echo "                 INSTALLING WINGS"
echo "============================================================"
echo

info "Menginstall Wings..."

printf '1\n' | bash "$TMP_INSTALLER"

WINGS_INSTALL_RESULT=$?

if [[ "$WINGS_INSTALL_RESULT" -ne 0 ]]; then

    warn "Wings gagal diinstall."

    echo
    echo "Panel tetap tersedia:"
    echo "https://${PANEL_DOMAIN}"
    echo

    rm -f "$TMP_INSTALLER"

    exit "$WINGS_INSTALL_RESULT"

fi

success "Wings berhasil diinstall."

# ============================================================
# NODE CONFIGURATION
# ============================================================

echo
echo "============================================================"
echo "               WINGS AUTO DEPLOY"
echo "============================================================"
echo
echo "Buat Node terlebih dahulu di:"
echo
echo "  Admin -> Nodes -> Create New"
echo
echo "FQDN Node:"
echo
echo "  ${NODE_DOMAIN}"
echo
echo "Setelah Node dibuat, buka Configuration."
echo
echo "Gunakan command Auto-Deploy / Generate Token"
echo "yang diberikan oleh Panel."
echo
echo "============================================================"
echo

read -rp "Paste command Auto-Deploy Wings: " WINGS_COMMAND

# ============================================================
# EMPTY COMMAND
# ============================================================

if [[ -z "$WINGS_COMMAND" ]]; then

    warn "Command kosong."
    warn "Wings belum dikonfigurasi."

    echo
    echo "Setelah config dipasang, jalankan:"
    echo
    echo "  systemctl enable --now wings"
    echo

    rm -f "$TMP_INSTALLER"

    unset ADMIN_PASSWORD
    unset ADMIN_PASSWORD_CONFIRM
    unset user_password

    exit 0

fi

# ============================================================
# WARNING
# ============================================================

echo
warn "Command akan dijalankan sekarang."
warn "Pastikan command berasal dari Panel Pterodactyl."
echo

read -rp "Lanjutkan? [y/N]: " RUN_COMMAND

if [[ ! "$RUN_COMMAND" =~ ^[Yy]$ ]]; then

    warn "Auto-Deploy dibatalkan."

    rm -f "$TMP_INSTALLER"

    unset ADMIN_PASSWORD
    unset ADMIN_PASSWORD_CONFIRM
    unset user_password

    exit 0

fi

# ============================================================
# EXECUTE AUTO DEPLOY
# ============================================================

echo
info "Menerapkan konfigurasi Wings..."

bash -c "$WINGS_COMMAND"

DEPLOY_RESULT=$?

if [[ "$DEPLOY_RESULT" -ne 0 ]]; then

    warn "Command Auto-Deploy gagal."

    echo
    echo "Cek:"
    echo
    echo "  /etc/pterodactyl/config.yml"
    echo
    echo "Log:"
    echo
    echo "  ${LOG_FILE}"
    echo

    exit "$DEPLOY_RESULT"

fi

success "Konfigurasi Wings berhasil diterapkan."

# ============================================================
# CONFIG CHECK
# ============================================================

echo
info "Memeriksa config Wings..."

if [[ -f /etc/pterodactyl/config.yml ]]; then

    success "/etc/pterodactyl/config.yml ditemukan."

else

    warn "/etc/pterodactyl/config.yml tidak ditemukan."

fi

# ============================================================
# SYSTEMD
# ============================================================

echo
echo "============================================================"
echo "                 STARTING WINGS"
echo "============================================================"
echo

info "systemctl daemon-reload..."

systemctl daemon-reload

success "daemon-reload selesai."

info "Mengaktifkan Wings saat boot..."

systemctl enable wings

success "Wings enabled."

info "Menjalankan Wings..."

systemctl start wings

# ============================================================
# STATUS
# ============================================================

sleep 2

echo
info "Mengecek status Wings..."

if systemctl is-active --quiet wings; then

    success "Wings is RUNNING."

else

    warn "Wings tidak running."

    echo
    echo "Status Wings:"
    echo

    systemctl status wings --no-pager || true

    echo
    echo "Journal Wings:"
    echo

    journalctl -u wings -n 50 --no-pager || true

fi

# ============================================================
# FINAL
# ============================================================

echo
echo "============================================================"
echo "             PTERODACTYL INSTALLATION DONE"
echo "============================================================"
echo

echo "Panel:"
echo "  https://${PANEL_DOMAIN}"
echo

echo "Node:"
echo "  ${NODE_DOMAIN}"
echo

echo "Admin:"
echo "  Username : ${ADMIN_USERNAME}"
echo "  Email    : ${ADMIN_EMAIL}"
echo

echo "Anonymous telemetry:"
echo "  NO"
echo

if systemctl is-active --quiet wings 2>/dev/null; then
    echo "Wings:"
    echo "  RUNNING"
else
    echo "Wings:"
    echo "  NOT RUNNING"
fi

echo
echo "Log:"
echo "  ${LOG_FILE}"
echo

echo "============================================================"

# ============================================================
# CLEANUP
# ============================================================

rm -f "$TMP_INSTALLER"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset user_password
unset WINGS_COMMAND

echo
success "LXJR OFFC Selesai."
echo