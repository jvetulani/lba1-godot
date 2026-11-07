extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var skeleton := Skeleton3D.new()
	root.add_child(skeleton)
	skeleton.add_bone("root")
	skeleton.add_bone("child")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)))
	print("rest=", skeleton.get_bone_global_rest(1), " pose=", skeleton.get_bone_global_pose(1))
	skeleton.set_bone_pose_position(1, Vector3(0, 2, 0))
	print("after=", skeleton.get_bone_global_pose(1))
	skeleton.free()
	quit()
