# mc-stack

Minecraft server for Raspberry Pi 5 running in Docker.

- `mc`: Minecraft server (port 25565)
- `backups`: local backups every 6h, kept 7 days
- `panel`: web admin panel (port 8080)
- `backup-sync`: nightly upload to Google Drive, kept 30 days, optional Discord alerts on failure

## Install

Requires Raspberry Pi OS Lite (64-bit) with SSH enabled.

```
sudo apt install -y git
git clone https://github.com/LasseRogers/mc-stack.git
cd mc-stack
bash setup-pi.sh
```

`setup-pi.sh` enables automatic security updates and a firewall (SSH only),
installs Docker and log2ram, creates `.env`, asks for the Minecraft version,
connects Google Drive, sets up optional Discord alerts, optionally restores the
latest world backup, then starts the stack.

- Minecraft: `<hostname>.local`
- Panel: `http://<hostname>.local:8080`

When migrating, stop the old host first (`docker compose down`) to avoid
two hosts uploading to the same Drive folder.

## Remote access (optional)

```
bash setup-tailscale.sh
```

Joins the Pi to a Tailscale tailnet so the panel is reachable from other
networks without opening ports. The script also prints an access policy that
lets shared users join the Minecraft server without reaching the panel.

## Usage

| | |
|---|---|
| Status | `docker compose ps` |
| Logs | `docker compose logs <service> --tail 50` |
| Backup now | `docker compose exec backups backup now` |
| Upload now | `docker compose exec backup-sync sync.sh` |
| Restore a backup | `bash restore.sh` |
| Stop / start | `docker compose down` / `docker compose up -d` |
| Update | `git pull && docker compose pull && docker compose up -d --build` |

Backup intervals, retention and memory are set in `compose.yaml`. The
Minecraft version (`MC_VERSION`) and Discord webhook (`DISCORD_WEBHOOK_URL`)
are set in `.env`. Run `docker compose up -d` after changing either.

`docker compose pull` updates images but not Minecraft itself, which stays on
`MC_VERSION`. To upgrade, change `MC_VERSION` (worlds can't be downgraded, so
take a backup first).

`.env` and `config/rclone/` contain secrets and are git-ignored.

## Development

Requires Python 3, shellcheck and bats:

```
sudo apt install -y python3-venv shellcheck bats
python3 -m venv .venv
.venv/bin/pip install -r services/admin-panel/requirements-dev.txt
```

Run the checks:

```
.venv/bin/pytest services/admin-panel
shellcheck setup-pi.sh setup-tailscale.sh restore.sh services/backup-sync/*.sh
bats tests/
```

The same checks run on every push via GitHub Actions.
