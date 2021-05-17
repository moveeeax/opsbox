#!/usr/bin/env bash
#
# common.sh - shared helpers for the opsbox toolkit.
#
# Source this file from a script:
#
#   source "$(dirname "$0")/../lib/common.sh"
#
# It provides timestamped logging, command checks, temp-dir management and
# a small retry helper. It does not enable errexit itself so that callers
# keep control over their own shell options.

# Colour output only when stderr is a terminal.
if [ -t 2 ]; then
  _OPSBOX_C_RED=$'\033[31m'
  _OPSBOX_C_YELLOW=$'\033[33m'
  _OPSBOX_C_RESET=$'\033[0m'
else
  _OPSBOX_C_RED=""
  _OPSBOX_C_YELLOW=""
  _OPSBOX_C_RESET=""
fi

_opsbox_ts() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

# info MESSAGE... - log an informational line to stderr.
info() {
  printf '%s [INFO] %s\n' "$(_opsbox_ts)" "$*" >&2
}

# warn MESSAGE... - log a warning to stderr.
warn() {
  printf '%s [WARN] %s%s%s\n' "$(_opsbox_ts)" "$_OPSBOX_C_YELLOW" "$*" "$_OPSBOX_C_RESET" >&2
}

# die MESSAGE... - log an error and exit non-zero.
die() {
  printf '%s [ERROR] %s%s%s\n' "$(_opsbox_ts)" "$_OPSBOX_C_RED" "$*" "$_OPSBOX_C_RESET" >&2
  exit 1
}

# require_cmd CMD... - ensure each named command is available, else die.
require_cmd() {
  local cmd missing=0
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      warn "required command not found: $cmd"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || die "missing required command(s)"
}

# make_tmpdir [PREFIX] - create a temp dir and echo its path.
# The directory is registered for cleanup via cleanup_tmpdirs / trap.
_OPSBOX_TMPDIRS=()
make_tmpdir() {
  local prefix="${1:-opsbox}"
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")" || die "mktemp failed"
  _OPSBOX_TMPDIRS+=("$dir")
  printf '%s\n' "$dir"
}

# cleanup_tmpdirs - remove every dir created by make_tmpdir.
cleanup_tmpdirs() {
  local dir
  for dir in "${_OPSBOX_TMPDIRS[@]:-}"; do
    [ -n "$dir" ] && [ -d "$dir" ] && rm -rf "$dir"
  done
  _OPSBOX_TMPDIRS=()
}

# retry N DELAY CMD... - run CMD until it succeeds, up to N attempts,
# sleeping DELAY seconds between tries. Returns the last exit status.
retry() {
  local attempts="$1" delay="$2"
  shift 2
  local n=1 rc=0
  while true; do
    "$@" && return 0
    rc=$?
    if [ "$n" -ge "$attempts" ]; then
      return "$rc"
    fi
    warn "attempt $n/$attempts failed (rc=$rc), retrying in ${delay}s: $*"
    n=$((n + 1))
    sleep "$delay"
  done
}
