class_name LBAWorld3D
extends Node3D

const HQR := preload("res://scripts/import/hqr_reader.gd")
const BODY := preload("res://scripts/import/lba1_body_decoder.gd")
const MESH := preload("res://scripts/render/character_mesh_builder.gd")
const GRID_RENDERER := preload("res://scripts/render/lba_grid_renderer.gd")

@onready var _actors: Node3D = $Actors
@onready var _bricks: Node3D = $Bricks
@onready var _camera: Camera3D = $Camera

var _actor_visuals: Dictionary = {}
var _actor_bodies: Dictionary = {}
var _grid_visual: Node3D = null


func load_grid_scene(scene_index: int, data_dir: String) -> bool:
	var result: Dictionary = GRID_RENDERER.build_scene(data_dir, scene_index, _camera)
	if not result.get("ok", false):
		push_error("LBA grid scene %d: %s" % [scene_index, result.get("error", "unavailable")])
		return false
	clear_grid_scene()
	_grid_visual = result["node"]
	_bricks.add_child(_grid_visual)
	return true


func clear_grid_scene() -> void:
	if _grid_visual == null:
		return
	_bricks.remove_child(_grid_visual)
	_grid_visual.queue_free()
	_grid_visual = null


func set_actor_body(actor_id: int, body_index: int, data_dir: String) -> bool:
	var body_entry: Dictionary = HQR.read_entry(data_dir.path_join("body.hqr"), body_index)
	if not body_entry.get("ok", false):
		push_error("LBA actor %d: %s" % [actor_id, body_entry.get("error", "Body unavailable")])
		return false
	var palette_entry: Dictionary = HQR.read_entry(data_dir.path_join("ress.hqr"), 0)
	if not palette_entry.get("ok", false):
		push_error("LBA palette: %s" % palette_entry.get("error", "Palette unavailable"))
		return false
	var palette: PackedByteArray = palette_entry["data"]
	if palette.size() < 768:
		push_error("LBA palette is truncated")
		return false
	var body: Dictionary = BODY.decode(body_entry["data"])
	if not body.get("ok", false):
		push_error("LBA body %d: %s" % [body_index, body.get("error", "Invalid body")])
		return false

	var visual: Node3D = MESH.build_static_pose(body, palette)
	visual.name = "Actor_%d" % actor_id
	for mesh_node in visual.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh_node as MeshInstance3D).material_override as ShaderMaterial
		if material != null and material.shader != null and material.shader.resource_path == "res://shaders/lba_character.gdshader":
			material.set_shader_parameter("use_scene_lights", true)
	if _actor_visuals.has(actor_id):
		var previous: Node3D = _actor_visuals[actor_id]
		visual.transform = previous.transform
		_actors.remove_child(previous)
		previous.queue_free()
	_actors.add_child(visual)
	_actor_visuals[actor_id] = visual
	_actor_bodies[actor_id] = body
	return true


func set_actor_transform(actor_id: int, world_transform: Transform3D) -> void:
	if _actor_visuals.has(actor_id):
		(_actor_visuals[actor_id] as Node3D).transform = world_transform


func set_actor_native_state(actor_id: int, x: int, y: int, z: int, angle: int) -> void:
	if not _actor_visuals.has(actor_id):
		return
	var position := Vector3(
		float(x) / 512.0 * GRID_RENDERER.CELL_XZ,
		float(y) / 256.0 * GRID_RENDERER.CELL_Y,
		float(z) / 512.0 * GRID_RENDERER.CELL_XZ)
	# Native angles use 1024 units per turn and the same X/Z rotation sign as
	# Godot's positive Y-axis rotation. BODY meshes were built at 1/512 scale.
	var rotation := Basis(Vector3.UP, TAU * float(angle & 1023) / 1024.0)
	var body_scale := Vector3(GRID_RENDERER.CELL_XZ,
		2.0 * GRID_RENDERER.CELL_Y, GRID_RENDERER.CELL_XZ)
	(_actor_visuals[actor_id] as Node3D).transform = Transform3D(rotation.scaled(body_scale), position)


func set_actor_pose(actor_id: int, pose: Dictionary) -> void:
	if _actor_visuals.has(actor_id):
		MESH.update_pose(_actor_visuals[actor_id], _actor_bodies[actor_id], pose)


func remove_actor(actor_id: int) -> void:
	if not _actor_visuals.has(actor_id):
		return
	var visual: Node3D = _actor_visuals[actor_id]
	_actor_visuals.erase(actor_id)
	_actor_bodies.erase(actor_id)
	_actors.remove_child(visual)
	visual.queue_free()


func clear_actors() -> void:
	for actor_id in _actor_visuals.keys():
		remove_actor(actor_id)
