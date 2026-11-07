extends SceneTree

const CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const BUILDER := preload("res://scripts/render/character_mesh_builder.gd")
const POSE := preload("res://scripts/animation/lba1_pose.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		push_error("LBA_TEST_DATA_PATH is required")
		quit(1)
		return
	var body: Dictionary = CACHE.get_resource(data_dir, "body", 1)
	var animation: Dictionary = CACHE.get_resource(data_dir, "animation", 0)
	var palette: Dictionary = CACHE.get_resource(data_dir, "palette", 0)
	if not body.get("ok", false) or not animation.get("ok", false) or not palette.get("ok", false):
		push_error("Twinsen BODY, animation or palette unavailable")
		quit(1)
		return
	var shared := {}
	var one: Node3D = BUILDER.build_static_pose(body, palette["data"], null, true, shared)
	var two: Node3D = BUILDER.build_static_pose(body, palette["data"], null, true, shared)
	root.add_child(one)
	root.add_child(two)
	var mesh: Mesh = (one.get_node("Polygons") as MeshInstance3D).mesh
	if mesh != (two.get_node("Polygons") as MeshInstance3D).mesh:
		_fail(one, two, "BODY instances do not share their mesh")
		return
	var frame := mini(1, int(animation["frame_count"]) - 1)
	var pose: Dictionary = POSE.sample(body, animation, frame, frame, 0.0)
	BUILDER.update_pose(one, body, pose)
	if mesh != (one.get_node("Polygons") as MeshInstance3D).mesh:
		_fail(one, two, "Animation rebuilt the BODY mesh")
		return
	var skeleton := one.get_node("Skeleton") as Skeleton3D
	var rest_points: PackedVector3Array = body["pose_points"]
	var posed_points: PackedVector3Array = pose["points"]
	var point_groups: PackedInt32Array = body["point_groups"]
	for i in range(rest_points.size()):
		var group := point_groups[i]
		var from: Vector3 = rest_points[i] * BUILDER.UNIT_SCALE
		var expected: Vector3 = posed_points[i] * BUILDER.UNIT_SCALE
		var bind: Transform3D = (one.get_node("Polygons") as MeshInstance3D).skin.get_bind_pose(group)
		var actual: Vector3 = skeleton.get_bone_global_pose(group) * (bind * from)
		if actual.distance_to(expected) > 0.001:
			print("group=", group, " rest=", from, " expected=", expected, " actual=", actual,
				" bind=", bind, " bone=", skeleton.get_bone_global_pose(group),
				" raw=", body["points"][i], " pivot=", body["groups"][group]["pivot"])
			_fail(one, two, "Skinning differs from original hierarchy at point %d" % i)
			return
	print("LBA skinning: shared BODY mesh and %d animated points verified" % rest_points.size())
	one.free()
	two.free()
	quit()


func _fail(one: Node3D, two: Node3D, message: String) -> void:
	push_error(message)
	one.free()
	two.free()
	quit(1)
