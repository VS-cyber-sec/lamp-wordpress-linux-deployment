#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  LAMP WordPress Pro — Master Deployment Script
#  Runs all phases in order with pre-flight checks.
#  Usage: sudo bash scripts/deploy_all.sh
# ═══════════════════════════════════════════════════════════════
set -euo pipefail
trap 'echo "❌ Deploy failed at line $LINENO. Check the output above." >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/config.env"

# ── colours ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

banner() {
  echo -e "${CYAN}"
  echo "  ██╗      █████╗ ███╗   ███╗██████╗     ██╗    ██╗██████╗  "
  echo "  ██║     ██╔══██╗████╗ ████║██╔══██╗    ██║    ██║██╔══██╗ "
  echo "  ██║     ███████║██╔████╔██║██████╔╝    ██║ █╗ ██║██████╔╝ "
  echo "  ██║     ██╔══██║██║╚██╔╝██║██╔═══╝     ██║███╗██║██╔═══╝  "
  echo "  ███████╗██║  ██║██║ ╚═╝ ██║██║         ╚███╔███╔╝██║      "
  echo "  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝          ╚══╝╚══╝ ╚═╝     "
  echo -e "${NC}"
  echo -e "  ${BOLD}LAMP × WordPress Pro — Production Deployment${NC}"
  echo -e "  ${YELLOW}AWS EC2 · Ubuntu 22.04 · Hardened · AI-Monitored${NC}"
  echo ""
}

log()     { echo -e "${GREEN}[✓]${NC} $*"; }
info()    { echo -e "${BLUE}[→]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── pre-flight checks ──────────────────────────────────────────
section "Pre-flight checks"

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Error: This script must be run as root (sudo bash deploy_all.sh)${NC}"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo -e "${RED}Error: config/config.env not found.${NC}"
  echo "  Run: cp config/config.example.env config/config.env"
  echo "  Then edit config/config.env with your values."
  exit 1
fi

source "$CONFIG_FILE"

# Validate required config values
required_vars=(DB_NAME DB_USER DB_PASSWORD EMAIL)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo -e "${RED}Error: $var is not set in config.env${NC}"; exit 1
  fi
done

if [[ "${DB_PASSWORD}" == "ChangeMe_StrongPassword123!" ]]; then
  echo -e "${RED}Error: You must change DB_PASSWORD in config.env before deploying!${NC}"
  exit 1
fi

log "Config loaded and validated"
log "Running as root"
log "Ubuntu version: $(lsb_release -ds 2>/dev/null || echo 'unknown')"
log "Target domain: ${DOMAIN:-'(none — using IP)'}"

# ── run phases ────────────────────────────────────────────────
START_TIME=$(date +%s)

section "Phase 1 — LAMP Stack"
bash "$SCRIPT_DIR/install_lamp.sh"

section "Phase 2 — WordPress"
bash "$SCRIPT_DIR/install_wordpress.sh"

section "Phase 3 — Security Hardening"
bash "$SCRIPT_DIR/harden_wordpress.sh"

if [[ -n "${DOMAIN:-}" && "${DOMAIN}" != "yourdomain.com" ]]; then
  section "Phase 4 — SSL Certificate"
  bash "$SCRIPT_DIR/ssl_setup.sh"
else
  warn "Skipping SSL — no domain set in config.env"
  warn "Add your domain later and run: sudo bash scripts/ssl_setup.sh"
fi

if [[ "${AI_MONITORING_ENABLED:-false}" == "true" ]]; then
  section "AI Monitoring Setup"
  bash "$SCRIPT_DIR/ai_monitor.sh" --setup
fi

# ── summary ───────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

section "Deployment Complete"
echo ""
echo -e "  ${GREEN}${BOLD}✅ WordPress is live!${NC}"
echo ""
echo -e "  ${BOLD}Site URL:${NC}      http://${DOMAIN:-$(curl -s ifconfig.me 2>/dev/null || echo 'YOUR_IP')}/wordpress"
echo -e "  ${BOLD}Admin panel:${NC}   http://${DOMAIN:-YOUR_IP}/wordpress/wp-admin"
echo -e "  ${BOLD}Time taken:${NC}    ${ELAPSED}s"
echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo "  1. Complete WordPress setup in your browser"
echo "  2. Set up your domain DNS A record → your Elastic IP"
echo "  3. Run ssl_setup.sh once DNS is live"
echo "  4. Test backup: sudo bash scripts/backup.sh --test"
echo "  5. Check AI report tomorrow: cat ai/reports/\$(date +%Y-%m-%d).md"
echo ""
