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

{ Screen effects (post-processing) using shaders (TCastleScreenEffects). }
unit CastleScreenEffects;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  {$ifdef OpenGLES} CastleGLES, {$else} CastleGL, {$endif}
  CastleVectors, CastleGLShaders, CastleUIControls, X3DNodes, CastleGLImages,
  CastleRectangles, CastleScene, CastleTransform, CastleCameras, CastleGLUtils,
  CastleRenderOptions, CastleInternalRenderer;

type
  { Screen effects are shaders that post-process the rendered screen.
    The effects may be defined using @url(https://castle-engine.io/x3d_extensions_screen_effects.php
    X3D node ScreenEffect).

    This control applies screen effects (post-processing)
    on the rendering done by children and (when this class is used as an ancestor)
    it's descendants.

    It can be used to apply screen effects over any UI control,
    like @link(TCastleViewport),
    @link(TCastleButton), @link(TCastleImageControl) and so on.
    Simply place the desired control as child of this control.

    To make it easier to apply effects on @link(TCastleViewport),
    it already descends from this class. So, while you can, you don't need to wrap
    @link(TCastleViewport) instance inside another @link(TCastleScreenEffects)
    instance. You can instead directly call @link(AddScreenEffect) on your
    @link(TCastleViewport) instance.

    Note that the UI controls rendered for the screen effects
    (our children and descendants) must always initialize and fill
    colors of the entire rectangle (@link(RenderRect)) of this control.
    Otherwise, the results are undefined, as an internal texture that is used
    for screen effects is initially undefined.
    You may use e.g. @link(TCastleRectangleControl) to fill the background with a solid color
    from @link(TCastleRectangleControl.Color).
    Or use @link(TCastleViewport) with @link(TCastleViewport.Transparent) = @false (default)
    which fills background with @link(TCastleViewport.BackgroundColor).
  }
  TCastleScreenEffects = class(TCastleUserInterface)
  strict private
    type
      TScreenPoint = packed record
        Position: TVector2;
        TexCoord: TVector2;
      end;
    var
      { Scene containing screen effects }
      ScreenEffectsScene: TCastleScene;
      ScreenEffectsRoot: TX3DRootNode;
      FScreenEffectsTimeScale: Single;
      { World to pass dummy camera position to ScreenEffectsScene. }
      World: TCastleRootTransform;
      FRenderer: TRenderer;
      FPrepareParams: TPrepareParams;

      { OpenGL(ES) resources for screen effects. }
      { If a texture for screen effects is ready, then
        ScreenEffectTextureDest/Src/Depth/Target are non-zero and
        ScreenEffectRTT is non-nil.
        Also, ScreenEffectTextureWidth/Height indicate size of the texture,
        as well as ScreenEffectRTT.Width/Height. }
      ScreenEffectTextureDest, ScreenEffectTextureSrc: TGLTexture;
      ScreenEffectTextureTarget: TGLenum;
      ScreenEffectTextureDepth: TGLTexture;
      ScreenEffectRTT: TGLRenderToTexture;
      ScreenEffectTextureWidth: Cardinal;
      ScreenEffectTextureHeight: Cardinal;
      { Whether ScreenEffectTextureDest/Src have float components
        (for InternalHighDynamicRange). }
      ScreenEffectTextureHighDynamicRange: Boolean;
      { Saved ScreenEffectsCount/NeedDepth result, during rendering. }
      CurrentScreenEffectsCount: Integer;
      CurrentScreenEffectsNeedDepth: boolean;
      { Whether InternalHighDynamicRange is used in this frame.
        Valid only between Render and RenderOverChildren calls. }
      CurrentHighDynamicRange: Boolean;
      { Shader converting linear colors to the screen (InternalHighDynamicRange),
        built for HighDynamicRangeShaderToneMapping. }
      HighDynamicRangeShader: TGLSLProgram;
      HighDynamicRangeShaderToneMapping: TToneMapping;
      HighDynamicRangeShaderFailed: Boolean;
      { Shader copying the colors unchanged, the last screen effect
        when InternalHighDynamicRange is used without other screen effects. }
      CopyShader: TGLSLProgram;

      { Whether InternalTemporalAntiAliasing is used in this frame.
        Valid only between Render and RenderOverChildren calls. }
      CurrentTemporalAntiAliasing: Boolean;
      { Shader blending the world with the history (InternalTemporalAntiAliasingResolve). }
      TemporalShader: TGLSLProgram;
      TemporalShaderFailed: Boolean;
      { The last 2 results of InternalTemporalAntiAliasingResolve:
        TemporalHistory[TemporalHistoryRead] is the previous frame's,
        the other one is written in this frame. }
      TemporalHistory: array [0..1] of TGLTexture;
      TemporalHistoryRead: Integer;
      { Whether TemporalHistory[TemporalHistoryRead] holds the previous frame. }
      TemporalHistoryValid: Boolean;
      TemporalHistoryWidth, TemporalHistoryHeight: Cardinal;
      TemporalRTT: TGLRenderToTexture;

      ScreenPointVbo: TGLBuffer;
      ScreenPointVao: TVertexArrayObject;
      ScreenPoint: packed array [0..3] of TScreenPoint;

      FScreenEffectsEnable: Boolean;

    function GetScreenEffectsCount: Cardinal;
    function GetScreenEffectsNeedDepth: Boolean;
    function GetScreenEffect(const Index: Integer): TGLSLProgram;
    { InternalHighDynamicRange shader, or @nil if it cannot be used. }
    function GetHighDynamicRangeShader: TGLSLProgram;
    { Shader copying the colors unchanged. }
    function GetCopyShader: TGLSLProgram;
    { InternalTemporalAntiAliasing shader, or @nil if it cannot be used. }
    function GetTemporalShader: TGLSLProgram;
    { Create TemporalHistory and TemporalRTT for the current size. }
    procedure PrepareTemporalHistory;
    procedure FreeTemporalHistory;
    { Render a full-screen quad with the Shader,
      reading ScreenEffectTextureSrc (and ScreenEffectTextureDepth). }
    procedure RenderOneEffect(const Shader: TGLSLProgram);

    procedure GLContextCloseEvent(Sender: TObject);
  protected
    { Valid only between Render and RenderOverChildren calls.
      Tells whether we actually use screen effects, thus RenderWithoutScreenEffects
      renders to texture.
      Read-only in descendants. }
    RenderScreenEffects: Boolean;

    { Descendants with special rendering code should override this,
      and @italic(never) override @link(Render) or @link(RenderOverChildren)
      (as those two methods have special implementation in this class).

      This rendering method will be called regardless if we have
      or not some screen effects.
      When no screen effects are actually used (e.g. @link(AddScreenEffect)
      wasn't used, @code(InternalExtraScreenEffectsCount) is zero), then our @link(Render)
      trivially calls this method without doing anything else. }
    procedure RenderWithoutScreenEffects; virtual;

    { Render these additional screen effects, defined by explicit TGLSLProgram
      instead of by AddScreenEffect call.
      This is internal, only to be used by TCastleViewport.
      @exclude }
    function InternalExtraGetScreenEffects(
      const Index: Integer): TGLSLProgram; virtual;
    { @exclude }
    function InternalExtraScreenEffectsCount: Integer; virtual;
    { @exclude }
    function InternalExtraScreenEffectsNeedDepth: Boolean; virtual;

    { Render in a texture with float color components,
      and expect @link(RenderWithoutScreenEffects) to output linear colors
      (without gamma correction and tone mapping),
      calling @link(InternalHighDynamicRangeResolve) after rendering them.
      This is internal, only to be used by TCastleViewport.HighDynamicRange.
      @exclude }
    function InternalHighDynamicRange: Boolean; virtual;

    { Whether @link(InternalHighDynamicRange) is used in this frame:
      it was requested and it is supported.
      Valid only between Render and RenderOverChildren calls.
      @exclude }
    function InternalHighDynamicRangeActive: Boolean;

    { Convert the linear colors rendered so far (when @link(InternalHighDynamicRangeActive))
      to the screen: apply gamma correction and tone mapping
      (following @link(ToneMapping)) once.
      Rendering after this (e.g. children user interface) uses the usual
      screen colors.
      @exclude }
    procedure InternalHighDynamicRangeResolve;

    { Blend the world rendered in this frame with the previous frames
      (temporal anti-aliasing), calling @link(InternalTemporalAntiAliasingResolve)
      after rendering it (and after @link(InternalHighDynamicRangeResolve)).
      The rendering should be jittered by a sub-pixel offset every frame.
      This is internal, only to be used by TCastleViewport.TemporalAntiAliasing.
      @exclude }
    function InternalTemporalAntiAliasing: Boolean; virtual;

    { Whether @link(InternalTemporalAntiAliasing) is used in this frame:
      it was requested and it is supported.
      Valid only between Render and RenderOverChildren calls.
      @exclude }
    function InternalTemporalAntiAliasingActive: Boolean;

    { Blend the world rendered so far (when @link(InternalTemporalAntiAliasingActive))
      with the result of the previous frame, and remember the result for the next frame.

      Reprojection transforms a point in the normalized device coordinates
      of this frame (without the jitter: x, y from the pixel center,
      z from the depth buffer) to the clip coordinates
      of the previous frame (without the jitter),
      where the history is read: these are the motion vectors.
      Feedback is the weight of the history (0..1).

      Rendering after this (e.g. children user interface) is not blended.
      @exclude }
    procedure InternalTemporalAntiAliasingResolve(const Reprojection: TMatrix4;
      const Feedback: Single);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Add or remove a ScreenEffect node that defines new shader screen effect.
      See https://castle-engine.io/x3d_extensions_screen_effects.php .

      In the simple case, you can pass here an instance of TScreenEffectNode.
      In a general case, you can passs here any X3D node you want,
      just remember that only the TScreenEffectNode inside will be rendered.
      You can e.g. pass a TGroupNode with TScreenEffectNode and TTimeSensorNode
      as children,
      and use TTimeSensorNode to provide time to your shader uniform parameter.
      Or you can e.g. pass an X3D graph loaded from X3D file
      using @link(X3DLoad.LoadNode), this way you can define effects
      inside an external X3D file, e.g. like this:

      @longCode(#
      ScreenEffects.AddScreenEffect(
        LoadNode('castle-data:/screen_effects_scene.x3dv'));
      #)

      If you're looking for inspirations what to put in screen_effects_scene.x3dv,
      see https://github.com/castle-engine/demo-models/tree/master/screen_effects .
      See also CGE example in "examples/screen_effects_demo/" directory
      ( https://github.com/castle-engine/castle-engine/tree/master/examples/screen_effects_demo )
      that shows more screen effects code,
      and shows how to load or construct X3D node graph with ScreenEffect.

      The memory management of the node added here is automatic:
      the added screen effect becomes owned by the internal X3D Group node.
      It's reference-count is increased at AddScreenEffect, and decreased
      at RemoveScreenEffect, and it is automatically freed when reference-count
      drops to zero.

      This means that, if you create the provided Node by code,
      and don't add it anywhere else, then the node will be freed
      automatically at our destructor (if you call AddScreenEffect
      and do not call RemoveScreenEffect on it),
      or at RemoveScreenEffect call.
      If you don't want this, use @link(TX3DNode.WaitForRelease)
      to manage the node destruction yourself.

      Note that the given Node should not be used by other TCastleScene instances.
      In general, a node should not be present in more than one TCastleScene instance,
      and we already insert the node into an internal TCastleScene instance.
      Use TX3DNode.DeepCopy if necessary to duplicate node into multiple scenes.

      Note that you can enable/disable the effect using @link(TScreenEffectNode.Enabled),
      or enable/disable all using @link(ScreenEffectsEnable).
      You do not need to remove the node by @link(RemoveScreenEffect) if you only want
      to disable it temporarily.
    }
    procedure AddScreenEffect(const Node: TAbstractChildNode);
    procedure RemoveScreenEffect(const Node: TAbstractChildNode);

    procedure BeforeRender; override;
    procedure Render; override;
    procedure RenderOverChildren; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: boolean); override;
    procedure GLContextClose; override;

    { Scale time passing inside TimeSensor nodes you add as part of AddScreenEffect.
      May be 0 to stop time passing.
      This has deliberately long name, instead of simple TimeScale,
      to make it clear that it's completely independent from
      @link(TCastleAbstractRootTransform.TimeScale). }
    property ScreenEffectsTimeScale: Single
      read FScreenEffectsTimeScale write FScreenEffectsTimeScale {$ifdef FPC}default 1{$endif};

    { Enable or disable all screen effects added by AddScreenEffect.
      When this is @true, particular screen effects can still be enabled/disabled
      using @link(TScreenEffectNode.Enabled).
      When this is @false, all effects are disabled, regardless of
      @link(TScreenEffectNode.Enabled). }
    property ScreenEffectsEnable: Boolean
      read FScreenEffectsEnable write FScreenEffectsEnable default true;

    { Make the screen effects rendering resources ready (e.g. link shaders). }
    procedure PrepareResources;
  end;

implementation

uses
  {$ifdef WASI} Job.Js, {$endif}
  CastleUtils, CastleLog, CastleRenderContext, CastleInternalGLUtils,
  CastleApplicationProperties, CastleInternalScreenEffects;

procedure SwapValues(var A, B: TGLTexture);
var
  Tmp: TGLTexture;
begin
  Tmp := A;
  A := B;
  B := Tmp;
end;

{ TCastleScreenEffects ------------------------------------------------------- }

constructor TCastleScreenEffects.Create(AOwner: TComponent);
begin
  inherited;
  FScreenEffectsTimeScale := 1;
  FScreenEffectsEnable := true;

  FRenderer := TRenderer.Create(nil);

  FPrepareParams := TPrepareParams.Create;
  FPrepareParams.GlobalLights := nil;
  FPrepareParams.GlobalFog := nil;
  FPrepareParams.RendererToPrepareShapes := FRenderer;

  ApplicationProperties.OnGLContextCloseObject.Add(
    {$ifdef FPC}@{$endif} GLContextCloseEvent);
end;

destructor TCastleScreenEffects.Destroy;
begin
  ApplicationProperties.OnGLContextCloseObject.Remove(
    {$ifdef FPC}@{$endif} GLContextCloseEvent);

  FreeAndNil(FPrepareParams);
  FreeAndNil(FRenderer);
  inherited;
end;

procedure TCastleScreenEffects.GLContextCloseEvent(Sender: TObject);
begin
  if ScreenEffectsScene <> nil then
    ScreenEffectsScene.GLContextClose;
end;

procedure TCastleScreenEffects.AddScreenEffect(const Node: TAbstractChildNode);
begin
  if ScreenEffectsScene = nil then
  begin
    ScreenEffectsRoot := TX3DRootNode.Create;

    { We create TCastleScene that is used only for rendering screen effects.
      This way we can make all "support" things for screen effects work,
      e.g. textures will be initialized using CastleInternalRenderer,
      TimeSensor will work and can be fed into shader uniform etc. }
    ScreenEffectsScene := TCastleScene.Create(Self);
    ScreenEffectsScene.Name := 'ScreenEffectsScene';
    ScreenEffectsScene.Load(ScreenEffectsRoot, true);
    ScreenEffectsScene.ProcessEvents := true;

    (* We setup World with camera knowledge to make some ProximitySensors working,
       like a dummy "ProximitySensors { size 10000 10000 10000 }". *)
    World := TCastleRootTransform.Create(Self);
    World.Add(ScreenEffectsScene);
    World.MainCamera := TCastleCamera.Create(Self);
    World.Add(World.MainCamera); // necessary to be able to query camera world coords
  end;

  { Note that AddChildren by default has AllowDuplicates=true,
    and enables multiple instances of this node on a list. That's good. }
  ScreenEffectsRoot.AddChildren(Node);

  { Send InternalCameraChanged now, to activate ProximitySensors inside new nodes. }
  ScreenEffectsScene.InternalCameraChanged;
end;

procedure TCastleScreenEffects.RemoveScreenEffect(const Node: TAbstractChildNode);
begin
  if ScreenEffectsRoot <> nil then
  begin
    ScreenEffectsRoot.FdChildren.Remove(Node);
    ScreenEffectsRoot.FdChildren.Changed;
  end;
end;

function TCastleScreenEffects.InternalExtraGetScreenEffects(const Index: Integer): TGLSLProgram;
begin
  raise EInternalError.Create('Override InternalExtraGetScreenEffects if you override InternalExtraScreenEffectsCount. In TCastleScreenEffects, InternalExtraScreenEffectsCount returns zero, so InternalExtraGetScreenEffects should never be called');
  Result := nil; // silence FPC warnings about undefined result
end;

function TCastleScreenEffects.InternalExtraScreenEffectsCount: Integer;
begin
  Result := 0;
end;

function TCastleScreenEffects.InternalExtraScreenEffectsNeedDepth: Boolean;
begin
  Result := false;
end;

function TCastleScreenEffects.InternalHighDynamicRange: Boolean;
begin
  Result := false;
end;

function TCastleScreenEffects.InternalHighDynamicRangeActive: Boolean;
begin
  Result := RenderScreenEffects and CurrentHighDynamicRange;
end;

function TCastleScreenEffects.InternalTemporalAntiAliasing: Boolean;
begin
  Result := false;
end;

function TCastleScreenEffects.InternalTemporalAntiAliasingActive: Boolean;
begin
  Result := RenderScreenEffects and CurrentTemporalAntiAliasing;
end;

function TCastleScreenEffects.GetCopyShader: TGLSLProgram;
var
  Shader: TGLSLScreenEffect;
begin
  if CopyShader = nil then
  begin
    Shader := TGLSLScreenEffect.Create;
    Shader.ScreenEffectShader :=
      'ivec2 screen_position();' + NL +
      'vec4 screen_get_color(ivec2 position);' + NL +
      'void main(void)' + NL +
      '{' + NL +
      '  gl_FragColor = screen_get_color(screen_position());' + NL +
      '}' + NL;
    Shader.Link;
    CopyShader := Shader;
  end;
  Result := CopyShader;
end;

function TCastleScreenEffects.GetTemporalShader: TGLSLProgram;
var
  Shader: TGLSLScreenEffect;
begin
  if (TemporalShader = nil) and
     (not TemporalShaderFailed) and
     GLFeatures.TextureDepth then
  begin
    Shader := TGLSLScreenEffect.Create;
    try
      Shader.NeedsDepth := true;
      Shader.ScreenEffectShader := {$I temporal_anti_aliasing.fs.inc};
      Shader.Link;
      TemporalShader := Shader;
    except
      on E: EGLSLError do
      begin
        FreeAndNil(Shader);
        WritelnWarning('Error when linking the shader for temporal anti-aliasing, disabling it: ' + E.Message);
        TemporalShaderFailed := true;
      end;
    end;
  end;
  Result := TemporalShader;
end;

procedure TCastleScreenEffects.FreeTemporalHistory;
begin
  FreeTexture(TemporalHistory[0]);
  FreeTexture(TemporalHistory[1]);
  FreeAndNil(TemporalRTT);
  TemporalHistoryValid := false;
end;

procedure TCastleScreenEffects.PrepareTemporalHistory;

  function CreateHistoryTexture: TGLTexture;
  begin
    Result := glCreateTexture();
    glBindTexture(GL_TEXTURE_2D, Result);
    { linear, as the history is read between pixels (by the motion vectors) }
    SetTextureFilter(GL_TEXTURE_2D, TextureFilter(minLinear, magLinear));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GLFeatures.CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GLFeatures.CLAMP_TO_EDGE);
    { Float components when possible: with 8 bits, blending a small part
      of each frame (1 - feedback) gets stuck a few levels off. }
    if GLFeatures.ColorBufferFloat then
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F,
        ScreenEffectTextureWidth, ScreenEffectTextureHeight, 0, GL_RGBA, GL_FLOAT, nil)
    else
      glTexImage2D(GL_TEXTURE_2D, 0, {$ifdef OpenGLES} GL_RGBA {$else} GL_RGBA8 {$endif},
        ScreenEffectTextureWidth, ScreenEffectTextureHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil);
    TextureMemoryProfiler.Allocate(Result, 'temporal-anti-aliasing-history', '', 0, false,
      ScreenEffectTextureWidth, ScreenEffectTextureHeight, 1);
  end;

begin
  if (TemporalRTT <> nil) and
     (TemporalHistoryWidth = ScreenEffectTextureWidth) and
     (TemporalHistoryHeight = ScreenEffectTextureHeight) then
    Exit;

  FreeTemporalHistory;
  TemporalHistoryWidth := ScreenEffectTextureWidth;
  TemporalHistoryHeight := ScreenEffectTextureHeight;
  TemporalHistory[0] := CreateHistoryTexture;
  TemporalHistory[1] := CreateHistoryTexture;
  TemporalHistoryRead := 0;

  TemporalRTT := TGLRenderToTexture.Create(TemporalHistoryWidth, TemporalHistoryHeight);
  TemporalRTT.SetTexture(TemporalHistory[1], GL_TEXTURE_2D);
  TemporalRTT.Buffer := tbColor;
  TemporalRTT.Stencil := false;
  TemporalRTT.GLContextOpen;
end;

function TCastleScreenEffects.GetHighDynamicRangeShader: TGLSLProgram;

  function ToneMappingDefines: String;
  begin
    case ToneMapping of
      tmUncharted  : Result := '#define CASTLE_TONE_MAPPING' + NL + '#define CASTLE_TONE_MAPPING_UNCHARTED' + NL;
      tmHejlRichard: Result := '#define CASTLE_TONE_MAPPING' + NL + '#define CASTLE_TONE_MAPPING_HEJLRICHARD' + NL;
      tmACES       : Result := '#define CASTLE_TONE_MAPPING' + NL + '#define CASTLE_TONE_MAPPING_ACES' + NL;
      else           Result := '';
    end;
  end;

var
  Shader: TGLSLScreenEffect;
begin
  if (HighDynamicRangeShader <> nil) and
     (HighDynamicRangeShaderToneMapping <> ToneMapping) then
    FreeAndNil(HighDynamicRangeShader);

  if (HighDynamicRangeShader = nil) and
     (not HighDynamicRangeShaderFailed) and
     GLFeatures.ColorBufferFloat then
  begin
    Shader := TGLSLScreenEffect.Create;
    try
      { Shapes always output linear colors in this mode
        (shapes without gamma correction output the inverse of it),
        so always apply gamma correction here. }
      Shader.ScreenEffectShader :=
        '#define CASTLE_GAMMA_CORRECTION' + NL +
        ToneMappingDefines +
        {$I tone_mapping.fs.inc} + NL +
        'ivec2 screen_position();' + NL +
        'vec4 screen_get_color(ivec2 position);' + NL +
        'void main(void)' + NL +
        '{' + NL +
        '  vec4 color = screen_get_color(screen_position());' + NL +
        '  gl_FragColor = vec4(castle_linear_to_screen(max(color.rgb, vec3(0.0))), color.a);' + NL +
        '}' + NL;
      Shader.Link;
      HighDynamicRangeShader := Shader;
      HighDynamicRangeShaderToneMapping := ToneMapping;
    except
      on E: EGLSLError do
      begin
        FreeAndNil(Shader);
        WritelnWarning('Error when linking the shader for high dynamic range rendering, disabling it: ' + E.Message);
        HighDynamicRangeShaderFailed := true;
      end;
    end;
  end;

  Result := HighDynamicRangeShader;
end;

function TCastleScreenEffects.GetScreenEffectsCount: Cardinal;
begin
  Result := 0;
  if ScreenEffectsEnable then
  begin
    if ScreenEffectsScene <> nil then
      { TCastleScene already implemented logic to only count screen effects
        that are enabled, and their GLSL code linked successfully.
        Cool, we depend on it. }
      Result := Result + ScreenEffectsScene.InternalScreenEffectsCount;
    Result := Result + InternalExtraScreenEffectsCount;
  end;
end;

function TCastleScreenEffects.GetScreenEffectsNeedDepth: Boolean;
begin
  Result := ScreenEffectsEnable and (
    ((ScreenEffectsScene <> nil) and ScreenEffectsScene.InternalScreenEffectsNeedDepth) or
    InternalExtraScreenEffectsNeedDepth
  );
end;

function TCastleScreenEffects.GetScreenEffect(const Index: Integer): TGLSLProgram;
var
  SceneEffects: Integer;
begin
  { Only the high dynamic range conversion (already done by
    InternalHighDynamicRangeResolve): copy the result to the screen. }
  if (CurrentHighDynamicRange or CurrentTemporalAntiAliasing) and
     (GetScreenEffectsCount = 0) then
    Exit(GetCopyShader);

  if ScreenEffectsScene <> nil then
    SceneEffects := ScreenEffectsScene.InternalScreenEffectsCount
  else
    SceneEffects := 0;

  if Index < SceneEffects then
    Result := ScreenEffectsScene.InternalScreenEffects(Index)
  else
    Result := InternalExtraGetScreenEffects(Index - SceneEffects);
end;

procedure TCastleScreenEffects.Render;
var
  SR: TRectangle;

  { Calculate
    RenderScreenEffects (whether we actually do anything about screen effects),
    CurrentScreenEffectsCount,
    CurrentScreenEffectsNeedDepth.
  }
  procedure CheckScreenEffects;
  begin
    { Check do we have any screen effects to show.

      Save GetScreenEffectsCount (and later GetScreenEffectsNeedDepth) result,
      to not recalculate it,
      and make the rest of code stable --- this way we know
      CurrentScreenEffectsCount and later CurrentScreenEffectsNeedDepth
      values are constant, even if user modifies FScreenEffects in the middle. }
    CurrentScreenEffectsCount := GetScreenEffectsCount;
    CurrentHighDynamicRange := InternalHighDynamicRange and
      (GetHighDynamicRangeShader <> nil);
    { Temporal anti-aliasing blends the history in GL_TEXTURE_2D textures,
      it is not used with multi-sampling (that already anti-aliases). }
    CurrentTemporalAntiAliasing := InternalTemporalAntiAliasing and
      (GLFeatures.CurrentMultiSampling <= 1) and
      (GetTemporalShader <> nil);
    if not CurrentTemporalAntiAliasing then
      TemporalHistoryValid := false;
    { With high dynamic range, InternalHighDynamicRangeResolve
      does the conversion (and InternalTemporalAntiAliasingResolve the blending),
      and the last effect (maybe just a copy, see GetScreenEffect)
      renders to the screen. }
    if (CurrentHighDynamicRange or CurrentTemporalAntiAliasing) and
       (CurrentScreenEffectsCount = 0) then
      CurrentScreenEffectsCount := 1;
    RenderScreenEffects := CurrentScreenEffectsCount <> 0;
    if not RenderScreenEffects then Exit; // no need to do anything else

    { all the checks below should pass on a modern GPU }
    SR := RenderRect.Round;
    RenderScreenEffects :=
      (not GLFeatures.EnableFixedFunction) and
      GLFeatures.UseMultiTexturing and
      { check IsTextureSized, to gracefully work (without screen effects)
        on old desktop OpenGL that does not support NPOT textures. }
      IsTextureSized(SR.Width, SR.Height, tsAny);
    if not RenderScreenEffects then
    begin
      CurrentHighDynamicRange := false;
      CurrentTemporalAntiAliasing := false;
      TemporalHistoryValid := false;
      Exit; // no need to do anything else
    end;

    { check the need to render depth buffer to a texture
      (temporal anti-aliasing reprojects the depth). }
    CurrentScreenEffectsNeedDepth := GetScreenEffectsNeedDepth or
      CurrentTemporalAntiAliasing;
    if CurrentScreenEffectsNeedDepth and not GLFeatures.TextureDepth then
    begin
      { We support only screen effects that do not require depth.
        TODO: It would be cleaner to still enable screen effects not using
        depth (and only them), instead of just disabling all screen effects. }
      RenderScreenEffects := false;
      CurrentHighDynamicRange := false;
      CurrentTemporalAntiAliasing := false;
      TemporalHistoryValid := false;
      Exit;
    end;
  end;

  { Create and setup new OpenGL texture for screen effects.
    Depends on ScreenEffectTextureWidth, ScreenEffectTextureHeight being set. }
  function CreateScreenEffectTexture(const Depth: boolean): TGLTexture;

    { Create new OpenGL texture for screen effect.
      Calls glTexImage2D or glTexImage2DMultisample
      (depending on multi-sampling requirements).

      - image contents are always unallocated (pixels = nil for glTexImage2D).
        For screen effects, we never need to load initial image contents,
        and we also do not have to care about pixel packing.
      - level for mipmaps is always 0
      - border is always 0
      - image target is ScreenEffectTextureTarget
      - size is ScreenEffectTextureWidth/Height }
    procedure TexImage2D(const InternalFormat: TGLint;
      const Format, AType: TGLenum);
    begin
      {$ifndef OpenGLES}
      if (GLFeatures.CurrentMultiSampling > 1) and GLFeatures.FBOMultiSampling then
        glTexImage2DMultisample(ScreenEffectTextureTarget,
          GLFeatures.CurrentMultiSampling, InternalFormat,
          ScreenEffectTextureWidth,
          ScreenEffectTextureHeight,
          { fixedsamplelocations = TRUE are necessary in case we use
            this with cbColor mode, where FBO will also have renderbuffer
            for depth (and maybe stencil). In this case,
            https://www.opengl.org/registry/specs/ARB/texture_multisample.txt
            says that

              if the attached images are a mix of
              renderbuffers and textures, the value of
              TEXTURE_FIXED_SAMPLE_LOCATIONS must be TRUE for all attached
              textures.

            which implies that this parameter must be true.
            See https://sourceforge.net/p/castle-engine/tickets/22/ . }
          GL_TRUE) else
      {$endif}
        glTexImage2D(ScreenEffectTextureTarget, 0, InternalFormat,
          ScreenEffectTextureWidth,
          ScreenEffectTextureHeight, 0, Format, AType, nil);
    end;

  begin
    Result := glCreateTexture();
    glBindTexture(ScreenEffectTextureTarget, Result);
    {$ifndef OpenGLES}
    { for multisample texture, these cannot be configured (OpenGL makes
      "invalid enumerant" error) }
    if ScreenEffectTextureTarget <> GL_TEXTURE_2D_MULTISAMPLE then
    {$endif}
    begin
      { TODO: NEAREST or LINEAR?
        Allow to config this at each screen effect,
        and optionally create another version? }
      SetTextureFilter(ScreenEffectTextureTarget, TextureFilter(minNearest, magNearest));
      glTexParameteri(ScreenEffectTextureTarget, GL_TEXTURE_WRAP_S, GLFeatures.CLAMP_TO_EDGE);
      glTexParameteri(ScreenEffectTextureTarget, GL_TEXTURE_WRAP_T, GLFeatures.CLAMP_TO_EDGE);
    end;
    if Depth then
    begin
      if GLFeatures.ShadowVolumesPossible and GLFeatures.PackedDepthStencil then
        TexImage2D(
          {$ifdef OpenGLES} GL_DEPTH24_STENCIL8 {$else} GL_DEPTH24_STENCIL8_EXT {$endif},
          {$ifdef OpenGLES} GL_DEPTH_STENCIL {$else} GL_DEPTH_STENCIL_EXT {$endif},
          {$ifdef OpenGLES} GL_UNSIGNED_INT_24_8 {$else} GL_UNSIGNED_INT_24_8_EXT {$endif})
      else
        TexImage2D(GL_DEPTH_COMPONENT, GL_DEPTH_COMPONENT,
          { On OpenGLES, using GL_UNSIGNED_BYTE will result in FBO failing
            with INCOMPLETE_ATTACHMENT.
            http://www.khronos.org/registry/gles/extensions/OES/OES_depth_texture.txt
            allows only GL_UNSIGNED_SHORT or GL_UNSIGNED_INT for depth textures. }
          {$ifdef OpenGLES} GL_UNSIGNED_SHORT {$else} GL_UNSIGNED_BYTE {$endif});
      //glTexParameteri(ScreenEffectTextureTarget, GL_TEXTURE_COMPARE_MODE_ARB, GL_NONE);
      //glTexParameteri(ScreenEffectTextureTarget, GL_DEPTH_TEXTURE_MODE_ARB, GL_LUMINANCE);
    end else
    if CurrentHighDynamicRange then
      TexImage2D(GL_RGBA16F, GL_RGBA, GL_FLOAT)
    else
      TexImage2D({$ifdef OpenGLES} GL_RGB {$else} GL_RGB8 {$endif},
        GL_RGB, GL_UNSIGNED_BYTE);

    TextureMemoryProfiler.Allocate(Result, 'screen-contents', '', { TODO } 0, false,
      ScreenEffectTextureWidth, ScreenEffectTextureHeight, 1);
  end;

  procedure BeginRenderingToTexture;
  begin
    { We need a temporary texture, for screen effect. }
    if (ScreenEffectTextureDest = GLObjectNone) or
       (ScreenEffectTextureSrc = GLObjectNone) or
       (CurrentScreenEffectsNeedDepth <> (ScreenEffectTextureDepth <> GLObjectNone)) or
       (CurrentHighDynamicRange <> ScreenEffectTextureHighDynamicRange) or
       (ScreenEffectRTT = nil) or
       (ScreenEffectTextureWidth  <> SR.Width ) or
       (ScreenEffectTextureHeight <> SR.Height) then
    begin
      FreeTexture(ScreenEffectTextureDest);
      FreeTexture(ScreenEffectTextureSrc);
      FreeTexture(ScreenEffectTextureDepth);
      FreeAndNil(ScreenEffectRTT);

      {$ifndef OpenGLES}
      if (GLFeatures.CurrentMultiSampling > 1) and GLFeatures.FBOMultiSampling then
        ScreenEffectTextureTarget := GL_TEXTURE_2D_MULTISAMPLE else
      {$endif}
        ScreenEffectTextureTarget := GL_TEXTURE_2D;

      ScreenEffectTextureWidth  := SR.Width;
      ScreenEffectTextureHeight := SR.Height;
      ScreenEffectTextureHighDynamicRange := CurrentHighDynamicRange;
      { We use two textures: ScreenEffectTextureDest is the destination
        of framebuffer, ScreenEffectTextureSrc is the source to render.

        Although for some effects one texture (both src and dest) is enough.
        But when you have > 1 effect and one of the effects has non-local
        operations (they read color values that can be modified by operations
        of the same shader, so it's undefined (depends on how shaders are
        executed in parallel) which one is first) then the artifacts are
        visible. For example, use castle-model-viewer "Edge Detect" effect +
        any other effect. }
      ScreenEffectTextureDest := CreateScreenEffectTexture(false);
      ScreenEffectTextureSrc := CreateScreenEffectTexture(false);
      if CurrentScreenEffectsNeedDepth then
        ScreenEffectTextureDepth := CreateScreenEffectTexture(true);

      { create new TGLRenderToTexture (usually, framebuffer object) }
      ScreenEffectRTT := TGLRenderToTexture.Create(
        ScreenEffectTextureWidth, ScreenEffectTextureHeight);
      ScreenEffectRTT.SetTexture(ScreenEffectTextureDest, ScreenEffectTextureTarget);
      ScreenEffectRTT.CompleteTextureTarget := ScreenEffectTextureTarget;
      { use the same multi-sampling strategy as container }
      ScreenEffectRTT.MultiSampling := GLFeatures.CurrentMultiSampling;
      if CurrentScreenEffectsNeedDepth then
      begin
        ScreenEffectRTT.Buffer := tbColorAndDepth;
        ScreenEffectRTT.DepthTexture := ScreenEffectTextureDepth;
        ScreenEffectRTT.DepthTextureTarget := ScreenEffectTextureTarget;
      end else
        ScreenEffectRTT.Buffer := tbColor;
      ScreenEffectRTT.Stencil := GLFeatures.ShadowVolumesPossible;
      ScreenEffectRTT.GLContextOpen;

      WritelnLog('Screen effects', Format('Created texture for screen effects, with size %d x %d, with depth texture: %s, float colors: %s',
        [ ScreenEffectTextureWidth,
          ScreenEffectTextureHeight,
          BoolToStr(CurrentScreenEffectsNeedDepth, true),
          BoolToStr(CurrentHighDynamicRange, true) ]));
    end;

    RenderContext.Viewport := SR;
    { Any subquequent changes to RenderContext.Viewport should by shifted,
      such that point SR.LeftBottom is actually at (0,0). }
    RenderContext.ViewportDelta := -SR.LeftBottom;
    { Note: the effective glViewport is now Rectangle(0, 0, SR.Width, SR.Height). }

    ScreenEffectRTT.RenderBegin;
    ScreenEffectRTT.SetTexture(ScreenEffectTextureDest, ScreenEffectTextureTarget);
  end;

begin
  inherited;

  { Whether we have to render screen effects or not (regular TCastleViewport items),
    break TDrawableImage batching as we no longer draw only images. }
  TDrawableImage.BatchingFlush;

  CheckScreenEffects;
  if RenderScreenEffects then
    BeginRenderingToTexture;
  RenderWithoutScreenEffects;
end;

procedure TCastleScreenEffects.RenderWithoutScreenEffects;
begin
end;

procedure TCastleScreenEffects.RenderOneEffect(const Shader: TGLSLProgram);
var
  BoundTextureUnits: Cardinal;
  AttribVertex, AttribTexCoord: TGLSLAttribute;
begin
  if ScreenPointVbo = GLObjectNone then
  begin
    { generate and fill ScreenPointVbo. It's contents are constant. }
    ScreenPointVbo := glCreateBuffer();
    ScreenPoint[0].TexCoord := Vector2(0, 0);
    ScreenPoint[0].Position := Vector2(-1, -1);
    ScreenPoint[1].TexCoord := Vector2(1, 0);
    ScreenPoint[1].Position := Vector2( 1, -1);
    ScreenPoint[2].TexCoord := Vector2(1, 1);
    ScreenPoint[2].Position := Vector2( 1,  1);
    ScreenPoint[3].TexCoord := Vector2(0, 1);
    ScreenPoint[3].Position := Vector2(-1,  1);
    RenderContext.BindBuffer[btArray] := ScreenPointVbo;
    glBufferData(GL_ARRAY_BUFFER, SizeOf(ScreenPoint), @(ScreenPoint[0]), GL_STATIC_DRAW);
  end;

  if ScreenPointVao = nil then
    ScreenPointVao := TVertexArrayObject.Create(nil);

  RenderContext.CurrentProgram := Shader;
  RenderContext.CurrentVao := ScreenPointVao;

  RenderContext.BindBuffer[btArray] := ScreenPointVbo;

  glActiveTexture(GL_TEXTURE0); // GLFeatures.UseMultiTexturing is already checked
  glBindTexture(ScreenEffectTextureTarget, ScreenEffectTextureSrc);
  BoundTextureUnits := 1;

  if CurrentScreenEffectsNeedDepth then
  begin
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(ScreenEffectTextureTarget, ScreenEffectTextureDepth);
    Inc(BoundTextureUnits);
  end;

  Shader.Uniform('screen').SetValue(0);
  if CurrentScreenEffectsNeedDepth then
    Shader.Uniform('screen_depth').SetValue(1);
  Shader.Uniform('screen_width').SetValue(TGLint(ScreenEffectTextureWidth));
  Shader.Uniform('screen_height').SetValue(TGLint(ScreenEffectTextureHeight));

  { Note that we ignore SetupUniforms result --- if some texture
    could not be bound, it will be undefined for shader.
    I don't see anything much better to do now. }
  Shader.SetupUniforms(BoundTextureUnits);

  { Note that there's no need to worry about Rect.Left or Rect.Bottom,
    here or inside RenderWithScreenEffectsCore, because we're already within
    RenderContext.Viewport that takes care of this. }

  AttribVertex := Shader.Attribute('vertex');
  AttribVertex.EnableArrayVector2(ScreenPointVao, SizeOf(TScreenPoint),
    OffsetUInt(ScreenPoint[0].Position, ScreenPoint[0]));
  AttribTexCoord := Shader.Attribute('tex_coord');
  AttribTexCoord.EnableArrayVector2(ScreenPointVao, SizeOf(TScreenPoint),
    OffsetUInt(ScreenPoint[0].TexCoord, ScreenPoint[0]));

  glDrawArrays(GL_TRIANGLE_FAN, 0, 4);

  AttribVertex.DisableArray;
  AttribTexCoord.DisableArray;
  RenderContext.BindBuffer[btArray] := GLObjectNone;
end;

procedure TCastleScreenEffects.InternalHighDynamicRangeResolve;
var
  SavedDepthTest, SavedDepthBufferUpdate: Boolean;
begin
  if not InternalHighDynamicRangeActive then
    Exit;

  { Render the linear colors (now in ScreenEffectTextureSrc) converted
    to the screen into ScreenEffectTextureDest, keeping the depth and stencil
    attachments, so rendering can continue on top of it. }
  ScreenEffectRTT.RenderEnd;
  SwapValues(ScreenEffectTextureDest, ScreenEffectTextureSrc);
  ScreenEffectRTT.RenderBegin;
  ScreenEffectRTT.SetTexture(ScreenEffectTextureDest, ScreenEffectTextureTarget);

  SavedDepthTest := RenderContext.DepthTest;
  SavedDepthBufferUpdate := RenderContext.DepthBufferUpdate;
  RenderContext.DepthTest := false;
  RenderContext.DepthBufferUpdate := false;
  RenderContext.BlendingDisable;

  RenderOneEffect(HighDynamicRangeShader);

  RenderContext.DepthTest := SavedDepthTest;
  RenderContext.DepthBufferUpdate := SavedDepthBufferUpdate;
end;

procedure TCastleScreenEffects.InternalTemporalAntiAliasingResolve(
  const Reprojection: TMatrix4; const Feedback: Single);
var
  SavedDepthTest, SavedDepthBufferUpdate: Boolean;
  HistoryWrite: Integer;
  SavedSrc: TGLTexture;
begin
  if not InternalTemporalAntiAliasingActive then
    Exit;

  PrepareTemporalHistory;
  HistoryWrite := 1 - TemporalHistoryRead;

  { The world (now in ScreenEffectTextureSrc) and its depth are blended
    with the history into TemporalHistory[HistoryWrite].
    The depth texture is not attached to TemporalRTT, so it can be read. }
  ScreenEffectRTT.RenderEnd;
  SwapValues(ScreenEffectTextureDest, ScreenEffectTextureSrc);

  SavedDepthTest := RenderContext.DepthTest;
  SavedDepthBufferUpdate := RenderContext.DepthBufferUpdate;
  RenderContext.DepthTest := false;
  RenderContext.DepthBufferUpdate := false;
  RenderContext.BlendingDisable;

  TemporalRTT.RenderBegin;
  TemporalRTT.SetTexture(TemporalHistory[HistoryWrite], GL_TEXTURE_2D);
  { texture units 0 and 1 are the screen and its depth, see RenderOneEffect }
  glActiveTexture(GL_TEXTURE2);
  glBindTexture(GL_TEXTURE_2D, TemporalHistory[TemporalHistoryRead]);
  RenderContext.CurrentProgram := TemporalShader;
  TemporalShader.Uniform('temporal_history').SetValue(2);
  TemporalShader.Uniform('temporal_reprojection').SetValue(Reprojection);
  TemporalShader.Uniform('temporal_feedback').SetValue(Feedback);
  TemporalShader.Uniform('temporal_history_valid').SetValue(TGLint(Ord(TemporalHistoryValid)));
  RenderOneEffect(TemporalShader);
  TemporalRTT.RenderEnd;

  { Copy the result to ScreenEffectTextureDest, keeping the depth and stencil
    attachments, so rendering can continue on top of it. }
  ScreenEffectRTT.RenderBegin;
  ScreenEffectRTT.SetTexture(ScreenEffectTextureDest, ScreenEffectTextureTarget);
  SavedSrc := ScreenEffectTextureSrc;
  ScreenEffectTextureSrc := TemporalHistory[HistoryWrite];
  RenderOneEffect(GetCopyShader);
  ScreenEffectTextureSrc := SavedSrc;

  RenderContext.DepthTest := SavedDepthTest;
  RenderContext.DepthBufferUpdate := SavedDepthBufferUpdate;

  TemporalHistoryRead := HistoryWrite;
  TemporalHistoryValid := true;
end;

procedure TCastleScreenEffects.RenderOverChildren;
var
  SR: TRectangle;

  procedure RenderWithScreenEffectsCore;
  var
    I: Integer;
  begin
    { Render all except the last screen effects: from texture
      (ScreenEffectTextureDest/Src) and to texture (using ScreenEffectRTT) }

    { The effective glViewport should be now Rectangle(0, 0, SR.Width, SR.Height).
      Although our "Render" implementation already set it
      (somewhat indirectly, using ViewportDelta),
      but something since then could have changed the Viewport
      (e.g. ControlRenderBegin done right before C.RenderOverChildren in CastleGLContainer).
      So set it as we need, again.
      And this time we don't need to deal with ViewportDelta, just zero it. }
    RenderContext.ViewportDelta := TVector2Integer.Zero;
    RenderContext.Viewport := Rectangle(0, 0, SR.Width, SR.Height);

    for I := 0 to CurrentScreenEffectsCount - 2 do
    begin
      ScreenEffectRTT.RenderBegin;
      ScreenEffectRTT.SetTexture(ScreenEffectTextureDest, ScreenEffectTextureTarget);
      RenderOneEffect(GetScreenEffect(I));
      ScreenEffectRTT.RenderEnd;

      SwapValues(ScreenEffectTextureDest, ScreenEffectTextureSrc);
    end;

    { the last effect gets a texture, and renders straight into screen }
    RenderContext.ViewportDelta := TVector2Integer.Zero;
    RenderContext.Viewport := RenderRect.Round;
    RenderOneEffect(GetScreenEffect(CurrentScreenEffectsCount - 1));
  end;

  procedure EndRenderingToTexture;
  begin
    SR := RenderRect.Round;

    ScreenEffectRTT.RenderEnd;

    SwapValues(ScreenEffectTextureDest, ScreenEffectTextureSrc);

    OrthoProjection(FloatRectangle(0, 0, SR.Width, SR.Height));
    RenderWithScreenEffectsCore;
  end;

begin
  inherited;
  if RenderScreenEffects then
    EndRenderingToTexture;
end;

procedure TCastleScreenEffects.Update(const SecondsPassed: Single; var HandleInput: boolean);
var
  RemoveItem: TRemoveType;
begin
  inherited;
  if (ScreenEffectsScene <> nil) and ScreenEffectsEnable then
  begin
    RemoveItem := rtNone;
    ScreenEffectsScene.Update(SecondsPassed * ScreenEffectsTimeScale, RemoveItem);
    { We ignore RemoveItem --- ScreenEffectsScene cannot be removed.
      Also, this is always TCastleScene that should not change RemoveItem ever. }
  end;
end;

procedure TCastleScreenEffects.PrepareResources;
begin
  if ScreenEffectsScene <> nil then
  begin
    {$warnings off} // using deprecated, this should be internal
    ScreenEffectsScene.PrepareResources([prScreenEffects], FPrepareParams);
    {$warnings on}
  end;
end;

procedure TCastleScreenEffects.BeforeRender;
begin
  inherited;
  PrepareResources;
end;

procedure TCastleScreenEffects.GLContextClose;
begin
  FreeTexture(ScreenEffectTextureDest);
  FreeTexture(ScreenEffectTextureSrc);
  FreeTexture(ScreenEffectTextureDepth);
  ScreenEffectTextureTarget := 0; //< clear, for safety
  FreeAndNil(ScreenEffectRTT);
  FreeBuffer(ScreenPointVbo);
  FreeAndNil(ScreenPointVao);
  FreeAndNil(HighDynamicRangeShader);
  FreeAndNil(CopyShader);
  FreeAndNil(TemporalShader);
  TemporalShaderFailed := false;
  FreeTemporalHistory;
  inherited;
end;

end.
