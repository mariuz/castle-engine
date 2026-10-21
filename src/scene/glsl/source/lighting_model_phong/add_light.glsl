/*
  Copyright 2010-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------

  Shader code used for adding light source contribution for Material
  (Phong lighting model).
  This is used by both desktop OpenGL and OpenGLES.
  This is used in both Gouraud and Phong shading,
  so it may go either in vertex or fragment shader.
*/

/* Punctual (PointLight, DirectionalLight, SpotLight) parameters */
#ifdef LIGHT<Light>_TYPE_PUNCTUAL
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
#endif

#ifdef LIGHT<Light>_HAS_AMBIENT
uniform vec3 castle_LightSource<Light>AmbientColor;
#endif

uniform vec3 castle_LightSource<Light>Color;

#ifdef LIGHT<Light>_HAS_ATTENUATION
/* Attenuation: constant, linear, quadratic. */
uniform vec3 castle_LightSource<Light>Attenuation;
#endif

#ifdef LIGHT<Light>_HAS_RADIUS
uniform float castle_LightSource<Light>Radius;
#endif

/* EnvironmentLight parameters, see lighting_model_physical/add_light.glsl */
#ifdef LIGHT<Light>_TYPE_ENVIRONMENT
uniform mat4 castle_LightSource<Light>EyeToLight;
#ifdef LIGHT<Light>_HAS_DIFFUSE_TEXTURE
uniform samplerCube castle_LightSource<Light>DiffuseTexture;
#endif
#ifdef LIGHT<Light>_HAS_SPECULAR_TEXTURE
uniform samplerCube castle_LightSource<Light>SpecularTexture;
#endif
#ifdef LIGHT<Light>_HAS_IRRADIANCE_VOLUME
#ifdef GL_ES
uniform highp sampler3D castle_LightSource<Light>IrradianceVolume;
#else
uniform sampler3D castle_LightSource<Light>IrradianceVolume;
#endif
uniform vec3 castle_LightSource<Light>InfluenceMin;
uniform vec3 castle_LightSource<Light>InfluenceSize;

vec3 castle_irradiance_volume<Light>(const in vec3 p, const in vec3 n)
{
  vec3 uvw = clamp((p - castle_LightSource<Light>InfluenceMin) /
    castle_LightSource<Light>InfluenceSize, 0.0, 1.0);
#ifdef CASTLE_GLSL_VERSION_UPGRADE
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

/* Add light contribution.
   Note: this never changes color.a.
*/
void PLUG_add_light(inout vec4 color,
  const in vec4 vertex_eye,
  const in vec3 normal_eye,
  const in MaterialInfo material_info)
{
#ifdef LIGHT<Light>_TYPE_ENVIRONMENT
  /* Image-based lighting, like in lighting_model_physical/add_light.glsl,
     without roughness (the specular texture is used unblurred). */
  {
    vec3 env_normal = normalize((castle_LightSource<Light>EyeToLight * vec4(normal_eye, 0.0)).xyz);
    vec3 env_light = vec3(0.0);
#if defined(LIGHT<Light>_HAS_IRRADIANCE_VOLUME)
    vec3 env_position = (castle_LightSource<Light>EyeToLight * vertex_eye).xyz;
    env_light += material_info.diffuse_alpha.rgb *
      castle_irradiance_volume<Light>(env_position, env_normal);
#elif defined(LIGHT<Light>_HAS_DIFFUSE_TEXTURE)
    env_light += material_info.diffuse_alpha.rgb *
      textureCube(castle_LightSource<Light>DiffuseTexture, env_normal).rgb;
#endif
#if defined(LIGHT<Light>_HAS_SPECULAR_TEXTURE) && defined(LIGHT<Light>_HAS_SPECULAR)
    vec3 env_reflect = normalize((castle_LightSource<Light>EyeToLight *
      vec4(reflect(normalize(vec3(vertex_eye)), normal_eye), 0.0)).xyz);
    env_light += material_info.specular *
      textureCube(castle_LightSource<Light>SpecularTexture, env_reflect).rgb;
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

  /* add ambient term */
  vec3 light_color =
#ifdef LIGHT<Light>_HAS_AMBIENT
  castle_LightSource<Light>AmbientColor * material_info.ambient;
#else
  vec3(0.0);
#endif

  /* add diffuse term */
  vec3 diffuse = castle_LightSource<Light>Color * material_info.diffuse_alpha.rgb;

  float diffuse_factor = max(dot(normal_eye, light_dir), 0.0);
  light_color += diffuse * diffuse_factor;

#ifdef LIGHT<Light>_HAS_SPECULAR
  /* add specular term */
  /* halfVector is an average of
     - normalize(light position - vertex_eye) (we already have this
       in light_dir) and
     - normalize(camera position - vertex_eye)
       (and camera position == zero in camera space). */
  vec3 halfVector = normalize(light_dir - normalize(vec3(vertex_eye)));
  if (diffuse_factor != 0.0) {
    vec3 specular_color = castle_LightSource<Light>Color * material_info.specular;

    light_color += specular_color *
      pow(max(dot(halfVector, normal_eye), 0.0), material_info.shininess);
  }
#endif

  color.rgb += light_color * scale * color_scale;
#endif
}
