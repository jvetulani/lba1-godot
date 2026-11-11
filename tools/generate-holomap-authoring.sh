#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${GODOT_BIN:-}" ]]; then
  if command -v godot >/dev/null; then GODOT_BIN=$(command -v godot)
  elif command -v godot4 >/dev/null; then GODOT_BIN=$(command -v godot4)
  else GODOT_BIN=/Work/Programs/Godot/4.8-beta2/Godot_v4.8-beta2_linux.x86_64
  fi
fi
if [[ ! -x "$GODOT_BIN" ]]; then echo "Godot not found: $GODOT_BIN" >&2; exit 1; fi
args=()
if [[ -n "${LBA_DATA_PATH:-}" ]]; then args+=("--data=$LBA_DATA_PATH"); fi
args+=("$@")
"$GODOT_BIN" --headless --path . --script res://scripts/editor/generate_holomap_authoring.gd -- "${args[@]}"
