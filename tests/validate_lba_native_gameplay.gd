extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		push_error("Set LBA_TEST_DATA_PATH to staged original game data")
		quit(1)
		return
	var app := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	root.add_child(app)
	var media_cache := OS.get_environment("LBA_TEST_MEDIA_CACHE")
	if not media_cache.is_empty():
		if not app.get_node("GameUI").configure_media(media_cache, data_dir):
			_fail(app, "The original intro media did not configure")
			return
		var plasma := app.get_node("GameUI/Frame/MainMenu/Center/Panel/Contents/NewGame/Plasma") as ColorRect
		var material := plasma.material as ShaderMaterial
		var palette := material.get_shader_parameter("original_palette") as Texture2D
		if palette == null or not material.get_shader_parameter("use_original_palette"):
			_fail(app, "Menu plasma did not receive the original LBA1 palette")
			return
		if not palette.get_image().get_pixel(0, 0).is_equal_approx(Color8(7, 11, 23)):
			_fail(app, "Menu plasma palette does not match original entry 64")
			return
		app._on_command(&"new_game", null)
		if not app.get_node("GameUI")._media_sequence.is_active():
			_fail(app, "New Game did not enter the intro")
			return
		app.get_node("GameUI")._media_sequence.skip()
	else:
		app._start_native_game()
	for attempt in range(250):
		await create_timer(0.04).timeout
		if app._game_started:
			break
	if not app._game_started:
		_fail(app, "New Game did not reach native-driven Godot gameplay")
		return
	var world := app.get_node("World3D") as LBAWorld3D
	if world.get_node("Bricks").get_child_count() == 0:
		_fail(app, "Native scene did not build Godot grid tiles")
		return
	var player := world.get_node_or_null("Actors/Actor_0") as Node3D
	if player == null or player.get_node_or_null("Polygons") == null:
		_fail(app, "Native player did not build a Godot BODY mesh")
		return
	var host: LBANativeHost = app.get_node("NativeHost")
	var polygon_mesh: Mesh = (player.get_node("Polygons") as MeshInstance3D).mesh
	var skeleton := player.get_node("Skeleton") as Skeleton3D
	var earlier: Dictionary = host.get_snapshot()["actors"][0]
	var earlier_bone := skeleton.get_bone_global_pose(1)
	var interpolated := false
	for sample in range(35):
		await create_timer(0.025).timeout
		var current: Dictionary = host.get_snapshot()["actors"][0]
		var current_bone := skeleton.get_bone_global_pose(1)
		if int(current["frame"]) == int(earlier["frame"]) \
				and current["pose_groups"] != earlier["pose_groups"] \
				and current_bone != earlier_bone:
			interpolated = true
			break
		earlier = current
		earlier_bone = current_bone
	if not interpolated:
		_fail(app, "Native animation did not update Godot bones between keyframes")
		return
	if (player.get_node("Polygons") as MeshInstance3D).mesh != polygon_mesh:
		_fail(app, "Animation rebuilt the BODY mesh")
		return
	var before := player.position
	Input.action_press(&"lba_forward")
	await create_timer(2.0).timeout
	Input.action_release(&"lba_forward")
	if player.position.distance_to(before) < 0.01:
		_fail(app, "Godot Input Map did not move the native player")
		return
	app._on_command(&"pause_game", null)
	await create_timer(0.2).timeout
	var pause_tick := int(host.get_snapshot().get("tick", -1))
	await create_timer(0.4).timeout
	var held_tick := int(host.get_snapshot().get("tick", -1))
	if held_tick != pause_tick:
		_fail(app, "Godot pause menu did not freeze native gameplay time")
		return
	app._on_command(&"resume_game", null)
	print("LBA gameplay: native scene 0, Godot grid and actors, Input Map movement verified")
	app.get_node("NativeHost").stop()
	app.free()
	quit(0)


func _fail(app: Node, message: String) -> void:
	push_error(message)
	app.get_node("NativeHost").stop()
	app.free()
	quit(1)
