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
    { Shape with visible = FALSE casts shadow volumes (shadow-only caster),
      also seen through the place where it would be. }
    procedure TestShadowVolumesInvisibleCaster;
    { TScreenTextureNode used by an effect of a shape with blending. }
    procedure TestScreenTexture;
    { Cube map with reflection texture coordinates on an unlit material
      (like Doom 3 "texgen reflect"). }
    procedure TestCubeMapReflectionUnlit;
    { Appearance.depthMode (TDepthModeNode) read from X3D. }
    procedure TestDepthModeParse;
    { TDepthModeNode depth function and polygon offset when rendering
      two coplanar shapes. }
    procedure TestDepthModeRender;
    { Texture used by a light's Effect, when the light is in another scene
      (CastGlobalLights) than the lit shapes. }
    procedure TestGlobalLightEffectTexture;
    { Light's Effect coloring the light with PLUG_light_color_scale. }
    procedure TestGlobalLightEffectColor;
    { PrepareResources with prShadowVolume calculates shadow volume edges
      only for scenes that cast shadows. }
    procedure TestPrepareShadowVolumesOnlyCasters;
    { Positional light with RadiusFalloff fades smoothly to zero at its radius. }
    procedure TestLightRadiusFalloff;
  end;

implementation

uses X3DNodes, CastleSceneCore, CastleScene, CastleBoxes, CastleVectors,
  CastleInternalRays, CastleProjection, CastleComponentSerialize,
  CastleUIControls, CastleWindow, CastleViewport, CastleInternalGLUtils,
  CastleImages, CastleColors, CastleRenderOptions, X3DFields,
  CastleShapes, CastleTransform, CastleUtils;

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

procedure TTestScene.TestGlobalLightEffectTexture;
const
  { The light's effect multiplies the light by the texture,
    projected along the world X axis on the floor 10 units wide:
    the texture is black on the left (-X) half, white on the right (+X) half. }
  EffectCode =
    { On OpenGLES all fragment shader parts are glued into one source,
      that already declares castle_vertex_eye. }
    '#ifndef GL_ES' + LineEnding +
    'varying vec4 castle_vertex_eye;' + LineEnding +
    '#endif' + LineEnding +
    'vec4 position_eye_to_world_space(vec4 position_eye);' + LineEnding +
    'uniform sampler2D test_light_texture;' + LineEnding +
    'void PLUG_light_scale(inout float scale, const in vec3 normal_eye, const in vec3 light_dir)' + LineEnding +
    '{' + LineEnding +
    '  vec4 world = position_eye_to_world_space(castle_vertex_eye);' + LineEnding +
    '  scale *= texture2D(test_light_texture, vec2(world.x / 10.0 + 0.5, 0.5)).r;' + LineEnding +
    '}';
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  LitScene, LightScene: TCastleScene;

  function BuildLitScene: TX3DRootNode;
  var
    Library_: TEffectNode;
    Shape: TShapeNode;
    Material: TMaterialNode;
    Box: TBoxNode;
    Transform: TTransformNode;
  begin
    Result := TX3DRootNode.Create;

    { Make position_eye_to_world_space available to the light effect. }
    Library_ := TEffectNode.Create;
    Library_.Language := slGLSL;
    Library_.FdShaderLibraries.Items.Add('castle-shader:/EyeWorldSpace.glsl');
    Result.AddChildren(Library_);

    Material := TMaterialNode.Create;
    Material.DiffuseColor := WhiteRGB;
    Box := TBoxNode.CreateWithShape(Shape);
    Box.Size := Vector3(10, 0.2, 10);
    Shape.Material := Material;
    Transform := TTransformNode.Create;
    Transform.Translation := Vector3(0, -0.1, 0);
    Transform.AddChildren(Shape);
    Result.AddChildren(Transform);
  end;

  function BuildLightScene: TX3DRootNode;
  var
    Light: TPointLightNode;
    Effect: TEffectNode;
    Part: TEffectPartNode;
    Texture: TPixelTextureNode;
    Image: TRGBImage;
  begin
    Image := TRGBImage.Create(2, 1);
    Image.Colors[0, 0, 0] := Black;
    Image.Colors[1, 0, 0] := White;
    Texture := TPixelTextureNode.Create;
    Texture.FdImage.Value := Image;
    Texture.TextureProperties := TTexturePropertiesNode.Create;
    Texture.TextureProperties.MinificationFilter := minNearest;
    Texture.TextureProperties.MagnificationFilter := magNearest;
    Texture.TextureProperties.BoundaryModeS := bmClampToEdge;
    Texture.TextureProperties.BoundaryModeT := bmClampToEdge;

    Effect := TEffectNode.Create;
    Effect.Language := slGLSL;
    Effect.AddCustomField(TSFNode.Create(Effect, true, 'test_light_texture',
      [TAbstractTextureNode], Texture));
    Part := TEffectPartNode.Create;
    Part.ShaderType := stFragment;
    Part.Contents := EffectCode;
    Effect.SetParts([Part]);

    Light := TPointLightNode.Create;
    Light.Global := true;
    Light.Location := Vector3(0, 5, 0);
    Light.Attenuation := Vector3(1, 0, 0);
    Light.Radius := 100;
    Light.SetEffects([Effect]);

    Result := TX3DRootNode.Create;
    Result.AddChildren(Light);
  end;

  { Floor color at world (X, 0, 0). }
  function FloorColor(const Image: TCastleImage; const X: Single): TCastleColor;
  var
    P: TVector2;
  begin
    P := Viewport.PositionFromWorld(Vector3(X, 0, 0));
    Result := Image.Colors[Round(P.X), Round(P.Y), 0];
  end;

var
  Image: TCastleImage;
  Left, Right: TCastleColor;
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

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.BackgroundColor := Black;
    Viewport.Camera.SetView(
      Vector3(0, 12, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, -1));
    Window.Controls.InsertFront(Viewport);

    LitScene := TCastleScene.Create(Window);
    LitScene.Load(BuildLitScene, true);
    LitScene.RenderOptions.PhongShading := true;
    Viewport.Items.Add(LitScene);

    { The light is in another scene, lighting LitScene as a global light. }
    LightScene := TCastleScene.Create(Window);
    LightScene.Load(BuildLightScene, true);
    LightScene.CastGlobalLights := true;
    Viewport.Items.Add(LightScene);

    Image := Window.SaveScreen;
    try
      Left := FloorColor(Image, -2.5);
      Right := FloorColor(Image, 2.5);
    finally FreeAndNil(Image) end;

    // texture is black on the left: no light
    AssertTrue(Left.X < 0.05);
    // texture is white on the right: lit (the texture was bound)
    AssertTrue(Right.X > 0.3);
    CheckGLErrors('TestGlobalLightEffectTexture');

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestScene.TestGlobalLightEffectColor;
const
  { The light's effect multiplies the light color by the texture (RGB),
    with PLUG_light_color_scale, projected along the world X axis
    on the floor 10 units wide:
    the texture is red on the left (-X) half, green on the right (+X) half. }
  EffectCode =
    { On OpenGLES all fragment shader parts are glued into one source,
      that already declares castle_vertex_eye. }
    '#ifndef GL_ES' + LineEnding +
    'varying vec4 castle_vertex_eye;' + LineEnding +
    '#endif' + LineEnding +
    'vec4 position_eye_to_world_space(vec4 position_eye);' + LineEnding +
    'uniform sampler2D test_light_texture;' + LineEnding +
    'void PLUG_light_color_scale(inout vec3 color_scale, const in vec3 normal_eye, const in vec3 light_dir)' + LineEnding +
    '{' + LineEnding +
    '  vec4 world = position_eye_to_world_space(castle_vertex_eye);' + LineEnding +
    '  color_scale *= texture2D(test_light_texture, vec2(world.x / 10.0 + 0.5, 0.5)).rgb;' + LineEnding +
    '}';
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  LitScene, LightScene: TCastleScene;

  { Floor with Phong (TMaterialNode) or physical (TPhysicalMaterialNode)
    material: the plug is in both lighting models. }
  function BuildLitScene(const Physical: Boolean): TX3DRootNode;
  var
    Library_: TEffectNode;
    Shape: TShapeNode;
    Material: TMaterialNode;
    PhysicalMaterial: TPhysicalMaterialNode;
    Box: TBoxNode;
    Transform: TTransformNode;
  begin
    Result := TX3DRootNode.Create;

    { Make position_eye_to_world_space available to the light effect. }
    Library_ := TEffectNode.Create;
    Library_.Language := slGLSL;
    Library_.FdShaderLibraries.Items.Add('castle-shader:/EyeWorldSpace.glsl');
    Result.AddChildren(Library_);

    Box := TBoxNode.CreateWithShape(Shape);
    Box.Size := Vector3(10, 0.2, 10);
    if Physical then
    begin
      PhysicalMaterial := TPhysicalMaterialNode.Create;
      PhysicalMaterial.BaseColor := WhiteRGB;
      PhysicalMaterial.Metallic := 0;
      PhysicalMaterial.Roughness := 1;
      Shape.Material := PhysicalMaterial;
    end else
    begin
      Material := TMaterialNode.Create;
      Material.DiffuseColor := WhiteRGB;
      Shape.Material := Material;
    end;
    Transform := TTransformNode.Create;
    Transform.Translation := Vector3(0, -0.1, 0);
    Transform.AddChildren(Shape);
    Result.AddChildren(Transform);
  end;

  function BuildLightScene: TX3DRootNode;
  var
    Light: TPointLightNode;
    Effect: TEffectNode;
    Part: TEffectPartNode;
    Texture: TPixelTextureNode;
    Image: TRGBImage;
  begin
    Image := TRGBImage.Create(2, 1);
    Image.Colors[0, 0, 0] := Red;
    Image.Colors[1, 0, 0] := Green;
    Texture := TPixelTextureNode.Create;
    Texture.FdImage.Value := Image;
    Texture.TextureProperties := TTexturePropertiesNode.Create;
    Texture.TextureProperties.MinificationFilter := minNearest;
    Texture.TextureProperties.MagnificationFilter := magNearest;
    Texture.TextureProperties.BoundaryModeS := bmClampToEdge;
    Texture.TextureProperties.BoundaryModeT := bmClampToEdge;

    Effect := TEffectNode.Create;
    Effect.Language := slGLSL;
    Effect.AddCustomField(TSFNode.Create(Effect, true, 'test_light_texture',
      [TAbstractTextureNode], Texture));
    Part := TEffectPartNode.Create;
    Part.ShaderType := stFragment;
    Part.Contents := EffectCode;
    Effect.SetParts([Part]);

    Light := TPointLightNode.Create;
    Light.Global := true;
    Light.Location := Vector3(0, 5, 0);
    Light.Attenuation := Vector3(1, 0, 0);
    Light.Radius := 100;
    Light.SetEffects([Effect]);

    Result := TX3DRootNode.Create;
    Result.AddChildren(Light);
  end;

  { Floor color at world (X, 0, 0). }
  function FloorColor(const Image: TCastleImage; const X: Single): TCastleColor;
  var
    P: TVector2;
  begin
    P := Viewport.PositionFromWorld(Vector3(X, 0, 0));
    Result := Image.Colors[Round(P.X), Round(P.Y), 0];
  end;

var
  Image: TCastleImage;
  Left, Right: TCastleColor;
  Physical: Boolean;
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

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.BackgroundColor := Black;
    Viewport.Camera.SetView(
      Vector3(0, 12, 0),
      Vector3(0, -1, 0),
      Vector3(0, 0, -1));
    Window.Controls.InsertFront(Viewport);

    { The light is in another scene, lighting LitScene as a global light. }
    LightScene := TCastleScene.Create(Window);
    LightScene.Load(BuildLightScene, true);
    LightScene.CastGlobalLights := true;
    Viewport.Items.Add(LightScene);

    for Physical := false to true do
    begin
      LitScene := TCastleScene.Create(Window);
      LitScene.Load(BuildLitScene(Physical), true);
      LitScene.RenderOptions.PhongShading := true;
      Viewport.Items.Add(LitScene);

      Image := Window.SaveScreen;
      try
        Left := FloorColor(Image, -2.5);
        Right := FloorColor(Image, 2.5);
      finally FreeAndNil(Image) end;

      // texture is red on the left: only red light
      AssertTrue(Left.X > 0.2);
      AssertTrue(Left.Y < 0.05);
      AssertTrue(Left.Z < 0.05);
      // texture is green on the right: only green light
      AssertTrue(Right.X < 0.05);
      AssertTrue(Right.Y > 0.2);
      AssertTrue(Right.Z < 0.05);
      CheckGLErrors('TestGlobalLightEffectColor');

      FreeAndNil(LitScene);
    end;

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestScene.TestPrepareShadowVolumesOnlyCasters;

  { Separate quads (not sharing any edge, so all their edges are border edges),
    like the open meshes of level geometry. }
  function OpenMesh(const QuadCount: Integer): TX3DRootNode;
  var
    Geometry: TIndexedTriangleSetNode;
    Coord: TCoordinateNode;
    Shape: TShapeNode;
    Points: TVector3List;
    Indexes: TInt32List;
    I, Base: Integer;
  begin
    Points := TVector3List.Create;
    Indexes := TInt32List.Create;
    try
      for I := 0 to QuadCount - 1 do
      begin
        Base := Points.Count;
        { a gap of 0.1 between quads, so no edges are shared }
        Points.Add(Vector3(I * 1.1    , 0, 0));
        Points.Add(Vector3(I * 1.1 + 1, 0, 0));
        Points.Add(Vector3(I * 1.1 + 1, 0, -1));
        Points.Add(Vector3(I * 1.1    , 0, -1));
        Indexes.AddRange([Base, Base + 1, Base + 2, Base, Base + 2, Base + 3]);
      end;
      Coord := TCoordinateNode.Create;
      Coord.SetPoint(Points);
      Geometry := TIndexedTriangleSetNode.Create;
      Geometry.Coord := Coord;
      Geometry.SetIndex(Indexes);
    finally
      FreeAndNil(Points);
      FreeAndNil(Indexes);
    end;
    Shape := TShapeNode.Create;
    Shape.Geometry := Geometry;
    Result := TX3DRootNode.Create;
    Result.AddChildren(Shape);
    { also a closed shape }
    Shape := TShapeNode.Create;
    Shape.Geometry := TBoxNode.Create;
    Result.AddChildren(Shape);
  end;

  { How many shapes have their shadow volume edges calculated. }
  function EdgesCalculatedCount(const Scene: TCastleSceneCore): Integer;
  var
    Shape: TShape;
  begin
    Result := 0;
    for Shape in Scene.Shapes.TraverseList(false) do
      if Shape.InternalShadowVolumes.ManifoldAndBorderEdgesCalculated then
        Inc(Result);
  end;

var
  Scene: TCastleSceneCore;
  Params: TPrepareParams;
begin
  Params := TPrepareParams.Create;
  try
    Scene := TCastleSceneCore.Create(nil);
    try
      Scene.Load(OpenMesh(100), true);
      AssertEquals(2, Scene.Shapes.TraverseList(false).Count);
      AssertEquals(0, EdgesCalculatedCount(Scene));

      { not casting shadows: nothing to prepare for shadow volumes }
      Scene.CastShadows := false;
      {$warnings off} // using PrepareResources, should be internal
      Scene.PrepareResources([prShadowVolume], Params);
      {$warnings on}
      AssertEquals(0, EdgesCalculatedCount(Scene));

      { casting shadows: edges of all shapes prepared }
      Scene.CastShadows := true;
      {$warnings off}
      Scene.PrepareResources([prShadowVolume], Params);
      {$warnings on}
      AssertEquals(2, EdgesCalculatedCount(Scene));
    finally FreeAndNil(Scene) end;
  finally FreeAndNil(Params) end;
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

procedure TTestScene.TestCubeMapReflectionUnlit;
const
  FaceColors: array [0..5] of TCastleColorRGB = (
    (X: 1; Y: 0; Z: 0), // front (-Z)
    (X: 0; Y: 1; Z: 0), // back (+Z)
    (X: 0; Y: 0; Z: 1), // left
    (X: 1; Y: 1; Z: 0), // right
    (X: 0; Y: 1; Z: 1), // top
    (X: 1; Y: 0; Z: 1)  // bottom
  );

  function Face(const I: Integer): TPixelTextureNode;
  var
    Image: TRGBImage;
  begin
    Image := TRGBImage.Create(1, 1);
    Image.Colors[0, 0, 0] := Vector4(FaceColors[I], 1);
    Result := TPixelTextureNode.Create;
    Result.FdImage.Value := Image;
  end;

  { A quad at z = 0 facing +Z, with an unlit material
    and a cube map with given texture coordinates generator mode. }
  function BuildScene(const Mode: String): TX3DRootNode;
  var
    Shape: TShapeNode;
    Faces: TIndexedFaceSetNode;
    Coord: TCoordinateNode;
    Cube: TComposedCubeMapTextureNode;
    Generator: TTextureCoordinateGeneratorNode;
  begin
    Faces := TIndexedFaceSetNode.CreateWithShape(Shape);
    Coord := TCoordinateNode.Create;
    Coord.SetPoint([Vector3(-5, -5, 0), Vector3(5, -5, 0), Vector3(5, 5, 0), Vector3(-5, 5, 0)]);
    Faces.Coord := Coord;
    Faces.SetCoordIndex([0, 1, 2, 3]);
    Shape.Material := TUnlitMaterialNode.Create;
    Cube := TComposedCubeMapTextureNode.Create;
    Cube.FdFront.Value := Face(0);
    Cube.FdBack.Value := Face(1);
    Cube.FdLeft.Value := Face(2);
    Cube.FdRight.Value := Face(3);
    Cube.FdTop.Value := Face(4);
    Cube.FdBottom.Value := Face(5);
    Shape.Texture := Cube;
    Generator := TTextureCoordinateGeneratorNode.Create;
    Generator.FdMode.Value := Mode;
    Faces.TexCoord := Generator;
    Result := TX3DRootNode.Create;
    Result.AddChildren(Shape);
  end;

var
  Window: TCastleWindow;
  Viewport: TCastleViewport;

  { Center color of the quad, seen from the given camera position
    (looking at the quad center). }
  function CenterColor(const Mode: String; const CameraPosition: TVector3): TCastleColorRGB;
  var
    Scene: TCastleScene;
    Image: TCastleImage;
  begin
    Viewport.Camera.SetView(CameraPosition, -CameraPosition, Vector3(0, 1, 0));
    Scene := TCastleScene.Create(nil);
    try
      Scene.Load(BuildScene(Mode), true);
      Viewport.Items.Add(Scene);
      Image := Window.SaveScreen;
      try
        Result := Image.Colors[Image.Width div 2, Image.Height div 2, 0].XYZ;
      finally FreeAndNil(Image) end;
    finally FreeAndNil(Scene) end;
  end;

  procedure AssertColor(const Expected, Actual: TCastleColorRGB; const Description: String);
  begin
    if not TVector3.Equals(Actual, Expected, 0.1) then
      Fail(Format('%s: color %s, expected %s', [Description, Actual.ToString, Expected.ToString]));
  end;

begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 100;
    Window.Height := 100;
    Window.Open;

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Window.Controls.InsertFront(Viewport);

    // looking straight at the quad: the reflection points back, to +Z
    AssertColor(FaceColors[1], CenterColor('WORLDSPACEREFLECTIONVECTOR', Vector3(0, 0, 5)),
      'reflection seen from +Z');
    // looking down from above: the reflection points down (-Y), the "bottom" face
    AssertColor(FaceColors[5], CenterColor('WORLDSPACEREFLECTIONVECTOR', Vector3(0, 4, 0.5)),
      'reflection seen from above');
    AssertColor(FaceColors[1], CenterColor('WORLDSPACENORMAL', Vector3(0, 0, 5)),
      'normal');
    CheckGLErrors('TestCubeMapReflectionUnlit');

    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestScene.TestShadowVolumesInvisibleCaster;
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  Light: TCastlePointLight;
  CasterScene, FloorScene: TCastleScene;
  Box: TBoxNode;
  CasterShape: TShapeNode;
  Lit: Single;

  function BuildCaster: TX3DRootNode;
  var
    Transform: TTransformNode;
  begin
    Box := TBoxNode.CreateWithShape(CasterShape);
    Box.Size := Vector3(2, 0.5, 2);
    CasterShape.Material := TMaterialNode.Create;
    Transform := TTransformNode.Create;
    Transform.Translation := Vector3(0, 2, 0);
    Transform.AddChildren(CasterShape);
    Result := TX3DRootNode.Create;
    Result.AddChildren(Transform);
  end;

  function BuildFloor: TX3DRootNode;
  var
    Shape: TShapeNode;
    FloorBox: TBoxNode;
    Transform: TTransformNode;
  begin
    FloorBox := TBoxNode.CreateWithShape(Shape);
    FloorBox.Size := Vector3(20, 0.2, 20);
    Shape.Material := TMaterialNode.Create;
    Transform := TTransformNode.Create;
    Transform.Translation := Vector3(0, -0.1, 0);
    Transform.AddChildren(Shape);
    Result := TX3DRootNode.Create;
    Result.AddChildren(Transform);
  end;

  { Brightness of the floor at world (X, 0, Z) on the screen. }
  function FloorBrightness(const X, Z: Single): Single;
  var
    Image: TCastleImage;
    P: TVector2;
    C: TCastleColor;
  begin
    Image := Window.SaveScreen;
    try
      P := Viewport.PositionFromWorld(Vector3(X, 0, Z));
      C := Image.Colors[Round(P.X), Round(P.Y), 0];
      Result := (C.X + C.Y + C.Z) / 3;
    finally FreeAndNil(Image) end;
  end;

  procedure CheckShadow(const Description: String; const Lit: Single);
  var
    Under: Single;
  begin
    Under := FloorBrightness(0, 0);
    if not (Under < Lit * 0.5) then
      Fail(Format('%s: floor under the caster %f, aside %f (expected in shadow under)',
        [Description, Under, Lit]));
  end;

begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 300;
    Window.Height := 300;
    Window.Open;

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.BackgroundColor := Black;
    Viewport.ShadowVolumes := true;
    { looking down at the floor through the caster }
    Viewport.Camera.SetView(Vector3(0, 6, 3), Vector3(0, -6, -3), Vector3(0, 1, 0));
    Window.Controls.InsertFront(Viewport);

    Light := TCastlePointLight.Create(Window);
    Light.Translation := Vector3(0, 5, 0);
    Light.Shadows := true;
    Viewport.Items.Add(Light);

    FloorScene := TCastleScene.Create(Window);
    FloorScene.Load(BuildFloor, true);
    FloorScene.CastShadows := false;
    Viewport.Items.Add(FloorScene);

    CasterScene := TCastleScene.Create(Window);
    CasterScene.Load(BuildCaster, true);
    Viewport.Items.Add(CasterScene);

    { the floor away from the caster is lit }
    Lit := FloorBrightness(2.5, 0);
    AssertTrue(Lit > 0.2);

    { invisible caster: its shadow is seen through it }
    CasterShape.Visible := false;
    CheckShadow('invisible caster, camera outside the shadow (z-pass)', Lit);

    { looking straight down through the caster's top (the light cap of its
      shadow volume): the view enters the shadow volume only there }
    Viewport.Camera.SetView(Vector3(0, 8, 0), Vector3(0, -1, 0), Vector3(0, 0, -1));
    CheckShadow('invisible caster, seen through its light cap (z-pass)', Lit);

    { camera inside the shadow volume, under the caster (z-fail) }
    Viewport.Camera.SetView(Vector3(0, 1.2, 0.2), Vector3(0, -1.2, -0.2), Vector3(0, 0, -1));
    CheckShadow('invisible caster, camera in the shadow (z-fail)', Lit);

    CheckGLErrors('TestShadowVolumesInvisibleCaster');
    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

procedure TTestScene.TestLightRadiusFalloff;
var
  Window: TCastleWindow;
  Viewport: TCastleViewport;
  Light: TCastlePointLight;
  FloorScene: TCastleScene;
  LightNode: TPointLightNode;

  function BuildFloor: TX3DRootNode;
  var
    Shape: TShapeNode;
    FloorBox: TBoxNode;
    Transform: TTransformNode;
  begin
    FloorBox := TBoxNode.CreateWithShape(Shape);
    FloorBox.Size := Vector3(30, 0.2, 30);
    Shape.Material := TMaterialNode.Create;
    Transform := TTransformNode.Create;
    Transform.Translation := Vector3(0, -0.1, 0);
    Transform.AddChildren(Shape);
    Result := TX3DRootNode.Create;
    Result.AddChildren(Transform);
  end;

  { Brightness of the floor at world (X, 0, 0) on the screen. }
  function FloorBrightness(const X: Single): Single;
  var
    Image: TCastleImage;
    P: TVector2;
    C: TCastleColor;
  begin
    Image := Window.SaveScreen;
    try
      P := Viewport.PositionFromWorld(Vector3(X, 0, 0));
      C := Image.Colors[Round(P.X), Round(P.Y), 0];
      Result := (C.X + C.Y + C.Z) / 3;
    finally FreeAndNil(Image) end;
  end;

const
  { The light is 5 above the floor, its radius is 10.
    Floor points at these X are at distance 5, 9 and 11 from the light. }
  XHalf = 0;
  XNear = 7.4833; // Sqrt(9 * 9 - 5 * 5)
  XOut = 9.798; // Sqrt(11 * 11 - 5 * 5)
var
  HardHalf, HardNear, SmoothHalf, SmoothNear: Single;
begin
  { attenuation computed on the CPU (ray-tracer) }
  LightNode := TPointLightNode.Create;
  try
    LightNode.Radius := 10;
    AssertSameValue(1, LightNode.CalculateAttenuation(9), 0.0001);
    LightNode.RadiusFalloff := true;
    AssertSameValue(1, LightNode.CalculateAttenuation(0), 0.0001);
    AssertSameValue(Sqr(1 - Sqr(Sqr(0.5))), LightNode.CalculateAttenuation(5), 0.0001);
    AssertSameValue(Sqr(1 - Sqr(Sqr(0.9))), LightNode.CalculateAttenuation(9), 0.0001);
    AssertSameValue(0, LightNode.CalculateAttenuation(11), 0.0001);
    { no radius: no falloff }
    LightNode.Radius := -1;
    AssertSameValue(1, LightNode.CalculateAttenuation(50), 0.0001);
  finally FreeAndNil(LightNode) end;

  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Width := 300;
    Window.Height := 300;
    Window.Open;

    Viewport := TCastleViewport.Create(Window);
    Viewport.FullSize := true;
    Viewport.BackgroundColor := Black;
    { looking down at the floor }
    Viewport.Camera.SetView(Vector3(5, 25, 0), Vector3(0, -1, 0), Vector3(0, 0, -1));
    Window.Controls.InsertFront(Viewport);

    Light := TCastlePointLight.Create(Window);
    Light.Translation := Vector3(0, 5, 0);
    Light.Radius := 10;
    Light.Intensity := 1;
    Light.Attenuation := Vector3(1, 0, 0); // no attenuation, only the radius
    Viewport.Items.Add(Light);

    FloorScene := TCastleScene.Create(Window);
    FloorScene.Load(BuildFloor, true);
    Viewport.Items.Add(FloorScene);

    { hard cut-off at the radius }
    HardHalf := FloorBrightness(XHalf);
    HardNear := FloorBrightness(XNear);
    AssertTrue(HardHalf > 0.2);
    AssertTrue(HardNear > 0.2);
    AssertTrue(FloorBrightness(XOut) < 0.1);

    { smooth falloff: (1 - ratio^4)^2 is 0.88 at half the radius,
      0.12 at 0.9 of the radius }
    Light.RadiusFalloff := true;
    SmoothHalf := FloorBrightness(XHalf);
    SmoothNear := FloorBrightness(XNear);
    if not ((SmoothHalf > HardHalf * 0.8) and (SmoothHalf < HardHalf * 0.95)) then
      Fail(Format('Floor at half the radius: %f with falloff, %f without (expected about 0.88 of it)',
        [SmoothHalf, HardHalf]));
    if not ((SmoothNear > HardNear * 0.05) and (SmoothNear < HardNear * 0.2)) then
      Fail(Format('Floor at 0.9 of the radius: %f with falloff, %f without (expected about 0.12 of it)',
        [SmoothNear, HardNear]));
    AssertTrue(FloorBrightness(XOut) < 0.1);

    CheckGLErrors('TestLightRadiusFalloff');
    Window.Close;
  finally DestroyWindowForTest(Window) end;
end;

initialization
  RegisterTest(TTestScene);
end.
