class_name LBAMediaImport
extends Node

signal source_changed(path: String)
signal cache_changed(path: String)
signal import_progress(message: String, fraction: float, busy: bool)
signal import_finished(success: bool, message: String)

const SETTINGS_PATH := "user://lba1-godot.cfg"
const RELEASE_PATH := "user://lba1-native"
const PROGRESS_RELATIVE := "data/media-cache/.import-progress.json"

var source_path := ""
var media_cache_path := ""
var _pid := -1
var _import_cache_path := ""
var _last_progress := ""
var _poll_elapsed := 0.0


func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		source_path = str(settings.get_value("original_game", "source_path", ""))
		media_cache_path = str(settings.get_value("original_game", "media_cache_path", ""))
	if media_cache_path.is_empty():
		var managed := _managed_cache_path()
		if _cache_has_media(managed):
			media_cache_path = managed
		else:
			var project_root := ProjectSettings.globalize_path("res://project.godot").get_base_dir()
			var release_cache := project_root.get_base_dir().path_join("releases/lba1-linux-x86_64/data/media-cache")
			if _cache_has_media(release_cache):
				media_cache_path = release_cache
	if source_path.is_empty() and not media_cache_path.is_empty():
		var imported_source := _cache_source(media_cache_path)
		if DirAccess.dir_exists_absolute(imported_source):
			set_source_path(imported_source)
	source_changed.emit(source_path)
	cache_changed.emit(get_media_cache_path())
	set_process(false)


func set_source_path(path: String) -> void:
	var cleaned := path.strip_edges()
	if cleaned == source_path:
		return
	source_path = cleaned
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("original_game", "source_path", source_path)
	var result := settings.save(SETTINGS_PATH)
	if result != OK:
		import_finished.emit(false, "Could not save the original game-data path.")
	source_changed.emit(source_path)


func set_media_cache_path(path: String) -> void:
	var cleaned := path.strip_edges().trim_suffix("/")
	if FileAccess.file_exists(cleaned.path_join("media-cache/manifest.json")):
		cleaned = cleaned.path_join("media-cache")
	if cleaned == media_cache_path:
		return
	media_cache_path = cleaned
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH)
	settings.set_value("original_game", "media_cache_path", media_cache_path)
	if settings.save(SETTINGS_PATH) != OK:
		import_finished.emit(false, "Could not save the media-cache path.")
	cache_changed.emit(get_media_cache_path())


func start_import() -> void:
	if _pid != -1:
		return
	if OS.has_feature("web") or OS.has_feature("android") or OS.has_feature("ios"):
		import_finished.emit(false, "Media conversion currently needs the desktop importer.")
		return
	if source_path.is_empty() or not DirAccess.dir_exists_absolute(source_path):
		import_finished.emit(false, "Choose a folder containing the original LBA1 game data.")
		return
	var launcher := _find_launcher()
	if launcher.is_empty():
		import_finished.emit(false, "Native media importer missing. Place lba1-native beside this Godot project or bundle its tools beside the game.")
		return
	var release := ProjectSettings.globalize_path(RELEASE_PATH)
	var result := DirAccess.make_dir_recursive_absolute(release)
	if result != OK:
		import_finished.emit(false, "Could not create the LBA1 import folder: %s" % release)
		return
	var progress := release.path_join(PROGRESS_RELATIVE)
	if FileAccess.file_exists(progress):
		DirAccess.remove_absolute(progress)
	var python := "python" if OS.has_feature("windows") else "python3"
	_import_cache_path = _managed_cache_path()
	_pid = OS.create_process(python, PackedStringArray([
		launcher, "--release", release, "--assets", source_path,
		"--import-only", "--no-gui",
	]))
	if _pid == -1:
		import_finished.emit(false, "Could not start Python. Install Python 3 or configure the desktop import helper.")
		return
	_last_progress = ""
	_poll_elapsed = 0.0
	import_progress.emit("Preparing original game data…", 0.0, true)
	set_process(true)


func get_media_cache_path() -> String:
	return media_cache_path if not media_cache_path.is_empty() else _managed_cache_path()


func get_staged_data_path() -> String:
	return ProjectSettings.globalize_path(RELEASE_PATH).path_join("data")


func is_import_ready() -> bool:
	if not _cache_has_media(get_media_cache_path()) or source_path.is_empty():
		return false
	var imported_source := _cache_source(get_media_cache_path())
	return imported_source == source_path or imported_source == source_path.path_join("Speedrun/Windows")


func ensure_staged_data() -> bool:
	if not is_import_ready():
		return false
	var data := get_staged_data_path()
	if FileAccess.file_exists(data.path_join("scene.hqr")) and FileAccess.file_exists(data.path_join("LBA.CFG")):
		return true
	var stage_tool := ProjectSettings.globalize_path("res://native/lba1-native/tools/stage_native_assets.py")
	if not FileAccess.file_exists(stage_tool):
		import_finished.emit(false, "Native data staging tool is missing.")
		return false
	var output: Array = []
	var python := "python" if OS.has_feature("windows") else "python3"
	var exit_code := OS.execute(python, PackedStringArray([stage_tool, "--assets", source_path,
		"--output", data]), output, true)
	if exit_code != 0:
		import_finished.emit(false, "Could not stage original LBA1 data: %s" % (str(output[0]) if not output.is_empty() else "exit %d" % exit_code))
		return false
	return FileAccess.file_exists(data.path_join("scene.hqr")) and FileAccess.file_exists(data.path_join("LBA.CFG"))


func _process(delta: float) -> void:
	_poll_elapsed += delta
	if _poll_elapsed < 0.2:
		return
	_poll_elapsed = 0.0
	_read_progress()
	if OS.is_process_running(_pid):
		return
	var exit_code := OS.get_process_exit_code(_pid)
	_pid = -1
	set_process(false)
	var manifest := _import_cache_path.path_join("manifest.json")
	var success := exit_code == 0 and FileAccess.file_exists(manifest)
	if success:
		set_media_cache_path(_import_cache_path)
	var message := "LBA1 audio and movies are ready." if success else "Media import failed (exit code %d). Check the Godot output and original game-data path." % exit_code
	import_progress.emit(message, 1.0 if success else 0.0, false)
	import_finished.emit(success, message)


func _read_progress() -> void:
	var progress := _import_cache_path.path_join(".import-progress.json")
	if not FileAccess.file_exists(progress):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(progress))
	if not (parsed is Dictionary):
		return
	var state := parsed as Dictionary
	var total := int(state.get("total", 0))
	var done := int(state.get("done", 0))
	var category := str(state.get("category", "Importing"))
	var item := str(state.get("item", ""))
	var message := "%s: %s (%d/%d)" % [category, item, done, total] if total > 0 else category
	if message != _last_progress:
		_last_progress = message
		import_progress.emit(message, float(done) / float(total) if total > 0 else 0.0, true)


func _find_launcher() -> String:
	var candidates := PackedStringArray()
	if not OS.has_feature("template"):
		var project_root := ProjectSettings.globalize_path("res://project.godot").get_base_dir()
		candidates.append(project_root.path_join("native/lba1-native/tools/run_first_time.py"))
		candidates.append(project_root.get_base_dir().path_join("lba1-native/tools/run_first_time.py"))
	var executable_dir := OS.get_executable_path().get_base_dir()
	candidates.append(executable_dir.path_join("lba1-native/tools/run_first_time.py"))
	candidates.append(executable_dir.path_join("tools/run_first_time.py"))
	for candidate in candidates:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _managed_cache_path() -> String:
	return ProjectSettings.globalize_path(RELEASE_PATH).path_join("data/media-cache")


func _cache_has_media(path: String) -> bool:
	if not FileAccess.file_exists(path.path_join("manifest.json")):
		return false
	var state_file := path.path_join(".import-state.json")
	if not FileAccess.file_exists(state_file):
		return false
	var state: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_file))
	return state is Dictionary and int(state.get("revision", 0)) == 4


func _cache_source(path: String) -> String:
	var state: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join(".import-state.json")))
	return str(state.get("source", "")) if state is Dictionary else ""
