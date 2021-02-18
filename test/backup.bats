#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  # Source the script's functions without running main.
  source "${REPO_ROOT}/bin/backup"
}

teardown() {
  teardown_tmp
}

@test "archive_name embeds basename and .tar.gz suffix" {
  run archive_name "etc"
  [ "$status" -eq 0 ]
  [[ "$output" == etc-*.tar.gz ]]
}

@test "create_archive produces a readable gzip tar" {
  mkdir -p "$TMP/src"
  echo hello > "$TMP/src/file.txt"
  out="$(create_archive "$TMP/src" "$TMP/out")"
  [ -f "$out" ]
  # Archive lists the file under the source basename.
  tar -tzf "$out" | grep -q "src/file.txt"
}

@test "create_archive fails on missing source" {
  run create_archive "$TMP/does-not-exist" "$TMP/out"
  [ "$status" -ne 0 ]
}

@test "rotate_archives keeps only the N newest" {
  mkdir -p "$TMP/out"
  # Create six archives with increasing mtimes.
  for i in 1 2 3 4 5 6; do
    f="$TMP/out/data-2021010${i}-000000.tar.gz"
    echo x > "$f"
    touch -d "2021-01-0${i} 00:00:00" "$f"
  done
  rotate_archives "$TMP/out" "data" 2
  count="$(find "$TMP/out" -name 'data-*.tar.gz' | wc -l)"
  [ "$count" -eq 2 ]
  # The two newest (05, 06) survive.
  [ -f "$TMP/out/data-20210105-000000.tar.gz" ]
  [ -f "$TMP/out/data-20210106-000000.tar.gz" ]
  [ ! -f "$TMP/out/data-20210101-000000.tar.gz" ]
}

@test "main creates an archive end to end" {
  mkdir -p "$TMP/src"
  echo data > "$TMP/src/a"
  run main --dest "$TMP/out" --keep 3 "$TMP/src"
  [ "$status" -eq 0 ]
  count="$(find "$TMP/out" -name 'src-*.tar.gz' | wc -l)"
  [ "$count" -eq 1 ]
}

@test "main rejects a non-numeric keep value" {
  mkdir -p "$TMP/src"
  run main --dest "$TMP/out" --keep abc "$TMP/src"
  [ "$status" -ne 0 ]
}
