extends GameActionPanel

@onready var _source: LineEdit = $Center/ContentCenter/Panel/Contents/SourceRow/SourcePath
@onready var _cache: LineEdit = $Center/ContentCenter/Panel/Contents/CacheRow/CachePath
@onready var _picker: FileDialog = $SourcePicker
@onready var _cache_picker: FileDialog = $CachePicker
@onready var _import_button: Button = $Center/ContentCenter/Panel/Contents/ImportOriginalMedia
@onready var _progress: ProgressBar = $Center/ContentCenter/Panel/Contents/ImportProgress
@onready var _status: Label = $Center/ContentCenter/Panel/Contents/ImportStatus


func _ready() -> void:
	super._ready()
	_source.text_submitted.connect(_on_source_submitted)
	_source.focus_exited.connect(_on_source_focus_exited)
	_cache.text_submitted.connect(_on_cache_submitted)
	_cache.focus_exited.connect(_on_cache_focus_exited)
	_picker.dir_selected.connect(_on_directory_selected)
	_cache_picker.dir_selected.connect(_on_cache_directory_selected)
	action_requested.connect(_on_panel_action)
	if OS.has_feature("web") or OS.has_feature("android") or OS.has_feature("ios"):
		_import_button.disabled = true
		_status.text = "Import the original media on a desktop build first."


func set_original_data_path(path: String) -> void:
	_source.text = path


func set_media_cache_path(path: String) -> void:
	_cache.text = path


func set_import_progress(message: String, fraction: float, busy: bool) -> void:
	_status.text = message
	_progress.value = clampf(fraction, 0.0, 1.0) * 100.0
	_import_button.disabled = busy or OS.has_feature("web") or OS.has_feature("android") or OS.has_feature("ios")
	_source.editable = not busy
	_cache.editable = not busy


func _on_panel_action(action: StringName, _value: Variant) -> void:
	if action == &"browse_original_data":
		if DirAccess.dir_exists_absolute(_source.text):
			_picker.current_dir = _source.text
		_picker.popup_centered()
	elif action == &"browse_media_cache":
		if DirAccess.dir_exists_absolute(_cache.text):
			_cache_picker.current_dir = _cache.text
		_cache_picker.popup_centered()
	elif action == &"import_original_media":
		action_requested.emit(&"original_data_path", _source.text)
		action_requested.emit(&"media_cache_path", _cache.text)


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
