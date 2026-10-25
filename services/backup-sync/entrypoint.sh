#!/bin/sh
set -eu

# Arguments run a one-off command instead of the scheduler.
if [ "$#" -gt 0 ]; then
  exec "$@"
fi

SYNC_SCHEDULE="${SYNC_SCHEDULE:-0 3 * * *}"
echo "${SYNC_SCHEDULE} /usr/local/bin/sync.sh" > /tmp/crontab

echo "[backup-sync] Schedule: ${SYNC_SCHEDULE} (TZ=${TZ:-UTC}) -> ${SYNC_DEST:-<not set>}"

if [ "${SYNC_ON_START:-true}" = "true" ]; then
  /usr/local/bin/sync.sh || true
fi

exec supercronic -passthrough-logs /tmp/crontab
