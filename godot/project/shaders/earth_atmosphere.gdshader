shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform sampler2D night_texture  : source_color, hint_default_black;
uniform sampler2D cloud_texture  : source_color, hint_default_white;
uniform vec3  sun_direction      : source_color = vec3(1.0, 0.0, 0.0);
uniform float atmosphere_density : hint_range(0.0, 1.0) = 0.6;
uniform float cloud_opacity      : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec3 normal   = normalize(NORMAL);
	float n_dot_l = dot(normal, normalize(sun_direction));
	float day     = smoothstep(-0.1, 0.2, n_dot_l);

	vec4 day_col   = texture(albedo_texture, UV);
	vec4 night_col = texture(night_texture,  UV);
	vec4 clouds    = texture(cloud_texture,  UV);

	// Day/night blend
	vec3 surface = mix(night_col.rgb * 0.4, day_col.rgb, day);

	// Cloud layer
	surface = mix(surface, clouds.rgb, clouds.r * cloud_opacity * day);

	// Atmosphere rim glow — no branching, use mix() + step()
	float rim = 1.0 - max(0.0, dot(normal, VIEW));
	rim = pow(rim, 3.0) * atmosphere_density;
	vec3 atmo_color = vec3(0.3, 0.6, 1.0);
	surface = mix(surface, atmo_color, rim);

	ALBEDO    = surface;
	ROUGHNESS = 0.7;
	METALLIC  = 0.0;
}
