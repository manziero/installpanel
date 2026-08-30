#!/bin/bash

set -e

# ============================================================
# PTERODACTYL AUTO INSTALLER
# ============================================================

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

# ------------------------------------------------------------
# ROOT
# ------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    die "Jalankan sebagai root."
fi

# ------------------------------------------------------------
# CURL
# ------------------------------------------------------------

if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y curl ca-certificates
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y curl ca-certificates
    else
        die "curl tidak tersedia."
    fi
fi

# ------------------------------------------------------------
# EXPECT
# ------------------------------------------------------------

if ! command -v expect >/dev/null 2>&1; then
    info "Menginstall expect..."

    if command -v apt-get >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y expect
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y expect
    else
        die "Tidak dapat menginstall expect."
    fi
fi

# ------------------------------------------------------------
# DOWNLOAD
# ------------------------------------------------------------

info "Mengambil installer Pterodactyl..."

rm -f "$TMP"

curl -fsSL "$INSTALLER_URL" -o "$TMP" ||
    die "Gagal mengambil installer."

# Hilangkan CRLF
sed -i 's/\r$//' "$TMP"

chmod 700 "$TMP"

# Pastikan syntax installer valid
/bin/bash -n "$TMP" ||
    die "Installer Pterodactyl memiliki syntax error."

ok "Installer berhasil disiapkan."

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# PANEL DATA
# ------------------------------------------------------------

PANEL_DOMAIN=""
ADMIN_EMAIL=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""

if [ "$MODE" = "1" ] || [ "$MODE" = "2" ]; then

    while true; do
        read -r -p "Panel subdomain: " PANEL_DOMAIN

        PANEL_DOMAIN="${PANEL_DOMAIN//$'\r'/}"

        if [[ "$PANEL_DOMAIN" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$ ]]; then
            break
        fi

        echo "[!] Domain tidak valid."
    done

    while true; do
        read -r -p "Admin email/Gmail: " ADMIN_EMAIL

        ADMIN_EMAIL="${ADMIN_EMAIL//$'\r'/}"

        if [[ "$ADMIN_EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
            break
        fi

        echo "[!] Email tidak valid."
    done

    while true; do
        read -r -p "Admin username: " ADMIN_USERNAME

        if [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
            break
        fi

        echo "[!] Username tidak valid."
    done

    while true; do

        read -r -s -p "Admin password: " ADMIN_PASSWORD
        echo

        read -r -s -p "Ulangi password: " ADMIN_PASSWORD2
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

# ------------------------------------------------------------
# NODE DATA
# ------------------------------------------------------------

NODE_DOMAIN=""

if [ "$MODE" = "2" ] || [ "$MODE" = "3" ]; then

    while true; do

        read -r -p "Node subdomain: " NODE_DOMAIN

        NODE_DOMAIN="${NODE_DOMAIN//$'\r'/}"

        if [[ "$NODE_DOMAIN" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$ ]]; then
            break
        fi

        echo "[!] Node domain tidak valid."

    done

fi

# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

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

read -r -p "Lanjutkan instalasi? [Y/n]: " CONFIRM

case "${CONFIRM:-Y}" in
    Y|y)
        ;;
    *)
        echo "Instalasi dibatalkan."
        exit 0
        ;;
esac

# ------------------------------------------------------------
# UPSTREAM MENU
# ------------------------------------------------------------

case "$MODE" in
    1)
        UPSTREAM="0"
        ;;
    2)
        UPSTREAM="2"
        ;;
    3)
        UPSTREAM="1"
        ;;
esac

# ------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------

export FQDN="${PANEL_DOMAIN}"
export EMAIL="${ADMIN_EMAIL}"

export user_email="${ADMIN_EMAIL}"
export user_username="${ADMIN_USERNAME}"
export user_password="${ADMIN_PASSWORD}"

export timezone="Asia/Jakarta"

export ANONYMOUS_TELEMETRY="false"
export SEND_TELEMETRY="false"
export TELEMETRY="false"

# ------------------------------------------------------------
# EXPECT RUNNER
# ------------------------------------------------------------

info "Menjalankan installer Pterodactyl..."

export AUTO_MODE="$UPSTREAM"
export AUTO_PANEL="$PANEL_DOMAIN"
export AUTO_NODE="$NODE_DOMAIN"
export AUTO_EMAIL="$ADMIN_EMAIL"
export AUTO_USERNAME="$ADMIN_USERNAME"
export AUTO_PASSWORD="$ADMIN_PASSWORD"

expect <<'EXPECT_SCRIPT'
set timeout -1

set installer $env(TMP)
set mode $env(AUTO_MODE)

spawn /bin/bash $installer

# ------------------------------------------------------------
# UPSTREAM MAIN MENU
# ------------------------------------------------------------

expect {
    -re {Input 0-[0-9]+:} {
        send "$mode\r"
        exp_continue
    }

    -re {Input [0-9]+-[0-9]+:} {
        send "$mode\r"
        exp_continue
    }

    timeout {
        exit 1
    }

    eof {
        exit
    }
}

EXPECT_SCRIPT

# ------------------------------------------------------------
# CLEANUP
# ------------------------------------------------------------

rm -f "$TMP"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD2
unset AUTO_PASSWORD

echo
echo "============================================================"
echo "            LXJR  INSTALLER SELESAI"
echo "============================================================"
echo

if [ -n "$PANEL_DOMAIN" ]; then
    echo "Panel : https://${PANEL_DOMAIN}"
fi

if [ -n "$NODE_DOMAIN" ]; then
    echo "Node  : ${NODE_DOMAIN}"
fi

echo
echo "============================================================"