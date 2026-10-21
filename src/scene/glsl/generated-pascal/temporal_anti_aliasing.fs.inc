{ -*- buffer-read-only: t -*- }
{ DON'T EDIT -- this file was automatically generated from "source/temporal_anti_aliasing.fs" }
'/*' + LineEnding +
'  Copyright 2026 Popa Marius Adrian.' + LineEnding +
'' + LineEnding +
'  This file is part of "Castle Game Engine".' + LineEnding +
'' + LineEnding +
'  "Castle Game Engine" is free software; see the file COPYING.md,' + LineEnding +
'  included in this distribution, for details about the copyright.' + LineEnding +
'' + LineEnding +
'  "Castle Game Engine" is distributed in the hope that it will be useful,' + LineEnding +
'  but WITHOUT ANY WARRANTY; without even the implied warranty of' + LineEnding +
'  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.' + LineEnding +
'' + LineEnding +
'  ----------------------------------------------------------------------------' + LineEnding +
'*/' + LineEnding +
'' + LineEnding +
'/* Temporal anti-aliasing (TCastleViewport.TemporalAntiAliasing):' + LineEnding +
'   blend the world rendered in this frame (with a sub-pixel jitter' + LineEnding +
'   of the projection) with the previous result (the history).' + LineEnding +
'' + LineEnding +
'   The motion vectors come from the depth buffer: each pixel''s point' + LineEnding +
'   is transformed to the previous frame''s clip coordinates by' + LineEnding +
'   temporal_reprojection, which follows the camera motion' + LineEnding +
'   (the front layer, rlFront, is assumed to move with the camera).' + LineEnding +
'   Moving objects (and anything else the reprojection gets wrong)' + LineEnding +
'   would leave trails, so the history is clamped to the colors around' + LineEnding +
'   the pixel in this frame (variance clipping in YCoCg, like Salvi 2016). */' + LineEnding +
'' + LineEnding +
'uniform sampler2D temporal_history;' + LineEnding +
'uniform mat4 temporal_reprojection;' + LineEnding +
'uniform float temporal_feedback;' + LineEnding +
'uniform int temporal_history_valid;' + LineEnding +
'' + LineEnding +
'ivec2 screen_position();' + LineEnding +
'vec4 screen_get_color(ivec2 position);' + LineEnding +
'float screen_get_depth(ivec2 position);' + LineEnding +
'' + LineEnding +
'vec3 rgb_to_ycocg(const in vec3 c)' + LineEnding +
'{' + LineEnding +
'  return vec3(' + LineEnding +
'     0.25 * c.r + 0.5 * c.g + 0.25 * c.b,' + LineEnding +
'     0.5  * c.r             - 0.5  * c.b,' + LineEnding +
'    -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'vec3 ycocg_to_rgb(const in vec3 c)' + LineEnding +
'{' + LineEnding +
'  return vec3(' + LineEnding +
'    c.x + c.y - c.z,' + LineEnding +
'    c.x       + c.z,' + LineEnding +
'    c.x - c.y - c.z);' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'void main(void)' + LineEnding +
'{' + LineEnding +
'  ivec2 position = screen_position();' + LineEnding +
'  vec3 current = rgb_to_ycocg(screen_get_color(position).rgb);' + LineEnding +
'' + LineEnding +
'  if (temporal_history_valid == 0) {' + LineEnding +
'    gl_FragColor = vec4(ycocg_to_rgb(current), 1.0);' + LineEnding +
'    return;' + LineEnding +
'  }' + LineEnding +
'' + LineEnding +
'  /* The mean and standard deviation of the 3x3 neighborhood' + LineEnding +
'     (outside the screen, the texture''s clamping repeats the edge),' + LineEnding +
'     and its nearest depth. */' + LineEnding +
'  vec3 m1 = vec3(0.0);' + LineEnding +
'  vec3 m2 = vec3(0.0);' + LineEnding +
'  float depth = 1.0;' + LineEnding +
'  for (int y = -1; y <= 1; y++)' + LineEnding +
'    for (int x = -1; x <= 1; x++) {' + LineEnding +
'      ivec2 p = position + ivec2(x, y);' + LineEnding +
'      vec3 c = rgb_to_ycocg(screen_get_color(p).rgb);' + LineEnding +
'      m1 += c;' + LineEnding +
'      m2 += c * c;' + LineEnding +
'      depth = min(depth, screen_get_depth(p));' + LineEnding +
'    }' + LineEnding +
'  m1 /= 9.0;' + LineEnding +
'  m2 /= 9.0;' + LineEnding +
'  vec3 sigma = sqrt(max(m2 - m1 * m1, vec3(0.0)));' + LineEnding +
'' + LineEnding +
'  /* Where was this point in the previous frame.' + LineEnding +
'     Use the nearest depth around: the pixels just outside a moving object''s' + LineEnding +
'     edge then move with it, the edge doesn''t leave a trail' + LineEnding +
'     (Karis 2014, "High Quality Temporal Supersampling"). */' + LineEnding +
'  vec2 size = vec2(float(screen_width), float(screen_height));' + LineEnding +
'  vec2 uv = (vec2(position) + vec2(0.5)) / size;' + LineEnding +
'  vec2 previous_uv;' + LineEnding +
'  vec4 previous;' + LineEnding +
'  /* Like TRenderContext.UpdateDepthRange: the world is rendered with' + LineEnding +
'     glDepthRange(0.1, 1), the front layer (rlFront, like a weapon' + LineEnding +
'     in an FPS game) with glDepthRange(0, 0.1). */' + LineEnding +
'  if (depth < 0.1) {' + LineEnding +
'    /* The front layer usually moves with the camera: no motion. */' + LineEnding +
'    previous = vec4(uv * 2.0 - vec2(1.0), 0.0, 1.0);' + LineEnding +
'  } else {' + LineEnding +
'    float ndc_depth = (depth - 0.1) / 0.9 * 2.0 - 1.0;' + LineEnding +
'    previous = temporal_reprojection *' + LineEnding +
'      vec4(uv * 2.0 - vec2(1.0), ndc_depth, 1.0);' + LineEnding +
'  }' + LineEnding +
'  previous_uv = previous.xy / previous.w * 0.5 + vec2(0.5);' + LineEnding +
'' + LineEnding +
'  if (previous.w <= 0.0 ||' + LineEnding +
'      any(lessThan(previous_uv, vec2(0.0))) ||' + LineEnding +
'      any(greaterThan(previous_uv, vec2(1.0)))) {' + LineEnding +
'    gl_FragColor = vec4(ycocg_to_rgb(current), 1.0);' + LineEnding +
'    return;' + LineEnding +
'  }' + LineEnding +
'' + LineEnding +
'  vec3 history = rgb_to_ycocg(texture2D(temporal_history, previous_uv).rgb);' + LineEnding +
'  history = clamp(history, m1 - sigma, m1 + sigma);' + LineEnding +
'' + LineEnding +
'  gl_FragColor = vec4(ycocg_to_rgb(mix(current, history, temporal_feedback)), 1.0);' + LineEnding +
'}' + LineEnding +
''
