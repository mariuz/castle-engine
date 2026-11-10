{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automatic tests for CastleTerrain sculpting, non-destructive edit layers,
  raycasting, and 4-channel RGBA splatmap painting. }
unit TestCastleTerrain;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestCastleTerrain = class(TCastleTestCase)
  published
    procedure TestSculptRaiseLowerAndAutoLevelExpansion;
    procedure TestNonDestructiveEditLayerOverNoiseAndFlattenSmooth;
    procedure TestSplatmapProceduralGenerationAndBrushNormalize;
    procedure TestSaveAndReloadHeightAndSplatmap;
  end;

implementation

uses
  CastleVectors, CastleImages, CastleFilesUtils, CastleUriUtils,
  CastleViewport, CastleTerrain;

procedure TTestCastleTerrain.TestSculptRaiseLowerAndAutoLevelExpansion;
var
  OwnerComp: TComponent;
  Viewport: TCastleViewport;
  Terrain: TCastleTerrain;
  ImgLayer: TCastleTerrainImage;
  HitPt: TVector3;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Viewport := TCastleViewport.Create(OwnerComp);
    Terrain := TCastleTerrain.Create(OwnerComp);
    Terrain.Size := Vector2(100, 100);
    Terrain.Subdivisions := Vector2(32, 32);
    Viewport.Items.Add(Terrain);

    ImgLayer := TCastleTerrainImage.Create(OwnerComp);
    ImgLayer.MinLevel := -0.5;
    ImgLayer.MaxLevel := 0.5;
    ImgLayer.CreateBlankImage(65, 65, 0.0);
    Terrain.Data := ImgLayer;

    AssertSameValue(0.0, Terrain.SampleHeightAtLocalXZ(0, 0), 0.01);
    AssertSameValue(0.0, Terrain.SampleHeightAtLocalXZ(-48, -48), 0.01);

    { Raise center by +6.0 (exceeds initial MaxLevel=0.5, testing auto-expansion) }
    Terrain.SculptHeightAtWorldPoint(Vector3(0, 0, 0), 20.0, tsbmRaise, 6.0, 0.0, OwnerComp, 65);
    AssertTrue(ImgLayer.MaxLevel >= 5.99);
    AssertSameValue(6.0, Terrain.SampleHeightAtLocalXZ(0, 0), 0.05);
    { Untouched corner must still be 0.0 after MinLevel/MaxLevel renormalization }
    AssertSameValue(0.0, Terrain.SampleHeightAtLocalXZ(-48, -48), 0.02);

    { RayCastWorld straight down onto the raised peak }
    AssertTrue(Terrain.RayCastWorld(Vector3(0, 25, 0), Vector3(0, -1, 0), HitPt));
    AssertSameValue(6.0, HitPt.Y, 0.15);

    { Lower corner (-25, 25) by -4.0 (exceeds initial MinLevel=-0.5) }
    Terrain.SculptHeightAtWorldPoint(Vector3(-25, 0, 25), 15.0, tsbmLower, 4.0, 0.0, OwnerComp, 65);
    AssertTrue(ImgLayer.MinLevel <= -3.9);
    AssertSameValue(-4.0, Terrain.SampleHeightAtLocalXZ(-25, 25), 0.15);
    { Previously raised center peak must remain 6.0! }
    AssertSameValue(6.0, Terrain.SampleHeightAtLocalXZ(0, 0), 0.05);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestCastleTerrain.TestNonDestructiveEditLayerOverNoiseAndFlattenSmooth;
var
  OwnerComp: TComponent;
  Terrain: TCastleTerrain;
  Noise: TCastleTerrainNoise;
  EditImg: TCastleTerrainImage;
  Combine: TCastleTerrainCombine;
  OrigCenterH, OrigCornerH, EdgeBeforeSmooth, EdgeAfterSmooth: Single;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Terrain := TCastleTerrain.Create(OwnerComp);
    Terrain.Size := Vector2(100, 100);
    Terrain.Subdivisions := Vector2(32, 32);

    Noise := TCastleTerrainNoise.Create(OwnerComp);
    Noise.Name := 'BaseNoise';
    Noise.Amplitude := 8.0;
    Noise.Seed := 7;
    Terrain.Data := Noise;

    OrigCenterH := Terrain.SampleHeightAtLocalXZ(0, 0);
    OrigCornerH := Terrain.SampleHeightAtLocalXZ(46, 46);
    AssertTrue(OrigCenterH > 0.1);

    { Sculpting a noise-driven terrain must wrap BaseNoise non-destructively in opAdd }
    EditImg := Terrain.SculptHeightAtWorldPoint(
      Vector3(0, 0, 0), 22.0, tsbmFlatten, 1.0, 2.0, OwnerComp, 65);
    AssertTrue(EditImg <> nil);
    AssertTrue(Terrain.Data is TCastleTerrainCombine);
    Combine := TCastleTerrainCombine(Terrain.Data);
    AssertTrue(Combine.Operation = opAdd);
    AssertTrue(Combine.Data1 = Noise);
    AssertTrue(Combine.Data2 = EditImg);

    { Center must now be flattened to Y = 2.0 despite procedural noise beneath it }
    AssertSameValue(2.0, Terrain.SampleHeightAtLocalXZ(0, 0), 0.05);
    { Far corner outside brush radius must retain exact procedural noise height }
    AssertSameValue(OrigCornerH, Terrain.SampleHeightAtLocalXZ(46, 46), 0.02);

    { Smooth over an area and verify no NaN and valid composite height }
    EdgeBeforeSmooth := Terrain.SampleHeightAtLocalXZ(18, 0);
    Terrain.SculptHeightAtWorldPoint(
      Vector3(18, 0, 0), 14.0, tsbmSmooth, 1.0, 0.0, OwnerComp, 65);
    EdgeAfterSmooth := Terrain.SampleHeightAtLocalXZ(18, 0);
    AssertTrue(Abs(EdgeAfterSmooth - EdgeBeforeSmooth) < 10.0);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestCastleTerrain.TestSplatmapProceduralGenerationAndBrushNormalize;
var
  OwnerComp: TComponent;
  Terrain: TCastleTerrain;
  Noise: TCastleTerrainNoise;
  Splat: TRGBAlphaImage;
  X, Y, SumRGBA: Integer;
  Px: TVector4Byte;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Terrain := TCastleTerrain.Create(OwnerComp);
    Terrain.Size := Vector2(100, 100);
    Noise := TCastleTerrainNoise.Create(OwnerComp);
    Noise.Amplitude := 12.0;
    Terrain.Data := Noise;

    AssertSameValue(0.0, Terrain.SplatmapInfluence, 0.001);

    Terrain.GenerateSplatmapFromProceduralLayers(33, 33);
    AssertSameValue(1.0, Terrain.SplatmapInfluence, 0.001);
    Splat := Terrain.SplatmapImage;
    AssertTrue(Splat <> nil);
    AssertEquals(33, Integer(Splat.Width));
    AssertEquals(33, Integer(Splat.Height));

    { Every pixel must be normalized to R+G+B+A = 255 }
    for Y := 0 to Integer(Splat.Height) - 1 do
      for X := 0 to Integer(Splat.Width) - 1 do
      begin
        Px := Splat.PixelPtr(X, Y)^;
        SumRGBA := Integer(Px.X) + Integer(Px.Y) + Integer(Px.Z) + Integer(Px.W);
        AssertEquals(255, SumRGBA);
      end;

    { Paint Layer 3 (Blue channel) at world origin }
    Terrain.PaintSplatmapAtWorldPoint(Vector3(0, 0, 0), 25.0, 3, 1.0, 33);
    Px := Splat.PixelPtr(16, 16)^;
    AssertEquals(0, Integer(Px.X));
    AssertEquals(0, Integer(Px.Y));
    AssertEquals(255, Integer(Px.Z));
    AssertEquals(0, Integer(Px.W));

    { Re-verify partition-of-unity across entire image after brush falloff }
    for Y := 0 to Integer(Splat.Height) - 1 do
      for X := 0 to Integer(Splat.Width) - 1 do
      begin
        Px := Splat.PixelPtr(X, Y)^;
        SumRGBA := Integer(Px.X) + Integer(Px.Y) + Integer(Px.Z) + Integer(Px.W);
        AssertEquals(255, SumRGBA);
      end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestCastleTerrain.TestSaveAndReloadHeightAndSplatmap;
var
  OwnerComp: TComponent;
  TerrainA, TerrainB: TCastleTerrain;
  ImgA, ImgB: TCastleTerrainImage;
  TempDir, HeightFile, SplatFile, HeightUrl, SplatUrl: String;
  CenterPx: TVector4Byte;
begin
  TempDir := IncludeTrailingPathDelimiter(GetTempDir(false)) + 'cge_terrain_test_' + IntToStr(Random(1000000));
  ForceDirectories(TempDir);
  HeightFile := IncludeTrailingPathDelimiter(TempDir) + 'sculpted_height.png';
  SplatFile := IncludeTrailingPathDelimiter(TempDir) + 'painted_splat.png';
  HeightUrl := FilenameToUriSafe(HeightFile);
  SplatUrl := FilenameToUriSafe(SplatFile);

  OwnerComp := TComponent.Create(nil);
  try
    TerrainA := TCastleTerrain.Create(OwnerComp);
    TerrainA.Size := Vector2(80, 80);
    ImgA := TerrainA.SculptHeightAtWorldPoint(
      Vector3(0, 0, 0), 20.0, tsbmRaise, 4.0, 0.0, OwnerComp, 33);
    ImgA.SaveImage(HeightUrl);

    TerrainA.CreateBlankSplatmap(33, 33, 1);
    TerrainA.PaintSplatmapAtWorldPoint(Vector3(0, 0, 0), 20.0, 4, 1.0, 33);
    TerrainA.SaveSplatmap(SplatUrl);

    TerrainB := TCastleTerrain.Create(OwnerComp);
    TerrainB.Size := Vector2(80, 80);
    ImgB := TCastleTerrainImage.Create(OwnerComp);
    ImgB.MinLevel := ImgA.MinLevel;
    ImgB.MaxLevel := ImgA.MaxLevel;
    ImgB.Url := HeightUrl;
    TerrainB.Data := ImgB;
    TerrainB.SplatmapUrl := SplatUrl;
    TerrainB.SplatmapInfluence := 1.0;

    AssertSameValue(4.0, TerrainB.SampleHeightAtLocalXZ(0, 0), 0.1);
    AssertSameValue(0.0, TerrainB.SampleHeightAtLocalXZ(-38, -38), 0.1);

    AssertTrue(TerrainB.SplatmapImage <> nil);
    CenterPx := TerrainB.SplatmapImage.PixelPtr(16, 16)^;
    AssertEquals(255, Integer(CenterPx.W));
  finally
    FreeAndNil(OwnerComp);
    if FileExists(HeightFile) then DeleteFile(HeightFile);
    if FileExists(SplatFile) then DeleteFile(SplatFile);
    RemoveDir(TempDir);
  end;
end;

initialization
  RegisterTest(TTestCastleTerrain);
end.
