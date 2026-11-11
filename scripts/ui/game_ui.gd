class_name GameUI
extends CanvasLayer

const ActionPanel = preload("res://scripts/ui/game_action_panel.gd")
const HQR = preload("res://scripts/import/hqr_reader.gd")
const PREVIEWS = preload("res://scripts/ui/lba_model_previews.gd")
const LANG := preload("res://scripts/ui/lba_languages.gd")
const TEXT_HQR := preload("res://scripts/ui/lba_text_hqr.gd")

signal command_requested(command: StringName, payload: Variant)
signal setting_changed(setting: StringName, value: Variant)
signal sequence_finished(kind: StringName)
signal media_error(message: String)
signal gameplay_turn_block_changed(blocked: bool)

@onready var _main: ActionPanel = $Frame/MainMenu
@onready var _pause: ActionPanel = $Frame/PauseMenu
@onready var _settings: ActionPanel = $Frame/SettingsMenu
# Assigned in the GameUI scene Inspector. Reparenting dialogue controls
# no longer requires updating a string path in this script.
@export_group("Dialogue UI")
@export var dialogue_panel: LBADialoguePanel

@onready var _dialogue: LBADialoguePanel = dialogue_panel
@onready var _inventory: LBAInventoryPanel = $Frame/Inventory
@onready var _mode: ActionPanel = $Frame/ModeMenu
@onready var _save: ActionPanel = $Frame/SaveScreen
@onready var _load: ActionPanel = $Frame/LoadScreen
@onready var _hud: Control = $Frame/HUD
@onready var _backdrop: TextureRect = $Frame/MenuBackdrop
@onready var _media_sequence: LBAMediaSequence = $Frame/MediaSequence

@onready var _holomap: LBAHolomap = $Frame/Holomap
@onready var _dialogue_choices: LBADialogueChoices = $Frame/DialogueChoices
@onready var _first_run: LBAFirstRunSetup = $Frame/FirstRunSetup

var _panels: Dictionary = {}
var _current: StringName = &"main"
var _previous: StringName = &"main"
var _world_active := false
var _dialogue_pages: PackedStringArray = PackedStringArray()
var _dialogue_page := 0
var _dialogue_reveal_progress := 0.0
var _mode_buttons: Array[Button] = []
var _mode_index := 0
var _native_mode := 0
var _held_ctrl := 0
var _held_mode_directions := {}
var _last_mode_step_usec := 0
var _previews: Node
var _inventory_flags := PackedInt32Array()
var _inventory_text_bank: Dictionary = {}
var _original_text_directory: String = ""
var _player_preview_body := -1
var _notice_revision := 0
var _save_slot_names: Dictionary = {}
var _scene_loading: Control
var _scene_loading_label: Label
var _scene_loading_bar: ProgressBar
var _text_language := 0
signal holomap_opened
signal dialogue_choice_selected(index: int)
signal dialogue_finished



func _ready() -> void:
	_previews = PREVIEWS.new()
	add_child(_previews)
	_panels = {
		&"main": _main, &"pause": _pause, &"settings": _settings,
		&"dialogue": _dialogue, &"inventory": _inventory, &"mode": _mode,
		&"save": _save, &"load": _load,
		&"holomap": _holomap, &"choices": _dialogue_choices, &"setup": _first_run,
	}
	_validate_dialogue_refs()
	for panel_id in _panels:
		var panel: Control = _panels[panel_id]
		if panel == null:
			push_warning("GameUI: panel '%s' is not assigned." % panel_id)
			continue
		if panel.has_signal("action_requested"):
			panel.connect("action_requested", Callable(self, "_on_action").bind(panel_id))
	_inventory.selected_item_changed.connect(func(slot: int) -> void:
		_previews.set_selected_preview("inventory", slot))
	_holomap.close_requested.connect(_close_holomap)
	_holomap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialogue_choices.option_chosen.connect(func(index: int) -> void:
		dialogue_choice_selected.emit(index)
		show_hud())
	_first_run.import_settings_requested.connect(func() -> void: show_panel(&"settings"))
	_media_sequence.sequence_finished.connect(func(kind: StringName) -> void:
		if kind == &"boot" and _current == &"main":
			show_panel(&"main")
		sequence_finished.emit(kind))
	_media_sequence.media_error.connect(func(message: String) -> void: media_error.emit(message))
	_create_scene_loading()
	var save_list := _save.get_node("Center/Panel/Contents/Entries") as ItemList
	save_list.item_selected.connect(_on_save_slot_selected)
	save_list.item_activated.connect(_on_save_slot_activated)
	save_list.item_clicked.connect(func(index: int, _position: Vector2, _button: int) -> void:
		_on_save_slot_activated(index))
	var save_name := _save.get_node("Center/Panel/Contents/SaveName") as LineEdit
	save_name.text_submitted.connect(func(_name: String) -> void: _submit_save())
	for button in _mode.get_node("Center/Panel/Upper/Contents/Modes").get_children():
		var mode_button := button as Button
		_mode_buttons.append(mode_button)
		mode_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mode_button.focus_mode = Control.FOCUS_NONE
	_apply_ui_language(LANG.get_text_index())
	show_panel(&"main")


func _apply_ui_language(index: int) -> void:
	_text_language = clampi(index, 0, 4)
	var names := {
		"Back": ["Back", "Retour", "Zurück", "Atrás", "Indietro"],
		"Settings": ["Settings", "Options", "Einstellungen", "Opciones", "Impostazioni"],
		"Options": ["Options", "Options", "Optionen", "Opciones", "Opzioni"],
		"Quit to Menu": ["Quit to Menu", "Menu principal", "Zum Hauptmenü", "Al menú", "Menu principale"],
		"Save game": ["Save game", "Sauvegarder", "Spiel speichern", "Guardar partida", "Salva partita"],
		"Load game": ["Load game", "Charger", "Spiel laden", "Cargar partida", "Carica partita"],
		"Resume": ["Resume", "Reprendre", "Fortsetzen", "Continuar", "Riprendi"],
		"Paused": ["Paused", "Pause", "Pause", "Pausa", "Pausa"],
		"Main menu": ["Main menu", "Menu principal", "Hauptmenü", "Menú principal", "Menu principale"],
		"Inventory": ["Inventory", "Inventaire", "Inventar", "Inventario", "Inventario"],
		"Save": ["Save", "Sauver", "Speichern", "Guardar", "Salva"],
		"Load": ["Load", "Charger", "Laden", "Cargar", "Carica"],
		"Use": ["Use", "Utiliser", "Benutzen", "Usar", "Usa"],
		"Continue": ["Continue", "Continuer", "Weiter", "Continuar", "Continua"],
		"Skip": ["Skip", "Passer", "Überspringen", "Omitir", "Salta"],
		"Language": ["Language", "Langue", "Sprache", "Idioma", "Lingua"],
		"Written": ["Written", "Écrit", "Text", "Texto", "Testo"],
		"Spoken": ["Spoken", "Voix", "Sprachausgabe", "Voz", "Voce"],
		"Master": ["Master", "Général", "Gesamt", "General", "Generale"],
		"Music": ["Music", "Musique", "Musik", "Música", "Musica"],
		"Speech": ["Speech", "Voix", "Sprache", "Voces", "Voci"],
		"Sound effects": ["Sound effects", "Effets sonores", "Soundeffekte", "Efectos de sonido", "Effetti sonori"],
		"Cinematics": ["Cinematics", "Cinématiques", "Filmsequenzen", "Cinemáticas", "Filmati"],
		"Wall Collision Damage": ["Wall Collision Damage", "Dégâts contre les murs", "Schaden durch Wände", "Daño por choque", "Danni contro i muri"],
		"Import audio and movies": ["Import audio and movies", "Importer sons et vidéos", "Audio und Videos importieren", "Importar audio y vídeos", "Importa audio e filmati"],
		"Browse…": ["Browse…", "Parcourir…", "Durchsuchen…", "Examinar…", "Sfoglia…"],
		"Save name": ["Save name", "Nom de sauvegarde", "Spielstandname", "Nombre guardado", "Nome salvataggio"],
	}
	for panel in [_main, _pause, _settings, _dialogue, _inventory, _mode, _save, _load]:
		if panel == null:
			continue
		for node in panel.find_children("*", "Control", true, false):
			if not (node is Label or node is BaseButton):
				continue
			if not node.has_meta("lba_source_label"):
				node.set_meta("lba_source_label", str(node.get("caption") if node is LBAPlasmaButton else node.get("text")))
			var english := str(node.get_meta("lba_source_label"))
			if names.has(english):
				if node is LBAPlasmaButton:
					node.set("caption", (names[english] as Array)[_text_language])
				else:
					node.set("text", (names[english] as Array)[_text_language])


func show_panel(panel_id: StringName) -> void:
	if panel_id != &"hud" and not _panels.has(panel_id):
		push_warning("Unknown game UI panel: %s" % panel_id)
		return
	if panel_id == &"dialogue" and not is_instance_valid(_dialogue):
		push_warning("GameUI: dialogue_panel is unassigned in the Inspector.")
		return
	if _current != panel_id:
		_previous = _current
	_current = panel_id
	for id in _panels:
		var panel := _panels[id] as Control
		if panel != null:
			panel.visible = id == panel_id
	_hud.visible = panel_id == &"hud"
	if _previews != null:
		var purpose := ""
		match panel_id:
			&"inventory": purpose = "inventory"
			&"mode": purpose = "mode"
			&"dialogue": purpose = "pickup"
		_previews.set_active_purpose(purpose)
	if panel_id == &"inventory":
		# An imported or previously selected game can reach Inventory before
		# the text bank was loaded. Recheck when entering the panel.
		if _inventory_text_bank.is_empty():
			_reload_inventory_texts()
		# Inventory flags may arrive before or after model configuration. Rebuild
		# the entries on entry, even when the flags have not changed this frame.
		_refresh_inventory_entries()
		_previews.set_selected_preview("inventory", _inventory.current_slot())
	elif panel_id == &"mode":
		_update_mode_selection()
	# Main-menu artwork belongs to the title flow, never to in-game overlays.
	_backdrop.visible = not _world_active and panel_id != &"hud"
	if panel_id == &"save":
		_save.get_node("Center/Panel/Contents/Entries").call_deferred("grab_focus")
	elif panel_id == &"load":
		_focus_load_slots.call_deferred()
	elif panel_id == &"mode":
		call_deferred("_focus_mode_index")
	elif panel_id != &"hud":
		var focused_panel := _panels.get(panel_id) as Control
		if focused_panel != null and focused_panel.has_method("focus_first"):
			focused_panel.call_deferred("focus_first")


func show_holomap_route(_points: PackedVector2Array, _travel_seconds: float = 0.0) -> void:
	# Compatibility shim: map coordinates alone do not identify an original
	# trajectory. Never render every route as a substitute.
	push_warning("Holomap: travel needs an original trajectory ID")


func show_holomap_travel(data_dir: String, state: PackedInt32Array, trajectory_id: int) -> void:
	_holomap.configure_travel(data_dir, state, trajectory_id)
	show_panel(&"holomap")


func configure_holomap(data_dir: String, native_state: PackedInt32Array,
		player_body: int = -1, player_pose: PackedInt32Array = PackedInt32Array()) -> void:
	_holomap.set_player_appearance(player_body, player_pose)
	_holomap.configure_inventory(data_dir, native_state)


func _open_holomap() -> void:
	# Inventory action is deferred; never allow an old activation to reopen the
	# map after Escape has already closed the inventory.
	if _current != &"inventory":
		return
	show_panel(&"holomap")
	holomap_opened.emit()


func _close_holomap() -> void:
	if _current == &"holomap":
		show_panel(&"hud" if _holomap.mode == LBAHolomap.Mode.TRAVEL else &"inventory")


func show_dialogue_choices(prompt: String, choices: PackedStringArray) -> void:
	_dialogue_choices.set_choices(prompt, choices)
	show_panel(&"choices")


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
	_original_text_directory = data_path
	_reload_inventory_texts()
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


func stop_menu_music() -> void:
	_media_sequence.stop_menu_music()


func set_languages(text_index: int, voice_index: int) -> void:
	_media_sequence.set_languages(text_index, voice_index)
	_apply_ui_language(text_index)
	_reload_inventory_texts()


func play_intro() -> bool:
	if _media_sequence.is_active() or not _media_sequence.play_intro():
		return false
	# Don't leave New Game focused behind the illustrated sequence. Otherwise
	# Enter is delivered to the hidden title button and starts a second game.
	for panel_id in _panels:
		var panel: Control = _panels[panel_id] as Control
		if panel != null:
			panel.visible = false
	_hud.visible = false
	_backdrop.visible = false
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	return true


func set_main_status(message: String) -> void:
	_main.get_node("Center/Panel/Contents/Status").text = message


func set_inventory(entries: Array[Dictionary]) -> void:
	_inventory.set_entries(entries)


func configure_game_models(data_dir: String) -> void:
	if _previews.data_dir != data_dir:
		_previews.configure(data_dir)
		_inventory_flags = PackedInt32Array()
		_player_preview_body = -1


func _reload_inventory_texts() -> void:
	_inventory_text_bank.clear()
	var path := ""
	if not _original_text_directory.is_empty():
		path = LANG.locate_text(_original_text_directory)
	if not path.is_empty():
		_inventory_text_bank = TEXT_HQR.load_bank(path, TEXT_HQR.GAM_BANK, _text_language)
		if _inventory_text_bank.is_empty() and _text_language != 0:
			push_warning("Inventory: GAM text bank missing for language %d; trying English." % _text_language)
			_inventory_text_bank = TEXT_HQR.load_bank(path, TEXT_HQR.GAM_BANK, 0)
	if _inventory_text_bank.is_empty():
		push_warning("Inventory: original GAM text bank not available at %s (data dir %s)." % [path, _original_text_directory])
	if _inventory_flags.size() == 28:
		_refresh_inventory_entries()


func set_inventory_state(flags: PackedInt32Array) -> void:
	if flags == _inventory_flags or flags.size() != 28:
		return
	_inventory_flags = flags.duplicate()
	_refresh_inventory_entries()


func _refresh_inventory_entries() -> void:
	if _inventory_flags.size() != 28:
		return
	var entries: Array[Dictionary] = []
	var unavailable: String = str((_inventory_text_bank.get(128, {}) as Dictionary).get("text", ""))
	if unavailable.is_empty():
		unavailable = "Item not available"
	for slot in range(28):
		var owned: bool = _inventory_flags[slot] != 0
		# The original GAMEMENU.C displays text ID 100 + InvSelect,
		# and ID 128 when that item hasn't been acquired.
		var entry: Dictionary = _inventory_text_bank.get(100 + slot, {})
		var description: String = str(entry.get("text", "")) if owned else unavailable
		if owned and description.is_empty():
			# Do not leave the description box blank: surface missing source
			# data explicitly instead of silently claiming the item is blank.
			description = "Original item description unavailable (GAM %d)" % (100 + slot)
			if slot == 0:
				push_warning("Inventory: missing original Holomap description, GAM 100")
		entries.append({"id": slot, "label": description, "description": description,
			"enabled": owned, "count": 0,
			"icon": _previews.model_texture("inventory_model", slot, "inventory", Vector2i(110, 110)) if owned else null})
	set_inventory(entries)
	if _current == &"inventory":
		_previews.set_selected_preview("inventory", _inventory.current_slot())


func set_player_preview(body_id: int, pose_groups: PackedInt32Array) -> void:
	if body_id < 0:
		return
	if body_id != _player_preview_body:
		_player_preview_body = body_id
		for index in range(4):
			var preview := _mode_buttons[index].get_node("Preview") as TextureRect
			preview.texture = _previews.model_texture("body", body_id, "mode%d" % index, Vector2i(256, 256))
	if _current == &"mode":
		_previews.update_player_pose(body_id, pose_groups)


func set_save_slots(entries: Array[Dictionary]) -> void:
	_save_slot_names.clear()
	for entry in entries:
		_save_slot_names[int(entry.get("id", -1))] = str(entry.get("name", ""))
	_save.set_entries(entries)
	_load.set_entries(entries)
	if _current == &"load":
		_focus_load_slots.call_deferred()
	var save_list := _save.get_node("Center/Panel/Contents/Entries") as ItemList
	if save_list.item_count > 0:
		save_list.select(0)
		_on_save_slot_selected(0)


func _focus_load_slots() -> void:
	var slots: ItemList = _load.get_node("Center/Panel/Contents/Entries") as ItemList
	if slots.item_count == 0:
		(_load.get_node("Center/Panel/Contents/Actions/Close") as Button).grab_focus()
		return
	var selected: PackedInt32Array = slots.get_selected_items()
	if selected.is_empty():
		for i in range(slots.item_count):
			if slots.is_item_selectable(i) and not slots.is_item_disabled(i):
				slots.select(i)
				break
	slots.grab_focus()
	slots.ensure_current_is_visible()


func _load_keyboard(key: InputEventKey) -> bool:
	# Mouse is deliberately not an activation path for this menu.
	var slots: ItemList = _load.get_node("Center/Panel/Contents/Entries") as ItemList
	var key_code: int = key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	if key_code == KEY_ESCAPE or key_code == KEY_BACKSPACE:
		show_panel(_previous if _previous != &"load" else &"main")
		return true
	if key_code == KEY_UP or key_code == KEY_DOWN:
		if slots.item_count == 0:
			return true
		var selected: PackedInt32Array = slots.get_selected_items()
		var current: int = selected[0] if not selected.is_empty() else (-1 if key_code == KEY_DOWN else 0)
		var delta: int = 1 if key_code == KEY_DOWN else -1
		for step in range(slots.item_count):
			current = posmod(current + delta, slots.item_count)
			if slots.is_item_selectable(current) and not slots.is_item_disabled(current):
				slots.select(current)
				slots.ensure_current_is_visible()
				break
		return true
	if key_code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if slots.get_selected_items().is_empty():
			_focus_load_slots()
		if not slots.get_selected_items().is_empty():
			# Existing confirmation and game-app load flow remains in charge.
			(_load.get_node("Center/Panel/Contents/Actions/Load") as Button).pressed.emit()
		return true
	return false


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


func set_settings(music: float, sound: float, speech: float, cinematic: float, wall_damage: bool, master: float = 255.0, lit_grids: bool = true) -> void:
	_settings.get_node("Center/ContentCenter/Panel/Contents/MasterRow/MasterVolume").set_value_no_signal(master)
	_settings.get_node("Center/ContentCenter/Panel/Contents/MusicRow/MusicVolume").set_value_no_signal(music)
	_settings.get_node("Center/ContentCenter/Panel/Contents/SoundRow/SoundVolume").set_value_no_signal(sound)
	_settings.get_node("Center/ContentCenter/Panel/Contents/SpeechRow/SpeechVolume").set_value_no_signal(speech)
	_settings.get_node("Center/ContentCenter/Panel/Contents/CinematicRow/CinematicVolume").set_value_no_signal(cinematic)
	_settings.get_node("Center/ContentCenter/Panel/Contents/WallCollisionDamage").set_pressed_no_signal(wall_damage)
	_settings.get_node("Center/ContentCenter/Panel/Contents/GridLighting").set_pressed_no_signal(lit_grids)


func set_original_data_path(path: String) -> void:
	_settings.call("set_original_data_path", path)


func set_media_cache_path(path: String) -> void:
	_settings.call("set_media_cache_path", path)


func set_soundfont_path(path: String) -> void:
	_settings.call("set_soundfont_path", path)


func set_import_progress(message: String, fraction: float, busy: bool) -> void:
	_settings.call("set_import_progress", message, fraction, busy)


func _create_scene_loading() -> void:
	_scene_loading = Control.new()
	_scene_loading.name = "SceneLoading"
	_scene_loading.visible = false
	_scene_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	_scene_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Frame.add_child(_scene_loading)
	_scene_loading.move_to_front()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.04, 0.07, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_loading.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_loading.add_child(center)
	var stack := VBoxContainer.new()
	stack.custom_minimum_size = Vector2(420.0, 110.0)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 18)
	center.add_child(stack)
	var title := Label.new()
	title.text = "LITTLE BIG ADVENTURE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	stack.add_child(title)
	_scene_loading_label = Label.new()
	_scene_loading_label.text = "Preparing the first scene…"
	_scene_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_scene_loading_label)
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(360.0, 14.0)
	progress.indeterminate = true
	progress.show_percentage = false
	_scene_loading_bar = progress
	stack.add_child(progress)


func show_scene_loading(message: String = "Preparing the first scene…") -> void:
	if _scene_loading == null:
		return
	_scene_loading_label.text = message
	_scene_loading_bar.indeterminate = true
	_scene_loading_bar.show_percentage = false
	_scene_loading_bar.value = 0.0
	_scene_loading.visible = true
	_scene_loading.move_to_front()


func set_scene_loading_progress(fraction: float, message: String) -> void:
	if _scene_loading == null or not _scene_loading.visible:
		return
	_scene_loading_label.text = message
	_scene_loading_bar.indeterminate = false
	_scene_loading_bar.value = 100.0 * clampf(fraction, 0.0, 1.0)


func hide_scene_loading() -> void:
	if _scene_loading != null:
		_scene_loading.visible = false


# Typography and frame padding now come exclusively from LBAUI.tres.

func _validate_dialogue_refs() -> void:
	if not is_instance_valid(_dialogue):
		push_warning("GameUI: drag the Dialogue scene into Dialogue UI > Dialogue Panel.")
	else:
		_dialogue.validate_refs()


func _dialogue_body() -> RichTextLabel:
	if not is_instance_valid(_dialogue) or not is_instance_valid(_dialogue.body):
		return null
	return _dialogue.body


func _dialogue_chevron() -> TextureRect:
	if not is_instance_valid(_dialogue) or not is_instance_valid(_dialogue.chevron):
		return null
	return _dialogue.chevron


func _dialogue_preview() -> TextureRect:
	if not is_instance_valid(_dialogue) or not is_instance_valid(_dialogue.item_preview):
		return null
	return _dialogue.item_preview


func _process(delta: float) -> void:
	if _current != &"dialogue":
		return
	var body := _dialogue_body()
	if body == null:
		return
	if body.visible_characters >= 0 and body.visible_characters < body.get_total_character_count():
		_dialogue_reveal_progress += delta * maxf(1.0, _dialogue.reveal_characters_per_second)
		body.visible_characters = mini(int(_dialogue_reveal_progress), body.get_total_character_count())
	var more := _dialogue_chevron()
	if more != null:
		more.visible = ((body.visible_characters < 0 or body.visible_characters >= body.get_total_character_count())
			and _dialogue_page < _dialogue_pages.size() - 1)


# LBA1 messages have no on-screen speaker name. The speaking actor's ID
# still goes to the world bridge for the speech-bubble effect.
func set_dialogue(text: String, found_item: int = -1, presentation: int = 0,
		speaker_color: Color = Color(-1.0, -1.0, -1.0)) -> void:
	if _dialogue_body() == null:
		push_warning("GameUI: dialogue cannot open; Body is unassigned in the Inspector.")
		dialogue_finished.emit()
		return
	if not is_instance_valid(_dialogue):
		push_warning("GameUI: Dialogue is unassigned in the Inspector.")
		dialogue_finished.emit()
		return
	var mode := clampi(presentation, 0, 2)
	# Existing two-argument pickup callers remain compatible.
	if mode == 0 and found_item >= 0:
		mode = 2
	var texture: Texture2D = null
	if mode == 2 and found_item >= 0 and _previews != null:
		texture = _previews.model_texture("inventory_model", found_item,
			"pickup", Vector2i(220, 220)) as Texture2D
	_dialogue.set_presentation(mode, texture)
	var body_label: RichTextLabel = _dialogue_body()
	if speaker_color.r >= 0.0:
		body_label.add_theme_color_override("default_color", speaker_color)
	else:
		body_label.remove_theme_color_override("default_color")
	show_panel(&"dialogue")
	_dialogue_pages = _paginate_dialogue(text)
	_dialogue_page = 0
	_show_dialogue_page()


func _paginate_dialogue(text: String) -> PackedStringArray:
	# MESSAGE.C interprets @ as an explicit line break and @P as a page break.
	# Measure the shared themed font, not a hardcoded pixel font.
	var body := _dialogue_body()
	if body == null:
		push_warning("GameUI: dialogue text reference missing; cannot measure pages.")
		return PackedStringArray([text])
	var font: Font = body.get_theme_font("normal_font")
	var font_size: int = body.get_theme_font_size("normal_font_size")
	var max_width := maxf(120.0, body.size.x - 24.0) if body.size.x > 100.0 else 544.0
	var pages := PackedStringArray()
	var lines := PackedStringArray()
	var current := ""
	var normalized := text.replace("\r", "").replace("@P", "\n\f\n").replace("@", "\n")
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
			if not current.is_empty() and font != null and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
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
	var body := _dialogue_body()
	if body == null:
		push_warning("GameUI: dialogue text reference missing. Skipping the dialogue.")
		dialogue_finished.emit()
		show_hud()
		return
	if _dialogue_page < 0 or _dialogue_page >= _dialogue_pages.size():
		push_warning("GameUI: dialogue page index is out of range.")
		return
	body.text = _dialogue_pages[_dialogue_page]
	# Reveal already-shaped glyphs so justification does not make words jump.
	body.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	body.visible_characters = 0
	_dialogue_reveal_progress = 0.0
	var more := _dialogue_chevron()
	if more != null:
		more.visible = false


func _advance_dialogue(abort: bool = false) -> void:
	var body := _dialogue_body()
	if body == null:
		push_warning("GameUI: missing dialogue text while advancing dialogue.")
		dialogue_finished.emit()
		show_hud()
		return
	if abort:
		dialogue_finished.emit()
		show_hud()
	elif _dialogue_page + 1 < _dialogue_pages.size():
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
	var base := "Center/Panel/Status/Contents/"
	var health_bar := _mode.get_node_or_null(base + "Bars/HealthRow/HealthBar") as ProgressBar
	var magic_bar := _mode.get_node_or_null(base + "Bars/MagicRow/MagicBar") as ProgressBar
	var clovers := _mode.get_node_or_null(base + "Bars/Clovers") as HBoxContainer
	var key_count := _mode.get_node_or_null(base + "Counters/KeysRow/Keys") as Label
	var money_count := _mode.get_node_or_null(base + "Counters/MoneyRow/Money") as Label
	if health_bar != null:
		health_bar.value = int(status.get("health", 0))
	if magic_bar != null:
		magic_bar.max_value = maxi(20, int(status.get("magic_level", 0)) * 20)
		magic_bar.value = int(status.get("magic_energy", 0))
	if clovers != null:
		for index in range(clovers.get_child_count()):
			var box := clovers.get_child(index) as CheckBox
			if box != null:
				box.visible = index < maxi(0, int(status.get("clover_boxes", 0)))
				box.set_pressed_no_signal(index < int(status.get("clovers", 0)))
	if key_count != null:
		key_count.text = str(int(status.get("keys", 0)))
	if money_count != null:
		money_count.text = str(int(status.get("money", 0)))


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
	if _media_sequence.is_active():
		if key.pressed and not key.echo:
			var media_code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
			if media_code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE] and _media_sequence.is_intro_illustration():
				_media_sequence.advance_intro_page()
				get_viewport().set_input_as_handled()
			elif media_code == KEY_ESCAPE:
				_media_sequence.skip()
				get_viewport().set_input_as_handled()
		return
	# Escape belongs to the topmost UI layer. Handle it in _input before
	# focused controls, the inventory or the native host can see it.
	if key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
		match _current:
			&"dialogue":
				# Signal the native dialogue host before returning to gameplay.
				_advance_dialogue(true)
			&"holomap":
				_close_holomap()
			&"inventory":
				command_requested.emit(&"resume_game", null)
			&"hud":
				command_requested.emit(&"pause_game", null)
			&"pause":
				command_requested.emit(&"resume_game", null)
			&"main":
				return
			_:
				show_panel(_previous if _previous != _current else &"hud")
		get_viewport().set_input_as_handled()
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
	if _current == &"load" and _load_keyboard(key):
		get_viewport().set_input_as_handled()
		return
	if _current == &"dialogue":
		if key.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] or key.physical_keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
			_advance_dialogue(key.keycode == KEY_ESCAPE)
			get_viewport().set_input_as_handled()
		return
	# Direct key handling before focused controls consume Space/ESC.
	# No on-screen Skip button is needed.
	if _media_sequence.is_active():
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			_media_sequence.skip()
			get_viewport().set_input_as_handled()
		return


func _mode_direction(key: InputEventKey) -> int:
	var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_LEFT:
		return -1
	if code == KEY_RIGHT:
		return 1
	return 0


func _select_mode(index: int) -> void:
	if _current != &"mode":
		return
	_mode_index = index
	_focus_mode_index()


func _focus_mode_index() -> void:
	_update_mode_selection()


func _update_mode_selection() -> void:
	if _current != &"mode":
		return
	var names := ["Normal", "Sporty", "Aggressive", "Discreet"]
	(_mode.get_node("Center/Panel/Upper/Contents/ModeLabel/Contents/ModeName") as Label).text = names[_mode_index]
	for index in range(_mode_buttons.size()):
		_mode_buttons[index].set_pressed_no_signal(index == _mode_index)
	_previews.set_selected_preview("mode", _mode_index)


func _unhandled_input(event: InputEvent) -> void:
	if _media_sequence.is_active():
		return
	if _current == &"mode":
		return
	if _current == &"holomap":
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
		&"open_holomap":
			if _source == &"inventory" and _current == &"inventory":
				call_deferred("_open_holomap")
		&"use_item": command_requested.emit(action, value)
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
		&"master_volume", &"music_volume", &"sound_volume", &"speech_volume", &"cinematic_volume", &"wall_collision_damage", &"grid_lighting_enabled":
			setting_changed.emit(action, value)
		_:
			command_requested.emit(action, value)
