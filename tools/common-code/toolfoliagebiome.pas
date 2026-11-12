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

{ Hierarchy discovery, 1-click biome & road exclusion volume creation, batch
  ecosystem population, LOD proxy auditing, and Markdown reporting for
  @link(TCastleFoliageBiomeVolume), @link(TCastleFoliageExclusionVolume), and
  @link(TCastleLodProxyBehavior) (Phase 303). }
unit ToolFoliageBiome;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleUiControls, CastleViewport,
  CastleFoliageBiome;

type
  TFoliageBiomeVolumeArray = array of TCastleFoliageBiomeVolume;
  TFoliageExclusionVolumeArray = array of TCastleFoliageExclusionVolume;
  TLodProxyBehaviorArray = array of TCastleLodProxyBehavior;

  { Hierarchy scan & ecosystem summary for Procedural Foliage Biome Studio. }
  TFoliageBiomeSummary = record
    Biomes: TFoliageBiomeVolumeArray;
    Exclusions: TFoliageExclusionVolumeArray;
    LodProxies: TLodProxyBehaviorArray;
    TotalGeneratedInstances: Integer;
    TotalSpeciesRules: Integer;
    Warnings: array of String;
  end;

  { Stateless editor helper for Procedural Foliage Ecosystems & LOD Proxies. }
  TFoliageBiomeHelper = class
  public
    class function ScanFoliageEcosystem(
      const ARoot: TComponent): TFoliageBiomeSummary;

    class function CreateBiomeVolumeInDesign(
      const ARoot, ADesignOwner: TComponent;
      const APresetIndex: Integer;
      const AWorldPos: TVector3): TCastleFoliageBiomeVolume;

    class function CreateExclusionVolumeInDesign(
      const ARoot, ADesignOwner: TComponent;
      const AWorldPos, ASize: TVector3): TCastleFoliageExclusionVolume;

    class function AttachLodProxyToTransform(
      const ATarget: TCastleTransform; const ADesignOwner: TComponent;
      const AHighUrl, AMediumUrl, ALowUrl: String): TCastleLodProxyBehavior;

    { Populate @code(ABiome) (or all biomes when @code(ABiome = nil)) while
      automatically passing every @link(TCastleFoliageExclusionVolume) in @code(ARoot). }
    class function PopulateBiomeWithSceneExclusions(
      const ARoot, ADesignOwner: TComponent;
      const ABiome: TCastleFoliageBiomeVolume = nil): Integer;

    class function BuildMarkdownReport(const ARoot: TComponent): String;
  end;

implementation

function ProposeUniqueFoliageName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function FindFoliageWorldContainer(const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindFoliageWorldContainer(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

{ TFoliageBiomeHelper -------------------------------------------------------- }

class function TFoliageBiomeHelper.ScanFoliageEcosystem(
  const ARoot: TComponent): TFoliageBiomeSummary;
var
  OutSum: TFoliageBiomeSummary;
  Visited: TList;

  procedure AppendWarning(const Msg: String);
  var
    N: Integer;
  begin
    N := Length(OutSum.Warnings);
    SetLength(OutSum.Warnings, N + 1);
    OutSum.Warnings[N] := Msg;
  end;

  procedure AddBiome(const B: TCastleFoliageBiomeVolume);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.Biomes) do
      if OutSum.Biomes[I] = B then
        Exit;
    SetLength(OutSum.Biomes, Length(OutSum.Biomes) + 1);
    OutSum.Biomes[High(OutSum.Biomes)] := B;
    Inc(OutSum.TotalGeneratedInstances, B.GeneratedInstanceCount);
    Inc(OutSum.TotalSpeciesRules, B.SpeciesCount);
  end;

  procedure AddExclusion(const E: TCastleFoliageExclusionVolume);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.Exclusions) do
      if OutSum.Exclusions[I] = E then
        Exit;
    SetLength(OutSum.Exclusions, Length(OutSum.Exclusions) + 1);
    OutSum.Exclusions[High(OutSum.Exclusions)] := E;
  end;

  procedure AddLod(const L: TCastleLodProxyBehavior);
  var
    I: Integer;
  begin
    for I := 0 to High(OutSum.LodProxies) do
      if OutSum.LodProxies[I] = L then
        Exit;
    SetLength(OutSum.LodProxies, Length(OutSum.LodProxies) + 1);
    OutSum.LodProxies[High(OutSum.LodProxies)] := L;
  end;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    VP: TCastleViewport;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if Visited.IndexOf(C) >= 0 then
      Exit;
    Visited.Add(C);

    if C is TCastleFoliageBiomeVolume then
      AddBiome(TCastleFoliageBiomeVolume(C));
    if C is TCastleFoliageExclusionVolume then
      AddExclusion(TCastleFoliageExclusionVolume(C));
    if C is TCastleLodProxyBehavior then
      AddLod(TCastleLodProxyBehavior(C));

    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      if VP.Items <> nil then
        Visit(VP.Items);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Visit(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Visit(T[I]);
    end;

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;
  end;

var
  I: Integer;
begin
  OutSum := Default(TFoliageBiomeSummary);
  if ARoot = nil then
  begin
    Result := OutSum;
    Exit;
  end;

  Visited := TList.Create;
  try
    Visit(ARoot);
  finally
    FreeAndNil(Visited);
  end;

  for I := 0 to High(OutSum.Biomes) do
    if OutSum.Biomes[I].SpeciesCount = 0 then
      AppendWarning(Format('Biome volume "%s" has 0 species rules configured.',
        [OutSum.Biomes[I].Name]));

  for I := 0 to High(OutSum.LodProxies) do
    if (OutSum.LodProxies[I].LowDistance <= OutSum.LodProxies[I].MediumDistance) or
       (OutSum.LodProxies[I].CullDistance <= OutSum.LodProxies[I].LowDistance) then
      AppendWarning(Format('LOD Proxy "%s" has non-increasing distance thresholds (%.1f / %.1f / %.1f).',
        [OutSum.LodProxies[I].Name,
         OutSum.LodProxies[I].MediumDistance,
         OutSum.LodProxies[I].LowDistance,
         OutSum.LodProxies[I].CullDistance]));

  Result := OutSum;
end;

class function TFoliageBiomeHelper.CreateBiomeVolumeInDesign(
  const ARoot, ADesignOwner: TComponent;
  const APresetIndex: Integer;
  const AWorldPos: TVector3): TCastleFoliageBiomeVolume;
var
  Container: TCastleTransform;
  OwnerToUse: TComponent;
begin
  Result := nil;
  Container := FindFoliageWorldContainer(ARoot);
  if Container = nil then
    Exit;
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Result := TCastleFoliageBiomeVolume.Create(OwnerToUse);
  Result.Name := ProposeUniqueFoliageName(OwnerToUse, 'FoliageBiome');
  Result.Translation := AWorldPos;
  Result.LoadBiomePreset(APresetIndex);
  Container.Add(Result);
end;

class function TFoliageBiomeHelper.CreateExclusionVolumeInDesign(
  const ARoot, ADesignOwner: TComponent;
  const AWorldPos, ASize: TVector3): TCastleFoliageExclusionVolume;
var
  Container: TCastleTransform;
  OwnerToUse: TComponent;
begin
  Result := nil;
  Container := FindFoliageWorldContainer(ARoot);
  if Container = nil then
    Exit;
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := ARoot;

  Result := TCastleFoliageExclusionVolume.Create(OwnerToUse);
  Result.Name := ProposeUniqueFoliageName(OwnerToUse, 'FoliageExclusion');
  Result.Translation := AWorldPos;
  Result.ExclusionSize := ASize;
  Container.Add(Result);
end;

class function TFoliageBiomeHelper.AttachLodProxyToTransform(
  const ATarget: TCastleTransform; const ADesignOwner: TComponent;
  const AHighUrl, AMediumUrl, ALowUrl: String): TCastleLodProxyBehavior;
var
  OwnerToUse: TComponent;
begin
  Result := nil;
  if ATarget = nil then
    Exit;
  Result := ATarget.FindBehavior(TCastleLodProxyBehavior) as TCastleLodProxyBehavior;
  if Result = nil then
  begin
    if ADesignOwner <> nil then
      OwnerToUse := ADesignOwner
    else
      OwnerToUse := ATarget.Owner;
    Result := TCastleLodProxyBehavior.Create(OwnerToUse);
    Result.Name := ProposeUniqueFoliageName(OwnerToUse, 'LodProxy');
    ATarget.AddBehavior(Result);
  end;
  Result.HighUrl := AHighUrl;
  Result.MediumUrl := AMediumUrl;
  Result.LowUrl := ALowUrl;
end;

class function TFoliageBiomeHelper.PopulateBiomeWithSceneExclusions(
  const ARoot, ADesignOwner: TComponent;
  const ABiome: TCastleFoliageBiomeVolume): Integer;
var
  Sum: TFoliageBiomeSummary;
  I: Integer;
begin
  Result := 0;
  Sum := ScanFoliageEcosystem(ARoot);
  if ABiome <> nil then
    Result := ABiome.PopulateBiomeInstances(ADesignOwner, Sum.Exclusions)
  else
    for I := 0 to High(Sum.Biomes) do
      Inc(Result, Sum.Biomes[I].PopulateBiomeInstances(ADesignOwner, Sum.Exclusions));
end;

class function TFoliageBiomeHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Sum: TFoliageBiomeSummary;
  SB: TStringBuilder;
  I: Integer;
  B: TCastleFoliageBiomeVolume;
begin
  Sum := ScanFoliageEcosystem(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Procedural Foliage Ecosystems & LOD Proxy Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Biome Volumes**: `%d` | **Exclusion Masks**: `%d` | **Generated Instances**: `%d` | **LOD Proxies**: `%d`',
      [Length(Sum.Biomes), Length(Sum.Exclusions),
       Sum.TotalGeneratedInstances, Length(Sum.LodProxies)]));
    SB.AppendLine;

    if Length(Sum.Biomes) > 0 then
    begin
      SB.AppendLine('| Biome Volume | Preset Title | Footprint `(W x D)` | Species | Spawned |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Sum.Biomes) do
      begin
        B := Sum.Biomes[I];
        SB.AppendLine(Format('| `%s` | %s | `%.0f x %.0f m` | `%d` | `%d / %d` |',
          [B.Name, B.BiomeTitle, B.VolumeSize.X, B.VolumeSize.Z,
           B.SpeciesCount, B.GeneratedInstanceCount, B.TargetInstanceCount]));
      end;
      SB.AppendLine;
    end;

    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine('## Ecosystem & LOD Diagnostics');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- [!] ' + Sum.Warnings[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
