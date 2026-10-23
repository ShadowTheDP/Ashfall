shader_type canvas_item;
render_mode unshaded;

// Monochrome vignette. Four hard steps, dithered at the boundary so it reads
// as deliberate shading rather than a smooth gradient.

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
	float edge = smoothstep(0.30, 0.90, d);
	edge = floor(edge * 5.0 + bayer4(FRAGCOORD.xy)) / 5.0;
	COLOR = vec4(vec3(0.012), edge * 0.85);
}
