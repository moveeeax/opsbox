# opsbox

A small, dependency-light toolkit of Bash helper scripts for day-to-day server
operations: backups, disk reporting, health probes, log rotation and cleanup of
stale files. Every script is self-contained, uses `set -euo pipefail`, ships a
`--help`, and is covered by a [bats](https://github.com/bats-core/bats-core)
test suite that is linted with [ShellCheck](https://www.shellcheck.net/).

## Layout

```
bin/            the command-line tools
lib/common.sh   shared logging / helper library, sourced by each tool
test/           bats test suite
```

## Requirements

- Bash 4+
- Standard GNU userland (`tar`, `gzip`, `find`, `df`, `du`, `stat`, `date`)
- `curl` or `wget` for HTTP health checks
- For development: `shellcheck` and `bats`

## Commands

All tools can be run directly (`bin/backup ...`) or through the `opsbox`
dispatcher, which forwards to the matching subcommand:

```sh
opsbox backup --dest /var/backups --keep 7 /etc
opsbox --version
opsbox --help          # list all subcommands
```

### `backup`

Create a timestamped `tar.gz` of a directory and rotate old archives.

```sh
backup --dest /var/backups --keep 7 /etc
# -> /var/backups/etc-20210131-020000.tar.gz  (keeps the 7 newest etc-*.tar.gz)
```

Options: `-d/--dest DIR`, `-k/--keep N`, `-h/--help`.

### `disk-report`

Report the size of each path and the usage of the filesystem holding it,
flagging any filesystem at or above a threshold.

```sh
disk-report --threshold 80 / /var /home
```

Exits non-zero if any path is missing or over threshold. Options:
`-t/--threshold PCT`, `-h/--help`.

### `healthcheck`

Probe one or more targets and exit non-zero if any is unreachable. Targets are
either `host:port` (TCP connect) or an `http(s)://` URL.

```sh
healthcheck --timeout 3 db.internal:5432 https://example.com/health
```

Options: `-t/--timeout SEC`, `-h/--help`.

### `logrotate-lite`

Rotate a single logfile when it reaches a size threshold, keeping N numbered
copies and optionally gzipping them.

```sh
logrotate-lite --size 10M --keep 7 --gzip /var/log/app.log
```

Options: `-s/--size SIZE` (bytes or `K`/`M`/`G`/`T` suffix), `-k/--keep N`,
`-z/--gzip`, `-f/--force`, `-h/--help`.

### `prune-old`

Delete files older than N days under a path. Dry-run by default; pass `--apply`
to actually remove.

```sh
prune-old --days 7 --pattern '*.log' /var/log/app      # preview only
prune-old --days 7 --pattern '*.log' --apply /var/log/app
```

Options: `-d/--days N`, `-p/--pattern GLOB`, `--apply`, `-h/--help`.

## Library

`lib/common.sh` provides timestamped `info` / `warn` / `die` logging,
`require_cmd` for dependency checks, `make_tmpdir` / `cleanup_tmpdirs` for
scratch space and a `retry N DELAY CMD...` helper. Source it from a script:

```sh
source "$(dirname "$0")/../lib/common.sh"
```

## Installation

Install the scripts and library under a prefix (default `/usr/local`):

```sh
sudo make install               # -> /usr/local/bin, /usr/local/lib/common.sh
make install PREFIX=$HOME/.local # user-local install
make uninstall                  # remove an installed copy
```

## Development

```sh
make lint    # shellcheck over lib and every script
make test    # run the bats suite
make check   # lint then test
```

Tool locations can be overridden, e.g. `make lint SHELLCHECK=/path/to/shellcheck`.

## License

MIT — see [LICENSE](LICENSE).
