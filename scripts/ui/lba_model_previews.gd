class_name LBAModelPreviews
extends Node

const CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const MESH := preload("res://scripts/render/character_mesh_builder.gd")
const POSE := preload("res://scripts/animation/lba1_pose.gd")
const LBA_LIGHTING := preload("res://scripts/render/lba_character_lighting.gd")

var data_dir := ""
var _views: Dictionary = {}
var _shared_geometry: Dictionary = {}
var _active_purpose := ""
var _selected_views: Dictionary = {"mode": 0, "inventory": 0}

func _process(delta: float) -> void:
	for key in _views:
		var purpose := str(key).get_slice(":", 2)
		var family := "mode" if purpose.begins_with("mode") else purpose
		if family != _active_purpose or family not in ["mode", "inventory", "pickup"]:
			continue
		if family == "mode" and purpose != "mode%d" % int(_selected_views["mode"]):
			continue
		if family == "inventory" and not str(key).begins_with("inventory_model:%d:" % int(_selected_views["inventory"])):
			continue
		var view: Dictionary = _views[key]
		(view["pivot"] as Node3D).rotation.y += delta * 1.4
		if str(view["body"].get("game", "LBA1")) == "LBA1":
			LBA_LIGHTING.apply_to_model(view["model"] as Node3D,
				LBA_LIGHTING.capture(view["world"] as Node3D))

func set_selected_preview(purpose: String, index: int) -> void:
	_selected_views[purpose] = index



func configure(path: String) -> void:
	if data_dir == path:
		return
	data_dir = path
	for view in _views.values():
		(view["viewport"] as SubViewport).queue_free()
	_views.clear()
	_shared_geometry.clear()


func set_active_purpose(purpose: String) -> void:
	_active_purpose = purpose
	for key in _views:
		var viewport := _views[key]["viewport"] as SubViewport
		var view_purpose := str(key).get_slice(":", 2)
		var matches := not purpose.is_empty() and (view_purpose == purpose or
			(purpose == "mode" and view_purpose.begins_with("mode")))
		viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS
			if matches else SubViewport.UPDATE_DISABLED)


func model_texture(kind: String, model_id: int, purpose: String,
		size: Vector2i = Vector2i(96, 84)) -> Texture2D:
	if data_dir.is_empty() or model_id < 0:
		return null
	var key := "%s:%d:%s" % [kind, model_id, purpose]
	if _views.has(key):
		return (_views[key]["viewport"] as SubViewport).get_texture()
	var body: Dictionary = CACHE.get_resource(data_dir, kind, model_id)
	var palette_entry: Dictionary = CACHE.get_resource(data_dir, "palette", 0)
	if not body.get("ok", false) or not palette_entry.get("ok", false):
		return null
	var viewport := SubViewport.new()
	viewport.name = "Preview_%s_%d_%s" % [kind, model_id, purpose]
	viewport.size = size
	viewport.transparent_bg = true
	# A SubViewport otherwise inherits the parent World3D, so its camera
	# can render the ENTIRE LEVEL behind the supposed item preview.
	viewport.own_world_3d = true
	# UPDATE_ONCE is too early here: the preview mesh and Camera3D are
	# instantiated only after the viewport enters the tree.  The first
	# frame could therefore be an empty transparent texture forever.
	# The ItemList icon pipeline does not reliably participate in the viewport's
	# visibility test, so UPDATE_WHEN_VISIBLE can leave the texture black.
	# Render only the currently open panel's viewports, not all 28 every frame.
	viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS
		if purpose == _active_purpose or (_active_purpose == "mode" and purpose.begins_with("mode"))
		else SubViewport.UPDATE_DISABLED)
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)
	for point in body["pose_points"]:
		var p: Vector3 = point / 512.0
		bounds_min = bounds_min.min(p)
		bounds_max = bounds_max.max(p)
	var center := (bounds_min + bounds_max) * 0.5
	var extent := maxf((bounds_max - bounds_min).length(), 0.75)
	var geometry_key := "%s:%d" % [kind, model_id]
	if not _shared_geometry.has(geometry_key):
		_shared_geometry[geometry_key] = {}
	var model: Node3D = MESH.build_static_pose(body, palette_entry["data"], null,
		purpose.begins_with("mode"), _shared_geometry[geometry_key])
	model.position = -center
	var pivot := Node3D.new()
	world.add_child(pivot)
	pivot.add_child(model)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent * (1.27 if purpose.begins_with("mode") else 1.45)
	world.add_child(camera)
	camera.position = Vector3(extent, extent * 1.15, extent * 1.4)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, -0.6, 0.0)
	world.add_child(light)
	_views[key] = {"viewport": viewport, "model": model, "pivot": pivot, "body": body, "world": world}
	if str(body.get("game", "LBA1")) == "LBA1":
		LBA_LIGHTING.apply_to_model(model, LBA_LIGHTING.capture(world))
	# Do not bake an empty first render into an inventory icon. The viewport
	# will update while the TextureRect/ItemList actually displays its texture.
	return viewport.get_texture()


func update_player_pose(model_id: int, groups: PackedInt32Array) -> void:
	var key := "body:%d:mode%d" % [model_id, int(_selected_views["mode"])]
	if not _views.has(key) or groups.is_empty():
		return
	var view: Dictionary = _views[key]
	var pose: Dictionary = POSE.from_native_groups(view["body"], groups)
	if not pose.is_empty():
		MESH.update_pose(view["model"], view["body"], pose)
