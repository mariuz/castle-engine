// -*- compile-command: "./test_single_testcase.sh TTestCastleShadowMaps" -*-
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

{ Test shadow maps: point lights (cube faces), cascades of directional lights
  (blended, following each viewport's camera), the shared shadow map atlas,
  global lights casting on other scenes, hidden casters (CastShadowsWhenHidden),
  sizes chosen by the screen size (ShadowMapsSizeByScreen). }
unit TestCastleShadowMaps;

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestCastleShadowMaps = class(TCastleTestCase)
  published
    procedure TestAtlasAllocation;
    procedure TestPointLight;
    procedure TestPointLightOwnTexture;
    procedure TestPointLightVariance;
    procedure TestSpotLight;
    procedure TestCascades;
    procedure TestGlobalLightOtherScene;
    procedure TestHiddenCasters;
    procedure TestSizeByScreen;
    procedure TestCascadesTwoViewports;
  end;

implementation

uses CastleWindow, CastleViewport, CastleScene, CastleVectors, CastleImages,
  CastleGLUtils, CastleRenderOptions, CastleRectangles, CastleInternalRenderer,
  CastleInternalGLUtils, CastleTransform,
  X3DNodes, CastleColors;

type
  { A window with a viewport, to render shadow map scenes. }
  TShadowMapsTest = class
    Owner: TCastleTestCase;
    Window: TCastleWindow;
    Viewport: TCastleViewport;
    Image: TCastleImage;
    constructor Create(const AOwner: TCastleTestCase);
    destructor Destroy; override;
    function AddScene(const Url: String): TCastleScene;
    { Update and render a few frames, keep the last in Image. }
    procedure Render;
    { Luminance of the rendered pixel showing this world point. }
    function Luminance(const WorldPoint: TVector3): Single;
  end;

constructor TShadowMapsTest.Create(const AOwner: TCastleTestCase);
begin
  inherited Create;
  Owner := AOwner;
  Window := AOwner.CreateWindowForTest;
  Window.Width := 300;
  Window.Height := 300;
  Window.Open;

  Viewport := TCastleViewport.Create(Window);
  Viewport.FullSize := true;
  Viewport.BackgroundColor := Black;
  Window.Controls.InsertFront(Viewport);
end;

destructor TShadowMapsTest.Destroy;
begin
  FreeAndNil(Image);
  Window.Close;
  Owner.DestroyWindowForTest(Window);
  inherited;
end;

function TShadowMapsTest.AddScene(const Url: String): TCastleScene;
begin
  Result := TCastleScene.Create(Window);
  Result.Load(Url);
  { only shadow maps, not shadow volumes }
  Result.ReceiveShadowVolumes := false;
  Viewport.Items.Add(Result);
end;

procedure TShadowMapsTest.Render;
var
  I: Integer;
begin
  { Update renders the shadow maps (TCastleScene.Update). }
  for I := 1 to 3 do
  begin
    Window.Container.EventUpdate;
    Window.SaveScreen.Free;
  end;
  Window.Container.EventUpdate;
  FreeAndNil(Image);
  Image := Window.SaveScreen;
end;

function TShadowMapsTest.Luminance(const WorldPoint: TVector3): Single;
var
  P: TVector4;
  X, Y: Integer;
begin
  P := Viewport.Camera.ProjectionMatrix * Viewport.Camera.Matrix * Vector4(WorldPoint, 1);
  X := Round((P.X / P.W * 0.5 + 0.5) * Image.Width);
  Y := Round((P.Y / P.W * 0.5 + 0.5) * Image.Height);
  Result := GrayscaleValue(Image.Colors[X, Y, 0].XYZ);
end;

{ Luminance of the rendered pixel showing this world point in viewport V. }
function LuminanceIn(const S: TShadowMapsTest; const V: TCastleViewport;
  const WorldPoint: TVector3): Single;
var
  P: TVector4;
  R: TFloatRectangle;
  X, Y: Integer;
begin
  P := V.Camera.ProjectionMatrix * V.Camera.Matrix * Vector4(WorldPoint, 1);
  R := V.RenderRect;
  X := Round(R.Left + (P.X / P.W * 0.5 + 0.5) * R.Width);
  Y := Round(R.Bottom + (P.Y / P.W * 0.5 + 0.5) * R.Height);
  Result := GrayscaleValue(S.Image.Colors[X, Y, 0].XYZ);
end;

{ Shadows of the 4 boxes around the point light: each in another cube face. }
procedure CheckPointLightShadows(const Test: TTestCastleShadowMaps;
  const S: TShadowMapsTest; const What: String);
const
  { a lit point, at about the same distance from the light as the shadows }
  Lit: TVector3 = (X: 5; Y: 0; Z: 5);
  Shadows: array [0..3] of TVector3 = (
    (X:  7; Y: 0; Z:  0),
    (X: -7; Y: 0; Z:  0),
    (X:  0; Y: 0; Z:  7),
    (X:  0; Y: 0; Z: -7)
  );
var
  I: Integer;
  LitValue, ShadowValue: Single;
begin
  LitValue := S.Luminance(Lit);
  Test.AssertTrue(What + ': lit floor is lit', LitValue > 0.2);
  Test.AssertTrue(What + ': floor under the light is lit',
    S.Luminance(Vector3(0, 0, 0)) > LitValue);
  for I := 0 to High(Shadows) do
  begin
    ShadowValue := S.Luminance(Shadows[I]);
    if ShadowValue > LitValue * 0.3 then
      Test.Fail(Format('%s: no shadow at %s (luminance %f, lit %f)', [
        What, Shadows[I].ToString, ShadowValue, LitValue]));
  end;
end;

procedure SetTopCamera(const S: TShadowMapsTest);
begin
  S.Viewport.Camera.SetView(
    Vector3(0, 20, 0.01), Vector3(0, -1, 0), Vector3(0, 0, -1));
end;

procedure TTestCastleShadowMaps.TestAtlasAllocation;
var
  Window: TCastleWindow;
  Atlas: TShadowMapAtlas;
  Rects: array [0..4] of TRectangle;
  R: TRectangle;
  I: Integer;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  Window := CreateWindowForTest;
  try
    Window.Open;
    if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) then
    begin
      Window.Close;
      AbortTest;
      Exit;
    end;

    Atlas := TShadowMapAtlas.Create(1024);
    try
      { 4 quarters fit, a 5th doesn't }
      for I := 0 to 3 do
        AssertTrue(Atlas.Allocate(512, Rects[I]));
      AssertFalse(Atlas.Allocate(512, Rects[4]));
      AssertFalse(Atlas.Allocate(16, R));
      for I := 0 to 3 do
      begin
        AssertEquals(512, Rects[I].Width);
        AssertTrue((Rects[I].Left mod 512 = 0) and (Rects[I].Bottom mod 512 = 0));
      end;
      AssertFalse(Rects[0].Collides(Rects[1]));
      AssertFalse(Rects[2].Collides(Rects[3]));

      { released quarters merge: the whole texture fits again }
      for I := 0 to 3 do
        Atlas.Release(Rects[I]);
      AssertTrue(Atlas.Allocate(1024, R));
      AssertTrue(R.Equals(Rectangle(0, 0, 1024, 1024)));
      Atlas.Release(R);

      { small and large blocks together }
      AssertTrue(Atlas.Allocate(128, Rects[0]));
      AssertTrue(Atlas.Allocate(512, Rects[1]));
      AssertTrue(Atlas.Allocate(512, Rects[2]));
      AssertTrue(Atlas.Allocate(512, Rects[3]));
      AssertFalse(Atlas.Allocate(512, R));
      AssertTrue(Atlas.Allocate(256, Rects[4]));
      AssertFalse(Rects[0].Collides(Rects[4]));
      for I := 0 to 4 do
        Atlas.Release(Rects[I]);
      AssertTrue(Atlas.Allocate(1024, R));
    finally FreeAndNil(Atlas) end;

    Window.Close;
  finally
    DestroyWindowForTest(Window);
  end;
end;

procedure TTestCastleShadowMaps.TestPointLight;
var
  S: TShadowMapsTest;
  Scene: TCastleScene;
  ShadowMap: TGeneratedShadowMapNode;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  S := TShadowMapsTest.Create(Self);
  try
    if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) then
    begin
      AbortTest;
      Exit;
    end;
    Scene := S.AddScene('castle-data:/shadow_maps/point_light.x3dv');
    SetTopCamera(S);
    S.Render;
    CheckPointLightShadows(Self, S, 'Point light');

    { 6 views in the atlas }
    ShadowMap := (Scene.Node(TPointLightNode, 'Light') as TPointLightNode).
      FdDefaultShadowMap.Value as TGeneratedShadowMapNode;
    AssertEquals(6, ShadowMap.InternalTileCount);
    AssertTrue(TVector3.Equals(ShadowMap.InternalLightPosition, Vector3(0, 4, 0), 0.001));
    AssertTrue(ShadowMap.InternalTexelSize.X < 1 / 1024);
    CheckGLErrors('TestPointLight');
  finally FreeAndNil(S) end;
end;

procedure TTestCastleShadowMaps.TestPointLightOwnTexture;
var
  S: TShadowMapsTest;
  Scene: TCastleScene;
  ShadowMap: TGeneratedShadowMapNode;
  SavedAtlasSize: Cardinal;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  SavedAtlasSize := ShadowMapsAtlasSize;
  ShadowMapsAtlasSize := 0;
  try
    S := TShadowMapsTest.Create(Self);
    try
      if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) then
      begin
        AbortTest;
        Exit;
      end;
      Scene := S.AddScene('castle-data:/shadow_maps/point_light.x3dv');
      SetTopCamera(S);
      S.Render;
      CheckPointLightShadows(Self, S, 'Point light, own texture');

      { 6 views in a texture of 3 x 2 views }
      ShadowMap := (Scene.Node(TPointLightNode, 'Light') as TPointLightNode).
        FdDefaultShadowMap.Value as TGeneratedShadowMapNode;
      AssertEquals(6, ShadowMap.InternalTileCount);
      AssertSameValue(1 / (3 * ShadowMap.Size), ShadowMap.InternalTexelSize.X, 0.0001);
      AssertSameValue(1 / (2 * ShadowMap.Size), ShadowMap.InternalTexelSize.Y, 0.0001);
      CheckGLErrors('TestPointLightOwnTexture');
    finally FreeAndNil(S) end;
  finally ShadowMapsAtlasSize := SavedAtlasSize end;
end;

procedure TTestCastleShadowMaps.TestPointLightVariance;
var
  S: TShadowMapsTest;
  Scene: TCastleScene;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  { Variance shadow maps need float textures, not implemented on OpenGLES. }
  {$ifdef OpenGLES}
  AbortTest;
  Exit;
  {$endif}

  S := TShadowMapsTest.Create(Self);
  try
    if not (GLFeatures.TextureFloat and GLFeatures.Shaders) then
    begin
      AbortTest;
      Exit;
    end;
    Scene := S.AddScene('castle-data:/shadow_maps/point_light.x3dv');
    Scene.RenderOptions.ShadowSampling := ssVarianceShadowMaps;
    SetTopCamera(S);
    S.Render;
    CheckPointLightShadows(Self, S, 'Point light, variance shadow maps');
    CheckGLErrors('TestPointLightVariance');
  finally FreeAndNil(S) end;
end;

procedure TTestCastleShadowMaps.TestSpotLight;
var
  S: TShadowMapsTest;
  Sampling: TShadowSampling;
  LitValue: Single;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  for Sampling := Low(TShadowSampling) to High(TShadowSampling) do
  begin
    { Variance shadow maps need float textures, not implemented on OpenGLES. }
    {$ifdef OpenGLES}
    if Sampling = ssVarianceShadowMaps then
      Continue;
    {$endif}
    S := TShadowMapsTest.Create(Self);
    try
      if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) or
         ((Sampling = ssVarianceShadowMaps) and not GLFeatures.TextureFloat) then
      begin
        AbortTest;
        Exit;
      end;
      S.AddScene('castle-data:/shadow_maps/spot_light.x3dv').
        RenderOptions.ShadowSampling := Sampling;
      SetTopCamera(S);
      S.Render;
      { the box at (2, 4, 0) casts a shadow at (4, 0, 0) }
      LitValue := S.Luminance(Vector3(-4, 0, 0));
      AssertTrue(LitValue > 0.5);
      if S.Luminance(Vector3(4, 0, 0)) > LitValue * 0.3 then
        Fail(Format('Spot light, %s: no shadow (luminance %f, lit %f)', [
          ShadowSamplingNames[Sampling], S.Luminance(Vector3(4, 0, 0)), LitValue]));
      CheckGLErrors('TestSpotLight');
    finally FreeAndNil(S) end;
  end;
end;

procedure TTestCastleShadowMaps.TestCascades;
const
  { the floating boxes are at y = 2.5, the light goes +0.5 x per -1 y }
  BoxesZ: array [0..2] of Single = (5, -10, -30);
  Blends: array [0..2] of Single = (0, 0.1, 0.5);
var
  SavedBlend: Single;
  BlendIndex: Integer;
  S: TShadowMapsTest;
  Scene: TCastleScene;
  ShadowMap: TGeneratedShadowMapNode;
  I, Cascade, CascadeCount: Integer;
  ShadowValue, LitValue, Depth: Single;
  Cascades: set of 0..3;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  S := TShadowMapsTest.Create(Self);
  try
    if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) then
    begin
      AbortTest;
      Exit;
    end;
    Scene := S.AddScene('castle-data:/shadow_maps/cascades.x3dv');
    SavedBlend := ShadowMapsCascadeBlend;
    try
    { without blending, with the default blending, and with a lot of it }
    for BlendIndex := 0 to High(Blends) do
    begin
    ShadowMapsCascadeBlend := Blends[BlendIndex];
    S.Viewport.Camera.SetView(
      Vector3(0, 6, 20), Vector3(0, -0.3, -1), Vector3(0, 1, 0));
    S.Render;

    ShadowMap := (Scene.Node(TDirectionalLightNode, 'Sun') as TDirectionalLightNode).
      FdDefaultShadowMap.Value as TGeneratedShadowMapNode;
    AssertEquals(4, ShadowMap.InternalTileCount);
    { the cascades end at increasing distances }
    for I := 1 to 3 do
      AssertTrue(ShadowMap.InternalCascadeSplits.Data[I] >
        ShadowMap.InternalCascadeSplits.Data[I - 1]);

    Cascades := [];
    for I := 0 to High(BoxesZ) do
    begin
      ShadowValue := S.Luminance(Vector3(1.25, 0, BoxesZ[I]));
      LitValue := S.Luminance(Vector3(-2.5, 0, BoxesZ[I]));
      if ShadowValue > LitValue * 0.3 then
        Fail(Format('Cascades (blend %f): no shadow at z = %f (luminance %f, lit %f)', [
          Blends[BlendIndex], BoxesZ[I], ShadowValue, LitValue]));

      { which cascade shows this shadow }
      Depth := -(S.Viewport.Camera.Matrix * Vector4(1.25, 0, BoxesZ[I], 1)).Z;
      Cascade := 0;
      while (Cascade < 3) and (Depth >= ShadowMap.InternalCascadeSplits.Data[Cascade]) do
        Inc(Cascade);
      Include(Cascades, Cascade);
    end;
    { the shadows are in different cascades }
    CascadeCount := 0;
    for I := 0 to 3 do
      if I in Cascades then
        Inc(CascadeCount);
    AssertTrue(CascadeCount >= 2);

    { the cascades follow the camera }
    S.Viewport.Camera.Translation := Vector3(0, 6, 10);
    S.Render;
    AssertTrue(ShadowMap.InternalCascadeSplits.Data[3] > 0);
    ShadowValue := S.Luminance(Vector3(1.25, 0, -10));
    LitValue := S.Luminance(Vector3(-2.5, 0, -10));
    AssertTrue(ShadowValue < LitValue * 0.3);
    CheckGLErrors('TestCascades');
    end;
    finally ShadowMapsCascadeBlend := SavedBlend end;
  finally FreeAndNil(S) end;
end;

procedure TTestCastleShadowMaps.TestGlobalLightOtherScene;
var
  S: TShadowMapsTest;
  LightScene: TCastleScene;
  Light: TPointLightNode;
  ShadowMap: TGeneratedShadowMapNode;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  S := TShadowMapsTest.Create(Self);
  try
    if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) then
    begin
      AbortTest;
      Exit;
    end;
    { the light is in a scene without shapes, the shadows in another scene }
    LightScene := S.AddScene('castle-data:/shadow_maps/point_light_only.x3dv');
    LightScene.CastGlobalLights := true;
    S.AddScene('castle-data:/shadow_maps/geometry_only.x3dv');
    SetTopCamera(S);
    S.Render;
    CheckPointLightShadows(Self, S, 'Global point light in another scene');

    { without shadows, its shadow map is released }
    Light := LightScene.Node(TPointLightNode, 'Light') as TPointLightNode;
    ShadowMap := Light.FdDefaultShadowMap.Value as TGeneratedShadowMapNode;
    AssertTrue(TTextureResources.Get(ShadowMap) <> nil);
    Light.Shadows := false;
    S.Render;
    AssertTrue(TTextureResources.Get(ShadowMap) = nil);
    AssertTrue(S.Luminance(Vector3(7, 0, 0)) > 0.2);

    { and prepared again with shadows }
    Light.Shadows := true;
    S.Render;
    AssertTrue(TTextureResources.Get(ShadowMap) <> nil);
    CheckPointLightShadows(Self, S, 'Global point light in another scene, again');
    CheckGLErrors('TestGlobalLightOtherScene');
  finally FreeAndNil(S) end;
end;

procedure TTestCastleShadowMaps.TestHiddenCasters;
var
  S: TShadowMapsTest;
  LightScene, Casters: TCastleScene;
  Color, P: TVector4;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  S := TShadowMapsTest.Create(Self);
  try
    if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) then
    begin
      AbortTest;
      Exit;
    end;
    LightScene := S.AddScene('castle-data:/shadow_maps/point_light_only.x3dv');
    LightScene.CastGlobalLights := true;
    S.AddScene('castle-data:/shadow_maps/floor_only.x3dv');
    Casters := S.AddScene('castle-data:/shadow_maps/casters_only.x3dv');
    SetTopCamera(S);
    S.Render;
    CheckPointLightShadows(Self, S, 'Casters in another scene');

    { hidden casters don't cast shadows }
    Casters.Visible := false;
    S.Render;
    AssertTrue(S.Luminance(Vector3(7, 0, 0)) > S.Luminance(Vector3(5, 0, 5)) * 0.5);

    { unless CastShadowsWhenHidden: shadows, but not the casters themselves }
    Casters.CastShadowsWhenHidden := true;
    S.Render;
    CheckPointLightShadows(Self, S, 'Hidden casters with CastShadowsWhenHidden');
    { the top of a box shows the floor (white), not the red box }
    P := S.Viewport.Camera.ProjectionMatrix * S.Viewport.Camera.Matrix * Vector4(3, 2.5, 0, 1);
    Color := S.Image.Colors[
      Round((P.X / P.W * 0.5 + 0.5) * S.Image.Width),
      Round((P.Y / P.W * 0.5 + 0.5) * S.Image.Height), 0];
    AssertTrue(Format('Hidden caster not rendered (color %s)', [Color.ToString]),
      Color.Y > Color.X * 0.5);

    { not when it doesn't exist, or doesn't cast shadows }
    Casters.CastShadows := false;
    S.Render;
    AssertTrue(S.Luminance(Vector3(7, 0, 0)) > S.Luminance(Vector3(5, 0, 5)) * 0.5);
    Casters.CastShadows := true;
    Casters.Exists := false;
    S.Render;
    AssertTrue(S.Luminance(Vector3(7, 0, 0)) > S.Luminance(Vector3(5, 0, 5)) * 0.5);
    CheckGLErrors('TestHiddenCasters');
  finally FreeAndNil(S) end;
end;

procedure TTestCastleShadowMaps.TestSizeByScreen;
var
  S: TShadowMapsTest;
  Scene: TCastleScene;
  ShadowMap: TGeneratedShadowMapNode;
  Res: TGeneratedShadowMapResource;
  FullSize, FarSize: Cardinal;
  SavedSizeByScreen: Boolean;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  SavedSizeByScreen := ShadowMapsSizeByScreen;
  ShadowMapsSizeByScreen := true;
  try
    S := TShadowMapsTest.Create(Self);
    try
      if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) then
      begin
        AbortTest;
        Exit;
      end;
      Scene := S.AddScene('castle-data:/shadow_maps/point_light.x3dv');
      ShadowMap := (Scene.Node(TPointLightNode, 'Light') as TPointLightNode).
        FdDefaultShadowMap.Value as TGeneratedShadowMapNode;
      ShadowMap.Size := 1024;

      { the camera within the light's range: the full size }
      SetTopCamera(S);
      S.Render;
      Res := TTextureResources.Get(ShadowMap) as TGeneratedShadowMapResource;
      AssertTrue(Res <> nil);
      FullSize := Res.CurrentTileSize;
      AssertEquals(1024, FullSize);
      CheckPointLightShadows(Self, S, 'Size by screen, near');

      { far away: smaller views }
      S.Viewport.Camera.SetView(
        Vector3(0, 300, 0.01), Vector3(0, -1, 0), Vector3(0, 0, -1));
      S.Render;
      FarSize := Res.CurrentTileSize;
      AssertTrue(Format('Far light has smaller shadow map (%d)', [FarSize]),
        FarSize < FullSize);
      AssertTrue(FarSize >= ShadowMapsMinSizeByScreen);
      AssertEquals(6, ShadowMap.InternalTileCount);
      AssertSameValue(FarSize * ShadowMap.InternalTexelSize.X,
        ShadowMap.InternalTiles[0].Rect.Z - ShadowMap.InternalTiles[0].Rect.X, 0.000001);

      { a bit closer: the same size (hysteresis) }
      S.Viewport.Camera.SetView(
        Vector3(0, 290, 0.01), Vector3(0, -1, 0), Vector3(0, 0, -1));
      S.Render;
      AssertEquals(FarSize, Res.CurrentTileSize);

      { back near: the full size again, with shadows }
      SetTopCamera(S);
      S.Render;
      AssertEquals(FullSize, Res.CurrentTileSize);
      CheckPointLightShadows(Self, S, 'Size by screen, near again');

      { without ShadowMapsSizeByScreen: always the full size }
      ShadowMapsSizeByScreen := false;
      S.Viewport.Camera.SetView(
        Vector3(0, 300, 0.01), Vector3(0, -1, 0), Vector3(0, 0, -1));
      S.Render;
      AssertEquals(FullSize, Res.CurrentTileSize);
      CheckGLErrors('TestSizeByScreen');
    finally FreeAndNil(S) end;
  finally ShadowMapsSizeByScreen := SavedSizeByScreen end;
end;

procedure TTestCastleShadowMaps.TestCascadesTwoViewports;
var
  S: TShadowMapsTest;
  Second: TCastleViewport;
  SecondCamera: TCastleCamera;
  ShadowValue, LitValue: Single;
begin
  if not CanCreateWindowForTest then
  begin
    AbortTest;
    Exit;
  end;

  S := TShadowMapsTest.Create(Self);
  try
    if not (GLFeatures.TextureDepth and GLFeatures.TextureDepthCompare) then
    begin
      AbortTest;
      Exit;
    end;
    { cascades only up to 15 from the camera }
    S.AddScene('castle-data:/shadow_maps/cascades_short.x3dv');
    S.Viewport.FullSize := false;
    S.Viewport.Width := 150;
    S.Viewport.Height := 300;
    S.Viewport.Camera.SetView(
      Vector3(0, 6, 12), Vector3(0, -0.6, -1), Vector3(0, 1, 0));

    { the second viewport shows the same world, from its own camera,
      near the far box (z = -30), out of the cascades of the first camera }
    Second := TCastleViewport.Create(S.Window);
    Second.Left := 150;
    Second.Width := 150;
    Second.Height := 300;
    Second.BackgroundColor := Black;
    Second.Items := S.Viewport.Items;
    SecondCamera := TCastleCamera.Create(S.Window);
    Second.Items.Add(SecondCamera);
    Second.Camera := SecondCamera;
    SecondCamera.SetView(
      Vector3(0, 6, -20), Vector3(0, -0.6, -1), Vector3(0, 1, 0));
    S.Window.Controls.InsertFront(Second);
    S.Render;

    { both show the shadows around their cameras }
    ShadowValue := LuminanceIn(S, S.Viewport, Vector3(1.25, 0, 5));
    LitValue := LuminanceIn(S, S.Viewport, Vector3(-2.5, 0, 5));
    AssertTrue(LitValue > 0.2);
    if ShadowValue > LitValue * 0.3 then
      Fail(Format('First viewport: no shadow (luminance %f, lit %f)', [ShadowValue, LitValue]));
    ShadowValue := LuminanceIn(S, Second, Vector3(1.25, 0, -30));
    LitValue := LuminanceIn(S, Second, Vector3(-2.5, 0, -30));
    AssertTrue(LitValue > 0.2);
    if ShadowValue > LitValue * 0.3 then
      Fail(Format('Second viewport: no shadow (luminance %f, lit %f)', [ShadowValue, LitValue]));
    CheckGLErrors('TestCascadesTwoViewports');
  finally FreeAndNil(S) end;
end;

initialization
  RegisterTest(TTestCastleShadowMaps);
end.
