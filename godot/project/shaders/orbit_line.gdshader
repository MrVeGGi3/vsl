shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform float glow_strength : hint_range(0.0, 4.0) = 1.5;

void fragment() {
	ALBEDO   = COLOR.rgb * glow_strength;
	ALPHA    = COLOR.a;
	EMISSION = COLOR.rgb * glow_strength;
}
