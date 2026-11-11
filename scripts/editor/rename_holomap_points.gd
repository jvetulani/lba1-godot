extends SceneTree
const AUTHORING := "res://scenes/holomap_authoring/TwinsunHolomap.tscn"

func _initialize() -> void:
    var scene := load(AUTHORING) as PackedScene
    if scene == null:
        push_error("Cannot open authored Holomap")
        quit.call_deferred(1)
        return
    var root := scene.instantiate() as Node3D
    var locations := root.get_node_or_null("LocationsAlignment/Locations")
    if locations == null:
        push_error("Missing location parent")
        root.free()
        quit.call_deferred(1)
        return
    var used := {}
    var renamed := 0
    for child in locations.get_children():
        if not child is Node3D:
            continue
        var old_name := str(child.name)
        var id := int(child.get_meta("lba_location_id", -1))
        if id < 0 and old_name.length() >= 3 and old_name.substr(0, 3).is_valid_int():
            id = int(old_name.substr(0, 3))
        if id < 0:
            push_error("Cannot identify location: " + old_name)
            root.free()
            quit.call_deferred(1)
            return
        child.set_meta("lba_location_id", id)
        var readable := old_name
        if old_name.length() > 4 and old_name.substr(0, 3).is_valid_int() and old_name.substr(3, 1) == "_":
            readable = old_name.substr(4)
        elif old_name.begins_with("Location_"):
            readable = "Unnamed"
        # Make repeated place names distinguishable without screen-visible numbers.
        # Original numeric ID remains stable in metadata for native game logic.
        var stem := readable.strip_edges().replace(" ", "_")
        if stem.is_empty(): stem = "Unnamed"
        var suffix := int(used.get(stem, 0))
        used[stem] = suffix + 1
        var candidate := stem
        if suffix > 0: candidate += "_" + _letters(suffix)
        child.name = candidate
        var label := child.get_node_or_null("LocationLabel") as Label3D
        if label != null:
            label.text = readable.replace("_", " ")
            label.visible = false
        renamed += 1
    if renamed != 150:
        push_error("Expected 150 locations, got %d" % renamed)
        root.free()
        quit.call_deferred(1)
        return
    var packed := PackedScene.new()
    # Make saved metadata and renamed node references persistent.
    _set_owners(root, root)
    var err := packed.pack(root)
    if err == OK:
        err = ResourceSaver.save(packed, AUTHORING)
    root.free()
    if err != OK:
        push_error("Could not save authored names: " + error_string(err))
        quit.call_deferred(1)
        return
    print("Renamed %d locations, retained IDs in metadata" % renamed)
    quit.call_deferred(0)

func _letters(n: int) -> String:
    var result := ""
    while n > 0:
        n -= 1
        result = char(65 + n % 26) + result
        n = int(n / 26)
    return result

func _set_owners(node: Node, owner_root: Node) -> void:
    for c in node.get_children():
        c.owner = owner_root
        _set_owners(c, owner_root)
