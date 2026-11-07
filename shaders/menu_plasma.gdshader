shader_type canvas_item;
render_mode unshaded;

uniform float speed : hint_range(0.02, 1.0) = 0.16;
uniform float selected : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * vec2(5.0, 2.2);
	float t = TIME * speed;
	float waves = sin(p.x * 2.5 + t * 2.0 + sin(p.y * 2.0 - t))
		+ sin(p.y * 4.0 - p.x * 1.3 + t * 1.4)
		+ sin(length(p - vec2(2.0, 1.0)) * 3.2 - t * 1.8);
	float glow = smoothstep(-1.7, 2.6, waves);
	vec3 dark_blue = vec3(0.025, 0.075, 0.13);
	vec3 blue = vec3(0.035, 0.22, 0.35);
	vec3 cyan = vec3(0.16, 0.53, 0.62);
	vec3 color = mix(dark_blue, blue, glow);
	color = mix(color, cyan, pow(glow, 3.0) * (0.35 + selected * 0.65));
	color *= 0.66 + selected * 0.48;
	COLOR = vec4(color, 1.0);
}
