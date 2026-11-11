extends Node

const BRICK_WARMUP := preload("res://scripts/import/lba_brick_import_warmup.gd")
const MODEL_WARMUP := preload("res://scripts/import/lba_model_import_warmup.gd")
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const GAME_AUDIO := preload("res://scripts/audio/lba_game_audio.gd")
const LANG := preload("res://scripts/ui/lba_languages.gd")
const TEXT_HQR := preload("res://scripts/ui/lba_text_hqr.gd")
const HQR := preload("res://scripts/import/hqr_reader.gd")

@onready var _ui: GameUI = $GameUI
@onready var _media: LBAMediaImport = $MediaImport
@onready var _audio: LBAAudioBuses = $AudioBuses
@onready var _world: LBAWorld3D = $World3D
@onready var _host: LBANativeHost = $NativeHost

var _active_scene := -1
var _active_grid_overlay := -2
var _brick_import_running := false
var _game_started := false
var _text_language := 0
var _voice_language := 0
var _localized_banks: Dictionary = {}
var _media_voice_assets: Dictionary = {}
var _last_display_dialogue: Dictionary = {}
var _speech_player: AudioStreamPlayer
var _game_audio: Node


func _ready() -> void:
	_text_language = LANG.get_text_index()
	_voice_language = LANG.get_voice_index()
	VISUAL_CACHE.configure(_media.get_media_cache_path().path_join("visual-cache"))
	_speech_player = AudioStreamPlayer.new()
	_speech_player.bus = "LBA Speech"
	add_child(_speech_player)
	_game_audio = GAME_AUDIO.new()
	add_child(_game_audio)
	_game_audio.configure(_media.get_media_cache_path())
	_media.source_changed.connect(_ui.set_original_data_path)
	_media.source_changed.connect(_on_media_selection_changed.unbind(1))
	_media.cache_changed.connect(_ui.set_media_cache_path)
	_media.soundfont_changed.connect(_ui.set_soundfont_path)
	_media.cache_changed.connect(_on_visual_cache_changed.unbind(1))
	_media.cache_changed.connect(_on_media_selection_changed.unbind(1))
	_media.import_progress.connect(_ui.set_import_progress)
	_media.import_finished.connect(_on_import_finished)
	_ui.command_requested.connect(_on_command)
	_ui.holomap_opened.connect(_on_holomap_opened)
	_ui.gameplay_turn_block_changed.connect(func(blocked: bool) -> void:
		_host.block_turn_actions = blocked)
	_ui.setting_changed.connect(_on_setting_changed)
	# Apply stored configuration to the actual world and to the native host.
	# The native host reapplies wall damage once simulation initialization ends.
	_host.configure_wall_collision_damage(_audio.wall_collision_damage)
	_world.apply_grid_render_settings(_audio.grid_lighting_enabled)
	_ui.sequence_finished.connect(_on_sequence_finished)
	_ui.media_error.connect(_on_media_error)
	_host.frame_received.connect(_on_native_frame)
	_host.dialogue_received.connect(_on_native_dialogue)
	_host.event_received.connect(_game_audio.apply_event)
	_ui.dialogue_finished.connect(_on_dialogue_finished)
	_host.startup_failed.connect(_on_native_failure)
	_host.stopped.connect(_on_native_failure)
	_world.visible = false
	_ui.set_languages(_text_language, _voice_language)
	_ui.set_original_data_path(_media.source_path)
	_ui.set_media_cache_path(_media.get_media_cache_path())
	_ui.set_soundfont_path(_media.soundfont_path)
	_ui.set_settings(
		_audio.levels[&"music_volume"], _audio.levels[&"sound_volume"],
		_audio.levels[&"speech_volume"], _audio.levels[&"cinematic_volume"],
		_audio.wall_collision_damage, _audio.levels[&"master_volume"],
		_audio.grid_lighting_enabled)
	if _media.is_import_ready():
		_ui.set_import_progress("Checking imported visual assets…", 0.0, true)
		_start_media_after_visual_import()
	else:
		_ui.show_panel(&"setup")
		_ui.set_main_status("Set the original data and converted media cache in Settings.")


var _holomap_actor_body := -1
var _holomap_actor_pose := PackedInt32Array()


func _on_holomap_opened() -> void:
	_ui.configure_holomap(_selected_data_dir(), _host.holomap_state(), _holomap_actor_body, _holomap_actor_pose)


func _on_setting_changed(setting: StringName, value: Variant) -> void:
	_audio.set_setting(setting, value)
	match setting:
		&"grid_lighting_enabled":
			_world.apply_grid_render_settings(_audio.grid_lighting_enabled)
		&"wall_collision_damage":
			_host.configure_wall_collision_damage(_audio.wall_collision_damage)


func _on_visual_cache_changed() -> void:
	VISUAL_CACHE.configure(_media.get_media_cache_path().path_join("visual-cache"))
	if _game_audio != null:
		_game_audio.configure(_media.get_media_cache_path())


func _on_command(command: StringName, payload: Variant) -> void:
	match command:
		&"text_language":
			_text_language = clampi(int(payload), 0, LANG.LABELS.size() - 1)
			_localized_banks.clear()
			_ui.set_languages(_text_language, _voice_language)
			_refresh_current_dialogue()
		&"voice_language":
			_voice_language = clampi(int(payload), 0, LANG.LABELS.size() - 1)
			_ui.set_languages(_text_language, _voice_language)
		&"original_data_path": _media.set_source_path(str(payload))
		&"media_cache_path": _media.set_media_cache_path(str(payload))
		&"soundfont_path": _media.set_soundfont_path(str(payload))
		&"import_original_media": _media.start_import()
		&"new_game":
			_ui.play_intro()
		&"open_save", &"open_load":
			_host.paused = _host._active
			_refresh_save_slots()
		&"save":
			var slot := int(payload.get("slot", -1)) if payload is Dictionary else int(payload)
			if slot < 0 or slot >= 5:
				return
			if _host.save_slot(slot):
				if payload is Dictionary:
					_store_save_name(slot, str(payload.get("name", "")))
				_refresh_save_slots()
				_host.paused = false
				_ui.show_hud()
				_ui.set_notification("Game saved in slot %d." % (slot + 1))
			else:
				push_warning("Could not save LBA1 slot %d" % slot)
		&"load":
			var slot := int(payload)
			var data_dir := _selected_data_dir()
			if not FileAccess.file_exists(data_dir.path_join("GODOT%02d.LBA" % slot)):
				push_warning("LBA1 slot %d is empty" % slot)
				return
			if not _host._active:
				_ui.stop_menu_music()
			if not _host._active and not _host.start_new_game(data_dir):
				return
			if _host.load_slot(slot):
				_active_scene = -1
				_active_grid_overlay = -2
				_world.clear_actors()
				_ui.set_world_active(true)
				_ui.show_hud()
				_ui.set_notification("Loaded slot %d." % (slot + 1))
			else:
				push_warning("Could not load LBA1 slot %d" % slot)
		&"quit_to_main":
			_speech_player.stop()
			_game_audio.stop()
			_host.stop()
			_world.clear_actors()
			_world.clear_grid_scene()
			_world.visible = false
			_active_scene = -1
			_active_grid_overlay = -2
			_game_started = false
			_ui.set_world_active(false)
			_ui.show_panel(&"main")
			_ui.play_menu_music()
		&"pause_simulation":
			_host.paused = true
		&"use_item":
			push_warning("Inventory item %d selected, but the current LBASimulation bridge has no use_item method yet." % int(payload))
			_ui.set_notification("Item use requires the native inventory action bridge.")
		&"set_behavior":
			_host.request_behavior(int(payload))
			_host.paused = false
			_ui.show_hud()
		&"pause_game":
			_host.paused = true
			_ui.show_panel(&"pause")
		&"resume_game":
			_host.paused = false
			_ui.show_hud()
		&"quit_game": get_tree().quit()
		_:
			_ui.show_panel(&"main")
			_ui.set_main_status("Native gameplay startup is not connected yet.")


func _on_import_finished(success: bool, message: String) -> void:
	_ui.set_import_progress(message, 1.0 if success else 0.0, false)
	if success:
		_start_media_after_visual_import()
	else:
		_ui.show_panel(&"setup")
		_ui.set_main_status(message)


# Import the original assets BEFORE playing the boot cinematics.
# Real progress advances between batches; only cache hits happen on later boots.
func _start_media_after_visual_import() -> void:
	if _brick_import_running:
		return
	_brick_import_running = true
	if not _media.ensure_staged_data():
		_brick_import_running = false
		_ui.show_panel(&"setup")
		_ui.set_main_status("Could not stage original LBA1 data for visual import.")
		return
	var data_dir := _selected_data_dir()
	var bricks_ready := BRICK_WARMUP.is_prepared(data_dir)
	var models_ready := MODEL_WARMUP.is_prepared(data_dir)
	var success := true
	if not bricks_ready or not models_ready:
		_ui.show_scene_loading("Preparing original tiles and models…")
		await get_tree().process_frame
	if not bricks_ready:
		success = await BRICK_WARMUP.warm_all(data_dir, Callable(self, "_on_brick_import_progress"))
	if success and not models_ready:
		success = await MODEL_WARMUP.warm_all(data_dir, Callable(self, "_on_model_import_progress"))
	_ui.hide_scene_loading()
	_brick_import_running = false
	if not success:
		_ui.show_panel(&"setup")
		_ui.set_import_progress("Visual asset import failed; see Godot output.", 0.0, false)
		return
	_ui.set_import_progress("Audio, video, tiles, models and animations ready.", 1.0, false)
	_start_media()


func _on_brick_import_progress(fraction: float, message: String) -> void:
	_ui.set_import_progress(message, fraction, true)
	_ui.set_scene_loading_progress(fraction * 0.7, message)


func _on_model_import_progress(fraction: float, message: String) -> void:
	_ui.set_import_progress(message, fraction, true)
	_ui.set_scene_loading_progress(0.7 + fraction * 0.3, message)


func _start_media() -> void:
	if not _media.ensure_staged_data():
		_ui.set_main_status("Original data or media cache is unavailable. Check Settings.")
		return
	if not _ui.configure_media(_media.get_media_cache_path(), _media.get_staged_data_path()):
		return
	_ui.show_panel(&"main")
	_ui.set_languages(_text_language, _voice_language)
	_ui.set_main_status("")
	_refresh_save_slots()
	_ui.play_boot_movie()


func _selected_data_dir() -> String:
	var test_data := OS.get_environment("LBA_TEST_DATA_PATH")
	return test_data if not test_data.is_empty() else _media.get_staged_data_path()


# These labels are original Godot UI metadata, NOT a gameplay IPC channel.
# The native .LBA save continues to own the entire authoritative game state.
func _save_name_path() -> String:
	return "user://lba1-save-names.json"


func _read_save_names() -> Dictionary:
	if not FileAccess.file_exists(_save_name_path()):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_save_name_path()))
	return data if data is Dictionary else {}


func _store_save_name(slot: int, name: String) -> void:
	var names := _read_save_names()
	names[str(slot)] = name.substr(0, 48)
	var file := FileAccess.open(_save_name_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(names))


func _refresh_save_slots() -> void:
	var data_dir := _selected_data_dir()
	var entries: Array[Dictionary] = []
	var names := _read_save_names()
	for slot in range(5):
		var present := FileAccess.file_exists(data_dir.path_join("GODOT%02d.LBA" % slot))
		var name := str(names.get(str(slot), "")) if present else ""
		entries.append({"id": slot, "name": name, "label": "Slot %d — %s" % [slot + 1,
			(name if not name.is_empty() else "Saved game") if present else "Empty"]})
	_ui.set_save_slots(entries)


func _on_media_selection_changed() -> void:
	if not _media.is_import_ready():
		_ui.set_import_progress("Choose a matching converted media cache, or import audio and movies.", 0.0, false)
		return
	if not _media.ensure_staged_data():
		return
	# A newly selected cache also needs the one-time BRK/model import.
	_start_media_after_visual_import()
	return
	if _ui.configure_media(_media.get_media_cache_path(), _media.get_staged_data_path()):
		_ui.set_languages(_text_language, _voice_language)
		_ui.set_import_progress("LBA1 audio and movies are ready.", 1.0, false)
		_ui.set_main_status("")
		_ui.play_menu_music()


func _on_sequence_finished(kind: StringName) -> void:
	if kind == &"boot":
		_ui.play_menu_music()
	elif kind == &"intro_movie" or kind == &"intro":
		_start_native_game()


func _on_media_error(message: String) -> void:
	_ui.show_panel(&"main")
	_ui.set_main_status(message)
	_ui.play_menu_music()


func _start_native_game() -> void:
	# Stop the separate UI soundtrack before native gameplay can start its own.
	_ui.stop_menu_music()
	# Keep the main-menu artwork hidden while the native process starts.
	_ui.set_world_active(true)
	_ui.show_hud()
	_ui.show_scene_loading("Preparing the first scene…")
	await get_tree().process_frame
	var data_dir := _selected_data_dir()
	if OS.get_environment("LBA_TEST_DATA_PATH").is_empty() and not _media.ensure_staged_data():
		_on_native_failure("Original data is unavailable. Check Settings.")
		return
	_host.start_new_game(data_dir)


func _unhandled_key_input(event: InputEvent) -> void:
	# F10 is a quick non-destructive renderer bottleneck diagnostic.
	# Compare FPS with the prison grid shown and hidden.
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F10 and _game_started:
		_world.toggle_grid_debug()
		print("LBA render diagnostic: bricks visible=", _world.are_bricks_visible(),
			" FPS=", Engine.get_frames_per_second())
		get_viewport().set_input_as_handled()


func _dialogue_speaker_colour(dialogue: Dictionary) -> Color:
	# Use the actual CoulObj ramp exported by the native game.
	var ramp: int = int(dialogue.get("color_ramp", -1))
	if ramp < 0 or ramp > 15:
		return Color(-1.0, -1.0, -1.0)
	var source_path: String = _selected_data_dir().path_join("ress.hqr")
	var palette_entry: Dictionary = HQR.read_entry(source_path, 0)
	if not palette_entry.get("ok", false):
		return Color(-1.0, -1.0, -1.0)
	var palette: PackedByteArray = palette_entry["data"]
	var at: int = (ramp * 16 + 12) * 3
	if at + 2 >= palette.size():
		return Color(-1.0, -1.0, -1.0)
	return Color8(palette[at], palette[at + 1], palette[at + 2])


func _on_native_dialogue(dialogue: Dictionary) -> void:
	# Bubble sprites 90/91 are presentation only; speaker ID comes from LBA1.
	_world.set_speaking_actor(int(dialogue.get("speaker", -1)))
	# Text and voice ordinal come directly from the engine's active TEXT.HQR bank.
	_last_display_dialogue = dialogue.duplicate(true)
	_ui.set_dialogue(_localized_dialogue_text(dialogue),
		int(dialogue.get("text_id", -1)) if int(dialogue.get("large_window", 0)) == 2 else -1,
		clampi(int(dialogue.get("large_window", 0)), 0, 2),
		_dialogue_speaker_colour(dialogue))
	_speech_player.stop()
	_speech_player.stream = null
	var bank := int(dialogue.get("bank", -1))
	var ordinal := int(dialogue.get("voice_index", -1))
	if bank < 0 or ordinal < 0:
		return
	var bank_name := ""
	match bank:
		0: bank_name = "sys"
		1: bank_name = "cre"
		2: bank_name = "gam"
		_: bank_name = "%03d" % (bank - 3)
	var text_path := LANG.locate_text(_selected_data_dir())
	if not text_path.is_empty():
		var localized_ordinal := TEXT_HQR.voice_ordinal(text_path, bank, _voice_language,
			int(dialogue.get("text_id", -1)))
		if localized_ordinal >= 0:
			ordinal = localized_ordinal
	var key := LANG.voice_key(_voice_language, bank_name, ordinal)
	var cache_dir := _media.get_media_cache_path()
	var manifest_path := cache_dir.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		return
	var assets: Variant = parsed.get("assets", {})
	if not (assets is Dictionary):
		return
	if not assets.has(key):
		# Only fall back to English when selected voice package is unavailable.
		var english_ordinal := int(dialogue.get("voice_index", -1))
		key = LANG.voice_key(0, bank_name, english_ordinal)
		if not assets.has(key):
			return
	var relative := str((assets[key] as Dictionary).get("path", ""))
	var voice_path := cache_dir.path_join(relative)
	if relative.is_empty() or not FileAccess.file_exists(voice_path):
		return
	_speech_player.stream = AudioStreamOggVorbis.load_from_file(voice_path)
	if _speech_player.stream != null:
		_speech_player.play()



func _localized_dialogue_text(dialogue: Dictionary) -> String:
	var fallback := str(dialogue.get("text", ""))
	var text_id := int(dialogue.get("text_id", -1))
	var bank := int(dialogue.get("bank", -1))
	if text_id < 0 or bank < 0:
		return fallback
	var archive := LANG.locate_text(_selected_data_dir())
	if archive.is_empty():
		return fallback
	var cache_key := "%s:%d:%d" % [archive, bank, _text_language]
	if not _localized_banks.has(cache_key):
		_localized_banks[cache_key] = TEXT_HQR.load_bank(archive, bank, _text_language)
	var record: Dictionary = (_localized_banks[cache_key] as Dictionary).get(text_id, {})
	var localized := str(record.get("text", ""))
	return localized if not localized.is_empty() else fallback


func _refresh_current_dialogue() -> void:
	if _last_display_dialogue.is_empty() or not _host.dialogue_active:
		return
	var dialogue := _last_display_dialogue
	_ui.set_dialogue(_localized_dialogue_text(dialogue),
		int(dialogue.get("text_id", -1)) if int(dialogue.get("large_window", 0)) == 2 else -1,
		clampi(int(dialogue.get("large_window", 0)), 0, 2),
		_dialogue_speaker_colour(dialogue))


func _on_dialogue_finished() -> void:
	_world.set_speaking_actor(-1)
	_speech_player.stop()
	_host.acknowledge_dialogue()


func _on_native_frame(state: Dictionary) -> void:
	var scene := int(state.get("scene", -1))
	if scene < 0:
		return
	var data_dir := _media.get_staged_data_path()
	var test_data := OS.get_environment("LBA_TEST_DATA_PATH")
	if not test_data.is_empty():
		data_dir = test_data
	var overlay := int(state.get("grid_overlay", -1))
	if scene != _active_scene or overlay != _active_grid_overlay:
		if not _game_started:
			_ui.show_scene_loading("Building the environment…")
		if not _world.load_grid_scene(scene, data_dir, overlay):
			_on_native_failure("Could not render LBA1 scene %d." % scene)
			return
		if scene != _active_scene:
			_world.clear_actors()
		_active_scene = scene
		_active_grid_overlay = overlay
	var actors: Array = state.get("actors", [])
	if not actors.is_empty() and actors[0] is Dictionary:
		_holomap_actor_body = int(actors[0].get("archive_body", -1))
		_holomap_actor_pose = actors[0].get("pose_groups", PackedInt32Array())
	_ui.configure_game_models(data_dir)
	_world.sync_actor_snapshots(actors, data_dir, int(state.get("grid_overlay_ceiling", 2147483647)))
	_world.focus_native_camera(actors, state.get("camera", PackedInt32Array()))
	_world.sync_extra_snapshots(state.get("extras", []), data_dir)
	_ui.set_gameplay_status(state.get("status", {}))
	_ui.set_inventory_state(state.get("inventory", PackedInt32Array()))
	if not actors.is_empty() and actors[0] is Dictionary:
		_ui.set_player_preview(int(actors[0].get("archive_body", -1)),
			actors[0].get("pose_groups", PackedInt32Array()))
	if not _game_started:
		_game_started = true
		_world.visible = true
		_ui.hide_scene_loading()
		_ui.show_hud()
		_ui.set_notification("")


func _on_native_failure(message: String) -> void:
	_ui.hide_scene_loading()
	_speech_player.stop()
	_game_audio.stop()
	_host.stop()
	_world.visible = false
	_game_started = false
	_ui.set_world_active(false)
	_ui.show_panel(&"main")
	_ui.set_main_status(message)
	_ui.play_menu_music()
