{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless helper for the World Partition Hierarchical LOD (HLOD) Spatial
  Cluster Baker & Draw-Call Merger Studio (Phase 333). }
unit ToolHlodStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils,
  CastleVectors, CastleColors, CastleViewport, CastleTransform, CastleScene,
  CastleHlodBaker;

type
  THlodStudioSummary = record
    ManagerCount: Integer;
    TotalCells: Integer;
    TotalClusteredProps: Integer;
    ActiveHlodCells: Integer;
    BaselineDrawCalls: Integer;
    EffectiveDrawCalls: Integer;
    BaselineTriangles: Integer;
    EffectiveTriangles: Integer;
    DrawCallSavingsPercent: Single;
    WarningsCount: Integer;
  end;

  THlodStudioHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstManager(const ARoot: TComponent): TCastleHlodClusterManager; static;

    { Spawns a 4-quadrant city district (16 static building/tower/crate props
      across 4 spatial 24m x 24m cells + 1 HlodIgnore_HeroBeacon) and bakes
      all 4 HLOD cluster cells. }
    class function SpawnCityDistrictHlodDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out AManager: TCastleHlodClusterManager): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): THlodStudioSummary; static;

    class function BuildMarkdownReport(const ARoot: TComponent): String; static;
  end;

implementation

function MakeUniqueName(const AOwner: TComponent; const ABase: String): String;
var
  Idx: Integer;
begin
  Result := ABase;
  if (AOwner = nil) or (AOwner.FindComponent(Result) = nil) then
    Exit;
  Idx := 1;
  repeat
    Result := ABase + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function THlodStudioHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function THlodStudioHelper.FindFirstManager(
  const ARoot: TComponent): TCastleHlodClusterManager;

  function ScanTransform(const T: TCastleTransform): TCastleHlodClusterManager;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then
      Exit;
    if T is TCastleHlodClusterManager then
      Exit(TCastleHlodClusterManager(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanTransform(T[I]);
      if Result <> nil then
        Exit;
    end;
  end;

var
  RootT: TCastleTransform;
begin
  RootT := ResolveRootTransform(ARoot);
  Result := ScanTransform(RootT);
end;

class function THlodStudioHelper.SpawnCityDistrictHlodDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out AManager: TCastleHlodClusterManager): Boolean;
const
  QuadCentersX: array[0..3] of Single = (-28.0, 10.0, -28.0, 10.0);
  QuadCentersZ: array[0..3] of Single = (-28.0, -28.0, 10.0, 10.0);
  SubOffsetsX: array[0..3] of Single = (3.0, 14.0, 4.0, 15.0);
  SubOffsetsZ: array[0..3] of Single = (3.0, 4.0, 14.0, 15.0);
  QuadColors: array[0..3] of TVector3 = (
    (X: 0.78; Y: 0.56; Z: 0.42),
    (X: 0.48; Y: 0.66; Z: 0.78),
    (X: 0.62; Y: 0.74; Z: 0.48),
    (X: 0.74; Y: 0.64; Z: 0.46)
  );
var
  RootT, DistrictGroup: TCastleTransform;
  Q, P: Integer;
  Box: TCastleBox;
  Cyl: TCastleCylinder;
  Beacon: TCastleSphere;
  H: Single;
begin
  AManager := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  DistrictGroup := TCastleTransform.Create(ADesignOwner);
  DistrictGroup.Name := MakeUniqueName(ADesignOwner, 'HlodCityDistrictRoot');
  RootT.Add(DistrictGroup);

  for Q := 0 to 3 do
  begin
    for P := 0 to 3 do
    begin
      H := 3.5 + 1.6 * P + 0.6 * Q;
      if P = 3 then
      begin
        { Watchtower / silo cylinder (128 tris baseline) }
        Cyl := TCastleCylinder.Create(ADesignOwner);
        Cyl.Name := MakeUniqueName(ADesignOwner, Format('DistrictTower_Q%d_P%d', [Q + 1, P + 1]));
        Cyl.Radius := 1.8;
        Cyl.Height := H + 2.0;
        Cyl.Translation := Vector3(QuadCentersX[Q] + SubOffsetsX[P], 0.5 * (H + 2.0), QuadCentersZ[Q] + SubOffsetsZ[P]);
        Cyl.Color := Vector4(QuadColors[Q].X * 0.92, QuadColors[Q].Y * 0.92, QuadColors[Q].Z * 0.92, 1.0);
        DistrictGroup.Add(Cyl);
      end else
      begin
        { Townhouse / warehouse block }
        Box := TCastleBox.Create(ADesignOwner);
        Box.Name := MakeUniqueName(ADesignOwner, Format('DistrictBuilding_Q%d_P%d', [Q + 1, P + 1]));
        Box.Size := Vector3(4.2, H, 4.0);
        Box.Translation := Vector3(QuadCentersX[Q] + SubOffsetsX[P], 0.5 * H, QuadCentersZ[Q] + SubOffsetsZ[P]);
        Box.Color := Vector4(QuadColors[Q].X, QuadColors[Q].Y, QuadColors[Q].Z, 1.0);
        DistrictGroup.Add(Box);
      end;
    end;
  end;

  { Excluded dynamic hero landmark at plaza center }
  Beacon := TCastleSphere.Create(ADesignOwner);
  Beacon.Name := MakeUniqueName(ADesignOwner, 'HlodIgnore_HeroBeacon');
  Beacon.Radius := 1.1;
  Beacon.Translation := Vector3(0.0, 1.5, 0.0);
  Beacon.Color := Vector4(0.96, 0.82, 0.24, 1.0);
  DistrictGroup.Add(Beacon);

  AManager := TCastleHlodClusterManager.Create(ADesignOwner);
  AManager.Name := MakeUniqueName(ADesignOwner, 'HlodClusterManager');
  AManager.CellSizeMeters := 32.0;
  AManager.HlodSwitchDistance := 45.0;
  AManager.HlodHysteresisMargin := 5.0;
  AManager.MinPropsPerCluster := 2;
  AManager.AutoEvaluateCamera := False;
  RootT.Add(AManager);

  AManager.BakeClustersFromHierarchy(RootT, ADesignOwner);
  Result := True;
end;

class function THlodStudioHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): THlodStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    M: TCastleHlodClusterManager;
  begin
    if T = nil then
      Exit;
    if T is TCastleHlodClusterManager then
    begin
      M := TCastleHlodClusterManager(T);
      Inc(Result.ManagerCount);
      Result.TotalCells := Result.TotalCells + M.CellCount;
      Result.TotalClusteredProps := Result.TotalClusteredProps + M.TotalClusteredProps;
      Result.ActiveHlodCells := Result.ActiveHlodCells + M.ActiveHlodCellCount;
      Result.BaselineDrawCalls := Result.BaselineDrawCalls + M.BaselineDrawCalls;
      Result.EffectiveDrawCalls := Result.EffectiveDrawCalls + M.EffectiveDrawCalls;
      Result.BaselineTriangles := Result.BaselineTriangles + M.BaselineTriangles;
      Result.EffectiveTriangles := Result.EffectiveTriangles + M.EffectiveTriangles;
      if M.CellCount = 0 then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s has 0 baked HLOD cells — click Bake Spatial HLOD Clusters.', [M.Name]));
      end;
      if M.HlodHysteresisMargin < 1.0 then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s has HlodHysteresisMargin = %.2fm (< 1.0m), risking boundary pop-thrashing.', [
            M.Name, M.HlodHysteresisMargin]));
      end;
    end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(THlodStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
  if Result.BaselineDrawCalls > 0 then
    Result.DrawCallSavingsPercent := 100.0 *
      Max(0.0, 1.0 - (Single(Result.EffectiveDrawCalls) / Single(Result.BaselineDrawCalls)));
end;

class function THlodStudioHelper.BuildMarkdownReport(const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: THlodStudioSummary;
  Mgr: TCastleHlodClusterManager;
  SB: TStringBuilder;
  I: Integer;
  C: THlodClusterCell;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    Mgr := FindFirstManager(ARoot);
    SB.AppendLine('# Castle Game Engine — World Partition HLOD Cluster Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **HLOD Managers**: `%d`', [Sum.ManagerCount]));
    SB.AppendLine(Format('- **Spatial Cells Baked**: `%d` (`%d` clustered props)', [
      Sum.TotalCells, Sum.TotalClusteredProps]));
    SB.AppendLine(Format('- **Active HLOD Proxy Cells**: `%d / %d`', [
      Sum.ActiveHlodCells, Sum.TotalCells]));
    SB.AppendLine(Format('- **Draw Calls (Effective / Baseline)**: `%d / %d` (`-%.1f%%` draw-call reduction)', [
      Sum.EffectiveDrawCalls, Sum.BaselineDrawCalls, Sum.DrawCallSavingsPercent]));
    SB.AppendLine(Format('- **Triangles (Effective / Baseline)**: `%d / %d`', [
      Sum.EffectiveTriangles, Sum.BaselineTriangles]));
    SB.AppendLine;
    if Mgr <> nil then
    begin
      SB.AppendLine('## Spatial HLOD Cells (`' + Mgr.Name + '`)');
      SB.AppendLine('| Cell `(X, Z)` | Center `(m)` | Props | Base Tris | Proxy Tris | Dist `(m)` | State |');
      SB.AppendLine('| :--- | :--- | ---: | ---: | ---: | ---: | :--- |');
      for I := 0 to Mgr.CellCount - 1 do
      begin
        C := Mgr.GetCell(I);
        SB.AppendLine(Format('| `(%d, %d)` | `(%.1f, %.1f, %.1f)` | %d | %d | %d | %.1f | **%s** |', [
          C.CellX, C.CellZ, C.WorldCenter.X, C.WorldCenter.Y, C.WorldCenter.Z,
          C.SourcePropCount, C.SourceTrianglesEstimate, C.ProxyTrianglesCount,
          C.LastCameraDistance,
          IfThen(C.UsingHlodProxy, 'HLOD Proxy (1 Draw)', 'Full Detail')
        ]));
      end;
      SB.AppendLine;
    end;
    if Warnings.Count > 0 then
    begin
      SB.AppendLine('## Diagnostics');
      for I := 0 to Warnings.Count - 1 do
        SB.AppendLine('- ' + Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Warnings);
  end;
end;

end.
