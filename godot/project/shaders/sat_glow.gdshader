shader_type spatial;
render_mode cull_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.2, 1.0);
uniform float pulse_speed : hint_range(0.5, 8.0) = 3.0;

void fragment() {
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	ALBEDO   = glow_color.rgb;
	EMISSION = glow_color.rgb * (2.0 + pulse * 3.0);
	ROUGHNESS = 0.0;
	METALLIC  = 0.0;
}
