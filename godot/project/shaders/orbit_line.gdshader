shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4  line_color    : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform float glow_strength : hint_range(0.0, 4.0) = 1.5;

void fragment() {
	ALBEDO    = line_color.rgb * glow_strength;
	ALPHA     = line_color.a;
	EMISSION  = line_color.rgb * glow_strength;
}
