#!/usr/bin/env bash
set -Eeuo pipefail
set +H

============================================================

PTERODACTYL AUTO INSTALLER - FINAL

One-line execution:

bash <(curl -fsSL https://raw.githubusercontent.com/manziero/installpanel/main/auto-instalpanel.sh)

Flow:

1. Ask all basic configuration first

2. Install Pterodactyl Panel

3. Ask/prepare Wings

4. Install Wings when requested

5. Apply official Node Auto-Deploy command

6. systemctl enable/start wings

Anonymous telemetry: OFF where supported

============================================================

INSTALLER_URL="https://pterodactyl-installer.se"
TMP_INSTALLER="/tmp/pterodactyl-installer.sh"
LOG_FILE="/var/log/pterodactyl-auto-installer.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

============================================================

ROOT

============================================================

if [[ "${EUID}" -ne 0 ]]; then
die "Script harus dijalankan sebagai root."
fi

============================================================

OS DETECTION

============================================================

if [[ ! -f /etc/os-release ]]; then
die "/etc/os-release tidak ditemukan."
fi

source /etc/os-release

OS="${ID:-}"
VERSION="${VERSION_ID:-}"
PRETTY="${PRETTY_NAME:-${OS} ${VERSION}}"

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

almalinux:8)
    ;;

almalinux:9)
    ;;

*)
    die "OS tidak didukung: ${PRETTY}"
    ;;

esac

============================================================

ARCHITECTURE

============================================================

ARCH="$(uname -m)"

case "${ARCH}" in
x86_64|amd64)
;;

aarch64|arm64)
    ;;

*)
    die "Architecture tidak didukung: ${ARCH}"
    ;;

esac

============================================================

INPUT CLEANER

============================================================

clean_input() {
local value="$1"

value="${value//$'\r'/}"

# trim leading whitespace
value="${value#"${value%%[![:space:]]*}"}"

# trim trailing whitespace
value="${value%"${value##*[![:space:]]}"}"

printf '%s' "${value}"

}

============================================================

DOMAIN VALIDATION

============================================================

valid_domain() {
local domain

domain="$(clean_input "$1")"

[[ -n "${domain}" ]] || return 1

[[ "${domain}" != *" "* ]] || return 1
[[ "${domain}" != *"_"* ]] || return 1
[[ "${domain}" != *".."* ]] || return 1
[[ "${domain}" != .* ]] || return 1
[[ "${domain}" != *. ]] || return 1

[[ "${domain}" =~ ^[A-Za-z0-9.-]+$ ]] || return 1

[[ "${domain}" == *.* ]] || return 1

return 0

}

============================================================

EMAIL VALIDATION

============================================================

valid_email() {
local email

email="$(clean_input "$1")"

[[ "${email}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]

}

============================================================

HEADER

============================================================

clear

echo
echo "============================================================"
echo "              PTERODACTYL AUTO INSTALLER"
echo "============================================================"
echo
echo "OS           : ${PRETTY}"
echo "Architecture : ${ARCH}"
echo "Telemetry    : OFF"
echo
echo "============================================================"
echo

============================================================

PANEL DOMAIN

============================================================

while true; do

read -r -p "Panel domain: " PANEL_DOMAIN

PANEL_DOMAIN="$(clean_input "${PANEL_DOMAIN}")"

if valid_domain "${PANEL_DOMAIN}"; then
    break
fi

warn "Domain tidak valid."
echo "Contoh: panel.example.com"
echo

done

============================================================

WINGS Y/N

============================================================

while true; do

read -r -p "Install Wings/Node? [Y/n]: " INSTALL_WINGS

INSTALL_WINGS="$(clean_input "${INSTALL_WINGS:-Y}")"

case "${INSTALL_WINGS}" in

    Y|y)
        INSTALL_WINGS="yes"
        break
        ;;

    N|n)
        INSTALL_WINGS="no"
        break
        ;;

    *)
        warn "Masukkan Y atau N."
        ;;

esac

done

============================================================

NODE DOMAIN

============================================================

NODE_DOMAIN=""

if [[ "${INSTALL_WINGS}" == "yes" ]]; then

while true; do

    read -r -p "Node domain: " NODE_DOMAIN

    NODE_DOMAIN="$(clean_input "${NODE_DOMAIN}")"

    if valid_domain "${NODE_DOMAIN}"; then
        break
    fi

    warn "Node domain tidak valid."
    echo "Contoh: node.example.com"
    echo

done

fi

============================================================

ADMIN EMAIL

============================================================

while true; do

read -r -p "Admin email/Gmail: " ADMIN_EMAIL

ADMIN_EMAIL="$(clean_input "${ADMIN_EMAIL}")"

if valid_email "${ADMIN_EMAIL}"; then
    break
fi

warn "Email tidak valid."

done

============================================================

ADMIN USERNAME

============================================================

while true; do

read -r -p "Admin username: " ADMIN_USERNAME

ADMIN_USERNAME="$(clean_input "${ADMIN_USERNAME}")"

if [[ "${ADMIN_USERNAME}" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
    break
fi

warn "Username tidak valid."

done

============================================================

ADMIN FIRST NAME

============================================================

read -r -p "Admin first name [Admin]: " ADMIN_FIRSTNAME
ADMIN_FIRSTNAME="$(clean_input "${ADMIN_FIRSTNAME:-Admin}")"

============================================================

ADMIN LAST NAME

============================================================

read -r -p "Admin last name [User]: " ADMIN_LASTNAME
ADMIN_LASTNAME="$(clean_input "${ADMIN_LASTNAME:-User}")"

============================================================

PASSWORD

============================================================

while true; do

read -r -s -p "Admin password: " ADMIN_PASSWORD
echo

if [[ "${#ADMIN_PASSWORD}" -lt 8 ]]; then
    warn "Password minimal 8 karakter."
    continue
fi

read -r -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
echo

if [[ "${ADMIN_PASSWORD}" != "${ADMIN_PASSWORD_CONFIRM}" ]]; then
    warn "Password tidak sama."
    continue
fi

break

done

============================================================

SUMMARY

============================================================

echo
echo "============================================================"
echo "                    CONFIGURATION"
echo "============================================================"
echo
echo "Panel domain : ${PANEL_DOMAIN}"
echo "Admin email  : ${ADMIN_EMAIL}"
echo "Admin user   : ${ADMIN_USERNAME}"
echo "Wings        : ${INSTALL_WINGS}"

if [[ "${INSTALL_WINGS}" == "yes" ]]; then
echo "Node domain  : ${NODE_DOMAIN}"
fi

echo
echo "Anonymous telemetry : NO"
echo "SSL                 : YES"
echo
echo "============================================================"
echo

read -r -p "Mulai instalasi? [Y/n]: " CONFIRM
CONFIRM="$(clean_input "${CONFIRM:-Y}")"

if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
warn "Instalasi dibatalkan."
exit 0
fi

============================================================

LOG

============================================================

touch "${LOG_FILE}"
chmod 600 "${LOG_FILE}"

============================================================

CURL

============================================================

if ! command -v curl >/dev/null 2>&1; then

info "Menginstall curl..."

case "${OS}" in

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

command -v curl >/dev/null 2>&1 ||
die "curl gagal diinstall."

============================================================

PUBLIC IP

============================================================

SERVER_IP="$(curl -4 -fsSL https://api.ipify.org 2>/dev/null || true)"

echo
info "Public IP: ${SERVER_IP:-unknown}"
echo

if [[ -n "${SERVER_IP}" ]]; then

echo "DNS yang harus diarahkan:"
echo
echo "  ${PANEL_DOMAIN} -> ${SERVER_IP}"

if [[ "${INSTALL_WINGS}" == "yes" ]]; then
    echo "  ${NODE_DOMAIN}  -> ${SERVER_IP}"
fi

echo

fi

============================================================

DOWNLOAD UPSTREAM

============================================================

info "Mengambil installer Pterodactyl upstream..."

rm -f "${TMP_INSTALLER}"

curl -fsSL 
"${INSTALLER_URL}" 
-o "${TMP_INSTALLER}" ||
die "Gagal mengambil installer Pterodactyl."

[[ -s "${TMP_INSTALLER}" ]] ||
die "Installer kosong."

chmod +x "${TMP_INSTALLER}"

success "Installer berhasil diambil."

============================================================

EXPORT CONFIG

============================================================

export FQDN="${PANEL_DOMAIN}"
export EMAIL="${ADMIN_EMAIL}"

export user_email="${ADMIN_EMAIL}"
export user_username="${ADMIN_USERNAME}"
export user_firstname="${ADMIN_FIRSTNAME}"
export user_lastname="${ADMIN_LASTNAME}"
export user_password="${ADMIN_PASSWORD}"

export timezone="Asia/Jakarta"

telemetry

export ANONYMOUS_TELEMETRY="false"
export SEND_TELEMETRY="false"
export TELEMETRY="false"

SSL

export CONFIGURE_LETSENCRYPT="true"

Don't let wrapper modify firewall

export CONFIGURE_FIREWALL="false"

============================================================

IMPORTANT

We do NOT pipe "0" into the upstream installer.

The upstream installer is interactive and needs its own

prompts. We launch it through Bash normally.

============================================================

echo
echo "============================================================"
echo "                 PTERODACTYL PANEL"
echo "============================================================"
echo

info "Installer upstream akan dibuka sekarang."
info "Ikuti prompt yang ditampilkan oleh installer."

echo

bash "${TMP_INSTALLER}"

PANEL_RESULT=$?

if [[ "${PANEL_RESULT}" -ne 0 ]]; then
die "Installer Panel gagal dengan exit code ${PANEL_RESULT}."
fi

============================================================

PANEL COMPLETE

============================================================

echo
echo "============================================================"
echo "                  PANEL SELESAI"
echo "============================================================"
echo

success "Panel installation finished."

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

WINGS SKIP

============================================================

if [[ "${INSTALL_WINGS}" == "no" ]]; then

rm -f "${TMP_INSTALLER}"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset user_password

echo
success "Wings dilewati."
echo

exit 0

fi

============================================================

WINGS INSTALL

============================================================

echo
echo "============================================================"
echo "                    WINGS INSTALL"
echo "============================================================"
echo

export FQDN="${NODE_DOMAIN}"
export EMAIL="${ADMIN_EMAIL}"

export CONFIGURE_LETSENCRYPT="true"
export CONFIGURE_FIREWALL="false"

info "Installer Wings akan dibuka sekarang."
info "Ikuti prompt Wings dari installer upstream."

echo

bash "${TMP_INSTALLER}"

WINGS_RESULT=$?

if [[ "${WINGS_RESULT}" -ne 0 ]]; then

warn "Wings installer gagal."

echo
echo "Panel tetap tersedia:"
echo "https://${PANEL_DOMAIN}"
echo

exit "${WINGS_RESULT}"

fi

success "Wings installer selesai."

============================================================

NODE CONFIGURATION

============================================================

echo
echo "============================================================"
echo "                 NODE CONFIGURATION"
echo "============================================================"
echo

echo "Node domain:"
echo
echo "  ${NODE_DOMAIN}"
echo

echo "Sekarang buat Node di Panel:"
echo
echo "  Admin Area"
echo "      -> Nodes"
echo "      -> Create New"
echo
echo "FQDN:"
echo
echo "  ${NODE_DOMAIN}"
echo
echo "Setelah Node dibuat:"
echo
echo "  Configuration"
echo "      -> Generate / Auto Deploy"
echo
echo "Paste command Auto-Deploy yang diberikan Panel."
echo

read -r -p "Auto-Deploy command (ENTER untuk skip): " WINGS_COMMAND

WINGS_COMMAND="$(clean_input "${WINGS_COMMAND}")"

============================================================

NO COMMAND

============================================================

if [[ -z "${WINGS_COMMAND}" ]]; then

warn "Auto-Deploy dilewati."

echo
echo "Setelah config Node tersedia, jalankan:"
echo
echo "  systemctl daemon-reload"
echo "  systemctl enable --now wings"
echo

rm -f "${TMP_INSTALLER}"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset user_password
unset WINGS_COMMAND

exit 0

fi

============================================================

EXECUTE NODE AUTO DEPLOY

============================================================

echo
info "Menjalankan Auto-Deploy command..."

bash -c "${WINGS_COMMAND}"

DEPLOY_RESULT=$?

if [[ "${DEPLOY_RESULT}" -ne 0 ]]; then

warn "Auto-Deploy command gagal."

echo
echo "Cek:"
echo
echo "  /etc/pterodactyl/config.yml"
echo

exit "${DEPLOY_RESULT}"

fi

success "Konfigurasi Node berhasil diterapkan."

============================================================

CONFIG CHECK

============================================================

echo
info "Checking Wings config..."

if [[ -f /etc/pterodactyl/config.yml ]]; then

success "/etc/pterodactyl/config.yml ditemukan."

else

warn "config.yml tidak ditemukan."
warn "Wings tidak akan dijalankan."

exit 1

fi

============================================================

SYSTEMD

============================================================

echo
echo "============================================================"
echo "                   STARTING WINGS"
echo "============================================================"
echo

info "systemctl daemon-reload"
systemctl daemon-reload

success "daemon-reload selesai."

info "systemctl enable wings"
systemctl enable wings

success "Wings enabled."

info "systemctl start wings"
systemctl start wings

sleep 2

============================================================

STATUS

============================================================

echo
info "Checking Wings status..."

if systemctl is-active --quiet wings; then

success "Wings is RUNNING."

else

warn "Wings gagal running."

echo
echo "========== SYSTEMCTL STATUS =========="
systemctl status wings --no-pager || true

echo
echo "========== WINGS JOURNAL =========="
journalctl -u wings -n 50 --no-pager || true

fi

============================================================

CLEANUP

============================================================

rm -f "${TMP_INSTALLER}"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset user_password
unset WINGS_COMMAND

============================================================

FINAL

============================================================

echo
echo "============================================================"
echo "             PTERODACTYL INSTALLATION DONE"
echo "============================================================"
echo
echo "Panel:"
echo "  https://${PANEL_DOMAIN}"
echo

if [[ -n "${NODE_DOMAIN}" ]]; then
echo "Node:"
echo "  ${NODE_DOMAIN}"
echo
fi

echo "Admin:"
echo "  ${ADMIN_USERNAME}"
echo "  ${ADMIN_EMAIL}"
echo

echo "Telemetry:"
echo "  OFF"
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
echo

success "LXJR OFFC Selesai."