#!/usr/bin/env bash
# Author a tiny map and print the Proton command to load it.
# Does not write into the game install. Pure GDScript — no Python needed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="${GAME_ROOT:-$HOME/.steam/steam/steamapps/common/Battlezone 98 Redux}"
OUT="${1:-/tmp/xxedplay-out}"
GODOT="${GODOT:-godot}"

"$GODOT" --headless --path "$ROOT" -s res://scripts/playtest_map.gd -- "$OUT" "$GAME"

echo
echo "Load in-game (game already running? close it first):"
echo "  STEAM_COMPAT_CLIENT_INSTALL_PATH=\$HOME/.steam/steam \\"
echo "  STEAM_COMPAT_DATA_PATH=\$HOME/.steam/steam/steamapps/compatdata/301650 \\"
echo "  \"\$HOME/.steam/steam/steamapps/common/Proton - Experimental/proton\" run \\"
echo "  \"$GAME/battlezone98redux.exe\" \"$OUT/xxedplay.bzn\" /win"
echo
echo "Or copy $OUT/* into a test mod under <game>/mods/<id>/ and enable that mod."
