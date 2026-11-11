class_name LBALanguages
extends RefCounted

const CFG_PATH := "user://lba1-godot.cfg"
# The original LBA1 TEXT.HQR has five languages, 14 banks each.
const LABELS := ["English", "Français", "Deutsch", "Español", "Italiano"]
const CODES := ["en", "fr", "de", "sp", "it"]

static func get_text_index() -> int:
	return _read_index("text_language")

static func get_voice_index() -> int:
	return _read_index("voice_language")

static func _read_index(key: String) -> int:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return 0
	return clampi(int(cfg.get_value("language", key, 0)), 0, LABELS.size() - 1)

static func save(text_index: int, voice_index: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("language", "text_language", clampi(text_index, 0, LABELS.size() - 1))
	cfg.set_value("language", "voice_language", clampi(voice_index, 0, LABELS.size() - 1))
	cfg.save(CFG_PATH)

static func locate_text(data_dir: String) -> String:
	for name in ["text.hqr", "TEXT.HQR", "Text.hqr"]:
		var path := data_dir.path_join(name)
		if FileAccess.file_exists(path):
			return path
	return ""

static func voice_key(language: int, bank_name: String, ordinal: int) -> String:
	return "voice:%s_%s:%d" % [CODES[clampi(language, 0, CODES.size() - 1)], bank_name, ordinal]
