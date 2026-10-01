// The curved screen: the 2D UI, with in-app video composited underneath
// it (the UI is transparent wherever it shows the film). For 3D films each
// eye gets its own half of a side-by-side or top-bottom frame.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform sampler2D ui_tex : source_color, filter_linear;
uniform sampler2D video_tex : source_color, filter_linear;
// Part of the UI texture shown on this mesh (xy offset, zw size), 0..1.
uniform vec4 ui_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform float opacity = 1.0;
// 0 = no video (UI only) .. 1 = video fully shown under the UI.
uniform float video_alpha = 0.0;
uniform vec2 video_size = vec2(16.0, 9.0);
// The picture within the video frame (black bars baked into the file
// excluded), 0..1: xy offset, zw size.
uniform vec4 content_rect = vec4(0.0, 0.0, 1.0, 1.0);
// 0 = 2D, 1 = side by side, 2 = top-bottom.
uniform int stereo_mode = 0;
uniform float screen_aspect = 1.7778;
// Floating: only the UI's own pixels show (the deck's controls float in the
// room, with no panel behind them).
uniform bool floating = false;

// The picture's colour at this point of the screen; a = 0 off the picture.
vec4 video_color(vec2 uv, int eye) {
	vec2 eye_size = video_size * content_rect.zw;
	vec2 scale = vec2(1.0);
	vec2 offset = vec2(0.0);
	if (stereo_mode == 1) {
		eye_size.x *= 0.5;
		scale = vec2(0.5, 1.0);
		offset = vec2(0.5 * float(eye), 0.0);
	} else if (stereo_mode == 2) {
		eye_size.y *= 0.5;
		scale = vec2(1.0, 0.5);
		offset = vec2(0.0, 0.5 * float(eye));
	}
	// Fit the picture inside the screen (letterbox/pillarbox).
	float picture_aspect = eye_size.x / max(eye_size.y, 1.0);
	vec2 fit = picture_aspect > screen_aspect
		? vec2(1.0, screen_aspect / picture_aspect)
		: vec2(picture_aspect / screen_aspect, 1.0);
	vec2 p = (uv - 0.5) / fit + 0.5;
	if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) {
		return vec4(0.0);
	}
	vec2 frame_uv = content_rect.xy + p * content_rect.zw;
	return vec4(texture(video_tex, offset + frame_uv * scale).rgb, 1.0);
}

void fragment() {
	vec4 ui = texture(ui_tex, ui_region.xy + UV * ui_region.zw);
	vec4 video = video_alpha > 0.0 ? video_color(UV, int(VIEW_INDEX)) : vec4(0.0);
	ALBEDO = mix(video.rgb * video_alpha, ui.rgb, ui.a);
	// Where there's no picture, only the UI is solid: as the film takes
	// over, the screen around it melts away instead of showing black bars.
	float coverage = floating ? ui.a : max(ui.a, max(video.a, 1.0 - video_alpha));
	if (floating) {
		ALBEDO = ui.a > 0.0 ? ui.rgb / ui.a : vec3(0.0);  // the viewport's colours are premultiplied
	}
	ALPHA = opacity * coverage;
}
