class_name LBACharacterLighting
extends RefCounted

# Per-vertex true Gouraud shading needs scene-light properties before the
# fragment stage. Godot's spatial light() callback cannot do that because it
# runs per fragment. This adapter feeds live Light3D properties to the shader.
# First pass uses directions/energy/ranges/cones, NOT shadow-map occlusion.
const MAX_LIGHTS := 8
const CHARACTER_SHADER := "res://shaders/lba_character.gdshader"


static func capture(root: Node3D) -> Dictionary:
	var positions := PackedVector4Array()
	var directions := PackedVector4Array()
	var colors := PackedVector4Array()
	var spots := PackedVector4Array()
	for node in root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light == null or not light.is_visible_in_tree() or light.light_energy <= 0.0:
			continue
		var position := light.global_position
		var direction := Vector3.ZERO
		var range_value := 0.0
		var type_id := 0.0
		var cutoff := -1.0
		var cone_power := 1.0
		var distance_power := 2.0
		if light is DirectionalLight3D:
			# Godot light shines along local -Z, so +Z points TO its source.
			direction = light.global_transform.basis.z.normalized()
		elif light is SpotLight3D:
			type_id = 2.0
			direction = -light.global_transform.basis.z.normalized()
			range_value = (light as SpotLight3D).spot_range
			cutoff = cos(deg_to_rad((light as SpotLight3D).spot_angle))
			cone_power = (light as SpotLight3D).spot_angle_attenuation
			distance_power = (light as SpotLight3D).spot_attenuation
		elif light is OmniLight3D:
			type_id = 1.0
			range_value = (light as OmniLight3D).omni_range
			distance_power = (light as OmniLight3D).omni_attenuation
		else:
			continue
		# RGB is reduced to luminance in the shader so the source palette
		# controls hue. Lights still contribute their authored energy/colour.
		var linear: Color = light.light_color.srgb_to_linear()
		positions.append(Vector4(position.x, position.y, position.z, type_id))
		directions.append(Vector4(direction.x, direction.y, direction.z, range_value))
		colors.append(Vector4(linear.r, linear.g, linear.b, light.light_energy))
		spots.append(Vector4(cutoff, cone_power, distance_power, 0.0))
		if positions.size() >= MAX_LIGHTS:
			break
	# Material uniform arrays always receive all 8 entries, even with fewer
	# scene lights. lba_light_count determines which elements are evaluated.
	var count := positions.size()
	while positions.size() < MAX_LIGHTS:
		positions.append(Vector4.ZERO)
		directions.append(Vector4.ZERO)
		colors.append(Vector4.ZERO)
		spots.append(Vector4.ZERO)
	return {
		"count": count, "positions": positions, "directions": directions,
		"colors": colors, "spots": spots
	}


static func apply_to_model(model: Node3D, data: Dictionary) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var material := mesh.material_override as ShaderMaterial
		if material == null or material.shader == null:
			continue
		if material.shader.resource_path != CHARACTER_SHADER:
			continue
		material.set_shader_parameter("use_scene_lights", true)
		material.set_shader_parameter("lba_light_count", data["count"])
		material.set_shader_parameter("lba_light_position_type", data["positions"])
		material.set_shader_parameter("lba_light_direction_range", data["directions"])
		material.set_shader_parameter("lba_light_color_energy", data["colors"])
		material.set_shader_parameter("lba_light_spot", data["spots"])
