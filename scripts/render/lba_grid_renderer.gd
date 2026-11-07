class_name LBAGridRenderer
extends RefCounted

const GRID := preload("res://scripts/import/lba1_grid_decoder.gd")
const BRICK := preload("res://scripts/import/lba1_brick_decoder.gd")
const HQR := preload("res://scripts/import/hqr_reader.gd")
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const COORD := preload("res://scripts/render/lba_coordinates.gd")
const TILE_SHADER := preload("res://shaders/lba_tile.gdshader")

# Original Map2Screen projects one X/Z cell to (24,12) pixels and one Y cell
# 15 pixels upward. A 30-degree isometric camera reproduces those spacings.
const PIXEL_SIZE := COORD.PIXEL_SIZE
const CELL_XZ := COORD.CELL_XZ
const CELL_Y := COORD.CELL_Y


static func build_scene(data_dir: String, scene_index: int, camera: Camera3D,
		overlay_index: int = -1) -> Dictionary:
	var kind := "grid" if overlay_index < 0 else "grid_variant"
	var entry_id := scene_index if overlay_index < 0 else scene_index * 256 + overlay_index + 1
	var scene: Dictionary = VISUAL_CACHE.get_resource(data_dir, kind, entry_id)
	if not scene.get("ok", false):
		return scene
	var palette_entry: Dictionary = VISUAL_CACHE.get_resource(data_dir, "palette", 0)
	if not palette_entry.get("ok", false):
		return {"ok": false, "error": "LBA1 palette is unavailable"}
	var palette: PackedByteArray = palette_entry["data"]
	var groups: Dictionary = {}
	var brick_ids: PackedInt32Array = scene["brick_ids"]
	for index in range(brick_ids.size()):
		var brick_id := brick_ids[index]
		if brick_id < 0:
			continue
		if not groups.has(brick_id):
			groups[brick_id] = []
		(groups[brick_id] as Array).append(index)

	var root := Node3D.new()
	root.name = "SceneGrid_%d_GRM_%d" % [scene_index, overlay_index]
	var facing := _camera_facing_basis()
	for brick_id in groups:
		var brick: Dictionary = VISUAL_CACHE.get_resource(data_dir, "brick", brick_id)
		if not brick.get("ok", false):
			root.free()
			return {"ok": false, "error": brick.get("error", "Cannot decode BRK %d" % brick_id)}
		var texture := ImageTexture.create_from_image(brick["image"])
		var material := ShaderMaterial.new()
		material.shader = TILE_SHADER
		material.set_shader_parameter("albedo_texture", texture)
		var quad := QuadMesh.new()
		quad.size = Vector2(brick["width"], brick["height"]) * PIXEL_SIZE
		var positions: Array = groups[brick_id]
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = quad
		instances.instance_count = positions.size()
		var image_center: Vector3 = COORD.grid_graph_center(
			int(brick["hot_x"]), int(brick["hot_y"]),
			int(brick["width"]), int(brick["height"]))
		material.set_shader_parameter("graph_center_offset", image_center)
		for instance_index in range(positions.size()):
			var cell_index: int = positions[instance_index]
			var z := cell_index / (GRID.WIDTH * GRID.HEIGHT)
			var x := (cell_index / GRID.HEIGHT) % GRID.WIDTH
			var y := cell_index % GRID.HEIGHT
			var position: Vector3 = COORD.grid_cell(x, y, z)
			instances.set_instance_transform(instance_index, Transform3D(facing, position + image_center))
		var node := MultiMeshInstance3D.new()
		node.name = "Brick_%d" % brick_id
		node.multimesh = instances
		node.material_override = material
		root.add_child(node)
	if camera != null:
		configure_preview_camera(camera)
	return {
		"ok": true,
		"node": root,
		"visible_count": scene["visible_count"],
		"unique_bricks": groups.size(),
	}


static func configure_preview_camera(camera: Camera3D) -> void:
	var center := Vector3(32.0 * CELL_XZ, 2.0 * CELL_Y, 32.0 * CELL_XZ)
	var from_center := Vector3(cos(deg_to_rad(30.0)) / sqrt(2.0), 0.5,
		cos(deg_to_rad(30.0)) / sqrt(2.0))
	camera.position = center + from_center * 30.0
	camera.look_at(center, Vector3.UP)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0


static func _camera_facing_basis() -> Basis:
	return COORD.camera_facing_basis()
