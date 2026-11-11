extends RefCounted

# Debug-only export for the first (prison) LBA1 scene.
# Called after BRK cache loading by lba_grid_renderer.gd. It does not rebake,
# alter pixel data used by the game, or export bricks outside the loaded scene.
const BRICK_PREPROCESS := preload("res://scripts/render/lba_brick_preprocess.gd")


static func export_bricks(originals: Dictionary, processed: Dictionary,
		folder: String) -> void:
	var abs_folder: String = ProjectSettings.globalize_path(folder)
	var error: Error = DirAccess.make_dir_recursive_absolute(abs_folder)
	if error != OK:
		push_warning("Prison alpha debug: cannot create folder %s (%s)" % [abs_folder, error])
		return

	var ids: Array = originals.keys()
	ids.sort()
	var exported: int = 0
	var cache_misses: int = 0
	var lines: PackedStringArray = PackedStringArray([
		"LBA prison (scene index 0): projected brick alpha diagnostics",
		"These are distinct brick TYPES present in scene 0, not every placed instance.",
		"All images use the baked canvas size, with the source centred in its original position.",
		"source_alpha: original opacity (white=opaque; black=transparent)",
		"baked_alpha: processed opacity actually loaded for this scene",
		"alpha_difference: green=added alpha, red=lost alpha, grey=unchanged original",
		"face_ownership: red=top, green=+X, blue=+Z; mixtures=overlapping face claims",
		"Face-active flags below are EXACTLY what v45 uses to allow/block outer edges.",
		"A cache miss means the renderer got the unprocessed source instead.",
		"",
	])

	for raw_id in ids:
		var brick_id: int = int(raw_id)
		var original_record: Dictionary = originals[raw_id]
		var baked_record: Dictionary = processed.get(raw_id, original_record)
		var source: Image = original_record.get("image")
		var baked: Image = baked_record.get("image")
		if source == null or source.is_empty() or baked == null or baked.is_empty():
			lines.append("brick %05d: skipped (missing image)" % brick_id)
			continue
		var pad: int = BRICK_PREPROCESS.PAD
		var w: int = source.get_width() + 2 * pad
		var h: int = source.get_height() + 2 * pad
		var padded: bool = int(baked_record.get("projected_pad", 0)) == pad \
			and baked.get_width() == w and baked.get_height() == h
		var unpadded: bool = baked.get_width() == source.get_width() \
			and baked.get_height() == source.get_height()
		if not padded and not unpadded:
			lines.append("brick %05d: skipped (unexpected baked size %dx%d)" % [
				brick_id, baked.get_width(), baked.get_height()])
			continue

		# Read the same v45 temporary face-mask/classifier used by the bake.
		# Debug-only: does not modify the cached or rendered image.
		var source_width: int = source.get_width()
		var source_height: int = source.get_height()
		var source_rgba: PackedByteArray = source.get_data()
		var faces: Array = BRICK_PREPROCESS._projected_front_faces(original_record)
		var face_split: Dictionary = BRICK_PREPROCESS._split_face_alpha(
			source_rgba, source_width, source_height, faces,
			int(original_record.get("projected_face_mask", -1)))
		var active: PackedByteArray = face_split["active"]
		var face_masks: PackedByteArray = face_split["masks"]
		var face_ownership: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		face_ownership.fill(Color.BLACK)
		var face_claims := PackedInt32Array([0, 0, 0])
		for iy in range(source_height):
			for ix in range(source_width):
				var pixel_index: int = iy * source_width + ix
				var r: float = float(face_masks[pixel_index]) / 255.0
				var g: float = float(face_masks[source_width * source_height + pixel_index]) / 255.0
				var b: float = float(face_masks[2 * source_width * source_height + pixel_index]) / 255.0
				if r > 0.0:
					face_claims[0] += 1
				if g > 0.0:
					face_claims[1] += 1
				if b > 0.0:
					face_claims[2] += 1
				face_ownership.set_pixel(ix + pad, iy + pad, Color(r, g, b, 1.0))

		var source_mask: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		var baked_mask: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		var difference: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		source_mask.fill(Color.BLACK)
		baked_mask.fill(Color.BLACK)
		difference.fill(Color.BLACK)
		var added_count: int = 0
		var lost_count: int = 0

		for y in range(h):
			for x in range(w):
				var sx: int = x - pad
				var sy: int = y - pad
				var old_alpha: float = 0.0
				var new_alpha: float = 0.0
				if sx >= 0 and sy >= 0 and sx < source.get_width() and sy < source.get_height():
					old_alpha = source.get_pixel(sx, sy).a
				if padded:
					new_alpha = baked.get_pixel(x, y).a
				elif sx >= 0 and sy >= 0 and sx < baked.get_width() and sy < baked.get_height():
					new_alpha = baked.get_pixel(sx, sy).a
				source_mask.set_pixel(x, y, Color(old_alpha, old_alpha, old_alpha, 1.0))
				baked_mask.set_pixel(x, y, Color(new_alpha, new_alpha, new_alpha, 1.0))
				if new_alpha > old_alpha + 0.001:
					added_count += 1
					difference.set_pixel(x, y, Color(0.0, new_alpha, 0.0, 1.0))
				elif old_alpha > new_alpha + 0.001:
					lost_count += 1
					difference.set_pixel(x, y, Color(old_alpha - new_alpha, 0.0, 0.0, 1.0))
				elif old_alpha > 0.0:
					difference.set_pixel(x, y, Color(0.28, 0.28, 0.28, 1.0))

		var base: String = folder.path_join("brick_%05d" % brick_id)
		var save_a: Error = source_mask.save_png(base + "_source_alpha.png")
		var save_b: Error = baked_mask.save_png(base + "_baked_alpha.png")
		var save_d: Error = difference.save_png(base + "_alpha_difference.png")
		var save_f: Error = face_ownership.save_png(base + "_face_ownership.png")
		if save_a != OK or save_b != OK or save_d != OK or save_f != OK:
			push_warning("Prison alpha debug: PNG save failed for brick %d" % brick_id)
			lines.append("brick %05d: PNG save failure" % brick_id)
			continue
		exported += 1
		if not padded:
			cache_misses += 1
		var permitted_edges := PackedStringArray()
		for fi in range(3):
			var edges := PackedStringArray()
			if active[fi] != 0:
				for edge in range(4):
					if BRICK_PREPROCESS._is_exterior_edge(fi, edge, active):
						edges.append(str(edge))
			permitted_edges.append(",".join(edges) if active[fi] != 0 else "inactive")
		lines.append(("brick %05d: %s; added=%d; lost=%d; faces=[%d,%d,%d]; "
			+ "face claims=[%d,%d,%d]; exposed edges=[%s|%s|%s]") % [
			brick_id, "cache OK" if padded else "CACHE MISS / original used",
			added_count, lost_count, active[0], active[1], active[2],
			face_claims[0], face_claims[1], face_claims[2],
			permitted_edges[0], permitted_edges[1], permitted_edges[2]])

	lines.append("")
	lines.append("Exported %d brick types, %d cache misses" % [exported, cache_misses])
	var manifest: FileAccess = FileAccess.open(folder.path_join("README.txt"), FileAccess.WRITE)
	if manifest != null:
		manifest.store_string("\n".join(lines) + "\n")
		manifest.close()
	print("Prison brick alpha diagnostics: %d types, %d cache misses, folder: %s" % [
		exported, cache_misses, abs_folder])
