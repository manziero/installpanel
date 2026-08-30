#!/bin/bash

# ============================================================
# PTERODACTYL AUTO INSTALLER
# ============================================================

set -e

INSTALLER_URL="https://pterodactyl-installer.se"
TMP="/tmp/pterodactyl-installer.sh"

info() {
    echo "[INFO] $1"
}

error() {
    echo "[ERROR] $1"
    exit 1
}

# ------------------------------------------------------------
# ROOT
# ------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    error "Jalankan script sebagai root."
fi

# ------------------------------------------------------------
# FIX CRLF
# ------------------------------------------------------------

download_installer() {
    rm -f "$TMP"

    curl -fsSL "$INSTALLER_URL" -o "$TMP" ||
        error "Gagal download installer."

    sed -i 's/\r$//' "$TMP"

    chmod +x "$TMP"
}

# ------------------------------------------------------------
# MENU CUSTOM
# ------------------------------------------------------------

clear

echo
echo "=================================================="
echo "        PTERODACTYL AUTO INSTALLER"
echo "=================================================="
echo
echo "[1] Install Panel saja"
echo "[2] Install Panel + Wings/Node"
echo "[3] Install Wings/Node saja"
echo
read -r -p "Pilih [1-3]: " MODE

case "$MODE" in

    1)
        UPSTREAM_OPTION="0"
        ;;

    2)
        UPSTREAM_OPTION="2"
        ;;

    3)
        UPSTREAM_OPTION="1"
        ;;

    *)
        error "Pilihan tidak valid."
        ;;

esac

# ------------------------------------------------------------
# PANEL INFORMATION
# ------------------------------------------------------------

PANEL_DOMAIN=""
NODE_DOMAIN=""
ADMIN_EMAIL=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""

if [ "$MODE" = "1" ] || [ "$MODE" = "2" ]; then

    while true; do
        read -r -p "Panel subdomain: " PANEL_DOMAIN

        if [[ "$PANEL_DOMAIN" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            break
        fi

        echo "[!] Domain tidak valid."
    done

    while true; do
        read -r -p "Admin email: " ADMIN_EMAIL

        if [[ "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
            break
        fi

        echo "[!] Email tidak valid."
    done

    read -r -p "Admin username: " ADMIN_USERNAME

    while true; do

        read -r -s -p "Admin password: " ADMIN_PASSWORD
        echo

        read -r -s -p "Confirm password: " ADMIN_PASSWORD_CONFIRM
        echo

        if [ "$ADMIN_PASSWORD" = "$ADMIN_PASSWORD_CONFIRM" ] &&
           [ "${#ADMIN_PASSWORD}" -ge 8 ]; then
            break
        fi

        echo "[!] Password tidak sama atau kurang dari 8 karakter."

    done

fi

# ------------------------------------------------------------
# NODE INFORMATION
# ------------------------------------------------------------

if [ "$MODE" = "2" ] || [ "$MODE" = "3" ]; then

    while true; do

        read -r -p "Node subdomain: " NODE_DOMAIN

        if [[ "$NODE_DOMAIN" =~ ^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            break
        fi

        echo "[!] Node domain tidak valid."

    done

fi

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

echo
echo "=================================================="
echo "                 KONFIGURASI"
echo "=================================================="

case "$MODE" in
    1)
        echo "Mode : Panel saja"
        echo "Panel: $PANEL_DOMAIN"
        ;;

    2)
        echo "Mode : Panel + Wings"
        echo "Panel: $PANEL_DOMAIN"
        echo "Node : $NODE_DOMAIN"
        ;;

    3)
        echo "Mode : Wings saja"
        echo "Node : $NODE_DOMAIN"
        ;;
esac

echo
echo "Anonymous telemetry: NO"
echo "=================================================="
echo

read -r -p "Lanjut instalasi? [Y/n]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^([Yy]|)$ ]]; then
    echo "Instalasi dibatalkan."
    exit 0
fi

# ------------------------------------------------------------
# DOWNLOAD
# ------------------------------------------------------------

info "Mengambil installer Pterodactyl..."

if ! command -v curl >/dev/null 2>&1; then

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl
    fi

fi

download_installer

# ------------------------------------------------------------
# ENV PANEL
# ------------------------------------------------------------

export FQDN="$PANEL_DOMAIN"
export EMAIL="$ADMIN_EMAIL"

export user_email="$ADMIN_EMAIL"
export user_username="$ADMIN_USERNAME"
export user_password="$ADMIN_PASSWORD"

export ANONYMOUS_TELEMETRY="false"
export SEND_TELEMETRY="false"

# ------------------------------------------------------------
# RUN UPSTREAM WITHOUT SHOWING ITS MENU
# ------------------------------------------------------------

info "Memulai installer Pterodactyl..."

printf '%s\n' "$UPSTREAM_OPTION" |
    /bin/bash "$TMP"

# ------------------------------------------------------------
# PANEL FINISH
# ------------------------------------------------------------

if [ "$MODE" = "1" ]; then

    echo
    echo "=================================================="
    echo "              PANEL SELESAI"
    echo "=================================================="
    echo
    echo "Panel : https://$PANEL_DOMAIN"
    echo "Email : $ADMIN_EMAIL"
    echo "User  : $ADMIN_USERNAME"
    echo

    rm -f "$TMP"

    exit 0

fi

# ------------------------------------------------------------
# WINGS FINISH
# ------------------------------------------------------------

if [ "$MODE" = "3" ]; then

    echo
    echo "=================================================="
    echo "              WINGS SELESAI"
    echo "=================================================="
    echo
    echo "Node : $NODE_DOMAIN"
    echo

fi

if [ "$MODE" = "2" ]; then

    echo
    echo "=================================================="
    echo "          PANEL + WINGS SELESAI"
    echo "=================================================="
    echo
    echo "Panel : https://$PANEL_DOMAIN"
    echo "Node  : $NODE_DOMAIN"
    echo

fi

# ------------------------------------------------------------
# START WINGS
# ------------------------------------------------------------

if command -v systemctl >/dev/null 2>&1; then

    systemctl daemon-reload || true
    systemctl enable wings || true
    systemctl start wings || true

    sleep 2

    if systemctl is-active --quiet wings; then
        echo "[OK] Wings sedang running."
    else
        echo "[!] Wings belum running."
        systemctl status wings --no-pager || true
    fi

fi

rm -f "$TMP"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM

echo
echo "=================================================="
echo "                 LXJR OFFC SELESAI"
echo "=================================================="