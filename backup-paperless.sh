#!/bin/bash
# If not installed, install cifs-utils: apt install -y cifs-utils
# Create credential file: nano /root/.smbcredentials
# Add and customize the lines below:
#   username=USERNAME
#   password=PASSWORD
#   domain=WORKGROUP # optional
# Modify permissions for the created .smbcredentials file: chmod 600 /root/.smbcredentials
# Make the script executable: chmod +x /path/to/script.sh
# Cronjob: 0 3 * * 0 /path/to/script.sh >> /var/log/backup-paperless.log 2>&1
# Clean up old backup files on Windows, where the SMB share is running, with a Powershell script:
#   $date = (Get-Date).AddDays(-31)
#   Get-ChildItem D:\Backup\paperless | Where-Object {$_.LastWriteTime -lt $date} | Remove-Item -Force

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
