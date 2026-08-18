#!/usr/bin/env bash
# Headless GDScript suite. Each tests/gd/test_*.gd runs in its OWN Godot
# process with its own timeout, so one hanging test cannot take down the
# run and the culprit is named. Pass test file names to run a subset:
#   scripts/test-editor.sh test_bz_hg2.gd test_bz_mat.gd
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
PER_TEST_TIMEOUT="${GODOT_TEST_TIMEOUT:-60}"

# Isolate user:// for the whole suite. Tests read and WRITE Settings
# (snap, view filters, game_root, recents); without isolation they poison
# the developer's real editor settings and inherit stale state from
# whatever ran before, making results order- and history-dependent.
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/bz-editor-tests.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
export XDG_DATA_HOME="$TEST_HOME/data"
export XDG_CONFIG_HOME="$TEST_HOME/config"
export XDG_CACHE_HOME="$TEST_HOME/cache"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "godot not found (set GODOT=). Editor tests skipped." >&2
  echo "Install Godot 4.7.1 and re-run scripts/test-editor.sh" >&2
  exit 2
fi

# Refresh the import cache + global class registry first; class_name
# resolution in -s mode depends on it. Failures here are non-fatal.
timeout 120 "$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  for f in tests/gd/test_*.gd; do
    files+=("$(basename "$f")")
  done
fi

pass=0
fail=0
failed_names=()
for f in "${files[@]}"; do
  out="$(timeout --signal=TERM --kill-after=5 "$PER_TEST_TIMEOUT" \
    "$GODOT" --headless --path "$ROOT" -s res://tests/gd/run_tests.gd -- "$f" 2>&1)"
  code=$?
  if [ "$code" -eq 0 ]; then
    pass=$((pass + 1))
    echo "PASS $f"
  else
    fail=$((fail + 1))
    if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
      failed_names+=("$f (TIMEOUT ${PER_TEST_TIMEOUT}s)")
      echo "FAIL $f — timed out after ${PER_TEST_TIMEOUT}s"
    else
      failed_names+=("$f (exit $code)")
      echo "FAIL $f — exit $code"
    fi
    echo "$out" | sed 's/^/    /' | tail -40
  fi
done

echo "----------------------------------------"
echo "suite: $pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failed_names[@]}"
  exit 1
fi
exit 0
