extends Node

const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const GAME_AUDIO := preload("res://scripts/audio/lba_game_audio.gd")

@onready var _ui: GameUI = $GameUI
@onready var _media: LBAMediaImport = $MediaImport
@onready var _audio: LBAAudioBuses = $AudioBuses
@onready var _world: LBAWorld3D = $World3D
@onready var _host: LBANativeHost = $NativeHost

var _active_scene := -1
var _active_grid_overlay := -2
var _game_started := false
var _speech_player: AudioStreamPlayer
var _game_audio: Node


func _ready() -> void:
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
	_media.cache_changed.connect(_on_visual_cache_changed.unbind(1))
	_media.cache_changed.connect(_on_media_selection_changed.unbind(1))
	_media.import_progress.connect(_ui.set_import_progress)
	_media.import_finished.connect(_on_import_finished)
	_ui.command_requested.connect(_on_command)
	_ui.gameplay_turn_block_changed.connect(func(blocked: bool) -> void:
		_host.block_turn_actions = blocked)
	_ui.setting_changed.connect(_audio.set_setting)
	_ui.sequence_finished.connect(_on_sequence_finished)
	_ui.media_error.connect(_on_media_error)
	_host.frame_received.connect(_on_native_frame)
	_host.dialogue_received.connect(_on_native_dialogue)
	_host.event_received.connect(_game_audio.apply_event)
	_ui.dialogue_finished.connect(_on_dialogue_finished)
	_host.startup_failed.connect(_on_native_failure)
	_host.stopped.connect(_on_native_failure)
	_world.visible = false
	_ui.set_original_data_path(_media.source_path)
	_ui.set_media_cache_path(_media.get_media_cache_path())
	_ui.set_settings(
		_audio.levels[&"music_volume"], _audio.levels[&"sound_volume"],
		_audio.levels[&"speech_volume"], _audio.levels[&"cinematic_volume"],
		_audio.wall_collision_damage, _audio.levels[&"master_volume"])
	if _media.is_import_ready():
		_ui.set_import_progress("LBA1 audio and movies are ready.", 1.0, false)
		_start_media()
	else:
		_ui.set_main_status("Set the original data and converted media cache in Settings.")


func _on_visual_cache_changed() -> void:
	VISUAL_CACHE.configure(_media.get_media_cache_path().path_join("visual-cache"))
	if _game_audio != null:
		_game_audio.configure(_media.get_media_cache_path())


func _on_command(command: StringName, payload: Variant) -> void:
	match command:
		&"original_data_path": _media.set_source_path(str(payload))
		&"media_cache_path": _media.set_media_cache_path(str(payload))
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
		_start_media()
	else:
		_ui.set_main_status(message)


func _start_media() -> void:
	if not _media.ensure_staged_data():
		_ui.set_main_status("Original data or media cache is unavailable. Check Settings.")
		return
	if not _ui.configure_media(_media.get_media_cache_path(), _media.get_staged_data_path()):
		return
	_ui.show_panel(&"main")
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
	if _ui.configure_media(_media.get_media_cache_path(), _media.get_staged_data_path()):
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
	# Keep the main-menu artwork hidden while the native process starts.
	_ui.set_world_active(true)
	_ui.show_hud()
	_ui.set_notification("Starting LBA1 gameplay…")
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


func _on_native_dialogue(dialogue: Dictionary) -> void:
	# Bubble sprites 90/91 are presentation only; speaker ID comes from LBA1.
	_world.set_speaking_actor(int(dialogue.get("speaker", -1)))
	# Text and voice ordinal come directly from the engine's active TEXT.HQR bank.
	_ui.set_dialogue("", str(dialogue.get("text", "")),
		int(dialogue.get("text_id", -1)) if int(dialogue.get("large_window", 0)) == 2 else -1)
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
	# English matches the default staged language; other languages require
	# the native LanguageCD setting to be exported separately.
	var key := "voice:en_%s:%d" % [bank_name, ordinal]
	var cache_dir := _media.get_media_cache_path()
	var manifest_path := cache_dir.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		return
	var assets: Variant = parsed.get("assets", {})
	if not (assets is Dictionary) or not assets.has(key):
		return
	var relative := str((assets[key] as Dictionary).get("path", ""))
	var voice_path := cache_dir.path_join(relative)
	if relative.is_empty() or not FileAccess.file_exists(voice_path):
		return
	_speech_player.stream = AudioStreamOggVorbis.load_from_file(voice_path)
	if _speech_player.stream != null:
		_speech_player.play()


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
		if not _world.load_grid_scene(scene, data_dir, overlay):
			_on_native_failure("Could not render LBA1 scene %d." % scene)
			return
		if scene != _active_scene:
			_world.clear_actors()
		_active_scene = scene
		_active_grid_overlay = overlay
	var actors: Array = state.get("actors", [])
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
		_ui.show_hud()
		_ui.set_notification("")


func _on_native_failure(message: String) -> void:
	_speech_player.stop()
	_game_audio.stop()
	_host.stop()
	_world.visible = false
	_game_started = false
	_ui.set_world_active(false)
	_ui.show_panel(&"main")
	_ui.set_main_status(message)
	_ui.play_menu_music()
