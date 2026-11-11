class_name LBASpriteRenderer
extends RefCounted

# SPRITES.HQR supplies the original imagery. For scene actors, collision ZVs
# now form visual proxies with UVs projected from the fixed LBA camera.
# Game extras and speech bubbles deliberately retain their billboard path.
const HQR := preload("res://scripts/import/hqr_reader.gd")
const GRAPH := preload("res://scripts/import/lba1_brick_decoder.gd")
const GRID := preload("res://scripts/render/lba_grid_renderer.gd")
const COORD := preload("res://scripts/render/lba_coordinates.gd")
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const SPRITE_PROJECTION_SHADER := preload("res://shaders/lba_sprite_projection.gdshader")

var _resources: Dictionary = {}
var _failed: Dictionary = {}
var _proxy_meshes: Dictionary = {}


func create_instance(data_dir: String, sprite_id: int,
		offset_x: int = 0, offset_y: int = 0, mode: String = "billboard",
		collision: Dictionary = {}, platform_taper: float = 0.15,
		visual_overhang: float = 0.0, visual_inset: float = 0.0,
		depth_bias: float = 0.0) -> MeshInstance3D:
	var resource := _get_sprite(data_dir, sprite_id)
	if resource.is_empty():
		return null
	var center_x := float(offset_x) + float(resource["width"]) * 0.5
	var center_y := float(offset_y) + float(resource["height"]) * 0.5
	var effective_mode := mode
	if mode != "billboard" and not has_valid_collision(collision):
		# Missing or invalid native ZV: remain visible, rather than invent
		# geometry from the sprite's screen bounding rectangle.
		effective_mode = "billboard"
	var visual := MeshInstance3D.new()
	visual.name = "Sprite_%d" % sprite_id
	visual.mesh = resource["mesh"] if effective_mode == "billboard" else _collision_mesh(
		data_dir, sprite_id, resource, effective_mode, collision, center_x, center_y,
		platform_taper, visual_overhang, visual_inset)
	if effective_mode == "billboard":
		visual.material_override = resource["material"]
	else:
		# Per-instance material so different actors can have different depth bias.
		var projected: ShaderMaterial = (resource["projection_material"] as ShaderMaterial).duplicate() as ShaderMaterial
		# View-space pushback: independent of reversed-Z precision, and works
		# with both the orthographic LBA camera and a mildly perspective camera.
		projected.set_shader_parameter("proxy_view_pushback", clampf(depth_bias, 0.0, 0.25))
		visual.material_override = projected
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.set_meta("offset_x", center_x)
	visual.set_meta("offset_y", center_y)
	visual.set_meta("render_mode", effective_mode)
	visual.set_meta("collision", collision.duplicate())
	visual.set_meta("platform_taper", platform_taper)
	visual.set_meta("visual_overhang", visual_overhang)
	visual.set_meta("visual_inset", visual_inset)
	visual.set_meta("depth_bias", depth_bias)
	visual.set_meta("source_width", float(resource["width"]))
	visual.set_meta("source_height", float(resource["height"]))
	return visual


func sprite_transform(world_position: Vector3, pixel_x: float, pixel_y: float) -> Transform3D:
	var facing: Basis = GRID._camera_facing_basis()
	return Transform3D(facing, world_position + facing.x * pixel_x * GRID.PIXEL_SIZE
		- facing.y * pixel_y * GRID.PIXEL_SIZE)


func scene_sprite_transform(world_position: Vector3, pixel_x: float,
		pixel_y: float, mode: String) -> Transform3D:
	if mode == "billboard":
		return sprite_transform(world_position, pixel_x, pixel_y)
	# Geometry is already expressed as world-axis-aligned points relative
	# to the actor; no camera-facing rotation should ever be applied.
	return Transform3D(Basis.IDENTITY, world_position)


func has_valid_collision(zv: Dictionary) -> bool:
	if zv.is_empty():
		return false
	for key in ["xmin", "xmax", "ymin", "ymax", "zmin", "zmax"]:
		if not zv.has(key):
			return false
	# The original game sometimes has unset / sentinel ZV bounds.
	for pair in [["xmin", "xmax"], ["ymin", "ymax"], ["zmin", "zmax"]]:
		var lo := int(zv[pair[0]])
		var hi := int(zv[pair[1]])
		if lo > hi or lo < -30000 or hi > 30000:
			return false
	return true


func choose_collision_mode(zv: Dictionary) -> String:
	if not has_valid_collision(zv):
		return "billboard"
	var dims := Vector3(
		float(int(zv["xmax"]) - int(zv["xmin"])) * COORD.CELL_XZ / 512.0,
		float(int(zv["ymax"]) - int(zv["ymin"])) * COORD.CELL_Y / 256.0,
		float(int(zv["zmax"]) - int(zv["zmin"])) * COORD.CELL_XZ / 512.0)
	var widest: float = maxf(dims.x, dims.z)
	var thinnest: float = minf(dims.x, dims.z)
	# Low, broad collision volume: platform with tapered visual sides.
	if dims.y < widest * 0.34 and thinnest > widest * 0.30:
		return "platform"
	# Tall, thin X/Z volume: door or gate plane.
	if thinnest < widest * 0.20 and dims.y > thinnest * 2.0:
		return "vertical_x" if dims.x >= dims.z else "vertical_z"
	return "box"


func _collision_mesh(data_dir: String, sprite_id: int, resource: Dictionary,
		mode: String, zv: Dictionary, center_x: float, center_y: float,
		platform_taper: float, visual_overhang: float, visual_inset: float) -> ArrayMesh:
	var key: String = "%s:%d:%s:%s:%.3f:%.4f:%.4f" % [data_dir, sprite_id, mode,
		str(zv), platform_taper, visual_overhang, visual_inset]
	if _proxy_meshes.has(key):
		return _proxy_meshes[key]
	var lo := COORD.native_position(int(zv["xmin"]), int(zv["ymin"]), int(zv["zmin"]))
	var hi := COORD.native_position(int(zv["xmax"]), int(zv["ymax"]), int(zv["zmax"]))
	# v50c: visual geometry may extend past collision; physics remains unchanged.
	var pad: float = clampf(visual_overhang, 0.0, 2.0)
	var x0: float = lo.x - pad
	var x1: float = hi.x + pad
	var y0: float = lo.y
	var y1: float = hi.y
	var z0: float = lo.z - pad
	var z1: float = hi.z + pad
	# Shrink ONLY the visual proxy's thickness. The simulation collision
	# remains exactly as it was in the original LBA engine.
	var inset: float = clampf(visual_inset, 0.0, 0.5)
	if mode == "platform":
		var platform_depth_delta: float = minf(inset, maxf((y1 - y0) * 0.40, 0.0))
		y0 += platform_depth_delta
		y1 -= platform_depth_delta
	elif mode == "horizontal":
		y1 -= minf(inset, maxf((y1 - y0) * 0.80, 0.0))
	elif mode == "box":
		# Collision-box proportions vary; inset the thinnest axis only.
		var width_x: float = x1 - x0
		var height_y: float = y1 - y0
		var depth_z: float = z1 - z0
		if height_y <= width_x and height_y <= depth_z:
			var box_depth_y: float = minf(inset, maxf(height_y * 0.40, 0.0))
			y0 += box_depth_y
			y1 -= box_depth_y
		elif width_x <= depth_z:
			var box_depth_x: float = minf(inset, maxf(width_x * 0.40, 0.0))
			x0 += box_depth_x
			x1 -= box_depth_x
		else:
			var box_depth_z: float = minf(inset, maxf(depth_z * 0.40, 0.0))
			z0 += box_depth_z
			z1 -= box_depth_z
	# ZV can be exactly planar. Give truly flat collision a minimal
	# thickness solely for the visual mesh, not the engine physics.
	if x1 - x0 < 0.01:
		x0 -= 0.005
		x1 += 0.005
	if z1 - z0 < 0.01:
		z0 -= 0.005
		z1 += 0.005
	if y1 - y0 < 0.01:
		y1 = y0 + 0.01
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var facing: Basis = COORD.camera_facing_basis()
	var source_width: float = float(resource["width"])
	var source_height: float = float(resource["height"])
	var left: float = center_x - source_width * 0.5
	var top: float = center_y - source_height * 0.5
	# Project each proxy vertex back to the original fixed-isometric
	# image. NO screen-space stretched quad and NO UV repetition.
	if mode == "horizontal":
		_add_proxy_face(vertices, uvs, indices,
			[Vector3(x0,y1,z0), Vector3(x1,y1,z0), Vector3(x1,y1,z1), Vector3(x0,y1,z1)],
			Vector3.UP, facing, left, top, source_width, source_height)
	elif mode == "vertical_x":
		var zmid := (z0 + z1) * 0.5
		_add_proxy_face(vertices, uvs, indices,
			[Vector3(x0,y0,zmid), Vector3(x1,y0,zmid), Vector3(x1,y1,zmid), Vector3(x0,y1,zmid)],
			Vector3(0,0,1), facing, left, top, source_width, source_height)
	elif mode == "vertical_z":
		var xmid := (x0 + x1) * 0.5
		_add_proxy_face(vertices, uvs, indices,
			[Vector3(xmid,y0,z0), Vector3(xmid,y0,z1), Vector3(xmid,y1,z1), Vector3(xmid,y1,z0)],
			Vector3(1,0,0), facing, left, top, source_width, source_height)
	else:
		var side_inset := 0.0 if mode != "platform" else clampf(platform_taper, 0.0, 0.40)
		var dx := (x1-x0)*side_inset
		var dz := (z1-z0)*side_inset
		# A shallow truncated pyramid has a full-size flat top and tapered
		# sides towards the lower collision footprint.
		var top_corners := [Vector3(x0,y1,z0), Vector3(x1,y1,z0),
			Vector3(x1,y1,z1), Vector3(x0,y1,z1)]
		var bottom_corners := [Vector3(x0+dx,y0,z0+dz), Vector3(x1-dx,y0,z0+dz),
			Vector3(x1-dx,y0,z1-dz), Vector3(x0+dx,y0,z1-dz)]
		_add_proxy_face(vertices, uvs, indices, top_corners, Vector3.UP, facing,
			left, top, source_width, source_height)
		# Only surfaces that face the original canonical camera receive the
		# projected sprite. Reprojecting back faces duplicates its artwork.
		for side in range(4):
			var other := (side + 1) % 4
			var edge: Vector3 = top_corners[other] - top_corners[side]
			var outward := Vector3(edge.z, 0.0, -edge.x).normalized()
			if outward.dot(facing.z) < 0.005:
				continue
			_add_proxy_face(vertices, uvs, indices,
				[bottom_corners[side], bottom_corners[other], top_corners[other], top_corners[side]],
				outward, facing, left, top, source_width, source_height)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_proxy_meshes[key] = result
	return result


func _add_proxy_face(vertices: PackedVector3Array, uvs: PackedVector2Array,
		indices: PackedInt32Array, corners: Array, _normal: Vector3,
		facing: Basis, left: float, top: float, width: float, height: float) -> void:
	var base := vertices.size()
	for point in corners:
		var pos: Vector3 = point
		vertices.append(pos)
		uvs.append(Vector2(
			(pos.dot(facing.x) / GRID.PIXEL_SIZE - left) / width,
			(-pos.dot(facing.y) / GRID.PIXEL_SIZE - top) / height))
	# Culling is disabled on the sprite shader: winding is irrelevant,
	# but depth testing against real grid and character geometry remains.
	indices.append_array(PackedInt32Array([base,base+1,base+2, base,base+2,base+3]))


func create_special_effect(kind: int) -> MeshInstance3D:
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
	var projected := ShaderMaterial.new()
	projected.shader = SPRITE_PROJECTION_SHADER
	projected.set_shader_parameter("sprite_texture", (material as StandardMaterial3D).albedo_texture)
	var result := {"mesh": quad, "material": material,
		"projection_material": projected,
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
