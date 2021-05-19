#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/lib/common.sh"
}

teardown() {
  teardown_tmp
}

@test "info and warn write to stderr" {
  run bash -c "source '${REPO_ROOT}/lib/common.sh'; info hello 2>&1 1>/dev/null"
  [[ "$output" == *"[INFO] hello"* ]]
  run bash -c "source '${REPO_ROOT}/lib/common.sh'; warn careful 2>&1 1>/dev/null"
  [[ "$output" == *"[WARN] careful"* ]]
}

@test "die exits non-zero with an error line" {
  run bash -c "source '${REPO_ROOT}/lib/common.sh'; die boom"
  [ "$status" -ne 0 ]
  [[ "$output" == *"[ERROR] boom"* ]]
}

@test "require_cmd passes for existing commands" {
  run require_cmd bash ls
  [ "$status" -eq 0 ]
}

@test "require_cmd fails for a bogus command" {
  run bash -c "source '${REPO_ROOT}/lib/common.sh'; require_cmd definitely-not-a-real-cmd-xyz"
  [ "$status" -ne 0 ]
}

@test "make_tmpdir creates a directory" {
  dir="$(make_tmpdir opsbox-test)"
  [ -d "$dir" ]
  rm -rf "$dir"
}

@test "retry succeeds after transient failures" {
  local marker="$TMP/attempts"
  echo 0 > "$marker"
  flaky() {
    local n
    n=$(( $(cat "$marker") + 1 ))
    echo "$n" > "$marker"
    [ "$n" -ge 3 ]
  }
  run retry 5 0 flaky
  [ "$status" -eq 0 ]
  [ "$(cat "$marker")" -eq 3 ]
}

@test "retry gives up after N attempts" {
  always_fail() { return 1; }
  run retry 2 0 always_fail
  [ "$status" -ne 0 ]
}
