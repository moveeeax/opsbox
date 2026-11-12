#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/bin/backup-verify"
  mkdir -p "$TMP/live/app/sub" "$TMP/scratch" "$TMP/bin"
  echo hello > "$TMP/live/app/a.txt"
  echo world > "$TMP/live/app/sub/b.txt"
  chmod 640 "$TMP/live/app/a.txt"
  # Same layout `backup` produces: the archive holds "app/...".
  tar -czf "$TMP/app.tar.gz" -C "$TMP/live" app
}

teardown() {
  teardown_tmp
}

# stub NAME BODY - put a fake NAME command first on PATH.
stub() {
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}

@test "format_ms renders seconds with milliseconds" {
  run format_ms 1234
  [ "$output" = "1.234" ]
  run format_ms 5
  [ "$output" = "0.005" ]
}

@test "is_within detects a path under another" {
  mkdir -p "$TMP/x/y"
  run is_within "$TMP/x/y" "$TMP/x"
  [ "$status" -eq 0 ]
  run is_within "$TMP/x" "$TMP/x"
  [ "$status" -eq 0 ]
  run is_within "$TMP/x" "$TMP/x/y"
  [ "$status" -ne 0 ]
  mkdir -p "$TMP/xy"
  run is_within "$TMP/xy" "$TMP/x"
  [ "$status" -ne 0 ]
}

@test "tar backup that matches the live tree passes" {
  run main --scratch "$TMP/scratch" --source "$TMP/live/app" "$TMP/app.tar.gz"
  [ "$status" -eq 0 ]
  [[ "$output" == *"restore: ok in "* ]]
  [[ "$output" == *"checked: 2 (all files)"* ]]
  [[ "$output" == *"match: 2"* ]]
  [[ "$output" == *"result: PASS"* ]]
}

@test "restore dir is removed afterwards unless --keep-scratch" {
  run main --scratch "$TMP/scratch" "$TMP/app.tar.gz"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$TMP/scratch")" ]
  run main --scratch "$TMP/scratch" --keep-scratch "$TMP/app.tar.gz"
  [ "$status" -eq 0 ]
  [ -f "$TMP"/scratch/backup-verify.*/app/a.txt ]
}

@test "restore never writes into the source tree" {
  before="$(find "$TMP/live" | sort)"
  run main --scratch "$TMP/scratch" --source "$TMP/live/app" "$TMP/app.tar.gz"
  [ "$status" -eq 0 ]
  [ "$(find "$TMP/live" | sort)" = "$before" ]
}

@test "a scratch dir inside the source is refused" {
  mkdir -p "$TMP/live/app/tmp"
  run main --scratch "$TMP/live/app/tmp" --source "$TMP/live/app" "$TMP/app.tar.gz"
  [ "$status" -ne 0 ]
  [[ "$output" == *"inside source"* ]]
}

@test "same mtime but different content is a mismatch" {
  touch -r "$TMP/live/app/a.txt" "$TMP/ref"
  echo HELLO > "$TMP/live/app/a.txt"
  touch -r "$TMP/ref" "$TMP/live/app/a.txt"
  run main --scratch "$TMP/scratch" --source "$TMP/live/app" "$TMP/app.tar.gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISMATCH (sha256): a.txt"* ]]
  [[ "$output" == *"result: FAIL"* ]]
}

@test "a mode change is a mismatch" {
  chmod 600 "$TMP/live/app/a.txt"
  run main --scratch "$TMP/scratch" --source "$TMP/live/app" "$TMP/app.tar.gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISMATCH (mode): a.txt"* ]]
}

@test "files edited or deleted after the backup are reported, not failed" {
  echo "new content" > "$TMP/live/app/a.txt"
  touch -d "+1 hour" "$TMP/live/app/a.txt"
  rm "$TMP/live/app/sub/b.txt"
  run main --scratch "$TMP/scratch" --source "$TMP/live/app" "$TMP/app.tar.gz"
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed since backup: 1"* ]]
  [[ "$output" == *"gone from live tree: 1"* ]]
}

@test "--sample checks only that many files" {
  for i in 1 2 3 4 5 6 7 8; do echo "$i" > "$TMP/live/app/f$i"; done
  tar -czf "$TMP/app.tar.gz" -C "$TMP/live" app
  run main --scratch "$TMP/scratch" --source "$TMP/live/app" --sample 3 "$TMP/app.tar.gz"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checked: 3 (random sample of 3)"* ]]
}

@test "a corrupt archive fails the restore" {
  head -c 100 "$TMP/app.tar.gz" > "$TMP/broken.tar.gz"
  run main --scratch "$TMP/scratch" "$TMP/broken.tar.gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"restore: FAILED"* ]]
  [[ "$output" == *"result: FAIL"* ]]
}

@test "--report writes the same report to a file" {
  run main --scratch "$TMP/scratch" --source "$TMP/live/app" --report "$TMP/out/report.txt" "$TMP/app.tar.gz"
  [ "$status" -eq 0 ]
  grep -q "result: PASS" "$TMP/out/report.txt"
}

@test "--report keeps the failing exit status" {
  head -c 100 "$TMP/app.tar.gz" > "$TMP/broken.tar.gz"
  run main --scratch "$TMP/scratch" --report "$TMP/report.txt" "$TMP/broken.tar.gz"
  [ "$status" -eq 1 ]
  grep -q "result: FAIL" "$TMP/report.txt"
}

@test "missing --root inside the restore is a failure with a hint" {
  run main --scratch "$TMP/scratch" --source "$TMP/live/app" --root nope "$TMP/app.tar.gz"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pass --root"* ]]
}

@test "restic driver restores SOURCE under its absolute path" {
  # Real restic recreates the snapshot's absolute paths under --target.
  stub restic 'while [ $# -gt 0 ]; do [ "$1" = --target ] && t="$2"; shift; done
src="'"$TMP/live/app"'"; mkdir -p "$t$src"; cp -a "$src/." "$t$src/"; echo "$t" > "'"$TMP"'/restic-target"'
  PATH="$TMP/bin:$PATH" run main --driver restic --scratch "$TMP/scratch" --source "$TMP/live/app" /srv/restic
  [ "$status" -eq 0 ]
  [[ "$output" == *"match: 2"* ]]
  [[ "$(cat "$TMP/restic-target")" == "$TMP/scratch/backup-verify."* ]]
}

@test "restic driver passes the repository and snapshot through" {
  stub restic 'printf "%s\n" "$@" > "'"$TMP"'/restic-args"'
  PATH="$TMP/bin:$PATH" run main --driver restic --scratch "$TMP/scratch" --snapshot abc123 /srv/restic
  [ "$status" -eq 0 ]
  [ "$(sed -n 1,4p "$TMP/restic-args" | tr '\n' ' ')" = "-r /srv/restic restore abc123 " ]
}

@test "borg driver extracts into the restore dir" {
  stub borg 'src="'"$TMP/live/app"'"; mkdir -p ".${src}"; cp -a "$src/." ".${src}/"'
  PATH="$TMP/bin:$PATH" run main --driver borg --scratch "$TMP/scratch" --source "$TMP/live/app" /srv/borg::nightly
  [ "$status" -eq 0 ]
  [[ "$output" == *"match: 2"* ]]
}

@test "pg_restore driver fails on an empty script" {
  stub pg_restore 'while [ $# -gt 0 ]; do [ "$1" = -f ] && out="$2"; shift; done; : > "$out"'
  touch "$TMP/db.dump"
  PATH="$TMP/bin:$PATH" run main --driver pg_restore --scratch "$TMP/scratch" "$TMP/db.dump"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty script"* ]]
}

@test "pg_restore driver passes with a non-empty script" {
  stub pg_restore 'while [ $# -gt 0 ]; do [ "$1" = -f ] && out="$2"; shift; done; echo "CREATE TABLE t ();" > "$out"'
  touch "$TMP/db.dump"
  PATH="$TMP/bin:$PATH" run main --driver pg_restore --scratch "$TMP/scratch" "$TMP/db.dump"
  [ "$status" -eq 0 ]
  [[ "$output" == *"restored: 1 file(s)"* ]]
}

@test "pg_restore with --source is rejected" {
  touch "$TMP/db.dump"
  run main --driver pg_restore --scratch "$TMP/scratch" --source "$TMP/live/app" "$TMP/db.dump"
  [ "$status" -ne 0 ]
}

@test "unknown driver is rejected" {
  run main --driver zip "$TMP/app.tar.gz"
  [ "$status" -ne 0 ]
}
