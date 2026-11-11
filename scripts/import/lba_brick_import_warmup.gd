class_name LBABrickImportWarmup
extends RefCounted

# IMPORT-STAGE cache generation. This is never called during a scene transition.
# The entire BRK archive is enumerated, including bricks not present in scene 0.
# The existing BRK preprocessor dispatches CPU pixel jobs to WorkerThreadPool.
# Yield between batches so Godot can draw genuine import progress.
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const PREPROCESS := preload("res://scripts/render/lba_brick_preprocess.gd")
const HQR := preload("res://scripts/import/hqr_reader.gd")
const BATCH_SIZE := 8


static func _completion_path() -> String:
	return VISUAL_CACHE.cache_path.path_join(PREPROCESS.cache_relative_dir()).path_join("import-complete.json")


static func _signature(data_dir: String) -> String:
	var value := "brk-preprocess-v%d;alpha-%.2f;cache-v%d" % [PREPROCESS.VERSION, PREPROCESS.outer_alpha_pixels(), VISUAL_CACHE.CONVERTER_VERSION]
	for archive in ["lba_brk.hqr", "ress.hqr"]:
		var path := data_dir.path_join(archive)
		if not FileAccess.file_exists(path):
			return ""
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return ""
		value += ";%s:%d:%d" % [archive, file.get_length(), FileAccess.get_modified_time(path)]
		file.close()
	return value.md5_text()


static func is_prepared(data_dir: String) -> bool:
	var signature := _signature(data_dir)
	if signature.is_empty():
		return false
	var marker := _completion_path()
	if not FileAccess.file_exists(marker):
		return false
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(marker))
	return decoded is Dictionary and str(decoded.get("signature", "")) == signature \
		and int(decoded.get("version", -1)) == PREPROCESS.VERSION


static func warm_all(data_dir: String, progress: Callable = Callable()) -> bool:
	if is_prepared(data_dir):
		if progress.is_valid():
			progress.call(1.0, "Projected brick textures already imported")
		return true
	var source_path := data_dir.path_join("lba_brk.hqr")
	var archive := FileAccess.open(source_path, FileAccess.READ)
	if archive == null:
		push_error("LBA brick import: cannot open " + source_path)
		return false
	if archive.get_length() < 8:
		push_error("LBA brick import: BRK archive is truncated")
		return false
	var index_bytes: int = int(archive.get_32())
	var archive_size: int = int(archive.get_length())
	if index_bytes < 8 or index_bytes % 4 != 0 or index_bytes > archive_size:
		push_error("LBA brick import: invalid BRK offset table")
		return false
	var count: int = index_bytes / 4
	# Most HQR archives have a terminal offset pointing at EOF.
	archive.seek(index_bytes - 4)
	if int(archive.get_32()) == archive_size:
		count -= 1
	archive.close()
	var processed_count := 0
	var valid_count := 0
	for first in range(0, count, BATCH_SIZE):
		var batch := {}
		for brick_id in range(first, mini(first + BATCH_SIZE, count)):
			# Generate and retain the decoded-asset .res cache as well as the
			# projected PNG cache. Runtime should never RLE-decode this twice.
			var brick: Dictionary = VISUAL_CACHE.get_resource(data_dir, "brick", brick_id)
			if not brick.get("ok", false):
				continue # Empty archive slots are valid and are not drawable bricks.
			batch[brick_id] = brick
			valid_count += 1
		if not batch.is_empty():
			PREPROCESS.prepare_bricks(batch)
		processed_count += mini(BATCH_SIZE, count - first)
		if progress.is_valid():
			progress.call(float(processed_count) / float(maxi(count, 1)),
				"Importing projected tiles: %d / %d" % [processed_count, count])
		await Engine.get_main_loop().process_frame
	if valid_count == 0:
		push_error("LBA brick import: no BRK images could be decoded")
		return false
	var marker := _completion_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(marker.get_base_dir()))
	var file := FileAccess.open(marker, FileAccess.WRITE)
	if file == null:
		push_error("LBA brick import: could not write completion marker")
		return false
	file.store_string(JSON.stringify({
		"version": PREPROCESS.VERSION,
		"signature": _signature(data_dir),
		"bricks": valid_count,
	}))
	file.close()
	if progress.is_valid():
		progress.call(1.0, "Imported %d projected brick textures" % valid_count)
	return true
