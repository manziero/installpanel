#!/usr/bin/env bash

# ============================================================
# PTERODACTYL AUTO INSTALLER
# Panel / Wings / Panel + Wings
# Upstream Pterodactyl Installer v1.3.0
# ============================================================

set -Eeuo pipefail

UPSTREAM_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh"
TMP_INSTALLER="/tmp/pterodactyl-upstream.sh"

# ============================================================
# FUNCTIONS
# ============================================================

die() {
    echo
    echo "[ERROR] $*"
    echo
    exit 1
}

info() {
    echo "[INFO] $*"
}

ok() {
    echo "[OK] $*"
}

cleanup() {
    rm -f "$TMP_INSTALLER"
}

trap cleanup EXIT

clean_input() {
    local value="${1-}"

    value="${value//$'\r'/}"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

valid_domain() {
    local domain

    domain="$(clean_input "${1-}")"

    [[ -n "$domain" ]] || return 1
    [[ "$domain" != *" "* ]] || return 1
    [[ "$domain" != *"_"* ]] || return 1
    [[ "$domain" != *".."* ]] || return 1
    [[ "$domain" != .* ]] || return 1
    [[ "$domain" != *. ]] || return 1
    [[ "$domain" == *.* ]] || return 1

    [[ "$domain" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$ ]]
}

valid_email() {
    local email

    email="$(clean_input "${1-}")"

    [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]
}

install_package() {
    local package="$1"

    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive

        apt-get update
        apt-get install -y "$package"

    elif command -v dnf >/dev/null 2>&1; then

        dnf install -y "$package"

    elif command -v yum >/dev/null 2>&1; then

        yum install -y "$package"

    else
        die "Package manager tidak didukung."
    fi
}

# ============================================================
# ROOT
# ============================================================

if [[ "$(id -u)" != "0" ]]; then
    die "Jalankan script sebagai root."
fi

# ============================================================
# REQUIREMENTS
# ============================================================

if ! command -v curl >/dev/null 2>&1; then
    info "Menginstall curl..."
    install_package curl
fi

if ! command -v sed >/dev/null 2>&1; then
    die "sed tidak ditemukan."
fi

if ! command -v bash >/dev/null 2>&1; then
    die "bash tidak ditemukan."
fi

if ! command -v expect >/dev/null 2>&1; then
    info "Menginstall expect..."

    install_package expect
fi

# ============================================================
# MENU
# ============================================================

clear 2>/dev/null || true

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
    MODE="$(clean_input "$MODE")"

    case "$MODE" in

        1)
            UPSTREAM_MODE="0"
            break
            ;;

        2)
            UPSTREAM_MODE="2"
            break
            ;;

        3)
            UPSTREAM_MODE="1"
            break
            ;;

        *)
            echo "[!] Pilihan hanya 1, 2, atau 3."
            ;;

    esac

done

# ============================================================
# VARIABLES
# ============================================================

PANEL_DOMAIN=""
NODE_DOMAIN=""

ADMIN_EMAIL=""
ADMIN_USERNAME=""
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="User"

ADMIN_PASSWORD=""
ADMIN_PASSWORD_CONFIRM=""

# ============================================================
# PANEL INPUT
# ============================================================

if [[ "$MODE" == "1" || "$MODE" == "2" ]]; then

    echo
    echo "================ PANEL ================="
    echo

    while true; do

        read -r -p "Panel subdomain: " PANEL_DOMAIN
        PANEL_DOMAIN="$(clean_input "$PANEL_DOMAIN")"

        if valid_domain "$PANEL_DOMAIN"; then
            break
        fi

        echo
        echo "[!] Domain tidak valid."
        echo "    Contoh: panel.example.com"
        echo

    done

    while true; do

        read -r -p "Admin email/Gmail: " ADMIN_EMAIL
        ADMIN_EMAIL="$(clean_input "$ADMIN_EMAIL")"

        if valid_email "$ADMIN_EMAIL"; then
            break
        fi

        echo
        echo "[!] Email tidak valid."
        echo

    done

    while true; do

        read -r -p "Admin username: " ADMIN_USERNAME
        ADMIN_USERNAME="$(clean_input "$ADMIN_USERNAME")"

        if [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
            break
        fi

        echo
        echo "[!] Username tidak valid."
        echo

    done

    read -r -p "Admin first name [Admin]: " ADMIN_FIRSTNAME
    ADMIN_FIRSTNAME="$(clean_input "${ADMIN_FIRSTNAME:-Admin}")"

    [[ -n "$ADMIN_FIRSTNAME" ]] || ADMIN_FIRSTNAME="Admin"

    read -r -p "Admin last name [User]: " ADMIN_LASTNAME
    ADMIN_LASTNAME="$(clean_input "${ADMIN_LASTNAME:-User}")"

    [[ -n "$ADMIN_LASTNAME" ]] || ADMIN_LASTNAME="User"

    while true; do

        read -r -s -p "Admin password: " ADMIN_PASSWORD
        echo

        if [[ "${#ADMIN_PASSWORD}" -lt 8 ]]; then
            echo "[!] Password minimal 8 karakter."
            continue
        fi

        read -r -s -p "Confirm password: " ADMIN_PASSWORD_CONFIRM
        echo

        if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
            echo "[!] Password tidak sama."
            continue
        fi

        break

    done

fi

# ============================================================
# WINGS INPUT
# ============================================================

if [[ "$MODE" == "2" || "$MODE" == "3" ]]; then

    echo
    echo "================ WINGS / NODE ================="
    echo

    while true; do

        read -r -p "Node subdomain: " NODE_DOMAIN
        NODE_DOMAIN="$(clean_input "$NODE_DOMAIN")"

        if valid_domain "$NODE_DOMAIN"; then
            break
        fi

        echo
        echo "[!] Node domain tidak valid."
        echo "    Contoh: node.example.com"
        echo

    done

fi

# Wings-only tetap membutuhkan email apabila Let's Encrypt diaktifkan.
if [[ "$MODE" == "3" ]]; then

    while true; do

        read -r -p "Email untuk Let's Encrypt: " ADMIN_EMAIL
        ADMIN_EMAIL="$(clean_input "$ADMIN_EMAIL")"

        if valid_email "$ADMIN_EMAIL"; then
            break
        fi

        echo
        echo "[!] Email tidak valid."
        echo

    done

fi

# ============================================================
# SUMMARY
# ============================================================

echo
echo "============================================================"

case "$MODE" in

    1)
        echo "Mode        : PANEL SAJA"
        ;;

    2)
        echo "Mode        : PANEL + WINGS"
        ;;

    3)
        echo "Mode        : WINGS SAJA"
        ;;

esac

[[ -n "$PANEL_DOMAIN" ]] && \
    echo "Panel       : $PANEL_DOMAIN"

[[ -n "$NODE_DOMAIN" ]] && \
    echo "Node        : $NODE_DOMAIN"

[[ -n "$ADMIN_EMAIL" ]] && \
    echo "Email       : $ADMIN_EMAIL"

echo "Timezone    : Asia/Jakarta"
echo "Firewall    : YES"
echo "Let's Encrypt: YES"
echo "Telemetry   : NO"

echo "============================================================"
echo

read -r -p "Lanjutkan instalasi? [Y/n]: " CONFIRM
CONFIRM="$(clean_input "${CONFIRM:-Y}")"

case "$CONFIRM" in

    "")
        ;;

    Y|y)
        ;;

    *)
        echo "Instalasi dibatalkan."
        exit 0
        ;;

esac

# ============================================================
# DOWNLOAD UPSTREAM
# ============================================================

info "Mengambil installer Pterodactyl..."

rm -f "$TMP_INSTALLER"

curl -fL \
    --retry 3 \
    --retry-delay 2 \
    --connect-timeout 20 \
    "$UPSTREAM_URL" \
    -o "$TMP_INSTALLER" ||
    die "Gagal mengambil installer Pterodactyl."

# ============================================================
# FIX CRLF
# ============================================================

sed -i 's/\r$//' "$TMP_INSTALLER"

chmod 700 "$TMP_INSTALLER"

# ============================================================
# SYNTAX CHECK
# ============================================================

if ! /bin/bash -n "$TMP_INSTALLER"; then

    echo
    echo "[ERROR] Syntax installer upstream tidak valid."
    echo

    exit 1

fi

ok "Installer upstream valid."

# ============================================================
# EXPORT EXPECT VARIABLES
# ============================================================

export AUTO_INSTALLER="$TMP_INSTALLER"
export AUTO_MODE="$UPSTREAM_MODE"

export AUTO_PANEL_DOMAIN="$PANEL_DOMAIN"
export AUTO_NODE_DOMAIN="$NODE_DOMAIN"

export AUTO_EMAIL="$ADMIN_EMAIL"

export AUTO_USERNAME="$ADMIN_USERNAME"
export AUTO_FIRSTNAME="$ADMIN_FIRSTNAME"
export AUTO_LASTNAME="$ADMIN_LASTNAME"
export AUTO_PASSWORD="$ADMIN_PASSWORD"

# ============================================================
# EXPECT
# ============================================================

info "Menjalankan installer Pterodactyl..."
echo

expect <<'EXPECT_SCRIPT'

set timeout -1

set installer $env(AUTO_INSTALLER)
set mode      $env(AUTO_MODE)

set panel_domain $env(AUTO_PANEL_DOMAIN)
set node_domain  $env(AUTO_NODE_DOMAIN)

set email        $env(AUTO_EMAIL)

set username     $env(AUTO_USERNAME)
set firstname    $env(AUTO_FIRSTNAME)
set lastname     $env(AUTO_LASTNAME)
set password     $env(AUTO_PASSWORD)

spawn /bin/bash $installer

# ============================================================
# MAIN MENU
# ============================================================

expect {

    -re {\* Input 0-[0-9]+: *$} {
        send -- "$mode\r"
        exp_continue
    }

    -re {Input 0-[0-9]+: *$} {
        send -- "$mode\r"
        exp_continue
    }

    # ========================================================
    # EXISTING INSTALLATION
    # ========================================================

    -re {\* Are you sure you want to proceed\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {\* Are you sure you want to proceed\? \(y/N\):} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # PANEL DATABASE
    # ========================================================

    -re {\* Database name \(panel\): *$} {
        send -- "panel\r"
        exp_continue
    }

    -re {\* Database username \(pterodactyl\): *$} {
        send -- "pterodactyl\r"
        exp_continue
    }

    -re {\* Password \(press enter to use randomly generated password\): *$} {
        send -- "\r"
        exp_continue
    }

    # ========================================================
    # TIMEZONE
    # ========================================================

    -re {\* Select timezone \[Europe/Stockholm\]: *$} {
        send -- "Asia/Jakarta\r"
        exp_continue
    }

    # ========================================================
    # PANEL EMAIL
    # ========================================================

    -re {\* Provide the email address that will be used to configure Let's Encrypt and Pterodactyl: *$} {
        send -- "$email\r"
        exp_continue
    }

    -re {\* Email address for the initial admin account: *$} {
        send -- "$email\r"
        exp_continue
    }

    # ========================================================
    # ADMIN
    # ========================================================

    -re {\* Username for the initial admin account: *$} {
        send -- "$username\r"
        exp_continue
    }

    -re {\* First name for the initial admin account: *$} {
        send -- "$firstname\r"
        exp_continue
    }

    -re {\* Last name for the initial admin account: *$} {
        send -- "$lastname\r"
        exp_continue
    }

    -re {\* Password for the initial admin account: *$} {
        send -- "$password\r"
        exp_continue
    }

    # ========================================================
    # PANEL FQDN
    # ========================================================

    -re {\* Set the FQDN of this panel \(panel\.example\.com\): *$} {
        send -- "$panel_domain\r"
        exp_continue
    }

    # ========================================================
    # UFW
    # ========================================================

    -re {\* Do you want to automatically configure UFW \(firewall\)\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # FIREWALL-CMD
    # ========================================================

    -re {\* Do you want to automatically configure firewall-cmd \(firewall\)\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # LET'S ENCRYPT
    # ========================================================

    -re {\* Do you want to automatically configure HTTPS using Let's Encrypt\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # ASSUME SSL
    # ========================================================

    -re {\* Assume SSL or not\? \(y/N\): *$} {
        send -- "n\r"
        exp_continue
    }

    # ========================================================
    # TELEMETRY
    # ========================================================

    -re {\* Enable sending anonymous telemetry data\? \(yes/no\) \[yes\]: *$} {
        send -- "no\r"
        exp_continue
    }

    # ========================================================
    # PANEL CONFIRM
    # ========================================================

    -re {\* Initial configuration completed\. Continue with installation\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # PANEL -> WINGS
    # ========================================================

    -re {\* Installation of panel completed\. Do you want to proceed to wings installation\? \(y/N\): *$} {

        if {$mode == "2"} {
            send -- "y\r"
        } else {
            send -- "n\r"
        }

        exp_continue
    }

    # ========================================================
    # WINGS FIREWALL UFW
    # ========================================================

    -re {\* Do you want to automatically configure UFW \(firewall\)\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # WINGS FIREWALLD
    # ========================================================

    -re {\* Do you want to automatically configure firewall-cmd \(firewall\)\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # DATABASE HOST
    # ========================================================

    -re {\* Do you want to automatically configure a user for database hosts\? \(y/N\): *$} {
        send -- "n\r"
        exp_continue
    }

    # ========================================================
    # WINGS LET'S ENCRYPT
    # ========================================================

    -re {\* Do you want to automatically configure HTTPS using Let's Encrypt\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # WINGS FQDN
    # ========================================================

    -re {\* Set the FQDN to use for Let's Encrypt \(node\.example\.com\): *$} {
        send -- "$node_domain\r"
        exp_continue
    }

    # ========================================================
    # WINGS EMAIL
    # ========================================================

    -re {\* Enter email address for Let's Encrypt: *$} {
        send -- "$email\r"
        exp_continue
    }

    # ========================================================
    # WINGS FINAL CONFIRM
    # ========================================================

    -re {\* Proceed with installation\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # UNSUPPORTED VIRTUALIZATION
    # ========================================================

    -re {\* Are you sure you want to proceed\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # END
    # ========================================================

    eof {
        catch wait result

        if {[lindex $result 3] != 0} {
            exit [lindex $result 3]
        }

        exit 0
    }

    timeout {
        puts stderr ""
        puts stderr "[ERROR] Installer timeout."
        exit 124
    }
}

EXPECT_SCRIPT

EXPECT_STATUS=$?

# ============================================================
# EXPECT RESULT
# ============================================================

if [[ "$EXPECT_STATUS" != "0" ]]; then

    echo
    echo "[ERROR] Installer berhenti dengan exit code: $EXPECT_STATUS"
    echo

    exit "$EXPECT_STATUS"

fi

# ============================================================
# PANEL CHECK
# ============================================================

if [[ "$MODE" == "1" || "$MODE" == "2" ]]; then

    if [[ ! -f "/var/www/pterodactyl/artisan" ]]; then

        echo
        echo "[ERROR] Panel belum ditemukan:"
        echo "/var/www/pterodactyl/artisan"
        echo

        exit 1

    fi

    ok "Pterodactyl Panel berhasil terdeteksi."

fi

# ============================================================
# WINGS CHECK
# ============================================================

if [[ "$MODE" == "2" || "$MODE" == "3" ]]; then

    echo
    echo "============================================================"
    echo "                    WINGS SELESAI"
    echo "============================================================"
    echo

    if [[ -f "/usr/bin/wings" ]]; then
        ok "Wings binary ditemukan."
    elif [[ -f "/usr/local/bin/wings" ]]; then
        ok "Wings binary ditemukan."
    else
        echo "[WARN] Binary Wings tidak ditemukan."
    fi

    echo
    echo "PENTING:"
    echo "Wings membutuhkan config.yml dari Node Panel."
    echo
    echo "Buat Node di Panel lalu gunakan Auto Deploy."
    echo
    echo "Contoh lokasi config:"
    echo "/etc/pterodactyl/config.yml"
    echo

fi

# ============================================================
# CLEAN
# ============================================================

rm -f "$TMP_INSTALLER"

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset AUTO_PASSWORD

# ============================================================
# FINAL
# ============================================================

echo
echo "============================================================"
echo "              LXJR OFFC INSTALASI PTERODACTYL SELESAI"
echo "============================================================"
echo

if [[ -n "$PANEL_DOMAIN" ]]; then
    echo "Panel : https://$PANEL_DOMAIN"
fi

if [[ -n "$NODE_DOMAIN" ]]; then
    echo "Node  : $NODE_DOMAIN"
fi

echo

if [[ "$MODE" == "1" ]]; then
    echo "Panel saja selesai."
fi

if [[ "$MODE" == "2" ]]; then
    echo "Panel + Wings selesai."
    echo "Buat Node dan pasang config.yml Wings dari Panel."
fi

if [[ "$MODE" == "3" ]]; then
    echo "Wings saja selesai."
    echo "Pasang config.yml dari Panel sebelum menjalankan Wings."
fi

echo
echo "================