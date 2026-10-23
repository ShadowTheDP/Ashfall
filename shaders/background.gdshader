shader_type canvas_item;
render_mode unshaded;

// Dithered pixel-art backdrop: a stepped vertical gradient plus a slow
// logarithmic spiral field, both quantised with a 4x4 Bayer matrix so the
// banding reads as intentional pixel dithering.

uniform vec4 color_top : source_color = vec4(0.055, 0.070, 0.098, 1.0);
uniform vec4 color_mid : source_color = vec4(0.098, 0.082, 0.118, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.047, 0.055, 0.075, 1.0);
uniform vec4 ember : source_color = vec4(0.910, 0.640, 0.240, 1.0);
uniform float steps = 9.0; // reserved for future banding control

float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(color_top.rgb, color_mid.rgb, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, color_bottom.rgb, smoothstep(0.55, 1.0, uv.y));

	// Warm glow behind the arena floor.
	float glow = 1.0 - smoothstep(0.0, 0.55, distance(uv, vec2(0.5, 0.82)));
	col += ember.rgb * glow * 0.10;

	// Logarithmic spiral field, only in the upper half.
	vec2 p = uv - vec2(0.5, 0.42);
	p.x *= 1.7778;
	float r = length(p);
	float theta = atan(p.y, p.x);
	float spiral = sin(theta * 5.0 + log(r + 0.04) * 9.0 - TIME * 0.13);
	float rings = sin(r * 52.0 - TIME * 0.20);
	float fade = smoothstep(0.85, 0.15, r);
	col += vec3(0.045, 0.075, 0.105) * smoothstep(0.55, 1.0, spiral) * fade * 0.10;
	col += vec3(0.040, 0.060, 0.090) * smoothstep(0.90, 1.0, rings) * fade * 0.07;

	// A gentle dither only in the darkest band, so banding reads as texture
	// without turning the whole screen into a checkerboard.
	float dither = (bayer4(FRAGCOORD.xy) - 0.5) * 0.006;
	col += vec3(dither);

	COLOR = vec4(col, 1.0);
}
