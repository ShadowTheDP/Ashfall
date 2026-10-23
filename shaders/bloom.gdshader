shader_type canvas_item;
render_mode unshaded, blend_add;

// Tight screen-space glow. Only the brightest pixels bleed, and only 2-4 px,
// so shapes keep their edges while impacts still feel hot.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float threshold : hint_range(0.0, 1.0) = 0.72;
uniform float intensity : hint_range(0.0, 2.0) = 0.55;

vec3 bright(vec2 uv) {
	vec3 c = texture(screen_texture, uv).rgb;
	return max(c - vec3(threshold), vec3(0.0));
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * 2.0;
	vec3 sum = vec3(0.0);
	sum += bright(SCREEN_UV + vec2(-1.0,  0.0) * px) * 0.14;
	sum += bright(SCREEN_UV + vec2( 1.0,  0.0) * px) * 0.14;
	sum += bright(SCREEN_UV + vec2( 0.0, -1.0) * px) * 0.14;
	sum += bright(SCREEN_UV + vec2( 0.0,  1.0) * px) * 0.14;
	sum += bright(SCREEN_UV + vec2(-2.0, -2.0) * px) * 0.07;
	sum += bright(SCREEN_UV + vec2( 2.0, -2.0) * px) * 0.07;
	sum += bright(SCREEN_UV + vec2(-2.0,  2.0) * px) * 0.07;
	sum += bright(SCREEN_UV + vec2( 2.0,  2.0) * px) * 0.07;
	COLOR = vec4(sum * intensity, 1.0);
}
