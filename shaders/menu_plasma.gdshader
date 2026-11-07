shader_type canvas_item;
render_mode unshaded;

uniform float speed : hint_range(0.02, 1.0) = 0.16;
uniform float selected : hint_range(0.0, 1.0) = 0.0;
uniform vec2 plasma_dimensions = vec2(4.0, 0.5);
uniform sampler2D original_palette : filter_nearest;
uniform bool use_original_palette = false;

void fragment() {
	// Moving radial fields produce the broad, overlapping bands of the
	// old-school plasma reference. The game palette supplies the colours.
	// Keep plasma frequency tied to physical button size, not UV aspect ratio.
	vec2 p = (UV - 0.5) * plasma_dimensions;
	float t = TIME * speed;
	vec2 center_a = vec2(2.5 * cos(t * 0.7), 0.8 * sin(t * 0.5));
	vec2 center_b = vec2(2.8 * sin(t * 0.4), 0.7 * cos(t * 0.9));
	vec2 center_c = vec2(2.2 * cos(t * 0.3), 0.9 * cos(t * 0.6));
	float waves = cos(length(p - center_a) * 2.5)
		+ cos(length(p - center_b) * 3.1)
		+ sin(length(p - center_c) * 2.2) * sin(p.x * 1.1);
	float level = fract(0.5 + waves * 0.18 + selected * 0.035);
	vec3 color;
	if (use_original_palette) {
		float index = floor(level * 15.0 + 0.5);
		color = texture(original_palette, vec2((index + 0.5) / 16.0, 0.5)).rgb;
	} else {
		color = mix(vec3(0.027, 0.043, 0.09), vec3(0.75, 0.86, 0.94), level);
	}
	COLOR = vec4(color, 1.0);
}
