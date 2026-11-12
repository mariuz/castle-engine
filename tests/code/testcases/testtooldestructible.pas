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

{ Automated tests for Phase 305 Destructible Voronoi Fracture, Radial Blast
  Impulse & Debris Lifecycle Studio (@link(CastleDestructible),
  @link(ToolDestructible)). }
unit TestToolDestructible;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  CastleTester, CastleVectors, CastleUtils, CastleTransform, CastleViewport,
  CastleComponentSerialize, CastleDestructible, ToolDestructible;

type
  TTestToolDestructible = class(TCastleTestCase)
  published
    procedure TestVoronoiVolumePartitionDamageBlastBounceAndExpiration;
    procedure TestRadialBlastAttenuationResetIntactAndJsonRoundtrip;
  end;

implementation

procedure TTestToolDestructible.TestVoronoiVolumePartitionDamageBlastBounceAndExpiration;
var
  Cells: TVoronoiShardCellArray;
  TotalVol, MeanSpreadBefore, MeanSpreadAfter: Single;
  I: Integer;
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Dest: TCastleDestructibleBehavior;
  BlastOrigin, PropCenter: TVector3;
begin
  { 1. Zero-gap 3D convex Voronoi polyhedra partition the exact prop box volume (2 * 3 * 1.5 = 9.0 m^3) }
  Cells := ComputeVoronoiFractureCells(
    TVector3.Zero, Vector3(2.0, 3.0, 1.5), 14, 2026, 0.0);
  AssertEquals(14, Length(Cells));
  TotalVol := 0.0;
  for I := 0 to High(Cells) do
  begin
    AssertTrue(Cells[I].Volume > 0.01);
    AssertTrue(Length(Cells[I].FacesLocal) >= 4);
    TotalVol := TotalVol + Cells[I].Volume;
  end;
  AssertSameValue(9.0, TotalVol, 1e-2);

  { 2. Damage threshold -> fracture -> radial spread -> ground bounce -> lifetime expiration }
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    Dest := TDestructibleHelper.CreateDestructiblePropInDesign(
      Vp, DesignOwner, dmpStoneMasonry, Vector3(0.0, 0.0, 0.0));
    AssertTrue(Dest <> nil);
    AssertFalse(Dest.IsFractured);
    AssertSameValue(150.0, Dest.CurrentHealth, 1e-3);
    Dest.DebrisLifetimeSec := 1.20;
    Dest.BlastImpulse := 6.0;
    Dest.GroundFloorY := 0.0;

    BlastOrigin := Vector3(0.0, 0.5, 0.6);

    { Sub-lethal hit reduces health without fracturing }
    AssertFalse(Dest.ApplyDamage(60.0, BlastOrigin));
    AssertFalse(Dest.IsFractured);
    AssertSameValue(90.0, Dest.CurrentHealth, 1e-3);
    AssertTrue(Dest.Parent.Visible);

    { Lethal hit shatters prop into 14 transient Voronoi shards and hides intact hull }
    AssertTrue(Dest.ApplyDamage(100.0, BlastOrigin));
    AssertTrue(Dest.IsFractured);
    AssertEquals(14, Dest.ActiveShardCount);
    AssertFalse(Dest.Parent.Visible);

    PropCenter := Dest.Parent.Translation;
    MeanSpreadBefore := 0.0;
    for I := 0 to Dest.ActiveShardCount - 1 do
      MeanSpreadBefore := MeanSpreadBefore +
        PointsDistance(Dest.GetShardTransform(I).Translation, PropCenter);
    MeanSpreadBefore := MeanSpreadBefore / Dest.ActiveShardCount;

    { Step 0.35s -> shards fly radially outward and stay >= GroundFloorY }
    AssertEquals(14, Dest.StepDebrisSimulation(0.20));
    AssertEquals(14, Dest.StepDebrisSimulation(0.15));

    MeanSpreadAfter := 0.0;
    for I := 0 to Dest.ActiveShardCount - 1 do
    begin
      MeanSpreadAfter := MeanSpreadAfter +
        PointsDistance(Dest.GetShardTransform(I).Translation, PropCenter);
      AssertTrue(Dest.GetShardTransform(I).Translation.Y >= 0.0);
    end;
    MeanSpreadAfter := MeanSpreadAfter / Dest.ActiveShardCount;
    AssertTrue(MeanSpreadAfter > MeanSpreadBefore + 0.40);

    { Advance past DebrisLifetimeSec (1.20s) -> all transient shards expire & free cleanly }
    for I := 1 to 6 do
      Dest.StepDebrisSimulation(0.20);
    AssertEquals(0, Dest.ActiveShardCount);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolDestructible.TestRadialBlastAttenuationResetIntactAndJsonRoundtrip;
var
  DesignOwner, LoadedOwner: TComponent;
  Vp: TCastleViewport;
  NearCrate, FarCrystal: TCastleDestructibleBehavior;
  ShatteredCount: Integer;
  SerializedJson, MdReport: String;
  LoadedRoot: TComponent;
  Sum: TDestructibleSummary;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    NearCrate := TDestructibleHelper.CreateDestructiblePropInDesign(
      Vp, DesignOwner, dmpWoodenCrate, Vector3(1.0, 0.0, 0.0));
    FarCrystal := TDestructibleHelper.CreateDestructiblePropInDesign(
      Vp, DesignOwner, dmpCrystalGlass, Vector3(25.0, 0.0, 0.0));

    { Radial blast at origin (radius 6m, damage 120) shatters NearCrate while FarCrystal stays intact }
    ShatteredCount := TDestructibleHelper.TriggerRadialBlastInHierarchy(
      Vp, Vector3(0.0, 0.5, 0.0), 6.0, 120.0);
    AssertEquals(1, ShatteredCount);
    AssertTrue(NearCrate.IsFractured);
    AssertTrue(NearCrate.ActiveShardCount > 0);
    AssertFalse(FarCrystal.IsFractured);

    { ComponentToString while NearCrate is fractured must NOT bake csTransient debris shards }
    SerializedJson := ComponentToString(Vp);
    AssertEquals(0, Pos('_VoronoiDebris', SerializedJson));

    { ResetAllDestructiblesInHierarchy restores intact hull, health & clears debris }
    TDestructibleHelper.ResetAllDestructiblesInHierarchy(Vp);
    AssertFalse(NearCrate.IsFractured);
    AssertEquals(0, NearCrate.ActiveShardCount);
    AssertTrue(NearCrate.Parent.Visible);
    AssertSameValue(NearCrate.MaxHealth, NearCrate.CurrentHealth, 1e-3);

    MdReport := TDestructibleHelper.BuildMarkdownReport(Vp);
    AssertTrue(Pos('Wooden Crate', MdReport) > 0);
    AssertTrue(Pos('Crystal Glass', MdReport) > 0);

    LoadedOwner := TComponent.Create(nil);
    try
      LoadedRoot := StringToComponent(SerializedJson, LoadedOwner);
      Sum := TDestructibleHelper.ScanDestructibles(LoadedRoot);
      AssertEquals(2, Length(Sum.Props));
      AssertEquals(0, Sum.ActiveDebrisShardCount);
    finally
      FreeAndNil(LoadedOwner);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolDestructible);
end.
