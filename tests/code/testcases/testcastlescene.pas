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
    { TScreenTextureNode used by an effect of a shape with blending. }
    procedure TestScreenTexture;
  end;

implementation

uses X3DNodes, CastleSceneCore, CastleScene, CastleBoxes, CastleVectors,
  CastleInternalRays, CastleProjection, CastleComponentSerialize,
  CastleUIControls, CastleWindow, CastleViewport, CastleInternalGLUtils,
  CastleImages, CastleColors, CastleRenderOptions, X3DFields;

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

procedure TTestScene.TestScreenTexture;
const
  WindowSize = 200;
  { Show the screen texture mirrored horizontally. }
  EffectCode =
    'uniform sampler2D screen_texture;' + LineEnding +
    'uniform vec2 screen_size;' + LineEnding +
    'void PLUG_fragment_modify(inout vec4 fragment_color)' + LineEnding +
    '{' + LineEnding +
    '  vec2 uv = gl_FragCoord.xy / screen_size;' + LineEnding +
    '  fragment_color = vec4(texture2D(screen_texture, vec2(1.0 - uv.x, uv.y)).rgb, 1.0);' + LineEnding +
    '}';
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;

  { Unlit square of given color and size at given position. }
  function Square(const Color: TCastleColorRGB; const Size: Single;
    const Translation: TVector3; out Shape: TShapeNode): TTransformNode;
  var
    Rectangle: TRectangle2DNode;
    Material: TUnlitMaterialNode;
  begin
    Rectangle := TRectangle2DNode.CreateWithShape(Shape);
    Rectangle.Size := Vector2(Size, Size);
    Material := TUnlitMaterialNode.Create;
    Material.EmissiveColor := Color;
    Shape.Material := Material;
    Result := TTransformNode.Create;
    Result.Translation := Translation;
    Result.AddChildren(Shape);
  end;

  function BuildScene: TX3DRootNode;
  var
    Shape: TShapeNode;
    Effect: TEffectNode;
    Part: TEffectPartNode;
  begin
    Result := TX3DRootNode.Create;
    // opaque background: red on the left, green on the right
    Result.AddChildren(Square(RedRGB, 20, Vector3(-10, 0, 0), Shape));
    Result.AddChildren(Square(GreenRGB, 20, Vector3(10, 0, 0), Shape));

    // shape with blending in front, showing the screen texture
    Result.AddChildren(Square(WhiteRGB, 20, Vector3(0, 0, 1), Shape));
    Shape.Appearance.AlphaMode := amBlend;
    Effect := TEffectNode.Create;
    Effect.Language := slGLSL;
    Effect.AddCustomField(TSFNode.Create(Effect, true, 'screen_texture',
      [TAbstractTextureNode], TScreenTextureNode.Create));
    Effect.AddCustomField(TSFVec2f.Create(Effect, true, 'screen_size',
      Vector2(WindowSize, WindowSize)));
    Part := TEffectPartNode.Create;
    Part.ShaderType := stFragment;
    Part.Contents := EffectCode;
    Effect.SetParts([Part]);
    Shape.Appearance.SetEffects([Effect]);
  end;

var
  Scene: TCastleScene;
  Image: TCastleImage;
  Left, Right: TCastleColorRGB;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := WindowSize;
    Window.Height := WindowSize;
    Window.AntiAliasing := aaNone;
    Window.Open;

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.BackgroundColor := Black;
    Viewport.Camera.SetView(Vector3(0, 0, 5), Vector3(0, 0, -1), Vector3(0, 1, 0));
    Window.Controls.InsertFront(Viewport);

    Scene := TCastleScene.Create(Window);
    Scene.Load(BuildScene, true);
    Viewport.Items.Add(Scene);

    { Render twice: the first frame prepares the screen texture. }
    Image := Window.SaveScreen;
    FreeAndNil(Image);
    Image := Window.SaveScreen;
    try
      Left := Image.Colors[WindowSize div 4, WindowSize div 2, 0].XYZ;
      Right := Image.Colors[WindowSize * 3 div 4, WindowSize div 2, 0].XYZ;
    finally FreeAndNil(Image) end;

    // mirrored: the left side shows the green right side, and the other way around
    if not (TVector3.Equals(Left, GreenRGB, 0.1) and TVector3.Equals(Right, RedRGB, 0.1)) then
      Fail(Format('Screen texture mirrored: left %s (expected green), right %s (expected red)',
        [Left.ToString, Right.ToString]));
    CheckGLErrors('TestScreenTexture');

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

initialization
  RegisterTest(TTestScene);
end.
