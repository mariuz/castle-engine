{ -*- buffer-read-only: t -*- }
{ DON'T EDIT -- this file was automatically generated from "source/shadow_map_common.fs" }
'/* Shadow map functions. */' + LineEnding +
'' + LineEnding +
'/* Define exactly one of PCF* symbols, or none (to not use any PCF).' + LineEnding +
'   This is defined (or not) when including this shader in Pascal code,' + LineEnding +
'   automatically. */' + LineEnding +
'//#define PCF4' + LineEnding +
'//#define PCF4_BILINEAR' + LineEnding +
'//#define PCF16' + LineEnding +
'' + LineEnding +
'float castleShadow2D(sampler2DShadow shadowMap, const shadowsPrecision vec3 shadowMapCoord)' + LineEnding +
'{' + LineEnding +
'  /* On OpenGLES, we require GLSL "300 es" that allows (and requires) to query' + LineEnding +
'     sampler2DShadow using texture*, not shadow2D* functions.' + LineEnding +
'     See https://stackoverflow.com/a/22426507' + LineEnding +
'     https://www.khronos.org/opengl/wiki/Sampler_(GLSL)' + LineEnding +
'' + LineEnding +
'     Modern GLSL (from #version 140) also requires it.' + LineEnding +
'  */' + LineEnding +
'  #ifdef CASTLE_GLSL_VERSION_UPGRADE' + LineEnding +
'  return texture(shadowMap, shadowMapCoord);' + LineEnding +
'  #else' + LineEnding +
'  return shadow2D(shadowMap, shadowMapCoord).r;' + LineEnding +
'  #endif' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'float castleShadow2DProj(sampler2DShadow shadowMap, const shadowsPrecision vec4 shadowMapCoord)' + LineEnding +
'{' + LineEnding +
'  #ifdef CASTLE_GLSL_VERSION_UPGRADE' + LineEnding +
'  return textureProj(shadowMap, shadowMapCoord);' + LineEnding +
'  #else' + LineEnding +
'  return shadow2DProj(shadowMap, shadowMapCoord).r;' + LineEnding +
'  #endif' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'float shadow(sampler2DShadow shadowMap, const shadowsPrecision vec4 shadowMapCoord,' + LineEnding +
'  const in float size)' + LineEnding +
'{' + LineEnding +
'  /* Avoid back-projecting shadows. */' + LineEnding +
'  if (shadowMapCoord.z < 0.0) return 0.0;' + LineEnding +
'' + LineEnding +
'  /* When coord2 is outside (0, 0) - (1, 1) square, it''s never in the shadow.' + LineEnding +
'     This makes sense, see' + LineEnding +
'     https://github.com/castle-engine/castle-engine/issues/308' + LineEnding +
'     and demo-models/shadow_maps/explicit_projection_parameters/' + LineEnding +
'  */' + LineEnding +
'  vec2 coord2 = shadowMapCoord.st / shadowMapCoord.q;' + LineEnding +
'  if (coord2.s < 0.0 || coord2.s > 1.0 ||' + LineEnding +
'      coord2.t < 0.0 || coord2.t > 1.0)' + LineEnding +
'    return 1.0;' + LineEnding +
'' + LineEnding +
'#ifdef PCF4_BILINEAR' + LineEnding +
'' + LineEnding +
'  /* We have to scale up/down by texture size to make the floor/fract' + LineEnding +
'     perform real bilinear filtering.' + LineEnding +
'     This also means that we have to handle xy and z separately. */' + LineEnding +
'  vec2 tc_full = size * coord2;' + LineEnding +
'  float z = shadowMapCoord.z / shadowMapCoord.w;' + LineEnding +
'' + LineEnding +
'  vec2 tc = floor(tc_full.xy);' + LineEnding +
'  vec2 f = fract(tc_full.xy);' + LineEnding +
'  vec2 f1 = vec2(1.0, 1.0) - f;' + LineEnding +
'' + LineEnding +
'  return' + LineEnding +
'    castleShadow2D(shadowMap, vec3( tc.x        / size,  tc.y        / size, z)) * f1.x * f1.y +' + LineEnding +
'    castleShadow2D(shadowMap, vec3( tc.x        / size, (tc.y + 1.0) / size, z)) * f1.x *  f.y +' + LineEnding +
'    castleShadow2D(shadowMap, vec3((tc.x + 1.0) / size,  tc.y        / size, z)) *  f.x * f1.y +' + LineEnding +
'    castleShadow2D(shadowMap, vec3((tc.x + 1.0) / size, (tc.y + 1.0) / size, z)) *  f.x *  f.y;' + LineEnding +
'' + LineEnding +
'#elif defined(PCF4)' + LineEnding +
'' + LineEnding +
'  /* PCF with 2x2 kernel */' + LineEnding +
'  float offset = shadowMapCoord.w / size;' + LineEnding +
'  return (' + LineEnding +
'    castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset, -offset, 0.0, 0.0)) +' + LineEnding +
'    castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset,  offset, 0.0, 0.0)) +' + LineEnding +
'    castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset,  offset, 0.0, 0.0)) +' + LineEnding +
'    castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset, -offset, 0.0, 0.0))' + LineEnding +
'    ) / 4.0;' + LineEnding +
'' + LineEnding +
'#elif defined(PCF16)' + LineEnding +
'' + LineEnding +
'  float offset = shadowMapCoord.w / size;' + LineEnding +
'  return' + LineEnding +
'    (' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 1.5, -offset * 1.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 1.5, -offset * 0.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 0.5, -offset * 0.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 0.5, -offset * 1.5, 0.0, 0.0)) +' + LineEnding +
'' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 1.5,  offset * 1.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 1.5,  offset * 0.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 0.5,  offset * 0.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4(-offset * 0.5,  offset * 1.5, 0.0, 0.0)) +' + LineEnding +
'' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 1.5,  offset * 1.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 1.5,  offset * 0.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 0.5,  offset * 0.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 0.5,  offset * 1.5, 0.0, 0.0)) +' + LineEnding +
'' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 1.5, -offset * 1.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 1.5, -offset * 0.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 0.5, -offset * 0.5, 0.0, 0.0)) +' + LineEnding +
'      castleShadow2DProj(shadowMap, shadowMapCoord + vec4( offset * 0.5, -offset * 1.5, 0.0, 0.0))' + LineEnding +
'    )' + LineEnding +
'    / 16.0;' + LineEnding +
'#else' + LineEnding +
'  /* No PCF */' + LineEnding +
'  return castleShadow2DProj(shadowMap, shadowMapCoord);' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'/* Shadow from one view (tile) of a shadow map, in a texture that may hold' + LineEnding +
'   many tiles (the shadow map atlas, or the 6 faces of a point light).' + LineEnding +
'' + LineEnding +
'   coord is the position in the texture coordinates (and depth in 0..1)' + LineEnding +
'   of the tile, before the division by w. rect is the tile' + LineEnding +
'   (minimum x, y and maximum x, y in 0..1), texel is 1 / the texture size.' + LineEnding +
'' + LineEnding +
'   When always_inside is false, positions outside the tile are lit' + LineEnding +
'   (like outside of a whole shadow map). Otherwise (cube faces)' + LineEnding +
'   they are clamped to it. The filtering samples (PCF) are clamped' + LineEnding +
'   to the tile too, so they never read the neighboring tiles. */' + LineEnding +
'float castle_shadow_tile(sampler2DShadow shadowMap, const shadowsPrecision vec4 coord,' + LineEnding +
'  const in vec4 rect, const in vec2 texel, const in bool always_inside)' + LineEnding +
'{' + LineEnding +
'  /* Avoid back-projecting shadows. */' + LineEnding +
'  if (!always_inside && coord.z < 0.0) return 0.0;' + LineEnding +
'' + LineEnding +
'  shadowsPrecision vec3 c = coord.xyz / coord.w;' + LineEnding +
'  if (!always_inside &&' + LineEnding +
'      (c.x < rect.x || c.x > rect.z ||' + LineEnding +
'       c.y < rect.y || c.y > rect.w))' + LineEnding +
'    return 1.0;' + LineEnding +
'' + LineEnding +
'#if defined(PCF16)' + LineEnding +
'  vec2 inset = texel * 2.0;' + LineEnding +
'#elif defined(PCF4) || defined(PCF4_BILINEAR)' + LineEnding +
'  vec2 inset = texel * 1.5;' + LineEnding +
'#else' + LineEnding +
'  vec2 inset = texel * 0.5;' + LineEnding +
'#endif' + LineEnding +
'  c.xy = clamp(c.xy, rect.xy + inset, rect.zw - inset);' + LineEnding +
'' + LineEnding +
'#ifdef PCF4_BILINEAR' + LineEnding +
'' + LineEnding +
'  vec2 tc_full = c.xy / texel;' + LineEnding +
'  vec2 tc = floor(tc_full);' + LineEnding +
'  vec2 f = fract(tc_full);' + LineEnding +
'  vec2 f1 = vec2(1.0, 1.0) - f;' + LineEnding +
'' + LineEnding +
'  return' + LineEnding +
'    castleShadow2D(shadowMap, vec3( tc.x        * texel.x,  tc.y        * texel.y, c.z)) * f1.x * f1.y +' + LineEnding +
'    castleShadow2D(shadowMap, vec3( tc.x        * texel.x, (tc.y + 1.0) * texel.y, c.z)) * f1.x *  f.y +' + LineEnding +
'    castleShadow2D(shadowMap, vec3((tc.x + 1.0) * texel.x,  tc.y        * texel.y, c.z)) *  f.x * f1.y +' + LineEnding +
'    castleShadow2D(shadowMap, vec3((tc.x + 1.0) * texel.x, (tc.y + 1.0) * texel.y, c.z)) *  f.x *  f.y;' + LineEnding +
'' + LineEnding +
'#elif defined(PCF4)' + LineEnding +
'' + LineEnding +
'  return (' + LineEnding +
'    castleShadow2D(shadowMap, c + vec3(-texel.x, -texel.y, 0.0)) +' + LineEnding +
'    castleShadow2D(shadowMap, c + vec3(-texel.x,  texel.y, 0.0)) +' + LineEnding +
'    castleShadow2D(shadowMap, c + vec3( texel.x,  texel.y, 0.0)) +' + LineEnding +
'    castleShadow2D(shadowMap, c + vec3( texel.x, -texel.y, 0.0))' + LineEnding +
'    ) / 4.0;' + LineEnding +
'' + LineEnding +
'#elif defined(PCF16)' + LineEnding +
'' + LineEnding +
'  float result = 0.0;' + LineEnding +
'  for (int y = 0; y < 4; y++)' + LineEnding +
'    for (int x = 0; x < 4; x++)' + LineEnding +
'      result += castleShadow2D(shadowMap, c + vec3(' + LineEnding +
'        (float(x) - 1.5) * texel.x,' + LineEnding +
'        (float(y) - 1.5) * texel.y, 0.0));' + LineEnding +
'  return result / 16.0;' + LineEnding +
'' + LineEnding +
'#else' + LineEnding +
'  return castleShadow2D(shadowMap, c);' + LineEnding +
'#endif' + LineEnding +
'}' + LineEnding +
''
