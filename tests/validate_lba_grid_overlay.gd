extends SceneTree

const GRID := preload("res://scripts/import/lba1_grid_decoder.gd")
const WORLD := preload("res://scenes/world/World3D.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		push_error("LBA_TEST_DATA_PATH is required")
		quit(1)
		return
	var base: Dictionary = GRID.read_scene(data_dir, 0)
	var cutaway: Dictionary = GRID.read_scene(data_dir, 0, 0)
	if not base.get("ok", false) or not cutaway.get("ok", false):
		push_error("Scene 0 or its first GRM is unavailable: %s" % cutaway.get("error", "base grid"))
		quit(1)
		return
	var changed := 0
	for i in range(GRID.CELL_COUNT):
		if base["cells"][i] != cutaway["cells"][i]:
			changed += 1
	if changed == 0:
		push_error("GRM 0 did not change any scene 0 cells")
		quit(1)
		return
	var native_cube_path := OS.get_environment("LBA_TEST_NATIVE_GRM_CUBE_PATH")
	if not native_cube_path.is_empty():
		var native_bytes := FileAccess.get_file_as_bytes(native_cube_path)
		if native_bytes.size() != GRID.CELL_COUNT * 2:
			push_error("Native GRM cube has an invalid length")
			quit(1)
			return
		for i in range(GRID.CELL_COUNT):
			if cutaway["cells"][i] != int(native_bytes.decode_u16(i * 2)):
				push_error("Godot GRM cell %d differs from native collision cube" % i)
				quit(1)
				return
	var world := WORLD.instantiate() as LBAWorld3D
	root.add_child(world)
	if not world.load_grid_scene(0, data_dir, 0):
		push_error("Godot could not build the GRM cutaway")
		quit(1)
		return
	if world.get_node("Bricks").get_child(0).name != "SceneGrid_0_GRM_0":
		push_error("World did not select the native GRM variant")
		quit(1)
		return
	var first_cutaway := world.get_node("Bricks").get_child(0)
	if not is_equal_approx((world.get_node("Camera") as Camera3D).size, 12.0):
		push_error("Gameplay camera zoom differs from the LBA framing")
		quit(1)
		return
	if not world.load_grid_scene(0, data_dir, -1) or world.get_node("Bricks").get_child(0).name != "SceneGrid_0_GRM_-1":
		push_error("World did not restore the base grid after leaving the GRM zone")
		quit(1)
		return
	if not world.load_grid_scene(0, data_dir, 0) or world.get_node("Bricks").get_child(0) != first_cutaway:
		push_error("GRM change rebuilt grid geometry instead of reusing the detached variant")
		quit(1)
		return
	world.free()
	print("LBA grid: scene 0 GRM 0 replaces %d cells and builds a cutaway%s" % [
		changed, "; all cells match native" if not native_cube_path.is_empty() else ""])
	quit()
