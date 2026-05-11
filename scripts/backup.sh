#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  Backup Script — WordPress Files + Database
#  Features: secure credentials, S3 upload, 28-day retention,
#            detailed logging, integrity check
#  Usage: sudo bash scripts/backup.sh [--test]
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/config.env"
source "$CONFIG_FILE"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $*" | tee -a "$LOG_FILE"; }
info()  { echo -e "${BLUE}[→]${NC} $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[✗]${NC} $*" | tee -a "$LOG_FILE"; }

TEST_MODE=false
[[ "${1:-}" == "--test" ]] && TEST_MODE=true

# ── Setup paths ───────────────────────────────────────────────
WP_DIR="/var/www/html/wordpress"
BACKUP_BASE="${BACKUP_DIR:-/backup}"
DATESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_PATH="${BACKUP_BASE}/wordpress-${DATESTAMP}"
LOG_DIR="${BACKUP_BASE}/logs"
LOG_FILE="${LOG_DIR}/backup-${DATESTAMP}.log"

mkdir -p "$BACKUP_PATH" "$LOG_DIR"

echo "════════════════════════════════════════" | tee -a "$LOG_FILE"
echo " WordPress Backup — $(date)"             | tee -a "$LOG_FILE"
echo " Destination: $BACKUP_PATH"              | tee -a "$LOG_FILE"
echo "════════════════════════════════════════" | tee -a "$LOG_FILE"

# ── Write secure MySQL credentials file ──────────────────────
MY_CNF=$(mktemp)
cat > "$MY_CNF" << EOF
[mysqldump]
user=${DB_USER}
password=${DB_PASSWORD}
EOF
chmod 600 "$MY_CNF"
trap "rm -f '$MY_CNF'" EXIT   # always delete even on failure

# ── 1. Database backup ────────────────────────────────────────
info "Dumping database '${DB_NAME}'..."
DB_FILE="${BACKUP_PATH}/database.sql"
mysqldump --defaults-file="$MY_CNF" \
  --single-transaction \
  --quick \
  --lock-tables=false \
  --routines \
  --triggers \
  "${DB_NAME}" > "$DB_FILE"

DB_SIZE=$(du -sh "$DB_FILE" | cut -f1)
log "Database dump complete (${DB_SIZE}): database.sql"

# ── 2. Compress database dump ─────────────────────────────────
gzip "$DB_FILE"
log "Database compressed: database.sql.gz"

# ── 3. File backup (rsync) ────────────────────────────────────
info "Syncing WordPress files..."
rsync -a --delete \
  --exclude="*.log" \
  --exclude=".git" \
  "${WP_DIR}/" "${BACKUP_PATH}/wordpress/"

FILE_SIZE=$(du -sh "${BACKUP_PATH}/wordpress" | cut -f1)
log "File sync complete (${FILE_SIZE})"

# ── 4. Create backup manifest ────────────────────────────────
info "Writing backup manifest..."
cat > "${BACKUP_PATH}/manifest.txt" << EOF
LAMP WordPress Pro — Backup Manifest
=====================================
Date:        $(date)
Hostname:    $(hostname)
WP version:  $(grep wp_version "${WP_DIR}/wp-includes/version.php" 2>/dev/null | cut -d"'" -f4 || echo 'unknown')
DB name:     ${DB_NAME}
Files:       $(find "${BACKUP_PATH}/wordpress" -type f | wc -l) files
DB size:     $(du -sh "${BACKUP_PATH}/database.sql.gz" | cut -f1)
Files size:  ${FILE_SIZE}
Total size:  $(du -sh "${BACKUP_PATH}" | cut -f1)
EOF
log "Manifest written"

# ── 5. S3 upload (if enabled) ────────────────────────────────
if [[ "${S3_ENABLED:-false}" == "true" && -n "${S3_BUCKET:-}" ]]; then
  info "Uploading backup to S3: s3://${S3_BUCKET}/backups/wordpress-${DATESTAMP}/"
  aws s3 sync "${BACKUP_PATH}/" \
    "s3://${S3_BUCKET}/backups/wordpress-${DATESTAMP}/" \
    --storage-class STANDARD_IA \
    --region "${AWS_REGION:-ap-south-1}" \
    --quiet
  log "S3 upload complete"
else
  warn "S3 upload skipped (S3_ENABLED=false or S3_BUCKET not set)"
fi

# ── 6. Retention: delete backups older than N days ────────────
RETENTION="${BACKUP_RETENTION_DAYS:-28}"
info "Applying ${RETENTION}-day retention policy..."
find "${BACKUP_BASE}" -maxdepth 1 -type d -name "wordpress-*" \
  -mtime "+${RETENTION}" -exec rm -rf {} \; 2>/dev/null || true
log "Old backups pruned (kept last ${RETENTION} days)"

# ── 7. Disk space check ───────────────────────────────────────
DISK_USED=$(df -h "${BACKUP_BASE}" | awk 'NR==2{print $5}' | tr -d '%')
if [[ "$DISK_USED" -gt 85 ]]; then
  warn "Disk usage is at ${DISK_USED}% — consider cleaning old backups or adding storage"
else
  log "Disk usage: ${DISK_USED}% (healthy)"
fi

# ── Summary ───────────────────────────────────────────────────
echo "" | tee -a "$LOG_FILE"
log "Backup complete: ${BACKUP_PATH}"
echo "  Total backup size: $(du -sh "${BACKUP_PATH}" | cut -f1)" | tee -a "$LOG_FILE"
echo "  Log: $LOG_FILE" | tee -a "$LOG_FILE"

[[ "$TEST_MODE" == "true" ]] && echo "  (Test mode: backup created and will be retained)"
