// -*- compile-command: "./test_single_testcase.sh TTestCastleEnvironmentLight" -*-
{
  Copyright 2026 Popa Marius Adrian.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Test EnvironmentLight rendering: image-based lighting, environment probes
  chosen per shape (influence box), irradiance volumes. }
unit TestCastleEnvironmentLight;

interface

uses
  Classes, SysUtils,
  CastleTester, CastleWindow, CastleViewport, CastleColors, CastleVectors,
  CastleScene, X3DNodes;

type
  TTestCastleEnvironmentLight = class(TCastleTestCase)
  strict private
    Window: TCastleWindow;
    Viewport: TCastleViewport;
    { Open Window with Viewport, @false if the test cannot run here. }
    function OpenWindow: Boolean;
    procedure CloseWindow;
    { Floor tile (physical, white, rough, not metallic) at X, facing +Y. }
    function AddTile(const X: Single; const Metallic: Single = 0;
      const Roughness: Single = 1): TCastleScene;
    { Scene with an environment light, as a global light. }
    function AddEnvironmentLight(const Light: TEnvironmentLightNode): TCastleScene;
    function ColorAt(const World: TVector3): TCastleColor;
  published
    { The light's textures are looked up by the normal in the light's (world)
      space: a floor facing +Y uses the top side, whatever the camera. }
    procedure TestWorldSpaceLookup;
    { Two environment lights on the same shapes: each has its own textures. }
    procedure TestTwoLights;
    { Each shape is lit by the environment light with the smallest influence
      box containing it, lights without a box are the fallback. }
    procedure TestProbesPerShape;
    { Diffuse light from the irradiance volume, varying with the position
      (L0) and the normal (L1). }
    procedure TestIrradianceVolume;
    { Specular light from the specular texture, by the reflection direction
      in the light's (world) space. }
    procedure TestSpecularReflection;
  end;

{ Cube map texture with a solid color on each side. }
function SolidCubeMap(const PositiveX, NegativeX, PositiveY, NegativeY,
  PositiveZ, NegativeZ: TCastleColorRGB): TComposedCubeMapTextureNode;

implementation

uses CastleImages, CastleRenderOptions, CastleTransform, CastleUtils,
  CastleInternalGLUtils, CastleGLUtils, CastleUriUtils, CastleFilesUtils;

function SolidPixelTexture(const Color: TCastleColorRGB): TPixelTextureNode;
var
  Image: TRGBImage;
begin
  Image := TRGBImage.Create(4, 4);
  Image.Clear(Vector4Byte(
    Round(Color.X * 255), Round(Color.Y * 255), Round(Color.Z * 255), 255));
  Result := TPixelTextureNode.Create;
  Result.FdImage.Value := Image;
end;

function SolidCubeMap(const PositiveX, NegativeX, PositiveY, NegativeY,
  PositiveZ, NegativeZ: TCastleColorRGB): TComposedCubeMapTextureNode;
begin
  Result := TComposedCubeMapTextureNode.Create;
  Result.Right  := SolidPixelTexture(PositiveX);
  Result.Left   := SolidPixelTexture(NegativeX);
  Result.Top    := SolidPixelTexture(PositiveY);
  Result.Bottom := SolidPixelTexture(NegativeY);
  Result.Front  := SolidPixelTexture(PositiveZ);
  Result.Back   := SolidPixelTexture(NegativeZ);
end;

function TTestCastleEnvironmentLight.OpenWindow: Boolean;
begin
  Result := CanCreateWindowForTest;
  if not Result then
    Exit;
  Window := CreateWindowForTest;
  Window.Width := 300;
  Window.Height := 200;
  Window.Open;
  if not (GLFeatures.Shaders and GLFeatures.TextureCubeMap) then
  begin
    CloseWindow;
    Exit(false);
  end;

  Viewport := TCastleViewport.Create(Window);
  Viewport.FullSize := true;
  Viewport.BackgroundColor := Black;
  Viewport.Camera.SetView(
    Vector3(0, 20, 0),
    Vector3(0, -1, 0),
    Vector3(0, 0, -1));
  Window.Controls.InsertFront(Viewport);
end;

procedure TTestCastleEnvironmentLight.CloseWindow;
begin
  Window.Close;
  DestroyWindowForTest(Window);
end;

function TTestCastleEnvironmentLight.AddTile(const X: Single;
  const Metallic: Single; const Roughness: Single): TCastleScene;
var
  Material: TPhysicalMaterialNode;
  Appearance: TAppearanceNode;
  Box: TBoxNode;
  Shape: TShapeNode;
  Root: TX3DRootNode;
begin
  Material := TPhysicalMaterialNode.Create;
  Material.BaseColor := Vector3(1, 1, 1);
  Material.Metallic := Metallic;
  Material.Roughness := Roughness;
  Appearance := TAppearanceNode.Create;
  Appearance.Material := Material;
  Box := TBoxNode.CreateWithShape(Shape);
  Box.Size := Vector3(4, 0.2, 4);
  Shape.Appearance := Appearance;
  Root := TX3DRootNode.Create;
  Root.AddChildren(Shape);

  Result := TCastleScene.Create(Window);
  Result.Load(Root, true);
  Result.Translation := Vector3(X, -0.1, 0);
  Viewport.Items.Add(Result);
end;

function TTestCastleEnvironmentLight.AddEnvironmentLight(
  const Light: TEnvironmentLightNode): TCastleScene;
var
  Root: TX3DRootNode;
begin
  Light.Global := true;
  Root := TX3DRootNode.Create;
  Root.AddChildren(Light);
  Result := TCastleScene.Create(Window);
  Result.Load(Root, true);
  Result.CastGlobalLights := true;
  Viewport.Items.Add(Result);
end;

function TTestCastleEnvironmentLight.ColorAt(const World: TVector3): TCastleColor;
var
  Image: TCastleImage;
  P: TVector2;
begin
  Image := Window.SaveScreen;
  try
    P := Viewport.PositionFromWorld(World);
    Result := Image.Colors[Round(P.X), Round(P.Y), 0];
  finally FreeAndNil(Image) end;
end;

procedure TTestCastleEnvironmentLight.TestWorldSpaceLookup;
const
  Red: TCastleColorRGB = (X: 1; Y: 0; Z: 0);
  Green: TCastleColorRGB = (X: 0; Y: 1; Z: 0);
  Blue: TCastleColorRGB = (X: 0; Y: 0; Z: 1);
var
  Light: TEnvironmentLightNode;
  C: TCastleColor;
begin
  if not OpenWindow then
  begin
    AbortTest;
    Exit;
  end;
  try
    AddTile(0);
    Light := TEnvironmentLightNode.Create;
    { +Y (up) red, -Y green, the sides blue }
    Light.DiffuseTexture := SolidCubeMap(Blue, Blue, Red, Green, Blue, Blue);
    AddEnvironmentLight(Light);

    { looking down }
    C := ColorAt(Vector3(0, 0, 0));
    AssertTrue('floor lit by the top side (red), got ' + C.ToString,
      (C.X > 0.8) and (C.Y < 0.1) and (C.Z < 0.1));

    { looking from the side and above: the eye-space normal is different,
      the light's texture is still read by the world normal }
    Viewport.Camera.SetView(
      Vector3(8, 8, 8),
      Vector3(-1, -1, -1),
      Vector3(-1, 2, -1));
    C := ColorAt(Vector3(0, 0, 0));
    AssertTrue('floor still lit by the top side (red), got ' + C.ToString,
      (C.X > 0.8) and (C.Y < 0.1) and (C.Z < 0.1));

    CheckGLErrors('TestWorldSpaceLookup');
  finally CloseWindow end;
end;

procedure TTestCastleEnvironmentLight.TestTwoLights;
const
  Red: TCastleColorRGB = (X: 1; Y: 0; Z: 0);
  Green: TCastleColorRGB = (X: 0; Y: 1; Z: 0);
  Black3: TCastleColorRGB = (X: 0; Y: 0; Z: 0);
var
  Light: TEnvironmentLightNode;
  C: TCastleColor;
begin
  if not OpenWindow then
  begin
    AbortTest;
    Exit;
  end;
  try
    AddTile(0);
    { two lights without influence boxes both light the floor:
      red from one, green from the other }
    Light := TEnvironmentLightNode.Create;
    Light.DiffuseTexture := SolidCubeMap(Black3, Black3, Red, Black3, Black3, Black3);
    AddEnvironmentLight(Light);
    Light := TEnvironmentLightNode.Create;
    Light.DiffuseTexture := SolidCubeMap(Black3, Black3, Green, Black3, Black3, Black3);
    AddEnvironmentLight(Light);

    C := ColorAt(Vector3(0, 0, 0));
    AssertTrue('floor lit by both lights (yellow), got ' + C.ToString,
      (C.X > 0.8) and (C.Y > 0.8) and (C.Z < 0.1));
    CheckGLErrors('TestTwoLights');
  finally CloseWindow end;
end;

procedure TTestCastleEnvironmentLight.TestProbesPerShape;
const
  Black3: TCastleColorRGB = (X: 0; Y: 0; Z: 0);

  function ProbeLight(const Color: TCastleColorRGB;
    const BoxCenter, BoxSize: TVector3): TEnvironmentLightNode;
  begin
    Result := TEnvironmentLightNode.Create;
    Result.DiffuseTexture := SolidCubeMap(Black3, Black3, Color, Black3, Black3, Black3);
    Result.InfluenceCenter := BoxCenter;
    Result.InfluenceSize := BoxSize;
  end;

  procedure AssertColor(const What: String; const C: TCastleColor; const Expected: TVector3);
  begin
    if not TVector3.Equals(C.XYZ, Expected, 0.1) then
      Fail(Format('%s: expected %s, got %s', [What, Expected.ToString, C.ToString]));
  end;

var
  Scene: TCastleScene;
begin
  if not OpenWindow then
  begin
    AbortTest;
    Exit;
  end;
  try
    Viewport.Camera.SetView(
      Vector3(0, 30, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, -1));
    { the same tiles (same shader program, unless the probes differ) }
    AddTile(-6);
    AddTile(0);
    AddTile(6);
    { fallback: blue }
    AddEnvironmentLight(ProbeLight(Vector3(0, 0, 1), TVector3.Zero, Vector3(-1, -1, -1)));
    { big box over x -10..2: yellow }
    AddEnvironmentLight(ProbeLight(Vector3(1, 1, 0), Vector3(-4, 0, 0), Vector3(12, 10, 10)));
    { small box over x -8..-4: red; the light is moved by its transformation,
      the box is in the light's local coordinates }
    Scene := AddEnvironmentLight(ProbeLight(Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(4, 10, 10)));
    Scene.Translation := Vector3(-5, 0, 0);

    AssertColor('tile in the small box', ColorAt(Vector3(-6, 0, 0)), Vector3(1, 0, 0));
    AssertColor('tile only in the big box', ColorAt(Vector3(0, 0, 0)), Vector3(1, 1, 0));
    AssertColor('tile outside the boxes', ColorAt(Vector3(6, 0, 0)), Vector3(0, 0, 1));
    CheckGLErrors('TestProbesPerShape');
  finally CloseWindow end;
end;

procedure TTestCastleEnvironmentLight.TestIrradianceVolume;
const
  { grid points along X, Y, Z }
  NX = 2;
  NY = 2;
  NZ = 2;

  { Irradiance volume texture with the given coefficients at the grid points
    x = 0 and x = 1 (the same along Y and Z). }
  function VolumeUrl(const FileName: String;
    const L0Left, L0Right, L1Y: TVector3): String;
  var
    Image: TRGBFloatImage;
    X, Y, Z, Slab: Integer;
    V: TVector3;
  begin
    Image := TRGBFloatImage.Create(NX, NY, NZ * 4);
    try
      for Slab := 0 to 3 do
        for Z := 0 to NZ - 1 do
          for Y := 0 to NY - 1 do
            for X := 0 to NX - 1 do
            begin
              case Slab of
                0: if X = 0 then V := L0Left else V := L0Right;
                2: V := L1Y;
                else V := TVector3.Zero;
              end;
              PVector3(Image.PixelPtr(X, Y, Slab * NZ + Z))^ := V;
            end;
      Result := FilenameToUriSafe(InclPathDelim(GetTempDir) + FileName);
      SaveImage(Image, Result);
    finally FreeAndNil(Image) end;
  end;

  function VolumeTexture(const Url: String): TImageTexture3DNode;
  var
    Props: TTexturePropertiesNode;
  begin
    Props := TTexturePropertiesNode.Create;
    Props.FdMinificationFilter.Value := 'AVG_PIXEL';
    Props.FdMagnificationFilter.Value := 'AVG_PIXEL';
    Props.BoundaryModeS := bmClampToEdge;
    Props.BoundaryModeT := bmClampToEdge;
    Props.BoundaryModeR := bmClampToEdge;
    Props.GenerateMipMaps := false;
    Result := TImageTexture3DNode.Create;
    Result.SetUrl([Url]);
    Result.TextureProperties := Props;
  end;

  procedure AssertColor(const What: String; const C: TCastleColor; const Expected: TVector3);
  begin
    if not TVector3.Equals(C.XYZ, Expected, 0.1) then
      Fail(Format('%s: expected %s, got %s', [What, Expected.ToString, C.ToString]));
  end;

var
  Light: TEnvironmentLightNode;
  LightScene: TCastleScene;
  C: TCastleColor;
begin
  if not OpenWindow then
  begin
    AbortTest;
    Exit;
  end;
  try
    if not GLFeatures.Texture3D then
    begin
      AbortTest;
      Exit;
    end;
    Viewport.Camera.SetView(
      Vector3(0, 30, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, -1));
    { a long floor over x -8..8 (two tiles side by side) }
    AddTile(-2);
    AddTile(2);
    AddTile(-6);
    AddTile(6);

    { L0 red at x = -8, green at x = 8; no L1 }
    Light := TEnvironmentLightNode.Create;
    Light.InfluenceCenter := TVector3.Zero;
    Light.InfluenceSize := Vector3(16, 4, 16);
    Light.IrradianceVolume := VolumeTexture(VolumeUrl(
      'castle_test_irradiance_volume_1.ktx',
      Vector3(1, 0, 0), Vector3(0, 1, 0), TVector3.Zero));
    LightScene := AddEnvironmentLight(Light);

    { the grid points are at the texel centers: x = -4 and x = 4
      (the box is 16 wide, 2 points), constant outside }
    AssertColor('left (red)', ColorAt(Vector3(-6, 0, 0)), Vector3(1, 0, 0));
    AssertColor('right (green)', ColorAt(Vector3(6, 0, 0)), Vector3(0, 1, 0));
    C := ColorAt(Vector3(0, 0, 0));
    { halfway: linear 0.5 + 0.5, gamma corrected to about 0.73 }
    AssertTrue('middle between red and green, got ' + C.ToString,
      (C.X > 0.6) and (C.X < 0.85) and (C.Y > 0.6) and (C.Y < 0.85) and (C.Z < 0.1));

    { L1 along Y: the floor (normal +Y) gets L0 + L1y }
    Viewport.Items.Remove(LightScene);
    Light := TEnvironmentLightNode.Create;
    Light.InfluenceCenter := TVector3.Zero;
    Light.InfluenceSize := Vector3(16, 4, 16);
    Light.IrradianceVolume := VolumeTexture(VolumeUrl(
      'castle_test_irradiance_volume_2.ktx',
      Vector3(0, 0, 0.5), Vector3(0, 0, 0.5), Vector3(0, 0, 0.5)));
    AddEnvironmentLight(Light);
    AssertColor('L0 + L1y for a floor facing +Y (blue 1)', ColorAt(Vector3(0, 0, 0)), Vector3(0, 0, 1));

    CheckGLErrors('TestIrradianceVolume');
  finally CloseWindow end;
end;

procedure TTestCastleEnvironmentLight.TestSpecularReflection;
const
  White3: TCastleColorRGB = (X: 1; Y: 1; Z: 1);
  Black3: TCastleColorRGB = (X: 0; Y: 0; Z: 0);
var
  Light: TEnvironmentLightNode;
  LightScene: TCastleScene;
  C: TCastleColor;
begin
  if not OpenWindow then
  begin
    AbortTest;
    Exit;
  end;
  try
    { a mirror: metallic, smooth }
    AddTile(0, 1, 0);
    { looking down at an angle: the reflected view goes up, mostly to +Y
      (not 45 degrees, where +Y and -Z would be equally major axes
      of the cube map lookup) }
    Viewport.Camera.SetView(
      Vector3(0, 8, 4),
      Vector3(0, -2, -1),
      Vector3(0, 1, -2));

    Light := TEnvironmentLightNode.Create;
    Light.SpecularTexture := SolidCubeMap(Black3, Black3, White3, Black3, Black3, Black3);
    LightScene := AddEnvironmentLight(Light);
    C := ColorAt(Vector3(0, 0, 0));
    AssertTrue('mirror reflects the top side (bright), got ' + C.ToString,
      (C.X > 0.8) and (C.Y > 0.8) and (C.Z > 0.8));

    Viewport.Items.Remove(LightScene);
    Light := TEnvironmentLightNode.Create;
    Light.SpecularTexture := SolidCubeMap(Black3, Black3, Black3, White3, Black3, Black3);
    AddEnvironmentLight(Light);
    C := ColorAt(Vector3(0, 0, 0));
    AssertTrue('mirror doesn''t reflect the bottom side (dark), got ' + C.ToString,
      (C.X < 0.1) and (C.Y < 0.1) and (C.Z < 0.1));

    CheckGLErrors('TestSpecularReflection');
  finally CloseWindow end;
end;

initialization
  RegisterTest(TTestCastleEnvironmentLight);
end.
