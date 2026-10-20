{ -*- buffer-read-only: t -*- }
{ DON'T EDIT -- this file was automatically generated from "source/variance_shadow_map_common.fs" }
'/* Extract shadow (how light is the point) from variance shadow map.' + LineEnding +
'   This closely follows VSM presentation, slide 16. */' + LineEnding +
'' + LineEnding +
'float shadow(sampler2D shadowMap, const shadowsPrecision vec4 shadowMapCoord, const in float size)' + LineEnding +
'{' + LineEnding +
'  /* Avoid back-projecting shadows. */' + LineEnding +
'  if (shadowMapCoord.z < 0.0) return 0.0;' + LineEnding +
'' + LineEnding +
'  /* When coord2 is outside (0, 0) - (1, 1) square,' + LineEnding +
'     it''s always in the shadow. Otherwise shadows would be stretched' + LineEnding +
'     over whole scene, due to clamping. */' + LineEnding +
'  vec2 coord2 = shadowMapCoord.st / shadowMapCoord.q;' + LineEnding +
'  if (coord2.s < 0.0 || coord2.s > 1.0 ||' + LineEnding +
'      coord2.t < 0.0 || coord2.t > 1.0)' + LineEnding +
'    return 0.0;' + LineEnding +
'' + LineEnding +
'  vec4 moments = texture2D(shadowMap, coord2);' + LineEnding +
'  float distance_to_light = shadowMapCoord.z / shadowMapCoord.q;' + LineEnding +
'' + LineEnding +
'  if (distance_to_light <= moments[0])' + LineEnding +
'    return 1.0; else' + LineEnding +
'  {' + LineEnding +
'    float E_x2 = moments[1];' + LineEnding +
'    float Ex_2 = moments[0] * moments[0];' + LineEnding +
'    float variance = E_x2 - Ex_2;' + LineEnding +
'    float m_d = moments[0] - distance_to_light;' + LineEnding +
'    return variance / (variance + m_d * m_d);' + LineEnding +
'  }' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'/* Shadow from one view (tile) of a variance shadow map,' + LineEnding +
'   see castle_shadow_tile in shadow_map_common.fs. */' + LineEnding +
'float castle_shadow_tile(sampler2D shadowMap, const shadowsPrecision vec4 coord,' + LineEnding +
'  const in vec4 rect, const in vec2 texel, const in bool always_inside)' + LineEnding +
'{' + LineEnding +
'  /* Avoid back-projecting shadows. */' + LineEnding +
'  if (!always_inside && coord.z < 0.0) return 0.0;' + LineEnding +
'' + LineEnding +
'  shadowsPrecision vec3 c = coord.xyz / coord.w;' + LineEnding +
'  /* Outside of the tile, it''s in the shadow, like outside of a whole' + LineEnding +
'     variance shadow map. */' + LineEnding +
'  if (!always_inside &&' + LineEnding +
'      (c.x < rect.x || c.x > rect.z ||' + LineEnding +
'       c.y < rect.y || c.y > rect.w))' + LineEnding +
'    return 0.0;' + LineEnding +
'  c.xy = clamp(c.xy, rect.xy + texel * 0.5, rect.zw - texel * 0.5);' + LineEnding +
'' + LineEnding +
'  vec4 moments = texture2D(shadowMap, c.xy);' + LineEnding +
'  float distance_to_light = c.z;' + LineEnding +
'' + LineEnding +
'  if (distance_to_light <= moments[0])' + LineEnding +
'    return 1.0; else' + LineEnding +
'  {' + LineEnding +
'    float E_x2 = moments[1];' + LineEnding +
'    float Ex_2 = moments[0] * moments[0];' + LineEnding +
'    float variance = E_x2 - Ex_2;' + LineEnding +
'    float m_d = moments[0] - distance_to_light;' + LineEnding +
'    return variance / (variance + m_d * m_d);' + LineEnding +
'  }' + LineEnding +
'}' + LineEnding +
''
