# pgBackRest – Production Backup Configuration

Enterprise-grade PostgreSQL backup solution using **pgBackRest** with automated full/incremental scheduling, log management, and retention policies.

---

## 📁 File Overview

| File | Purpose |
|------|---------|
| `pgbackrest.conf` | Main configuration → deploy to `/etc/pgbackrest.conf` |
| `pg_backup.sh` | Backup script with day-based logic → deploy to `/opt/pgbackrest/scripts/` |
| `crontab.txt` | Cron schedule (daily at 2 AM) → install via `crontab -e` |

---

## 🔧 Backup Policy

| Day | Backup Type |
|-----|-------------|
| **Sunday** | Full Backup |
| **Monday – Saturday** | Incremental Backup |

**Retention:** 4 full backups + 7 differentials + matching archive sets

---

## 🚀 Deployment Guide

### 1. Install pgBackRest

```bash
# RHEL / Rocky / AlmaLinux
sudo dnf install -y pgbackrest

# Debian / Ubuntu
sudo apt-get install -y pgbackrest
```

### 2. Deploy Configuration

```bash
# Copy configuration file
sudo cp pgbackrest.conf /etc/pgbackrest.conf
sudo chown postgres:postgres /etc/pgbackrest.conf
sudo chmod 640 /etc/pgbackrest.conf
```

> [!IMPORTANT]
> Edit `/etc/pgbackrest.conf` and update `pg1-path` to match your actual PostgreSQL data directory.

### 3. Create Required Directories

```bash
# Backup repository
sudo mkdir -p /u01/posthger
sudo chown postgres:postgres /u01/posthger
sudo chmod 750 /u01/posthger

# Log directory
sudo mkdir -p /var/log/pgbackrest
sudo chown postgres:postgres /var/log/pgbackrest
sudo chmod 750 /var/log/pgbackrest

# Archive spool directory
sudo mkdir -p /var/spool/pgbackrest
sudo chown postgres:postgres /var/spool/pgbackrest
sudo chmod 750 /var/spool/pgbackrest

# Script directory
sudo mkdir -p /opt/pgbackrest/scripts
```

### 4. Configure PostgreSQL for WAL Archiving

Add to `postgresql.conf`:

```ini
archive_mode = on
archive_command = 'pgbackrest --stanza=prod-db archive-push %p'
```

Restart PostgreSQL:

```bash
sudo systemctl restart postgresql-16
```

### 5. Deploy Backup Script

```bash
sudo cp pg_backup.sh /opt/pgbackrest/scripts/pg_backup.sh
sudo chown postgres:postgres /opt/pgbackrest/scripts/pg_backup.sh
sudo chmod 750 /opt/pgbackrest/scripts/pg_backup.sh
```

### 6. Initialize Stanza

```bash
# Create the stanza (first-time setup)
sudo -u postgres pgbackrest --stanza=prod-db stanza-create

# Verify the stanza configuration
sudo -u postgres pgbackrest --stanza=prod-db check
```

### 7. Install Crontab

```bash
# As the postgres user
sudo -u postgres crontab -e
# Paste the contents of crontab.txt
```

---

## ✅ Verification Commands

### Check Stanza Health

```bash
sudo -u postgres pgbackrest --stanza=prod-db check
```

### View Backup Inventory

```bash
sudo -u postgres pgbackrest --stanza=prod-db info
```

### Detailed Backup Info (JSON)

```bash
sudo -u postgres pgbackrest --stanza=prod-db info --output=json
```

### Run a Manual Full Backup

```bash
sudo -u postgres pgbackrest --stanza=prod-db --type=full backup
```

### Run a Manual Incremental Backup

```bash
sudo -u postgres pgbackrest --stanza=prod-db --type=incr backup
```

### Verify Latest Backup Integrity

```bash
sudo -u postgres pgbackrest --stanza=prod-db --set=latest verify
```

### Expire Old Backups (per retention policy)

```bash
sudo -u postgres pgbackrest --stanza=prod-db expire
```

---

## 📋 Log Locations

| Log | Path |
|-----|------|
| pgBackRest native logs | `/var/log/pgbackrest/prod-db-backup.log` |
| Backup script logs | `/var/log/pgbackrest/pg_backup_script.log` |
| Cron output | `/var/log/pgbackrest/pg_backup_cron.log` |

Script logs auto-rotate (30 day retention).

---

## 🔄 Restore Procedures

### Full Restore (stop PostgreSQL first)

```bash
sudo systemctl stop postgresql-16

sudo -u postgres pgbackrest --stanza=prod-db --delta restore

sudo systemctl start postgresql-16
```

### Point-in-Time Recovery (PITR)

```bash
sudo systemctl stop postgresql-16

sudo -u postgres pgbackrest --stanza=prod-db \
    --type=time \
    --target="2026-02-19 14:30:00" \
    --target-action=promote \
    --delta \
    restore

sudo systemctl start postgresql-16
```

### Restore to an Alternate Location

```bash
sudo -u postgres pgbackrest --stanza=prod-db \
    --pg1-path=/var/lib/pgsql/16/data_restore \
    --delta \
    restore
```

---

## ⚙️ Configuration Reference

### Key `pgbackrest.conf` Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `repo1-path` | `/u01/posthger` | Backup storage location |
| `repo1-retention-full` | `4` | Keep 4 full backups |
| `repo1-retention-diff` | `7` | Keep 7 differential sets |
| `compress-type` | `lz4` | Fast compression |
| `process-max` | `4` | Parallel backup processes |
| `start-fast` | `y` | Force immediate checkpoint |
| `delta` | `y` | Enable delta restore |
| `archive-async` | `y` | Async WAL archiving |

---

## 🛡️ Enterprise Hardening Checklist

- [ ] Verify `pg1-path` matches actual PostgreSQL data directory
- [ ] Test email alerts by setting `ALERT_ENABLED="true"` in `pg_backup.sh`
- [ ] Run an initial full backup and verify with `pgbackrest check`
- [ ] Test a restore to an alternate location
- [ ] Set up monitoring/alerting on backup script exit codes
- [ ] Configure TLS if using remote backup repository
- [ ] Restrict `/etc/pgbackrest.conf` permissions (`640`, owned by `postgres`)
- [ ] Add backup verification to weekly runbook
- [ ] Document restore procedures in your DR playbook
