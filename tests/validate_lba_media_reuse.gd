extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var expected := OS.get_environment("LBA_TEST_MEDIA_CACHE")
	if expected.is_empty():
		push_error("Set LBA_TEST_MEDIA_CACHE to an existing converted media cache")
		quit(1)
		return
	var app := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	var media := app.get_node("MediaImport") as LBAMediaImport
	if media.get_media_cache_path() != expected or not media.is_import_ready():
		_fail(app, "Godot did not discover the existing native release cache")
		return
	var data := media.get_staged_data_path()
	if not FileAccess.file_exists(data.path_join("scene.hqr")) or not FileAccess.file_exists(data.path_join("LBA.CFG")):
		_fail(app, "Godot did not stage writable original game data")
		return
	var field := app.get_node("GameUI/Frame/SettingsMenu/Center/ContentCenter/Panel/Contents/CacheRow/CachePath") as LineEdit
	if field.text != expected:
		_fail(app, "Settings did not display the selected media cache")
		return
	app._on_command(&"media_cache_path", expected.get_base_dir())
	if media.get_media_cache_path() != expected:
		_fail(app, "Settings did not accept the cache parent directory")
		return
	var settings := ConfigFile.new()
	if settings.load("user://lba1-godot.cfg") != OK or str(settings.get_value("original_game", "media_cache_path", "")) != expected:
		_fail(app, "Media cache selection was not persisted")
		return
	print("LBA media: existing converted cache reused, writable data staged, Settings path persisted")
	app.free()
	quit(0)


func _fail(app: Node, message: String) -> void:
	push_error(message)
	app.free()
	quit(1)
