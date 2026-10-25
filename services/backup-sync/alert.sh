#!/bin/sh
# Post a message to a Discord webhook. No-op if DISCORD_WEBHOOK_URL is unset.
# Usage: alert.sh "message"
set -eu

[ -n "${DISCORD_WEBHOOK_URL:-}" ] || exit 0

# Escape for JSON: backslashes, quotes, then drop control characters.
msg="$(printf '%s' "mc-stack: $*" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\000-\037')"

if ! curl -fsS --max-time 15 -H "Content-Type: application/json" \
     -d "{\"content\":\"${msg}\"}" "$DISCORD_WEBHOOK_URL" >/dev/null; then
  echo "[backup-sync] failed to send alert" >&2
  exit 1
fi
