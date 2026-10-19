// -*- compile-command: "./test_single_testcase.sh TTestCastleInternalGLShadowVolumes" -*-
{
  Copyright 2023-2023 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

unit TestCastleInternalGLShadowVolumes;

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestCastleInternalGLShadowVolumes = class(TCastleTestCase)
  published
    procedure TestCasterShadowPossiblyVisible;
    procedure TestSeveralLights;
    { Light passes of several lights on a physical (gamma corrected) material
      add up like a single pass with TCastleViewport.HighDynamicRange. }
    procedure TestSeveralLightsHighDynamicRange;
  end;

implementation

uses CastleTransform, CastleFrustum, CastleInternalGLShadowVolumes, CastleProjection,
  CastleVectors, CastleViewport, CastleBoxes, CastleWindow, CastleScene, CastleImages,
  CastleColors, CastleGLUtils, CastleUIControls, CastleRenderOptions,
  CastleInternalGLUtils, Math, CastleLog;

procedure TTestCastleInternalGLShadowVolumes.TestCasterShadowPossiblyVisible;
var
  Viewport: TCastleViewport;
  Camera: TCastleCamera;
  Projection: TProjection;
  Frustum: TFrustum;
  SvRenderer: TGLShadowVolumeRenderer;
begin
  Viewport := TCastleViewport.Create(nil);

  Camera := Viewport.Camera;
  { stand at (10, 0, 0), looking in -Z, up in +Y }
  Camera.SetView(
    Vector3(10, 0, 0),
    Vector3(0, 0, -1),
    Vector3(0, 1, 0));

  FillChar(Projection, SizeOf(Projection), #0);
  Projection.ProjectionType := ptPerspective;
  Projection.PerspectiveAnglesRad := Vector2(Pi / 3, Pi / 3);
  Projection.ProjectionNear := 1;
  Projection.ProjectionFar := ZFarInfinity;

  Frustum.Init(Projection.Matrix(1), Camera.Matrix);
  AssertTrue(Frustum.FarInfinity);

  SvRenderer := TGLShadowVolumeRenderer.Create;
  try
    // point light test
    SvRenderer.InitFrustumAndLight(Frustum, Vector4(-10, 0, 0, 1));
    AssertTrue(SvRenderer.GetCasterShadowPossiblyVisible(
      Box3D(Vector3(-1, -1, -1), Vector3(1, 1, 1)).Transform(TranslationMatrix(0, 0, 0))
    ));
    AssertTrue(SvRenderer.GetCasterShadowPossiblyVisible(
      Box3D(Vector3(-1, -1, -1), Vector3(1, 1, 1)).Transform(TranslationMatrix(-10, 0, 0))
    ));
    AssertTrue(SvRenderer.GetCasterShadowPossiblyVisible(
      Box3D(Vector3(-1, -1, -1), Vector3(1, 1, 1)).Transform(TranslationMatrix(10, 0, 0))
    ));
    // too far to the right to cast shadows
    AssertFalse(SvRenderer.GetCasterShadowPossiblyVisible(
      Box3D(Vector3(-1, -1, -1), Vector3(1, 1, 1)).Transform(TranslationMatrix(20, 0, 0))
    ));

    // directional light test
    SvRenderer.InitFrustumAndLight(Frustum, Vector4(1, 0, 0, 0));
    AssertTrue(SvRenderer.GetCasterShadowPossiblyVisible(
      Box3D(Vector3(-1, -1, -1), Vector3(1, 1, 1)).Transform(TranslationMatrix(0, 0, 0))
    ));
    AssertTrue(SvRenderer.GetCasterShadowPossiblyVisible(
      Box3D(Vector3(-1, -1, -1), Vector3(1, 1, 1)).Transform(TranslationMatrix(-10, 0, 0))
    ));
    AssertTrue(SvRenderer.GetCasterShadowPossiblyVisible(
      Box3D(Vector3(-1, -1, -1), Vector3(1, 1, 1)).Transform(TranslationMatrix(10, 0, 0))
    ));
    // too far to the right to cast shadows
    AssertFalse(SvRenderer.GetCasterShadowPossiblyVisible(
      Box3D(Vector3(-1, -1, -1), Vector3(1, 1, 1)).Transform(TranslationMatrix(20, 0, 0))
    ));
  finally
    FreeAndNil(SvRenderer);
    FreeAndNil(Viewport);
  end;
end;

procedure TTestCastleInternalGLShadowVolumes.TestSeveralLights;
{ Render with shadow volumes from 2 lights, a red one on the left (-X)
  and a green one on the right (+X), a box between them,
  looking down at the floor.

  The floor at +X is in the shadow of the red light (but lit by the green one),
  the floor at -X is in the shadow of the green light (but lit by the red one). }
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  Floor, Box: TCastleBox;
  LightRed, LightGreen: TCastlePointLight;

  { Color of the rendered floor at given world position. }
  function FloorColor(const Image: TCastleImage; const X: Single): TCastleColor;
  var
    P: TVector2;
  begin
    P := Viewport.PositionFromWorld(Vector3(X, 0, 0));
    Result := Image.Colors[Round(P.X), Round(P.Y), 0];
  end;

  function Render: TCastleImage;
  begin
    Result := Window.SaveScreen;
  end;

const
  Dark = 0.05;
  Lit = 0.2;
var
  Image: TCastleImage;
  ColorLeft, ColorRight: TCastleColor;
  LeftBlack, RightBlack: Boolean;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 400;
    Window.Height := 400;
    Window.Open;

    if not GLFeatures.ShadowVolumesPossible then
    begin
      // no stencil buffer, cannot test
      Window.Close;
      AbortTest;
      Exit;
    end;

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.BackgroundColor := Black;
    Viewport.Camera.SetView(
      Vector3(0, 12, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, -1));
    Window.Controls.InsertFront(Viewport);

    { Phong materials: no gamma correction, so the light passes add up exactly. }
    Floor := TCastleBox.Create(Window);
    Floor.Size := Vector3(10, 0.2, 10);
    Floor.Translation := Vector3(0, -0.1, 0);
    Floor.Material := pmPhong;
    Floor.CastShadows := false;
    Viewport.Items.Add(Floor);

    Box := TCastleBox.Create(Window);
    Box.Size := Vector3(1, 2, 1);
    Box.Translation := Vector3(0, 1, 0);
    Box.Material := pmPhong;
    Viewport.Items.Add(Box);

    LightRed := TCastlePointLight.Create(Window);
    LightRed.Translation := Vector3(-2.5, 3, 0);
    LightRed.Color := Vector3(1, 0, 0);
    LightRed.Intensity := 20;
    LightRed.Shadows := true;
    Viewport.Items.Add(LightRed);

    LightGreen := TCastlePointLight.Create(Window);
    LightGreen.Translation := Vector3(2.5, 3, 0);
    LightGreen.Color := Vector3(0, 1, 0);
    LightGreen.Intensity := 20;
    LightGreen.Shadows := true;
    Viewport.Items.Add(LightGreen);

    { Several lights: each casts its own shadows. }
    Viewport.ShadowVolumesMaxLights := 2;
    Image := Render;
    try
      ColorLeft := FloorColor(Image, -2);
      ColorRight := FloorColor(Image, 2);
    finally FreeAndNil(Image) end;
    // in the green light's shadow, lit by red
    AssertTrue(ColorLeft.X > Lit);
    AssertTrue(ColorLeft.Y < Dark);
    // in the red light's shadow, lit by green
    AssertTrue(ColorRight.X < Dark);
    AssertTrue(ColorRight.Y > Lit);

    { One light (default): only the main light casts shadows,
      and other lights with shadowVolumes are off in its shadow,
      so one side is black and the other lit by both lights. }
    Viewport.ShadowVolumesMaxLights := 1;
    Image := Render;
    try
      ColorLeft := FloorColor(Image, -2);
      ColorRight := FloorColor(Image, 2);
    finally FreeAndNil(Image) end;
    LeftBlack := (ColorLeft.X < Dark) and (ColorLeft.Y < Dark);
    RightBlack := (ColorRight.X < Dark) and (ColorRight.Y < Dark);
    AssertTrue(LeftBlack <> RightBlack);
    if LeftBlack then
      AssertTrue((ColorRight.X > Lit) and (ColorRight.Y > Lit))
    else
      AssertTrue((ColorLeft.X > Lit) and (ColorLeft.Y > Lit));

    { Without shadows: both sides lit by both lights. }
    Viewport.ShadowVolumes := false;
    Image := Render;
    try
      ColorLeft := FloorColor(Image, -2);
      ColorRight := FloorColor(Image, 2);
    finally FreeAndNil(Image) end;
    AssertTrue((ColorLeft.X > Lit) and (ColorLeft.Y > Lit));
    AssertTrue((ColorRight.X > Lit) and (ColorRight.Y > Lit));

    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;


procedure TTestCastleInternalGLShadowVolumes.TestSeveralLightsHighDynamicRange;
{ Two white lights above a floor with a physical material, both casting
  shadow volumes (nothing is in shadow). Where both lights reach the floor,
  rendering them in separate passes (ShadowVolumesMaxLights = 2)
  should look like rendering them at once (shadow volumes off),
  which is only true with HighDynamicRange: without it, the light passes
  are added after gamma correction, which is too bright. }
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  Floor: TCastleBox;

  function FloorBrightness: Single;
  var
    Image: TCastleImage;
    P: TVector2;
    C: TCastleColor;
  begin
    Image := Window.SaveScreen;
    try
      P := Viewport.PositionFromWorld(Vector3(0, 0, 0));
      C := Image.Colors[Round(P.X), Round(P.Y), 0];
      Result := (C.X + C.Y + C.Z) / 3;
    finally FreeAndNil(Image) end;
  end;

  function AddLight(const X: Single): TCastlePointLight;
  begin
    Result := TCastlePointLight.Create(Window);
    Result.Translation := Vector3(X, 3, 0);
    Result.Intensity := 4;
    Result.Shadows := true;
    Viewport.Items.Add(Result);
  end;

var
  OnePass, SeveralPasses, SeveralPassesHdr, OnePassHdr: Single;
  LightLeft, LightRight: TCastlePointLight;
  Ambient, OnlyLeft, OnlyRight, Expected: Single;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 400;
    Window.Height := 400;
    Window.Open;

    if not (GLFeatures.ShadowVolumesPossible and GLFeatures.ColorBufferFloat) then
    begin
      Window.Close;
      AbortTest;
      Exit;
    end;

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.BackgroundColor := Black;
    Viewport.Camera.SetView(
      Vector3(0, 12, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, -1));
    Window.Controls.InsertFront(Viewport);

    Floor := TCastleBox.Create(Window);
    Floor.Size := Vector3(10, 0.2, 10);
    Floor.Translation := Vector3(0, -0.1, 0);
    Floor.Material := pmPhysical;
    Floor.CastShadows := false;
    Viewport.Items.Add(Floor);

    LightLeft := AddLight(-1);
    LightRight := AddLight(1);
    Viewport.ShadowVolumesMaxLights := 2;

    Viewport.ShadowVolumes := false;
    OnePass := FloorBrightness;
    { not black, not saturated, so the comparisons below mean something }
    AssertTrue(OnePass > 0.2);
    AssertTrue(OnePass < 0.85);

    Viewport.ShadowVolumes := true;
    SeveralPasses := FloorBrightness;
    { too bright without high dynamic range }
    AssertTrue(SeveralPasses > OnePass + 0.05);

    Viewport.HighDynamicRange := true;
    SeveralPassesHdr := FloorBrightness;
    if Abs(SeveralPassesHdr - OnePass) > 0.03 then
      Fail(Format('Light passes with HighDynamicRange: %f, one pass: %f (without HighDynamicRange: %f)',
        [SeveralPassesHdr, OnePass, SeveralPasses]));

    { one pass looks the same with high dynamic range }
    Viewport.ShadowVolumes := false;
    OnePassHdr := FloorBrightness;
    if Abs(OnePassHdr - OnePass) > 0.02 then
      Fail(Format('One pass with HighDynamicRange: %f, without: %f', [OnePassHdr, OnePass]));

    { also for a Phong material (no gamma correction) }
    Floor.Material := pmPhong;
    Viewport.HighDynamicRange := false;
    OnePass := FloorBrightness;
    Viewport.HighDynamicRange := true;
    OnePassHdr := FloorBrightness;
    if Abs(OnePassHdr - OnePass) > 0.02 then
      Fail(Format('Phong, one pass with HighDynamicRange: %f, without: %f', [OnePassHdr, OnePass]));

    { Phong (no gamma correction) light passes: without HighDynamicRange
      they add up in screen colors, with it in linear colors
      (documented at TCastleViewport.HighDynamicRange).
      Measure the ambient part (no lights) and each light alone
      (rendered in one pass, as the same color with and without
      HighDynamicRange) without HighDynamicRange. }
    Viewport.ShadowVolumes := true;
    Viewport.HighDynamicRange := false;
    Floor.Color := Vector4(0.5, 0.5, 0.5, 1); // keep the sums below 1
    LightLeft.Exists := false;
    LightRight.Exists := false;
    Ambient := FloorBrightness;
    LightLeft.Exists := true;
    OnlyLeft := FloorBrightness - Ambient;
    LightLeft.Exists := false;
    LightRight.Exists := true;
    OnlyRight := FloorBrightness - Ambient;
    LightLeft.Exists := true;

    SeveralPasses := FloorBrightness;
    Expected := Ambient + OnlyLeft + OnlyRight;
    if Abs(SeveralPasses - Expected) > 0.02 then
      Fail(Format('Phong light passes without HighDynamicRange: %f, expected the sum %f', [SeveralPasses, Expected]));

    Viewport.HighDynamicRange := true;
    SeveralPassesHdr := FloorBrightness;
    Expected := Power(
      Power(Ambient, 2.2) + Power(OnlyLeft, 2.2) + Power(OnlyRight, 2.2), 1 / 2.2);
    WritelnLog('Phong light passes: ambient %f, lights %f and %f, both %f, both with HighDynamicRange %f (expected %f)',
      [Ambient, OnlyLeft, OnlyRight, SeveralPasses, SeveralPassesHdr, Expected]);
    if Abs(SeveralPassesHdr - Expected) > 0.02 then
      Fail(Format('Phong light passes with HighDynamicRange: %f, expected the sum in linear colors %f (screen colors sum %f)',
        [SeveralPassesHdr, Expected, SeveralPasses]));

    CheckGLErrors('TestSeveralLightsHighDynamicRange');
    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;

initialization
  RegisterTest(TTestCastleInternalGLShadowVolumes);
end.
