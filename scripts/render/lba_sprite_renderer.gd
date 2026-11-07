class_name LBASpriteRenderer
extends RefCounted

# One decoder/cache for original scene sprites, extras, pickups and dialogue
# bubbles. Original SPRITES.HQR entries contain a uint32 graph offset followed
# by the same palettized RLE graph data used by LBA1 bricks.
const HQR := preload("res://scripts/import/hqr_reader.gd")
const GRAPH := preload("res://scripts/import/lba1_brick_decoder.gd")
const GRID := preload("res://scripts/render/lba_grid_renderer.gd")
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")

var _resources: Dictionary = {}
var _palettes: Dictionary = {}
var _failed: Dictionary = {}


func create_instance(data_dir: String, sprite_id: int,
		offset_x: int = 0, offset_y: int = 0) -> MeshInstance3D:
	var resource := _get_sprite(data_dir, sprite_id)
	if resource.is_empty():
		return null
	var visual := MeshInstance3D.new()
	visual.name = "Sprite_%d" % sprite_id
	visual.mesh = resource["mesh"]
	visual.material_override = resource["material"]
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Native PtrZvExtra offsets already specify the top-left sprite position.
	# Adding the graph hot spot again double-offsets moving platforms and NPC sprites.
	visual.set_meta("offset_x", float(offset_x) + float(resource["width"]) * 0.5)
	visual.set_meta("offset_y", float(offset_y) + float(resource["height"]) * 0.5)
	return visual


func sprite_transform(world_position: Vector3, pixel_x: float, pixel_y: float) -> Transform3D:
	var facing: Basis = GRID._camera_facing_basis()
	# Native graph positions are screen-pixel offsets from the projected point.
	return Transform3D(facing, world_position +
		facing.x * float(pixel_x) * GRID.PIXEL_SIZE -
		facing.y * float(pixel_y) * GRID.PIXEL_SIZE)


func create_special_effect(kind: int) -> MeshInstance3D:
	# Aff2DShape in EXTRA.C draws closed LINES, never a filled sprite.
	# The original BigStar has zoom=4/16; Poff grows from 1/16 to 32/16.
	var points := PackedVector2Array()
	if kind == 0:
		points = PackedVector2Array([
			Vector2(0, -20), Vector2(4, -6), Vector2(19, -6),
			Vector2(7, 2), Vector2(12, 16), Vector2(0, 7),
			Vector2(-12, 16), Vector2(-7, 2), Vector2(-19, -6), Vector2(-4, -6)])
	else:
		points = PackedVector2Array([
			Vector2(0, -20), Vector2(6, -16), Vector2(8, -10),
			Vector2(14, -12), Vector2(20, -4), Vector2(18, 4),
			Vector2(12, 4), Vector2(16, 8), Vector2(8, 16),
			Vector2(2, 12), Vector2(-4, 18), Vector2(-10, 16),
			Vector2(-12, 8), Vector2(-16, 10), Vector2(-20, 4),
			Vector2(-12, -8), Vector2(-6, -6), Vector2(-10, -12)])
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(points.size()):
		var start: Vector2 = points[index]
		var end: Vector2 = points[(index + 1) % points.size()]
		# World scale is applied by special_transform(), so base mesh is 1:1 pixels.
		lines.surface_add_vertex(Vector3(start.x * GRID.PIXEL_SIZE,
			-start.y * GRID.PIXEL_SIZE, 0.0))
		lines.surface_add_vertex(Vector3(end.x * GRID.PIXEL_SIZE,
			-end.y * GRID.PIXEL_SIZE, 0.0))
	lines.surface_end()
	var visual := MeshInstance3D.new()
	visual.name = "Special_%d" % kind
	visual.mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	material.albedo_color = Color(1.0, 0.96, 0.82)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return visual


func special_transform(position: Vector3, scale_factor: float, angle: float) -> Transform3D:
	var facing: Basis = GRID._camera_facing_basis()
	var rotation := Basis(facing.z, angle)
	return Transform3D(facing * rotation * Basis.from_scale(Vector3.ONE * scale_factor), position)

func _get_sprite(data_dir: String, sprite_id: int) -> Dictionary:
	var key := "%s:%d" % [data_dir, sprite_id]
	if _resources.has(key):
		return _resources[key]
	if _failed.has(key):
		return {}
	var graph: Dictionary = VISUAL_CACHE.get_resource(data_dir, "sprite", sprite_id)
	if not graph.get("ok", false):
		_failed[key] = true
		push_warning("LBA sprite %d: %s" % [sprite_id, graph.get("error", "unavailable")])
		return {}
	var quad := QuadMesh.new()
	quad.size = Vector2(graph["width"], graph["height"]) * GRID.PIXEL_SIZE
	var material := _material(ImageTexture.create_from_image(graph["image"]))
	var result := {"mesh": quad, "material": material,
		"hot_x": graph["hot_x"], "hot_y": graph["hot_y"],
		"width": graph["width"], "height": graph["height"]}
	_resources[key] = result
	return result


func _material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	return material
