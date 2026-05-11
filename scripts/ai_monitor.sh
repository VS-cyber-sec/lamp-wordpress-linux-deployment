#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  AI-Powered Server Monitor
#  Uses the Claude API to analyse Apache logs, detect anomalies,
#  generate plain-English health reports, and send them by email.
#
#  Usage:
#    sudo bash scripts/ai_monitor.sh           # run analysis now
#    sudo bash scripts/ai_monitor.sh --setup   # install cron job
#    sudo bash scripts/ai_monitor.sh --report  # print last report
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${REPO_DIR}/config/config.env"
source "$CONFIG_FILE"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[→]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

REPORT_DIR="${REPO_DIR}/ai/reports"
TODAY=$(date +%Y-%m-%d)
REPORT_FILE="${REPORT_DIR}/${TODAY}.md"
mkdir -p "$REPORT_DIR"

# ── --setup: install cron job ─────────────────────────────────
if [[ "${1:-}" == "--setup" ]]; then
  if [[ -z "${ANTHROPIC_API_KEY:-}" || "${ANTHROPIC_API_KEY}" == "sk-ant-your-key-here" ]]; then
    echo -e "${RED}Error: Set ANTHROPIC_API_KEY in config/config.env first.${NC}"
    exit 1
  fi

  CRON_CMD="0 7 * * * root bash ${SCRIPT_DIR}/ai_monitor.sh >> /var/log/ai_monitor.log 2>&1"
  echo "$CRON_CMD" > /etc/cron.d/ai-monitor
  chmod 644 /etc/cron.d/ai-monitor
  log "AI monitor cron installed: runs daily at 7 AM"
  log "Reports saved to: ${REPORT_DIR}/"
  info "Run now with: sudo bash scripts/ai_monitor.sh"
  exit 0
fi

# ── --report: print last report ───────────────────────────────
if [[ "${1:-}" == "--report" ]]; then
  LATEST=$(ls -1t "${REPORT_DIR}"/*.md 2>/dev/null | head -1)
  if [[ -n "$LATEST" ]]; then
    cat "$LATEST"
  else
    echo "No reports yet. Run: sudo bash scripts/ai_monitor.sh"
  fi
  exit 0
fi

# ── Validate API key ──────────────────────────────────────────
if [[ "${AI_MONITORING_ENABLED:-false}" != "true" ]]; then
  warn "AI monitoring is disabled (AI_MONITORING_ENABLED=false in config.env)"
  exit 0
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" || "${ANTHROPIC_API_KEY}" == "sk-ant-your-key-here" ]]; then
  echo -e "${RED}Error: ANTHROPIC_API_KEY not set in config/config.env${NC}"
  exit 1
fi

# ── Collect server data ───────────────────────────────────────
info "Collecting server telemetry..."

# Apache error log — last 24 hours (max 200 lines)
ERROR_LOG=$(tail -n 200 /var/log/apache2/error.log 2>/dev/null | \
  grep "$(date --date='1 day ago' '+%a %b %d')\|$(date '+%a %b %d')" | \
  tail -100 || echo "(no error log entries)")

# Apache access log — last 24 hours (max 300 lines, summarised)
ACCESS_LOG=$(tail -n 500 /var/log/apache2/access.log 2>/dev/null | \
  awk '{print $1,$7,$9}' | tail -300 || echo "(no access log entries)")

# fail2ban events
FAIL2BAN_LOG=$(grep "Ban\|Unban" /var/log/fail2ban.log 2>/dev/null | tail -50 || echo "(no fail2ban events)")

# System stats
DISK_USAGE=$(df -h / /backup 2>/dev/null || df -h /)
MEMORY=$(free -h)
UPTIME=$(uptime)
WP_VERSION=$(grep wp_version /var/www/html/wordpress/wp-includes/version.php 2>/dev/null | cut -d"'" -f4 || echo "unknown")
APACHE_STATUS=$(systemctl is-active apache2 2>/dev/null || echo "unknown")
MARIADB_STATUS=$(systemctl is-active mariadb 2>/dev/null || echo "unknown")
FAIL2BAN_STATUS=$(systemctl is-active fail2ban 2>/dev/null || echo "unknown")
UFW_STATUS=$(ufw status 2>/dev/null | head -5 || echo "unknown")

log "Telemetry collected"

# ── Build AI prompt ───────────────────────────────────────────
PROMPT="You are a Linux server security and reliability analyst. Analyse the following WordPress server data and produce a concise, actionable daily health report.

SERVER INFO:
- Date: ${TODAY}
- WordPress version: ${WP_VERSION}
- Apache: ${APACHE_STATUS}
- MariaDB: ${MARIADB_STATUS}
- fail2ban: ${FAIL2BAN_STATUS}
- Uptime: ${UPTIME}

MEMORY:
${MEMORY}

DISK USAGE:
${DISK_USAGE}

UFW FIREWALL STATUS:
${UFW_STATUS}

APACHE ERROR LOG (last 24h):
${ERROR_LOG}

APACHE ACCESS LOG SUMMARY (last 24h, format: IP URL STATUS):
${ACCESS_LOG}

FAIL2BAN EVENTS (last 24h):
${FAIL2BAN_LOG}

Write a health report in Markdown with these sections:
1. **Overall Status** (one of: ✅ Healthy / ⚠️ Needs Attention / 🚨 Critical Issues)
2. **Summary** (2-3 sentences max)
3. **Issues Found** (list any errors, anomalies, suspicious IPs, unusual patterns — or 'None' if clean)
4. **Security Events** (brute force attempts, banned IPs, suspicious requests)
5. **Resource Health** (disk, memory — flag if anything is above 80%)
6. **Recommended Actions** (numbered list of specific things to do, or 'No action needed')

Be concise, direct, and specific. Format as clean Markdown. Do not include preamble or sign-off."

# ── Call Claude API ───────────────────────────────────────────
info "Sending data to Claude API for analysis..."

RESPONSE=$(curl -fsSL https://api.anthropic.com/v1/messages \
  -H "x-api-key: ${ANTHROPIC_API_KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$(jq -n \
    --arg model "claude-sonnet-4-20250514" \
    --arg prompt "$PROMPT" \
    '{
      model: $model,
      max_tokens: 1024,
      messages: [{ role: "user", content: $prompt }]
    }'
  )" 2>/dev/null)

# Extract report text from API response
REPORT_TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text' 2>/dev/null || echo "Error: Could not parse API response")

# ── Save report ───────────────────────────────────────────────
cat > "$REPORT_FILE" << EOF
# AI Health Report — ${TODAY}
*Generated by lamp-wordpress-pro AI Monitor*

---

${REPORT_TEXT}

---
*Report generated: $(date) | Model: claude-sonnet-4*
EOF

log "Report saved: ${REPORT_FILE}"

# ── Email report (if enabled) ─────────────────────────────────
if [[ "${AI_REPORT_EMAIL:-false}" == "true" && -n "${EMAIL:-}" ]]; then
  if command -v mail &>/dev/null || command -v sendmail &>/dev/null; then
    SUBJECT="WordPress Server Report — ${TODAY} — $(echo "$REPORT_TEXT" | grep -o '✅ Healthy\|⚠️ Needs Attention\|🚨 Critical Issues' | head -1 || echo 'See report')"
    echo "$REPORT_TEXT" | mail -s "$SUBJECT" "${EMAIL}" 2>/dev/null && \
      log "Report emailed to ${EMAIL}" || \
      warn "Email send failed — check mail config"
  else
    warn "mail/sendmail not installed — skipping email"
  fi
fi

# ── Print to console ──────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$REPORT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
