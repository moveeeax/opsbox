#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/bin/procwatch"
  export OPSBOX_PROC="$TMP/proc"
  mkdir -p "$TMP/proc"
  printf 'cpu  1 2 3 4\nbtime 1767225600\n' > "$TMP/proc/stat"
  # init <- bash <- java, with java in a systemd service.
  fake_proc 1 systemd 0 1 1 1 0 0 /sbin/init
  fake_proc 900 bash 1 10 5 1 1000 4096 -bash
  fake_proc 1234 java 900 500 100 42 360000 3145728 /usr/bin/java -Xmx4g -jar app.jar
  printf '0::/system.slice/app.service\n' > "$TMP/proc/1234/cgroup"
  for fd in 0 1 2 3 4 5 6 7; do
    fake_proc_fd 1234 "$fd" "/var/log/app-$((fd % 3)).log"
  done
}

teardown() {
  teardown_tmp
}

# fake_proc PID COMM PPID UTIME STIME THREADS STARTTIME RSS_KB ARGV...
fake_proc() {
  local pid="$1" comm="$2" ppid="$3" utime="$4" stime="$5" threads="$6" start="$7" rss="$8"
  shift 8
  fake_proc_pid "$pid" "$comm" "$@"
  local dir="$TMP/proc/$pid"
  # Fields 3..22 of proc(5): state ppid pgrp session tty tpgid flags minflt
  # cminflt majflt cmajflt utime stime cutime cstime priority nice
  # num_threads itrealvalue starttime, then a few more.
  printf '%s (%s) S %s %s %s 0 -1 4194560 100 0 0 0 %s %s 0 0 20 0 %s 0 %s 1000 50\n' \
    "$pid" "$comm" "$ppid" "$pid" "$pid" "$utime" "$stime" "$threads" "$start" > "$dir/stat"
  printf 'Name:\t%s\nVmRSS:\t%s kB\nThreads:\t%s\n' "$comm" "$rss" "$threads" > "$dir/status"
  printf 'Limit                     Soft Limit           Hard Limit           Units\n' > "$dir/limits"
  printf 'Max open files            10                   4096                 files\n' >> "$dir/limits"
}

@test "add_rule parses size, percent and duration" {
  add_rule 'rss>2G for 5m'
  add_rule 'fd>80%'
  add_rule 'threads > 200'
  [ "${PW_RULE_METRIC[0]}" = rss ]
  [ "${PW_RULE_LIMIT[0]}" = 2147483648 ]
  [ "${PW_RULE_FOR[0]}" = 300 ]
  [ "${PW_RULE_PCT[1]}" = 1 ]
  [ "${PW_RULE_LIMIT[1]}" = 80 ]
  [ "${PW_RULE_LIMIT[2]}" = 200 ]
  [ "${PW_RULE_FOR[2]}" = 0 ]
}

@test "add_rule rejects garbage and percent outside fd" {
  run add_rule 'mem>2G'
  [ "$status" -ne 0 ]
  run add_rule 'rss>80%'
  [ "$status" -ne 0 ]
  [[ "$output" == *"only supported for fd"* ]]
  run add_rule 'cpu>5G'
  [ "$status" -ne 0 ]
}

@test "proc_stat_fields copes with spaces and parens in comm" {
  printf '77 (we (ird) name) S 1 77 77 0 -1 0 0 0 0 0 3 4 0 0 20 0 1 0 500 0 0\n' > "$TMP/proc/1234/stat"
  run proc_stat_fields 1234
  [[ "$output" == "S 1 77 "* ]]
}

@test "proc_parents walks up to init" {
  run proc_parents 1234
  [ "$output" = "1234 java <- 900 bash <- 1 systemd" ]
}

@test "proc_cmdline joins argv and marks kernel threads" {
  run proc_cmdline 1234
  [ "$output" = "/usr/bin/java -Xmx4g -jar app.jar" ]
  : > "$TMP/proc/900/cmdline"
  run proc_cmdline 900
  [ "$output" = "[bash]" ]
}

@test "cgroup_unit picks the innermost service or scope" {
  run cgroup_unit /system.slice/app.service
  [ "$output" = app.service ]
  run cgroup_unit /user.slice/user-1000.slice/user@1000.service/app.slice/run-r1.scope
  [ "$output" = run-r1.scope ]
  run cgroup_unit /
  [ "$output" = "" ]
}

@test "cpu_pct is ticks over wall time" {
  # 50 ticks at 100 Hz in 1000 ms = 0.5 s of CPU per second.
  run cpu_pct 50 1000 100
  [ "$output" = 50 ]
  run cpu_pct 50 0 100
  [ "$status" -ne 0 ]
}

@test "track_breach waits for the window and fires once" {
  track_breach k 1 100 300; [ "$PW_RESULT" = "" ]
  track_breach k 1 300 300; [ "$PW_RESULT" = "" ]
  track_breach k 1 400 300; [ "$PW_RESULT" = fire ]
  track_breach k 1 500 300; [ "$PW_RESULT" = "" ]
  # Clearing re-arms, and the window starts over.
  track_breach k 0 600 300; [ "$PW_RESULT" = "" ]
  track_breach k 1 700 300; [ "$PW_RESULT" = "" ]
  track_breach k 1 1000 300; [ "$PW_RESULT" = fire ]
}

@test "track_breach with no window fires on the first breach" {
  track_breach k 1 100 0
  [ "$PW_RESULT" = fire ]
}

@test "an rss breach reports cmdline, parents, unit and start time" {
  run main --once --rule 'rss>2G'
  [ "$status" -eq 1 ]
  [[ "$output" == *"FIRED rss>2G: pid 1234 rss=3.0G"* ]]
  [[ "$output" == *"cmd:     /usr/bin/java -Xmx4g -jar app.jar"* ]]
  [[ "$output" == *"parents: 1234 java <- 900 bash <- 1 systemd"* ]]
  [[ "$output" == *"cgroup:  /system.slice/app.service (unit app.service)"* ]]
  [[ "$output" == *"started: "* ]]
  [[ "$output" != *"pid 900 "* ]]
}

@test "nothing over threshold exits 0" {
  run main --once --rule 'rss>8G' --rule 'threads>100'
  [ "$status" -eq 0 ]
  [[ "$output" != *"FIRED"* ]]
}

@test "fd percent of the soft limit" {
  # 8 open fds against a soft limit of 10 is 80%.
  run main --once --rule 'fd>79%'
  [ "$status" -eq 1 ]
  [[ "$output" == *"FIRED fd>79%: pid 1234 fd=80%"* ]]
  run main --once --rule 'fd>80%'
  [ "$status" -eq 0 ]
}

@test "threads and absolute fd counts" {
  run main --once --rule 'threads>40' --rule 'fd>7'
  [ "$status" -eq 1 ]
  [[ "$output" == *"FIRED threads>40: pid 1234 threads=42"* ]]
  [[ "$output" == *"FIRED fd>7: pid 1234 fd=8"* ]]
}

@test "--pid limits the scan" {
  run main --once --pid 900 --rule 'rss>1K'
  [ "$status" -eq 1 ]
  [[ "$output" == *"pid 900 "* ]]
  [[ "$output" != *"pid 1234 "* ]]
}

@test "a for window longer than the run warns and does not fire" {
  run main --once --rule 'rss>2G for 5m'
  [ "$status" -eq 0 ]
  [[ "$output" == *"cannot fire"* ]]
}

@test "--exec gets the offender in the environment" {
  run main --once --rule 'rss>2G' --exec "env | grep '^PROCWATCH_' | sort > '$TMP/env.txt'"
  [ "$status" -eq 1 ]
  grep -qx 'PROCWATCH_PID=1234' "$TMP/env.txt"
  grep -qx 'PROCWATCH_RULE=rss>2G' "$TMP/env.txt"
  grep -qx 'PROCWATCH_VALUE=3221225472' "$TMP/env.txt"
  grep -qx 'PROCWATCH_CMDLINE=/usr/bin/java -Xmx4g -jar app.jar' "$TMP/env.txt"
  grep -qx 'PROCWATCH_UNIT=app.service' "$TMP/env.txt"
}

@test "a failing --exec hook is a warning, not a crash" {
  run main --once --rule 'rss>2G' --exec 'exit 3'
  [ "$status" -eq 1 ]
  [[ "$output" == *"exec hook failed"* ]]
}

@test "--snapshot-dir saves status, limits and top fds" {
  run main --once --rule 'rss>2G' --snapshot-dir "$TMP/snaps"
  [ "$status" -eq 1 ]
  snap="$(find "$TMP/snaps" -mindepth 1 -maxdepth 1 -type d -name 'procwatch-1234-*')"
  [ -f "$snap/status" ]
  [ -f "$snap/limits" ]
  # fds 0..7 map to app-0 (3x), app-1 (3x), app-2 (2x).
  [ "$(wc -l < "$snap/fds.txt")" -eq 3 ]
  [[ "$(tail -n 1 "$snap/fds.txt")" == *"2 /var/log/app-2.log" ]]
}

@test "an idle process does not trip a cpu rule" {
  run main --once --interval 0 --rule 'cpu>90'
  [ "$status" -eq 0 ]
  [[ "$output" != *"FIRED"* ]]
}

# bump_utime PID TICKS [STARTTIME] - rewrite the fixture stat with more CPU.
bump_utime() {
  fake_proc "$1" java 900 "$2" 100 42 "${3:-360000}" 3145728 /usr/bin/java
}

@test "cpu is measured between two rounds" {
  add_rule 'cpu>90'
  check_round 100 "" "" 1 1234
  # Pretend the baseline was taken one second ago; at 100 Hz, 200 more
  # ticks in that second is 200% (two busy cores).
  PW_PREV_NS=$(( $(date +%s%N) - 1000000000 ))
  bump_utime 1234 700
  hz="$(getconf CLK_TCK)"
  [ "$hz" -eq 100 ] || skip "fixture assumes CLK_TCK=100, got $hz"
  check_round 101 "" "" 0 1234 > "$TMP/out"
  [ "$PW_FIRED_COUNT" -eq 1 ]
  grep -q "FIRED cpu>90: pid 1234 cpu=" "$TMP/out"
}

@test "a reused pid does not inherit the old process's cpu baseline" {
  add_rule 'cpu>90'
  check_round 100 "" "" 1 1234
  PW_PREV_NS=$(( $(date +%s%N) - 1000000000 ))
  # Same pid, new start time: a different process.
  bump_utime 1234 700 999999
  check_round 101 "" "" 0 1234 > "$TMP/out"
  [ "$PW_FIRED_COUNT" -eq 0 ]
}

@test "missing rule is an error" {
  run main --once
  [ "$status" -ne 0 ]
}
