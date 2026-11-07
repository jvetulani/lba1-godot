extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var panel := (load("res://scenes/ui/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(panel)
	var button := panel.get_node("Center/Panel/Contents/NewGame") as Button
	if button == null or not button is LBAPlasmaButton:
		_fail(panel, "New Game is not a reusable plasma button")
		return
	if str(button.get_node("Caption").text) != "New game":
		_fail(panel, "The Godot button text is missing")
		return
	var material := button.get_node("Plasma").material as ShaderMaterial
	if material == null or material.shader == null:
		_fail(panel, "The plasma shader is missing")
		return
	var other := panel.get_node("Center/Panel/Contents/Continue") as Button
	var other_material := other.get_node("Plasma").material as ShaderMaterial
	if material == other_material:
		_fail(panel, "Buttons share selection state")
		return
	panel.focus_first()
	if not button.has_focus() or material.get_shader_parameter("selected") != 1.0:
		_fail(panel, "Keyboard/gamepad focus did not highlight New Game")
		return
	if other_material.get_shader_parameter("selected") != 0.0:
		_fail(panel, "Focus highlighted another button")
		return
	var actions: Array[StringName] = []
	panel.action_requested.connect(func(action: StringName, _value: Variant) -> void: actions.append(action))
	button.pressed.emit()
	if actions != [&"new_game"]:
		_fail(panel, "The button did not emit the New Game command")
		return
	print("LBA menu: text, plasma shader, focus and command verified")
	panel.free()
	quit(0)


func _fail(panel: Node, message: String) -> void:
	push_error(message)
	panel.free()
	quit(1)
