extends Node

@onready var _ui: GameUI = $GameUI
@onready var _media: LBAMediaImport = $MediaImport
@onready var _audio: LBAAudioBuses = $AudioBuses


func _ready() -> void:
	_media.source_changed.connect(_ui.set_original_data_path)
	_media.import_progress.connect(_ui.set_import_progress)
	_media.import_finished.connect(_on_import_finished)
	_ui.command_requested.connect(_on_command)
	_ui.setting_changed.connect(_audio.set_setting)
	_ui.sequence_finished.connect(_on_sequence_finished)
	_ui.media_error.connect(_on_media_error)
	_ui.set_original_data_path(_media.source_path)
	_ui.set_settings(
		_audio.levels[&"music_volume"], _audio.levels[&"sound_volume"],
		_audio.levels[&"speech_volume"], _audio.levels[&"cinematic_volume"],
		_audio.wall_collision_damage, _audio.levels[&"master_volume"])
	if _media.is_import_ready():
		_ui.set_import_progress("LBA1 audio and movies are ready.", 1.0, false)
		_start_media()
	else:
		_ui.set_main_status("Choose and import your original LBA1 data in Settings.")


func _on_command(command: StringName, payload: Variant) -> void:
	match command:
		&"original_data_path": _media.set_source_path(str(payload))
		&"import_original_media": _media.start_import()
		&"new_game":
			if not _ui.play_intro():
				_ui.show_panel(&"main")
		&"quit_to_main":
			_ui.show_panel(&"main")
			_ui.play_menu_music()
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
	if not _ui.configure_media(_media.get_media_cache_path(), _media.get_staged_data_path()):
		return
	_ui.show_panel(&"main")
	_ui.set_main_status("")
	_ui.play_boot_movie()


func _on_sequence_finished(kind: StringName) -> void:
	if kind == &"boot":
		_ui.play_menu_music()
	elif kind == &"intro_movie" or kind == &"intro":
		# Native bootstrap and scene rendering still need a Godot host backend.
		_ui.show_panel(&"main")
		_ui.set_main_status("Intro complete. Native gameplay startup is not connected yet.")
		_ui.play_menu_music()


func _on_media_error(message: String) -> void:
	_ui.show_panel(&"main")
	_ui.set_main_status(message)
	_ui.play_menu_music()
