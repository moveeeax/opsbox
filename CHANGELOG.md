# Changelog

All notable changes to this project are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed
- `logrotate-lite` recreates the rotated logfile with the original file's mode
  and ownership instead of whatever the current umask produces. A `0600` log
  previously came back as `0644` after rotation, exposing its successor to
  every user on the host.
- `logrotate-lite` accepts the `B`/`b` size suffix its own parser already had a
  branch for; `--size 512B` used to be rejected as invalid.
- `backup` and `logrotate-lite` read `--keep` values with a leading zero (`08`,
  `09`) as decimal. Bash parsed them as invalid octal, which aborted the
  rotation loop and left the tool exiting 0 having rotated nothing - in
  `logrotate-lite` that also clobbered the existing `.1` copy.
- `prune-old` no longer discards `find`'s exit status. A scan that failed
  reported "matched 0 file(s)" and exited 0, indistinguishable from a clean
  run with nothing to prune; it now warns and exits non-zero.

### Changed
- CI: `actions/checkout` v2 -> v5, bats-core pinned to `v1.14.0`, and the
  workflow token scoped to `contents: read`.

## [0.1.0] - 2021-01-31

### Added
- `lib/common.sh` shared library: timestamped logging (`info`/`warn`/`die`),
  `require_cmd`, `make_tmpdir`/`cleanup_tmpdirs`, `retry`, `is_uint` and
  `opsbox_version`.
- `backup` - timestamped tar.gz archives with keep-N rotation.
- `disk-report` - human-readable disk usage with threshold warnings.
- `healthcheck` - TCP and HTTP reachability probes with a timeout.
- `logrotate-lite` - size-based logfile rotation with optional gzip.
- `prune-old` - age-based file deletion, dry-run by default.
- `opsbox` dispatcher for running subcommands.
- bats test suite, ShellCheck linting, Makefile (`lint`/`test`/`check`/
  `install`/`uninstall`) and GitHub Actions CI.
