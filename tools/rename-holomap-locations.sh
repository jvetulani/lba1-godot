#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${GODOT_BIN:-}" ]]; then
  if command -v godot >/dev/null 2>&1; then GODOT_BIN="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then GODOT_BIN="$(command -v godot4)"
  else GODOT_BIN="/Work/Programs/Godot/4.8-beta2/Godot_v4.8-beta2_linux.x86_64"
  fi
fi
if [[ ! -x "$GODOT_BIN" ]]; then echo "Godot executable missing: $GODOT_BIN" >&2; exit 1; fi
scene=scenes/holomap_authoring/TwinsunAuthoring.tscn
[[ -f "$scene" ]] || { echo "Authoring scene missing: $scene" >&2; exit 1; }
backup="$scene.before-location-names-$(date +%Y%m%d-%H%M%S).bak"
cp -p "$scene" "$backup"
echo "Backed up authoring scene: $backup"
"$GODOT_BIN" --headless --path . --script res://scripts/editor/rename_holomap_locations.gd
