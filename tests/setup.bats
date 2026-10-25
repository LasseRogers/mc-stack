#!/usr/bin/env bats

load test_helper

setup() {
  use_stubs
  project_with setup-pi.sh
}

env_value() { grep "^$1=" .env | cut -d= -f2-; }

# Answers in order: password, repeat, Minecraft version, connect Drive,
# webhook, reboot. (A restore question appears only with Drive backups.)

@test "fresh setup writes .env with defaults" {
  feed setup-pi.sh pw pw "" n "" n
  [ "$status" -eq 0 ]
  [ "$(stat -c %a .env)" = "600" ]
  [[ "$(env_value RCON_PASSWORD)" =~ ^[0-9a-f]{48}$ ]]
  [[ "$(env_value PANEL_SECRET_KEY)" =~ ^[0-9a-f]{64}$ ]]
  [ "$(env_value ADMIN_PASSWORD)" = "'pw'" ]
  [ "$(env_value SERVER_TZ)" = "Europe/Copenhagen" ]
  [ "$(env_value MC_VERSION)" = "26.3" ]
  [ "$(env_value DISCORD_WEBHOOK_URL)" = "" ]
  called "compose up -d --build"
}

@test "asks again when the passwords don't match" {
  feed setup-pi.sh one two pw pw "" n "" n
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mismatch."* ]]
  [ "$(env_value ADMIN_PASSWORD)" = "'pw'" ]
}

@test "rejects single quotes in the password" {
  feed setup-pi.sh "it's" "it's" pw pw "" n "" n
  [ "$status" -eq 0 ]
  [[ "$output" == *"Single quotes are not allowed."* ]]
}

@test "accepts a specific Minecraft version and rejects unknown ones" {
  feed setup-pi.sh pw pw 1.21.99 26.4-pre1 1.21.4 n "" n
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown release: 1.21.99"* ]]
  [[ "$output" == *"unknown release: 26.4-pre1"* ]]
  [ "$(env_value MC_VERSION)" = "1.21.4" ]
}

@test "accepts latest for auto-updates" {
  feed setup-pi.sh pw pw Latest n "" n
  [ "$status" -eq 0 ]
  [ "$(env_value MC_VERSION)" = "LATEST" ]
}

@test "validates and tests the Discord webhook" {
  feed setup-pi.sh pw pw "" n \
    https://example.com/hook \
    https://discord.com/api/webhooks/fail \
    https://discord.com/api/webhooks/ok \
    n
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a Discord webhook URL"* ]]
  [[ "$output" == *"test message failed"* ]]
  [[ "$output" == *"test message sent"* ]]
  [ "$(env_value DISCORD_WEBHOOK_URL)" = "https://discord.com/api/webhooks/ok" ]
}

@test "firewall allows SSH before it is enabled" {
  feed setup-pi.sh pw pw "" n "" n
  [ "$status" -eq 0 ]
  allow=$(grep -n "ufw allow 22/tcp" "$STUB_LOG" | cut -d: -f1)
  enable=$(grep -n "ufw --force enable" "$STUB_LOG" | cut -d: -f1)
  [ -n "$allow" ] && [ -n "$enable" ] && [ "$allow" -lt "$enable" ]
}

@test "connects Drive and restores the latest backup" {
  export STUB_REMOTE_FILES="world-20261020-030000.tar.gz world-20261024-030000.tar.gz"
  feed setup-pi.sh pw pw "" y "" "" y n
  [ "$status" -eq 0 ]
  called "config create offsite drive scope=drive.file"
  [[ "$output" == *"restored world-20261024-030000.tar.gz"* ]]
  [ -f backups/world-20261024-030000.tar.gz ]
  called "entrypoint sh mc"
}

@test "leaves an existing world alone" {
  printf '[offsite]\ntype = drive\n' > config/rclone/rclone.conf
  export STUB_VOLUME_EXISTS=1 STUB_REMOTE_FILES="world-20261024-030000.tar.gz"
  feed setup-pi.sh pw pw "" "" n
  [ "$status" -eq 0 ]
  [[ "$output" == *"volume exists, skipping"* ]]
  not_called "entrypoint sh mc"
}

@test "second run keeps existing settings" {
  feed setup-pi.sh pw pw 1.21.4 n "" n
  cp .env first.env
  feed setup-pi.sh n n
  [ "$status" -eq 0 ]
  [[ "$output" == *"exists, skipping"* ]]
  [[ "$output" == *"pinned: 1.21.4"* ]]
  [[ "$output" == *"disabled (set DISCORD_WEBHOOK_URL"* ]]
  diff first.env .env
}
