shader_type canvas_item;
// Blur lives on the fill only. The nine-slice frame is another CanvasItem.
uniform sampler2D scene_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D fill_texture : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(0.06, 0.13, 0.18, 0.87);
uniform float blur_lod : hint_range(0.0, 6.0) = 2.25;
void fragment() {
    vec4 shape = texture(fill_texture, UV);
    vec3 behind = textureLod(scene_texture, SCREEN_UV, blur_lod).rgb;
    vec3 mixed = mix(behind, tint.rgb, tint.a);
    COLOR = vec4(mixed, shape.a);
}
