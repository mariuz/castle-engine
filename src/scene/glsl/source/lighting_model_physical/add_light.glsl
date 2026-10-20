/*
  Copyright 2020-2022 Michalis Kamburelis and glTF-Sample-Viewer authors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------

  Shader code used for adding light source contribution for PhysicalMaterial
  (PBR lighting model).
  This is used by both desktop OpenGL and OpenGLES.

  In the future this may be used in both Gouraud and Phong shading,
  so it may go either in vertex or fragment shader.
  For now: since PhysicalMaterial now forces Phong shading, this is only used in Phong shading.
*/

/* Light source position (or direction, if not LIGHT<Light>_TYPE_POSITIONAL)
   in eye coordinates. */
uniform vec3 castle_LightSource<Light>Position;

/* SpotLight specific parameters */
#ifdef LIGHT<Light>_TYPE_SPOT
uniform vec3 castle_LightSource<Light>SpotDirection;
uniform float castle_LightSource<Light>SpotCosCutoff;
#ifdef LIGHT<Light>_HAS_BEAM_WIDTH
/* In radians. Note that this differs from gl_LightSource[<Light>].spotCutoff
   that is in degrees. */
uniform float castle_LightSource<Light>SpotCutoff;
uniform float castle_LightSource<Light>BeamWidth;
#endif
#ifdef LIGHT<Light>_HAS_SPOT_EXPONENT
uniform float castle_LightSource<Light>SpotExponent;
#endif
#endif

uniform vec3 castle_LightSource<Light>Color;

#ifdef LIGHT<Light>_HAS_ATTENUATION
/* Attenuation: constant, linear, quadratic. */
uniform vec3 castle_LightSource<Light>Attenuation;
#endif

#ifdef LIGHT<Light>_HAS_RADIUS
uniform float castle_LightSource<Light>Radius;
#endif

/* EnvironmentLight parameters */
#ifdef LIGHT<Light>_TYPE_ENVIRONMENT
/* Eye space to the light's local space (of its textures and influence box). */
uniform mat4 castle_LightSource<Light>EyeToLight;
#ifdef LIGHT<Light>_HAS_DIFFUSE_TEXTURE
/* Irradiance cube map: the diffuse light for each normal direction. */
uniform samplerCube castle_LightSource<Light>DiffuseTexture;
#endif
#ifdef LIGHT<Light>_HAS_SPECULAR_TEXTURE
/* Prefiltered radiance cube map: mipmap levels for increasing roughness. */
uniform samplerCube castle_LightSource<Light>SpecularTexture;
#endif
#ifdef LIGHT<Light>_HAS_IRRADIANCE_VOLUME
/* Spherical harmonics (L0, L1x, L1y, L1z) of the irradiance in a grid
   over the influence box, 4 slabs along Z, see EnvironmentLight.irradianceVolume. */
#ifdef GL_ES
uniform highp sampler3D castle_LightSource<Light>IrradianceVolume;
#else
uniform sampler3D castle_LightSource<Light>IrradianceVolume;
#endif
uniform vec3 castle_LightSource<Light>InfluenceMin;
uniform vec3 castle_LightSource<Light>InfluenceSize;
#endif

/* Analytic approximation of the split-sum environment BRDF
   (Brian Karis, "Physically Based Shading on Mobile", 2014). */
vec3 castle_env_brdf_approx<Light>(const in vec3 specular_color,
  const in float roughness, const in float n_dot_v)
{
  const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
  const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
  vec4 r = roughness * c0 + c1;
  float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
  vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;
  return specular_color * ab.x + ab.y;
}

#ifdef LIGHT<Light>_HAS_IRRADIANCE_VOLUME
/* Irradiance for the normal n (light's local space) at the point p
   (light's local space) from the irradiance volume. */
vec3 castle_irradiance_volume<Light>(const in vec3 p, const in vec3 n)
{
  vec3 uvw = clamp((p - castle_LightSource<Light>InfluenceMin) /
    castle_LightSource<Light>InfluenceSize, 0.0, 1.0);
#ifdef CASTLE_GLSL_VERSION_UPGRADE
  /* Keep the Z coordinate within the half texels of each slab,
     so that linear filtering doesn't mix the slabs. */
  float slab_texels = float(textureSize(castle_LightSource<Light>IrradianceVolume, 0).z) / 4.0;
  uvw.z = clamp(uvw.z, 0.5 / slab_texels, 1.0 - 0.5 / slab_texels);
#endif
  uvw.z /= 4.0;
  vec3 l0  = texture3D(castle_LightSource<Light>IrradianceVolume, uvw).rgb;
  vec3 l1x = texture3D(castle_LightSource<Light>IrradianceVolume, uvw + vec3(0.0, 0.0, 0.25)).rgb;
  vec3 l1y = texture3D(castle_LightSource<Light>IrradianceVolume, uvw + vec3(0.0, 0.0, 0.5)).rgb;
  vec3 l1z = texture3D(castle_LightSource<Light>IrradianceVolume, uvw + vec3(0.0, 0.0, 0.75)).rgb;
  return max(l0 + l1x * n.x + l1y * n.y + l1z * n.z, vec3(0.0));
}
#endif
#endif

// In case of OpenGLES, all shader code is glued, so this is already declared
#ifndef GL_ES
AngularInfo getAngularInfo(const in vec3 pointToLight, const in vec3 normal, const in vec3 view);
vec3 specularReflection(const in MaterialInfo materialInfo, const in AngularInfo angularInfo);
float visibilityOcclusion(const in MaterialInfo materialInfo, const in AngularInfo angularInfo);
float microfacetDistribution(const in MaterialInfo materialInfo, const in AngularInfo angularInfo);
vec3 diffuse(const in MaterialInfo materialInfo);
#endif

/* Add light contribution.
   Note: this never changes color.a.
*/
void PLUG_add_light(inout vec4 color,
  const in vec4 vertex_eye,
  const in vec3 normal_eye,
  const in MaterialInfo material_info,
  const in vec3 view)
{
#ifdef LIGHT<Light>_TYPE_ENVIRONMENT
  /* Image-based lighting: the light's textures (in its local space)
     are looked up by the world normal and reflection direction. */
  {
    vec3 env_normal = normalize((castle_LightSource<Light>EyeToLight * vec4(normal_eye, 0.0)).xyz);
    vec3 env_light = vec3(0.0);

#if defined(LIGHT<Light>_HAS_IRRADIANCE_VOLUME)
    vec3 env_position = (castle_LightSource<Light>EyeToLight * vertex_eye).xyz;
    env_light += material_info.diffuseColor *
      castle_irradiance_volume<Light>(env_position, env_normal);
#elif defined(LIGHT<Light>_HAS_DIFFUSE_TEXTURE)
    env_light += material_info.diffuseColor *
      textureCube(castle_LightSource<Light>DiffuseTexture, env_normal).rgb;
#endif

#ifdef LIGHT<Light>_HAS_SPECULAR_TEXTURE
    vec3 env_reflect = normalize((castle_LightSource<Light>EyeToLight *
      vec4(reflect(-view, normal_eye), 0.0)).xyz);
    float n_dot_v = clamp(dot(normal_eye, view), 0.0, 1.0);
    /* rougher surfaces read blurrier mipmap levels of the prefiltered map */
    float env_lod = 0.0;
#ifdef CASTLE_GLSL_VERSION_UPGRADE
    env_lod = material_info.perceptualRoughness *
      log2(float(textureSize(castle_LightSource<Light>SpecularTexture, 0).x));
#endif
    env_light +=
      castle_env_brdf_approx<Light>(material_info.specularColor,
        material_info.perceptualRoughness, n_dot_v) *
      textureCube(castle_LightSource<Light>SpecularTexture, env_reflect, env_lod).rgb;
#endif

    color.rgb += castle_LightSource<Light>Color * env_light;
    return;
  }
#else
  vec3 light_dir;

/* Calculate light_dir */
#ifdef LIGHT<Light>_TYPE_PUNCTUAL
  #ifdef LIGHT<Light>_TYPE_POSITIONAL
    light_dir = castle_LightSource<Light>Position - vec3(vertex_eye);
    float distance_to_light = length(light_dir);
    light_dir /= distance_to_light;
  #else
    light_dir = normalize(castle_LightSource<Light>Position);
  #endif
#else
  light_dir = normal_eye;
#endif

#ifdef LIGHT<Light>_TYPE_SPOT
  /* Check SpotCosCutoff first, as we want to add nothing
     (not even ambient term) when were outside of spot light cone. */

  float spot_cos = dot(normalize(castle_LightSource<Light>SpotDirection), -light_dir);
  if (spot_cos < castle_LightSource<Light>SpotCosCutoff)
    return;
#endif

  float scale = 1.0;
  /* PLUG: light_scale (scale, normal_eye, light_dir) */

  /* Like scale, but per color component: multiplies the light's color,
     for example by a colored image projected from the light. */
  vec3 color_scale = vec3(1.0);
  /* PLUG: light_color_scale (color_scale, normal_eye, light_dir) */

#ifdef LIGHT<Light>_TYPE_SPOT
#ifdef LIGHT<Light>_HAS_BEAM_WIDTH
  /* calculate spot following VRML 2.0/X3D idea of beamWidth */
  float cutOffAngle = castle_LightSource<Light>SpotCutoff;
  if (castle_LightSource<Light>BeamWidth < cutOffAngle) {
    scale *= clamp(
      (                    acos(spot_cos) - cutOffAngle) /
      (castle_LightSource<Light>BeamWidth - cutOffAngle),
      0.0, 1.0);
  }
#endif

#ifdef LIGHT<Light>_HAS_SPOT_EXPONENT
  /* calculate spot like fixed-function pipeline, using exponent */
  scale *= pow(spot_cos, castle_LightSource<Light>SpotExponent);
#endif
#endif

#ifdef LIGHT<Light>_HAS_ATTENUATION
  scale /= max(1.0,
           castle_LightSource<Light>Attenuation.x +
           castle_LightSource<Light>Attenuation.y * distance_to_light +
           castle_LightSource<Light>Attenuation.z * distance_to_light * distance_to_light);
#endif

#ifdef LIGHT<Light>_HAS_RADIUS
  #ifdef LIGHT<Light>_HAS_RADIUS_FALLOFF
  /* Smooth falloff to zero at the radius,
     the window function recommended by glTF KHR_lights_punctual for "range". */
  float radius_ratio = distance_to_light / castle_LightSource<Light>Radius;
  float radius_window = clamp(1.0 - radius_ratio * radius_ratio * radius_ratio * radius_ratio, 0.0, 1.0);
  scale *= radius_window * radius_window;
  #else
  if (distance_to_light >= castle_LightSource<Light>Radius)
    scale = 0.0;
  #endif
#endif

  /* Main code that calculates per-light-source contribution to the final color.
     Was called "getPointShade" in glTF-Sample-Viewer.

     light_dir now must be the direction from current vertex to light source.
     It is assumed to be already normalized.

     view is direction from current vertex to camera, in eye-space,
     already normalized.
     IOW, "normalize(- vertex_eye)" because camera position is zero in eye-space.
  */
  AngularInfo angularInfo = getAngularInfo(light_dir, normal_eye, view);

  if (angularInfo.NdotL > 0.0 || angularInfo.NdotV > 0.0)
  {
    // Calculate the shading terms for the microfacet specular shading model
    vec3 F = specularReflection(material_info, angularInfo);
    float Vis = visibilityOcclusion(material_info, angularInfo);
    float D = microfacetDistribution(material_info, angularInfo);

    // Calculation of analytical lighting contribution
    vec3 diffuseContrib = (1.0 - F) * diffuse(material_info);
    vec3 specContrib = F * Vis * D;

    // Obtain final intensity as reflectance (BRDF) scaled by the energy of the light (cosine law)
    vec3 light_contribution = angularInfo.NdotL * (diffuseContrib + specContrib);

    color.rgb += castle_LightSource<Light>Color *
      light_contribution *
      scale * color_scale;
  }
#endif
}
