#!/usr/bin/env bash
set -Eeuo pipefail
set +H

============================================================

PTERODACTYL AUTO INSTALLER

PANEL + OPTIONAL WINGS

============================================================

INSTALLER_URL="https://pterodactyl-installer.se"
TMP_INSTALLER="/tmp/pterodactyl-installer.sh"
LOG_FILE="/var/log/pterodactyl-auto-installer.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $"; }
ok()    { echo -e "${GREEN}[✓]${NC} $"; }
warn()  { echo -e "${YELLOW}[!]${NC} $"; }
die()   { echo -e "${RED}[ERROR]${NC} $"; exit 1; }

============================================================

ROOT

============================================================

[[ "$EUID" -eq 0 ]] || die "Jalankan sebagai root."

============================================================

OS

============================================================

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

============================================================

DOMAIN CHECK

============================================================

clean_input() {
local value="$1"

value="${value//$'\r'/}"
value="${value#"${value%%[![:space:]]*}"}"
value="${value%"${value##*[![:space:]]}"}"

printf '%s' "$value"

}

valid_domain() {
local d
d="$(clean_input "$1")"

[[ "$d" == *.* ]] &&
[[ "$d" != *" "* ]] &&
[[ "$d" != *"_"* ]] &&
[[ "$d" =~ ^[A-Za-z0-9.-]+$ ]] &&
[[ "$d" != .* ]] &&
[[ "$d" != *. ]] &&
[[ "$d" != *..* ]]

}

============================================================

HEADER

============================================================

clear

echo
echo "============================================================"
echo "             PTERODACTYL AUTO INSTALLER"
echo "============================================================"
echo
echo "OS : ${PRETTY}"
echo
echo "============================================================"
echo

============================================================

PANEL DOMAIN

============================================================

read -rp "Panel domain: " PANEL_DOMAIN
PANEL_DOMAIN="$(clean_input "$PANEL_DOMAIN")"

[[ -n "$PANEL_DOMAIN" ]] || die "Panel domain kosong."
valid_domain "$PANEL_DOMAIN" || die "Panel domain tidak valid: ${PANEL_DOMAIN}"

============================================================

WINGS

============================================================

read -rp "Install Wings/Node? [Y/n]: " INSTALL_WINGS
INSTALL_WINGS="$(clean_input "${INSTALL_WINGS:-Y}")"

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

============================================================

NODE DOMAIN

============================================================

NODE_DOMAIN=""

if [[ "$INSTALL_WINGS" == "yes" ]]; then

read -rp "Node domain: " NODE_DOMAIN
NODE_DOMAIN="$(clean_input "$NODE_DOMAIN")"

[[ -n "$NODE_DOMAIN" ]] || die "Node domain kosong."
valid_domain "$NODE_DOMAIN" || die "Node domain tidak valid: ${NODE_DOMAIN}"

fi

============================================================

ADMIN EMAIL

============================================================

read -rp "Admin email/Gmail: " ADMIN_EMAIL
ADMIN_EMAIL="$(clean_input "$ADMIN_EMAIL")"

[[ "$ADMIN_EMAIL" == @.* ]] || die "Email tidak valid."

============================================================

ADMIN USER

============================================================

read -rp "Admin username: " ADMIN_USERNAME
ADMIN_USERNAME="$(clean_input "$ADMIN_USERNAME")"

[[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9._-]{3,32}$ ]] ||
die "Username tidak valid."

============================================================

ADMIN FIRST/LAST NAME

============================================================

read -rp "Admin first name [Admin]: " ADMIN_FIRSTNAME
ADMIN_FIRSTNAME="${ADMIN_FIRSTNAME:-Admin}"

read -rp "Admin last name [User]: " ADMIN_LASTNAME
ADMIN_LASTNAME="${ADMIN_LASTNAME:-User}"

============================================================

PASSWORD

============================================================

read -rsp "Admin password: " ADMIN_PASSWORD
echo

[[ ${#ADMIN_PASSWORD} -ge 8 ]] ||
die "Password minimal 8 karakter."

read -rsp "Confirm password: " ADMIN_PASSWORD_CONFIRM
echo

[[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]] ||
die "Password tidak sama."

============================================================

SUMMARY

============================================================

echo
echo "============================================================"
echo "                    CONFIGURATION"
echo "============================================================"
echo
echo "Panel : ${PANEL_DOMAIN}"
echo "Email : ${ADMIN_EMAIL}"
echo "User  : ${ADMIN_USERNAME}"
echo "Wings : ${INSTALL_WINGS}"

if [[ "$INSTALL_WINGS" == "yes" ]]; then
echo "Node  : ${NODE_DOMAIN}"
fi

echo
echo "============================================================"
echo

read -rp "Lanjut? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"

[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 0

============================================================

LOG

============================================================

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

============================================================

CURL

============================================================

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

command -v curl >/dev/null 2>&1 ||
die "curl tidak tersedia."

============================================================

PUBLIC IP

============================================================

SERVER_IP="$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || true)"

echo
info "VPS IP: ${SERVER_IP:-unknown}"
echo

echo "DNS yang diperlukan:"
echo
echo "  ${PANEL_DOMAIN} -> ${SERVER_IP}"

if [[ "$INSTALL_WINGS" == "yes" ]]; then
echo "  ${NODE_DOMAIN}  -> ${SERVER_IP}"
fi

echo

============================================================

DOWNLOAD UPSTREAM INSTALLER

============================================================

info "Downloading Pterodactyl installer..."

curl -fsSL "$INSTALLER_URL" -o "$TMP_INSTALLER" ||
die "Gagal download installer."

chmod +x "$TMP_INSTALLER"

ok "Installer downloaded."

============================================================

PANEL VARIABLES

============================================================

export FQDN="$PANEL_DOMAIN"
export EMAIL="$ADMIN_EMAIL"

export user_email="$ADMIN_EMAIL"
export user_username="$ADMIN_USERNAME"
export user_firstname="$ADMIN_FIRSTNAME"
export user_lastname="$ADMIN_LASTNAME"
export user_password="$ADMIN_PASSWORD"

export timezone="Asia/Jakarta"

Disable anonymous telemetry where supported

export ANONYMOUS_TELEMETRY="false"
export SEND_TELEMETRY="false"
export TELEMETRY="false"

export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_FIREWALL="false"

============================================================

PANEL

============================================================

echo
echo "============================================================"
echo "                 INSTALLING PANEL"
echo "============================================================"
echo

bash "$TMP_INSTALLER"

============================================================

PANEL FINISHED

============================================================

echo
echo "============================================================"
echo "                  PANEL SELESAI"
echo "============================================================"
echo
ok "Panel selesai."

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

============================================================

WINGS NO

============================================================

if [[ "$INSTALL_WINGS" == "no" ]]; then

rm -f "$TMP_INSTALLER"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset user_password

echo
ok "Wings dilewati."
exit 0

fi

============================================================

WINGS

============================================================

echo
echo "============================================================"
echo "                   INSTALLING WINGS"
echo "============================================================"
echo

export FQDN="$NODE_DOMAIN"
export EMAIL="$ADMIN_EMAIL"
export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_FIREWALL="false"

Run upstream installer and select Wings

printf '1\n' | bash "$TMP_INSTALLER"

echo
ok "Wings installer selesai."

============================================================

AUTO DEPLOY

============================================================

echo
echo "============================================================"
echo "                 NODE CONFIGURATION"
echo "============================================================"
echo
echo "Node:"
echo "  ${NODE_DOMAIN}"
echo
echo "Setelah Node dibuat di Panel:"
echo
echo "  Admin -> Nodes -> ${NODE_DOMAIN} -> Configuration"
echo
echo "Paste command Auto-Deploy dari Panel."
echo

read -rsp "Auto-Deploy command: " WINGS_COMMAND
echo

if [[ -n "$WINGS_COMMAND" ]]; then

echo
info "Applying Wings configuration..."

bash -c "$WINGS_COMMAND"

ok "Wings configuration applied."

else

warn "Auto-Deploy kosong."

fi

============================================================

CONFIG CHECK

============================================================

if [[ -f /etc/pterodactyl/config.yml ]]; then
ok "config.yml ditemukan."
else
warn "config.yml belum ditemukan."
fi

============================================================

SYSTEMCTL

============================================================

echo
echo "============================================================"
echo "                    STARTING WINGS"
echo "============================================================"
echo

systemctl daemon-reload
ok "daemon-reload"

systemctl enable wings
ok "Wings enabled"

if [[ -f /etc/pterodactyl/config.yml ]]; then

systemctl start wings

sleep 2

if systemctl is-active --quiet wings; then
    ok "Wings RUNNING"
else

    warn "Wings gagal start."

    echo
    systemctl status wings --no-pager || true

    echo
    journalctl -u wings -n 50 --no-pager || true

fi

else

warn "Wings tidak distart karena config.yml belum tersedia."

fi

============================================================

CLEANUP

============================================================

rm -f "$TMP_INSTALLER"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset user_password
unset WINGS_COMMAND

============================================================

FINAL

============================================================

echo
echo "============================================================"
echo "               INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Panel:"
echo "  https://${PANEL_DOMAIN}"
echo

if [[ "$INSTALL_WINGS" == "yes" ]]; then
echo "Node:"
echo "  ${NODE_DOMAIN}"
echo
fi

echo "Admin:"
echo "  ${ADMIN_USERNAME}"
echo "  ${ADMIN_EMAIL}"
echo
echo "Anonymous telemetry: NO"
echo
echo "Log:"
echo "  ${LOG_FILE}"
echo
echo "============================================================"
echo

ok "LXJR OFFC Selesai."