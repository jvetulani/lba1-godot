extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var data_dir := OS.get_environment("LBA_TEST_DATA_PATH")
	if data_dir.is_empty():
		push_error("Set LBA_TEST_DATA_PATH to the original game data directory")
		quit(1)
		return
	var world := (load("res://scenes/world/World3D.tscn") as PackedScene).instantiate()
	root.add_child(world)
	if not world.set_actor_body(0, 0, data_dir):
		_fail(world, "The original LBA1 body did not load")
		return
	var actor := world.get_node("Actors/Actor_0") as Node3D
	var polygons := actor.get_node("Polygons") as MeshInstance3D
	if polygons.mesh == null or polygons.mesh.get_surface_count() == 0:
		_fail(world, "The actor has no polygon mesh")
		return
	var material := polygons.material_override as ShaderMaterial
	if material == null or material.shader == null or material.shader.resource_path != "res://shaders/lba_character.gdshader":
		_fail(world, "The actor does not use the LBA1 character shader")
		return
	var transform := Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
	world.set_actor_transform(0, transform)
	if actor.transform != transform:
		_fail(world, "The renderer did not apply an actor transform")
		return
	world.remove_actor(0)
	if world.get_node("Actors").get_child_count() != 0:
		_fail(world, "The actor was not removed")
		return
	print("LBA actor: original BODY.HQR mesh, palette and shader verified")
	world.free()
	quit(0)


func _fail(world: Node, message: String) -> void:
	push_error(message)
	world.free()
	quit(1)
