/*
  Show what is behind the shape (screen_texture, a ScreenTexture:
  the colors rendered before this shape), moved by waves:
  glass refraction (speed = 0) or heat haze (moving waves).

  The ScreenTexture covers the viewport: we sample it at the screen
  position of the fragment, from castle_vertex_eye (needs Phong shading)
  and the projection matrix.
*/

uniform sampler2D screen_texture;
/* Distortion size, in the viewport size units (0..1). */
uniform float strength;
/* How fast the waves move. */
uniform float speed;
uniform float time;
uniform vec3 tint;

uniform mat4 castle_ProjectionMatrix;
varying vec4 castle_vertex_eye;

void PLUG_fragment_modify(inout vec4 fragment_color)
{
  vec4 clip = castle_ProjectionMatrix * castle_vertex_eye;
  vec2 screen_uv = clip.xy / clip.w * 0.5 + 0.5;
  vec2 offset = strength * vec2(
    sin(castle_vertex_eye.y * 9.0 + time * speed),
    cos(castle_vertex_eye.x * 7.0 + time * speed * 0.8));
  fragment_color = vec4(texture2D(screen_texture, screen_uv + offset).rgb * tint, 1.0);
}
