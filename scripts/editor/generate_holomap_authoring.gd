extends SceneTree

# One-time editor authoring import. Never overwrites the scene unless --force is passed.
const HQR = preload("res://scripts/import/hqr_reader.gd")
const BODY = preload("res://scripts/import/lba1_body_decoder.gd")
const MESH = preload("res://scripts/render/character_mesh_builder.gd")
const OUT_SCENE := "res://scenes/holomap_authoring/TwinsunAuthoring.tscn"
const OUT_TEXTURE := "res://scenes/holomap_authoring/twinsun_editor_preview.png"
const R := 3.0
const ROWS := 16
const COLS := 32

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var forced := "--force" in args
	if FileAccess.file_exists(OUT_SCENE) and not forced:
		print("Holomap scene already exists; preserving edits: ", OUT_SCENE)
		quit(0)
		return
	var archive := _find_archive(args)
	if archive.is_empty():
		push_error("Cannot find RESS.HQR; pass --data=/absolute/path/to/staged/data")
		quit(1)
		return
	var palette := HQR.read_entry(archive, 5)
	var elevation := HQR.read_entry(archive, 6)
	var surface := HQR.read_entry(archive, 7)
	var locations := HQR.read_entry(archive, 8)
	if not (palette.get("ok", false) and elevation.get("ok", false) and surface.get("ok", false) and locations.get("ok", false)):
		push_error("RESS.HQR is missing required Holomap entries 5, 6, 7 or 8")
		quit(1)
		return
	var colors: PackedByteArray = palette["data"]
	var pixels: PackedByteArray = surface["data"]
	var heights: PackedByteArray = elevation["data"]
	var positions: PackedByteArray = locations["data"]
	if colors.size() < 768 or pixels.size() < 65536 or heights.size() < 544 or positions.size() < 1200:
		push_error("Holomap data is truncated")
		quit(1)
		return
	var root_directory := ProjectSettings.globalize_path("res://scenes/holomap_authoring")
	DirAccess.make_dir_recursive_absolute(root_directory)
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var k := int(pixels[y * 256 + x]) * 3
			image.set_pixel(x, y, Color8(colors[k], colors[k + 1], colors[k + 2]))
	var err := image.save_png(ProjectSettings.globalize_path(OUT_TEXTURE))
	if err != OK:
		push_error("Failed to write Holomap editor texture")
		quit(1)
		return
	var root := Node3D.new()
	root.name = "TwinsunAuthoring"
	root.set_meta("purpose", "EDITOR-ONLY location positioning; runtime loads original RESS.HQR")
	var globe_alignment := Node3D.new()
	globe_alignment.name = "GlobeAlignment"
	root.add_child(globe_alignment)
	var sphere := MeshInstance3D.new()
	sphere.name = "Twinsun"
	globe_alignment.add_child(sphere)
	sphere.mesh = _mesh(heights, ImageTexture.create_from_image(image))
	var locations_alignment := Node3D.new()
	locations_alignment.name = "LocationsAlignment"
	root.add_child(locations_alignment)
	var marker_parent := Node3D.new()
	marker_parent.name = "Locations"
	locations_alignment.add_child(marker_parent)
	var shared_sphere := SphereMesh.new()
	shared_sphere.radius = 0.055
	shared_sphere.height = 0.11
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.3, 0.15)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shared_sphere.material = material
	for i in range(150):
		var offset := i * 8
		var alpha := int(positions.decode_s16(offset))
		var beta := int(positions.decode_s16(offset + 2))
		var size := int(positions.decode_s16(offset + 4))
		var message := int(positions.decode_s16(offset + 6))
		var point := Node3D.new()
		point.name = "Location_%03d" % i
		point.position = _holomap_marker_position(float(alpha), float(beta), float(size))
		point.set_meta("lba_alpha", alpha)
		point.set_meta("original_angle_mapping", "LBA1 SetAngleCamera(alpha,beta,0) + WorldRotatePoint(0,0,1000+Size)")
		point.set_meta("lba_beta", beta)
		point.set_meta("lba_message_id", message)
		marker_parent.add_child(point)
		var visual := MeshInstance3D.new()
		visual.name = "MarkerPreview"
		visual.mesh = shared_sphere
		point.add_child(visual)
		var name_label := Label3D.new()
		name_label.name = "LocationLabel"
		name_label.text = "%03d" % i
		name_label.font_size = 36
		name_label.pixel_size = 0.003
		name_label.position = Vector3(0.0, 0.13, 0.0)
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = false
		name_label.visible = false  # Keep 150 labels searchable, but do not obscure the globe
		point.add_child(name_label)
		var model_alignment := Node3D.new()
		model_alignment.name = "CharacterAlignment"
		point.add_child(model_alignment)
	# Editable original Holomap Twinsen, separate from location marker points.
	# This is editor-only art; runtime still loads original marker resources.
	var mini_entry: Dictionary = HQR.read_entry(archive, 9)
	if not mini_entry.get("ok", false):
		push_error("RESS.HQR entry 9 (Holomap Twinsen) missing; cannot author model alignment")
		quit(1)
		return
	var decoded: Dictionary = BODY.decode(mini_entry["data"])
	if not decoded.get("ok", false):
		push_error("Unable to decode original miniature Twinsen: " + str(decoded.get("error", "unknown")))
		quit(1)
		return
	var character_placement := Node3D.new()
	character_placement.name = "TwinsenPlacement"
	# Initial position follows location 004, but is freely editable afterward.
	character_placement.position = marker_parent.get_node("Location_004").position
	character_placement.set_meta("starting_location", 4)
	locations_alignment.add_child(character_placement)
	var local_alignment := Node3D.new()
	local_alignment.name = "ModelAlignment"
	character_placement.add_child(local_alignment)
	# Orient the character anchor so its positive local Y axis points out from
	# the planet. Edit ModelAlignment to correct the BODY's local axis/heading.
	local_alignment.quaternion = Quaternion(Vector3.UP, character_placement.position.normalized())
	var miniature: Node3D = MESH.build_static_pose(decoded, colors)
	miniature.name = "TwinsenOriginalModel"
	local_alignment.add_child(miniature)
	var points: PackedVector3Array = decoded["pose_points"]
	if points.is_empty():
		push_error("Original miniature Twinsen has no pose points")
		quit(1)
		return
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for vertex in points:
		var vertex_position: Vector3 = vertex / 512.0
		low = low.min(vertex_position)
		high = high.max(vertex_position)
	var character_height := 0.48
	var miniature_scale := character_height / maxf(0.01, high.y - low.y)
	miniature.scale = Vector3.ONE * miniature_scale
	# Expose the raw model orientation rather than burying a correction here.
	# Initially align its lowest Y with the editable character anchor.
	miniature.position = Vector3(-(low.x + high.x) * miniature_scale * 0.5,
		-low.y * miniature_scale, -(low.z + high.z) * miniature_scale * 0.5)
	var lighting := DirectionalLight3D.new()
	lighting.name = "PreviewSun"
	lighting.rotation_degrees = Vector3(-35, 40, 0)
	lighting.light_energy = 1.25
	root.add_child(lighting)
	var camera := Camera3D.new()
	camera.name = "EditorCamera"
	camera.position = Vector3(0, 2, 11)
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0, 2, 11), Vector3.ZERO)
	camera.current = true
	_set_owner_recursive(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK or ResourceSaver.save(packed, OUT_SCENE) != OK:
		push_error("Unable to save Holomap authoring scene")
		quit(1)
		return
	print("Created: ", OUT_SCENE, " with 150 LBA1-matrix location transforms and original Twinsen model")
	print("GlobeAlignment and LocationsAlignment can be adjusted independently.")
	# Release the scene tree and its mesh/texture resources before the headless process exits.
	root.free()
	packed = null
	quit.call_deferred(0)

func _set_owner_recursive(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_owner_recursive(child, scene_root)

func _find_archive(args: PackedStringArray) -> String:
	var candidates: Array[String] = []
	for arg in args:
		if arg.begins_with("--data="):
			candidates.append(arg.trim_prefix("--data="))
	candidates.append(ProjectSettings.globalize_path("user://lba1-native/data"))
	for base in candidates:
		for filename in ["RESS.HQR", "ress.hqr"]:
			var path := base.path_join(filename)
			if FileAccess.file_exists(path):
				return path
	return ""

# LBA1 HOLOMAP.C ComputeCoorGlobe():
#   Rotate(1000 + height * 2, 0, alpha) -> (r*cos(a), -r*sin(a))
#   Rotate(x, 0, beta) -> (x*cos(b), -x*sin(b))
#   WorldRotatePoint() with zero camera angles leaves this vector unchanged.
# The old scene used +Y and +Z, mirroring the original terrain geometry.
func _surface(alpha: float, beta: float, altitude: float = 0.0) -> Vector3:
	var a := alpha * TAU / 1024.0
	var b := beta * TAU / 1024.0
	var radius := R * (1000.0 + altitude * 2.0) / 1000.0
	return Vector3(cos(a) * cos(b), -sin(a), -cos(a) * sin(b)) * radius

# LBA1 HOLOMAP.C DrawListPos(): SetAngleCamera(alpha,beta,0) followed
# by WorldRotatePoint(0,0,1000+Size). This is NOT the same transform as
# ComputeCoorGlobe(), and treating the two as equal moved locations to
# different hemispheres (particularly Clear Water Lake).
# Derived from the original 3x3 matrix, gamma=0; see renderer.cpp.
func _holomap_marker_position(alpha: float, beta: float, size: float) -> Vector3:
	var a := alpha * TAU / 1024.0
	var b := beta * TAU / 1024.0
	var radius := R * (1000.0 + size) / 1000.0
	return Vector3(sin(b), -sin(a) * cos(b), cos(a) * cos(b)) * radius

func _mesh(heights: PackedByteArray, tex: Texture2D) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(ROWS + 1):
		for col in range(COLS + 1):
			var alpha := -256.0 + 512.0 * row / ROWS
			var beta := 1024.0 * col / COLS
			var altitude := int(heights[row * COLS + (col % COLS)])
			vertices.append(_surface(alpha, beta, altitude))
			uvs.append(Vector2(float(col) / COLS, float(row) / ROWS))
	for row in range(ROWS):
		for col in range(COLS):
			var a := row * (COLS + 1) + col
			var b := a + COLS + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh
