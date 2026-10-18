{
  Copyright 2024-2024 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Test for CastleRendererInternalShader unit. }
unit TestCastleRendererInternalShader;

interface

uses
  Classes, SysUtils,
  CastleTester, CastleWindow, CastleViewport, CastleColors, X3DNodes;

type
  TTestCastleRendererInternalShader = class(TCastleTestCase)
  strict private
    { Open the window, with a viewport that looks from the top
      at 2 floor patches (to be added by the caller) around
      (-PatchX, 0, 0) and (PatchX, 0, 0). }
    function OpenWindowWithViewport(const Window: TCastleWindow): TCastleViewport;
    { Rendered color at the middle of floor patch at (X, 0, 0). }
    function RenderedPatchColor(const Window: TCastleWindow;
      const Viewport: TCastleViewport; const X: Single): TCastleColor;
    { Effect on a light source, multiplying the light by LightFactor
      (passed as a uniform, so the GLSL code is the same for all LightFactor
      values). Optionally uses a function from the EyeWorldSpace shader library. }
    function CreateLightFactorEffect(const LightFactor: Single;
      const UseShaderLibrary: Boolean): TEffectNode;
    { Effect on a light source, multiplying the light by the light's own
      custom field test_light_factor (a per-light uniform),
      so it can be shared by many lights. }
    function CreateSharedLightFactorEffect: TEffectNode;
    { Point light above (X, 0, 0) with the custom field test_light_factor. }
    function CreateFactorLight(const X, LightFactor: Single;
      const Color: TCastleColorRGB; const Effect: TEffectNode): TPointLightNode;
    { Floor patch shape at (X, 0, 0). }
    function CreatePatchShape(const X: Single): TTransformNode;
  published
    procedure TestFindPlugName;
    { Shapes lit by different lights, whose Effect nodes have the same code
      but different uniform values, must not share a shader program. }
    procedure TestLightEffectsNotShared;
    { TCastleAbstractLight.SetEffects, with effects using a shader library. }
    procedure TestLightComponentEffects;
    { Shapes for which the same light (with Effect) has a different
      light number must not share a shader program. }
    procedure TestLightEffectsDifferentLightNumber;
    { Lights sharing one Effect node, each with its own value
      of a custom field (a per-light uniform). }
    procedure TestLightEffectsPerLightUniforms;
    { One shape lit by 2 lights sharing an Effect node:
      the <Light> placeholder makes each light read its own uniform. }
    procedure TestLightEffectsPerLightUniformsSameShape;
  end;

implementation

uses CastleUtils, CastleRendererInternalShader,
  CastleVectors, CastleImages, CastleScene,
  CastleRenderOptions, CastleTransform, X3DFields;

const
  { Floor patches are at (-PatchX, 0, 0) and (PatchX, 0, 0). }
  PatchX = 3;
  PatchSize: TVector3 = (X: 4; Y: 0.2; Z: 4);

function TTestCastleRendererInternalShader.OpenWindowWithViewport(
  const Window: TCastleWindow): TCastleViewport;
begin
  Window.Width := 400;
  Window.Height := 400;
  Window.Open;

  Result := TCastleViewport.Create(Window);
  Result.FullSize := true;
  Result.BackgroundColor := Black;
  Result.Camera.SetView(
    Vector3(0, 12, 0),
    Vector3(0, -1, 0),
    Vector3(0, 0, -1));
  Window.Controls.InsertFront(Result);
end;

function TTestCastleRendererInternalShader.RenderedPatchColor(
  const Window: TCastleWindow; const Viewport: TCastleViewport;
  const X: Single): TCastleColor;
var
  Image: TCastleImage;
  P: TVector2;
begin
  Image := Window.SaveScreen;
  try
    P := Viewport.PositionFromWorld(Vector3(X, 0, 0));
    Result := Image.Colors[Round(P.X), Round(P.Y), 0];
  finally FreeAndNil(Image) end;
end;

function TTestCastleRendererInternalShader.CreateLightFactorEffect(
  const LightFactor: Single; const UseShaderLibrary: Boolean): TEffectNode;
const
  EffectCode =
    'uniform float test_light_factor;' + LineEnding +
    'void PLUG_light_scale(inout float scale, const in vec3 normal_eye, const in vec3 light_dir)' + LineEnding +
    '{' + LineEnding +
    '  scale *= test_light_factor;' + LineEnding +
    '}';
  { Note: direction_eye_to_world_space relies on EyeWorldSpace shader library. }
  EffectCodeWithLibrary =
    'uniform float test_light_factor;' + LineEnding +
    'vec3 direction_eye_to_world_space(vec3 direction_eye);' + LineEnding +
    'void PLUG_light_scale(inout float scale, const in vec3 normal_eye, const in vec3 light_dir)' + LineEnding +
    '{' + LineEnding +
    '  scale *= test_light_factor * length(direction_eye_to_world_space(light_dir));' + LineEnding +
    '}';
var
  Part: TEffectPartNode;
begin
  Result := TEffectNode.Create;
  Result.Language := slGLSL;
  Result.AddCustomField(TSFFloat.Create(Result, true, 'test_light_factor', LightFactor));
  Part := TEffectPartNode.Create;
  Part.ShaderType := stFragment;
  if UseShaderLibrary then
  begin
    Result.SetShaderLibraries(['castle-shader:/EyeWorldSpace.glsl']);
    Part.Contents := EffectCodeWithLibrary;
  end else
    Part.Contents := EffectCode;
  Result.SetParts([Part]);
end;

function TTestCastleRendererInternalShader.CreateSharedLightFactorEffect: TEffectNode;
const
  EffectCode =
    'uniform float test_light_factor<Light>;' + LineEnding +
    'void PLUG_light_scale(inout float scale, const in vec3 normal_eye, const in vec3 light_dir)' + LineEnding +
    '{' + LineEnding +
    '  scale *= test_light_factor<Light>;' + LineEnding +
    '}';
var
  Part: TEffectPartNode;
begin
  Result := TEffectNode.Create;
  Result.Language := slGLSL;
  Part := TEffectPartNode.Create;
  Part.ShaderType := stFragment;
  Part.Contents := EffectCode;
  Result.SetParts([Part]);
end;

function TTestCastleRendererInternalShader.CreateFactorLight(const X, LightFactor: Single;
  const Color: TCastleColorRGB; const Effect: TEffectNode): TPointLightNode;
begin
  Result := TPointLightNode.Create;
  Result.Global := false;
  Result.Location := Vector3(X, 3, 0);
  Result.Attenuation := Vector3(1, 0, 0);
  Result.Color := Color;
  Result.AddCustomField(TSFFloat.Create(Result, true, 'test_light_factor', LightFactor));
  Result.SetEffects([Effect]);
end;

function TTestCastleRendererInternalShader.CreatePatchShape(const X: Single): TTransformNode;
var
  Shape: TShapeNode;
  Appearance: TAppearanceNode;
  Material: TMaterialNode;
  Box: TBoxNode;
begin
  Material := TMaterialNode.Create;
  Material.DiffuseColor := WhiteRGB;
  Appearance := TAppearanceNode.Create;
  Appearance.Material := Material;
  Box := TBoxNode.CreateWithShape(Shape);
  Box.Size := PatchSize;
  Shape.Appearance := Appearance;
  Result := TTransformNode.Create;
  Result.Translation := Vector3(X, -0.1, 0);
  Result.AddChildren(Shape);
end;

procedure TTestCastleRendererInternalShader.TestFindPlugName;
var
  PlugName, DeclaredParameters: String;
begin
  PlugName := FindPlugName(NL +
    'void PLUG_main_texture_apply ( inout vec4 fcol, const in vec3 unused )' + NL +
    '{' + NL +
    '}', DeclaredParameters);
  AssertEquals('main_texture_apply', PlugName);
  AssertEquals('( inout vec4 fcol, const in vec3 unused )', DeclaredParameters);

  PlugName := FindPlugName(NL +
    'void PLUG_main_texture_apply( inout vec4 fcol, const in vec3 unused )' + NL +
    '{' + NL +
    '}', DeclaredParameters);
  AssertEquals('main_texture_apply', PlugName);
  AssertEquals('( inout vec4 fcol, const in vec3 unused )', DeclaredParameters);

  // Make sure PLUG_xxx not followed by ( is not recognized
  PlugName := FindPlugName(NL +
    '/* void PLUG_main_texture_apply bla blah */', DeclaredParameters);
  AssertEquals('', PlugName);
end;

procedure TTestCastleRendererInternalShader.TestLightEffectsNotShared;
var
  Window: TCastleWindow;

  { A scene with a floor patch at (X, 0, 0) lit by its own point light
    (not global: it lights only this scene), whose Effect multiplies
    the light by LightFactor. }
  function CreateLitPatch(const X, LightFactor: Single): TCastleScene;
  var
    Root: TX3DRootNode;
    Shape: TShapeNode;
    Appearance: TAppearanceNode;
    Material: TMaterialNode;
    Box: TBoxNode;
    Transform: TTransformNode;
    Light: TPointLightNode;
  begin
    Root := TX3DRootNode.Create;

    Material := TMaterialNode.Create;
    Material.DiffuseColor := WhiteRGB;
    Appearance := TAppearanceNode.Create;
    Appearance.Material := Material;
    Box := TBoxNode.CreateWithShape(Shape);
    Box.Size := PatchSize;
    Shape.Appearance := Appearance;
    Transform := TTransformNode.Create;
    Transform.Translation := Vector3(X, -0.1, 0);
    Transform.AddChildren(Shape);
    Root.AddChildren(Transform);

    Light := TPointLightNode.Create;
    Light.Global := false;
    Light.Location := Vector3(X, 3, 0);
    Light.Attenuation := Vector3(1, 0, 0);
    Light.SetEffects([CreateLightFactorEffect(LightFactor, false)]);
    Root.AddChildren(Light);

    Result := TCastleScene.Create(Window);
    Result.Load(Root, true);
    Result.RenderOptions.PhongShading := true;
  end;

var
  Viewport: TCastleViewport;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Viewport := OpenWindowWithViewport(Window);

    { Same shape, same material, same light type: before including light
      effects in the shader code hash, both patches shared one shader program,
      with the uniform value of the first one rendered. }
    Viewport.Items.Add(CreateLitPatch(-PatchX, 0));
    Viewport.Items.Add(CreateLitPatch(PatchX, 1));

    AssertTrue(RenderedPatchColor(Window, Viewport, -PatchX).X < 0.05);
    AssertTrue(RenderedPatchColor(Window, Viewport, PatchX).X > 0.3);

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestCastleRendererInternalShader.TestLightComponentEffects;
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;

  { A floor patch at (X, 0, 0) lit by a TCastlePointLight above it
    (its radius doesn't reach the other patch),
    whose effect multiplies the light by LightFactor. }
  procedure AddLitPatch(const X, LightFactor: Single);
  var
    Box: TCastleBox;
    Light: TCastlePointLight;
  begin
    Box := TCastleBox.Create(Window);
    Box.Size := PatchSize;
    Box.Translation := Vector3(X, -0.1, 0);
    Viewport.Items.Add(Box);

    Light := TCastlePointLight.Create(Window);
    Light.Translation := Vector3(X, 1, 0);
    Light.Attenuation := Vector3(1, 0, 0);
    Light.Radius := 3.5;
    Light.SetEffects([CreateLightFactorEffect(LightFactor, true)]);
    Viewport.Items.Add(Light);
  end;

begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Viewport := OpenWindowWithViewport(Window);

    AddLitPatch(-PatchX, 0);
    AddLitPatch(PatchX, 1);

    AssertTrue(RenderedPatchColor(Window, Viewport, -PatchX).X < 0.05);
    AssertTrue(RenderedPatchColor(Window, Viewport, PatchX).X > 0.3);

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestCastleRendererInternalShader.TestLightEffectsDifferentLightNumber;
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;

  procedure AddPatch(const X: Single);
  var
    Box: TCastleBox;
  begin
    Box := TCastleBox.Create(Window);
    Box.Size := PatchSize;
    Box.Translation := Vector3(X, -0.1, 0);
    Viewport.Items.Add(Box);
  end;

  function AddLight(const X, Radius: Single; const Color: TCastleColorRGB): TCastlePointLight;
  begin
    Result := TCastlePointLight.Create(Window);
    Result.Translation := Vector3(X, 2, 0);
    Result.Attenuation := Vector3(1, 0, 0);
    Result.Radius := Radius;
    Result.Color := Color;
    Viewport.Items.Add(Result);
  end;

var
  MiddleLight: TCastlePointLight;
  PatchColor: TCastleColor;
  I: Integer;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Viewport := OpenWindowWithViewport(Window);

    AddPatch(-PatchX);
    AddPatch(PatchX);

    { Each patch is lit by 2 lights of the same type:
      - red light, at the side, that reaches only this patch,
      - green light in the middle, reaches both patches,
        but has an Effect that multiplies it by zero.

      The order of lights makes the green light to be
      the 2nd light of the left patch, and the 1st light of the right patch.
      So the patches cannot share a shader program, as the effect is plugged
      to a different light number.
      If they would share it, the effect would be applied to the red light
      on one of the patches, leaving the patch green. }
    AddLight(-PatchX - 1.5, 3.5, RedRGB);
    MiddleLight := AddLight(0, 6, GreenRGB);
    MiddleLight.SetEffects([CreateLightFactorEffect(0, false)]);
    AddLight(PatchX + 1.5, 3.5, RedRGB);

    for I := 0 to 1 do
    begin
      PatchColor := RenderedPatchColor(Window, Viewport, Iff(I = 0, -PatchX, PatchX));
      AssertTrue(PatchColor.X > 0.2);
      AssertTrue(PatchColor.Y < 0.05);
    end;

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestCastleRendererInternalShader.TestLightEffectsPerLightUniforms;
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  Root: TX3DRootNode;
  SharedEffect: TEffectNode;
  LeftLight, RightLight: TPointLightNode;
  Scene: TCastleScene;

  { A group with a floor patch at (X, 0, 0) and its point light
    (not global: it lights only this group), sharing SharedEffect. }
  function CreateLitPatch(const X, LightFactor: Single; out Light: TPointLightNode): TGroupNode;
  begin
    Result := TGroupNode.Create;
    Result.AddChildren(CreatePatchShape(X));
    Light := CreateFactorLight(X, LightFactor, WhiteRGB, SharedEffect);
    Result.AddChildren(Light);
  end;

begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Viewport := OpenWindowWithViewport(Window);

    { One Effect node used by both lights, the values differ:
      the patches can share a shader program, the uniform is set per shape. }
    SharedEffect := CreateSharedLightFactorEffect;
    Root := TX3DRootNode.Create;
    Root.AddChildren(CreateLitPatch(-PatchX, 0, LeftLight));
    Root.AddChildren(CreateLitPatch(PatchX, 1, RightLight));
    Scene := TCastleScene.Create(Window);
    Scene.Load(Root, true);
    Scene.RenderOptions.PhongShading := true;
    Viewport.Items.Add(Scene);

    AssertTrue(RenderedPatchColor(Window, Viewport, -PatchX).X < 0.05);
    AssertTrue(RenderedPatchColor(Window, Viewport, PatchX).X > 0.3);

    { Changing a light's custom field changes the rendering. }
    (LeftLight.Field('test_light_factor') as TSFFloat).Send(1);
    (RightLight.Field('test_light_factor') as TSFFloat).Send(0);
    AssertTrue(RenderedPatchColor(Window, Viewport, -PatchX).X > 0.3);
    AssertTrue(RenderedPatchColor(Window, Viewport, PatchX).X < 0.05);

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestCastleRendererInternalShader.TestLightEffectsPerLightUniformsSameShape;
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  Root: TX3DRootNode;
  SharedEffect: TEffectNode;
  Scene: TCastleScene;
  PatchColor: TCastleColor;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Viewport := OpenWindowWithViewport(Window);

    { A patch lit by a red light (factor 1) and a green light (factor 0),
      both with the same Effect node: the effect is plugged once per light,
      <Light> making each copy read the uniform of its light.
      Without it both copies would read one uniform: the patch would be
      black or yellow. }
    SharedEffect := CreateSharedLightFactorEffect;
    Root := TX3DRootNode.Create;
    Root.AddChildren(CreatePatchShape(PatchX));
    Root.AddChildren(CreateFactorLight(PatchX - 0.5, 1, RedRGB, SharedEffect));
    Root.AddChildren(CreateFactorLight(PatchX + 0.5, 0, GreenRGB, SharedEffect));
    Scene := TCastleScene.Create(Window);
    Scene.Load(Root, true);
    Scene.RenderOptions.PhongShading := true;
    Viewport.Items.Add(Scene);

    PatchColor := RenderedPatchColor(Window, Viewport, PatchX);
    AssertTrue(PatchColor.X > 0.2);
    AssertTrue(PatchColor.Y < 0.05);

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

initialization
  RegisterTest(TTestCastleRendererInternalShader);
end.
