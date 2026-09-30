shader_type canvas_item;
// Full-screen color finishing pass. Keep the existing light split and gentle
// edge falloff. Screen-space grain made both small sprites and UI look noisy;
// material detail belongs in the artwork, not a noise overlay on the whole game.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// Light split: warm the highlights, cool the shadows. This is most of what sells
// "lit" rather than "coloured in" on flat art.
uniform vec3 warm : source_color = vec3(1.04, 1.005, 0.95);
uniform vec3 cool : source_color = vec3(0.95, 0.975, 1.06);
uniform float split_strength : hint_range(0.0, 1.0) = 0.3;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.08;
uniform float contrast : hint_range(0.5, 1.5) = 1.0;
uniform float saturation : hint_range(0.5, 1.5) = 1.0;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));

	// Tint toward warm in the highlights and cool in the shadows, weighted so
	// mid-tones move least — that keeps skin and parchment where the artist put
	// them while still giving the frame a light direction.
	float t = smoothstep(0.25, 0.85, luma);
	vec3 tint = mix(cool, warm, t);
	col *= mix(vec3(1.0), tint, split_strength);

	col = (col - 0.5) * contrast + 0.5;

	float l2 = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(l2), col, saturation);

	vec2 d = SCREEN_UV - vec2(0.5);
	float vig = 1.0 - dot(d, d) * vignette_strength * 2.2;
	col *= clamp(vig, 0.0, 1.0);

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
