class_name GameUI
extends CanvasLayer

const ActionPanel = preload("res://scripts/ui/game_action_panel.gd")
const HQR = preload("res://scripts/import/hqr_reader.gd")
const PREVIEWS = preload("res://scripts/ui/lba_model_previews.gd")

signal command_requested(command: StringName, payload: Variant)
signal setting_changed(setting: StringName, value: Variant)
signal sequence_finished(kind: StringName)
signal media_error(message: String)
signal gameplay_turn_block_changed(blocked: bool)

@onready var _main: ActionPanel = $Frame/MainMenu
@onready var _pause: ActionPanel = $Frame/PauseMenu
@onready var _settings: ActionPanel = $Frame/SettingsMenu
@onready var _dialogue: ActionPanel = $Frame/Dialogue
@onready var _inventory: ActionPanel = $Frame/Inventory
@onready var _mode: ActionPanel = $Frame/ModeMenu
@onready var _save: ActionPanel = $Frame/SaveScreen
@onready var _load: ActionPanel = $Frame/LoadScreen
@onready var _hud: Control = $Frame/HUD
@onready var _backdrop: TextureRect = $Frame/MenuBackdrop
@onready var _media_sequence: LBAMediaSequence = $Frame/MediaSequence

var _panels: Dictionary = {}
var _current: StringName = &"main"
var _previous: StringName = &"main"
var _world_active := false
var _dialogue_pages: PackedStringArray = PackedStringArray()
var _dialogue_page := 0
var _mode_buttons: Array[Button] = []
var _mode_index := 0
var _native_mode := 0
var _held_ctrl := 0
var _held_mode_directions := {}
var _last_mode_step_usec := 0
var _previews: Node
var _inventory_flags := PackedInt32Array()
var _player_preview_body := -1
var _notice_revision := 0
var _save_slot_names: Dictionary = {}
signal dialogue_finished



func _ready() -> void:
	_previews = PREVIEWS.new()
	add_child(_previews)
	_panels = {
		&"main": _main, &"pause": _pause, &"settings": _settings,
		&"dialogue": _dialogue, &"inventory": _inventory, &"mode": _mode,
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
	_install_dialogue_font()
	var save_list := _save.get_node("Center/Panel/Contents/Entries") as ItemList
	save_list.item_selected.connect(_on_save_slot_selected)
	save_list.item_activated.connect(_on_save_slot_activated)
	save_list.item_clicked.connect(func(index: int, _position: Vector2, _button: int) -> void:
		_on_save_slot_activated(index))
	var save_name := _save.get_node("Center/Panel/Contents/SaveName") as LineEdit
	save_name.text_submitted.connect(func(_name: String) -> void: _submit_save())
	(_dialogue.get_node("Bottom/Panel/Contents/Actions") as Control).hide()
	for button in _mode.find_children("*", "Button", true, false):
		var mode_button := button as Button
		_mode_buttons.append(mode_button)
		var index := _mode_buttons.size() - 1
		mode_button.mouse_entered.connect(_select_mode.bind(index))
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
	if _previews != null:
		var purpose := ""
		match panel_id:
			&"inventory": purpose = "inventory"
			&"mode": purpose = "mode"
			&"dialogue": purpose = "pickup"
		_previews.set_active_purpose(purpose)
	# Main-menu artwork belongs to the title flow, never to in-game overlays.
	_backdrop.visible = not _world_active and panel_id != &"hud"
	if panel_id == &"save":
		_save.get_node("Center/Panel/Contents/Entries").call_deferred("grab_focus")
	elif panel_id == &"mode":
		call_deferred("_focus_mode_index")
	elif panel_id != &"hud":
		(_panels[panel_id] as ActionPanel).call_deferred("focus_first")


func show_hud() -> void:
	show_panel(&"hud")


func is_media_active() -> bool:
	return _media_sequence.is_active()


func skip_media() -> void:
	_media_sequence.skip()


func set_world_active(active: bool) -> void:
	_world_active = active
	if not active:
		_held_ctrl = 0
		_held_mode_directions.clear()
		gameplay_turn_block_changed.emit(false)
	_backdrop.visible = not _world_active and _current != &"hud"


func configure_media(cache_path: String, data_path: String) -> bool:
	if not _media_sequence.configure(cache_path, data_path):
		return false
	_backdrop.texture = LBAMediaSequence.load_resource_texture(data_path.path_join("ress.hqr"), 14, 0)
	var palette_entry: Dictionary = HQR.read_entry(data_path.path_join("ress.hqr"), 0)
	if palette_entry.get("ok", false):
		var palette: PackedByteArray = palette_entry["data"]
		if palette.size() >= 80 * 3:
			var image := Image.create(16, 1, false, Image.FORMAT_RGBA8)
			for index in range(16):
				var offset := (64 + index) * 3
				image.set_pixel(index, 0, Color8(palette[offset], palette[offset + 1],
					palette[offset + 2]))
			var texture := ImageTexture.create_from_image(image)
			for button in _main.find_children("*", "Button", true, false):
				if button is LBAPlasmaButton:
					button.set_original_palette(texture)
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


func configure_game_models(data_dir: String) -> void:
	if _previews.data_dir != data_dir:
		_previews.configure(data_dir)
		_inventory_flags = PackedInt32Array()
		_player_preview_body = -1


func set_inventory_state(flags: PackedInt32Array) -> void:
	if flags == _inventory_flags or flags.size() != 28:
		return
	_inventory_flags = flags.duplicate()
	var entries: Array[Dictionary] = []
	for slot in range(28):
		var owned := flags[slot] != 0
		entries.append({"id": slot, "label": "", "enabled": owned,
			"icon": _previews.model_texture("inventory_model", slot, "inventory") if owned else null})
	set_inventory(entries)


func set_player_preview(body_id: int, pose_groups: PackedInt32Array) -> void:
	if body_id < 0:
		return
	if body_id != _player_preview_body:
		_player_preview_body = body_id
		(_mode.get_node("Center/Panel/Contents/Twinsen") as TextureRect).texture = \
			_previews.model_texture("body", body_id, "mode", Vector2i(180, 145))
	if _current == &"mode":
		_previews.update_player_pose(body_id, pose_groups)


func set_save_slots(entries: Array[Dictionary]) -> void:
	_save_slot_names.clear()
	for entry in entries:
		_save_slot_names[int(entry.get("id", -1))] = str(entry.get("name", ""))
	_save.set_entries(entries)
	_load.set_entries(entries)
	var save_list := _save.get_node("Center/Panel/Contents/Entries") as ItemList
	if save_list.item_count > 0:
		save_list.select(0)
		_on_save_slot_selected(0)


func _on_save_slot_selected(index: int) -> void:
	var save_name := _save.get_node("Center/Panel/Contents/SaveName") as LineEdit
	var slot := _save.get_node("Center/Panel/Contents/Entries") as ItemList
	if index < 0 or index >= slot.item_count:
		return
	save_name.text = str(_save_slot_names.get(index, ""))


func _on_save_slot_activated(index: int) -> void:
	_on_save_slot_selected(index)
	var save_name := _save.get_node("Center/Panel/Contents/SaveName") as LineEdit
	save_name.grab_focus()
	save_name.select_all()


func _submit_save() -> void:
	var list := _save.get_node("Center/Panel/Contents/Entries") as ItemList
	var selected := list.get_selected_items()
	if selected.is_empty():
		return
	var slot := selected[0]
	var name := (_save.get_node("Center/Panel/Contents/SaveName") as LineEdit).text.strip_edges()
	command_requested.emit(&"save", {"slot": slot, "name": name})


func set_settings(music: float, sound: float, speech: float, cinematic: float, wall_damage: bool, master: float = 255.0) -> void:
	_settings.get_node("Center/ContentCenter/Panel/Contents/MasterRow/MasterVolume").set_value_no_signal(master)
	_settings.get_node("Center/ContentCenter/Panel/Contents/MusicRow/MusicVolume").set_value_no_signal(music)
	_settings.get_node("Center/ContentCenter/Panel/Contents/SoundRow/SoundVolume").set_value_no_signal(sound)
	_settings.get_node("Center/ContentCenter/Panel/Contents/SpeechRow/SpeechVolume").set_value_no_signal(speech)
	_settings.get_node("Center/ContentCenter/Panel/Contents/CinematicRow/CinematicVolume").set_value_no_signal(cinematic)
	_settings.get_node("Center/ContentCenter/Panel/Contents/WallCollisionDamage").set_pressed_no_signal(wall_damage)


func set_original_data_path(path: String) -> void:
	_settings.call("set_original_data_path", path)


func set_media_cache_path(path: String) -> void:
	_settings.call("set_media_cache_path", path)


func set_import_progress(message: String, fraction: float, busy: bool) -> void:
	_settings.call("set_import_progress", message, fraction, busy)


func _install_dialogue_font() -> void:
	# Typeface is a modern, scalable replacement; do not use the LBA bitmap font.
	# Bundle an OFL-licensed font into assets/fonts/ for portable builds later.
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Zilla Slab", "Roboto Slab", "DejaVu Serif"])
	font.font_weight = 600
	var body := _dialogue.get_node("Bottom/Panel/Contents/Text") as RichTextLabel
	body.add_theme_font_override("normal_font", font)
	body.add_theme_font_size_override("normal_font_size", 26)
	body.add_theme_color_override("default_color", Color(0.72, 0.91, 0.97))
	var speaker := _dialogue.get_node("Bottom/Panel/Contents/Speaker") as Label
	speaker.add_theme_font_override("font", font)
	speaker.add_theme_font_size_override("font_size", 20)


func set_dialogue(speaker: String, text: String, found_item: int = -1) -> void:
	var item_preview := _dialogue.get_node("ItemPreview") as TextureRect
	item_preview.visible = found_item >= 0
	item_preview.texture = _previews.model_texture("inventory_model", found_item,
		"pickup", Vector2i(220, 220)) if found_item >= 0 else null
	var speaker_label := _dialogue.get_node("Bottom/Panel/Contents/Speaker") as Label
	speaker_label.text = speaker
	speaker_label.visible = not speaker.is_empty()
	_dialogue_pages = _paginate_dialogue(text)
	_dialogue_page = 0
	_show_dialogue_page()
	show_panel(&"dialogue")


func _paginate_dialogue(text: String) -> PackedStringArray:
	# MESSAGE.C interprets @ as an explicit line break and @P as a page break.
	# Measure actual Godot font glyphs, not a fixed character count: the new
	# proportional font is wider than the original bitmap glyphs.
	var body := _dialogue.get_node("Bottom/Panel/Contents/Text") as RichTextLabel
	var font: Font = body.get_theme_font("normal_font")
	var font_size: int = body.get_theme_font_size("normal_font_size")
	var max_width := 570.0
	var pages := PackedStringArray()
	var lines := PackedStringArray()
	var current := ""
	var normalized := text.replace("\r", "").replace("@P", "\n\f\n").replace("@", "\n")
	# Original 0x01 also terminates a formatted line.
	normalized = normalized.replace(String.chr(1), "\n")
	for paragraph in normalized.split("\n", true):
		if paragraph.contains("\f"):
			if not current.is_empty():
				lines.append(current)
				current = ""
			pages.append("\n".join(lines))
			lines.clear()
			continue
		if paragraph.is_empty():
			if not current.is_empty():
				lines.append(current)
				current = ""
			if lines.size() >= 3:
				pages.append("\n".join(lines))
				lines.clear()
			continue
		for word in paragraph.split(" ", false):
			var candidate := word if current.is_empty() else current + " " + word
			if not current.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
				lines.append(current)
				current = word
				if lines.size() >= 3:
					pages.append("\n".join(lines))
					lines.clear()
			else:
				current = candidate
		if not current.is_empty():
			lines.append(current)
			current = ""
		if lines.size() >= 3:
			pages.append("\n".join(lines))
			lines.clear()
	if not current.is_empty():
		lines.append(current)
	if not lines.is_empty():
		pages.append("\n".join(lines))
	if pages.is_empty():
		pages.append("")
	return pages

func _show_dialogue_page() -> void:
	(_dialogue.get_node("Bottom/Panel/Contents/Text") as RichTextLabel).text = _dialogue_pages[_dialogue_page]
	(_dialogue.get_node("Bottom/Panel/Contents/PageChevron") as Label).visible = _dialogue_page + 1 < _dialogue_pages.size()


func _advance_dialogue(abort: bool = false) -> void:
	if not abort and _dialogue_page + 1 < _dialogue_pages.size():
		_dialogue_page += 1
		_show_dialogue_page()
	else:
		dialogue_finished.emit()
		show_hud()


func set_gameplay_status(status: Dictionary) -> void:
	if status.is_empty():
		return
	_native_mode = clampi(int(status.get("behavior", 0)), 0, 3)
	if _current != &"mode":
		_mode_index = _native_mode
	var base := "Center/Panel/Contents/Status/"
	_mode.get_node(base + "Vitals/Health").text = "Health: %d" % int(status.get("health", 0))
	(_mode.get_node(base + "Vitals/HealthBar") as ProgressBar).value = int(status.get("health", 0))
	_mode.get_node(base + "Vitals/Magic").text = "Magic level: %d  Energy: %d" % [
		int(status.get("magic_level", 0)), int(status.get("magic_energy", 0))]
	var magic_bar := _mode.get_node(base + "Vitals/MagicBar") as ProgressBar
	magic_bar.max_value = maxi(20, int(status.get("magic_level", 0)) * 20)
	magic_bar.value = int(status.get("magic_energy", 0))
	_mode.get_node(base + "Items/Clovers").text = "Clovers: %d / %d" % [
		int(status.get("clovers", 0)), int(status.get("clover_boxes", 0))]
	_mode.get_node(base + "Items/Keys").text = "Keys: %d" % int(status.get("keys", 0))
	_mode.get_node(base + "Items/Money").text = "Money: %d" % int(status.get("money", 0))


func set_notification(message: String) -> void:
	_notice_revision += 1
	var revision := _notice_revision
	_hud.get_node("Notice").text = message
	if not message.is_empty():
		get_tree().create_timer(2.5).timeout.connect(func() -> void:
			if is_inside_tree() and _notice_revision == revision:
				_hud.get_node("Notice").text = "")


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null:
		return
	if key.keycode == KEY_CTRL or key.physical_keycode == KEY_CTRL:
		var side := 2 if key.location == 2 else 1
		if key.pressed and not key.echo:
			var was_released := _held_ctrl == 0
			_held_ctrl |= side
			if was_released and _current == &"hud" and _world_active:
				_mode_index = _native_mode
				show_panel(&"mode")
				gameplay_turn_block_changed.emit(true)
				command_requested.emit(&"pause_simulation", null)
		elif not key.pressed:
			_held_ctrl &= ~side
			if _held_ctrl == 0 and _current == &"mode":
				show_hud()
				command_requested.emit(&"set_behavior", _mode_index)
				gameplay_turn_block_changed.emit(not _held_mode_directions.is_empty())
		get_viewport().set_input_as_handled()
		return
	var direction := _mode_direction(key)
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if direction != 0 and (_current == &"mode" or _held_mode_directions.has(code)):
		if key.pressed:
			var was_held := _held_mode_directions.has(code)
			_held_mode_directions[code] = true
			var now := Time.get_ticks_usec()
			if _current == &"mode" and (not was_held or key.echo and now - _last_mode_step_usec >= 120000):
				_select_mode(posmod(_mode_index + direction, 4))
				_last_mode_step_usec = now
		else:
			_held_mode_directions.erase(code)
			if _current != &"mode" and _held_mode_directions.is_empty():
				gameplay_turn_block_changed.emit(false)
		if _current == &"mode":
			get_viewport().set_input_as_handled()
		return
	if not key.pressed or key.echo:
		return
	if _current == &"dialogue":
		if key.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] or key.physical_keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
			_advance_dialogue(key.keycode == KEY_ESCAPE)
			get_viewport().set_input_as_handled()
		return
	# Direct key handling before focused controls consume Space/ESC.
	# No on-screen Skip button is needed.
	if _media_sequence.is_active():
		if key.keycode in [KEY_ESCAPE, KEY_SPACE] or key.physical_keycode in [KEY_ESCAPE, KEY_SPACE]:
			_media_sequence.skip()
			get_viewport().set_input_as_handled()
		return


func _mode_direction(key: InputEventKey) -> int:
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_LEFT or code == KEY_A:
		return -1
	if code == KEY_RIGHT or code == KEY_D:
		return 1
	return 0


func _select_mode(index: int) -> void:
	if _current != &"mode":
		return
	_mode_index = index
	_focus_mode_index()


func _focus_mode_index() -> void:
	if _current == &"mode" and _mode_index >= 0 and _mode_index < _mode_buttons.size():
		_mode_buttons[_mode_index].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _media_sequence.is_active():
		return
	if _current == &"mode":
		return
	if event.is_action_pressed(&"lba_inventory") and _current == &"hud":
		show_panel(&"inventory")
		command_requested.emit(&"pause_simulation", null)
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"ui_cancel") and not event.is_action_pressed(&"lba_pause"):
		return
	if _current == &"hud":
		command_requested.emit(&"pause_game", null)
	elif _current == &"pause" or (_current == &"inventory" and _previous == &"hud"):
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
		&"open_save":
			show_panel(&"save")
			command_requested.emit(action, null)
		&"open_load":
			show_panel(&"load")
			command_requested.emit(action, null)
		&"save": _submit_save()
		&"close":
			if _current in [&"inventory", &"mode"] and _previous == &"hud":
				command_requested.emit(&"resume_game", null)
			else:
				show_panel(_previous if _previous != _current else &"hud")
		&"resume": command_requested.emit(&"resume_game", value)
		&"quit_to_main": command_requested.emit(action, value)
		&"master_volume", &"music_volume", &"sound_volume", &"speech_volume", &"cinematic_volume", &"wall_collision_damage":
			setting_changed.emit(action, value)
		_:
			command_requested.emit(action, value)
