extends SceneTree

# Optional sanity check: run with your Godot 4.8 binary:
# godot --headless --path . --script res://tools/verify_lba_tile_visual.gd
func _initialize() -> void:
	var candidate: Resource = load("res://shaders/lba_tile_visual.tres")
	var shader: VisualShader = candidate as VisualShader
	if shader == null:
		push_error("LBA v55: visual grid shader failed to load")
		quit(2)
		return
	var code: String = shader.code
	for required in ["albedo_texture", "normal_texture", "grid_lighting_enabled", "DIFFUSE_LIGHT", "ATTENUATION", "discard"]:
		var required_name: String = str(required)
		if required_name not in code:
			push_error("LBA v55: expected code not generated: " + required_name)
			quit(3)
			return
	print("LBA v55: VisualShader generated; ", code.length(), " characters of shader code")
	print("LBA v55: material uniform names and light stage present")
	quit(0)
