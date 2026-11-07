class_name GameUI
extends CanvasLayer

const ActionPanel = preload("res://scripts/ui/game_action_panel.gd")

signal command_requested(command: StringName, payload: Variant)
signal setting_changed(setting: StringName, value: Variant)
signal sequence_finished(kind: StringName)
signal media_error(message: String)

@onready var _main: ActionPanel = $Frame/MainMenu
@onready var _pause: ActionPanel = $Frame/PauseMenu
@onready var _settings: ActionPanel = $Frame/SettingsMenu
@onready var _dialogue: ActionPanel = $Frame/Dialogue
@onready var _inventory: ActionPanel = $Frame/Inventory
@onready var _save: ActionPanel = $Frame/SaveScreen
@onready var _load: ActionPanel = $Frame/LoadScreen
@onready var _hud: Control = $Frame/HUD
@onready var _backdrop: TextureRect = $Frame/MenuBackdrop
@onready var _media_sequence: LBAMediaSequence = $Frame/MediaSequence

var _panels: Dictionary = {}
var _current: StringName = &"main"
var _previous: StringName = &"main"


func _ready() -> void:
	_panels = {
		&"main": _main, &"pause": _pause, &"settings": _settings,
		&"dialogue": _dialogue, &"inventory": _inventory,
		&"save": _save, &"load": _load,
	}
	for panel_id in _panels:
		var panel: ActionPanel = _panels[panel_id]
		panel.action_requested.connect(_on_action.bind(panel_id))
	_media_sequence.sequence_finished.connect(func(kind: StringName) -> void:
		if _current == &"main":
			_main.call_deferred("focus_first")
		sequence_finished.emit(kind))
	_media_sequence.media_error.connect(func(message: String) -> void: media_error.emit(message))
	show_panel(&"main")


func show_panel(panel_id: StringName) -> void:
	if panel_id != &"hud" and not _panels.has(panel_id):
		push_warning("Unknown game UI panel: %s" % panel_id)
		return
	if _current != panel_id:
		_previous = _current
	_current = panel_id
	for id in _panels:
		(_panels[id] as Control).visible = id == panel_id
	_hud.visible = panel_id == &"hud"
	_backdrop.visible = panel_id != &"hud"
	if panel_id != &"hud":
		(_panels[panel_id] as ActionPanel).call_deferred("focus_first")


func show_hud() -> void:
	show_panel(&"hud")


func configure_media(cache_path: String, data_path: String) -> bool:
	if not _media_sequence.configure(cache_path, data_path):
		return false
	_backdrop.texture = LBAMediaSequence.load_resource_texture(data_path.path_join("ress.hqr"), 14, 0)
	return true


func play_boot_movie() -> bool:
	return _media_sequence.play_boot()


func play_menu_music() -> void:
	_media_sequence.play_menu_music()


func play_intro() -> bool:
	return _media_sequence.play_intro()


func set_main_status(message: String) -> void:
	_main.get_node("Center/Panel/Contents/Status").text = message


func set_inventory(entries: Array[Dictionary]) -> void:
	_inventory.set_entries(entries)


func set_save_slots(entries: Array[Dictionary]) -> void:
	_save.set_entries(entries)
	_load.set_entries(entries)


func set_settings(music: float, sound: float, speech: float, cinematic: float, wall_damage: bool, master: float = 255.0) -> void:
	_settings.get_node("Center/ContentCenter/Panel/Contents/MasterRow/MasterVolume").set_value_no_signal(master)
	_settings.get_node("Center/ContentCenter/Panel/Contents/MusicRow/MusicVolume").set_value_no_signal(music)
	_settings.get_node("Center/ContentCenter/Panel/Contents/SoundRow/SoundVolume").set_value_no_signal(sound)
	_settings.get_node("Center/ContentCenter/Panel/Contents/SpeechRow/SpeechVolume").set_value_no_signal(speech)
	_settings.get_node("Center/ContentCenter/Panel/Contents/CinematicRow/CinematicVolume").set_value_no_signal(cinematic)
	_settings.get_node("Center/ContentCenter/Panel/Contents/WallCollisionDamage").set_pressed_no_signal(wall_damage)


func set_original_data_path(path: String) -> void:
	_settings.call("set_original_data_path", path)


func set_import_progress(message: String, fraction: float, busy: bool) -> void:
	_settings.call("set_import_progress", message, fraction, busy)


func set_dialogue(speaker: String, text: String) -> void:
	_dialogue.get_node("Bottom/Panel/Contents/Speaker").text = speaker
	_dialogue.get_node("Bottom/Panel/Contents/Text").text = text
	show_panel(&"dialogue")


func set_hud(life: int, magic: int, gold: int) -> void:
	_hud.get_node("Top/Stats/Life").text = "Life: %d" % life
	_hud.get_node("Top/Stats/Magic").text = "Magic: %d" % magic
	_hud.get_node("Top/Stats/Gold").text = "Gold: %d" % gold


func set_notification(message: String) -> void:
	_hud.get_node("Notice").text = message


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"lba_inventory") and _current == &"hud" and not _media_sequence.is_active():
		show_panel(&"inventory")
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"ui_cancel") and not event.is_action_pressed(&"lba_pause"):
		return
	if _media_sequence.is_active():
		_media_sequence.skip()
		get_viewport().set_input_as_handled()
		return
	if _current == &"hud":
		command_requested.emit(&"pause_game", null)
	elif _current == &"pause":
		command_requested.emit(&"resume_game", null)
	elif _current != &"main":
		show_panel(_previous if _previous != _current else &"hud")
	else:
		return
	get_viewport().set_input_as_handled()


func _on_action(action: StringName, value: Variant, _source: StringName) -> void:
	match action:
		&"open_settings": show_panel(&"settings")
		&"open_inventory": show_panel(&"inventory")
		&"open_save": show_panel(&"save")
		&"open_load": show_panel(&"load")
		&"close": show_panel(_previous if _previous != _current else &"hud")
		&"resume": command_requested.emit(&"resume_game", value)
		&"quit_to_main": command_requested.emit(action, value)
		&"master_volume", &"music_volume", &"sound_volume", &"speech_volume", &"cinematic_volume", &"wall_collision_damage":
			setting_changed.emit(action, value)
		_:
			command_requested.emit(action, value)
