extends SceneTree

const PREP := preload("res://scripts/render/lba_brick_preprocess.gd")
const GRID_RENDERER := preload("res://scripts/render/lba_grid_renderer.gd")

func _initialize() -> void:
	var image := Image.create(48, 38, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(10, 26):
		for x in range(10, 38):
			image.set_pixel(x, y, Color(0.5, 0.3, 0.2, 1.0))
	# Explicit transparent hole inside the painted portion.
	image.set_pixel(24, 18, Color(0, 0, 0, 0))
	var brick := {"ok": true, "image": image, "width": 48, "height": 38,
		"hot_x": 0, "hot_y": 0}
	var job := {"source": brick, "pixels": image.get_data(),
		"faces": PREP._projected_front_faces(brick)}
	var prep := PREP.new()
	prep._jobs = [job]
	prep._results.resize(1)
	prep._process_job(0)
	var pixels: PackedByteArray = prep._results[0]
	var new_image := Image.create_from_data(48 + PREP.PAD * 2, 38 + PREP.PAD * 2,
		false, Image.FORMAT_RGBA8, pixels)
	for y in range(38):
		for x in range(48):
			if new_image.get_pixel(x + PREP.PAD, y + PREP.PAD) != image.get_pixel(x, y):
				push_error("Original RGBA changed at %d,%d" % [x, y])
				quit(1)
	var padded := brick.duplicate()
	padded["projected_pad"] = PREP.PAD
	var original_mesh := GRID_RENDERER.projected_brick_mesh(brick)
	var new_mesh := GRID_RENDERER.projected_brick_mesh(padded)
	var old_uvs: PackedVector2Array = original_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var new_uvs: PackedVector2Array = new_mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	for i in range(old_uvs.size()):
		var expected := Vector2((old_uvs[i].x * 48.0 + PREP.PAD) / (48.0 + 2 * PREP.PAD),
			(old_uvs[i].y * 38.0 + PREP.PAD) / (38.0 + 2 * PREP.PAD))
		if not new_uvs[i].is_equal_approx(expected):
			push_error("UV shift incorrect at vertex %d" % i)
			quit(1)
	print("PASS: original alpha and colors preserved, UVs match padded image")
	quit(0)
