extends SceneTree


func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	print("host check entered")
	var host := LBANativeHost.new()
	print("host constructed")
	root.add_child(host)
	print("host added")
	if not host.start_new_game(OS.get_environment("LBA_TEST_DATA_PATH")):
		push_error("In-process host could not start")
		quit(1)
		return
	for tick in range(10):
		await physics_frame
	var state := host.get_snapshot()
	if int(state.get("scene", -1)) < 0 or (state.get("actors", []) as Array).is_empty():
		push_error("In-process host produced no playable scene")
		quit(1)
		return
	print("LBA host: scene=", state["scene"], " tick=", state["tick"])
	host.stop()
	if not host.start_new_game(OS.get_environment("LBA_TEST_DATA_PATH")):
		push_error("In-process host could not restart")
		quit(1)
		return
	for tick in range(3):
		await physics_frame
	state = host.get_snapshot()
	if int(state.get("scene", -1)) < 0:
		push_error("In-process host restart produced no scene")
		quit(1)
		return
	host.stop()
	host.free()
	quit()
