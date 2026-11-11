extends SceneTree

# Run once from the repository with Godot 4.8:
# godot --headless --path . --script res://scripts/editor/generate_lba_scene_placeholders.gd -- --data /absolute/path/to/staged/data
# Existing .tscn files are NEVER overwritten. --refresh-preview replaces only PreviewCollisionGrid.
const GRID := preload("res://scripts/import/lba1_grid_decoder.gd")
const HQR := preload("res://scripts/import/hqr_reader.gd")
const COORD := preload("res://scripts/render/lba_coordinates.gd")
const SHAPES := preload("res://scripts/render/lba1_brick_shapes.gd")
const PREVIEW_SCRIPT := preload("res://scripts/editor/lba_collision_preview.gd")
const SUN_SCENE := preload("res://scenes/lighting/LBA_Sun.tscn")
const OUTPUT := "res://scenes/lba_locations"
const SCENE_COUNT := 120 # Original grid slots 0..119; higher GRI entries are overlay GRMs.

func _initialize() -> void:
	call_deferred("_generate")

func _generate() -> void:
	var args := OS.get_cmdline_user_args()
	var data_dir := ProjectSettings.globalize_path("user://lba1-native/data")
	var refresh := false
	for i in range(args.size()):
		if args[i] == "--data" and i + 1 < args.size():
			data_dir = args[i + 1]
		if args[i] == "--refresh-preview":
			refresh = true
	if not FileAccess.file_exists(data_dir.path_join("lba_gri.hqr")):
		push_error("No staged lba_gri.hqr at %s; pass --data /absolute/path/to/data" % data_dir)
		quit(1)
		return
	var gri := FileAccess.get_file_as_bytes(data_dir.path_join("lba_gri.hqr"))
	var bll := FileAccess.get_file_as_bytes(data_dir.path_join("lba_bll.hqr"))
	if gri.is_empty() or bll.is_empty():
		push_error("Missing or empty GRI/BLL archive in %s" % data_dir)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var saved := 0
	var skipped := 0
	var failed := 0
	for index in range(SCENE_COUNT):
		var path := "%s/Scene_%03d.tscn" % [OUTPUT, index]
		if FileAccess.file_exists(path) and not refresh:
			skipped += 1
			continue
		var raw_grid := HQR.read_entry_bytes(gri, index)
		var raw_blocks := HQR.read_entry_bytes(bll, index)
		if not raw_grid.get("ok", false) or not raw_blocks.get("ok", false):
			# Some original grid slots intentionally contain no usable layout.
			if not FileAccess.file_exists(path):
				print("Skipping empty scene slot %d" % index)
				skipped += 1
			continue
		var decoded: Dictionary = GRID.decode(raw_grid["data"], raw_blocks["data"]) if raw_grid.get("ok", false) and raw_blocks.get("ok", false) else {}
		if not decoded.get("ok", false):
			push_warning("Skipping scene %d: %s" % [index, decoded.get("error", "data missing")])
			failed += 1
			continue
		var root: Node3D
		if FileAccess.file_exists(path):
			root = (load(path) as PackedScene).instantiate() as Node3D
			var existing := root.get_node_or_null("PreviewCollisionGrid")
			if existing != null:
				root.remove_child(existing)
				existing.free()
		else:
			root = Node3D.new()
			root.name = "Scene_%03d" % index
			root.set_meta("lba_scene_index", index)
			var lighting := Node3D.new()
			lighting.name = "Lighting"
			root.add_child(lighting)
			lighting.owner = root
			var sun := SUN_SCENE.instantiate() as DirectionalLight3D
			sun.name = "Sun"
			lighting.add_child(sun)
			sun.owner = root
			var replacements := Node3D.new()
			replacements.name = "ReplacementAssets"
			root.add_child(replacements)
			replacements.owner = root
			var markers := Node3D.new()
			markers.name = "Markers"
			root.add_child(markers)
			markers.owner = root
		var preview := _build_preview(decoded)
		root.add_child(preview)
		preview.owner = root
		for child in preview.get_children():
			child.owner = root
		# Avoid baking the original grid as collision physics; this is editor visualization only.
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, path)
		root.free()
		if err != OK:
			failed += 1
			push_error("Could not save %s: %s" % [path, error_string(err)])
		else:
			saved += 1
			print("Saved %s (%d occupied cells)" % [path, decoded["occupied_count"]])
	print("LBA scene placeholders: saved=%d skipped=%d failed=%d" % [saved, skipped, failed])
	quit(1 if failed > 0 else 0)

func _build_preview(decoded: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "PreviewCollisionGrid"
	root.set_script(PREVIEW_SCRIPT)
	root.set_meta("preview_only", true)
	var shapes: PackedByteArray = decoded["shape_ids"]
	var cells: PackedInt32Array = decoded["cells"]
	var by_shape: Dictionary = {}
	for i in range(cells.size()):
		if (cells[i] & 0xff) == 0:
			continue
		var s := int(shapes[i])
		# Collision shapes 0 and 14+ are not standard solid/ramp cells.
		if s < 1 or s > 13:
			continue
		if not by_shape.has(s):
			by_shape[s] = []
		(by_shape[s] as Array).append(i)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.75, 0.85, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for shape in by_shape:
		var cell_indices: Array = by_shape[shape]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _make_shape_mesh(int(shape))
		mm.instance_count = cell_indices.size()
		for j in range(cell_indices.size()):
			var index: int = cell_indices[j]
			var z: int = int(index / (GRID.WIDTH * GRID.HEIGHT))
			var x: int = int(index / GRID.HEIGHT) % GRID.WIDTH
			var y: int = index % GRID.HEIGHT
			mm.set_instance_transform(j, Transform3D(Basis.IDENTITY, COORD.grid_cell(x, y, z)))
		var node := MultiMeshInstance3D.new()
		node.name = "CollisionShape_%02d" % int(shape)
		node.multimesh = mm
		# Godot does not persist the edited MultiMesh instance buffer in .tscn.
		# Save compact original cell indices and reconstruct in the editor instead.
		node.set_meta("lba_cell_indices", PackedInt32Array(cell_indices))
		node.material_override = material
		root.add_child(node)
	return root

func _make_shape_mesh(shape: int) -> ArrayMesh:
	var w: float = COORD.CELL_XZ
	var h: float = COORD.CELL_Y
	var base := [Vector3(0,0,0), Vector3(w,0,0), Vector3(w,0,w), Vector3(0,0,w)]
	var top: Array[Vector3] = []
	for i in range(4):
		top.append(base[i] + Vector3.UP * h * SHAPES.height_fraction(shape, (1.0 if i == 1 or i == 2 else 0.0), (1.0 if i >= 2 else 0.0)))
	var vertices := PackedVector3Array()
	if shape in [6, 7, 10, 11]:
		_add_triangle(vertices, top[0], top[1], top[2])
		_add_triangle(vertices, top[0], top[2], top[3])
	elif shape in [8, 9, 12, 13]:
		_add_triangle(vertices, top[0], top[1], top[3])
		_add_triangle(vertices, top[1], top[2], top[3])
	else:
		_add_triangle(vertices, top[0], top[1], top[2])
		_add_triangle(vertices, top[0], top[2], top[3])
	for i in range(4):
		var j := (i + 1) % 4
		_add_triangle(vertices, base[i], base[j], top[j])
		_add_triangle(vertices, base[i], top[j], top[i])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _add_triangle(vertices: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
