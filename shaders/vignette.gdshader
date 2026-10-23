shader_type canvas_item;
render_mode unshaded;

// Dithered vignette: the falloff is quantised into four steps so the edges
// stay in the pixel language instead of turning into a smooth gradient.

float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	vec2 uv = UV;
	float d = distance(uv, vec2(0.5, 0.5));
	float edge = smoothstep(0.34, 0.88, d);
	edge = floor(edge * 5.0 + bayer4(FRAGCOORD.xy)) / 5.0;
	COLOR = vec4(vec3(0.015, 0.020, 0.032), edge * 0.82);
}
