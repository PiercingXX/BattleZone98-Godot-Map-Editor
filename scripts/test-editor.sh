#!/usr/bin/env bash
# Headless GDScript suite. Each tests/gd/test_*.gd runs in its OWN Godot
# process with its own timeout, so one hanging test cannot take down the
# run and the culprit is named. Pass test file names to run a subset:
#   scripts/test-editor.sh test_bz_hg2.gd test_bz_mat.gd
#
# Verdicts, from run_tests.gd's exit code:
#   0  PASS
#   3  SKIP  — a precondition the machine cannot supply (the gitignored .bzn
#             fixtures). Never a pass and never a regression.
#   *  FAIL
#
# CI budgets (unset = unenforced, so a plain local run is unchanged):
#   GODOT_TEST_MIN_PASS   fail if fewer than N files passed (catches a test
#                         file that silently stopped being discovered)
#   GODOT_TEST_MAX_SKIP   fail if more than N files skipped
#   GODOT_TEST_MAX_WARN   fail if more than N files printed a SCRIPT ERROR
#   GODOT_TEST_STRICT=1   treat any SCRIPT ERROR as a failure outright
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Windows: Godot is a native binary, so it needs native paths, and bash does
# not convert environment variables — only argv, and only sometimes. cygpath
# ships with Git for Windows; elsewhere this is the identity function.
_native() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

if [ -z "${GODOT:-}" ]; then
  for c in godot /usr/bin/godot /usr/local/bin/godot "$HOME/.local/bin/godot"; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then
      GODOT="$c"
      break
    fi
  done
fi
GODOT="${GODOT:-godot}"
# A GODOT handed over in Windows form (C:\...\godot.exe) is neither on PATH
# nor -x from bash. Convert before the existence check below rejects it.
if command -v cygpath >/dev/null 2>&1; then
  case "$GODOT" in
    *\\*|[A-Za-z]:/*) GODOT="$(cygpath -u "$GODOT")" ;;
  esac
fi
PER_TEST_TIMEOUT="${GODOT_TEST_TIMEOUT:-60}"

# Isolate user:// for the whole suite. Tests read and WRITE Settings
# (snap, view filters, game_root, recents); without isolation they poison
# the developer's real editor settings and inherit stale state from
# whatever ran before, making results order- and history-dependent.
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/bz-editor-tests.XXXXXX")"
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/data" "$TEST_HOME/config" "$TEST_HOME/cache" "$TEST_HOME/appdata"
export XDG_DATA_HOME="$TEST_HOME/data"
export XDG_CONFIG_HOME="$TEST_HOME/config"
export XDG_CACHE_HOME="$TEST_HOME/cache"
# Windows ignores XDG_*: user:// lives under %APPDATA%. Point that at the same
# throwaway home so the isolation is real on both platforms.
APPDATA="$(_native "$TEST_HOME/appdata")"
LOCALAPPDATA="$APPDATA"
export APPDATA LOCALAPPDATA
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "godot not found (set GODOT=). Editor tests skipped." >&2
  echo "Install Godot 4.7 stable and re-run scripts/test-editor.sh" >&2
  exit 2
fi

# `timeout` is GNU coreutils. Git for Windows normally ships it, but if it is
# missing every test would die at exit 127 and read as a total suite failure —
# far worse than losing the per-test kill. Degrade loudly instead.
if command -v timeout >/dev/null 2>&1; then
  _run_capped() { timeout --signal=TERM --kill-after=5 "$PER_TEST_TIMEOUT" "$@"; }
  _run_import() { timeout 120 "$@"; }
else
  echo "note: 'timeout' not found — running without a per-test kill" >&2
  _run_capped() { "$@"; }
  _run_import() { "$@"; }
fi

PROJECT_PATH="$(_native "$ROOT")"

# Refresh the import cache + global class registry first; class_name
# resolution in -s mode depends on it. Failures here are non-fatal.
_run_import "$GODOT" --headless --path "$PROJECT_PATH" --import >/dev/null 2>&1

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
skip=0
warn=0
failed_names=()
skipped_names=()
warned_names=()
for f in "${files[@]}"; do
  out="$(_run_capped "$GODOT" --headless --path "$PROJECT_PATH" \
    -s res://tests/gd/run_tests.gd -- "$f" 2>&1)"
  code=$?
  # A GDScript runtime error aborts run() where it stands. Every assertion
  # after it is skipped in silence, so the file still reports PASS while
  # testing almost nothing. Surface it; STRICT makes it fatal.
  errors=0
  strict_fail=0
  case "$out" in
    *"SCRIPT ERROR"*) errors=1 ;;
  esac
  if [ "$errors" -eq 1 ]; then
    # Counted whatever the verdict, so a script error cannot hide behind a skip.
    warn=$((warn + 1))
    warned_names+=("$f")
    if [ "${GODOT_TEST_STRICT:-0}" = "1" ] && { [ "$code" -eq 0 ] || [ "$code" -eq 3 ]; }; then
      code=1
      strict_fail=1
    fi
  fi
  if [ "$code" -eq 0 ]; then
    if [ "$errors" -eq 1 ]; then
      echo "PASS $f — WARNING: SCRIPT ERROR, run() aborted early"
      echo "$out" | grep -A 3 "SCRIPT ERROR" | sed 's/^/    /' | head -8
    else
      echo "PASS $f"
    fi
    pass=$((pass + 1))
  elif [ "$code" -eq 3 ]; then
    skip=$((skip + 1))
    reason="$(echo "$out" | grep "^SKIP " | head -1 | sed "s/^SKIP $f //")"
    skipped_names+=("$f ${reason}")
    echo "SKIP $f ${reason}"
    if [ "$errors" -eq 1 ]; then
      echo "     WARNING: SCRIPT ERROR as well"
      echo "$out" | grep -A 3 "SCRIPT ERROR" | sed 's/^/    /' | head -8
    fi
  else
    fail=$((fail + 1))
    if [ "$strict_fail" -eq 1 ]; then
      failed_names+=("$f (SCRIPT ERROR, strict)")
      echo "FAIL $f — SCRIPT ERROR aborted run() (GODOT_TEST_STRICT)"
    elif [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
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
echo "suite: $pass passed, $fail failed, $skip skipped, $warn with script errors"
if [ "$skip" -gt 0 ]; then
  printf '  skipped: %s\n' "${skipped_names[@]}"
fi
if [ "$warn" -gt 0 ]; then
  printf '  script errors: %s\n' "${warned_names[@]}"
fi
if [ "$fail" -gt 0 ]; then
  printf '  failed: %s\n' "${failed_names[@]}"
  exit 1
fi

# Budgets. Each is a ratchet: a number that only ever goes down. They exist so
# a test that quietly stops running is a red build, not a silent hole.
budget_broken=0
if [ -n "${GODOT_TEST_MIN_PASS:-}" ] && [ "$pass" -lt "$GODOT_TEST_MIN_PASS" ]; then
  echo "budget: $pass passed, expected at least $GODOT_TEST_MIN_PASS" >&2
  budget_broken=1
fi
if [ -n "${GODOT_TEST_MAX_SKIP:-}" ] && [ "$skip" -gt "$GODOT_TEST_MAX_SKIP" ]; then
  echo "budget: $skip skipped, at most $GODOT_TEST_MAX_SKIP allowed" >&2
  budget_broken=1
fi
if [ -n "${GODOT_TEST_MAX_WARN:-}" ] && [ "$warn" -gt "$GODOT_TEST_MAX_WARN" ]; then
  echo "budget: $warn with script errors, at most $GODOT_TEST_MAX_WARN allowed" >&2
  budget_broken=1
fi
[ "$budget_broken" -eq 0 ] || exit 1
exit 0
