# Shared helpers for the opsbox bats suite.

# Absolute path to the repository root (parent of test/).
REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
export REPO_ROOT

# Create a scratch dir for a test and cd into a predictable layout.
setup_tmp() {
  TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/opsbox-test.XXXXXX")"
  export TMP
}

teardown_tmp() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# fake_proc_pid PID COMM [ARG...] - create a minimal /proc/PID entry under
# $TMP/proc (point OPSBOX_PROC there). cmdline is NUL-separated like the
# kernel's; COMM defaults to the first argument when no args are given.
fake_proc_pid() {
  local pid="$1" comm="$2"
  shift 2
  local dir="$TMP/proc/$pid"
  mkdir -p "$dir/fd"
  printf '%s\n' "$comm" > "$dir/comm"
  if [ $# -gt 0 ]; then
    printf '%s\0' "$@" > "$dir/cmdline"
  else
    printf '%s\0' "$comm" > "$dir/cmdline"
  fi
}

# fake_proc_fd PID FD TARGET - add an fd symlink pointing at TARGET.
fake_proc_fd() {
  ln -s "$3" "$TMP/proc/$1/fd/$2"
}
