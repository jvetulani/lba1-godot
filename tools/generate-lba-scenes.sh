#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-}"
if [[ -z "$GODOT" ]]; then
  for candidate in godot godot4; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ -z "$GODOT" && -x "/Work/Programs/Godot/4.8-beta2/Godot_v4.8-beta2_linux.x86_64" ]]; then
  GODOT="/Work/Programs/Godot/4.8-beta2/Godot_v4.8-beta2_linux.x86_64"
fi
if [[ -z "$GODOT" || ! -x "$GODOT" ]]; then
  echo "Godot executable not found; set GODOT_BIN=/path/to/godot" >&2
  exit 1
fi
"$GODOT" --headless --path . --script res://scripts/editor/generate_lba_scene_placeholders.gd -- "$@"
