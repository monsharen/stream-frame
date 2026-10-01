// Bias lighting ("Ambilight"): a soft glow around the screen in the colours
// at the matching edge of the picture, fading out with distance. Drawn on
// a band behind the screen, additively.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

// The picture averaged into a small grid of colour cells.
uniform sampler2D ambient : source_color, hint_default_black, filter_linear, repeat_disable;
// What lights it outside the film (menus, a poster while loading), mixed in
// by menu_mix.
uniform sampler2D menu_light : source_color, hint_default_black, filter_linear, repeat_disable;
uniform float menu_mix = 0.0;
// Screen size as a fraction of this band (centred).
uniform vec2 inner = vec2(0.5, 0.45);
uniform float screen_aspect = 1.7778;
uniform float strength = 0.35;
// Fades the whole effect in and out.
uniform float fade = 0.0;
// Spread of the glow, in screen heights.
uniform float spread = 0.22;

void fragment() {
	vec2 p = (UV - 0.5) / inner + 0.5;  // 0..1 across the screen itself
	vec2 at = clamp(p, vec2(0.02), vec2(0.98));
	vec3 colour = mix(texture(ambient, at).rgb, texture(menu_light, at).rgb, menu_mix);
	// Distance outside the screen's edge, in screen heights.
	vec2 outside = max(abs(p - 0.5) - 0.5, 0.0) * vec2(screen_aspect, 1.0);
	float d = length(outside);
	float glow = exp(-(d * d) / (2.0 * spread * spread));
	// Never a hard edge where the band ends.
	glow *= smoothstep(0.0, 0.06, min(UV.x, 1.0 - UV.x)) * smoothstep(0.0, 0.06, min(UV.y, 1.0 - UV.y));
	ALBEDO = colour * glow * strength * fade;
}
