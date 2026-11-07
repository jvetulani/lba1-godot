shader_type spatial;
render_mode cull_disabled, specular_disabled;

// The source BRK artwork is sampled pixel for pixel. A generated normal map
// can be assigned later without changing scene geometry or sampling mode.
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_nearest, repeat_disable;
uniform bool has_normal_map = false;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
// Reference-palette baseline: original BRK artwork is already hand-shaded.
// 1.0 preserves all authored colour; lower values opt into directional shading.
uniform float ambient_fraction : hint_range(0.0, 1.0) = 1.0;
uniform int light_steps : hint_range(2, 16) = 8;
uniform vec3 graph_center_offset = vec3(0.0);

void vertex() {
	vec4 vertex_clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 cell_origin = MODEL_MATRIX[3].xyz - graph_center_offset;
	vec4 cell_clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(cell_origin, 1.0);
	vertex_clip.z = cell_clip.z;
	POSITION = vertex_clip;
}

void fragment() {
	vec4 source = texture(albedo_texture, UV);
	if (source.a < alpha_cutoff) {
		discard;
	}
	ALBEDO = vec3(0.0);
	EMISSION = source.rgb * ambient_fraction;
	if (has_normal_map) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
		NORMAL_MAP_DEPTH = 1.0;
	}
}

void light() {
	vec3 source = texture(albedo_texture, UV).rgb;
	float strength = max(dot(normalize(NORMAL), normalize(LIGHT)), 0.0) * ATTENUATION;
	float bands = float(max(light_steps, 2));
	float threshold = fract(sin(dot(floor(FRAGCOORD.xy), vec2(127.1, 311.7))) * 43758.5453);
	float level = (floor(strength * bands) + step(threshold, fract(strength * bands))) / bands;
	DIFFUSE_LIGHT += source * LIGHT_COLOR * level * (1.0 - ambient_fraction);
}
