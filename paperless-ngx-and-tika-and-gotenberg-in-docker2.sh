# bash -c "$(curl -fsSL https://raw.githubusercontent.com/celalettinb-art/paperless/refs/heads/main/paperless-ngx-and-tika-and-gotenberg-in-docker2.sh)"

function post_install_paperless() {
echo "SSH Root Login erlauben"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart sshd

echo "Zufallspasswort ohne Sonderzeichen generieren"
tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 > /root/scan.creds
chmod 600 /root/scan.creds

SCAN_PW=$(cat /root/scan.creds)

echo "OCR Sprachen installieren"
apt update
apt install -y tesseract-ocr-deu tesseract-ocr-tur

echo "Paperless Konfiguration anpassen"
CONF="/opt/paperless/paperless.conf"
grep -q PAPERLESS_OCR_LANGUAGE $CONF || cat <<EOT >> $CONF
PAPERLESS_OCR_LANGUAGE=deu
PAPERLESS_OCR_LANGUAGES=eng tur
PAPERLESS_TIME_ZONE=Europe/Berlin
EOT

echo "Docker installieren"
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
  > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "Startscript fuer Gotenberg & Tika anpassen"
SCRIPT="/opt/paperless/scripts/start_services.sh"
cp $SCRIPT ${SCRIPT}.bak

cat <<'EOT' > $SCRIPT
#!/usr/bin/env bash
docker run --restart=always -p 3000:3000 -d gotenberg/gotenberg:latest \
  gotenberg --chromium-disable-javascript=true --chromium-allow-list="file:///tmp/.*"

docker run --restart=always -p 9998:9998 -d apache/tika:latest
EOT

chmod +x $SCRIPT
$SCRIPT

echo "Paperless Tika/Gotenberg konfigurieren"
grep -q PAPERLESS_TIKA_ENABLED $CONF || cat <<EOT >> $CONF
PAPERLESS_TIKA_ENABLED=true
PAPERLESS_TIKA_ENDPOINT=http://0.0.0.0:9998
PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://0.0.0.0:3000
EOT

echo "Samba installieren & konfigurieren"
apt install -y samba

adduser --disabled-password --gecos "" scan
echo "scan:$SCAN_PW" | chpasswd
echo -e "$SCAN_PW\n$SCAN_PW" | smbpasswd -a scan

cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

cat <<'EOT' >> /etc/samba/smb.conf

[consume]
path = /opt/paperless_data/consume
browseable = yes
writable = yes
valid users = scan
force user = scan
force group = scan
create mask = 0664
directory mask = 0775
EOT

sed -i '/\[homes\]/,/^$/s/^/;/' /etc/samba/smb.conf

chown -R scan:scan /opt/paperless_data/consume
chmod -R 775 /opt/paperless_data/consume

systemctl restart smbd
systemctl enable smbd

echo "Post-Install abgeschlossen"
EOF
}


post_install_paperless
