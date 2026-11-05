{
  Copyright 2010-2023 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Internal screen effects stuff. }
unit CastleInternalScreenEffects;

interface

uses CastleGLShaders, CastleRenderOptions, CastleInternalRHI;

type
  { GLSL shader program specialized for rendering screen effects.
    See https://castle-engine.io/x3d_extensions_screen_effects.php
    about screen effects.

    Do not use the ancestor AttachVertexShader and AttachFragmentShader
    methods, instead set the @link(ScreenEffectShader).
    This way, the standard GLSL functionality of screen effects
    will be attached to the vertex and fragment shader code automatically.
    At link time, this looks at current OpenGL context multi-sampling capabilities,
    and the @link(NeedsDepth) value, to link the correct shader code. }
  TGLSLScreenEffect = class(TGLSLProgram)
  private
    FScreenEffectShader: string;
    FNeedsDepth: boolean;
    FRHIOwnerDevice: TRHIDevice;
    FRHIVertexGLSL: String;
    FRHIFragmentGLSL: String;
    FRHIVertexShader: TRHIShaderModule;
    FRHIFragmentShader: TRHIShaderModule;
    FRHIDescriptorLayout: TRHIDescriptorSetLayout;
    FRHIPipeline: TRHIPipeline;
    procedure FreeRHIResources;
  public
    constructor Create;
    destructor Destroy; override;

    property NeedsDepth: boolean read FNeedsDepth write FNeedsDepth default false;

    { In this class, UniformMissing is by default umIgnore, since it's
      normal that screen effect doesn't use some of it's uniform variables. }
    property UniformMissing default umIgnore;

    { Attach GLSL code for the screen effect (executed as part of fragment shader).
      See https://castle-engine.io/x3d_extensions_screen_effects.php . }
    property ScreenEffectShader: string read FScreenEffectShader write FScreenEffectShader;

    procedure Link; override;

    { Lazily compiles or retrieves the RHI post-processing graphics pipeline for
      this screen effect on @code(ADevice), generating Vulkan GLSL 450 vertex and
      fragment shader sources with @code(screen_effect_library) helpers.
      @exclude }
    function GetOrCreateRHIPipeline(const ADevice: TRHIDevice): TRHIPipeline;
    property RHIVertexGLSL: String read FRHIVertexGLSL;
    property RHIFragmentGLSL: String read FRHIFragmentGLSL;
    property RHIVertexShader: TRHIShaderModule read FRHIVertexShader;
    property RHIFragmentShader: TRHIShaderModule read FRHIFragmentShader;
    property RHIDescriptorLayout: TRHIDescriptorSetLayout read FRHIDescriptorLayout;
    property RHIPipeline: TRHIPipeline read FRHIPipeline;
  end;

{ Standard GLSL vertex shader for screen effect. }
function ScreenEffectVertex: string;

(*Library of GLSL fragment shader functions useful for screen effects.
  This looks at current OpenGL context multi-sampling capabilities
  to return the correct shader code.

  Note that to work with OpenGLES, we have to glue all fragment shaders,
  and ScreenEffectFragment must be before the actual shader code.
  The string returned by this function is guaranteed to end with a newline,
  to make it easy.

  So you usually want to create screen effect shaders like this:

  @longCode(#
    Shader := TGLSLProgram.Create;
    Shader.AttachVertexShader(ScreenEffectVertex);
    Shader.AttachFragmentShader(
      ScreenEffectFragment(false { or true if you use depth }) +
      '... my custom screen effect GLSL code ...');
    Shader.Link;
    { umIgnore is a good idea here, in case some uniform variable
      from ScreenEffectFragment code may be left unused. }
    Shader.UniformMissing := umIgnore;
  #)
*)
function ScreenEffectFragment(const Depth: boolean): string;

implementation

uses SysUtils,
  CastleGLUtils, CastleUtils, CastleLog, CastleVectors, CastleInternalShaderRHI;

{ routines ------------------------------------------------------------------- }

function ScreenEffectVertex: string;
begin
  Result := {$I screen_effect.vs.inc};
end;

function ScreenEffectFragment(const Depth: boolean): string;
begin
  Result := '';
  if Depth then
    Result := Result + ('#define DEPTH' +NL);
  if (GLFeatures <> nil) and GLFeatures.FBOMultiSampling then
  begin
    if GLFeatures.CurrentMultiSampling > 1 then
      Result := Result +
        '#define MULTI_SAMPLING' +NL +
        '#define MULTI_SAMPLING_' + IntToStr(GLFeatures.CurrentMultiSampling) +NL;
    if not (GLFeatures.CurrentMultiSampling in [1, 2, 4, 8, 16]) then
      WritelnWarning('Screen Effects', Format('Our GLSL library for screen effects is not prepared for your number of samples (anti-aliasing): %d. ' + 'This may indicate that your GPU is very new or very weird. Please submit this as a bug (see https://castle-engine.io/forum.php for links to forum, bug tracker and more), citing this message. For now, screen effects will not work.',
        [GLFeatures.CurrentMultiSampling]));
  end;
  Result := Result + ({$I screen_effect_library.glsl.inc} + NL);
end;

{ TGLSLScreenEffect ---------------------------------------------------------- }

constructor TGLSLScreenEffect.Create;
begin
  inherited;
  UniformMissing := umIgnore;
  Name := 'TGLSLScreenEffect';
end;

destructor TGLSLScreenEffect.Destroy;
begin
  FreeRHIResources;
  inherited;
end;

procedure TGLSLScreenEffect.FreeRHIResources;
begin
  FreeAndNil(FRHIDescriptorLayout);
  FreeAndNil(FRHIFragmentShader);
  FreeAndNil(FRHIVertexShader);
  FRHIPipeline := nil; // Owned by RHIDevice pipeline cache
  FRHIOwnerDevice := nil;
  FRHIVertexGLSL := '';
  FRHIFragmentGLSL := '';
end;

procedure TGLSLScreenEffect.Link;
var
  VS, FS: String;
begin
  if FScreenEffectShader = '' then
    raise EGLSLError.Create('TGLSLScreenEffect shader not assigned by AttachScreenEffectShader method');
  FreeRHIResources;
  VS := ScreenEffectVertex;
  FS := ScreenEffectFragment(NeedsDepth) + FScreenEffectShader;
  AttachVertexShader(VS);
  AttachFragmentShader(FS);
  inherited;
  if RHIDevice <> nil then
    GetOrCreateRHIPipeline(RHIDevice);
end;

function TGLSLScreenEffect.GetOrCreateRHIPipeline(const ADevice: TRHIDevice): TRHIPipeline;
var
  ShaderGen: TCastleShaderGeneratorRHI;
  DefaultMainVS, ScreenLibFrag: String;
  Bindings: array of TRHIDescriptorBindingDesc;
  PipeDesc: TRHIGraphicsPipelineDesc;
  DebugPrefix: String;
begin
  if (ADevice = nil) or (Trim(FScreenEffectShader) = '') then
    Exit(nil);
  if (FRHIPipeline <> nil) and (FRHIOwnerDevice = ADevice) then
    Exit(FRHIPipeline);

  FreeRHIResources;
  FRHIOwnerDevice := ADevice;

  if Name <> '' then
    DebugPrefix := Name
  else
    DebugPrefix := 'TGLSLScreenEffect';

  ShaderGen := TCastleShaderGeneratorRHI.Create(ADevice.Capabilities.Backend);
  try
    DefaultMainVS :=
      'void main(void)' + LineEnding +
      '{' + LineEnding +
      '  v_tex_coord = tex_coord;' + LineEnding +
      '  gl_Position = vec4(vertex, 0.0, 1.0);' + LineEnding +
      '}' + LineEnding;

    FRHIVertexGLSL :=
      ShaderGen.GenerateScreenEffectPreamble(ssVertex, NeedsDepth) + LineEnding +
      DefaultMainVS;

    ScreenLibFrag :=
      'ivec2 screen_position() { return ivec2(tex_coord * castle_Screen.screen_size); }' + LineEnding +
      'int screen_x() { return int(tex_coord.x * castle_Screen.screen_size.x); }' + LineEnding +
      'int screen_y() { return int(tex_coord.y * castle_Screen.screen_size.y); }' + LineEnding +
      'vec2 screenf_position() { return tex_coord * castle_Screen.screen_size; }' + LineEnding +
      'float screenf_x() { return tex_coord.x * castle_Screen.screen_size.x; }' + LineEnding +
      'float screenf_y() { return tex_coord.y * castle_Screen.screen_size.y; }' + LineEnding +
      'vec4 screenf_get_color(vec2 position) { return texture(screen, position / castle_Screen.screen_size); }' + LineEnding +
      'vec4 screenf_get_original_color() { return texture(screen, screenf_01_position); }' + LineEnding +
      'vec4 screenf_01_get_color(vec2 position) { return texture(screen, position); }' + LineEnding +
      'vec4 screen_get_color(ivec2 position) { return screenf_get_color(vec2(position) + vec2(0.5)); }' + LineEnding;
    if NeedsDepth then
      ScreenLibFrag := ScreenLibFrag +
        'float screenf_01_get_depth(vec2 position) { return texture(screen_depth, position).r; }' + LineEnding +
        'float screenf_get_depth(vec2 position) { return screenf_01_get_depth(position / castle_Screen.screen_size); }' + LineEnding +
        'float screenf_get_original_depth() { return screenf_01_get_depth(screenf_01_position); }' + LineEnding +
        'float screen_get_depth(ivec2 position) { return screenf_get_depth(vec2(position) + vec2(0.5)); }' + LineEnding +
        'float screenf_get_depth_fast(vec2 position) { return screenf_get_depth(position); }' + LineEnding +
        'float screen_get_depth_fast(ivec2 position) { return screen_get_depth(position); }' + LineEnding;

    FRHIFragmentGLSL :=
      ShaderGen.GenerateScreenEffectPreamble(ssFragment, NeedsDepth) + LineEnding +
      ScreenLibFrag + LineEnding +
      ShaderGen.UpgradeUserEffectUniforms(FScreenEffectShader);
  finally
    FreeAndNil(ShaderGen);
  end;

  FRHIVertexShader := ADevice.CreateShaderModuleFromGLSL(
    ssVertex, FRHIVertexGLSL, DebugPrefix + '.VS');
  FRHIFragmentShader := ADevice.CreateShaderModuleFromGLSL(
    ssFragment, FRHIFragmentGLSL, DebugPrefix + '.FS');

  if NeedsDepth then
    SetLength(Bindings, 2)
  else
    SetLength(Bindings, 1);
  FillChar(Bindings[0], Length(Bindings) * SizeOf(TRHIDescriptorBindingDesc), 0);
  Bindings[0].Binding := 0;
  Bindings[0].DescriptorType := dtCombinedImageSampler;
  Bindings[0].Count := 1;
  Bindings[0].StageFlags := [ssFragment];
  if NeedsDepth then
  begin
    Bindings[1].Binding := 1;
    Bindings[1].DescriptorType := dtCombinedImageSampler;
    Bindings[1].Count := 1;
    Bindings[1].StageFlags := [ssFragment];
  end;
  FRHIDescriptorLayout := ADevice.CreateDescriptorSetLayout(Bindings);

  FillChar(PipeDesc, SizeOf(PipeDesc), 0);
  PipeDesc.VertexShader := FRHIVertexShader;
  PipeDesc.FragmentShader := FRHIFragmentShader;
  PipeDesc.Topology := ptTriangleList;
  PipeDesc.Rasterizer := TRHIRasterizerStateDesc.DefaultCullBack;
  PipeDesc.Rasterizer.CullMode := cmNone;
  PipeDesc.DepthStencil := TRHIDepthStencilStateDesc.DefaultDisabled;
  PipeDesc.BlendState := TRHIBlendStateDesc.DefaultOpaque;
  SetLength(PipeDesc.VertexInput.Bindings, 1);
  PipeDesc.VertexInput.Bindings[0].Binding := 0;
  PipeDesc.VertexInput.Bindings[0].Stride := SizeOf(TVector2) * 2;
  PipeDesc.VertexInput.Bindings[0].PerInstance := False;
  SetLength(PipeDesc.VertexInput.Attributes, 2);
  PipeDesc.VertexInput.Attributes[0].Location := 0;
  PipeDesc.VertexInput.Attributes[0].Binding := 0;
  PipeDesc.VertexInput.Attributes[0].Format := vafVector2;
  PipeDesc.VertexInput.Attributes[0].Offset := 0;
  PipeDesc.VertexInput.Attributes[1].Location := 1;
  PipeDesc.VertexInput.Attributes[1].Binding := 0;
  PipeDesc.VertexInput.Attributes[1].Format := vafVector2;
  PipeDesc.VertexInput.Attributes[1].Offset := SizeOf(TVector2);
  SetLength(PipeDesc.ColorAttachmentFormats, 1);
  PipeDesc.ColorAttachmentFormats[0] := pfRGBA8_UNorm;
  PipeDesc.SampleCount := 1;
  SetLength(PipeDesc.DescriptorSetLayouts, 1);
  PipeDesc.DescriptorSetLayouts[0] := FRHIDescriptorLayout;
  PipeDesc.PushConstantSize := SizeOf(TCastleScreenPushConstants);
  PipeDesc.PushConstantStages := [ssVertex, ssFragment];
  PipeDesc.DebugName := DebugPrefix + '.PSO';
  FRHIPipeline := ADevice.GetOrCreatePipeline(PipeDesc);
  Result := FRHIPipeline;
end;

end.
