#!/usr/bin/env bash
# Author a tiny map and print the Proton command to load it.
# Does not write into the game install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="${GAME_ROOT:-$HOME/.steam/steam/steamapps/common/Battlezone 98 Redux}"
OUT="${1:-/tmp/xxedplay-out}"
export PYTHONPATH="$ROOT/backend${PYTHONPATH:+:$PYTHONPATH}"
PYTHON="${PYTHON:-$ROOT/.venv/bin/python}"
mkdir -p /tmp/xxedplay-session "$OUT"
"$PYTHON" - <<PY
from pathlib import Path
from bzmap.editor.new import create_map
from bzmap.editor.save import save_session
game = Path(r"$GAME")
sess = Path("/tmp/xxedplay-session")
out = Path(r"$OUT")
create_map("xxedplay", "mars", 1280, 1280, sess, game, pack_kind="bzp")
print(save_session(sess, out))
PY
echo
echo "Load in-game (game already running? close it first):"
echo "  STEAM_COMPAT_CLIENT_INSTALL_PATH=\$HOME/.steam/steam \\"
echo "  STEAM_COMPAT_DATA_PATH=\$HOME/.steam/steam/steamapps/compatdata/301650 \\"
echo "  \"\$HOME/.steam/steam/steamapps/common/Proton - Experimental/proton\" run \\"
echo "  \"$GAME/battlezone98redux.exe\" \"$OUT/xxedplay.bzn\" /win"
echo
echo "Or copy $OUT/* into a test mod under <game>/mods/<id>/ and enable that mod."
