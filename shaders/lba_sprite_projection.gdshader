shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
// View-space pushback in world units. Let Godot's projection matrix handle
// reversed-Z; this is stable under ortho and moderate perspective cameras.
uniform float proxy_view_pushback : hint_range(0.0, 0.25, 0.001) = 0.0;
// For doors/gates only: slide the sprite across a STATIONARY aperture mesh.
// The moving picture is clipped by the aperture's original geometry.
uniform vec2 sprite_uv_motion = vec2(0.0);

void vertex() {
    vec4 view_position = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    view_position.z -= proxy_view_pushback;
    POSITION = PROJECTION_MATRIX * view_position;
}

void fragment() {
    // Geometry may extend beyond the sprite's painted rectangle.
    // Never smear a border pixel across the missing region.
    vec2 sprite_uv = UV + sprite_uv_motion;
    if (sprite_uv.x < 0.0 || sprite_uv.x >= 1.0 || sprite_uv.y < 0.0 || sprite_uv.y >= 1.0) {
        discard;
    }
    vec4 pixel = texture(sprite_texture, sprite_uv);
    if (pixel.a < 0.5) {
        discard;
    }
    ALBEDO = pixel.rgb;
}
