{
  Copyright 2026-2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated unit tests for Phase 303 Procedural Foliage Ecosystems, Biome Masks
  & Multi-LOD Proxy Studio (@link(TCastleFoliageBiomeVolume),
  @link(TCastleFoliageExclusionVolume), @link(TCastleLodProxyBehavior), and
  @link(TFoliageBiomeHelper)). }
unit TestToolFoliageBiome;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolFoliageBiome = class(TCastleTestCase)
  published
    procedure TestSeededBiomeScatterExclusionMaskSlopeAltitudeAndPoissonSpacing;
    procedure TestLodProxyHysteresisNoThrashingAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleComponentSerialize, CastleTransform,
  CastleUiControls, CastleViewport, CastleScene,
  EditorRegisterAllComponents,
  CastleFoliageBiome, ToolFoliageBiome;

procedure TTestToolFoliageBiome.TestSeededBiomeScatterExclusionMaskSlopeAltitudeAndPoissonSpacing;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  Vp: TCastleViewport;
  MeadowFloor, HighSnowPeak: TCastleBox;
  Biome: TCastleFoliageBiomeVolume;
  RoadExcl: TCastleFoliageExclusionVolume;
  Spec: TFoliageSpeciesEntry;
  Spawned1, Spawned2, I, J: Integer;
  PosW, PosJ: TVector3;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'ViewportMain';
    RootUi.InsertFront(Vp);

    { 1. Flat valley floor at Y = 0 (X in [-25..25], Z in [-25..25]) }
    MeadowFloor := TCastleBox.Create(DesignOwner);
    MeadowFloor.Name := 'MeadowFloor';
    MeadowFloor.Size := Vector3(50.0, 2.0, 50.0);
    MeadowFloor.Translation := Vector3(0.0, -1.0, 0.0);
    Vp.Items.Add(MeadowFloor);

    { 2. High snow pillar at center-west (-12, 0..18, 0) whose top sits at Y = 18.0
         (exceeding Species MaxAltitude = 10.0, so 0 trees may spawn at Y > 10!) }
    HighSnowPeak := TCastleBox.Create(DesignOwner);
    HighSnowPeak.Name := 'HighSnowPeak';
    HighSnowPeak.Size := Vector3(10.0, 18.0, 10.0);
    HighSnowPeak.Translation := Vector3(-12.0, 9.0, 0.0);
    Vp.Items.Add(HighSnowPeak);

    { 3. Road exclusion corridor centered at X = +8 (width 6m + 0.5m falloff -> [4.5 .. 11.5]) }
    RoadExcl := TFoliageBiomeHelper.CreateExclusionVolumeInDesign(
      RootUi, DesignOwner, Vector3(8.0, 0.0, 0.0), Vector3(6.0, 10.0, 50.0));
    RoadExcl.FalloffMargin := 0.5;

    { 4. Biome volume with single Pine species: MinRadiusSpacing = 2.5m, MaxAltitude = 10.0m }
    Biome := TFoliageBiomeHelper.CreateBiomeVolumeInDesign(
      RootUi, DesignOwner, 0, Vector3(0.0, 10.0, 0.0));
    Biome.VolumeSize := Vector3(44.0, 30.0, 44.0);
    Biome.ClearSpecies;
    Spec := Default(TFoliageSpeciesEntry);
    Spec.SpeciesId := 'TestPine';
    Spec.Archetype := faPineTree;
    Spec.Weight := 1.0;
    Spec.MinScale := 0.9;
    Spec.MaxScale := 1.2;
    Spec.MinRadiusSpacing := 2.5;
    Spec.AlignToSlopeFactor := 0.15;
    Spec.MinAltitude := -2.0;
    Spec.MaxAltitude := 10.0;
    Spec.MaxSlopeDeg := 30.0;
    Biome.AddOrUpdateSpecies(Spec);
    Biome.Seed := 777;
    Biome.TargetInstanceCount := 24;

    Spawned1 := TFoliageBiomeHelper.PopulateBiomeWithSceneExclusions(RootUi, DesignOwner, Biome);
    AssertTrue(Spawned1 >= 10);
    AssertEquals(Spawned1, Biome.GeneratedInstanceCount);

    { Verify EVERY spawned tree respects:
      - MaxAltitude <= 10.0 (rejecting HighSnowPeak Y=18),
      - RoadExcl exclusion volume,
      - Pairwise Poisson spacing >= 2.5m }
    for I := 0 to Biome.Count - 1 do
      if Biome.Items[I].Tag = FoliageGeneratedInstanceTag then
      begin
        PosW := Biome.Translation + Biome.Items[I].Translation;
        AssertTrue(PosW.Y <= 10.01);
        AssertFalse(RoadExcl.ContainsWorldPoint(PosW));
        for J := I + 1 to Biome.Count - 1 do
          if Biome.Items[J].Tag = FoliageGeneratedInstanceTag then
          begin
            PosJ := Biome.Translation + Biome.Items[J].Translation;
            AssertTrue(PointsDistance(PosW, PosJ) >= 2.49);
          end;
      end;

    { Re-populating with identical seed 777 yields identical count }
    Spawned2 := TFoliageBiomeHelper.PopulateBiomeWithSceneExclusions(RootUi, DesignOwner, Biome);
    AssertEquals(Spawned1, Spawned2);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolFoliageBiome.TestLodProxyHysteresisNoThrashingAndJsonRoundtrip;
var
  DesignOwner, LoadedOwner: TComponent;
  World, LoadedWorld, TreeActor: TCastleTransform;
  Biome: TCastleFoliageBiomeVolume;
  Lod: TCastleLodProxyBehavior;
  JsonStr, Report: String;
  LoadedSum: TFoliageBiomeSummary;
begin
  DesignOwner := TComponent.Create(nil);
  try
    World := TCastleTransform.Create(DesignOwner);
    World.Name := 'WorldRoot';

    TreeActor := TCastleTransform.Create(DesignOwner);
    TreeActor.Name := 'HeroPine';
    World.Add(TreeActor);

    Lod := TFoliageBiomeHelper.AttachLodProxyToTransform(
      TreeActor, DesignOwner,
      'castle-data:/pine_lod0.gltf',
      'castle-data:/pine_lod1.gltf',
      'castle-data:/pine_lod2.gltf');
    Lod.MediumDistance := 25.0;
    Lod.LowDistance := 60.0;
    Lod.CullDistance := 120.0;
    Lod.HysteresisMargin := 3.0;

    { 1. Hysteresis band checks around 25.0m +/- 3.0m }
    AssertEquals(Ord(fllHigh), Ord(Lod.EvaluateForDistance(10.0)));
    AssertEquals(Ord(fllHigh), Ord(Lod.EvaluateForDistance(27.5))); // inside +3m hysteresis -> stays High!
    AssertEquals(Ord(fllMedium), Ord(Lod.EvaluateForDistance(28.5))); // crosses 28.0m -> Medium!
    AssertEquals('castle-data:/pine_lod1.gltf', Lod.ActiveResolvedUrl);
    AssertEquals(Ord(fllMedium), Ord(Lod.EvaluateForDistance(22.5))); // inside -3m hysteresis -> stays Medium!
    AssertEquals(Ord(fllHigh), Ord(Lod.EvaluateForDistance(21.5))); // drops below 22.0m -> back to High!

    { 2. Multi-band jump to Culled and back to Low }
    AssertEquals(Ord(fllCulled), Ord(Lod.EvaluateForDistance(150.0)));
    AssertEquals('', Lod.ActiveResolvedUrl);
    AssertEquals(Ord(fllLow), Ord(Lod.EvaluateForDistance(110.0)));
    AssertEquals('castle-data:/pine_lod2.gltf', Lod.ActiveResolvedUrl);

    { 3. Headless biome scatter + JSON roundtrip without transient X3D bloat }
    Biome := TFoliageBiomeHelper.CreateBiomeVolumeInDesign(World, DesignOwner, 1, TVector3.Zero);
    Biome.TargetInstanceCount := 8;
    AssertEquals(8, TFoliageBiomeHelper.PopulateBiomeWithSceneExclusions(World, DesignOwner, Biome));

    Report := TFoliageBiomeHelper.BuildMarkdownReport(World);
    AssertTrue(Pos('Procedural Foliage Ecosystems & LOD Proxy Report', Report) > 0);

    JsonStr := ComponentToString(World);
    AssertEquals(0, Pos('TConeNode', JsonStr));
    AssertEquals(0, Pos('TSphereNode', JsonStr));

    LoadedOwner := TComponent.Create(nil);
    try
      LoadedWorld := StringToComponent(JsonStr, LoadedOwner) as TCastleTransform;
      try
        LoadedSum := TFoliageBiomeHelper.ScanFoliageEcosystem(LoadedWorld);
        AssertEquals(1, Length(LoadedSum.Biomes));
        AssertEquals(8, LoadedSum.TotalGeneratedInstances);
        AssertEquals(1, Length(LoadedSum.LodProxies));
        AssertEquals('castle-data:/pine_lod1.gltf', LoadedSum.LodProxies[0].MediumUrl);
      finally
        FreeAndNil(LoadedWorld);
      end;
    finally
      FreeAndNil(LoadedOwner);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolFoliageBiome);
end.
