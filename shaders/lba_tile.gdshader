shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// The source BRK artwork is sampled pixel for pixel. A generated normal map
// can be assigned later without changing scene geometry or sampling mode.
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_nearest, repeat_disable;
uniform bool has_normal_map = false;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec4 source = texture(albedo_texture, UV);
	ALBEDO = source.rgb;
	ALPHA = source.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	if (has_normal_map) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
}
