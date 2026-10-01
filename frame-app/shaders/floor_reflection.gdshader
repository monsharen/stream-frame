// A soft reflection of the picture on the floor in front of the screen,
// like a cinema's polished floor: the picture's colours, mirrored, fading
// with distance from the screen. Drawn additively.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform sampler2D ambient : source_color, hint_default_black, filter_linear, repeat_disable;
uniform sampler2D menu_light : source_color, hint_default_black, filter_linear, repeat_disable;
uniform float menu_mix = 0.0;
uniform float strength = 0.22;
uniform float fade = 0.0;

void fragment() {
	// The plane's UV.y runs from the viewer (0) to the screen's foot (1).
	float from_screen = 1.0 - UV.y;
	// Mirrored: the bottom of the picture is reflected nearest the screen.
	vec2 at = vec2(UV.x, 1.0 - from_screen * 0.6);
	vec3 colour = mix(texture(ambient, at).rgb, texture(menu_light, at).rgb, menu_mix);
	float falloff = pow(1.0 - from_screen, 2.5) * smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	ALBEDO = colour * falloff * strength * fade;
}
