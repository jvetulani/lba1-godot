extends SceneTree

const InputScript = preload("res://scripts/bridge/lba_gameplay_input.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var expected := {
		&"lba_forward": InputScript.FORWARD,
		&"lba_backward": InputScript.BACKWARD,
		&"lba_turn_left": InputScript.TURN_LEFT,
		&"lba_turn_right": InputScript.TURN_RIGHT,
		&"lba_primary": InputScript.PRIMARY,
		&"lba_weapon": InputScript.WEAPON,
		&"lba_recenter_camera": InputScript.RECENTER_CAMERA,
	}
	for action in expected:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			push_error("Missing Godot Input Map action: %s" % action)
			quit(1)
			return
		Input.action_press(action)
		if InputScript.sample_actions() != expected[action]:
			push_error("Native action bit mismatch for %s" % action)
			quit(2)
			return
		Input.action_release(action)
	if InputScript.sample_actions() != 0:
		push_error("A released gameplay action remained held")
		quit(3)
		return
	for action in [&"lba_pause", &"lba_inventory"]:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			push_error("Missing UI Input Map action: %s" % action)
			quit(4)
			return
	print("LBA Input Map: keyboard/gamepad actions and native bits verified")
	quit(0)
