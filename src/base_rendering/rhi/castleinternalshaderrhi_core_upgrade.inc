{%MainUnit castleinternalshaderrhi.pas}
{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{$ifdef read_implementation}
const
  NL = LineEnding;

{ TCastleLightsUniformBlock }

procedure TCastleLightsUniformBlock.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

function TCastleLightsUniformBlock.AddLightInternal(const APos, AColor, ASpotDir,
  ASpotParams, AAtten, AAmbient: TVector4): Integer;
begin
  if Count >= CASTLE_MAX_LIGHTS then Exit(-1);
  Result := Count;
  Lights[Result].Position := APos;
  Lights[Result].Color := AColor;
  Lights[Result].SpotDirection := ASpotDir;
  Lights[Result].SpotParams := ASpotParams;
  Lights[Result].Attenuation := AAtten;
  Lights[Result].AmbientColor := AAmbient;
  Lights[Result].ProjectorMatrix := TMatrix4.Identity;
  Inc(Count);
end;

function TCastleLightsUniformBlock.AddDirectionalLight(const Direction, Color,
  AmbientColor: TVector3): Integer;
begin
  Result := AddLightInternal(Vector4(Direction, 0.0), Vector4(Color, 0.0),
    Vector4(0, 0, -1, -1.0), Vector4(0, 0, 0, 0), Vector4(1, 0, 0, 0), Vector4(AmbientColor, 1.0));
end;

function TCastleLightsUniformBlock.AddPointLight(const Position, Color,
  AmbientColor: TVector3; const Attenuation: TVector3; const Radius: Single): Integer;
begin
  Result := AddLightInternal(Vector4(Position, 1.0), Vector4(Color, Radius),
    Vector4(0, 0, -1, -1.0), Vector4(0, 0, 0, 0), Vector4(Attenuation, 0.0), Vector4(AmbientColor, 1.0));
end;

function TCastleLightsUniformBlock.AddSpotLight(const Position, Direction, Color,
  AmbientColor: TVector3; const Attenuation: TVector3; const Radius, SpotCosCutoff,
  SpotCutoff, BeamWidth, SpotExponent: Single): Integer;
begin
  Result := AddLightInternal(Vector4(Position, 2.0), Vector4(Color, Radius),
    Vector4(Direction, SpotCosCutoff), Vector4(SpotCutoff, BeamWidth, SpotExponent, 0.0),
    Vector4(Attenuation, 0.0), Vector4(AmbientColor, 1.0));
end;

procedure TCastleLightsUniformBlock.SetProjectorMatrix(const Index: Integer;
  const Matrix: TMatrix4; const AShadowSlotIndex: Integer);
begin
  if (Index >= 0) and (Index < Integer(Count)) then
  begin
    Lights[Index].ProjectorMatrix := Matrix;
    Lights[Index].SpotParams.W := Single(EnsureRange(AShadowSlotIndex, 0, 3) + 1);
  end;
end;

{ TCastleMaterialUniformBlock }

procedure TCastleMaterialUniformBlock.InitDefaultPBR;
begin
  BaseColor := Vector4(1.0, 1.0, 1.0, 1.0);
  SpecularColor := Vector4(0.04, 0.04, 0.04, 0.0); // a = 0.0 -> PBR Metallic-Roughness
  EmissiveColor := Vector4(0.0, 0.0, 0.0, 0.0);    // a = 0.0 -> Metallic = 0
  PBRParams := Vector4(1.0, 1.0, 1.0, 0.0);        // Roughness=1, NormalScale=1, OcclusionStrength=1, AlphaCutoff=0
end;

procedure TCastleMaterialUniformBlock.InitDefaultPhong;
begin
  BaseColor := Vector4(0.8, 0.8, 0.8, 1.0);
  SpecularColor := Vector4(0.0, 0.0, 0.0, 25.6);   // a > 0.0 -> Phong shininess (0.2 * 128)
  EmissiveColor := Vector4(0.0, 0.0, 0.0, 0.0);
  PBRParams := Vector4(0.5, 1.0, 1.0, 0.0);
end;

procedure TCastleMaterialUniformBlock.InitDefaultUnlit;
begin
  BaseColor := Vector4(1.0, 1.0, 1.0, 1.0);
  SpecularColor := Vector4(0.0, 0.0, 0.0, -1.0);   // a < 0.0 -> Unlit shading model
  EmissiveColor := Vector4(0.0, 0.0, 0.0, 0.0);
  PBRParams := Vector4(1.0, 1.0, 1.0, 0.0);
end;

{ TCastleShaderGeneratorRHI }

constructor TCastleShaderGeneratorRHI.Create(const ABackend: TRHIBackendType);
begin
  inherited Create;
  FBackend := ABackend;
end;

function TCastleShaderGeneratorRHI.GenerateVersionAndLayoutMacros: String;
begin
  Result := GenerateVersionAndLayoutMacrosForStage(ssVertex);
end;

function TCastleShaderGeneratorRHI.GenerateVersionAndLayoutMacrosForStage(
  const AStage: TRHIShaderStage): String;

  function BuildOpenGLSlotMacros: String;
  var
    S, B: Integer;
  begin
    Result := '';
    for S := 0 to 3 do
      for B := 0 to 7 do
        Result := Result + Format('#define CASTLE_GL_SLOT_%d_%d %d', [S, B, S * 8 + B]) + NL;
    Result := Result +
      '#define CASTLE_GL_BIND2(SetIdx, BindIdx) CASTLE_GL_SLOT_ ## SetIdx ## _ ## BindIdx' + NL +
      '#define CASTLE_GL_BIND(SetIdx, BindIdx) CASTLE_GL_BIND2(SetIdx, BindIdx)' + NL;
  end;

begin
  case FBackend of
    rbVulkan:
      begin
        Result :=
          '#version 450' + NL;
        if AStage = ssFragment then
          Result := Result +
            'precision highp float;' + NL +
            'precision highp int;' + NL;
        Result := Result +
          '#define CASTLE_VULKAN 1' + NL +
          '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140, set = SetIdx, binding = BindIdx)' + NL +
          '#define CASTLE_SSBO(SetIdx, BindIdx) layout(std430, set = SetIdx, binding = BindIdx)' + NL +
          '#define CASTLE_SAMPLER(SetIdx, BindIdx) layout(set = SetIdx, binding = BindIdx)' + NL +
          '#define CASTLE_DESCRIPTOR_SET(SetIdx, BindIdx) layout(set = SetIdx, binding = BindIdx)' + NL +
          '#define CASTLE_IMAGE(SetIdx, BindIdx, ImgFmt) layout(ImgFmt, set = SetIdx, binding = BindIdx)' + NL +
          '#define CASTLE_PUSH_CONSTANT layout(push_constant)' + NL +
          '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
          '#define CASTLE_VERTEX_INDEX gl_VertexIndex' + NL +
          '#define CASTLE_INSTANCE_INDEX gl_InstanceIndex' + NL;
      end;

    rbOpenGL:
      begin
        if AStage = ssCompute then
          Result := '#version 430 core' + NL
        else
          Result :=
            '#version 330 core' + NL +
            '#extension GL_ARB_separate_shader_objects : enable' + NL +
            '#extension GL_ARB_shading_language_420pack : enable' + NL +
            '#extension GL_ARB_explicit_attrib_location : enable' + NL +
            '#extension GL_ARB_shader_storage_buffer_object : enable' + NL +
            '#extension GL_ARB_shader_image_load_store : enable' + NL;
        Result := Result +
          '#define CASTLE_OPENGL 1' + NL +
          BuildOpenGLSlotMacros +
          { Flattens (SetIdx, BindIdx) to literal integer slot SetIdx * 8 + BindIdx }
          '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140, binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
          '#define CASTLE_SSBO(SetIdx, BindIdx) layout(std430, binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
          '#define CASTLE_SAMPLER(SetIdx, BindIdx) layout(binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
          '#define CASTLE_DESCRIPTOR_SET(SetIdx, BindIdx) layout(binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
          '#define CASTLE_IMAGE(SetIdx, BindIdx, ImgFmt) layout(ImgFmt, binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
          { Maps Push Constants to reserved UBO slot 24 in OpenGL }
          '#define CASTLE_PUSH_CONSTANT layout(std140, binding = 24)' + NL +
          '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
          '#define CASTLE_VERTEX_INDEX gl_VertexID' + NL +
          '#define CASTLE_INSTANCE_INDEX gl_InstanceID' + NL;
      end;

    rbOpenGLES:
      begin
        if AStage = ssCompute then
          Result :=
            '#version 310 es' + NL +
            'precision highp float;' + NL +
            'precision highp int;' + NL +
            '#define CASTLE_OPENGLES 1' + NL +
            BuildOpenGLSlotMacros +
            '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140, binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
            '#define CASTLE_SSBO(SetIdx, BindIdx) layout(std430, binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
            '#define CASTLE_SAMPLER(SetIdx, BindIdx) layout(binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
            '#define CASTLE_DESCRIPTOR_SET(SetIdx, BindIdx) layout(binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
            '#define CASTLE_IMAGE(SetIdx, BindIdx, ImgFmt) layout(ImgFmt, binding = CASTLE_GL_BIND(SetIdx, BindIdx))' + NL +
            '#define CASTLE_PUSH_CONSTANT layout(std140, binding = 24)' + NL +
            '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
            '#define CASTLE_VERTEX_INDEX gl_VertexID' + NL +
            '#define CASTLE_INSTANCE_INDEX gl_InstanceID' + NL
        else
          Result :=
            '#version 300 es' + NL +
            'precision highp float;' + NL +
            'precision highp int;' + NL +
            '#define CASTLE_OPENGLES 1' + NL +
            '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140)' + NL +
            '#define CASTLE_SSBO(SetIdx, BindIdx) layout(std430)' + NL +
            '#define CASTLE_SAMPLER(SetIdx, BindIdx)' + NL +
            '#define CASTLE_DESCRIPTOR_SET(SetIdx, BindIdx)' + NL +
            '#define CASTLE_IMAGE(SetIdx, BindIdx, ImgFmt) layout(ImgFmt)' + NL +
            '#define CASTLE_PUSH_CONSTANT layout(std140)' + NL +
            '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
            '#define CASTLE_VERTEX_INDEX gl_VertexID' + NL +
            '#define CASTLE_INSTANCE_INDEX gl_InstanceID' + NL;
      end;
  end;
end;

function TCastleShaderGeneratorRHI.GenerateStandardUniformBlocks(
  const AStage: TRHIShaderStage): String;
begin
  Result := GenerateStandardUniformBlocksForStage(AStage, True);
end;

function TCastleShaderGeneratorRHI.GenerateStandardUniformBlocksForStage(
  const AStage: TRHIShaderStage;
  const AIncludeSkinningUBO: Boolean): String;
var
  LightAliases, SkinningSection: String;
  I: Integer;
begin
  LightAliases := '';
  for I := 0 to CASTLE_MAX_LIGHTS - 1 do
  begin
    LightAliases := LightAliases +
      Format('#define castle_LightSource%dPosition CastleLights.u_Lights[%d].Position.xyz', [I, I]) + NL +
      Format('#define castle_LightSource%dColor CastleLights.u_Lights[%d].Color.rgb', [I, I]) + NL +
      Format('#define castle_LightSource%dRadius CastleLights.u_Lights[%d].Color.w', [I, I]) + NL +
      Format('#define castle_LightSource%dSpotDirection CastleLights.u_Lights[%d].SpotDirection.xyz', [I, I]) + NL +
      Format('#define castle_LightSource%dSpotCosCutoff CastleLights.u_Lights[%d].SpotDirection.w', [I, I]) + NL +
      Format('#define castle_LightSource%dSpotCutoff CastleLights.u_Lights[%d].SpotParams.x', [I, I]) + NL +
      Format('#define castle_LightSource%dBeamWidth CastleLights.u_Lights[%d].SpotParams.y', [I, I]) + NL +
      Format('#define castle_LightSource%dSpotExponent CastleLights.u_Lights[%d].SpotParams.z', [I, I]) + NL +
      Format('#define castle_LightSource%dAttenuation CastleLights.u_Lights[%d].Attenuation.xyz', [I, I]) + NL +
      Format('#define castle_LightSource%dAmbientColor CastleLights.u_Lights[%d].AmbientColor.rgb', [I, I]) + NL +
      Format('#define castle_projector_matrix_%d CastleLights.u_Lights[%d].ProjectorMatrix', [I, I]) + NL;
  end;

  if AIncludeSkinningUBO then
    SkinningSection :=
      '/* --- Set 2: Per-Object / Skinning Uniforms --- */' + NL +
      'CASTLE_UBO(2, 0) uniform CastleSkinningBlock {' + NL +
      '  mat4 u_JointMatrices[256];' + NL +
      '  uint u_JointCount;' + NL +
      '} CastleSkinning;' + NL +
      NL +
      '#define castle_JointMatrix CastleSkinning.u_JointMatrices' + NL +
      NL
  else
    SkinningSection := '';

  Result :=
    '/* --- Set 0, Binding 0: Global / Per-Pass Uniforms --- */' + NL +
    'CASTLE_UBO(0, 0) uniform CastleSceneBlock {' + NL +
    '  mat4 u_ProjectionMatrix;' + NL +
    '  mat4 u_ViewMatrix;' + NL +
    '  mat4 u_ViewMatrixInverse;' + NL +
    '  vec4 u_CameraPosition;' + NL +
    '  vec4 u_FogColor;' + NL +
    '  vec4 u_FogParams;' + NL +
    '  uint u_LightCount;' + NL +
    '} CastleScene;' + NL +
    NL +
    '/* Legacy CGE uniform aliases for Set 0 */' + NL +
    '#define castle_ProjectionMatrix CastleScene.u_ProjectionMatrix' + NL +
    '#define castle_ViewMatrix CastleScene.u_ViewMatrix' + NL +
    '#define castle_ViewMatrixInverse CastleScene.u_ViewMatrixInverse' + NL +
    '#define castle_CameraMatrix CastleScene.u_ViewMatrix' + NL +
    '#define castle_CameraInverseMatrix CastleScene.u_ViewMatrixInverse' + NL +
    '#define castle_CameraRotationMatrix mat3(CastleScene.u_ViewMatrix)' + NL +
    '#define castle_CameraRotationInverseMatrix mat3(CastleScene.u_ViewMatrixInverse)' + NL +
    '#define castle_WorldEyePosition CastleScene.u_CameraPosition.xyz' + NL +
    '#define castle_SceneTime CastleScene.u_CameraPosition.w' + NL +
    NL +
    '/* --- Set 0, Binding 1: Multi-Light Uniform Block --- */' + NL +
    'struct CastleLightData {' + NL +
    '  vec4 Position;' + NL +
    '  vec4 Color;' + NL +
    '  vec4 SpotDirection;' + NL +
    '  vec4 SpotParams;' + NL +
    '  vec4 Attenuation;' + NL +
    '  vec4 AmbientColor;' + NL +
    '  mat4 ProjectorMatrix;' + NL +
    '};' + NL +
    NL +
    'CASTLE_UBO(0, 1) uniform CastleLightsBlock {' + NL +
    '  uint u_LightCount;' + NL +
    '  uint u_Pad0;' + NL +
    '  uint u_Pad1;' + NL +
    '  uint u_Pad2;' + NL +
    '  CastleLightData u_Lights[32];' + NL +
    '} CastleLights;' + NL +
    NL +
    '#define castle_LightCount CastleLights.u_LightCount' + NL +
    LightAliases + NL +
    '/* --- Set 0, Bindings 2..5: Shadow Map Samplers --- */' + NL +
    'CASTLE_SAMPLER(0, 2) uniform sampler2DShadow castle_shadow_map_0;' + NL +
    'CASTLE_SAMPLER(0, 3) uniform sampler2DShadow castle_shadow_map_1;' + NL +
    'CASTLE_SAMPLER(0, 4) uniform sampler2DShadow castle_shadow_map_2;' + NL +
    'CASTLE_SAMPLER(0, 5) uniform sampler2DShadow castle_shadow_map_3;' + NL +
    NL +
    '/* --- Set 1: Per-Material Uniforms & Samplers --- */' + NL +
    'CASTLE_UBO(1, 0) uniform CastleMaterialBlock {' + NL +
    '  vec4 u_BaseColor;' + NL +
    '  vec4 u_SpecularColor;' + NL +
    '  vec4 u_EmissiveColor;' + NL +
    '  vec4 u_PBRParams;' + NL +
    '} CastleMaterial;' + NL +
    NL +
    '/* Legacy CGE uniform aliases for Set 1 */' + NL +
    '#define castle_MaterialDiffuseAlpha CastleMaterial.u_BaseColor' + NL +
    '#define castle_MaterialBaseColor CastleMaterial.u_BaseColor' + NL +
    '#define castle_MaterialSpecular CastleMaterial.u_SpecularColor.rgb' + NL +
    '#define castle_MaterialShininess CastleMaterial.u_SpecularColor.a' + NL +
    '#define castle_MaterialEmissive CastleMaterial.u_EmissiveColor.rgb' + NL +
    '#define castle_MaterialMetallic CastleMaterial.u_EmissiveColor.a' + NL +
    '#define castle_MaterialRoughness CastleMaterial.u_PBRParams.x' + NL +
    '#define castle_MaterialNormalScale CastleMaterial.u_PBRParams.y' + NL +
    '#define castle_MaterialOcclusionStrength CastleMaterial.u_PBRParams.z' + NL +
    '#define castle_AlphaCutoff CastleMaterial.u_PBRParams.w' + NL +
    NL +
    'CASTLE_SAMPLER(1, 1) uniform sampler2D castle_base_color_texture;' + NL +
    'CASTLE_SAMPLER(1, 2) uniform sampler2D castle_normal_texture;' + NL +
    'CASTLE_SAMPLER(1, 3) uniform sampler2D castle_metallic_roughness_texture;' + NL +
    'CASTLE_SAMPLER(1, 4) uniform sampler2D castle_emissive_texture;' + NL +
    'CASTLE_SAMPLER(1, 5) uniform sampler2D castle_occlusion_texture;' + NL +
    'CASTLE_SAMPLER(1, 6) uniform sampler2D castle_brdf_lut_texture;' + NL +
    'CASTLE_SAMPLER(1, 7) uniform samplerCube castle_env_specular_texture;' + NL +
    NL +
    SkinningSection +
    '/* --- Push Constants: Per-Draw Matrices --- */' + NL +
    'CASTLE_PUSH_CONSTANT uniform CastlePushConstants {' + NL +
    '  mat4 u_ModelViewMatrix;' + NL +
    '  vec4 u_NormalMatrixRow0;' + NL +
    '  vec4 u_NormalMatrixRow1;' + NL +
    '  vec4 u_NormalMatrixRow2;' + NL +
    '  vec4 u_ObjectParams;' + NL +
    '} CastleDraw;' + NL +
    NL +
    '#define castle_ModelViewMatrix CastleDraw.u_ModelViewMatrix' + NL +
    '#define castle_NormalMatrix mat3(CastleDraw.u_NormalMatrixRow0.xyz, CastleDraw.u_NormalMatrixRow1.xyz, CastleDraw.u_NormalMatrixRow2.xyz)' + NL +
    '#define castle_ObjectParams CastleDraw.u_ObjectParams' + NL +
    '#define castle_ObjectMaterialIndex uint(CastleDraw.u_ObjectParams.x + 0.5)' + NL +
    '#define castle_ObjectSkinningMode int(CastleDraw.u_ObjectParams.y + 0.5)' + NL +
    '#define castle_ObjectSpecularAAEnabled (CastleDraw.u_ObjectParams.z > 0.5)' + NL +
    '#define castle_ObjectShadowMapMode int(CastleDraw.u_ObjectParams.w + 0.5)' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateStageIO(const AStage: TRHIShaderStage): String;
begin
  case AStage of
    ssVertex:
      Result :=
        '/* --- Standard Vertex Attributes (Locations 0..7) --- */' + NL +
        'CASTLE_LOCATION(0) in vec4 castle_Vertex;' + NL +
        'CASTLE_LOCATION(1) in vec3 castle_Normal;' + NL +
        'CASTLE_LOCATION(2) in vec2 castle_MultiTexCoord0;' + NL +
        'CASTLE_LOCATION(3) in vec2 castle_MultiTexCoord1;' + NL +
        'CASTLE_LOCATION(4) in vec4 castle_ColorPerVertex;' + NL +
        'CASTLE_LOCATION(5) in vec4 castle_Tangent;' + NL +
        'CASTLE_LOCATION(6) in vec4 castle_Joints0;' + NL +
        'CASTLE_LOCATION(7) in vec4 castle_Weights0;' + NL +
        NL +
        '/* --- Vertex-to-Fragment Varyings --- */' + NL +
        'CASTLE_LOCATION(0) out vec4 castle_vertex_eye;' + NL +
        'CASTLE_LOCATION(1) out vec3 castle_normal_eye;' + NL +
        'CASTLE_LOCATION(2) out vec2 castle_tex_coord0;' + NL +
        'CASTLE_LOCATION(3) out vec2 castle_tex_coord1;' + NL +
        'CASTLE_LOCATION(4) out vec4 castle_color_per_vertex;' + NL +
        'CASTLE_LOCATION(5) out mat3 castle_tangent_to_eye_space;' + NL +
        '#define castle_TexCoord0 vec4(castle_tex_coord0, 0.0, 1.0)' + NL +
        '#define castle_TexCoord1 vec4(castle_tex_coord1, 0.0, 1.0)' + NL;

    ssFragment:
      Result :=
        '/* --- Fragment Inputs (Must match Vertex Outputs by Location) --- */' + NL +
        'CASTLE_LOCATION(0) in vec4 castle_vertex_eye;' + NL +
        'CASTLE_LOCATION(1) in vec3 castle_normal_eye;' + NL +
        'CASTLE_LOCATION(2) in vec2 castle_tex_coord0;' + NL +
        'CASTLE_LOCATION(3) in vec2 castle_tex_coord1;' + NL +
        'CASTLE_LOCATION(4) in vec4 castle_color_per_vertex;' + NL +
        'CASTLE_LOCATION(5) in mat3 castle_tangent_to_eye_space;' + NL +
        '#define castle_TexCoord0 vec4(castle_tex_coord0, 0.0, 1.0)' + NL +
        '#define castle_TexCoord1 vec4(castle_tex_coord1, 0.0, 1.0)' + NL +
        '#define castle_ColorPerVertex castle_color_per_vertex' + NL +
        NL +
        '/* --- CGE Color-Space Helper Functions (terrain.fs & Effect shaders) --- */' + NL +
        'vec4 castle_texture_color_to_linear(const in vec4 srgbIn) {' + NL +
        '#ifdef CASTLE_GAMMA_CORRECTION' + NL +
        '  return vec4(pow(max(srgbIn.rgb, vec3(0.0)), vec3(2.2)), srgbIn.a);' + NL +
        '#else' + NL +
        '  return srgbIn;' + NL +
        '#endif' + NL +
        '}' + NL +
        'vec3 castle_texture_color_to_linear(const in vec3 srgbIn) {' + NL +
        '#ifdef CASTLE_GAMMA_CORRECTION' + NL +
        '  return pow(max(srgbIn, vec3(0.0)), vec3(2.2));' + NL +
        '#else' + NL +
        '  return srgbIn;' + NL +
        '#endif' + NL +
        '}' + NL +
        'vec3 castle_linear_to_screen(const in vec3 linearIn) {' + NL +
        '#ifdef CASTLE_GAMMA_CORRECTION' + NL +
        '  return pow(max(linearIn, vec3(0.0)), vec3(1.0 / 2.2));' + NL +
        '#else' + NL +
        '  return linearIn;' + NL +
        '#endif' + NL +
        '}' + NL +
        NL +
        '/* --- Fragment Color Output --- */' + NL +
        'CASTLE_LOCATION(0) out vec4 castle_FragColor;' + NL;

    ssGeometry:
      Result :=
        '/* --- Geometry Inputs (Must match Vertex Outputs by Location) --- */' + NL +
        '#define CASTLE_GEOMETRY_INPUT_SIZE gl_in.length()' + NL +
        'CASTLE_LOCATION(0) in vec4 castle_vertex_eye[];' + NL +
        'CASTLE_LOCATION(1) in vec3 castle_normal_eye[];' + NL +
        'CASTLE_LOCATION(2) in vec2 castle_tex_coord0[];' + NL +
        'CASTLE_LOCATION(3) in vec2 castle_tex_coord1[];' + NL +
        'CASTLE_LOCATION(4) in vec4 castle_color_per_vertex[];' + NL +
        'CASTLE_LOCATION(5) in mat3 castle_tangent_to_eye_space[];' + NL +
        '#define castle_TexCoord0 castle_tex_coord0' + NL +
        '#define castle_TexCoord1 castle_tex_coord1' + NL +
        '#define castle_ColorPerVertex castle_color_per_vertex' + NL +
        NL +
        '/* --- Geometry Outputs (Must match Fragment Inputs by Location) --- */' + NL +
        'CASTLE_LOCATION(0) out vec4 castle_vertex_eye_geoshader;' + NL +
        'CASTLE_LOCATION(1) out vec3 castle_normal_eye_geoshader;' + NL +
        'CASTLE_LOCATION(2) out vec2 castle_tex_coord0_geoshader;' + NL +
        'CASTLE_LOCATION(3) out vec2 castle_tex_coord1_geoshader;' + NL +
        'CASTLE_LOCATION(4) out vec4 castle_color_per_vertex_geoshader;' + NL +
        'CASTLE_LOCATION(5) out mat3 castle_tangent_to_eye_space_geoshader;' + NL +
        '#define castle_TexCoord0_geoshader castle_tex_coord0_geoshader' + NL +
        '#define castle_TexCoord1_geoshader castle_tex_coord1_geoshader' + NL +
        '#define castle_ColorPerVertex_geoshader castle_color_per_vertex_geoshader' + NL +
        NL +
        '/* --- Geometry Shader Helper Forward Declarations --- */' + NL +
        'void geometryVertexSet(const int index);' + NL +
        'void geometryVertexZero();' + NL +
        'void geometryVertexAdd(const int index, const float scale);' + NL;
  else
    Result := '';
  end;
end;

function TCastleShaderGeneratorRHI.GeneratePreamble(const AStage: TRHIShaderStage): String;
begin
  if AStage = ssCompute then
    Result := GenerateVersionAndLayoutMacrosForStage(ssCompute) + NL
  else
    Result :=
      GenerateVersionAndLayoutMacrosForStage(AStage) + NL +
      GenerateStandardUniformBlocks(AStage) + NL +
      GenerateStageIO(AStage) + NL;
end;

function TCastleShaderGeneratorRHI.GeneratePreambleFor3DVertex(
  const AHasSkinning, AHasTangents, AHasTexCoord1, AHasColorPerVertex: Boolean): String;
var
  AttrIO: String;
begin
  AttrIO :=
    '/* --- Active Standard Vertex Attributes --- */' + NL +
    'CASTLE_LOCATION(0) in vec4 castle_Vertex;' + NL +
    'CASTLE_LOCATION(1) in vec3 castle_Normal;' + NL +
    'CASTLE_LOCATION(2) in vec2 castle_MultiTexCoord0;' + NL;

  if AHasTexCoord1 then
    AttrIO := AttrIO + 'CASTLE_LOCATION(3) in vec2 castle_MultiTexCoord1;' + NL
  else
    AttrIO := AttrIO + '#define castle_MultiTexCoord1 (castle_MultiTexCoord0.xy)' + NL;

  if AHasColorPerVertex then
    AttrIO := AttrIO + 'CASTLE_LOCATION(4) in vec4 castle_ColorPerVertex;' + NL
  else
    AttrIO := AttrIO + '#define castle_ColorPerVertex vec4(1.0)' + NL;

  if AHasTangents then
    AttrIO := AttrIO + 'CASTLE_LOCATION(5) in vec4 castle_Tangent;' + NL
  else
    AttrIO := AttrIO + '#define castle_Tangent vec4(1.0, 0.0, 0.0, 1.0)' + NL;

  if AHasSkinning then
    AttrIO := AttrIO +
      'CASTLE_LOCATION(6) in vec4 castle_Joints0;' + NL +
      'CASTLE_LOCATION(7) in vec4 castle_Weights0;' + NL;

  AttrIO := AttrIO + NL +
    '/* --- Vertex-to-Fragment Varyings --- */' + NL +
    'CASTLE_LOCATION(0) out vec4 castle_vertex_eye;' + NL +
    'CASTLE_LOCATION(1) out vec3 castle_normal_eye;' + NL +
    'CASTLE_LOCATION(2) out vec2 castle_tex_coord0;' + NL +
    'CASTLE_LOCATION(3) out vec2 castle_tex_coord1;' + NL +
    'CASTLE_LOCATION(4) out vec4 castle_color_per_vertex;' + NL +
    'CASTLE_LOCATION(5) out mat3 castle_tangent_to_eye_space;' + NL +
    '#define castle_TexCoord0 vec4(castle_tex_coord0, 0.0, 1.0)' + NL +
    '#define castle_TexCoord1 vec4(castle_tex_coord1, 0.0, 1.0)' + NL;

  Result :=
    GenerateVersionAndLayoutMacrosForStage(ssVertex) + NL +
    GenerateStandardUniformBlocksForStage(ssVertex, AHasSkinning) + NL +
    AttrIO + NL;
end;

function TCastleShaderGeneratorRHI.GenerateComputePreamble(const ALocalSizeX,
  ALocalSizeY, ALocalSizeZ: Cardinal): String;
begin
  Result :=
    GenerateVersionAndLayoutMacrosForStage(ssCompute) + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = %d) in;',
      [Max(Cardinal(1), ALocalSizeX),
       Max(Cardinal(1), ALocalSizeY),
       Max(Cardinal(1), ALocalSizeZ)]) + NL;
end;

function TCastleShaderGeneratorRHI.GenerateBindlessPreamble(const AStage: TRHIShaderStage;
  const AMaxBindlessTextures: Cardinal): String;
var
  ArrayDecl: String;
begin
  if FBackend <> rbVulkan then
    Exit(GeneratePreamble(AStage));

  if AMaxBindlessTextures > 0 then
    ArrayDecl := Format('CASTLE_SAMPLER(1, 0) uniform sampler2D castle_BindlessTextures[%d];', [AMaxBindlessTextures])
  else
    ArrayDecl := 'CASTLE_SAMPLER(1, 0) uniform sampler2D castle_BindlessTextures[];';

  Result :=
    GenerateVersionAndLayoutMacros +
    '#extension GL_EXT_nonuniform_qualifier : require' + NL +
    '#define CASTLE_BINDLESS_TEXTURES 1' + NL +
    NL +
    GenerateStandardUniformBlocks(AStage) + NL +
    '/* --- Bindless Texture Table & Multi-Material SSBO (VK_EXT_descriptor_indexing) --- */' + NL +
    ArrayDecl + NL +
    NL +
    'struct CastleBindlessMaterialEntry {' + NL +
    '  vec4 BaseColor;' + NL +
    '  vec4 SpecularColor;' + NL +
    '  vec4 EmissiveColor;' + NL +
    '  vec4 PBRParams;' + NL +
    '  uint BaseColorTexIndex;' + NL +
    '  uint NormalTexIndex;' + NL +
    '  uint MetallicRoughnessTexIndex;' + NL +
    '  uint EmissiveTexIndex;' + NL +
    '};' + NL +
    NL +
    'CASTLE_SSBO(1, 1) readonly buffer CastleBindlessMaterialsBlock {' + NL +
    '  CastleBindlessMaterialEntry u_Materials[];' + NL +
    '} CastleBindlessMaterials;' + NL +
    NL +
    '#define castle_SampleBindless2D(TexIdx, UV) texture(castle_BindlessTextures[nonuniformEXT(uint(TexIdx))], (UV))' + NL +
    '#define castle_GetMaterialEntry(MatIdx) CastleBindlessMaterials.u_Materials[uint(MatIdx)]' + NL +
    '#define castle_DrawMaterialIndex uint(CastleDraw.u_ObjectParams.x)' + NL +
    NL +
    GenerateStageIO(AStage) + NL;
end;

function IsGLSLIdentChar(const C: Char): Boolean; inline;
begin
  Result := (C in ['a'..'z', 'A'..'Z', '0'..'9', '_']);
end;

function ContainsGLSLIdentifier(const Source, Ident: String): Boolean;
var
  StartPos, MatchPos, EndIdx, IdentLen, SrcLen: Integer;
begin
  Result := False;
  IdentLen := Length(Ident);
  SrcLen := Length(Source);
  if (IdentLen = 0) or (SrcLen < IdentLen) then Exit;

  StartPos := 1;
  while StartPos <= SrcLen - IdentLen + 1 do
  begin
    MatchPos := PosEx(Ident, Source, StartPos);
    if MatchPos = 0 then Exit(False);

    EndIdx := MatchPos + IdentLen;
    if ((MatchPos = 1) or not IsGLSLIdentChar(Source[MatchPos - 1])) and
       ((EndIdx > SrcLen) or not IsGLSLIdentChar(Source[EndIdx])) then
      Exit(True);

    StartPos := MatchPos + 1;
  end;
end;

function TCastleShaderGeneratorRHI.UpgradeLegacyGLSLBuiltIns(
  const UserEffectSource: String; const EffectDebugName: String): String;
var
  UnusedWarningsCount: Cardinal;
begin
  Result := UpgradeLegacyGLSLBuiltIns(UserEffectSource, EffectDebugName, UnusedWarningsCount);
end;

function TCastleShaderGeneratorRHI.UpgradeLegacyGLSLBuiltIns(
  const UserEffectSource: String; const EffectDebugName: String;
  out AWarningsCount: Cardinal): String;
type
  TLegacyBuiltInMapping = record
    LegacySymbol: String;
    ReplacementExpr: String;
    Description: String;
  end;
const
  LegacyBuiltIns: array[0..11] of TLegacyBuiltInMapping = (
    (LegacySymbol: 'gl_ModelViewProjectionMatrix';
     ReplacementExpr: '(castle_ProjectionMatrix * castle_ModelViewMatrix)';
     Description: 'deprecated OpenGL built-in matrix uniform'),
    (LegacySymbol: 'gl_ModelViewMatrix';
     ReplacementExpr: 'castle_ModelViewMatrix';
     Description: 'deprecated OpenGL built-in matrix uniform'),
    (LegacySymbol: 'gl_ProjectionMatrix';
     ReplacementExpr: 'castle_ProjectionMatrix';
     Description: 'deprecated OpenGL built-in matrix uniform'),
    (LegacySymbol: 'gl_NormalMatrix';
     ReplacementExpr: 'castle_NormalMatrix';
     Description: 'deprecated OpenGL built-in normal matrix uniform'),
    (LegacySymbol: 'gl_Vertex';
     ReplacementExpr: 'castle_Vertex';
     Description: 'deprecated OpenGL built-in vertex attribute'),
    (LegacySymbol: 'gl_Normal';
     ReplacementExpr: 'castle_Normal';
     Description: 'deprecated OpenGL built-in normal attribute'),
    (LegacySymbol: 'gl_MultiTexCoord0';
     ReplacementExpr: 'vec4(castle_MultiTexCoord0, 0.0, 1.0)';
     Description: 'deprecated OpenGL built-in texture coordinate attribute'),
    (LegacySymbol: 'gl_MultiTexCoord1';
     ReplacementExpr: 'vec4(castle_MultiTexCoord1, 0.0, 1.0)';
     Description: 'deprecated OpenGL built-in texture coordinate attribute'),
    (LegacySymbol: 'gl_Color';
     ReplacementExpr: 'castle_ColorPerVertex';
     Description: 'deprecated OpenGL built-in vertex color attribute'),
    (LegacySymbol: 'gl_FragColor';
     ReplacementExpr: 'castle_FragColor';
     Description: 'deprecated OpenGL built-in fragment output variable'),
    (LegacySymbol: 'texture2D';
     ReplacementExpr: 'texture';
     Description: 'deprecated GLSL 1.20 texture lookup function'),
    (LegacySymbol: 'textureCube';
     ReplacementExpr: 'texture';
     Description: 'deprecated GLSL 1.20 cube texture lookup function')
  );
var
  CompatDefines, UpgradedLines: TStringBuilder;
  Lines: TStringList;
  Line, Trimmed: String;
  I: Integer;
begin
  AWarningsCount := 0;
  if FBackend <> rbVulkan then
    Exit(UserEffectSource);

  CompatDefines := TStringBuilder.Create;
  UpgradedLines := TStringBuilder.Create;
  Lines := TStringList.Create;
  try
    for I := Low(LegacyBuiltIns) to High(LegacyBuiltIns) do
    begin
      if ContainsGLSLIdentifier(UserEffectSource, LegacyBuiltIns[I].LegacySymbol) then
      begin
        Inc(AWarningsCount);
        WritelnWarning('Shader', Format(
          'Custom shader "%s" uses %s "%s" which is removed in Vulkan GLSL #version 450. ' +
          'Auto-upgrading to "%s"; please update your Effect shader to use Castle Game Engine equivalents.',
          [EffectDebugName, LegacyBuiltIns[I].Description,
           LegacyBuiltIns[I].LegacySymbol, LegacyBuiltIns[I].ReplacementExpr]));
        CompatDefines.AppendLine(Format('#ifndef %s', [LegacyBuiltIns[I].LegacySymbol]));
        CompatDefines.AppendLine(Format('#define %s %s',
          [LegacyBuiltIns[I].LegacySymbol, LegacyBuiltIns[I].ReplacementExpr]));
        CompatDefines.AppendLine('#endif');
      end;
    end;

    if ContainsGLSLIdentifier(UserEffectSource, 'gl_PositionIn') then
    begin
      Inc(AWarningsCount);
      WritelnWarning('Shader', Format(
        'Custom shader "%s" uses deprecated GLSL 1.50 geometry input "gl_PositionIn" which is removed in Vulkan GLSL #version 450. ' +
        'Auto-upgrading to "gl_in[...].gl_Position".',
        [EffectDebugName]));
    end;

    Lines.Text := UserEffectSource;
    for Line in Lines do
    begin
      Trimmed := Trim(Line);
      while Pos('gl_PositionIn[', Trimmed) > 0 do
      begin
        I := Pos('gl_PositionIn[', Trimmed);
        Trimmed := Copy(Trimmed, 1, I - 1) + 'gl_in[' +
          StringReplace(Copy(Trimmed, I + Length('gl_PositionIn['), MaxInt), ']', '].gl_Position', []);
      end;
      if Pos('[CASTLE_GEOMETRY_INPUT_SIZE]', Trimmed) > 0 then
        Trimmed := StringReplace(Trimmed, '[CASTLE_GEOMETRY_INPUT_SIZE]', '[]', [rfReplaceAll]);
      if IsPrefix('attribute ', Trimmed, False) then
      begin
        Inc(AWarningsCount);
        WritelnWarning('Shader', Format(
          'Custom shader "%s" uses deprecated GLSL qualifier "attribute" ("%s") which is removed in #version 450. ' +
          'Auto-upgrading to "in".',
          [EffectDebugName, Trimmed]));
        UpgradedLines.AppendLine('in ' + Trim(SEnding(Trimmed, Length('attribute ') + 1)));
      end else
      if IsPrefix('varying in ', Trimmed, False) then
      begin
        Inc(AWarningsCount);
        WritelnWarning('Shader', Format(
          'Custom shader "%s" uses deprecated GLSL qualifier "varying in" ("%s") which is removed in #version 450. ' +
          'Auto-upgrading to "in".',
          [EffectDebugName, Trimmed]));
        UpgradedLines.AppendLine('in ' + Trim(SEnding(Trimmed, Length('varying in ') + 1)));
      end else
      if IsPrefix('varying out ', Trimmed, False) then
      begin
        Inc(AWarningsCount);
        WritelnWarning('Shader', Format(
          'Custom shader "%s" uses deprecated GLSL qualifier "varying out" ("%s") which is removed in #version 450. ' +
          'Auto-upgrading to "out".',
          [EffectDebugName, Trimmed]));
        UpgradedLines.AppendLine('out ' + Trim(SEnding(Trimmed, Length('varying out ') + 1)));
      end else
      if IsPrefix('varying ', Trimmed, False) then
      begin
        Inc(AWarningsCount);
        WritelnWarning('Shader', Format(
          'Custom shader "%s" uses deprecated GLSL qualifier "varying" ("%s") which is removed in #version 450. ' +
          'Auto-upgrading to "in".',
          [EffectDebugName, Trimmed]));
        UpgradedLines.AppendLine('in ' + Trim(SEnding(Trimmed, Length('varying ') + 1)));
      end else
      if Trimmed <> Trim(Line) then
        UpgradedLines.AppendLine(Trimmed)
      else
        UpgradedLines.AppendLine(Line);
    end;

    if CompatDefines.Length > 0 then
      Result :=
        '/* --- Auto-Generated #version 450 Legacy OpenGL Compatibility Aliases --- */' + NL +
        CompatDefines.ToString + NL +
        UpgradedLines.ToString
    else
      Result := UpgradedLines.ToString;
  finally
    FreeAndNil(Lines);
    FreeAndNil(UpgradedLines);
    FreeAndNil(CompatDefines);
  end;
end;

function TCastleShaderGeneratorRHI.UpgradeUserEffectUniforms(
  const UserEffectSource: String): String;
const
  PrecisionQualifiers: array[0..2] of String = ('lowp ', 'mediump ', 'highp ');
var
  Lines: TStringList;
  UBOMembers, AliasDefines, StrippedBody: TStringBuilder;
  UpgradedInput, Line, Trimmed, DeclBody, VarType, VarName, BaseName, Qual: String;
  SpacePos, SemiPos, BracketPos, CustomSamplerSlot: Integer;
begin
  if FBackend <> rbVulkan then
    Exit(UserEffectSource);

  UpgradedInput := SanitizeVulkanShaderSource(UpgradeLegacyGLSLBuiltIns(UserEffectSource, 'Effect'));

  Lines := TStringList.Create;
  UBOMembers := TStringBuilder.Create;
  AliasDefines := TStringBuilder.Create;
  StrippedBody := TStringBuilder.Create;
  try
    Lines.Text := UpgradedInput;
    CustomSamplerSlot := 2;

    for Line in Lines do
    begin
      Trimmed := Trim(Line);
      if IsPrefix('uniform ', Trimmed, False) and (Pos('{', Trimmed) = 0) then
      begin
        DeclBody := Trim(SEnding(Trimmed, Length('uniform ') + 1));
        SemiPos := Pos(';', DeclBody);
        if SemiPos > 0 then
          DeclBody := Copy(DeclBody, 1, SemiPos - 1);

        for Qual in PrecisionQualifiers do
          if IsPrefix(Qual, DeclBody, False) then
          begin
            DeclBody := Trim(SEnding(DeclBody, Length(Qual) + 1));
            Break;
          end;

        SpacePos := Pos(' ', DeclBody);
        if SpacePos > 0 then
        begin
          VarType := Trim(Copy(DeclBody, 1, SpacePos - 1));
          VarName := Trim(Copy(DeclBody, SpacePos + 1, MaxInt));

          if IsPrefix('sampler', VarType, False) then
          begin
            StrippedBody.AppendLine(Format('CASTLE_SAMPLER(2, %d) uniform %s %s;',
              [CustomSamplerSlot, VarType, VarName]));
            Inc(CustomSamplerSlot);
          end else
          begin
            BracketPos := Pos('[', VarName);
            if BracketPos > 0 then
              BaseName := Trim(Copy(VarName, 1, BracketPos - 1))
            else
              BaseName := VarName;
            UBOMembers.AppendLine(Format('  %s u_user_%s;', [VarType, VarName]));
            AliasDefines.AppendLine(Format('#undef %s', [BaseName]));
            AliasDefines.AppendLine(Format('#define %s CastleUserEffect.u_user_%s',
              [BaseName, BaseName]));
          end;
        end;
      end else
        StrippedBody.AppendLine(Line);
    end;

    if UBOMembers.Length > 0 then
      Result :=
        '/* --- Auto-Generated Set 2 UBO for User X3D Effect Node --- */' + NL +
        'CASTLE_UBO(2, 1) uniform CastleUserEffectBlock {' + NL +
        UBOMembers.ToString +
        '} CastleUserEffect;' + NL +
        AliasDefines.ToString + NL +
        StrippedBody.ToString
    else
      Result := StrippedBody.ToString;
  finally
    FreeAndNil(StrippedBody);
    FreeAndNil(AliasDefines);
    FreeAndNil(UBOMembers);
    FreeAndNil(Lines);
  end;
end;

function TUserEffectShaderLayout.FindUniform(const AName: String;
  out ADesc: TUserEffectUniformDesc): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Uniforms) do
    if Uniforms[I].Name = AName then
    begin
      ADesc := Uniforms[I];
      Exit(True);
    end;
  FillChar(ADesc, SizeOf(ADesc), 0);
  Result := False;
end;

function TUserEffectShaderLayout.FindSampler(const AName: String;
  out ADesc: TUserEffectSamplerDesc): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Samplers) do
    if Samplers[I].Name = AName then
    begin
      ADesc := Samplers[I];
      Exit(True);
    end;
  FillChar(ADesc, SizeOf(ADesc), 0);
  Result := False;
end;

function TUserEffectShaderLayout.FindVarying(const AName: String;
  out ADesc: TUserEffectVaryingDesc): Boolean;
var
  I: Integer;
  LookupName: String;
begin
  LookupName := AName;
  for I := 0 to High(Varyings) do
    if Varyings[I].Name = LookupName then
    begin
      ADesc := Varyings[I];
      Exit(True);
    end;
  if IsSuffix('_geoshader', LookupName, False) then
  begin
    LookupName := Copy(LookupName, 1, Length(LookupName) - Length('_geoshader'));
    for I := 0 to High(Varyings) do
      if Varyings[I].Name = LookupName then
      begin
        ADesc := Varyings[I];
        Exit(True);
      end;
  end;
  FillChar(ADesc, SizeOf(ADesc), 0);
  Result := False;
end;

function IsBuiltInCastleVaryingName(const AName: String): Boolean;
const
  BuiltInVaryings: array[0..17] of String = (
    'castle_vertex_eye',
    'castle_normal_eye',
    'castle_tex_coord0',
    'castle_tex_coord1',
    'castle_TexCoord0',
    'castle_TexCoord1',
    'castle_color_per_vertex',
    'castle_ColorPerVertex',
    'castle_tangent_to_eye_space',
    'castle_fog_frag_coord',
    'castle_tex_coord0_4d',
    'castle_FragColor',
    'castle_vertex_eye_geoshader',
    'castle_normal_eye_geoshader',
    'castle_tex_coord0_geoshader',
    'castle_tex_coord1_geoshader',
    'castle_color_per_vertex_geoshader',
    'castle_tangent_to_eye_space_geoshader'
  );
var
  S: String;
begin
  for S in BuiltInVaryings do
    if S = AName then
      Exit(True);
  Result := False;
end;

function IsBuiltInScreenEffectSamplerName(const AName: String): Boolean;
begin
  Result := (AName = 'screen') or (AName = 'screen_depth');
end;

function IsBuiltInCastleVertexAttrName(const AName: String): Boolean;
const
  BuiltInAttrs: array[0..12] of String = (
    'castle_Vertex',
    'castle_Normal',
    'castle_MultiTexCoord0',
    'castle_MultiTexCoord1',
    'castle_ColorPerVertex',
    'castle_Tangent',
    'castle_Joints0',
    'castle_Weights0',
    'castle_SkinJoints0',
    'castle_SkinWeights0',
    'castle_FogCoord',
    'vertex',
    'tex_coord'
  );
var
  S: String;
begin
  for S in BuiltInAttrs do
    if S = AName then
      Exit(True);
  Result := False;
end;

procedure ComputeStd140TypeLayout(const AGLSLType: String;
  const AArrayCount: Cardinal; out ABaseAlign, AByteSize: PtrUInt);
begin
  if AArrayCount > 0 then
  begin
    ABaseAlign := 16;
    if AGLSLType = 'mat4' then
      AByteSize := PtrUInt(AArrayCount) * 64
    else if AGLSLType = 'mat3' then
      AByteSize := PtrUInt(AArrayCount) * 48
    else if AGLSLType = 'mat2' then
      AByteSize := PtrUInt(AArrayCount) * 32
    else
      AByteSize := PtrUInt(AArrayCount) * 16;
    Exit;
  end;

  if (AGLSLType = 'float') or (AGLSLType = 'int') or
     (AGLSLType = 'uint') or (AGLSLType = 'bool') then
  begin
    ABaseAlign := 4;
    AByteSize := 4;
  end else
  if (AGLSLType = 'vec2') or (AGLSLType = 'ivec2') or
     (AGLSLType = 'uvec2') or (AGLSLType = 'bvec2') then
  begin
    ABaseAlign := 8;
    AByteSize := 8;
  end else
  if (AGLSLType = 'vec3') or (AGLSLType = 'ivec3') or
     (AGLSLType = 'uvec3') or (AGLSLType = 'bvec3') then
  begin
    ABaseAlign := 16;
    AByteSize := 12;
  end else
  if (AGLSLType = 'vec4') or (AGLSLType = 'ivec4') or
     (AGLSLType = 'uvec4') or (AGLSLType = 'bvec4') then
  begin
    ABaseAlign := 16;
    AByteSize := 16;
  end else
  if AGLSLType = 'mat2' then
  begin
    ABaseAlign := 16;
    AByteSize := 32;
  end else
  if AGLSLType = 'mat3' then
  begin
    ABaseAlign := 16;
    AByteSize := 48;
  end else
  if AGLSLType = 'mat4' then
  begin
    ABaseAlign := 16;
    AByteSize := 64;
  end else
  begin
    ABaseAlign := 16;
    AByteSize := 16;
  end;
end;

function ComputeVaryingLocationSlots(const AGLSLType: String): Cardinal;
begin
  if AGLSLType = 'mat4' then
    Result := 4
  else if AGLSLType = 'mat3' then
    Result := 3
  else if AGLSLType = 'mat2' then
    Result := 2
  else
    Result := 1;
end;

function StripGLSLLineCommentAndTrackState(const ALine: String;
  var AInBlockComment: Boolean; var ABraceDepth: Integer): String;
var
  I, Len: Integer;
  C, NextC: Char;
  InSingleLineComment: Boolean;
  SB: TStringBuilder;
begin
  Len := Length(ALine);
  if Len = 0 then Exit('');
  SB := TStringBuilder.Create(Len);
  try
    I := 1;
    InSingleLineComment := False;
    while I <= Len do
    begin
      C := ALine[I];
      if I < Len then NextC := ALine[I + 1] else NextC := #0;
      if AInBlockComment then
      begin
        if (C = '*') and (NextC = '/') then
        begin
          AInBlockComment := False;
          Inc(I, 2);
          Continue;
        end;
        Inc(I);
        Continue;
      end;
      if InSingleLineComment then
        Break;
      if (C = '/') and (NextC = '*') then
      begin
        AInBlockComment := True;
        Inc(I, 2);
        Continue;
      end;
      if (C = '/') and (NextC = '/') then
        Break;
      if C = '{' then
        Inc(ABraceDepth)
      else if (C = '}') and (ABraceDepth > 0) then
        Dec(ABraceDepth);
      SB.Append(C);
      Inc(I);
    end;
    Result := Trim(SB.ToString);
  finally
    FreeAndNil(SB);
  end;
end;

procedure StripGLSLStorageAndPrecisionQualifiers(var ADeclBody: String;
  out AInterpQual: String);
var
  Changed: Boolean;
begin
  AInterpQual := '';
  repeat
    Changed := False;
    ADeclBody := Trim(ADeclBody);
    if IsPrefix('centroid ', ADeclBody, False) then
    begin
      ADeclBody := Trim(SEnding(ADeclBody, Length('centroid ') + 1));
      Changed := True;
    end else
    if IsPrefix('flat ', ADeclBody, False) then
    begin
      AInterpQual := 'flat ';
      ADeclBody := Trim(SEnding(ADeclBody, Length('flat ') + 1));
      Changed := True;
    end else
    if IsPrefix('noperspective ', ADeclBody, False) then
    begin
      AInterpQual := 'noperspective ';
      ADeclBody := Trim(SEnding(ADeclBody, Length('noperspective ') + 1));
      Changed := True;
    end else
    if IsPrefix('smooth ', ADeclBody, False) then
    begin
      AInterpQual := '';
      ADeclBody := Trim(SEnding(ADeclBody, Length('smooth ') + 1));
      Changed := True;
    end else
    if IsPrefix('lowp ', ADeclBody, False) then
    begin
      ADeclBody := Trim(SEnding(ADeclBody, Length('lowp ') + 1));
      Changed := True;
    end else
    if IsPrefix('mediump ', ADeclBody, False) then
    begin
      ADeclBody := Trim(SEnding(ADeclBody, Length('mediump ') + 1));
      Changed := True;
    end else
    if IsPrefix('highp ', ADeclBody, False) then
    begin
      ADeclBody := Trim(SEnding(ADeclBody, Length('highp ') + 1));
      Changed := True;
    end;
  until not Changed;
end;

function TryMatchVaryingDeclarationPrefix(const ATrimmed: String;
  const AStage: TRHIShaderStage; out ADeclBody: String;
  out AExplicitDir: String): Boolean;
begin
  Result := False;
  ADeclBody := '';
  AExplicitDir := '';
  if (Pos('(', ATrimmed) > 0) or (Pos('{', ATrimmed) > 0) or
     (Pos(';', ATrimmed) = 0) or IsPrefix('#', ATrimmed, False) then
    Exit;

  if IsPrefix('varying in ', ATrimmed, False) then
  begin
    ADeclBody := Trim(SEnding(ATrimmed, Length('varying in ') + 1));
    AExplicitDir := 'in';
    Exit(True);
  end;
  if IsPrefix('varying out ', ATrimmed, False) then
  begin
    ADeclBody := Trim(SEnding(ATrimmed, Length('varying out ') + 1));
    AExplicitDir := 'out';
    Exit(True);
  end;
  if IsPrefix('varying ', ATrimmed, False) then
  begin
    ADeclBody := Trim(SEnding(ATrimmed, Length('varying ') + 1));
    Exit(True);
  end;
  if IsPrefix('flat out ', ATrimmed, False) or IsPrefix('noperspective out ', ATrimmed, False) or
     IsPrefix('smooth out ', ATrimmed, False) or
     ((AStage in [ssVertex, ssGeometry]) and IsPrefix('out ', ATrimmed, False)) then
  begin
    if IsPrefix('out ', ATrimmed, False) then
      ADeclBody := Trim(SEnding(ATrimmed, Length('out ') + 1))
    else if IsPrefix('flat out ', ATrimmed, False) then
      ADeclBody := 'flat ' + Trim(SEnding(ATrimmed, Length('flat out ') + 1))
    else if IsPrefix('noperspective out ', ATrimmed, False) then
      ADeclBody := 'noperspective ' + Trim(SEnding(ATrimmed, Length('noperspective out ') + 1))
    else
      ADeclBody := Trim(SEnding(ATrimmed, Length('smooth out ') + 1));
    AExplicitDir := 'out';
    Exit(True);
  end;
  if IsPrefix('flat in ', ATrimmed, False) or IsPrefix('noperspective in ', ATrimmed, False) or
     IsPrefix('smooth in ', ATrimmed, False) or
     ((AStage in [ssFragment, ssGeometry]) and IsPrefix('in ', ATrimmed, False)) then
  begin
    if IsPrefix('in ', ATrimmed, False) then
      ADeclBody := Trim(SEnding(ATrimmed, Length('in ') + 1))
    else if IsPrefix('flat in ', ATrimmed, False) then
      ADeclBody := 'flat ' + Trim(SEnding(ATrimmed, Length('flat in ') + 1))
    else if IsPrefix('noperspective in ', ATrimmed, False) then
      ADeclBody := 'noperspective ' + Trim(SEnding(ATrimmed, Length('noperspective in ') + 1))
    else
      ADeclBody := Trim(SEnding(ATrimmed, Length('smooth in ') + 1));
    AExplicitDir := 'in';
    Exit(True);
  end;
end;

function TCastleShaderGeneratorRHI.ExtractUserEffectLayout(
  const AVertSource, AFragSource: String;
  const AGeomSource: String;
  const AFirstVaryingLocation: Cardinal): TUserEffectShaderLayout;
var
  UBOCursor: PtrUInt;
  NextVaryingLoc: Cardinal;

  procedure ScanStage(const AStage: TRHIShaderStage; const ASource: String);
  var
    Sanitized, Line, CleanLine, DeclBody, ExplicitDir, InterpQual, VarType,
      Declarators, OneDecl, BaseName, SuffixStr, CountStr: String;
    Lines: TStringList;
    InBlockComment: Boolean;
    BraceDepth, DepthBefore, SemiPos, SpacePos, CommaPos, BracketPos, EndBracketPos: Integer;
    ArrCount: Cardinal;
    BaseAlign, ByteSize: PtrUInt;
    ExistingUniform: TUserEffectUniformDesc;
    ExistingSampler: TUserEffectSamplerDesc;
    ExistingVarying: TUserEffectVaryingDesc;
    NewIdx: Integer;
  begin
    if Trim(ASource) = '' then Exit;
    Sanitized := SanitizeVulkanShaderSource(ASource);
    Lines := TStringList.Create;
    try
      Lines.Text := Sanitized;
      InBlockComment := False;
      BraceDepth := 0;
      for Line in Lines do
      begin
        DepthBefore := BraceDepth;
        CleanLine := StripGLSLLineCommentAndTrackState(Line, InBlockComment, BraceDepth);
        if (CleanLine = '') or (DepthBefore <> 0) then
          Continue;

        if IsPrefix('uniform ', CleanLine, False) and (Pos('{', CleanLine) = 0) and
           (Pos('(', CleanLine) = 0) then
        begin
          DeclBody := Trim(SEnding(CleanLine, Length('uniform ') + 1));
          SemiPos := Pos(';', DeclBody);
          if SemiPos > 0 then
            DeclBody := Trim(Copy(DeclBody, 1, SemiPos - 1));
          StripGLSLStorageAndPrecisionQualifiers(DeclBody, InterpQual);
          SpacePos := Pos(' ', DeclBody);
          if SpacePos > 0 then
          begin
            VarType := Trim(Copy(DeclBody, 1, SpacePos - 1));
            Declarators := Trim(Copy(DeclBody, SpacePos + 1, MaxInt));
            while Declarators <> '' do
            begin
              CommaPos := Pos(',', Declarators);
              if CommaPos > 0 then
              begin
                OneDecl := Trim(Copy(Declarators, 1, CommaPos - 1));
                Declarators := Trim(Copy(Declarators, CommaPos + 1, MaxInt));
              end else
              begin
                OneDecl := Trim(Declarators);
                Declarators := '';
              end;
              if OneDecl = '' then Continue;
              BracketPos := Pos('[', OneDecl);
              ArrCount := 0;
              SuffixStr := '';
              if BracketPos > 0 then
              begin
                BaseName := Trim(Copy(OneDecl, 1, BracketPos - 1));
                SuffixStr := Trim(Copy(OneDecl, BracketPos, MaxInt));
                EndBracketPos := Pos(']', SuffixStr);
                if EndBracketPos > 1 then
                begin
                  CountStr := Trim(Copy(SuffixStr, 2, EndBracketPos - 2));
                  ArrCount := Max(1, StrToIntDef(CountStr, 1));
                end else
                  ArrCount := 1;
              end else
                BaseName := OneDecl;

              if (BaseName = '') or IsBuiltInScreenEffectSamplerName(BaseName) then
                Continue;

              if IsPrefix('sampler', VarType, False) then
              begin
                if (not Result.FindSampler(BaseName, ExistingSampler)) and
                   (Length(Result.Samplers) < CASTLE_MAX_USER_EFFECT_SAMPLERS) then
                begin
                  NewIdx := Length(Result.Samplers);
                  SetLength(Result.Samplers, NewIdx + 1);
                  Result.Samplers[NewIdx].Name := BaseName;
                  Result.Samplers[NewIdx].GLSLType := VarType;
                  Result.Samplers[NewIdx].SlotIndex := NewIdx;
                end;
              end else
              begin
                if not Result.FindUniform(BaseName, ExistingUniform) then
                begin
                  ComputeStd140TypeLayout(VarType, ArrCount, BaseAlign, ByteSize);
                  UBOCursor := (UBOCursor + BaseAlign - 1) and not (BaseAlign - 1);
                  NewIdx := Length(Result.Uniforms);
                  SetLength(Result.Uniforms, NewIdx + 1);
                  Result.Uniforms[NewIdx].Name := BaseName;
                  Result.Uniforms[NewIdx].GLSLType := VarType;
                  Result.Uniforms[NewIdx].DeclSuffix := SuffixStr;
                  Result.Uniforms[NewIdx].ByteOffset := UBOCursor;
                  Result.Uniforms[NewIdx].ByteSize := ByteSize;
                  Result.Uniforms[NewIdx].ArrayCount := ArrCount;
                  Inc(UBOCursor, ByteSize);
                end;
              end;
            end;
          end;
        end else
        if TryMatchVaryingDeclarationPrefix(CleanLine, AStage, DeclBody, ExplicitDir) then
        begin
          SemiPos := Pos(';', DeclBody);
          if SemiPos > 0 then
            DeclBody := Trim(Copy(DeclBody, 1, SemiPos - 1));
          StripGLSLStorageAndPrecisionQualifiers(DeclBody, InterpQual);
          SpacePos := Pos(' ', DeclBody);
          if SpacePos > 0 then
          begin
            VarType := Trim(Copy(DeclBody, 1, SpacePos - 1));
            Declarators := Trim(Copy(DeclBody, SpacePos + 1, MaxInt));
            while Declarators <> '' do
            begin
              CommaPos := Pos(',', Declarators);
              if CommaPos > 0 then
              begin
                OneDecl := Trim(Copy(Declarators, 1, CommaPos - 1));
                Declarators := Trim(Copy(Declarators, CommaPos + 1, MaxInt));
              end else
              begin
                OneDecl := Trim(Declarators);
                Declarators := '';
              end;
              BracketPos := Pos('[', OneDecl);
              if BracketPos > 0 then
                BaseName := Trim(Copy(OneDecl, 1, BracketPos - 1))
              else
                BaseName := OneDecl;
              if IsSuffix('_geoshader', BaseName, False) then
                BaseName := Copy(BaseName, 1, Length(BaseName) - Length('_geoshader'));
              if (BaseName = '') or IsBuiltInCastleVaryingName(BaseName) then
                Continue;
              if not Result.FindVarying(BaseName, ExistingVarying) then
              begin
                NewIdx := Length(Result.Varyings);
                SetLength(Result.Varyings, NewIdx + 1);
                Result.Varyings[NewIdx].Name := BaseName;
                Result.Varyings[NewIdx].GLSLType := VarType;
                Result.Varyings[NewIdx].InterpQual := InterpQual;
                Result.Varyings[NewIdx].Location := NextVaryingLoc;
                Result.Varyings[NewIdx].LocationSlots := ComputeVaryingLocationSlots(VarType);
                Inc(NextVaryingLoc, Result.Varyings[NewIdx].LocationSlots);
              end;
            end;
          end;
        end;
      end;
    finally
      FreeAndNil(Lines);
    end;
  end;

begin
  FillChar(Result, SizeOf(Result), 0);
  UBOCursor := 0;
  NextVaryingLoc := AFirstVaryingLocation;
  ScanStage(ssVertex, AVertSource);
  ScanStage(ssGeometry, AGeomSource);
  ScanStage(ssFragment, AFragSource);
  if Length(Result.Uniforms) > 0 then
  begin
    Result.TotalUBOSize := (UBOCursor + 15) and not PtrUInt(15);
    if Result.TotalUBOSize = 0 then
      Result.TotalUBOSize := 16;
  end;
end;

function TCastleShaderGeneratorRHI.UpgradeUserEffectStageSource(
  const AStage: TRHIShaderStage;
  const AStageSource: String;
  const ALayout: TUserEffectShaderLayout;
  const AFirstSamplerBinding: Cardinal;
  const ASetIndex: Cardinal): String;
var
  Sanitized, Line, CleanLine, DeclBody, ExplicitDir, InterpQual, VarType,
    Declarators, OneDecl, BaseName, SuffixStr, DirKeyword, HeaderDecls: String;
  Lines: TStringList;
  UBOMembers, AliasDefines, SamplerDecls, BodyBuilder: TStringBuilder;
  InBlockComment: Boolean;
  BraceDepth, DepthBefore, SemiPos, SpacePos, CommaPos, BracketPos, I: Integer;
  VDesc: TUserEffectVaryingDesc;
begin
  if FBackend <> rbVulkan then
    Exit(AStageSource);
  if Trim(AStageSource) = '' then
    Exit('');

  Sanitized := SanitizeVulkanShaderSource(AStageSource);

  Lines := TStringList.Create;
  UBOMembers := TStringBuilder.Create;
  AliasDefines := TStringBuilder.Create;
  SamplerDecls := TStringBuilder.Create;
  BodyBuilder := TStringBuilder.Create;
  try
    for I := 0 to High(ALayout.Uniforms) do
    begin
      UBOMembers.AppendLine(Format('  %s u_user_%s%s;',
        [ALayout.Uniforms[I].GLSLType, ALayout.Uniforms[I].Name, ALayout.Uniforms[I].DeclSuffix]));
      AliasDefines.AppendLine(Format('#undef %s', [ALayout.Uniforms[I].Name]));
      AliasDefines.AppendLine(Format('#define %s CastleUserEffect.u_user_%s',
        [ALayout.Uniforms[I].Name, ALayout.Uniforms[I].Name]));
    end;

    for I := 0 to High(ALayout.Samplers) do
      SamplerDecls.AppendLine(Format('CASTLE_SAMPLER(%d, %d) uniform %s %s;',
        [ASetIndex, Integer(AFirstSamplerBinding) + ALayout.Samplers[I].SlotIndex,
         ALayout.Samplers[I].GLSLType, ALayout.Samplers[I].Name]));

    Lines.Text := Sanitized;
    InBlockComment := False;
    BraceDepth := 0;
    for Line in Lines do
    begin
      DepthBefore := BraceDepth;
      CleanLine := StripGLSLLineCommentAndTrackState(Line, InBlockComment, BraceDepth);
      if (CleanLine <> '') and (DepthBefore = 0) and
         IsPrefix('uniform ', CleanLine, False) and (Pos('{', CleanLine) = 0) and
         (Pos('(', CleanLine) = 0) then
      begin
        DeclBody := Trim(SEnding(CleanLine, Length('uniform ') + 1));
        SemiPos := Pos(';', DeclBody);
        if SemiPos > 0 then
          DeclBody := Trim(Copy(DeclBody, 1, SemiPos - 1));
        StripGLSLStorageAndPrecisionQualifiers(DeclBody, InterpQual);
        SpacePos := Pos(' ', DeclBody);
        if SpacePos > 0 then
        begin
          Declarators := Trim(Copy(DeclBody, SpacePos + 1, MaxInt));
          if IsBuiltInScreenEffectSamplerName(Declarators) then
            BodyBuilder.AppendLine('// [Vulkan RHI screen sampler]: ' + Line)
          else
            BodyBuilder.AppendLine('// [Vulkan RHI Set 2 uniform]: ' + Line);
        end else
          BodyBuilder.AppendLine(Line);
      end else
      if (CleanLine <> '') and (DepthBefore = 0) and
         TryMatchVaryingDeclarationPrefix(CleanLine, AStage, DeclBody, ExplicitDir) then
      begin
        SemiPos := Pos(';', DeclBody);
        if SemiPos > 0 then
          DeclBody := Trim(Copy(DeclBody, 1, SemiPos - 1));
        StripGLSLStorageAndPrecisionQualifiers(DeclBody, InterpQual);
        SpacePos := Pos(' ', DeclBody);
        if SpacePos > 0 then
        begin
          VarType := Trim(Copy(DeclBody, 1, SpacePos - 1));
          Declarators := Trim(Copy(DeclBody, SpacePos + 1, MaxInt));
          while Declarators <> '' do
          begin
            CommaPos := Pos(',', Declarators);
            if CommaPos > 0 then
            begin
              OneDecl := Trim(Copy(Declarators, 1, CommaPos - 1));
              Declarators := Trim(Copy(Declarators, CommaPos + 1, MaxInt));
            end else
            begin
              OneDecl := Trim(Declarators);
              Declarators := '';
            end;
            BracketPos := Pos('[', OneDecl);
            if BracketPos > 0 then
            begin
              BaseName := Trim(Copy(OneDecl, 1, BracketPos - 1));
              SuffixStr := Trim(Copy(OneDecl, BracketPos, MaxInt));
              if SuffixStr = '[CASTLE_GEOMETRY_INPUT_SIZE]' then
                SuffixStr := '[]';
            end else
            begin
              BaseName := OneDecl;
              SuffixStr := '';
            end;
            if IsBuiltInCastleVaryingName(BaseName) then
              BodyBuilder.AppendLine('// [Vulkan RHI built-in varying]: ' + BaseName)
            else if ALayout.FindVarying(BaseName, VDesc) then
            begin
              if ExplicitDir <> '' then
                DirKeyword := ExplicitDir
              else if AStage = ssVertex then
                DirKeyword := 'out'
              else
                DirKeyword := 'in';
              BodyBuilder.AppendLine(Format('CASTLE_LOCATION(%d) %s%s %s %s%s;',
                [VDesc.Location, VDesc.InterpQual, DirKeyword, VarType, BaseName, SuffixStr]));
            end else
              BodyBuilder.AppendLine(Line);
          end;
        end else
          BodyBuilder.AppendLine(Line);
      end else
      if (CleanLine <> '') and (DepthBefore = 0) and (AStage = ssVertex) and
         (Pos('(', CleanLine) = 0) and (Pos('{', CleanLine) = 0) and (Pos(';', CleanLine) > 0) and
         (IsPrefix('attribute ', CleanLine, False) or IsPrefix('in ', CleanLine, False)) then
      begin
        if IsPrefix('attribute ', CleanLine, False) then
          DeclBody := Trim(SEnding(CleanLine, Length('attribute ') + 1))
        else
          DeclBody := Trim(SEnding(CleanLine, Length('in ') + 1));
        SemiPos := Pos(';', DeclBody);
        if SemiPos > 0 then
          DeclBody := Trim(Copy(DeclBody, 1, SemiPos - 1));
        StripGLSLStorageAndPrecisionQualifiers(DeclBody, InterpQual);
        SpacePos := Pos(' ', DeclBody);
        if SpacePos > 0 then
        begin
          BaseName := Trim(Copy(DeclBody, SpacePos + 1, MaxInt));
          BracketPos := Pos('[', BaseName);
          if BracketPos > 0 then
            BaseName := Trim(Copy(BaseName, 1, BracketPos - 1));
          if IsBuiltInCastleVertexAttrName(BaseName) then
            BodyBuilder.AppendLine('// [Vulkan RHI built-in attribute]: ' + BaseName)
          else
            BodyBuilder.AppendLine(Line);
        end else
          BodyBuilder.AppendLine(Line);
      end else
        BodyBuilder.AppendLine(Line);
    end;

    HeaderDecls := '';
    if UBOMembers.Length > 0 then
      HeaderDecls := HeaderDecls +
        '/* --- Auto-Generated Set 2 UBO for User X3D Effect Node --- */' + NL +
        Format('CASTLE_UBO(%d, 1) uniform CastleUserEffectBlock {', [ASetIndex]) + NL +
        UBOMembers.ToString +
        '} CastleUserEffect;' + NL +
        AliasDefines.ToString + NL;
    if SamplerDecls.Length > 0 then
      HeaderDecls := HeaderDecls + SamplerDecls.ToString + NL;

    Result := HeaderDecls + UpgradeLegacyGLSLBuiltIns(BodyBuilder.ToString, 'Effect');
    { Isolate user EffectPart uniform macros (e.g. terrain.fs uniform vec4 metallic/roughness)
      from CGE's own local variables inside main(), while keeping macros active when AStageSource
      itself defines main() (ComposedShader / ScreenEffect). }
    if (Length(ALayout.Uniforms) > 0) and (Pos('main(', AStageSource) = 0) and
       (Pos('main (', AStageSource) = 0) then
    begin
      Result := Result + NL;
      for I := 0 to High(ALayout.Uniforms) do
        Result := Result + Format('#undef %s', [ALayout.Uniforms[I].Name]) + NL;
    end;
  finally
    FreeAndNil(BodyBuilder);
    FreeAndNil(SamplerDecls);
    FreeAndNil(AliasDefines);
    FreeAndNil(UBOMembers);
    FreeAndNil(Lines);
  end;
end;

function TCastleShaderGeneratorRHI.FinalizeVertexShaderSource(
  const StitchedSource: String): String;
var
  LastBracePos: Integer;
begin
  if FBackend <> rbVulkan then
    Exit(StitchedSource);

  (* Inject Vulkan clip-space depth conversion ([-1..1] -> [0..1]) before the final '}'
     of main() so CGE's OpenGL projection matrices work identically in Vulkan *)
  LastBracePos := RPos('}', StitchedSource);
  if LastBracePos > 0 then
    Result := Copy(StitchedSource, 1, LastBracePos - 1) + NL +
      '  /* Vulkan NDC depth adjustment [0..1] */' + NL +
      '  gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;' + NL +
      '}' + NL
  else
    Result := StitchedSource;
end;

function TCastleShaderGeneratorRHI.FinalizeGeometryShaderSource(
  const StitchedSource: String;
  const PlugSetCalls: String;
  const PlugZeroCalls: String;
  const PlugAddCalls: String): String;
var
  HasInputLayout, HasMain: Boolean;
begin
  Result := StitchedSource;
  if FBackend <> rbVulkan then
    Exit;

  HasInputLayout :=
    (Pos(') in;', Result) > 0) or
    (Pos(')in;', Result) > 0);
  HasMain := Pos('void main', Result) > 0;

  if not HasInputLayout then
  begin
    if Pos('void geometryVertexAdd(const int index, const float scale);', Result) > 0 then
      Result := StringReplace(
        Result,
        'void geometryVertexAdd(const int index, const float scale);',
        'void geometryVertexAdd(const int index, const float scale);' + NL +
        'layout(triangles) in;' + NL +
        'layout(triangle_strip, max_vertices = 3) out;',
        [])
    else if HasMain then
      Result := StringReplace(
        Result,
        'void main',
        'layout(triangles) in;' + NL +
        'layout(triangle_strip, max_vertices = 3) out;' + NL +
        'void main',
        [])
    else
      Result :=
        'layout(triangles) in;' + NL +
        'layout(triangle_strip, max_vertices = 3) out;' + NL +
        Result;
  end;

  if not HasMain then
    Result := Result + NL +
      'void main()' + NL +
      '{' + NL +
      '  for (int i = 0; i < 3; ++i) {' + NL +
      '    gl_Position = gl_in[i].gl_Position;' + NL +
      '    geometryVertexSet(i);' + NL +
      '    EmitVertex();' + NL +
      '  }' + NL +
      '  EndPrimitive();' + NL +
      '}' + NL;

  Result := Result + NL +
    '/* --- CGE Geometry Shader Varying Pass-Through & Blending Implementations --- */' + NL +
    'void geometryVertexSet(const int index)' + NL +
    '{' + NL +
    '  castle_vertex_eye_geoshader = castle_vertex_eye[index];' + NL +
    '  castle_normal_eye_geoshader = castle_normal_eye[index];' + NL +
    '  castle_tex_coord0_geoshader = castle_tex_coord0[index];' + NL +
    '  castle_tex_coord1_geoshader = castle_tex_coord1[index];' + NL +
    '  castle_color_per_vertex_geoshader = castle_color_per_vertex[index];' + NL +
    '  castle_tangent_to_eye_space_geoshader = castle_tangent_to_eye_space[index];' + NL;
  if PlugSetCalls <> '' then
    Result := Result + PlugSetCalls + NL;
  Result := Result +
    '}' + NL +
    NL +
    'void geometryVertexZero()' + NL +
    '{' + NL +
    '  castle_vertex_eye_geoshader = vec4(0.0);' + NL +
    '  castle_normal_eye_geoshader = vec3(0.0);' + NL +
    '  castle_tex_coord0_geoshader = vec2(0.0);' + NL +
    '  castle_tex_coord1_geoshader = vec2(0.0);' + NL +
    '  castle_color_per_vertex_geoshader = vec4(0.0);' + NL +
    '  castle_tangent_to_eye_space_geoshader = mat3(0.0);' + NL;
  if PlugZeroCalls <> '' then
    Result := Result + PlugZeroCalls + NL;
  Result := Result +
    '}' + NL +
    NL +
    'void geometryVertexAdd(const int index, const float scale)' + NL +
    '{' + NL +
    '  castle_vertex_eye_geoshader += castle_vertex_eye[index] * scale;' + NL +
    '  castle_normal_eye_geoshader += castle_normal_eye[index] * scale;' + NL +
    '  castle_tex_coord0_geoshader += castle_tex_coord0[index] * scale;' + NL +
    '  castle_tex_coord1_geoshader += castle_tex_coord1[index] * scale;' + NL +
    '  castle_color_per_vertex_geoshader += castle_color_per_vertex[index] * scale;' + NL +
    '  castle_tangent_to_eye_space_geoshader += castle_tangent_to_eye_space[index] * scale;' + NL;
  if PlugAddCalls <> '' then
    Result := Result + PlugAddCalls + NL;
  Result := Result +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.SanitizeVulkanShaderSource(
  const Source: String): String;
const
  BuiltInUniformTokens: array[0..13] of String = (
    'castle_LightSource', 'castle_projector_matrix', 'castle_ModelViewMatrix',
    'castle_ProjectionMatrix', 'castle_NormalMatrix', 'castle_JointMatrix',
    'castle_Material', 'castle_WorldEyePosition', 'castle_SceneTime', 'castle_Fog',
    'castle_CameraMatrix', 'castle_CameraInverseMatrix',
    'castle_CameraRotationMatrix', 'castle_CameraRotationInverseMatrix'
  );
var
  Lines: TStringList;
  ResultBuilder: TStringBuilder;
  Line, Trimmed, Token: String;
  IsBuiltIn: Boolean;
begin
  if FBackend <> rbVulkan then
    Exit(Source);

  Lines := TStringList.Create;
  ResultBuilder := TStringBuilder.Create;
  try
    Lines.Text := Source;
    for Line in Lines do
    begin
      Trimmed := Trim(Line);
      IsBuiltIn := False;
      if IsPrefix('uniform ', Trimmed, False) and (Pos('{', Trimmed) = 0) then
        for Token in BuiltInUniformTokens do
          if Pos(Token, Trimmed) > 0 then
          begin
            IsBuiltIn := True;
            Break;
          end;

      if IsBuiltIn then
        ResultBuilder.AppendLine('// [Vulkan RHI UBO]: ' + Line)
      else
      if (Pos('{', Trimmed) = 0) and IsSuffix(');', Trimmed, False) and
         ((Pos('castle_texture_color_to_linear(', Trimmed) > 0) or
          (Pos('castle_linear_to_screen(', Trimmed) > 0)) then
        ResultBuilder.AppendLine('// [Vulkan RHI built-in helper]: ' + Line)
      else
        ResultBuilder.AppendLine(Line);
    end;
    Result := ResultBuilder.ToString;
  finally
    FreeAndNil(ResultBuilder);
    FreeAndNil(Lines);
  end;
end;

function TCastleShaderGeneratorRHI.GenerateScreenEffectPreamble(
  const AStage: TRHIShaderStage; const HasDepth: Boolean;
  const AIncludeVertexResources: Boolean): String;
begin
  if FBackend <> rbVulkan then
    Exit('');

  Result :=
    '#version 450' + NL +
    '#extension GL_ARB_separate_shader_objects : enable' + NL +
    '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140, set = SetIdx, binding = BindIdx)' + NL +
    '#define CASTLE_SAMPLER(SetIdx, BindIdx) layout(set = SetIdx, binding = BindIdx)' + NL +
    '#define CASTLE_DESCRIPTOR_SET(SetIdx, BindIdx) layout(set = SetIdx, binding = BindIdx)' + NL +
    '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL;

  if (AStage = ssFragment) or AIncludeVertexResources then
  begin
    Result := Result +
      NL +
      '/* --- Screen Effect Push Constants --- */' + NL +
      'layout(push_constant) uniform CastleScreenPushConstants {' + NL +
      '  vec2 screen_size;' + NL +
      '  vec2 screen_planes;' + NL +
      '  vec4 screen_custom;' + NL +
      '} castle_Screen;' + NL +
      NL +
      '#define screen_width (castle_Screen.screen_size.x)' + NL +
      '#define screen_height (castle_Screen.screen_size.y)' + NL +
      '#define near (castle_Screen.screen_planes.x)' + NL +
      '#define far (castle_Screen.screen_planes.y)' + NL +
      NL +
      '/* --- Screen Effect Textures (Set 0) --- */' + NL +
      'layout(set = 0, binding = 0) uniform sampler2D screen;' + NL;

    if HasDepth then
      Result := Result +
        'layout(set = 0, binding = 1) uniform sampler2D screen_depth;' + NL;
  end;

  Result := Result +
    NL +
    '/* --- Compatibility Aliases --- */' + NL +
    '#define texture2D texture' + NL +
    '#define textureCube texture' + NL +
    NL;

  case AStage of
    ssVertex:
      Result := Result +
        '/* --- Vertex Shader Stage IO --- */' + NL +
        'layout(location = 0) in vec2 vertex;' + NL +
        'layout(location = 1) in vec2 tex_coord;' + NL +
        'layout(location = 0) out vec2 v_tex_coord;' + NL;
    ssFragment:
      Result := Result +
        '/* --- Fragment Shader Stage IO --- */' + NL +
        'layout(location = 0) in vec2 tex_coord;' + NL +
        'layout(location = 0) out vec4 castle_FragColor;' + NL +
        '#define gl_FragColor castle_FragColor' + NL +
        '#define screenf_01_position tex_coord' + NL;
  end;
end;

function TCastleShaderGeneratorRHI.GenerateBatch2DFragmentPreamble: String;
begin
  Result :=
    GenerateVersionAndLayoutMacrosForStage(ssFragment) + NL +
    '/* --- 2D Batch Push Constants (64 bytes, matches TCastle2DPushConstants) --- */' + NL +
    'CASTLE_PUSH_CONSTANT uniform Castle2DPushConstants {' + NL +
    '  mat4 u_ModelViewMatrix;' + NL +
    '} CastleDraw;' + NL +
    NL +
    '/* --- 2D Batch Fragment Inputs & Output (matches BuiltInBatch2DVertSPIRV) --- */' + NL +
    'CASTLE_LOCATION(0) in vec2 castle_tex_coord0;' + NL +
    'CASTLE_LOCATION(1) in vec4 castle_color_per_vertex;' + NL +
    'CASTLE_LOCATION(0) out vec4 castle_FragColor;' + NL +
    NL;
end;

function TCastleShaderGeneratorRHI.GenerateComputeCullingShader(
  const AWorkgroupSizeX: Cardinal): String;
var
  EffectiveLocalSizeX: Cardinal;
begin
  if AWorkgroupSizeX = 0 then
    EffectiveLocalSizeX := 64
  else
    EffectiveLocalSizeX := AWorkgroupSizeX;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = 1, local_size_z = 1) in;', [EffectiveLocalSizeX]) + NL +
    NL +
    'layout(std140, set = 0, binding = 0) uniform CastleGpuCullingUniforms {' + NL +
    '  vec4 u_FrustumPlanes[6];' + NL +
    '  vec4 u_CameraPosition;' + NL +
    '  vec4 u_HiZParams;' + NL +
    '  uint u_InstanceCount;' + NL +
    '  uint u_EnableFrustumCulling;' + NL +
    '  uint u_EnableDistanceCulling;' + NL +
    '  uint u_CompactDrawStream;' + NL +
    '} CastleCulling;' + NL +
    NL +
    'struct CastleGpuCullingInstance {' + NL +
    '  vec4 BoundingSphere;' + NL +
    '  vec4 AABBMin;' + NL +
    '  vec4 AABBMax;' + NL +
    '  uint IndexCount;' + NL +
    '  uint FirstIndex;' + NL +
    '  int  VertexOffset;' + NL +
    '  uint FirstInstance;' + NL +
    '  uint InstanceCount;' + NL +
    '  uint MaterialIndex;' + NL +
    '  uint Padding0;' + NL +
    '  uint Padding1;' + NL +
    '};' + NL +
    NL +
    'struct CastleDrawIndexedIndirectCommand {' + NL +
    '  uint indexCount;' + NL +
    '  uint instanceCount;' + NL +
    '  uint firstIndex;' + NL +
    '  int  vertexOffset;' + NL +
    '  uint firstInstance;' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 1) readonly buffer CastleCullingInstancesBlock {' + NL +
    '  CastleGpuCullingInstance u_Instances[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 2) writeonly buffer CastleIndirectCommandsBlock {' + NL +
    '  CastleDrawIndexedIndirectCommand u_Commands[];' + NL +
    '};' + NL +
    NL +
    'layout(std430, set = 0, binding = 3) buffer CastleVisibilityOutputBlock {' + NL +
    '  uint u_VisibleCount;' + NL +
    '  uint u_VisibilityFlags[];' + NL +
    '};' + NL +
    NL +
    'bool IsSphereInsideFrustum(vec3 center, float radius) {' + NL +
    '  for (int i = 0; i < 6; ++i) {' + NL +
    '    vec4 plane = CastleCulling.u_FrustumPlanes[i];' + NL +
    '    if (dot(plane.xyz, center) + plane.w < -radius)' + NL +
    '      return false;' + NL +
    '  }' + NL +
    '  return true;' + NL +
    '}' + NL +
    NL +
    'void main() {' + NL +
    '  uint idx = gl_GlobalInvocationID.x;' + NL +
    '  if (idx >= CastleCulling.u_InstanceCount) return;' + NL +
    '  CastleGpuCullingInstance inst = u_Instances[idx];' + NL +
    '  bool visible = true;' + NL +
    '  if (CastleCulling.u_EnableFrustumCulling != 0u) {' + NL +
    '    visible = IsSphereInsideFrustum(inst.BoundingSphere.xyz, inst.BoundingSphere.w);' + NL +
    '  }' + NL +
    '  if (visible && (CastleCulling.u_EnableDistanceCulling != 0u) && (CastleCulling.u_CameraPosition.w > 0.0)) {' + NL +
    '    float dist = distance(inst.BoundingSphere.xyz, CastleCulling.u_CameraPosition.xyz) - inst.BoundingSphere.w;' + NL +
    '    if (dist > CastleCulling.u_CameraPosition.w)' + NL +
    '      visible = false;' + NL +
    '  }' + NL +
    '  u_VisibilityFlags[idx] = visible ? 1u : 0u;' + NL +
    '  if (CastleCulling.u_CompactDrawStream != 0u) {' + NL +
    '    if (visible) {' + NL +
    '      uint outSlot = atomicAdd(u_VisibleCount, 1u);' + NL +
    '      CastleDrawIndexedIndirectCommand cmd;' + NL +
    '      cmd.indexCount = inst.IndexCount;' + NL +
    '      cmd.instanceCount = inst.InstanceCount;' + NL +
    '      cmd.firstIndex = inst.FirstIndex;' + NL +
    '      cmd.vertexOffset = inst.VertexOffset;' + NL +
    '      cmd.firstInstance = inst.FirstInstance;' + NL +
    '      u_Commands[outSlot] = cmd;' + NL +
    '    }' + NL +
    '  } else {' + NL +
    '    if (visible) atomicAdd(u_VisibleCount, 1u);' + NL +
    '    CastleDrawIndexedIndirectCommand cmd;' + NL +
    '    cmd.indexCount = inst.IndexCount;' + NL +
    '    cmd.instanceCount = visible ? inst.InstanceCount : 0u;' + NL +
    '    cmd.firstIndex = inst.FirstIndex;' + NL +
    '    cmd.vertexOffset = inst.VertexOffset;' + NL +
    '    cmd.firstInstance = inst.FirstInstance;' + NL +
    '    u_Commands[idx] = cmd;' + NL +
    '  }' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateHiZDownsampleComputeShader(
  const AWorkgroupSizeX: Cardinal;
  const AWorkgroupSizeY: Cardinal): String;
var
  LocalSizeX, LocalSizeY: Cardinal;
begin
  if AWorkgroupSizeX = 0 then
    LocalSizeX := 8
  else
    LocalSizeX := AWorkgroupSizeX;
  if AWorkgroupSizeY = 0 then
    LocalSizeY := 8
  else
    LocalSizeY := AWorkgroupSizeY;

  Result :=
    '#version 450' + NL +
    Format('layout(local_size_x = %d, local_size_y = %d, local_size_z = 1) in;', [LocalSizeX, LocalSizeY]) + NL +
    NL +
    'layout(set = 0, binding = 0) uniform sampler2D u_SrcDepthMip;' + NL +
    'layout(set = 0, binding = 1, r32f) uniform writeonly image2D u_DstDepthMip;' + NL +
    NL +
    'layout(push_constant) uniform CastleHiZPushConstants {' + NL +
    '  uvec2 u_DstMipSize;' + NL +
    '  uvec2 u_SrcMipSize;' + NL +
    '} pc;' + NL +
    NL +
    'void main() {' + NL +
    '  uvec2 dstCoord = gl_GlobalInvocationID.xy;' + NL +
    '  if (dstCoord.x >= pc.u_DstMipSize.x || dstCoord.y >= pc.u_DstMipSize.y) return;' + NL +
    '  ivec2 srcBase = ivec2(dstCoord * 2u);' + NL +
    '  ivec2 maxSrc = ivec2(max(pc.u_SrcMipSize, uvec2(1u))) - ivec2(1);' + NL +
    '  float d00 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(0, 0), ivec2(0), maxSrc), 0).r;' + NL +
    '  float d10 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(1, 0), ivec2(0), maxSrc), 0).r;' + NL +
    '  float d01 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(0, 1), ivec2(0), maxSrc), 0).r;' + NL +
    '  float d11 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(1, 1), ivec2(0), maxSrc), 0).r;' + NL +
    '  float maxDepth = max(max(d00, d10), max(d01, d11));' + NL +
    '  if (((pc.u_SrcMipSize.x & 1u) != 0u) && (dstCoord.x + 1u == pc.u_DstMipSize.x)) {' + NL +
    '    float d20 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(2, 0), ivec2(0), maxSrc), 0).r;' + NL +
    '    float d21 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(2, 1), ivec2(0), maxSrc), 0).r;' + NL +
    '    maxDepth = max(maxDepth, max(d20, d21));' + NL +
    '  }' + NL +
    '  if (((pc.u_SrcMipSize.y & 1u) != 0u) && (dstCoord.y + 1u == pc.u_DstMipSize.y)) {' + NL +
    '    float d02 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(0, 2), ivec2(0), maxSrc), 0).r;' + NL +
    '    float d12 = texelFetch(u_SrcDepthMip, clamp(srcBase + ivec2(1, 2), ivec2(0), maxSrc), 0).r;' + NL +
    '    maxDepth = max(maxDepth, max(d02, d12));' + NL +
    '  }' + NL +
    '  imageStore(u_DstDepthMip, ivec2(dstCoord), vec4(maxDepth, 0.0, 0.0, 1.0));' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GeneratePBRFunctions: String;
begin
  Result :=
    '/* --- glTF 2.0 / X3D PhysicalMaterial Cook-Torrance Microfacet GGX BRDF --- */' + NL +
    'const float CASTLE_PI = 3.14159265358979323846;' + NL +
    NL +
    'float DistributionGGX(float NdotH, float roughness) {' + NL +
    '  float alpha = max(roughness * roughness, 0.002025);' + NL +
    '  float alpha2 = alpha * alpha;' + NL +
    '  float denom = (NdotH * NdotH) * (alpha2 - 1.0) + 1.0;' + NL +
    '  return alpha2 / max(CASTLE_PI * denom * denom, 1e-7);' + NL +
    '}' + NL +
    NL +
    'float GeometrySmithGGXCorrelated(float NdotV, float NdotL, float roughness) {' + NL +
    '  float alpha = max(roughness * roughness, 0.002025);' + NL +
    '  float alpha2 = alpha * alpha;' + NL +
    '  float ggxV = NdotL * sqrt(max(NdotV * NdotV * (1.0 - alpha2) + alpha2, 1e-7));' + NL +
    '  float ggxL = NdotV * sqrt(max(NdotL * NdotL * (1.0 - alpha2) + alpha2, 1e-7));' + NL +
    '  return 0.5 / max(ggxV + ggxL, 1e-5);' + NL +
    '}' + NL +
    NL +
    'vec3 FresnelSchlick(float cosTheta, vec3 F0) {' + NL +
    '  float clamped = clamp(1.0 - cosTheta, 0.0, 1.0);' + NL +
    '  float c2 = clamped * clamped;' + NL +
    '  return F0 + (1.0 - F0) * (c2 * c2 * clamped);' + NL +
    '}' + NL +
    NL +
    'vec3 FresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness) {' + NL +
    '  float clamped = clamp(1.0 - cosTheta, 0.0, 1.0);' + NL +
    '  float c2 = clamped * clamped;' + NL +
    '  return F0 + (max(vec3(1.0 - roughness), F0) - F0) * (c2 * c2 * clamped);' + NL +
    '}' + NL +
    NL +
    '/* Screen-space derivative cotangent-frame TBN normal mapping (Christian Schuler) */' + NL +
    'vec3 PerturbNormalCotangent(vec3 N, vec3 V, vec2 texCoord, vec3 tangentNormal, float normalScale) {' + NL +
    '  vec3 dp1 = dFdx(-V);' + NL +
    '  vec3 dp2 = dFdy(-V);' + NL +
    '  vec2 duv1 = dFdx(texCoord);' + NL +
    '  vec2 duv2 = dFdy(texCoord);' + NL +
    '  vec3 dp2perp = cross(dp2, N);' + NL +
    '  vec3 dp1perp = cross(N, dp1);' + NL +
    '  vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;' + NL +
    '  vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;' + NL +
    '  float invmax = inversesqrt(max(dot(T, T), dot(B, B)) + 1e-7);' + NL +
    '  mat3 TBN = mat3(T * invmax, B * invmax, N);' + NL +
    '  vec3 scaledNormal = normalize(tangentNormal * vec3(normalScale, normalScale, 1.0));' + NL +
    '  return normalize(TBN * scaledNormal);' + NL +
    '}' + NL +
    NL +
    'vec3 PerturbNormalTBN(mat3 TBN, vec3 tangentNormal, float normalScale) {' + NL +
    '  vec3 scaledNormal = normalize(tangentNormal * vec3(normalScale, normalScale, 1.0));' + NL +
    '  return normalize(TBN * scaledNormal);' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateDirectCookTorranceGGX(vec3 N, vec3 V, vec3 L, vec3 lightRadiance,' + NL +
    '  vec3 albedo, float metallic, float roughness) {' + NL +
    '  vec3 H = normalize(V + L);' + NL +
    '  float NdotL = max(dot(N, L), 0.0);' + NL +
    '  float NdotV = max(dot(N, V), 1e-4);' + NL +
    '  float NdotH = max(dot(N, H), 0.0);' + NL +
    '  float HdotV = max(dot(H, V), 0.0);' + NL +
    '  if (NdotL <= 0.0) return vec3(0.0);' + NL +
    '  vec3 F0 = mix(vec3(0.04), albedo, metallic);' + NL +
    '  float D = DistributionGGX(NdotH, roughness);' + NL +
    '  float Vis = GeometrySmithGGXCorrelated(NdotV, NdotL, roughness);' + NL +
    '  vec3 F = FresnelSchlick(HdotV, F0);' + NL +
    '  vec3 specular = (D * Vis) * F;' + NL +
    '  vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);' + NL +
    '  vec3 diffuse = kD * albedo / CASTLE_PI;' + NL +
    '  return (diffuse + specular) * lightRadiance * NdotL;' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateIBLCookTorranceGGX(vec3 N, vec3 V, vec3 albedo, float metallic,' + NL +
    '  float roughness, float ao, vec3 diffuseIrradiance, vec3 prefilteredEnvColor, vec2 brdfLut) {' + NL +
    '  float NdotV = max(dot(N, V), 1e-4);' + NL +
    '  vec3 F0 = mix(vec3(0.04), albedo, metallic);' + NL +
    '  vec3 F = FresnelSchlickRoughness(NdotV, F0, roughness);' + NL +
    '  vec3 kD = (vec3(1.0) - F) * (1.0 - metallic);' + NL +
    '  vec3 diffuse = diffuseIrradiance * albedo * kD;' + NL +
    '  vec3 specular = prefilteredEnvColor * (F * brdfLut.x + brdfLut.y);' + NL +
    '  return (diffuse + specular) * ao;' + NL +
    '}' + NL +
    NL +
    'vec3 LINEARtoSRGB(vec3 color) {' + NL +
    '  return pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));' + NL +
    '}' + NL +
    NL +
    'vec3 toneMapUncharted2Impl(vec3 color) {' + NL +
    '  const float A = 0.15;' + NL +
    '  const float B = 0.50;' + NL +
    '  const float C = 0.10;' + NL +
    '  const float D = 0.20;' + NL +
    '  const float E = 0.02;' + NL +
    '  const float F = 0.30;' + NL +
    '  return ((color * (A * color + C * B) + D * E) / (color * (A * color + B) + D * F)) - E / F;' + NL +
    '}' + NL +
    NL +
    'vec3 toneMapUncharted(vec3 color) {' + NL +
    '  const float W = 11.2;' + NL +
    '  color = toneMapUncharted2Impl(color * 2.0);' + NL +
    '  vec3 whiteScale = 1.0 / toneMapUncharted2Impl(vec3(W));' + NL +
    '  return color * whiteScale;' + NL +
    '}' + NL +
    NL +
    'vec3 toneMapHejlRichard(vec3 color) {' + NL +
    '  color = max(vec3(0.0), color - vec3(0.004));' + NL +
    '  return (color * (6.2 * color + 0.5)) / (color * (6.2 * color + 1.7) + 0.06);' + NL +
    '}' + NL +
    NL +
    'vec3 toneMapACES(vec3 color) {' + NL +
    '  const float A = 2.51;' + NL +
    '  const float B = 0.03;' + NL +
    '  const float C = 2.43;' + NL +
    '  const float D = 0.59;' + NL +
    '  const float E = 0.14;' + NL +
    '  return clamp((color * (A * color + B)) / (color * (C * color + D) + E), 0.0, 1.0);' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateDefault3DVertexShader(
  const HasSkinning: Boolean; const HasTangents: Boolean): String;
begin
  Result := GenerateDefault3DVertexShader(HasSkinning, HasTangents, True, True);
end;

function TCastleShaderGeneratorRHI.GenerateDefault3DVertexShader(
  const HasSkinning, HasTangents, HasTexCoord1, HasColorPerVertex: Boolean): String;
var
  PreambleText, Body: String;
begin
  if HasSkinning and HasTangents and HasTexCoord1 and HasColorPerVertex then
    PreambleText := GeneratePreamble(ssVertex)
  else
    PreambleText := GeneratePreambleFor3DVertex(HasSkinning, HasTangents, HasTexCoord1, HasColorPerVertex);

  Body :=
    PreambleText +
    'void main() {' + NL +
    '  vec4 localPos = castle_Vertex;' + NL +
    '  vec3 localNormal = castle_Normal;' + NL +
    '  vec3 localTangent = castle_Tangent.xyz;' + NL;

  if HasSkinning then
    Body := Body +
      '  if ((CastleSkinning.u_JointCount > 0u) && (castle_ObjectSkinningMode != 0)) {' + NL +
      '    mat4 skinMat =' + NL +
      '      castle_Weights0.x * CastleSkinning.u_JointMatrices[uint(castle_Joints0.x + 0.5)] +' + NL +
      '      castle_Weights0.y * CastleSkinning.u_JointMatrices[uint(castle_Joints0.y + 0.5)] +' + NL +
      '      castle_Weights0.z * CastleSkinning.u_JointMatrices[uint(castle_Joints0.z + 0.5)] +' + NL +
      '      castle_Weights0.w * CastleSkinning.u_JointMatrices[uint(castle_Joints0.w + 0.5)];' + NL +
      '    if (castle_ObjectSkinningMode == 2) {' + NL +
      '      /* Volume-preserving rotational orthonormalization (Dual-Quaternion mode) */' + NL +
      '      vec3 r0 = normalize(skinMat[0].xyz);' + NL +
      '      vec3 r1 = normalize(skinMat[1].xyz - dot(skinMat[1].xyz, r0) * r0);' + NL +
      '      vec3 r2 = cross(r0, r1);' + NL +
      '      mat3 skinRot = mat3(r0, r1, r2);' + NL +
      '      localPos = vec4(skinRot * localPos.xyz + skinMat[3].xyz, localPos.w);' + NL +
      '      localNormal = skinRot * localNormal;' + NL +
      '      localTangent = skinRot * localTangent;' + NL +
      '    } else {' + NL +
      '      localPos = skinMat * localPos;' + NL +
      '      localNormal = mat3(skinMat) * localNormal;' + NL +
      '      localTangent = mat3(skinMat) * localTangent;' + NL +
      '    }' + NL +
      '  }' + NL;

  Body := Body +
    '  castle_vertex_eye = castle_ModelViewMatrix * localPos;' + NL +
    '  castle_normal_eye = normalize(castle_NormalMatrix * localNormal);' + NL +
    '  castle_tex_coord0 = castle_MultiTexCoord0;' + NL +
    '  castle_tex_coord1 = castle_MultiTexCoord1;' + NL +
    '  castle_color_per_vertex = castle_ColorPerVertex;' + NL;

  if HasTangents then
    Body := Body +
      '  vec3 T = normalize(castle_NormalMatrix * localTangent);' + NL +
      '  vec3 N = castle_normal_eye;' + NL +
      '  T = normalize(T - dot(T, N) * N);' + NL +
      '  vec3 B = cross(N, T) * castle_Tangent.w;' + NL +
      '  castle_tangent_to_eye_space = mat3(T, B, N);' + NL
  else
    Body := Body +
      '  castle_tangent_to_eye_space = mat3(1.0);' + NL;

  Body := Body +
    '  gl_Position = castle_ProjectionMatrix * castle_vertex_eye;' + NL +
    '}' + NL;

  Result := FinalizeVertexShaderSource(Body);
end;

function TCastleShaderGeneratorRHI.GenerateClusteredForwardAndShadowFunctions: String;
begin
  Result :=
    '/* Set 0 / Set 1 Clustered Forward+ & Shadow Atlas Bindings */' + NL +
    'struct CastleClusteredLightData {' + NL +
    '  vec4 PositionAndRange;' + NL +
    '  vec4 DirectionAndSpotCos;' + NL +
    '  vec4 ColorAndIntensity;' + NL +
    '  vec4 ShadowAndTypeParams;' + NL +
    '};' + NL +
    NL +
    'struct CastleClusterGridEntryData {' + NL +
    '  uint Offset;' + NL +
    '  uint Count;' + NL +
    '};' + NL +
    NL +
    'struct CastlePositionalShadowTileData {' + NL +
    '  mat4 LightViewProjMatrix;' + NL +
    '  vec4 AtlasUVScaleOffset;' + NL +
    '};' + NL +
    NL +
    'layout(std140, set = 0, binding = 2) uniform CastleClusterCullingBlock {' + NL +
    '  mat4 u_InvProjectionMatrix;' + NL +
    '  vec4 u_ScreenAndDepthParams;' + NL +
    '  uvec4 u_ClusterGridDim;' + NL +
    '  vec4 u_LogDepthParams;' + NL +
    '} CastleClusterUniforms;' + NL +
    NL +
    'layout(std430, set = 0, binding = 3) readonly buffer CastleClusteredLightsBuffer {' + NL +
    '  CastleClusteredLightData u_ClusteredLights[];' + NL +
    '} CastleClusteredLightsSSBO;' + NL +
    NL +
    'layout(std430, set = 0, binding = 4) readonly buffer CastleClusterGridBuffer {' + NL +
    '  CastleClusterGridEntryData u_ClusterGrid[];' + NL +
    '} CastleClusterGridSSBO;' + NL +
    NL +
    'layout(std430, set = 0, binding = 5) readonly buffer CastleClusterLightIndexBuffer {' + NL +
    '  uint u_ClusterLightIndices[];' + NL +
    '} CastleClusterLightIndexSSBO;' + NL +
    NL +
    'layout(std140, set = 0, binding = 6) uniform CastleCascadeShadowBlock {' + NL +
    '  mat4 u_CascadeViewProjMatrix[4];' + NL +
    '  vec4 u_CascadeAtlasUVScaleOffset[4];' + NL +
    '  vec4 u_CascadeSplitDepths;' + NL +
    '} CastleCascadeShadows;' + NL +
    NL +
    'layout(std430, set = 0, binding = 7) readonly buffer CastlePositionalShadowTilesBuffer {' + NL +
    '  CastlePositionalShadowTileData u_ShadowTiles[];' + NL +
    '} CastlePositionalShadowTilesSSBO;' + NL +
    NL +
    'layout(set = 1, binding = 8) uniform sampler2D castle_shadow_atlas_texture;' + NL +
    NL +
    'uvec3 ComputeClusterIndex3D(vec2 fragCoord, float positiveViewDepth) {' + NL +
    '  vec2 screenSize = max(CastleClusterUniforms.u_ScreenAndDepthParams.xy, vec2(1.0));' + NL +
    '  float zNear = max(CastleClusterUniforms.u_ScreenAndDepthParams.z, 1e-3);' + NL +
    '  float zFar = max(CastleClusterUniforms.u_ScreenAndDepthParams.w, zNear + 1e-2);' + NL +
    '  float clampedZ = clamp(positiveViewDepth, zNear, zFar);' + NL +
    '  uint cx = min(uint((fragCoord.x / screenSize.x) * float(CastleClusterUniforms.u_ClusterGridDim.x)), CastleClusterUniforms.u_ClusterGridDim.x - 1u);' + NL +
    '  uint cy = min(uint((fragCoord.y / screenSize.y) * float(CastleClusterUniforms.u_ClusterGridDim.y)), CastleClusterUniforms.u_ClusterGridDim.y - 1u);' + NL +
    '  float sliceF = log(clampedZ / zNear) / max(log(zFar / zNear), 1e-5) * float(CastleClusterUniforms.u_ClusterGridDim.z);' + NL +
    '  uint cz = min(uint(max(sliceF, 0.0)), CastleClusterUniforms.u_ClusterGridDim.z - 1u);' + NL +
    '  return uvec3(cx, cy, cz);' + NL +
    '}' + NL +
    NL +
    'uint FlattenClusterIndex(uvec3 clusterCoord) {' + NL +
    '  return (clusterCoord.z * CastleClusterUniforms.u_ClusterGridDim.y + clusterCoord.y) * CastleClusterUniforms.u_ClusterGridDim.x + clusterCoord.x;' + NL +
    '}' + NL +
    NL +
    'float SampleShadowAtlasPCF3x3(vec2 atlasUV, float compareDepth, vec2 texelSize) {' + NL +
    '  float shadow = 0.0;' + NL +
    '  for (int y = -1; y <= 1; ++y) {' + NL +
    '    for (int x = -1; x <= 1; ++x) {' + NL +
    '      vec2 sampleUV = atlasUV + vec2(float(x), float(y)) * texelSize;' + NL +
    '      float closestDepth = texture(castle_shadow_atlas_texture, sampleUV).r;' + NL +
    '      shadow += (compareDepth <= closestDepth) ? 1.0 : 0.0;' + NL +
    '    }' + NL +
    '  }' + NL +
    '  return shadow * (1.0 / 9.0);' + NL +
    '}' + NL +
    NL +
    'float SampleShadowAtlasPCSS(vec2 atlasUV, float compareDepth, vec2 texelSize) {' + NL +
    '  float blockerSum = 0.0;' + NL +
    '  float blockerCount = 0.0;' + NL +
    '  for (int y = -1; y <= 1; ++y) {' + NL +
    '    for (int x = -1; x <= 1; ++x) {' + NL +
    '      vec2 searchUV = atlasUV + vec2(float(x), float(y)) * texelSize * 2.0;' + NL +
    '      float d = texture(castle_shadow_atlas_texture, searchUV).r;' + NL +
    '      if (d < compareDepth) {' + NL +
    '        blockerSum += d;' + NL +
    '        blockerCount += 1.0;' + NL +
    '      }' + NL +
    '    }' + NL +
    '  }' + NL +
    '  if (blockerCount < 0.5) return 1.0;' + NL +
    '  float avgBlockerDepth = max(blockerSum / blockerCount, 1e-4);' + NL +
    '  float penumbraScale = clamp((compareDepth - avgBlockerDepth) / avgBlockerDepth * 3.0, 1.0, 4.0);' + NL +
    '  return SampleShadowAtlasPCF3x3(atlasUV, compareDepth, texelSize * penumbraScale);' + NL +
    '}' + NL +
    NL +
    'float EvaluateDirectionalCascadeShadow(vec3 worldPos, float positiveViewDepth, float NdotL) {' + NL +
    '  int cascadeIdx = 3;' + NL +
    '  if (positiveViewDepth < CastleCascadeShadows.u_CascadeSplitDepths.x) cascadeIdx = 0;' + NL +
    '  else if (positiveViewDepth < CastleCascadeShadows.u_CascadeSplitDepths.y) cascadeIdx = 1;' + NL +
    '  else if (positiveViewDepth < CastleCascadeShadows.u_CascadeSplitDepths.z) cascadeIdx = 2;' + NL +
    '  vec4 lightClip = CastleCascadeShadows.u_CascadeViewProjMatrix[cascadeIdx] * vec4(worldPos, 1.0);' + NL +
    '  vec3 lightNDC = lightClip.xyz / max(lightClip.w, 1e-5);' + NL +
    '  vec2 uv01 = lightNDC.xy * 0.5 + 0.5;' + NL +
    '  if (uv01.x < 0.0 || uv01.x > 1.0 || uv01.y < 0.0 || uv01.y > 1.0 || lightNDC.z < 0.0 || lightNDC.z > 1.0) return 1.0;' + NL +
    '  vec4 scaleOffset = CastleCascadeShadows.u_CascadeAtlasUVScaleOffset[cascadeIdx];' + NL +
    '  vec2 atlasUV = uv01 * scaleOffset.xy + scaleOffset.zw;' + NL +
    '  float slopeBias = max(0.0025 * (1.0 - max(NdotL, 0.0)), 0.0005);' + NL +
    '  vec2 texelSize = vec2(1.0) / max(vec2(textureSize(castle_shadow_atlas_texture, 0)), vec2(1.0));' + NL +
    '  if (castle_ObjectShadowMapMode == 1)' + NL +
    '    return SampleShadowAtlasPCSS(atlasUV, lightNDC.z - slopeBias, texelSize);' + NL +
    '  return SampleShadowAtlasPCF3x3(atlasUV, lightNDC.z - slopeBias, texelSize);' + NL +
    '}' + NL +
    NL +
    'float EvaluatePositionalAtlasShadow(vec3 worldPos, int shadowTileIdx, float bias) {' + NL +
    '  if (shadowTileIdx < 0) return 1.0;' + NL +
    '  CastlePositionalShadowTileData tile = CastlePositionalShadowTilesSSBO.u_ShadowTiles[shadowTileIdx];' + NL +
    '  vec4 lightClip = tile.LightViewProjMatrix * vec4(worldPos, 1.0);' + NL +
    '  if (lightClip.w <= 1e-5) return 1.0;' + NL +
    '  vec3 lightNDC = lightClip.xyz / lightClip.w;' + NL +
    '  vec2 uv01 = lightNDC.xy * 0.5 + 0.5;' + NL +
    '  if (uv01.x < 0.0 || uv01.x > 1.0 || uv01.y < 0.0 || uv01.y > 1.0 || lightNDC.z < 0.0 || lightNDC.z > 1.0) return 1.0;' + NL +
    '  vec2 atlasUV = uv01 * tile.AtlasUVScaleOffset.xy + tile.AtlasUVScaleOffset.zw;' + NL +
    '  vec2 texelSize = vec2(1.0) / max(vec2(textureSize(castle_shadow_atlas_texture, 0)), vec2(1.0));' + NL +
    '  return SampleShadowAtlasPCF3x3(atlasUV, lightNDC.z - max(bias, 0.0005), texelSize);' + NL +
    '}' + NL +
    NL +
    'vec3 EvaluateClusteredForwardLights(vec2 fragCoord, vec3 eyePos, vec3 worldPos, vec3 N, vec3 V, vec3 baseColor, float metallic, float roughness, bool useShadows) {' + NL +
    '  float positiveViewDepth = max(-eyePos.z, 1e-3);' + NL +
    '  uvec3 clusterCoord = ComputeClusterIndex3D(fragCoord, positiveViewDepth);' + NL +
    '  uint clusterIdx = FlattenClusterIndex(clusterCoord);' + NL +
    '  CastleClusterGridEntryData entry = CastleClusterGridSSBO.u_ClusterGrid[clusterIdx];' + NL +
    '  vec3 totalRadiance = vec3(0.0);' + NL +
    '  uint count = min(entry.Count, 64u);' + NL +
    '  for (uint i = 0u; i < count; ++i) {' + NL +
    '    uint lightIdx = CastleClusterLightIndexSSBO.u_ClusterLightIndices[entry.Offset + i];' + NL +
    '    CastleClusteredLightData cl = CastleClusteredLightsSSBO.u_ClusteredLights[lightIdx];' + NL +
    '    int lightType = int(cl.ShadowAndTypeParams.x + 0.5);' + NL +
    '    vec3 L;' + NL +
    '    float attenuation = 1.0;' + NL +
    '    if (lightType == 0) {' + NL +
    '      L = normalize(-cl.DirectionAndSpotCos.xyz);' + NL +
    '    } else {' + NL +
    '      vec3 toLight = cl.PositionAndRange.xyz - eyePos;' + NL +
    '      float dist = length(toLight);' + NL +
    '      float range = max(cl.PositionAndRange.w, 1e-4);' + NL +
    '      if (dist >= range) continue;' + NL +
    '      L = toLight / max(dist, 1e-5);' + NL +
    '      float distRatio = dist / range;' + NL +
    '      float windowFactor = max(1.0 - pow(distRatio, 4.0), 0.0);' + NL +
    '      attenuation = (windowFactor * windowFactor) / (dist * dist + 1.0);' + NL +
    '      if (lightType == 2) {' + NL +
    '        float cosDir = dot(-L, normalize(cl.DirectionAndSpotCos.xyz));' + NL +
    '        float outerCos = cl.DirectionAndSpotCos.w;' + NL +
    '        float innerCos = max(cl.ShadowAndTypeParams.y, outerCos + 1e-4);' + NL +
    '        float spotFactor = clamp((cosDir - outerCos) / (innerCos - outerCos), 0.0, 1.0);' + NL +
    '        attenuation *= spotFactor * spotFactor;' + NL +
    '      }' + NL +
    '    }' + NL +
    '    if (attenuation <= 0.0) continue;' + NL +
    '    float shadowVis = 1.0;' + NL +
    '    if (useShadows) {' + NL +
    '      if (lightType == 0) {' + NL +
    '        shadowVis = EvaluateDirectionalCascadeShadow(worldPos, positiveViewDepth, max(dot(N, L), 0.0));' + NL +
    '      } else {' + NL +
    '        int tileIdx = int(floor(cl.ShadowAndTypeParams.z + 0.5));' + NL +
    '        shadowVis = EvaluatePositionalAtlasShadow(worldPos, tileIdx, cl.ShadowAndTypeParams.w);' + NL +
    '      }' + NL +
    '    }' + NL +
    '    vec3 radiance = cl.ColorAndIntensity.rgb * (cl.ColorAndIntensity.w * attenuation * shadowVis);' + NL +
    '    totalRadiance += EvaluateDirectCookTorranceGGX(N, V, L, radiance, baseColor, metallic, roughness);' + NL +
    '  }' + NL +
    '  return totalRadiance;' + NL +
    '}' + NL;
end;

function TCastleShaderGeneratorRHI.GenerateDefault3DFragmentShader(
  const HasBaseColorTex: Boolean;
  const HasNormalTex: Boolean;
  const HasMetallicRoughnessTex: Boolean;
  const HasEmissiveTex: Boolean;
  const HasOcclusionTex: Boolean;
  const HasIBL: Boolean;
  const UseAlphaTest: Boolean;
  const HasClusteredForward: Boolean;
  const HasCascadedShadows: Boolean): String;
begin
  Result :=
    GeneratePreamble(ssFragment) +
    GeneratePBRFunctions + NL;

  if HasClusteredForward or HasCascadedShadows then
    Result := Result + GenerateClusteredForwardAndShadowFunctions + NL;

  Result := Result +
    'void main() {' + NL +
    '  vec4 baseColor = castle_MaterialBaseColor;' + NL;

  if HasBaseColorTex then
    Result := Result +
      '  baseColor *= texture(castle_base_color_texture, castle_tex_coord0);' + NL;

  if UseAlphaTest then
    Result := Result +
      '  if (baseColor.a < castle_AlphaCutoff) discard;' + NL;

  Result := Result +
    '  /* Unlit Material Early Out (SpecularColor.a < 0.0) */' + NL +
    '  if (castle_MaterialShininess < 0.0) {' + NL;
  if HasEmissiveTex then
    Result := Result +
      '    vec3 unlitColor = baseColor.rgb + castle_MaterialEmissive * texture(castle_emissive_texture, castle_tex_coord0).rgb;' + NL
  else
    Result := Result +
      '    vec3 unlitColor = baseColor.rgb + castle_MaterialEmissive;' + NL;
  Result := Result +
    '    castle_FragColor = vec4(unlitColor, baseColor.a);' + NL +
    '    return;' + NL +
    '  }' + NL +
    NL +
    '  float metallic = clamp(castle_MaterialMetallic, 0.0, 1.0);' + NL +
    '  float roughness = clamp(castle_MaterialRoughness, 0.04, 1.0);' + NL;

  if HasMetallicRoughnessTex then
    Result := Result +
      '  vec4 mrSample = texture(castle_metallic_roughness_texture, castle_tex_coord0);' + NL +
      '  roughness = clamp(roughness * mrSample.g, 0.04, 1.0);' + NL +
      '  metallic = clamp(metallic * mrSample.b, 0.0, 1.0);' + NL;

  Result := Result +
    '  float ao = 1.0;' + NL;
  if HasOcclusionTex then
    Result := Result +
      '  float occSample = texture(castle_occlusion_texture, castle_tex_coord0).r;' + NL +
      '  ao = mix(1.0, occSample, clamp(castle_MaterialOcclusionStrength, 0.0, 1.0));' + NL;

  Result := Result +
    '  vec3 N = normalize(castle_normal_eye);' + NL +
    '  vec3 V = normalize(-castle_vertex_eye.xyz);' + NL;

  if HasNormalTex then
    Result := Result +
      '  vec3 tangentNormal = texture(castle_normal_texture, castle_tex_coord0).xyz * 2.0 - 1.0;' + NL +
      '  N = PerturbNormalCotangent(N, -castle_vertex_eye.xyz, castle_tex_coord0, tangentNormal, castle_MaterialNormalScale);' + NL;

  Result := Result +
    '  if (castle_ObjectSpecularAAEnabled) {' + NL +
    '    vec3 dndu = dFdx(N);' + NL +
    '    vec3 dndv = dFdy(N);' + NL +
    '    float normalVar = 0.25 * (dot(dndu, dndu) + dot(dndv, dndv));' + NL +
    '    float kernelRoughness2 = min(2.0 * normalVar, 0.18);' + NL +
    '    roughness = clamp(sqrt(clamp(roughness * roughness + kernelRoughness2, 0.0, 1.0)), 0.04, 1.0);' + NL +
    '  }' + NL +
    '  vec3 Lo = vec3(0.0);' + NL;

  if HasClusteredForward then
  begin
    Result := Result +
      '  vec3 worldPos = (castle_ViewMatrixInverse * castle_vertex_eye).xyz;' + NL +
      Format('  Lo += EvaluateClusteredForwardLights(gl_FragCoord.xy, castle_vertex_eye.xyz, worldPos, N, V, baseColor.rgb, metallic, roughness, %s);',
        [IfThen(HasCascadedShadows, 'true', 'false')]) + NL;
  end else
  begin
    Result := Result +
      '  uint lightCount = min(castle_LightCount, 32u);' + NL +
      '  for (uint i = 0u; i < lightCount; ++i) {' + NL +
      '    CastleLightData light = CastleLights.u_Lights[i];' + NL +
      '    vec3 L;' + NL +
      '    float attenuation = 1.0;' + NL +
      '    if (light.Position.w == 0.0) {' + NL +
      '      L = normalize(-light.Position.xyz);' + NL +
      '    } else {' + NL +
      '      vec3 toLight = light.Position.xyz - castle_vertex_eye.xyz;' + NL +
      '      float dist = length(toLight);' + NL +
      '      L = toLight / max(dist, 1e-5);' + NL +
      '      float attenDenom = light.Attenuation.x + light.Attenuation.y * dist + light.Attenuation.z * dist * dist;' + NL +
      '      if (attenDenom > 0.0) attenuation = 1.0 / attenDenom;' + NL +
      '      if (light.Color.w > 0.0 && dist > light.Color.w) attenuation = 0.0;' + NL +
      '      if (light.Position.w > 1.5 && light.SpotDirection.w >= 0.0) {' + NL +
      '        float cosDir = dot(-L, normalize(light.SpotDirection.xyz));' + NL +
      '        if (cosDir < light.SpotDirection.w) {' + NL +
      '          attenuation = 0.0;' + NL +
      '        } else if (light.SpotParams.y > 0.0 && light.SpotParams.y < light.SpotParams.x) {' + NL +
      '          attenuation *= clamp((acos(clamp(cosDir, -1.0, 1.0)) - light.SpotParams.x) / (light.SpotParams.y - light.SpotParams.x), 0.0, 1.0);' + NL +
      '        } else if (light.SpotParams.z > 0.0) {' + NL +
      '          attenuation *= pow(max(cosDir, 0.0), light.SpotParams.z);' + NL +
      '        }' + NL +
      '      }' + NL +
      '    }' + NL +
      '    float shadowVis = 1.0;' + NL;
    if HasCascadedShadows then
      Result := Result +
        '    if (light.Position.w == 0.0) {' + NL +
        '      vec3 worldPos = (castle_ViewMatrixInverse * castle_vertex_eye).xyz;' + NL +
        '      shadowVis = EvaluateDirectionalCascadeShadow(worldPos, max(-castle_vertex_eye.z, 1e-3), max(dot(N, L), 0.0));' + NL +
        '    }' + NL;
    Result := Result +
      '    vec3 radiance = light.Color.rgb * (attenuation * shadowVis);' + NL +
      '    Lo += EvaluateDirectCookTorranceGGX(N, V, L, radiance, baseColor.rgb, metallic, roughness);' + NL +
      '    Lo += light.AmbientColor.rgb * baseColor.rgb * (ao * attenuation);' + NL +
      '  }' + NL;
  end;

  if HasIBL then
    Result := Result +
      '  float NdotV = max(dot(N, V), 1e-4);' + NL +
      '  vec3 R = reflect(-V, N);' + NL +
      '  vec3 worldR = mat3(castle_ViewMatrixInverse) * R;' + NL +
      '  vec3 prefilteredEnv = textureLod(castle_env_specular_texture, worldR, roughness * 4.0).rgb;' + NL +
      '  vec2 brdfLut = texture(castle_brdf_lut_texture, vec2(NdotV, roughness)).rg;' + NL +
      '  vec3 diffuseIrradiance = textureLod(castle_env_specular_texture, mat3(castle_ViewMatrixInverse) * N, 4.0).rgb;' + NL +
      '  Lo += EvaluateIBLCookTorranceGGX(N, V, baseColor.rgb, metallic, roughness, ao, diffuseIrradiance, prefilteredEnv, brdfLut);' + NL;

  Result := Result +
    '  vec3 emissive = castle_MaterialEmissive;' + NL;
  if HasEmissiveTex then
    Result := Result +
      '  emissive *= texture(castle_emissive_texture, castle_tex_coord0).rgb;' + NL;

  Result := Result +
    '  castle_FragColor = vec4(Lo + emissive, baseColor.a);' + NL +
    '}' + NL;
end;

{$endif read_implementation}
