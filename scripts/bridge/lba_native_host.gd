class_name LBANativeHost
extends Node

signal frame_received(state: Dictionary)
signal dialogue_received(dialogue: Dictionary)
signal event_received(event: Dictionary)
signal startup_failed(message: String)
signal stopped(message: String)

const INPUT := preload("res://scripts/bridge/lba_gameplay_input.gd")

var dialogue_active := false
var paused := false
var block_turn_actions := false
var _active := false
var _simulation: Object
var _last_dialogue_id := -1
var _desired_wall_collision_damage: bool = false


func start_new_game(data_dir: String) -> bool:
	stop()
	if not FileAccess.file_exists(data_dir.path_join("scene.hqr")):
		startup_failed.emit("Original LBA1 data is unavailable. Check Settings.")
		return false
	if not ClassDB.can_instantiate(&"LBASimulation"):
		startup_failed.emit("The LBA1 GDExtension is missing. Build this project with CMake first.")
		return false
	_simulation = ClassDB.instantiate(&"LBASimulation")
	if _simulation == null or int(_simulation.abi_version()) != 1:
		startup_failed.emit("The LBA1 GDExtension ABI is incompatible.")
		stop()
		return false
	if int(_simulation.start(data_dir)) != 1:
		startup_failed.emit("The original LBA1 simulation could not start with this data folder.")
		stop()
		return false
	if not _simulation.has_method("collision_flat"):
		push_warning("LBA scene sprite ZV unavailable: rebuild native GDExtension for collision-shaped sprite proxies")
	_last_dialogue_id = -1
	dialogue_active = false
	paused = false
	block_turn_actions = false
	_active = true
	_apply_wall_collision_damage()
	set_physics_process(true)
	return true


# A native setting, not a Godot-only visual preference. Applied immediately
# when playing, and again after new-game/load initialization resets native flags.
func configure_wall_collision_damage(enabled: bool) -> void:
	_desired_wall_collision_damage = enabled
	if _active:
		_apply_wall_collision_damage()


func _apply_wall_collision_damage() -> void:
	if _simulation == null:
		return
	if not _simulation.has_method("set_wall_damage"):
		push_error("LBA native library is missing set_wall_damage; rebuild the GDExtension.")
		return
	var accepted: bool = int(_simulation.set_wall_damage(int(_desired_wall_collision_damage))) == 1
	var actual: int = -1
	if _simulation.has_method("get_wall_damage"):
		actual = int(_simulation.get_wall_damage())
	print("LBA native wall collision damage: requested=", _desired_wall_collision_damage,
		" accepted=", accepted, " actual=", actual)
	if not accepted or actual != int(_desired_wall_collision_damage):
		push_error("Native wall collision damage setting did not stick.")


func request_behavior(mode: int) -> void:
	if _active and mode >= 0 and mode <= 3:
		_simulation.set_behavior(mode)


func holomap_state() -> PackedInt32Array:
	if _active and _simulation != null and _simulation.has_method("holomap_flat"):
		return _simulation.holomap_flat()
	return PackedInt32Array()


func save_slot(slot: int) -> bool:
	return _active and int(_simulation.save_slot(slot)) == 1


func load_slot(slot: int) -> bool:
	if not _active or int(_simulation.load_slot(slot)) != 1:
		return false
	_last_dialogue_id = -1
	dialogue_active = false
	paused = false
	block_turn_actions = false
	_apply_wall_collision_damage()
	return true


func stop() -> void:
	_active = false
	paused = false
	block_turn_actions = false
	dialogue_active = false
	set_physics_process(false)
	if _simulation != null:
		_simulation.shutdown()
		_simulation.free()
		_simulation = null


func _exit_tree() -> void:
	stop()


func _physics_process(_delta: float) -> void:
	if not _active or paused:
		return
	var actions := 0 if dialogue_active else INPUT.sample_actions()
	if block_turn_actions:
		actions &= ~(INPUT.TURN_LEFT | INPUT.TURN_RIGHT)
	var result := int(_simulation.step(actions))
	frame_received.emit(get_snapshot())
	var events: PackedInt32Array = _simulation.events_flat()
	for i in range(0, events.size(), 14):
		event_received.emit({
			"type": events[i], "scene": events[i + 1],
			"previous_scene": events[i + 2], "island": events[i + 3],
			"actor_count": events[i + 4], "resource": events[i + 5],
			"x": events[i + 6], "y": events[i + 7], "z": events[i + 8],
			"left": events[i + 9], "right": events[i + 10],
			"pitch": events[i + 11], "repeat": events[i + 12],
			"flags": events[i + 13],
		})
	var dialogue: PackedInt32Array = _simulation.dialogue_fields()
	if dialogue.size() >= 6:
		var serial := int(dialogue[0])
		if serial >= 0 and serial != _last_dialogue_id:
			_last_dialogue_id = serial
			dialogue_active = true
			dialogue_received.emit({
				"id": serial, "text_id": dialogue[1], "bank": dialogue[2],
				"speaker": dialogue[3], "voice_index": dialogue[4],
				"large_window": dialogue[5],
				"color_ramp": dialogue[6] if dialogue.size() >= 7 else -1,
				"text": _simulation.dialogue_text(),
			})
	if result != -32768:
		stop()
		stopped.emit("The original LBA1 simulation ended (%d)." % result)


func acknowledge_dialogue() -> void:
	if not _active or not dialogue_active or _last_dialogue_id < 0:
		return
	if int(_simulation.acknowledge_dialogue(_last_dialogue_id)) == 1:
		dialogue_active = false


func get_snapshot() -> Dictionary:
	if _simulation == null:
		return {}
	var poses := {}
	var raw_poses: PackedInt32Array = _simulation.poses_flat()
	var pose_at := 0
	while pose_at + 2 <= raw_poses.size():
		var actor_id := raw_poses[pose_at]
		var group_count := raw_poses[pose_at + 1]
		pose_at += 2
		if group_count < 0 or pose_at + group_count * 4 > raw_poses.size():
			break
		poses[actor_id] = raw_poses.slice(pose_at, pose_at + group_count * 4)
		pose_at += group_count * 4
	# Collision zone (ZV) comes from original native simulation. This is used
	# only to shape projected visual proxies, never to change game collision.
	var collision_by_actor := {}
	if _simulation.has_method("collision_flat"):
		var raw_collision: PackedInt32Array = _simulation.collision_flat()
		for z in range(0, raw_collision.size() - 6, 7):
			collision_by_actor[raw_collision[z]] = {
				"xmin": raw_collision[z + 1], "xmax": raw_collision[z + 2],
				"ymin": raw_collision[z + 3], "ymax": raw_collision[z + 4],
				"zmin": raw_collision[z + 5], "zmax": raw_collision[z + 6],
			}
	var actors := []
	var raw_actors: PackedInt32Array = _simulation.actors_flat()
	for i in range(0, raw_actors.size(), 17):
		actors.append({
			"i": raw_actors[i], "x": raw_actors[i + 1],
			"y": raw_actors[i + 2], "z": raw_actors[i + 3],
			"angle": raw_actors[i + 4], "body": raw_actors[i + 5],
			"archive_body": raw_actors[i + 6], "flags": raw_actors[i + 7],
			"sprite": raw_actors[i + 8], "animation": raw_actors[i + 9],
			"frame": raw_actors[i + 10], "life": raw_actors[i + 11],
			"offset_x": raw_actors[i + 12], "offset_y": raw_actors[i + 13],
			"y_max": raw_actors[i + 14],
			"collision": collision_by_actor.get(raw_actors[i], {}),
			"generic_body": raw_actors[i + 15],
			"generic_animation": raw_actors[i + 16],
			"pose_groups": poses.get(raw_actors[i], PackedInt32Array()),
		})
	var extras := []
	var raw_extras: PackedInt32Array = _simulation.extras_flat()
	for i in range(0, raw_extras.size(), 10):
		extras.append({
			"i": raw_extras[i], "x": raw_extras[i + 1],
			"y": raw_extras[i + 2], "z": raw_extras[i + 3],
			"sprite": raw_extras[i + 4], "flags": raw_extras[i + 5],
			"age": raw_extras[i + 6], "quantity": raw_extras[i + 7],
			"offset_x": raw_extras[i + 8], "offset_y": raw_extras[i + 9],
		})
	var raw_status: PackedInt32Array = _simulation.status_flat()
	var status := {}
	if raw_status.size() == 8:
		status = {"behavior": raw_status[0], "health": raw_status[1],
			"magic_level": raw_status[2], "magic_energy": raw_status[3],
			"clovers": raw_status[4], "clover_boxes": raw_status[5],
			"keys": raw_status[6], "money": raw_status[7]}
	return {"scene": int(_simulation.scene_number()),
		"grid_overlay": int(_simulation.grid_overlay()),
		"grid_overlay_ceiling": int(_simulation.grid_overlay_ceiling()),
		"tick": int(_simulation.tick()), "actors": actors, "extras": extras,
		"status": status, "inventory": _simulation.inventory_flat(),
		"camera": _simulation.camera_flat()}
