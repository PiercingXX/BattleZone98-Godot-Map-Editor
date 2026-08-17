#!/usr/bin/env bash
# One entry point: the headless editor GDScript suite.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/test-editor.sh" "$@"
