#!/bin/bash
###############################################################################
# pgBackRest Automated Backup Script
# Purpose : Day-based full/incremental backup for PostgreSQL
# Schedule: Full on Sunday, Incremental Monday–Saturday
# Location: /u01/posthger (configured in /etc/pgbackrest.conf)
# Usage   : ./pg_backup.sh
# Crontab : 0 2 * * * /opt/pgbackrest/scripts/pg_backup.sh >> /var/log/pgbackrest/pg_backup_cron.log 2>&1
# Last Updated: 2026-02-19
###############################################################################

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
STANZA="prod-db"
LOG_DIR="/var/log/pgbackrest"
SCRIPT_LOG="${LOG_DIR}/pg_backup_script.log"
LOCK_FILE="/tmp/pgbackrest_backup.lock"
DATE_STAMP=$(date '+%Y-%m-%d_%H%M%S')
DAY_OF_WEEK=$(date '+%u')   # 1=Monday ... 7=Sunday

# ─── Alert Configuration (customize as needed) ──────────────────────────────
ALERT_EMAIL="dba-team@example.com"
ALERT_ENABLED="false"        # Set to "true" to enable email alerts

# ─── Functions ───────────────────────────────────────────────────────────────

log_msg() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "${SCRIPT_LOG}"
}

send_alert() {
    local subject="$1"
    local body="$2"
    if [[ "${ALERT_ENABLED}" == "true" ]]; then
        echo "${body}" | mail -s "${subject}" "${ALERT_EMAIL}" 2>/dev/null || \
            log_msg "WARN" "Failed to send email alert"
    fi
}

cleanup() {
    rm -f "${LOCK_FILE}"
    log_msg "INFO" "Lock file removed. Script cleanup complete."
}

# ─── Pre-flight Checks ──────────────────────────────────────────────────────

# Ensure log directory exists
if [[ ! -d "${LOG_DIR}" ]]; then
    mkdir -p "${LOG_DIR}"
    chown postgres:postgres "${LOG_DIR}"
    chmod 750 "${LOG_DIR}"
fi

# Prevent concurrent execution
if [[ -f "${LOCK_FILE}" ]]; then
    EXISTING_PID=$(cat "${LOCK_FILE}" 2>/dev/null)
    if kill -0 "${EXISTING_PID}" 2>/dev/null; then
        log_msg "ERROR" "Another backup is already running (PID: ${EXISTING_PID}). Exiting."
        send_alert "[PGBACKREST] Backup Skipped - Concurrent Run" \
            "A backup process (PID: ${EXISTING_PID}) is already running on $(hostname). Backup at ${DATE_STAMP} was skipped."
        exit 1
    else
        log_msg "WARN" "Stale lock file found (PID: ${EXISTING_PID} not running). Removing."
        rm -f "${LOCK_FILE}"
    fi
fi

echo $$ > "${LOCK_FILE}"
trap cleanup EXIT

log_msg "INFO" "======================================================================"
log_msg "INFO" "pgBackRest Backup Started - ${DATE_STAMP}"
log_msg "INFO" "Hostname: $(hostname) | Stanza: ${STANZA}"
log_msg "INFO" "======================================================================"

# ─── Determine Backup Type ──────────────────────────────────────────────────

if [[ "${DAY_OF_WEEK}" -eq 7 ]]; then
    BACKUP_TYPE="full"
    log_msg "INFO" "Day of week: Sunday (${DAY_OF_WEEK}) → FULL backup selected"
else
    BACKUP_TYPE="incr"
    log_msg "INFO" "Day of week: $(date '+%A') (${DAY_OF_WEEK}) → INCREMENTAL backup selected"
fi

# ─── Execute Backup ─────────────────────────────────────────────────────────

log_msg "INFO" "Executing: pgbackrest --stanza=${STANZA} --type=${BACKUP_TYPE} backup"

BACKUP_START=$(date +%s)

if pgbackrest --stanza="${STANZA}" --type="${BACKUP_TYPE}" backup 2>&1 | tee -a "${SCRIPT_LOG}"; then
    BACKUP_END=$(date +%s)
    BACKUP_DURATION=$(( BACKUP_END - BACKUP_START ))
    log_msg "INFO" "Backup completed successfully in ${BACKUP_DURATION} seconds."

    # ─── Post-Backup Verification ────────────────────────────────────────
    log_msg "INFO" "Running post-backup verification..."

    if pgbackrest --stanza="${STANZA}" check 2>&1 | tee -a "${SCRIPT_LOG}"; then
        log_msg "INFO" "Stanza check PASSED."
    else
        log_msg "WARN" "Stanza check reported warnings. Review logs."
    fi

    # Log current backup info
    log_msg "INFO" "Current backup inventory:"
    pgbackrest --stanza="${STANZA}" info 2>&1 | tee -a "${SCRIPT_LOG}"

    send_alert "[PGBACKREST] Backup SUCCESS on $(hostname)" \
        "Backup Type: ${BACKUP_TYPE}\nDuration: ${BACKUP_DURATION}s\nStanza: ${STANZA}\nTimestamp: ${DATE_STAMP}"

else
    BACKUP_END=$(date +%s)
    BACKUP_DURATION=$(( BACKUP_END - BACKUP_START ))
    log_msg "ERROR" "Backup FAILED after ${BACKUP_DURATION} seconds!"

    send_alert "[PGBACKREST] *** Backup FAILED on $(hostname) ***" \
        "Backup Type: ${BACKUP_TYPE}\nStanza: ${STANZA}\nTimestamp: ${DATE_STAMP}\nDuration: ${BACKUP_DURATION}s\n\nCheck logs at: ${SCRIPT_LOG}"

    exit 2
fi

# ─── Log Rotation (keep last 30 days of script logs) ────────────────────────

find "${LOG_DIR}" -name "pg_backup_script*.log" -mtime +30 -delete 2>/dev/null || true

log_msg "INFO" "======================================================================"
log_msg "INFO" "pgBackRest Backup Finished - $(date '+%Y-%m-%d %H:%M:%S')"
log_msg "INFO" "======================================================================"

exit 0
