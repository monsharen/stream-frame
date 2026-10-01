// The night sky's colour in a direction: shared by the sky itself and the
// floor, which reflects it (shaders/night_sky.gdshader, night_floor.gdshader).

// A low moon behind you, a little to the left (you face -z): out of the
// way of the screen, and laying its path across the water when you turn.
const vec3 MOON_DIR = vec3(-0.37, 0.2, 0.907);
const vec3 MOON_COLOUR = vec3(1.0, 0.96, 0.88);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Stars: the sky is wrapped in a cube, and each face is a grid where a
// cell may hold one star (`density`: the share that do) at a random point.
// A grid cell is about 1/`scale` radians across. Stars are under half a
// cell wide, so only the 2×2 cells around a point can reach it: 4 checks
// per pixel (a grid in 3D would need 8). Brighter stars are a little
// bigger; each has a hint of colour and twinkles slowly.
vec3 star_layer(vec3 dir, float scale, float density, float size, float time) {
	vec3 a = abs(dir);
	vec2 uv;
	float face;
	if (a.x >= a.y && a.x >= a.z) {
		uv = dir.yz / a.x;
		face = dir.x > 0.0 ? 0.0 : 1.0;
	} else if (a.y >= a.z) {
		uv = dir.xz / a.y;
		face = dir.y > 0.0 ? 2.0 : 3.0;
	} else {
		uv = dir.xy / a.z;
		face = dir.z > 0.0 ? 4.0 : 5.0;
	}
	vec2 p = uv * scale;
	vec2 base = floor(p - 0.5);
	vec3 light = vec3(0.0);
	for (int x = 0; x <= 1; x++) {
		for (int y = 0; y <= 1; y++) {
			vec3 c = vec3(base + vec2(float(x), float(y)), face * 1000.0);
			float h = hash13(c);
			if (h > density) {
				continue;
			}
			vec3 r = hash33(c);
			float magnitude = pow(r.z, 3.0) * 0.85 + 0.15;
			vec2 star = c.xy + 0.25 + 0.5 * r.xy;  // kept off the cell edges
			float glow = smoothstep(size * (0.6 + 0.8 * magnitude), 0.0, length(p - star));
			if (glow <= 0.0) {
				continue;
			}
			float twinkle = 0.75 + 0.25 * sin(time * (0.6 + 2.0 * h / density) + h * 400.0);
			// From faintly blue to faintly warm.
			vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.88, 0.75), fract(h * 97.0));
			light += tint * glow * glow * magnitude * twinkle;
		}
	}
	return light;
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise in 2D: half the cost of noise3, for shapes that only need
// two dimensions.
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

// The aurora: curtains of light along the horizon all round, made of fine
// vertical rays, brightest at their lower edge and fading upwards, drifting
// slowly; blue shading to violet around the sky (like the Steam Frame's
// own home, but softer).
vec3 aurora(vec3 dir, float time) {
	float h = dir.y;
	if (h < -0.02 || h > 0.6) {
		return vec3(0.0);
	}
	float az = atan(dir.x, dir.z);  // -PI..PI around you
	vec2 ring = vec2(cos(az), sin(az));  // seamless all the way round
	// Where the curtains are (large, slow patches) and their folds, which
	// move the lower edge up and down along the horizon.
	float patches = noise2(ring * 1.6 + vec2(time * 0.015, 0.0));
	if (patches < 0.25) {
		return vec3(0.0);  // no curtain here: skip the rest
	}
	float fold = noise2(ring * 4.0 + vec2(7.0, time * 0.03));
	float base = 0.015 + 0.06 * fold;
	// Fine vertical rays, shimmering slowly.
	float rays = noise2(ring * 38.0 + vec2(0.0, time * 0.08)) * 0.65 + noise2(ring * 90.0 + vec2(time * 0.12, 3.0)) * 0.35;
	rays = pow(rays, 2.2);
	float above = h - base;
	float height = smoothstep(-0.015, 0.02, above) * exp(-max(above, 0.0) * (5.0 - 2.5 * patches));
	// Fades out well before the cut-off above, so it never ends in an edge.
	float strength = height * (0.35 + 1.1 * rays) * smoothstep(0.25, 0.75, patches) * smoothstep(0.6, 0.3, h);
	vec3 blue = vec3(0.12, 0.38, 1.0);
	vec3 violet = vec3(0.55, 0.28, 1.0);
	vec3 colour = mix(blue, violet, 0.5 + 0.5 * sin(az * 1.0 + 0.6));
	// A touch paler near the bright lower edge.
	colour = mix(colour, vec3(0.6, 0.8, 1.0), 0.25 * exp(-max(above, 0.0) * 30.0));
	return colour * strength * 0.45;
}


// `richness` (0..1) brings in the subtle parts (aurora, Milky Way, the
// faint stars), skipped entirely at 0: the sky dims for films, when they'd
// barely show, and so costs less while you watch. `reflected`: as seen in
// the rippled water, where faint stars and fine detail are lost anyway.
vec3 night_sky(vec3 dir, float time, vec3 low, vec3 high, float richness, bool reflected) {
	float up = clamp(dir.y, 0.0, 1.0);
	vec3 colour = mix(low, high, pow(up, 0.45));
	float clear = smoothstep(0.0, 0.18, dir.y);  // stars fade into the haze

	// The stars, from a few bright ones to many faint ones, in one layer.
	colour += star_layer(dir, 170.0, 0.09, 0.17, time) * 1.5 * clear;

	if (richness > 0.0) {
		// The Milky Way: a soft, patchy band across the sky, dense with stars.
		vec3 band_normal = normalize(vec3(0.35, 0.55, 0.75));
		float band = exp(-pow(dot(dir, band_normal), 2.0) * 18.0);
		if (band > 0.02) {
			float patches = reflected ? 0.5 : noise3(dir * 6.0);
			colour += vec3(0.05, 0.05, 0.075) * band * patches * smoothstep(-0.02, 0.25, dir.y) * richness;
			if (!reflected) {
				colour += star_layer(dir, 260.0, 0.25, 0.12, time) * band * 0.5 * clear * richness;
			}
		}
		colour += aurora(dir, time) * richness;
	}

	// The moon: a soft disc and its halo.
	float to_moon = dot(dir, normalize(MOON_DIR));
	colour += MOON_COLOUR * (smoothstep(0.99975, 0.99985, to_moon) * 1.4
		+ pow(max(to_moon, 0.0), 900.0) * 0.25 + pow(max(to_moon, 0.0), 40.0) * 0.035);

	return colour;
}
