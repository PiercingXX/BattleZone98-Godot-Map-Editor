#!/usr/bin/env bash
# Headless GDScript suite. Godot 4.7 on this machine has been observed to
# raise blocking GUI alerts under --headless; wrap in a timeout and fall
# back to xvfb-run when the first attempt hangs.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ -z "${GODOT:-}" ]; then
  for c in godot /usr/bin/godot /usr/local/bin/godot "$HOME/.local/bin/godot"; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then
      GODOT="$c"
      break
    fi
  done
fi
GODOT="${GODOT:-godot}"
TIMEOUT_SEC="${GODOT_TEST_TIMEOUT:-90}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "godot not found (set GODOT=). Editor tests skipped." >&2
  echo "Install Godot 4.7.1 and re-run scripts/test-editor.sh" >&2
  exit 2
fi

run_godot() {
  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM --kill-after=5 "$TIMEOUT_SEC" "$@"
  else
    "$@"
  fi
}

ARGS=("$GODOT" --headless --path "$ROOT" -s res://tests/gd/run_tests.gd)

echo "editor tests: ${ARGS[*]}"
run_godot "${ARGS[@]}"
code=$?
if [ "$code" -eq 0 ]; then
  exit 0
fi
if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
  if command -v xvfb-run >/dev/null 2>&1; then
    echo "headless timed out; retrying under xvfb-run -a" >&2
    run_godot xvfb-run -a "${ARGS[@]}"
    exit $?
  fi
  echo "headless timed out and xvfb-run is not available" >&2
  exit "$code"
fi
exit "$code"
