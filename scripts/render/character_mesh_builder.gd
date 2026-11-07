class_name CharacterMeshBuilder
extends RefCounted

const UNIT_SCALE := 1.0 / 512.0
const CHARACTER_SHADER := preload("res://shaders/lba_character.gdshader")
const LBA2_CHARACTER_SHADER := preload("res://shaders/lba2_character.gdshader")
const LBA2_SPECTRAL_OVERLAY := preload("res://shaders/lba2_spectral_overlay.gdshader")
const LBA2_FIREBALL := preload("res://shaders/lba2_fireball.gdshader")
const LBA2_TRANSLUCENT_SOLID := preload("res://shaders/lba2_translucent_solid.gdshader")
const LBA2_APPEARANCE := preload("res://scripts/render/lba2_appearance.gd")
const LBA1_FACE_MODES := preload("res://scripts/render/lba1_face_modes.gd")
const LBA1_TRANSPARENT_FACE := preload("res://shaders/lba1_transparent_face.gdshader")
const WIREFRAME_SHADER := preload("res://shaders/wireframe_overlay.gdshader")
const BONE_DEBUG := preload("res://scripts/render/bone_debug_overlay.gd")


static func build_static_pose(body: Dictionary, palette_bytes: PackedByteArray, atlas_override: Texture2D = null) -> Node3D:
	var character := Node3D.new()
	character.name = "%sBody" % body.get("game", "LBA1")
	var is_lba2: bool = body.get("game", "LBA1") == "LBA2"
	var palette_texture := _make_palette_texture(palette_bytes, is_lba2 or body.get("game", "") == "LBA2-96" or str(body.get("game", "")).begins_with("AITD"))
	var atlas_texture: Texture2D = atlas_override
	var shade_texture: Texture2D = null
	if atlas_texture == null and body.has("texture_atlas"):
		atlas_texture = ImageTexture.create_from_image(Image.create_from_data(256, 256, false, Image.FORMAT_R8, body["texture_atlas"]))
	if body.has("shade_table"):
		shade_texture = ImageTexture.create_from_image(Image.create_from_data(256, 256, false, Image.FORMAT_R8, body["shade_table"]))
	var points: PackedVector3Array = body["pose_points"]
	var polygons_node := MeshInstance3D.new()
	polygons_node.name = "Polygons"
	polygons_node.mesh = _build_polygon_mesh(body, points, [])
	if is_lba2 and LBA2_APPEARANCE.uses_fireball_glow(body):
		var fire_material := ShaderMaterial.new()
		fire_material.shader = LBA2_FIREBALL
		fire_material.set_shader_parameter("opacity", float(body.get("appearance", {}).get("opacity", 0.58)))
		var low := INF
		var high := -INF
		for point in points:
			low = minf(low, point.y * UNIT_SCALE)
			high = maxf(high, point.y * UNIT_SCALE)
		fire_material.set_shader_parameter("height_range", Vector2(low, maxf(high, low + 0.001)))
		polygons_node.material_override = fire_material
	elif is_lba2 and LBA2_APPEARANCE.uses_translucent_solid(body):
		var effect_material := ShaderMaterial.new()
		effect_material.shader = LBA2_TRANSLUCENT_SOLID
		effect_material.set_shader_parameter("palette_texture", palette_texture)
		effect_material.set_shader_parameter("opacity", body.get("appearance", {}).get("opacity", LBA2_APPEARANCE.SPECTRAL_OPACITY))
		polygons_node.material_override = effect_material
	else:
		polygons_node.material_override = _make_material(palette_texture, -1, is_lba2, atlas_texture, shade_texture, body.get("normal_light_level", 12))
		if body.get("game", "LBA1") == "LBA1":
			polygons_node.material_override.set_shader_parameter("lba1_palette_effects", true)
	if is_lba2 and atlas_texture != null and LBA2_APPEARANCE.uses_spectral_preview(body):
		var overlay := ShaderMaterial.new()
		overlay.shader = LBA2_SPECTRAL_OVERLAY
		overlay.set_shader_parameter("texture_atlas", atlas_texture)
		overlay.set_shader_parameter("opacity", body.get("appearance", {}).get("opacity", LBA2_APPEARANCE.SPECTRAL_OPACITY))
		polygons_node.material_override.next_pass = overlay
	character.add_child(polygons_node)
	var wireframe := MeshInstance3D.new()
	wireframe.name = "Wireframe"
	wireframe.mesh = _build_wire_mesh(body, points)
	var wire_material := ShaderMaterial.new()
	wire_material.shader = WIREFRAME_SHADER
	wireframe.material_override = wire_material
	wireframe.visible = false
	character.add_child(wireframe)
	character.add_child(BONE_DEBUG.create(body))
	if LBA2_APPEARANCE.has_translucent_faces(body):
		var glass := MeshInstance3D.new()
		glass.name = "TranslucentPolygons"
		glass.mesh = _build_polygon_mesh(body, points, [], true)
		var glass_material := ShaderMaterial.new()
		glass_material.shader = LBA2_TRANSLUCENT_SOLID
		glass_material.set_shader_parameter("palette_texture", palette_texture)
		glass_material.set_shader_parameter("opacity", body["appearance"].get("opacity", LBA2_APPEARANCE.SPECTRAL_OPACITY))
		glass.material_override = glass_material
		character.add_child(glass)
	if LBA1_FACE_MODES.has_transparent_faces(body):
		var glass := MeshInstance3D.new()
		glass.name = "LBA1TransparentPolygons"
		glass.mesh = _build_polygon_mesh(body, points, [], true)
		var glass_material := ShaderMaterial.new()
		glass_material.shader = LBA1_TRANSPARENT_FACE
		glass_material.set_shader_parameter("palette_texture", palette_texture)
		glass.material_override = glass_material
		character.add_child(glass)

	for sphere_data in body["spheres"]:
		var sphere := MeshInstance3D.new()
		sphere.name = "Sphere_%d" % sphere_data["center"]
		sphere.set_meta("center_index", sphere_data["center"])
		var radius := float(sphere_data["radius"]) * UNIT_SCALE
		var shape := SphereMesh.new()
		shape.radius = radius
		shape.height = radius * 2.0
		shape.radial_segments = 12
		shape.rings = 6
		sphere.mesh = shape
		sphere.position = points[sphere_data["center"]] * UNIT_SCALE
		sphere.material_override = _make_material(palette_texture, sphere_data["palette_index"], is_lba2)
		character.add_child(sphere)

	for line_data in body["lines"]:
		var line := MeshInstance3D.new()
		line.name = "Line_%d_%d" % [line_data["first"], line_data["second"]]
		line.set_meta("first_index", line_data["first"])
		line.set_meta("second_index", line_data["second"])
		var shape := CylinderMesh.new()
		shape.top_radius = 0.006
		shape.bottom_radius = 0.006
		shape.radial_segments = 4
		line.mesh = shape
		line.material_override = _make_material(palette_texture, line_data["palette_index"], is_lba2)
		character.add_child(line)
		_set_line_pose(line, points[line_data["first"]], points[line_data["second"]])

	return character


static func update_pose(character: Node3D, body: Dictionary, pose: Dictionary) -> void:
	var points: PackedVector3Array = pose["points"]
	var polygon_mesh: MeshInstance3D = character.get_node("Polygons")
	polygon_mesh.mesh = _build_polygon_mesh(body, points, pose["bases"])
	var wireframe: MeshInstance3D = character.get_node("Wireframe")
	if wireframe.visible:
		wireframe.mesh = _build_wire_mesh(body, points)
	var bones: Node3D = character.get_node("Bones")
	if bones.visible:
		BONE_DEBUG.update(bones, body, points)
	if character.has_node("TranslucentPolygons"):
		character.get_node("TranslucentPolygons").mesh = _build_polygon_mesh(body, points, pose["bases"], true)
	if character.has_node("LBA1TransparentPolygons"):
		character.get_node("LBA1TransparentPolygons").mesh = _build_polygon_mesh(body, points, pose["bases"], true)
	for child in character.get_children():
		if child.has_meta("center_index"):
			child.position = points[int(child.get_meta("center_index"))] * UNIT_SCALE
		elif child.has_meta("first_index"):
			_set_line_pose(child, points[int(child.get_meta("first_index"))], points[int(child.get_meta("second_index"))])


static func _set_line_pose(line: MeshInstance3D, first_raw: Vector3, second_raw: Vector3) -> void:
	var first := first_raw * UNIT_SCALE
	var second := second_raw * UNIT_SCALE
	var direction := second - first
	line.visible = direction.length_squared() >= 0.000001
	if not line.visible:
		return
	var shape: CylinderMesh = line.mesh
	shape.height = direction.length()
	line.position = (first + second) * 0.5
	line.quaternion = Quaternion(Vector3.UP, direction.normalized())


static func _build_wire_mesh(body: Dictionary, points: PackedVector3Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var endpoints := PackedFloat32Array()
	var seen := {}
	for polygon in body["polygons"]:
		var indices: PackedInt32Array = polygon["points"]
		for edge in range(indices.size()):
			var first_index: int = indices[edge]
			var second_index: int = indices[(edge + 1) % indices.size()]
			if first_index == second_index:
				continue
			var key := Vector2i(mini(first_index, second_index), maxi(first_index, second_index))
			if seen.has(key):
				continue
			seen[key] = true
			var first := points[first_index] * UNIT_SCALE
			var second := points[second_index] * UNIT_SCALE
			for corner in [0.0, 1.0, 2.0, 2.0, 1.0, 3.0]:
				vertices.append(first)
				endpoints.append_array(PackedFloat32Array([second.x, second.y, second.z, corner]))
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_CUSTOM0] = endpoints
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	return mesh


static func _build_polygon_mesh(body: Dictionary, points: PackedVector3Array, bases: Array, glass_only: bool = false) -> ArrayMesh:
	var normals: PackedVector3Array = body["normals"]
	var normal_divisors: PackedInt32Array = body["normal_divisors"]
	var point_groups: PackedInt32Array = body["point_groups"]
	var vertices := PackedVector3Array()
	var vertex_normals := PackedVector3Array()
	var palette_coordinates := PackedVector2Array()
	var source_normals := PackedFloat32Array()
	var texture_uvs := PackedVector2Array()
	var texture_regions := PackedFloat32Array()
	var rest_positions := PackedFloat32Array()
	var is_lba2: bool = body.get("game", "LBA1") == "LBA2"

	for polygon in body["polygons"]:
		if (LBA2_APPEARANCE.is_translucent_face(body, polygon) or LBA1_FACE_MODES.is_transparent(body, polygon)) != glass_only:
			continue
		var point_indices: PackedInt32Array = polygon["points"]
		var marble_face: bool = body.get("game", "LBA1") == "LBA1" and int(polygon["render_type"]) == 4
		var marble_axis := 0
		var marble_min := INF
		var marble_max := -INF
		if marble_face:
			for point_index in point_indices:
				marble_min = minf(marble_min, points[point_index].x)
				marble_max = maxf(marble_max, points[point_index].x)
			if marble_max - marble_min < 0.001:
				marble_axis = 2
				marble_min = INF
				marble_max = -INF
				for point_index in point_indices:
					marble_min = minf(marble_min, points[point_index].z)
					marble_max = maxf(marble_max, points[point_index].z)
		var normal_indices: PackedInt32Array = polygon["normals"]
		var first := points[point_indices[0]]
		var second := points[point_indices[1]]
		var third := points[point_indices[2]]
		var face_normal := (second - first).cross(third - first).normalized()
		if str(body.get("game", "")).begins_with("AITD"):
			face_normal = -face_normal
		var surface_offset := LBA2_APPEARANCE.surface_offset_for_face(body, polygon)
		if str(body.get("game", "")).begins_with("AITD"):
			surface_offset -= float(polygon.get("surface_layer", 0)) * 0.15 * UNIT_SCALE
		for triangle_index in range(1, point_indices.size() - 1):
			var corners := [0, triangle_index + 1, triangle_index]
			for corner in corners:
				var vertex := points[point_indices[corner]] * UNIT_SCALE
				var rest_position: Vector3 = body["pose_points"][point_indices[corner]] * UNIT_SCALE
				vertex += face_normal * surface_offset
				var texture_offset: float = body.get("appearance", {}).get("textured_surface_offset", 0.0)
				if texture_offset > 0.0 and polygon.get("texture_handle", -1) >= 0:
					var outward := Vector3(vertex.x, 0.0, vertex.z).normalized()
					vertex += outward * texture_offset
				vertices.append(vertex)
				var normal_index := normal_indices[corner]
				var normal := face_normal
				var source_normal := Vector3.ZERO
				var divisor := 1.0
				if normal_index >= 0:
					source_normal = normals[normal_index]
					if not bases.is_empty():
						source_normal = bases[point_groups[point_indices[corner]]] * source_normal
					divisor = 1.0 if is_lba2 else float(normal_divisors[normal_index])
					if source_normal.length_squared() > 0.0:
						normal = source_normal.normalized()
				vertex_normals.append(normal)
				palette_coordinates.append(Vector2(float(polygon["palette_index"]), float(polygon["render_type"])))
				source_normals.append_array(PackedFloat32Array([source_normal.x, source_normal.y, source_normal.z, -1.0 if is_lba2 and polygon.get("clamp_light_ramp", false) else divisor]))
				var texture_uv := Vector2.ZERO
				var texture_region := PackedFloat32Array([0.0, 0.0, 255.0, 255.0])
				if marble_face:
					texture_uv.x = clampf((points[point_indices[corner]][marble_axis] - marble_min) / maxf(marble_max - marble_min, 1.0), 0.0, 1.0)
					texture_region[0] = float(int(polygon["color_word"]) >> 8)
				if polygon.get("texture_handle", -1) >= 0:
					texture_uv = polygon["texture_uvs"][corner]
					var origin: Vector2 = polygon["texture_origin"]
					var mask: Vector2 = polygon["texture_mask"]
					texture_region = PackedFloat32Array([origin.x, origin.y, mask.x, mask.y])
				texture_uvs.append(texture_uv)
				texture_regions.append_array(texture_region)
				rest_positions.append_array(PackedFloat32Array([rest_position.x, rest_position.y, rest_position.z, 0.0]))

	var mesh_arrays := []
	mesh_arrays.resize(Mesh.ARRAY_MAX)
	mesh_arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh_arrays[Mesh.ARRAY_NORMAL] = vertex_normals
	mesh_arrays[Mesh.ARRAY_TEX_UV2] = palette_coordinates
	mesh_arrays[Mesh.ARRAY_TEX_UV] = texture_uvs
	mesh_arrays[Mesh.ARRAY_CUSTOM0] = source_normals
	mesh_arrays[Mesh.ARRAY_CUSTOM1] = texture_regions
	mesh_arrays[Mesh.ARRAY_CUSTOM2] = rest_positions
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays, [], {}, (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT))
	return mesh


static func _make_palette_texture(bytes: PackedByteArray, eight_bit: bool = false) -> ImageTexture:
	var image := Image.create_empty(256, 1, false, Image.FORMAT_RGBA8)
	for index in range(256):
		var start := index * 3
		var divisor := 255.0 if eight_bit else 63.0
		image.set_pixel(index, 0, Color(
			float(bytes[start] if eight_bit else bytes[start] >> 2) / divisor,
			float(bytes[start + 1] if eight_bit else bytes[start + 1] >> 2) / divisor,
			float(bytes[start + 2] if eight_bit else bytes[start + 2] >> 2) / divisor
		))
	return ImageTexture.create_from_image(image)


static func _make_material(palette: Texture2D, override_index: int, is_lba2: bool, atlas: Texture2D = null, shade_table: Texture2D = null, normal_level: int = 12) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = LBA2_CHARACTER_SHADER if is_lba2 else CHARACTER_SHADER
	material.set_shader_parameter("palette_texture", palette)
	material.set_shader_parameter("palette_index_override", override_index)
	if not is_lba2:
		# LBA1 and the 1996 demo both shade inside 16-colour palette ramps.
		# Soft blending across a ramp edge produces high-contrast speckles.
		material.set_shader_parameter("palette_ramp_size", 16.0)
	if is_lba2:
		material.set_shader_parameter("has_texture_atlas", atlas != null)
		if atlas != null:
			material.set_shader_parameter("texture_atlas", atlas)
		if shade_table != null:
			material.set_shader_parameter("shade_table", shade_table)
			material.set_shader_parameter("normal_light_level", float(normal_level))
	elif atlas != null:
		material.set_shader_parameter("has_texture_atlas", true)
		material.set_shader_parameter("texture_atlas", atlas)
		if shade_table != null:
			material.set_shader_parameter("has_shade_table", true)
			material.set_shader_parameter("shade_table", shade_table)
			material.set_shader_parameter("normal_light_level", float(normal_level))
	return material
