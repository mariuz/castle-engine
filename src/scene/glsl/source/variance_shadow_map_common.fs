/* Extract shadow (how light is the point) from variance shadow map.
   This closely follows VSM presentation, slide 16. */

float shadow(sampler2D shadowMap, const shadowsPrecision vec4 shadowMapCoord, const in float size)
{
  /* Avoid back-projecting shadows. */
  if (shadowMapCoord.z < 0.0) return 0.0;

  /* When coord2 is outside (0, 0) - (1, 1) square,
     it's always in the shadow. Otherwise shadows would be stretched
     over whole scene, due to clamping. */
  vec2 coord2 = shadowMapCoord.st / shadowMapCoord.q;
  if (coord2.s < 0.0 || coord2.s > 1.0 ||
      coord2.t < 0.0 || coord2.t > 1.0)
    return 0.0;

  vec4 moments = texture2D(shadowMap, coord2);
  float distance_to_light = shadowMapCoord.z / shadowMapCoord.q;

  if (distance_to_light <= moments[0])
    return 1.0; else
  {
    float E_x2 = moments[1];
    float Ex_2 = moments[0] * moments[0];
    float variance = E_x2 - Ex_2;
    float m_d = moments[0] - distance_to_light;
    return variance / (variance + m_d * m_d);
  }
}

/* Shadow from one view (tile) of a variance shadow map,
   see castle_shadow_tile in shadow_map_common.fs. */
float castle_shadow_tile(sampler2D shadowMap, const shadowsPrecision vec4 coord,
  const in vec4 rect, const in vec2 texel, const in bool always_inside)
{
  /* Avoid back-projecting shadows. */
  if (!always_inside && coord.z < 0.0) return 0.0;

  shadowsPrecision vec3 c = coord.xyz / coord.w;
  /* Outside of the tile, it's in the shadow, like outside of a whole
     variance shadow map. */
  if (!always_inside &&
      (c.x < rect.x || c.x > rect.z ||
       c.y < rect.y || c.y > rect.w))
    return 0.0;
  c.xy = clamp(c.xy, rect.xy + texel * 0.5, rect.zw - texel * 0.5);

  vec4 moments = texture2D(shadowMap, c.xy);
  float distance_to_light = c.z;

  if (distance_to_light <= moments[0])
    return 1.0; else
  {
    float E_x2 = moments[1];
    float Ex_2 = moments[0] * moments[0];
    float variance = E_x2 - Ex_2;
    float m_d = moments[0] - distance_to_light;
    return variance / (variance + m_d * m_d);
  }
}
