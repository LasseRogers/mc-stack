#!/usr/bin/env bats

load test_helper

setup() {
  use_stubs
  ALERT="$REPO/services/backup-sync/alert.sh"
  export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/test"
}

content() {
  python3 -c 'import json, sys; print(json.loads(sys.stdin.readline())["content"])' \
    < "$STUB_LOG.body"
}

@test "does nothing without a webhook" {
  DISCORD_WEBHOOK_URL="" run sh "$ALERT" "hello"
  [ "$status" -eq 0 ]
  not_called "curl"
}

@test "posts the message to the webhook" {
  run sh "$ALERT" "hello"
  [ "$status" -eq 0 ]
  called "curl"
  called "$DISCORD_WEBHOOK_URL"
  [ "$(content)" = "mc-stack: hello" ]
}

@test "escapes quotes and backslashes" {
  run sh "$ALERT" 'say "hi" \ ok'
  [ "$status" -eq 0 ]
  [ "$(content)" = 'mc-stack: say "hi" \ ok' ]
}

@test "drops control characters" {
  run sh "$ALERT" "$(printf 'line1\nline2\ttab')"
  [ "$status" -eq 0 ]
  [ "$(content)" = "mc-stack: line1line2tab" ]
}

@test "fails when the webhook can't be reached" {
  DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/fail" run sh "$ALERT" "hello"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to send alert"* ]]
}
