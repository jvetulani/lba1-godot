extends SceneTree

const GRID := preload("res://scripts/import/lba1_grid_decoder.gd")
const BRICK := preload("res://scripts/import/lba1_brick_decoder.gd")
const HQR := preload("res://scripts/import/hqr_reader.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		push_error("Set LBA_TEST_DATA_PATH to the original game data directory")
		quit(1)
		return
	var scene: Dictionary = GRID.read_scene(data_dir, 0)
	if not scene.get("ok", false):
		push_error(scene.get("error", "Cannot decode scene 0"))
		quit(1)
		return
	if scene["cells"].size() != GRID.CELL_COUNT or scene["brick_ids"].size() != GRID.CELL_COUNT:
		push_error("The scene grid has incorrect dimensions")
		quit(1)
		return
	if scene["occupied_count"] <= 0 or scene["visible_count"] <= 0:
		push_error("The original scene contains no decoded bricks")
		quit(1)
		return
	var palette_entry: Dictionary = HQR.read_entry(data_dir.path_join("ress.hqr"), 0)
	if not palette_entry.get("ok", false):
		push_error("Original palette is unavailable")
		quit(1)
		return
	var first_brick := -1
	var unique_bricks := {}
	for brick_id in scene["brick_ids"]:
		if brick_id >= 0:
			if first_brick < 0:
				first_brick = brick_id
			unique_bricks[brick_id] = true
	for brick_id in unique_bricks:
		var brick: Dictionary = BRICK.read_brick(data_dir, brick_id, palette_entry["data"])
		if not brick.get("ok", false):
			push_error(brick.get("error", "Cannot decode scene brick"))
			quit(1)
			return
		if brick["image"].get_width() != brick["width"] or brick["image"].get_height() != brick["height"]:
			push_error("Decoded brick image dimensions disagree")
			quit(1)
			return
	var shader := load("res://shaders/lba_tile.gdshader") as Shader
	if shader == null:
		push_error("Godot tile shader is unavailable")
		quit(1)
		return
	var uniform_names := {}
	for uniform_data in shader.get_shader_uniform_list():
		uniform_names[uniform_data["name"]] = true
	if not uniform_names.has("albedo_texture") or not uniform_names.has("normal_texture"):
		push_error("Tile shader lacks albedo or normal texture inputs")
		quit(1)
		return
	var malformed: Dictionary = GRID.decode(PackedByteArray(), PackedByteArray())
	if malformed.get("ok", false):
		push_error("Malformed scene data was accepted")
		quit(1)
		return
	print("LBA scene 0: %d occupied cells, %d visible bricks, %d blocks, %d decoded brick images (first %d)" % [
		scene["occupied_count"], scene["visible_count"], scene["block_count"], unique_bricks.size(), first_brick])
	quit(0)
