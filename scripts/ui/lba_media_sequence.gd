class_name LBAMediaSequence
extends Control

signal sequence_finished(kind: StringName)
signal media_error(message: String)

const HQRReaderScript = preload("res://scripts/import/hqr_reader.gd")
const INTRO_IMAGES := [[15, 16], [17, 18], [19, 20]]
# English GAM text IDs 150, 151 and 152 resolve to these VOX indices.
const INTRO_VOICES := ["voice:en_gam:58", "voice:en_gam:59", "voice:en_gam:60"]

@onready var _illustration: TextureRect = $Illustration
@onready var _movie: VideoStreamPlayer = $Movie
@onready var _skip: Button = $Skip
@onready var _narrator: AudioStreamPlayer = $Narrator
@onready var _music: AudioStreamPlayer = $Music

var _cache_path := ""
var _data_path := ""
var _assets: Dictionary = {}
var _kind: StringName = &""
var _slide := 0
var _movie_fps := 12.0
var _cues: Array[Dictionary] = []
var _next_cue := 0
var _fade: Tween


func _ready() -> void:
	_skip.pressed.connect(skip)
	_narrator.finished.connect(_on_narrator_finished)
	_movie.finished.connect(_on_movie_finished)
	set_process(false)


func configure(cache_path: String, data_path: String) -> bool:
	_cache_path = cache_path
	_data_path = data_path
	var manifest_path := cache_path.path_join("manifest.json")
	if not FileAccess.file_exists(manifest_path):
		media_error.emit("Converted LBA1 media is missing. Import the original data in Settings.")
		return false
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (manifest is Dictionary) or not (manifest as Dictionary).get("assets", null) is Dictionary:
		media_error.emit("The LBA1 media manifest is invalid.")
		return false
	_assets = (manifest as Dictionary)["assets"]
	return true


func play_menu_music() -> void:
	if not _assets.is_empty() and _kind == &"":
		_play_music("cd:9" if _asset_path("cd:9") != "" else "midi:9", true)


func play_boot() -> bool:
	return _play_movie(&"boot", "dragon3")


func play_intro() -> bool:
	if _assets.is_empty():
		media_error.emit("Import LBA1 media before starting a new game.")
		return false
	var resource_path := _data_path.path_join("ress.hqr")
	if not FileAccess.file_exists(resource_path):
		media_error.emit("Original ress.hqr is missing from the imported game data.")
		return false
	for voice_key in INTRO_VOICES:
		if _asset_path(voice_key) == "":
			media_error.emit("The English intro narration is missing: %s" % voice_key)
			return false
	if _asset_path("movie:introd") == "":
		media_error.emit("Converted LBA1 intro movie is missing: introd")
		return false
	_stop_music()
	_kind = &"intro"
	visible = true
	_movie.visible = false
	_movie.stop()
	_slide = 0
	_show_slide()
	_skip.call_deferred("grab_focus")
	return true


func skip() -> void:
	if _kind == &"":
		return
	_finish()


func is_active() -> bool:
	return _kind != &""


func _show_slide() -> void:
	var resource_path := _data_path.path_join("ress.hqr")
	var image_id: int = INTRO_IMAGES[_slide][0]
	var palette_id: int = INTRO_IMAGES[_slide][1]
	var texture := load_resource_texture(resource_path, image_id, palette_id)
	if texture == null:
		media_error.emit("Could not read intro illustration %d from ress.hqr." % image_id)
		_finish(false)
		return
	_illustration.texture = texture
	_illustration.visible = true
	_play_narration(INTRO_VOICES[_slide])


static func load_resource_texture(resource_path: String, image_id: int, palette_id: int) -> Texture2D:
	var pixels: Dictionary = HQRReaderScript.read_entry(resource_path, image_id)
	var palette: Dictionary = HQRReaderScript.read_entry(resource_path, palette_id)
	if not pixels.get("ok", false) or not palette.get("ok", false):
		return null
	var indexed: PackedByteArray = pixels["data"]
	var colors: PackedByteArray = palette["data"]
	if indexed.size() != 640 * 480 or colors.size() != 256 * 3:
		return null
	var rgba := PackedByteArray()
	rgba.resize(640 * 480 * 4)
	for i in range(indexed.size()):
		var color_offset := int(indexed[i]) * 3
		var offset := i * 4
		for channel in range(3):
			# Match the original 6-bit DAC quantization used by the SDL port.
			var dac := int(colors[color_offset + channel]) >> 2
			rgba[offset + channel] = (dac << 2) | (dac >> 4)
		rgba[offset + 3] = 255
	return ImageTexture.create_from_image(Image.create_from_data(640, 480, false, Image.FORMAT_RGBA8, rgba))


func _play_narration(key: String) -> void:
	var path := _asset_path(key)
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		media_error.emit("Could not play intro narration: %s" % path)
		_finish(false)
		return
	_narrator.stream = stream
	_narrator.play()


func _on_narrator_finished() -> void:
	if _kind != &"intro":
		return
	_slide += 1
	if _slide < INTRO_IMAGES.size():
		_show_slide()
	else:
		_play_movie(&"intro_movie", "introd")


func _play_movie(kind: StringName, stem: String) -> bool:
	var key := "movie:%s" % stem
	var path := _asset_path(key)
	if path == "":
		media_error.emit("Converted LBA1 movie is missing: %s" % stem)
		if _kind == &"intro":
			_finish(false)
		return false
	var stream := VideoStreamTheora.new()
	stream.file = path
	_kind = kind
	visible = true
	_illustration.visible = false
	_movie.visible = true
	_movie.stream = stream
	_movie_fps = float((_assets[key] as Dictionary).get("fps", 12))
	_cues = _read_cues(_cache_path.path_join("movies/%s.events" % stem))
	_next_cue = 0
	if kind == &"intro_movie":
		_play_music("midi:1", false)
	_movie.play()
	set_process(true)
	_skip.call_deferred("grab_focus")
	return true


func _read_cues(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return result
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var columns := line.strip_edges().split(" ", false)
		if columns.size() < 2:
			columns = line.strip_edges().split("\t", false)
		if columns.size() >= 2 and columns[0].is_valid_int() and columns[1].is_valid_int():
			result.append({"frame": int(columns[0]), "value": int(columns[1])})
	return result


func _process(_delta: float) -> void:
	if _kind != &"boot" and _kind != &"intro_movie":
		return
	var frame := int(floor(_movie.stream_position * _movie_fps))
	while _next_cue < _cues.size() and int(_cues[_next_cue]["frame"]) <= frame:
		var value := int(_cues[_next_cue]["value"])
		if value == 1:
			_play_music("midi:26", false)
		elif value == 4:
			_fade_music()
		_next_cue += 1


func _on_movie_finished() -> void:
	if _kind == &"boot" or _kind == &"intro_movie":
		_finish()


func _finish(emit_completed: bool = true) -> void:
	var finished_kind := _kind
	_kind = &""
	set_process(false)
	_movie.stop()
	_movie.stream = null
	_movie.visible = false
	_narrator.stop()
	_narrator.stream = null
	_illustration.texture = null
	visible = false
	_stop_music()
	if emit_completed:
		sequence_finished.emit(finished_kind)


func _asset_path(key: String) -> String:
	if not _assets.has(key):
		return ""
	var relative := str((_assets[key] as Dictionary).get("path", ""))
	var absolute := _cache_path.path_join(relative)
	return absolute if FileAccess.file_exists(absolute) else ""


func _play_music(key: String, looped: bool) -> void:
	var path := _asset_path(key)
	if path == "":
		media_error.emit("Converted LBA1 music is missing: %s" % key)
		return
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		media_error.emit("Could not play LBA1 music: %s" % path)
		return
	if _fade != null and _fade.is_running():
		_fade.kill()
	_music.stop()
	_music.stream = null
	stream.loop = looped
	_music.stream = stream
	_music.volume_db = 0.0
	_music.play()


func _fade_music() -> void:
	if not _music.playing:
		return
	if _fade != null and _fade.is_running():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_music, "volume_db", -60.0, 1.0)
	_fade.tween_callback(_music.stop)


func _stop_music() -> void:
	if _fade != null and _fade.is_running():
		_fade.kill()
	_music.stop()
	_music.stream = null
