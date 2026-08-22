#!/usr/bin/env bash
# Microbenchmarks for the interactive paths AGENTS.md rule 6 calls correctness:
# height-texture upload, analytic raycast, full-grid selection.
#
#   scripts/bench.sh                 # table on stdout + JSON under cache/bench/
#   scripts/bench.sh out.json        # JSON at an explicit path
#   GODOT=/path/to/godot scripts/bench.sh
#
# Not part of scripts/test.sh and not part of the blocking CI job: a perf
# threshold enforced on a shared runner fails builds for reasons that have
# nothing to do with the diff. Run it locally, or via the manually-triggered
# `Benchmarks` workflow, and compare JSON to JSON from the same machine.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

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
if command -v cygpath >/dev/null 2>&1; then
  case "$GODOT" in
    *\\*|[A-Za-z]:/*) GODOT="$(cygpath -u "$GODOT")" ;;
  esac
fi
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "godot not found (set GODOT=)." >&2
  echo "Install Godot 4.7 stable and re-run scripts/bench.sh" >&2
  exit 2
fi

# cache/ is gitignored, so a benchmark run never dirties the working tree.
OUT="${1:-${BENCH_OUT:-$ROOT/cache/bench/bench-$(date -u +%Y%m%dT%H%M%SZ).json}}"
mkdir -p "$(dirname "$OUT")"

# Same throwaway home as the suite: benchmarks must not read or write the
# developer's real editor settings.
BENCH_HOME="$(mktemp -d "${TMPDIR:-/tmp}/bz-editor-bench.XXXXXX")"
trap 'rm -rf "$BENCH_HOME"' EXIT
mkdir -p "$BENCH_HOME/data" "$BENCH_HOME/config" "$BENCH_HOME/cache" "$BENCH_HOME/appdata"
export XDG_DATA_HOME="$BENCH_HOME/data"
export XDG_CONFIG_HOME="$BENCH_HOME/config"
export XDG_CACHE_HOME="$BENCH_HOME/cache"
APPDATA="$(_native "$BENCH_HOME/appdata")"
LOCALAPPDATA="$APPDATA"
export APPDATA LOCALAPPDATA

PROJECT_PATH="$(_native "$ROOT")"
"$GODOT" --headless --path "$PROJECT_PATH" --import >/dev/null 2>&1

"$GODOT" --headless --path "$PROJECT_PATH" \
  -s res://tests/gd/bench_main.gd -- "$(_native "$OUT")"
