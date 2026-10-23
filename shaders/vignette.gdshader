shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 uv = UV;
	float d = distance(uv, vec2(0.5, 0.5));
	float edge = smoothstep(0.34, 0.86, d);
	vec3 tint = vec3(0.010, 0.014, 0.026);
	COLOR = vec4(tint, edge * 0.88);
}
