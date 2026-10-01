// A wall tile's artwork: the image (cropped to fill), tinted, with rounded
// corners (anti-aliased; outside them nothing is drawn, not even depth).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled;

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_art = false;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// The tile's size and corner radius, in metres.
uniform vec2 size = vec2(0.56, 0.315);
uniform float radius = 0.018;

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 q = abs(p) - (size * 0.5 - radius);
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
	float edge = fwidth(d);
	float mask = 1.0 - smoothstep(-edge, edge, d);
	if (mask <= 0.0) {
		discard;
	}
	vec4 colour = has_art ? texture(art, UV * uv_scale + uv_offset) * tint : tint;
	ALBEDO = colour.rgb;
	ALPHA = colour.a * mask;
}
