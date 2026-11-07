extends SceneTree

const TEST_SLOT := 4


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		push_error("LBA_TEST_DATA_PATH is required")
		quit(1)
		return
	var slot_path := data_dir.path_join("GODOT%02d.LBA" % TEST_SLOT)
	var old_slot := FileAccess.get_file_as_bytes(slot_path) if FileAccess.file_exists(slot_path) else PackedByteArray()
	var app := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	app._start_native_game()
	for attempt in range(250):
		await create_timer(0.02).timeout
		if app._game_started:
			break
	if not app._game_started:
		_finish(app, slot_path, old_slot, "New Game did not reach gameplay")
		return
	var host: LBANativeHost = app.get_node("NativeHost")
	var before: Dictionary = host.get_snapshot()["actors"][0]
	app._on_command(&"open_save", null)
	app._on_command(&"save", TEST_SLOT)
	if not FileAccess.file_exists(slot_path):
		_finish(app, slot_path, old_slot, "Godot save action did not write an original .LBA slot")
		return
	Input.action_press(&"lba_forward")
	await create_timer(1.0).timeout
	Input.action_release(&"lba_forward")
	var moved: Dictionary = host.get_snapshot()["actors"][0]
	if moved["z"] == before["z"]:
		_finish(app, slot_path, old_slot, "Player did not move before load")
		return
	app._on_command(&"open_load", null)
	app._on_command(&"load", TEST_SLOT)
	await create_timer(0.1).timeout
	var restored: Dictionary = host.get_snapshot()["actors"][0]
	if restored["z"] != before["z"]:
		_finish(app, slot_path, old_slot, "Original .LBA load did not restore Twinsen")
		return
	app._on_command(&"quit_to_main", null)
	app._start_native_game()
	await create_timer(0.2).timeout
	if not app._game_started or int(host.get_snapshot().get("scene", -1)) != 0:
		_finish(app, slot_path, old_slot, "Quit and New Game left stale native state")
		return
	print("LBA save/load: Godot UI slot, native .LBA round trip, quit and restart verified")
	_finish(app, slot_path, old_slot, "")


func _finish(app: Node, slot_path: String, old_slot: PackedByteArray, error: String) -> void:
	Input.action_release(&"lba_forward")
	app.get_node("NativeHost").stop()
	app.free()
	if old_slot.is_empty():
		DirAccess.remove_absolute(slot_path)
	else:
		var file := FileAccess.open(slot_path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(old_slot)
			file.close()
	if not error.is_empty():
		push_error(error)
	quit(0 if error.is_empty() else 1)
