shader_type canvas_item;
render_mode unshaded;
// Geometry-edge smoothing for Compatibility, whose 2D MSAA is unsupported.
// Applied only to the final world pass; screen-space controls stay outside it.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform bool smoothing_enabled = true;
vec4 sample_world(vec2 uv) {
 return textureLod(screen_texture, uv, 0.0);
}
float luminance(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
void fragment() {
 vec2 uv = SCREEN_UV;
 vec2 px = SCREEN_PIXEL_SIZE;
 vec4 center = sample_world(uv);
 vec4 result = center;
 if (smoothing_enabled && center.a > 0.999) {
  vec4 nw = sample_world(uv + vec2(-1.0, -1.0) * px);
  vec4 ne = sample_world(uv + vec2( 1.0, -1.0) * px);
  vec4 sw = sample_world(uv + vec2(-1.0,  1.0) * px);
  vec4 se = sample_world(uv + vec2( 1.0,  1.0) * px);
  float lm = luminance(center.rgb);
  float lnw = luminance(nw.rgb); float lne = luminance(ne.rgb);
  float lsw = luminance(sw.rgb); float lse = luminance(se.rgb);
  float lo = min(lm, min(min(lnw, lne), min(lsw, lse)));
  float hi = max(lm, max(max(lnw, lne), max(lsw, lse)));
  // Leave low-contrast materials alone. Never filter across transparent bounds.
  if (hi - lo > max(0.04, hi * 0.125) && min(min(nw.a, ne.a), min(sw.a, se.a)) > 0.999) {
   vec2 direction = vec2(-((lnw + lne) - (lsw + lse)), (lnw + lsw) - (lne + lse));
   float reduce = max((lnw + lne + lsw + lse) * 0.03125, 0.0078125);
   direction = clamp(direction / (min(abs(direction.x), abs(direction.y)) + reduce), vec2(-4.0), vec2(4.0)) * px;
   vec3 a = 0.5 * (sample_world(uv - direction / 6.0).rgb + sample_world(uv + direction / 6.0).rgb);
   vec3 b = a * 0.5 + 0.25 * (sample_world(uv - direction * 0.5).rgb + sample_world(uv + direction * 0.5).rgb);
   float lb = luminance(b);
   result.rgb = (lb < lo || lb > hi) ? a : b;
  }
 }
 COLOR = result;
}
