/*
  Copyright 2026 Popa Marius Adrian.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
*/

/* Temporal anti-aliasing (TCastleViewport.TemporalAntiAliasing):
   blend the world rendered in this frame (with a sub-pixel jitter
   of the projection) with the previous result (the history).

   The motion vectors come from the depth buffer: each pixel's point
   is transformed to the previous frame's clip coordinates by
   temporal_reprojection, which follows the camera motion
   (the front layer, rlFront, is assumed to move with the camera).
   Moving objects (and anything else the reprojection gets wrong)
   would leave trails, so the history is clamped to the colors around
   the pixel in this frame (variance clipping in YCoCg, like Salvi 2016). */

uniform sampler2D temporal_history;
uniform mat4 temporal_reprojection;
uniform float temporal_feedback;
uniform int temporal_history_valid;

ivec2 screen_position();
vec4 screen_get_color(ivec2 position);
float screen_get_depth(ivec2 position);

vec3 rgb_to_ycocg(const in vec3 c)
{
  return vec3(
     0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
     0.5  * c.r             - 0.5  * c.b,
    -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}

vec3 ycocg_to_rgb(const in vec3 c)
{
  return vec3(
    c.x + c.y - c.z,
    c.x       + c.z,
    c.x - c.y - c.z);
}

void main(void)
{
  ivec2 position = screen_position();
  vec3 current = rgb_to_ycocg(screen_get_color(position).rgb);

  if (temporal_history_valid == 0) {
    gl_FragColor = vec4(ycocg_to_rgb(current), 1.0);
    return;
  }

  /* The mean and standard deviation of the 3x3 neighborhood
     (outside the screen, the texture's clamping repeats the edge),
     and its nearest depth. */
  vec3 m1 = vec3(0.0);
  vec3 m2 = vec3(0.0);
  float depth = 1.0;
  for (int y = -1; y <= 1; y++)
    for (int x = -1; x <= 1; x++) {
      ivec2 p = position + ivec2(x, y);
      vec3 c = rgb_to_ycocg(screen_get_color(p).rgb);
      m1 += c;
      m2 += c * c;
      depth = min(depth, screen_get_depth(p));
    }
  m1 /= 9.0;
  m2 /= 9.0;
  vec3 sigma = sqrt(max(m2 - m1 * m1, vec3(0.0)));

  /* Where was this point in the previous frame.
     Use the nearest depth around: the pixels just outside a moving object's
     edge then move with it, the edge doesn't leave a trail
     (Karis 2014, "High Quality Temporal Supersampling"). */
  vec2 size = vec2(float(screen_width), float(screen_height));
  vec2 uv = (vec2(position) + vec2(0.5)) / size;
  vec2 previous_uv;
  vec4 previous;
  /* Like TRenderContext.UpdateDepthRange: the world is rendered with
     glDepthRange(0.1, 1), the front layer (rlFront, like a weapon
     in an FPS game) with glDepthRange(0, 0.1). */
  if (depth < 0.1) {
    /* The front layer usually moves with the camera: no motion. */
    previous = vec4(uv * 2.0 - vec2(1.0), 0.0, 1.0);
  } else {
    float ndc_depth = (depth - 0.1) / 0.9 * 2.0 - 1.0;
    previous = temporal_reprojection *
      vec4(uv * 2.0 - vec2(1.0), ndc_depth, 1.0);
  }
  previous_uv = previous.xy / previous.w * 0.5 + vec2(0.5);

  if (previous.w <= 0.0 ||
      any(lessThan(previous_uv, vec2(0.0))) ||
      any(greaterThan(previous_uv, vec2(1.0)))) {
    gl_FragColor = vec4(ycocg_to_rgb(current), 1.0);
    return;
  }

  vec3 history = rgb_to_ycocg(texture2D(temporal_history, previous_uv).rgb);
  history = clamp(history, m1 - sigma, m1 + sigma);

  gl_FragColor = vec4(ycocg_to_rgb(mix(current, history, temporal_feedback)), 1.0);
}
