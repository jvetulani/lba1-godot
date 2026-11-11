extends SceneTree

# In-place renaming of existing Holomap authoring nodes from original TEXT.HQR.
# Never regenerates mesh, marker positions, model transforms, or the scene hierarchy.
const TEXT_HQR := preload("res://scripts/ui/lba_text_hqr.gd")
const SCENE_PATH := "res://scenes/holomap_authoring/TwinsunHolomap.tscn"
const LANGUAGE := 0 # English; stable node names independent of active game language
const HOLOMAP_TEXT_BANK := 2

func _initialize() -> void:
	var text_path := _locate_text_archive()
	if text_path.is_empty():
		push_error("TEXT.HQR not found. Set LBA_DATA_PATH=/path/to/staged/data (containing TEXT.HQR). No changes made.")
		quit.call_deferred(1)
		return
	var bank: Dictionary = TEXT_HQR.load_bank(text_path, HOLOMAP_TEXT_BANK, LANGUAGE)
	if bank.is_empty():
		push_error("Unable to decode English Holomap text bank from " + text_path + ". No changes made.")
		quit.call_deferred(1)
		return
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Cannot load " + SCENE_PATH + ". No changes made.")
		quit.call_deferred(1)
		return
	var scene := packed.instantiate() as Node3D
	if scene == null:
		push_error("Cannot instantiate authoring scene. No changes made.")
		quit.call_deferred(1)
		return
	var locations := scene.get_node_or_null("LocationsAlignment/Locations")
	if locations == null:
		push_error("LocationsAlignment/Locations missing. No changes made.")
		scene.free()
		quit.call_deferred(1)
		return

	var renamed := 0
	var unavailable := 0
	var seen := {}
	for node in locations.get_children():
		if not (node is Node3D):
			continue
		var marker_id := _marker_id(node)
		if marker_id < 0 or marker_id >= 150:
			continue
		var message_id := int(node.get_meta("lba_message_id", -1))
		var entry: Dictionary = bank.get(message_id, {})
		var full_text := str(entry.get("text", "")).strip_edges()
		var title := _first_readable_line(full_text)
		if title.is_empty():
			unavailable += 1
			title = "Unnamed"
		var new_name := "%03d_%s" % [marker_id, _safe_name(title)]
		# Keep the ID in the name: original messages can have duplicate names.
		if seen.has(new_name):
			new_name += "_" + str(marker_id)
		seen[new_name] = true
		if node.name != new_name:
			node.name = new_name
			renamed += 1
		node.set_meta("lba_location_id", marker_id)
		if not full_text.is_empty():
			node.set_meta("lba_original_location_text", full_text)
		var label := node.get_node_or_null("LocationLabel") as Label3D
		if label != null:
			label.text = "%03d  %s" % [marker_id, title.substr(0, 52)]

	if renamed == 0 and unavailable >= 150:
		push_error("No location descriptions resolved from TEXT.HQR; refusing to rewrite the scene.")
		scene.free()
		quit.call_deferred(1)
		return
	var err := packed.pack(scene)
	if err == OK:
		err = ResourceSaver.save(packed, SCENE_PATH)
	scene.free()
	packed = null
	if err != OK:
		push_error("Could not save Holomap authoring scene, error %d" % err)
		quit.call_deferred(1)
		return
	print("Holomap names: renamed=%d, unnamed=%d, text=%s" % [renamed, unavailable, text_path])
	print("Marker transforms, GlobeAlignment, LocationsAlignment and TwinsenPlacement preserved.")
	quit.call_deferred(0)

func _marker_id(node: Node) -> int:
	if node.has_meta("lba_location_id"):
		return int(node.get_meta("lba_location_id"))
	var name := String(node.name)
	if name.begins_with("Location_") and name.substr(9, 3).is_valid_int():
		return int(name.substr(9, 3))
	if name.length() >= 3 and name.substr(0, 3).is_valid_int():
		return int(name.substr(0, 3))
	return -1

func _first_readable_line(raw: String) -> String:
	for line in raw.replace("\r", "\n").split("\n"):
		var candidate := line.strip_edges()
		if not candidate.is_empty():
			return candidate
	return ""

func _safe_name(raw: String) -> String:
	var result := ""
	var separator := false
	for i in range(raw.length()):
		var c := raw.substr(i, 1)
		var cp := raw.unicode_at(i)
		var allowed := (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)
		if allowed:
			result += c
			separator = false
		elif not separator and not result.is_empty():
			result += "_"
			separator = true
	result = result.trim_suffix("_")
	if result.is_empty():
		result = "Unnamed"
	return result.substr(0, 55).trim_suffix("_")

func _locate_text_archive() -> String:
	var folders: Array[String] = []
	var user_folder := OS.get_environment("LBA_DATA_PATH")
	if not user_folder.is_empty():
		folders.append(user_folder)
	folders.append(ProjectSettings.globalize_path("user://lba1-native/data"))
	for folder in folders:
		for filename in ["TEXT.HQR", "text.hqr"]:
			var candidate := folder.path_join(filename)
			if FileAccess.file_exists(candidate):
				return candidate
	return ""
