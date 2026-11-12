#!/usr/bin/env bats

load test_helper

setup() {
  setup_tmp
  source "${REPO_ROOT}/bin/opsbox"
}

teardown() {
  teardown_tmp
}

@test "is_command recognises known subcommands" {
  run is_command backup
  [ "$status" -eq 0 ]
  run is_command prune-old
  [ "$status" -eq 0 ]
}

@test "is_command knows the newer subcommands" {
  local c
  for c in backup-verify logrotate-audit procwatch; do
    run is_command "$c"
    [ "$status" -eq 0 ]
    [ -x "${REPO_ROOT}/bin/$c" ]
  done
}

@test "every subcommand is installed by make install" {
  run make -C "$REPO_ROOT" install DESTDIR="$TMP/root" PREFIX=/usr/local
  [ "$status" -eq 0 ]
  local c
  for c in "${OPSBOX_COMMANDS[@]}"; do
    [ -x "$TMP/root/usr/local/bin/$c" ]
  done
}

@test "is_command rejects unknown names" {
  run is_command frobnicate
  [ "$status" -ne 0 ]
}

@test "opsbox --version prints the version" {
  run "${REPO_ROOT}/bin/opsbox" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")" ]
}

@test "opsbox --help lists commands" {
  run "${REPO_ROOT}/bin/opsbox" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"backup"* ]]
  [[ "$output" == *"healthcheck"* ]]
}

@test "opsbox with no args fails" {
  run "${REPO_ROOT}/bin/opsbox"
  [ "$status" -ne 0 ]
}

@test "opsbox with unknown command fails" {
  run "${REPO_ROOT}/bin/opsbox" nope
  [ "$status" -ne 0 ]
}

@test "opsbox dispatches to a real subcommand" {
  mkdir -p "$TMP/src"
  echo data > "$TMP/src/a"
  run "${REPO_ROOT}/bin/opsbox" backup --dest "$TMP/out" --keep 2 "$TMP/src"
  [ "$status" -eq 0 ]
  count="$(find "$TMP/out" -name 'src-*.tar.gz' | wc -l)"
  [ "$count" -eq 1 ]
}

@test "opsbox --version works after make install" {
  run make -C "$REPO_ROOT" install DESTDIR="$TMP/root" PREFIX=/usr/local
  [ "$status" -eq 0 ]
  run "$TMP/root/usr/local/bin/opsbox" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")" ]
  [ "$output" != "unknown" ]
}

@test "make uninstall removes the installed VERSION" {
  make -C "$REPO_ROOT" install DESTDIR="$TMP/root" PREFIX=/usr/local
  run make -C "$REPO_ROOT" uninstall DESTDIR="$TMP/root" PREFIX=/usr/local
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/root/usr/local/share/opsbox/VERSION" ]
  [ ! -e "$TMP/root/usr/local/bin/opsbox" ]
}
