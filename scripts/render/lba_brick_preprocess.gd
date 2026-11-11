class_name LBABrickPreprocess
extends RefCounted

# V47: Split original BRK alpha into three TEMPORARY projected-face masks.
# Decide face presence with an exact pixel scan, not sparse alpha probes.
# Pad only truly exposed edges in each face's local UV coordinates.
# Recombine the results as ONE BRK image; original UVs are unchanged.
# RGB is filled separately but cannot create visible alpha coverage.
const COORD := preload("res://scripts/render/lba_coordinates.gd")
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")

const VERSION := 16
const PAD := 8
const DEFAULT_OUTER_ALPHA_PIXELS := 2.0
# Number of local face-space pixels that an occupied texel must be away
# from geometric face edges to prove that a face is genuinely populated.
# This prevents a neighbour's shared-edge texel from activating an empty face.
const FACE_INTERIOR_PROOF_PIXELS := 0.75

# Optional per-brick overrides: a source dictionary may supply:
#   alpha_outer_pixels: float (0..8)
#   projected_face_mask: integer (bit 0=top, bit 1=+X, bit 2=+Z)
# No BRK has to use these; useful for slopes and unusual sprite-like objects.
var _jobs: Array = []
var _results: Array = []


static func outer_alpha_pixels() -> float:
	return clampf(float(ProjectSettings.get_setting(
		"lba/tiles/alpha_outer_pixels", DEFAULT_OUTER_ALPHA_PIXELS)), 0.0, float(PAD))


static func cache_relative_dir() -> String:
	# A setting change must invalidate the import-complete marker AND PNG cache.
	return "brick-projected/v%d/outer-%d" % [VERSION, roundi(outer_alpha_pixels() * 100.0)]


static func _extent_for_source(source: Dictionary) -> float:
	return clampf(float(source.get("alpha_outer_pixels", outer_alpha_pixels())), 0.0, float(PAD))


# This is called at import time by LBABrickImportWarmup. Existing BRK scene
# meshes/UVs remain unchanged: output adds PAD texels around the same image.
static func prepare_bricks(bricks: Dictionary, allow_generate: bool = true) -> Dictionary:
	var output := {}
	var processor := LBABrickPreprocess.new()
	var ids := bricks.keys()
	var directory := VISUAL_CACHE.cache_path.path_join(cache_relative_dir())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var cache_hits := 0
	for brick_id in ids:
		var source: Dictionary = bricks[brick_id]
		var image: Image = source["image"]
		if image == null or image.is_empty() or image.get_format() != Image.FORMAT_RGBA8:
			output[brick_id] = source
			continue
		var width: int = image.get_width()
		var height: int = image.get_height()
		var rgba: PackedByteArray = image.get_data()
		var hash_context := HashingContext.new()
		hash_context.start(HashingContext.HASH_MD5)
		hash_context.update(rgba)
		var signature: String = hash_context.finish().hex_encode() + "_%d_%d_%d_%d" % [
			width, height, int(source["hot_x"]), int(source["hot_y"])]
		var extent: float = _extent_for_source(source)
		var face_override: int = int(source.get("projected_face_mask", -1))
		var key := "%05d_%s_e%d_f%d.png" % [int(brick_id), signature,
			roundi(extent * 100.0), face_override]
		var file_path := directory.path_join(key)
		if FileAccess.file_exists(file_path):
			var saved := Image.new()
			if saved.load(file_path) == OK and saved.get_width() == width + PAD * 2 \
					and saved.get_height() == height + PAD * 2:
				var cached := source.duplicate()
				cached["image"] = saved
				cached["projected_pad"] = PAD
				output[brick_id] = cached
				cache_hits += 1
				continue
		if not allow_generate:
			output[brick_id] = source
			push_warning("Projected BRK cache miss: %s (re-import tiles)." % key)
			continue
		processor._jobs.append({
			"id": brick_id, "source": source, "pixels": rgba,
			"faces": _projected_front_faces(source),
			"extent": extent, "face_override": face_override,
			"path": file_path,
		})
	processor._results.resize(processor._jobs.size())
	if not processor._jobs.is_empty():
		if processor._jobs.size() >= 8:
			var group_id := WorkerThreadPool.add_group_task(processor._process_job,
				processor._jobs.size(), -1, false,
				"LBA BRK exterior edge UV-space alpha / separate RGB padding")
			WorkerThreadPool.wait_for_group_task_completion(group_id)
		else:
			for index in range(processor._jobs.size()):
				processor._process_job(index)
		for index in range(processor._jobs.size()):
			var job: Dictionary = processor._jobs[index]
			var source: Dictionary = job["source"]
			var pixels: PackedByteArray = processor._results[index]
			var width: int = int(source["width"]) + PAD * 2
			var height: int = int(source["height"]) + PAD * 2
			var processed := Image.create_from_data(width, height, false,
				Image.FORMAT_RGBA8, pixels)
			var adapted := source.duplicate()
			adapted["image"] = processed
			adapted["projected_pad"] = PAD
			output[job["id"]] = adapted
			processed.save_png(job["path"])
	print("LBA brick preprocess v%d: " % VERSION, cache_hits,
		" cached; ", processor._jobs.size(), " prepared")
	return output


static func _projected_front_faces(brick: Dictionary) -> Array:
	var r := COORD.CELL_XZ * 0.5
	var y := COORD.CELL_Y
	# Top, +X side, +Z side: SAME order as old preprocessor.
	var faces := [
		[Vector3(-r,y,-r), Vector3(r,y,-r), Vector3(r,y,r), Vector3(-r,y,r)],
		[Vector3(r,0,-r), Vector3(r,0,r), Vector3(r,y,r), Vector3(r,y,-r)],
		[Vector3(-r,0,r), Vector3(r,0,r), Vector3(r,y,r), Vector3(-r,y,r)]
	]
	var basis := COORD.camera_facing_basis()
	var left := COORD.GRID_GRAPH_ORIGIN_PIXELS.x + float(brick["hot_x"])
	var top := COORD.GRID_GRAPH_ORIGIN_PIXELS.y + float(brick["hot_y"])
	var projected := []
	for face in faces:
		var polygon := PackedVector2Array()
		for vertex in face:
			polygon.append(Vector2(vertex.dot(basis.x) / COORD.PIXEL_SIZE - left,
				-vertex.dot(basis.y) / COORD.PIXEL_SIZE - top))
		projected.append(polygon)
	return projected


# TEMPORARY per-face alpha extraction. The original sprite is never split
# on disk: these masks exist only while baking one BRK.
#
# Examine every original non-transparent pixel, not a sparse grid. Sample
# within that pixel footprint so diagonal face boundaries don't drop thin
# pixel art; shared-border texels may appear in both temporary masks.
# A face is considered populated ONLY if a pixel lies in its interior,
# rather than only on a shared boundary with another face.
static func _split_face_alpha(pixels: PackedByteArray, width: int,
		height: int, faces: Array, face_override: int) -> Dictionary:
	# One buffer with 3 contiguous face planes, avoiding PackedByteArray
	# copy-on-write when writing into a nested Array element.
	var face_alpha := PackedByteArray()
	face_alpha.resize(width * height * 3)
	var interiors := PackedInt32Array([0, 0, 0])
	var possible := PackedInt32Array([0, 0, 0])
	var descriptors: Array = []
	for face_index in range(3):
		var corners: PackedVector2Array = faces[face_index]
		var axis_u: Vector2 = corners[1] - corners[0]
		var axis_v: Vector2 = corners[3] - corners[0]
		var determinant: float = axis_u.cross(axis_v)
		descriptors.append({
			"origin": corners[0], "u": axis_u, "v": axis_v,
			"det": determinant, "fw": axis_u.length(),
			"fh": axis_v.length(),
		})
	var subsamples: Array[Vector2] = [
		Vector2.ZERO, Vector2(-0.35, -0.35), Vector2(0.35, -0.35),
		Vector2(-0.35, 0.35), Vector2(0.35, 0.35),
	]
	for py in range(height):
		for px in range(width):
			var pixel_index: int = py * width + px
			var alpha: int = int(pixels[pixel_index * 4 + 3])
			if alpha == 0:
				continue
			var center := Vector2(float(px) + 0.5, float(py) + 0.5)
			for face_index in range(3):
				var face: Dictionary = descriptors[face_index]
				var det: float = float(face["det"])
				if absf(det) < 0.00001:
					continue
				var origin: Vector2 = face["origin"]
				var axis_u: Vector2 = face["u"]
				var axis_v: Vector2 = face["v"]
				var fw: float = float(face["fw"])
				var fh: float = float(face["fh"])
				var center_rel: Vector2 = center - origin
				var cu: float = center_rel.cross(axis_v) / det
				var cv: float = axis_u.cross(center_rel) / det
				var belongs := false
				for offset: Vector2 in subsamples:
					var rel: Vector2 = center_rel + offset
					var u: float = rel.cross(axis_v) / det
					var v: float = axis_u.cross(rel) / det
					if u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0:
						belongs = true
						break
				if not belongs:
					continue
				face_alpha[face_index * width * height + pixel_index] = alpha
				possible[face_index] += 1
				# Count only actual interior texels. A single row touching a
				# common seam is insufficient to mark an empty face occupied.
				var interior_distance := minf(
					minf(cu * fw, (1.0 - cu) * fw),
					minf(cv * fh, (1.0 - cv) * fh))
				if interior_distance >= FACE_INTERIOR_PROOF_PIXELS:
					interiors[face_index] += 1
	var active := PackedByteArray([0, 0, 0])
	if face_override >= 0:
		for i in range(3):
			active[i] = 1 if (face_override & (1 << i)) != 0 else 0
	else:
		for i in range(3):
			active[i] = 1 if interiors[i] > 0 else 0
		# Extremely thin/special sprites may occupy only shared seam texels.
		# Choose a single face, rather than let a seam activate several.
		if active[0] == 0 and active[1] == 0 and active[2] == 0:
			var strongest := -1
			for i in range(3):
				if strongest < 0 or possible[i] > possible[strongest]:
					strongest = i
			if strongest >= 0 and possible[strongest] > 0:
				active[strongest] = 1
	return {"masks": face_alpha, "active": active}


# When another face is truly populated, don't deposit padding inside its
# projected footprint. An EMPTY face offers no such obstruction.
static func _inside_other_populated_face(point: Vector2, faces: Array,
		skip_index: int, active: PackedByteArray) -> bool:
	for other_index in range(3):
		if other_index == skip_index or active[other_index] == 0:
			continue
		var corners: PackedVector2Array = faces[other_index]
		var origin: Vector2 = corners[0]
		var axis_u: Vector2 = corners[1] - origin
		var axis_v: Vector2 = corners[3] - origin
		var det: float = axis_u.cross(axis_v)
		if absf(det) < 0.00001:
			continue
		var rel: Vector2 = point - origin
		var u: float = rel.cross(axis_v) / det
		var v: float = axis_u.cross(rel) / det
		if u > 0.0001 and u < 0.9999 and v > 0.0001 and v < 0.9999:
			return true
	return false


# Each pair here is one of the three TRUE shared cube edges:
# top edge 1 <-> +X edge 2; top edge 2 <-> +Z edge 2;
# +X edge 1 <-> +Z edge 1. Any other edge is exposed.
# Edge numbers: 0=v0, 1=u1, 2=v1, 3=u0.
static func _is_exterior_edge(face_index: int, edge: int,
		active: PackedByteArray) -> bool:
	if face_index == 0 and edge == 1:
		return active[1] == 0
	if face_index == 1 and edge == 2:
		return active[0] == 0
	if face_index == 0 and edge == 2:
		return active[2] == 0
	if face_index == 2 and edge == 2:
		return active[0] == 0
	if face_index == 1 and edge == 1:
		return active[2] == 0
	if face_index == 2 and edge == 1:
		return active[1] == 0
	return true


# Full colour flood based ONLY on the original alpha. All transparent texels
# get nearby RGB, even inside a brick, but the alpha is NOT altered here.
# Four-neighbour propagation is intentional: no RGB blending of palette art.
static func _fill_rgb_under_transparency(pixels: PackedByteArray, width: int,
		height: int, dw: int, dh: int) -> PackedByteArray:
	var total: int = dw * dh
	var output := PackedByteArray()
	output.resize(total * 4)
	var owners := PackedInt32Array()
	owners.resize(total)
	owners.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(total)
	var tail := 0
	for y in range(height):
		for x in range(width):
			var si: int = (y * width + x) * 4
			var di: int = ((y + PAD) * dw + x + PAD) * 4
			for c in range(4):
				output[di + c] = pixels[si + c]
			if pixels[si + 3] > 0:
				var target: int = di / 4
				owners[target] = target
				queue[tail] = target
				tail += 1
	var head := 0
	while head < tail:
		var p: int = queue[head]
		head += 1
		var x: int = p % dw
		var y: int = p / dw
		var source_offset: int = owners[p] * 4
		# Explicit neighbours avoid creating an Array in the flood inner loop.
		for direction in range(4):
			var q: int = p
			match direction:
				0:
					if x == 0:
						continue
					q = p - 1
				1:
					if x == dw - 1:
						continue
					q = p + 1
				2:
					if y == 0:
						continue
					q = p - dw
				3:
					if y == dh - 1:
						continue
					q = p + dw
			if owners[q] >= 0:
				continue
			owners[q] = owners[p]
			var dst_offset: int = q * 4
			for c in range(3):
				output[dst_offset + c] = output[source_offset + c]
			queue[tail] = q
			tail += 1
	return output


# V47: Each exposed edge gets a scanline of the OUTERMOST ORIGINAL opaque
# texels in its face's unskewed coordinates. Unlike v45, seeds do NOT have to
# touch the theoretical cube edge: an inset silhouette still extends outward.
#
# Coordinates: s/t are U/V in face-local *pixel* units, not BRK image X/Y.
#   edge 0: outward = decreasing t; edge 1: increasing s
#   edge 2: increasing t; edge 3: decreasing s
# The first opaque texel from the selected side is the source for that ray.
# Only that silhouette is extended; inner holes and shared cube edges aren't
# treated as independent alpha-dilation boundaries.
static func _edge_coordinates(edge: int, s: float, t: float,
		fw: float, fh: float) -> Vector2:
	match edge:
		0:
			return Vector2(s, t)
		1:
			return Vector2(t, fw - s)
		2:
			return Vector2(s, fh - t)
		3:
			return Vector2(t, s)
	return Vector2(-100000.0, 100000.0)


# Half-pixel scanlines prevent holes at diagonal projected edges. A source
# pixel belongs to nearby scanlines to account for the original pixel grid's
# imperfect alignment with the projected face coordinates.
static func _make_edge_rays(face_alpha: PackedByteArray, face_offset: int,
		width: int, height: int,
		origin: Vector2, axis_u: Vector2, axis_v: Vector2,
		determinant: float, fw: float, fh: float, edge: int) -> Dictionary:
	var tangent_span: float = fw if edge == 0 or edge == 2 else fh
	var ray_count: int = ceili(tangent_span * 2.0) + 3
	var distances := PackedFloat32Array()
	distances.resize(ray_count)
	distances.fill(100000.0)
	var sources := PackedInt32Array()
	sources.resize(ray_count)
	sources.fill(-1)
	var alphas := PackedInt32Array()
	alphas.resize(ray_count)
	alphas.fill(0)

	for sy in range(height):
		for sx in range(width):
			var pixel: int = sy * width + sx
			var alpha: int = int(face_alpha[face_offset + pixel])
			if alpha == 0:
				continue
			var rel := Vector2(float(sx) + 0.5, float(sy) + 0.5) - origin
			var s: float = rel.cross(axis_v) / determinant * fw
			var t: float = axis_u.cross(rel) / determinant * fh
			var coords: Vector2 = _edge_coordinates(edge, s, t, fw, fh)
			var tangent: float = coords.x
			var normal: float = coords.y
			if tangent < -0.75 or tangent > tangent_span + 0.75:
				continue
			# Pixel centres can lie just outside the quad when their footprints
			# overlap its rasterised edge. Preserve those original edge texels.
			var center_bin: int = roundi(tangent * 2.0) + 1
			for bin_index in range(maxi(0, center_bin - 2),
					mini(ray_count - 1, center_bin + 2) + 1):
				var bin_tangent: float = float(bin_index - 1) * 0.5
				if absf(tangent - bin_tangent) > 0.76:
					continue
				var previous: float = distances[bin_index]
				if normal < previous - 0.001 or (
						absf(normal - previous) <= 0.001 and alpha > alphas[bin_index]):
					distances[bin_index] = normal
					sources[bin_index] = pixel * 4
					alphas[bin_index] = alpha
	return {"distances": distances, "sources": sources, "alphas": alphas,
		"tangent_span": tangent_span, "count": ray_count}


# Return the nearest silhouette texel along the chosen outward direction.
# A ray's seed is the *first opaque texel* in that direction, not a pixel
# required to lie in the first strip of the mathematically projected quad.
static func _edge_candidate(tangent: float, normal: float, extent: float,
		rays: Dictionary) -> Vector3:
	var span: float = float(rays["tangent_span"])
	if tangent < -0.75 or tangent > span + 0.75:
		return Vector3(-1.0, 0.0, 100000.0)
	var count: int = int(rays["count"])
	var distances: PackedFloat32Array = rays["distances"]
	var sources: PackedInt32Array = rays["sources"]
	var alphas: PackedInt32Array = rays["alphas"]
	var center_bin: int = roundi(tangent * 2.0) + 1
	var best_distance: float = 100000.0
	var best_source: int = -1
	var best_alpha: int = 0
	for bin_index in range(maxi(0, center_bin - 2),
			mini(count - 1, center_bin + 2) + 1):
		var source: int = sources[bin_index]
		if source < 0:
			continue
		var bin_tangent: float = float(bin_index - 1) * 0.5
		if absf(tangent - bin_tangent) > 0.76:
			continue
		var outward: float = distances[bin_index] - normal
		if outward <= 0.001 or outward > extent + 0.35:
			continue
		if outward < best_distance:
			best_distance = outward
			best_source = source
			best_alpha = alphas[bin_index]
	return Vector3(float(best_source), float(best_alpha), best_distance)


func _process_job(index: int) -> void:
	var job: Dictionary = _jobs[index]
	var src: Dictionary = job["source"]
	var width: int = int(src["width"])
	var height: int = int(src["height"])
	var dw: int = width + PAD * 2
	var dh: int = height + PAD * 2
	var pixels: PackedByteArray = job["pixels"]
	var faces: Array = job["faces"]
	var extent: float = float(job["extent"])

	# The whole-image colour flood is deliberately independent of alpha.
	# Visible new pixels are replaced with the RGB of THEIR OWN face's seed.
	var output: PackedByteArray = _fill_rgb_under_transparency(
		pixels, width, height, dw, dh)
	if extent <= 0.0:
		_results[index] = output
		return
	var split: Dictionary = _split_face_alpha(pixels, width, height,
		faces, int(job["face_override"]))
	var active: PackedByteArray = split["active"]
	var face_masks: PackedByteArray = split["masks"]
	var additions := PackedByteArray()
	additions.resize(dw * dh)
	var rgb_sources := PackedInt32Array()
	rgb_sources.resize(dw * dh)
	rgb_sources.fill(-1)
	var best_distances := PackedFloat32Array()
	best_distances.resize(dw * dh)
	best_distances.fill(100000.0)

	# Evaluate in the BRK's own pixel positions, but measure both the edge
	# direction and padding distance in the UNSKEWED coordinates of that face.
	var offsets: Array[Vector2] = [
		Vector2.ZERO, Vector2(-0.28, -0.28), Vector2(0.28, -0.28),
		Vector2(-0.28, 0.28), Vector2(0.28, 0.28),
	]
	for face_index in range(3):
		if active[face_index] == 0:
			continue
		var face: PackedVector2Array = faces[face_index]
		var face_offset: int = face_index * width * height
		var origin: Vector2 = face[0]
		var axis_u: Vector2 = face[1] - origin
		var axis_v: Vector2 = face[3] - origin
		var determinant: float = axis_u.cross(axis_v)
		if absf(determinant) < 0.0001:
			continue
		var fw: float = axis_u.length()
		var fh: float = axis_v.length()
		if fw < 1.0 or fh < 1.0:
			continue

		# The target may be up to 'extent' away from the ACTUAL silhouette,
		# including the portion that falls inside the theoretical cube edge.
		# Therefore search the complete projected face bbox + outward margin.
		var min_x: int = dw - 1
		var min_y: int = dh - 1
		var max_x: int = 0
		var max_y: int = 0
		for corner: Vector2 in face:
			min_x = mini(min_x, floori(corner.x) + PAD)
			min_y = mini(min_y, floori(corner.y) + PAD)
			max_x = maxi(max_x, ceili(corner.x) + PAD)
			max_y = maxi(max_y, ceili(corner.y) + PAD)
		var margin: int = ceili(extent) + 2
		min_x = maxi(0, min_x - margin)
		min_y = maxi(0, min_y - margin)
		max_x = mini(dw - 1, max_x + margin)
		max_y = mini(dh - 1, max_y + margin)

		for edge in range(4):
			if not _is_exterior_edge(face_index, edge, active):
				continue
			var rays: Dictionary = _make_edge_rays(face_masks, face_offset,
				width, height, origin, axis_u, axis_v,
				determinant, fw, fh, edge)
			for dy in range(min_y, max_y + 1):
				for dx in range(min_x, max_x + 1):
					var target: int = dy * dw + dx
					# Never replace the source image's alpha or palette colours.
					if output[target * 4 + 3] > 0:
						continue
					var pixel_center := Vector2(float(dx - PAD) + 0.5,
						float(dy - PAD) + 0.5)
					# The other populated face owns its entire projected island,
					# even when a few of its own pixels are transparent.
					if _inside_other_populated_face(pixel_center,
						faces, face_index, active):
						continue
					var candidate_alpha: int = 0
					var candidate_source: int = -1
					var candidate_distance: float = 100000.0
					for sample_offset: Vector2 in offsets:
						var point: Vector2 = pixel_center + sample_offset
						var rel: Vector2 = point - origin
						var s: float = rel.cross(axis_v) / determinant * fw
						var t: float = axis_u.cross(rel) / determinant * fh
						var coordinates: Vector2 = _edge_coordinates(
							edge, s, t, fw, fh)
						var found: Vector3 = _edge_candidate(coordinates.x,
							coordinates.y, extent, rays)
						if found.x < 0.0:
							continue
						if found.z < candidate_distance:
							candidate_distance = found.z
							candidate_source = int(found.x)
							candidate_alpha = int(found.y)
						# Centre sample usually suffices; only check the four subpixel
						# fallbacks when rasterisation missed a diagonal edge.
						break
					if candidate_source >= 0 and (
						candidate_distance < best_distances[target] or
						(candidate_distance <= best_distances[target] + 0.001 and
						candidate_alpha > int(additions[target]))):
						best_distances[target] = candidate_distance
						additions[target] = candidate_alpha
						rgb_sources[target] = candidate_source

	# Final RGB/alpha composition: source opaque pixels are never touched;
	# ONLY exterior edge rays grant new alpha, and each visible new texel
	# takes its own face's RGB, never that of the independent RGB flood.
	for p in range(dw * dh):
		if output[p * 4 + 3] == 0 and additions[p] > 0:
			var seed_offset: int = rgb_sources[p]
			if seed_offset >= 0:
				for c in range(3):
					output[p * 4 + c] = pixels[seed_offset + c]
			output[p * 4 + 3] = additions[p]
	_results[index] = output
