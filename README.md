# opsbox

A small, dependency-light toolkit of Bash helper scripts for day-to-day server
operations: backups and restore tests, disk reporting and growth tracking,
health probes, log rotation and its audit, process watching and cleanup of
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
- Standard GNU userland (`tar`, `gzip`, `find`, `df`, `du`, `stat`, `date`,
  `sha256sum`, `shuf`)
- `curl` or `wget` for HTTP health checks
- Linux `/proc` for `procwatch`, `disk-report --deleted` and the open-file
  check in `logrotate-audit`
- `restic`, `borg` or `pg_restore` only for the matching `backup-verify` driver
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

### `backup-verify`

Restore a backup into a fresh directory under `--scratch` (never over the live
path) and check what came back. With `--source`, each restored file is compared
with the live tree: SHA-256, size, mode, and owner/group when run as root. A
file whose live mtime differs was changed after the backup and is reported but
not failed; same mtime with different content or metadata is a mismatch. The
restore wall-clock time goes into the report, so the RTO in the runbook is
measured.

```sh
backup-verify --source /etc --sample 200 --report /var/log/verify-etc.txt \
  /var/backups/etc-20260101-020000.tar.gz
backup-verify --driver restic --source /srv/data --scratch /var/tmp /srv/restic-repo
backup-verify --driver pg_restore /var/backups/app.dump
```

Drivers: `tar` (default, any compression tar detects), `restic` (`--snapshot`,
default `latest`), `borg` (`REPO::ARCHIVE`) and `pg_restore` (turns the dump
back into a SQL script, no database server needed). Each runs the real tool;
repository passwords come from its own environment variables. Exits 1 if the
restore fails or any file mismatches.

Options: `-D/--driver NAME`, `-s/--scratch DIR`, `-S/--source DIR`,
`--root PATH`, `--snapshot ID`, `-n/--sample N`, `-r/--report FILE`,
`-k/--keep-scratch`, `-h/--help`.

### `disk-report`

Report the size of each path and the usage of the filesystem holding it,
flagging any filesystem at or above a threshold.

```sh
disk-report --threshold 80 / /var /home
```

Exits non-zero if any path is missing or over threshold.

To see what grew rather than what is big, take a snapshot (plain text,
`bytes<TAB>path` per directory down to `--depth`, default 2) and compare a
later run against it:

```sh
disk-report --snapshot /var/lib/opsbox/disk-$(date +%F).tsv /var   # e.g. daily from cron
disk-report --since /var/lib/opsbox/disk-2026-11-01.tsv --top 20 --min-growth 100M
# +3.2G    /var/lib/docker/overlay2 (was 11.0G, now 14.2G)
# +1.1G    /var/log/new-app (new, now 1.1G)
```

`--since` without a path rescans the paths stored in the snapshot. Scans stay
on one filesystem unless `--cross-mounts` is given. `--deleted` adds the files
that were deleted but are still held open by a process, found through
`/proc/*/fd`: space `df` counts and `du` cannot see.

Options: `-t/--threshold PCT`, `--snapshot FILE`, `--since FILE`,
`-n/--depth N`, `--top N`, `--min-growth SIZE`, `--cross-mounts`, `--deleted`,
`-h/--help`.

### `healthcheck`

Probe one or more targets and exit non-zero if any is unreachable. Targets are
either `host:port` (TCP connect) or an `http(s)://` URL.

```sh
healthcheck --timeout 3 db.internal:5432 https://example.com/health
```

Options: `-t/--timeout SEC`, `-h/--help`.

### `logrotate-audit`

Read a logrotate config, following `include`, expand every path glob and report
rules that match no file (`unmatched`), files under `--logdir` that no rule
covers (`uncovered`; rotated copies like `app.log.1` or `app.log.2.gz` are not
counted), `create`/`su` directives that disagree with the file or a parent dir
logrotate will refuse to rotate in (`perms`), files claimed by two rules
(`overlap`) and files held open by a process whose rule has no `postrotate` or
`copytruncate` (`open`). Each rule also gets a retention estimate: rotate count
times current size.

```sh
logrotate-audit --config /etc/logrotate.conf --logdir /var/log --fail-on unmatched,open
```

Exits 0 unless a category listed in `--fail-on` (or `any`) was found.

Options: `-c/--config FILE`, `-l/--logdir DIR`, `-i/--ignore GLOB`,
`-f/--format table|tsv`, `--fail-on LIST`, `-h/--help`.

### `logrotate-lite`

Rotate a single logfile when it reaches a size threshold, keeping N numbered
copies and optionally gzipping them.

```sh
logrotate-lite --size 10M --keep 7 --gzip /var/log/app.log
```

Options: `-s/--size SIZE` (bytes, or a `B`/`K`/`M`/`G`/`T` suffix, case-insensitive), `-k/--keep N`,
`-z/--gzip`, `-f/--force`, `-h/--help`.

### `procwatch`

Sample processes from `/proc` and report the ones over a rule, with the full
command line, parent chain, cgroup, systemd unit and start time instead of a
bare PID.

```sh
procwatch --rule 'rss>2G for 5m' --rule 'fd>80%' --exec /usr/local/bin/notify.sh
procwatch --once --rule 'threads>500' --snapshot-dir /var/tmp/procwatch
```

Metrics: `rss` (bytes or a size suffix), `cpu` (percent of one core over the
interval), `fd` (count, or percent of the soft `Max open files` limit) and
`threads`. `for DURATION` (`s`/`m`/`h`) makes a rule fire only after the breach
held that long. A rule fires once per breach; `--exec` runs a command with the
offender in `PROCWATCH_*` variables, and `--snapshot-dir` saves the process's
`status`, `limits` and most common open files. With `--count`/`--once` the exit
status is 1 if anything fired.

Options: `-r/--rule RULE`, `-i/--interval SEC`, `-n/--count N`, `--once`,
`-p/--pid PID`, `-e/--exec CMD`, `-s/--snapshot-dir DIR`, `-h/--help`.

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
scratch space, `parse_size` / `human_bytes`, procfs readers
(`proc_open_files`, `deleted_open_files`; `OPSBOX_PROC` points them at another
tree, which the tests use) and a `retry N DELAY CMD...` helper. Source it from a script:

```sh
source "$(dirname "$0")/../lib/common.sh"
```

## Installation

Install the scripts and library under a prefix (default `/usr/local`):

```sh
sudo make install               # -> /usr/local/bin, /usr/local/lib/common.sh,
                                #    /usr/local/share/opsbox/VERSION
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
