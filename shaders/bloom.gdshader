shader_type canvas_item;
render_mode unshaded, blend_add;

// Cheap screen-space bloom for the GL Compatibility renderer.
// Samples the already-rendered frame, keeps bright pixels and adds a blurred
// copy back. HUD and vignette are on higher CanvasLayers, so they stay crisp.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float threshold : hint_range(0.0, 1.0) = 0.46;
uniform float intensity : hint_range(0.0, 2.0) = 0.72;

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_texture, uv).rgb;
	return max(c - vec3(threshold), vec3(0.0));
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * 2.0;
	vec3 sum = vec3(0.0);
	sum += bright(SCREEN_UV + vec2(-3.0,  0.0) * px) * 0.10;
	sum += bright(SCREEN_UV + vec2( 3.0,  0.0) * px) * 0.10;
	sum += bright(SCREEN_UV + vec2( 0.0, -3.0) * px) * 0.10;
	sum += bright(SCREEN_UV + vec2( 0.0,  3.0) * px) * 0.10;
	sum += bright(SCREEN_UV + vec2(-2.0, -2.0) * px) * 0.08;
	sum += bright(SCREEN_UV + vec2( 2.0, -2.0) * px) * 0.08;
	sum += bright(SCREEN_UV + vec2(-2.0,  2.0) * px) * 0.08;
	sum += bright(SCREEN_UV + vec2( 2.0,  2.0) * px) * 0.08;
	sum += bright(SCREEN_UV + vec2(-6.0,  0.0) * px) * 0.05;
	sum += bright(SCREEN_UV + vec2( 6.0,  0.0) * px) * 0.05;
	sum += bright(SCREEN_UV + vec2( 0.0, -6.0) * px) * 0.05;
	sum += bright(SCREEN_UV + vec2( 0.0,  6.0) * px) * 0.05;
	COLOR = vec4(sum * intensity, 1.0);
}
