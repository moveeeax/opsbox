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

@test "create_archive removes a partial archive when tar fails" {
  mkdir -p "$TMP/src" "$TMP/out"
  echo hello > "$TMP/src/file.txt"
  # No write permission on the destination: tar's open() fails immediately.
  # Skip under root, which ignores permission bits.
  if [ "$(id -u)" -eq 0 ]; then
    skip "cannot deny write access while running as root"
  fi
  chmod 500 "$TMP/out"
  run create_archive "$TMP/src" "$TMP/out"
  chmod 700 "$TMP/out"
  [ "$status" -ne 0 ]
  count="$(find "$TMP/out" -type f | wc -l)"
  [ "$count" -eq 0 ]
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

@test "rotate_archives reads a leading-zero keep as decimal, not octal" {
  mkdir -p "$TMP/out"
  # Ten archives, oldest first. "08" is not a valid octal literal, so an
  # arithmetic context that does not force base 10 aborts the rotation loop
  # and leaves every archive in place while still exiting 0.
  for i in 01 02 03 04 05 06 07 08 09 10; do
    f="$TMP/out/data-202101${i}-000000.tar.gz"
    echo x > "$f"
    touch -d "2021-01-${i} 00:00:00" "$f"
  done
  rotate_archives "$TMP/out" "data" 08
  count="$(find "$TMP/out" -name 'data-*.tar.gz' | wc -l)"
  [ "$count" -eq 8 ]
  # The two oldest are the ones that go.
  [ ! -f "$TMP/out/data-20210101-000000.tar.gz" ]
  [ ! -f "$TMP/out/data-20210102-000000.tar.gz" ]
  [ -f "$TMP/out/data-20210110-000000.tar.gz" ]
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
