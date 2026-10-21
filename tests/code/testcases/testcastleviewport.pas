// -*- compile-command: "./test_single_testcase.sh TTestCastleViewport" -*-
{
  Copyright 2022-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Test CastleViewport unit. }
unit TestCastleViewport;

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestCastleViewport = class(TCastleTestCase)
    procedure TestReadingOldDesigns;
    procedure TestReadingOldDesigns2DSceneManager;
    procedure TestCameraNonDesign;
    procedure TestAutoCameraIgnoresGizmos;
    procedure TestAutoProjection;
    procedure TestEffectiveBlendingSort;
    procedure TestHighDynamicRangeTransparent;
    procedure TestHighDynamicRangeSameLook;
    procedure TestHighDynamicRangeMultiSampling;
    procedure TestTemporalAntiAliasingEdges;
    procedure TestTemporalAntiAliasingCameraMotion;
    procedure TestTemporalAntiAliasingTransparent;
  end;

implementation

uses CastleComponentSerialize, CastleUIControls, CastleViewport, CastleCameras,
  Castle2DSceneManager, CastleProjection, CastleUtils, CastleTransform, CastleVectors,
  CastleScene, CastleBoxes, CastleRenderOptions, CastleWindow, CastleImages,
  CastleColors, CastleGLUtils, CastleControls, X3DNodes, CastleStringUtils, CastleLog,
  CastleInternalGLUtils;

procedure TTestCastleViewport.TestReadingOldDesigns;

  { Check camera was read and inserted into viewport items. }
  procedure AssertCameraUpgraded(const V: TCastleViewport; const CameraName: String);
  begin
    AssertTrue(V.Camera <> nil);
    AssertTrue(V.Camera.Name = CameraName);
    AssertTrue(V.Items.Count > 0);
    AssertTrue(V.Items[V.Items.Count - 1] = V.Camera);
  end;

var
  RootOwner: TComponent;
  //Root: TCastleUserInterface;
begin
  RootOwner := TComponent.Create(nil);
  {Root := }UserInterfaceLoad('castle-data:/designs_before_camera_as_transform/multiple_viewports.castle-user-interface', RootOwner);
  try
    AssertCameraUpgraded(RootOwner.FindRequiredComponent('ViewportTransparent') as TCastleViewport, 'Camera');
    // when reading at runtime, we don't rename it to Camera1 etc. unless we have to, at CastleComponentSerialize
    AssertCameraUpgraded(RootOwner.FindRequiredComponent('ViewportExamine') as TCastleViewport, 'Camera1');
    AssertCameraUpgraded(RootOwner.FindRequiredComponent('ViewportScreenEffect') as TCastleViewport, 'Camera2');
    AssertCameraUpgraded(RootOwner.FindRequiredComponent('ViewportNormal') as TCastleViewport, 'Camera3');
  finally FreeAndNil(RootOwner) end;

  RootOwner := TComponent.Create(nil);
  {Root := }UserInterfaceLoad('castle-data:/designs_before_camera_as_transform/template_2d.castle-user-interface', RootOwner);
  try
    AssertCameraUpgraded(RootOwner.FindRequiredComponent('MainViewport') as TCastleViewport, 'Camera');
  finally FreeAndNil(RootOwner) end;

  RootOwner := TComponent.Create(nil);
  {Root := }UserInterfaceLoad('castle-data:/designs_before_camera_as_transform/template_3d.castle-user-interface', RootOwner);
  try
    AssertCameraUpgraded(RootOwner.FindRequiredComponent('MainViewport') as TCastleViewport, 'Camera');
    AssertTrue((RootOwner.FindRequiredComponent('WalkNavigation') as TCastleNavigation).Parent =
      RootOwner.FindRequiredComponent('MainViewport'));
  finally FreeAndNil(RootOwner) end;

  RootOwner := TComponent.Create(nil);
  {Root := }UserInterfaceLoad('castle-data:/designs_before_camera_as_transform/template_3d_viewer.castle-user-interface', RootOwner);
  try
    AssertCameraUpgraded(RootOwner.FindRequiredComponent('Viewport') as TCastleViewport, 'Camera');
    AssertTrue((RootOwner.FindRequiredComponent('ExamineNavigation1') as TCastleNavigation).Parent =
      RootOwner.FindRequiredComponent('Viewport'));
  finally FreeAndNil(RootOwner) end;
end;

procedure TTestCastleViewport.TestReadingOldDesigns2DSceneManager;

  { Check camera will be inserted into TCastle2DSceneManager items. }
  procedure AssertCameraUpgraded2DSceneManager(const V: TCastle2DSceneManager);
  var
    DummyHandleInput: Boolean;
  begin
    { TCastle2DSceneManager may not include camera as a subcomponent,
      it will be added later during Update. }
    AssertTrue(V.Camera = nil);

    DummyHandleInput := true;
    V.Update(1/30, DummyHandleInput);

    AssertTrue(V.Camera <> nil);
    AssertTrue(V.Items.Count > 0);
    AssertTrue(V.Items[V.Items.Count - 1] = V.Camera);
    AssertTrue(V.Camera.Name = ''); // created by SetupCamera, nameless, to not conflict with existing components
    AssertTrue(V.Camera.ProjectionType = ptOrthographic);
  end;

var
  RootOwner: TComponent;
  //Root: TCastleUserInterface;
begin
  RootOwner := TComponent.Create(nil);
  {Root := }UserInterfaceLoad('castle-data:/designs_before_camera_as_transform/old_scaling_tests_2dscenemanager_without_camera.castle-user-interface', RootOwner);
  try
    AssertCameraUpgraded2DSceneManager(RootOwner.FindRequiredComponent('SceneManager1') as TCastle2DSceneManager);
  finally FreeAndNil(RootOwner) end;
end;

procedure TTestCastleViewport.TestCameraNonDesign;
var
  V: TCastleViewport;
  SavedApplicationMode: TCastleApplicationMode;
begin
  // fake design-mode (CGE editor) for test
  SavedApplicationMode := InternalCastleApplicationMode;
  InternalCastleApplicationMode := appDesign;
  try
    V := TCastleViewport.InternalCreateNonDesign(nil, 0);
    try
      // V.Camera will be auto-created, but it will not have a bounding box or any children (so no gizmo)
      AssertTrue(V.Camera <> nil);
      AssertTrue(V.Camera.BoundingBox.IsEmpty);
      AssertTrue(V.Camera.Count = 0);
      AssertTrue(V.Items.BoundingBox.IsEmpty);
    finally FreeAndNil(V) end;
  finally InternalCastleApplicationMode := SavedApplicationMode end;
end;

procedure TTestCastleViewport.TestAutoCameraIgnoresGizmos;
var
  V: TCastleViewport;
  C: TCastleCamera;
  L: TCastlePointLight;
  SavedApplicationMode: TCastleApplicationMode;
begin
  {$ifdef WASI} // TODO: web: why fails here?
  AbortTest;
  Exit;
  {$endif}

  // fake design-mode (CGE editor) for test
  SavedApplicationMode := InternalCastleApplicationMode;
  // TODO: should be done globally at some place where tests start
  InternalCastleDesignData := 'castle-data:/editor-data/';
  InternalCastleApplicationMode := appDesign;
  try
    V := TCastleViewport.Create(nil);
    try
      V.Items.Add(TCastleBox.Create(V));

      { Bbox of C gizmo should not affect camera determined by V.AssignDefaultCamera }
      C := TCastleCamera.Create(V);
      C.Translation := Vector3(10, 10, 10);
      V.Camera := C;
      V.Items.Add(C);

      { Bbox of L gizmo should not affect camera determined by V.AssignDefaultCamera }
      L := TCastlePointLight.Create(V);
      L.Translation := Vector3(100, 100, 100);
      V.Items.Add(L);

      { Bbox of L gizmo should not affect camera determined by V.AssignDefaultCamera }
      L := TCastlePointLight.Create(V);
      L.Translation := Vector3(1000, 1000, 1000);
      V.Items.Add(L);

      { Bbox will be larger because of C and L, this is normal,
        they have bboxes to allow picking. }
      AssertBoxesEqual(Box3D(
        Vector3(-1.00, -1.00, -1.00),
        Vector3(1000.50, 1000.50, 1000.50)
      ), V.Items.BoundingBox);

      V.AssignDefaultCamera;

      AssertVectorEquals(Vector3(0.00, 0.00, 5.00), C.Translation);
    finally FreeAndNil(V) end;
  finally InternalCastleApplicationMode := SavedApplicationMode end;
end;

type
  TMyViewport = class(TCastleViewport)
    function Proj: TProjection;
  end;

function TMyViewport.Proj: TProjection;
begin
  Result := CalculateProjection;
end;

procedure TTestCastleViewport.TestAutoProjection;
var
  V: TMyViewport;
  B1, B2: TCastleBox;
  ProjectionNear: Single;
begin
  V := TMyViewport.Create(nil);
  try
    ProjectionNear := V.Proj.ProjectionNear;
    AssertEquals(DefaultCameraRadius * RadiusToProjectionNear, ProjectionNear);

    B1 := TCastleBox.Create(V);
    B1.Size := Vector3(10, 10, 10);
    V.Items.Add(B1);
    ProjectionNear := V.Proj.ProjectionNear;
    AssertEquals(DefaultCameraRadius * RadiusToProjectionNear, ProjectionNear);

    { At the very least, adding and enlarging B2 should not make ProjectionNear
      larger, as it would be surprising for user.
      Actually, now it's simpler: we just use constant
      DefaultCameraRadius * RadiusToProjectionNear always. }

    B2 := TCastleBox.Create(V);
    B2.Size := Vector3(10, 10, 10);
    V.Items.Add(B2);
    ProjectionNear := V.Proj.ProjectionNear;
    AssertEquals(DefaultCameraRadius * RadiusToProjectionNear, ProjectionNear);

    B2.Translation := Vector3(1000, 1000, 1000);
    ProjectionNear := V.Proj.ProjectionNear;
    AssertEquals(DefaultCameraRadius * RadiusToProjectionNear, ProjectionNear);
  finally FreeAndNil(V) end;
end;

procedure TTestCastleViewport.TestEffectiveBlendingSort;

  { Copy-pasted from CastleViewport.pas, to test it. }
  function EffectiveBlendingSort(const V: TCastleViewport): TShapeSortNoAuto;
  begin
    if V.BlendingSort = sortAuto then
    begin
      if (V.Camera <> nil) and
        (V.Camera.ProjectionType = ptOrthographic) and
        (TVector3.Equals(V.Camera.Direction, DefaultCameraDirection)) then
        Result := sort2D
      else
        Result := sort3D;
    end else
      Result := V.BlendingSort;
  end;

var
  V: TCastleViewport;
begin
  V := TCastleViewport.Create(nil);
  try
    AssertTrue(V.BlendingSort = sortAuto);
    AssertTrue(sort3D = EffectiveBlendingSort(V));

    V.Setup2D;

    // camera after Setup2D should cause sort2D detected, relied on e.g. by Escape, Unholy
    AssertTrue(V.BlendingSort = sortAuto);
    AssertTrue(sort2D = EffectiveBlendingSort(V));

    V.BlendingSort := sort3DGround;
    AssertTrue(sort3DGround = EffectiveBlendingSort(V));
  finally FreeAndNil(V) end;
end;

{ HighDynamicRange tests ------------------------------------------------------ }

type
  { Scene for the HighDynamicRange tests: a Phong floor and box lit by
    one point light (rendered in one pass, so HighDynamicRange
    should not change how it looks). }
  THighDynamicRangeTestScene = class
    Window: TCastleWindow;
    Viewport: TCastleViewport;
    Light: TCastlePointLight;
    Box: TCastleBox;
    constructor Create(const AWindow: TCastleWindow);
    function Render: TCastleImage;
  end;

constructor THighDynamicRangeTestScene.Create(const AWindow: TCastleWindow);
var
  Floor: TCastleBox;
begin
  inherited Create;
  Window := AWindow;
  Viewport := TCastleViewport.Create(Window);
  Viewport.FullSize := true;
  Viewport.BackgroundColor := Vector4(0.3, 0.4, 0.5, 1);
  Viewport.Camera.SetView(
    Vector3(0, 6, 8),
    Vector3(0, -6, -8),
    Vector3(0, 8, -6));
  Window.Controls.InsertFront(Viewport);

  Floor := TCastleBox.Create(Window);
  Floor.Size := Vector3(10, 0.2, 10);
  Floor.Translation := Vector3(0, -0.1, 0);
  Floor.Material := pmPhong;
  Viewport.Items.Add(Floor);

  Box := TCastleBox.Create(Window);
  Box.Translation := Vector3(0, 1, 0);
  Box.Material := pmPhong;
  Box.Color := Vector4(1, 0.5, 0.2, 1);
  Viewport.Items.Add(Box);

  Light := TCastlePointLight.Create(Window);
  Light.Translation := Vector3(2, 4, 2);
  Light.Intensity := 3;
  Viewport.Items.Add(Light);
end;

function THighDynamicRangeTestScene.Render: TCastleImage;
begin
  Result := Window.SaveScreen;
end;

{ Mean and maximum difference of the color components of 2 images
  of the same size. }
procedure ImageDifference(const A, B: TCastleImage; out Mean, Max: Single);
var
  X, Y, I: Integer;
  CA, CB: TCastleColor;
  D: Single;
begin
  Mean := 0;
  Max := 0;
  for Y := 0 to A.Height - 1 do
    for X := 0 to A.Width - 1 do
    begin
      CA := A.Colors[X, Y, 0];
      CB := B.Colors[X, Y, 0];
      for I := 0 to 2 do
      begin
        D := Abs(CA.Data[I] - CB.Data[I]);
        Mean := Mean + D;
        if D > Max then
          Max := D;
      end;
    end;
  Mean := Mean / (A.Width * A.Height * 3);
end;

procedure TTestCastleViewport.TestHighDynamicRangeTransparent;
{ A transparent viewport with HighDynamicRange must still show
  what is behind it (HighDynamicRange is ignored then). }
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  Background: TCastleRectangleControl;
  Box: TCastleBox;
  Image: TCastleImage;
  Corner, Center: TCastleColor;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 200;
    Window.Height := 200;
    Window.Open;

    Background := TCastleRectangleControl.Create(Window);
    Background.FullSize := true;
    Background.Color := Red;
    Window.Controls.InsertFront(Background);

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.Transparent := true;
    Viewport.HighDynamicRange := true;
    Viewport.Camera.SetView(
      Vector3(0, 0, 10),
      Vector3(0, 0, -1),
      Vector3(0, 1, 0));
    Background.InsertFront(Viewport);

    Box := TCastleBox.Create(Window);
    Box.Material := pmUnlit;
    Box.Color := Vector4(0, 0, 1, 1);
    Viewport.Items.Add(Box);

    Image := Window.SaveScreen;
    try
      Corner := Image.Colors[5, 5, 0];
      Center := Image.Colors[Image.Width div 2, Image.Height div 2, 0];
    finally FreeAndNil(Image) end;

    if not TVector3.Equals(Corner.XYZ, Vector3(1, 0, 0), 0.02) then
      Fail('Transparent viewport with HighDynamicRange: expected red behind it, got ' + Corner.ToString);
    if not TVector3.Equals(Center.XYZ, Vector3(0, 0, 1), 0.02) then
      Fail('Transparent viewport with HighDynamicRange: expected blue box, got ' + Center.ToString);

    CheckGLErrors('TestHighDynamicRangeTransparent');
    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;

procedure TTestCastleViewport.TestHighDynamicRangeSameLook;
{ Rendering in one pass looks the same with and without HighDynamicRange,
  also together with screen space effects and custom screen effects. }
var
  Window: TCastleWindow;
  S: THighDynamicRangeTestScene;

  { Rendering with and without HighDynamicRange looks the same:
    the mean difference of color components is at most MaxMean,
    every difference at most MaxDifference (which catches
    a missing shadow too). }
  procedure CheckSameLook(const What: String;
    const MaxMean: Single = 0.01; const MaxDifference: Single = 0.03);
  var
    Ldr, Hdr: TCastleImage;
    Mean, Max: Single;
  begin
    S.Viewport.HighDynamicRange := false;
    Ldr := S.Render;
    try
      S.Viewport.HighDynamicRange := true;
      Hdr := S.Render;
      try
        ImageDifference(Ldr, Hdr, Mean, Max);
        WritelnLog('HighDynamicRange %s: mean difference %.4f, max %.4f', [What, Mean, Max]);
        if (Mean > MaxMean) or (Max > MaxDifference) then
          Fail(Format('%s: with HighDynamicRange the mean difference is %f, max %f',
            [What, Mean, Max]));
      finally FreeAndNil(Hdr) end;
    finally FreeAndNil(Ldr) end;
    CheckGLErrors(What);
  end;

var
  ScreenEffect: TScreenEffectNode;
  ComposedShader: TComposedShaderNode;
  FragmentShader: TShaderPartNode;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 200;
    Window.Height := 200;
    Window.Open;

    if not GLFeatures.ColorBufferFloat then
    begin
      Window.Close;
      AbortTest;
      Exit;
    end;

    S := THighDynamicRangeTestScene.Create(Window);
    try
      CheckSameLook('plain');

      S.Viewport.ScreenSpaceAmbientOcclusion := true;
      CheckSameLook('ScreenSpaceAmbientOcclusion');
      S.Viewport.ScreenSpaceAmbientOcclusion := false;

      S.Viewport.ScreenSpaceReflections := true;
      CheckSameLook('ScreenSpaceReflections');
      S.Viewport.ScreenSpaceReflections := false;

      { shadow volumes with one light are rendered in one pass too
        (the debug rendering of shadow volumes is blended
        in linear color space, so allow more difference) }
      if GLFeatures.ShadowVolumesPossible then
      begin
        S.Light.Shadows := true;
        S.Viewport.ShadowVolumes := true;
        CheckSameLook('ShadowVolumes');
        S.Viewport.ShadowVolumesRender := true;
        CheckSameLook('ShadowVolumesRender', 0.05, 0.3);
        S.Viewport.ShadowVolumesRender := false;
        S.Viewport.ShadowVolumes := false;
      end;

      { a custom screen effect (inverting colors) gets the screen colors
        (last: the viewport keeps it) }
      FragmentShader := TShaderPartNode.Create;
      FragmentShader.ShaderType := stFragment;
      FragmentShader.Contents :=
        'void main (void)' + NL +
        '{' + NL +
        '  vec4 c = screen_get_color(screen_position());' + NL +
        '  gl_FragColor = vec4(vec3(1.0) - c.rgb, 1.0);' + NL +
        '}';
      ComposedShader := TComposedShaderNode.Create;
      ComposedShader.SetParts([FragmentShader]);
      ScreenEffect := TScreenEffectNode.Create;
      ScreenEffect.SetShaders([ComposedShader]);
      S.Viewport.AddScreenEffect(ScreenEffect);
      CheckSameLook('custom screen effect');
    finally FreeAndNil(S) end;

    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;

procedure TTestCastleViewport.TestHighDynamicRangeMultiSampling;
{ HighDynamicRange works with multi-sampling, keeping the anti-aliased edges. }
var
  Window: TCastleWindow;
  S: THighDynamicRangeTestScene;
  Ldr, Hdr: TCastleImage;
  Mean, Max: Single;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 200;
    Window.Height := 200;
    Window.MultiSampling := 4;
    try
      Window.Open;
    except
      on EGLContextNotPossible do
      begin
        { no multi-sampled window (e.g. Xvfb), cannot test }
        AbortTest;
        Exit;
      end;
    end;

    if not (GLFeatures.ColorBufferFloat and (GLFeatures.CurrentMultiSampling > 1)) then
    begin
      Window.Close;
      AbortTest;
      Exit;
    end;

    S := THighDynamicRangeTestScene.Create(Window);
    try
      Ldr := S.Render;
      try
        S.Viewport.HighDynamicRange := true;
        Hdr := S.Render;
        try
          ImageDifference(Ldr, Hdr, Mean, Max);
          WritelnLog('HighDynamicRange with multi-sampling: mean difference %f, max %f', [Mean, Max]);
          { edges are averaged in linear color space with HighDynamicRange,
            so allow a larger max difference }
          if Mean > 0.01 then
            Fail(Format('Multi-sampling with HighDynamicRange: mean difference %f, max %f', [Mean, Max]));
        finally FreeAndNil(Hdr) end;
      finally FreeAndNil(Ldr) end;
    finally FreeAndNil(S) end;

    CheckGLErrors('TestHighDynamicRangeMultiSampling');
    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;

{ TemporalAntiAliasing tests -------------------------------------------------- }

type
  { Scene for the TemporalAntiAliasing tests: a white unlit box,
    rotated so its edges are diagonal, on a black background. }
  TTemporalTestScene = class
    Window: TCastleWindow;
    Viewport: TCastleViewport;
    Box: TCastleBox;
    constructor Create(const AWindow: TCastleWindow);
    { Render Frames frames, return the last one. }
    function Render(const Frames: Integer = 1): TCastleImage;
  end;

constructor TTemporalTestScene.Create(const AWindow: TCastleWindow);
begin
  inherited Create;
  Window := AWindow;
  Viewport := TCastleViewport.Create(Window);
  Viewport.FullSize := true;
  Viewport.BackgroundColor := Black;
  Viewport.Camera.SetView(
    Vector3(0, 0, 10),
    Vector3(0, 0, -1),
    Vector3(0, 1, 0));
  Window.Controls.InsertFront(Viewport);

  Box := TCastleBox.Create(Window);
  Box.Size := Vector3(4, 3, 1);
  Box.Rotation := Vector4(0, 0, 1, 0.5);
  Box.Material := pmUnlit;
  Box.Color := White;
  Viewport.Items.Add(Box);
end;

function TTemporalTestScene.Render(const Frames: Integer): TCastleImage;
var
  I: Integer;
begin
  for I := 1 to Frames - 1 do
    Window.SaveScreen.Free;
  Result := Window.SaveScreen;
end;

{ Number of pixels neither black nor white (anti-aliased edges). }
function PartialPixels(const Image: TCastleImage): Integer;
var
  X, Y: Integer;
  G: Single;
begin
  Result := 0;
  for Y := 0 to Image.Height - 1 do
    for X := 0 to Image.Width - 1 do
    begin
      G := Image.Colors[X, Y, 0].X;
      if (G > 0.15) and (G < 0.85) then
        Inc(Result);
    end;
end;

{ Number of pixels whose color differs by more than 0.75
  (anti-aliased edges differ less from the aliased ones). }
function VeryDifferentPixels(const A, B: TCastleImage): Integer;
var
  X, Y: Integer;
begin
  Result := 0;
  for Y := 0 to A.Height - 1 do
    for X := 0 to A.Width - 1 do
      if Abs(A.Colors[X, Y, 0].X - B.Colors[X, Y, 0].X) > 0.75 then
        Inc(Result);
end;

procedure TTestCastleViewport.TestTemporalAntiAliasingEdges;
{ With TemporalAntiAliasing the edges get intermediate colors over a few frames,
  the projection is jittered, the image doesn't move. }
var
  Window: TCastleWindow;
  S: TTemporalTestScene;

  procedure CheckAntiAliased(const What: String);
  var
    Aliased, AntiAliased: TCastleImage;
    PartialBefore, PartialAfter: Integer;
    Mean, Max: Single;
    Projection1, Projection2: TMatrix4;
  begin
    S.Viewport.TemporalAntiAliasing := false;
    Aliased := S.Render(2);
    try
      Projection1 := S.Viewport.Camera.ProjectionMatrix;
      S.Render.Free;
      Projection2 := S.Viewport.Camera.ProjectionMatrix;
      AssertTrue(What + ': no jitter without TemporalAntiAliasing',
        TMatrix4.PerfectlyEquals(Projection1, Projection2));

      S.Viewport.TemporalAntiAliasing := true;
      AntiAliased := S.Render(24);
      try
        Projection1 := S.Viewport.Camera.ProjectionMatrix;
        S.Render.Free;
        Projection2 := S.Viewport.Camera.ProjectionMatrix;
        AssertFalse(What + ': jitter with TemporalAntiAliasing',
          TMatrix4.PerfectlyEquals(Projection1, Projection2));

        PartialBefore := PartialPixels(Aliased);
        PartialAfter := PartialPixels(AntiAliased);
        ImageDifference(Aliased, AntiAliased, Mean, Max);
        WritelnLog('TemporalAntiAliasing %s: partial pixels %d -> %d, mean difference %.4f, max %.4f',
          [What, PartialBefore, PartialAfter, Mean, Max]);
        { the box's edges are about 350 pixels long }
        if PartialAfter < PartialBefore + 100 then
          Fail(Format('%s: edges not anti-aliased (partial pixels %d -> %d)',
            [What, PartialBefore, PartialAfter]));
        if Mean > 0.02 then
          Fail(Format('%s: the image changed (mean difference %f)', [What, Mean]));
      finally FreeAndNil(AntiAliased) end;
    finally FreeAndNil(Aliased) end;
    CheckGLErrors(What);
  end;

begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 200;
    Window.Height := 200;
    Window.Open;

    if (GLFeatures.CurrentMultiSampling > 1) or not GLFeatures.TextureDepth then
    begin
      Window.Close;
      AbortTest;
      Exit;
    end;

    S := TTemporalTestScene.Create(Window);
    try
      CheckAntiAliased('plain');

      if GLFeatures.ColorBufferFloat then
      begin
        S.Viewport.HighDynamicRange := true;
        CheckAntiAliased('HighDynamicRange');
        S.Viewport.HighDynamicRange := false;
      end;

      S.Viewport.ScreenSpaceAmbientOcclusion := true;
      CheckAntiAliased('ScreenSpaceAmbientOcclusion');
      S.Viewport.ScreenSpaceAmbientOcclusion := false;
    finally FreeAndNil(S) end;

    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;

procedure TTestCastleViewport.TestTemporalAntiAliasingCameraMotion;
{ When the camera moves, the history follows it (motion vectors from the depth):
  no trails behind the edges. }
const
  StepCount = 5;
var
  Window: TCastleWindow;
  S: TTemporalTestScene;
  Reference: TCastleImage;
  AntiAliased: array [1..StepCount] of TCastleImage;
  Different: Integer;
  Step: Integer;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 200;
    Window.Height := 200;
    Window.Open;

    if (GLFeatures.CurrentMultiSampling > 1) or not GLFeatures.TextureDepth then
    begin
      Window.Close;
      AbortTest;
      Exit;
    end;

    for Step := 1 to StepCount do
      AntiAliased[Step] := nil;
    S := TTemporalTestScene.Create(Window);
    try
      S.Viewport.TemporalAntiAliasing := true;
      S.Render(16).Free;
      { pan the camera by about 6 pixels every frame
        (the view is about 8.3 units wide at the box) }
      for Step := 1 to StepCount do
      begin
        S.Viewport.Camera.Translation := Vector3(0.25 * Step, 0.1 * Step, 10);
        AntiAliased[Step] := S.Render;
      end;
      { compare with the views without TemporalAntiAliasing
        (rendered after, as switching it off forgets the history) }
      S.Viewport.TemporalAntiAliasing := false;
      for Step := 1 to StepCount do
      begin
        S.Viewport.Camera.Translation := Vector3(0.25 * Step, 0.1 * Step, 10);
        Reference := S.Render;
        try
          Different := VeryDifferentPixels(Reference, AntiAliased[Step]);
          WritelnLog('TemporalAntiAliasing camera motion step %d: %d very different pixels',
            [Step, Different]);
          { a trail along the edges would be dozens of pixels }
          if Different > 5 then
            Fail(Format('Camera motion step %d: %d very different pixels (trails)',
              [Step, Different]));
        finally FreeAndNil(Reference) end;
      end;
    finally
      for Step := 1 to StepCount do
        FreeAndNil(AntiAliased[Step]);
      FreeAndNil(S);
    end;

    CheckGLErrors('TestTemporalAntiAliasingCameraMotion');
    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;

procedure TTestCastleViewport.TestTemporalAntiAliasingTransparent;
{ A transparent viewport ignores TemporalAntiAliasing:
  what is behind it stays, the projection is not jittered. }
var
  Window: TCastleWindow;
  Background: TCastleRectangleControl;
  S: TTemporalTestScene;
  Image: TCastleImage;
  Projection1: TMatrix4;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 200;
    Window.Height := 200;
    Window.Open;

    Background := TCastleRectangleControl.Create(Window);
    Background.FullSize := true;
    Background.Color := Red;
    Window.Controls.InsertFront(Background);

    S := TTemporalTestScene.Create(Window);
    try
      S.Viewport.Transparent := true;
      S.Viewport.TemporalAntiAliasing := true;
      Image := S.Render(3);
      try
        Projection1 := S.Viewport.Camera.ProjectionMatrix;
        if not TVector3.Equals(Image.Colors[5, 5, 0].XYZ, Vector3(1, 0, 0), 0.02) then
          Fail('Transparent viewport with TemporalAntiAliasing: expected red behind it, got ' +
            Image.Colors[5, 5, 0].ToString);
      finally FreeAndNil(Image) end;
      S.Render.Free;
      AssertTrue('Transparent viewport: no jitter',
        TMatrix4.PerfectlyEquals(Projection1, S.Viewport.Camera.ProjectionMatrix));
    finally FreeAndNil(S) end;

    CheckGLErrors('TestTemporalAntiAliasingTransparent');
    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;

initialization
  RegisterTest(TTestCastleViewport);
end.
