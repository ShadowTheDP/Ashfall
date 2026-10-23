shader_type canvas_item;
render_mode unshaded;

// Monochrome backdrop. Everything is a value, never a hue: a stepped vertical
// ramp, one soft light pool behind the arena floor, and a slowly turning
// logarithmic-spiral field for depth.

uniform vec4 shade_top : source_color = vec4(0.043, 0.047, 0.055, 1.0);
uniform vec4 shade_mid : source_color = vec4(0.070, 0.074, 0.082, 1.0);
uniform vec4 shade_bottom : source_color = vec4(0.031, 0.035, 0.039, 1.0);
uniform float spiral_strength = 0.10;

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(shade_top.rgb, shade_mid.rgb, smoothstep(0.0, 0.55, uv.y));
	col = mix(col, shade_bottom.rgb, smoothstep(0.55, 1.0, uv.y));

	// Light pool behind the floor line.
	float pool = 1.0 - smoothstep(0.0, 0.58, distance(uv, vec2(0.5, 0.84)));
	col += vec3(0.055) * pool;

	// Logarithmic spiral field: sin(theta * 5 + log(r) * 9 - t).
	vec2 p = uv - vec2(0.5, 0.42);
	p.x *= 1.6;
	float r = length(p);
	float theta = atan(p.y, p.x);
	float spiral = sin(theta * 5.0 + log(r + 0.04) * 9.0 - TIME * 0.11);
	float rings = sin(r * 46.0 - TIME * 0.17);
	float fade = smoothstep(0.80, 0.12, r);
	col += vec3(0.045) * smoothstep(0.55, 1.0, spiral) * fade * spiral_strength;
	col += vec3(0.032) * smoothstep(0.90, 1.0, rings) * fade * spiral_strength;

	// Very light dither so the ramp does not band on cheap displays.
	float dither = (fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.005;
	col += vec3(dither);

	COLOR = vec4(col, 1.0);
}
