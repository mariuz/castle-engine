{%MainUnit castlerendererinternalshader.pas}
{
  Copyright 2010-2024 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Generating shader code for shadow maps. }

{$ifdef read_interface}

//type
  { How the views (tiles) of a shadow map are used. }
  TShadowMapKind = (
    { One view: spot light, or directional light without cascades. }
    smkSingle,
    { 6 views, the cube faces around a point light. }
    smkPoint,
    { 2 to 4 views, cascades of a directional light, chosen by the distance
      from the camera. }
    smkCascades
  );

  { Generating shadow map shader code.

    Initially, TShader.EnableShadowMap only initialized this and calls PrepareHash.

    Later, once we know we need to generate new code,
    and once light shader code is fully known
    (e.g. we know lighting model, physical or Phong) -> then GenerateCode is called.

    Uniforms are set by SetUniforms (once, after linking)
    and SetDynamicUniforms (each frame).

    The shadow map has one or more views (tiles, see ShadowMapKind),
    in one texture that may be shared by many shadow maps
    (the shadow map atlas): then they share the TextureUnit,
    and Id makes the names of the uniforms of each shadow map unique. }
  TShadowMapShader = record
  strict private
    function ShadowMapName: String;
    function UniformName(const Suffix: String): String;
  public
    TextureUnit: Integer;
    Id: Integer;
    ShadowMap: TGeneratedShadowMapNode;
    { How the views of a shadow map of this light are used, and how many there are. }
    class function ShadowMapKind(const Light: TAbstractPunctualLightNode;
      out TileCount: Integer): TShadowMapKind; static;
    procedure PrepareHash(var Hash: TShaderCodeHash);
    procedure GenerateCode(const Shader: TShader);
    procedure SetUniformsOnce(const AProgram: TX3DShaderProgram);
    procedure SetDynamicUniforms(const AProgram: TX3DShaderProgram;
      const RenderingCamera: TRenderingCamera);
  end;

  { List of TShadowMapShader, containing all shadow maps used
    when rendering one shape.
    The methods here just call corresponding TShadowMapShader methods
    on all children.
    Follows castlerendererinternalshader_feature_api.md API conventions. }
  TShadowMapShaderList = class({$ifdef FPC}specialize{$endif} TStructList<TShadowMapShader>)
  public
    procedure GenerateCode(const Shader: TShader);
    procedure SetUniformsOnce(const AProgram: TX3DShaderProgram);
    procedure SetDynamicUniforms(const AProgram: TX3DShaderProgram;
      const RenderingCamera: TRenderingCamera);
  end;

{$endif read_interface}

{$ifdef read_implementation}

{ TShadowMapShader ----------------------------------------------------------- }

class function TShadowMapShader.ShadowMapKind(const Light: TAbstractPunctualLightNode;
  out TileCount: Integer): TShadowMapKind;
begin
  if Light is TAbstractPointLightNode then
  begin
    TileCount := 6;
    Result := smkPoint;
  end else
  if (Light is TAbstractDirectionalLightNode) and
     (TAbstractDirectionalLightNode(Light).ShadowCascades > 1) then
  begin
    TileCount := Min(TAbstractDirectionalLightNode(Light).ShadowCascades, 4);
    Result := smkCascades;
  end else
  begin
    TileCount := 1;
    Result := smkSingle;
  end;
end;

procedure TShadowMapShader.PrepareHash(var Hash: TShaderCodeHash);
var
  Kind: TShadowMapKind;
  TileCount: Integer;
begin
  Hash.AddInteger(6353 * TextureUnit);
  Hash.AddInteger(4093 * (Id + 1));
  Hash.AddPointer(ShadowMap);
  if ShadowMap.Light is TAbstractPunctualLightNode then
  begin
    Kind := ShadowMapKind(TAbstractPunctualLightNode(ShadowMap.Light), TileCount);
    Hash.AddInteger(2591 * (Ord(Kind) + 1) + 37 * TileCount);
  end;
end;

function TShadowMapShader.ShadowMapName: String;
begin
  Result := 'castle_shadow_map_' + IntToStr(TextureUnit);
end;

function TShadowMapShader.UniformName(const Suffix: String): String;
begin
  Result := 'castle_shadow_' + IntToStr(Id) + '_' + Suffix;
end;

procedure TShadowMapShader.GenerateCode(const Shader: TShader);
const
  { The fragment position in eye space, shared by all shadow maps.
    The define avoids declaring it again
    when the shader code is glued into one (on OpenGLES). }
  VertexEyeDeclare =
    '#ifndef CASTLE_SHADOW_VERTEX_EYE' + NL +
    '#define CASTLE_SHADOW_VERTEX_EYE' + NL +
    'varying shadowsPrecision vec4 castle_shadow_vertex_eye;' + NL +
    '#endif' + NL;
  VectorComponent: array [0..3] of String = ('x', 'y', 'z', 'w');
var
  SamplerType, Declarations, Body, M, R: String;
  ShadowLightShader: TLightShader;
  Kind: TShadowMapKind;
  TileCount, K: Integer;

  function TileChoice(const Index: Integer): String;
  begin
    Result := Format('{ m = %s; r = %s; o = %s; }', [
      UniformName('matrix_' + IntToStr(Index)),
      UniformName('rect_' + IntToStr(Index)),
      UniformName('offset_' + IntToStr(Index))
    ]);
  end;

begin
  // we pass here only TGeneratedShadowMapNode with light node set
  Assert(ShadowMap.Light <> nil);

  if not Shader.LightShaders.Find(ShadowMap.Light, ShadowLightShader) then
    Exit;
  if not (ShadowMap.Light is TAbstractPunctualLightNode) then
    Exit;
  Kind := ShadowMapKind(TAbstractPunctualLightNode(ShadowMap.Light), TileCount);

  { For variance shadow maps, use normal sampler2D, not sampler2DShadow }
  if Shader.ShadowSampling = ssVarianceShadowMaps then
    SamplerType := 'sampler2D'
  else
    SamplerType := 'sampler2DShadow';

  { Vertex shader passes the vertex position in eye space. }
  Shader.Plug(stVertex,
    StringReplace(VertexEyeDeclare, 'shadowsPrecision ', '', []) +
    'void PLUG_vertex_eye_space(const in vec4 vertex_eye, const in vec3 normal_eye)' + NL +
    '{' + NL +
    '  castle_shadow_vertex_eye = vertex_eye;' + NL +
    '}' + NL);

  Declarations :=
    Format('#ifndef CASTLE_SHADOW_MAP_%d', [TextureUnit]) + NL +
    Format('#define CASTLE_SHADOW_MAP_%d', [TextureUnit]) + NL +
    Format('uniform %s %s;', [SamplerType, ShadowMapName]) + NL +
    '#endif' + NL +
    VertexEyeDeclare +
    Format('uniform vec2 %s;', [UniformName('texel')]) + NL;
  for K := 0 to TileCount - 1 do
  begin
    Declarations := Declarations +
      Format('uniform mat4 %s;', [UniformName('matrix_' + IntToStr(K))]) + NL +
      Format('uniform vec4 %s;', [UniformName('rect_' + IntToStr(K))]) + NL;
    if Kind <> smkSingle then
      Declarations := Declarations +
        Format('uniform float %s;', [UniformName('offset_' + IntToStr(K))]) + NL;
  end;

  M := UniformName('matrix_0');
  R := UniformName('rect_0');
  case Kind of
    smkSingle:
      Body := Format('  scale *= castle_shadow_tile(%s, %s * castle_shadow_vertex_eye, %s, %s, false);', [
        ShadowMapName, M, R, UniformName('texel')]) + NL;
    smkPoint:
      begin
        Declarations := Declarations +
          Format('uniform mat4 %s;', [UniformName('to_light')]) + NL;
        { Choose the cube face by the largest coordinate
          of the direction from the light (in world space),
          faces are +X, -X, +Y, -Y, +Z, -Z. }
        Body :=
          Format('  vec3 d = (%s * castle_shadow_vertex_eye).xyz;', [UniformName('to_light')]) + NL +
          '  vec3 a = abs(d);' + NL +
          '  mat4 m;' + NL +
          '  vec4 r;' + NL +
          '  float o;' + NL +
          '  if (a.x >= a.y && a.x >= a.z) {' + NL +
          '    if (d.x >= 0.0) ' + TileChoice(0) + ' else ' + TileChoice(1) + NL +
          '  } else if (a.y >= a.z) {' + NL +
          '    if (d.y >= 0.0) ' + TileChoice(2) + ' else ' + TileChoice(3) + NL +
          '  } else {' + NL +
          '    if (d.z >= 0.0) ' + TileChoice(4) + ' else ' + TileChoice(5) + NL +
          '  }' + NL +
          { Normal offset: look up the shadow map a bit away from the surface,
            by about 1.5 texels of the shadow map at this distance,
            to avoid surfaces in their own shadow (shadow acne). }
          Format('  scale *= castle_shadow_tile(%s, m * (castle_shadow_vertex_eye + vec4(normal_eye * (o * length(d)), 0.0)), r, %s, true);', [
            ShadowMapName, UniformName('texel')]) + NL;
      end;
    smkCascades:
      begin
        Declarations := Declarations +
          Format('uniform vec4 %s;', [UniformName('splits')]) + NL;
        { Choose the cascade by the distance from the camera. }
        Body :=
          '  float depth = -castle_shadow_vertex_eye.z;' + NL +
          '  mat4 m;' + NL +
          '  vec4 r;' + NL +
          '  float o;' + NL +
          Format('  if (depth < %s.x) ', [UniformName('splits')]) + TileChoice(0) + NL;
        for K := 1 to TileCount - 1 do
          Body := Body + Format('  else if (depth < %s.%s) ', [
            UniformName('splits'), VectorComponent[K]]) + TileChoice(K) + NL;
        Body := Body +
          '  else return;' + NL +
          { normal offset, like for point lights }
          Format('  scale *= castle_shadow_tile(%s, m * (castle_shadow_vertex_eye + vec4(normal_eye * o, 0.0)), r, %s, false);', [
            ShadowMapName, UniformName('texel')]) + NL;
      end;
    {$ifndef COMPILER_CASE_ANALYSIS}
    else raise EInternalError.Create('ShadowMapKind?');
    {$endif}
  end;

  { Fragment shader uses castle_shadow_vertex_eye to calculate shadow,
    when given light is applied. }
  Shader.Plug(stFragment,
    Declarations +

    // Do not redeclare shadow() and friends on OpenGLES
    {$ifndef OpenGLES}
    Shader.DeclareShadowFunctions + NL +
    {$endif}

    'void PLUG_light_scale(inout float scale, const in vec3 normal_eye, const in vec3 light_dir)' + NL +
    '{' + NL +
    Body +
    '}',
    ShadowLightShader.Code);
end;

procedure TShadowMapShader.SetUniformsOnce(const AProgram: TX3DShaderProgram);
begin
  AProgram.SetUniform(ShadowMapName, TextureUnit);
end;

procedure TShadowMapShader.SetDynamicUniforms(const AProgram: TX3DShaderProgram;
  const RenderingCamera: TRenderingCamera);

  { Matrix from the clip space of a tile's view
    to the texture coordinates (and depth in 0..1) of the tile Rect. }
  function TileMatrix(const Rect: TVector4): TMatrix4;
  var
    SX, SY: Single;
  begin
    SX := (Rect.Z - Rect.X) * 0.5;
    SY := (Rect.W - Rect.Y) * 0.5;
    Result := TMatrix4.Identity;
    Result.Data[0, 0] := SX;
    Result.Data[1, 1] := SY;
    Result.Data[2, 2] := 0.5;
    Result.Data[3, 0] := Rect.X + SX;
    Result.Data[3, 1] := Rect.Y + SY;
    Result.Data[3, 2] := 0.5;
  end;

var
  Kind: TShadowMapKind;
  TileCount, K: Integer;
begin
  if not (ShadowMap.Light is TAbstractPunctualLightNode) then
    Exit;
  Kind := ShadowMapKind(TAbstractPunctualLightNode(ShadowMap.Light), TileCount);
  RenderingCamera.InverseMatrixNeeded;

  for K := 0 to TileCount - 1 do
    if K < ShadowMap.InternalTileCount then
    begin
      AProgram.SetUniform(UniformName('matrix_' + IntToStr(K)),
        TileMatrix(ShadowMap.InternalTiles[K].Rect) *
        ShadowMap.InternalTiles[K].ViewProjection *
        RenderingCamera.InverseMatrix);
      AProgram.SetUniform(UniformName('rect_' + IntToStr(K)),
        ShadowMap.InternalTiles[K].Rect);
      if Kind <> smkSingle then
        AProgram.SetUniform(UniformName('offset_' + IntToStr(K)),
          ShadowMap.InternalTiles[K].NormalOffset);
    end else
    begin
      { not rendered yet: nothing is in the shadow }
      AProgram.SetUniform(UniformName('matrix_' + IntToStr(K)), TMatrix4.Identity);
      AProgram.SetUniform(UniformName('rect_' + IntToStr(K)), Vector4(2, 2, 2, 2));
    end;
  AProgram.SetUniform(UniformName('texel'), ShadowMap.InternalTexelSize);

  case Kind of
    smkPoint:
      AProgram.SetUniform(UniformName('to_light'),
        TranslationMatrix(-ShadowMap.InternalLightPosition) *
        RenderingCamera.InverseMatrix);
    smkCascades:
      AProgram.SetUniform(UniformName('splits'), ShadowMap.InternalCascadeSplits);
    else ;
  end;
end;

{ TShadowMapShaderList ----------------------------------------------------------- }

procedure TShadowMapShaderList.GenerateCode(const Shader: TShader);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    L[I].GenerateCode(Shader);
end;

procedure TShadowMapShaderList.SetUniformsOnce(const AProgram: TX3DShaderProgram);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    L[I].SetUniformsOnce(AProgram);
end;

procedure TShadowMapShaderList.SetDynamicUniforms(const AProgram: TX3DShaderProgram;
  const RenderingCamera: TRenderingCamera);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    L[I].SetDynamicUniforms(AProgram, RenderingCamera);
end;

{$endif read_implementation}
