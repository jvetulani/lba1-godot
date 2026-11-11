class_name LBA1FaceModes
extends RefCounted

# In LBA1's FillVertic dispatch, 5 replaces the destination palette ramp and
# 6 writes every other pixel. LBA2 uses different render-type meanings.
static func is_transparent(body: Dictionary, polygon: Dictionary) -> bool:
	return body.get("game", "LBA1") == "LBA1" and int(polygon["render_type"]) in [5, 6]


static func has_transparent_faces(body: Dictionary) -> bool:
	if body.get("game", "LBA1") != "LBA1":
		return false
	for polygon in body["polygons"]:
		if int(polygon["render_type"]) in [5, 6]:
			return true
	return false


# LBA1 special polygon mode 5 overlays the destination palette ramp. It is
# used for the vehicle/body mesh ground-shadow artwork, unlike mode 6's
# transparent stipple. Keep these geometries independently controllable.
# Some LBA1 models use a low, flat stippled polygon (type 6) for a
# ground overlay. Do not discard other type-6 polygons such as glass.
# Compare polygons in the model's authored pose space, before world transforms.
static func is_ground_shadow_face(body: Dictionary, polygon: Dictionary) -> bool:
	if body.get("game", "") != "LBA1" or int(polygon.get("render_type", -1)) != 6:
		return false
	var points: PackedVector3Array = body.get("pose_points", PackedVector3Array())
	var indices: PackedInt32Array = polygon.get("points", PackedInt32Array())
	if indices.size() < 3 or points.is_empty():
		return false
	var model_low: float = INF
	var model_high: float = -INF
	var x_min: float = INF
	var x_max: float = -INF
	var z_min: float = INF
	var z_max: float = -INF
	for v in points:
		model_low = minf(model_low, v.y)
		model_high = maxf(model_high, v.y)
		x_min = minf(x_min, v.x)
		x_max = maxf(x_max, v.x)
		z_min = minf(z_min, v.z)
		z_max = maxf(z_max, v.z)
	var y_low: float = INF
	var y_high: float = -INF
	var p_x_low: float = INF
	var p_x_high: float = -INF
	var p_z_low: float = INF
	var p_z_high: float = -INF
	for index in indices:
		if index < 0 or index >= points.size():
			return false
		var v: Vector3 = points[index]
		y_low = minf(y_low, v.y)
		y_high = maxf(y_high, v.y)
		p_x_low = minf(p_x_low, v.x)
		p_x_high = maxf(p_x_high, v.x)
		p_z_low = minf(p_z_low, v.z)
		p_z_high = maxf(p_z_high, v.z)
	# A flat horizontal sheet near the model's lowest authored Y.
	if y_high - y_low > 32.0 or y_low > model_low + 48.0:
		return false
	# Reject narrow rods and tiny checkerboard facets.
	var sheet_extent: float = maxf(p_x_high - p_x_low, p_z_high - p_z_low)
	var model_extent: float = maxf(x_max - x_min, z_max - z_min)
	return sheet_extent >= maxf(64.0, model_extent * 0.32)


static func has_legacy_shadow_faces(body: Dictionary) -> bool:
	if body.get("game", "LBA1") != "LBA1":
		return false
	for polygon in body["polygons"]:
		if int(polygon["render_type"]) == 5 or is_ground_shadow_face(body, polygon):
			return true
	return false


static func has_stipple_faces(body: Dictionary) -> bool:
	if body.get("game", "LBA1") != "LBA1":
		return false
	for polygon in body["polygons"]:
		if int(polygon["render_type"]) == 6 and not is_ground_shadow_face(body, polygon):
			return true
	return false
