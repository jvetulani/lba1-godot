class_name LBAGridRenderer
extends RefCounted

const GRID := preload("res://scripts/import/lba1_grid_decoder.gd")
const BRICK := preload("res://scripts/import/lba1_brick_decoder.gd")
const HQR := preload("res://scripts/import/hqr_reader.gd")
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const COORD := preload("res://scripts/render/lba_coordinates.gd")
const TILE_SHADER := preload("res://shaders/lba_tile_visual.tres")
const BRICK_PREPROCESS := preload("res://scripts/render/lba_brick_preprocess.gd")
const BRICK_SHAPES := preload("res://scripts/render/lba1_brick_shapes.gd")
# v59_authored_grid_shapes: BLL terrain geometry, collision unchanged.
# Set LBA_GRID_FORCE_CUBES=1 in the shell for before/after comparisons.
const FORCE_CUBES_ENV := "LBA_GRID_FORCE_CUBES"
const BRICK_ALPHA_DEBUG := preload("res://scripts/render/lba_brick_alpha_debug.gd")

# Original Map2Screen projects one X/Z cell to (24,12) pixels and one Y cell
# 15 pixels upward. A 30-degree isometric camera reproduces those spacings.
const PIXEL_SIZE := COORD.PIXEL_SIZE
const CELL_XZ := COORD.CELL_XZ
const CELL_Y := COORD.CELL_Y
# All game scenes use projected 3D bricks by default. Set the environment
# variable LBA_BRICK_BILLBOARDS=1 before starting Godot for A/B comparison.
const BILLBOARD_ENV := "LBA_BRICK_BILLBOARDS"
# Require visible image coverage, not merely valid mesh winding and UV values.
const MIN_PROJECTED_ALPHA_COVERAGE := 0.015
const COVERAGE_SAMPLES_PER_AXIS := 12

# Per-face projected UV contraction: 1.0 = original, 0.995 = 0.5% inset.
# Geometry/vertex positions and real 3D depth remain unchanged.
const LBA_FACE_UV_SCALE := 1.0
# Original projected BRK image only contains the three faces facing LBA's
# canonical isometric camera. The other three can accidentally sample opaque
# texels from neighbouring faces and cast phantom shadows.
const CANONICAL_EXTERIOR_FACES_ONLY: bool = true


static func build_scene(data_dir: String, scene_index: int, camera: Camera3D,
		overlay_index: int = -1, master_material: ShaderMaterial = null,
		force_cube_bricks: PackedInt32Array = PackedInt32Array(),
		allow_slope_bricks: PackedInt32Array = PackedInt32Array(),
		scene_brick_overrides: Dictionary = {},
		report_slope_candidates: bool = false) -> Dictionary:
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
	var shape_ids: PackedByteArray = scene.get("shape_ids", PackedByteArray())
	var slope_cells: int = 0
	var candidate_bricks: Dictionary = {}
	for index in range(brick_ids.size()):
		var brick_id: int = brick_ids[index]
		if brick_id < 0:
			continue
		var authored_shape: int = int(shape_ids[index]) if index < shape_ids.size() else 1
		var is_slope: bool = authored_shape >= 2 and authored_shape <= 13
		# Classification never changes native collision. Per-scene overrides
		# take priority over the BRK allowlist/denylist.
		var identity: String = "%d:%d" % [scene_index, brick_id]
		var cell_z: int = index / (GRID.WIDTH * GRID.HEIGHT)
		var cell_x: int = (index / GRID.HEIGHT) % GRID.WIDTH
		var cell_y: int = index % GRID.HEIGHT
		var cell_key: String = "%d:%d:%d:%d" % [scene_index, cell_x, cell_y, cell_z]
		if authored_shape >= 2 and authored_shape <= 13 and not candidate_bricks.has(brick_id):
			candidate_bricks[brick_id] = "%d:%d:%d" % [cell_x, cell_y, cell_z]
		if scene_brick_overrides.has(cell_key):
			is_slope = bool(scene_brick_overrides[cell_key]) and is_slope
		elif scene_brick_overrides.has(identity):
			is_slope = bool(scene_brick_overrides[identity]) and is_slope
		elif brick_id in force_cube_bricks:
			is_slope = false
		elif not allow_slope_bricks.is_empty() and not (brick_id in allow_slope_bricks):
			is_slope = false
		var shape_id: int = authored_shape if is_slope else 1
		var group_key := Vector2i(brick_id, shape_id)
		if not groups.has(group_key):
			groups[group_key] = []
		(groups[group_key] as Array).append(index)
		if shape_id >= 2 and shape_id <= 13:
			slope_cells += 1
	if report_slope_candidates:
		print("LBA slope candidate BRK IDs (id: first x:y:z) scene=", scene_index,
			" overrides are separate from native collision: ", candidate_bricks)

	var root := Node3D.new()
	root.name = "SceneGrid_%d_GRM_%d" % [scene_index, overlay_index]
	var billboard_mode := OS.get_environment(BILLBOARD_ENV) == "1"
	var facing := _camera_facing_basis()
	var fallback_count := 0
	var projected_count := 0
	# Load each unique original brick on the main thread. Process the decoded
	# images in parallel, never the thousands of individual cube instances.
	var brick_sources: Dictionary = {}
	for variant_key in groups:
		var key: Vector2i = variant_key
		var brick_id: int = key.x
		if brick_sources.has(brick_id):
			continue
		var resource: Dictionary = VISUAL_CACHE.get_resource(data_dir, "brick", brick_id)
		if not resource.get("ok", false):
			root.free()
			return {"ok": false, "error": resource.get("error", "Cannot decode BRK %d" % brick_id)}
		brick_sources[brick_id] = resource
	var processed_bricks: Dictionary = {} if billboard_mode else BRICK_PREPROCESS.prepare_bricks(brick_sources, false)
	# Preserve prison-only diagnostic alpha export; never trigger a new bake.
	if scene_index == 0 and overlay_index < 0 and not billboard_mode:
		var debug_folder: String = VISUAL_CACHE.cache_path.path_join(
			BRICK_PREPROCESS.cache_relative_dir()).path_join("debug/prison_scene_0")
		BRICK_ALPHA_DEBUG.export_bricks(brick_sources, processed_bricks, debug_folder)
	# Both slope and cube instances reuse GPU textures when using the same BRK.
	var texture_cache: Dictionary = {}
	for variant_key in groups:
		var key: Vector2i = variant_key
		var brick_id: int = key.x
		var shape_id: int = key.y
		var visual_shape_id: int = 1 if OS.get_environment(FORCE_CUBES_ENV) == "1" else shape_id
		var brick: Dictionary = brick_sources[brick_id]
		var material: ShaderMaterial
		if master_material != null and master_material.shader != null:
			material = master_material.duplicate(false) as ShaderMaterial
		else:
			material = ShaderMaterial.new()
			material.shader = TILE_SHADER
		var quad: Mesh
		var brick_billboard: bool = billboard_mode
		if not brick_billboard:
			var coverage: float = projected_alpha_coverage(brick, visual_shape_id)
			if coverage < MIN_PROJECTED_ALPHA_COVERAGE:
				brick_billboard = true
				fallback_count += 1
			else:
				projected_count += 1
		var render_image: Image = brick["image"]
		if brick_billboard:
			var legacy_quad := QuadMesh.new()
			legacy_quad.size = Vector2(brick["width"], brick["height"]) * PIXEL_SIZE
			quad = legacy_quad
		else:
			var processed: Dictionary = processed_bricks.get(brick_id, brick)
			render_image = processed["image"]
			quad = projected_brick_mesh(processed, visual_shape_id)
		var texture_key := Vector2i(brick_id, 1 if brick_billboard else 0)
		if not texture_cache.has(texture_key):
			texture_cache[texture_key] = ImageTexture.create_from_image(render_image)
		var gpu_texture: Texture2D = texture_cache[texture_key]
		material.set_shader_parameter("albedo_texture", gpu_texture)
		# Compatibility with existing master shaders: both are the same RGBA.
		material.set_shader_parameter("alpha_texture", gpu_texture)
		material.set_shader_parameter("use_billboard_depth", brick_billboard)
		var positions: Array = groups[key]
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = quad
		instances.instance_count = positions.size()
		var image_center: Vector3 = COORD.grid_graph_center(
			int(brick["hot_x"]), int(brick["hot_y"]),
			int(brick["width"]), int(brick["height"]))
		material.set_shader_parameter("graph_center_offset", image_center)
		for instance_index in range(positions.size()):
			var cell_index: int = int(positions[instance_index])
			var z: int = cell_index / (GRID.WIDTH * GRID.HEIGHT)
			var x: int = (cell_index / GRID.HEIGHT) % GRID.WIDTH
			var y: int = cell_index % GRID.HEIGHT
			var position: Vector3 = COORD.grid_cell(x, y, z)
			instances.set_instance_transform(instance_index,
				Transform3D(facing, position + image_center) if brick_billboard
				else Transform3D(Basis.IDENTITY, position))
		var node := MultiMeshInstance3D.new()
		node.name = "Brick_%d_Shape_%d" % [brick_id, shape_id]
		node.set_meta("lba_brick_id", brick_id)
		node.set_meta("lba_shape_id", shape_id)
		node.multimesh = instances
		node.material_override = material
		root.add_child(node)
	if slope_cells > 0:
		print("LBA authored grid ramps: ", slope_cells,
			" cells across ", groups.size(), " (BRK, shape) mesh variants")

	if not billboard_mode:
		print("LBA projected bricks: ", projected_count, " mesh types; ",
			fallback_count, " billboard fallback types (no projected opaque pixels)")
	if camera != null:
		configure_preview_camera(camera)
	return {
		"ok": true,
		"node": root,
		"visible_count": scene["visible_count"],
		"unique_bricks": brick_sources.size(),
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


# The original BRK file is a screen-space isometric projection, NOT a UV
# atlas. Recover its source pixel for each world-space vertex using the
# same fixed camera basis as the legacy billboard renderer. UVs therefore
# remain stable as actors move and as the gameplay camera pans.
static func projected_uv(local_position: Vector3, hot_x: int, hot_y: int,
		width: int, height: int) -> Vector2:
	var basis := COORD.camera_facing_basis()
	var screen_x := local_position.dot(basis.x) / PIXEL_SIZE
	var screen_y := -local_position.dot(basis.y) / PIXEL_SIZE
	var image_left := COORD.GRID_GRAPH_ORIGIN_PIXELS.x + float(hot_x)
	var image_top := COORD.GRID_GRAPH_ORIGIN_PIXELS.y + float(hot_y)
	return Vector2((screen_x - image_left) / float(width),
		(screen_y - image_top) / float(height))


# Each original GRI cell is a cubic X/Z footprint, one native grid level tall.
# Share one ArrayMesh for every instance of the same BRK artwork.
# Flat vertex normals are important: they provide physically meaningful
# baseline lighting even before a normal map has been authored.
static func projected_brick_mesh(brick: Dictionary, shape_id: int = 1) -> ArrayMesh:
	var faces: Array = BRICK_SHAPES.face_list(shape_id, CELL_XZ * 0.5, CELL_Y)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for face in faces:
		var corners: Array = face["v"]
		if corners.size() < 3:
			continue
		var target: Vector3 = face["n"]
		var edge_a: Vector3 = corners[1] - corners[0]
		var edge_b: Vector3 = corners[2] - corners[0]
		var raw_normal: Vector3 = edge_a.cross(edge_b)
		if raw_normal.length_squared() < 0.0000000001:
			continue
		var normal: Vector3 = raw_normal.normalized()
		if normal.dot(target) < 0.0:
			normal = -normal
		# The UVs use the original fixed isometric projection and BRK padding.
		# Rotating the actual view camera never changes texture coordinates.
		var face_uvs: Array[Vector2] = []
		for vertex in corners:
			var uv: Vector2 = projected_uv(vertex, int(brick["hot_x"]),
				int(brick["hot_y"]), int(brick["width"]), int(brick["height"]))
			var pad: int = int(brick.get("projected_pad", 0))
			if pad > 0:
				uv = Vector2((uv.x * float(brick["width"]) + float(pad)) /
					float(int(brick["width"]) + pad * 2),
					(uv.y * float(brick["height"]) + float(pad)) /
					float(int(brick["height"]) + pad * 2))
			face_uvs.append(uv)
		var uv_center := Vector2.ZERO
		for uv in face_uvs:
			uv_center += uv
		uv_center /= float(face_uvs.size())
		for i in range(face_uvs.size()):
			face_uvs[i] = uv_center + (face_uvs[i] - uv_center) * LBA_FACE_UV_SCALE
		# Derive tangents from physical surface edges and the source BRK UV.
		# This keeps optional tangent-space normal maps functional on slopes.
		var t1: Vector2 = face_uvs[1] - face_uvs[0]
		var t2: Vector2 = face_uvs[2] - face_uvs[0]
		var determinant: float = t1.x * t2.y - t1.y * t2.x
		var tangent: Vector3 = edge_a
		var bitangent: Vector3 = edge_b
		if absf(determinant) > 0.0000001:
			tangent = (edge_a * t2.y - edge_b * t1.y) / determinant
			bitangent = (edge_b * t1.x - edge_a * t2.x) / determinant
		tangent -= normal * tangent.dot(normal)
		if tangent.length_squared() < 0.0000000001:
			tangent = normal.cross(Vector3.RIGHT)
			if tangent.length_squared() < 0.0000000001:
				tangent = normal.cross(Vector3.FORWARD)
		tangent = tangent.normalized()
		var tangent_sign: float = 1.0 if normal.cross(tangent).dot(bitangent) >= 0.0 else -1.0
		var base: int = vertices.size()
		for i in range(corners.size()):
			vertices.append(corners[i])
			normals.append(normal)
			uvs.append(face_uvs[i])
			tangents.append_array(PackedFloat32Array([
				tangent.x, tangent.y, tangent.z, tangent_sign]))
		var face_positive: bool = raw_normal.dot(target) > 0.0
		for i in range(1, corners.size() - 1):
			if face_positive:
				indices.append_array(PackedInt32Array([base, base + i, base + i + 1]))
			else:
				indices.append_array(PackedInt32Array([base, base + i + 1, base + i]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Estimate whether the authored projected BRK actually paints the generated
# faces. If not, keep the old billboard fallback instead of dropping art.
static func projected_alpha_coverage(brick: Dictionary, shape_id: int = 1) -> float:
	var image: Image = brick.get("image")
	if image == null or image.is_empty():
		return 0.0
	var mesh: ArrayMesh = projected_brick_mesh(brick, shape_id)
	var arrays: Array = mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var hits: int = 0
	var total: int = 0
	for tri in range(indices.size() / 3):
		var uv0: Vector2 = uvs[indices[tri * 3]]
		var uv1: Vector2 = uvs[indices[tri * 3 + 1]]
		var uv2: Vector2 = uvs[indices[tri * 3 + 2]]
		for iy in range(COVERAGE_SAMPLES_PER_AXIS):
			for ix in range(COVERAGE_SAMPLES_PER_AXIS - iy):
				var u: float = (float(ix) + 0.33) / float(COVERAGE_SAMPLES_PER_AXIS)
				var v: float = (float(iy) + 0.33) / float(COVERAGE_SAMPLES_PER_AXIS)
				var uv: Vector2 = uv0 * (1.0 - u - v) + uv1 * u + uv2 * v
				total += 1
				if uv.x < 0.0 or uv.x >= 1.0 or uv.y < 0.0 or uv.y >= 1.0:
					continue
				var px: int = mini(int(floor(uv.x * image.get_width())), image.get_width() - 1)
				var py: int = mini(int(floor(uv.y * image.get_height())), image.get_height() - 1)
				if image.get_pixel(px, py).a >= 0.5:
					hits += 1
	return float(hits) / float(maxi(total, 1))
