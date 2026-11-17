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

{ Stateless helper for the MegaLights Clustered Tile Light-Grid Culler,
  Procedural Gobo Cookie & Flicker Profile Studio (Phase 341). }
unit ToolMegaLights;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleViewport, CastleTransform, CastleScene,
  CastleMegaLights;

type
  TMegaLightsStudioSummary = record
    ManagerCount: Integer;
    LightFunctionCount: Integer;
    TotalLights: Integer;
    ActiveLights: Integer;
    CulledLights: Integer;
    PeakTileLights: Integer;
    OverflowTiles: Integer;
    WarningsCount: Integer;
  end;

  TMegaLightsHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstManager(const ARoot: TComponent): TCastleMegaLightsManager; static;

    { Spawns a 32-light cyberpunk neon/torch street corridor with Light-Function
      flicker & gobo behaviors and builds the 16x8x16 clustered light grid. }
    class function SpawnCyberpunkAlleyMegaLightsDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out AManager: TCastleMegaLightsManager): Boolean; static;

    class procedure StepAllLightFunctions(const ARoot: TComponent;
      const Dt: Single); static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TMegaLightsStudioSummary; static;

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

class function TMegaLightsHelper.ResolveRootTransform(
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

class function TMegaLightsHelper.FindFirstManager(
  const ARoot: TComponent): TCastleMegaLightsManager;

  function ScanRec(const T: TCastleTransform): TCastleMegaLightsManager;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleMegaLightsManager then
      Exit(TCastleMegaLightsManager(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TMegaLightsHelper.SpawnCyberpunkAlleyMegaLightsDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out AManager: TCastleMegaLightsManager): Boolean;
var
  RootT, AlleyGroup: TCastleTransform;
  I, SideSign: Integer;
  ZPos: Single;
  PtLight: TCastlePointLight;
  Fn: TCastleLightFunctionBehavior;
begin
  AManager := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  AlleyGroup := TCastleTransform.Create(ADesignOwner);
  AlleyGroup.Name := MakeUniqueName(ADesignOwner, 'MegaLightsNeonAlley');
  RootT.Add(AlleyGroup);

  for I := 0 to 31 do
  begin
    if (I mod 2) = 0 then SideSign := -1 else SideSign := +1;
    ZPos := -26.0 + (I div 2) * 3.5;

    PtLight := TCastlePointLight.Create(ADesignOwner);
    PtLight.Name := MakeUniqueName(ADesignOwner, Format('AlleyNeonLight_%d', [I + 1]));
    PtLight.Translation := Vector3(SideSign * 3.6, 2.4 + (I mod 3) * 0.6, ZPos);
    PtLight.Radius := 8.5;
    PtLight.Intensity := 14.0;
    if (I mod 3) = 0 then
      PtLight.Color := Vector3(1.0, 0.25, 0.78)
    else if (I mod 3) = 1 then
      PtLight.Color := Vector3(0.20, 0.88, 1.0)
    else
      PtLight.Color := Vector3(1.0, 0.72, 0.24);
    AlleyGroup.Add(PtLight);

    Fn := TCastleLightFunctionBehavior.Create(ADesignOwner);
    Fn.Name := MakeUniqueName(ADesignOwner, Format('AlleyLightFn_%d', [I + 1]));
    Fn.BaseIntensity := 14.0;
    Fn.PhaseOffsetSec := I * 0.23;
    case I mod 3 of
      0: begin Fn.FlickerProfile := lfpBrokenFluorescentStrobe; Fn.GoboPattern := lgpWindowVenetianBlinds; end;
      1: begin Fn.FlickerProfile := lfpSirenPulseBeacon;        Fn.GoboPattern := lgpIndustrialFanBlades; end;
    else
         begin Fn.FlickerProfile := lfpTorchCampfirePerlin;     Fn.GoboPattern := lgpCathedralRoseGrate; end;
    end;
    PtLight.AddBehavior(Fn);
    Fn.StepLightFunction(0.0);
  end;

  AManager := TCastleMegaLightsManager.Create(ADesignOwner);
  AManager.Name := MakeUniqueName(ADesignOwner, 'MegaLightsClusterManager');
  AManager.VolumeHalfExtentXZ := 36.0;
  AManager.VolumeHeightY := 16.0;
  AManager.DistanceCullMeters := 65.0;
  AManager.MaxLightsPerCluster := 8;
  RootT.Add(AManager);
  AManager.RebuildLightClusters(RootT, Vector3(0, 2, 0));
  Result := True;
end;

class procedure TMegaLightsHelper.StepAllLightFunctions(
  const ARoot: TComponent; const Dt: Single);

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleLightFunctionBehavior then
        TCastleLightFunctionBehavior(T.Behaviors[I]).StepLightFunction(Dt);
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TMegaLightsHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TMegaLightsStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    M: TCastleMegaLightsManager;
  begin
    if T = nil then Exit;
    if T is TCastleMegaLightsManager then
    begin
      M := TCastleMegaLightsManager(T);
      Inc(Result.ManagerCount);
      Result.TotalLights := Result.TotalLights + M.TotalSceneLights;
      Result.ActiveLights := Result.ActiveLights + M.ActiveUnculledLights;
      Result.CulledLights := Result.CulledLights + M.CulledDistantLights;
      if M.HotspotMaxLightsInAnyTile > Result.PeakTileLights then
        Result.PeakTileLights := M.HotspotMaxLightsInAnyTile;
      Result.OverflowTiles := Result.OverflowTiles + M.OverflowTileCount;
      if M.OverflowTileCount > 0 then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s has %d 3D cluster tiles exceeding MaxLightsPerCluster=%d (Peak=%d).', [
            M.Name, M.OverflowTileCount, M.MaxLightsPerCluster, M.HotspotMaxLightsInAnyTile]));
      end;
    end;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleLightFunctionBehavior then
        Inc(Result.LightFunctionCount);
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TMegaLightsStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TMegaLightsHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TMegaLightsStudioSummary;
  SB: TStringBuilder;
  I: Integer;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    SB.AppendLine('# Castle Game Engine — MegaLights Clustered Grid & Light-Function Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **MegaLights Managers**: `%d` (`%d` Light-Function behaviors)', [
      Sum.ManagerCount, Sum.LightFunctionCount]));
    SB.AppendLine(Format('- **Punctual Lights (Active / Total / Distance-Culled)**: `%d / %d / %d`', [
      Sum.ActiveLights, Sum.TotalLights, Sum.CulledLights]));
    SB.AppendLine(Format('- **Cluster Tile Hotspot Peak**: `%d` lights/tile (`%d` overflow tiles)', [
      Sum.PeakTileLights, Sum.OverflowTiles]));
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
