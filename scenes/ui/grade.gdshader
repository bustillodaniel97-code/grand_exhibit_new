shader_type canvas_item;
// Full-screen finishing pass.
//
// WHY. Every surface in this game is a flat untextured fill with a hard colour
// boundary, which is the exact recipe for the "plastic toy" read — no material,
// no light direction, no variation within a shape. The fix is not more geometry;
// it is the finishing layer that photographic and stylised-3D games apply on top:
// a light split, a little grain so flats are not mathematically flat, falloff at
// the frame edge, and a curve that stops the brights from sitting at pure value.
//
// WHAT IT DELIBERATELY DOES NOT DO. No blur-based bloom. A real bloom needs
// several taps of the screen texture, and on a tile-based mobile GPU under the
// GL Compatibility renderer that bandwidth is the whole frame budget. Everything
// here is per-pixel ALU on a single sample, which costs effectively nothing.
//
// Keep it SUBTLE. This runs over the UI as well as the world; anything strong
// enough to be obvious on the floor is far too strong on text.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// Light split: warm the highlights, cool the shadows. This is most of what sells
// "lit" rather than "coloured in" on flat art.
uniform vec3 warm : source_color = vec3(1.04, 1.005, 0.95);
uniform vec3 cool : source_color = vec3(0.95, 0.975, 1.06);
uniform float split_strength : hint_range(0.0, 1.0) = 0.55;

// Grain. Breaks the dead-flat interior of every filled polygon. Static, not
// animated: animated grain on a phone reads as video noise and costs battery for
// nothing, since the eye only needs the surface to stop looking synthetic.
uniform float grain_amount : hint_range(0.0, 0.12) = 0.028;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.28;
uniform float contrast : hint_range(0.5, 1.5) = 1.045;
uniform float saturation : hint_range(0.5, 1.5) = 1.06;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

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

	// Grain scaled by how dark the pixel is: shadows can carry noise, highlights
	// cannot without looking dirty.
	float g = hash12(SCREEN_UV * vec2(1920.0, 1080.0)) - 0.5;
	col += g * grain_amount * (1.0 - t * 0.75);

	vec2 d = SCREEN_UV - vec2(0.5);
	float vig = 1.0 - dot(d, d) * vignette_strength * 2.2;
	col *= clamp(vig, 0.0, 1.0);

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
