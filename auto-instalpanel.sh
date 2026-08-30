#!/usr/bin/env bash

# ============================================================
# PTERODACTYL AUTO INSTALLER
# RELEASE: v1.3.0
#
# MODE:
# 1 = Panel saja
# 2 = Panel + Wings
# 3 = Wings saja
# ============================================================

set -Ee

UPSTREAM_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/v1.3.0/install.sh"
TMP_INSTALLER="/tmp/pterodactyl-installer-v1.3.0.sh"
LOG_FILE="/var/log/pterodactyl-auto-installer.log"

die() {
    echo
    echo "[ERROR] $*"
    echo
    exit 1
}

info() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*"; }

cleanup() { rm -f "$TMP_INSTALLER"; }
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
    die "Script harus dijalankan sebagai root."
fi

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
    [ -n "$domain" ] || return 1
    [[ "$domain" != *" "* ]] || return 1
    [[ "$domain" != *"_"* ]] || return 1
    [[ "$domain" != *".."* ]] || return 1
    [[ "$domain" != .* ]] || return 1
    [[ "$domain" != *. ]] || return 1
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

clear 2>/dev/null || true

echo
echo "============================================================"
echo "              PTERODACTYL AUTO INSTALLER"
echo "                    RELEASE v1.3.0"
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
        1) UPSTREAM_MODE="0"; break ;;
        2) UPSTREAM_MODE="2"; break ;;
        3) UPSTREAM_MODE="1"; break ;;
        *) echo "[!] Masukkan 1, 2, atau 3." ;;
    esac
done

PANEL_DOMAIN=""
NODE_DOMAIN=""
ADMIN_EMAIL=""
ADMIN_USERNAME=""
ADMIN_FIRSTNAME="Admin"
ADMIN_LASTNAME="User"
ADMIN_PASSWORD=""
ADMIN_PASSWORD_CONFIRM=""

if [ "$MODE" = "1" ] || [ "$MODE" = "2" ]; then
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
        read -r -p "Admin/Gmail: " ADMIN_EMAIL
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
    [ -n "$ADMIN_FIRSTNAME" ] || ADMIN_FIRSTNAME="Admin"

    read -r -p "Admin last name [User]: " ADMIN_LASTNAME
    ADMIN_LASTNAME="$(clean_input "${ADMIN_LASTNAME:-User}")"
    [ -n "$ADMIN_LASTNAME" ] || ADMIN_LASTNAME="User"

    while true; do
        read -r -s -p "Admin password: " ADMIN_PASSWORD
        echo

        if [ "${#ADMIN_PASSWORD}" -lt 8 ]; then
            echo "[!] Password minimal 8 karakter."
            continue
        fi

        read -r -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo

        if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
            echo "[!] Password tidak sama."
            continue
        fi

        break
    done
fi

if [ "$MODE" = "2" ] || [ "$MODE" = "3" ]; then
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

echo
echo "============================================================"

case "$MODE" in
    1) echo "Mode : PANEL SAJA" ;;
    2) echo "Mode : PANEL + WINGS" ;;
    3) echo "Mode : WINGS SAJA" ;;
esac

[ -n "$PANEL_DOMAIN" ] && echo "Panel : $PANEL_DOMAIN"
[ -n "$NODE_DOMAIN" ] && echo "Node  : $NODE_DOMAIN"
[ -n "$ADMIN_EMAIL" ] && echo "Email : $ADMIN_EMAIL"

echo "Timezone : Asia/Jakarta"
echo "Firewall : YES"
echo "HTTPS    : YES"
echo "Telemetry: NO"
echo "============================================================"
echo

read -r -p "Lanjutkan instalasi? [Y/n]: " CONFIRM
CONFIRM="$(clean_input "${CONFIRM:-Y}")"

case "$CONFIRM" in
    ""|Y|y) ;;
    *) echo "Instalasi dibatalkan."; exit 0 ;;
esac

info "Mengambil Pterodactyl Installer v1.3.0..."

rm -f "$TMP_INSTALLER"

curl -fsSL \
    --retry 5 \
    --retry-delay 2 \
    --connect-timeout 20 \
    "$UPSTREAM_URL" \
    -o "$TMP_INSTALLER" ||
    die "Gagal download installer upstream."

sed -i 's/\r$//' "$TMP_INSTALLER"
chmod 700 "$TMP_INSTALLER"

if ! bash -n "$TMP_INSTALLER"; then
    die "Syntax installer upstream rusak."
fi

ok "Syntax installer upstream OK."

export AUTO_MODE="$UPSTREAM_MODE"
export AUTO_PANEL_DOMAIN="$PANEL_DOMAIN"
export AUTO_NODE_DOMAIN="$NODE_DOMAIN"
export AUTO_EMAIL="$ADMIN_EMAIL"
export AUTO_USERNAME="$ADMIN_USERNAME"
export AUTO_FIRSTNAME="$ADMIN_FIRSTNAME"
export AUTO_LASTNAME="$ADMIN_LASTNAME"
export AUTO_PASSWORD="$ADMIN_PASSWORD"
export AUTO_INSTALLER="$TMP_INSTALLER"

info "Menjalankan installer Pterodactyl..."
echo

expect <<'EXPECT_SCRIPT' 2>&1 | tee -a "$LOG_FILE"

set timeout -1

set installer "$env(AUTO_INSTALLER)"
set mode "$env(AUTO_MODE)"
set panel_domain "$env(AUTO_PANEL_DOMAIN)"
set node_domain "$env(AUTO_NODE_DOMAIN)"
set email "$env(AUTO_EMAIL)"
set username "$env(AUTO_USERNAME)"
set firstname "$env(AUTO_FIRSTNAME)"
set lastname "$env(AUTO_LASTNAME)"
set password "$env(AUTO_PASSWORD)"

spawn /bin/bash "$installer"

expect {
    -re {.*Input 0-[0-9]+: *$} {
        send -- "$mode\r"
        exp_continue
    }

    -re {.*Are you sure you want to proceed\? *\(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {.*Database name \(panel\): *$} {
        send -- "panel\r"
        exp_continue
    }

    -re {.*Database username \(pterodactyl\): *$} {
        send -- "pterodactyl\r"
        exp_continue
    }

    -re {.*Password \(press enter to use randomly generated password\): *$} {
        send -- "\r"
        exp_continue
    }

    -re {.*Select timezone.*: *$} {
        send -- "Asia/Jakarta\r"
        exp_continue
    }

    -re {.*Provide the email address that will be used to configure Let's Encrypt and Pterodactyl: *$} {
        send -- "$email\r"
        exp_continue
    }

    -re {.*Email address for the initial admin account: *$} {
        send -- "$email\r"
        exp_continue
    }

    -re {.*Username for the initial admin account: *$} {
        send -- "$username\r"
        exp_continue
    }

    -re {.*First name for the initial admin account: *$} {
        send -- "$firstname\r"
        exp_continue
    }

    -re {.*Last name for the initial admin account: *$} {
        send -- "$lastname\r"
        exp_continue
    }

    -re {.*Password for the initial admin account: *$} {
        send -- "$password\r"
        exp_continue
    }

    -re {.*Set the FQDN of this panel.*: *$} {
        send -- "$panel_domain\r"
        exp_continue
    }

    -re {.*Do you want to automatically configure UFW.*firewall.*\? *\(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {.*Do you want to automatically configure firewall-cmd.*firewall.*\? *\(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {.*Do you want to automatically configure HTTPS using Let's Encrypt\? *\(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {.*Assume SSL or not\? *\(y/N\): *$} {
        send -- "n\r"
        exp_continue
    }

    -re {.*Enable sending anonymous telemetry data.*} {
        send -- "no\r"
        exp_continue
    }

    -re {.*Initial configuration completed\. Continue with installation\? *\(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {.*Do you agree to the Let's Encrypt Subscriber Agreement.*} {
        send -- "y\r"
        exp_continue
    }

    -re {.*I agree that this HTTPS request is performed.*} {
        send -- "y\r"
        exp_continue
    }

    -re {.*Do you agree.*Let's Encrypt.*} {
        send -- "y\r"
        exp_continue
    }

    -re {.*Still assume SSL\? *\(y/N\): *$} {
        send -- "n\r"
        exp_continue
    }

    -re {.*Do you want to proceed to wings installation\? *\(y/N\): *$} {
        if {$mode == "2"} {
            send -- "y\r"
        } else {
            send -- "n\r"
        }
        exp_continue
    }

    -re {.*Do you want to automatically configure a user for database hosts\? *\(y/N\): *$} {
        send -- "n\r"
        exp_continue
    }

    -re {.*Set the FQDN to use for Let's Encrypt.*: *$} {
        send -- "$node_domain\r"
        exp_continue
    }

    -re {.*Do you still want to automatically configure HTTPS using Let's Encrypt\? *\(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {.*Enter email address for Let's Encrypt: *$} {
        send -- "$email\r"
        exp_continue
    }

    -re {.*Proceed with installation\? *\(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {.*order to register.*ACME.*} {
        send -- "y\r"
        exp_continue
    }
    # ========================================================
    # UNIVERSAL Y/N HANDLER
    # ========================================================
    # Semua prompt dengan format (y/N) otomatis dijawab Y.
    -re {(?i).*\([yY]/[nN]\).*} {
        send -- "y\r"
        exp_continue
    }
    -re {.*Proceed anyways.*\(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }



    eof {
        catch wait result
        set exit_code [lindex $result 3]

        if {$exit_code == 0} {
            exit 0
        }

        exit $exit_code
    }

    timeout {
        puts stderr ""
        puts stderr {[ERROR] Installer timeout.}
        exit 124
    }
}

EXPECT_SCRIPT

EXPECT_STATUS=${PIPESTATUS[0]}

if [ "$EXPECT_STATUS" -ne 0 ]; then
    echo
    echo "============================================================"
    echo "[ERROR] Installer upstream gagal."
    echo "[ERROR] Exit code: $EXPECT_STATUS"
    echo "============================================================"
    echo
    echo "Log:"
    echo "$LOG_FILE"
    echo
    exit "$EXPECT_STATUS"
fi

if [ "$MODE" = "1" ] || [ "$MODE" = "2" ]; then
    if [ -f "/var/www/pterodactyl/artisan" ]; then
        ok "Pterodactyl Panel berhasil terdeteksi."
    else
        die "Panel tidak ditemukan di /var/www/pterodactyl."
    fi
fi

if [ "$MODE" = "2" ] || [ "$MODE" = "3" ]; then
    if [ -x "/usr/local/bin/wings" ] || [ -x "/usr/bin/wings" ]; then
        ok "Wings berhasil terdeteksi."
    else
        warn "Binary Wings tidak ditemukan."
    fi

    echo
    echo "============================================================"
    echo "                    WINGS NEXT STEP"
    echo "============================================================"
    echo
    echo "Node domain:"
    echo "$NODE_DOMAIN"
    echo
    echo "Buat Node di Panel lalu gunakan Auto Deploy."
    echo
    echo "File yang harus tersedia:"
    echo "/etc/pterodactyl/config.yml"
    echo
    echo "Setelah config.yml tersedia:"
    echo
    echo "systemctl daemon-reload"
    echo "systemctl enable --now wings"
    echo
    echo "============================================================"
    echo
fi

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset AUTO_PASSWORD

echo
echo "============================================================"
echo "                 INSTALASI SELESAI"
echo "============================================================"
echo

if [ -n "$PANEL_DOMAIN" ]; then
    echo "Panel : https://$PANEL_DOMAIN"
fi

if [ -n "$NODE_DOMAIN" ]; then
    echo "Node  : $NODE_DOMAIN"
fi

echo

case "$MODE" in
    1) echo "Panel saja selesai." ;;
    2)
        echo "Panel + Wings selesai dipasang."
        echo "Wings menunggu config.yml dari Node Panel."
        ;;
    3)
        echo "Wings saja selesai dipasang."
        echo "Wings menunggu config.yml dari Node Panel."
        ;;
esac

echo
echo "Log:"
echo "$LOG_FILE"
