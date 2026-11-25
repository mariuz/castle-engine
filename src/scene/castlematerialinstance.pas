{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Material Instance hierarchy & Material Parameter
  Collection runtime (@link(TCastleMaterialInstance),
  @link(TCastleMaterialParameterCollection)) supporting multi-level parent/child
  parameter inheritance, zero-recompile Scalar / Vector / Texture overrides,
  FStaticParameterSet Static Switch permutation tracking, Reset-to-Parent
  propagation, and scene-wide global MPC weather/look-dev uniform modulation
  (Phase 391 — UE 5.5 UMaterialInstanceConstant & UMaterialParameterCollection Parity). }
unit CastleMaterialInstance;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Parameter value kind in a @link(TCastleMaterialInstance) (UE 5.5 parity). }
  TMaterialParamKind = (
    mpkScalar,
    mpkVector,
    mpkTexture,
    mpkStaticSwitch
  );

  { Built-in global environment presets for @link(TCastleMaterialParameterCollection). }
  TMpcEnvironmentPreset = (
    mpcpCustom,
    mpcpClearNoonDry,
    mpcpMonsoonRainStorm,
    mpcpBlizzardSnowline,
    mpcpCyberpunkNeonNight
  );

  { Built-in Material Instance starter presets. }
  TMaterialInstancePreset = (
    mipCustom,
    mipMasterStandardPbr,
    mipWeatheredCastleStoneParent,
    mipMossyDungeonChild,
    mipSciFiTitaniumTrim
  );

  { Named global parameter entry in a @link(TCastleMaterialParameterCollection). }
  TMpcParameterEntry = record
    ParamName: String;
    IsVector: Boolean;
    ScalarValue: Single;
    VectorValue: TVector4;
  end;
  TMpcParameterEntryArray = array of TMpcParameterEntry;

  { Single overridable parameter slot on a @link(TCastleMaterialInstance). }
  TMaterialParameterSlot = record
    ParamName: String;
    GroupName: String;
    Kind: TMaterialParamKind;
    IsOverridden: Boolean;
    ScalarValue: Single;
    MinScalar: Single;
    MaxScalar: Single;
    VectorValue: TVector4;
    TextureSlot: String;
    SwitchValue: Boolean;
  end;
  TMaterialParameterSlotArray = array of TMaterialParameterSlot;

  { Final evaluated PBR surface state after Parent inheritance + MPC modulation. }
  TResolvedPbrSurface = record
    FinalBaseColor: TVector4;
    FinalMetallic: Single;
    FinalRoughness: Single;
    FinalClearCoat: Single;
    FinalNormalStrength: Single;
    FinalUVTiling: Single;
    FinalEmissiveRGB: TVector3;
    AlbedoTextureSlot: String;
    NormalTextureSlot: String;
    OrmTextureSlot: String;
    UseTriplanar: Boolean;
    UseWeatheringMpc: Boolean;
    UseEmissivePulse: Boolean;
    TwoSidedFoliage: Boolean;
    OverriddenCount: Integer;
    HierarchyDepth: Integer;
    StaticSwitchMaskHex: String;
    ShaderPermutationsCompiled: Integer;
  end;

  { Global Material Parameter Collection (UE 5.5 UMaterialParameterCollection parity)
    broadcasting global Scalar and Vector uniforms (e.g. GlobalWetness, SnowCoverage,
    WindStrength, SunTintRGBA) across all subscribed Material Instances in a scene. }
  TCastleMaterialParameterCollection = class(TCastleComponent)
  private
    FCollectionKey: String;
    FPreset: TMpcEnvironmentPreset;
    FEntries: TMpcParameterEntryArray;
    FRevision: Integer;

    procedure SetPreset(const AValue: TMpcEnvironmentPreset);
    function GetGlobalWetness: Single;
    procedure SetGlobalWetness(const AValue: Single);
    function GetSnowCoverage: Single;
    procedure SetSnowCoverage(const AValue: Single);
    function GetWindStrength: Single;
    procedure SetWindStrength(const AValue: Single);
    function GetEmissivePulsePhase: Single;
    procedure SetEmissivePulsePhase(const AValue: Single);
    function GetCollectionJson: String;
    procedure SetCollectionJson(const AValue: String);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ClearParameters;
    procedure ApplyPreset(const APreset: TMpcEnvironmentPreset);
    function FindParamIndex(const AParamName: String): Integer;
    procedure SetScalar(const AParamName: String; const AValue: Single);
    function GetScalar(const AParamName: String; const ADefault: Single = 0.0): Single;
    procedure SetVector(const AParamName: String; const AValue: TVector4);
    function GetVector(const AParamName: String; const ADefault: TVector4): TVector4;

    function MpcSummaryBadge: String;

    property Entries: TMpcParameterEntryArray read FEntries;
    property Revision: Integer read FRevision;
  published
    property CollectionKey: String read FCollectionKey write FCollectionKey;
    property GlobalWetness: Single read GetGlobalWetness write SetGlobalWetness {$ifdef FPC}default 0.0{$endif};
    property SnowCoverage: Single read GetSnowCoverage write SetSnowCoverage {$ifdef FPC}default 0.0{$endif};
    property WindStrength: Single read GetWindStrength write SetWindStrength {$ifdef FPC}default 0.25{$endif};
    property EmissivePulsePhase: Single read GetEmissivePulsePhase write SetEmissivePulsePhase {$ifdef FPC}default 0.5{$endif};
    property CollectionJson: String read GetCollectionJson write SetCollectionJson;
    property Preset: TMpcEnvironmentPreset
      read FPreset write SetPreset default mpcpClearNoonDry;
  end;

  { Hierarchical Material Instance behavior (UE 5.5 UMaterialInstanceConstant /
    UMaterialInstanceDynamic parity) supporting multi-level parent inheritance,
    per-parameter bOverride_* flags, zero-recompile scalar/vector/texture tuning,
    Static Switch permutation tracking, and live MPC environmental blending. }
  TCastleMaterialInstance = class(TCastleBehavior)
  private
    FMasterMaterialKey: String;
    FPreset: TMaterialInstancePreset;
    FParentInstance: TCastleMaterialInstance;
    FParameterCollection: TCastleMaterialParameterCollection;
    FSyncParentPrimitiveColor: Boolean;
    FSlots: TMaterialParameterSlotArray;
    FInstanceRevision: Integer;
    FShaderPermutationsCompiled: Integer;

    procedure SetPreset(const AValue: TMaterialInstancePreset);
    procedure SetParentInstance(const AValue: TCastleMaterialInstance);
    procedure SetParameterCollection(const AValue: TCastleMaterialParameterCollection);
    function GetOverridesJson: String;
    procedure SetOverridesJson(const AValue: String);

    procedure InitDefaultParameterCatalog;
    function WouldCreateParentCycle(const ACandidateParent: TCastleMaterialInstance): Boolean;
    function ComputeStaticSwitchMaskHex(const ASurface: TResolvedPbrSurface): String;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TMaterialInstancePreset);

    { Parameter Lookup & Zero-Recompile Override Setters }
    function FindSlotIndex(const AParamName: String): Integer;
    function IsParameterOverridden(const AParamName: String): Boolean;

    procedure SetScalarParameterValue(const AParamName: String; const AValue: Single);
    procedure SetVectorParameterValue(const AParamName: String; const AValue: TVector4);
    procedure SetTextureParameterValue(const AParamName, ASlotUrl: String);
    procedure SetStaticSwitchParameterValue(const AParamName: String; const AEnabled: Boolean);

    function ResetParameterToParent(const AParamName: String): Boolean;
    procedure ResetAllOverrides;
    function OverriddenParameterCount: Integer;
    function HierarchyChainString: String;

    { Effective Multi-Level Inheritance + MPC Evaluation }
    function GetEffectiveSlot(const AParamName: String; out OutSlot: TMaterialParameterSlot;
      out OutSourceName: String): Boolean;
    function EvaluateEffectiveSurface(
      const AOverrideMpc: TCastleMaterialParameterCollection = nil): TResolvedPbrSurface;
    procedure SyncToAttachedTransform(
      const AOverrideMpc: TCastleMaterialParameterCollection = nil);

    function MaterialInstanceSummaryBadge: String;

    property Slots: TMaterialParameterSlotArray read FSlots;
    property InstanceRevision: Integer read FInstanceRevision;
    property ShaderPermutationsCompiled: Integer read FShaderPermutationsCompiled;
  published
    property MasterMaterialKey: String read FMasterMaterialKey write FMasterMaterialKey;
    property ParentInstance: TCastleMaterialInstance
      read FParentInstance write SetParentInstance;
    property ParameterCollection: TCastleMaterialParameterCollection
      read FParameterCollection write SetParameterCollection;
    property SyncParentPrimitiveColor: Boolean
      read FSyncParentPrimitiveColor write FSyncParentPrimitiveColor default True;
    property OverridesJson: String read GetOverridesJson write SetOverridesJson;
    property Preset: TMaterialInstancePreset
      read FPreset write SetPreset default mipMasterStandardPbr;
  end;

implementation

uses
  fpjson, jsonparser;

function Clamp01(const V: Single): Single;
begin
  if V < 0.0 then Result := 0.0
  else if V > 1.0 then Result := 1.0
  else Result := V;
end;

function LerpSingle(const A, B, T: Single): Single;
begin
  Result := A + (B - A) * T;
end;

function LerpVec3(const A, B: TVector3; const T: Single): TVector3;
begin
  Result := Vector3(
    LerpSingle(A.X, B.X, T),
    LerpSingle(A.Y, B.Y, T),
    LerpSingle(A.Z, B.Z, T)
  );
end;

{ TCastleMaterialParameterCollection ----------------------------------------- }

constructor TCastleMaterialParameterCollection.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCollectionKey := 'MPC_GlobalEnvironment';
  FRevision := 1;
  ApplyPreset(mpcpClearNoonDry);
end;

function TCastleMaterialParameterCollection.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'CollectionKey') or
     (PropertyName = 'Preset') or
     (PropertyName = 'GlobalWetness') or
     (PropertyName = 'SnowCoverage') or
     (PropertyName = 'WindStrength') or
     (PropertyName = 'EmissivePulsePhase') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMaterialParameterCollection.ClearParameters;
begin
  FEntries := nil;
  Inc(FRevision);
end;

function TCastleMaterialParameterCollection.FindParamIndex(
  const AParamName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if SameText(FEntries[I].ParamName, AParamName) then
      Exit(I);
  Result := -1;
end;

procedure TCastleMaterialParameterCollection.SetScalar(
  const AParamName: String; const AValue: Single);
var
  Idx: Integer;
begin
  if Trim(AParamName) = '' then Exit;
  Idx := FindParamIndex(AParamName);
  if Idx < 0 then
  begin
    Idx := Length(FEntries);
    SetLength(FEntries, Idx + 1);
    FEntries[Idx].ParamName := Trim(AParamName);
    FEntries[Idx].VectorValue := Vector4(0, 0, 0, 1);
  end;
  FEntries[Idx].IsVector := False;
  FEntries[Idx].ScalarValue := AValue;
  Inc(FRevision);
end;

function TCastleMaterialParameterCollection.GetScalar(
  const AParamName: String; const ADefault: Single): Single;
var
  Idx: Integer;
begin
  Idx := FindParamIndex(AParamName);
  if (Idx >= 0) and (not FEntries[Idx].IsVector) then
    Result := FEntries[Idx].ScalarValue
  else
    Result := ADefault;
end;

procedure TCastleMaterialParameterCollection.SetVector(
  const AParamName: String; const AValue: TVector4);
var
  Idx: Integer;
begin
  if Trim(AParamName) = '' then Exit;
  Idx := FindParamIndex(AParamName);
  if Idx < 0 then
  begin
    Idx := Length(FEntries);
    SetLength(FEntries, Idx + 1);
    FEntries[Idx].ParamName := Trim(AParamName);
    FEntries[Idx].ScalarValue := 0.0;
  end;
  FEntries[Idx].IsVector := True;
  FEntries[Idx].VectorValue := AValue;
  Inc(FRevision);
end;

function TCastleMaterialParameterCollection.GetVector(
  const AParamName: String; const ADefault: TVector4): TVector4;
var
  Idx: Integer;
begin
  Idx := FindParamIndex(AParamName);
  if (Idx >= 0) and FEntries[Idx].IsVector then
    Result := FEntries[Idx].VectorValue
  else
    Result := ADefault;
end;

procedure TCastleMaterialParameterCollection.ApplyPreset(
  const APreset: TMpcEnvironmentPreset);
begin
  FPreset := APreset;
  if APreset = mpcpCustom then Exit;

  FEntries := nil;
  case APreset of
    mpcpMonsoonRainStorm:
      begin
        SetScalar('GlobalWetness', 0.92);
        SetScalar('SnowCoverage', 0.0);
        SetScalar('WindStrength', 0.80);
        SetScalar('EmissivePulsePhase', 0.65);
        SetVector('AtmosphereTint', Vector4(0.72, 0.80, 0.94, 1.0));
      end;
    mpcpBlizzardSnowline:
      begin
        SetScalar('GlobalWetness', 0.25);
        SetScalar('SnowCoverage', 0.88);
        SetScalar('WindStrength', 0.95);
        SetScalar('EmissivePulsePhase', 0.40);
        SetVector('AtmosphereTint', Vector4(0.90, 0.95, 1.00, 1.0));
      end;
    mpcpCyberpunkNeonNight:
      begin
        SetScalar('GlobalWetness', 0.78);
        SetScalar('SnowCoverage', 0.0);
        SetScalar('WindStrength', 0.35);
        SetScalar('EmissivePulsePhase', 1.00);
        SetVector('AtmosphereTint', Vector4(0.85, 0.55, 1.00, 1.0));
      end;
  else
    begin
      FPreset := mpcpClearNoonDry;
      SetScalar('GlobalWetness', 0.0);
      SetScalar('SnowCoverage', 0.0);
      SetScalar('WindStrength', 0.25);
      SetScalar('EmissivePulsePhase', 0.50);
      SetVector('AtmosphereTint', Vector4(1.00, 0.98, 0.94, 1.0));
    end;
  end;
end;

procedure TCastleMaterialParameterCollection.SetPreset(
  const AValue: TMpcEnvironmentPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

function TCastleMaterialParameterCollection.GetGlobalWetness: Single;
begin
  Result := GetScalar('GlobalWetness', 0.0);
end;

procedure TCastleMaterialParameterCollection.SetGlobalWetness(const AValue: Single);
begin
  FPreset := mpcpCustom;
  SetScalar('GlobalWetness', Clamp01(AValue));
end;

function TCastleMaterialParameterCollection.GetSnowCoverage: Single;
begin
  Result := GetScalar('SnowCoverage', 0.0);
end;

procedure TCastleMaterialParameterCollection.SetSnowCoverage(const AValue: Single);
begin
  FPreset := mpcpCustom;
  SetScalar('SnowCoverage', Clamp01(AValue));
end;

function TCastleMaterialParameterCollection.GetWindStrength: Single;
begin
  Result := GetScalar('WindStrength', 0.25);
end;

procedure TCastleMaterialParameterCollection.SetWindStrength(const AValue: Single);
begin
  FPreset := mpcpCustom;
  SetScalar('WindStrength', Clamp01(AValue));
end;

function TCastleMaterialParameterCollection.GetEmissivePulsePhase: Single;
begin
  Result := GetScalar('EmissivePulsePhase', 0.5);
end;

procedure TCastleMaterialParameterCollection.SetEmissivePulsePhase(const AValue: Single);
begin
  FPreset := mpcpCustom;
  SetScalar('EmissivePulsePhase', Clamp01(AValue));
end;

function TCastleMaterialParameterCollection.GetCollectionJson: String;
var
  Root, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('collectionKey', FCollectionKey);
    Arr := TJSONArray.Create;
    Root.Add('parameters', Arr);
    for I := 0 to High(FEntries) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('name', FEntries[I].ParamName);
      ItemObj.Add('isVector', FEntries[I].IsVector);
      ItemObj.Add('scalar', FEntries[I].ScalarValue);
      ItemObj.Add('vx', FEntries[I].VectorValue.X);
      ItemObj.Add('vy', FEntries[I].VectorValue.Y);
      ItemObj.Add('vz', FEntries[I].VectorValue.Z);
      ItemObj.Add('vw', FEntries[I].VectorValue.W);
      Arr.Add(ItemObj);
    end;
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleMaterialParameterCollection.SetCollectionJson(const AValue: String);
var
  Data: TJSONData;
  Root, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
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
    Root := TJSONObject(Data);
    FCollectionKey := Root.Get('collectionKey', FCollectionKey);
    Arr := Root.Find('parameters', jtArray) as TJSONArray;
    if Arr <> nil then
    begin
      SetLength(FEntries, Arr.Count);
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(Arr.Items[I]);
          FEntries[I].ParamName := ItemObj.Get('name', 'Param' + IntToStr(I));
          FEntries[I].IsVector := ItemObj.Get('isVector', False);
          FEntries[I].ScalarValue := ItemObj.Get('scalar', 0.0);
          FEntries[I].VectorValue := Vector4(
            ItemObj.Get('vx', 0.0),
            ItemObj.Get('vy', 0.0),
            ItemObj.Get('vz', 0.0),
            ItemObj.Get('vw', 1.0));
        end;
    end;
    Inc(FRevision);
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleMaterialParameterCollection.MpcSummaryBadge: String;
begin
  Result := Format('[MPC:%s Wet=%.2f Snow=%.2f Wind=%.2f Rev=%d]',
    [FCollectionKey, GlobalWetness, SnowCoverage, WindStrength, FRevision]);
end;

{ TCastleMaterialInstance ---------------------------------------------------- }

constructor TCastleMaterialInstance.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMasterMaterialKey := 'M_MasterPBR_Weathering';
  FSyncParentPrimitiveColor := True;
  FInstanceRevision := 1;
  FShaderPermutationsCompiled := 1;
  InitDefaultParameterCatalog;
  ApplyPreset(mipMasterStandardPbr);
end;

procedure TCastleMaterialInstance.Notification(
  AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
  begin
    if AComponent = FParentInstance then
      FParentInstance := nil;
    if AComponent = FParameterCollection then
      FParameterCollection := nil;
  end;
end;

function TCastleMaterialInstance.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'MasterMaterialKey') or
     (PropertyName = 'ParentInstance') or
     (PropertyName = 'ParameterCollection') or
     (PropertyName = 'SyncParentPrimitiveColor') or
     (PropertyName = 'Preset') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMaterialInstance.InitDefaultParameterCatalog;

  procedure AddScalar(const AName, AGroup: String; const ADef, AMin, AMax: Single);
  var
    N: Integer;
  begin
    N := Length(FSlots);
    SetLength(FSlots, N + 1);
    FSlots[N] := Default(TMaterialParameterSlot);
    FSlots[N].ParamName := AName;
    FSlots[N].GroupName := AGroup;
    FSlots[N].Kind := mpkScalar;
    FSlots[N].ScalarValue := ADef;
    FSlots[N].MinScalar := AMin;
    FSlots[N].MaxScalar := AMax;
  end;

  procedure AddVector(const AName, AGroup: String; const ADef: TVector4);
  var
    N: Integer;
  begin
    N := Length(FSlots);
    SetLength(FSlots, N + 1);
    FSlots[N] := Default(TMaterialParameterSlot);
    FSlots[N].ParamName := AName;
    FSlots[N].GroupName := AGroup;
    FSlots[N].Kind := mpkVector;
    FSlots[N].VectorValue := ADef;
  end;

  procedure AddTexture(const AName, AGroup, ADefSlot: String);
  var
    N: Integer;
  begin
    N := Length(FSlots);
    SetLength(FSlots, N + 1);
    FSlots[N] := Default(TMaterialParameterSlot);
    FSlots[N].ParamName := AName;
    FSlots[N].GroupName := AGroup;
    FSlots[N].Kind := mpkTexture;
    FSlots[N].TextureSlot := ADefSlot;
  end;

  procedure AddSwitch(const AName, AGroup: String; const ADef: Boolean);
  var
    N: Integer;
  begin
    N := Length(FSlots);
    SetLength(FSlots, N + 1);
    FSlots[N] := Default(TMaterialParameterSlot);
    FSlots[N].ParamName := AName;
    FSlots[N].GroupName := AGroup;
    FSlots[N].Kind := mpkStaticSwitch;
    FSlots[N].SwitchValue := ADef;
  end;

begin
  FSlots := nil;
  { Vector Parameters }
  AddVector('BaseColorTint', '01 - Albedo & Tint', Vector4(0.72, 0.72, 0.74, 1.0));
  AddVector('EmissiveColor', '04 - Emissive', Vector4(0.0, 0.65, 1.0, 1.0));
  AddVector('SnowAlbedoTint', '05 - MPC Weathering', Vector4(0.93, 0.96, 1.0, 1.0));

  { Scalar Parameters }
  AddScalar('Metallic', '02 - PBR Surface', 0.0, 0.0, 1.0);
  AddScalar('Roughness', '02 - PBR Surface', 0.55, 0.04, 1.0);
  AddScalar('ClearCoat', '02 - PBR Surface', 0.0, 0.0, 1.0);
  AddScalar('NormalStrength', '02 - PBR Surface', 1.0, 0.0, 2.5);
  AddScalar('UVTiling', '01 - Albedo & Tint', 1.0, 0.1, 16.0);
  AddScalar('EmissiveIntensity', '04 - Emissive', 0.0, 0.0, 20.0);
  AddScalar('MPC_WetnessInfluence', '05 - MPC Weathering', 1.0, 0.0, 1.0);
  AddScalar('MPC_SnowInfluence', '05 - MPC Weathering', 1.0, 0.0, 1.0);

  { Texture Slot Parameters }
  AddTexture('AlbedoTexture', '03 - Texture Slots', 'T_DefaultGrid_BaseColor.png');
  AddTexture('NormalTexture', '03 - Texture Slots', 'T_DefaultFlat_Normal.png');
  AddTexture('ORMTexture', '03 - Texture Slots', 'T_Default_ORM.png');

  { Static Switch Parameters (FStaticParameterSet) }
  AddSwitch('bUseWeatheringMPC', '06 - Static Switches', True);
  AddSwitch('bUseTriplanarProjection', '06 - Static Switches', False);
  AddSwitch('bUseEmissivePulse', '06 - Static Switches', False);
  AddSwitch('bTwoSidedFoliage', '06 - Static Switches', False);
end;

function TCastleMaterialInstance.WouldCreateParentCycle(
  const ACandidateParent: TCastleMaterialInstance): Boolean;
var
  Cur: TCastleMaterialInstance;
  Steps: Integer;
begin
  Result := False;
  Cur := ACandidateParent;
  Steps := 0;
  while (Cur <> nil) and (Steps < 32) do
  begin
    if Cur = Self then Exit(True);
    Cur := Cur.ParentInstance;
    Inc(Steps);
  end;
end;

procedure TCastleMaterialInstance.SetParentInstance(
  const AValue: TCastleMaterialInstance);
begin
  if FParentInstance = AValue then Exit;
  if WouldCreateParentCycle(AValue) then Exit;

  if FParentInstance <> nil then
    FParentInstance.RemoveFreeNotification(Self);
  FParentInstance := AValue;
  if FParentInstance <> nil then
    FParentInstance.FreeNotification(Self);

  Inc(FInstanceRevision);
  SyncToAttachedTransform;
end;

procedure TCastleMaterialInstance.SetParameterCollection(
  const AValue: TCastleMaterialParameterCollection);
begin
  if FParameterCollection = AValue then Exit;
  if FParameterCollection <> nil then
    FParameterCollection.RemoveFreeNotification(Self);
  FParameterCollection := AValue;
  if FParameterCollection <> nil then
    FParameterCollection.FreeNotification(Self);

  Inc(FInstanceRevision);
  SyncToAttachedTransform;
end;

function TCastleMaterialInstance.FindSlotIndex(const AParamName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSlots) do
    if SameText(FSlots[I].ParamName, AParamName) then
      Exit(I);
  Result := -1;
end;

function TCastleMaterialInstance.IsParameterOverridden(const AParamName: String): Boolean;
var
  Idx: Integer;
begin
  Idx := FindSlotIndex(AParamName);
  Result := (Idx >= 0) and FSlots[Idx].IsOverridden;
end;

procedure TCastleMaterialInstance.SetScalarParameterValue(
  const AParamName: String; const AValue: Single);
var
  Idx: Integer;
begin
  Idx := FindSlotIndex(AParamName);
  if (Idx < 0) or (FSlots[Idx].Kind <> mpkScalar) then Exit;
  FSlots[Idx].ScalarValue := EnsureRange(AValue, FSlots[Idx].MinScalar, FSlots[Idx].MaxScalar);
  FSlots[Idx].IsOverridden := True;
  { Dynamic/Constant scalar overrides NEVER trigger shader permutation recompilation! }
  Inc(FInstanceRevision);
  SyncToAttachedTransform;
end;

procedure TCastleMaterialInstance.SetVectorParameterValue(
  const AParamName: String; const AValue: TVector4);
var
  Idx: Integer;
begin
  Idx := FindSlotIndex(AParamName);
  if (Idx < 0) or (FSlots[Idx].Kind <> mpkVector) then Exit;
  FSlots[Idx].VectorValue := AValue;
  FSlots[Idx].IsOverridden := True;
  Inc(FInstanceRevision);
  SyncToAttachedTransform;
end;

procedure TCastleMaterialInstance.SetTextureParameterValue(
  const AParamName, ASlotUrl: String);
var
  Idx: Integer;
begin
  Idx := FindSlotIndex(AParamName);
  if (Idx < 0) or (FSlots[Idx].Kind <> mpkTexture) then Exit;
  FSlots[Idx].TextureSlot := Trim(ASlotUrl);
  FSlots[Idx].IsOverridden := True;
  Inc(FInstanceRevision);
  SyncToAttachedTransform;
end;

procedure TCastleMaterialInstance.SetStaticSwitchParameterValue(
  const AParamName: String; const AEnabled: Boolean);
var
  Idx: Integer;
  WasEffective: TMaterialParameterSlot;
  Src: String;
  ChangedEffective: Boolean;
begin
  Idx := FindSlotIndex(AParamName);
  if (Idx < 0) or (FSlots[Idx].Kind <> mpkStaticSwitch) then Exit;

  ChangedEffective := True;
  if GetEffectiveSlot(AParamName, WasEffective, Src) then
    ChangedEffective := (WasEffective.SwitchValue <> AEnabled);

  FSlots[Idx].SwitchValue := AEnabled;
  FSlots[Idx].IsOverridden := True;
  Inc(FInstanceRevision);
  { Only Static Switch toggles compile a new FStaticParameterSet shader permutation }
  if ChangedEffective then
    Inc(FShaderPermutationsCompiled);
  SyncToAttachedTransform;
end;

function TCastleMaterialInstance.ResetParameterToParent(
  const AParamName: String): Boolean;
var
  Idx: Integer;
  WasSwitch: Boolean;
begin
  Idx := FindSlotIndex(AParamName);
  if (Idx < 0) or (not FSlots[Idx].IsOverridden) then
    Exit(False);

  WasSwitch := FSlots[Idx].Kind = mpkStaticSwitch;
  FSlots[Idx].IsOverridden := False;
  Inc(FInstanceRevision);
  if WasSwitch then
    Inc(FShaderPermutationsCompiled);
  SyncToAttachedTransform;
  Result := True;
end;

procedure TCastleMaterialInstance.ResetAllOverrides;
var
  I: Integer;
begin
  for I := 0 to High(FSlots) do
    FSlots[I].IsOverridden := False;
  Inc(FInstanceRevision);
  SyncToAttachedTransform;
end;

function TCastleMaterialInstance.OverriddenParameterCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSlots) do
    if FSlots[I].IsOverridden then
      Inc(Result);
end;

function TCastleMaterialInstance.HierarchyChainString: String;
var
  Cur: TCastleMaterialInstance;
  Steps: Integer;
  RootKey, NodeLabel: String;
begin
  Result := '';
  Cur := Self;
  RootKey := FMasterMaterialKey;
  Steps := 0;
  while (Cur <> nil) and (Steps < 16) do
  begin
    NodeLabel := Cur.Name;
    if NodeLabel = '' then NodeLabel := 'MI_Unnamed';
    if Result = '' then
      Result := NodeLabel
    else
      Result := NodeLabel + ' -> ' + Result;
    RootKey := Cur.MasterMaterialKey;
    Cur := Cur.ParentInstance;
    Inc(Steps);
  end;
  if RootKey = '' then RootKey := 'M_MasterPBR';
  Result := RootKey + ' -> ' + Result;
end;

procedure TCastleMaterialInstance.ApplyPreset(const APreset: TMaterialInstancePreset);
begin
  FPreset := APreset;
  if APreset = mipCustom then Exit;

  InitDefaultParameterCatalog;
  case APreset of
    mipWeatheredCastleStoneParent:
      begin
        FMasterMaterialKey := 'M_MasterPBR_Weathering';
        SetVectorParameterValue('BaseColorTint', Vector4(0.48, 0.46, 0.43, 1.0));
        SetScalarParameterValue('Roughness', 0.78);
        SetScalarParameterValue('Metallic', 0.0);
        SetScalarParameterValue('NormalStrength', 1.35);
        SetScalarParameterValue('UVTiling', 3.0);
        SetTextureParameterValue('AlbedoTexture', 'T_CastleAshlarStone_D.png');
        SetTextureParameterValue('NormalTexture', 'T_CastleAshlarStone_N.png');
        SetStaticSwitchParameterValue('bUseWeatheringMPC', True);
        SetStaticSwitchParameterValue('bUseTriplanarProjection', True);
      end;
    mipMossyDungeonChild:
      begin
        FMasterMaterialKey := 'M_MasterPBR_Weathering';
        { Child overrides only Albedo tint, Roughness, and Wetness influence;
          inherits UVTiling=3.0, NormalTexture, and bUseTriplanarProjection from Parent! }
        SetVectorParameterValue('BaseColorTint', Vector4(0.28, 0.44, 0.27, 1.0));
        SetScalarParameterValue('Roughness', 0.64);
        SetScalarParameterValue('MPC_WetnessInfluence', 1.0);
        SetScalarParameterValue('MPC_SnowInfluence', 0.35);
      end;
    mipSciFiTitaniumTrim:
      begin
        FMasterMaterialKey := 'M_MasterPBR_HardSurface';
        SetVectorParameterValue('BaseColorTint', Vector4(0.62, 0.66, 0.72, 1.0));
        SetScalarParameterValue('Metallic', 0.92);
        SetScalarParameterValue('Roughness', 0.24);
        SetScalarParameterValue('ClearCoat', 0.35);
        SetVectorParameterValue('EmissiveColor', Vector4(0.10, 0.78, 1.00, 1.0));
        SetScalarParameterValue('EmissiveIntensity', 3.5);
        SetTextureParameterValue('AlbedoTexture', 'T_SciFiHullTrim_D.png');
        SetStaticSwitchParameterValue('bUseEmissivePulse', True);
      end;
  else
    begin
      FPreset := mipMasterStandardPbr;
      FMasterMaterialKey := 'M_MasterPBR_Weathering';
    end;
  end;
  FShaderPermutationsCompiled := 1;
  SyncToAttachedTransform;
end;

procedure TCastleMaterialInstance.SetPreset(const AValue: TMaterialInstancePreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

function TCastleMaterialInstance.GetEffectiveSlot(const AParamName: String;
  out OutSlot: TMaterialParameterSlot; out OutSourceName: String): Boolean;
var
  Cur, LastValid: TCastleMaterialInstance;
  Idx, Steps: Integer;
begin
  Result := False;
  OutSlot := Default(TMaterialParameterSlot);
  OutSourceName := '';

  Cur := Self;
  LastValid := Self;
  Steps := 0;
  while (Cur <> nil) and (Steps < 16) do
  begin
    Idx := Cur.FindSlotIndex(AParamName);
    if (Idx >= 0) and Cur.FSlots[Idx].IsOverridden then
    begin
      OutSlot := Cur.FSlots[Idx];
      if Cur = Self then
        OutSourceName := 'Self (Overridden)'
      else if Cur.Name <> '' then
        OutSourceName := 'Parent (' + Cur.Name + ')'
      else
        OutSourceName := 'Parent Instance';
      Exit(True);
    end;
    LastValid := Cur;
    Cur := Cur.ParentInstance;
    Inc(Steps);
  end;

  { Fallback to root Master Material default value }
  Idx := LastValid.FindSlotIndex(AParamName);
  if Idx >= 0 then
  begin
    OutSlot := LastValid.FSlots[Idx];
    OutSourceName := 'Master (' + LastValid.MasterMaterialKey + ')';
    Result := True;
  end;
end;

function TCastleMaterialInstance.ComputeStaticSwitchMaskHex(
  const ASurface: TResolvedPbrSurface): String;
var
  Mask: Cardinal;
begin
  Mask := 0;
  if ASurface.UseWeatheringMpc then Mask := Mask or 1;
  if ASurface.UseTriplanar then Mask := Mask or 2;
  if ASurface.UseEmissivePulse then Mask := Mask or 4;
  if ASurface.TwoSidedFoliage then Mask := Mask or 8;
  Result := '0x' + IntToHex(Mask, 2);
end;

function TCastleMaterialInstance.EvaluateEffectiveSurface(
  const AOverrideMpc: TCastleMaterialParameterCollection): TResolvedPbrSurface;

  function EffScalar(const N: String; const Def: Single): Single;
  var
    S: TMaterialParameterSlot;
    Src: String;
  begin
    if GetEffectiveSlot(N, S, Src) then
      Result := S.ScalarValue
    else
      Result := Def;
  end;

  function EffVec(const N: String; const Def: TVector4): TVector4;
  var
    S: TMaterialParameterSlot;
    Src: String;
  begin
    if GetEffectiveSlot(N, S, Src) then
      Result := S.VectorValue
    else
      Result := Def;
  end;

  function EffTex(const N, Def: String): String;
  var
    S: TMaterialParameterSlot;
    Src: String;
  begin
    if GetEffectiveSlot(N, S, Src) then
      Result := S.TextureSlot
    else
      Result := Def;
  end;

  function EffSwitch(const N: String; const Def: Boolean): Boolean;
  var
    S: TMaterialParameterSlot;
    Src: String;
  begin
    if GetEffectiveSlot(N, S, Src) then
      Result := S.SwitchValue
    else
      Result := Def;
  end;

var
  ActiveMpc: TCastleMaterialParameterCollection;
  BaseCol, SnowCol, EmissCol: TVector4;
  BaseRGB: TVector3;
  WetInf, SnowInf, WetAmount, SnowAmount, Porosity, PulseMul: Single;
  Cur: TCastleMaterialInstance;
begin
  Result := Default(TResolvedPbrSurface);

  BaseCol := EffVec('BaseColorTint', Vector4(0.72, 0.72, 0.74, 1.0));
  EmissCol := EffVec('EmissiveColor', Vector4(0.0, 0.65, 1.0, 1.0));
  SnowCol := EffVec('SnowAlbedoTint', Vector4(0.93, 0.96, 1.0, 1.0));

  Result.FinalMetallic := Clamp01(EffScalar('Metallic', 0.0));
  Result.FinalRoughness := Clamp01(EffScalar('Roughness', 0.55));
  Result.FinalClearCoat := Clamp01(EffScalar('ClearCoat', 0.0));
  Result.FinalNormalStrength := EffScalar('NormalStrength', 1.0);
  Result.FinalUVTiling := EffScalar('UVTiling', 1.0);

  Result.AlbedoTextureSlot := EffTex('AlbedoTexture', 'T_DefaultGrid_BaseColor.png');
  Result.NormalTextureSlot := EffTex('NormalTexture', 'T_DefaultFlat_Normal.png');
  Result.OrmTextureSlot := EffTex('ORMTexture', 'T_Default_ORM.png');

  Result.UseWeatheringMpc := EffSwitch('bUseWeatheringMPC', True);
  Result.UseTriplanar := EffSwitch('bUseTriplanarProjection', False);
  Result.UseEmissivePulse := EffSwitch('bUseEmissivePulse', False);
  Result.TwoSidedFoliage := EffSwitch('bTwoSidedFoliage', False);

  WetInf := Clamp01(EffScalar('MPC_WetnessInfluence', 1.0));
  SnowInf := Clamp01(EffScalar('MPC_SnowInfluence', 1.0));

  BaseRGB := Vector3(BaseCol.X, BaseCol.Y, BaseCol.Z);

  ActiveMpc := AOverrideMpc;
  if ActiveMpc = nil then
    ActiveMpc := FParameterCollection;

  { Apply global MPC Weathering (Snow accumulation + Porous Dielectric Rain Darkening) }
  if Result.UseWeatheringMpc and (ActiveMpc <> nil) then
  begin
    SnowAmount := Clamp01(ActiveMpc.SnowCoverage * SnowInf);
    WetAmount := Clamp01(ActiveMpc.GlobalWetness * WetInf * (1.0 - 0.75 * SnowAmount));

    { 1. Porous non-metallic dielectric darkening & mirror puddle smoothing when wet }
    if WetAmount > 0.001 then
    begin
      Porosity := (1.0 - Result.FinalMetallic) * Clamp01(Result.FinalRoughness);
      BaseRGB := BaseRGB * LerpSingle(1.0, 0.56, Porosity * WetAmount);
      Result.FinalRoughness := LerpSingle(Result.FinalRoughness, 0.08, WetAmount * 0.88);
      Result.FinalClearCoat := Max(Result.FinalClearCoat, WetAmount * 0.65);
    end;

    { 2. Fresh snow blanket albedo & frosty micro-roughness }
    if SnowAmount > 0.001 then
    begin
      BaseRGB := LerpVec3(BaseRGB, Vector3(SnowCol.X, SnowCol.Y, SnowCol.Z), SnowAmount);
      Result.FinalMetallic := LerpSingle(Result.FinalMetallic, 0.0, SnowAmount);
      Result.FinalRoughness := LerpSingle(Result.FinalRoughness, 0.82, SnowAmount);
    end;
  end;

  PulseMul := EffScalar('EmissiveIntensity', 0.0);
  if Result.UseEmissivePulse and (ActiveMpc <> nil) then
    PulseMul := PulseMul * (0.35 + 0.65 * ActiveMpc.EmissivePulsePhase);

  Result.FinalBaseColor := Vector4(
    Clamp01(BaseRGB.X), Clamp01(BaseRGB.Y), Clamp01(BaseRGB.Z), BaseCol.W);
  Result.FinalEmissiveRGB := Vector3(
    EmissCol.X * PulseMul, EmissCol.Y * PulseMul, EmissCol.Z * PulseMul);

  Result.OverriddenCount := OverriddenParameterCount;
  Result.HierarchyDepth := 0;
  Cur := FParentInstance;
  while (Cur <> nil) and (Result.HierarchyDepth < 16) do
  begin
    Inc(Result.HierarchyDepth);
    Cur := Cur.ParentInstance;
  end;
  Result.StaticSwitchMaskHex := ComputeStaticSwitchMaskHex(Result);
  Result.ShaderPermutationsCompiled := FShaderPermutationsCompiled;
end;

procedure TCastleMaterialInstance.SyncToAttachedTransform(
  const AOverrideMpc: TCastleMaterialParameterCollection);
var
  Surf: TResolvedPbrSurface;
begin
  if (not FSyncParentPrimitiveColor) or (Parent = nil) then Exit;
  Surf := EvaluateEffectiveSurface(AOverrideMpc);
  if Parent is TCastleBox then
    TCastleBox(Parent).Color := Surf.FinalBaseColor
  else if Parent is TCastleSphere then
    TCastleSphere(Parent).Color := Surf.FinalBaseColor;
end;

function TCastleMaterialInstance.GetOverridesJson: String;
var
  Root, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('masterMaterialKey', FMasterMaterialKey);
    Arr := TJSONArray.Create;
    Root.Add('overrides', Arr);
    for I := 0 to High(FSlots) do
      if FSlots[I].IsOverridden then
      begin
        ItemObj := TJSONObject.Create;
        ItemObj.Add('name', FSlots[I].ParamName);
        ItemObj.Add('kind', Ord(FSlots[I].Kind));
        ItemObj.Add('scalar', FSlots[I].ScalarValue);
        ItemObj.Add('vx', FSlots[I].VectorValue.X);
        ItemObj.Add('vy', FSlots[I].VectorValue.Y);
        ItemObj.Add('vz', FSlots[I].VectorValue.Z);
        ItemObj.Add('vw', FSlots[I].VectorValue.W);
        ItemObj.Add('tex', FSlots[I].TextureSlot);
        ItemObj.Add('sw', FSlots[I].SwitchValue);
        Arr.Add(ItemObj);
      end;
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleMaterialInstance.SetOverridesJson(const AValue: String);
var
  Data: TJSONData;
  Root, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I, Idx: Integer;
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
    Root := TJSONObject(Data);
    FMasterMaterialKey := Root.Get('masterMaterialKey', FMasterMaterialKey);
    ResetAllOverrides;
    Arr := Root.Find('overrides', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(Arr.Items[I]);
          Idx := FindSlotIndex(ItemObj.Get('name', ''));
          if Idx >= 0 then
          begin
            FSlots[Idx].IsOverridden := True;
            FSlots[Idx].ScalarValue := ItemObj.Get('scalar', FSlots[Idx].ScalarValue);
            FSlots[Idx].VectorValue := Vector4(
              ItemObj.Get('vx', FSlots[Idx].VectorValue.X),
              ItemObj.Get('vy', FSlots[Idx].VectorValue.Y),
              ItemObj.Get('vz', FSlots[Idx].VectorValue.Z),
              ItemObj.Get('vw', FSlots[Idx].VectorValue.W));
            FSlots[Idx].TextureSlot := ItemObj.Get('tex', FSlots[Idx].TextureSlot);
            FSlots[Idx].SwitchValue := ItemObj.Get('sw', FSlots[Idx].SwitchValue);
          end;
        end;
    Inc(FInstanceRevision);
    SyncToAttachedTransform;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleMaterialInstance.MaterialInstanceSummaryBadge: String;
var
  Surf: TResolvedPbrSurface;
begin
  Surf := EvaluateEffectiveSurface;
  Result := Format('[MI:%s Ov=%d Depth=%d R=%.2f M=%.2f Perm=%s]',
    [FMasterMaterialKey, Surf.OverriddenCount, Surf.HierarchyDepth,
     Surf.FinalRoughness, Surf.FinalMetallic, Surf.StaticSwitchMaskHex]);
end;

initialization
  RegisterSerializableComponent(TCastleMaterialParameterCollection,
    ['Materials & VFX', 'Material Parameter Collection (MPC)']);
  RegisterSerializableComponent(TCastleMaterialInstance,
    ['Materials & VFX', 'Material Instance (Parent/Child Overrides)']);
end.
