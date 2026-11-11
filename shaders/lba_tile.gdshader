shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// LBA1 projected BRK grid. Main art/alpha come from the existing BRK renderer.
// Toon light stage mirrors the user's toon.tres: N dot L -> ramp -> light
// colour * ATTENUATION, adding contributions across ALL active lights.
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D alpha_texture : filter_nearest, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_nearest, repeat_disable;
uniform bool has_normal_map = false;
uniform bool normal_map_world_space = true;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.5;
uniform bool grid_lighting_enabled = true;
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.0;
uniform float directional_strength : hint_range(0.0, 3.0) = 1.0;
uniform int light_steps : hint_range(2, 16) = 8;
uniform float dither_strength : hint_range(0.0, 1.0) = 0.75;
uniform float toon_specular_strength : hint_range(0.0, 1.0) = 0.0;
uniform int specular_steps : hint_range(2, 16) = 4;
uniform float specular_power : hint_range(1.0, 64.0) = 16.0;
uniform vec3 graph_center_offset = vec3(0.0);
uniform bool use_billboard_depth = false;

float grid_bayer4(vec2 ip) {
	vec2 p = mod(floor(ip), 4.0);
	float a = 0.0;
	// Canonical 4x4 Bayer ordered threshold, stable in original BRK texels.
	if (p.y < 1.0) {
		if (p.x < 1.0) { a = 0.0; }
		else if (p.x < 2.0) { a = 8.0; }
		else if (p.x < 3.0) { a = 2.0; }
		else { a = 10.0; }
	} else if (p.y < 2.0) {
		if (p.x < 1.0) { a = 12.0; }
		else if (p.x < 2.0) { a = 4.0; }
		else if (p.x < 3.0) { a = 14.0; }
		else { a = 6.0; }
	} else if (p.y < 3.0) {
		if (p.x < 1.0) { a = 3.0; }
		else if (p.x < 2.0) { a = 11.0; }
		else if (p.x < 3.0) { a = 1.0; }
		else { a = 9.0; }
	} else {
		if (p.x < 1.0) { a = 15.0; }
		else if (p.x < 2.0) { a = 7.0; }
		else if (p.x < 3.0) { a = 13.0; }
		else { a = 5.0; }
	}
	return (a + 0.5) / 16.0;
}

float grid_toon_ramp(float cosine, float levels, vec2 texel) {
	float t = clamp(cosine, 0.0, 1.0);
	float steps = max(levels - 1.0, 1.0);
	float scaled = t * steps;
	float discrete = (floor(scaled) + step(grid_bayer4(texel), fract(scaled))) / steps;
	// Keep the viewer's footprint-aware transition to suppress crawling.
	float pixel_footprint = max(length(dFdx(texel)), length(dFdy(texel)));
	float amount = (1.0 - smoothstep(0.75, 1.5, pixel_footprint)) * dither_strength;
	return mix(t, discrete, amount);
}

void fragment() {
	vec3 paint_out;
	vec3 emission_out;
	float normal_depth_out;
if (UV.x < 0.0 || UV.x > 1.0 || UV.y < 0.0 || UV.y > 1.0) {
	discard;
}
vec4 sampled_art = texture(albedo_texture, UV);
// Discard, don't write ALPHA: depth/shadows remain on the opaque cutout pass.
if (texture(alpha_texture, UV).a < alpha_cutoff) {
	discard;
}
paint_out = grid_lighting_enabled ? sampled_art.rgb : vec3(0.0);
emission_out = grid_lighting_enabled ? sampled_art.rgb * ambient_floor : sampled_art.rgb;
normal_depth_out = 1.0;
if (grid_lighting_enabled && has_normal_map) {
	vec3 encoded_n = texture(normal_texture, UV).rgb;
	if (normal_map_world_space) {
		vec3 n_world = normalize(encoded_n * 2.0 - vec3(1.0));
		NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	} else {
		NORMAL_MAP = encoded_n;
		NORMAL_MAP_DEPTH = 1.0;
	}
}

	ALBEDO = paint_out;
	EMISSION = emission_out;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
void light() {
	vec3 light_diffuse_out;
	vec3 light_specular_out;
// Reuse the computed fragment ALBEDO. Godot applies it to DIFFUSE_LIGHT.
// All lights accumulate in the engine light loop, just as in toon.tres.
vec3 surface_n = normalize(NORMAL);
vec3 direction_l = normalize(LIGHT);
vec2 brick_texel = UV * vec2(textureSize(albedo_texture, 0));
float cosine = max(dot(surface_n, direction_l), 0.0);
float diffuse_band = grid_toon_ramp(cosine, float(max(light_steps, 2)), brick_texel);
vec3 diffuse_step = diffuse_band * LIGHT_COLOR * ATTENUATION * directional_strength / PI;
light_diffuse_out = DIFFUSE_LIGHT + (grid_lighting_enabled ? diffuse_step : vec3(0.0));
light_specular_out = SPECULAR_LIGHT;
if (grid_lighting_enabled && toon_specular_strength > 0.0) {
	vec3 reflected = reflect(-direction_l, surface_n);
	float shininess = pow(max(dot(normalize(VIEW), reflected), 0.0), specular_power);
	float spec_band = grid_toon_ramp(shininess, float(max(specular_steps, 2)), brick_texel);
	light_specular_out += spec_band * LIGHT_COLOR * ATTENUATION * toon_specular_strength / PI;
}

	DIFFUSE_LIGHT = light_diffuse_out;
	SPECULAR_LIGHT = light_specular_out;
}
