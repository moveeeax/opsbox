# Changelog

All notable changes to this project are documented in this file. The format is
loosely based on [Keep a Changelog](https://keepachangelog.com/).

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
