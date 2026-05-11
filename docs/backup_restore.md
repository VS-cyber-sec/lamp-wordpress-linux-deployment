# Backup and Restore Guide

---

## Creating a backup

**Manual backup:**
```bash
sudo bash scripts/backup.sh
```

**Test run (won't be pruned by retention policy):**
```bash
sudo bash scripts/backup.sh --test
```

**Check backup logs:**
```bash
ls -la /backup/logs/
cat /backup/logs/backup-$(date +%Y-%m-%d)*.log
```

---

## Backup structure

Each backup creates a dated folder:
```
/backup/
  wordpress-2025-07-15_02-00-01/
    database.sql.gz       ← Full database dump (compressed)
    wordpress/            ← Complete WordPress file tree
      wp-config.php
      wp-content/
      wp-includes/
      wp-admin/
      ...
    manifest.txt          ← Backup summary (date, sizes, WP version)
  logs/
    backup-2025-07-15_02-00-01.log
```

---

## Restoring from backup

### Restore the database

```bash
# Find your backup
ls /backup/

# Decompress the SQL dump
gunzip /backup/wordpress-YYYY-MM-DD_HH-MM-SS/database.sql.gz

# Drop and recreate the database
mysql -e "DROP DATABASE IF EXISTS wordpress_db; CREATE DATABASE wordpress_db;"

# Restore
mysql wordpress_db < /backup/wordpress-YYYY-MM-DD_HH-MM-SS/database.sql

echo "Database restored"
```

### Restore WordPress files

```bash
# Backup current files first (just in case)
sudo mv /var/www/html/wordpress /var/www/html/wordpress.old

# Restore from backup
sudo rsync -a /backup/wordpress-YYYY-MM-DD_HH-MM-SS/wordpress/ /var/www/html/wordpress/

# Fix ownership and permissions
sudo chown -R www-data:www-data /var/www/html/wordpress
sudo find /var/www/html/wordpress -type d -exec chmod 755 {} \;
sudo find /var/www/html/wordpress -type f -exec chmod 644 {} \;
sudo chmod 640 /var/www/html/wordpress/wp-config.php

sudo systemctl reload apache2
echo "Files restored"
```

### Full restore (both database and files)

```bash
BACKUP="/backup/wordpress-YYYY-MM-DD_HH-MM-SS"

# Files
sudo rsync -a "${BACKUP}/wordpress/" /var/www/html/wordpress/
sudo chown -R www-data:www-data /var/www/html/wordpress

# Database
gunzip "${BACKUP}/database.sql.gz"
mysql -e "DROP DATABASE IF EXISTS wordpress_db; CREATE DATABASE wordpress_db;"
mysql wordpress_db < "${BACKUP}/database.sql"

sudo systemctl reload apache2
echo "Full restore complete"
```

---

## Restoring from S3

If you have S3 backups enabled:

```bash
# List available backups
aws s3 ls s3://your-bucket-name/backups/

# Download a specific backup
aws s3 sync s3://your-bucket-name/backups/wordpress-YYYY-MM-DD_HH-MM-SS/ \
  /backup/restored/ \
  --region ap-south-1

# Then follow the restore steps above using /backup/restored/ as your BACKUP path
```

---

## Verifying a backup

```bash
# Check the manifest
cat /backup/wordpress-YYYY-MM-DD_HH-MM-SS/manifest.txt

# Count files
find /backup/wordpress-YYYY-MM-DD_HH-MM-SS/wordpress -type f | wc -l

# Check SQL dump is valid
gunzip -c /backup/wordpress-YYYY-MM-DD_HH-MM-SS/database.sql.gz | head -20
```
