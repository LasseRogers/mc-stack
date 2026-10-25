#!/usr/bin/env bats

load test_helper

setup() {
  use_stubs
  project_with restore.sh
  printf '[offsite]\ntype = drive\n' > config/rclone/rclone.conf
  touch backups/world-20261023-030000.tar.gz backups/world-20261024-030000.tar.gz
  export STUB_REMOTE_FILES="world-20261020-030000.tar.gz world-20261024-030000.tar.gz"
  export STUB_BACKUP_NOW="world-20261025-210000.tar.gz"
}

@test "lists local and Drive backups, newest first" {
  feed restore.sh ""
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" == *"1) world-20261024-030000.tar.gz  [local + drive]" ]]
  [[ "${lines[2]}" == *"2) world-20261023-030000.tar.gz  [local]" ]]
  [[ "${lines[3]}" == *"3) world-20261020-030000.tar.gz  [drive]" ]]
  [[ "$output" == *"cancelled"* ]]
  not_called "compose stop"
}

@test "rejects an invalid choice" {
  feed restore.sh 9
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid choice"* ]]
  not_called "compose stop"
}

@test "does nothing unless confirmed" {
  feed restore.sh 2 n
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelled"* ]]
  not_called "backup now"
}

@test "restores a local backup in the right order" {
  feed restore.sh 2 y
  [ "$status" -eq 0 ]
  [[ "$output" == *"saved as world-20261025-210000.tar.gz"* ]]
  [[ "$output" == *"found locally"* ]]
  [[ "$output" == *"pick world-20261025-210000.tar.gz"* ]]
  not_called "rclone copy"
  run grep -nE "backup now|compose stop mc backups|entrypoint sh mc|compose up -d" "$STUB_LOG"
  [[ "${lines[0]}" == *"backup now"* ]]
  [[ "${lines[1]}" == *"compose stop mc backups"* ]]
  [[ "${lines[2]}" == *"entrypoint sh mc"* ]]
  [[ "${lines[3]}" == *"compose up -d"* ]]
  called " sh world-20261023-030000.tar.gz"
}

@test "downloads a Drive-only backup first" {
  feed restore.sh 3 y
  [ "$status" -eq 0 ]
  [[ "$output" == *"downloaded from Google Drive"* ]]
  called "rclone copy offsite:minecraft-backups/world-20261020-030000.tar.gz /restore"
  [ -f backups/world-20261020-030000.tar.gz ]
}

@test "stops if the safety backup fails and the user declines" {
  export STUB_BACKUP_NOW=""
  feed restore.sh 2 y n
  [ "$status" -eq 1 ]
  [[ "$output" == *"cancelled"* ]]
  not_called "compose stop"
}

@test "lists only local backups without Google Drive" {
  rm config/rclone/rclone.conf
  feed restore.sh ""
  [ "$status" -eq 0 ]
  not_called " lsf "
  [[ "$output" != *"[drive]"* ]]
}

@test "reports when there are no backups" {
  rm backups/*
  export STUB_REMOTE_FILES=""
  feed restore.sh ""
  [ "$status" -eq 1 ]
  [[ "$output" == *"No backups found."* ]]
}
