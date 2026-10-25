#!/usr/bin/env bash
# Provision a fresh Raspberry Pi OS (64-bit) host for mc-stack.
# Usage: bash setup-pi.sh   (idempotent, run as a regular user)
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run as root."
  exit 1
fi

cd "$(dirname "$0")"

RCLONE_IMAGE="rclone/rclone:latest"
REMOTE="offsite"
REMOTE_DIR="minecraft-backups"
VOLUME="mc-stack_mc-data"

step() { echo; echo "==> $*"; }
ask()  { local a; read -rp "$1 [Y/n] " a; case "${a:-y}" in [Yy]*) return 0 ;; *) return 1 ;; esac; }
rclone_run() {
  sudo docker run --rm "$@"
}

step "[1/10] System update"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
sudo apt-get install -y curl rsync openssl python3
sudo apt-get install -y unattended-upgrades
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' \
  | sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
echo "automatic security updates enabled"

step "[2/10] Docker"
if command -v docker >/dev/null 2>&1; then
  echo "already installed"
else
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "$USER"

step "[3/10] log2ram"
if systemctl list-unit-files log2ram.service 2>/dev/null | grep -q '^log2ram.service'; then
  echo "already installed"
else
  tmp="$(mktemp -d)"
  curl -fsSL https://github.com/azlux/log2ram/archive/master.tar.gz | tar xz -C "$tmp"
  (cd "$tmp/log2ram-master" && sudo ./install.sh)
  rm -rf "$tmp"
fi

step "[4/10] Firewall"
# Docker publishes container ports past ufw, so this covers host services
# (SSH etc.) only. Container ports are controlled in compose.yaml.
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment ssh
if ip link show tailscale0 >/dev/null 2>&1; then
  sudo ufw allow in on tailscale0 comment tailscale
fi
sudo ufw --force enable
sudo ufw status verbose

mkdir -p backups config/rclone

step "[5/10] .env"
if [ -f .env ]; then
  echo "exists, skipping"
else
  while true; do
    read -rsp "Panel password: " pw1; echo
    read -rsp "Repeat: " pw2; echo
    if [ -z "$pw1" ]; then echo "Empty password."
    elif [[ "$pw1" == *"'"* ]]; then echo "Single quotes are not allowed."
    elif [ "$pw1" != "$pw2" ]; then echo "Mismatch."
    else break; fi
  done
  umask 077
  cat > .env <<EOF
RCON_PASSWORD=$(openssl rand -hex 24)
ADMIN_PASSWORD='${pw1}'
PANEL_SECRET_KEY=$(openssl rand -hex 32)
EOF
  umask 022
  unset pw1 pw2
  echo "written (mode 600)"
fi

if ! grep -q '^SERVER_TZ=' .env; then
  tz="$(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || true)"
  echo "SERVER_TZ=${tz:-UTC}" >> .env
  echo "time zone: ${tz:-UTC}"
fi

step "[6/10] Minecraft version"
if grep -q '^MC_VERSION=' .env; then
  echo "pinned: $(grep '^MC_VERSION=' .env | cut -d= -f2)"
else
  manifest="$(curl -fsSL https://piston-meta.mojang.com/mc/game/version_manifest_v2.json)"
  mc_latest="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["latest"]["release"])' <<<"$manifest")"
  while true; do
    read -rp "Minecraft version [${mc_latest}] (or 'latest' to auto-update): " v
    v="${v:-$mc_latest}"
    if [ "${v,,}" = "latest" ]; then v=LATEST; break; fi
    if python3 -c '
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if any(x["id"] == sys.argv[1] and x["type"] == "release" for x in d["versions"]) else 1)
' "$v" <<<"$manifest"; then break; fi
    echo "unknown release: $v"
  done
  echo "MC_VERSION=${v}" >> .env
  echo "pinned: ${v}"
fi

step "[7/10] Google Drive"
if grep -qs "^\[${REMOTE}\]" config/rclone/rclone.conf; then
  echo "already configured"
elif ask "Configure now?"; then
  host="$(hostname).local"
  cat <<EOF

OAuth needs a browser. From a machine with one, open a tunnel:

  ssh -N -L 53682:127.0.0.1:53682 ${USER}@${host}

then open the link printed below in that machine's browser.

EOF
  read -rp "Press Enter once the tunnel is up... " _
  rclone_run -it --network host \
    --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$PWD/config/rclone:/config/rclone" \
    "$RCLONE_IMAGE" config create "$REMOTE" drive scope=drive.file
  echo "configured, tunnel can be closed"
else
  echo "skipped (re-run to configure)"
fi

step "[8/10] Backup alerts"
if grep -q '^DISCORD_WEBHOOK_URL=' .env; then
  if grep -q '^DISCORD_WEBHOOK_URL=.' .env; then
    echo "already configured"
  else
    echo "disabled (set DISCORD_WEBHOOK_URL in .env to enable)"
  fi
else
  while true; do
    read -rp "Discord webhook URL for backup alerts (Enter to skip): " hook
    [ -z "$hook" ] && break
    case "$hook" in
      https://discord.com/api/webhooks/*|https://discordapp.com/api/webhooks/*) ;;
      *) echo "not a Discord webhook URL"; continue ;;
    esac
    if curl -fsS --max-time 15 -H "Content-Type: application/json" \
         -d '{"content":"mc-stack: test alert from setup-pi.sh"}' "$hook" >/dev/null; then
      echo "test message sent"
      break
    fi
    echo "test message failed, check the URL"
  done
  echo "DISCORD_WEBHOOK_URL=${hook}" >> .env
  [ -n "$hook" ] && echo "enabled" || echo "skipped"
fi

step "[9/10] World data"
if sudo docker volume inspect "$VOLUME" >/dev/null 2>&1; then
  echo "volume exists, skipping"
elif grep -qs "^\[${REMOTE}\]" config/rclone/rclone.conf; then
  rclone_args=(-v "$PWD/config/rclone:/config/rclone" "$RCLONE_IMAGE")
  latest="$(rclone_run "${rclone_args[@]}" lsf "${REMOTE}:${REMOTE_DIR}" \
              --include "world-*.tar.gz" 2>/dev/null | sort | tail -n 1 || true)"
  if [ -n "$latest" ] && ask "Restore $latest?"; then
    rclone_run -v "$PWD/backups:/backups" "${rclone_args[@]}" \
      copy "${REMOTE}:${REMOTE_DIR}/${latest}" /backups
    sudo docker compose run --rm --no-deps -v "$PWD/backups:/restore:ro" \
      --entrypoint sh mc -c "tar -xzf /restore/${latest} -C /data && chown -R 1000:1000 /data"
    echo "restored ${latest}"
  else
    echo "no restore, new world"
  fi
else
  echo "no restore, new world"
fi

step "[10/10] Start"
sudo docker compose up -d --build

echo
echo "Minecraft: $(hostname).local"
echo "Panel:     http://$(hostname).local:8080"
echo
echo "Reboot required (log2ram, docker group)."
if ask "Reboot now?"; then
  sudo reboot
fi
