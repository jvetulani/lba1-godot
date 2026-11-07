extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		push_error("LBA_TEST_DATA_PATH is required")
		quit(1)
		return
	if not ClassDB.can_instantiate(&"LBASimulation"):
		push_error("Missing LBASimulation extension")
		quit(1)
		return
	var sim: Object = ClassDB.instantiate(&"LBASimulation")
	if sim == null or int(sim.start(data_dir)) != 1:
		push_error("Native game initialization failed")
		quit(1)
		return
	var state: PackedInt32Array = sim.camera_flat()
	if state.size() != 5 or state[0] < 0:
		push_error("Camera state ABI must expose follow actor, zone flag and grid anchor")
		sim.shutdown()
		sim.free()
		quit(1)
		return
	print("LBA camera state: follow=", state[0], " forced=", state[1], " anchor=", state.slice(2))
	sim.shutdown()
	sim.free()
	quit(0)
