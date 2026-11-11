@tool
extends EditorExportPlugin

# Keep copyrighted original game art in the developer-only authoring scene.
# The sanitized runtime scene is generated with bake-holomap-runtime.sh.
const SF_NAME := "GeneralUser-GS.sf2"
var _destination := ""

func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_destination = ""
	if features.has("windows") or features.has("linux") or features.has("macos"):
		_destination = path.get_base_dir().path_join("lba1-native")
	if not FileAccess.file_exists(ProjectSettings.globalize_path("res://scenes/holomap_authoring/TwinsunRuntime.tscn")):
		push_error("Holomap: sanitized runtime scene missing; run bash tools/bake-holomap-runtime.sh before exporting")

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path == "res://scenes/holomap_authoring/TwinsunAuthoring.tscn" \
			or path == "res://scenes/holomap_authoring/twinsun_editor_preview.png" \
			or path == "res://scenes/holomap_authoring/twinsen_editor_preview.png":
		skip()

func _export_end() -> void:
	if _destination.is_empty():
		return
	var root := ProjectSettings.globalize_path("res://")
	var sf_src := root.path_join("native/lba1-native/soundfonts").path_join(SF_NAME)
	if not FileAccess.file_exists(sf_src):
		push_error("LBA export: missing SoundFont " + sf_src)
		_destination = ""
		return
	var source_tools := root.path_join("native/lba1-native/tools")
	var dir := DirAccess.open(source_tools)
	if dir == null:
		push_error("LBA export: missing importer scripts " + source_tools)
		_destination = ""
		return
	var sf_dest := _destination.path_join("soundfonts")
	var tool_dest := _destination.path_join("tools")
	if DirAccess.make_dir_recursive_absolute(sf_dest) != OK or DirAccess.make_dir_recursive_absolute(tool_dest) != OK:
		push_error("LBA export: unable to create companion directories beside build")
		_destination = ""
		return
	if DirAccess.copy_absolute(sf_src, sf_dest.path_join(SF_NAME)) != OK:
		push_error("LBA export: couldn't copy " + SF_NAME)
	for name in dir.get_files():
		if not name.ends_with(".py"):
			continue
		if DirAccess.copy_absolute(source_tools.path_join(name), tool_dest.path_join(name)) != OK:
			push_error("LBA export: couldn't copy importer " + name)
	print("LBA export companions copied to: ", _destination)
	_destination = ""
