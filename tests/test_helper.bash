# Shared setup for the bats tests.

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Put the stubs first on PATH and start an empty call log.
use_stubs() {
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  : > "$STUB_LOG"
  export PATH="$REPO/tests/stubs:$PATH"
}

# Copy a top-level script into a fresh project folder and cd into it.
project_with() {
  export PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT/backups" "$PROJECT/config/rclone"
  cp "$REPO/$1" "$PROJECT/"
  cd "$PROJECT"
}

# Run a script with lines of input, e.g. feed restore.sh "3" "y"
feed() {
  local script="$1"
  shift
  run bash -c 'printf "%s\n" "${@:2}" | bash "$1"' _ "$script" "$@"
}

calls() { cat "$STUB_LOG"; }
called() { grep -qF -- "$1" "$STUB_LOG"; }
not_called() { ! grep -qF -- "$1" "$STUB_LOG"; }
