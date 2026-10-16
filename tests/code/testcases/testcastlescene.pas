// -*- compile-command: "./test_single_testcase.sh TTestScene" -*-
{
  Copyright 2004-2022 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Test CastleScene unit. }
unit TestCastleScene;

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestScene = class(TCastleTestCase)
  published
    procedure TestScene;
    procedure TestSpatialUpgrade;
    procedure TestImageTransformImageWidthHeight;
    { Testcase from https://github.com/castle-engine/castle-engine/issues/664 }
    procedure TestRenderReferencesAndLightRadius;
    { Appearance.depthMode (TDepthModeNode) read from X3D. }
    procedure TestDepthModeParse;
    { TDepthModeNode depth function and polygon offset when rendering
      two coplanar shapes. }
    procedure TestDepthModeRender;
  end;

implementation

uses X3DNodes, CastleSceneCore, CastleScene, CastleBoxes, CastleVectors,
  CastleInternalRays, CastleProjection, CastleComponentSerialize,
  CastleUIControls, CastleWindow, CastleViewport, CastleInternalGLUtils,
  CastleImages, CastleColors;

procedure TTestScene.TestScene;

  procedure EmptySceneAsserts(EmptyScene: TCastleScene);
  var
    CamProjection: TProjectionType;
    CamPos, CamDir, CamUp, GravityUp: TVector3;
  begin
    AssertTrue(EmptyScene.VerticesCount = 0);
    AssertTrue(EmptyScene.TrianglesCount = 0);

    AssertTrue(EmptyScene.BoundingBox.IsEmpty);

    AssertTrue(EmptyScene.ShapesActiveCount = 0);

    AssertTrue(EmptyScene.GetViewpoint(CamProjection, CamPos, CamDir, CamUp, GravityUp) = nil);

    AssertTrue(EmptyScene.FogStack.Top = nil);

    AssertTrue(EmptyScene.InternalBackgroundRenderer = nil);
  end;

var
  EmptyScene: TCastleScene;
begin
  EmptyScene := TCastleScene.Create(nil);
  try
    EmptySceneAsserts(EmptyScene);
    EmptyScene.ChangedAll;
    EmptySceneAsserts(EmptyScene);
  finally FreeAndNil(EmptyScene) end;

  EmptyScene := TCastleScene.Create(nil);
  try
    EmptyScene.Load(TX3DRootNode.Create, true);
    EmptySceneAsserts(EmptyScene);
    EmptyScene.ChangedAll;
    EmptySceneAsserts(EmptyScene);
  finally FreeAndNil(EmptyScene) end;
end;

procedure TTestScene.TestSpatialUpgrade;
var
  SceneSpatialNone, SceneSpatialPreciseCollisions,
    SceneSpatialOnlyRendering, SceneSpatialOnlyDynamicCollisions,
    SceneSpatialOnlyVisibleTriangles, SceneSpatialOnlyStaticCollisions: TCastleScene;
  UiOwner: TComponent;
begin
  UiOwner := TComponent.Create(nil);
  try
    UserInterfaceLoad('castle-data:/designs/test_spatial_upgrade.castle-user-interface', UiOwner);

    SceneSpatialNone := UiOwner.FindRequiredComponent('SceneSpatialNone') as TCastleScene;
    SceneSpatialPreciseCollisions := UiOwner.FindRequiredComponent('SceneSpatialPreciseCollisions') as TCastleScene;
    SceneSpatialOnlyRendering := UiOwner.FindRequiredComponent('SceneSpatialOnlyRendering') as TCastleScene;
    SceneSpatialOnlyDynamicCollisions := UiOwner.FindRequiredComponent('SceneSpatialOnlyDynamicCollisions') as TCastleScene;
    SceneSpatialOnlyVisibleTriangles := UiOwner.FindRequiredComponent('SceneSpatialOnlyVisibleTriangles') as TCastleScene;
    SceneSpatialOnlyStaticCollisions := UiOwner.FindRequiredComponent('SceneSpatialOnlyStaticCollisions') as TCastleScene;

    AssertFalse(SceneSpatialNone.PreciseCollisions);
    AssertTrue(SceneSpatialPreciseCollisions.PreciseCollisions);
    AssertTrue(SceneSpatialOnlyRendering.PreciseCollisions);
    AssertTrue(SceneSpatialOnlyDynamicCollisions.PreciseCollisions);
    AssertTrue(SceneSpatialOnlyVisibleTriangles.PreciseCollisions);
    AssertTrue(SceneSpatialOnlyStaticCollisions.PreciseCollisions);
  finally FreeAndNil(UiOwner) end;
end;

procedure TTestScene.TestImageTransformImageWidthHeight;
var
  ImageTransform: TCastleImageTransform;
begin
  ImageTransform := TCastleImageTransform.Create(nil);
  try
    AssertEquals(0, ImageTransform.ImageWidth);
    AssertEquals(0, ImageTransform.ImageHeight);

    ImageTransform.Url := 'castle-data:/test_texture.png';
    AssertEquals(256, ImageTransform.ImageWidth);
    AssertEquals(256, ImageTransform.ImageHeight);

    ImageTransform.Size := Vector2(100, 200);
    ImageTransform.Scale := Vector3(0.25, 0.333333, 1);

    // ImageWidth and ImageHeight should not change because of Size and Scale
    AssertEquals(256, ImageTransform.ImageWidth);
    AssertEquals(256, ImageTransform.ImageHeight);

    // LocalBoundingBox should reflect Size
    AssertSameValue(100, ImageTransform.LocalBoundingBox.SizeX);
    AssertSameValue(200, ImageTransform.LocalBoundingBox.SizeY);

    // BoundingBox should reflect Size scaled by Scale
    AssertSameValue(100 * 0.25, ImageTransform.BoundingBox.SizeX, 0.01);
    AssertSameValue(200 * 0.333333, ImageTransform.BoundingBox.SizeY, 0.01);

    ImageTransform.Url := '';

    // make sure ImageWidth and ImageHeight are reset to 0
    AssertEquals(0, ImageTransform.ImageWidth);
    AssertEquals(0, ImageTransform.ImageHeight);

    { The box is, for now, not empty, but has zero size. Though we don't promise
      exact behavior of this in API. }
    AssertFalse(ImageTransform.LocalBoundingBox.IsEmpty);
    AssertSameValue(0, ImageTransform.LocalBoundingBox.SizeX);
    AssertSameValue(0, ImageTransform.LocalBoundingBox.SizeY);
    AssertFalse(ImageTransform.BoundingBox.IsEmpty);
    AssertSameValue(0, ImageTransform.BoundingBox.SizeX);
    AssertSameValue(0, ImageTransform.BoundingBox.SizeY);
  finally FreeAndNil(ImageTransform) end;
end;

procedure TTestScene.TestRenderReferencesAndLightRadius;

{ Testcase from
  https://github.com/castle-engine/castle-engine/issues/664

  Before the fixes, rendering would fail with
  OpenGL error (1282): The specified operation is not allowed in the current state.
}

var
  Window: TCastleWindow;
  View: TCastleView;
  Viewport1: TCastleViewport;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    //Window.Visible := false; // need to be Visible to reproduce the crash
    Window.Open;

    View := TCastleView.Create(nil);
    try
      View.DesignUrl := 'castle-data:/designs/gh_664_references_and_light_radius/gameviewmain.castle-user-interface';
      Window.Container.View := View;
      Viewport1 := View.DesignedComponent('Viewport1') as TCastleViewport;

      // default view is already "bad" in design, crashes before 664 fix
      Window.Container.EventBeforeRender;
      Window.Container.EventRender;
      Window.Container.EventUpdate;
      CheckGLErrors('TestRenderReferencesAndLightRadius, frame 0');

      // this is good view, no crash
      Viewport1.Camera.SetWorldView(
        Vector3(0.00, 1.58, 0.83), // position
        Vector3(-0.72, 0.00, -0.69), // direction
        Vector3(0.00, 1.00, 0.00)  // up (current)
      );
      Window.Container.EventBeforeRender;
      Window.Container.EventRender;
      Window.Container.EventUpdate;
      CheckGLErrors('TestRenderReferencesAndLightRadius, frame 1');

      // this is bad view, crashes before 664 fix
      Viewport1.Camera.SetWorldView(
        Vector3(0.00, 1.58, 0.83), // position
        Vector3(-0.98, 0.00, -0.20), // direction
        Vector3(0.00, 1.00, 0.00)  // up (current)
      );
      Window.Container.EventBeforeRender;
      Window.Container.EventRender;
      Window.Container.EventUpdate;
      CheckGLErrors('TestRenderReferencesAndLightRadius, frame 2');

      // Interactive test:
      // while not Window.Closed do
      //   Application.ProcessAllMessages;
    finally FreeAndNil(View) end;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestScene.TestDepthModeParse;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  DepthMode: TDepthModeNode;
begin
  Root := LoadX3DClassicFromString(
    '#X3D V4.0 utf8' + LineEnding +
    'PROFILE Interchange' + LineEnding +
    'DEF S Shape {' + LineEnding +
    '  appearance Appearance {' + LineEnding +
    '    depthMode DepthMode { depthFunc "lequal" polygonOffset -1 -2 }' + LineEnding +
    '  }' + LineEnding +
    '  geometry Box { }' + LineEnding +
    '}', '');
  try
    Shape := Root.FindNode(TShapeNode, 'S') as TShapeNode;
    DepthMode := Shape.Appearance.DepthMode;
    AssertTrue(DepthMode <> nil);
    AssertTrue(DepthMode.DepthFunc = dmfLessEqual);
    AssertVectorEquals(Vector2(-1, -2), DepthMode.PolygonOffset);
  finally FreeAndNil(Root) end;

  DepthMode := TDepthModeNode.Create;
  try
    AssertTrue(DepthMode.DepthFunc = dmfDefault);
    AssertVectorEquals(Vector2(0, 0), DepthMode.PolygonOffset);
    DepthMode.FdDepthFunc.Value := 'always';
    AssertTrue(DepthMode.DepthFunc = dmfAlways);
  finally FreeAndNil(DepthMode) end;
end;

procedure TTestScene.TestDepthModeRender;
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  DepthMode: TDepthModeNode;

  { A square at z = 0, facing the camera, in a new scene. }
  function AddSquare(const Color: TCastleColorRGB; const WithDepthMode: Boolean): TCastleScene;
  var
    Root: TX3DRootNode;
    Shape: TShapeNode;
    Rectangle: TRectangle2DNode;
    Material: TUnlitMaterialNode;
  begin
    Rectangle := TRectangle2DNode.CreateWithShape(Shape);
    Rectangle.Size := Vector2(4, 4);
    Material := TUnlitMaterialNode.Create;
    Material.EmissiveColor := Color;
    Shape.Material := Material;
    if WithDepthMode then
      Shape.Appearance.DepthMode := DepthMode;
    Root := TX3DRootNode.Create;
    Root.AddChildren(Shape);

    Result := TCastleScene.Create(Window);
    Result.Load(Root, true);
    Viewport.Items.Add(Result);
  end;

  function CenterColor: TCastleColorRGB;
  var
    Image: TCastleImage;
  begin
    Image := Window.SaveScreen;
    try
      Result := Image.Colors[Image.Width div 2, Image.Height div 2, 0].XYZ;
    finally FreeAndNil(Image) end;
  end;

  procedure AssertCenter(const Expected: TCastleColorRGB; const Description: String);
  var
    C: TCastleColorRGB;
  begin
    C := CenterColor;
    if not TVector3.Equals(C, Expected, 0.1) then
      Fail(Format('%s: center color %s, expected %s',
        [Description, C.ToString, Expected.ToString]));
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

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.BackgroundColor := Black;
    Viewport.Camera.SetView(Vector3(0, 0, 5), Vector3(0, 0, -1), Vector3(0, 1, 0));
    Window.Controls.InsertFront(Viewport);

    DepthMode := TDepthModeNode.Create;
    // the red square is rendered first, the green one at the same depth after it
    AddSquare(RedRGB, false);
    AddSquare(GreenRGB, true);

    AssertCenter(RedRGB, 'default (less)');

    DepthMode.DepthFunc := dmfLessEqual;
    AssertCenter(GreenRGB, 'lequal');

    DepthMode.DepthFunc := dmfAlways;
    AssertCenter(GreenRGB, 'always');

    DepthMode.DepthFunc := dmfNever;
    AssertCenter(RedRGB, 'never');

    DepthMode.DepthFunc := dmfLess;
    AssertCenter(RedRGB, 'less');

    // negative polygon offset moves the green square towards the camera
    DepthMode.PolygonOffset := Vector2(-1, -1);
    AssertCenter(GreenRGB, 'less with polygon offset -1 -1');

    DepthMode.PolygonOffset := Vector2(1, 1);
    AssertCenter(RedRGB, 'less with polygon offset 1 1');

    // the polygon offset and depth function are restored after the shape
    DepthMode.DepthFunc := dmfDefault;
    DepthMode.PolygonOffset := Vector2(0, 0);
    AssertCenter(RedRGB, 'default again');

    CheckGLErrors('TestDepthModeRender');
    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

initialization
  RegisterTest(TTestScene);
end.
