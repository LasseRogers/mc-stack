#!/usr/bin/env bash
# Restore the world from a backup (local or Google Drive).
# Usage: bash restore.sh
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run as root."
  exit 1
fi

cd "$(dirname "$0")"

REMOTE="offsite"
REMOTE_DIR="minecraft-backups"
DC=(sudo docker compose)

step() { echo; echo "==> $*"; }

# ------------------------------------------------------------- list backups

local_files=()
for f in backups/world-*.tar.gz; do
  [ -f "$f" ] && local_files+=("$(basename "$f")")
done

remote_files=()
if grep -qs "^\[${REMOTE}\]" config/rclone/rclone.conf; then
  mapfile -t remote_files < <("${DC[@]}" run --rm --no-deps -T backup-sync \
    rclone lsf "${REMOTE}:${REMOTE_DIR}" --include "world-*.tar.gz" 2>/dev/null || true)
fi

mapfile -t all < <(printf '%s\n' "${local_files[@]}" "${remote_files[@]}" | grep . | sort -ru)

if [ "${#all[@]}" -eq 0 ]; then
  echo "No backups found."
  exit 1
fi

where() {
  local l=0 r=0
  printf '%s\n' "${local_files[@]}" | grep -qx "$1" && l=1
  printf '%s\n' "${remote_files[@]}" | grep -qx "$1" && r=1
  if [ $l -eq 1 ] && [ $r -eq 1 ]; then echo "local + drive"
  elif [ $l -eq 1 ]; then echo "local"
  else echo "drive"; fi
}

echo "Backups (newest first):"
for i in "${!all[@]}"; do
  printf '  %2d) %s  [%s]\n' "$((i + 1))" "${all[$i]}" "$(where "${all[$i]}")"
done

echo
read -rp "Restore which backup? (number, Enter to cancel): " n
[ -z "$n" ] && { echo "cancelled"; exit 0; }
if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "${#all[@]}" ]; then
  echo "invalid choice"
  exit 1
fi
file="${all[$((n - 1))]}"

echo
echo "This replaces the current world with ${file}."
echo "Progress since then is lost (a backup of the current world is made first)."
read -rp "Continue? [y/N] " a
case "$a" in [Yy]*) ;; *) echo "cancelled"; exit 0 ;; esac

# ------------------------------------------------------------------ restore

step "[1/4] Backing up the current world"
newest_local() {
  local f newest=""
  for f in backups/world-*.tar.gz; do [ -f "$f" ] && newest="$f"; done
  echo "$newest"
}
before="$(newest_local)"
if "${DC[@]}" exec -T backups backup now; then
  after="$(newest_local)"
  if [ -n "$after" ] && [ "$after" != "$before" ]; then
    safety="$(basename "$after")"
    echo "saved as ${safety}"
  fi
fi
if [ -z "${safety:-}" ]; then
  read -rp "Could not back up the current world. Continue anyway? [y/N] " a
  case "$a" in [Yy]*) ;; *) echo "cancelled"; exit 1 ;; esac
fi

step "[2/4] Getting ${file}"
if [ -f "backups/${file}" ]; then
  echo "found locally"
else
  "${DC[@]}" run --rm --no-deps -T -v "$PWD/backups:/restore" backup-sync \
    rclone copy "${REMOTE}:${REMOTE_DIR}/${file}" /restore
  echo "downloaded from Google Drive"
fi

step "[3/4] Replacing the world"
"${DC[@]}" stop mc backups
# Single quotes on purpose: this script runs inside the container.
# shellcheck disable=SC2016
"${DC[@]}" run --rm --no-deps -T -v "$PWD/backups:/restore:ro" --entrypoint sh mc -c '
  set -e
  L="$(sed -n "s/^level-name=//p" /data/server.properties 2>/dev/null)"
  L="${L:-world}"
  rm -rf "/data/$L" "/data/${L}_nether" "/data/${L}_the_end"
  tar -xzf "/restore/$1" -C /data
  chown -R 1000:1000 /data
' sh "$file"

step "[4/4] Starting"
"${DC[@]}" up -d

echo
echo "Restored ${file}. The server takes a minute or two to come up."
if [ -n "${safety:-}" ]; then
  echo "To undo, run restore.sh again and pick ${safety}."
fi
