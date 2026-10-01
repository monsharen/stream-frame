// The ground: a still sheet of dark water reflecting the night sky, all
// round you, so you stand on a surface that runs off into the dark. Like
// real water it mirrors little looking straight down and more and more
// towards the horizon (Fresnel); slow, gentle ripples make the reflected
// stars waver. Far away it melts into the sky's horizon haze. `ripple` 0
// makes it a sheet of glass. `brightness` follows the sky's.
shader_type spatial;
// No highlights from the room light: its reflections are drawn separately
// (screen and wall reflections); it only tints the water.
render_mode cull_disabled, specular_disabled;

uniform vec3 albedo : source_color = vec3(0.02, 0.024, 0.032);
uniform vec3 horizon : source_color = vec3(0.045, 0.055, 0.085);
uniform vec3 zenith : source_color = vec3(0.004, 0.005, 0.012);
uniform float brightness = 1.0;
// How much of the sky it reflects, and how much looking straight down.
uniform float reflectivity = 0.9;
uniform float base_reflectance = 0.04;
// Ripples: their slope (0 = glass), and how far out they settle.
uniform float ripple = 1.0;
uniform float ripple_distance = 60.0;
// A faint glow on the water where you stand: colour and radius (metres).
uniform vec3 pool_colour : source_color = vec3(0.035, 0.04, 0.055);
uniform float pool_radius = 3.0;
// Distances (metres, from you) over which the water gives way to the haze.
uniform float fade_start = 6.0;
uniform float fade_end = 220.0;

#include "res://shaders/night_sky.gdshaderinc"

varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// The water's slope (d height / dx, dz) at p: a few slow waves from
// different directions, so the pattern never visibly repeats.
vec2 ripple_slope(vec2 p, float t) {
	// direction (x, z), wavelength (m), height (m)
	vec4 waves[5] = vec4[](
		vec4(0.80, 0.60, 3.1, 0.010),
		vec4(-0.45, 0.89, 1.7, 0.006),
		vec4(0.20, -0.98, 1.1, 0.004),
		vec4(-0.93, -0.37, 0.7, 0.0025),
		vec4(0.60, -0.80, 0.45, 0.0015)
	);
	float speeds[5] = float[](0.55, 0.8, 1.0, 1.3, 1.7);
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 5; i++) {
		vec2 dir = waves[i].xy;
		float k = 6.2831853 / waves[i].z;
		slope += dir * (waves[i].w * k * cos(dot(dir, p) * k + t * speeds[i]));
	}
	return slope;
}

void fragment() {
	float distance = length(world.xz - CAMERA_POSITION_WORLD.xz);
	vec2 slope = ripple_slope(world.xz, TIME) * ripple * (1.0 - smoothstep(ripple_distance * 0.3, ripple_distance, distance));
	vec3 normal = normalize(vec3(-slope.x, 1.0, -slope.y));

	// The sky mirrored in the water, stronger at grazing angles.
	vec3 view = normalize(world - CAMERA_POSITION_WORLD);
	vec3 mirrored = reflect(view, normal);
	mirrored.y = abs(mirrored.y);  // never below the horizon, even on a ripple
	float facing = clamp(dot(-view, normal), 0.0, 1.0);
	float fresnel = base_reflectance + (1.0 - base_reflectance) * pow(1.0 - facing, 5.0);
	vec3 reflection = night_sky(mirrored, TIME, horizon, zenith, smoothstep(0.15, 0.45, brightness), true) * fresnel * reflectivity;
	// The moon's path: the ripples catch it as glints, and a soft sheen
	// runs between them.
	float to_moon = max(dot(mirrored, normalize(MOON_DIR)), 0.0);
	reflection += MOON_COLOUR * (pow(to_moon, 1500.0) * 2.5 + pow(to_moon, 120.0) * 0.12) * mix(fresnel, 1.0, 0.3);

	float haze = sqrt(smoothstep(fade_start, fade_end, distance));
	float pool = exp(-(distance * distance) / (2.0 * pool_radius * pool_radius));

	ALBEDO = albedo * (1.0 - haze);
	ROUGHNESS = 0.15;
	EMISSION = (mix(reflection, horizon, haze) + pool_colour * pool) * brightness;
}
