#!/bin/bash

# ============================================================
# PTERODACTYL AUTO INSTALLER
# ============================================================

set -e

INSTALLER_URL="https://pterodactyl-installer.se"
TMP_INSTALLER="/tmp/pterodactyl-installer.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

die() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# ============================================================
# ROOT
# ============================================================

if [ "$(id -u)" != "0" ]; then
    die "Jalankan sebagai root."
fi

# ============================================================
# CHECK BASH
# ============================================================

if [ -z "${BASH_VERSION}" ]; then
    exec /bin/bash "$0" "$@"
fi

# ============================================================
# OS
# ============================================================

if [ ! -f /etc/os-release ]; then
    die "/etc/os-release tidak ditemukan."
fi

. /etc/os-release

OS="${ID}"
VERSION="${VERSION_ID}"

case "${OS}:${VERSION}" in
    ubuntu:22.04|ubuntu:24.04|ubuntu:26.04)
        ;;
    debian:10|debian:11|debian:12|debian:13)
        ;;
    rocky:8|rocky:9)
        ;;
    almalinux:8|almalinux:9)
        ;;
    *)
        die "OS tidak didukung: ${PRETTY_NAME}"
        ;;
esac

# ============================================================
# DOMAIN VALIDATION
# ============================================================

valid_domain() {
    DOMAIN="$1"

    DOMAIN="$(printf '%s' "$DOMAIN" | tr -d '\r')"

    case "$DOMAIN" in
        ""|.*|*.|*..*)
            return 1
            ;;
    esac

    echo "$DOMAIN" | grep -Eq \
        '^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$'
}

valid_email() {
    echo "$1" | grep -Eq \
        '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
}

# ============================================================
# HEADER
# ============================================================

clear

echo
echo "============================================================"
echo "             PTERODACTYL AUTO INSTALLER"
echo "============================================================"
echo
echo "OS: ${PRETTY_NAME}"
echo
echo "============================================================"
echo

# ============================================================
# PANEL DOMAIN
# ============================================================

while true; do

    printf "Panel subdomain: "
    read PANEL_DOMAIN

    PANEL_DOMAIN="$(printf '%s' "$PANEL_DOMAIN" | tr -d '\r')"

    if valid_domain "$PANEL_DOMAIN"; then
        break
    fi

    warn "Domain tidak valid. Contoh: panel.example.com"

done

# ============================================================
# ADMIN EMAIL
# ============================================================

while true; do

    printf "Admin email/Gmail: "
    read ADMIN_EMAIL

    ADMIN_EMAIL="$(printf '%s' "$ADMIN_EMAIL" | tr -d '\r')"

    if valid_email "$ADMIN_EMAIL"; then
        break
    fi

    warn "Email tidak valid."

done

# ============================================================
# ADMIN USER
# ============================================================

while true; do

    printf "Admin username: "
    read ADMIN_USERNAME

    ADMIN_USERNAME="$(printf '%s' "$ADMIN_USERNAME" | tr -d '\r')"

    if echo "$ADMIN_USERNAME" | grep -Eq \
        '^[A-Za-z0-9._-]{3,32}$'; then
        break
    fi

    warn "Username tidak valid."

done

# ============================================================
# ADMIN NAME
# ============================================================

printf "Admin first name [Admin]: "
read ADMIN_FIRSTNAME

if [ -z "$ADMIN_FIRSTNAME" ]; then
    ADMIN_FIRSTNAME="Admin"
fi

printf "Admin last name [User]: "
read ADMIN_LASTNAME

if [ -z "$ADMIN_LASTNAME" ]; then
    ADMIN_LASTNAME="User"
fi

# ============================================================
# PASSWORD
# ============================================================

while true; do

    printf "Admin password: "
    stty -echo
    read ADMIN_PASSWORD
    stty echo
    echo

    if [ "${#ADMIN_PASSWORD}" -lt 8 ]; then
        warn "Password minimal 8 karakter."
        continue
    fi

    printf "Ulangi password: "
    stty -echo
    read ADMIN_PASSWORD_CONFIRM
    stty echo
    echo

    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        warn "Password tidak sama."
        continue
    fi

    break

done

# ============================================================
# WINGS
# ============================================================

printf "Install Wings/Node? [Y/n]: "
read INSTALL_WINGS

if [ -z "$INSTALL_WINGS" ]; then
    INSTALL_WINGS="y"
fi

case "$INSTALL_WINGS" in
    Y|y)
        INSTALL_WINGS="yes"
        ;;
    N|n)
        INSTALL_WINGS="no"
        ;;
    *)
        die "Jawab Y atau N."
        ;;
esac

# ============================================================
# NODE DOMAIN
# ============================================================

NODE_DOMAIN=""

if [ "$INSTALL_WINGS" = "yes" ]; then

    while true; do

        printf "Node subdomain: "
        read NODE_DOMAIN

        NODE_DOMAIN="$(printf '%s' "$NODE_DOMAIN" | tr -d '\r')"

        if valid_domain "$NODE_DOMAIN"; then
            break
        fi

        warn "Node domain tidak valid. Contoh: node.example.com"

    done

fi

# ============================================================
# SUMMARY
# ============================================================

echo
echo "============================================================"
echo "                    CONFIGURATION"
echo "============================================================"
echo
echo "Panel : ${PANEL_DOMAIN}"
echo "Email : ${ADMIN_EMAIL}"
echo "User  : ${ADMIN_USERNAME}"
echo "Wings : ${INSTALL_WINGS}"

if [ "$INSTALL_WINGS" = "yes" ]; then
    echo "Node  : ${NODE_DOMAIN}"
fi

echo
echo "Anonymous telemetry: NO"
echo
echo "============================================================"
echo

printf "Lanjut instalasi? [Y/n]: "
read CONFIRM

if [ -z "$CONFIRM" ]; then
    CONFIRM="y"
fi

case "$CONFIRM" in
    Y|y)
        ;;
    *)
        echo "Dibatalkan."
        exit 0
        ;;
esac

# ============================================================
# CURL
# ============================================================

if ! command -v curl >/dev/null 2>&1; then

    info "Installing curl..."

    case "$OS" in

        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y curl ca-certificates
            ;;

        rocky|almalinux)
            dnf install -y curl ca-certificates
            ;;

    esac

fi

# ============================================================
# DOWNLOAD INSTALLER
# ============================================================

rm -f "$TMP_INSTALLER"

info "Downloading Pterodactyl installer..."

curl -fsSL "$INSTALLER_URL" -o "$TMP_INSTALLER" ||
    die "Gagal download installer."

if [ ! -s "$TMP_INSTALLER" ]; then
    die "Installer kosong."
fi

chmod 700 "$TMP_INSTALLER"

ok "Installer berhasil didownload."

# ============================================================
# ENVIRONMENT
# ============================================================

export FQDN="$PANEL_DOMAIN"
export EMAIL="$ADMIN_EMAIL"

export user_email="$ADMIN_EMAIL"
export user_username="$ADMIN_USERNAME"
export user_firstname="$ADMIN_FIRSTNAME"
export user_lastname="$ADMIN_LASTNAME"
export user_password="$ADMIN_PASSWORD"

export timezone="Asia/Jakarta"

export ANONYMOUS_TELEMETRY="false"
export SEND_TELEMETRY="false"
export TELEMETRY="false"

# ============================================================
# PANEL
# ============================================================

echo
echo "============================================================"
echo "                  INSTALLING PANEL"
echo "============================================================"
echo

info "Menjalankan installer Panel."

# IMPORTANT:
# Jalankan installer dengan Bash langsung.
# Tidak memakai printf | bash.
# Tidak memakai sh.

bash "$TMP_INSTALLER"

# ============================================================
# PANEL DONE
# ============================================================

echo
echo "============================================================"
echo "                    PANEL SELESAI"
echo "============================================================"
echo

ok "Panel installer selesai."

echo
echo "Panel:"
echo "https://${PANEL_DOMAIN}"
echo
echo "Admin:"
echo "${ADMIN_USERNAME}"
echo "${ADMIN_EMAIL}"
echo

# ============================================================
# WINGS NO
# ============================================================

if [ "$INSTALL_WINGS" = "no" ]; then

    rm -f "$TMP_INSTALLER"

    unset ADMIN_PASSWORD
    unset ADMIN_PASSWORD_CONFIRM
    unset user_password

    ok "Wings dilewati."
    exit 0

fi

# ============================================================
# WINGS
# ============================================================

echo
echo "============================================================"
echo "                    WINGS / NODE"
echo "============================================================"
echo

echo "Node:"
echo "${NODE_DOMAIN}"
echo

echo "Sekarang installer Wings akan dijalankan."
echo

export FQDN="$NODE_DOMAIN"
export EMAIL="$ADMIN_EMAIL"

# ============================================================
# WINGS INSTALL
# ============================================================

bash "$TMP_INSTALLER"

# ============================================================
# NODE TOKEN
# ============================================================

echo
echo "============================================================"
echo "                 NODE AUTO DEPLOY"
echo "============================================================"
echo

echo "Buat Node di Panel:"
echo
echo "Admin Area -> Nodes -> Create New"
echo
echo "FQDN:"
echo "${NODE_DOMAIN}"
echo
echo "Setelah Node dibuat, buka Configuration."
echo
echo "Copy command Auto-Deploy dari Panel."
echo

printf "Paste command Auto-Deploy: "
read WINGS_COMMAND

if [ -z "$WINGS_COMMAND" ]; then

    warn "Command kosong."
    warn "Wings belum dikonfigurasi."

    rm -f "$TMP_INSTALLER"

    unset ADMIN_PASSWORD
    unset ADMIN_PASSWORD_CONFIRM
    unset user_password

    exit 0

fi

# ============================================================
# EXECUTE TOKEN
# ============================================================

echo
info "Menjalankan Auto-Deploy..."

bash -c "$WINGS_COMMAND"

# ============================================================
# CONFIG
# ============================================================

if [ ! -f /etc/pterodactyl/config.yml ]; then

    warn "/etc/pterodactyl/config.yml belum ditemukan."

else

    ok "config.yml ditemukan."

fi

# ============================================================
# START WINGS
# ============================================================

echo
echo "============================================================"
echo "                   STARTING WINGS"
echo "============================================================"
echo

systemctl daemon-reload

systemctl enable wings

systemctl start wings

sleep 2

# ============================================================
# STATUS
# ============================================================

if systemctl is-active --quiet wings; then

    ok "Wings RUNNING."

else

    warn "Wings tidak running."

    echo
    systemctl status wings --no-pager || true

    echo
    journalctl -u wings -n 50 --no-pager || true

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
echo "               INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Panel:"
echo "https://${PANEL_DOMAIN}"
echo

if [ "$INSTALL_WINGS" = "yes" ]; then
    echo "Node:"
    echo "${NODE_DOMAIN}"
    echo
fi

echo "Admin:"
echo "${ADMIN_USERNAME}"
echo "${ADMIN_EMAIL}"
echo
echo "Anonymous telemetry: NO"
echo
echo "============================================================"
echo

ok "LXJR OFFC Selesai."