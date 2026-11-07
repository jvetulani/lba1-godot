extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui := (load("res://scenes/ui/GameUI.tscn") as PackedScene).instantiate() as GameUI
	root.add_child(ui)
	var commands: Array[StringName] = []
	ui.command_requested.connect(func(command: StringName, _payload: Variant) -> void: commands.append(command))
	var main := ui.get_node("Frame/MainMenu")
	(main.get_node("Center/Panel/Contents/OpenSettings") as Button).pressed.emit()
	if not ui.get_node("Frame/SettingsMenu").visible or main.visible:
		_fail(ui, "Main menu did not open Settings")
		return
	var settings := ui.get_node("Frame/SettingsMenu")
	(settings.find_child("Close", true, false) as Button).pressed.emit()
	if not main.visible:
		_fail(ui, "Settings did not return to the main menu")
		return
	(main.get_node("Center/Panel/Contents/OpenLoad") as Button).pressed.emit()
	if not ui.get_node("Frame/LoadScreen").visible:
		_fail(ui, "Main menu did not open Load game")
		return
	(ui.get_node("Frame/LoadScreen/Center/Panel/Contents/Actions/Close") as Button).pressed.emit()
	if not main.visible:
		_fail(ui, "Load game did not return to the main menu")
		return
	(main.get_node("Center/Panel/Contents/NewGame") as Button).pressed.emit()
	if commands != [&"new_game"]:
		_fail(ui, "New game did not reach the host command signal")
		return
	ui.show_panel(&"pause")
	(ui.get_node("Frame/PauseMenu/Center/Panel/Contents/OpenSave") as Button).pressed.emit()
	if not ui.get_node("Frame/SaveScreen").visible:
		_fail(ui, "Pause menu did not open Save game")
		return
	(ui.get_node("Frame/SaveScreen/Center/Panel/Contents/Actions/Close") as Button).pressed.emit()
	if not ui.get_node("Frame/PauseMenu").visible:
		_fail(ui, "Save game did not return to Pause")
		return
	print("LBA UI: Settings, Load, New Game command, Pause and Save navigation verified")
	ui.free()
	quit(0)


func _fail(ui: Node, message: String) -> void:
	push_error(message)
	ui.free()
	quit(1)
