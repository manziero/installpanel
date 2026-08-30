#!/bin/bash

# ============================================================
# PTERODACTYL AUTO INSTALLER
# ============================================================

set -e

INSTALLER_URL="https://pterodactyl-installer.se"
TMP="/tmp/pterodactyl-installer.sh"

die() {
    echo "[ERROR] $1"
    exit 1
}

info() {
    echo "[INFO] $1"
}

ok() {
    echo "[OK] $1"
}

[ "$(id -u)" = "0" ] || die "Jalankan sebagai root."

# ============================================================
# FIX CRLF
# ============================================================

download_installer() {
    rm -f "$TMP"

    curl -fsSL "$INSTALLER_URL" -o "$TMP" ||
        die "Gagal mengambil installer Pterodactyl."

    sed -i 's/\r$//' "$TMP"

    chmod 700 "$TMP"
}

# ============================================================
# CHECK DOMAIN
# ============================================================

valid_domain() {
    printf '%s' "$1" |
        grep -Eq '^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
}

valid_email() {
    printf '%s' "$1" |
        grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
}

# ============================================================
# MENU
# ============================================================

clear

echo
echo "============================================================"
echo "              PTERODACTYL AUTO INSTALLER"
echo "============================================================"
echo
echo "[1] Install Panel saja"
echo "[2] Install Panel + Wings"
echo "[3] Install Wings saja"
echo

while true; do
    read -r -p "Pilih [1-3]: " MODE

    case "$MODE" in
        1|2|3)
            break
            ;;
        *)
            echo "[!] Pilihan harus 1, 2, atau 3."
            ;;
    esac
done

# ============================================================
# PANEL INPUT
# ============================================================

PANEL_DOMAIN=""
ADMIN_EMAIL=""
ADMIN_USERNAME=""
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="User"
ADMIN_PASSWORD=""

if [ "$MODE" = "1" ] || [ "$MODE" = "2" ]; then

    while true; do
        read -r -p "Panel subdomain: " PANEL_DOMAIN

        if valid_domain "$PANEL_DOMAIN"; then
            break
        fi

        echo "[!] Domain tidak valid."
    done

    while true; do
        read -r -p "Admin email: " ADMIN_EMAIL

        if valid_email "$ADMIN_EMAIL"; then
            break
        fi

        echo "[!] Email tidak valid."
    done

    read -r -p "Admin username: " ADMIN_USERNAME

    read -r -p "Admin first name [Admin]: " TMP
    [ -n "$TMP" ] && ADMIN_FIRSTNAME="$TMP"

    read -r -p "Admin last name [User]: " TMP
    [ -n "$TMP" ] && ADMIN_LASTNAME="$TMP"

    while true; do

        read -r -s -p "Admin password: " ADMIN_PASSWORD
        echo

        read -r -s -p "Confirm password: " ADMIN_PASSWORD2
        echo

        if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD2" ]; then
            echo "[!] Password tidak sama."
            continue
        fi

        if [ "${#ADMIN_PASSWORD}" -lt 8 ]; then
            echo "[!] Password minimal 8 karakter."
            continue
        fi

        break
    done

fi

# ============================================================
# WINGS INPUT
# ============================================================

NODE_DOMAIN=""

if [ "$MODE" = "2" ] || [ "$MODE" = "3" ]; then

    while true; do

        read -r -p "Node subdomain: " NODE_DOMAIN

        if valid_domain "$NODE_DOMAIN"; then
            break
        fi

        echo "[!] Node domain tidak valid."

    done

fi

# ============================================================
# SUMMARY
# ============================================================

echo
echo "============================================================"

case "$MODE" in
    1)
        echo "Mode : PANEL SAJA"
        ;;
    2)
        echo "Mode : PANEL + WINGS"
        ;;
    3)
        echo "Mode : WINGS SAJA"
        ;;
esac

[ -n "$PANEL_DOMAIN" ] && echo "Panel: $PANEL_DOMAIN"
[ -n "$NODE_DOMAIN" ] && echo "Node : $NODE_DOMAIN"

echo "============================================================"
echo

read -r -p "Mulai instalasi? [Y/n]: " CONFIRM

case "${CONFIRM:-Y}" in
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

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl ca-certificates
    else
        die "Tidak menemukan package manager."
    fi

fi

# ============================================================
# DOWNLOAD UPSTREAM
# ============================================================

info "Mengambil installer Pterodactyl..."

download_installer

ok "Installer siap."

# ============================================================
# MODE PANEL
# ============================================================

if [ "$MODE" = "1" ] || [ "$MODE" = "2" ]; then

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

    echo
    echo "============================================================"
    echo "                    INSTALLING PANEL"
    echo "============================================================"
    echo

    # Jalankan installer upstream dengan input terminal sendiri.
    # Kita tidak pipe stdin karena installer memiliki banyak prompt.
    "$TMP" </dev/tty

fi

# ============================================================
# WINGS
# ============================================================

if [ "$MODE" = "2" ] || [ "$MODE" = "3" ]; then

    echo
    echo "============================================================"
    echo "                    INSTALLING WINGS"
    echo "============================================================"
    echo

    export FQDN="$NODE_DOMAIN"
    export EMAIL="$ADMIN_EMAIL"

    export ANONYMOUS_TELEMETRY="false"
    export SEND_TELEMETRY="false"
    export TELEMETRY="false"

    "$TMP" </dev/tty

    echo
    echo "============================================================"
    echo "                    WINGS SELESAI"
    echo "============================================================"
    echo

    echo "Node domain:"
    echo "$NODE_DOMAIN"
    echo

    echo "PENTING:"
    echo "Buat Node di Panel terlebih dahulu."
    echo "Kemudian gunakan konfigurasi/Auto Deploy dari Panel."
    echo

fi

# ============================================================
# CLEANUP
# ============================================================

rm -f "$TMP"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD2

echo
echo "============================================================"
echo "                 LXJR OFFC INSTALASI SELESAI"
echo "============================================================"
echo

[ -n "$PANEL_DOMAIN" ] && \
    echo "Panel: https://$PANEL_DOMAIN"

[ -n "$NODE_DOMAIN" ] && \
    echo "Node : $NODE_DOMAIN"

echo