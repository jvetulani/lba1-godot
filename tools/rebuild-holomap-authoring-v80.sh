#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${GODOT_BIN:-}" ]]; then
  if command -v godot >/dev/null 2>&1; then GODOT_BIN="$(command -v godot)"
  elif command -v godot4 >/dev/null 2>&1; then GODOT_BIN="$(command -v godot4)"
  else GODOT_BIN="/Work/Programs/Godot/4.8-beta2/Godot_v4.8-beta2_linux.x86_64"
  fi
fi
[[ -x "$GODOT_BIN" ]] || { echo "Missing executable: $GODOT_BIN" >&2; exit 1; }
scene="scenes/holomap_authoring/TwinsunAuthoring.tscn"
if [[ -f "$scene" ]]; then
  backup="${scene}.before-v80-$(date +%Y%m%d-%H%M%S).bak"
  cp -p "$scene" "$backup"
  echo "Backed up scene to $backup"
fi
args=()
if [[ -n "${LBA_DATA_PATH:-}" ]]; then args+=("--data=$LBA_DATA_PATH"); fi
"$GODOT_BIN" --headless --path . --script res://scripts/editor/generate_holomap_authoring.gd -- --force "${args[@]}"
[[ -f "$scene" ]] || { echo "Scene generation failed" >&2; exit 1; }
"$GODOT_BIN" --headless --path . --script res://scripts/editor/rename_holomap_locations.gd
printf '\nUpdated editor globe and 150 named markers using original LBA1 transforms.\n'
printf 'Labels are hidden by default; select a location node to inspect it.\n'
