#!/bin/sh
# Upload local backups and prune old remote copies.
set -eu

SRC="${SYNC_SRC:-/backups}"
DEST="${SYNC_DEST:?SYNC_DEST is not set}"
REMOTE="${DEST%%:*}"
KEEP_DAYS="${REMOTE_KEEP_DAYS:-30}"
MAX_AGE_HOURS="${MAX_BACKUP_AGE_HOURS:-24}"

log() { echo "[backup-sync] $(date '+%Y-%m-%d %H:%M:%S') $*"; }
fail() { log "$*"; alert.sh "$*" || true; exit 1; }

# Prevent overlapping runs.
exec 9>"${TMPDIR:-/tmp}/sync.lock"
if ! flock -n 9; then
  log "already running, skipping"
  exit 0
fi

# Alert when local backups have stopped (backups service down or failing).
# Names contain the timestamp, so the last match is the newest.
newest=""
for f in "$SRC"/world-*.tar.gz; do
  [ -f "$f" ] && newest="$f"
done
if [ -z "$newest" ]; then
  log "no local backups in ${SRC}"
  alert.sh "no local backups found in ${SRC}" || true
elif [ $(( $(date +%s) - $(stat -c %Y "$newest") )) -gt $(( MAX_AGE_HOURS * 3600 )) ]; then
  log "newest local backup is older than ${MAX_AGE_HOURS}h: $(basename "$newest")"
  alert.sh "no new local backup in ${MAX_AGE_HOURS}h (newest: $(basename "$newest"))" || true
fi

if ! rclone listremotes 2>/dev/null | grep -qx "${REMOTE}:"; then
  fail "remote '${REMOTE}' not configured (run setup-pi.sh)"
fi

# Never touch the remote when the source is empty.
if [ -z "$(ls -A "$SRC" 2>/dev/null)" ]; then
  log "${SRC} is empty, skipping"
  exit 0
fi

log "copy ${SRC} -> ${DEST}"
# copy, not sync: remote retention is handled separately below.
# --min-age skips archives that may still be in progress.
if ! rclone copy "$SRC" "$DEST" --exclude ".*" --min-age 5m --stats-one-line --stats 0 -v; then
  fail "upload to ${DEST} failed"
fi

if [ "$KEEP_DAYS" -gt 0 ]; then
  log "prune > ${KEEP_DAYS}d"
  if ! rclone delete "$DEST" --min-age "${KEEP_DAYS}d" -v; then
    fail "pruning ${DEST} failed"
  fi
fi

log "done"
