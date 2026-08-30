#!/usr/bin/env bash

# ============================================================
# PTERODACTYL AUTO INSTALLER
# Full wrapper - upstream installer v1.3.0
# ============================================================

set -Eeuo pipefail

INSTALLER_URL="https://pterodactyl-installer.se"
TMP_INSTALLER="/tmp/pterodactyl-upstream.sh"

# ------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# ROOT
# ------------------------------------------------------------

if [[ "$(id -u)" != "0" ]]; then
    die "Script harus dijalankan sebagai root."
fi

# ------------------------------------------------------------
# NORMALIZE INPUT
# ------------------------------------------------------------

clean_input() {
    local value="${1-}"

    value="${value//$'\r'/}"

    # trim leading whitespace
    value="${value#"${value%%[![:space:]]*}"}"

    # trim trailing whitespace
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

# ------------------------------------------------------------
# VALIDATION
# ------------------------------------------------------------

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

    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1

    return 0
}

valid_email() {
    local email

    email="$(clean_input "${1-}")"

    [[ "$email" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]
}

# ------------------------------------------------------------
# CHECK COMMAND
# ------------------------------------------------------------

install_package() {
    local package="$1"

    if command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$package"

    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "$package"

    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$package"

    else
        die "Package manager tidak didukung."
    fi
}

# ------------------------------------------------------------
# REQUIREMENTS
# ------------------------------------------------------------

command -v curl >/dev/null 2>&1 || {
    info "Menginstall curl..."
    install_package curl
}

command -v ca-certificates >/dev/null 2>&1 || true

if ! command -v expect >/dev/null 2>&1; then
    info "Menginstall expect..."
    install_package expect
fi

command -v bash >/dev/null 2>&1 ||
    die "Bash tidak ditemukan."

command -v sed >/dev/null 2>&1 ||
    die "sed tidak ditemukan."

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
            echo "[!] Pilihan harus 1, 2, atau 3."
            ;;

    esac

done

# ------------------------------------------------------------
# VARIABLES
# ------------------------------------------------------------

PANEL_DOMAIN=""
NODE_DOMAIN=""

ADMIN_EMAIL=""
ADMIN_USERNAME=""
ADMIN_FIRSTNAME=""
ADMIN_LASTNAME=""
ADMIN_PASSWORD=""

# ------------------------------------------------------------
# PANEL INPUT
# ------------------------------------------------------------

if [[ "$MODE" == "1" || "$MODE" == "2" ]]; then

    echo
    echo "================ PANEL ================="

    while true; do

        read -r -p "Panel subdomain: " PANEL_DOMAIN
        PANEL_DOMAIN="$(clean_input "$PANEL_DOMAIN")"

        if valid_domain "$PANEL_DOMAIN"; then
            break
        fi

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

        echo "[!] Email tidak valid."
        echo

    done

    while true; do

        read -r -p "Admin username: " ADMIN_USERNAME
        ADMIN_USERNAME="$(clean_input "$ADMIN_USERNAME")"

        if [[ "$ADMIN_USERNAME" =~ ^[A-Za-z0-9._-]{3,32}$ ]]; then
            break
        fi

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

        read -r -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo

        if [[ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]]; then
            echo "[!] Password tidak sama."
            continue
        fi

        break

    done

fi

# ------------------------------------------------------------
# NODE INPUT
# ------------------------------------------------------------

if [[ "$MODE" == "2" || "$MODE" == "3" ]]; then

    echo
    echo "================ WINGS / NODE ================="

    while true; do

        read -r -p "Node subdomain: " NODE_DOMAIN
        NODE_DOMAIN="$(clean_input "$NODE_DOMAIN")"

        if valid_domain "$NODE_DOMAIN"; then
            break
        fi

        echo "[!] Domain tidak valid."
        echo "    Contoh: node.example.com"
        echo

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

[[ -n "$PANEL_DOMAIN" ]] && \
    echo "Panel: $PANEL_DOMAIN"

[[ -n "$NODE_DOMAIN" ]] && \
    echo "Node : $NODE_DOMAIN"

[[ -n "$ADMIN_EMAIL" ]] && \
    echo "Email: $ADMIN_EMAIL"

echo "Timezone: Asia/Jakarta"
echo "Telemetry: NO"
echo "Let's Encrypt: YES"
echo "Firewall: YES"

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

# ------------------------------------------------------------
# DOWNLOAD UPSTREAM
# ------------------------------------------------------------

info "Mengambil installer Pterodactyl terbaru..."

rm -f "$TMP_INSTALLER"

curl -fL --retry 3 --connect-timeout 15 \
    "$INSTALLER_URL" \
    -o "$TMP_INSTALLER" ||
    die "Gagal download installer Pterodactyl."

# ------------------------------------------------------------
# REMOVE CRLF
# ------------------------------------------------------------

sed -i 's/\r$//' "$TMP_INSTALLER"

chmod 700 "$TMP_INSTALLER"

# ------------------------------------------------------------
# SYNTAX CHECK
# ------------------------------------------------------------

if ! /bin/bash -n "$TMP_INSTALLER"; then
    die "Installer upstream memiliki syntax error."
fi

ok "Installer upstream valid."

# ------------------------------------------------------------
# ENVIRONMENT FOR EXPECT
# ------------------------------------------------------------

export AUTO_UPSTREAM_MODE="$UPSTREAM_MODE"
export AUTO_PANEL_DOMAIN="$PANEL_DOMAIN"
export AUTO_NODE_DOMAIN="$NODE_DOMAIN"
export AUTO_ADMIN_EMAIL="$ADMIN_EMAIL"
export AUTO_ADMIN_USERNAME="$ADMIN_USERNAME"
export AUTO_ADMIN_FIRSTNAME="$ADMIN_FIRSTNAME"
export AUTO_ADMIN_LASTNAME="$ADMIN_LASTNAME"
export AUTO_ADMIN_PASSWORD="$ADMIN_PASSWORD"
export AUTO_INSTALLER="$TMP_INSTALLER"

# ------------------------------------------------------------
# RUN UPSTREAM
# ------------------------------------------------------------

info "Menjalankan installer Pterodactyl..."
echo

expect <<'EXPECT_EOF'

set timeout -1

set installer $env(AUTO_INSTALLER)
set mode     $env(AUTO_UPSTREAM_MODE)

set panel_domain  $env(AUTO_PANEL_DOMAIN)
set node_domain   $env(AUTO_NODE_DOMAIN)

set admin_email     $env(AUTO_ADMIN_EMAIL)
set admin_username  $env(AUTO_ADMIN_USERNAME)
set admin_firstname $env(AUTO_ADMIN_FIRSTNAME)
set admin_lastname  $env(AUTO_ADMIN_LASTNAME)
set admin_password  $env(AUTO_ADMIN_PASSWORD)

spawn /bin/bash $installer

# ============================================================
# MAIN UPSTREAM MENU
# ============================================================

expect {
    -re {Input 0-[0-9]+: *$} {
        send -- "$mode\r"
        exp_continue
    }

    -re {\* Input 0-[0-9]+: *$} {
        send -- "$mode\r"
        exp_continue
    }

    # Existing panel
    -re {Are you sure you want to proceed\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # Existing wings
    -re {Are you sure you want to proceed\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # PANEL DATABASE
    # ========================================================

    -re {Database name \(panel\): *$} {
        send -- "panel\r"
        exp_continue
    }

    -re {Database username \(pterodactyl\): *$} {
        send -- "pterodactyl\r"
        exp_continue
    }

    -re {Password \(press enter to use randomly generated password\): *$} {
        send -- "\r"
        exp_continue
    }

    # ========================================================
    # TIMEZONE
    # ========================================================

    -re {Select timezone \[Europe/Stockholm\]: *$} {
        send -- "Asia/Jakarta\r"
        exp_continue
    }

    # ========================================================
    # PANEL EMAIL
    # ========================================================

    -re {Provide the email address that will be used to configure Let's Encrypt and Pterodactyl: *$} {
        send -- "$admin_email\r"
        exp_continue
    }

    # ========================================================
    # ADMIN
    # ========================================================

    -re {Email address for the initial admin account: *$} {
        send -- "$admin_email\r"
        exp_continue
    }

    -re {Username for the initial admin account: *$} {
        send -- "$admin_username\r"
        exp_continue
    }

    -re {First name for the initial admin account: *$} {
        send -- "$admin_firstname\r"
        exp_continue
    }

    -re {Last name for the initial admin account: *$} {
        send -- "$admin_lastname\r"
        exp_continue
    }

    -re {Password for the initial admin account: *$} {
        send -- "$admin_password\r"
        exp_continue
    }

    # ========================================================
    # PANEL FQDN
    # ========================================================

    -re {Set the FQDN of this panel \(panel\.example\.com\): *$} {
        send -- "$panel_domain\r"
        exp_continue
    }

    # ========================================================
    # FIREWALL
    # ========================================================

    -re {Configure firewall\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {Would you like to configure the firewall\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {configure UFW\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # LET'S ENCRYPT
    # ========================================================

    -re {Do you want to automatically configure HTTPS using Let's Encrypt\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # ASSUME SSL
    # ========================================================

    -re {Assume SSL or not\? \(y/N\): *$} {
        send -- "n\r"
        exp_continue
    }

    # ========================================================
    # TELEMETRY
    # ========================================================

    -re {Enable sending anonymous telemetry data\? \(yes/no\) \[yes\]: *$} {
        send -- "no\r"
        exp_continue
    }

    # ========================================================
    # PANEL FINAL CONFIRMATION
    # ========================================================

    -re {Initial configuration completed\. Continue with installation\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # UPSTREAM PANEL -> WINGS
    # ========================================================

    -re {Do you want to proceed to wings installation\? \(y/N\): *$} {
        if {$mode == "2"} {
            send -- "y\r"
        } else {
            send -- "n\r"
        }
        exp_continue
    }

    # ========================================================
    # WINGS FIREWALL
    # ========================================================

    -re {Configure firewall\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {Would you like to configure the firewall\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {configure UFW\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # WINGS DATABASE HOST
    # ========================================================

    -re {Do you want to automatically configure a user for database hosts\? \(y/N\): *$} {
        send -- "n\r"
        exp_continue
    }

    # ========================================================
    # WINGS SSL
    # ========================================================

    -re {Do you want to automatically configure HTTPS using Let's Encrypt\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {Set the FQDN to use for Let's Encrypt \(node\.example\.com\): *$} {
        send -- "$node_domain\r"
        exp_continue
    }

    -re {Enter email address for Let's Encrypt: *$} {
        send -- "$admin_email\r"
        exp_continue
    }

    # ========================================================
    # WINGS FINAL
    # ========================================================

    -re {Proceed with installation\? \(y/N\): *$} {
        send -- "y\r"
        exp_continue
    }

    # ========================================================
    # END
    # ========================================================

    eof {
        catch wait result
        exit 0
    }

    timeout {
        puts stderr "\n[ERROR] Timeout menunggu installer upstream."
        exit 124
    }
}

EXPECT_EOF

EXPECT_STATUS=$?

if [[ "$EXPECT_STATUS" != "0" ]]; then
    die "Installer upstream gagal. Exit code: $EXPECT_STATUS"
fi

ok "Installer upstream selesai."

# ------------------------------------------------------------
# PANEL CHECK
# ------------------------------------------------------------

if [[ "$MODE" == "1" || "$MODE" == "2" ]]; then

    if [[ ! -f "/var/www/pterodactyl/artisan" ]]; then
        die "Panel tidak ditemukan di /var/www/pterodactyl."
    fi

    ok "Pterodactyl Panel terdeteksi."
fi

# ------------------------------------------------------------
# WINGS CHECK
# ------------------------------------------------------------

if [[ "$MODE" == "2" || "$MODE" == "3" ]]; then

    if [[ ! -f "/usr/bin/wings" && ! -f "/usr/local/bin/wings" ]]; then
        echo "[WARN] Binary Wings tidak ditemukan."
    else
        ok "Wings terdeteksi."
    fi

    echo
    echo "============================================================"
    echo "                 KONFIGURASI WINGS"
    echo "============================================================"
    echo
    echo "Buat Node di Panel:"
    echo "  $PANEL_DOMAIN"
    echo
    echo "Setelah Node dibuat, buka tab Installation/Auto Deploy"
    echo "dan paste command Auto-Deploy yang diberikan Panel."
    echo
    echo "Command tersebut akan membuat:"
    echo "  /etc/pterodactyl/config.yml"
    echo
    echo "============================================================"
    echo

    while true; do

        read -r -p "Auto-Deploy command (ENTER untuk skip): " WINGS_COMMAND
        WINGS_COMMAND="$(clean_input "$WINGS_COMMAND")"

        if [[ -z "$WINGS_COMMAND" ]]; then
            echo
            echo "[INFO] Auto-Deploy dilewati."
            echo "[INFO] Wings belum akan dijalankan."
            break
        fi

        echo
        echo "[INFO] Menjalankan Auto-Deploy command..."
        echo

        # Jalankan command yang diberikan user.
        bash -c "$WINGS_COMMAND"

        if [[ ! -f "/etc/pterodactyl/config.yml" ]]; then
            echo
            echo "[WARN] /etc/pterodactyl/config.yml belum ditemukan."
            echo "[WARN] Periksa Auto-Deploy command."
            echo
            continue
        fi

        ok "config.yml Wings ditemukan."

        echo
        info "Mengaktifkan dan menjalankan Wings..."

        systemctl daemon-reload

        systemctl enable wings

        systemctl restart wings

        sleep 3

        if systemctl is-active --quiet wings; then
            ok "Wings berhasil running."
        else
            echo
            echo "[WARN] Wings gagal running."
            echo
            systemctl status wings --no-pager || true
        fi

        break

    done

fi

# ------------------------------------------------------------
# FINAL
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                 LXJR OFFC INSTALASI SELESAI"
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
    echo "Panel saja sudah selesai."
fi

if [[ "$MODE" == "2" ]]; then
    echo "Panel + Wings sudah dipasang."
    echo "Jika Auto-Deploy sudah dijalankan, Wings sudah di-start."
fi

if [[ "$MODE" == "3" ]]; then
    echo "Wings sudah dipasang."
fi

echo
echo "============================================================"