shader_type spatial;
render_mode cull_back, unshaded;

uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D texture_atlas : filter_nearest, repeat_disable;
uniform sampler2D shade_table : filter_nearest, repeat_disable;
uniform bool has_texture_atlas = false;
uniform bool has_shade_table = false;
uniform bool lba1_palette_effects = false;
// Preview shading stays inside the source palette's 16-colour ramps.
uniform float palette_ramp_size = 0.0;
uniform float normal_light_level = 12.0;
uniform int palette_index_override = -1;
// LBA1 sphere primitives have a material palette index but no CUSTOM2 data.
// Their palette index identifies the colour ramp, not a fixed brightness.
uniform bool lba_sphere_primitive = false;
// Draw original LBA1 line primitives at their authored palette index.
uniform bool lba_line_primitive = false;
// The authored palette index is a sphere's reference shade in its colour ramp.
// At this many accumulated lighting steps, the sphere retains that shade.
// Additional scene light moves it brighter; less light makes it darker.
uniform float sphere_reference_steps : hint_range(0.0, 15.0) = 7.0;
// Only generated SphereMesh primitives receive this flag (not line cylinders).
// Sphere UVs stay attached to curved geometry, avoiding projection-axis pops.
uniform bool lba_sphere_uv_dither = false;
// Small projected sphere patterns fade to a single exact palette index.
uniform float sphere_dither_density : hint_range(4.0, 24.0, 1.0) = 10.0;
// Keep dark sphere materials inside the useful portion of their own palette
// ramp. Some LBA1 banks contain high-luma orange entries that are inappropriate
// as highlights for very dark hair. Does not affect polygons or hand colours
// whose palette steps remain close to their authored colour.
uniform bool sphere_palette_highlight_guard = true;
uniform float sphere_palette_max_luma_ratio : hint_range(1.0, 8.0, 0.1) = 3.0;
uniform float sphere_palette_max_luma_added : hint_range(0.0, 0.5, 0.01) = 0.10;
// Eye-white diagnostic/guard: only brighten an anomalously near-black shade
// when the ORIGINAL authored sphere colour is already bright. Dark authored
// pupils and hair are excluded. This does not repair missing/backfacing faces.
uniform bool sphere_palette_shadow_guard = true;
uniform float sphere_palette_bright_base : hint_range(0.0, 1.0) = 0.45;
uniform float sphere_palette_min_luma_ratio : hint_range(0.0, 1.0) = 0.14;
uniform bool use_mesh_lighting = false;
uniform float mesh_light_span = 7.0;
// Godot game mode: every light pass supplies its actual direction, colour,
// attenuation and shadow. The legacy vector remains for viewer previews.
uniform bool use_scene_lights = false;
// Anchor overall ordering to the actor position, but keep local BODY depth so
// faces still occlude one another and walls can genuinely cover the actor.
uniform bool use_actor_depth = false;
// Keep intra-BODY face depth, but do not let distant face vertices pull a
// whole actor through a foreground/behind brick billboard. This controls
// presentation only; collision and world transforms remain native.
uniform float actor_depth_span : hint_range(0.0, 1.0) = 0.08;
instance uniform vec3 actor_sort_origin = vec3(0.0);
// Runtime lights are supplied by lba_character_lighting.gd. This is deliberate:
// Godot spatial light() runs per fragment, so exact Gouraud lighting must be
// evaluated per vertex if palette quantisation is to happen AFTER accumulation.
// The input lights come from actual Directional/Omni/SpotLight3D scene nodes.
// Only ordinary polygon surfaces; sphere hair and authored lines stay unchanged.
uniform float lba_polygon_light_boost : hint_range(0.5, 2.5, 0.05) = 1.2;
uniform float scene_ambient_steps : hint_range(0.0, 15.0) = 2.0;
uniform float scene_light_span : hint_range(0.0, 15.0) = 7.0;
uniform float scene_specular_steps : hint_range(0.0, 15.0) = 0.0;
uniform float scene_specular_power : hint_range(1.0, 128.0) = 32.0;
uniform int lba_light_count = 0;
// position_type.w: 0 directional, 1 omni, 2 spot
uniform vec4 lba_light_position_type[8];
// direction_range.xyz: direction TOWARDS source for directional, beam for spot
// direction_range.w: distance range for omni/spot
uniform vec4 lba_light_direction_range[8];
// Linear light colour RGB and scene light_energy in W
uniform vec4 lba_light_color_energy[8];
// Spot: x = cos(outer angle), y = angular exponent; z = range exponent
uniform vec4 lba_light_spot[8];
// 0 = palette bands, 1 = source MAT_DITHER faces (diagnostic),
// 3 = smooth, 4 = soft model-anchored dither.
uniform int dither_mode = 4;
uniform float dither_pixel_scale = 1.0;
uniform float soft_dither_strength = 0.7;
// Preview experiments: 0 = current, 1 = quiet smooth, 2 = palette-only flats.
uniform int soft_dither_profile = 1;
uniform bool platform_style = false;
// Approximate integer vector from LBA1 SetLightVector(896, 950, 0): a
// 59-unit light rotated by the game's angle convention. Scene light changes
// and the original trigonometric lookup table are future work.
uniform vec3 source_light_vector = vec3(-25.8, 37.6, 37.6);

varying float source_palette_index;
varying flat float source_render_type;
varying flat float source_base_index;
varying vec3 pixel_source_normal;
varying float pixel_light_scale;
varying float platform_height;
varying flat vec4 texture_region;
varying vec3 dither_anchor;

float dither_hash(vec2 coordinate) {
	return fract(sin(dot(coordinate, vec2(127.1, 311.7))) * 43758.5453);
}

float aperiodic_threshold(vec2 screen_pixel) {
	return dither_hash(floor(screen_pixel / max(dither_pixel_scale, 1.0)));
}

vec2 anchored_dither_coord() {
	vec3 face_axis = abs(cross(dFdx(dither_anchor), dFdy(dither_anchor)));
	if (face_axis.x > face_axis.y && face_axis.x > face_axis.z) {
		return dither_anchor.yz * 256.0;
	}
	if (face_axis.y > face_axis.z) {
		return dither_anchor.xz * 256.0;
	}
	return dither_anchor.xy * 256.0;
}

float anchored_dither_threshold(vec2 coord) {
	vec2 cell = floor(coord);
	vec2 tile = floor(cell / 8.0);
	vec2 local = mod(cell, 8.0);
	int turn = int(floor(dither_hash(tile + vec2(19.0, 7.0)) * 4.0));
	if (turn == 1) {
		local = vec2(7.0 - local.y, local.x);
	} else if (turn == 2) {
		local = vec2(7.0 - local.x, 7.0 - local.y);
	} else if (turn == 3) {
		local = vec2(local.y, 7.0 - local.x);
	}
	return dither_hash(local + tile * vec2(37.0, 53.0));
}

float anchored_dither_weight(vec2 coord) {
	float footprint = max(length(dFdx(coord)), length(dFdy(coord)));
	return 1.0 - smoothstep(0.75, 1.5, footprint);
}

float transition_dither_coverage(vec3 lower_color, vec3 upper_color, float shade) {
	// Estimate visible colour change over a patch, rather than gating every
	// palette step separately. The latter makes flat/dither/flat stripes.
	float shade_slope = length(vec2(dFdx(shade), dFdy(shade)));
	float visible_change = length(upper_color - lower_color) * shade_slope * 64.0;
	return smoothstep(0.08, 0.22, visible_change);
}

vec3 preview_dither_blend(vec3 lower_color, vec3 upper_color, float shade, vec2 coord) {
	float fraction = fract(shade);
	float threshold = anchored_dither_threshold(coord);
	vec3 smooth_color = mix(lower_color, upper_color, fraction);
	vec3 stepped_color = fraction > threshold ? upper_color : lower_color;
	float footprint = anchored_dither_weight(coord);
	if (soft_dither_profile == 0) {
		return mix(smooth_color, stepped_color, footprint * soft_dither_strength);
	}
	float coverage = transition_dither_coverage(lower_color, upper_color, shade) * footprint;
	if (soft_dither_profile == 1) {
		return mix(smooth_color, stepped_color, coverage * soft_dither_strength * 0.8);
	}
	float nearest = step(0.5, fraction);
	float active_fraction = mix(nearest, fraction, coverage);
	return active_fraction > threshold ? upper_color : lower_color;
}

float keep_in_palette_ramp(float base_index, float lit_index) {
	if (palette_ramp_size < 2.0 || (dither_mode != 3 && dither_mode != 4)) {
		return mod(lit_index, 256.0);
	}
	float ramp_start = floor(base_index / palette_ramp_size) * palette_ramp_size;
	return clamp(lit_index, ramp_start, ramp_start + palette_ramp_size - 1.0);
}

float varied_bayer_threshold(vec2 screen_pixel, float cell) {
	vec2 grid_pixel = floor(screen_pixel / cell);
	vec2 tile = floor(grid_pixel / 4.0);
	ivec2 pixel = ivec2(mod(grid_pixel, vec2(4.0)));
	int rotation = int(floor(dither_hash(tile) * 4.0));
	if (rotation == 1) {
		pixel = ivec2(3 - pixel.y, pixel.x);
	} else if (rotation == 2) {
		pixel = ivec2(3 - pixel.x, 3 - pixel.y);
	} else if (rotation == 3) {
		pixel = ivec2(pixel.y, 3 - pixel.x);
	}
	int bayer[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(bayer[pixel.y * 4 + pixel.x]) + 0.5) / 16.0;
}

void vertex() {
	// LBA_DEPTH_FIX_V2: always use explicit true mesh clip depth.
	// No actor origin compression and no actor_depth_span adjustment.
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	texture_region = CUSTOM1;
	// Generated SphereMesh has no CUSTOM2 vertex attributes. Use its local
	// surface position so the palette dithering follows the sphere itself.
	dither_anchor = lba_sphere_primitive ? VERTEX : CUSTOM2.xyz;
	platform_height = clamp((VERTEX.y + 0.06) / 0.12, 0.0, 1.0);
	float base_index = palette_index_override >= 0
		? float(palette_index_override)
		: floor(UV2.x + 0.5);
	source_base_index = base_index;
	if (use_mesh_lighting) {
		vec3 normal_world = normalize(MODEL_NORMAL_MATRIX * NORMAL);
		pixel_source_normal = normal_world;
		pixel_light_scale = mesh_light_span / max(length(source_light_vector), 0.001);
		source_palette_index = keep_in_palette_ramp(base_index, base_index + max(dot(normal_world, normalize(source_light_vector)), 0.0) * mesh_light_span);
		source_render_type = 9.0;
	} else {
		float normal_length = length(CUSTOM0.xyz);
		pixel_source_normal = normal_length > 0.0 ? CUSTOM0.xyz / normal_length : vec3(0.0);
		pixel_light_scale = normal_length / max(CUSTOM0.w, 1.0);
		float vertex_shade = palette_index_override >= 0
			? 0.0
			: max(dot(CUSTOM0.xyz, source_light_vector), 0.0) / max(CUSTOM0.w, 1.0);
		// Soft dither interpolates the original palette light value before
		// resolving its bands. Its mean shade matches the source palette mode.
		float shade = dither_mode == 4 && palette_index_override < 0 ? max(vertex_shade - 0.75, 0.0) : floor(vertex_shade);
		source_palette_index = keep_in_palette_ramp(base_index, base_index + shade);
		source_render_type = palette_index_override >= 0 ? -1.0 : UV2.y;
	}
	// LBA_LINE_AUTHORED_PALETTE_V50H: original LBA lines use fixed ink.
	if (lba_line_primitive) {
		source_palette_index = base_index;
		source_render_type = -1.0;
	}
	// Real-time LBA1 Gouraud pass. Lighting uses skinned mesh normals where
	// Godot exposes them, interpolates a fractional PALETTE INDEX, and never
	// blends or adds white RGB light to the palette colours.
	bool lba_dynamic = use_scene_lights && !has_texture_atlas && !platform_style
		&& !lba_line_primitive
		&& (source_render_type >= 7.0 || palette_index_override >= 0);
	if (lba_dynamic) {
		vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 n = normalize(MODEL_NORMAL_MATRIX * NORMAL);
		vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_position);
		float accumulated_steps = scene_ambient_steps;
		for (int i = 0; i < 8; i++) {
			if (i >= lba_light_count) { break; }
			float type_id = lba_light_position_type[i].w;
			vec3 light_direction = vec3(0.0, 1.0, 0.0);
			float attenuation = 1.0;
			if (type_id < 0.5) {
				light_direction = normalize(lba_light_direction_range[i].xyz);
			} else {
				vec3 to_light = lba_light_position_type[i].xyz - world_position;
				float distance_to_light = length(to_light);
				light_direction = to_light / max(distance_to_light, 0.0001);
				float range_value = max(lba_light_direction_range[i].w, 0.001);
				float falloff = clamp(1.0 - distance_to_light / range_value, 0.0, 1.0);
				attenuation = pow(falloff, max(lba_light_spot[i].z, 0.01));
				if (type_id > 1.5) {
					float cone = dot(-light_direction, normalize(lba_light_direction_range[i].xyz));
					float edge = clamp((cone - lba_light_spot[i].x)
						/ max(1.0 - lba_light_spot[i].x, 0.001), 0.0, 1.0);
					attenuation *= pow(edge, max(lba_light_spot[i].y, 0.01));
				}
			}
			float ndotl = max(dot(n, light_direction), 0.0);
			float luminance = dot(lba_light_color_energy[i].rgb, vec3(0.2126, 0.7152, 0.0722));
			float strength = max(luminance * lba_light_color_energy[i].a, 0.0) * attenuation;
			accumulated_steps += ndotl * strength * scene_light_span;
			if (scene_specular_steps > 0.0 && ndotl > 0.0) {
				vec3 half_direction = normalize(light_direction + view_direction);
				float highlight = pow(max(dot(n, half_direction), 0.0), scene_specular_power);
				accumulated_steps += highlight * strength * scene_specular_steps;
			}
		}
		// Keep every BODY polygon's shading unchanged. For spheres, preserve
		// the original model's palette *index*, including its shade offset
		// within the 16-colour ramp. v42b reset that offset to zero, which
		// changed the intended colour of hair and other authored spheres.
		// Only the delta from reference illumination changes their shade.
		if (!lba_sphere_primitive) {
			accumulated_steps *= lba_polygon_light_boost;
		}
		float ramp_start = floor(base_index / 16.0) * 16.0;
		float lit_base = lba_sphere_primitive
			? base_index - sphere_reference_steps : base_index;
		source_palette_index = clamp(lit_base + accumulated_steps,
			ramp_start, ramp_start + 15.0);
	}
}

void fragment() {
	float palette_index = floor(source_palette_index);
	// LBA1 only: the obsolete LBA2 atlas/shade-table branch was removed.
	if (lba1_palette_effects && source_render_type == 1.0) {
		// SVGAPolyTele varies the four palette entries starting at its base.
		float shade = floor(dither_hash(floor(FRAGCOORD.xy)) * 4.0);
		float index = mod(source_base_index + shade, 256.0);
		ALBEDO = texture(palette_texture, vec2((index + 0.5) / 256.0, 0.5)).rgb;
		ROUGHNESS = 1.0;
	} else if (lba1_palette_effects && source_render_type == 4.0) {
		// SVGAPolyMarbre interpolates palette indices across each screen row.
		float delta = mod(texture_region.x - source_base_index + 128.0, 256.0) - 128.0;
		float index = mod(floor(source_base_index + delta * clamp(UV.x, 0.0, 1.0) + 0.5), 256.0);
		ALBEDO = texture(palette_texture, vec2((index + 0.5) / 256.0, 0.5)).rgb;
		ROUGHNESS = 1.0;
	} else if (lba1_palette_effects && (source_render_type == 2.0 || source_render_type == 3.0)) {
		// Copper advances each source scanline; Bopper holds each palette
		// colour for two lines. Both reverse at the 16-colour ramp edges.
		float source_line = floor(FRAGCOORD.y / max(VIEWPORT_SIZE.y / 480.0, 1.0));
		float line_step = source_render_type == 3.0 ? floor(source_line * 0.5) : source_line;
		float ramp_step = 15.0 - abs(mod(line_step + mod(source_base_index, 16.0), 30.0) - 15.0);
		float index = floor(source_base_index / 16.0) * 16.0 + ramp_step;
		ALBEDO = texture(palette_texture, vec2((index + 0.5) / 256.0, 0.5)).rgb;
		ROUGHNESS = 1.0;
	} else if (platform_style) {
		float lit = max(dot(normalize(pixel_source_normal), normalize(source_light_vector)), 0.0);
		float level = clamp(0.18 + platform_height * 0.56 + lit * 0.16, 0.0, 1.0);
		if (pixel_source_normal.y > 0.7) {
			level = 0.96;
		}
		if (dither_mode != 3 && dither_mode != 4) {
			float steps = level * 8.0;
			float threshold = 0.5;
			level = (floor(steps) + (fract(steps) > threshold ? 1.0 : 0.0)) / 8.0;
		}
		ALBEDO = mix(vec3(0.42, 0.15, 0.015), vec3(0.98, 0.68, 0.075), level);
		ROUGHNESS = 1.0;
	} else if ((dither_mode == 3 || dither_mode == 4) && source_render_type >= 7.0) {
		float pixel_shade = max(dot(normalize(pixel_source_normal), source_light_vector), 0.0) * pixel_light_scale;
		float smooth_index = dither_mode == 3 ? keep_in_palette_ramp(source_base_index, source_base_index + pixel_shade) : source_palette_index;
		float lower_index = floor(smooth_index);
		float upper_index = mod(lower_index + 1.0, 256.0);
		vec3 lower_color = texture(palette_texture, vec2((lower_index + 0.5) / 256.0, 0.5)).rgb;
		vec3 upper_color = texture(palette_texture, vec2((upper_index + 0.5) / 256.0, 0.5)).rgb;
		float fraction = fract(smooth_index);
		ALBEDO = mix(lower_color, upper_color, fraction);
		if (dither_mode == 4) {
			vec2 coord = anchored_dither_coord();
			ALBEDO = preview_dither_blend(lower_color, upper_color, smooth_index, coord);
		}
		ROUGHNESS = 1.0;
	} else {
		bool dither_face = dither_mode == 1 && source_render_type >= 10.0;
		if (dither_face) {
			// LBA1 type 10 uses the dedicated SVGAPolyDith scanline path.
			// Diffuse the 8.8 palette-index fraction along each screen row. The
			// prefix sum is evaluated analytically in short blocks, so each fragment
			// runs in constant time even at 4K. Original polygon-edge scan conversion
			// and low-byte rotation still need a matched-game reference.
			float cell = 1.0;
			float cell_x = floor(FRAGCOORD.x / cell);
			float local_x = mod(cell_x, 64.0);
			float row = floor(FRAGCOORD.y / cell);
			float block = floor(cell_x / 64.0);
			float phase = fract(row * 0.61803398875 + block * 0.41421356237);
			float shade = floor(source_palette_index * 256.0) / 256.0;
			float gradient = dFdx(source_palette_index) * cell;
			float first = shade - gradient * local_x;
			float prefix = (local_x + 1.0) * first + gradient * local_x * (local_x + 1.0) * 0.5;
			float previous = local_x * first + gradient * (local_x - 1.0) * local_x * 0.5;
			palette_index = floor(prefix + phase) - floor(previous + phase);
		}
		palette_index = mod(palette_index, 256.0);
		ALBEDO = texture(palette_texture, vec2((palette_index + 0.5) / 256.0, 0.5)).rgb;
		ROUGHNESS = 1.0;
	}
	// The final pixel is ALWAYS one of the source palette entries. The
	// interpolated per-VERTEX light value only chooses the neighbouring indices.
	// Keep the original model-anchored dither so the transition has LBA texture.
	bool lba_dynamic = use_scene_lights && !has_texture_atlas && !platform_style
		&& !lba_line_primitive
		&& (source_render_type >= 7.0 || palette_index_override >= 0);
	if (lba_dynamic) {
		float index_low = floor(source_palette_index);
		float ramp_end = floor(source_base_index / 16.0) * 16.0 + 15.0;
		float index_high = min(index_low + 1.0, ramp_end);
		// VIEWER_DITHER_RESTORE_V50F: restore the established viewer soft dither.
		// Gouraud lighting still comes from all supplied scene lights in vertex().
		// At subpixel scale, the old viewer fades hard dithering towards a smooth
		// palette interpolation instead of generating crawling speckles.
		float coverage = fract(source_palette_index);
		vec2 stable_coord = lba_sphere_uv_dither
			? UV * vec2(sphere_dither_density * 2.0, sphere_dither_density)
			: anchored_dither_coord();
		vec3 color_low = texture(palette_texture,
			vec2((index_low + 0.5) / 256.0, 0.5)).rgb;
		vec3 color_high = texture(palette_texture,
			vec2((index_high + 0.5) / 256.0, 0.5)).rgb;
		vec3 palette_color;
		float index_final = coverage > anchored_dither_threshold(stable_coord) ? index_high : index_low;
		if (dither_mode == 4) {
			// Same footprint and colour-change handling as the original viewer.
			palette_color = preview_dither_blend(color_low, color_high,
				source_palette_index, stable_coord);
		} else if (dither_mode == 3) {
			palette_color = mix(color_low, color_high, coverage);
		} else {
			float threshold = anchored_dither_threshold(stable_coord);
			if (lba_sphere_uv_dither) {
				float footprint = max(length(dFdx(stable_coord)), length(dFdy(stable_coord)));
				float resolved = 1.0 - smoothstep(0.65, 1.40, footprint);
				coverage = mix(step(0.5, coverage), coverage, resolved);
			}
			palette_color = coverage > threshold ? color_high : color_low;
		}
		if (lba_sphere_uv_dither && sphere_palette_highlight_guard) {
			// Authored colour is the reference. Never let a lighting-driven
			// shade selection turn a dark sphere into a saturated bright patch.
			// This also catches outlier colours INSIDE the same 16-entry ramp;
			// clamping to the ramp edge alone cannot do that.
			vec3 authored_color = texture(palette_texture,
				vec2((source_base_index + 0.5) / 256.0, 0.5)).rgb;
			vec3 luma_weights = vec3(0.2126, 0.7152, 0.0722);
			float authored_luma = dot(authored_color, luma_weights);
			float max_luma = max(authored_luma * sphere_palette_max_luma_ratio,
				authored_luma + sphere_palette_max_luma_added);
			if (dot(palette_color, luma_weights) > max_luma) {
				// First try the immediately darker palette entry. Falling all
				// the way back to the source shade is a last resort.
				float fallback_index = max(floor(source_base_index), index_final - 1.0);
				vec3 fallback_color = texture(palette_texture,
					vec2((fallback_index + 0.5) / 256.0, 0.5)).rgb;
				palette_color = dot(fallback_color, luma_weights) <= max_luma
					? fallback_color : authored_color;
			}
		}
		if (lba_sphere_uv_dither && sphere_palette_shadow_guard) {
			vec3 authored_color = texture(palette_texture,
				vec2((source_base_index + 0.5) / 256.0, 0.5)).rgb;
			vec3 luma_weights = vec3(0.2126, 0.7152, 0.0722);
			float authored_luma = dot(authored_color, luma_weights);
			float darkest_allowed = max(0.06, authored_luma * sphere_palette_min_luma_ratio);
			if (authored_luma >= sphere_palette_bright_base &&
					dot(palette_color, luma_weights) < darkest_allowed) {
				// Search towards brighter entries within the SAME 16-colour bank.
				float ramp_end = floor(source_base_index / 16.0) * 16.0 + 15.0;
				vec3 replacement = authored_color;
				for (int step_index = 0; step_index < 16; step_index++) {
					float next_index = min(index_final + float(step_index), ramp_end);
					vec3 next_color = texture(palette_texture,
						vec2((next_index + 0.5) / 256.0, 0.5)).rgb;
					if (dot(next_color, luma_weights) >= darkest_allowed) {
						replacement = next_color;
						break;
					}
				}
				palette_color = replacement;
			}
		}
		ALBEDO = palette_color;
		ROUGHNESS = 1.0;
	}
}
