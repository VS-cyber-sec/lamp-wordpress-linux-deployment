#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Phase 4 — SSL Certificate via Let's Encrypt (Certbot)
#  Free, auto-renewing HTTPS for your domain.
#  Requires: domain DNS A record already pointing to this server.
# ═══════════════════════════════════════════════════════════════
set -euo pipefail
trap 'echo "❌ ssl_setup.sh failed at line $LINENO" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/config/config.env"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[→]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

WP_DIR="/var/www/html/wordpress"

# ── Validate domain is set ────────────────────────────────────
if [[ -z "${DOMAIN:-}" || "${DOMAIN}" == "yourdomain.com" ]]; then
  echo -e "${RED}Error: DOMAIN is not set in config.env.${NC}"
  echo "Set DOMAIN=yourdomain.com and ensure DNS is pointing to this server."
  exit 1
fi

# ── Check DNS resolves to this server ────────────────────────
info "Checking DNS resolution for ${DOMAIN}..."
SERVER_IP=$(curl -fsSL ifconfig.me 2>/dev/null || echo "unknown")
DOMAIN_IP=$(dig +short "${DOMAIN}" 2>/dev/null | tail -1 || echo "unresolved")

if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
  warn "DNS check: ${DOMAIN} resolves to ${DOMAIN_IP}, but this server is ${SERVER_IP}"
  warn "Make sure your domain's A record points to ${SERVER_IP} before continuing."
  read -rp "Continue anyway? (y/N): " proceed
  [[ "${proceed,,}" == "y" ]] || exit 1
else
  log "DNS OK: ${DOMAIN} → ${SERVER_IP}"
fi

# ── Install Certbot ──────────────────────────────────────────
if ! command -v certbot &>/dev/null; then
  info "Installing Certbot..."
  apt-get install -y certbot python3-certbot-apache
  log "Certbot installed"
else
  log "Certbot already installed"
fi

# ── Obtain certificate ────────────────────────────────────────
info "Requesting SSL certificate for ${DOMAIN} and www.${DOMAIN}..."
certbot --apache \
  --non-interactive \
  --agree-tos \
  --email "${EMAIL}" \
  --domains "${DOMAIN},www.${DOMAIN}" \
  --redirect    # auto-redirect HTTP → HTTPS
log "SSL certificate obtained and installed"

# ── Enable HSTS in security headers ──────────────────────────
info "Enabling HSTS header..."
HEADERS_CONF="/etc/apache2/conf-available/security-headers.conf"
if [[ -f "$HEADERS_CONF" ]]; then
  sed -i 's/# Header always set Strict-Transport-Security/Header always set Strict-Transport-Security/' "$HEADERS_CONF"
  systemctl reload apache2
  log "HSTS enabled (Strict-Transport-Security)"
fi

# ── Enable FORCE_SSL_ADMIN in wp-config.php ──────────────────
info "Enabling FORCE_SSL_ADMIN in wp-config.php..."
WP_CONFIG="$WP_DIR/wp-config.php"
if grep -q "FORCE_SSL_ADMIN" "$WP_CONFIG"; then
  sed -i "s/define( 'FORCE_SSL_ADMIN', false )/define( 'FORCE_SSL_ADMIN', true )/" "$WP_CONFIG"
else
  echo "define( 'FORCE_SSL_ADMIN', true );" >> "$WP_CONFIG"
fi
log "FORCE_SSL_ADMIN = true"

# ── Test auto-renewal ─────────────────────────────────────────
info "Testing certificate auto-renewal..."
certbot renew --dry-run
log "Auto-renewal dry run passed"

# ── Verify auto-renewal cron/timer ───────────────────────────
if systemctl list-timers | grep -q certbot; then
  log "Certbot renewal timer: active (systemd)"
else
  # Add cron fallback
  (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
  log "Certbot renewal cron added: daily at 3 AM"
fi

echo ""
log "SSL setup complete!"
echo "  🔒 https://${DOMAIN}/wordpress"
echo "  🔒 https://www.${DOMAIN}/wordpress"
echo "  Certificate auto-renews every 90 days"
echo ""
echo "  Update WordPress URLs in Dashboard → Settings → General:"
echo "  WordPress Address: https://${DOMAIN}/wordpress"
echo "  Site Address:      https://${DOMAIN}/wordpress"
