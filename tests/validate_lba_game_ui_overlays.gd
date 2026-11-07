extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui := (load("res://scenes/ui/GameUI.tscn") as PackedScene).instantiate() as GameUI
	root.add_child(ui)
	var backdrop := ui.get_node("Frame/MenuBackdrop") as TextureRect
	if not backdrop.visible:
		_fail(ui, "Main menu backdrop is missing")
		return
	ui.set_world_active(true)
	ui.show_panel(&"pause")
	if backdrop.visible:
		_fail(ui, "Pause menu obscures the Godot world with menu artwork")
		return
	ui.show_hud()
	if backdrop.visible:
		_fail(ui, "HUD obscures the Godot world with menu artwork")
		return
	ui.set_world_active(false)
	ui.show_panel(&"main")
	if not backdrop.visible:
		_fail(ui, "Main menu backdrop did not return")
		return
	if ui.get_node("Frame/PauseMenu").find_child("OpenInventory", true, false) != null:
		_fail(ui, "Inventory is still a pause-menu entry")
		return
	print("LBA UI overlays: title backdrop isolated, in-game overlays transparent")
	ui.free()
	quit(0)


func _fail(ui: Node, message: String) -> void:
	push_error(message)
	ui.free()
	quit(1)
