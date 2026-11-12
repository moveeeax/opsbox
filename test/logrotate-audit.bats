#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/bin/logrotate-audit"
  L="$TMP/log"
  mkdir -p "$L/app" "$TMP/etc/logrotate.d"
  chmod 755 "$L" "$L/app"
  echo line > "$L/app/app.log"
  chmod 640 "$L/app/app.log"
  # Keep the fixture away from the real /proc unless a test sets one up.
  export OPSBOX_PROC="$TMP/proc"
  ME="$(id -un)"
  GRP="$(id -gn)"
  # BSD-style filesystems hand new files the directory's group instead.
  chgrp "$GRP" "$L/app/app.log"
}

teardown() {
  teardown_tmp
}

# conf FILE - write stdin to FILE.
conf() {
  cat > "$1"
}

@test "parse_rules applies global defaults and block overrides" {
  run parse_rules <<'CONF'
#@file /etc/logrotate.conf
weekly
rotate 4
create
/var/log/a.log /var/log/b.log {
  daily
  rotate 7
  postrotate
    rotate 99
  endscript
}
"/var/log/with space.log"
{
  su www-data adm
  copytruncate
}
CONF
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'1\t/etc/logrotate.conf\t/var/log/a.log\t7\tdaily\tdefault\t-\t1\t0' ]
  [ "${lines[1]}" = $'1\t/etc/logrotate.conf\t/var/log/b.log\t7\tdaily\tdefault\t-\t1\t0' ]
  [ "${lines[2]}" = $'2\t/etc/logrotate.conf\t/var/log/with space.log\t4\tweekly\tdefault\twww-data adm\t0\t1' ]
}

@test "expand_config inlines include files and directories in order" {
  printf '/b {\n}\n' > "$TMP/etc/logrotate.d/b"
  printf '/a {\n}\n' > "$TMP/etc/logrotate.d/a"
  printf '/stale {\n}\n' > "$TMP/etc/logrotate.d/a.dpkg-old"
  printf 'rotate 2\ninclude %s\n' "$TMP/etc/logrotate.d" > "$TMP/etc/logrotate.conf"
  run bash -c "source '${REPO_ROOT}/bin/logrotate-audit'; expand_config '$TMP/etc/logrotate.conf' | parse_rules | cut -f3,4"
  [ "$status" -eq 0 ]
  # The global "rotate 2" before the include applies to included rules.
  [ "$output" = $'/a\t2\n/b\t2' ]
}

@test "a rule that matches nothing is unmatched" {
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/*.log {
  rotate 3
}
$L/gone/*.log {
  missingok
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv
  [ "$status" -eq 0 ]
  [[ "$output" == *$'unmatched\t'"$L/gone/*.log"* ]]
  [[ "$output" != *$'unmatched\t'"$L/app/*.log"* ]]
}

@test "--fail-on turns findings into a non-zero exit" {
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/gone.log {
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --fail-on unmatched
  [ "$status" -eq 1 ]
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --fail-on overlap
  [ "$status" -eq 0 ]
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --fail-on any
  [ "$status" -eq 1 ]
}

@test "unknown --fail-on category is rejected" {
  : > "$TMP/etc/logrotate.conf"
  run main --config "$TMP/etc/logrotate.conf" --fail-on bogus
  [ "$status" -ne 0 ]
}

@test "files no rule covers are listed, rotated copies are not" {
  echo x > "$L/orphan.log"
  echo x > "$L/app/app.log.1"
  echo x > "$L/app/app.log.2.gz"
  echo x > "$L/orphan.log-20260101"
  echo x > "$L/skip.journal"
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv --ignore '*.journal'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'uncovered\t'"$L/orphan.log"$'\t'* ]]
  [[ "$output" != *"app.log.1"* ]]
  [[ "$output" != *"app.log.2.gz"* ]]
  [[ "$output" != *"orphan.log-20260101"* ]]
  [[ "$output" != *"skip.journal"* ]]
  [[ "$output" != *$'uncovered\t'"$L/app/app.log"$'\t'* ]]
}

@test "create that differs from the file is a perms finding" {
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
  create 0600 $ME $GRP
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv
  [[ "$output" == *$'perms\t'"$L/app/app.log"$'\t'"create 0600 $ME $GRP, but file is 640 $ME $GRP"* ]]
}

@test "create that matches the file is clean" {
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
  create 0640 $ME $GRP
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv --fail-on perms
  [ "$status" -eq 0 ]
  [[ "$output" != *$'perms\t'* ]]
}

@test "world-writable parent dir without su is a perms finding" {
  chmod 777 "$L/app"
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv
  [[ "$output" == *$'perms\t'"$L/app/app.log"$'\t'"parent dir $L/app is writable"* ]]
}

@test "su that differs from the file owner is a perms finding" {
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
  su nobody-xyz nogroup-xyz
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv
  [[ "$output" == *$'perms\t'"$L/app/app.log"$'\t'"su nobody-xyz nogroup-xyz, but file is owned by $ME:$GRP"* ]]
}

@test "a file claimed by two rules is an overlap with conflicting retention" {
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/*.log {
  rotate 7
  daily
}
$L/app/app.log {
  rotate 52
  weekly
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv
  [[ "$output" == *$'overlap\t'"$L/app/app.log"$'\t'"claimed by 2 rules: rotate 7 daily"*"rotate 52 weekly"*"conflicting retention"* ]]
}

@test "an open file without postrotate or copytruncate is flagged" {
  fake_proc_pid 300 nginx
  fake_proc_fd 300 5 "$L/app/app.log"
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
  rotate 2
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv --fail-on open
  [ "$status" -eq 1 ]
  [[ "$output" == *$'open\t'"$L/app/app.log"$'\t'"held open by pid 300 (nginx)"* ]]
}

@test "an open file with postrotate or copytruncate is fine" {
  fake_proc_pid 300 nginx
  fake_proc_fd 300 5 "$L/app/app.log"
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
  postrotate
    kill -HUP 300
  endscript
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --fail-on open
  [ "$status" -eq 0 ]
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
  copytruncate
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --fail-on open
  [ "$status" -eq 0 ]
}

@test "retention estimates rotate count times current size" {
  head -c 2048 /dev/zero > "$L/app/app.log"
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/app/app.log {
  rotate 52
  daily
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L" --format tsv
  [[ "$output" == *$'retention\t'"$L/app/app.log"$'\t'"rotate 52 daily: 52 x 2.0K = up to 104.0K kept"* ]]
}

@test "table format prints category and path" {
  conf "$TMP/etc/logrotate.conf" <<CONF
$L/gone.log {
}
CONF
  run main --config "$TMP/etc/logrotate.conf" --logdir "$L"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "unmatched  $L/gone.log" ]
}

@test "missing config is an error" {
  run main --config "$TMP/nope.conf"
  [ "$status" -ne 0 ]
}
