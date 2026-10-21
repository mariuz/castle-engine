{ -*- buffer-read-only: t -*- }
{ DON'T EDIT -- this file was automatically generated from "source/lighting_model_phong/add_light.glsl" }
'/*' + LineEnding +
'  Copyright 2010-2022 Michalis Kamburelis.' + LineEnding +
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
'  Shader code used for adding light source contribution for Material' + LineEnding +
'  (Phong lighting model).' + LineEnding +
'  This is used by both desktop OpenGL and OpenGLES.' + LineEnding +
'  This is used in both Gouraud and Phong shading,' + LineEnding +
'  so it may go either in vertex or fragment shader.' + LineEnding +
'*/' + LineEnding +
'' + LineEnding +
'/* Punctual (PointLight, DirectionalLight, SpotLight) parameters */' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_PUNCTUAL' + LineEnding +
'  /* Light source position (or direction, if not LIGHT<Light>_TYPE_POSITIONAL)' + LineEnding +
'     in eye coordinates. */' + LineEnding +
'  uniform vec3 castle_LightSource<Light>Position;' + LineEnding +
'' + LineEnding +
'  /* SpotLight specific parameters */' + LineEnding +
'  #ifdef LIGHT<Light>_TYPE_SPOT' + LineEnding +
'    uniform vec3 castle_LightSource<Light>SpotDirection;' + LineEnding +
'    uniform float castle_LightSource<Light>SpotCosCutoff;' + LineEnding +
'    #ifdef LIGHT<Light>_HAS_BEAM_WIDTH' + LineEnding +
'      /* In radians. Note that this differs from gl_LightSource[<Light>].spotCutoff' + LineEnding +
'         that is in degrees. */' + LineEnding +
'      uniform float castle_LightSource<Light>SpotCutoff;' + LineEnding +
'      uniform float castle_LightSource<Light>BeamWidth;' + LineEnding +
'    #endif' + LineEnding +
'    #ifdef LIGHT<Light>_HAS_SPOT_EXPONENT' + LineEnding +
'      uniform float castle_LightSource<Light>SpotExponent;' + LineEnding +
'    #endif' + LineEnding +
'  #endif' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_AMBIENT' + LineEnding +
'uniform vec3 castle_LightSource<Light>AmbientColor;' + LineEnding +
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
'/* EnvironmentLight parameters, see lighting_model_physical/add_light.glsl */' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_ENVIRONMENT' + LineEnding +
'uniform mat4 castle_LightSource<Light>EyeToLight;' + LineEnding +
'#ifdef LIGHT<Light>_HAS_DIFFUSE_TEXTURE' + LineEnding +
'uniform samplerCube castle_LightSource<Light>DiffuseTexture;' + LineEnding +
'#endif' + LineEnding +
'#ifdef LIGHT<Light>_HAS_SPECULAR_TEXTURE' + LineEnding +
'uniform samplerCube castle_LightSource<Light>SpecularTexture;' + LineEnding +
'#endif' + LineEnding +
'#ifdef LIGHT<Light>_HAS_IRRADIANCE_VOLUME' + LineEnding +
'#ifdef GL_ES' + LineEnding +
'uniform highp sampler3D castle_LightSource<Light>IrradianceVolume;' + LineEnding +
'#else' + LineEnding +
'uniform sampler3D castle_LightSource<Light>IrradianceVolume;' + LineEnding +
'#endif' + LineEnding +
'uniform vec3 castle_LightSource<Light>InfluenceMin;' + LineEnding +
'uniform vec3 castle_LightSource<Light>InfluenceSize;' + LineEnding +
'' + LineEnding +
'vec3 castle_irradiance_volume<Light>(const in vec3 p, const in vec3 n)' + LineEnding +
'{' + LineEnding +
'  vec3 uvw = clamp((p - castle_LightSource<Light>InfluenceMin) /' + LineEnding +
'    castle_LightSource<Light>InfluenceSize, 0.0, 1.0);' + LineEnding +
'#ifdef CASTLE_GLSL_VERSION_UPGRADE' + LineEnding +
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
'/* Add light contribution.' + LineEnding +
'   Note: this never changes color.a.' + LineEnding +
'*/' + LineEnding +
'void PLUG_add_light(inout vec4 color,' + LineEnding +
'  const in vec4 vertex_eye,' + LineEnding +
'  const in vec3 normal_eye,' + LineEnding +
'  const in MaterialInfo material_info)' + LineEnding +
'{' + LineEnding +
'#ifdef LIGHT<Light>_TYPE_ENVIRONMENT' + LineEnding +
'  /* Image-based lighting, like in lighting_model_physical/add_light.glsl,' + LineEnding +
'     without roughness (the specular texture is used unblurred). */' + LineEnding +
'  {' + LineEnding +
'    vec3 env_normal = normalize((castle_LightSource<Light>EyeToLight * vec4(normal_eye, 0.0)).xyz);' + LineEnding +
'    vec3 env_light = vec3(0.0);' + LineEnding +
'#if defined(LIGHT<Light>_HAS_IRRADIANCE_VOLUME)' + LineEnding +
'    vec3 env_position = (castle_LightSource<Light>EyeToLight * vertex_eye).xyz;' + LineEnding +
'    env_light += material_info.diffuse_alpha.rgb *' + LineEnding +
'      castle_irradiance_volume<Light>(env_position, env_normal);' + LineEnding +
'#elif defined(LIGHT<Light>_HAS_DIFFUSE_TEXTURE)' + LineEnding +
'    env_light += material_info.diffuse_alpha.rgb *' + LineEnding +
'      textureCube(castle_LightSource<Light>DiffuseTexture, env_normal).rgb;' + LineEnding +
'#endif' + LineEnding +
'#if defined(LIGHT<Light>_HAS_SPECULAR_TEXTURE) && defined(LIGHT<Light>_HAS_SPECULAR)' + LineEnding +
'    vec3 env_reflect = normalize((castle_LightSource<Light>EyeToLight *' + LineEnding +
'      vec4(reflect(normalize(vec3(vertex_eye)), normal_eye), 0.0)).xyz);' + LineEnding +
'    env_light += material_info.specular *' + LineEnding +
'      textureCube(castle_LightSource<Light>SpecularTexture, env_reflect).rgb;' + LineEnding +
'#endif' + LineEnding +
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
'  /* add ambient term */' + LineEnding +
'  vec3 light_color =' + LineEnding +
'#ifdef LIGHT<Light>_HAS_AMBIENT' + LineEnding +
'  castle_LightSource<Light>AmbientColor * material_info.ambient;' + LineEnding +
'#else' + LineEnding +
'  vec3(0.0);' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'  /* add diffuse term */' + LineEnding +
'  vec3 diffuse = castle_LightSource<Light>Color * material_info.diffuse_alpha.rgb;' + LineEnding +
'' + LineEnding +
'  float diffuse_factor = max(dot(normal_eye, light_dir), 0.0);' + LineEnding +
'  light_color += diffuse * diffuse_factor;' + LineEnding +
'' + LineEnding +
'#ifdef LIGHT<Light>_HAS_SPECULAR' + LineEnding +
'  /* add specular term */' + LineEnding +
'  /* halfVector is an average of' + LineEnding +
'     - normalize(light position - vertex_eye) (we already have this' + LineEnding +
'       in light_dir) and' + LineEnding +
'     - normalize(camera position - vertex_eye)' + LineEnding +
'       (and camera position == zero in camera space). */' + LineEnding +
'  vec3 halfVector = normalize(light_dir - normalize(vec3(vertex_eye)));' + LineEnding +
'  if (diffuse_factor != 0.0) {' + LineEnding +
'    vec3 specular_color = castle_LightSource<Light>Color * material_info.specular;' + LineEnding +
'' + LineEnding +
'    light_color += specular_color *' + LineEnding +
'      pow(max(dot(halfVector, normal_eye), 0.0), material_info.shininess);' + LineEnding +
'  }' + LineEnding +
'#endif' + LineEnding +
'' + LineEnding +
'  color.rgb += light_color * scale * color_scale;' + LineEnding +
'#endif' + LineEnding +
'}' + LineEnding +
''
