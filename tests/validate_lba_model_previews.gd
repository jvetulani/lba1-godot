extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		push_error("LBA_TEST_DATA_PATH is required")
		quit(1)
		return
	var ui := (load("res://scenes/ui/GameUI.tscn") as PackedScene).instantiate() as GameUI
	root.add_child(ui)
	ui.configure_game_models(data_dir)
	var flags := PackedInt32Array()
	flags.resize(28)
	flags[0] = 1
	flags[1] = 1
	ui.set_inventory_state(flags)
	var items := ui.get_node("Frame/Inventory/Center/Panel/Contents/Entries") as ItemList
	if items.item_count != 28 or items.get_item_icon(0) == null or items.get_item_icon(1) == null:
		_fail(ui, "Inventory did not render original item models in its 28-slot grid")
		return
	if items.is_item_selectable(2):
		_fail(ui, "Unowned inventory slots are selectable")
		return
	ui.set_player_preview(0, PackedInt32Array())
	var twinsen := ui.get_node("Frame/ModeMenu/Center/Panel/Contents/Twinsen") as TextureRect
	if twinsen.texture == null:
		_fail(ui, "Ctrl selector has no Twinsen model viewport")
		return
	ui.set_dialogue("Found item", 0)
	var pickup := ui.get_node("Frame/Dialogue/ItemPreview") as TextureRect
	if not pickup.visible or pickup.texture == null or pickup.texture == items.get_item_icon(0):
		_fail(ui, "Pickup preview is missing its independent viewport")
		return
	await process_frame
	await process_frame
	var preview_root := ui.find_child("Preview_inventory_model_0_pickup", true, false) as SubViewport
	if preview_root == null or preview_root.size != Vector2i(220, 220) \
			or not preview_root.transparent_bg or not preview_root.own_world_3d \
			or preview_root.find_children("*", "MeshInstance3D", true, false).is_empty() \
			or preview_root.find_children("*", "Camera3D", true, false).size() != 1:
		_fail(ui, "Pickup SubViewport needs a transparent model scene and dedicated camera")
		return
	for purpose in ["inventory", "mode"]:
		var view := ui.find_child("Preview_%s_0_%s" % ["body" if purpose == "mode" else "inventory_model", purpose], true, false) as SubViewport
		if view == null or not view.transparent_bg or not view.own_world_3d or view.find_children("*", "Camera3D", true, false).size() != 1:
			_fail(ui, "%s preview lacks its transparent viewport and camera" % purpose)
			return
	print("LBA model previews: inventory grid, Ctrl Twinsen, pickup SubViewports render")
	ui.free()
	await process_frame
	quit(0)


func _fail(ui: Node, message: String) -> void:
	push_error(message)
	ui.free()
	quit(1)
