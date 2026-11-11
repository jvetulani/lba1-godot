class_name LBAModelImportWarmup
extends RefCounted

# Import once: BODY, INVOBJ and ANIM decoded .res caches.
# Per-actor SubViewport thumbnails remain presentation work.
const CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const BATCH_SIZE := 12


static func _signature(data_dir: String) -> String:
	var result := "models;visual-converter=%d" % CACHE.CONVERTER_VERSION
	for name in ["body.hqr", "invobj.hqr", "anim.hqr"]:
		var path := data_dir.path_join(name)
		if not FileAccess.file_exists(path):
			return ""
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return ""
		result += ";%s:%d:%d" % [name, file.get_length(), FileAccess.get_modified_time(path)]
		file.close()
	return result.md5_text()


static func _marker() -> String:
	return CACHE.cache_path.path_join("v%d/model-import-complete.json" % CACHE.CONVERTER_VERSION)


static func is_prepared(data_dir: String) -> bool:
	var signature := _signature(data_dir)
	if signature.is_empty() or not FileAccess.file_exists(_marker()):
		return false
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(_marker()))
	return decoded is Dictionary and str(decoded.get("signature", "")) == signature


static func _entry_count(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8:
		return 0
	var count_bytes := int(file.get_32())
	if count_bytes < 8 or count_bytes % 4 != 0 or count_bytes > file.get_length():
		return 0
	var count := count_bytes / 4
	file.seek(count_bytes - 4)
	if int(file.get_32()) == file.get_length():
		count -= 1
	file.close()
	return count


static func warm_all(data_dir: String, progress: Callable = Callable()) -> bool:
	if is_prepared(data_dir):
		if progress.is_valid():
			progress.call(1.0, "3D model and animation cache already imported")
		return true
	var categories := [
		{"kind": "body", "path": "body.hqr"},
		{"kind": "inventory_model", "path": "invobj.hqr"},
		{"kind": "animation", "path": "anim.hqr"},
	]
	var total := 0
	for category in categories:
		category["count"] = _entry_count(data_dir.path_join(str(category["path"])))
		total += int(category["count"])
	if total <= 0:
		push_error("LBA model import: no BODY, INVOBJ or ANIM archive entries")
		return false
	var done := 0
	var valid := 0
	for category in categories:
		var kind := str(category["kind"])
		for first in range(0, int(category["count"]), BATCH_SIZE):
			for index in range(first, mini(first + BATCH_SIZE, int(category["count"]))):
				var data: Dictionary = CACHE.get_resource(data_dir, kind, index)
				if data.get("ok", false):
					valid += 1
				done += 1
			if progress.is_valid():
				progress.call(float(done) / float(total),
					"Importing %s: %d / %d" % [kind, done, total])
			await Engine.get_main_loop().process_frame
	if valid <= 0:
		return false
	var marker := _marker()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(marker.get_base_dir()))
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"signature": _signature(data_dir), "valid": valid}))
	file.close()
	if progress.is_valid():
		progress.call(1.0, "Imported %d model/animation records" % valid)
	return true
