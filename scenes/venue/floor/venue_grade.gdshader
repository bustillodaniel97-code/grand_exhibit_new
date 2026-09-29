shader_type canvas_item;
render_mode unshaded, blend_mix;

// A restrained painterly grade for the diorama. Structural shadows remain
// authored into the floor/props; this supplies one coherent warm key, cool
// depth and edge focus without a real-time light per object.
void fragment() {
	vec2 p = UV;
	float key = clamp(1.08 - p.x * 0.62 - p.y * 0.34, 0.0, 1.0);
	vec3 warm = vec3(1.0, 0.70, 0.38);
	vec3 cool = vec3(0.20, 0.28, 0.46);
	vec3 tint = mix(cool, warm, key);

	vec2 centered = (p - vec2(0.5)) * vec2(0.82, 1.0);
	float edge = smoothstep(0.30, 0.72, length(centered));
	float depth = smoothstep(0.48, 1.0, p.y);
	// Readable at gameplay zoom: warm gallery key, cool depth and a soft
	// vignette. The previous 3.5% base was effectively invisible on the cream
	// floor and did not survive display scaling.
	float sheen = smoothstep(0.0, 0.35, p.x + p.y) *
		(1.0 - smoothstep(0.35, 0.72, p.x + p.y));
	float alpha = 0.070 + edge * 0.060 + depth * 0.025 + sheen * 0.035;
	COLOR = vec4(tint, alpha);
}
