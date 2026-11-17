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

{ World Partition Runtime Data Layers providing hierarchical parent/sub-layer
  Unloaded / LoadedHidden / Activated state inheritance, 1-click world scenario
  switching, and live tagged actor visibility gating
  (Phase 343 — Unreal Engine 6.0+ UDataLayerManager Parity). }
unit CastleDataLayers;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils, fpjson, jsonparser,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Runtime lifecycle state of a World Partition Data Layer, ordered monotonically
    from Unloaded (0) < LoadedHidden (1) < Activated (2) so effective child state
    is Min(DesiredState, ParentEffectiveState). }
  TDataLayerRuntimeState = (
    dlrsUnloaded,
    dlrsLoadedHidden,
    dlrsActivated
  );

  { Built-in multi-layer world scenario presets. }
  TDataLayerScenarioPreset = (
    dlspCustom,
    dlspPeacetimeTown,
    dlspActiveSiegeBattle,
    dlspPostWarRuins
  );

  { Metadata & runtime state for a named Data Layer. }
  TDataLayerDefinition = record
    Name: String;
    ParentLayerName: String;
    DesiredState: TDataLayerRuntimeState;
    DebugColorRGB: TVector3;
    Description: String;
  end;

  { Behavior attached to any TCastleTransform assigning it to a named World
    Partition Data Layer. }
  TCastleDataLayerTagBehavior = class(TCastleBehavior)
  private
    FLayerName: String;
    FInvertActivation: Boolean;
    FLastAppliedState: TDataLayerRuntimeState;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function DataLayerTagSummaryBadge: String;

    property LastAppliedState: TDataLayerRuntimeState read FLastAppliedState write FLastAppliedState;
  published
    property LayerName: String read FLayerName write FLayerName;
    property InvertActivation: Boolean read FInvertActivation write FInvertActivation default False;
  end;

  { Centralized World Partition Data Layer Manager evaluating hierarchical
    parent/child layer inheritance and toggling tagged world actors. }
  TCastleDataLayerManager = class(TCastleTransform)
  private
    FScenarioPreset: TDataLayerScenarioPreset;
    FDefaultUnknownLayerState: TDataLayerRuntimeState;
    FLayers: array of TDataLayerDefinition;

    FTaggedActorCount: Integer;
    FActivatedActorCount: Integer;
    FLoadedHiddenActorCount: Integer;
    FUnloadedActorCount: Integer;
    FMissingLayerTagCount: Integer;

    procedure SetScenarioPreset(const AValue: TDataLayerScenarioPreset);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ClearLayers;
    function LayerCount: Integer;
    function IndexOfLayer(const AName: String): Integer;
    function GetLayer(const AIndex: Integer): TDataLayerDefinition;

    function AddOrUpdateLayer(const AName, AParentLayerName: String;
      const ADesiredState: TDataLayerRuntimeState;
      const ADebugColorRGB: TVector3;
      const ADescription: String = ''): Integer;

    function SetLayerState(const AName: String;
      const ADesiredState: TDataLayerRuntimeState): Boolean;

    function GetLayerDesiredState(const AName: String): TDataLayerRuntimeState;

    { Effective runtime state of AName after applying recursive parent-layer
      inheritance: Effective(Child) = Min(Desired(Child), Effective(Parent)). }
    function EvaluateEffectiveLayerState(const AName: String): TDataLayerRuntimeState;

    { Populate or switch the 7-layer Town / Siege / Ruins hierarchy preset. }
    procedure ApplyScenarioPreset(const APreset: TDataLayerScenarioPreset);

    { Evaluate all TCastleDataLayerTagBehavior instances under AWorldRoot and
      synchronize Parent.Exists with each layer's effective state. }
    procedure ApplyDataLayersToWorld(const AWorldRoot: TCastleTransform);

    function ExportMermaidHierarchy: String;
    function DataLayerSummaryBadge: String;

    property TaggedActorCount: Integer read FTaggedActorCount;
    property ActivatedActorCount: Integer read FActivatedActorCount;
    property LoadedHiddenActorCount: Integer read FLoadedHiddenActorCount;
    property UnloadedActorCount: Integer read FUnloadedActorCount;
    property MissingLayerTagCount: Integer read FMissingLayerTagCount;
  published
    property ScenarioPreset: TDataLayerScenarioPreset
      read FScenarioPreset write SetScenarioPreset default dlspPeacetimeTown;
    property DefaultUnknownLayerState: TDataLayerRuntimeState
      read FDefaultUnknownLayerState write FDefaultUnknownLayerState default dlrsUnloaded;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function DataLayerStateToDisplayName(const AState: TDataLayerRuntimeState): String;
function DataLayerScenarioToDisplayName(const APreset: TDataLayerScenarioPreset): String;

implementation

uses
  CastleComponentSerialize;

function DataLayerStateToDisplayName(const AState: TDataLayerRuntimeState): String;
begin
  case AState of
    dlrsUnloaded:     Result := 'Unloaded';
    dlrsLoadedHidden: Result := 'LoadedHidden';
    dlrsActivated:    Result := 'Activated';
  end;
end;

function DataLayerScenarioToDisplayName(const APreset: TDataLayerScenarioPreset): String;
begin
  case APreset of
    dlspCustom:            Result := 'Custom Layer Overrides';
    dlspPeacetimeTown:     Result := 'Peacetime Market Town';
    dlspActiveSiegeBattle: Result := 'Active Fortress Siege';
    dlspPostWarRuins:      Result := 'Post-War Aftermath Ruins';
  end;
end;

{ TCastleDataLayerTagBehavior ------------------------------------------------ }

constructor TCastleDataLayerTagBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLayerName := 'MarketStalls';
  FInvertActivation := False;
  FLastAppliedState := dlrsActivated;
end;

function TCastleDataLayerTagBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, ['LayerName', 'InvertActivation']) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleDataLayerTagBehavior.DataLayerTagSummaryBadge: String;
begin
  Result := Format('[DataLayerTag:%s State=%s]', [
    IfThen(FLayerName <> '', FLayerName, '<none>'),
    DataLayerStateToDisplayName(FLastAppliedState)
  ]);
end;

{ TCastleDataLayerManager ---------------------------------------------------- }

constructor TCastleDataLayerManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDefaultUnknownLayerState := dlrsUnloaded;
  FScenarioPreset := dlspCustom;
  ApplyScenarioPreset(dlspPeacetimeTown);
end;

destructor TCastleDataLayerManager.Destroy;
begin
  SetLength(FLayers, 0);
  inherited Destroy;
end;

function TCastleDataLayerManager.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'ScenarioPreset', 'DefaultUnknownLayerState', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleDataLayerManager.ClearLayers;
begin
  SetLength(FLayers, 0);
end;

function TCastleDataLayerManager.LayerCount: Integer;
begin
  Result := Length(FLayers);
end;

function TCastleDataLayerManager.IndexOfLayer(const AName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FLayers) do
    if SameText(FLayers[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

function TCastleDataLayerManager.GetLayer(const AIndex: Integer): TDataLayerDefinition;
begin
  if (AIndex >= 0) and (AIndex <= High(FLayers)) then
    Result := FLayers[AIndex]
  else
    Result := Default(TDataLayerDefinition);
end;

function TCastleDataLayerManager.AddOrUpdateLayer(
  const AName, AParentLayerName: String;
  const ADesiredState: TDataLayerRuntimeState;
  const ADebugColorRGB: TVector3;
  const ADescription: String): Integer;
var
  CleanName: String;
begin
  CleanName := Trim(AName);
  if CleanName = '' then
    Exit(-1);
  Result := IndexOfLayer(CleanName);
  if Result < 0 then
  begin
    Result := Length(FLayers);
    SetLength(FLayers, Result + 1);
  end;
  FLayers[Result].Name := CleanName;
  FLayers[Result].ParentLayerName := Trim(AParentLayerName);
  FLayers[Result].DesiredState := ADesiredState;
  FLayers[Result].DebugColorRGB := ADebugColorRGB;
  FLayers[Result].Description := ADescription;
end;

function TCastleDataLayerManager.SetLayerState(const AName: String;
  const ADesiredState: TDataLayerRuntimeState): Boolean;
var
  Idx: Integer;
begin
  Idx := IndexOfLayer(AName);
  Result := Idx >= 0;
  if Result then
  begin
    FLayers[Idx].DesiredState := ADesiredState;
    FScenarioPreset := dlspCustom;
  end;
end;

function TCastleDataLayerManager.GetLayerDesiredState(
  const AName: String): TDataLayerRuntimeState;
var
  Idx: Integer;
begin
  Idx := IndexOfLayer(AName);
  if Idx >= 0 then
    Result := FLayers[Idx].DesiredState
  else
    Result := FDefaultUnknownLayerState;
end;

function TCastleDataLayerManager.EvaluateEffectiveLayerState(
  const AName: String): TDataLayerRuntimeState;
var
  CurName: String;
  Idx, GuardDepth: Integer;
  ParentEff: TDataLayerRuntimeState;
begin
  Idx := IndexOfLayer(AName);
  if Idx < 0 then
    Exit(FDefaultUnknownLayerState);

  Result := FLayers[Idx].DesiredState;
  CurName := FLayers[Idx].ParentLayerName;
  GuardDepth := 0;
  while (CurName <> '') and (GuardDepth < 16) do
  begin
    Inc(GuardDepth);
    Idx := IndexOfLayer(CurName);
    if Idx < 0 then
    begin
      if Ord(FDefaultUnknownLayerState) < Ord(Result) then
        Result := FDefaultUnknownLayerState;
      Break;
    end;
    ParentEff := FLayers[Idx].DesiredState;
    if Ord(ParentEff) < Ord(Result) then
      Result := ParentEff;
    CurName := FLayers[Idx].ParentLayerName;
  end;
end;

procedure TCastleDataLayerManager.SetScenarioPreset(
  const AValue: TDataLayerScenarioPreset);
begin
  if FScenarioPreset = AValue then Exit;
  if AValue = dlspCustom then
    FScenarioPreset := dlspCustom
  else
    ApplyScenarioPreset(AValue);
end;

procedure TCastleDataLayerManager.ApplyScenarioPreset(
  const APreset: TDataLayerScenarioPreset);
var
  CivicState, SiegeState, RuinsState: TDataLayerRuntimeState;
begin
  FScenarioPreset := APreset;
  if APreset = dlspCustom then
    Exit;

  case APreset of
    dlspPeacetimeTown:
      begin
        CivicState := dlrsActivated;
        SiegeState := dlrsUnloaded;
        RuinsState := dlrsUnloaded;
      end;
    dlspActiveSiegeBattle:
      begin
        CivicState := dlrsLoadedHidden;
        SiegeState := dlrsActivated;
        RuinsState := dlrsUnloaded;
      end;
    dlspPostWarRuins:
      begin
        CivicState := dlrsUnloaded;
        SiegeState := dlrsUnloaded;
        RuinsState := dlrsActivated;
      end;
  else
    CivicState := dlrsActivated;
    SiegeState := dlrsUnloaded;
    RuinsState := dlrsUnloaded;
  end;

  { Parent root layers control scenario macro-state; sub-layers remain
    DesiredState = Activated so toggling a parent cascades automatically }
  AddOrUpdateLayer('PeacetimeCivic', '', CivicState, Vector3(0.28, 0.82, 0.48),
    'Root civic life & peacetime props');
  AddOrUpdateLayer('MarketStalls', 'PeacetimeCivic', dlrsActivated, Vector3(0.36, 0.90, 0.58),
    'Town square merchant awnings & crates');

  AddOrUpdateLayer('CitySiege', '', SiegeState, Vector3(0.95, 0.42, 0.28),
    'Root active siege warfare layer');
  AddOrUpdateLayer('SiegeCatapults', 'CitySiege', dlrsActivated, Vector3(0.92, 0.56, 0.24),
    'Attacking trebuchets & siege engines');
  AddOrUpdateLayer('BreachFires', 'CitySiege', dlrsActivated, Vector3(1.00, 0.30, 0.22),
    'Wall breach smoke & fire braziers');

  AddOrUpdateLayer('PostWarRuins', '', RuinsState, Vector3(0.62, 0.66, 0.76),
    'Root post-battle aftermath layer');
  AddOrUpdateLayer('RubbleBarricades', 'PostWarRuins', dlrsActivated, Vector3(0.72, 0.74, 0.82),
    'Collapsed masonry & makeshift barricades');
end;

procedure TCastleDataLayerManager.ApplyDataLayersToWorld(
  const AWorldRoot: TCastleTransform);

  procedure ApplyRec(const T: TCastleTransform);
  var
    I: Integer;
    B: TCastleBehavior;
    TagBeh: TCastleDataLayerTagBehavior;
    EffState: TDataLayerRuntimeState;
    ShouldExist: Boolean;
  begin
    if T = nil then Exit;
    if (T <> AWorldRoot) and (csTransient in T.ComponentStyle) then
      Exit;

    for I := 0 to T.BehaviorsCount - 1 do
    begin
      B := T.Behaviors[I];
      if B is TCastleDataLayerTagBehavior then
      begin
        TagBeh := TCastleDataLayerTagBehavior(B);
        Inc(FTaggedActorCount);
        if IndexOfLayer(TagBeh.LayerName) < 0 then
          Inc(FMissingLayerTagCount);

        EffState := EvaluateEffectiveLayerState(TagBeh.LayerName);
        TagBeh.LastAppliedState := EffState;

        case EffState of
          dlrsActivated:    Inc(FActivatedActorCount);
          dlrsLoadedHidden: Inc(FLoadedHiddenActorCount);
          dlrsUnloaded:     Inc(FUnloadedActorCount);
        end;

        ShouldExist := (EffState = dlrsActivated);
        if TagBeh.InvertActivation then
          ShouldExist := not ShouldExist;
        T.Exists := ShouldExist;
        Break;
      end;
    end;

    for I := 0 to T.Count - 1 do
      ApplyRec(T[I]);
  end;

begin
  FTaggedActorCount := 0;
  FActivatedActorCount := 0;
  FLoadedHiddenActorCount := 0;
  FUnloadedActorCount := 0;
  FMissingLayerTagCount := 0;
  if AWorldRoot = nil then Exit;
  ApplyRec(AWorldRoot);
end;

function TCastleDataLayerManager.GetConfigJson: String;
var
  RootObj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('scenarioPreset', Ord(FScenarioPreset));
    Arr := TJSONArray.Create;
    RootObj.Add('layers', Arr);
    for I := 0 to High(FLayers) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('name', FLayers[I].Name);
      ItemObj.Add('parent', FLayers[I].ParentLayerName);
      ItemObj.Add('state', Ord(FLayers[I].DesiredState));
      ItemObj.Add('r', FLayers[I].DebugColorRGB.X);
      ItemObj.Add('g', FLayers[I].DebugColorRGB.Y);
      ItemObj.Add('b', FLayers[I].DebugColorRGB.Z);
      ItemObj.Add('desc', FLayers[I].Description);
      Arr.Add(ItemObj);
    end;
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleDataLayerManager.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I, PresetOrd, StateOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then Exit;
    RootObj := TJSONObject(Data);

    PresetOrd := RootObj.Get('scenarioPreset', Ord(FScenarioPreset));
    if (PresetOrd >= Ord(Low(TDataLayerScenarioPreset))) and
       (PresetOrd <= Ord(High(TDataLayerScenarioPreset))) then
      FScenarioPreset := TDataLayerScenarioPreset(PresetOrd);

    Arr := RootObj.Find('layers', jtArray) as TJSONArray;
    if Arr <> nil then
    begin
      SetLength(FLayers, Arr.Count);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then Continue;
        ItemObj := TJSONObject(Arr.Items[I]);
        FLayers[I].Name := ItemObj.Get('name', '');
        FLayers[I].ParentLayerName := ItemObj.Get('parent', '');
        StateOrd := EnsureRange(ItemObj.Get('state', 0),
          Ord(Low(TDataLayerRuntimeState)), Ord(High(TDataLayerRuntimeState)));
        FLayers[I].DesiredState := TDataLayerRuntimeState(StateOrd);
        FLayers[I].DebugColorRGB := Vector3(
          ItemObj.Get('r', 0.5),
          ItemObj.Get('g', 0.6),
          ItemObj.Get('b', 0.8));
        FLayers[I].Description := ItemObj.Get('desc', '');
      end;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleDataLayerManager.ExportMermaidHierarchy: String;
var
  SB: TStringBuilder;
  I: Integer;
  Eff: TDataLayerRuntimeState;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('flowchart TD');
    for I := 0 to High(FLayers) do
    begin
      Eff := EvaluateEffectiveLayerState(FLayers[I].Name);
      SB.AppendLine(Format('  %s["%s (%s)"]', [
        FLayers[I].Name, FLayers[I].Name, DataLayerStateToDisplayName(Eff)]));
      if FLayers[I].ParentLayerName <> '' then
        SB.AppendLine(Format('  %s --> %s', [FLayers[I].ParentLayerName, FLayers[I].Name]));
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

function TCastleDataLayerManager.DataLayerSummaryBadge: String;
begin
  Result := Format('[DataLayers:%d Act=%d/%d Hid=%d Unld=%d]', [
    Length(FLayers), FActivatedActorCount, FTaggedActorCount,
    FLoadedHiddenActorCount, FUnloadedActorCount
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleDataLayerManager,
    ['World & Streaming', 'World Partition Data Layer Manager (TCastleDataLayerManager)']);
  RegisterSerializableComponent(TCastleDataLayerTagBehavior,
    ['World & Streaming', 'Data Layer Actor Tag (TCastleDataLayerTagBehavior)']);

end.
