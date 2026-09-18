#!/usr/bin/env bash

# ============================================================
# PTERODACTYL AUTO INSTALLER
# RELEASE: v1.3.0
#
# MODE:
# 1  = Panel saja
# 2  = Panel + Wings
# 3  = Wings saja
# 4  = Database saja
# 5  = phpMyAdmin saja
# 6  = Database + phpMyAdmin
# 7  = Ganti Subdomain Panel
# 8  = Uninstall Panel
# 9  = Uninstall Wings/Node
# 10 = Uninstall Panel + Wings/Node
# ============================================================

set -Ee

UPSTREAM_URL="https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/v1.3.0/install.sh"
TMP_INSTALLER="/tmp/pterodactyl-installer-v1.3.0.sh"
LOG_FILE="/var/log/pterodactyl-auto-installer.log"
EXPECT_SCRIPT_FILE="/tmp/pterodactyl-expect-$$.exp"

die() {
    echo
    echo "[ERROR] $*"
    echo
    exit 1
}

info() { echo "[INFO] $*"; }
ok() { echo "[OK] $*"; }
warn() { echo "[WARN] $*"; }

cleanup() { rm -f "$TMP_INSTALLER" "$EXPECT_SCRIPT_FILE" 2>/dev/null || true; }
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

random_suffix() {
    # Usage: random_suffix [panjang]  -> string acak huruf kecil+angka
    local len="${1:-5}"
    local out
    out="$(tr -dc 'a-z0-9' </dev/urandom 2>/dev/null | head -c "$len")"
    if [ -z "$out" ]; then
        # fallback kalau /dev/urandom tidak tersedia
        out="$(( RANDOM % 900000 + 100000 ))"
        out="${out:0:$len}"
    fi
    printf '%s' "$out"
}

detect_total_memory_mb() {
    # Ambil total RAM fisik VPS dalam MB dari /proc/meminfo
    local mem
    mem="$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)"
    if [ -n "$mem" ] && [ "$mem" -gt 0 ] 2>/dev/null; then
        printf '%s' "$mem"
    else
        printf '0'
    fi
}

detect_total_disk_mb() {
    # Ambil total disk partisi root (/) dalam MB
    local disk
    disk="$(df -BM --output=size / 2>/dev/null | tail -n 1 | tr -dc '0-9')"
    if [ -n "$disk" ] && [ "$disk" -gt 0 ] 2>/dev/null; then
        printf '%s' "$disk"
    else
        printf '0'
    fi
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

json_get_field() {
    # Ambil satu field top-level dari JSON pakai python3 (lebih aman daripada regex sed/grep).
    # Usage: json_get_field '<json>' 'key1.key2' (dot notation sederhana, tanpa array index)
    local json="$1"
    local path="$2"
    python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)
path = sys.argv[2].split(".")
cur = data
try:
    for p in path:
        cur = cur[p]
    if cur is None:
        sys.exit(1)
    print(cur)
except (KeyError, TypeError, IndexError):
    sys.exit(1)
' "$json" "$path" 2>/dev/null
}

panel_api_call() {
    # Usage: panel_api_call METHOD PATH [JSON_BODY]
    # Cetak "HTTP_CODE|||BODY" ke stdout. Butuh PANEL_ADDRESS_API & PANEL_API_KEY.
    local method="$1"
    local path="$2"
    local body="${3-}"
    local resp http_code resp_body

    if [ -n "$body" ]; then
        resp="$(curl -sS -o /tmp/panel_api_resp.$$ -w "%{http_code}" \
            -X "$method" "${PANEL_ADDRESS_API}${path}" \
            -H "Authorization: Bearer ${PANEL_API_KEY}" \
            -H "Content-Type: application/json" \
            -H "Accept: Application/vnd.pterodactyl.v1+json" \
            --data "$body" 2>/dev/null)"
    else
        resp="$(curl -sS -o /tmp/panel_api_resp.$$ -w "%{http_code}" \
            -X "$method" "${PANEL_ADDRESS_API}${path}" \
            -H "Authorization: Bearer ${PANEL_API_KEY}" \
            -H "Accept: Application/vnd.pterodactyl.v1+json" 2>/dev/null)"
    fi

    http_code="$resp"
    resp_body="$(cat /tmp/panel_api_resp.$$ 2>/dev/null)"
    rm -f /tmp/panel_api_resp.$$

    printf '%s|||%s' "$http_code" "$resp_body"
}

auto_generate_panel_api_key() {
    # Bikin Application API Key otomatis dengan bootstrap langsung ke aplikasi
    # Laravel Panel (tanpa "php artisan tinker" - itu bisa NGEGANTUNG karena
    # tinker jatuh ke mode interaktif kalau stdin bukan TTY). Hanya jalan kalau
    # Panel ada di server yang sama (MODE 2) karena butuh akses filesystem Panel.
    # Hasil disimpan di variabel global AUTOKEY_RESULT (kosong kalau gagal).
    AUTOKEY_RESULT=""

    [ -f /var/www/pterodactyl/artisan ] || return 1
    [ -f /var/www/pterodactyl/vendor/autoload.php ] || return 1
    [ -n "$ADMIN_USERNAME" ] || return 1

    local gen_file="/tmp/pterodactyl-autokey-$$.php"
    cat > "$gen_file" <<'PHP_EOF'
<?php
define('LARAVEL_START', microtime(true));

require '/var/www/pterodactyl/vendor/autoload.php';
$app = require '/var/www/pterodactyl/bootstrap/app.php';

$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

try {
    $identifierArg = getenv('AUTOKEY_ADMIN');
    $user = \Pterodactyl\Models\User::where('username', $identifierArg)
        ->orWhere('email', $identifierArg)
        ->first();

    if (!$user || !$user->root_admin) {
        fwrite(STDOUT, "AUTOKEY_FAIL:no_admin_user\n");
        exit(0);
    }

    $service = app(\Pterodactyl\Services\Api\KeyCreationService::class);
    $service->setKeyType(\Pterodactyl\Models\ApiKey::TYPE_APPLICATION);

    // r_locations & r_nodes = 3 (Read + Write), sisanya 0 (None) -> izin minimal
    // yang dibutuhkan untuk auto provisioning Location + Node.
    $key = $service->handle(
        ['user_id' => $user->id, 'memo' => 'auto-provision-installer'],
        ['r_locations' => 3, 'r_nodes' => 3]
    );

    $plain = decrypt($key->token);
    fwrite(STDOUT, "AUTOKEY_OK:" . $key->identifier . $plain . "\n");
} catch (\Throwable $e) {
    fwrite(STDOUT, "AUTOKEY_FAIL:" . $e->getMessage() . "\n");
}
PHP_EOF

    local output
    output="$(cd /var/www/pterodactyl && AUTOKEY_ADMIN="$ADMIN_USERNAME" timeout 30 php "$gen_file" < /dev/null 2>/dev/null)"
    rm -f "$gen_file"

    local line
    line="$(printf '%s\n' "$output" | grep -o 'AUTOKEY_OK:[^[:space:]]*' | tail -n1)"

    if [ -n "$line" ]; then
        AUTOKEY_RESULT="${line#AUTOKEY_OK:}"
        return 0
    fi

    return 1
}

provision_node_via_api() {
    echo
    echo "================ AUTO PROVISION NODE (API) ================="
    echo

    if ! command -v python3 >/dev/null 2>&1; then
        info "Menginstall python3 (dibutuhkan untuk parsing JSON API)..."
        install_package python3
    fi

    local base_domain
    if [ "$MODE" = "2" ]; then
        base_domain="$PANEL_DOMAIN"
    else
        base_domain="${PANEL_ADDRESS#https://}"
        base_domain="${base_domain#http://}"
    fi

    PANEL_ADDRESS_API="https://${base_domain}"

    info "Mengecek koneksi ke Panel API ($PANEL_ADDRESS_API)..."
    local check
    check="$(panel_api_call GET "/api/application/nodes")"
    local check_code="${check%%|||*}"

    if [ "$check_code" != "200" ]; then
        warn "Panel API tidak bisa diakses atau API Key salah (HTTP $check_code)."
        warn "Auto provisioning DIBATALKAN. Lanjut manual lewat panel web."
        return 1
    fi
    ok "Koneksi ke Panel API berhasil."

    # ---------- LOCATION ----------
    local loc_resp loc_code loc_body LOCATION_ID
    info "Membuat Location '$LOCATION_SHORT'..."
    loc_resp="$(panel_api_call POST "/api/application/locations" \
        "$(python3 -c 'import json,sys; print(json.dumps({"short": sys.argv[1], "long": sys.argv[2]}))' "$LOCATION_SHORT" "$LOCATION_LONG")")"
    loc_code="${loc_resp%%|||*}"
    loc_body="${loc_resp#*|||}"

    if [ "$loc_code" = "201" ]; then
        LOCATION_ID="$(json_get_field "$loc_body" "attributes.id")"
        ok "Location baru dibuat (ID: $LOCATION_ID)."
    else
        warn "Location gagal dibuat (HTTP $loc_code), kemungkinan short code sudah dipakai."
        info "Mencoba pakai Location yang sudah ada dengan short '$LOCATION_SHORT'..."

        local list_resp list_body
        list_resp="$(panel_api_call GET "/api/application/locations")"
        list_body="${list_resp#*|||}"

        LOCATION_ID="$(python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
    target = sys.argv[2]
    for item in data.get("data", []):
        attr = item.get("attributes", {})
        if attr.get("short") == target:
            print(attr.get("id"))
            break
except Exception:
    pass
' "$list_body" "$LOCATION_SHORT")"

        if [ -z "$LOCATION_ID" ]; then
            die "Tidak bisa membuat atau menemukan Location. Cek permission API Key (Locations: Read+Write)."
        fi
        ok "Menggunakan Location yang sudah ada (ID: $LOCATION_ID)."
    fi

    # ---------- NODE ----------
    local node_resp node_code node_body NODE_ID
    info "Membuat Node '$NODE_NAME' (fqdn: $NODE_DOMAIN)..."

    local node_payload
    node_payload="$(python3 -c '
import json, sys
name, location_id, fqdn, memory, mem_over, disk, disk_over = sys.argv[1:8]
print(json.dumps({
    "name": name,
    "location_id": int(location_id),
    "fqdn": fqdn,
    "scheme": "https",
    "behind_proxy": False,
    "memory": int(memory),
    "memory_overallocate": int(mem_over),
    "disk": int(disk),
    "disk_overallocate": int(disk_over),
    "upload_size": 100,
    "daemon_sftp": 2022,
    "daemon_listen": 8080,
}))
' "$NODE_NAME" "$LOCATION_ID" "$NODE_DOMAIN" "$NODE_MEMORY" "$NODE_MEMORY_OVERALLOCATE" "$NODE_DISK" "$NODE_DISK_OVERALLOCATE")"

    node_resp="$(panel_api_call POST "/api/application/nodes" "$node_payload")"
    node_code="${node_resp%%|||*}"
    node_body="${node_resp#*|||}"

    if [ "$node_code" = "201" ]; then
        NODE_ID="$(json_get_field "$node_body" "attributes.id")"
        ok "Node baru dibuat (ID: $NODE_ID)."
    else
        warn "Node gagal dibuat (HTTP $node_code), kemungkinan fqdn '$NODE_DOMAIN' sudah terdaftar."
        info "Mencoba pakai Node yang sudah ada dengan fqdn '$NODE_DOMAIN'..."

        local nlist_resp nlist_body
        nlist_resp="$(panel_api_call GET "/api/application/nodes")"
        nlist_body="${nlist_resp#*|||}"

        NODE_ID="$(python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
    target = sys.argv[2]
    for item in data.get("data", []):
        attr = item.get("attributes", {})
        if attr.get("fqdn") == target:
            print(attr.get("id"))
            break
except Exception:
    pass
' "$nlist_body" "$NODE_DOMAIN")"

        if [ -z "$NODE_ID" ]; then
            warn "Response API: $node_body"
            die "Tidak bisa membuat atau menemukan Node. Cek permission API Key (Nodes: Read+Write) & fqdn."
        fi
        ok "Menggunakan Node yang sudah ada (ID: $NODE_ID)."
    fi

    # ---------- AMBIL CONFIG & TULIS config.yml ----------
    info "Mengambil config token Node dari Panel..."
    local cfg_resp cfg_code cfg_body
    cfg_resp="$(panel_api_call GET "/api/application/nodes/${NODE_ID}/configuration")"
    cfg_code="${cfg_resp%%|||*}"
    cfg_body="${cfg_resp#*|||}"

    if [ "$cfg_code" != "200" ]; then
        warn "Response: $cfg_body"
        die "Gagal mengambil configuration Node (HTTP $cfg_code)."
    fi

    mkdir -p /etc/pterodactyl

    if ! python3 -c '
import json, sys, yaml
' >/dev/null 2>&1; then
        info "Menginstall python3-yaml untuk menulis config.yml..."
        install_package python3-yaml 2>/dev/null || pip3 install pyyaml >/dev/null 2>&1 || true
    fi

    python3 -c '
import json, sys
try:
    import yaml
    data = json.loads(sys.argv[1])
    with open(sys.argv[2], "w") as f:
        yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
except ImportError:
    # Fallback: PyYAML tidak ada, tulis JSON murni (config.yml wings kompatibel dengan JSON valid,
    # karena JSON adalah subset dari YAML).
    data = json.loads(sys.argv[1])
    with open(sys.argv[2], "w") as f:
        json.dump(data, f, indent=2)
' "$cfg_body" "/etc/pterodactyl/config.yml"

    if [ ! -s /etc/pterodactyl/config.yml ]; then
        die "Gagal menulis /etc/pterodactyl/config.yml."
    fi

    ok "config.yml berhasil ditulis ke /etc/pterodactyl/config.yml."

    # ---------- START WINGS ----------
    info "Menjalankan systemctl daemon-reload & enable --now wings..."
    systemctl daemon-reload
    systemctl enable --now wings

    sleep 2

    if systemctl is-active --quiet wings; then
        ok "Wings berhasil berjalan dan terhubung ke Node ID $NODE_ID."
    else
        warn "Wings gagal start. Cek log dengan: journalctl -u wings -n 100 --no-pager"
    fi

    echo
    echo "============================================================"
    echo "        AUTO PROVISIONING NODE SELESAI"
    echo "============================================================"
    echo "Location ID : $LOCATION_ID"
    echo "Node ID     : $NODE_ID"
    echo "Node FQDN   : $NODE_DOMAIN"
    echo "Memory      : ${NODE_MEMORY} MB (overallocate ${NODE_MEMORY_OVERALLOCATE}%)"
    echo "Disk        : ${NODE_DISK} MB (overallocate ${NODE_DISK_OVERALLOCATE}%)"
    echo "============================================================"
    echo

    return 0
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

install_database() {
    echo
    echo "================ DATABASE ================="
    echo

    read -r -s -p "MySQL root password (kosongkan jika tanpa password): " MYSQL_ROOT_PASSWORD
    echo

    while true; do
        read -r -p "Username database baru: " DB_USER
        DB_USER="$(clean_input "$DB_USER")"

        if [[ "$DB_USER" =~ ^[A-Za-z0-9_]{3,32}$ ]]; then
            break
        fi

        echo "[!] Username tidak valid. Gunakan huruf/angka/underscore, 3-32 karakter."
    done

    while true; do
        read -r -s -p "Password database (minimal 4 karakter): " DB_PASSWORD
        echo

        if [ "${#DB_PASSWORD}" -lt 4 ]; then
            echo "[!] Password minimal 4 karakter."
            continue
        fi

        read -r -s -p "Confirm password database: " DB_PASSWORD_CONFIRM
        echo

        if [ "$DB_PASSWORD" != "$DB_PASSWORD_CONFIRM" ]; then
            echo "[!] Password tidak sama."
            continue
        fi

        break
    done

    info "Membuat user database '$DB_USER'..."

    if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
        MYSQL_CMD=(mysql -u root -p"$MYSQL_ROOT_PASSWORD")
    else
        MYSQL_CMD=(mysql -u root)
    fi

    # Deteksi apakah ini MariaDB atau MySQL (MariaDB tidak punya mysql_native_password
    # sebagai keyword plugin yang sama; auth plugin defaultnya sudah kompatibel).
    DB_ENGINE_INFO="$("${MYSQL_CMD[@]}" -N -e "SELECT VERSION();" 2>/dev/null)"

    if echo "$DB_ENGINE_INFO" | grep -qi "mariadb"; then
        # MariaDB: auth plugin default sudah kompatibel dengan Panel, tidak perlu dipaksa.
        "${MYSQL_CMD[@]}" <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    else
        # MySQL 8+: paksa mysql_native_password supaya Panel (PHP) bisa connect,
        # karena default caching_sha2_password sering gagal dikenali PHP mysqlnd.
        "${MYSQL_CMD[@]}" <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    fi

    if [ $? -ne 0 ]; then
        unset MYSQL_ROOT_PASSWORD DB_PASSWORD DB_PASSWORD_CONFIRM
        die "Gagal membuat user database. Periksa kembali password root MySQL."
    fi

    ok "User database '$DB_USER' berhasil dibuat/diupdate (host: 127.0.0.1 / localhost)."

    systemctl restart mysql 2>/dev/null || systemctl restart mariadb 2>/dev/null || \
        warn "Gagal restart service MySQL/MariaDB, restart manual jika perlu."
    ok "Service database berhasil direstart."

    echo
    info "Saat bikin 'Database Host' di Panel, gunakan:"
    echo "    Host     : 127.0.0.1"
    echo "    Port     : 3306"
    echo "    Username : $DB_USER"
    echo

    unset MYSQL_ROOT_PASSWORD DB_PASSWORD DB_PASSWORD_CONFIRM
}

install_phpmyadmin() {
    echo
    echo "================ PHPMYADMIN ================="
    echo

    if [ ! -d /var/www/pterodactyl/public ]; then
        die "Direktori /var/www/pterodactyl/public tidak ditemukan. Install Panel terlebih dahulu (mode 1/2)."
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        info "Menginstall unzip..."
        install_package unzip
    fi

    if ! command -v wget >/dev/null 2>&1; then
        info "Menginstall wget..."
        install_package wget
    fi

    local PHPMYADMIN_VERSION="5.2.2"
    info "Mengunduh phpMyAdmin ${PHPMYADMIN_VERSION}..."

    cd /var/www/pterodactyl/public || die "Gagal masuk ke direktori public."

    wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.zip" \
        -O "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.zip" ||
        die "Gagal download phpMyAdmin."

    unzip -q -o "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.zip" ||
        die "Gagal ekstrak phpMyAdmin."

    rm -f "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.zip"
    rm -rf phpmyadmin
    mv "phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages" phpmyadmin

    chown -R www-data:www-data phpmyadmin 2>/dev/null || \
        warn "Gagal set ownership www-data, sesuaikan manual jika perlu."

    ok "phpMyAdmin berhasil dipasang di /var/www/pterodactyl/public/phpmyadmin"
    echo
    echo "Akses via: https://<domain-panel>/phpmyadmin"
    echo
}

confirm_uninstall() {
    local label="$1"
    echo
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo " PERINGATAN: Ini akan MENGHAPUS PERMANEN $label"
    echo " Semua data terkait (file, database, service) akan HILANG"
    echo " dan TIDAK BISA DIKEMBALIKAN kecuali kamu punya backup sendiri."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    read -r -p "Ketik 'HAPUS' (huruf kapital) untuk konfirmasi: " CONFIRM_UNINSTALL
    CONFIRM_UNINSTALL="$(clean_input "$CONFIRM_UNINSTALL")"

    if [ "$CONFIRM_UNINSTALL" != "HAPUS" ]; then
        echo "Dibatalkan. Tidak ada yang dihapus."
        return 1
    fi

    return 0
}

uninstall_panel() {
    echo
    echo "================ UNINSTALL PANEL ================="
    echo

    if ! confirm_uninstall "Pterodactyl Panel (file, database 'panel', config Nginx, cron, queue worker, SSL)"; then
        return 0
    fi

    info "Menghentikan service terkait Panel..."
    systemctl stop nginx 2>/dev/null || true

    local PHP_FPM_SERVICE
    PHP_FPM_SERVICE="$(
        systemctl list-unit-files --type=service --no-legend 'php*-fpm.service' 2>/dev/null |
        awk '{print $1}' | sort -V | tail -n 1
    )"
    [ -n "$PHP_FPM_SERVICE" ] && systemctl stop "$PHP_FPM_SERVICE" 2>/dev/null || true

    info "Menghentikan & menghapus queue worker (pteroq)..."
    systemctl stop pteroq 2>/dev/null || true
    systemctl disable pteroq 2>/dev/null || true
    rm -f /etc/systemd/system/pteroq.service
    systemctl daemon-reload

    info "Menghapus cron job Panel..."
    (crontab -l 2>/dev/null | grep -vE 'pterodactyl|artisan schedule:run' | crontab -) 2>/dev/null || true

    # Ambil daftar domain panel dari .env SEBELUM file-nya dihapus,
    # supaya sertifikat SSL yang benar bisa ditawarkan untuk dihapus juga.
    local PANEL_DOMAIN_DETECTED=""
    if [ -f /var/www/pterodactyl/.env ]; then
        PANEL_DOMAIN_DETECTED="$(grep -E '^APP_URL=' /var/www/pterodactyl/.env 2>/dev/null | \
            head -n1 | sed -E 's#^APP_URL=https?://##; s#/$##' | tr -d '\r\n')"
    fi

    info "Menghapus file Panel di /var/www/pterodactyl..."
    rm -rf /var/www/pterodactyl

    info "Menghapus semua konfigurasi Nginx yang terkait Panel..."
    local f
    for f in /etc/nginx/sites-available/*.conf /etc/nginx/sites-enabled/*.conf /etc/nginx/conf.d/*.conf; do
        [ -e "$f" ] || continue
        if grep -qE 'pterodactyl|/var/www/pterodactyl' "$f" 2>/dev/null; then
            rm -f "$f"
            ok "Dihapus: $f"
        fi
    done

    if command -v mysql >/dev/null 2>&1; then
        read -r -p "Hapus juga database 'panel' beserta user-nya? [y/N]: " DROP_DB
        DROP_DB="$(clean_input "${DROP_DB:-N}")"

        case "$DROP_DB" in
            y|Y)
                read -r -s -p "MySQL root password (kosongkan jika tanpa password): " MYSQL_ROOT_PASSWORD
                echo

                local MYSQL_CMD
                if [ -n "$MYSQL_ROOT_PASSWORD" ]; then
                    MYSQL_CMD=(mysql -u root -p"$MYSQL_ROOT_PASSWORD")
                else
                    MYSQL_CMD=(mysql -u root)
                fi

                "${MYSQL_CMD[@]}" -e "DROP DATABASE IF EXISTS panel;" 2>/dev/null && \
                    ok "Database 'panel' berhasil dihapus." || \
                    warn "Gagal menghapus database 'panel', cek password root MySQL."

                "${MYSQL_CMD[@]}" -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>/dev/null || true
                "${MYSQL_CMD[@]}" -e "DROP USER IF EXISTS 'pterodactyl'@'%';" 2>/dev/null || true
                unset MYSQL_ROOT_PASSWORD
                ;;
            *) info "Database tidak dihapus." ;;
        esac
    fi

    if [ -n "$PANEL_DOMAIN_DETECTED" ] && command -v certbot >/dev/null 2>&1; then
        if certbot certificates 2>/dev/null | grep -q "$PANEL_DOMAIN_DETECTED"; then
            read -r -p "Hapus juga sertifikat SSL Let's Encrypt untuk $PANEL_DOMAIN_DETECTED? [y/N]: " DROP_CERT
            DROP_CERT="$(clean_input "${DROP_CERT:-N}")"

            case "$DROP_CERT" in
                y|Y)
                    certbot delete --cert-name "$PANEL_DOMAIN_DETECTED" --non-interactive 2>/dev/null && \
                        ok "Sertifikat SSL $PANEL_DOMAIN_DETECTED dihapus." || \
                        warn "Gagal menghapus sertifikat SSL $PANEL_DOMAIN_DETECTED."
                    ;;
                *) info "Sertifikat SSL tidak dihapus." ;;
            esac
        fi
    fi

    rm -f /var/log/pterodactyl-auto-installer.log

    if command -v nginx >/dev/null 2>&1; then
        nginx -t >/dev/null 2>&1 && systemctl start nginx 2>/dev/null || \
            warn "Nginx tidak di-start karena config bermasalah (cek 'nginx -t')."
    fi
    [ -n "$PHP_FPM_SERVICE" ] && systemctl start "$PHP_FPM_SERVICE" 2>/dev/null || true

    echo
    info "Verifikasi sisa file/service Panel..."
    local LEFTOVER=()
    [ -d /var/www/pterodactyl ] && LEFTOVER+=("/var/www/pterodactyl")
    [ -f /etc/systemd/system/pteroq.service ] && LEFTOVER+=("/etc/systemd/system/pteroq.service")
    for f in /etc/nginx/sites-available/*.conf /etc/nginx/sites-enabled/*.conf /etc/nginx/conf.d/*.conf; do
        [ -e "$f" ] || continue
        grep -qE 'pterodactyl|/var/www/pterodactyl' "$f" 2>/dev/null && LEFTOVER+=("$f")
    done

    echo
    echo "============================================================"
    echo "                 UNINSTALL PANEL SELESAI"
    echo "============================================================"
    if [ "${#LEFTOVER[@]}" -eq 0 ]; then
        ok "Tidak ada sisa file/config Panel yang ditemukan. Bersih total."
    else
        warn "Masih ada sisa yang GAGAL dihapus (cek permission/mount):"
        printf '  - %s\n' "${LEFTOVER[@]}"
    fi
    echo
}

uninstall_wings() {
    echo
    echo "================ UNINSTALL WINGS/NODE ================="
    echo

    if ! confirm_uninstall "Wings/Node (service, config, SEMUA data & container server game di node ini)"; then
        return 0
    fi

    info "Menghentikan & menonaktifkan service Wings..."
    systemctl stop wings 2>/dev/null || true
    systemctl disable wings 2>/dev/null || true

    if command -v docker >/dev/null 2>&1; then
        echo
        warn "Node ini punya container Docker (server game) yang dikelola Wings."
        read -r -p "Hapus juga SEMUA container + volume + image Docker milik Wings? [y/N]: " DROP_DOCKER
        DROP_DOCKER="$(clean_input "${DROP_DOCKER:-N}")"

        case "$DROP_DOCKER" in
            y|Y)
                info "Menghapus semua container Docker..."
                docker ps -aq 2>/dev/null | xargs -r docker rm -f >/dev/null 2>&1 || true
                ok "Container Docker dihapus."

                info "Menghapus volume Docker menganggur..."
                docker volume prune -f >/dev/null 2>&1 || true
                ok "Volume Docker dibersihkan."

                info "Menghapus network Docker milik Pterodactyl..."
                docker network rm pterodactyl_nw >/dev/null 2>&1 || true

                read -r -p "Hapus juga SEMUA image Docker di server ini (bukan cuma milik Pterodactyl)? [y/N]: " DROP_IMAGES
                DROP_IMAGES="$(clean_input "${DROP_IMAGES:-N}")"
                case "$DROP_IMAGES" in
                    y|Y)
                        docker rmi -f $(docker images -aq) >/dev/null 2>&1 || true
                        ok "Image Docker dihapus."
                        ;;
                    *) info "Image Docker tidak dihapus." ;;
                esac
                ;;
            *) info "Container/volume/image Docker TIDAK dihapus. Data server game masih ada." ;;
        esac
    fi

    info "Menghapus binary, service & log Wings..."
    rm -f /etc/systemd/system/wings.service
    rm -f /usr/local/bin/wings
    rm -f /usr/bin/wings
    rm -rf /var/log/wings*
    systemctl daemon-reload
    systemctl reset-failed wings 2>/dev/null || true

    info "Menghapus config & data volume server game Wings..."
    rm -rf /etc/pterodactyl
    rm -rf /var/lib/pterodactyl

    echo
    info "Verifikasi sisa file/service Wings..."
    local LEFTOVER=()
    [ -d /etc/pterodactyl ] && LEFTOVER+=("/etc/pterodactyl")
    [ -d /var/lib/pterodactyl ] && LEFTOVER+=("/var/lib/pterodactyl")
    [ -f /etc/systemd/system/wings.service ] && LEFTOVER+=("/etc/systemd/system/wings.service")
    { command -v wings >/dev/null 2>&1; } && LEFTOVER+=("binary wings masih ada di PATH")

    echo
    echo "============================================================"
    echo "              UNINSTALL WINGS/NODE SELESAI"
    echo "============================================================"
    if [ "${#LEFTOVER[@]}" -eq 0 ]; then
        ok "Tidak ada sisa file/config Wings yang ditemukan. Bersih total."
    else
        warn "Masih ada sisa yang GAGAL dihapus (cek permission/mount):"
        printf '  - %s\n' "${LEFTOVER[@]}"
    fi
    echo
}

ensure_http_redirect() {
    # Memastikan blok "listen 80" untuk $domain di file config Nginx ini
    # punya redirect otomatis ke HTTPS. Kalau tidak ada, redirect disisipkan.
    # Kalau block listen 80 untuk domain itu SAMA SEKALI tidak ada di file
    # manapun, dianggap perlu ditambah manual (di-return kode 2).
    local file="$1"
    local domain="$2"

    awk -v domain="$domain" '
    BEGIN { depth=0; buf=""; has80=0; hasdomain=0; hasredirect=0 }
    {
        line=$0
        if (depth==0 && line ~ /server[ \t]*\{/) {
            depth=1; buf=line "\n"; has80=0; hasdomain=0; hasredirect=0; next
        }
        if (depth>0) {
            o=gsub(/\{/,"{",line); c=gsub(/\}/,"}",line)
            depth += o - c
            buf = buf line "\n"
            if (line ~ /listen[ \t]+80([ \t;]|$)/) has80=1
            if (index(line, domain) > 0) hasdomain=1
            if (line ~ /return[ \t]+30[128]/ || line ~ /ssl_certificate/) {
                if (line ~ /return[ \t]+30[128]/) hasredirect=1
            }
            if (depth==0) {
                if (has80 && hasdomain && !hasredirect) {
                    n=split(buf, arr, "\n")
                    for (i=1; i<n-1; i++) printf "%s\n", arr[i]
                    printf "    return 301 https://$host$request_uri;\n"
                    printf "%s\n", arr[n-1]
                    print "FOUND_AND_FIXED" > "/dev/stderr"
                } else {
                    printf "%s", buf
                    if (has80 && hasdomain && hasredirect) print "ALREADY_OK" > "/dev/stderr"
                }
                next
            }
            next
        }
        print line
    }
    ' "$file" > "${file}.tmp_redirect" 2>"${file}.tmp_status"

    if grep -q "FOUND_AND_FIXED\|ALREADY_OK" "${file}.tmp_status" 2>/dev/null; then
        mv "${file}.tmp_redirect" "$file"
        rm -f "${file}.tmp_status"
        return 0
    else
        rm -f "${file}.tmp_redirect" "${file}.tmp_status"
        return 2
    fi
}

ganti_subdomain_panel() {
    echo
    echo "================ GANTI SUBDOMAIN PANEL ================="
    echo

    if [ ! -f /var/www/pterodactyl/.env ]; then
        die "File /var/www/pterodactyl/.env tidak ditemukan. Pastikan Panel sudah terinstall."
    fi

    # --- Scan domain yang BENERAN ada di config Nginx (bukan cuma nebak dari .env) ---
    # Ini penting kalau di server ada banyak vhost/domain (multi-tenant),
    # supaya user gak salah ketik domain lama dan bikin proses ganti domain
    # kelewat/gagal diam-diam.
    local NGINX_KNOWN_DOMAINS=()
    local ff sn
    for ff in /etc/nginx/sites-available/*.conf /etc/nginx/sites-enabled/*.conf /etc/nginx/conf.d/*.conf; do
        [ -e "$ff" ] || continue
        while IFS= read -r sn; do
            [ -n "$sn" ] || continue
            case "$sn" in
                _|default_server|localhost|*.local) continue ;;
            esac
            NGINX_KNOWN_DOMAINS+=("$sn")
        done < <(grep -hoE '^\s*server_name\s+[^;]+;' "$ff" 2>/dev/null | \
                  sed -E 's/^\s*server_name\s+//; s/;\s*$//' | tr ' ' '\n')
    done

    NGINX_KNOWN_DOMAINS=($(printf '%s\n' "${NGINX_KNOWN_DOMAINS[@]}" | sort -u))

    if [ "${#NGINX_KNOWN_DOMAINS[@]}" -gt 0 ]; then
        echo "Domain yang terdeteksi di config Nginx server ini:"
        local i=1
        for sn in "${NGINX_KNOWN_DOMAINS[@]}"; do
            echo "  [$i] $sn"
            i=$((i + 1))
        done
        echo
        echo "PENTING: ketik domain lama PERSIS SAMA seperti salah satu di atas."
        echo "Kalau typo dikit aja, Nginx TIDAK akan ikut keganti (sudah pernah kejadian)."
        echo
    else
        warn "Tidak ada 'server_name' terdeteksi di config Nginx manapun. Lanjut dengan hati-hati."
    fi

    local DETECTED_DOMAIN
    DETECTED_DOMAIN="$(grep -E '^APP_URL=' /var/www/pterodactyl/.env 2>/dev/null | \
        head -n1 | sed -E 's#^APP_URL=https?://##; s#/$##' | tr -d '\r\n')"

    OLD_DOMAIN=""

    if [ -n "$DETECTED_DOMAIN" ]; then
        echo "Domain panel saat ini terdeteksi dari .env: $DETECTED_DOMAIN"
        read -r -p "Gunakan domain ini sebagai domain lama? [Y/n]: " USE_DETECTED
        USE_DETECTED="$(clean_input "${USE_DETECTED:-Y}")"

        case "$USE_DETECTED" in
            ""|Y|y) OLD_DOMAIN="$DETECTED_DOMAIN" ;;
            *) ;;
        esac
    fi

    if [ -z "$OLD_DOMAIN" ]; then
        while true; do
            read -r -p "Domain panel lama (ketik PERSIS dari daftar di atas): " OLD_DOMAIN
            OLD_DOMAIN="$(clean_input "$OLD_DOMAIN")"

            if valid_domain "$OLD_DOMAIN"; then
                break
            fi

            echo "[!] Domain tidak valid."
        done
    fi

    # --- VALIDASI KETAT: domain lama HARUS benar-benar ada di Nginx ---
    # Kalau tidak cocok sama sekali, JANGAN lanjut diam-diam (ini akar
    # masalah kenapa dulu Nginx gak ikut keganti). Paksa user perbaiki dulu.
    if [ "${#NGINX_KNOWN_DOMAINS[@]}" -gt 0 ]; then
        local MATCH_FOUND=0
        for sn in "${NGINX_KNOWN_DOMAINS[@]}"; do
            if [ "$sn" = "$OLD_DOMAIN" ]; then
                MATCH_FOUND=1
                break
            fi
        done

        while [ "$MATCH_FOUND" -eq 0 ]; do
            echo
            warn "Domain '$OLD_DOMAIN' TIDAK ditemukan persis di config Nginx manapun."
            warn "Kalau dipaksa lanjut, Nginx TIDAK akan ikut keganti (cuma .env yang berubah) — ini bakal bikin TLS/404 error."
            echo "Domain yang valid:"
            for sn in "${NGINX_KNOWN_DOMAINS[@]}"; do
                echo "  - $sn"
            done
            echo
            read -r -p "Ketik ulang domain lama (persis), atau ketik 'batal' untuk keluar: " OLD_DOMAIN
            OLD_DOMAIN="$(clean_input "$OLD_DOMAIN")"

            if [ "$OLD_DOMAIN" = "batal" ]; then
                echo "Dibatalkan."
                return 0
            fi

            for sn in "${NGINX_KNOWN_DOMAINS[@]}"; do
                if [ "$sn" = "$OLD_DOMAIN" ]; then
                    MATCH_FOUND=1
                    break
                fi
            done
        done
        ok "Domain lama valid & cocok dengan config Nginx: $OLD_DOMAIN"
    fi

    while true; do
        read -r -p "Domain panel baru (contoh: panel-baru.my.id): " NEW_DOMAIN
        NEW_DOMAIN="$(clean_input "$NEW_DOMAIN")"

        if ! valid_domain "$NEW_DOMAIN"; then
            echo "[!] Domain tidak valid."
            continue
        fi

        if [ "$NEW_DOMAIN" = "$OLD_DOMAIN" ]; then
            echo "[!] Domain baru sama dengan domain lama."
            continue
        fi

        break
    done

    echo
    echo "Domain lama : $OLD_DOMAIN"
    echo "Domain baru : $NEW_DOMAIN"
    echo
    read -r -p "Lanjutkan ganti subdomain panel? [Y/n]: " CONFIRM_DOMAIN
    CONFIRM_DOMAIN="$(clean_input "${CONFIRM_DOMAIN:-Y}")"

    case "$CONFIRM_DOMAIN" in
        ""|Y|y) ;;
        *) echo "Dibatalkan."; return 0 ;;
    esac

    local BACKUP_DIR
    BACKUP_DIR="/root/panel-domain-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    local ENV_BACKUP="$BACKUP_DIR/dotenv.bak"
    cp -a /var/www/pterodactyl/.env "$ENV_BACKUP" 2>/dev/null || true

    local -A BACKUP_MAP
    local NGINX_FILES_FOUND=()
    local f idx=0
    for f in /etc/nginx/sites-available/*.conf /etc/nginx/sites-enabled/*.conf /etc/nginx/conf.d/*.conf; do
        [ -e "$f" ] || continue
        if grep -q "$OLD_DOMAIN" "$f" 2>/dev/null; then
            NGINX_FILES_FOUND+=("$f")
            idx=$((idx + 1))
            local bpath="$BACKUP_DIR/nginx_${idx}.bak"
            cp -a "$f" "$bpath" 2>/dev/null || true
            BACKUP_MAP["$bpath"]="$f"
        fi
    done

    if [ "${#NGINX_FILES_FOUND[@]}" -eq 0 ]; then
        die "Tidak ada file config Nginx yang cocok dengan '$OLD_DOMAIN'. Dibatalkan sebelum ada yang berubah sama sekali (mencegah kondisi setengah-jadi)."
    fi

    ok "Backup disimpan di: $BACKUP_DIR"

    # Rollback otomatis kalau ada langkah yang gagal di tengah jalan,
    # supaya panel TIDAK pernah ditinggal dalam kondisi rusak/down.
    rollback_domain_change() {
        warn "Melakukan rollback ke konfigurasi domain lama..."
        cp -a "$ENV_BACKUP" /var/www/pterodactyl/.env 2>/dev/null || true

        local bkey
        for bkey in "${!BACKUP_MAP[@]}"; do
            cp -a "$bkey" "${BACKUP_MAP[$bkey]}" 2>/dev/null || true
        done

        systemctl restart nginx 2>/dev/null || true

        local PHP_FPM_SERVICE_RB
        PHP_FPM_SERVICE_RB="$(
            systemctl list-unit-files --type=service --no-legend 'php*-fpm.service' 2>/dev/null |
            awk '{print $1}' | sort -V | tail -n 1
        )"
        [ -n "$PHP_FPM_SERVICE_RB" ] && systemctl restart "$PHP_FPM_SERVICE_RB" 2>/dev/null || true

        warn "Rollback selesai. Panel tetap berjalan normal di domain lama ($OLD_DOMAIN)."
    }

    # --- Cek DNS domain baru sebelum ubah apa pun ---
    echo
    info "Mengecek apakah DNS $NEW_DOMAIN sudah mengarah ke server ini..."

    local SERVER_IP RESOLVED_IP
    SERVER_IP="$(curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null || curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null)"
    RESOLVED_IP="$(getent ahostsv4 "$NEW_DOMAIN" 2>/dev/null | awk '{print $1}' | head -n1)"

    if [ -z "$RESOLVED_IP" ]; then
        warn "Domain $NEW_DOMAIN belum bisa di-resolve (DNS mungkin belum aktif/propagasi)."
        read -r -p "Tetap lanjutkan? Ini bisa membuat pembuatan SSL gagal. [y/N]: " FORCE_CONTINUE
        FORCE_CONTINUE="$(clean_input "${FORCE_CONTINUE:-N}")"
        case "$FORCE_CONTINUE" in
            y|Y) ;;
            *) echo "Dibatalkan. Arahkan DNS $NEW_DOMAIN ke server ini dulu, lalu jalankan ulang."; return 0 ;;
        esac
    elif [ -n "$SERVER_IP" ] && [ "$SERVER_IP" != "$RESOLVED_IP" ]; then
        warn "DNS $NEW_DOMAIN mengarah ke $RESOLVED_IP, tapi IP server ini $SERVER_IP."
        read -r -p "Tetap lanjutkan? [y/N]: " FORCE_CONTINUE
        FORCE_CONTINUE="$(clean_input "${FORCE_CONTINUE:-N}")"
        case "$FORCE_CONTINUE" in
            y|Y) ;;
            *) echo "Dibatalkan. Perbaiki DNS dulu, lalu jalankan ulang."; return 0 ;;
        esac
    else
        ok "DNS $NEW_DOMAIN sudah mengarah ke server ini."
    fi

    # --- Buat sertifikat SSL domain baru DULU, sebelum config diubah ---
    # Urutan ini penting: kalau config diubah duluan sementara sertifikat
    # domain baru belum ada, Nginx bisa gagal restart dan PANEL BISA DOWN
    # TOTAL (domain lama maupun baru). Jadi sertifikat harus siap dulu.
    if ! command -v certbot >/dev/null 2>&1; then
        info "Menginstall certbot..."
        install_package certbot || true
    fi

    if ! command -v certbot >/dev/null 2>&1; then
        warn "certbot tidak tersedia dan gagal diinstall."
        warn "Dibatalkan agar panel di domain lama ($OLD_DOMAIN) tetap aman."
        return 1
    fi

    info "Membuat sertifikat SSL untuk $NEW_DOMAIN (Nginx berhenti sebentar)..."
    systemctl stop nginx 2>/dev/null || true

    if certbot certonly --standalone -d "$NEW_DOMAIN" --non-interactive --agree-tos \
        -m "admin@${NEW_DOMAIN}" --no-eff-email; then
        ok "Sertifikat SSL untuk $NEW_DOMAIN berhasil dibuat."
    else
        systemctl start nginx 2>/dev/null || true
        warn "Gagal membuat sertifikat SSL untuk $NEW_DOMAIN."
        warn "Kemungkinan DNS belum mengarah ke server ini, atau port 80 tertutup/dipakai."
        warn "Config panel TIDAK diubah — panel lama ($OLD_DOMAIN) tetap aman & jalan seperti biasa."
        return 1
    fi

    systemctl start nginx 2>/dev/null || true

    # --- Baru sekarang ubah .env dan config Nginx ---
    # PENTING: APP_URL di .env adalah SATU-SATUNYA sumber kebenaran yang
    # dipakai Pterodactyl untuk generate command auto-deploy Wings (bukan
    # dari database/tabel settings — sudah dikonfirmasi resmi oleh
    # maintainer Pterodactyl). Sebelumnya kita cuma replace OLD_DOMAIN
    # jadi NEW_DOMAIN di .env, tapi kalau APP_URL yang sebenarnya sudah
    # "nyasar" ke http://localhost (misal dari awal install belum pernah
    # di-set benar), replace berbasis teks itu TIDAK akan match dan
    # APP_URL tetap localhost selamanya walau domain di Nginx sudah benar.
    # Makanya sekarang APP_URL langsung DIPAKSA/di-set ulang total,
    # apapun isinya sebelumnya.
    info "Mengganti domain di .env Panel..."
    if grep -qE '^APP_URL=' /var/www/pterodactyl/.env; then
        sed -i "s#^APP_URL=.*#APP_URL=https://${NEW_DOMAIN}#" /var/www/pterodactyl/.env
    else
        echo "APP_URL=https://${NEW_DOMAIN}" >> /var/www/pterodactyl/.env
    fi
    # Ganti juga kemunculan domain lama di baris .env lain (kalau ada,
    # misal TRUSTED_PROXIES atau catatan lain yang menyebut domain lama).
    sed -i "s#${OLD_DOMAIN}#${NEW_DOMAIN}#g" /var/www/pterodactyl/.env

    local VERIFY_ENV
    VERIFY_ENV="$(grep -E '^APP_URL=' /var/www/pterodactyl/.env)"
    if echo "$VERIFY_ENV" | grep -qi "localhost\|$OLD_DOMAIN"; then
        warn "APP_URL masih salah setelah diupdate: $VERIFY_ENV"
        warn "Cek permission /var/www/pterodactyl/.env (harus writable oleh user yang jalanin script ini)."
    else
        ok "File .env berhasil diupdate: $VERIFY_ENV"
    fi

    if [ "${#NGINX_FILES_FOUND[@]}" -gt 0 ]; then
        info "Mengganti domain di konfigurasi Nginx (server_name, path SSL, dll)..."
        for f in "${NGINX_FILES_FOUND[@]}"; do
            sed -i "s#${OLD_DOMAIN}#${NEW_DOMAIN}#g" "$f"
            ok "Updated: $f"
        done

        info "Memastikan redirect otomatis HTTP -> HTTPS aktif untuk $NEW_DOMAIN..."
        local REDIRECT_HANDLED=0
        for f in "${NGINX_FILES_FOUND[@]}"; do
            if ensure_http_redirect "$f" "$NEW_DOMAIN"; then
                REDIRECT_HANDLED=1
            fi
        done

        if [ "$REDIRECT_HANDLED" -eq 0 ]; then
            warn "Tidak ditemukan blok 'listen 80' untuk $NEW_DOMAIN di config manapun."
            info "Membuat blok redirect HTTP->HTTPS baru untuk $NEW_DOMAIN..."
            local REDIRECT_CONF="/etc/nginx/conf.d/pterodactyl-redirect.conf"
            cat > "$REDIRECT_CONF" <<REDIRECT_EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${NEW_DOMAIN};
    return 301 https://\$host\$request_uri;
}
REDIRECT_EOF
            ok "Blok redirect dibuat di: $REDIRECT_CONF"
        else
            ok "Redirect HTTP -> HTTPS untuk $NEW_DOMAIN sudah aktif."
        fi
    else
        warn "Tidak ada file konfigurasi Nginx yang mengandung domain lama ($OLD_DOMAIN)."
        warn "Jika config Nginx panel ada di lokasi lain, sesuaikan manual."
    fi

    # --- Update tabel `settings` di database ---
    # Pterodactyl menyimpan APP_URL (dan setting lain) di DB, yang bisa
    # OVERRIDE nilai .env. Kalau ini tidak diupdate, hal-hal seperti
    # command auto-deploy Wings bisa tetap kebaca domain lama / localhost.
    info "Mengganti domain di tabel settings database..."
    if [ -f /var/www/pterodactyl/.env ] && command -v mysql >/dev/null 2>&1; then
        local DB_NAME DB_USER DB_PASS DB_HOST DB_PORT
        DB_NAME="$(grep -E '^DB_DATABASE=' /var/www/pterodactyl/.env | cut -d '=' -f2- | tr -d '\r\n')"
        DB_USER="$(grep -E '^DB_USERNAME=' /var/www/pterodactyl/.env | cut -d '=' -f2- | tr -d '\r\n')"
        DB_PASS="$(grep -E '^DB_PASSWORD=' /var/www/pterodactyl/.env | cut -d '=' -f2- | tr -d '\r\n')"
        DB_HOST="$(grep -E '^DB_HOST=' /var/www/pterodactyl/.env | cut -d '=' -f2- | tr -d '\r\n')"
        DB_PORT="$(grep -E '^DB_PORT=' /var/www/pterodactyl/.env | cut -d '=' -f2- | tr -d '\r\n')"
        DB_HOST="${DB_HOST:-127.0.0.1}"
        DB_PORT="${DB_PORT:-3306}"

        if [ -n "$DB_NAME" ] && [ -n "$DB_USER" ]; then
            local MYSQL_CMD=(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME")
            [ -n "$DB_PASS" ] && MYSQL_CMD=(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME")

            # 1) Ganti baris yang masih mengandung domain LAMA (kasus normal)
            local ROWS_AFFECTED
            ROWS_AFFECTED="$(
                "${MYSQL_CMD[@]}" -N -e \
                    "UPDATE settings SET value = REPLACE(value, '${OLD_DOMAIN}', '${NEW_DOMAIN}') WHERE value LIKE '%${OLD_DOMAIN}%'; SELECT ROW_COUNT();" \
                    2>/dev/null
            )"

            # 2) FALLBACK: paksa timpa key app-url spesifik walau isinya literal
            #    "localhost" / "http://localhost" (bukan mengandung domain lama),
            #    supaya command auto-deploy Wings pasti kebaca domain baru.
            local ROWS_FORCED
            ROWS_FORCED="$(
                "${MYSQL_CMD[@]}" -N -e \
                    "UPDATE settings SET value = 'https://${NEW_DOMAIN}' WHERE \`key\` = 'settings::app:url' OR \`key\` LIKE '%app:url%' OR (\`key\` LIKE '%url%' AND value LIKE '%localhost%'); SELECT ROW_COUNT();" \
                    2>/dev/null
            )"

            if [ -n "$ROWS_AFFECTED" ] || [ -n "$ROWS_FORCED" ]; then
                ok "Tabel settings diupdate (${ROWS_AFFECTED:-0} baris ganti domain lama, ${ROWS_FORCED:-0} baris app:url dipaksa ke domain baru)."
            else
                warn "Gagal update tabel settings. Cek kredensial DB atau jalankan manual jika perlu."
            fi
        else
            warn "Kredensial database tidak lengkap di .env, lewati update tabel settings."
        fi
    else
        warn "MySQL client tidak ditemukan, lewati update tabel settings (mungkin perlu manual)."
    fi

    info "Membersihkan cache Panel (config, cache, compiled, route, view)..."
    (cd /var/www/pterodactyl && php artisan optimize:clear >/dev/null 2>&1 || true)
    (cd /var/www/pterodactyl && php artisan config:clear >/dev/null 2>&1 || true)
    (cd /var/www/pterodactyl && php artisan cache:clear >/dev/null 2>&1 || true)
    (cd /var/www/pterodactyl && php artisan view:clear >/dev/null 2>&1 || true)
    ok "Cache Panel dibersihkan."

    # --- Test config sebelum benar-benar restart. Kalau gagal, ROLLBACK OTOMATIS ---
    info "Mengetes konfigurasi Nginx..."
    if ! nginx -t >/dev/null 2>&1; then
        warn "Konfigurasi Nginx TIDAK VALID setelah perubahan."
        rollback_domain_change
        unset -f rollback_domain_change
        die "Ganti subdomain dibatalkan & di-rollback otomatis. Panel tetap di domain lama ($OLD_DOMAIN)."
    fi
    ok "Konfigurasi Nginx valid."

    systemctl restart nginx
    ok "Nginx berhasil direstart."

    # --- Verifikasi BENERAN: cert yang disajikan Nginx sudah cert domain baru ---
    # Kejadian nyata: restart nginx "sukses" (exit code 0) tapi cert yang
    # disajikan tetap cert domain lama. Makanya di sini kita cek LANGSUNG
    # ke server pakai openssl, bukan cuma percaya exit code restart.
    # Kalau masih ketuker, paksa restart ULANG (bukan cuma reload).
    info "Memverifikasi sertifikat yang benar-benar disajikan Nginx..."
    sleep 1

    local SERVED_CN
    SERVED_CN="$(
        echo | openssl s_client -servername "$NEW_DOMAIN" -connect 127.0.0.1:443 2>/dev/null | \
        openssl x509 -noout -subject 2>/dev/null | \
        sed -E 's/.*CN\s*=\s*//'
    )"

    if [ "$SERVED_CN" != "$NEW_DOMAIN" ]; then
        warn "Nginx masih menyajikan cert untuk '$SERVED_CN' (harusnya '$NEW_DOMAIN'). Mencoba restart ulang..."
        systemctl stop nginx 2>/dev/null || true
        sleep 1
        systemctl start nginx 2>/dev/null || true
        sleep 1

        SERVED_CN="$(
            echo | openssl s_client -servername "$NEW_DOMAIN" -connect 127.0.0.1:443 2>/dev/null | \
            openssl x509 -noout -subject 2>/dev/null | \
            sed -E 's/.*CN\s*=\s*//'
        )"

        if [ "$SERVED_CN" = "$NEW_DOMAIN" ]; then
            ok "Setelah restart ulang, Nginx sekarang menyajikan cert yang benar ($NEW_DOMAIN)."
        else
            warn "Nginx MASIH menyajikan cert salah ('$SERVED_CN') setelah restart ulang."
            warn "Kemungkinan ada file config Nginx LAIN yang bentrok (server_name sama/duplikat)."
            warn "Cek manual: grep -rl '$NEW_DOMAIN' /etc/nginx/sites-enabled/ /etc/nginx/conf.d/"
            warn "Lalu jalankan manual: nginx -t && systemctl restart nginx"
        fi
    else
        ok "Nginx terkonfirmasi menyajikan sertifikat yang benar untuk $NEW_DOMAIN."
    fi

    local PHP_FPM_SERVICE
    PHP_FPM_SERVICE="$(
        systemctl list-unit-files --type=service --no-legend 'php*-fpm.service' 2>/dev/null |
        awk '{print $1}' | sort -V | tail -n 1
    )"

    if [ -n "$PHP_FPM_SERVICE" ]; then
        systemctl restart "$PHP_FPM_SERVICE" 2>/dev/null && \
            ok "PHP-FPM ($PHP_FPM_SERVICE) berhasil direstart." || \
            warn "Gagal restart PHP-FPM ($PHP_FPM_SERVICE)."
    fi

    unset -f rollback_domain_change

    # --- Kalau Wings/Node ada di server yang sama, update juga remote-nya ---
    # supaya Node tetap konek (hijau) ke Panel di domain baru.
    local WINGS_CONFIG="/etc/pterodactyl/config.yml"
    if [ -f "$WINGS_CONFIG" ] && grep -q "$OLD_DOMAIN" "$WINGS_CONFIG" 2>/dev/null; then
        echo
        info "Wings/Node terdeteksi di server ini dan masih mengarah ke domain lama."
        cp -a "$WINGS_CONFIG" "$BACKUP_DIR/config.yml.bak" 2>/dev/null || true

        sed -i "s#${OLD_DOMAIN}#${NEW_DOMAIN}#g" "$WINGS_CONFIG"
        ok "config.yml Wings berhasil diupdate ke domain baru."

        if command -v wings >/dev/null 2>&1 || systemctl list-unit-files --type=service --no-legend 'wings.service' >/dev/null 2>&1; then
            info "Merestart service Wings..."
            if systemctl restart wings 2>/dev/null; then
                ok "Wings berhasil direstart dan sekarang mengarah ke $NEW_DOMAIN."
            else
                warn "Gagal restart Wings otomatis. Restart manual: systemctl restart wings"
            fi
        else
            warn "Service 'wings' tidak ditemukan, restart manual jika perlu."
        fi
    fi

    # --- Verifikasi akhir: panel beneran bisa dibuka atau tidak ---
    echo
    info "Memverifikasi panel bisa diakses di domain baru..."
    sleep 2

    local HTTP_CODE
    HTTP_CODE="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 10 "https://${NEW_DOMAIN}" 2>/dev/null)"

    local HTTP_REDIRECT_CODE
    HTTP_REDIRECT_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://${NEW_DOMAIN}" 2>/dev/null)"

    echo
    echo "============================================================"
    echo "         GANTI SUBDOMAIN PANEL SELESAI"
    echo "============================================================"
    echo
    echo "Domain lama : $OLD_DOMAIN"
    echo "Domain baru : $NEW_DOMAIN"
    echo "Backup      : $BACKUP_DIR"
    echo

    if [[ "$HTTP_CODE" =~ ^(200|301|302|303|307|308)$ ]]; then
        ok "Panel TERKONFIRMASI bisa dibuka di: https://$NEW_DOMAIN (HTTP $HTTP_CODE)"
    else
        warn "Panel belum merespons normal di https://$NEW_DOMAIN (kode: ${HTTP_CODE:-tidak ada respons})."
        warn "Kemungkinan DNS masih propagasi (tunggu beberapa menit) atau firewall/port 443 tertutup."
        warn "Config sudah benar & backup ada di: $BACKUP_DIR jika perlu dikembalikan manual."
    fi

    if [[ "$HTTP_REDIRECT_CODE" =~ ^(301|302|307|308)$ ]]; then
        ok "Akses http:// otomatis redirect ke https:// (HTTP $HTTP_REDIRECT_CODE). Tidak perlu ketik https:// manual."
    else
        warn "Akses http:// (tanpa 's') belum redirect otomatis ke https:// (kode: ${HTTP_REDIRECT_CODE:-tidak ada respons})."
        warn "Untuk sementara akses panel HARUS pakai https://$NEW_DOMAIN secara eksplisit."
    fi

    echo
    info "Cek APP_URL yang akan dipakai saat generate command Wings..."
    local ENV_APP_URL
    ENV_APP_URL="$(grep -E '^APP_URL=' /var/www/pterodactyl/.env 2>/dev/null | cut -d '=' -f2-)"

    if echo "$ENV_APP_URL" | grep -qi "localhost"; then
        warn "APP_URL di .env MASIH 'localhost': $ENV_APP_URL"
        warn "Command auto-deploy Wings kemungkinan masih salah. Cek manual: grep APP_URL /var/www/pterodactyl/.env"
    else
        ok "APP_URL di .env sudah benar: $ENV_APP_URL"
        ok "Saat bikin/lihat command auto-deploy Node baru, seharusnya sudah pakai $ENV_APP_URL (bukan localhost)."
    fi
    echo
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
echo "              PTERODACTYL AUTO INSTALLER LUXXY ASTRA"
echo "                    LXST AUTO INSTALLER v1"
echo "============================================================"
echo
echo "[1] Install Panel saja"
echo "[2] Install Panel + Wings"
echo "[3] Install Wings saja"
echo "[4] Install Database saja"
echo "[5] Install phpMyAdmin saja"
echo "[6] Install Database + phpMyAdmin"
echo "[7] Ganti Subdomain Panel"
echo "[8] Uninstall Panel"
echo "[9] Uninstall Wings/Node"
echo "[10] Uninstall Panel + Wings/Node"
echo "[11] Auto Create Node/Location (Panel & Wings SUDAH terinstall)"
echo

while true; do
    read -r -p "Pilih [1-11]: " MODE
    MODE="$(clean_input "$MODE")"

    case "$MODE" in
        1) UPSTREAM_MODE="0"; break ;;
        2) UPSTREAM_MODE="2"; break ;;
        3) UPSTREAM_MODE="1"; break ;;
        4) break ;;
        5) break ;;
        6) break ;;
        7) break ;;
        8) break ;;
        9) break ;;
        10) break ;;
        11) break ;;
        *) echo "[!] Masukkan 1-11." ;;
    esac
done

if [ "$MODE" = "4" ]; then
    install_database
    echo
    echo "============================================================"
    echo "                 DATABASE SELESAI"
    echo "============================================================"
    exit 0
fi

if [ "$MODE" = "5" ]; then
    install_phpmyadmin
    echo
    echo "============================================================"
    echo "                 PHPMYADMIN SELESAI"
    echo "============================================================"
    exit 0
fi

if [ "$MODE" = "6" ]; then
    install_database
    install_phpmyadmin
    echo
    echo "============================================================"
    echo "         DATABASE + PHPMYADMIN SELESAI"
    echo "============================================================"
    exit 0
fi

if [ "$MODE" = "7" ]; then
    ganti_subdomain_panel
    exit 0
fi

if [ "$MODE" = "8" ]; then
    uninstall_panel
    exit 0
fi

if [ "$MODE" = "9" ]; then
    uninstall_wings
    exit 0
fi

if [ "$MODE" = "10" ]; then
    uninstall_panel
    uninstall_wings
    echo
    echo "============================================================"
    echo "       UNINSTALL PANEL + WINGS/NODE SELESAI"
    echo "============================================================"
    exit 0
fi

if [ "$MODE" = "11" ]; then
    echo
    echo "============================================================"
    echo "     AUTO CREATE NODE/LOCATION (TANPA INSTALL ULANG)"
    echo "============================================================"
    echo
    echo "Mode ini CUMA menjalankan proses:"
    echo "  - Membuat Location + Node di Panel"
    echo "  - Ambil config token Node & tulis ke /etc/pterodactyl/config.yml"
    echo "  - systemctl enable --now wings"
    echo
    echo "Panel & Wings HARUS SUDAH terinstall duluan di server ini"
    echo "(pakai menu [2] atau [3]). Kalau belum, batalkan dan install dulu."
    echo

    if ! command -v wings >/dev/null 2>&1 && [ ! -x /usr/local/bin/wings ]; then
        die "Wings belum terinstall di server ini. Jalankan menu [2] atau [3] dulu, baru pakai mode ini."
    fi

    PANEL_LOCAL="n"
    if [ -f /var/www/pterodactyl/artisan ]; then
        read -r -p "Panel ada di server ini juga? [Y/n]: " PANEL_LOCAL_ANS
        PANEL_LOCAL_ANS="$(clean_input "${PANEL_LOCAL_ANS:-Y}")"
        case "$PANEL_LOCAL_ANS" in
            ""|Y|y) PANEL_LOCAL="y" ;;
            *) PANEL_LOCAL="n" ;;
        esac
    fi

    echo
    while true; do
        read -r -p "Node subdomain (fqdn Wings yang sudah ada SSL-nya): " NODE_DOMAIN
        NODE_DOMAIN="$(clean_input "$NODE_DOMAIN")"
        if valid_domain "$NODE_DOMAIN"; then
            break
        fi
        echo "[!] Domain tidak valid."
    done

    if [ "$PANEL_LOCAL" = "y" ]; then
        MODE="2"

        while true; do
            read -r -p "Panel subdomain (tanpa https://): " PANEL_DOMAIN
            PANEL_DOMAIN="$(clean_input "$PANEL_DOMAIN")"
            if valid_domain "$PANEL_DOMAIN"; then
                break
            fi
            echo "[!] Domain tidak valid."
        done

        read -r -p "Username admin Panel (buat auto-generate API Key): " ADMIN_USERNAME
        ADMIN_USERNAME="$(clean_input "$ADMIN_USERNAME")"
    else
        MODE="3"

        while true; do
            read -r -p "Panel subdomain (tanpa https://): " PANEL_ADDRESS
            PANEL_ADDRESS="$(clean_input "$PANEL_ADDRESS")"
            if valid_domain "$PANEL_ADDRESS"; then
                PANEL_ADDRESS="https://$PANEL_ADDRESS"
                break
            fi
            echo "[!] Domain tidak valid."
        done
    fi

    LOCATION_SHORT="loc-$(random_suffix 4)"
    LOCATION_LONG="Auto Location @LXST OFFC $(random_suffix 4)"
    NODE_NAME="node-$(random_suffix 5)"
    info "Location (otomatis): $LOCATION_SHORT"
    info "Node name (otomatis): $NODE_NAME"

    NODE_MEMORY="$(detect_total_memory_mb)"
    if [ -z "$NODE_MEMORY" ] || [ "$NODE_MEMORY" -le 0 ]; then
        die "Gagal mendeteksi total RAM VPS secara otomatis. Cek 'free -m'."
    fi
    NODE_MEMORY_OVERALLOCATE=0
    info "Total Memory Node (otomatis dari RAM VPS): ${NODE_MEMORY} MB"

    NODE_DISK="$(detect_total_disk_mb)"
    if [ -z "$NODE_DISK" ] || [ "$NODE_DISK" -le 0 ]; then
        die "Gagal mendeteksi total Disk VPS secara otomatis. Cek 'df -m /'."
    fi
    NODE_DISK_OVERALLOCATE=0
    info "Total Disk Node (otomatis dari Disk VPS): ${NODE_DISK} MB"

    PANEL_API_KEY=""
    if [ "$MODE" = "2" ]; then
        info "Mencoba generate Application API Key otomatis dari admin '$ADMIN_USERNAME'..."
        if auto_generate_panel_api_key && [ -n "$AUTOKEY_RESULT" ]; then
            PANEL_API_KEY="$AUTOKEY_RESULT"
            ok "API Key otomatis berhasil dibuat (izin: Locations & Nodes = Read+Write)."
        else
            warn "Gagal generate API Key otomatis. Silakan masukkan manual."
        fi
    fi

    if [ -z "$PANEL_API_KEY" ]; then
        while true; do
            read -r -s -p "Panel Application API Key (ptla_...): " PANEL_API_KEY
            echo
            PANEL_API_KEY="$(clean_input "$PANEL_API_KEY")"
            [ -n "$PANEL_API_KEY" ] && break
            echo "[!] API Key tidak boleh kosong."
        done
    fi

    if ! provision_node_via_api; then
        die "Auto create Node gagal. Cek pesan error di atas, lalu coba lagi."
    fi

    exit 0
fi

PANEL_DOMAIN=""
PANEL_ADDRESS=""
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
            echo "[!] Password minimal 2 karakter."
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

if [ "$MODE" = "3" ]; then

# ========================================================
# WINGS-ONLY EMAIL FIX
# ========================================================

while true; do
    read -r -p "Email untuk Let's Encrypt: " ADMIN_EMAIL
    ADMIN_EMAIL="$(clean_input "$ADMIN_EMAIL")"

    if valid_email "$ADMIN_EMAIL"; then
        break
    fi

    echo
    echo "[!] Email tidak valid/kosong. Masukkan email yang valid."
    echo
done

echo
echo "================ ALAMAT PANEL ================="
echo
echo "Wings perlu tahu alamat Panel yang sudah terpasang (di server ini/lain)."
echo "Contoh: panel.example.com"
echo

while true; do
    read -r -p "Panel subdomain (tanpa https://): " PANEL_ADDRESS
    PANEL_ADDRESS="$(clean_input "$PANEL_ADDRESS")"

    if valid_domain "$PANEL_ADDRESS"; then
        PANEL_ADDRESS="https://$PANEL_ADDRESS"
        break
    fi

    echo
    echo "[!] Domain tidak valid."
    echo "    Contoh: panel.example.com"
    echo
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

DBHOST_USERNAME=""
DBHOST_PASSWORD=""
DBHOST_PASSWORD_CONFIRM=""

if [ "$MODE" = "2" ] || [ "$MODE" = "3" ]; then
    echo
    echo "================ DATABASE HOST (WINGS) ================="
    echo
    echo "Installer Wings akan otomatis bikin user MySQL untuk Database Host."
    echo

    read -r -p "Username Database Host [pterodactyluser]: " DBHOST_USERNAME
    DBHOST_USERNAME="$(clean_input "${DBHOST_USERNAME:-pterodactyluser}")"
    [ -n "$DBHOST_USERNAME" ] || DBHOST_USERNAME="pterodactyluser"

    if ! [[ "$DBHOST_USERNAME" =~ ^[A-Za-z0-9_]{3,32}$ ]]; then
        warn "Username tidak valid, pakai default 'pterodactyluser'."
        DBHOST_USERNAME="pterodactyluser"
    fi

    while true; do
        read -r -s -p "Password Database Host (minimal 4 karakter): " DBHOST_PASSWORD
        echo

        if [ "${#DBHOST_PASSWORD}" -lt 4 ]; then
            echo "[!] Password minimal 4 karakter."
            continue
        fi

        read -r -s -p "Confirm password Database Host: " DBHOST_PASSWORD_CONFIRM
        echo

        if [ "$DBHOST_PASSWORD" != "$DBHOST_PASSWORD_CONFIRM" ]; then
            echo "[!] Password tidak sama."
            continue
        fi

        break
    done
fi

# ============================================================
# AUTO PROVISIONING: LOCATION + NODE + TOKEN VIA PANEL API
# (Pertanyaannya baru muncul SETELAH Panel+Wings selesai diinstall,
#  lihat blok "AUTO PROVISIONING NODE (OPSIONAL)" di bagian bawah script)
# ============================================================
AUTO_PROVISION="n"
PANEL_API_KEY=""
LOCATION_SHORT=""
LOCATION_LONG=""
NODE_NAME=""
NODE_MEMORY=""
NODE_MEMORY_OVERALLOCATE=""
NODE_DISK=""
NODE_DISK_OVERALLOCATE=""

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
[ -n "$DBHOST_USERNAME" ] && echo "DB Host User : $DBHOST_USERNAME"

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

if [ -z "$PANEL_ADDRESS" ] && [ -n "$PANEL_DOMAIN" ]; then
    PANEL_ADDRESS="https://$PANEL_DOMAIN"
fi

# Versi tanpa skema (http:// / https://), khusus untuk prompt Wings
# "Enter the panel address (blank for any address):" yang tidak butuh skema.
PANEL_ADDRESS_NOSCHEME="${PANEL_ADDRESS#http://}"
PANEL_ADDRESS_NOSCHEME="${PANEL_ADDRESS_NOSCHEME#https://}"

export AUTO_MODE="$UPSTREAM_MODE"
export AUTO_PANEL_DOMAIN="$PANEL_DOMAIN"
export AUTO_PANEL_ADDRESS="$PANEL_ADDRESS"
export AUTO_PANEL_ADDRESS_NOSCHEME="$PANEL_ADDRESS_NOSCHEME"
export AUTO_NODE_DOMAIN="$NODE_DOMAIN"
export AUTO_EMAIL="$ADMIN_EMAIL"
export AUTO_USERNAME="$ADMIN_USERNAME"
export AUTO_FIRSTNAME="$ADMIN_FIRSTNAME"
export AUTO_LASTNAME="$ADMIN_LASTNAME"
export AUTO_PASSWORD="$ADMIN_PASSWORD"
export AUTO_DBHOST_USERNAME="$DBHOST_USERNAME"
export AUTO_DBHOST_PASSWORD="$DBHOST_PASSWORD"
export AUTO_INSTALLER="$TMP_INSTALLER"

info "Menjalankan installer Pterodactyl..."
echo

cat > "$EXPECT_SCRIPT_FILE" <<'EXPECT_SCRIPT'

set timeout 300

set installer "$env(AUTO_INSTALLER)"
set mode "$env(AUTO_MODE)"
set panel_domain "$env(AUTO_PANEL_DOMAIN)"
set panel_address "$env(AUTO_PANEL_ADDRESS)"
set panel_address_noscheme "$env(AUTO_PANEL_ADDRESS_NOSCHEME)"
set node_domain "$env(AUTO_NODE_DOMAIN)"
set email "$env(AUTO_EMAIL)"
set username "$env(AUTO_USERNAME)"
set firstname "$env(AUTO_FIRSTNAME)"
set lastname "$env(AUTO_LASTNAME)"
set password "$env(AUTO_PASSWORD)"
set dbhost_username "$env(AUTO_DBHOST_USERNAME)"
set dbhost_password "$env(AUTO_DBHOST_PASSWORD)"

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

    -re {.*Enter the panel address.*blank for any address.*: *$} {
        send -- "$panel_address_noscheme\r"
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
        send -- "y\r"
        exp_continue
    }

    -re {(?i).*do you want to configure mysql to be accessed externally.*\([yY]/[nN]\): *$} {
        send -- "y\r"
        exp_continue
    }

    -re {.*[Dd]atabase host username \(.*\): *$} {
        send -- "$dbhost_username\r"
        exp_continue
    }

    -re {.*[Dd]atabase host password.*: *$} {
        send -- "$dbhost_password\r"
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
    if {$email eq ""} {
        puts stderr "[ERROR] Email Let's Encrypt kosong."
        exit 2
    }
    send -- "$email
"
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
        puts stderr "============================================================"
        puts stderr "\[PERHATIAN\] Tidak ada pertanyaan yang dikenali selama 5 menit."
        puts stderr "Kontrol terminal diserahkan ke kamu sekarang."
        puts stderr "Silakan jawab pertanyaan yang muncul secara manual."
        puts stderr "Proses otomatis TIDAK akan lanjut lagi setelah ini."
        puts stderr "============================================================"
        puts stderr ""
        interact
        exit 0
    }
}

EXPECT_SCRIPT

expect -f "$EXPECT_SCRIPT_FILE" 2>&1 | tee -a "$LOG_FILE"

EXPECT_STATUS=${PIPESTATUS[0]}


# ============================================================
# PHP-FPM AUTO START / 502 FIX
# ============================================================
info "Memastikan PHP-FPM aktif untuk mencegah 502 Bad Gateway..."

PHP_FPM_SERVICE="$(
    systemctl list-unit-files --type=service --no-legend 'php*-fpm.service' 2>/dev/null |
    awk '{print $1}' |
    sort -V |
    tail -n 1
)"

if [ -z "$PHP_FPM_SERVICE" ]; then
    PHP_FPM_SERVICE="$(
        find /usr/lib/systemd/system /lib/systemd/system \
            -maxdepth 1 -type f -name 'php*-fpm.service' 2>/dev/null |
        sed 's#.*/##' |
        sort -V |
        tail -n 1
    )"
fi

if [ -n "$PHP_FPM_SERVICE" ]; then
    systemctl daemon-reload
    systemctl enable "$PHP_FPM_SERVICE" >/dev/null 2>&1 || true
    systemctl restart "$PHP_FPM_SERVICE"

    if systemctl is-active --quiet "$PHP_FPM_SERVICE"; then
        ok "PHP-FPM aktif: $PHP_FPM_SERVICE"
    else
        warn "PHP-FPM gagal aktif: $PHP_FPM_SERVICE"
        systemctl status "$PHP_FPM_SERVICE" --no-pager -l || true
    fi
else
    warn "Service PHP-FPM tidak ditemukan."
fi

if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
        systemctl restart nginx
        ok "Nginx berhasil direstart setelah PHP-FPM."
    else
        warn "Konfigurasi Nginx gagal dites."
        nginx -t || true
    fi
fi

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
    echo "================ AUTO PROVISIONING NODE (OPSIONAL) ================="
    echo
    echo "Panel + Wings sudah selesai diinstall. Kalau diaktifkan, script akan otomatis:"
    echo "  - Membuat Location di Panel (kalau belum ada)"
    echo "  - Membuat Node di Panel (fqdn = node subdomain di atas)"
    echo "  - Mengisi total memory & disk (+ overallocate)"
    echo "  - Ambil config token Node & tulis ke /etc/pterodactyl/config.yml"
    echo "  - systemctl enable --now wings"
    echo
    if [ "$MODE" = "2" ]; then
        echo "Application API Key akan dibuat OTOMATIS pakai akun admin '$ADMIN_USERNAME'"
        echo "(tidak perlu login/buka dashboard Panel). Kalau gagal, kamu akan diminta"
        echo "memasukkan API Key manual sebagai cadangan."
    else
        echo "Mode Wings-saja: Panel ada di server lain, jadi butuh Application API Key"
        echo "dari Panel tersebut (Panel > Admin > Application API > Create New,"
        echo "izin minimal: Locations & Nodes = Read + Write)."
    fi
    echo

    read -r -p "Aktifkan auto provisioning Node via API? [y/N]: " AUTO_PROVISION
    AUTO_PROVISION="$(clean_input "${AUTO_PROVISION:-N}")"

    case "$AUTO_PROVISION" in
        y|Y)
            AUTO_PROVISION="y"

            PANEL_API_KEY=""
            if [ "$MODE" = "2" ]; then
                info "Mencoba generate Application API Key otomatis dari admin '$ADMIN_USERNAME'..."
                if auto_generate_panel_api_key && [ -n "$AUTOKEY_RESULT" ]; then
                    PANEL_API_KEY="$AUTOKEY_RESULT"
                    ok "API Key otomatis berhasil dibuat (izin: Locations & Nodes = Read+Write)."
                else
                    warn "Gagal generate API Key otomatis. Silakan masukkan manual."
                fi
            fi

            if [ -z "$PANEL_API_KEY" ]; then
                while true; do
                    read -r -s -p "Panel Application API Key (ptla_...): " PANEL_API_KEY
                    echo
                    PANEL_API_KEY="$(clean_input "$PANEL_API_KEY")"
                    [ -n "$PANEL_API_KEY" ] && break
                    echo "[!] API Key tidak boleh kosong."
                done
            fi

            # ---------- LOCATION (otomatis, random) ----------
            LOCATION_SHORT="loc-$(random_suffix 4)"
            LOCATION_LONG="Auto Location $(random_suffix 4)"
            info "Location short code (otomatis): $LOCATION_SHORT"
            info "Location description (otomatis): $LOCATION_LONG"

            # ---------- NODE NAME (otomatis, random) ----------
            NODE_NAME="node-$(random_suffix 5)"
            info "Nama Node (otomatis): $NODE_NAME"

            # ---------- MEMORY (otomatis, dari RAM VPS) ----------
            NODE_MEMORY="$(detect_total_memory_mb)"
            if [ -z "$NODE_MEMORY" ] || [ "$NODE_MEMORY" -le 0 ]; then
                die "Gagal mendeteksi total RAM VPS secara otomatis. Cek 'free -m'."
            fi
            info "Total Memory Node (otomatis dari RAM VPS): ${NODE_MEMORY} MB"

            NODE_MEMORY_OVERALLOCATE=0
            info "Memory overallocate (otomatis): ${NODE_MEMORY_OVERALLOCATE}%"

            # ---------- DISK (otomatis, dari Disk VPS) ----------
            NODE_DISK="$(detect_total_disk_mb)"
            if [ -z "$NODE_DISK" ] || [ "$NODE_DISK" -le 0 ]; then
                die "Gagal mendeteksi total Disk VPS secara otomatis. Cek 'df -m /'."
            fi
            info "Total Disk Node (otomatis dari Disk VPS): ${NODE_DISK} MB"

            NODE_DISK_OVERALLOCATE=0
            info "Disk overallocate (otomatis): ${NODE_DISK_OVERALLOCATE}%"
            ;;
        *)
            AUTO_PROVISION="n"
            ;;
    esac

    if [ "$AUTO_PROVISION" = "y" ]; then
        if ! provision_node_via_api; then
            warn "Auto provisioning gagal/dibatalkan. Silakan lanjutkan manual di bawah ini."
            echo
            echo "============================================================"
            echo "                    WINGS NEXT STEP (MANUAL)"
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
    else
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
fi

unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_CONFIRM
unset AUTO_PASSWORD
unset DBHOST_PASSWORD
unset DBHOST_PASSWORD_CONFIRM
unset AUTO_DBHOST_PASSWORD

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

if [ -n "$DBHOST_USERNAME" ]; then
    echo "DB Host Username : $DBHOST_USERNAME"
    echo "DB Host Host/Port: 127.0.0.1 : 3306"
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
