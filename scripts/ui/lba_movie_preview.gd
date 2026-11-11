@tool
extends Control

# Visual editor preview of actual converted frames. Runtime movie playback
# remains owned by LBAMediaSequence. This stage is intentionally shared by both.
@export_enum("introd", "dragon3") var movie_name := "introd":
	set(value):
		movie_name = value
		if is_inside_tree():
			_refresh_poster()

@export_global_dir var media_cache_directory := ""

@export_range(0.0, 100.0, 0.1, "suffix:%") var preview_percent := 25.0:
	set(value):
		preview_percent = value
		if is_inside_tree():
			_refresh_poster()

# Classic LBA movies were presented inside a 4:3 picture. This option
# deliberately differs from the compressed file's storage resolution.
@export_enum("Classic 4:3", "Source pixels", "16:9", "Custom") var display_shape := 0:
	set(value):
		display_shape = value
		if is_inside_tree():
			_fit_picture()

@export_range(0.5, 3.0, 0.001) var custom_aspect := 1.333333:
	set(value):
		custom_aspect = value
		if is_inside_tree():
			_fit_picture()

@export var show_safe_area := false:
	set(value):
		show_safe_area = value
		if is_inside_tree():
			_refresh_poster()

var _preview_image_size := Vector2i(640, 480)
var _preview_frame_count := 0
var _preview_duration := 0.0


func _ready() -> void:
	_fit_picture()
	var player := get_node("Picture/Movie") as VideoStreamPlayer
	var poster := get_node("Picture/EditorPoster") as TextureRect
	var hint := get_node("Picture/PreviewHint") as Label
	if Engine.is_editor_hint():
		# Do not let an empty VideoStreamPlayer paint black over the still frame.
		player.hide()
		_refresh_poster.call_deferred()
		return
	# The poster is an editor-only visual aid, never a runtime overlay.
	poster.hide()
	hint.hide()
	player.hide()
	# F6 runs this preview by itself. In the game, LBAMediaSequence
	# supplies the stream and explicitly makes the player visible.
	if get_parent() == get_tree().root:
		_play_direct_preview()


func _fit_picture() -> void:
	# One layout owner for editor poster AND runtime VideoStreamPlayer.
	# No manual positions, offsets or independent fullscreen anchors.
	var picture := get_node_or_null("Picture") as AspectRatioContainer
	if picture == null:
		return
	var aspect := 4.0 / 3.0
	match display_shape:
		1:
			aspect = float(_preview_image_size.x) / maxf(1.0, float(_preview_image_size.y))
		2:
			aspect = 16.0 / 9.0
		3:
			aspect = maxf(0.1, custom_aspect)
	picture.ratio = aspect


func _refresh_poster() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var poster := get_node_or_null("Picture/EditorPoster") as TextureRect
	var hint := get_node_or_null("Picture/PreviewHint") as Label
	var safe := get_node_or_null("Picture/SafeArea") as Control
	if poster == null:
		return
	var directory := "res://assets/editor_previews/%s" % movie_name
	var metadata_path := directory.path_join("preview.json")
	_preview_frame_count = 0
	_preview_duration = 0.0
	_preview_image_size = Vector2i(640, 480)
	if FileAccess.file_exists(metadata_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		if parsed is Dictionary:
			_preview_frame_count = int(parsed.get("frame_count", 0))
			_preview_duration = float(parsed.get("duration_seconds", 0.0))
			_preview_image_size = Vector2i(int(parsed.get("width", 640)), int(parsed.get("height", 480)))
	var frame_idx := clampi(roundi(preview_percent * 0.01 * float(maxi(0, _preview_frame_count - 1))),
		0, maxi(0, _preview_frame_count - 1))
	var frame_path := directory.path_join("frame_%03d.jpg" % frame_idx)
	var image := Image.new()
	if FileAccess.file_exists(frame_path) and image.load(frame_path) == OK:
		poster.texture = ImageTexture.create_from_image(image)
		poster.visible = true
		if hint != null:
			hint.visible = false
	else:
		poster.texture = null
		poster.visible = false
		if hint != null:
			hint.visible = true
			hint.text = "Extract preview frames once using tools/make_video_posters.py\nThen scrub Preview Percent in the Inspector."
	if safe != null:
		safe.visible = show_safe_area
	_fit_picture()


func _play_direct_preview() -> void:
	var cache := _cache_directory()
	var manifest_path := cache.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		push_warning("Movie preview: configure Media Cache Directory on the root node")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary):
		return
	var assets: Variant = (parsed as Dictionary).get("assets", {})
	if not (assets is Dictionary):
		return
	var key := "movie:%s" % movie_name
	if not assets.has(key):
		push_warning("Movie preview: missing %s" % key)
		return
	var path := cache.path_join(str((assets[key] as Dictionary).get("path", "")))
	if not FileAccess.file_exists(path):
		push_warning("Movie preview: file missing: %s" % path)
		return
	var stream := VideoStreamTheora.new()
	stream.file = path
	var player := get_node("Picture/Movie") as VideoStreamPlayer
	player.stream = stream
	player.show()
	player.play()


func _cache_directory() -> String:
	if not media_cache_directory.is_empty():
		return media_cache_directory
	var cfg := ConfigFile.new()
	if cfg.load("user://lba1-godot.cfg") == OK:
		var chosen := str(cfg.get_value("original_game", "media_cache_path", ""))
		if not chosen.is_empty():
			return chosen
	var project := ProjectSettings.globalize_path("res://project.godot").get_base_dir()
	return project.get_base_dir().path_join("releases/lba1-linux-x86_64/data/media-cache")
