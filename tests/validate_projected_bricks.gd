extends SceneTree

const RENDERER := preload("res://scripts/render/lba_grid_renderer.gd")
const COORD := preload("res://scripts/render/lba_coordinates.gd")

func _initialize() -> void:
	var brick := {"width": 48, "height": 40, "hot_x": 0, "hot_y": 0}
	var mesh: ArrayMesh = RENDERER.projected_brick_mesh(brick)
	assert(mesh.get_surface_count() == 1)
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert(vertices.size() == 24)
	assert(uvs.size() == 24)
	assert(normals.size() == 24)
	assert(indices.size() == 36)
	for i in range(vertices.size()):
		var uv := RENDERER.projected_uv(vertices[i], 0, 0, 48, 40)
		assert(uv.distance_to(uvs[i]) < 0.00001)
	for i in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[i]]
		var b: Vector3 = vertices[indices[i + 1]]
		var c: Vector3 = vertices[indices[i + 2]]
		assert((b - a).cross(c - a).dot(normals[indices[i]]) > 0.0)
	var top_uv := RENDERER.projected_uv(Vector3(0, COORD.CELL_Y, 0), 0, 0, 48, 40)
	assert(top_uv.y < RENDERER.projected_uv(Vector3.ZERO, 0, 0, 48, 40).y)
	print("PASS: brick geometry, face winding and original-camera UV mapping")
	quit()
