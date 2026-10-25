# mc-stack

Minecraft server for Raspberry Pi 5 running in Docker.

- `mc`: Minecraft server (port 25565)
- `backups`: local backups every 6h, kept 7 days
- `panel`: web admin panel (port 8080)
- `backup-sync`: nightly upload to Google Drive, kept 30 days

## Install

Requires Raspberry Pi OS Lite (64-bit) with SSH enabled.

```
sudo apt install -y git
git clone https://github.com/<user>/mc-stack.git
cd mc-stack
bash setup-pi.sh
```

`setup-pi.sh` installs Docker and log2ram, creates `.env`, connects Google
Drive, optionally restores the latest world backup, then starts the stack.

- Minecraft: `<hostname>.local`
- Panel: `http://<hostname>.local:8080`

When migrating, stop the old host first (`docker compose down`) to avoid
two hosts uploading to the same Drive folder.

## Usage

| | |
|---|---|
| Status | `docker compose ps` |
| Logs | `docker compose logs <service> --tail 50` |
| Backup now | `docker compose exec backups backup now` |
| Upload now | `docker compose exec backup-sync sync.sh` |
| Stop / start | `docker compose down` / `docker compose up -d` |
| Update | `git pull && docker compose pull && docker compose up -d --build` |

Backup intervals, retention and memory are set in `compose.yaml`.

`.env` and `config/rclone/` contain secrets and are git-ignored.
