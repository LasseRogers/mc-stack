#!/bin/sh
# Upload local backups and prune old remote copies.
set -eu

SRC=/backups
DEST="${SYNC_DEST:?SYNC_DEST is not set}"
REMOTE="${DEST%%:*}"
KEEP_DAYS="${REMOTE_KEEP_DAYS:-30}"

log() { echo "[backup-sync] $(date '+%Y-%m-%d %H:%M:%S') $*"; }

# Prevent overlapping runs.
exec 9>/tmp/sync.lock
if ! flock -n 9; then
  log "already running, skipping"
  exit 0
fi

if ! rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:"; then
  log "remote '${REMOTE}' not configured (run setup-pi.sh)"
  exit 1
fi

# Never touch the remote when the source is empty.
if [ -z "$(ls -A "$SRC" 2>/dev/null)" ]; then
  log "${SRC} is empty, skipping"
  exit 0
fi

log "copy ${SRC} -> ${DEST}"
# copy, not sync: remote retention is handled separately below.
# --min-age skips archives that may still be in progress.
rclone copy "$SRC" "$DEST" --exclude ".*" --min-age 5m --stats-one-line --stats 0 -v

if [ "$KEEP_DAYS" -gt 0 ]; then
  log "prune > ${KEEP_DAYS}d"
  rclone delete "$DEST" --min-age "${KEEP_DAYS}d" -v
fi

log "done"
