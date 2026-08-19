#!/usr/bin/env bash
# Export the Windows x86_64 build. Produces a single self-contained .exe
# (PCK embedded) that runs on a stock Windows box with no Python, no Godot,
# and no other runtime installed — the format layer is pure GDScript.
#
#   scripts/export-windows.sh [output.exe]
#
# export_presets.cfg is gitignored (Godot convention — it can hold local
# signing paths), so this script writes the preset when it is absent. Edit the
# generated file for signing or icons; the script never overwrites an existing
# one.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-build/win/bz98-map-editor.exe}"

if [ -z "${GODOT:-}" ]; then
  for c in godot /usr/bin/godot /usr/local/bin/godot "$HOME/.local/bin/godot"; do
    if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then
      GODOT="$c"
      break
    fi
  done
fi
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "godot not found (set GODOT=)." >&2
  exit 2
fi

VERSION="$("$GODOT" --version 2>/dev/null | head -1 | cut -d. -f1-3)"
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Export templates missing: $TEMPLATE_DIR" >&2
  echo "Install them from the Godot editor (Editor > Manage Export Templates)," >&2
  echo "or unpack Godot_v${VERSION}-stable_export_templates.tpz there." >&2
  exit 2
fi

if [ ! -f export_presets.cfg ]; then
  echo "writing export_presets.cfg (gitignored; edit freely)"
  cat > export_presets.cfg <<'PRESET'
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="templates/**"
exclude_filter=""
export_path="build/win/bz98-map-editor.exe"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
application/icon=""
application/console_wrapper_icon=""
application/icon_interpolation=4
application/file_version=""
application/product_version=""
application/company_name=""
application/product_name=""
application/file_description=""
application/copyright=""
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
application/d3d12_agility_sdk_multiarch=true
ssh_remote_deploy/enabled=false
PRESET
fi

mkdir -p "$(dirname "$OUT")"
# Refresh the import cache first; class_name resolution depends on it.
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" "$OUT"
echo "exported: $OUT"
