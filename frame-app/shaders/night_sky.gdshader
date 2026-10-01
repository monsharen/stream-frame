// A clear night sky: two layers of stars (a few bright, many faint) with a
// hint of colour and a slow twinkle, a faint Milky Way band, and a soft
// glow along the horizon (matched by the floor's haze, so the ground melts
// into it). `brightness` dims it all, like a cinema's lights going down.
shader_type sky;

uniform float brightness = 1.0;
// The haze at the horizon; the floor fades to the same colour.
uniform vec3 horizon : source_color = vec3(0.045, 0.055, 0.085);
uniform vec3 zenith : source_color = vec3(0.004, 0.005, 0.012);

#include "res://shaders/night_sky.gdshaderinc"

void sky() {
	// The subtle parts fade out (and stop costing anything) as the sky dims.
	COLOR = night_sky(EYEDIR, TIME, horizon, zenith, smoothstep(0.15, 0.45, brightness), false) * brightness;
}
