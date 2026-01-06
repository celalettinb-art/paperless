#!/usr/bin/env bash
# WARNING! Read the script before executing! All at your own risk!
# Install Paperless NGX from here https://community-scripts.github.io/ProxmoxVE/scripts?id=paperless-ngx
# Then run the script -> bash -c "$(curl -fsSL https://raw.githubusercontent.com/celalettinb-art/paperless/refs/heads/main/paperless-ngx-and-tika-and-gotenberg-in-docker.sh)"
# Everything the script does is listed in headings in Script.
set -e
check_exit() {
    if [ $1 -eq 0 ]; then
        echo -e "\e[32m✅ $2 successful\e[0m"
    else
        echo -e "\e[31m❌ $2 failed\e[0m"
        exit 1
    fi
}
function post_install_paperless() {

### ===========================================
### Allow SSH root login (WARNING: insecure)
### ===========================================
echo -e "👉 " "\e[1;33mAllow SSH root login (WARNING: insecure)\e[0m"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart sshd

check_exit $? "Allow SSH root login"

### ===========================================
### Generate random password
### ===========================================
echo -e "👉 " "\e[1;33mGenerate random password\e[0m"
SCAN_PW=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
echo "$SCAN_PW" > /root/scan.creds
chmod 600 /root/scan.creds

check_exit $? "Generate random password"

### ===========================================
### Install OCR languages
### ===========================================
echo -e "\e[1;33mInstall OCR languages\e[0m"
apt update
apt install -y tesseract-ocr-deu tesseract-ocr-eng tesseract-ocr-tur

check_exit $? "Install OCR languages"

### ===========================================
### Customize paperless configuration
### ===========================================
echo -e "👉 " "\e[1;33mEdit Paperless configuration\e[0m"
CONF="/opt/paperless/paperless.conf"
mkdir -p "$(dirname "$CONF")"
touch "$CONF"

grep -q PAPERLESS_OCR_LANGUAGE "$CONF" || cat <<EOT >> "$CONF"
PAPERLESS_OCR_LANGUAGE=deu
PAPERLESS_OCR_LANGUAGES=eng tur
PAPERLESS_TIME_ZONE=Europe/Berlin
EOT

check_exit $? "Customize paperless configuration"

### ===========================================
### Install Docker
### ===========================================
echo -e "👉 " "\e[1;33mInstall Docker\e[0m"
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

check_exit $? "Install Docker"

### ===========================================
### Customize start script for Gotenberg & Tika
### ===========================================
echo -e "👉 " "\e[1;33mCustomize start script for Gotenberg & Tika\e[0m"
SCRIPT="/opt/paperless/scripts/start_services.sh"
mkdir -p "$(dirname "$SCRIPT")"

[ -f "$SCRIPT" ] && cp "$SCRIPT" "${SCRIPT}.bak"

cat <<'EOT' > "$SCRIPT"

check_exit $? "Customize start script for Gotenberg & Tika"

### ===========================================
### Create Gotenberg & Tike containers
### ===========================================
echo -e "👉 " "\e[1;33mCreate Gotenberg & Tike containers\e[0m"
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

check_exit $? "Create Gotenberg & Tike containers"

### ===========================================
### Configure Tika & Gotenberg in Paperless
### ===========================================
echo -e "👉 " "\e[1;33mConfigure Tika & Gotenberg in Paperless\e[0m"
grep -q PAPERLESS_TIKA_ENABLED "$CONF" || cat <<EOT >> "$CONF"
PAPERLESS_TIKA_ENABLED=true
PAPERLESS_TIKA_ENDPOINT=http://localhost:9998
PAPERLESS_TIKA_GOTENBERG_ENDPOINT=http://localhost:3000
EOT

check_exit $? "Configure Tika & Gotenberg in Paperless"

### ===========================================
### Install & configure Samba and create scan User
### ===========================================
echo -e "👉 " "\e[1;33mInstall & configure Samba and create scan User\e[0m"
apt install -y samba

id scan &>/dev/null || adduser --disabled-password --gecos "" scan
echo "scan:$SCAN_PW" | chpasswd
echo -e "$SCAN_PW\n$SCAN_PW" | smbpasswd -a scan

cp /etc/samba/smb.conf /etc/samba/smb.conf.bak

check_exit $? "Install & configure Samba and create scan User"

### ===========================================
### Disable [homes] and add [consume]
### ===========================================
echo -e "👉 " "\e[1;33mDisable [homes] and add [consume]\e[0m"
sed -i '/^\[homes\]/a \   available = no' /etc/samba/smb.conf
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


check_exit $? "Disable [homes] and add [consume]"

echo
echo -e "\e[1;32m========================================\e[0m"
echo -e "👍 " "\e[1;32mPost-installation complete\e[0m"
echo -e "🧾 " "\e[1;32mSamba User: scan\e[0m"
echo -e "🧾 " "\e[1;32mSamba Password: $SCAN_PW\e[0m"
echo -e "🧾 " "\e[1;32mYou can read the password for scan here afterwards: cat ~/scan.creds\e[0m"
echo -e "⚠️ " "\e[1;32mPlease be sure to change it! (smbpasswd -a scan)\e[0m"
echo -e "\e[1;32m========================================\e[0m"
}

post_install_paperless
