shader_type canvas_item;
// Miniature (tilt-shift) blur: sharp in a horizontal band around `focus`,
// blurring toward the top and bottom of the screen. This is the Link's
// Awakening diorama look. The Compatibility renderer has no depth of field,
// so it is done in screen space with a fixed 12-tap disc, cheap enough for phones.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float focus : hint_range(0.0, 1.0) = 0.5;
uniform float band : hint_range(0.0, 1.0) = 0.5;
uniform float falloff : hint_range(0.01, 1.0) = 0.3;
uniform float max_radius_px : hint_range(0.0, 16.0) = 4.5;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

const vec2 TAPS[12] = vec2[](
	vec2(1.0, 0.0), vec2(0.5, 0.866), vec2(-0.5, 0.866), vec2(-1.0, 0.0), vec2(-0.5, -0.866), vec2(0.5, -0.866),
	vec2(0.5, 0.0), vec2(0.25, 0.433), vec2(-0.25, 0.433), vec2(-0.5, 0.0), vec2(-0.25, -0.433), vec2(0.25, -0.433));

void fragment() {
	float d = abs(SCREEN_UV.y - focus);
	float k = smoothstep(band * 0.5, band * 0.5 + falloff, d);
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	if (k > 0.01) {
		vec2 r = SCREEN_PIXEL_SIZE * max_radius_px * k;
		vec3 acc = col;
		for (int i = 0; i < 12; i++) {
			acc += texture(screen_tex, SCREEN_UV + TAPS[i] * r).rgb;
		}
		col = acc / 13.0;
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(l), col, saturation), 1.0);
}
