{ -*- buffer-read-only: t -*- }
{ DON'T EDIT -- this file was automatically generated from "source/lighting_model_physical/add_light.glsl" }
'/*' + LineEnding +
'  Copyright 2020-2022 Michalis Kamburelis and glTF-Sample-Viewer authors.' + LineEnding +
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
'' + LineEnding +
'  Shader code used for adding light source contribution for PhysicalMaterial' + LineEnding +
'  (PBR lighting model).' + LineEnding +
'  This is used by both desktop OpenGL and OpenGLES.' + LineEnding +
'' + LineEnding +
'  In the future this may be used in both Gouraud and Phong shading,' + LineEnding +
'  so it may go either in vertex or fragment shader.' + LineEnding +
'  For now: since PhysicalMaterial now forces Phong shading, this is only used in Phong shading.' + LineEnding +
'*/' + LineEnding +
'' + LineEnding +
'/* Light source position (or direction, if not LIGHT<Light>_TYPE_POSITIONAL)' + LineEnding +
'   in eye coordinates. */' + LineEnding +
'uniform vec3 castle_LightSource<Light>Position;' + LineEnding +
'' + LineEnding +
'/* SpotLight specific parameters */' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_SPOT' + LineEnding +
'uniform vec3 castle_LightSource<Light>SpotDirection;' + LineEnding +
'uniform float castle_LightSource<Light>SpotCosCutoff;' + LineEnding +
'#ifdef LIGHT<Light>_HAS_BEAM_WIDTH' + LineEnding +
'/* In radians. Note that this differs from gl_LightSource[<Light>].spotCutoff' + LineEnding +
'   that is in degrees. */' + LineEnding +
'uniform float castle_LightSource<Light>SpotCutoff;' + LineEnding +
'uniform float castle_LightSource<Light>BeamWidth;' + LineEnding +
'#endif' + LineEnding +
'#ifdef LIGHT<Light>_HAS_SPOT_EXPONENT' + LineEnding +
'uniform float castle_LightSource<Light>SpotExponent;' + LineEnding +
'#endif' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'uniform vec3 castle_LightSource<Light>Color;' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_ATTENUATION' + LineEnding +
'/* Attenuation: constant, linear, quadratic. */' + LineEnding +
'uniform vec3 castle_LightSource<Light>Attenuation;' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_RADIUS' + LineEnding +
'uniform float castle_LightSource<Light>Radius;' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'/* EnvironmentLight parameters */' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_ENVIRONMENT' + LineEnding +
'/* Eye space to the light''s local space (of its textures and influence box). */' + LineEnding +
'uniform mat4 castle_LightSource<Light>EyeToLight;' + LineEnding +
'#ifdef LIGHT<Light>_HAS_DIFFUSE_TEXTURE' + LineEnding +
'/* Irradiance cube map: the diffuse light for each normal direction. */' + LineEnding +
'uniform samplerCube castle_LightSource<Light>DiffuseTexture;' + LineEnding +
'#endif' + LineEnding +
'#ifdef LIGHT<Light>_HAS_SPECULAR_TEXTURE' + LineEnding +
'/* Prefiltered radiance cube map: mipmap levels for increasing roughness. */' + LineEnding +
'uniform samplerCube castle_LightSource<Light>SpecularTexture;' + LineEnding +
'#endif' + LineEnding +
'#ifdef LIGHT<Light>_HAS_IRRADIANCE_VOLUME' + LineEnding +
'/* Spherical harmonics (L0, L1x, L1y, L1z) of the irradiance in a grid' + LineEnding +
'   over the influence box, 4 slabs along Z, see EnvironmentLight.irradianceVolume. */' + LineEnding +
'#ifdef GL_ES' + LineEnding +
'uniform highp sampler3D castle_LightSource<Light>IrradianceVolume;' + LineEnding +
'#else' + LineEnding +
'uniform sampler3D castle_LightSource<Light>IrradianceVolume;' + LineEnding +
'#endif' + LineEnding +
'uniform vec3 castle_LightSource<Light>InfluenceMin;' + LineEnding +
'uniform vec3 castle_LightSource<Light>InfluenceSize;' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'/* Analytic approximation of the split-sum environment BRDF' + LineEnding +
'   (Brian Karis, "Physically Based Shading on Mobile", 2014). */' + LineEnding +
'vec3 castle_env_brdf_approx<Light>(const in vec3 specular_color,' + LineEnding +
'  const in float roughness, const in float n_dot_v)' + LineEnding +
'{' + LineEnding +
'  const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);' + LineEnding +
'  const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);' + LineEnding +
'  vec4 r = roughness * c0 + c1;' + LineEnding +
'  float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;' + LineEnding +
'  vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;' + LineEnding +
'  return specular_color * ab.x + ab.y;' + LineEnding +
'}' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_IRRADIANCE_VOLUME' + LineEnding +
'/* Irradiance for the normal n (light''s local space) at the point p' + LineEnding +
'   (light''s local space) from the irradiance volume. */' + LineEnding +
'vec3 castle_irradiance_volume<Light>(const in vec3 p, const in vec3 n)' + LineEnding +
'{' + LineEnding +
'  vec3 uvw = clamp((p - castle_LightSource<Light>InfluenceMin) /' + LineEnding +
'    castle_LightSource<Light>InfluenceSize, 0.0, 1.0);' + LineEnding +
'#ifdef CASTLE_GLSL_VERSION_UPGRADE' + LineEnding +
'  /* Keep the Z coordinate within the half texels of each slab,' + LineEnding +
'     so that linear filtering doesn''t mix the slabs. */' + LineEnding +
'  float slab_texels = float(textureSize(castle_LightSource<Light>IrradianceVolume, 0).z) / 4.0;' + LineEnding +
'  uvw.z = clamp(uvw.z, 0.5 / slab_texels, 1.0 - 0.5 / slab_texels);' + LineEnding +
'#endif' + LineEnding +
'  uvw.z /= 4.0;' + LineEnding +
'  vec3 l0  = texture3D(castle_LightSource<Light>IrradianceVolume, uvw).rgb;' + LineEnding +
'  vec3 l1x = texture3D(castle_LightSource<Light>IrradianceVolume, uvw + vec3(0.0, 0.0, 0.25)).rgb;' + LineEnding +
'  vec3 l1y = texture3D(castle_LightSource<Light>IrradianceVolume, uvw + vec3(0.0, 0.0, 0.5)).rgb;' + LineEnding +
'  vec3 l1z = texture3D(castle_LightSource<Light>IrradianceVolume, uvw + vec3(0.0, 0.0, 0.75)).rgb;' + LineEnding +
'  return max(l0 + l1x * n.x + l1y * n.y + l1z * n.z, vec3(0.0));' + LineEnding +
'}' + LineEnding +
'#endif' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'// In case of OpenGLES, all shader code is glued, so this is already declared' + LineEnding +
'#ifndef GL_ES' + LineEnding +
'AngularInfo getAngularInfo(const in vec3 pointToLight, const in vec3 normal, const in vec3 view);' + LineEnding +
'vec3 specularReflection(const in MaterialInfo materialInfo, const in AngularInfo angularInfo);' + LineEnding +
'float visibilityOcclusion(const in MaterialInfo materialInfo, const in AngularInfo angularInfo);' + LineEnding +
'float microfacetDistribution(const in MaterialInfo materialInfo, const in AngularInfo angularInfo);' + LineEnding +
'vec3 diffuse(const in MaterialInfo materialInfo);' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'/* Add light contribution.' + LineEnding +
'   Note: this never changes color.a.' + LineEnding +
'*/' + LineEnding +
'void PLUG_add_light(inout vec4 color,' + LineEnding +
'  const in vec4 vertex_eye,' + LineEnding +
'  const in vec3 normal_eye,' + LineEnding +
'  const in MaterialInfo material_info,' + LineEnding +
'  const in vec3 view)' + LineEnding +
'{' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_ENVIRONMENT' + LineEnding +
'  /* Image-based lighting: the light''s textures (in its local space)' + LineEnding +
'     are looked up by the world normal and reflection direction. */' + LineEnding +
'  {' + LineEnding +
'    vec3 env_normal = normalize((castle_LightSource<Light>EyeToLight * vec4(normal_eye, 0.0)).xyz);' + LineEnding +
'    vec3 env_light = vec3(0.0);' + LineEnding +
'' + LineEnding +
'#if defined(LIGHT<Light>_HAS_IRRADIANCE_VOLUME)' + LineEnding +
'    vec3 env_position = (castle_LightSource<Light>EyeToLight * vertex_eye).xyz;' + LineEnding +
'    env_light += material_info.diffuseColor *' + LineEnding +
'      castle_irradiance_volume<Light>(env_position, env_normal);' + LineEnding +
'#elif defined(LIGHT<Light>_HAS_DIFFUSE_TEXTURE)' + LineEnding +
'    env_light += material_info.diffuseColor *' + LineEnding +
'      textureCube(castle_LightSource<Light>DiffuseTexture, env_normal).rgb;' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_SPECULAR_TEXTURE' + LineEnding +
'    vec3 env_reflect = normalize((castle_LightSource<Light>EyeToLight *' + LineEnding +
'      vec4(reflect(-view, normal_eye), 0.0)).xyz);' + LineEnding +
'    float n_dot_v = clamp(dot(normal_eye, view), 0.0, 1.0);' + LineEnding +
'    /* rougher surfaces read blurrier mipmap levels of the prefiltered map */' + LineEnding +
'    float env_lod = 0.0;' + LineEnding +
'#ifdef CASTLE_GLSL_VERSION_UPGRADE' + LineEnding +
'    env_lod = material_info.perceptualRoughness *' + LineEnding +
'      log2(float(textureSize(castle_LightSource<Light>SpecularTexture, 0).x));' + LineEnding +
'#endif' + LineEnding +
'    env_light +=' + LineEnding +
'      castle_env_brdf_approx<Light>(material_info.specularColor,' + LineEnding +
'        material_info.perceptualRoughness, n_dot_v) *' + LineEnding +
'      textureCube(castle_LightSource<Light>SpecularTexture, env_reflect, env_lod).rgb;' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'    color.rgb += castle_LightSource<Light>Color * env_light;' + LineEnding +
'    return;' + LineEnding +
'  }' + LineEnding +
'#else' + LineEnding +
'  vec3 light_dir;' + LineEnding +
'' + LineEnding +
'/* Calculate light_dir */' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_PUNCTUAL' + LineEnding +
'  #ifdef LIGHT<Light>_TYPE_POSITIONAL' + LineEnding +
'    light_dir = castle_LightSource<Light>Position - vec3(vertex_eye);' + LineEnding +
'    float distance_to_light = length(light_dir);' + LineEnding +
'    light_dir /= distance_to_light;' + LineEnding +
'  #else' + LineEnding +
'    light_dir = normalize(castle_LightSource<Light>Position);' + LineEnding +
'  #endif' + LineEnding +
'#else' + LineEnding +
'  light_dir = normal_eye;' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_SPOT' + LineEnding +
'  /* Check SpotCosCutoff first, as we want to add nothing' + LineEnding +
'     (not even ambient term) when were outside of spot light cone. */' + LineEnding +
'' + LineEnding +
'  float spot_cos = dot(normalize(castle_LightSource<Light>SpotDirection), -light_dir);' + LineEnding +
'  if (spot_cos < castle_LightSource<Light>SpotCosCutoff)' + LineEnding +
'    return;' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'  float scale = 1.0;' + LineEnding +
'  /* PLUG: light_scale (scale, normal_eye, light_dir) */' + LineEnding +
'' + LineEnding +
'  /* Like scale, but per color component: multiplies the light''s color,' + LineEnding +
'     for example by a colored image projected from the light. */' + LineEnding +
'  vec3 color_scale = vec3(1.0);' + LineEnding +
'  /* PLUG: light_color_scale (color_scale, normal_eye, light_dir) */' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_SPOT' + LineEnding +
'#ifdef LIGHT<Light>_HAS_BEAM_WIDTH' + LineEnding +
'  /* calculate spot following VRML 2.0/X3D idea of beamWidth */' + LineEnding +
'  float cutOffAngle = castle_LightSource<Light>SpotCutoff;' + LineEnding +
'  if (castle_LightSource<Light>BeamWidth < cutOffAngle) {' + LineEnding +
'    scale *= clamp(' + LineEnding +
'      (                    acos(spot_cos) - cutOffAngle) /' + LineEnding +
'      (castle_LightSource<Light>BeamWidth - cutOffAngle),' + LineEnding +
'      0.0, 1.0);' + LineEnding +
'  }' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_SPOT_EXPONENT' + LineEnding +
'  /* calculate spot like fixed-function pipeline, using exponent */' + LineEnding +
'  scale *= pow(spot_cos, castle_LightSource<Light>SpotExponent);' + LineEnding +
'#endif' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_ATTENUATION' + LineEnding +
'  scale /= max(1.0,' + LineEnding +
'           castle_LightSource<Light>Attenuation.x +' + LineEnding +
'           castle_LightSource<Light>Attenuation.y * distance_to_light +' + LineEnding +
'           castle_LightSource<Light>Attenuation.z * distance_to_light * distance_to_light);' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_RADIUS' + LineEnding +
'  #ifdef LIGHT<Light>_HAS_RADIUS_FALLOFF' + LineEnding +
'  /* Smooth falloff to zero at the radius,' + LineEnding +
'     the window function recommended by glTF KHR_lights_punctual for "range". */' + LineEnding +
'  float radius_ratio = distance_to_light / castle_LightSource<Light>Radius;' + LineEnding +
'  float radius_window = clamp(1.0 - radius_ratio * radius_ratio * radius_ratio * radius_ratio, 0.0, 1.0);' + LineEnding +
'  scale *= radius_window * radius_window;' + LineEnding +
'  #else' + LineEnding +
'  if (distance_to_light >= castle_LightSource<Light>Radius)' + LineEnding +
'    scale = 0.0;' + LineEnding +
'  #endif' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'  /* Main code that calculates per-light-source contribution to the final color.' + LineEnding +
'     Was called "getPointShade" in glTF-Sample-Viewer.' + LineEnding +
'' + LineEnding +
'     light_dir now must be the direction from current vertex to light source.' + LineEnding +
'     It is assumed to be already normalized.' + LineEnding +
'' + LineEnding +
'     view is direction from current vertex to camera, in eye-space,' + LineEnding +
'     already normalized.' + LineEnding +
'     IOW, "normalize(- vertex_eye)" because camera position is zero in eye-space.' + LineEnding +
'  */' + LineEnding +
'  AngularInfo angularInfo = getAngularInfo(light_dir, normal_eye, view);' + LineEnding +
'' + LineEnding +
'  if (angularInfo.NdotL > 0.0 || angularInfo.NdotV > 0.0)' + LineEnding +
'  {' + LineEnding +
'    // Calculate the shading terms for the microfacet specular shading model' + LineEnding +
'    vec3 F = specularReflection(material_info, angularInfo);' + LineEnding +
'    float Vis = visibilityOcclusion(material_info, angularInfo);' + LineEnding +
'    float D = microfacetDistribution(material_info, angularInfo);' + LineEnding +
'' + LineEnding +
'    // Calculation of analytical lighting contribution' + LineEnding +
'    vec3 diffuseContrib = (1.0 - F) * diffuse(material_info);' + LineEnding +
'    vec3 specContrib = F * Vis * D;' + LineEnding +
'' + LineEnding +
'    // Obtain final intensity as reflectance (BRDF) scaled by the energy of the light (cosine law)' + LineEnding +
'    vec3 light_contribution = angularInfo.NdotL * (diffuseContrib + specContrib);' + LineEnding +
'' + LineEnding +
'    color.rgb += castle_LightSource<Light>Color *' + LineEnding +
'      light_contribution *' + LineEnding +
'      scale * color_scale;' + LineEnding +
'  }' + LineEnding +
'#endif' + LineEnding +
'}' + LineEnding +
''
