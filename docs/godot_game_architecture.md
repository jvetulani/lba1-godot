# LBA1 Godot game architecture

## Current boundary

`scenes/Main.tscn` composes `scenes/world/World3D.tscn` and
`scenes/ui/GameUI.tscn` as separate instances, with sibling media-import and
audio-bus controllers. The world scene currently
contains an orthographic camera and named containers for grid, bricks, actors,
sprites, and effects. It is a scene contract, not a reconstructed LBA1 world.
The Godot game scene is the project's default scene. The LBA1 character mesh
renderer and dither shader are part of this game project.

`GameUI.tscn` has a CanvasLayer root. Its main, pause, settings, dialogue,
inventory, save, load, and HUD children are independent Control scenes.
The main menu currently uses Godot text and reusable buttons with a slowly
animated plasma shader. The original LBA1 bitmap font is not imported yet.
Interactive controls use Godot focus and the built-in `ui_*` navigation
actions. `GameUI` owns panel visibility and focus. It emits
`command_requested(command, payload)` for gameplay requests and
`setting_changed(setting, value)` for options. A host must apply gameplay
changes, save/load requests, and settings through the native bridge, then
update the displayed UI using `show_panel`, `set_settings`, `set_hud`,
`set_dialogue`, `set_inventory`, and `set_save_slots`. UI controls do not
write native state or manipulate world meshes.

`project.godot` defines keyboard and gamepad actions for movement, primary
action, weapon, camera recentering, pause, and inventory. `LBAGameplayInput`
samples held gameplay actions into the exact bit layout of `lba_host.h`.
Pause and inventory are handled by Godot UI; the native gameplay bits will be
sent once the host runtime is connected.
Run `godot --headless --path . --script tests/validate_lba_input_map.gd`
to verify action names and native bit values.

No native gameplay bridge or scene renderer is connected yet. The menus are
presentation and request surfaces, not a playable game. The `Main.tscn`
settings panel is wired to the media-import controller and Godot audio buses.
After import, Godot displays the original menu artwork, plays the converted
DRAGON3 boot movie and menu track, the three English narrated introduction illustrations from `ress.hqr`,
and the INTROD OGV with its external music cues. FMV sound effects are already
in the OGV soundtrack. The sequence returns to the menu after INTROD and
reports that native gameplay startup is still unavailable.
With imported data available, run the media smoke check with
`LBA_TEST_DATA_PATH=/absolute/path/to/data godot --headless --path . --script tests/validate_lba_media_sequence.gd`.

## Original media and settings

The Settings menu saves the user-selected original LBA1 data directory in
`user://lba1-godot.cfg`. On desktop, **Import audio and movies** invokes the
native port's `tools/run_first_time.py --import-only --no-gui` with that source.
The launcher stages the original data in `user://lba1-native/data`, converts
audio and FMVs into `data/media-cache`, and maintains its existing revisioned
manifest/cache state. `MediaImport` reads the launcher's progress JSON and
emits completion. An editor run finds
`native/lba1-native/tools/run_first_time.py`;
the adjacent `../lba1-native` checkout is a development fallback.
The submodule is pinned at `eaab71e`.
An exported desktop build needs the same helper and its sibling tools bundled
beside the executable. This setup requires Python 3 and the native importer's
media tools. Browser export needs a separate user upload/decoder path.

`LBAAudioBuses` creates Music, Sound, Speech, and Cinematics buses. Cinematics
sends to Music, then Master, matching the native mix of cinematic × music ×
master for premixed FMV sound. The Settings menu exposes all five volumes in
the native 0–255 scale plus Wall Collision Damage and persists them in the same
Godot user config.
This is the control and bus-routing counterpart to the native options. The
native library now exposes `LBA_GetAudioSettings` and `LBA_SetAudioSettings`;
the Godot gameplay bridge still needs to call them, emit ordered audio/movie
events, and reproduce the SDL mixer's per-sample gain and voice calibration.
Until that bridge exists, native SDL sound does not play through Godot's buses.

## Native state contract to develop

`native/lba1-native/include/lba_host.h` already exposes pointer-free actor snapshots,
scene-loaded events, a 50 Hz loop step, semantic input bits, and audio-setting
values. It cannot start an independent Godot game yet: engine initialization,
presentation, and several script and menu calls still depend on the SDL
frontend. Godot therefore must not invoke the loop step as though it were a
standalone runtime.

Extend that contract with scene/cube identity, grid and brick resource IDs,
camera state, scene-transition events, dialogue and inventory state, settings,
and ordered audio/cinematic events. Define snapshot lifetime and resource
revision rules before a host consumes them. The native engine owns simulation,
collision, scripts, transitions, saves, inventory decisions, and settings
semantics. Godot owns presentation and input collection. The SDL frontend
remains a behavior reference.

Document and test the original world coordinate axes, scale, rotation units,
camera projection, and scene origin before choosing Godot conversion constants.
`CharacterMeshBuilder.UNIT_SCALE` scales model coordinates for display; that
value alone does not establish the game-world mapping.

## Godot rendering path

Godot must construct the final world from native nodes and rendering
resources, not from the SDL framebuffer. Before implementing it, inspect and
document the original grid, brick, tile, sprite, and animation formats and
their scene references. The world renderer will place bricks and tiles,
actors, sprites, effects, and the isometric camera from stable bridge data.
The existing LBA1 BODY decoder, mesh builder, pose handling, palette, and
`shaders/lba_character.gdshader` provide the character rendering base.
Maintain source palette characteristics and the established soft dither style.
`World3D.tscn` now exposes `set_actor_body`, `set_actor_transform`,
`set_actor_pose`, and `remove_actor`. It loads an original body and palette
through the HQR reader, then builds a Godot mesh with the dither shader. The
caller supplies a Godot transform; native-to-Godot world coordinates are not
mapped yet. With original data available, validate this path using
`LBA_TEST_DATA_PATH=/absolute/path/to/data godot --headless --path . --script tests/validate_lba_actor_renderer.gd`.

## Next implementation target

1. Extract native host initialization and New Game/Continue commands from
   `lba_main` and `MainGameMenu` so Godot can start a game after its intro.
   Replace calls that draw, block for input, or play audio/video inside the
   simulation with ordered host events. Preserve the SDL frontend as the
   reference implementation.
2. Build a small GDExtension around the C host API. On each fixed 50 Hz tick,
   map Godot Input Map actions into `LBA_SetGameplayActions`, step native
   simulation, then consume scene, audio, and movie events. Apply the existing
   Godot bus settings to the native engine and persist changes in the Godot
   config.
3. Expose scene/grid/brick resources and reconstruct one scene in
   `World3D.tscn` with the existing character shader and dithered materials.
   Verify coordinate scale, camera, animation, and collisions against SDL.
4. Connect save/load and inventory requests, scene transitions, dialogue,
   scripted FMVs, and remaining target-platform asset paths. Validate each
   against the original game before calling the loop playable.

Do not ship original game archives, converted media, or SoundFont binaries in
this source project. Review the native engine's GPL terms before combining
it with another distribution.
