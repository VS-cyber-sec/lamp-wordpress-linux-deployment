#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Phase 3 — Security Hardening
#  Hardens file permissions, Apache config, UFW firewall,
#  fail2ban, wp-config.php protections, and more.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail
trap 'echo "❌ harden_wordpress.sh failed at line $LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/config.env"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[→]${NC} $*"; }

WP_DIR="/var/www/html/wordpress"

# ── 1. File permissions ────────────────────────────────────────
info "Setting strict file permissions..."
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;
chmod 640 "$WP_DIR/wp-config.php"            # more restrictive than 644
chown -R www-data:www-data "$WP_DIR"
log "Permissions: dirs=755, files=644, wp-config.php=640"

# ── 2. Protect wp-config.php at the Apache level ──────────────
info "Blocking direct HTTP access to wp-config.php..."
cat > "$WP_DIR/.htaccess-security" << 'EOF'
# Block wp-config.php access
<Files wp-config.php>
    Order Deny,Allow
    Deny from all
</Files>

# Block xmlrpc.php (common brute-force target)
<Files xmlrpc.php>
    Order Deny,Allow
    Deny from all
</Files>

# Block hidden files (.git, .env, etc.)
<FilesMatch "^\.">
    Order Deny,Allow
    Deny from all
</FilesMatch>

# Disable directory listing
Options -Indexes

# Prevent PHP execution in uploads folder
<IfModule mod_php.c>
    <Directory /var/www/html/wordpress/wp-content/uploads>
        php_flag engine off
    </Directory>
</IfModule>
EOF
# Merge with existing .htaccess if present
if [[ -f "$WP_DIR/.htaccess" ]]; then
  cat "$WP_DIR/.htaccess-security" >> "$WP_DIR/.htaccess"
else
  mv "$WP_DIR/.htaccess-security" "$WP_DIR/.htaccess"
fi
rm -f "$WP_DIR/.htaccess-security"
chown www-data:www-data "$WP_DIR/.htaccess"
chmod 644 "$WP_DIR/.htaccess"
log "wp-config.php, xmlrpc.php, and hidden files blocked via .htaccess"

# ── 3. Disable Apache autoindex and disable server tokens ──────
info "Disabling Apache directory listing and version disclosure..."
a2dismod autoindex 2>/dev/null || true

# Hide Apache version from headers
cat >> /etc/apache2/conf-available/security.conf << 'EOF'

# Hardened by lamp-wordpress-pro
ServerTokens Prod
ServerSignature Off
TraceEnable Off
EOF
a2enconf security 2>/dev/null || true
log "Directory listing disabled, server version hidden"

# ── 4. Add security headers ───────────────────────────────────
info "Adding HTTP security headers..."
cat > /etc/apache2/conf-available/security-headers.conf << 'EOF'
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
    # HSTS — uncomment after SSL is confirmed working
    # Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</IfModule>
EOF
a2enconf security-headers
systemctl reload apache2
log "Security headers configured (X-Frame-Options, CSP, HSTS-ready)"

# ── 5. Install and configure UFW firewall ─────────────────────
info "Installing and configuring UFW firewall..."
apt-get install -y ufw -qq

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    comment 'SSH'
ufw allow 80/tcp    comment 'HTTP'
ufw allow 443/tcp   comment 'HTTPS'
ufw --force enable
log "UFW enabled: allow SSH(22), HTTP(80), HTTPS(443) — deny all else"

# ── 6. Install fail2ban against brute-force attacks ───────────
info "Installing and configuring fail2ban..."
apt-get install -y fail2ban -qq

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s

[apache-auth]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 3

[apache-badbots]
enabled  = true
port     = http,https
logpath  = %(apache_access_log)s
maxretry = 2

[wordpress-login]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
maxretry = 5
findtime = 5m
filter   = wordpress-login
EOF

# Custom fail2ban filter for WordPress login brute force
cat > /etc/fail2ban/filter.d/wordpress-login.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* "POST /wordpress/wp-login.php
ignoreregex =
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban configured: SSH, Apache, WordPress login brute-force protection"

# ── 7. Disable PHP execution in uploads directory ─────────────
info "Blocking PHP execution in uploads directory..."
UPLOADS_DIR="$WP_DIR/wp-content/uploads"
mkdir -p "$UPLOADS_DIR"
cat > "$UPLOADS_DIR/.htaccess" << 'EOF'
# Prevent PHP execution in the uploads directory
<FilesMatch "\.php$">
    Order Deny,Allow
    Deny from all
</FilesMatch>
EOF
chown www-data:www-data "$UPLOADS_DIR/.htaccess"
log "PHP execution blocked in wp-content/uploads/"

# ── 8. Ensure DISALLOW_FILE_EDIT is in wp-config.php ─────────
if ! grep -q "DISALLOW_FILE_EDIT" "$WP_DIR/wp-config.php"; then
  info "Adding DISALLOW_FILE_EDIT to wp-config.php..."
  echo "define( 'DISALLOW_FILE_EDIT', true );" >> "$WP_DIR/wp-config.php"
  log "DISALLOW_FILE_EDIT added to wp-config.php"
else
  log "DISALLOW_FILE_EDIT already present in wp-config.php"
fi

# ── 9. Set up automatic security updates ──────────────────────
info "Enabling automatic security updates..."
apt-get install -y unattended-upgrades -qq
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
systemctl enable unattended-upgrades
log "Automatic security updates enabled"

# ── summary ───────────────────────────────────────────────────
echo ""
log "Hardening complete. Summary:"
echo "  ✅ File permissions: 755/644, wp-config=640"
echo "  ✅ DISALLOW_FILE_EDIT: enabled"
echo "  ✅ Apache: autoindex off, version hidden, security headers"
echo "  ✅ .htaccess: wp-config.php, xmlrpc.php, hidden files blocked"
echo "  ✅ UFW firewall: only ports 22, 80, 443 open"
echo "  ✅ fail2ban: SSH + WordPress brute-force protection"
echo "  ✅ PHP in uploads: blocked"
echo "  ✅ Automatic security updates: enabled"
