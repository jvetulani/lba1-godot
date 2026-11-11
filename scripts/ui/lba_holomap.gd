@tool
class_name LBAHolomap
extends Control

signal close_requested

@export_group("Holomap UI")
@export var globe_viewport: SubViewport
@export var holomap_environment: Node3D
@export var globe_rotation: Node3D
@export var location_label: Label
@export_group("Holomap Controls")
@export_range(0.1, 4.0, 0.05) var holomap_rotation_speed: float = 1.6
@export_range(1.0, 30.0, 0.5) var holomap_rotation_smoothing: float = 12.0
@export_group("TwinsunHolomap Scene")
@export var twinsun_holomap: Node3D
@export var globe_mesh: MeshInstance3D
@export var locations_root: Node3D
@export var twinsen_placement: Node3D
@export var model_alignment: Node3D
@export var twinsen_placeholder: MeshInstance3D
@export_group("Runtime-created Children")
@export var markers_container: Node3D
@export var trajectories_container: Node3D


# The original resources in RESS.HQR are the source of truth, not an editor mock route.
const HQR := preload("res://scripts/import/hqr_reader.gd")
const BODY := preload("res://scripts/import/lba1_body_decoder.gd")
const MESH := preload("res://scripts/render/character_mesh_builder.gd")
const VISUAL_CACHE := preload("res://scripts/import/lba_visual_cache.gd")
const POSE := preload("res://scripts/animation/lba1_pose.gd")
const TEXT_HQR := preload("res://scripts/ui/lba_text_hqr.gd")
const LANG := preload("res://scripts/ui/lba_languages.gd")
const MAX_POS := 150
const RADIUS := 3.0
const LAT_STEPS := 16
const LON_STEPS := 32

enum Mode { INVENTORY, TRAVEL }
var mode: Mode = Mode.INVENTORY
var _travel_id := -1
var _travel_elapsed := 0.0
var _travel_interval := 0.38
var _travel_shown := 0
var _marker_models: Dictionary = {}
var _travel_vehicle: Node3D
var _initial_orientation := Quaternion.IDENTITY
var _orientation := Quaternion.IDENTITY
var _target_orientation := Quaternion.IDENTITY

var _positions: Array[Dictionary] = []
var _flags := PackedInt32Array()
var _trajs: Array[Dictionary] = []
var _current := -1
var _selected := -1
var _pitch := 0.0
var _yaw := 0.0
var _target_pitch := 0.0
var _target_yaw := 0.0
var _viewport: SubViewport
var _pivot: Node3D
var _globe: MeshInstance3D
var _markers: Node3D
var _routes: Node3D
var _world: Node3D
var _status: Label
var _atlas: ImageTexture
var _messages := {}
var _loaded_path := ""
var _data_dir := ""
var _player_archive_body := -1
var _player_pose_groups := PackedInt32Array()
var _authored: Node3D
var _locations: Node3D
var _twinsen_anchor: Node3D
var _twinsen_model: Node3D
var _last_live_body := -99999



func _ready() -> void:
	_build_view()
	set_process(true)


func _build_view() -> void:
	# All pre-existing nodes are required typed Inspector assignments.
	_viewport = globe_viewport
	_world = holomap_environment
	_pivot = globe_rotation
	_globe = globe_mesh
	_markers = markers_container
	_routes = trajectories_container
	_status = location_label
	_authored = twinsun_holomap
	_locations = locations_root
	_twinsen_anchor = twinsen_placement
	if not _validate_scene_references():
		set_process(false)
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# The marker-preview branch stays editable, but is not visible in game.
	# The sphere is replaced by the original globe in _load_resources().
	if not Engine.is_editor_hint():
		locations_root.visible = false
		twinsen_placeholder.visible = false


func _validate_scene_references() -> bool:
	var required := {
		"globe_viewport": globe_viewport,
		"holomap_environment": holomap_environment,
		"globe_rotation": globe_rotation,
		"location_label": location_label,
		"twinsen_holomap": twinsun_holomap,
		"globe_mesh": globe_mesh,
		"locations_root": locations_root,
		"twinsen_placement": twinsen_placement,
		"model_alignment": model_alignment,
		"twinsen_placeholder": twinsen_placeholder,
		"markers_container": markers_container,
		"trajectories_container": trajectories_container,
	}
	var valid := true
	for name in required:
		if required[name] == null:
			push_error("Holomap: required Inspector reference '%s' is not assigned" % name)
			valid = false
	return valid


func set_player_appearance(body_id: int, pose_groups: PackedInt32Array = PackedInt32Array()) -> void:
	_player_archive_body = body_id
	_player_pose_groups = pose_groups
	_last_live_body = -99999


func configure_map(data_dir: String, native_state: PackedInt32Array) -> void:
	_data_dir = data_dir
	if _pivot == null:
		return
	var archive := data_dir.path_join("ress.hqr")
	if not FileAccess.file_exists(archive):
		archive = data_dir.path_join("RESS.HQR")
	var text_path: String = LANG.locate_text(data_dir)
	_messages = TEXT_HQR.load_bank(text_path, 2, LANG.get_text_index()) if not text_path.is_empty() else {}
	if archive != _loaded_path:
		if not _load_resources(archive):
			_status.text = "Original Holomap resources unavailable: ress.hqr"
			return
		_loaded_path = archive
		_load_marker_models(archive)
	if native_state.size() != MAX_POS + 1:
		_status.text = "Holomap native flags unavailable. Rebuild the GDExtension."
		return
	_current = clampi(int(native_state[0]), 0, MAX_POS - 1)
	_flags = native_state.slice(1)
	_selected = _current
	if mode == Mode.INVENTORY:
		_jump_to(_current)
		_update_markers()
	else:
		_start_travel(_travel_id)
	_update_status()


func _load_resources(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var pal := HQR.read_entry(path, 5)
	var alt := HQR.read_entry(path, 6)
	var map := HQR.read_entry(path, 7)
	var pos := HQR.read_entry(path, 8)
	var traj := HQR.read_entry(path, 30)
	if not (pal.get("ok", false) and alt.get("ok", false) and map.get("ok", false) and pos.get("ok", false)):
		return false
	var colors: PackedByteArray = pal.data
	var pixels: PackedByteArray = map.data
	var heights: PackedByteArray = alt.data
	if colors.size() < 768 or pixels.size() < 65536 or heights.size() < 32 * 17:
		return false
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in range(256):
		for x in range(256):
			var idx := int(pixels[y * 256 + x]) * 3
			image.set_pixel(x, y, Color8(colors[idx], colors[idx + 1], colors[idx + 2]))
	_atlas = ImageTexture.create_from_image(image)
	var positions: PackedByteArray = pos.data
	_positions.clear()
	for i in range(mini(MAX_POS, int(positions.size() / 8))):
		var o := i * 8
		_positions.append({"alpha": positions.decode_s16(o), "beta": positions.decode_s16(o + 2),
			"size": positions.decode_s16(o + 4), "message": positions.decode_s16(o + 6)})
	if _positions.size() != MAX_POS:
		return false
	# Editor-only copyrighted preview is excluded from exports. The original
	# globe is recreated here from the player's imported RESS.HQR at runtime.
	if _globe != null:
		_globe.mesh = _make_globe(heights)
	_trajs = _parse_trajectories(traj.data) if traj.get("ok", false) else []
	return true


# TwinsunHolomap.tscn is instantiated by Holomap.tscn, not by this script.
# There is no generated runtime scene and no bake step.


func _authored_location(index: int) -> Node3D:
	if _locations == null:
		return null
	for node in _locations.get_children():
		if node is Node3D and (int(node.get_meta("lba_location_id", -1)) == index
				or node.name.begins_with("%03d_" % index)
				or node.name == "Location_%03d" % index):
			return node as Node3D
	return null


func _location_position(index: int) -> Vector3:
	var node := _authored_location(index)
	if node != null:
		return _authored.to_local(node.global_position)
	if index >= 0 and index < _positions.size():
		var p: Dictionary = _positions[index]
		return _surface(float(p.alpha), float(p.beta), float(p.size) / 2.0)
	return Vector3.UP * RADIUS


func _refresh_live_twinsen() -> void:
	if _twinsen_anchor == null or _current < 0:
		return
	var marker := _authored_location(_current)
	# The saved authoring hierarchy is exactly:
	# TwinsenPlacement -> ModelAlignment -> CurrentTwinsen.
	# Do NOT look for or create a TwinsenHeight node.
	var alignment := model_alignment
	if marker == null or alignment == null:
		push_error("Holomap: missing authored marker or TwinsenPlacement/ModelAlignment")
		return
	# The artist's only two placement controls are the orbit rotation and
	# ModelAlignment's local Y. The character and its model are never rotated.
	# Explicitly undo the previously baked ModelAlignment rotations at runtime.
	# ModelAlignment rotation is authored as zero, and never changed by code.
	# Compare both points in the pivot PARENT's coordinate system. This keeps
	# the authored LocationsAlignment transform in the calculation.
	var marker_in_parent: Vector3 = _twinsen_anchor.get_parent().to_local(marker.global_position)
	var toward_marker: Vector3 = marker_in_parent - _twinsen_anchor.position
	if toward_marker.length_squared() < 0.000001:
		push_error("Holomap: marker lies at TwinsenPlacement pivot")
		return
	# Rotate only TwinsenPlacement: its local +Y points at the marker.
	_twinsen_anchor.quaternion = Quaternion(Vector3.UP, toward_marker.normalized())
	# Move only ModelAlignment's local Y until its origin reaches the marker.
	# No hardcoded radius, Euler offsets, model alignment or mesh-bounds fixes.
	alignment.position.y = _twinsen_anchor.to_local(marker.global_position).y
	if _twinsen_model != null and _last_live_body == _player_archive_body:
		if not _player_pose_groups.is_empty() and not _data_dir.is_empty():
			var live_body: Dictionary = VISUAL_CACHE.get_resource(_data_dir, "body", _player_archive_body)
			if live_body.get("ok", false):
				var live_pose: Dictionary = POSE.from_native_groups(live_body, _player_pose_groups)
				if not live_pose.is_empty():
					MESH.update_pose(_twinsen_model, live_body, live_pose)
		return
	if _twinsen_model != null:
		_twinsen_model.queue_free()
		_twinsen_model = null
	_last_live_body = _player_archive_body
	var decoded: Dictionary = {}
	var palette: PackedByteArray = PackedByteArray()
	if _player_archive_body >= 0 and not _data_dir.is_empty():
		decoded = VISUAL_CACHE.get_resource(_data_dir, "body", _player_archive_body)
		var color_bank: Dictionary = VISUAL_CACHE.get_resource(_data_dir, "palette", 0)
		if color_bank.get("ok", false):
			palette = color_bank["data"]
	# The RESS miniature is a last-resort visual only if native actor state is absent.
	if not decoded.get("ok", false):
		decoded = _marker_models.get(9, {})
		var marker_palette: Dictionary = HQR.read_entry(_loaded_path, 5)
		if marker_palette.get("ok", false):
			palette = marker_palette["data"]
	if not decoded.get("ok", false) or palette.size() < 768:
		push_warning("Holomap: player body unavailable for current outfit")
		return
	if (decoded.get("pose_points", PackedVector3Array()) as PackedVector3Array).is_empty():
		return
	var model := MESH.build_static_pose(decoded, palette, null, true)
	if not _player_pose_groups.is_empty() and decoded.get("game", "") == "LBA1":
		var pose: Dictionary = POSE.from_native_groups(decoded, _player_pose_groups)
		if not pose.is_empty():
			MESH.update_pose(model, decoded, pose)
	model.name = "CurrentTwinsen"
	# Reproduce the USER-VERIFIED local pole pose exactly. No bounds-based
	# scale/position, and no rotation of CurrentTwinsen or ModelAlignment.
	model.position = Vector3(0.0, 0.0, -0.015)
	model.scale = Vector3.ONE * 0.476
	alignment.add_child(model)
	_twinsen_model = model


# Match the proven v80 editor globe conversion. The actual mesh and palette
# still come from the player's original RESS.HQR, not from editor resources.
func _surface(alpha: float, beta: float, altitude: float = 0.0) -> Vector3:
	var a := alpha * TAU / 1024.0
	var b := beta * TAU / 1024.0
	var radius := RADIUS * (1000.0 + altitude * 2.0) / 1000.0
	return Vector3(cos(a) * cos(b), -sin(a), -cos(a) * sin(b)) * radius


func _make_globe(heights: PackedByteArray) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(LAT_STEPS + 1):
		for col in range(LON_STEPS + 1):
			var a := -256.0 + 512.0 * row / LAT_STEPS
			var b := 1024.0 * col / LON_STEPS
			var alt := int(heights[row * LON_STEPS + (col % LON_STEPS)])
			vertices.append(_surface(a, b, alt))
			uv.append(Vector2(float(col) / LON_STEPS, float(row) / LAT_STEPS))
	for row in range(LAT_STEPS):
		for col in range(LON_STEPS):
			var a := row * (LON_STEPS + 1) + col
			var b := a + LON_STEPS + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_texture = _atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.surface_set_material(0, material)
	return result


func _parse_trajectories(raw: PackedByteArray) -> Array[Dictionary]:
	var parsed: Array[Dictionary] = []
	var o := 0
	while o + 14 <= raw.size():
		var start := int(raw.decode_u16(o))
		var end := int(raw.decode_u16(o + 2))
		var count := int(raw.decode_u16(o + 12))
		if count <= 0 or count > 512 or o + 14 + count * 4 > raw.size():
			break
		var points := PackedVector3Array()
		for i in range(count):
			var p := o + 14 + i * 4
			points.append(_surface(raw.decode_s16(p), raw.decode_s16(p + 2), 14.0))
		parsed.append({"from": start, "to": end, "vehicle": int(raw.decode_u16(o + 4)), "points": points})
		o += 14 + count * 4
	return parsed


# Original miniature Holomap models are BODY-format records in RESS.HQR.
# Decode with the same pipeline as the rest of the game; never substitute
# bright spheres for undiscovered positions or decorative routes.
func _load_marker_models(archive: String) -> void:
	_marker_models.clear()
	for resource_id in [9, 10, 11]:
		var entry: Dictionary = HQR.read_entry(archive, resource_id)
		if not entry.get("ok", false):
			push_warning("Holomap: missing original RESS.HQR entry %d" % resource_id)
			continue
		var decoded: Dictionary = BODY.decode(entry["data"])
		if decoded.get("ok", false):
			_marker_models[resource_id] = decoded
		else:
			push_warning("Holomap: unable to decode marker %d: %s" % [resource_id, str(decoded.get("error", "unknown"))])


func _clear_children(parent: Node3D) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _spawn_original_marker(resource_id: int, position: Vector3, height: float = 0.42) -> Node3D:
	if not _marker_models.has(resource_id):
		return null
	var palette: Dictionary = HQR.read_entry(_loaded_path, 5)
	if not palette.get("ok", false):
		return null
	var body: Dictionary = _marker_models[resource_id]
	var model := MESH.build_static_pose(body, palette["data"])
	var points: PackedVector3Array = body["pose_points"]
	if points.is_empty():
		model.queue_free()
		return null
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for raw_point in points:
		var p: Vector3 = raw_point / 512.0
		low = low.min(p)
		high = high.max(p)
	var scale_factor: float = height / maxf(0.01, high.y - low.y)
	model.scale = Vector3.ONE * scale_factor
	# Original RESS.HQR Holomap BODY models use the native engine's
	# downward Y axis. Convert them to Godot Y-up before anchoring feet.
	# Rotating around X reverses both Y and Z.
	model.rotation.x = PI
	model.position = Vector3(-(low.x + high.x) * scale_factor * 0.5,
		high.y * scale_factor, (low.z + high.z) * scale_factor * 0.5)
	var anchor := Node3D.new()
	anchor.position = position
	anchor.quaternion = Quaternion(Vector3.UP, position.normalized())
	anchor.add_child(model)
	_markers.add_child(anchor)
	return anchor


func _update_markers() -> void:
	_clear_children(_markers)
	_clear_children(_routes)
	if mode != Mode.INVENTORY:
		return
	for i in range(_positions.size()):
		if i != _current and (_flags.size() <= i or (_flags[i] & 128) == 0):
			continue
		var p: Dictionary = _positions[i]
		var position := _location_position(i)
		var destination: bool = _flags.size() > i and (_flags[i] & 1) != 0
		if i == _current:
			if _twinsen_anchor == null:
				_spawn_original_marker(9, position)
			else:
				_refresh_live_twinsen()
		if destination:
			_spawn_original_marker(10, position)


func _jump_to(index: int) -> void:
	if index < 0 or index >= _positions.size():
		return
	var p: Dictionary = _positions[index]
	# Derive orientation directly from the selected surface normal. This works
	# for both hemispheres and avoids the old double-latitude Euler sign bug.
	var direction := _location_position(index).normalized()
	_target_orientation = Quaternion(direction, Vector3.BACK)
	if _orientation == Quaternion.IDENTITY and _selected == _current:
		_orientation = _target_orientation
	_pitch = 0.0
	_yaw = 0.0
	_target_pitch = 0.0
	_target_yaw = 0.0
	_apply_globe_rotation()


func _apply_globe_rotation() -> void:
	if _pivot == null:
		return
	_pivot.quaternion = Quaternion(Vector3.RIGHT, _pitch) * Quaternion(Vector3.UP, _yaw) * _orientation


# Travel is a separate mode of this same screen. Only the requested trajectory
# is drawn, progressively. The normal inventory Holomap never shows routes.
func configure_travel(data_dir: String, native_state: PackedInt32Array, trajectory_id: int) -> void:
	mode = Mode.TRAVEL
	_travel_id = trajectory_id
	configure_map(data_dir, native_state)


func configure_inventory(data_dir: String, native_state: PackedInt32Array) -> void:
	mode = Mode.INVENTORY
	_travel_id = -1
	configure_map(data_dir, native_state)


func _start_travel(trajectory_id: int) -> void:
	_clear_children(_markers)
	_clear_children(_routes)
	_travel_elapsed = 0.0
	_travel_shown = 0
	if trajectory_id < 0 or trajectory_id >= _trajs.size():
		_status.text = "Travel trajectory unavailable"
		return
	var travel: Dictionary = _trajs[trajectory_id]
	var start_index := int(travel["from"])
	if start_index >= 0 and start_index < _positions.size():
		_jump_to(start_index)
	# Vehicle models are stored at RESS entries 31 + vehicle*2.
	var archive := _loaded_path
	var entry_id := 31 + int(travel.get("vehicle", 0)) * 2
	var entry: Dictionary = HQR.read_entry(archive, entry_id)
	if entry.get("ok", false):
		var body: Dictionary = BODY.decode(entry["data"])
		if body.get("ok", false):
			_marker_models[entry_id] = body
			var from_location: Dictionary = _positions[start_index] if start_index >= 0 and start_index < _positions.size() else {}
			if not from_location.is_empty():
				_spawn_original_marker(entry_id, _location_position(start_index), 0.5)
	# The character's appearance is still sourced from the current native body.
	# Vehicle and traveler are distinct nodes; a future native event supplies
	# the specific travel ID. No fake default vehicle is selected here.
	if _twinsen_anchor != null:
		_refresh_live_twinsen()
	_update_status()


func _add_travel_dot(point: Vector3) -> void:
	var dot := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.027
	mesh.height = 0.054
	dot.mesh = mesh
	dot.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.8, 0.24)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material_override = material
	_routes.add_child(dot)


func _select_arrow(direction: int) -> void:
	if _flags.size() != MAX_POS:
		return
	var idx := _selected
	for _n in range(MAX_POS):
		idx = posmod(idx + direction, MAX_POS)
		if idx == _current or (_flags[idx] & 129) != 0:
			_selected = idx
			_jump_to(idx)
			_update_status()
			return
	_selected = _current
	_jump_to(_current)
	_update_status()


func _update_status() -> void:
	if _status == null:
		return
	if mode == Mode.TRAVEL:
		if _travel_id >= 0 and _travel_id < _trajs.size():
			_status.text = "Journey %d" % _travel_id
		return
	var message := ""
	if _selected >= 0 and _selected < _positions.size():
		var text_id := int(_positions[_selected].get("message", -1))
		message = str((_messages.get(text_id, {}) as Dictionary).get("text", "")).strip_edges()
	if message.is_empty():
		message = "Current location" if _selected == _current else "Destination"
	_status.text = message.replace("\n", " ").substr(0, 100)


func _request_close() -> void:
	close_requested.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_H] and mode == Mode.INVENTORY:
		_request_close()
	elif mode == Mode.INVENTORY and key.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		# Plain arrows move to the previous/next discovered location.
		# Ctrl+arrows NEVER select a destination; held keys rotate in _process.
		if not key.ctrl_pressed and not Input.is_key_pressed(KEY_CTRL):
			_select_arrow(-1 if key.keycode in [KEY_LEFT, KEY_UP] else 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _pivot == null or not visible:
		return
	# Original LBA Holomap controls: HOLD Ctrl + an arrow to rotate.
	# Read key state every frame; no OS key-repeat steps or one-shot nudges.
	if mode == Mode.INVENTORY and Input.is_key_pressed(KEY_CTRL):
		var horizontal := float(Input.is_key_pressed(KEY_LEFT)) - float(Input.is_key_pressed(KEY_RIGHT))
		var vertical := float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
		_target_yaw += horizontal * holomap_rotation_speed * delta
		_target_pitch += vertical * holomap_rotation_speed * delta
	# Exponential smoothing behaves consistently at different frame rates.
	var blend := 1.0 - exp(-holomap_rotation_smoothing * delta)
	_pitch = lerpf(_pitch, _target_pitch, blend)
	_yaw = lerpf(_yaw, _target_yaw, blend)
	_orientation = _orientation.slerp(_target_orientation, blend)
	_apply_globe_rotation()
	if mode == Mode.TRAVEL and _travel_id >= 0 and _travel_id < _trajs.size():
		var points: PackedVector3Array = _trajs[_travel_id]["points"]
		_travel_elapsed += delta
		while _travel_elapsed >= _travel_interval and _travel_shown < points.size():
			_travel_elapsed -= _travel_interval
			_add_travel_dot(points[_travel_shown])
			_travel_shown += 1
