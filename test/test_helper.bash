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
