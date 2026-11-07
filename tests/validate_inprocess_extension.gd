extends SceneTree


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	if not ClassDB.can_instantiate(&"LBASimulation"):
		push_error("LBASimulation GDExtension did not load")
		quit(1)
		return
	var simulation: Object = ClassDB.instantiate(&"LBASimulation")
	if simulation == null:
		push_error("LBASimulation could not be instantiated")
		quit(1)
		return
	if simulation.abi_version() != 1:
		push_error("Unexpected LBA simulation ABI version")
		quit(1)
		return
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if not data_dir.is_empty():
		if simulation.start(data_dir) != 1:
			push_error("Original LBA1 game failed to start in-process")
			quit(1)
			return
		if int(simulation.scene_number()) != -1:
			push_error("Invalid initial simulation state")
			quit(1)
			return
		simulation.step(0)
		var actors: PackedInt32Array = simulation.actors_flat()
		if int(simulation.scene_number()) < 0 or actors.is_empty() or actors.size() % 17 != 0:
			push_error("LBA1 gameplay did not produce an actor snapshot")
			quit(1)
			return
		print("LBA in-process scene=", simulation.scene_number(), " actors=", actors.size() / 17)
		simulation.shutdown()
	simulation.free()
	quit()
