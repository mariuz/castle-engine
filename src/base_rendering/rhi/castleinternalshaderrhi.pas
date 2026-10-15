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

{ Upgrade extension for CastleRendererInternalShader to emit Vulkan GLSL 450
  (UBOs, Push Constants, explicit stage locations) alongside OpenGL/OpenGLES. }
unit CastleInternalShaderRHI;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, StrUtils, Generics.Collections,
  CastleVectors, CastleColors, CastleStringUtils, CastleLog,
  CastleInternalRHI;

const
  { Maximum bone matrices supported in Set 2 skinning UBO }
  CASTLE_MAX_BONE_MATRICES = 256;
  { Maximum lights supported in Set 0 Binding 1 lights UBO }
  CASTLE_MAX_LIGHTS = 32;

type
  { Standard CGE Vertex Attribute Locations (strictly fixed across all shaders) }
  TCastleVertexLocation = (
    vlPosition    = 0,
    vlNormal      = 1,
    vlTexCoord0   = 2,
    vlTexCoord1   = 3,
    vlColor       = 4,
    vlTangent     = 5,
    vlJoints0     = 6,
    vlWeights0    = 7
  );

  { CPU-side mirror of Set 0, Binding 0 (Per-Pass / Global Scene UBO - std140) }
  PCastleSceneUniformBlock = ^TCastleSceneUniformBlock;
  TCastleSceneUniformBlock = packed record
    ProjectionMatrix: TMatrix4;
    ViewMatrix: TMatrix4;
    ViewMatrixInverse: TMatrix4;
    CameraPosition: TVector4;       // xyz = World Eye Pos, w = Scene Time
    FogColor: TVector4;             // rgb = Fog Color, a = Fog Density
    FogParams: TVector4;            // x = Start, y = End, z = Type, w = Reserved
    LightCount: Cardinal;
    Padding0, Padding1, Padding2: Cardinal;
  end;

  { CPU-side mirror of a single light entry in CastleLightsBlock (std140) }
  PCastleLightData = ^TCastleLightData;
  TCastleLightData = packed record
    Position: TVector4;         // xyz = eye-space position/direction, w = light type (0=dir, 1=point, 2=spot)
    Color: TVector4;            // rgb = color * intensity, w = radius
    SpotDirection: TVector4;    // xyz = eye-space direction, w = spotCosCutoff
    SpotParams: TVector4;       // x = spotCutoff (rad), y = beamWidth (rad), z = spotExponent, w = reserved
    Attenuation: TVector4;      // xyz = constant, linear, quadratic factors, w = reserved
    AmbientColor: TVector4;     // rgb = ambient color * ambient intensity, w = shadow map index / enabled (1.0)
    ProjectorMatrix: TMatrix4;  // 64 bytes: eye-to-light-clip-space projector matrix for shadow mapping
  end; // 6 * 16 + 64 = 160 bytes (160 mod 16 = 0)

  { CPU-side mirror of Set 0, Binding 1 (Multi-Light UBO - std140) }
  PCastleLightsUniformBlock = ^TCastleLightsUniformBlock;
  TCastleLightsUniformBlock = packed record
    Count: Cardinal;                                                // 4 bytes
    Padding0, Padding1, Padding2: Cardinal;                         // 12 bytes
    Lights: array [0 .. CASTLE_MAX_LIGHTS - 1] of TCastleLightData; // 32 * 160 = 5120 bytes
    procedure Clear;
    function AddDirectionalLight(const Direction, Color, AmbientColor: TVector3): Integer;
    function AddPointLight(const Position, Color, AmbientColor: TVector3;
      const Attenuation: TVector3; const Radius: Single): Integer;
    function AddSpotLight(const Position, Direction, Color, AmbientColor: TVector3;
      const Attenuation: TVector3; const Radius, SpotCosCutoff, SpotCutoff, BeamWidth, SpotExponent: Single): Integer;
    procedure SetProjectorMatrix(const Index: Integer; const Matrix: TMatrix4);
  end; // Total = 5136 bytes (5136 mod 16 = 0)

  { CPU-side mirror of Set 1, Binding 0 (Per-Material UBO - std140) }
  PCastleMaterialUniformBlock = ^TCastleMaterialUniformBlock;
  TCastleMaterialUniformBlock = packed record
    BaseColor: TVector4;            // PBR BaseColor / Phong DiffuseColor + Opacity
    SpecularColor: TVector4;        // rgb = Specular, a = Shininess
    EmissiveColor: TVector4;        // rgb = Emissive, a = Metallic
    PBRParams: TVector4;            // x = Roughness, y = NormalScale, z = OcclusionStrength, w = AlphaCutoff
  end;

  { CPU-side mirror of Per-Draw Push Constants (128 bytes max, guaranteed by Vulkan spec) }
  PCastlePushConstantsBlock = ^TCastlePushConstantsBlock;
  TCastlePushConstantsBlock = packed record
    ModelViewMatrix: TMatrix4;      // 64 bytes
    NormalMatrixRow0: TVector4;     // 16 bytes (std140 padded 3x3 normal matrix)
    NormalMatrixRow1: TVector4;     // 16 bytes
    NormalMatrixRow2: TVector4;     // 16 bytes
    ObjectParams: TVector4;         // 16 bytes (x = MaterialIndex, y = BoneOffset, zw = Custom)
  end; // Total = 128 bytes

  { CPU-side mirror of Set 2, Binding 0 (Per-Object Skinning UBO - std140) }
  PCastleSkinningUniformBlock = ^TCastleSkinningUniformBlock;
  TCastleSkinningUniformBlock = packed record
    JointMatrices: array [0 .. CASTLE_MAX_BONE_MATRICES - 1] of TMatrix4; // 256 * 64 = 16384 bytes
    JointCount: Cardinal;
    Padding0, Padding1, Padding2: Cardinal;
  end;

  { Generates RHI-compliant GLSL headers, UBO blocks, and varying layouts }
  TCastleShaderGeneratorRHI = class
  private
    FBackend: TRHIBackendType;
    function GenerateVersionAndLayoutMacros: String;
    function GenerateStandardUniformBlocks(const AStage: TRHIShaderStage): String;
    function GenerateStageIO(const AStage: TRHIShaderStage): String;
  public
    constructor Create(const ABackend: TRHIBackendType);

    { Builds the complete preamble injected before CGE's internal GLSL templates }
    function GeneratePreamble(const AStage: TRHIShaderStage): String;

    { Transforms legacy user X3D EffectPart uniform declarations into a std140 UBO
      at Set 2, Binding 0 so existing custom shaders compile in Vulkan }
    function UpgradeUserEffectUniforms(const UserEffectSource: String): String;

    { Appends Vulkan clip-space depth adjustment (Z from [-1..1] to [0..1])
      at the end of the vertex shader main() }
    function FinalizeVertexShaderSource(const StitchedSource: String): String;

    { Strips or comments out legacy bare uniform declarations replaced by Set 0..2 UBOs and Push Constants }
    function SanitizeVulkanShaderSource(const Source: String): String;

    { Computes the 64-bit FNV-1a hash of the final GLSL source for on-disk SPIR-V caching }
    class function ComputeSourceHash(const FinalGLSL: String): UInt64; static;
  end;

implementation

const
  NL = LineEnding;

{ TCastleLightsUniformBlock }

procedure TCastleLightsUniformBlock.Clear;
begin
  FillChar(Self, SizeOf(Self), 0);
end;

function TCastleLightsUniformBlock.AddDirectionalLight(const Direction, Color,
  AmbientColor: TVector3): Integer;
begin
  if Count >= CASTLE_MAX_LIGHTS then Exit(-1);
  Result := Count;
  Lights[Result].Position := Vector4(Direction, 0.0);
  Lights[Result].Color := Vector4(Color, 0.0);
  Lights[Result].SpotDirection := Vector4(0, 0, -1, -1.0);
  Lights[Result].SpotParams := Vector4(0, 0, 0, 0);
  Lights[Result].Attenuation := Vector4(1, 0, 0, 0);
  Lights[Result].AmbientColor := Vector4(AmbientColor, 1.0);
  Lights[Result].ProjectorMatrix := TMatrix4.Identity;
  Inc(Count);
end;

function TCastleLightsUniformBlock.AddPointLight(const Position, Color,
  AmbientColor: TVector3; const Attenuation: TVector3; const Radius: Single): Integer;
begin
  if Count >= CASTLE_MAX_LIGHTS then Exit(-1);
  Result := Count;
  Lights[Result].Position := Vector4(Position, 1.0);
  Lights[Result].Color := Vector4(Color, Radius);
  Lights[Result].SpotDirection := Vector4(0, 0, -1, -1.0);
  Lights[Result].SpotParams := Vector4(0, 0, 0, 0);
  Lights[Result].Attenuation := Vector4(Attenuation, 0);
  Lights[Result].AmbientColor := Vector4(AmbientColor, 1.0);
  Lights[Result].ProjectorMatrix := TMatrix4.Identity;
  Inc(Count);
end;

function TCastleLightsUniformBlock.AddSpotLight(const Position, Direction, Color,
  AmbientColor: TVector3; const Attenuation: TVector3; const Radius, SpotCosCutoff,
  SpotCutoff, BeamWidth, SpotExponent: Single): Integer;
begin
  if Count >= CASTLE_MAX_LIGHTS then Exit(-1);
  Result := Count;
  Lights[Result].Position := Vector4(Position, 2.0);
  Lights[Result].Color := Vector4(Color, Radius);
  Lights[Result].SpotDirection := Vector4(Direction, SpotCosCutoff);
  Lights[Result].SpotParams := Vector4(SpotCutoff, BeamWidth, SpotExponent, 0);
  Lights[Result].Attenuation := Vector4(Attenuation, 0);
  Lights[Result].AmbientColor := Vector4(AmbientColor, 1.0);
  Lights[Result].ProjectorMatrix := TMatrix4.Identity;
  Inc(Count);
end;

procedure TCastleLightsUniformBlock.SetProjectorMatrix(const Index: Integer;
  const Matrix: TMatrix4);
begin
  if (Index >= 0) and (Index < Integer(Count)) then
    Lights[Index].ProjectorMatrix := Matrix;
end;

{ TCastleShaderGeneratorRHI }

constructor TCastleShaderGeneratorRHI.Create(const ABackend: TRHIBackendType);
begin
  inherited Create;
  FBackend := ABackend;
end;

function TCastleShaderGeneratorRHI.GenerateVersionAndLayoutMacros: String;
begin
  case FBackend of
    rbVulkan:
      Result :=
        '#version 450' + NL +
        '#define CASTLE_VULKAN 1' + NL +
        '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140, set = SetIdx, binding = BindIdx)' + NL +
        '#define CASTLE_SSBO(SetIdx, BindIdx) layout(std430, set = SetIdx, binding = BindIdx)' + NL +
        '#define CASTLE_SAMPLER(SetIdx, BindIdx) layout(set = SetIdx, binding = BindIdx)' + NL +
        '#define CASTLE_PUSH_CONSTANT layout(push_constant)' + NL +
        '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
        '#define CASTLE_VERTEX_INDEX gl_VertexIndex' + NL +
        '#define CASTLE_INSTANCE_INDEX gl_InstanceIndex' + NL;

    rbOpenGL:
      Result :=
        '#version 330 core' + NL +
        '#extension GL_ARB_shading_language_420pack : enable' + NL +
        '#extension GL_ARB_explicit_attrib_location : enable' + NL +
        '#define CASTLE_OPENGL 1' + NL +
        { Flattens (SetIdx, BindIdx) to match GL_DESCRIPTOR_SET_SLOT_STRIDE = 4 }
        '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140, binding = (SetIdx * 4 + BindIdx))' + NL +
        '#define CASTLE_SAMPLER(SetIdx, BindIdx) layout(binding = (SetIdx * 4 + BindIdx))' + NL +
        { Maps Push Constants to reserved UBO slot 15 in OpenGL }
        '#define CASTLE_PUSH_CONSTANT layout(std140, binding = 15)' + NL +
        '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
        '#define CASTLE_VERTEX_INDEX gl_VertexID' + NL +
        '#define CASTLE_INSTANCE_INDEX gl_InstanceID' + NL;

    rbOpenGLES:
      Result :=
        '#version 300 es' + NL +
        'precision highp float;' + NL +
        'precision highp int;' + NL +
        '#define CASTLE_OPENGLES 1' + NL +
        '#define CASTLE_UBO(SetIdx, BindIdx) layout(std140)' + NL +
        '#define CASTLE_SAMPLER(SetIdx, BindIdx)' + NL +
        '#define CASTLE_PUSH_CONSTANT layout(std140)' + NL +
        '#define CASTLE_LOCATION(LocIdx) layout(location = LocIdx)' + NL +
        '#define CASTLE_VERTEX_INDEX gl_VertexID' + NL +
        '#define CASTLE_INSTANCE_INDEX gl_InstanceID' + NL;
  end;
end;

function TCastleShaderGeneratorRHI.GenerateStandardUniformBlocks(
  const AStage: TRHIShaderStage): String;
var
  LightAliases: String;
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
    '#define castle_AlphaCutoff CastleMaterial.u_PBRParams.w' + NL +
    NL +
    'CASTLE_SAMPLER(1, 1) uniform sampler2D castle_base_color_texture;' + NL +
    'CASTLE_SAMPLER(1, 2) uniform sampler2D castle_normal_texture;' + NL +
    'CASTLE_SAMPLER(1, 3) uniform sampler2D castle_metallic_roughness_texture;' + NL +
    'CASTLE_SAMPLER(1, 4) uniform sampler2D castle_emissive_texture;' + NL +
    NL +
    '/* --- Set 2: Per-Object / Skinning Uniforms --- */' + NL +
    'CASTLE_UBO(2, 0) uniform CastleSkinningBlock {' + NL +
    '  mat4 u_JointMatrices[256];' + NL +
    '  uint u_JointCount;' + NL +
    '} CastleSkinning;' + NL +
    NL +
    '#define castle_JointMatrix CastleSkinning.u_JointMatrices' + NL +
    NL +
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
    '#define castle_NormalMatrix mat3(CastleDraw.u_NormalMatrixRow0.xyz, CastleDraw.u_NormalMatrixRow1.xyz, CastleDraw.u_NormalMatrixRow2.xyz)' + NL;
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
        'CASTLE_LOCATION(6) in uvec4 castle_Joints0;' + NL +
        'CASTLE_LOCATION(7) in vec4 castle_Weights0;' + NL +
        NL +
        '/* --- Vertex-to-Fragment Varyings --- */' + NL +
        'CASTLE_LOCATION(0) out vec4 castle_vertex_eye;' + NL +
        'CASTLE_LOCATION(1) out vec3 castle_normal_eye;' + NL +
        'CASTLE_LOCATION(2) out vec2 castle_tex_coord0;' + NL +
        'CASTLE_LOCATION(3) out vec2 castle_tex_coord1;' + NL +
        'CASTLE_LOCATION(4) out vec4 castle_color_per_vertex;' + NL +
        'CASTLE_LOCATION(5) out mat3 castle_tangent_to_eye_space;' + NL;

    ssFragment:
      Result :=
        '/* --- Fragment Inputs (Must match Vertex Outputs by Location) --- */' + NL +
        'CASTLE_LOCATION(0) in vec4 castle_vertex_eye;' + NL +
        'CASTLE_LOCATION(1) in vec3 castle_normal_eye;' + NL +
        'CASTLE_LOCATION(2) in vec2 castle_tex_coord0;' + NL +
        'CASTLE_LOCATION(3) in vec2 castle_tex_coord1;' + NL +
        'CASTLE_LOCATION(4) in vec4 castle_color_per_vertex;' + NL +
        'CASTLE_LOCATION(5) in mat3 castle_tangent_to_eye_space;' + NL +
        NL +
        '/* --- Fragment Color Output --- */' + NL +
        'CASTLE_LOCATION(0) out vec4 castle_FragColor;' + NL;
  else
    Result := '';
  end;
end;

function TCastleShaderGeneratorRHI.GeneratePreamble(const AStage: TRHIShaderStage): String;
begin
  Result :=
    GenerateVersionAndLayoutMacros + NL +
    GenerateStandardUniformBlocks(AStage) + NL +
    GenerateStageIO(AStage) + NL;
end;

function TCastleShaderGeneratorRHI.UpgradeUserEffectUniforms(
  const UserEffectSource: String): String;
var
  Lines: TStringList;
  UBOMembers, AliasDefines, StrippedBody: TStringBuilder;
  Line, Trimmed, DeclBody, VarType, VarName: String;
  SpacePos, SemiPos, CustomSamplerSlot: Integer;
begin
  { Parses custom user EffectPart code looking for bare "uniform float my_var;"
    declarations. Sampler uniforms are assigned to Set 2 bindings 1+, and value
    uniforms are packed into a generated Set 2, Binding 0 UBO with #define aliases. }
  Lines := TStringList.Create;
  UBOMembers := TStringBuilder.Create;
  AliasDefines := TStringBuilder.Create;
  StrippedBody := TStringBuilder.Create;
  try
    Lines.Text := UserEffectSource;
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
            UBOMembers.AppendLine(Format('  %s u_user_%s;', [VarType, VarName]));
            AliasDefines.AppendLine(Format('#define %s CastleUserEffect.u_user_%s',
              [VarName, VarName]));
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

function TCastleShaderGeneratorRHI.SanitizeVulkanShaderSource(
  const Source: String): String;
var
  Lines: TStringList;
  ResultBuilder: TStringBuilder;
  Line, Trimmed: String;
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
      if IsPrefix('uniform ', Trimmed, False) and
         ( (Pos('castle_LightSource', Trimmed) > 0) or
           (Pos('castle_projector_matrix', Trimmed) > 0) or
           (Pos('castle_ModelViewMatrix', Trimmed) > 0) or
           (Pos('castle_ProjectionMatrix', Trimmed) > 0) or
           (Pos('castle_NormalMatrix', Trimmed) > 0) or
           (Pos('castle_JointMatrix', Trimmed) > 0) or
           (Pos('castle_Material', Trimmed) > 0) or
           (Pos('castle_WorldEyePosition', Trimmed) > 0) or
           (Pos('castle_SceneTime', Trimmed) > 0) or
           (Pos('castle_Fog', Trimmed) > 0) ) and
         (Pos('{', Trimmed) = 0) then
      begin
        ResultBuilder.AppendLine('// [Vulkan RHI UBO]: ' + Line);
      end else
        ResultBuilder.AppendLine(Line);
    end;
    Result := ResultBuilder.ToString;
  finally
    FreeAndNil(ResultBuilder);
    FreeAndNil(Lines);
  end;
end;

class function TCastleShaderGeneratorRHI.ComputeSourceHash(const FinalGLSL: String): UInt64;
const
  FNV_OFFSET_BASIS: UInt64 = QWord($CBF29CE484222325);
  FNV_PRIME: UInt64 = $100000001B3;
var
  I: Integer;
begin
  {$Q-}{$R-}
  Result := FNV_OFFSET_BASIS;
  for I := 1 to Length(FinalGLSL) do
  begin
    Result := Result xor Ord(FinalGLSL[I]);
    Result := Result * FNV_PRIME;
  end;
  {$Q+}{$R+}
end;

end.
