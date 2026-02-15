#!/bin/bash
# If not installed, install cifs-utils: apt install -y cifs-utils
# Create log file (once): touch /var/log/smb_backup.log
# Modify permissions for the created smb_backup.log file: chmod 600 /var/log/smb_backup.log
# Create credential file: nano /root/.smbcredentials
## Add and customize the lines below:
#     username=USERNAME
#     password=PASSWORD
#     domain=WORKGROUP # optional
# Modify permissions for the created .smbcredentials file: chmod 600 /root/.smbcredentials
# Create a file in /root/ with the name backup-paperless.sh and add this script content: nano /root/backup-paperless.sh
# Make the script executable: chmod +x /root/backup-paperless.sh
# Cronjob: 0 3 * * 0 /root/backup-paperless.sh >> /var/log/smb_backup.log 2>&1
# List Cronjobs: crontab -l | Edit Cronjobs crontab -e
# Test by executing manually: /usr/bin/env -i HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bi  /root/backup-paperless.sh  >> /var/log/smb_backup.log 2>&1
## Read logs:
#    tail -n 50 /var/log/smb_backup.log
#    tail -f /var/log/smb_backup.log (live)
#    grep CRON /var/log/syslog
#    journalctl -u cron -f
## Clean up old backup files on Windows, where the SMB share is running, with a Powershell script:
#     $date = (Get-Date).AddDays(-31)
#     Get-ChildItem D:\Backup\paperless | Where-Object {$_.LastWriteTime -lt $date} | Remove-Item -Force

#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

set -e

# Configuration
DATE=$(date +%Y-%m-%d)
SERVER="//IP_ADDRESS/Backup"
EXPORT_DIR="/opt/paperless/export/$DATE"
REMOTE_DIR="paperless" 
CREDS="/root/.smbcredentials"

# Create Export Folder
mkdir -p "$EXPORT_DIR"
chmod 777 "$EXPORT_DIR"

# Run Paperless Export
cd /opt/paperless/src/
uv run ./manage.py document_exporter "$EXPORT_DIR/" -z -f -p -d --no-progress-bar

# Upload
smbclient "$SERVER" -A="$CREDS" -c "cd $REMOTE_DIR; put $EXPORT_DIR/export-$DATE.zip export-$DATE.zip"

# Remove Folder
rm -rf "$EXPORT_DIR"
