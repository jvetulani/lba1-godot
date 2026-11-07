# lba1-godot

Godot 4 rendering, audio, movie, UI, and input host for the original Little
Big Adventure 1 engine. The native submodule will supply gameplay simulation
and state while retaining its standalone SDL game. This repository contains
no original game data.

## Current state

With original game data imported, the Godot main scene displays the menu
artwork and plays converted menu music, the DRAGON3 boot movie, the English
narrated intro illustrations, and the INTROD OGV. It has modular CanvasLayer menus, Godot audio buses, a
persistent original-data path, and keyboard/gamepad Input Map actions. The
native simulation and world renderer are not connected, so New Game returns
to the menu after the intro.
`World3D.tscn` can already load an original LBA1 BODY.HQR actor into the
Godot mesh renderer with the existing dither shader. Actor and world state
still need to come from the native host.
The project also decodes original GRI/BLL scene grids and BRK brick images,
with a nearest-sampled tile shader that accepts optional normal maps. Its
window starts at 1280×720 and supports resizing.

The pinned `native/lba1-native` submodule owns the 64-bit engine and media
importer. Godot's desktop importer discovers its tools there. A release must
bundle the importer tools separately.

## Native repository relationship

`lba1-native` is pinned at `eaab71e` as a submodule at `native/lba1-native`.
Clone this repository with `--recurse-submodules`, or run
`git submodule update --init` after cloning.

## Stages

1. **Menu presentation:** Godot Control text and buttons, original artwork,
   a slow plasma button shader, keyboard/gamepad focus, imported audio and FMV.
   The original bitmap font and final menu styling are still to come.
2. **Native host:** split engine startup and the New Game/Continue commands
   from SDL, send simulation events through a stable C API, and wrap it in a
   Godot GDExtension. Apply Godot Input Map actions at 50 Hz.
3. **First world scene:** expose grid, brick, sprite, actor, camera, and
   animation snapshots. Render one real scene's tiles and actors with Godot,
   using the LBA1 character shader. The first actor mesh path is in place.
4. **Playable slice:** connect collision, scripts, dialogue, inventory,
   transitions, save/load, and in-game music/cutscenes to reach continuous
   gameplay from the menu.
5. **Platform parity:** validate Linux and Windows first, then Web and
   mobile/macOS asset and media paths with platform-specific packaging.

Run the project with Godot 4.8 or newer. In Settings, choose your own
original LBA1 game-data directory and import media. See
`docs/godot_game_architecture.md` for the current bridge boundary.

No copyrighted game archives or converted media are stored here. Review the
GPL terms of the native engine before distribution.
