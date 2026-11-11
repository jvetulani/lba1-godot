# Render-only reconstruction of the original LBA1 BLL collision shape byte.
# Matches ReajustPos() in native/lba1-native/engine/game/OBJECT.C.
# This does NOT change native gameplay collision or BRK artwork.
class_name LBA1BrickShapes
extends RefCounted


static func height_fraction(shape: int, x: float, z: float) -> float:
	# x,z are normalized coordinates within the cell (0..1).
	# 0 and 1 (and unused codes) keep their original solid-cube visuals.
	match shape:
		2: return x
		3: return z
		4: return 1.0 - z
		5: return 1.0 - x
		6: return maxf(x, z)
		7: return maxf(1.0 - x, 1.0 - z)
		8: return maxf(x, 1.0 - z)
		9: return maxf(1.0 - x, z)
		10: return minf(x, z)
		11: return minf(1.0 - x, 1.0 - z)
		12: return minf(x, 1.0 - z)
		13: return minf(1.0 - x, z)
		_: return 1.0


static func face_list(shape: int, half_extent: float, cell_height: float) -> Array:
	# World-space corners A, B, C, D correspond to (X,Z) = (0,0),
	# (1,0), (1,1), (0,1) in the LBA grid collision cell.
	var r: float = half_extent
	var xz: Array[Vector2] = [Vector2(-r, -r), Vector2(r, -r),
		Vector2(r, r), Vector2(-r, r)]
	var h: PackedFloat32Array = PackedFloat32Array()
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for i in range(4):
		var u: float = (xz[i].x + r) / (2.0 * r)
		var v: float = (xz[i].y + r) / (2.0 * r)
		var height: float = cell_height * height_fraction(shape, u, v)
		h.append(height)
		top.append(Vector3(xz[i].x, height, xz[i].y))
		bottom.append(Vector3(xz[i].x, 0.0, xz[i].y))
	var top_polygons: Array = [[0, 1, 2, 3]]
	# Complex ramps have a ridge/valley on one of the diagonals, rather
	# than a bilinear quad. Split exactly where native collision switches.
	if shape in [6, 7, 10, 11]:
		top_polygons = [[0, 1, 2], [0, 2, 3]]
	elif shape in [8, 9, 12, 13]:
		top_polygons = [[0, 1, 3], [1, 2, 3]]
	var faces: Array = []
	for polygon in top_polygons:
		var verts: Array[Vector3] = []
		for corner in polygon:
			verts.append(top[int(corner)])
		faces.append({"n": Vector3.UP, "v": verts})
	# The original BRK sprite owns only the three canonical visible faces:
	# top, +X and +Z. Drawing the opposite faces sampled unrelated texels.
	if h[1] > 0.000001 or h[2] > 0.000001:
		var right_side: Array[Vector3]
		if h[1] > 0.000001 and h[2] > 0.000001:
			right_side = [bottom[1], bottom[2], top[2], top[1]]
		elif h[1] > 0.000001:
			right_side = [bottom[1], bottom[2], top[1]]
		else:
			right_side = [bottom[1], bottom[2], top[2]]
		faces.append({"n": Vector3.RIGHT, "v": right_side})
	if h[2] > 0.000001 or h[3] > 0.000001:
		var back_side: Array[Vector3]
		if h[3] > 0.000001 and h[2] > 0.000001:
			back_side = [bottom[3], top[3], top[2], bottom[2]]
		elif h[3] > 0.000001:
			back_side = [bottom[3], top[3], bottom[2]]
		else:
			back_side = [bottom[3], top[2], bottom[2]]
		faces.append({"n": Vector3.BACK, "v": back_side})
	return faces
