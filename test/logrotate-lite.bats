#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/bin/logrotate-lite"
}

teardown() {
  teardown_tmp
}

# Write a file of exactly N bytes.
make_file() {
  local path="$1" bytes="$2"
  head -c "$bytes" /dev/zero | tr '\0' 'x' > "$path"
}

@test "parse_size handles plain bytes" {
  run parse_size 2048
  [ "$output" -eq 2048 ]
}

@test "parse_size handles K/M/G suffixes" {
  run parse_size 1K
  [ "$output" -eq 1024 ]
  run parse_size 2M
  [ "$output" -eq 2097152 ]
  run parse_size 1G
  [ "$output" -eq 1073741824 ]
}

@test "parse_size rejects garbage" {
  run parse_size "big"
  [ "$status" -ne 0 ]
}

@test "file_size reports byte count" {
  make_file "$TMP/f" 123
  run file_size "$TMP/f"
  [ "$output" -eq 123 ]
}

@test "main rotates when over threshold and truncates original" {
  make_file "$TMP/app.log" 4096
  run main --size 1K --keep 3 "$TMP/app.log"
  [ "$status" -eq 0 ]
  [ -f "$TMP/app.log" ]
  [ "$(file_size "$TMP/app.log")" -eq 0 ]
  [ -f "$TMP/app.log.1" ]
  [ "$(file_size "$TMP/app.log.1")" -eq 4096 ]
}

@test "main skips rotation when under threshold" {
  make_file "$TMP/app.log" 100
  run main --size 1K "$TMP/app.log"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/app.log.1" ]
  [ "$(file_size "$TMP/app.log")" -eq 100 ]
}

@test "rotate_file shifts and caps at keep" {
  make_file "$TMP/app.log" 10
  echo one > "$TMP/app.log.1"
  echo two > "$TMP/app.log.2"
  echo three > "$TMP/app.log.3"
  rotate_file "$TMP/app.log" 3 0
  # keep=3 means .3 is the oldest allowed; the previous .3 is discarded.
  [ -f "$TMP/app.log.1" ]
  [ -f "$TMP/app.log.2" ]
  [ -f "$TMP/app.log.3" ]
  # The old .3 ("three") must be gone; .3 now holds the old .2 ("two").
  grep -q two "$TMP/app.log.3"
}

@test "gzip mode compresses the rotated copy" {
  make_file "$TMP/app.log" 2048
  run main --size 1K --keep 2 --gzip "$TMP/app.log"
  [ "$status" -eq 0 ]
  [ -f "$TMP/app.log.1.gz" ]
  [ ! -f "$TMP/app.log.1" ]
}

@test "force rotates a small file" {
  make_file "$TMP/app.log" 5
  run main --force "$TMP/app.log"
  [ "$status" -eq 0 ]
  [ -f "$TMP/app.log.1" ]
}
