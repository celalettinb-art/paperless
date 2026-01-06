#!/usr/bin/env bash
set -e

function post_install_paperless() {

echo "SSH Root Login erlauben (WARNUNG: unsicher)"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart sshd

echo "Zufallspasswort ohne Sonderzeichen generieren"
SCAN_PW=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
echo "$SCAN_PW" > /root/scan.creds
chmod 600 /root/scan.creds

echo "OCR Sprachen installieren"
apt update
apt install -y tesseract-ocr-deu tesseract-ocr-eng tesseract-ocr-tur

echo "Paperless Konfiguration anpassen"
CONF="/opt/paperless/paperless.conf"
mkdir -p "$(dirname "$CONF")"
touch "$CONF"

grep -q PAPERLESS_OCR_LANGUAGE "$CONF" || cat <<EOT >> "$CONF"
PAPERLESS_OCR_LANGUAGE=deu
PAPERLESS_OCR_LANGUAGES=eng tur
PAPERLESS_TIME_ZONE=Europe/Berlin
EOT

echo "Docker installieren"
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

ARCH=$(dpkg --print-architecture)

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
  > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

echo "Startscript fuer Gotenberg & Tika anpassen"
SCRIPT="/opt/paperless/scripts/start_services.sh"
mkdir -p "$(dirname "$SCRIPT")"

[ -f "$SCRIPT" ] && cp "$SCRIPT" "${SCRIPT}.bak"

cat <<'EOT' > "$SCRIPT"
#!/usr/bin/env bash

docker rm -f gotenberg tika 2>/dev/null || true

docker run -d \
  --name gotenberg \
  --restart=always \
  -p 3000:3000 \
  gotenberg/gotenberg:latest \
  gotenberg --chromium-disable-javascript=true \
            --chromium-allow-list="file:///tmp/.*"

docker run -d \
  --name tika \
  --restart=always \
  -p 9998:9998 \
  apache/tika:latest
EOT

chmod +x "$SCRIPT"
"$SCRIPT"

echo "Paperless Tika/Gotenberg konfigurieren"
grep -q PAPERLESS_TIKA_ENABLED "$CONF" || cat <<EOT >> "$CONF"
PAPERLESS_TIKA_ENABLED=true
PAPERLESS_TIKA_ENDPOINT=http://localhost:9998
PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://localhost:3000
EOT

echo "Samba installieren & konfigurieren"
apt install -y samba

id scan &>/dev/null || adduser --disabled-password --gecos "" scan
echo "scan:$SCAN_PW" | chpasswd
echo -e "$SCAN_PW\n$SCAN_PW" | smbpasswd -a scan

cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

grep -q "\[consume\]" /etc/samba/smb.conf || cat <<'EOT' >> /etc/samba/smb.conf

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

mkdir -p /opt/paperless_data/consume
chown -R scan:scan /opt/paperless_data/consume
chmod -R 775 /opt/paperless_data/consume

systemctl restart smbd
systemctl enable smbd

echo
echo "========================================"
echo "Post-Install abgeschlossen"
echo "Samba User: scan"
echo "Samba Passwort: $SCAN_PW"
echo "========================================"
}

post_install_paperless
