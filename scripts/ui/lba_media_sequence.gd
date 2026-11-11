class_name LBAMediaSequence
extends Control

signal sequence_finished(kind: StringName)
signal media_error(message: String)

const HQRReaderScript = preload("res://scripts/import/hqr_reader.gd")
const TEXT_HQR := preload("res://scripts/ui/lba_text_hqr.gd")
const LANG := preload("res://scripts/ui/lba_languages.gd")
const INTRO_MIN_PAGE_SECONDS := 1.2
const INTRO_IMAGES := [[15, 16], [17, 18], [19, 20]]
const INTRO_STAGE_SCENES := [
	preload("res://scenes/ui/intro/IntroScreen1.tscn"),
	preload("res://scenes/ui/intro/IntroScreen2.tscn"),
	preload("res://scenes/ui/intro/IntroScreen3.tscn"),
]
const DREAM_MOVIE_SCENE := preload("res://scenes/ui/previews/DreamSequence.tscn")
const DRAGON_MOVIE_SCENE := preload("res://scenes/ui/previews/DragonBoot.tscn")
# English GAM text IDs 150, 151 and 152 resolve to these VOX indices.
const INTRO_VOICES := ["voice:en_gam:58", "voice:en_gam:59", "voice:en_gam:60"]

@onready var _illustration: TextureRect = $Illustration
@onready var _intro_caption: RichTextLabel = $IntroCaption
@onready var _movie: VideoStreamPlayer = $Movie
@onready var _skip: Button = $Skip
@onready var _narrator: AudioStreamPlayer = $Narrator
@onready var _music: AudioStreamPlayer = $Music

var _cache_path := ""
var _data_path := ""
var _text_language := 0
var _voice_language := 0
var _assets: Dictionary = {}
var _kind: StringName = &""
var _slide := 0
var _movie_fps := 12.0
var _logo_seconds := 0.0
var _cues: Array[Dictionary] = []
var _next_cue := 0
var _fade: Tween
var _intro_texts: PackedStringArray = PackedStringArray()
var _intro_pages: PackedStringArray = PackedStringArray()
var _intro_deadlines: PackedFloat32Array = PackedFloat32Array()
var _intro_page_index := 0
var _intro_elapsed := 0.0
var _intro_reveal_progress := 0.0
var _intro_voice_length := 0.0
var _intro_voice_finished: bool = false
var _intro_page_hold: float = 0.0
var _intro_page_start: float = 0.0
var _intro_chevron: TextureRect
const INTRO_REVEALED_HOLD_SECONDS: float = 0.85
const INTRO_DEFAULT_REVEAL_RATE: float = 22.0
var _dream_play_elapsed := 0.0
var _dream_play_started := false
var _intro_stage: Control
var _movie_stage: Control
var _original_illustration: TextureRect
var _original_caption: RichTextLabel
var _original_movie: VideoStreamPlayer


func _ready() -> void:
	_skip.visible = false
	_intro_caption.visible = false
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(skip)
	_narrator.finished.connect(_on_narrator_finished)
	_movie.finished.connect(_on_movie_finished)
	set_process(false)
	# Parent captions to the illustration, so both always use exactly the
	# same coordinate space and never drift into the side letterbox.
	_intro_caption.reparent(_illustration, false)
	_original_illustration = _illustration
	_original_caption = _intro_caption
	_original_movie = _movie
	_illustration.resized.connect(_on_intro_resized)
	resized.connect(_on_intro_resized)


func _on_intro_resized() -> void:
	# Runtime layout and text wrapping come from each IntroScreen scene.
	# Refit the root's 640x480 reference canvas only, without touching Caption.
	if _intro_stage != null:
		_fit_intro_stage()


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
	_text_language = LANG.get_text_index()
	_voice_language = LANG.get_voice_index()
	_load_original_intro_texts()
	return true


func set_languages(text_index: int, voice_index: int) -> void:
	_text_language = clampi(text_index, 0, LANG.LABELS.size() - 1)
	_voice_language = clampi(voice_index, 0, LANG.LABELS.size() - 1)
	if _data_path.is_empty():
		return
	_load_original_intro_texts()
	if _kind == &"intro" and _slide < _intro_texts.size():
		_setup_intro_pages(_intro_texts[_slide])
		_update_intro_page()


func _intro_voice_key(slide_index: int) -> String:
	var text_path := LANG.locate_text(_data_path)
	if not text_path.is_empty():
		var ordinal := TEXT_HQR.voice_ordinal(text_path, 2, _voice_language, 150 + slide_index)
		if ordinal >= 0:
			var wanted := LANG.voice_key(_voice_language, "gam", ordinal)
			if _asset_path(wanted) != "":
				return wanted
	# Voice importer may only have English files; keep the original narration.
	return INTRO_VOICES[slide_index]


func _load_original_intro_texts() -> void:
	_intro_texts = PackedStringArray()
	var path := _data_path.path_join("text.hqr")
	if not FileAccess.file_exists(path):
		path = _data_path.path_join("TEXT.HQR")
	if not FileAccess.file_exists(path):
		push_warning("Intro captions unavailable: original TEXT.HQR not found")
		return
	var texts: Array = TEXT_HQR.load_intro_texts(path, _text_language)
	for entry in texts:
		_intro_texts.append(str(entry))
	if _intro_texts.size() != 3:
		push_warning("Intro captions incomplete: expected GAM IDs 150, 151, 152")


func _setup_intro_pages(text: String) -> void:
	_intro_pages = _paginate_intro_text(text)
	_intro_deadlines = PackedFloat32Array()
	_intro_page_index = 0
	var total_chars := 0.0
	for page in _intro_pages:
		total_chars += maxf(1.0, float(page.length()))
	var total_duration := maxf(0.05, _intro_voice_length)
	var elapsed := 0.0
	for page in _intro_pages:
		elapsed += total_duration * maxf(1.0, float(page.length())) / total_chars
		_intro_deadlines.append(elapsed)


func _paginate_intro_text(text: String) -> PackedStringArray:
	# Only original LBA content markers: @P is a page, @ is a line break.
	# No font measurement, width-based wrapping, centering or line limits.
	var normalized := text.replace("\r", "").replace("@P", "\f").replace("@", "\n")
	normalized = normalized.replace(String.chr(1), "\n")
	var pages := PackedStringArray()
	for original_page in normalized.split("\f", true):
		pages.append(original_page)
	if pages.is_empty():
		pages.append("")
	return pages


func _update_intro_page() -> void:
	_intro_reveal_progress = 0.0
	_intro_page_hold = 0.0
	_intro_page_start = _intro_deadlines[_intro_page_index - 1] if _intro_page_index > 0 and _intro_deadlines.size() >= _intro_page_index else 0.0
	if _intro_chevron != null:
		_intro_chevron.visible = false
	if _intro_pages.is_empty():
		_intro_caption.text = ""
		_intro_caption.visible_characters = 0
		_intro_caption.visible = false
		return
	var page: String = _intro_pages[clampi(_intro_page_index, 0, _intro_pages.size() - 1)]
	# One setter supplies CONTENT only. RichTextLabel scene settings supply style.
	_intro_caption.text = page
	# Shape the FULL justified paragraph first; clip glyphs afterward.
	# Without this, each newly visible character rejustifies the line.
	_intro_caption.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_intro_caption.visible_characters = 0
	_intro_caption.visible = not page.is_empty()


func play_menu_music() -> void:
	if _assets.is_empty() or _kind != &"":
		return
	# Menu theme 9 has an authored CD equivalent: physical CD track 10.
	# Preserve the MIDI conversion as a fallback for installations without CD.
	if _asset_path("cd:10") != "":
		_play_music("cd:10", true)
	elif _asset_path("midi:9") != "":
		_play_music("midi:9", true)


func stop_menu_music() -> void:
	# Used at gameplay transition. The cinematic player must not keep playing
	# beneath the native game's independent music player.
	_stop_music()


func play_boot() -> bool:
	# Original PERSO.C calls AdelineLogo() before DRAGON3.FLA.
	# RESS_LOGO_PCR=27 / RESS_LOGO_PAL=28; theme is MIDI 31.
	var logo := load_resource_texture(_data_path.path_join("ress.hqr"), 27, 28)
	if logo == null:
		push_warning("Adeline logo unavailable; continuing to dragon cinematic")
		return _play_movie(&"boot", "dragon3")
	_kind = &"boot_logo"
	# The original logo jingle should finish before the dragon sequence.
	# Prefer the imported audio duration over a hard-coded four seconds.
	_logo_seconds = 5.5
	visible = true
	_movie.stop()
	_movie.visible = false
	_illustration.texture = logo
	_illustration.visible = true
	_play_music("midi:31", false)
	if _music.stream != null and _music.stream.get_length() > 0.0:
		_logo_seconds = maxf(5.5, _music.stream.get_length() + 0.2)
	($Background as ColorRect).color = Color.WHITE
	set_process(true)
	return true


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
			push_warning("English intro narration absent: %s; showing text without speech" % voice_key)
	if _asset_path("movie:introd") == "":
		media_error.emit("Converted LBA1 intro movie is missing: introd")
		return false
	_stop_music()
	_kind = &"intro"
	visible = true
	_movie.visible = false
	_movie.stop()
	_slide = 0
	_intro_caption.visible = false
	set_process(true)
	_show_slide()
	return true


func skip() -> void:
	# Public skip entry point is also used by the UI's Escape shortcut.
	# During illustrated narration Escape advances ONE picture; it must not
	# emit sequence_finished and jump straight into gameplay.
	if _kind == &"intro":
		advance_intro(true)
		return
	if _kind == &"boot_logo":
		_stop_music()
		_play_movie(&"boot", "dragon3")
		return
	if _kind != &"":
		_finish()


func advance_intro(explicit_skip: bool = false) -> void:
	if _kind != &"intro":
		return
	# VOX audio owns its own lifetime. Automatic transitions and last-page
	# Enter/Space must never stop a still-playing narration clip.
	if not explicit_skip and (not _intro_voice_finished or _narrator.playing):
		return
	if explicit_skip and _narrator.playing:
		print("LBA intro narration explicitly skipped on illustration ", _slide + 1)
	_narrator.stop()
	_slide += 1
	if _slide < INTRO_IMAGES.size():
		_show_slide()
	else:
		print("LBA intro: slide 3 advanced, starting dream video introd")
		_play_movie(&"intro_movie", "introd")

func advance_intro_page() -> void:
	# Enter/Space advance a single page, not the entire illustration.
	if _kind != &"intro":
		return
	if _intro_page_index + 1 < _intro_pages.size():
		_intro_page_index += 1
		_update_intro_page()
	else:
		# On the final page, Enter/Space finishes the text reveal but does
		# not cut off the narration. Escape remains the explicit audio skip.
		var count: int = _intro_caption.get_total_character_count()
		if _intro_caption.visible_characters < count:
			_intro_caption.visible_characters = count
			_intro_reveal_progress = float(count)
			if _intro_chevron != null:
				_intro_chevron.visible = true
		else:
			advance_intro()


func is_active() -> bool:
	return _kind != &""


func is_intro_illustration() -> bool:
	return _kind == &"intro"


func _show_slide() -> void:
	_mount_intro_stage(_slide)
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
	print("LBA intro: illustration ", _slide + 1, "/", INTRO_IMAGES.size())
	_intro_voice_length = 0.0
	_intro_voice_finished = false
	_play_narration(_intro_voice_key(_slide))
	_setup_intro_pages(_intro_texts[_slide] if _slide < _intro_texts.size() else "")
	_intro_elapsed = 0.0
	_update_intro_page()


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
	if path.is_empty():
		_intro_voice_length = 7.0
		var expected_slide: int = _slide
		get_tree().create_timer(7.0).timeout.connect(func() -> void:
			if _kind == &"intro" and _slide == expected_slide:
				_on_narrator_finished())
		return
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		media_error.emit("Could not play intro narration: %s" % path)
		_finish(false)
		return
	_narrator.stream = stream
	_intro_voice_length = stream.get_length()
	print("LBA intro VOX started: slide=", _slide + 1, " duration=", _intro_voice_length, " file=", path.get_file())
	_narrator.play()


func _on_narrator_finished() -> void:
	# VOX duration must never truncate a monologue or the typewriter effect.
	if _kind == &"intro":
		_intro_voice_finished = true


func _play_movie(kind: StringName, stem: String) -> bool:
	($Background as ColorRect).color = Color.BLACK
	var key := "movie:%s" % stem
	var path := _asset_path(key)
	if path == "":
		media_error.emit("Converted LBA1 movie is missing: %s" % stem)
		if _kind == &"intro":
			_finish(false)
		return false
	_mount_movie_stage(stem)
	var stream := VideoStreamTheora.new()
	stream.file = path
	_kind = kind
	visible = true
	_illustration.visible = false
	_intro_caption.visible = false
	_movie.visible = true
	_movie.stream = stream
	_movie_fps = float((_assets[key] as Dictionary).get("fps", 12))
	_cues = _read_cues(_cache_path.path_join("movies/%s.events" % stem))
	_next_cue = 0
	if kind == &"intro_movie":
		_dream_play_elapsed = 0.0
		_dream_play_started = false
		_play_music("midi:1", false)
	_movie.play()
	print("LBA movie stage: ", stem, " visible=", _movie.is_visible_in_tree(),
		" rect=", _movie.get_global_rect(), " texture=", _movie.get_video_texture() != null)
	if kind == &"intro_movie":
		print("LBA intro movie: playing ", path, " fps=", _movie_fps)
		_check_intro_movie_started.call_deferred()
	set_process(true)
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


func _process(delta: float) -> void:
	if _kind == &"intro":
		_intro_elapsed += delta
		# Keep authored wrapping stable; reveal laid-out glyphs only.
		if _intro_caption.visible and _intro_caption.visible_characters >= 0:
			var total: int = _intro_caption.get_total_character_count()
			if _intro_caption.visible_characters < total:
				var rate: float = INTRO_DEFAULT_REVEAL_RATE
				if _intro_stage != null:
					rate = maxf(1.0, float(_intro_stage.get("reveal_characters_per_second")))
				# The narration's actual length caps the text speed for each
				# authored page. Missing/very short voices use the scene cap.
				if _intro_voice_length > 0.0 and _intro_page_index < _intro_deadlines.size():
					var page_duration: float = _intro_deadlines[_intro_page_index] - _intro_page_start
					if page_duration > 0.5:
						rate = minf(rate, float(total) / page_duration)
				_intro_reveal_progress += delta * rate
				_intro_caption.visible_characters = mini(int(_intro_reveal_progress), total)
		var all_revealed: bool = not _intro_caption.visible or (
			_intro_caption.visible_characters >= _intro_caption.get_total_character_count())
		if _intro_chevron != null:
			_intro_chevron.visible = all_revealed
		if all_revealed:
			_intro_page_hold += delta
			if _intro_page_hold >= INTRO_REVEALED_HOLD_SECONDS and (
					_intro_page_index >= _intro_deadlines.size() or
					_intro_elapsed >= _intro_deadlines[_intro_page_index]):
				if _intro_page_index + 1 < _intro_pages.size():
					_intro_page_index += 1
					_update_intro_page()
				elif _intro_voice_finished:
					advance_intro()
		else:
			_intro_page_hold = 0.0
		return
	if _kind == &"boot_logo":
		_logo_seconds -= delta
		if _logo_seconds <= 0.0:
			_stop_music()
			_play_movie(&"boot", "dragon3")
		return
	if _kind != &"boot" and _kind != &"intro_movie":
		return
	if _kind == &"intro_movie" and _movie.is_playing():
		_dream_play_started = true
		_dream_play_elapsed += delta
	var frame := int(floor(_movie.stream_position * _movie_fps))
	while _next_cue < _cues.size() and int(_cues[_next_cue]["frame"]) <= frame:
		var value := int(_cues[_next_cue]["value"])
		if value == 1:
			_play_music("midi:26", false)
		elif value == 4:
			_fade_music()
		_next_cue += 1


func _check_intro_movie_started() -> void:
	# Allow the VideoStreamPlayer two render frames to initialize its decoder.
	await get_tree().process_frame
	await get_tree().process_frame
	if _kind != &"intro_movie":
		return
	if not _movie.is_playing():
		push_error("LBA dream video did not start: %s" % _asset_path("movie:introd"))
		# Do NOT advance to gameplay silently if the movie never opened.
		media_error.emit("Dream video failed to start. Check converted introd video.")
		_finish(false)


func _on_movie_finished() -> void:
	if _kind == &"intro_movie":
		print("LBA intro movie: ended at ", _movie.stream_position, " sec")
		if not _dream_play_started or _dream_play_elapsed < 0.5:
			# A decoder failure is NOT the end of the story. Keep the player on
			# the film screen and report the missing/corrupt converted video.
			push_error("Dream video ended before showing content: " + _asset_path("movie:introd"))
			media_error.emit("Dream video failed to play. Re-import introd movie and inspect Godot Output.")
			_finish(false)
			return
	if _kind == &"boot" or _kind == &"intro_movie":
		_finish()


func _finish(emit_completed: bool = true) -> void:
	var finished_kind := &"boot" if _kind == &"boot_logo" else _kind
	_kind = &""
	set_process(false)
	_movie.stop()
	_movie.stream = null
	_movie.visible = false
	_narrator.stop()
	_narrator.stream = null
	_illustration.texture = null
	_intro_caption.visible = false
	_intro_caption.text = ""
	_release_editable_stages()
	visible = false
	_stop_music()
	if emit_completed:
		sequence_finished.emit(finished_kind)




# Real runtime stage instances. Move Caption and Illustration in each .tscn,
# and the changes appear during New Game without any hard-coded positioning.
func _mount_intro_stage(slide_index: int) -> void:
	if slide_index < 0 or slide_index >= INTRO_STAGE_SCENES.size():
		return
	if _movie_stage != null:
		_movie_stage.queue_free()
		_movie_stage = null
		_movie = _original_movie
	var previous := _intro_stage
	_intro_stage = (INTRO_STAGE_SCENES[slide_index] as PackedScene).instantiate() as Control
	add_child(_intro_stage)
	_illustration = _intro_stage.get_node("Illustration") as TextureRect
	_intro_caption = _intro_stage.get_node("Caption") as RichTextLabel
	_intro_chevron = _intro_stage.get_node_or_null("PageChevron") as TextureRect
	if _intro_chevron != null:
		_intro_chevron.visible = false
	_original_illustration.visible = false
	_intro_stage.visible = true
	_fit_intro_stage()
	if previous != null:
		previous.queue_free()


func _fit_intro_stage() -> void:
	if _intro_stage == null:
		return
	var space := size
	if space.x <= 0.0 or space.y <= 0.0:
		return
	# Scenes are authored on a wide canvas, not on the source image's 640x480
	# pixel grid. Keep the whole scene (including the colour-matched Background)
	# visible and scale it as one unit. Never resize Caption independently.
	var canvas: Vector2 = _intro_stage.get("design_canvas_size")
	canvas.x = maxf(1.0, canvas.x)
	canvas.y = maxf(1.0, canvas.y)
	var scale_factor := minf(space.x / canvas.x, space.y / canvas.y)
	# The source scenes use Full Rect in editor. Remove their parent-relative
	# root anchors at runtime or the canvas size can be added to the viewport.
	_intro_stage.anchor_left = 0.0
	_intro_stage.anchor_top = 0.0
	_intro_stage.anchor_right = 0.0
	_intro_stage.anchor_bottom = 0.0
	_intro_stage.size = canvas
	_intro_stage.scale = Vector2.ONE * scale_factor
	_intro_stage.position = (space - canvas * scale_factor) * 0.5


func _mount_movie_stage(stem: String) -> void:
	if _intro_stage != null:
		_intro_stage.queue_free()
		_intro_stage = null
		_intro_chevron = null
		_illustration = _original_illustration
		_intro_caption = _original_caption
	if _movie_stage != null:
		_movie.stop()
		_movie_stage.queue_free()
		_movie_stage = null
	_movie = _original_movie
	if stem != "introd" and stem != "dragon3":
		return
	var packed: PackedScene = DREAM_MOVIE_SCENE if stem == "introd" else DRAGON_MOVIE_SCENE
	_movie_stage = packed.instantiate() as Control
	add_child(_movie_stage)
	_movie_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_movie_stage.move_to_front()
	_movie_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_movie = _movie_stage.get_node("Picture/Movie") as VideoStreamPlayer
	_movie.finished.connect(_on_movie_finished)
	_original_movie.visible = false
	_original_illustration.visible = false


func _release_editable_stages() -> void:
	if _intro_stage != null:
		_intro_stage.queue_free()
		_intro_stage = null
		_intro_chevron = null
	if _movie_stage != null:
		_movie_stage.queue_free()
		_movie_stage = null
	_illustration = _original_illustration
	_intro_caption = _original_caption
	_movie = _original_movie
	_original_movie.visible = false
	_original_illustration.visible = false
	_original_caption.visible = false


func _asset_path(key: String) -> String:
	if not _assets.has(key):
		return ""
	var relative := str((_assets[key] as Dictionary).get("path", ""))
	var absolute := _cache_path.path_join(relative)
	return absolute if FileAccess.file_exists(absolute) else ""


func _play_music(key: String, looped: bool) -> void:
	var path := _asset_path(key)
	if path == "":
		push_warning("Converted LBA1 music is missing: %s" % key)
		return
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		push_warning("Could not play LBA1 music: %s" % path)
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
