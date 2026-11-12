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

# write_fixture FILE LINE... - a hand-written snapshot with a header.
write_fixture() {
  local f="$1"
  shift
  {
    printf '# disk-report snapshot\n# taken\t2026-11-01T02:00:00+0000\n# depth\t2\n'
    printf '%s\n' "$@"
  } > "$f"
}

@test "human_bytes keeps the sign of a negative number" {
  run human_bytes -1536
  [ "$output" = "-1.5K" ]
}

@test "snapshot writes bytes<TAB>path lines under a header" {
  mkdir -p "$TMP/data/a/deep/deeper"
  head -c 4096 /dev/zero > "$TMP/data/a/file"
  run main --snapshot "$TMP/snap.tsv" --depth 1 "$TMP/data"
  [ "$status" -eq 0 ]
  grep -q $'^# depth\t1$' "$TMP/snap.tsv"
  grep -q $'^# root\t'"$TMP/data"'$' "$TMP/snap.tsv"
  grep -qE $'^[0-9]+\t'"$TMP/data/a"'$' "$TMP/snap.tsv"
  grep -qE $'^[0-9]+\t'"$TMP/data"'$' "$TMP/snap.tsv"
  # depth 1 stops above a/deep.
  ! grep -q "$TMP/data/a/deep" "$TMP/snap.tsv"
}

@test "snapshot leaves no temp file next to the destination" {
  mkdir -p "$TMP/data" "$TMP/snaps"
  run main --snapshot "$TMP/snaps/snap.tsv" "$TMP/data"
  [ "$status" -eq 0 ]
  [ "$(find "$TMP/snaps" -type f | wc -l)" -eq 1 ]
}

@test "snapshot_diff ranks by growth and marks new paths" {
  write_fixture "$TMP/old" $'100\t/a' $'1000\t/b' $'50\t/shrunk'
  write_fixture "$TMP/new" $'150\t/a' $'4000\t/b' $'10\t/shrunk' $'700\t/fresh'
  run snapshot_diff "$TMP/old" "$TMP/new" 10 1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'3000\t1000\t4000\t/b' ]
  [ "${lines[1]}" = $'700\t-\t700\t/fresh' ]
  [ "${lines[2]}" = $'50\t100\t150\t/a' ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "snapshot_diff honours top and min growth" {
  write_fixture "$TMP/old" $'100\t/a' $'1000\t/b'
  write_fixture "$TMP/new" $'150\t/a' $'4000\t/b' $'700\t/fresh'
  run snapshot_diff "$TMP/old" "$TMP/new" 1 1
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"/b" ]]
  run snapshot_diff "$TMP/old" "$TMP/new" 10 701
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"/b" ]]
}

@test "snapshot_diff handles sizes above 2^32" {
  write_fixture "$TMP/old" $'11811160064\t/var/lib/docker'
  write_fixture "$TMP/new" $'15246344192\t/var/lib/docker'
  run snapshot_diff "$TMP/old" "$TMP/new" 10 1
  [ "$output" = $'3435184128\t11811160064\t15246344192\t/var/lib/docker' ]
}

@test "format_growth prints was/now and new" {
  run format_growth <<< $'3435184128\t11811160064\t15246344192\t/var/lib/docker\n1073741824\t-\t1073741824\t/var/log/new'
  [ "${lines[0]}" = "+3.1G    /var/lib/docker (was 11.0G, now 14.1G)" ]
  [ "${lines[1]}" = "+1.0G    /var/log/new (new, now 1.0G)" ]
}

@test "since reports a directory that grew after the snapshot" {
  mkdir -p "$TMP/data/quiet" "$TMP/data/busy"
  run main --snapshot "$TMP/snap.tsv" "$TMP/data"
  [ "$status" -eq 0 ]
  head -c 1048576 /dev/zero > "$TMP/data/busy/blob"
  mkdir -p "$TMP/data/fresh"
  head -c 2048 /dev/zero > "$TMP/data/fresh/f"
  # No PATH: rescan the roots recorded in the snapshot.
  run main --since "$TMP/snap.tsv" --min-growth 1K
  [ "$status" -eq 0 ]
  [[ "$output" == *"+1.0M"*"$TMP/data/busy (was "* ]]
  [[ "$output" == *"$TMP/data/fresh (new, now"* ]]
  [[ "$output" != *"$TMP/data/quiet"* ]]
}

@test "since says so when nothing grew" {
  mkdir -p "$TMP/data"
  main --snapshot "$TMP/snap.tsv" "$TMP/data"
  run main --since "$TMP/snap.tsv" --min-growth 1M "$TMP/data"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing grew"* ]]
}

@test "since rejects a file that is not a snapshot" {
  echo "hello" > "$TMP/junk"
  run main --since "$TMP/junk" "$TMP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a disk-report snapshot"* ]]
}

@test "snapshot and since together are rejected" {
  run main --snapshot "$TMP/a" --since "$TMP/b" "$TMP"
  [ "$status" -ne 0 ]
}

@test "deleted_open_files lists only unlinked targets with their size" {
  mkdir -p "$TMP/data"
  # The fixture symlink must resolve for stat -L, so the target file is
  # literally named "... (deleted)", which is what the kernel shows.
  head -c 5000 /dev/zero > "$TMP/data/app.log (deleted)"
  echo live > "$TMP/data/live.log"
  fake_proc_pid 42 java
  fake_proc_fd 42 3 "$TMP/data/app.log (deleted)"
  fake_proc_fd 42 4 "$TMP/data/live.log"
  OPSBOX_PROC="$TMP/proc" run deleted_open_files
  [ "$status" -eq 0 ]
  [ "$output" = "5000"$'\t'"42"$'\t'"3"$'\t'"$TMP/data/app.log" ]
}

@test "main --deleted names the process holding the space" {
  mkdir -p "$TMP/data"
  head -c 5000 /dev/zero > "$TMP/data/app.log (deleted)"
  fake_proc_pid 42 java
  fake_proc_fd 42 3 "$TMP/data/app.log (deleted)"
  OPSBOX_PROC="$TMP/proc" run main --threshold 100 --deleted "$TMP/data"
  [[ "$output" == *"4.8K"*"pid=42 (java) fd=3 $TMP/data/app.log"* ]]
}
