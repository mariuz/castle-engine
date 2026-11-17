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

{ Stateless helper for the World Partition Runtime Data Layers, Scenario
  Visibility/Load States & Sub-Layer Inheritance Studio (Phase 343). }
unit ToolDataLayers;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleDataLayers;

type
  TDataLayersStudioSummary = record
    ManagerCount: Integer;
    DefinedLayersCount: Integer;
    TaggedActorsCount: Integer;
    ActivatedActorsCount: Integer;
    LoadedHiddenActorsCount: Integer;
    UnloadedActorsCount: Integer;
    MissingLayerTagsCount: Integer;
    WarningsCount: Integer;
  end;

  TDataLayersHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstManager(const ARoot: TComponent): TCastleDataLayerManager; static;

    { Spawn a multi-scenario Fortress Town Square scene with permanent walls plus
      8 props tagged across MarketStalls, SiegeCatapults, BreachFires & RubbleBarricades. }
    class function SpawnFortressScenarioDataLayersDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out AManager: TCastleDataLayerManager): Boolean; static;

    class function SwitchScenarioAndApply(const ARoot: TComponent;
      const APreset: TDataLayerScenarioPreset): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TDataLayersStudioSummary; static;

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

class function TDataLayersHelper.ResolveRootTransform(
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

class function TDataLayersHelper.FindFirstManager(
  const ARoot: TComponent): TCastleDataLayerManager;

  function ScanRec(const T: TCastleTransform): TCastleDataLayerManager;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleDataLayerManager then
      Exit(TCastleDataLayerManager(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TDataLayersHelper.SpawnFortressScenarioDataLayersDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out AManager: TCastleDataLayerManager): Boolean;
var
  RootT: TCastleTransform;
  FloorBox, WallBox: TCastleBox;

  procedure SpawnTaggedBox(const ABaseName, ALayerName: String;
    const APos, ASize: TVector3; const AColor: TVector4);
  var
    B: TCastleBox;
    Tag: TCastleDataLayerTagBehavior;
  begin
    B := TCastleBox.Create(ADesignOwner);
    B.Name := MakeUniqueName(ADesignOwner, ABaseName);
    B.Size := ASize;
    B.Translation := APos;
    B.Color := AColor;
    Tag := TCastleDataLayerTagBehavior.Create(ADesignOwner);
    Tag.Name := MakeUniqueName(ADesignOwner, ABaseName + '_Tag');
    Tag.LayerName := ALayerName;
    B.AddBehavior(Tag);
    RootT.Add(B);
  end;

begin
  AManager := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  { Permanent base world geometry (untagged: always loaded & visible) }
  FloorBox := TCastleBox.Create(ADesignOwner);
  FloorBox.Name := MakeUniqueName(ADesignOwner, 'FortressCourtyardFloor');
  FloorBox.Size := Vector3(32.0, 0.5, 32.0);
  FloorBox.Translation := Vector3(0.0, -0.25, 0.0);
  FloorBox.Color := Vector4(0.32, 0.34, 0.38, 1.0);
  RootT.Add(FloorBox);

  WallBox := TCastleBox.Create(ADesignOwner);
  WallBox.Name := MakeUniqueName(ADesignOwner, 'FortressCurtainWall');
  WallBox.Size := Vector3(24.0, 5.0, 1.8);
  WallBox.Translation := Vector3(0.0, 2.5, -8.0);
  WallBox.Color := Vector4(0.52, 0.50, 0.48, 1.0);
  RootT.Add(WallBox);

  { 1. PeacetimeCivic -> MarketStalls (2 merchant awnings) }
  SpawnTaggedBox('MerchantStall_West', 'MarketStalls',
    Vector3(-4.5, 1.1, 2.5), Vector3(2.8, 2.2, 2.0), Vector4(0.26, 0.78, 0.46, 1.0));
  SpawnTaggedBox('MerchantStall_East', 'MarketStalls',
    Vector3(+4.5, 1.1, 2.5), Vector3(2.8, 2.2, 2.0), Vector4(0.32, 0.84, 0.52, 1.0));

  { 2. CitySiege -> SiegeCatapults & BreachFires (4 siege actors) }
  SpawnTaggedBox('SiegeTrebuchet_1', 'SiegeCatapults',
    Vector3(-6.0, 1.6, -13.5), Vector3(3.2, 3.2, 4.2), Vector4(0.86, 0.52, 0.22, 1.0));
  SpawnTaggedBox('SiegeTrebuchet_2', 'SiegeCatapults',
    Vector3(+6.0, 1.6, -13.5), Vector3(3.2, 3.2, 4.2), Vector4(0.86, 0.52, 0.22, 1.0));
  SpawnTaggedBox('WallBreachFire_1', 'BreachFires',
    Vector3(-2.0, 1.8, -7.2), Vector3(1.6, 3.6, 1.6), Vector4(0.98, 0.30, 0.18, 1.0));
  SpawnTaggedBox('WallBreachFire_2', 'BreachFires',
    Vector3(+2.0, 1.8, -7.2), Vector3(1.6, 3.6, 1.6), Vector4(0.98, 0.30, 0.18, 1.0));

  { 3. PostWarRuins -> RubbleBarricades (2 aftermath rubble mounds) }
  SpawnTaggedBox('CollapsedRubble_1', 'RubbleBarricades',
    Vector3(-1.8, 0.9, -4.5), Vector3(3.8, 1.8, 2.8), Vector4(0.58, 0.60, 0.66, 1.0));
  SpawnTaggedBox('CollapsedRubble_2', 'RubbleBarricades',
    Vector3(+2.4, 0.7, -3.2), Vector3(3.2, 1.4, 2.4), Vector4(0.58, 0.60, 0.66, 1.0));

  AManager := TCastleDataLayerManager.Create(ADesignOwner);
  AManager.Name := MakeUniqueName(ADesignOwner, 'WorldDataLayerManager');
  RootT.Add(AManager);
  AManager.ApplyScenarioPreset(dlspPeacetimeTown);
  AManager.ApplyDataLayersToWorld(RootT);
  Result := True;
end;

class function TDataLayersHelper.SwitchScenarioAndApply(const ARoot: TComponent;
  const APreset: TDataLayerScenarioPreset): Boolean;
var
  Mgr: TCastleDataLayerManager;
  RootT: TCastleTransform;
begin
  Mgr := FindFirstManager(ARoot);
  RootT := ResolveRootTransform(ARoot);
  Result := (Mgr <> nil) and (RootT <> nil);
  if not Result then Exit;
  Mgr.ApplyScenarioPreset(APreset);
  Mgr.ApplyDataLayersToWorld(RootT);
end;

class function TDataLayersHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TDataLayersStudioSummary;
var
  RootT: TCastleTransform;
  Mgr: TCastleDataLayerManager;
begin
  Result := Default(TDataLayersStudioSummary);
  RootT := ResolveRootTransform(ARoot);
  Mgr := FindFirstManager(ARoot);
  if (RootT = nil) or (Mgr = nil) then
    Exit;

  Mgr.ApplyDataLayersToWorld(RootT);
  Result.ManagerCount := 1;
  Result.DefinedLayersCount := Mgr.LayerCount;
  Result.TaggedActorsCount := Mgr.TaggedActorCount;
  Result.ActivatedActorsCount := Mgr.ActivatedActorCount;
  Result.LoadedHiddenActorsCount := Mgr.LoadedHiddenActorCount;
  Result.UnloadedActorsCount := Mgr.UnloadedActorCount;
  Result.MissingLayerTagsCount := Mgr.MissingLayerTagCount;

  if Mgr.MissingLayerTagCount > 0 then
  begin
    Inc(Result.WarningsCount);
    if AWarnings <> nil then
      AWarnings.Add(Format('%d actor tag(s) reference an undefined Data Layer name (falling back to %s).', [
        Mgr.MissingLayerTagCount, DataLayerStateToDisplayName(Mgr.DefaultUnknownLayerState)]));
  end;
end;

class function TDataLayersHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TDataLayersStudioSummary;
  Mgr: TCastleDataLayerManager;
  SB: TStringBuilder;
  I: Integer;
  Def: TDataLayerDefinition;
  Eff: TDataLayerRuntimeState;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    Mgr := FindFirstManager(ARoot);
    SB.AppendLine('# Castle Game Engine — World Partition Runtime Data Layers Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Defined Data Layers**: `%d`', [Sum.DefinedLayersCount]));
    SB.AppendLine(Format('- **Tagged Actors (Activated / LoadedHidden / Unloaded)**: `%d / %d / %d` (Total `%d`)', [
      Sum.ActivatedActorsCount, Sum.LoadedHiddenActorsCount,
      Sum.UnloadedActorsCount, Sum.TaggedActorsCount]));
    if Mgr <> nil then
    begin
      SB.AppendLine(Format('- **Active Scenario Preset**: `%s`', [
        DataLayerScenarioToDisplayName(Mgr.ScenarioPreset)]));
      SB.AppendLine;
      SB.AppendLine('| Layer Name | Parent Layer | Desired State | Effective State |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to Mgr.LayerCount - 1 do
      begin
        Def := Mgr.GetLayer(I);
        Eff := Mgr.EvaluateEffectiveLayerState(Def.Name);
        SB.AppendLine(Format('| `%s` | `%s` | `%s` | **%s** |', [
          Def.Name, Def.ParentLayerName,
          DataLayerStateToDisplayName(Def.DesiredState),
          DataLayerStateToDisplayName(Eff)]));
      end;
      SB.AppendLine;
      SB.AppendLine('```mermaid');
      SB.Append(Mgr.ExportMermaidHierarchy);
      SB.AppendLine('```');
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
