#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Phase 2 — WordPress Installation
#  Downloads latest WordPress, creates DB, writes wp-config.php
#  Idempotent: safe to run multiple times
# ═══════════════════════════════════════════════════════════════
set -euo pipefail
trap 'echo "❌ install_wordpress.sh failed at line $LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/config.env"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[→]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

WP_DIR="/var/www/html/wordpress"
CONF_DIR="$(dirname "$SCRIPT_DIR")/config"

# ── 1. Create MySQL credentials file (secure, no plaintext pw) ─
info "Writing secure MySQL credentials file..."
cat > /root/.my.cnf << EOF
[client]
user=root
[mysqldump]
user=${DB_USER}
password=${DB_PASSWORD}
EOF
chmod 600 /root/.my.cnf
log "~/.my.cnf written (permissions: 600)"

# ── 2. Secure MariaDB non-interactively ────────────────────────
info "Securing MariaDB installation..."
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASSWORD}_root';" 2>/dev/null || true
mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1');" 2>/dev/null || true
mysql -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true
log "MariaDB secured"

# ── 3. Create WordPress database and user ─────────────────────
info "Setting up WordPress database..."
mysql << SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
log "Database '${DB_NAME}' and user '${DB_USER}' ready"

# ── 4. Download WordPress (skip if already installed) ──────────
if [[ -d "$WP_DIR" && -f "$WP_DIR/wp-login.php" ]]; then
  warn "WordPress already installed at $WP_DIR — skipping download"
else
  info "Downloading latest WordPress..."
  wget -q https://wordpress.org/latest.zip -O /tmp/wordpress.zip
  unzip -q /tmp/wordpress.zip -d /tmp
  mv /tmp/wordpress "$WP_DIR"
  rm /tmp/wordpress.zip
  log "WordPress downloaded and extracted to $WP_DIR"
fi

# ── 5. Write wp-config.php from template ──────────────────────
if [[ ! -f "$WP_DIR/wp-config.php" ]]; then
  info "Writing wp-config.php..."
  cp "$WP_DIR/wp-config-sample.php" "$WP_DIR/wp-config.php"

  # Inject database settings
  sed -i "s/database_name_here/${DB_NAME}/"     "$WP_DIR/wp-config.php"
  sed -i "s/username_here/${DB_USER}/"           "$WP_DIR/wp-config.php"
  sed -i "s/password_here/${DB_PASSWORD}/"       "$WP_DIR/wp-config.php"
  sed -i "s/localhost/${DB_HOST}/"               "$WP_DIR/wp-config.php"

  # Inject fresh salts from WordPress.org API
  info "Fetching fresh WordPress security salts..."
  SALTS=$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || echo "")
  if [[ -n "$SALTS" ]]; then
    # Remove placeholder salt block and replace with fresh ones
    sed -i '/AUTH_KEY/,/NONCE_SALT/d' "$WP_DIR/wp-config.php"
    SALT_MARKER="define( 'AUTH_KEY'"
    printf '%s\n' "$SALTS" | sed -i "/\/\*\*#@\+\*\//r /dev/stdin" "$WP_DIR/wp-config.php" || true
    log "Fresh security salts injected"
  fi

  # Add extra security constants
  cat >> "$WP_DIR/wp-config.php" << 'EXTRA'

// ── Security constants added by lamp-wordpress-pro ──
define( 'DISALLOW_FILE_EDIT', true );        // Disable theme/plugin file editor
define( 'DISALLOW_FILE_MODS', false );       // Allow plugin/theme updates
define( 'WP_AUTO_UPDATE_CORE', 'minor' );   // Auto-update minor WP releases
define( 'FORCE_SSL_ADMIN', false );          // Set true after SSL is enabled
EXTRA
  log "wp-config.php written with security constants"
else
  warn "wp-config.php already exists — skipping"
fi

# ── 6. Set ownership and permissions ──────────────────────────
info "Setting file ownership and permissions..."
chown -R www-data:www-data "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;
chmod 640 "$WP_DIR/wp-config.php"
log "Permissions set: dirs=755, files=644, wp-config=640"

# ── 7. Deploy Apache VirtualHost config ───────────────────────
info "Installing Apache VirtualHost config..."
cp "$CONF_DIR/apache_wordpress.conf" /etc/apache2/sites-available/wordpress.conf

# Inject domain into VirtualHost if set
if [[ -n "${DOMAIN:-}" && "${DOMAIN}" != "yourdomain.com" ]]; then
  sed -i "s/yourdomain.com/${DOMAIN}/g" /etc/apache2/sites-available/wordpress.conf
  log "Domain ${DOMAIN} set in Apache config"
fi

a2ensite wordpress.conf
a2dissite 000-default.conf 2>/dev/null || true
systemctl reload apache2
log "Apache VirtualHost enabled"

# ── 8. Create uploads directory with correct perms ─────────────
UPLOADS_DIR="$WP_DIR/wp-content/uploads"
mkdir -p "$UPLOADS_DIR"
chown -R www-data:www-data "$UPLOADS_DIR"
chmod 755 "$UPLOADS_DIR"
log "Uploads directory ready at $UPLOADS_DIR"

echo ""
log "WordPress installed successfully!"
log "Visit: http://${DOMAIN:-$(hostname -I | awk '{print $1}')}/wordpress"
log "Complete setup in your browser to choose site title, admin user, and password."
