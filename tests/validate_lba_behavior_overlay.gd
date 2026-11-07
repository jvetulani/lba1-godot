extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_environment("LBA_TEST_DATA_PATH").is_empty():
		push_error("LBA_TEST_DATA_PATH is required")
		quit(1)
		return
	var app := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	app._start_native_game()
	for attempt in range(250):
		await create_timer(0.02).timeout
		if app._game_started:
			break
	if not app._game_started:
		_fail(app, "New Game did not reach gameplay")
		return
	var ui: GameUI = app.get_node("GameUI")
	var host: LBANativeHost = app.get_node("NativeHost")
	if ui._current != &"hud" or ui.get_node_or_null("Frame/HUD/Top") != null:
		_fail(app, "Normal gameplay still shows a persistent status HUD")
		return
	var native: PackedInt32Array = host._simulation.status_flat()
	var status: Dictionary = host.get_snapshot()["status"]
	if native.size() != 8 or status.get("health") != native[1] \
			or status.get("magic_level") != native[2] \
			or status.get("magic_energy") != native[3] \
			or status.get("clovers") != native[4] \
			or status.get("clover_boxes") != native[5] \
			or status.get("keys") != native[6] or status.get("money") != native[7]:
		_fail(app, "Status snapshot differs from authoritative native values")
		return
	var status_root := "Frame/ModeMenu/Center/Panel/Contents/Status/"
	if (ui.get_node(status_root + "Vitals/Health") as Label).text != "Health: %d" % native[1] \
			or (ui.get_node(status_root + "Vitals/Magic") as Label).text != "Magic level: %d  Energy: %d" % [native[2], native[3]] \
			or (ui.get_node(status_root + "Items/Clovers") as Label).text != "Clovers: %d / %d" % [native[4], native[5]] \
			or (ui.get_node(status_root + "Items/Keys") as Label).text != "Keys: %d" % native[6] \
			or (ui.get_node(status_root + "Items/Money") as Label).text != "Money: %d" % native[7]:
		_fail(app, "Ctrl overlay does not show native status")
		return
	var commits := []
	ui.command_requested.connect(func(command: StringName, value: Variant) -> void:
		if command == &"set_behavior": commits.append(value))
	var first: Dictionary = host.get_snapshot()["actors"][0]
	_send_key(KEY_CTRL, true, 1)
	await process_frame
	if ui._current != &"mode" or not host.paused or ui._mode_index != native[0]:
		_fail(app, "Holding Ctrl did not open at the native behavior")
		return
	_send_key(KEY_RIGHT, true)
	await process_frame
	if ui._mode_index != posmod(native[0] + 1, 4):
		_fail(app, "Ctrl + Right did not advance behavior")
		return
	_send_key(KEY_RIGHT, true, 0, true)
	await process_frame
	if ui._mode_index != posmod(native[0] + 1, 4):
		_fail(app, "Keyboard repeat double-stepped immediately")
		return
	_send_key(KEY_RIGHT, false)
	_send_key(KEY_LEFT, true)
	await process_frame
	if ui._mode_index != native[0]:
		_fail(app, "Ctrl + Left did not move back")
		return
	_send_key(KEY_LEFT, false)
	_send_key(KEY_RIGHT, true)
	_send_key(KEY_CTRL, true, 2)
	await create_timer(0.15).timeout
	var held: Dictionary = host.get_snapshot()["actors"][0]
	if held["x"] != first["x"] or held["z"] != first["z"] or held["angle"] != first["angle"]:
		_fail(app, "Behavior navigation moved or turned Twinsen")
		return
	_send_key(KEY_CTRL, false, 1)
	await process_frame
	if ui._current != &"mode" or commits.size() != 0:
		_fail(app, "Releasing one of two Ctrl keys committed early")
		return
	_send_key(KEY_CTRL, false, 2)
	await create_timer(0.12).timeout
	var selected := posmod(native[0] + 1, 4)
	if ui._current != &"hud" or commits.size() != 1 or commits[0] != selected \
			or host.get_snapshot()["status"]["behavior"] != selected:
		_fail(app, "Last Ctrl release did not commit behavior exactly once")
		return
	if not host.block_turn_actions or host.get_snapshot()["actors"][0]["angle"] != first["angle"]:
		_fail(app, "Held Right leaked into gameplay after Ctrl release")
		return
	_send_key(KEY_RIGHT, false)
	await process_frame
	if host.block_turn_actions:
		_fail(app, "Turn input remained blocked after Right release")
		return
	_send_key(KEY_CTRL, true, 1)
	await process_frame
	if ui._current != &"mode" or ui._mode_index != selected:
		_fail(app, "Reopened Ctrl overlay forgot the selected behavior")
		return
	_send_key(KEY_CTRL, false, 1)
	await process_frame
	if commits.size() != 2 or commits[1] != selected:
		_fail(app, "Ctrl release did not commit the retained mode once")
		return
	print("LBA Ctrl overlay: hold, arrows, dual Ctrl, native status and clean HUD verified")
	host.stop()
	app.free()
	quit()


func _send_key(code: Key, pressed: bool, location: int = 0, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.location = location
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func _fail(app: Node, message: String) -> void:
	push_error(message)
	app.get_node("NativeHost").stop()
	app.free()
	quit(1)
