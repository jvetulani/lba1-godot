@tool
extends Control

# Editor-only preview. Actual original pixels and narration text are read from
# the user's own LBA1 files, not bundled with the Godot project.
const HQR := preload("res://scripts/import/hqr_reader.gd")
const TEXT := preload("res://scripts/ui/lba_text_hqr.gd")
const LANG := preload("res://scripts/ui/lba_languages.gd")

@export_enum("Saved language", "English", "Français", "Deutsch", "Español", "Italiano") var preview_language: int = 0:
	set(value):
		preview_language = value
		if is_inside_tree():
			_refresh_preview.call_deferred()

@export_range(0, 2) var slide_index: int = 0:
	set(value):
		slide_index = value
		if is_inside_tree():
			_refresh_preview.call_deferred()

@export_global_dir var data_directory: String = "":
	set(value):
		data_directory = value
		if is_inside_tree():
			_refresh_preview.call_deferred()


@export_group("Intro Canvas")
# Match the canvas on which Caption, Illustration and Background were authored.
# This is presentation metadata, NOT the original 640x480 image resolution.
@export var design_canvas_size: Vector2 = Vector2(1280.0, 720.0)

@export_group("Text Reveal")
@export_range(1.0, 240.0, 1.0) var reveal_characters_per_second: float = 22.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview.call_deferred()


func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var directory := _resolve_data_directory()
	var image: TextureRect = get_node_or_null("Illustration") as TextureRect
	var caption: RichTextLabel = get_node_or_null("Caption") as RichTextLabel
	var info: Label = get_node_or_null("PreviewHelp") as Label
	if image == null or caption == null:
		return
	var text_path := _find_file(directory, "text.hqr")
	var ress_path := _find_file(directory, "ress.hqr")
	if info != null:
		info.visible = ress_path.is_empty() or text_path.is_empty()
		info.text = "Original data missing for editor preview.\nSet Data Directory on this scene's root, or configure it in the game's Settings."
	if not ress_path.is_empty():
		image.texture = _original_picture(ress_path, [15, 17, 19][slide_index], [16, 18, 20][slide_index])
	if not text_path.is_empty():
		var lines: Array = TEXT.load_intro_texts(text_path, LANG.get_text_index() if preview_language == 0 else preview_language - 1)
		if lines.size() > slide_index:
			caption.text = str(lines[slide_index]).replace("@P", "\n\n").replace("@", "\n")


func _resolve_data_directory() -> String:
	if not data_directory.is_empty():
		return data_directory
	var cfg := ConfigFile.new()
	if cfg.load("user://lba1-godot.cfg") == OK:
		var source := str(cfg.get_value("original_game", "source_path", ""))
		if not source.is_empty():
			return source
	var staged := ProjectSettings.globalize_path("user://lba1-native/data")
	if DirAccess.dir_exists_absolute(staged):
		return staged
	return ""


func _find_file(directory: String, name: String) -> String:
	if directory.is_empty():
		return ""
	for candidate in [directory.path_join(name), directory.path_join(name.to_upper()),
			directory.path_join(name.to_lower())]:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _original_picture(ress_path: String, image_id: int, palette_id: int) -> Texture2D:
	var pixels: Dictionary = HQR.read_entry(ress_path, image_id)
	var palette: Dictionary = HQR.read_entry(ress_path, palette_id)
	if not pixels.get("ok", false) or not palette.get("ok", false):
		return null
	var indexed: PackedByteArray = pixels["data"]
	var colors: PackedByteArray = palette["data"]
	if indexed.size() != 640 * 480 or colors.size() != 256 * 3:
		return null
	var rgba := PackedByteArray()
	rgba.resize(640 * 480 * 4)
	for i in range(indexed.size()):
		var o := int(indexed[i]) * 3
		var d := i * 4
		for c in range(3):
			var v := int(colors[o + c]) >> 2
			rgba[d + c] = (v << 2) | (v >> 4)
		rgba[d + 3] = 255
	return ImageTexture.create_from_image(Image.create_from_data(640, 480, false, Image.FORMAT_RGBA8, rgba))
