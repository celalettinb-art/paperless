#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://docs.paperless-ngx.com/
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/celalettinb-art/paperless/refs/heads/main/paperless-ngx-with-tika-and-gotenberg.sh)"

APP="Paperless-ngx"
var_tags="${var_tags:-document;management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/paperless ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Check for old data structure and prompt migration (exclude symlinks)
  if [[ -f /opt/paperless/paperless.conf ]]; then
    local OLD_DIRS=()
    [[ -d /opt/paperless/consume && ! -L /opt/paperless/consume ]] && OLD_DIRS+=("consume")
    [[ -d /opt/paperless/data && ! -L /opt/paperless/data ]] && OLD_DIRS+=("data")
    [[ -d /opt/paperless/media && ! -L /opt/paperless/media ]] && OLD_DIRS+=("media")

    if [[ ${#OLD_DIRS[@]} -gt 0 ]]; then
      msg_error "Old data structure detected in /opt/paperless/"
      msg_custom "📂" "Found directories: ${OLD_DIRS[*]}"
      echo -e ""
      msg_custom "🔄" "Migration required to new data structure (/opt/paperless_data/)"
      msg_custom "📖" "Please follow the migration guide:"
      echo -e "${TAB}${GATEWAY}${BGN}https://github.com/community-scripts/ProxmoxVE/discussions/9223${CL}"
      echo -e ""
      msg_custom "⚠️" "Update aborted. Please migrate your data first."
      exit 1
    fi
  fi

  if check_for_gh_release "paperless" "paperless-ngx/paperless-ngx"; then
    msg_info "Stopping all Paperless-ngx Services"
    systemctl stop paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue
    msg_ok "Stopped all Paperless-ngx Services"

    if grep -q "uv run" /etc/systemd/system/paperless-webserver.service; then

      msg_info "Backing up configuration"
      local BACKUP_DIR="/opt/paperless_backup_$$"
      mkdir -p "$BACKUP_DIR"
      [[ -f /opt/paperless/paperless.conf ]] && cp /opt/paperless/paperless.conf "$BACKUP_DIR/"
      msg_ok "Backup completed to $BACKUP_DIR"

      PYTHON_VERSION="3.13" setup_uv
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "paperless" "paperless-ngx/paperless-ngx" "prebuild" "latest" "/opt/paperless" "paperless*tar.xz"
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jbig2enc" "ie13/jbig2enc" "tarball" "latest" "/opt/jbig2enc"

      . /etc/os-release
      if [ "$VERSION_CODENAME" = "bookworm" ]; then
        setup_gs
      else
        $STD apt install -y ghostscript
      fi

      msg_info "Updating Paperless-ngx"
      cp -r "$BACKUP_DIR"/* /opt/paperless/
      cd /opt/paperless
      $STD uv sync --all-extras
      cd /opt/paperless/src
      $STD uv run -- python manage.py migrate
      msg_ok "Updated Paperless-ngx"

      rm -rf "$BACKUP_DIR"

    else
      msg_warn "You are about to migrate your Paperless-ngx installation to uv!"
      msg_custom "🔒" "It is strongly recommended to take a Proxmox snapshot first:"
      echo -e "   1. Stop the container:  pct stop <CTID>"
      echo -e "   2. Create a snapshot:  pct snapshot <CTID> pre-paperless-uv-migration"
      echo -e "   3. Start the container again\n"

      read -rp "Have you created a snapshot? [y/N]: " confirm
      if [[ ! "$confirm" =~ ^([yY]|[yY][eE][sS])$ ]]; then
        msg_error "Migration aborted. Please create a snapshot first."
        exit
      fi
      msg_info "Migrating old Paperless-ngx installation to uv"
      rm -rf /opt/paperless/venv
      find /opt/paperless -name "__pycache__" -type d -exec rm -rf {} +

      msg_info "Backing up configuration"
      local BACKUP_DIR="/opt/paperless_backup_$$"
      mkdir -p "$BACKUP_DIR"
      [[ -f /opt/paperless/paperless.conf ]] && cp /opt/paperless/paperless.conf "$BACKUP_DIR/"
      msg_ok "Backup completed to $BACKUP_DIR"

      declare -A PATCHES=(
        ["paperless-consumer.service"]="ExecStart=uv run -- python manage.py document_consumer"
        ["paperless-scheduler.service"]="ExecStart=uv run -- celery --app paperless beat --loglevel INFO"
        ["paperless-task-queue.service"]="ExecStart=uv run -- celery --app paperless worker --loglevel INFO"
        ["paperless-webserver.service"]="ExecStart=uv run -- granian --interface asgi --ws \"paperless.asgi:application\""
      )

      for svc in "${!PATCHES[@]}"; do
        path=$(systemctl show -p FragmentPath "$svc" | cut -d= -f2)
        if [[ -n "$path" && -f "$path" ]]; then
          sed -i "s|^ExecStart=.*|${PATCHES[$svc]}|" "$path"
          if [[ "$svc" == "paperless-webserver.service" ]]; then
            grep -q "^Environment=GRANIAN_HOST=" "$path" ||
              sed -i '/^\[Service\]/a Environment=GRANIAN_HOST=::' "$path"
            grep -q "^Environment=GRANIAN_PORT=" "$path" ||
              sed -i '/^\[Service\]/a Environment=GRANIAN_PORT=8000' "$path"
            grep -q "^Environment=GRANIAN_WORKERS=" "$path" ||
              sed -i '/^\[Service\]/a Environment=GRANIAN_WORKERS=1' "$path"
          fi
          msg_ok "Patched $svc"
        else
          msg_error "Service file for $svc not found!"
        fi
      done

      $STD systemctl daemon-reload
      msg_info "Backing up configuration"
      BACKUP_DIR="/opt/paperless_backup_$$"
      mkdir -p "$BACKUP_DIR"
      [[ -f /opt/paperless/paperless.conf ]] && cp /opt/paperless/paperless.conf "$BACKUP_DIR/"
      msg_ok "Backup completed to $BACKUP_DIR"

      PYTHON_VERSION="3.13" setup_uv
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "paperless" "paperless-ngx/paperless-ngx" "prebuild" "latest" "/opt/paperless" "paperless*tar.xz"
      CLEAN_INSTALL=1 fetch_and_deploy_gh_release "jbig2enc" "ie13/jbig2enc" "tarball" "latest" "/opt/jbig2enc"

      . /etc/os-release
      if [ "$VERSION_CODENAME" = "bookworm" ]; then
        setup_gs
      else
        msg_info "Installing Ghostscript"
        $STD apt install -y ghostscript
        msg_ok "Installed Ghostscript"
      fi

      msg_info "Updating Paperless-ngx"
      cp -r "$BACKUP_DIR"/* /opt/paperless/
      cd /opt/paperless
      $STD uv sync --all-extras
      cd /opt/paperless/src
      $STD uv run -- python manage.py migrate
      msg_ok "Paperless-ngx migration and update completed"

      rm -rf "$BACKUP_DIR"
      if [[ -d /opt/paperless/backup ]]; then
        rm -rf /opt/paperless/backup
        msg_ok "Removed old backup directory"
      fi
    fi

    msg_info "Starting all Paperless-ngx Services"
    systemctl start paperless-consumer paperless-webserver paperless-scheduler paperless-task-queue
    sleep 1
    msg_ok "Started all Paperless-ngx Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

function post_install_paperless() {
  msg_info "Running Paperless post-install configuration"

  pct exec "$CTID" -- bash <<'EOF'
set -e

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

  msg_ok "Paperless Post-Install Configuration completed"
}


start
build_container
post_install_paperless
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"

