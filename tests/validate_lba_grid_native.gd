extends SceneTree

const CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const COORD := preload("res://scripts/render/lba_coordinates.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	var cube_path := OS.get_environment("LBA_TEST_NATIVE_CUBE_PATH")
	if data_dir.is_empty() or cube_path.is_empty():
		push_error("LBA_TEST_DATA_PATH and LBA_TEST_NATIVE_CUBE_PATH are required")
		quit(1)
		return
	var scene: Dictionary = CACHE.get_resource(data_dir, "grid", 0)
	if not scene.get("ok", false):
		push_error(str(scene.get("error", "Grid unavailable")))
		quit(1)
		return
	var native_bytes := FileAccess.get_file_as_bytes(cube_path)
	var cells: PackedInt32Array = scene["cells"]
	if native_bytes.size() != cells.size() * 2:
		push_error("Native cube length differs from Godot grid")
		quit(1)
		return
	var mismatches := 0
	for i in range(cells.size()):
		var expected := int(native_bytes.decode_u16(i * 2))
		if cells[i] != expected:
			if mismatches < 8:
				print("cell ", i, ": Godot=", cells[i], " native=", expected)
			mismatches += 1
	if mismatches > 0:
		push_error("Godot grid differs from native collision cube in %d cells" % mismatches)
		quit(1)
		return
	# Map2Screen's brick origin (288,215) and Proj_ISO's actor origin
	# (311,240) must align after each graph's hot spot and dimensions.
	var floor: Dictionary = CACHE.get_resource(data_dir, "brick", 0)
	var center := COORD.grid_graph_center(int(floor["hot_x"]), int(floor["hot_y"]),
		int(floor["width"]), int(floor["height"]))
	var facing := COORD.camera_facing_basis()
	for cell in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(0, 1, 0),
		Vector3i(0, 0, 1), Vector3i(28, 4, 37), Vector3i(63, 24, 63)]:
		var position: Vector3 = COORD.grid_cell(cell.x, cell.y, cell.z) + center
		var projected_x := position.dot(facing.x) / COORD.PIXEL_SIZE
		var projected_y := -position.dot(facing.y) / COORD.PIXEL_SIZE
		var expected_x := 288.0 + float(cell.x - cell.z) * 24.0 \
			+ float(floor["hot_x"]) + float(floor["width"]) * 0.5 - 311.0
		var expected_y := 215.0 + float(cell.x + cell.z) * 12.0 \
			- float(cell.y) * 15.0 + float(floor["hot_y"]) \
			+ float(floor["height"]) * 0.5 - 240.0
		if absf(projected_x - expected_x) > 0.01 or absf(projected_y - expected_y) > 0.01:
			push_error("Godot graph placement differs from native projection at %s" % cell)
			quit(1)
			return
	print("LBA grid: all %d Godot cells match native collision data" % cells.size())
	quit()
