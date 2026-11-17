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

{ Stateless helper for the Landscape Thermal Talus & Droplet Hydraulic Erosion,
  Sediment Deposition & Flow-Map Baker Studio (Phase 340). }
unit ToolErosionStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform,
  CastleErosionBaker;

type
  TErosionStudioSummary = record
    BakerCount: Integer;
    TotalThermalPasses: Integer;
    TotalDroplets: Integer;
    TotalTriangles: Integer;
    MaxSlopeDeg: Single;
    WarningsCount: Integer;
  end;

  TErosionStudioHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstBaker(const ARoot: TComponent): TCastleTerrainErosionBaker; static;

    class function SpawnErodedAlpinePeakDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ABaker: TCastleTerrainErosionBaker): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TErosionStudioSummary; static;

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

class function TErosionStudioHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function TErosionStudioHelper.FindFirstBaker(
  const ARoot: TComponent): TCastleTerrainErosionBaker;

  function ScanRec(const T: TCastleTransform): TCastleTerrainErosionBaker;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleTerrainErosionBaker then
      Exit(TCastleTerrainErosionBaker(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TErosionStudioHelper.SpawnErodedAlpinePeakDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ABaker: TCastleTerrainErosionBaker): Boolean;
var
  RootT: TCastleTransform;
begin
  ABaker := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  ABaker := TCastleTerrainErosionBaker.Create(ADesignOwner);
  ABaker.Name := MakeUniqueName(ADesignOwner, 'LandscapeErosionBaker');
  ABaker.Preset := etpAlpineVolcanicCone;
  ABaker.RunThermalErosionSteps(8);
  ABaker.RunHydraulicDroplets(1200);
  RootT.Add(ABaker);
  Result := True;
end;

class function TErosionStudioHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TErosionStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    B: TCastleTerrainErosionBaker;
  begin
    if T = nil then Exit;
    if T is TCastleTerrainErosionBaker then
    begin
      B := TCastleTerrainErosionBaker(T);
      Inc(Result.BakerCount);
      Result.TotalThermalPasses := Result.TotalThermalPasses + B.ThermalPassesRun;
      Result.TotalDroplets := Result.TotalDroplets + B.DropletsSimulated;
      Result.TotalTriangles := Result.TotalTriangles + B.GeneratedTriangleCount;
      if B.MaxSlopeAngleDeg > Result.MaxSlopeDeg then
        Result.MaxSlopeDeg := B.MaxSlopeAngleDeg;
      if (B.ThermalPassesRun = 0) and (B.DropletsSimulated = 0) then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s has 0 thermal/hydraulic passes — run erosion steps to carve gullies.', [B.Name]));
      end;
    end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TErosionStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TErosionStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TErosionStudioSummary;
  B: TCastleTerrainErosionBaker;
  SB: TStringBuilder;
  I: Integer;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    B := FindFirstBaker(ARoot);
    SB.AppendLine('# Castle Game Engine — Landscape Thermal & Hydraulic Erosion Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Erosion Bakers (`TCastleTerrainErosionBaker`)**: `%d` (`%d` tris)', [
      Sum.BakerCount, Sum.TotalTriangles]));
    SB.AppendLine(Format('- **Thermal Talus Passes / Hydraulic Droplets**: `%d` / `%d`', [
      Sum.TotalThermalPasses, Sum.TotalDroplets]));
    if B <> nil then
    begin
      SB.AppendLine(Format('- **Total Terrain Volume**: `%.1f m^3` (Peak `%.2f m`, Max Slope `%.1f°`)', [
        B.TotalTerrainVolume, B.PeakElevation, B.MaxSlopeAngleDeg]));
      SB.AppendLine(Format('- **Cumulative Eroded / Deposited Material**: `%.2f m` / `%.2f m`', [
        B.TotalErodedMeters, B.TotalDepositedMeters]));
    end;
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
