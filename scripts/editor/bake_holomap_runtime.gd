extends SceneTree

# Make a distribution-safe runtime scene from the editor workbench.
# The original planet/character are deliberately not saved into the runtime .tscn.
const AUTHORING := "res://scenes/holomap_authoring/TwinsunAuthoring.tscn"
const RUNTIME := "res://scenes/holomap_authoring/TwinsunRuntime.tscn"

func _initialize() -> void:
	if not ResourceLoader.exists(AUTHORING):
		push_error("Holomap authoring scene missing: " + AUTHORING)
		quit.call_deferred(1)
		return
	var original := load(AUTHORING) as PackedScene
	if original == null:
		push_error("Holomap authoring scene cannot be loaded")
		quit.call_deferred(1)
		return
	var copy := original.instantiate() as Node3D
	if copy == null:
		quit.call_deferred(1)
		return
	copy.name = "TwinsunRuntime"
	var globe := copy.get_node_or_null("GlobeAlignment/Twinsun") as MeshInstance3D
	if globe == null:
		push_error("GlobeAlignment/Twinsun missing")
		copy.free()
		quit.call_deferred(1)
		return
	# Remove original-game mesh, texture, and its palette from the saved runtime.
	globe.mesh = null
	globe.material_override = null
	globe.material_overlay = null
	var character := copy.get_node_or_null("LocationsAlignment/TwinsenPlacement/ModelAlignment/TwinsenOriginalModel")
	if character != null:
		character.get_parent().remove_child(character)
		character.free()
	# Editor-only markers and labels should not render in the game.
	var locations := copy.get_node_or_null("LocationsAlignment/Locations") as Node3D
	if locations == null:
		push_error("Missing Locations node")
		copy.free()
		quit.call_deferred(1)
		return
	var count := 0
	for location in locations.get_children():
		if not location is Node3D:
			continue
		var label_id := -1
		if location.has_meta("lba_location_id"):
			label_id = int(location.get_meta("lba_location_id"))
		else:
			var prefix := str(location.name).substr(0, 3)
			if prefix.is_valid_int():
				label_id = int(prefix)
		if label_id >= 0:
			location.set_meta("lba_location_id", label_id)
			count += 1
		for sub_name in ["MarkerPreview", "LocationLabel"]:
			var sub := location.get_node_or_null(sub_name)
			if sub != null:
				location.remove_child(sub)
				sub.free()
	# The preview camera is only useful in the authoring editor.
	var camera := copy.get_node_or_null("EditorCamera")
	if camera != null:
		copy.remove_child(camera)
		camera.free()
	if count != 150:
		push_error("Expected 150 Holomap locations, found %d" % count)
		copy.free()
		quit.call_deferred(1)
		return
	_fix_ownership(copy, copy)
	var result := PackedScene.new()
	var err := result.pack(copy)
	if err == OK:
		err = ResourceSaver.save(result, RUNTIME)
	copy.free()
	result = null
	if err != OK:
		push_error("Could not save sanitized runtime Holomap: %s" % error_string(err))
		quit.call_deferred(1)
		return
	print("Baked safe Holomap: ", RUNTIME, " with ", count, " authored location transforms")
	quit.call_deferred(0)

func _fix_ownership(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_fix_ownership(child, scene_root)
