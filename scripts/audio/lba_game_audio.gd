class_name LBAGameAudio
extends Node

var _cache_path := ""
var _assets: Dictionary = {}
var _music: AudioStreamPlayer
var _sounds: Dictionary = {}


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = &"LBA Music"
	add_child(_music)


func configure(cache_path: String) -> void:
	_cache_path = cache_path
	_assets.clear()
	var path := cache_path.path_join("manifest.json")
	if FileAccess.file_exists(path):
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if manifest is Dictionary and manifest.get("assets", null) is Dictionary:
			_assets = manifest["assets"]


func apply_event(event: Dictionary) -> void:
	var kind := int(event.get("type", 0))
	var resource := int(event.get("resource", -1))
	match kind:
		2: _play_music("cd:%d" % resource)
		3: _play_music("midi:%d" % resource)
		4:
			_music.stop()
			_music.stream = null
		5: _play_sound(resource, event)
		6: _stop_sound(resource)


func stop() -> void:
	_music.stop()
	_music.stream = null
	_stop_sound(-1)


func _play_music(key: String) -> void:
	var path := _asset_path(key)
	if path.is_empty():
		push_warning("Original LBA1 music resource unavailable: %s" % key)
		return
	var stream := AudioStreamOggVorbis.load_from_file(path)
	if stream == null:
		push_warning("Cannot load converted LBA1 music: %s" % path)
		return
	_music.stop()
	_music.stream = stream
	_music.play()


func _play_sound(resource: int, event: Dictionary) -> void:
	var path := _asset_path("samples.hqr:%d" % resource)
	if path.is_empty():
		return
	var stream := _load_imported_pcm(path)
	if stream == null:
		push_warning("Cannot load converted LBA1 sound: %s" % path)
		return
	var player := AudioStreamPlayer.new()
	player.bus = &"LBA Sound"
	player.stream = stream
	player.pitch_scale = clampf(float(event.get("pitch", 4096)) / 4096.0, 0.25, 4.0)
	player.volume_linear = clampf((float(event.get("left", 255)) + float(event.get("right", 255))) / 510.0, 0.0, 1.0)
	add_child(player)
	if not _sounds.has(resource):
		_sounds[resource] = []
	(_sounds[resource] as Array).append(player)
	player.finished.connect(_finish_sound.bind(resource, player))
	player.play()


func _load_imported_pcm(path: String) -> AudioStreamWAV:
	# The native importer writes a canonical 44-byte PCM RIFF file. Loading its
	# payload directly also handles odd-sized 8-bit chunks without WAV padding.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 44:
		return null
	var bytes := file.get_buffer(file.get_length())
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF" \
			or bytes.slice(8, 12).get_string_from_ascii() != "WAVE" \
			or bytes.decode_u16(20) != 1:
		return null
	var channels := int(bytes.decode_u16(22))
	var bits := int(bytes.decode_u16(34))
	if channels < 1 or channels > 2 or bits not in [8, 16]:
		return null
	var pcm := bytes.slice(44)
	if bits == 8:
		for i in range(pcm.size()):
			pcm[i] = int(pcm[i]) ^ 0x80
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS if bits == 8 else AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(bytes.decode_u32(24))
	stream.stereo = channels == 2
	stream.data = pcm
	return stream


func _finish_sound(resource: int, player: AudioStreamPlayer) -> void:
	if _sounds.has(resource):
		(_sounds[resource] as Array).erase(player)
		if (_sounds[resource] as Array).is_empty():
			_sounds.erase(resource)
	player.queue_free()


func _stop_sound(resource: int) -> void:
	var keys := _sounds.keys() if resource < 0 else [resource]
	for key in keys:
		if not _sounds.has(key):
			continue
		for player in _sounds[key]:
			(player as AudioStreamPlayer).stop()
			(player as AudioStreamPlayer).queue_free()
		_sounds.erase(key)


func _asset_path(key: String) -> String:
	if not _assets.has(key):
		return ""
	var relative := str((_assets[key] as Dictionary).get("path", ""))
	var path := _cache_path.path_join(relative)
	return path if not relative.is_empty() and FileAccess.file_exists(path) else ""
