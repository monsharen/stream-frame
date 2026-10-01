// The movie wall's light on the floor in front of it, like a polished
// floor catching the posters' colours: brightest at the wall's foot,
// fading towards the viewer. Drawn additively.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

// The wall's light by angle, left to right.
uniform sampler2D wall_light : source_color, hint_default_black, filter_linear, repeat_disable;
uniform float strength = 0.35;
uniform float fade = 1.0;

void fragment() {
	// UV.x runs along the wall; UV.y from the wall's foot (0) inwards (1).
	vec3 colour = texture(wall_light, vec2(UV.x, 0.5)).rgb;
	float falloff = pow(1.0 - UV.y, 2.2) * smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	ALBEDO = colour * falloff * strength * fade;
}
