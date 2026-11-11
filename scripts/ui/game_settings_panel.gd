extends GameActionPanel

const LANG := preload("res://scripts/ui/lba_languages.gd")

@onready var _source: LineEdit = $Center/ContentCenter/Panel/Contents/SourceRow/SourcePath
@onready var _cache: LineEdit = $Center/ContentCenter/Panel/Contents/CacheRow/CachePath
@onready var _soundfont: LineEdit = $Center/ContentCenter/Panel/Contents/SoundFontRow/SoundFontPath
@onready var _soundfont_picker: FileDialog = $SoundFontPicker
@onready var _picker: FileDialog = $SourcePicker
@onready var _cache_picker: FileDialog = $CachePicker
@onready var _import_button: Button = $Center/ContentCenter/Panel/Contents/ImportOriginalMedia
@onready var _progress: ProgressBar = $Center/ContentCenter/Panel/Contents/ImportProgress
@onready var _status: Label = $Center/ContentCenter/Panel/Contents/ImportStatus
@onready var _text_language: OptionButton = $Center/ContentCenter/Panel/Contents/TextLanguageRow/TextLanguage
@onready var _voice_language: OptionButton = $Center/ContentCenter/Panel/Contents/VoiceLanguageRow/VoiceLanguage


func _ready() -> void:
	super._ready()
	for index in range(LANG.LABELS.size()):
		_text_language.add_item(LANG.LABELS[index], index)
		_voice_language.add_item(LANG.LABELS[index], index)
	_text_language.select(LANG.get_text_index())
	_voice_language.select(LANG.get_voice_index())
	_text_language.item_selected.connect(func(index: int) -> void:
		LANG.save(index, _voice_language.get_selected_id())
		action_requested.emit(&"text_language", index))
	_voice_language.item_selected.connect(func(index: int) -> void:
		LANG.save(_text_language.get_selected_id(), index)
		action_requested.emit(&"voice_language", index))
	var scroll: ScrollContainer = get_node_or_null("Center") as ScrollContainer
	if scroll != null:
		scroll.follow_focus = true
		# Make the overflow obvious and let keyboard/mouse reach every setting.
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
		for node in find_children("*", "Control", true, false):
			var option: Control = node as Control
			if option is BaseButton and option.has_meta("action"):
				option.focus_mode = Control.FOCUS_ALL
			if option != null and option.focus_mode != Control.FOCUS_NONE:
				option.focus_entered.connect(_scroll_to_focused_setting.bind(option))
	_source.text_submitted.connect(_on_source_submitted)
	_source.focus_exited.connect(_on_source_focus_exited)
	_cache.text_submitted.connect(_on_cache_submitted)
	_cache.focus_exited.connect(_on_cache_focus_exited)
	_picker.dir_selected.connect(_on_directory_selected)
	_cache_picker.dir_selected.connect(_on_cache_directory_selected)
	_soundfont.text_submitted.connect(_on_soundfont_submitted)
	_soundfont.focus_exited.connect(_on_soundfont_focus_exited)
	_soundfont_picker.file_selected.connect(_on_soundfont_selected)
	action_requested.connect(_on_panel_action)
	if OS.has_feature("web") or OS.has_feature("android") or OS.has_feature("ios"):
		_import_button.disabled = true
		_status.text = "Import the original media on a desktop build first."


func set_original_data_path(path: String) -> void:
	_source.text = path


func set_media_cache_path(path: String) -> void:
	_cache.text = path


func set_soundfont_path(path: String) -> void:
	_soundfont.text = path


func set_import_progress(message: String, fraction: float, busy: bool) -> void:
	_status.text = message
	_progress.value = clampf(fraction, 0.0, 1.0) * 100.0
	_import_button.disabled = busy or OS.has_feature("web") or OS.has_feature("android") or OS.has_feature("ios")
	_source.editable = not busy
	_cache.editable = not busy
	_soundfont.editable = not busy


func _on_panel_action(action: StringName, _value: Variant) -> void:
	if action == &"browse_original_data":
		if DirAccess.dir_exists_absolute(_source.text):
			_picker.current_dir = _source.text
		_picker.popup_centered()
	elif action == &"browse_media_cache":
		if DirAccess.dir_exists_absolute(_cache.text):
			_cache_picker.current_dir = _cache.text
		_cache_picker.popup_centered()
	elif action == &"browse_soundfont":
		if FileAccess.file_exists(_soundfont.text):
			_soundfont_picker.current_dir = _soundfont.text.get_base_dir()
		_soundfont_picker.popup_centered()
	elif action == &"import_original_media":
		action_requested.emit(&"original_data_path", _source.text)
		action_requested.emit(&"media_cache_path", _cache.text)
		action_requested.emit(&"soundfont_path", _soundfont.text)


func _on_source_submitted(path: String) -> void:
	action_requested.emit(&"original_data_path", path)
	_source.release_focus()


func _on_source_focus_exited() -> void:
	action_requested.emit(&"original_data_path", _source.text)


func _on_directory_selected(path: String) -> void:
	_source.text = path
	action_requested.emit(&"original_data_path", path)


func _on_cache_submitted(path: String) -> void:
	action_requested.emit(&"media_cache_path", path)
	_cache.release_focus()


func _on_cache_focus_exited() -> void:
	action_requested.emit(&"media_cache_path", _cache.text)


func _on_cache_directory_selected(path: String) -> void:
	_cache.text = path
	action_requested.emit(&"media_cache_path", path)


func _scroll_to_focused_setting(control: Control) -> void:
	var scroll: ScrollContainer = get_node_or_null("Center") as ScrollContainer
	if scroll != null and is_instance_valid(control):
		scroll.ensure_control_visible.call_deferred(control)
		# A ScrollContainer must be scrolled, not merely focused, when the
		# selected control is outside its clipped viewport. This also supports
		# keyboard navigation inherited from GameActionPanel.


func _on_soundfont_submitted(path: String) -> void:
	action_requested.emit(&"soundfont_path", path)
	_soundfont.release_focus()


func _on_soundfont_focus_exited() -> void:
	action_requested.emit(&"soundfont_path", _soundfont.text)


func _on_soundfont_selected(path: String) -> void:
	_soundfont.text = path
	action_requested.emit(&"soundfont_path", path)
