/* Shadow map functions. */

/* Define exactly one of PCF* symbols, or none (to not use any PCF).
   This is defined (or not) when including this shader in Pascal code,
   automatically. */
//#define PCF4
//#define PCF4_BILINEAR
//#define PCF16

float castleShadow2D(sampler2DShadow shadowMap, const shadowsPrecision vec3 shadowMapCoord)
{
  /* On OpenGLES, we require GLSL "300 es" that allows (and requires) to query
     sampler2DShadow using texture*, not shadow2D* functions.
     See https://stackoverflow.com/a/22426507
     https://www.khronos.org/opengl/wiki/Sampler_(GLSL)

     Modern GLSL (from #version 140) also requires it.
  */
  #ifdef CASTLE_GLSL_VERSION_UPGRADE
  return texture(shadowMap, shadowMapCoord);
  #else
  return shadow2D(shadowMap, shadowMapCoord).r;
  #endif
}

float castleShadow2DProj(sampler2DShadow shadowMap, const shadowsPrecision vec4 shadowMapCoord)
{
  #ifdef CASTLE_GLSL_VERSION_UPGRADE
  return textureProj(shadowMap, shadowMapCoord);
  #else
  return shadow2DProj(shadowMap, shadowMapCoord).r;
  #endif
}

float shadow(sampler2DShadow shadowMap, const shadowsPrecision vec4 shadowMapCoord,
  const in float size)
{
  /* Avoid back-projecting shadows. */
  if (shadowMapCoord.z < 0.0) return 0.0;

  /* When coord2 is outside (0, 0) - (1, 1) square, it's never in the shadow.
     This makes sense, see
     https://github.com/castle-engine/castle-engine/issues/308
     and demo-models/shadow_maps/explicit_projection_parameters/
  */
  vec2 coord2 = shadowMapCoord.st / shadowMapCoord.q;
  if (coord2.s < 0.0 || coord2.s > 1.0 ||
      coord2.t < 0.0 || coord2.t > 1.0)
    return 1.0;

#ifdef PCF4_BILINEAR

  /* We have to scale up/down by texture size to make the floor/fract
     perform real bilinear filtering.
     This also means that we have to handle xy and z separately. */
  vec2 tc_full = size * coord2;
  float z = shadowMapCoord.z / shadowMapCoord.w;

  vec2 tc = floor(tc_full.xy);
  vec2 f = fract(tc_full.xy);
  vec2 f1 = vec2(1.0, 1.0) - f;

  return
    castleShadow2D(shadowMap, vec3( tc.x        / size,  tc.y        / size, z)) * f1.x * f1.y +
    castleShadow2D(shadowMap, vec3( tc.x        / size, (tc.y + 1.0) / size, z)) * f1.x *  f.y +
    castleShadow2D(shadowMap, vec3((tc.x + 1.0) / size,  tc.y        / size, z)) *  f.x * f1.y +
    castleShadow2D(shadowMap, vec3((tc.x + 1.0) / size, (tc.y + 1.0) / size, z)) *  f.x *  f.y;

#elif defined(PCF4)

  /* PCF with 2x2 kernel */
  float offset = shadowMapCoord.w / size;
  return (
    castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset, -offset, 0.0, 0.0)) +
    castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset,  offset, 0.0, 0.0)) +
    castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset,  offset, 0.0, 0.0)) +
    castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset, -offset, 0.0, 0.0))
    ) / 4.0;

#elif defined(PCF16)

  float offset = shadowMapCoord.w / size;
  return
    (
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 1.5, -offset * 1.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 1.5, -offset * 0.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 0.5, -offset * 0.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 0.5, -offset * 1.5, 0.0, 0.0)) +

      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 1.5,  offset * 1.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 1.5,  offset * 0.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 0.5,  offset * 0.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 0.5,  offset * 1.5, 0.0, 0.0)) +

      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 1.5,  offset * 1.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 1.5,  offset * 0.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 0.5,  offset * 0.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 0.5,  offset * 1.5, 0.0, 0.0)) +

      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 1.5, -offset * 1.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 1.5, -offset * 0.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 0.5, -offset * 0.5, 0.0, 0.0)) +
      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 0.5, -offset * 1.5, 0.0, 0.0))
    )
    / 16.0;
#else
  /* No PCF */
  return castleShadow2DProj(shadowMap, shadowMapCoord);
#endif

}

/* Shadow from one view (tile) of a shadow map, in a texture that may hold
   many tiles (the shadow map atlas, or the 6 faces of a point light).

   coord is the position in the texture coordinates (and depth in 0..1)
   of the tile, before the division by w. rect is the tile
   (minimum x, y and maximum x, y in 0..1), texel is 1 / the texture size.

   When always_inside is false, positions outside the tile are lit
   (like outside of a whole shadow map). Otherwise (cube faces)
   they are clamped to it. The filtering samples (PCF) are clamped
   to the tile too, so they never read the neighboring tiles. */
float castle_shadow_tile(sampler2DShadow shadowMap, const shadowsPrecision vec4 coord,
  const in vec4 rect, const in vec2 texel, const in bool always_inside)
{
  /* Avoid back-projecting shadows. */
  if (!always_inside && coord.z < 0.0) return 0.0;

  shadowsPrecision vec3 c = coord.xyz / coord.w;
  if (!always_inside &&
      (c.x < rect.x || c.x > rect.z ||
       c.y < rect.y || c.y > rect.w))
    return 1.0;

#if defined(PCF16)
  vec2 inset = texel * 2.0;
#elif defined(PCF4) || defined(PCF4_BILINEAR)
  vec2 inset = texel * 1.5;
#else
  vec2 inset = texel * 0.5;
#endif
  c.xy = clamp(c.xy, rect.xy + inset, rect.zw - inset);

#ifdef PCF4_BILINEAR

  vec2 tc_full = c.xy / texel;
  vec2 tc = floor(tc_full);
  vec2 f = fract(tc_full);
  vec2 f1 = vec2(1.0, 1.0) - f;

  return
    castleShadow2D(shadowMap, vec3( tc.x        * texel.x,  tc.y        * texel.y, c.z)) * f1.x * f1.y +
    castleShadow2D(shadowMap, vec3( tc.x        * texel.x, (tc.y + 1.0) * texel.y, c.z)) * f1.x *  f.y +
    castleShadow2D(shadowMap, vec3((tc.x + 1.0) * texel.x,  tc.y        * texel.y, c.z)) *  f.x * f1.y +
    castleShadow2D(shadowMap, vec3((tc.x + 1.0) * texel.x, (tc.y + 1.0) * texel.y, c.z)) *  f.x *  f.y;

#elif defined(PCF4)

  return (
    castleShadow2D(shadowMap, c + vec3(-texel.x, -texel.y, 0.0)) +
    castleShadow2D(shadowMap, c + vec3(-texel.x,  texel.y, 0.0)) +
    castleShadow2D(shadowMap, c + vec3( texel.x,  texel.y, 0.0)) +
    castleShadow2D(shadowMap, c + vec3( texel.x, -texel.y, 0.0))
    ) / 4.0;

#elif defined(PCF16)

  float result = 0.0;
  for (int y = 0; y < 4; y++)
    for (int x = 0; x < 4; x++)
      result += castleShadow2D(shadowMap, c + vec3(
        (float(x) - 1.5) * texel.x,
        (float(y) - 1.5) * texel.y, 0.0));
  return result / 16.0;

#else
  return castleShadow2D(shadowMap, c);
#endif
}
