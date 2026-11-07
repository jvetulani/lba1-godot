class_name LBAWorld3D
extends Node3D

const HQR := preload("res://scripts/import/hqr_reader.gd")
const BODY := preload("res://scripts/import/lba1_body_decoder.gd")
const MESH := preload("res://scripts/render/character_mesh_builder.gd")
const GRID_RENDERER := preload("res://scripts/render/lba_grid_renderer.gd")
const ANIMATION := preload("res://scripts/import/lba1_animation_decoder.gd")
const POSE := preload("res://scripts/animation/lba1_pose.gd")
const SPRITES := preload("res://scripts/render/lba_sprite_renderer.gd")
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const COORD := preload("res://scripts/render/lba_coordinates.gd")

@onready var _actors: Node3D = $Actors
@onready var _bricks: Node3D = $Bricks
@onready var _camera: Camera3D = $Camera

var _actor_visuals: Dictionary = {}
var _actor_bodies: Dictionary = {}
var _grid_visual: Node3D = null
var _grid_variants: Dictionary = {}
var _grid_scene := -1
var _grid_overlay := -2
var _grid_data_dir := ""
var _archive_bodies: Dictionary = {}
var _geometry_cache: Dictionary = {}
var _animations: Dictionary = {}
var _pose_keys: Dictionary = {}
var _sprite_actor_visuals: Dictionary = {}
var _extra_visuals: Dictionary = {}
var _sprite_renderer := SPRITES.new()
var _sprite_root: Node3D
var _extra_root: Node3D
var _speech_bubble: MeshInstance3D
var _speaker_id := -1
var _bubble_flip := false
var _last_actor_snapshots: Array = []
var _last_overlay_ceiling := 2147483647
var _sprite_data_dir := ""


func _ready() -> void:
	_sprite_root = Node3D.new()
	_sprite_root.name = "SceneSprites"
	add_child(_sprite_root)
	_extra_root = Node3D.new()
	_extra_root.name = "EngineExtras"
	add_child(_extra_root)


func _exit_tree() -> void:
	clear_grid_scene()



func load_grid_scene(scene_index: int, data_dir: String, overlay_index: int = -1) -> bool:
	if _grid_visual != null and _grid_scene == scene_index and _grid_overlay == overlay_index and _grid_data_dir == data_dir:
		return true
	if _grid_scene != scene_index or _grid_data_dir != data_dir:
		clear_grid_scene()
	var next: Node3D = _grid_variants.get(overlay_index)
	if next == null:
		var result: Dictionary = GRID_RENDERER.build_scene(data_dir, scene_index, null, overlay_index)
		if not result.get("ok", false):
			push_error("LBA grid scene %d: %s" % [scene_index, result.get("error", "unavailable")])
			return false
		next = result["node"]
		_grid_variants[overlay_index] = next
	if _grid_visual != null:
		_bricks.remove_child(_grid_visual)
	_grid_visual = next
	_bricks.add_child(_grid_visual)
	_grid_scene = scene_index
	_grid_overlay = overlay_index
	_grid_data_dir = data_dir
	return true


func toggle_grid_debug() -> void:
	_bricks.visible = not _bricks.visible


func are_bricks_visible() -> bool:
	return _bricks.visible


func clear_grid_scene() -> void:
	if _grid_visual != null:
		_bricks.remove_child(_grid_visual)
	for variant in _grid_variants.values():
		(variant as Node3D).free()
	_grid_variants.clear()
	_grid_visual = null
	_grid_scene = -1
	_grid_overlay = -2
	_grid_data_dir = ""


func set_actor_body(actor_id: int, body_index: int, data_dir: String) -> bool:
	var body: Dictionary = VISUAL_CACHE.get_resource(data_dir, "body", body_index)
	if not body.get("ok", false):
		push_error("LBA actor %d: %s" % [actor_id, body.get("error", "Body unavailable")])
		return false
	var palette_entry: Dictionary = VISUAL_CACHE.get_resource(data_dir, "palette", 0)
	if not palette_entry.get("ok", false):
		push_error("LBA palette: %s" % palette_entry.get("error", "Palette unavailable"))
		return false
	var palette: PackedByteArray = palette_entry["data"]
	if palette.size() < 768:
		push_error("LBA palette is truncated")
		return false
	var geometry_key := "%s:%d" % [data_dir, body_index]
	if not _geometry_cache.has(geometry_key):
		_geometry_cache[geometry_key] = {}
	var visual: Node3D = MESH.build_static_pose(body, palette, null, true,
		_geometry_cache[geometry_key])
	visual.name = "Actor_%d" % actor_id
	for mesh_node in visual.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh_node as MeshInstance3D).material_override as ShaderMaterial
		if material != null and material.shader != null and material.shader.resource_path == "res://shaders/lba_character.gdshader":
			material.set_shader_parameter("use_scene_lights", true)
			material.set_shader_parameter("use_actor_depth", true)
	if _actor_visuals.has(actor_id):
		var previous: Node3D = _actor_visuals[actor_id]
		visual.transform = previous.transform
		_actors.remove_child(previous)
		previous.queue_free()
	_actors.add_child(visual)
	_actor_visuals[actor_id] = visual
	_actor_bodies[actor_id] = body
	_archive_bodies[actor_id] = body_index
	_pose_keys.erase(actor_id)
	return true


func set_actor_transform(actor_id: int, world_transform: Transform3D) -> void:
	if _actor_visuals.has(actor_id):
		(_actor_visuals[actor_id] as Node3D).transform = world_transform


func set_actor_native_state(actor_id: int, x: int, y: int, z: int, angle: int) -> void:
	if not _actor_visuals.has(actor_id):
		return
	var position: Vector3 = COORD.native_position(x, y, z)
	# Native angles use 1024 units per turn and the same X/Z rotation sign as
	# Godot's positive Y-axis rotation. BODY meshes were built at 1/512 scale.
	(_actor_visuals[actor_id] as Node3D).transform = Transform3D(COORD.body_basis(angle), position)
	for mesh_node in (_actor_visuals[actor_id] as Node3D).find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		var material := mesh.material_override as ShaderMaterial
		if material != null and material.shader != null and material.shader.resource_path == "res://shaders/lba_character.gdshader":
			mesh.set_instance_shader_parameter("actor_sort_origin", position)


func set_actor_pose(actor_id: int, pose: Dictionary) -> void:
	if _actor_visuals.has(actor_id):
		MESH.update_pose(_actor_visuals[actor_id], _actor_bodies[actor_id], pose)


func remove_actor(actor_id: int) -> void:
	if not _actor_visuals.has(actor_id):
		return
	var visual: Node3D = _actor_visuals[actor_id]
	_actor_visuals.erase(actor_id)
	_actor_bodies.erase(actor_id)
	_archive_bodies.erase(actor_id)
	_pose_keys.erase(actor_id)
	_actors.remove_child(visual)
	visual.queue_free()


func clear_actors() -> void:
	for actor_id in _actor_visuals.keys():
		remove_actor(actor_id)
	for actor_id in _sprite_actor_visuals.keys():
		_remove_visual(_sprite_actor_visuals, actor_id)
	for extra_id in _extra_visuals.keys():
		_remove_visual(_extra_visuals, extra_id)
	set_speaking_actor(-1)


func sync_actor_snapshots(actors: Array, data_dir: String, overlay_ceiling: int = 2147483647) -> void:
	_last_actor_snapshots = actors
	_last_overlay_ceiling = overlay_ceiling
	_sprite_data_dir = data_dir
	var present := {}
	var sprite_present := {}
	for value in actors:
		if not value is Dictionary:
			continue
		var actor: Dictionary = value
		var actor_id := int(actor.get("i", -1))
		var archive_body := int(actor.get("archive_body", -1))
		var flags := int(actor.get("flags", 0))
		# OBJECT.C AffScene omits actors above an active GRM zone.
		if int(actor.get("y", 0)) > overlay_ceiling:
			continue
		# Preserve original engine visibility; sprite actors are still
		# simulated by native LBA1 but rendered using SPRITES.HQR instead.
		if actor_id < 0 or (flags & 512) != 0:
			continue
		if (flags & 1024) != 0:
			var sprite_id := int(actor.get("body", -1))
			if sprite_id >= 0:
				sprite_present[actor_id] = true
				_sync_sprite_visual(_sprite_actor_visuals, _sprite_root, actor_id,
					sprite_id, actor, data_dir)
			continue
		if int(actor.get("body", -1)) < 0:
			continue
		if archive_body < 0:
			continue
		present[actor_id] = true
		if _archive_bodies.get(actor_id, -1) != archive_body:
			if not set_actor_body(actor_id, archive_body, data_dir):
				_archive_bodies[actor_id] = archive_body
				continue
		set_actor_native_state(actor_id, int(actor.get("x", 0)), int(actor.get("y", 0)),
			int(actor.get("z", 0)), int(actor.get("angle", 0)))
		var native_groups: PackedInt32Array = actor.get("pose_groups", PackedInt32Array())
		if not native_groups.is_empty():
			var pose: Dictionary = POSE.from_native_groups(_actor_bodies[actor_id], native_groups)
			if not pose.is_empty():
				set_actor_pose(actor_id, pose)
		else:
			_apply_native_pose(actor_id, int(actor.get("animation", -1)),
				int(actor.get("frame", 0)), data_dir)
	for actor_id in _actor_visuals.keys():
		if not present.has(actor_id):
			remove_actor(actor_id)
	for actor_id in _sprite_actor_visuals.keys():
		if not sprite_present.has(actor_id):
			_remove_visual(_sprite_actor_visuals, actor_id)
	_update_speech_bubble(actors, data_dir, overlay_ceiling)
	# The native camera can follow a vehicle or an NPC, not always actor 0.
	# CameraZone also overrides the camera center with a scripted grid anchor.
	# Camera placement is applied by the app after receiving the full snapshot.


func sync_extra_snapshots(extras: Array, data_dir: String) -> void:
	var present := {}
	for value in extras:
		if not value is Dictionary:
			continue
		var extra: Dictionary = value
		var extra_id := int(extra.get("i", -1))
		var sprite_id := int(extra.get("sprite", -1))
		if extra_id < 0 or sprite_id < 0:
			continue
		present[extra_id] = true
		if (sprite_id & 32768) != 0:
			_sync_special_effect(extra_id, sprite_id & 32767, extra)
		else:
			_sync_sprite_visual(_extra_visuals, _extra_root, extra_id,
				sprite_id, extra, data_dir)
	for extra_id in _extra_visuals.keys():
		if not present.has(extra_id):
			_remove_visual(_extra_visuals, extra_id)


func set_speaking_actor(actor_id: int) -> void:
	if actor_id >= 0 and actor_id != _speaker_id:
		_bubble_flip = not _bubble_flip
	_speaker_id = actor_id
	if actor_id >= 0 and not _sprite_data_dir.is_empty():
		_update_speech_bubble(_last_actor_snapshots, _sprite_data_dir, _last_overlay_ceiling)
	if actor_id < 0 and _speech_bubble != null:
		_speech_bubble.visible = false


func _update_speech_bubble(actors: Array, data_dir: String, overlay_ceiling: int) -> void:
	if _speaker_id < 0:
		return
	for value in actors:
		if not value is Dictionary or int(value.get("i", -1)) != _speaker_id \
				or int(value.get("y", 0)) > overlay_ceiling:
			continue
		var bubble_id := 90 if _bubble_flip else 91
		if _speech_bubble == null or int(_speech_bubble.get_meta("sprite_id", -1)) != bubble_id:
			if _speech_bubble != null:
				_speech_bubble.queue_free()
			_speech_bubble = _sprite_renderer.create_instance(data_dir, bubble_id)
			if _speech_bubble == null:
				return
			# INCRUST.C DrawBulle anchors the graph beside the actor's head:
			# right for sprite 90, left for 91, with its top 20 px higher.
			var width_pixels := (_speech_bubble.mesh as QuadMesh).size.x / COORD.PIXEL_SIZE
			var height_pixels := (_speech_bubble.mesh as QuadMesh).size.y / COORD.PIXEL_SIZE
			_speech_bubble.set_meta("offset_x", 10.0 + width_pixels * 0.5 if bubble_id == 90 else -10.0 - width_pixels * 0.5)
			_speech_bubble.set_meta("offset_y", -20.0 + height_pixels * 0.5)
			var bubble_material := (_speech_bubble.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
			bubble_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bubble_material.no_depth_test = true
			bubble_material.render_priority = 100
			_speech_bubble.material_override = bubble_material
			_speech_bubble.set_meta("sprite_id", bubble_id)
			_sprite_root.add_child(_speech_bubble)
		_speech_bubble.visible = true
		var top: float = float(value.get("y", 0)) + float(value.get("y_max", 1300))
		var location := _native_position(int(value.get("x", 0)), int(top), int(value.get("z", 0)))
		_speech_bubble.transform = _sprite_renderer.sprite_transform(location,
			int(_speech_bubble.get_meta("offset_x", 0)),
			int(_speech_bubble.get_meta("offset_y", 0)))
		return
	if _speech_bubble != null:
		_speech_bubble.visible = false


func _sync_sprite_visual(visuals: Dictionary, parent: Node3D, item_id: int,
		sprite_id: int, state: Dictionary, data_dir: String) -> void:
	var visual: MeshInstance3D = visuals.get(item_id)
	if visual == null or int(visual.get_meta("sprite_id", -1)) != sprite_id:
		_remove_visual(visuals, item_id)
		visual = _sprite_renderer.create_instance(data_dir, sprite_id,
			int(state.get("offset_x", 0)), int(state.get("offset_y", 0)))
		if visual == null:
			return
		visual.set_meta("sprite_id", sprite_id)
		parent.add_child(visual)
		visuals[item_id] = visual
	visual.transform = _sprite_renderer.sprite_transform(
		_native_position(int(state.get("x", 0)), int(state.get("y", 0)),
			int(state.get("z", 0))), int(visual.get_meta("offset_x", 0)),
		int(visual.get_meta("offset_y", 0)))


func _sync_special_effect(extra_id: int, kind: int, state: Dictionary) -> void:
	if kind != 0 and kind != 1:
		_remove_visual(_extra_visuals, extra_id)
		return
	var visual: MeshInstance3D = _extra_visuals.get(extra_id)
	if visual == null or int(visual.get_meta("effect_kind", -1)) != kind:
		_remove_visual(_extra_visuals, extra_id)
		visual = _sprite_renderer.create_special_effect(kind)
		visual.set_meta("effect_kind", kind)
		_extra_root.add_child(visual)
		_extra_visuals[extra_id] = visual
	var age: int = maxi(0, int(state.get("age", 0)))
	# EXTRA.C: star zoom=4; impact zoom=min(32, 1+age); both /16.
	var scale_factor: float = 0.25 if kind == 0 else float(mini(32, 1 + age)) / 16.0
	visual.transform = _sprite_renderer.special_transform(
		_native_position(int(state.get("x", 0)), int(state.get("y", 0)),
			int(state.get("z", 0))), scale_factor, float(age) * TAU / 32.0 if kind == 0 else 0.0)


func _native_position(x: int, y: int, z: int) -> Vector3:
	return COORD.native_position(x, y, z)


func _remove_visual(visuals: Dictionary, key: int) -> void:
	if not visuals.has(key):
		return
	var visual: Node3D = visuals[key]
	visuals.erase(key)
	if is_instance_valid(visual):
		visual.queue_free()


func focus_native_camera(actors: Array, camera_state: PackedInt32Array) -> void:
	if actors.is_empty():
		return
	var follow_id := 0
	if camera_state.size() == 5:
		follow_id = camera_state[0]
	if camera_state.size() == 5 and camera_state[1] != 0:
		var target := COORD.grid_cell(camera_state[2], camera_state[3], camera_state[4])
		_position_camera(target)
		return
	for actor in actors:
		if actor is Dictionary and int(actor.get("i", -1)) == follow_id:
			focus_native_actor(actor)
			return
	if actors[0] is Dictionary:
		focus_native_actor(actors[0])


func focus_native_actor(actor: Dictionary) -> void:
	var target: Vector3 = COORD.native_position(int(actor.get("x", 0)),
		int(actor.get("y", 0)), int(actor.get("z", 0)))
	_position_camera(target)


func _position_camera(target: Vector3) -> void:
	var from_center := Vector3(cos(deg_to_rad(30.0)) / sqrt(2.0), 0.5,
		cos(deg_to_rad(30.0)) / sqrt(2.0))
	_camera.position = target + from_center * 30.0
	_camera.look_at(target, Vector3.UP)


func _apply_native_pose(actor_id: int, animation_index: int, frame: int, data_dir: String) -> void:
	if animation_index < 0 or not _actor_visuals.has(actor_id):
		return
	var key := Vector2i(animation_index, frame)
	if _pose_keys.get(actor_id) == key:
		return
	if not _animations.has(animation_index):
		_animations[animation_index] = VISUAL_CACHE.get_resource(data_dir, "animation", animation_index)
	var animation: Dictionary = _animations[animation_index]
	if not animation.get("ok", false):
		return
	var frame_index := clampi(frame, 0, int(animation["frame_count"]) - 1)
	var pose: Dictionary = POSE.sample(_actor_bodies[actor_id], animation,
		frame_index, frame_index, 0.0)
	set_actor_pose(actor_id, pose)
	_pose_keys[actor_id] = key
