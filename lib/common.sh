#!/usr/bin/env bash
#
# common.sh - shared helpers for the opsbox toolkit.
#
# Source this file from a script:
#
#   source "$(dirname "$0")/../lib/common.sh"
#
# It provides timestamped logging, command checks, temp-dir management,
# size parsing/formatting, procfs readers and a small retry helper. It does not enable errexit itself so that callers
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

# opsbox_version - print the toolkit version from the VERSION file.
# Looks next to a source checkout (<root>/VERSION) first, then in the location
# `make install` uses (<PREFIX>/share/opsbox/VERSION).
opsbox_version() {
  local here version_file
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for version_file in "${here}/../VERSION" "${here}/../share/opsbox/VERSION"; do
    if [ -f "$version_file" ]; then
      tr -d '[:space:]' < "$version_file"
      printf '\n'
      return 0
    fi
  done
  printf 'unknown\n'
}

# is_uint VALUE - succeed if VALUE is a non-negative integer.
is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# parse_size SIZE -> bytes. Accepts plain integer or a B/K/M/G/T suffix
# (case-insensitive, powers of 1024).
parse_size() {
  local s="$1" num unit
  num="${s%[KkMmGgTtBb]}"
  unit="${s#"$num"}"
  case "$num" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$unit" in
    ''|B|b) printf '%s\n' "$num" ;;
    K|k) printf '%s\n' $((num * 1024)) ;;
    M|m) printf '%s\n' $((num * 1024 * 1024)) ;;
    G|g) printf '%s\n' $((num * 1024 * 1024 * 1024)) ;;
    T|t) printf '%s\n' $((num * 1024 * 1024 * 1024 * 1024)) ;;
    *) return 1 ;;
  esac
}

# human_bytes N -> e.g. "1.5K", "3.0M", "2.1G". A negative N keeps its sign.
human_bytes() {
  local bytes="$1" sign=""
  if [ "$bytes" -lt 0 ]; then
    sign="-"
    bytes=$((-bytes))
  fi
  local -a units=(B K M G T P)
  local i=0
  # Work in tenths to keep one decimal without floating point.
  local value=$((bytes * 10))
  while [ "$value" -ge 10240 ] && [ "$i" -lt $((${#units[@]} - 1)) ]; do
    value=$((value / 1024))
    i=$((i + 1))
  done
  printf '%s%d.%d%s\n' "$sign" $((value / 10)) $((value % 10)) "${units[i]}"
}

# opsbox_proc_root - where procfs is read from. Tests point OPSBOX_PROC at a
# fixture tree; everything else gets /proc.
opsbox_proc_root() {
  printf '%s\n' "${OPSBOX_PROC:-/proc}"
}

# proc_open_files -> "pid<TAB>fd<TAB>target" for every file descriptor this
# user can see under procfs. Processes owned by other users are skipped
# silently unless running as root, the same as ls -l /proc/PID/fd would.
proc_open_files() {
  local proc pid_dir fd target
  proc="$(opsbox_proc_root)"
  for pid_dir in "$proc"/[0-9]*; do
    [ -d "$pid_dir/fd" ] || continue
    for fd in "$pid_dir"/fd/*; do
      target="$(readlink -- "$fd" 2>/dev/null)" || continue
      printf '%s\t%s\t%s\n' "${pid_dir##*/}" "${fd##*/}" "$target"
    done
  done
}

# deleted_open_files -> "bytes<TAB>pid<TAB>fd<TAB>path" for each descriptor
# that still points at an unlinked file. Space held this way is invisible to
# du but still counted by df until the process closes the file or exits.
deleted_open_files() {
  local proc pid fd target bytes
  proc="$(opsbox_proc_root)"
  while IFS=$'\t' read -r pid fd target; do
    case "$target" in
      *' (deleted)') ;;
      *) continue ;;
    esac
    # stat -L follows the /proc magic link to the unlinked inode itself.
    bytes="$(stat -L -c '%s' -- "$proc/$pid/fd/$fd" 2>/dev/null)" || continue
    printf '%s\t%s\t%s\t%s\n' "$bytes" "$pid" "$fd" "${target% (deleted)}"
  done < <(proc_open_files)
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
