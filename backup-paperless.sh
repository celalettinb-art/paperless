#!/bin/bash

# If not installed, install cifs-utils: apt install -y cifs-utils
# Create credential file: nano /root/.smbcredentials
# Add and customize the lines below:
# username=USERNAME
# password=PASSWORD
# domain=WORKGROUP # optional
# Modify permissions for the created .smbcredentials file: chmod 600 /root/.smbcredentials
# Make the script executable: chmod +x /path/to/script.sh
# Cronjob: 0 3 * * * /path/to/script.sh >> /var/log/backup-paperless.log 2>&1

# mount SMB-Share mounten 
mount -t cifs //192.168.1.8/Backup/paperless /mnt/backup-paperless \
  -o credentials=/root/.smbcredentials,iocharset=utf8,nofail

# Dateien löschen, die älter als 14 Tage sind
find /mnt/backup-paperless -type f -mtime +14 -delete

# Export-Verzeichnis anlegen
mkdir /opt/paperless/export/$(date +%Y-%m-%d)
chmod 777 /opt/paperless/export/$(date +%Y-%m-%d)

# Paperless Export
cd /opt/paperless/src/ || exit 1
./manage.py document_exporter ../export/$(date +%Y-%m-%d)/ -z

# ZIP ins SMB-Share verschieben
mv /opt/paperless/export/$(date +%Y-%m-%d)/export-$(date +%Y-%m-%d).zip /mnt/backup-paperless

# Temporäres Export-Verzeichnis löschen
rm -r /opt/paperless/export/$(date +%Y-%m-%d)/

# SMB-Share aushängen
umount /mnt/backup-paperless
