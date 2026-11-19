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

{ Context-driven multi-column Chooser Table evaluating hierarchical GameplayTag
  prefixes, numeric [Min..Max] parameter ranges, boolean state flags, priority
  tiers, and seeded weighted tie-breaking to resolve animation clips, audio cues,
  or VFX prefabs without hardcoded branching
  (Phase 347 — Unreal Engine 5.9 / 6.0+ UChooserTable Parity). }
unit CastleChooserTable;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils, fpjson, jsonparser,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Built-in multi-column Chooser Table presets. }
  TChooserPreset = (
    chpCustom,
    chpFootstepSurfaceStance,
    chpMeleeComboMontage,
    chpAiCombatBarkSelector
  );

  { Runtime context struct passed into TCastleChooserTable.EvaluateChooser. }
  TChooserContextQuery = record
    TagContextA: String;
    TagContextB: String;
    NumericParamA: Single;
    NumericParamB: Single;
    BoolFlag: Boolean;
    class function Create(const ATagA, ATagB: String;
      const ANumA: Single = 0.0; const ANumB: Single = 0.0;
      const ABool: Boolean = True): TChooserContextQuery; static;
  end;

  { Single rule row inside a Chooser Table. }
  TChooserRow = record
    RowId: String;
    ResultAssetUrl: String;
    ResultScale: Single;
    Priority: Integer;
    Weight: Single;
    RequiredTagA: String;
    RequiredTagB: String;
    MinNumericA: Single;
    MaxNumericA: Single;
    MinNumericB: Single;
    MaxNumericB: Single;
    CheckBoolFlag: Boolean;
    ExpectedBoolValue: Boolean;
  end;

  { Multi-column context-driven asset/montage/audio Chooser Table component. }
  TCastleChooserTable = class(TCastleTransform)
  private
    FPreset: TChooserPreset;
    FRandomSeed: Integer;
    FRngState: Cardinal;
    FRows: array of TChooserRow;

    FTotalEvaluations: Integer;
    FLastResolvedAsset: String;
    FLastMatchedRowId: String;
    FLastCandidateCount: Integer;

    procedure SetPreset(const AValue: TChooserPreset);
    procedure SetRandomSeed(const AValue: Integer);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ClearRows;
    function RowCount: Integer;
    function GetRow(const AIndex: Integer): TChooserRow;

    function AddChooserRow(const ARowId, AResultAssetUrl: String;
      const APriority: Integer; const AWeight: Single;
      const AReqTagA, AReqTagB: String;
      const AMinNumA, AMaxNumA: Single;
      const AMinNumB: Single = -1e6; const AMaxNumB: Single = 1e6;
      const ACheckBool: Boolean = False; const AExpectedBool: Boolean = True;
      const AResultScale: Single = 1.0): Integer;

    procedure ApplyPreset(const APreset: TChooserPreset);

    { Test whether row AIndex satisfies all column constraints of AQuery. }
    function RowMatchesQuery(const AIndex: Integer;
      const AQuery: TChooserContextQuery): Boolean;

    function CountMatchingRows(const AQuery: TChooserContextQuery): Integer;

    { Evaluate all rows against AQuery, filter to highest matching Priority tier,
      and break ties via seeded Weight probability. Returns ResultAssetUrl. }
    function EvaluateChooser(const AQuery: TChooserContextQuery;
      out AChosenRow: TChooserRow;
      const ASeedOverride: Integer = -1): String;

    function ValidateRows(const AWarnings: TStrings): Boolean;
    function ChooserSummaryBadge: String;

    property TotalEvaluations: Integer read FTotalEvaluations;
    property LastResolvedAsset: String read FLastResolvedAsset;
    property LastMatchedRowId: String read FLastMatchedRowId;
    property LastCandidateCount: Integer read FLastCandidateCount;
  published
    property Preset: TChooserPreset
      read FPreset write SetPreset default chpFootstepSurfaceStance;
    property RandomSeed: Integer
      read FRandomSeed write SetRandomSeed default 20260347;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function ChooserTagMatches(const ARequiredPattern, AActualTag: String): Boolean;
function ChooserPresetToDisplayName(const APreset: TChooserPreset): String;

implementation

uses
  CastleComponentSerialize;

function ChooserPresetToDisplayName(const APreset: TChooserPreset): String;
begin
  case APreset of
    chpCustom:                Result := 'Custom Chooser Table';
    chpFootstepSurfaceStance: Result := 'Footstep Surface x Stance x Speed';
    chpMeleeComboMontage:     Result := 'Melee Weapon x Combo x Airborne';
    chpAiCombatBarkSelector:  Result := 'AI Tactical Bark Weighted Selector';
  end;
end;

function ChooserTagMatches(const ARequiredPattern, AActualTag: String): Boolean;
var
  Req, Act: String;
begin
  Req := Trim(ARequiredPattern);
  if Req = '' then
    Exit(True);
  Act := Trim(AActualTag);
  if SameText(Req, Act) then
    Exit(True);
  { Dot-hierarchy prefix match: e.g. 'Surface.Stone' matches 'Surface.Stone.Wet' }
  if EndsText('.', Req) then
    Result := StartsText(Req, Act)
  else
    Result := StartsText(Req + '.', Act);
end;

{$PUSH}{$Q-}{$R-}
function NextChooserUnitFloat(var State: Cardinal): Single;
begin
  if State = 0 then
    State := 161803399;
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := (State and $FFFFFF) / 16777216.0;
end;
{$POP}

{ TChooserContextQuery ------------------------------------------------------- }

class function TChooserContextQuery.Create(const ATagA, ATagB: String;
  const ANumA, ANumB: Single; const ABool: Boolean): TChooserContextQuery;
begin
  Result.TagContextA := ATagA;
  Result.TagContextB := ATagB;
  Result.NumericParamA := ANumA;
  Result.NumericParamB := ANumB;
  Result.BoolFlag := ABool;
end;

{ TCastleChooserTable -------------------------------------------------------- }

constructor TCastleChooserTable.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRandomSeed := 20260347;
  FRngState := Cardinal(FRandomSeed);
  FPreset := chpCustom;
  ApplyPreset(chpFootstepSurfaceStance);
end;

destructor TCastleChooserTable.Destroy;
begin
  SetLength(FRows, 0);
  inherited Destroy;
end;

function TCastleChooserTable.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, ['Preset', 'RandomSeed', 'ConfigJson']) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleChooserTable.ClearRows;
begin
  SetLength(FRows, 0);
end;

function TCastleChooserTable.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TCastleChooserTable.GetRow(const AIndex: Integer): TChooserRow;
begin
  if (AIndex >= 0) and (AIndex <= High(FRows)) then
    Result := FRows[AIndex]
  else
    Result := Default(TChooserRow);
end;

function TCastleChooserTable.AddChooserRow(const ARowId, AResultAssetUrl: String;
  const APriority: Integer; const AWeight: Single;
  const AReqTagA, AReqTagB: String;
  const AMinNumA, AMaxNumA, AMinNumB, AMaxNumB: Single;
  const ACheckBool, AExpectedBool: Boolean;
  const AResultScale: Single): Integer;
begin
  Result := Length(FRows);
  SetLength(FRows, Result + 1);
  FRows[Result].RowId := ARowId;
  FRows[Result].ResultAssetUrl := AResultAssetUrl;
  FRows[Result].ResultScale := AResultScale;
  FRows[Result].Priority := APriority;
  FRows[Result].Weight := Max(0.001, AWeight);
  FRows[Result].RequiredTagA := Trim(AReqTagA);
  FRows[Result].RequiredTagB := Trim(AReqTagB);
  FRows[Result].MinNumericA := AMinNumA;
  FRows[Result].MaxNumericA := AMaxNumA;
  FRows[Result].MinNumericB := AMinNumB;
  FRows[Result].MaxNumericB := AMaxNumB;
  FRows[Result].CheckBoolFlag := ACheckBool;
  FRows[Result].ExpectedBoolValue := AExpectedBool;
end;

procedure TCastleChooserTable.SetPreset(const AValue: TChooserPreset);
begin
  if FPreset = AValue then Exit;
  if AValue = chpCustom then
    FPreset := chpCustom
  else
    ApplyPreset(AValue);
end;

procedure TCastleChooserTable.SetRandomSeed(const AValue: Integer);
begin
  FRandomSeed := AValue;
  FRngState := Cardinal(Abs(AValue) + 1);
end;

procedure TCastleChooserTable.ApplyPreset(const APreset: TChooserPreset);
begin
  FPreset := APreset;
  if APreset = chpCustom then
    Exit;

  ClearRows;
  case APreset of
    chpFootstepSurfaceStance:
      begin
        AddChooserRow('Stone_Sprint', 'castle-data:/sfx/footstep_stone_sprint.wav',
          20, 1.0, 'Surface.Stone', 'Stance.Sprint', 4.5, 20.0, -1e6, 1e6, True, True, 1.25);
        AddChooserRow('Stone_Walk', 'castle-data:/sfx/footstep_stone_walk.wav',
          15, 1.0, 'Surface.Stone', 'Stance.Walk', 0.5, 4.5, -1e6, 1e6, True, True, 1.00);
        AddChooserRow('Stone_Sneak', 'castle-data:/sfx/footstep_stone_scuff_quiet.wav',
          20, 1.0, 'Surface.Stone', 'Stance.Crouch', 0.1, 3.0, -1e6, 1e6, True, True, 0.35);
        AddChooserRow('Mud_Squelch_Fast', 'castle-data:/sfx/footstep_mud_splash.wav',
          20, 1.0, 'Surface.Mud', '', 3.5, 20.0, -1e6, 1e6, True, True, 1.15);
        AddChooserRow('Mud_Step_Slow', 'castle-data:/sfx/footstep_mud_squelch.wav',
          15, 1.0, 'Surface.Mud', '', 0.1, 3.5, -1e6, 1e6, True, True, 0.85);
        AddChooserRow('Water_Wade', 'castle-data:/sfx/footstep_water_slosh.wav',
          25, 1.0, 'Surface.Water', '', 0.1, 20.0, -1e6, 1e6, False, True, 1.10);
        AddChooserRow('Default_Fallback', 'castle-data:/sfx/footstep_generic_dirt.wav',
          0, 1.0, '', '', 0.0, 100.0);
      end;

    chpMeleeComboMontage:
      begin
        AddChooserRow('Greatsword_Plunge_Air', 'anim_greatsword_air_slam',
          30, 1.0, 'Weapon.Greatsword', '', 0.0, 10.0, -1e6, 1e6, True, False, 1.35);
        AddChooserRow('Greatsword_Finisher_3', 'anim_greatsword_spin_cleave',
          25, 1.0, 'Weapon.Greatsword', '', 2.5, 3.5, -1e6, 1e6, True, True, 1.20);
        AddChooserRow('Greatsword_Opener', 'anim_greatsword_slash_01',
          15, 1.0, 'Weapon.Greatsword', '', 0.5, 2.4, -1e6, 1e6, True, True, 1.00);
        AddChooserRow('DualDagger_Flurry', 'anim_dagger_rapid_flurry',
          20, 1.0, 'Weapon.Daggers', '', 0.5, 5.0, -1e6, 1e6, True, True, 1.15);
        AddChooserRow('Unarmed_Jab_Fallback', 'anim_unarmed_jab',
          0, 1.0, '', '', -10.0, 100.0);
      end;

    chpAiCombatBarkSelector:
      begin
        { Equal-priority weighted barks so squads vary callouts organically }
        AddChooserRow('Bark_Flank_A', 'castle-data:/vo/npc_flank_left.ogg',
          20, 3.0, 'Bark.Flank', 'Alert.Combat', 0.0, 50.0);
        AddChooserRow('Bark_Flank_B', 'castle-data:/vo/npc_pin_them_down.ogg',
          20, 2.0, 'Bark.Flank', 'Alert.Combat', 0.0, 50.0);
        AddChooserRow('Bark_Flank_C', 'castle-data:/vo/npc_circle_around.ogg',
          20, 1.0, 'Bark.Flank', 'Alert.Combat', 0.0, 50.0);
        AddChooserRow('Bark_LowHp_Retreat', 'castle-data:/vo/npc_need_medic.ogg',
          35, 1.0, '', 'Alert.Combat', 0.0, 50.0, 0.0, 0.25);
        AddChooserRow('Bark_Idle_Fallback', 'castle-data:/vo/npc_all_clear.ogg',
          0, 1.0, '', '', 0.0, 200.0);
      end;
  end;
end;

function TCastleChooserTable.RowMatchesQuery(const AIndex: Integer;
  const AQuery: TChooserContextQuery): Boolean;
var
  R: TChooserRow;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
    Exit(False);
  R := FRows[AIndex];
  if not ChooserTagMatches(R.RequiredTagA, AQuery.TagContextA) then
    Exit(False);
  if not ChooserTagMatches(R.RequiredTagB, AQuery.TagContextB) then
    Exit(False);
  if (AQuery.NumericParamA < R.MinNumericA) or (AQuery.NumericParamA > R.MaxNumericA) then
    Exit(False);
  if (AQuery.NumericParamB < R.MinNumericB) or (AQuery.NumericParamB > R.MaxNumericB) then
    Exit(False);
  if R.CheckBoolFlag and (AQuery.BoolFlag <> R.ExpectedBoolValue) then
    Exit(False);
  Result := True;
end;

function TCastleChooserTable.CountMatchingRows(
  const AQuery: TChooserContextQuery): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FRows) do
    if RowMatchesQuery(I, AQuery) then
      Inc(Result);
end;

function TCastleChooserTable.EvaluateChooser(
  const AQuery: TChooserContextQuery;
  out AChosenRow: TChooserRow;
  const ASeedOverride: Integer): String;
var
  I, BestPrio, CandCount, PickIdx: Integer;
  Cands: array of Integer;
  TotalWeight, Roll, Accum: Single;
  LocalSeed: Cardinal;
begin
  AChosenRow := Default(TChooserRow);
  Result := '';
  FLastCandidateCount := 0;
  BestPrio := Low(Integer);

  for I := 0 to High(FRows) do
    if RowMatchesQuery(I, AQuery) then
    begin
      Inc(FLastCandidateCount);
      if FRows[I].Priority > BestPrio then
        BestPrio := FRows[I].Priority;
    end;

  if FLastCandidateCount = 0 then
  begin
    FLastResolvedAsset := '';
    FLastMatchedRowId := '';
    Exit('');
  end;

  CandCount := 0;
  TotalWeight := 0.0;
  SetLength(Cands, Length(FRows));
  for I := 0 to High(FRows) do
    if RowMatchesQuery(I, AQuery) and (FRows[I].Priority = BestPrio) then
    begin
      Cands[CandCount] := I;
      TotalWeight := TotalWeight + Max(0.001, FRows[I].Weight);
      Inc(CandCount);
    end;

  PickIdx := Cands[0];
  if CandCount > 1 then
  begin
    if ASeedOverride >= 0 then
    begin
      LocalSeed := Cardinal(ASeedOverride + 1);
      Roll := NextChooserUnitFloat(LocalSeed) * TotalWeight;
    end else
      Roll := NextChooserUnitFloat(FRngState) * TotalWeight;

    Accum := 0.0;
    for I := 0 to CandCount - 1 do
    begin
      Accum := Accum + Max(0.001, FRows[Cands[I]].Weight);
      if Roll <= Accum then
      begin
        PickIdx := Cands[I];
        Break;
      end;
    end;
  end;

  AChosenRow := FRows[PickIdx];
  Result := AChosenRow.ResultAssetUrl;
  FLastResolvedAsset := Result;
  FLastMatchedRowId := AChosenRow.RowId;
  Inc(FTotalEvaluations);
end;

function TCastleChooserTable.ValidateRows(const AWarnings: TStrings): Boolean;
var
  I: Integer;
  HasWildcardFallback: Boolean;
begin
  Result := True;
  HasWildcardFallback := False;
  for I := 0 to High(FRows) do
  begin
    if Trim(FRows[I].ResultAssetUrl) = '' then
    begin
      Result := False;
      if AWarnings <> nil then
        AWarnings.Add(Format('Row "%s" has an empty ResultAssetUrl.', [FRows[I].RowId]));
    end;
    if (FRows[I].MinNumericA > FRows[I].MaxNumericA) or
       (FRows[I].MinNumericB > FRows[I].MaxNumericB) then
    begin
      Result := False;
      if AWarnings <> nil then
        AWarnings.Add(Format('Row "%s" has inverted numeric range (Min > Max).', [FRows[I].RowId]));
    end;
    if (FRows[I].RequiredTagA = '') and (FRows[I].RequiredTagB = '') and
       (not FRows[I].CheckBoolFlag) then
      HasWildcardFallback := True;
  end;
  if (Length(FRows) > 0) and (not HasWildcardFallback) then
  begin
    Result := False;
    if AWarnings <> nil then
      AWarnings.Add('Chooser table has no wildcard fallback row; unmatched queries will return empty.');
  end;
end;

function TCastleChooserTable.GetConfigJson: String;
var
  RootObj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    Arr := TJSONArray.Create;
    RootObj.Add('rows', Arr);
    for I := 0 to High(FRows) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('id', FRows[I].RowId);
      ItemObj.Add('asset', FRows[I].ResultAssetUrl);
      ItemObj.Add('scale', FRows[I].ResultScale);
      ItemObj.Add('prio', FRows[I].Priority);
      ItemObj.Add('weight', FRows[I].Weight);
      ItemObj.Add('tagA', FRows[I].RequiredTagA);
      ItemObj.Add('tagB', FRows[I].RequiredTagB);
      ItemObj.Add('minA', FRows[I].MinNumericA);
      ItemObj.Add('maxA', FRows[I].MaxNumericA);
      ItemObj.Add('minB', FRows[I].MinNumericB);
      ItemObj.Add('maxB', FRows[I].MaxNumericB);
      ItemObj.Add('chkBool', FRows[I].CheckBoolFlag);
      ItemObj.Add('expBool', FRows[I].ExpectedBoolValue);
      Arr.Add(ItemObj);
    end;
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleChooserTable.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I, PresetOrd: Integer;
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

    PresetOrd := RootObj.Get('preset', Ord(FPreset));
    if (PresetOrd >= Ord(Low(TChooserPreset))) and (PresetOrd <= Ord(High(TChooserPreset))) then
      FPreset := TChooserPreset(PresetOrd);

    Arr := RootObj.Find('rows', jtArray) as TJSONArray;
    if Arr <> nil then
    begin
      SetLength(FRows, Arr.Count);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then Continue;
        ItemObj := TJSONObject(Arr.Items[I]);
        FRows[I].RowId := ItemObj.Get('id', '');
        FRows[I].ResultAssetUrl := ItemObj.Get('asset', '');
        FRows[I].ResultScale := ItemObj.Get('scale', 1.0);
        FRows[I].Priority := ItemObj.Get('prio', 0);
        FRows[I].Weight := Max(0.001, ItemObj.Get('weight', 1.0));
        FRows[I].RequiredTagA := ItemObj.Get('tagA', '');
        FRows[I].RequiredTagB := ItemObj.Get('tagB', '');
        FRows[I].MinNumericA := ItemObj.Get('minA', -1e6);
        FRows[I].MaxNumericA := ItemObj.Get('maxA', 1e6);
        FRows[I].MinNumericB := ItemObj.Get('minB', -1e6);
        FRows[I].MaxNumericB := ItemObj.Get('maxB', 1e6);
        FRows[I].CheckBoolFlag := ItemObj.Get('chkBool', False);
        FRows[I].ExpectedBoolValue := ItemObj.Get('expBool', True);
      end;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleChooserTable.ChooserSummaryBadge: String;
begin
  Result := Format('[Chooser:%d rows Eval=#%d -> %s]', [
    Length(FRows), FTotalEvaluations,
    IfThen(FLastMatchedRowId <> '', FLastMatchedRowId, 'idle')
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleChooserTable,
    ['AI & Gameplay', 'Context-Driven Chooser Table (TCastleChooserTable)']);

end.
