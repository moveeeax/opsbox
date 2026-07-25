#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/bin/prune-old"
  # Layout: one recent file, two old files (one matching a pattern).
  touch "$TMP/recent.log"
  touch -d "40 days ago" "$TMP/old.log"
  touch -d "40 days ago" "$TMP/old.txt"
}

teardown() {
  teardown_tmp
}

@test "find_old_files matches only files older than threshold" {
  run find_old_files "$TMP" 30 '*'
  [ "$status" -eq 0 ]
  [[ "$output" == *"old.log"* ]]
  [[ "$output" == *"old.txt"* ]]
  [[ "$output" != *"recent.log"* ]]
}

@test "find_old_files honours the pattern" {
  run find_old_files "$TMP" 30 '*.log'
  [[ "$output" == *"old.log"* ]]
  [[ "$output" != *"old.txt"* ]]
}

@test "dry-run reports but does not delete" {
  run prune_old "$TMP" 30 '*' 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove"* ]]
  [ -f "$TMP/old.log" ]
  [ -f "$TMP/old.txt" ]
}

@test "apply deletes old files but keeps recent" {
  run prune_old "$TMP" 30 '*' 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed"* ]]
  [ ! -f "$TMP/old.log" ]
  [ ! -f "$TMP/old.txt" ]
  [ -f "$TMP/recent.log" ]
}

@test "prune_old surfaces a failed scan instead of reporting zero matches" {
  # find cannot read this path at all, so "0 files matched" would be a lie.
  run prune_old "$TMP/definitely-missing" 30 '*' 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"results are incomplete"* ]]
}

@test "main defaults to dry-run" {
  run main --days 30 "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [ -f "$TMP/old.log" ]
}

@test "main --apply with pattern deletes only matches" {
  run main --days 30 --pattern '*.log' --apply "$TMP"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/old.log" ]
  [ -f "$TMP/old.txt" ]
}

@test "main rejects a missing directory" {
  run main --days 30 "$TMP/nope"
  [ "$status" -ne 0 ]
}

@test "main rejects a non-numeric days value" {
  run main --days xx "$TMP"
  [ "$status" -ne 0 ]
}
