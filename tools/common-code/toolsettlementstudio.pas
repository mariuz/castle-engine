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

{ Stateless helper for the PCG Spline-Biome Settlement, Road-Intersection Graph,
  Building Lot Subdivision & Perimeter Fence Generator Studio (Phase 335). }
unit ToolSettlementStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform,
  CastlePcgSettlement;

type
  TSettlementStudioSummary = record
    SettlementCount: Integer;
    TotalRoadSegments: Integer;
    TotalBuildingLots: Integer;
    TotalStreetlamps: Integer;
    TotalFencePosts: Integer;
    TotalTriangles: Integer;
    OverlappingPairs: Integer;
    RoadIntrusions: Integer;
    WarningsCount: Integer;
  end;

  TSettlementStudioHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstSettlement(const ARoot: TComponent): TCastlePcgSettlement; static;

    class function SpawnCrossroadsVillageDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ASettlement: TCastlePcgSettlement): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TSettlementStudioSummary; static;

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

class function TSettlementStudioHelper.ResolveRootTransform(
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

class function TSettlementStudioHelper.FindFirstSettlement(
  const ARoot: TComponent): TCastlePcgSettlement;

  function ScanRec(const T: TCastleTransform): TCastlePcgSettlement;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastlePcgSettlement then
      Exit(TCastlePcgSettlement(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TSettlementStudioHelper.SpawnCrossroadsVillageDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ASettlement: TCastlePcgSettlement): Boolean;
var
  RootT: TCastleTransform;
begin
  ASettlement := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  ASettlement := TCastlePcgSettlement.Create(ADesignOwner);
  ASettlement.Name := MakeUniqueName(ADesignOwner, 'PcgCrossroadsVillage');
  ASettlement.SettlementRadius := 34.0;
  ASettlement.Preset := pspCrossroadsHamlet;
  ASettlement.RandomSeed := 2026;
  RootT.Add(ASettlement);
  ASettlement.RebuildSettlement(RootT.World);
  Result := True;
end;

class function TSettlementStudioHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TSettlementStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I, Ov, Intr: Integer;
    S: TCastlePcgSettlement;
  begin
    if T = nil then
      Exit;
    if T is TCastlePcgSettlement then
    begin
      S := TCastlePcgSettlement(T);
      Inc(Result.SettlementCount);
      Result.TotalRoadSegments := Result.TotalRoadSegments + S.RoadSegmentCount;
      Result.TotalBuildingLots := Result.TotalBuildingLots + S.BuildingLotCount;
      Result.TotalStreetlamps := Result.TotalStreetlamps + S.StreetlampCount;
      Result.TotalFencePosts := Result.TotalFencePosts + S.FencePostCount;
      Result.TotalTriangles := Result.TotalTriangles + S.GeneratedTriangleCount;
      Ov := S.CountOverlappingLotPairs;
      Intr := S.CountRoadIntrudingLots;
      Result.OverlappingPairs := Result.OverlappingPairs + Ov;
      Result.RoadIntrusions := Result.RoadIntrusions + Intr;
      if S.BuildingLotCount = 0 then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s generated 0 building lots — increase SettlementRadius or reduce LotWidthMeters.', [S.Name]));
      end;
      if (Ov > 0) or (Intr > 0) then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s detected %d overlaps / %d road intrusions.', [S.Name, Ov, Intr]));
      end;
    end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TSettlementStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TSettlementStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TSettlementStudioSummary;
  SB: TStringBuilder;
  I: Integer;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    SB.AppendLine('# Castle Game Engine — PCG Biome Settlement & Road Graph Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **PCG Settlements (`TCastlePcgSettlement`)**: `%d`', [Sum.SettlementCount]));
    SB.AppendLine(Format('- **Road Segments**: `%d`', [Sum.TotalRoadSegments]));
    SB.AppendLine(Format('- **Subdivided Building Lots**: `%d` (`%d` overlaps, `%d` road intrusions)', [
      Sum.TotalBuildingLots, Sum.OverlappingPairs, Sum.RoadIntrusions]));
    SB.AppendLine(Format('- **Streetlamps / Perimeter Fence Posts**: `%d` / `%d`', [
      Sum.TotalStreetlamps, Sum.TotalFencePosts]));
    SB.AppendLine(Format('- **Batched Settlement Triangles**: `%d`', [Sum.TotalTriangles]));
    if Warnings.Count > 0 then
    begin
      SB.AppendLine;
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
