#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Phase 1 — LAMP Stack Installation
#  Installs: Apache 2, MariaDB, PHP 8.1 + all WordPress extensions
#  Idempotent: safe to run multiple times
# ═══════════════════════════════════════════════════════════════
set -euo pipefail
trap 'echo "❌ install_lamp.sh failed at line $LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/config.env"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[→]${NC} $*"; }

# ── 1. Update package index ────────────────────────────────────
info "Updating package index..."
apt-get update -qq
log "Package index updated"

# ── 2. Install Apache ──────────────────────────────────────────
if ! dpkg -l apache2 &>/dev/null; then
  info "Installing Apache 2..."
  apt-get install -y apache2
  log "Apache 2 installed"
else
  log "Apache 2 already installed — skipping"
fi

# ── 3. Install MariaDB ─────────────────────────────────────────
if ! dpkg -l mariadb-server &>/dev/null; then
  info "Installing MariaDB..."
  apt-get install -y mariadb-server
  log "MariaDB installed"
else
  log "MariaDB already installed — skipping"
fi

# ── 4. Install PHP + ALL WordPress-recommended extensions ──────
info "Installing PHP 8.1 and WordPress extensions..."
apt-get install -y \
  php \
  php-mysql \
  php-curl \
  php-gd \
  php-mbstring \
  php-xml \
  php-xmlrpc \
  php-soap \
  php-intl \
  php-zip \
  php-imagick \
  php-bcmath \
  libapache2-mod-php
log "PHP and all extensions installed"

# ── 5. Install supporting utilities ───────────────────────────
info "Installing utilities (unzip, curl, wget, git)..."
apt-get install -y unzip curl wget git jq
log "Utilities installed"

# ── 6. Install AWS CLI (for S3 backups) ───────────────────────
if ! command -v aws &>/dev/null; then
  info "Installing AWS CLI..."
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install --update
  rm -rf /tmp/aws /tmp/awscliv2.zip
  log "AWS CLI installed"
else
  log "AWS CLI already installed — skipping"
fi

# ── 7. Enable Apache modules ───────────────────────────────────
info "Enabling Apache modules..."
a2enmod rewrite
a2enmod headers
a2enmod ssl
log "Apache modules enabled: rewrite, headers, ssl"

# ── 8. Enable and start services ──────────────────────────────
info "Enabling and starting services..."
systemctl enable apache2  && systemctl start  apache2
systemctl enable mariadb  && systemctl start  mariadb
log "Apache 2 running and enabled on boot"
log "MariaDB running and enabled on boot"

# ── 9. Increase PHP upload limits for WordPress ───────────────
PHP_INI=$(php -r "echo php_ini_loaded_file();")
info "Tuning PHP settings in $PHP_INI..."
sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
sed -i 's/post_max_size = .*/post_max_size = 64M/'             "$PHP_INI"
sed -i 's/memory_limit = .*/memory_limit = 256M/'             "$PHP_INI"
sed -i 's/max_execution_time = .*/max_execution_time = 300/'  "$PHP_INI"
systemctl reload apache2
log "PHP limits set: upload=64M, memory=256M, max_exec=300s"

# ── verify ─────────────────────────────────────────────────────
echo ""
log "LAMP stack ready:"
echo "  Apache: $(apache2 -v 2>&1 | head -1)"
echo "  MariaDB: $(mariadb --version 2>&1 | head -1)"
echo "  PHP: $(php -v | head -1)"
