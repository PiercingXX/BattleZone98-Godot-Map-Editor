#!/usr/bin/env bash
# One entry point: backend pytest, then the editor GDScript suite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [ -x "$ROOT/.venv/bin/python" ]; then
  PY="$ROOT/.venv/bin/python"
else
  PY="python3"
fi
echo "== backend =="
"$PY" -m pytest backend/tests -q
echo "== editor =="
"$ROOT/scripts/test-editor.sh"
