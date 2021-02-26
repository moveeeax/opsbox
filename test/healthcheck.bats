#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/bin/healthcheck"
}

teardown() {
  # Stop any listener started by a test.
  if [ -n "${LISTENER_PID:-}" ]; then
    kill "$LISTENER_PID" 2>/dev/null || true
    wait "$LISTENER_PID" 2>/dev/null || true
  fi
  teardown_tmp
}

# Start a background TCP listener on a free port; sets PORT and LISTENER_PID.
start_listener() {
  PORT=0
  # Pick a high port unlikely to collide.
  PORT=$(( (RANDOM % 2000) + 20000 ))
  python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
  LISTENER_PID=$!
  # Wait until the port accepts a connection.
  local i
  for i in $(seq 1 50); do
    if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${PORT}" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

@test "classify_target recognises http and https" {
  run classify_target "http://example.com"
  [ "$output" = "http" ]
  run classify_target "https://example.com/path"
  [ "$output" = "http" ]
}

@test "classify_target recognises host:port" {
  run classify_target "db.internal:5432"
  [ "$output" = "tcp" ]
}

@test "classify_target rejects junk" {
  run classify_target "not a target"
  [ "$status" -ne 0 ]
}

@test "check_tcp succeeds against a live listener" {
  start_listener
  run check_tcp 127.0.0.1 "$PORT" 3
  [ "$status" -eq 0 ]
}

@test "check_tcp fails against a closed port" {
  run check_tcp 127.0.0.1 1 2
  [ "$status" -ne 0 ]
}

@test "check_http succeeds against a live server" {
  start_listener
  run check_http "http://127.0.0.1:${PORT}/" 3
  [ "$status" -eq 0 ]
}

@test "main returns non-zero when a target is unreachable" {
  run main --timeout 2 127.0.0.1:1
  [ "$status" -ne 0 ]
}

@test "main succeeds when all targets are reachable" {
  start_listener
  run main --timeout 3 "127.0.0.1:${PORT}"
  [ "$status" -eq 0 ]
}
