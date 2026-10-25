#!/usr/bin/env bats

load test_helper

setup() {
  use_stubs
  export PATH="$REPO/services/backup-sync:$PATH"
  export TMPDIR="$BATS_TEST_TMPDIR"
  export SYNC_SRC="$BATS_TEST_TMPDIR/backups"
  export SYNC_DEST="offsite:mc"
  export STUB_RCLONE_REMOTE="offsite"
  export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/test"
  mkdir -p "$SYNC_SRC"
  SYNC="$REPO/services/backup-sync/sync.sh"
}

backup_aged() {
  touch -d "$2" "$SYNC_SRC/$1"
}

@test "uploads and prunes when backups are fresh" {
  backup_aged world-20261025-120000.tar.gz "1 hour ago"
  run sh "$SYNC"
  [ "$status" -eq 0 ]
  called "rclone copy $SYNC_SRC offsite:mc --exclude .* --min-age 5m"
  called "rclone delete offsite:mc --min-age 30d"
  not_called "curl"
}

@test "alerts and skips upload when there are no backups" {
  run sh "$SYNC"
  [ "$status" -eq 0 ]
  grep -q "no local backups found" "$STUB_LOG.body"
  not_called "rclone copy"
}

@test "alerts when the newest backup is too old, but still uploads" {
  backup_aged world-20261020-120000.tar.gz "30 hours ago"
  run sh "$SYNC"
  [ "$status" -eq 0 ]
  grep -q "no new local backup in 24h (newest: world-20261020-120000.tar.gz)" "$STUB_LOG.body"
  called "rclone copy"
}

@test "looks at the newest backup, not the oldest" {
  backup_aged world-20261020-120000.tar.gz "30 hours ago"
  backup_aged world-20261025-120000.tar.gz "1 hour ago"
  run sh "$SYNC"
  [ "$status" -eq 0 ]
  not_called "curl"
}

@test "alerts and stops when the remote is not configured" {
  export STUB_RCLONE_REMOTE=""
  backup_aged world-20261025-120000.tar.gz "1 hour ago"
  run sh "$SYNC"
  [ "$status" -eq 1 ]
  grep -q "remote 'offsite' not configured" "$STUB_LOG.body"
  not_called "rclone copy"
}

@test "alerts when the upload fails, and does not prune" {
  export STUB_RCLONE_FAIL="copy"
  backup_aged world-20261025-120000.tar.gz "1 hour ago"
  run sh "$SYNC"
  [ "$status" -eq 1 ]
  grep -q "upload to offsite:mc failed" "$STUB_LOG.body"
  not_called "rclone delete"
}

@test "alerts when pruning fails" {
  export STUB_RCLONE_FAIL="delete"
  backup_aged world-20261025-120000.tar.gz "1 hour ago"
  run sh "$SYNC"
  [ "$status" -eq 1 ]
  grep -q "pruning offsite:mc failed" "$STUB_LOG.body"
}

@test "keeps everything when REMOTE_KEEP_DAYS is 0" {
  export REMOTE_KEEP_DAYS=0
  backup_aged world-20261025-120000.tar.gz "1 hour ago"
  run sh "$SYNC"
  [ "$status" -eq 0 ]
  not_called "rclone delete"
}

@test "works without a webhook" {
  export DISCORD_WEBHOOK_URL=""
  run sh "$SYNC"
  [ "$status" -eq 0 ]
  not_called "curl"
}
