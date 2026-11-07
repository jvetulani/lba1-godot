shader_type spatial;
render_mode cull_disabled, specular_disabled;

// The source BRK artwork is sampled pixel for pixel. A generated normal map
// can be assigned later without changing scene geometry or sampling mode.
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_nearest, repeat_disable;
uniform bool has_normal_map = false;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform float ambient_fraction : hint_range(0.0, 1.0) = 0.35;
uniform int light_steps : hint_range(2, 16) = 8;

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
