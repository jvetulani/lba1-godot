class_name CharacterPose
extends RefCounted

# Both games rotate local group points around a parent pivot. They use
# different angle units; the caller supplies the game's full-turn value.


static func sample(body: Dictionary, animation: Dictionary, source_frame: int, target_frame: int, weight: float, angle_units: float) -> Dictionary:
	var source_transforms: Array = animation["frames"][source_frame]["transforms"]
	var target_transforms: Array = animation["frames"][target_frame]["transforms"]
	var groups: Array = body["groups"]
	var half_turn := angle_units * 0.5
	var raw_points: PackedVector3Array = body["points"]
	var points := raw_points.duplicate()
	var bases: Array[Basis] = []
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		var parent: int = group["parent"]
		var parent_basis := Basis.IDENTITY if parent < 0 else bases[parent]
		var pivot := Vector3.ZERO if parent < 0 else points[group["pivot"]]
		var from: Dictionary = source_transforms[group_index] if group_index < source_transforms.size() else {"type": 0, "values": Vector3i.ZERO}
		var to: Dictionary = target_transforms[group_index] if group_index < target_transforms.size() else {"type": 0, "values": Vector3i.ZERO}
		# Group 0 is the actor's master motion. Its type-1 values are
		# per-frame rotation steps, unlike type-1 child-group translations.
		var transform_type: int = 0 if group_index == 0 else to["type"]
		var values := Vector3.ZERO
		for axis in range(3):
			var start := float(from["values"][axis])
			var end := float(to["values"][axis])
			if transform_type == 0:
				var difference := fposmod(end - start + half_turn, angle_units) - half_turn
				values[axis] = start + difference * weight
			else:
				values[axis] = lerpf(start, end, weight)
		if transform_type == 1:
			values = limit_child_translation(body, group_index, values)
		var local_basis := Basis.IDENTITY
		if transform_type == 0 and group_index > 0:
			var angle_scale := TAU / angle_units
			local_basis = Basis(Vector3.RIGHT, values.x * angle_scale) * Basis(Vector3.BACK, values.z * angle_scale) * Basis(Vector3.UP, values.y * angle_scale)
		var world_basis := parent_basis * local_basis
		bases.append(world_basis)
		for point_index in range(group["first"], group["first"] + group["count"]):
			var local_point: Vector3 = raw_points[point_index]
			if transform_type == 1:
				local_point += values
			points[point_index] = pivot + world_basis * local_point
	return {"points": points, "bases": bases, "master_rotation": master_rotation_units(animation, source_frame, target_frame, weight) * (TAU / angle_units)}


static func from_native_groups(body: Dictionary, packed: PackedInt32Array, angle_units: float) -> Dictionary:
	var groups: Array = body["groups"]
	if packed.size() != groups.size() * 4:
		return {}
	var raw_points: PackedVector3Array = body["points"]
	var points := raw_points.duplicate()
	var bases: Array[Basis] = []
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		var parent: int = group["parent"]
		var parent_basis := Basis.IDENTITY if parent < 0 else bases[parent]
		var pivot := Vector3.ZERO if parent < 0 else points[group["pivot"]]
		var at := group_index * 4
		var transform_type := packed[at] & 1
		var values := Vector3(packed[at + 1], packed[at + 2], packed[at + 3])
		if transform_type == 1:
			values = limit_child_translation(body, group_index, values)
		var local_basis := Basis.IDENTITY
		if transform_type == 0 and group_index > 0:
			var scale := TAU / angle_units
			local_basis = Basis(Vector3.RIGHT, values.x * scale) * Basis(Vector3.BACK, values.z * scale) * Basis(Vector3.UP, values.y * scale)
		var world_basis := parent_basis * local_basis
		bases.append(world_basis)
		for point_index in range(group["first"], group["first"] + group["count"]):
			var local_point: Vector3 = raw_points[point_index]
			if transform_type == 1:
				local_point += values
			points[point_index] = pivot + world_basis * local_point
	return {"points": points, "bases": bases}


static func limit_child_translation(body: Dictionary, group_index: int, values: Vector3) -> Vector3:
	var limits: Dictionary = body.get("appearance", {}).get("group_translation_limits", {})
	if limits.has(str(group_index)):
		return values.limit_length(float(limits[str(group_index)]))
	return values


static func master_rotation_units(animation: Dictionary, source_frame: int, target_frame: int, weight: float) -> Vector3:
	var rotation := Vector3.ZERO
	for frame_index in range(1, source_frame + 1):
		var step: Dictionary = animation["frames"][frame_index]["transforms"][0]
		if step["type"] == 1:
			rotation += Vector3(step["values"])
	if target_frame != source_frame:
		var next_step: Dictionary = animation["frames"][target_frame]["transforms"][0]
		if next_step["type"] == 1:
			rotation += Vector3(next_step["values"]) * weight
	return rotation
