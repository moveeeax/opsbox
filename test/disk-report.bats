#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/bin/disk-report"
}

teardown() {
  teardown_tmp
}

@test "human_bytes formats bytes" {
  run human_bytes 512
  [ "$output" = "512.0B" ]
}

@test "human_bytes formats kilobytes" {
  run human_bytes 1536
  [ "$output" = "1.5K" ]
}

@test "human_bytes formats megabytes" {
  run human_bytes 3145728
  [ "$output" = "3.0M" ]
}

@test "over_threshold true when equal or greater" {
  run over_threshold 90 90
  [ "$status" -eq 0 ]
  run over_threshold 95 90
  [ "$status" -eq 0 ]
}

@test "over_threshold false when below" {
  run over_threshold 80 90
  [ "$status" -ne 0 ]
}

@test "du_bytes returns a positive number for a real dir" {
  echo "some content here" > "$TMP/file"
  run du_bytes "$TMP"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

@test "report_path warns and returns 2 over threshold" {
  # threshold 0 forces every filesystem to exceed it.
  run report_path "$TMP" 0
  [ "$status" -eq 2 ]
  [[ "$output" == *"threshold 0%"* ]]
}

@test "report_path returns 1 for missing path" {
  run report_path "$TMP/nope" 90
  [ "$status" -eq 1 ]
}

@test "main flags an over-threshold path via exit code" {
  run main --threshold 0 "$TMP"
  [ "$status" -eq 1 ]
}
