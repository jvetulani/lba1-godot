class_name LBAWorld3D
extends Node3D

const HQR := preload("res://scripts/import/hqr_reader.gd")
const BODY := preload("res://scripts/import/lba1_body_decoder.gd")
const MESH := preload("res://scripts/render/character_mesh_builder.gd")

@onready var _actors: Node3D = $Actors

var _actor_visuals: Dictionary = {}
var _actor_bodies: Dictionary = {}


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
