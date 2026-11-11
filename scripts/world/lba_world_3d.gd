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
const LBA_LIGHTING := preload("res://scripts/render/lba_character_lighting.gd")


@export_group("Character Palette Lighting")
@export_range(0.5, 2.5, 0.05) var polygon_light_boost: float = 1.2

@export_group("Visual Grid Slope Overrides")
# BLL shape is collision only, not a guarantee that the BRK artwork is a ramp.
# Add a brick ID here to render it as a cube, e.g. [123, 456] for telepods.
@export var force_cube_brick_ids: PackedInt32Array = PackedInt32Array()
# Optional whitelist. If non-empty, ONLY these BRK IDs use authored slopes.
@export var allow_slope_brick_ids: PackedInt32Array = PackedInt32Array()
# Overrides keyed as "scene:brick" or "scene:x:y:z" (per cell), e.g. "4:123": false.
@export var slope_scene_brick_overrides: Dictionary = {}
# Log candidate BRK IDs and one cell location to help curate telepods vs ramps.
@export var log_slope_candidates: bool = false

@export_group("Isometric Scene Sprite Geometry")
# Only actual SPRITE_3D scene actors; never extras, stars, speech, drops.
# Collision auto uses LBA's authored collision ZV to choose a geometry profile.
@export_enum("Collision auto", "Billboard (legacy)", "Collision box", "Tapered platform", "Horizontal top", "Vertical X", "Vertical Z") var default_scene_sprite_mode: int = 0
@export_range(0.0, 0.4, 0.01) var platform_side_taper: float = 0.15
# Extra visual size in world units; never changes native collisions.
@export_range(0.0, 1.0, 0.01) var platform_visual_overhang: float = 0.12
# Optional per actor/sprite overrides, e.g. {"sprite:26": 0.18, "actor:7": 0.0}.
# actor:N takes priority. Values are world units added to every X/Z side.
@export var scene_sprite_visual_overhang: Dictionary = {}
# Visual-only inward shrinking along the proxy's thickness axis, world units.
# The collision box and its physics never change.
@export_range(0.0, 0.5, 0.005) var scene_sprite_visual_inset: float = 0.0
# Small VIEW-SPACE pushback in world units, letting Godot's own projection
# handle reversed-Z. Orthographic pixel positions stay unchanged.
@export_range(0.0, 0.25, 0.001) var scene_sprite_depth_bias: float = 0.015
# Per-instance overrides: {"actor:7": 0.025, "sprite:26": 0.0}.
@export var scene_sprite_visual_inset_overrides: Dictionary = {}
@export var scene_sprite_depth_bias_overrides: Dictionary = {}
# Doors/gates only, not platforms or cranes. Examples:
# {"actor:7": "fixed_aperture", "sprite:26": "fixed_aperture"}
# "follow" keeps the render proxy moving with the native actor (default).
# A fixed aperture stays at the actor's first observed location, while the
# image follows actor motion as a UV shift and is clipped to the original plane.
@export var scene_sprite_motion_profiles: Dictionary = {}
# Per-actor / per-sprite: {"sprite:12": "platform", "actor:5": "vertical_z"}
# Also accepts "box", "horizontal", "vertical_x", "vertical_z", "billboard".
@export var scene_sprite_profiles: Dictionary = {}
const SCENE_SPRITE_MODES := ["collision_auto", "billboard", "box", "platform", "horizontal", "vertical_x", "vertical_z"]

@export_group("Grid Lighting & Normal Maps")
# Single editable template. Each BRK copies its settings, not its albedo.
@export var grid_master_material: ShaderMaterial = preload("res://shaders/lba_grid_master.tres")
@export_range(0.0, 1.0, 0.01) var grid_ambient_floor: float = 0.0
@export_range(0.0, 2.0, 0.05) var grid_directional_strength: float = 1.0
@export_range(2, 16, 1) var grid_light_steps: int = 8
@export_range(0.0, 1.0, 0.05) var grid_dither_strength: float = 0.75
@export var grid_normal_map_world_space: bool = true
@export var grid_brick_normal_maps: Dictionary = {}

@export_group("Original LBA Model Shadow Meshes")
# Follows VisualShader > Flags > Unshaded, with explicit overrides for testing.
@export_enum("Follow Grid VisualShader", "Always Original", "Always Real-Time") var original_shadow_mode: int = 0
@export_range(0.0, 0.75, 0.005) var legacy_shadow_camera_offset: float = 0.075
# Visual-only clearance above the actor's contact plane. Never affects collision.
@export_range(0.0, 0.25, 0.005) var legacy_shadow_surface_clearance: float = 0.04

@onready var _actors: Node3D = $Actors
@onready var _bricks: Node3D = $Bricks
@export_group("Camera Orbit & Rotation")
# Offsets are *additive* to the native LBA camera angle (45-degree azimuth,
# 30-degree elevation). The Camera node's authored Transform rotation is also
# captured at startup as an additive offset. Do not edit Remote/Camera.rotation
# expecting it to persist: edit these World3D offsets live instead.
@export_range(-180.0, 180.0, 0.1) var camera_yaw_offset_degrees: float = 0.0
@export_range(-80.0, 80.0, 0.1) var camera_pitch_offset_degrees: float = 0.0
@export_range(-180.0, 180.0, 0.1) var camera_roll_offset_degrees: float = 0.0
@export_range(1.0, 150.0, 0.5) var camera_follow_distance: float = 30.0
@export var camera_use_authored_rotation: bool = true

@onready var _camera: Camera3D = $Camera
var _camera_authored_rotation_degrees: Vector3 = Vector3.ZERO

var _actor_visuals: Dictionary = {}
var _actor_bodies: Dictionary = {}
var _grid_visual: Node3D = null
var _authored_location: Node3D = null
var _grid_variants: Dictionary = {}
var _grid_scene := -1
var _grid_overlay := -2
var _grid_lighting_enabled: bool = true
var _grid_master_last_values: Dictionary = {}
var _grid_master_last_shader_id: int = -1
var _grid_master_last_material_id: int = -1
var _grid_data_dir := ""
var _brick_geometry_debug := false
var _brick_debug_material: StandardMaterial3D
var _archive_bodies: Dictionary = {}
var _geometry_cache: Dictionary = {}
var _animations: Dictionary = {}
var _pose_keys: Dictionary = {}
var _sprite_actor_visuals: Dictionary = {}
# Actor-local first-seen aperture positions and authored collision bounds.
var _sprite_aperture_anchors: Dictionary = {}
var _extra_visuals: Dictionary = {}
var _sprite_renderer := SPRITES.new()
var _legacy_shadow_visible: bool = false
var _sprite_root: Node3D
var _extra_root: Node3D
var _speech_bubble: MeshInstance3D
var _speaker_id := -1
var _bubble_flip := false
var _last_actor_snapshots: Array = []
var _last_overlay_ceiling := 2147483647
var _sprite_data_dir := ""


func _ready() -> void:
	_camera_authored_rotation_degrees = _camera.rotation_degrees
	_sprite_root = Node3D.new()
	_sprite_root.name = "SceneSprites"
	add_child(_sprite_root)
	_extra_root = Node3D.new()
	_extra_root.name = "EngineExtras"
	add_child(_extra_root)


func _process(_delta: float) -> void:
	_sync_original_shadow_mode()
	_sync_grid_master_material()
	if _actor_visuals.is_empty():
		return
	var lighting := LBA_LIGHTING.capture(self)
	for visual in _actor_visuals.values():
		LBA_LIGHTING.apply_to_model(visual as Node3D, lighting)
		for part in (visual as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mesh_part: MeshInstance3D = part as MeshInstance3D
			var material: ShaderMaterial = mesh_part.material_override as ShaderMaterial
			if material != null and material.shader != null \
					and material.shader.resource_path == "res://shaders/lba_character.gdshader":
				material.set_shader_parameter("lba_polygon_light_boost", polygon_light_boost)


func _exit_tree() -> void:
	clear_grid_scene()



func load_grid_scene(scene_index: int, data_dir: String, overlay_index: int = -1) -> bool:
	if _grid_visual != null and _grid_scene == scene_index and _grid_overlay == overlay_index and _grid_data_dir == data_dir:
		return true
	if _grid_scene != scene_index or _grid_data_dir != data_dir:
		clear_grid_scene()
	var next: Node3D = _grid_variants.get(overlay_index)
	if next == null:
		var result: Dictionary = GRID_RENDERER.build_scene(data_dir, scene_index, null, overlay_index, grid_master_material, force_cube_brick_ids, allow_slope_brick_ids, slope_scene_brick_overrides, log_slope_candidates)
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
	_load_authored_location(scene_index)
	_apply_brick_geometry_debug()
	apply_grid_render_settings(_grid_lighting_enabled)
	return true


# Editable per-location scenes live in the repository. The imported grid geometry
# is solely an editor guide: never instantiate it into running gameplay.
func _load_authored_location(scene_index: int) -> void:
	if _authored_location != null:
		remove_child(_authored_location)
		_authored_location.queue_free()
		_authored_location = null
	var path := "res://scenes/lba_locations/Scene_%03d.tscn" % scene_index
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			_authored_location = packed.instantiate() as Node3D
			if _authored_location != null:
				_authored_location.name = "AuthoredLocation"
				add_child(_authored_location)
				var preview := _authored_location.get_node_or_null("PreviewCollisionGrid")
				if preview != null:
					preview.visible = false
	# The authored sun takes over only if one was supplied in this scene.
	var global_sun := get_node_or_null("Sun") as DirectionalLight3D
	if global_sun != null:
		global_sun.visible = _authored_location == null or _authored_location.get_node_or_null("Lighting/Sun") == null


func apply_grid_render_settings(lit: bool) -> void:
	_grid_lighting_enabled = lit
	var applied: int = 0
	# MultiMeshInstance3D materials belong to the BRK grid variants.
	for variant_node in _grid_variants.values():
		var grid_root: Node3D = variant_node as Node3D
		if grid_root == null:
			continue
		for child in grid_root.get_children():
			var mesh_node: MultiMeshInstance3D = child as MultiMeshInstance3D
			if mesh_node == null:
				continue
			var material: ShaderMaterial = mesh_node.material_override as ShaderMaterial
			if material == null or material.shader == null:
				continue
			# No resource_path equality check: preloaded shaders and packed
			# resources may have different paths for the same tile shader.
			applied += 1
			material.set_shader_parameter("grid_lighting_enabled", lit)
			if grid_master_material == null:
				material.set_shader_parameter("ambient_floor", grid_ambient_floor)
				material.set_shader_parameter("directional_strength", grid_directional_strength)
				material.set_shader_parameter("light_steps", grid_light_steps)
				material.set_shader_parameter("dither_strength", grid_dither_strength)
				material.set_shader_parameter("normal_map_world_space", grid_normal_map_world_space)
			var brick_id: String = str(mesh_node.get_meta("lba_brick_id", String(mesh_node.name).trim_prefix("Brick_")))
			if grid_brick_normal_maps.has(brick_id) or grid_brick_normal_maps.has(int(brick_id)):
				var value: Variant = grid_brick_normal_maps.get(brick_id,
					grid_brick_normal_maps.get(int(brick_id), null))
				var normal_map: Texture2D = value as Texture2D
				material.set_shader_parameter("has_normal_map", normal_map != null)
				material.set_shader_parameter("normal_texture", normal_map)
	print("LBA grid lighting applied: lit=", lit, " materials=", applied, " active scene=", _grid_scene)
	if _grid_scene >= 0 and applied == 0:
		push_error("Grid contains no ShaderMaterials to light; inspect renderer material assignment.")


# Keep per-BRK materials in sync with one Inspector-editable master.
# ShaderMaterial.changed is not guaranteed for uniform edits, hence polling.
func _sync_grid_master_material() -> void:
	var master: ShaderMaterial = grid_master_material
	if master == null or master.shader == null or _grid_variants.is_empty():
		return
	var shared_parameters: Dictionary = {}
	for prop_info in master.get_property_list():
		var property_name: String = String(prop_info.get("name", ""))
		if not property_name.begins_with("shader_parameter/"):
			continue
		var name: String = property_name.trim_prefix("shader_parameter/")
		if name in ["albedo_texture", "alpha_texture", "graph_center_offset", "use_billboard_depth", "grid_lighting_enabled"]:
			continue
		shared_parameters[name] = master.get_shader_parameter(name)
	var shader_id: int = master.shader.get_instance_id()
	var material_id: int = master.get_instance_id()
	if shader_id == _grid_master_last_shader_id and material_id == _grid_master_last_material_id and shared_parameters == _grid_master_last_values:
		return
	_grid_master_last_values = shared_parameters.duplicate()
	_grid_master_last_shader_id = shader_id
	_grid_master_last_material_id = material_id
	var changed_count: int = 0
	for variant in _grid_variants.values():
		var grid_root: Node3D = variant as Node3D
		if grid_root == null:
			continue
		for child in grid_root.get_children():
			var grid_node: MultiMeshInstance3D = child as MultiMeshInstance3D
			if grid_node == null:
				continue
			var material: ShaderMaterial = grid_node.material_override as ShaderMaterial
			if material == null:
				continue
			if material.shader != master.shader:
				material.shader = master.shader
			for key in shared_parameters:
				material.set_shader_parameter(StringName(key), shared_parameters[key])
			# Preserve optional per-brick normal maps over the global default.
			var brick_id: String = str(grid_node.get_meta("lba_brick_id", String(grid_node.name).trim_prefix("Brick_")))
			if grid_brick_normal_maps.has(brick_id) or grid_brick_normal_maps.has(int(brick_id)):
				var value: Variant = grid_brick_normal_maps.get(brick_id,
					grid_brick_normal_maps.get(int(brick_id), null))
				var normal_map: Texture2D = value as Texture2D
				material.set_shader_parameter("normal_texture", normal_map)
				material.set_shader_parameter("has_normal_map", normal_map != null)
			changed_count += 1
	print("LBA grid master updated: ", changed_count, " BRK materials")


# VisualShader's render-mode Unshaded is the source of truth. Unlike a
# fragment uniform, its state belongs to the shader resource itself.
func _original_shadows_requested() -> bool:
	if original_shadow_mode == 1:
		return true
	if original_shadow_mode == 2:
		return false
	var selected_shader: Shader = null
	if grid_master_material != null:
		selected_shader = grid_master_material.shader
	if not _grid_lighting_enabled:
		return true
	if selected_shader is VisualShader:
		return bool(selected_shader.get("flags/unshaded"))
	return false


func _sync_original_shadow_mode() -> void:
	var wanted: bool = _original_shadows_requested()
	if wanted != _legacy_shadow_visible:
		_legacy_shadow_visible = wanted
		print("LBA model palette-overlay shadows: ", "on" if wanted else "off")
	_update_legacy_model_shadow_meshes(wanted)


func _update_legacy_model_shadow_meshes(wanted: bool) -> void:
	# Dedicated mode-5 mesh on each actor (including trucks and tanks).
	# Keeping mode 6 separate preserves its stippled transparent surfaces.
	var camera_forward: Vector3 = Vector3(0.0, 0.0, 1.0)
	if _camera != null:
		camera_forward = _camera.global_transform.basis.z.normalized()
	for actor_value in _actor_visuals.values():
		var actor_root: Node3D = actor_value as Node3D
		if actor_root == null:
			continue
		# Do not double-render Godot shadows and LBA's authored overlays.
		for candidate in actor_root.find_children("*", "MeshInstance3D", true, false):
			var part: MeshInstance3D = candidate as MeshInstance3D
			if part == null:
				continue
			if part.name == "LBA1LegacyShadowPolygons" or part.name == "LBA1TransparentPolygons" or part.name == "Wireframe":
				part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				part.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if wanted
					else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		var overlay: MeshInstance3D = actor_root.get_node_or_null("LBA1LegacyShadowPolygons") as MeshInstance3D
		if overlay == null:
			continue
		overlay.visible = wanted
		if wanted:
			# Both camera offset and a small upward clearance are required;
			# camera-only displacement can leave a buried shadow clipped.
			var offset_world: Vector3 = camera_forward * legacy_shadow_camera_offset
			var mesh_aabb: AABB = overlay.mesh.get_aabb() if overlay.mesh != null else AABB()
			# Flat shadow sheets may have an authored negative local Y.
			# Place those at the model contact plane rather than below the grid.
			var lift_local: float = legacy_shadow_surface_clearance
			if mesh_aabb.size.y < 0.12 and mesh_aabb.position.y < 0.0:
				lift_local += minf(-mesh_aabb.position.y, 1.0)
			var offset_local: Vector3 = actor_root.global_transform.basis.inverse() * offset_world
			overlay.position = offset_local + Vector3.UP * lift_local
		else:
			overlay.position = Vector3.ZERO


func toggle_grid_debug() -> void:
	_bricks.visible = not _bricks.visible


func toggle_brick_geometry_debug() -> void:
	_brick_geometry_debug = not _brick_geometry_debug
	if _brick_geometry_debug:
		_bricks.visible = true
	_apply_brick_geometry_debug()
	print("LBA F9 brick geometry debug: ", "SOLID CUBES" if _brick_geometry_debug else "ORIGINAL MATERIALS")


func _apply_brick_geometry_debug() -> void:
	if _grid_visual == null:
		return
	if _brick_debug_material == null:
		_brick_debug_material = StandardMaterial3D.new()
		_brick_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_brick_debug_material.albedo_color = Color(1.0, 0.12, 0.8, 1.0)
		_brick_debug_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for child in _grid_visual.get_children():
		var mesh_instance := child as MultiMeshInstance3D
		if mesh_instance == null:
			continue
		if _brick_geometry_debug:
			if not mesh_instance.has_meta("lba_debug_original_material"):
				mesh_instance.set_meta("lba_debug_original_material", mesh_instance.material_override)
			mesh_instance.material_override = _brick_debug_material
		elif mesh_instance.has_meta("lba_debug_original_material"):
			mesh_instance.material_override = mesh_instance.get_meta("lba_debug_original_material") as Material
			mesh_instance.remove_meta("lba_debug_original_material")


func are_bricks_visible() -> bool:
	return _bricks.visible


func clear_grid_scene() -> void:
	if _authored_location != null:
		remove_child(_authored_location)
		_authored_location.queue_free()
		_authored_location = null
	var global_sun := get_node_or_null("Sun") as DirectionalLight3D
	if global_sun != null:
		global_sun.visible = true
	if _grid_visual != null:
		_bricks.remove_child(_grid_visual)
	for variant in _grid_variants.values():
		(variant as Node3D).free()
	_grid_variants.clear()
	_grid_visual = null
	_grid_scene = -1
	_grid_overlay = -2
	_grid_data_dir = ""
	# Actor ids can be reused by another scene, never keep a prior door anchor.
	_sprite_aperture_anchors.clear()


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
			material.set_shader_parameter("use_actor_depth", false) # LBA_DEPTH_FIX_V2
	if _actor_visuals.has(actor_id):
		var previous: Node3D = _actor_visuals[actor_id]
		visual.transform = previous.transform
		_actors.remove_child(previous)
		previous.queue_free()
	_actors.add_child(visual)
	_actor_visuals[actor_id] = visual
	if body.get("game", "") == "LBA1":
		var legacy_count: int = int(visual.get_meta("lba_original_shadow_face_count", 0))
		var mode_counts: Dictionary = {}
		for poly in body["polygons"]:
			var mode: int = int(poly["render_type"])
			mode_counts[mode] = int(mode_counts.get(mode, 0)) + 1
		print("LBA model shadow probe actor=", actor_id, " body=", body_index,
			" overlay_faces=", legacy_count, " modes=", mode_counts)
	_update_legacy_model_shadow_meshes(_original_shadows_requested())
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
	_sprite_aperture_anchors.clear()
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
			_sprite_aperture_anchors.erase(actor_id)
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


func _scene_sprite_profile(sprite_id: int, actor_id: int, state: Dictionary) -> String:
	var mode: String = SCENE_SPRITE_MODES[clampi(default_scene_sprite_mode, 0, SCENE_SPRITE_MODES.size() - 1)]
	var actor_key := "actor:%d" % actor_id
	var sprite_key := "sprite:%d" % sprite_id
	if scene_sprite_profiles.has(actor_key):
		mode = str(scene_sprite_profiles[actor_key])
	elif scene_sprite_profiles.has(sprite_key):
		mode = str(scene_sprite_profiles[sprite_key])
	elif scene_sprite_profiles.has(sprite_id):
		mode = str(scene_sprite_profiles[sprite_id])
	if not _sprite_renderer.has_valid_collision(state.get("collision", {})):
		return "billboard"
	if mode == "collision_auto" or mode == "proxy":
		return _sprite_renderer.choose_collision_mode(state.get("collision", {}))
	if mode not in ["box", "platform", "billboard", "horizontal", "vertical_x", "vertical_z"]:
		return "billboard"
	return mode


func _scene_sprite_overhang(sprite_id: int, actor_id: int, mode: String) -> float:
	# Collision ZV sizes continue to drive gameplay; adjust only displayed mesh.
	var overhang: float = platform_visual_overhang if mode == "platform" else 0.0
	var actor_key: String = "actor:%d" % actor_id
	var sprite_key: String = "sprite:%d" % sprite_id
	if scene_sprite_visual_overhang.has(actor_key):
		overhang = float(scene_sprite_visual_overhang[actor_key])
	elif scene_sprite_visual_overhang.has(sprite_key):
		overhang = float(scene_sprite_visual_overhang[sprite_key])
	elif scene_sprite_visual_overhang.has(sprite_id):
		overhang = float(scene_sprite_visual_overhang[sprite_id])
	return clampf(overhang, 0.0, 2.0)


func _scene_sprite_numeric_override(sprite_id: int, actor_id: int,
		default_value: float, values: Dictionary) -> float:
	var actor_key: String = "actor:%d" % actor_id
	var sprite_key: String = "sprite:%d" % sprite_id
	if values.has(actor_key):
		return float(values[actor_key])
	if values.has(sprite_key):
		return float(values[sprite_key])
	if values.has(sprite_id):
		return float(values[sprite_id])
	return default_value


func _scene_sprite_motion_profile(sprite_id: int, actor_id: int, mode: String) -> String:
	# Keeping geometry fixed makes sense only for stationary upright apertures.
	# Platforms, travelling machinery, crane parts and extras always follow.
	if mode != "vertical_x" and mode != "vertical_z":
		return "follow"
	var actor_key: String = "actor:%d" % actor_id
	var sprite_key: String = "sprite:%d" % sprite_id
	var value: String = "follow"
	if scene_sprite_motion_profiles.has(actor_key):
		value = str(scene_sprite_motion_profiles[actor_key])
	elif scene_sprite_motion_profiles.has(sprite_key):
		value = str(scene_sprite_motion_profiles[sprite_key])
	elif scene_sprite_motion_profiles.has(sprite_id):
		value = str(scene_sprite_motion_profiles[sprite_id])
	return "fixed_aperture" if value == "fixed_aperture" else "follow"


func _aperture_uv_shift(anchor_world: Vector3, current_world: Vector3,
		visual: MeshInstance3D) -> Vector2:
	var delta: Vector3 = current_world - anchor_world
	var facing: Basis = COORD.camera_facing_basis()
	var width_px: float = maxf(1.0, float(visual.get_meta("source_width", 1.0)))
	var height_px: float = maxf(1.0, float(visual.get_meta("source_height", 1.0)))
	return Vector2(-delta.dot(facing.x) / (COORD.PIXEL_SIZE * width_px),
		delta.dot(facing.y) / (COORD.PIXEL_SIZE * height_px))


func _sync_sprite_visual(visuals: Dictionary, parent: Node3D, item_id: int,
		sprite_id: int, state: Dictionary, data_dir: String) -> void:
	# Extras deliberately use original billboards, irrespective of ID.
	var mode: String = _scene_sprite_profile(sprite_id, item_id, state) if parent == _sprite_root else "billboard"
	var motion_mode: String = _scene_sprite_motion_profile(sprite_id, item_id, mode) if parent == _sprite_root else "follow"
	var position: Vector3 = _native_position(int(state.get("x", 0)), int(state.get("y", 0)), int(state.get("z", 0)))
	var collision: Dictionary = state.get("collision", {}) if parent == _sprite_root else {}
	var anchor_position: Vector3 = position
	if motion_mode == "fixed_aperture":
		if not _sprite_aperture_anchors.has(item_id):
			_sprite_aperture_anchors[item_id] = {"position": position, "collision": collision.duplicate()}
		var anchor: Dictionary = _sprite_aperture_anchors[item_id]
		anchor_position = anchor["position"] as Vector3
		collision = anchor["collision"] as Dictionary
	else:
		_sprite_aperture_anchors.erase(item_id)
	var visual_overhang: float = _scene_sprite_overhang(sprite_id, item_id, mode) if parent == _sprite_root else 0.0
	var visual_inset: float = clampf(_scene_sprite_numeric_override(sprite_id, item_id,
		scene_sprite_visual_inset, scene_sprite_visual_inset_overrides), 0.0, 0.5) if parent == _sprite_root else 0.0
	var depth_bias: float = clampf(_scene_sprite_numeric_override(sprite_id, item_id,
		scene_sprite_depth_bias, scene_sprite_depth_bias_overrides), 0.0, 0.25) if parent == _sprite_root else 0.0
	var visual: MeshInstance3D = visuals.get(item_id)
	var changed := visual == null or int(visual.get_meta("sprite_id", -1)) != sprite_id
	if visual != null:
		changed = changed or str(visual.get_meta("render_mode", "billboard")) != mode
		changed = changed or str(visual.get_meta("motion_mode", "follow")) != motion_mode
		changed = changed or (mode != "billboard" and visual.get_meta("collision", {}) != collision)
		changed = changed or (mode == "platform" and absf(float(visual.get_meta("platform_taper", 0.0)) - platform_side_taper) > 0.001)
		changed = changed or (absf(float(visual.get_meta("visual_overhang", 0.0)) - visual_overhang) > 0.0001)
		changed = changed or (absf(float(visual.get_meta("visual_inset", 0.0)) - visual_inset) > 0.0001)
		changed = changed or (absf(float(visual.get_meta("depth_bias", 0.0)) - depth_bias) > 0.000001)
	if changed:
		_remove_visual(visuals, item_id)
		visual = _sprite_renderer.create_instance(data_dir, sprite_id,
			int(state.get("offset_x", 0)), int(state.get("offset_y", 0)),
			mode, collision, platform_side_taper, visual_overhang, visual_inset, depth_bias)
		if visual == null:
			return
		visual.set_meta("sprite_id", sprite_id)
		visual.set_meta("motion_mode", motion_mode)
		parent.add_child(visual)
		visuals[item_id] = visual
		if parent == _sprite_root:
			print("LBA scene sprite %d (actor %d): %s, ZV=%s" % [sprite_id,
				item_id, str(visual.get_meta("render_mode", "billboard")), str(collision)])
			if visual_overhang > 0.0:
				print("LBA sprite %d (actor %d) visual overhang: %.2f on each X/Z side" % [sprite_id, item_id, visual_overhang])
	# Do not freeze the simulation. Only render the door on a stationary
	# aperture, shifting its texture so its visible pixels still move.
	var render_position: Vector3 = anchor_position if motion_mode == "fixed_aperture" else position
	visual.transform = _sprite_renderer.scene_sprite_transform(render_position,
		float(visual.get_meta("offset_x", 0.0)),
		float(visual.get_meta("offset_y", 0.0)),
		str(visual.get_meta("render_mode", "billboard")))
	if motion_mode == "fixed_aperture":
		var material: ShaderMaterial = visual.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("sprite_uv_motion",
				_aperture_uv_shift(anchor_position, position, visual))


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
	# Native actor follow still controls the focus target. Only the *orientation*
	# and orbit distance are adjustable; the Camera resource controls perspective,
	# FOV, near/far, and h/v offset without runtime interference.
	var offset_angles: Vector3 = Vector3(
		camera_pitch_offset_degrees,
		camera_yaw_offset_degrees,
		camera_roll_offset_degrees)
	if camera_use_authored_rotation:
		offset_angles += _camera_authored_rotation_degrees
	var elevation: float = deg_to_rad(clampf(30.0 + offset_angles.x, -85.0, 85.0))
	var azimuth: float = deg_to_rad(45.0 + offset_angles.y)
	var from_center: Vector3 = Vector3(
		cos(elevation) * sin(azimuth),
		sin(elevation),
		cos(elevation) * cos(azimuth))
	var focus_world: Vector3 = to_global(target)
	_camera.global_position = focus_world + from_center * camera_follow_distance
	_camera.look_at(focus_world, Vector3.UP)
	_camera.rotate_object_local(Vector3.BACK, deg_to_rad(offset_angles.z))


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
