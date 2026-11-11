extends SceneTree

# Repair only the editor camera in the existing scene. Never regenerate locations or mesh.
const SCENE_PATH := "res://scenes/holomap_authoring/TwinsunHolomap.tscn"

func _initialize() -> void:
    var packed: PackedScene = load(SCENE_PATH)
    if packed == null:
        push_error("Holomap authoring scene missing: " + SCENE_PATH)
        quit.call_deferred(1)
        return
    var root := packed.instantiate()
    if root == null:
        push_error("Cannot instantiate Holomap authoring scene")
        quit.call_deferred(1)
        return
    var camera := root.get_node_or_null("EditorCamera") as Camera3D
    if camera == null:
        push_error("EditorCamera not found; refusing to modify the authoring scene")
        root.free()
        quit.call_deferred(1)
        return
    # look_at() needs the node to be in the scene tree; look_at_from_position() does not.
    camera.look_at_from_position(Vector3(0, 2, 11), Vector3.ZERO)
    var result := packed.pack(root)
    if result == OK:
        result = ResourceSaver.save(packed, SCENE_PATH)
    root.free()
    packed = null
    if result != OK:
        push_error("Could not save camera-only repair, Godot error %d" % result)
        quit.call_deferred(1)
        return
    print("Repaired EditorCamera in ", SCENE_PATH, "; location edits preserved.")
    quit.call_deferred(0)
