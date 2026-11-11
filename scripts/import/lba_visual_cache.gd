class_name LBAVisualCache
extends RefCounted

const HQR := preload("res://scripts/import/hqr_reader.gd")
const BODY := preload("res://scripts/import/lba1_body_decoder.gd")
const ANIMATION := preload("res://scripts/import/lba1_animation_decoder.gd")
const GRID := preload("res://scripts/import/lba1_grid_decoder.gd")
const GRAPH := preload("res://scripts/import/lba1_brick_decoder.gd")
const ASSET := preload("res://scripts/import/lba_visual_asset.gd")
const CONVERTER_VERSION := 2

static var cache_path := "user://lba1-visual-cache"
static var _fingerprints: Dictionary = {}
static var _memory: Dictionary = {}


static func configure(path: String) -> void:
	var chosen := path.strip_edges().trim_suffix("/")
	if chosen.is_empty():
		chosen = "user://lba1-visual-cache"
	if chosen != cache_path:
		cache_path = chosen
		_memory.clear()
		_fingerprints.clear()


static func get_resource(data_dir: String, kind: String, entry_id: int) -> Dictionary:
	var archives := _archives_for(kind)
	if archives.is_empty() or entry_id < 0:
		return {"ok": false, "error": "Unknown visual resource %s:%d" % [kind, entry_id]}
	var digest := _source_digest(data_dir, archives)
	if digest.is_empty():
		return {"ok": false, "error": "Original %s archive is unavailable" % kind}
	var key := "%s/%s/%d/%s" % [cache_path, kind, entry_id, digest]
	if _memory.has(key):
		var cached_payload: Dictionary = _memory[key]
		if kind not in ["grid", "grid_variant"] or cached_payload.has("shape_ids"):
			return cached_payload
	var path := cache_path.path_join("v%d/%s/%05d.res" % [CONVERTER_VERSION, kind, entry_id])
	if FileAccess.file_exists(path):
		var saved: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if saved != null and saved.get("kind") == kind and saved.get("entry_id") == entry_id \
				and saved.get("converter_version") == CONVERTER_VERSION and saved.get("source_digest") == digest:
			var saved_payload: Dictionary = saved.get("payload")
			if kind not in ["grid", "grid_variant"] or saved_payload.has("shape_ids"):
				_memory[key] = saved_payload
				return saved_payload
	var decoded := _decode(data_dir, kind, entry_id)
	if not decoded.get("ok", false):
		return decoded
	var asset: Resource = ASSET.new()
	asset.set("kind", kind)
	asset.set("entry_id", entry_id)
	asset.set("converter_version", CONVERTER_VERSION)
	asset.set("source_digest", digest)
	asset.set("payload", decoded)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) == OK:
		var temporary := path + ".tmp.res"
		if ResourceSaver.save(asset, temporary) == OK:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	_memory[key] = decoded
	return decoded


static func _source_digest(data_dir: String, archives: PackedStringArray) -> String:
	var combined := "v%d" % CONVERTER_VERSION
	for archive in archives:
		var path := data_dir.path_join(archive)
		if not FileAccess.file_exists(path):
			return ""
		var modified := FileAccess.get_modified_time(path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return ""
		var size := file.get_length()
		file.close()
		var fingerprint: Dictionary = _fingerprints.get(path, {})
		if fingerprint.get("modified", -1) != modified or fingerprint.get("size", -1) != size:
			fingerprint = {"modified": modified, "size": size, "digest": FileAccess.get_md5(path)}
			_fingerprints[path] = fingerprint
		combined += ":" + str(fingerprint["digest"])
	return combined.md5_text()


static func _archives_for(kind: String) -> PackedStringArray:
	match kind:
		"body": return PackedStringArray(["body.hqr"])
		"inventory_model": return PackedStringArray(["invobj.hqr"])
		"animation": return PackedStringArray(["anim.hqr"])
		"grid", "grid_variant": return PackedStringArray(["lba_gri.hqr", "lba_bll.hqr"])
		"brick": return PackedStringArray(["lba_brk.hqr", "ress.hqr"])
		"sprite": return PackedStringArray(["sprites.hqr", "ress.hqr"])
		"palette": return PackedStringArray(["ress.hqr"])
	return PackedStringArray()


static func _decode(data_dir: String, kind: String, entry_id: int) -> Dictionary:
	match kind:
		"body":
			var entry: Dictionary = HQR.read_entry(data_dir.path_join("body.hqr"), entry_id)
			return BODY.decode(entry["data"]) if entry.get("ok", false) else entry
		"inventory_model":
			var entry: Dictionary = HQR.read_entry(data_dir.path_join("invobj.hqr"), entry_id)
			return BODY.decode(entry["data"]) if entry.get("ok", false) else entry
		"animation":
			var entry: Dictionary = HQR.read_entry(data_dir.path_join("anim.hqr"), entry_id)
			return ANIMATION.decode(entry["data"]) if entry.get("ok", false) else entry
		"grid": return GRID.read_scene(data_dir, entry_id)
		"grid_variant": return GRID.read_scene(data_dir, entry_id / 256, entry_id % 256 - 1)
		"palette": return HQR.read_entry(data_dir.path_join("ress.hqr"), entry_id)
		"brick":
			var palette: Dictionary = get_resource(data_dir, "palette", 0)
			return GRAPH.read_brick(data_dir, entry_id, palette["data"]) if palette.get("ok", false) else palette
		"sprite":
			var entry: Dictionary = HQR.read_entry(data_dir.path_join("sprites.hqr"), entry_id)
			if not entry.get("ok", false):
				return entry
			var bytes: PackedByteArray = entry["data"]
			if bytes.size() < 8:
				return {"ok": false, "error": "Sprite entry is truncated"}
			var offset := int(bytes.decode_u32(0))
			if offset < 4 or offset + 4 > bytes.size():
				return {"ok": false, "error": "Sprite graph offset is invalid"}
			var palette: Dictionary = get_resource(data_dir, "palette", 0)
			return GRAPH.decode(bytes.slice(offset), palette["data"]) if palette.get("ok", false) else palette
	return {"ok": false, "error": "Unsupported visual resource kind"}
