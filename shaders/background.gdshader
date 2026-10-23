shader_type canvas_item;
render_mode unshaded;

uniform vec4 color_top : source_color = vec4(0.030, 0.040, 0.070, 1.0);
uniform vec4 color_mid : source_color = vec4(0.085, 0.072, 0.115, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.045, 0.050, 0.078, 1.0);
uniform vec4 ember : source_color = vec4(0.910, 0.640, 0.240, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(color_top.rgb, color_mid.rgb, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, color_bottom.rgb, smoothstep(0.55, 1.0, uv.y));

	float glow = 1.0 - smoothstep(0.0, 0.58, distance(uv, vec2(0.5, 0.80)));
	col += ember.rgb * glow * 0.11;

	float band = sin(uv.y * 24.0 + TIME * 0.30) * 0.5 + 0.5;
	col += vec3(0.030, 0.036, 0.052) * band * smoothstep(0.45, 1.0, uv.y) * 0.35;

	float drift = sin(uv.x * 8.0 + TIME * 0.12) * 0.5 + 0.5;
	col += vec3(0.012, 0.016, 0.026) * drift * smoothstep(0.35, 0.9, uv.y);

	// Logarithmic spiral field: sin(theta * 5 + log(r) * 9 - t).
	vec2 p = uv - vec2(0.5, 0.45);
	p.x *= 1.777;
	float r = length(p);
	float theta = atan(p.y, p.x);
	float spiral = sin(theta * 5.0 + log(r + 0.02) * 9.0 - TIME * 0.16);
	float rings = sin(r * 44.0 - TIME * 0.22);
	float spokes = sin(theta * 12.0 + TIME * 0.05);
	float radial_fade = smoothstep(0.95, 0.18, r);
	col += vec3(0.050, 0.095, 0.140) * smoothstep(0.35, 1.0, spiral) * radial_fade * 0.055;
	col += vec3(0.040, 0.065, 0.100) * smoothstep(0.88, 1.0, rings) * radial_fade * 0.050;
	col += vec3(0.025, 0.040, 0.060) * smoothstep(0.90, 1.0, spokes) * radial_fade * 0.040;

	col += (hash(uv * 512.0 + vec2(TIME * 3.0)) - 0.5) * 0.012;
	COLOR = vec4(col, 1.0);
}
