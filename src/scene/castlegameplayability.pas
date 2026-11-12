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

{ Gameplay Ability, Cooldown, Stacking Status Buff/Debuff & Derived Attribute
  System (@link(TCastleAbilitySystemBehavior))
  (Phase 310 — UE 6.0+ Gameplay Ability System / GAS Parity). }
unit CastleGameplayAbility;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Generics.Collections,
  CastleVectors, CastleClassUtils, CastleTransform, CastleBehaviors;

type
  { Aggregator operator matching Unreal Engine GAS UGameplayEffect modifiers. }
  TGasModifierOp = (
    gmoFlatAdd,
    gmoPercentAdd,
    gmoMultiply
  );

  { Built-in RPG / action character GAS loadouts. }
  TGasArchetypePreset = (
    gapCustom,
    gapArcaneMage,
    gapVanguardPaladin,
    gapShadowRanger
  );

  { Attribute definition with BaseValue, bounds, and optional MaxAttrName cap. }
  TGasAttributeDef = record
    AttrName: String;
    BaseValue: Single;
    MinValue: Single;
    MaxValue: Single;
    MaxAttrName: String;
    class function CreateSimple(const AName: String;
      const ABase, AMin, AMax: Single; const AMaxAttr: String = ''): TGasAttributeDef; static;
  end;

  { Status effect / buff / debuff / instant modifier definition. }
  TGasEffectDef = record
    EffectId: String;
    EffectTag: String;
    GrantedTag: String;
    GrantsImmunityPattern: String;
    DurationSec: Single;
    MaxStacks: Integer;
    TargetAttrName: String;
    ModOp: TGasModifierOp;
    ModMagnitude: Single;
    PeriodSec: Single;
    PeriodicAttrName: String;
    PeriodicDeltaPerStack: Single;
    class function CreateDefault(const AId: String): TGasEffectDef; static;
  end;

  { Runtime active durational status effect instance on an entity. }
  TGasActiveEffect = record
    Def: TGasEffectDef;
    RemainingSec: Single;
    PeriodAccumSec: Single;
    CurrentStacks: Integer;
  end;

  { Activatable gameplay ability with resource cost, cooldown, tag gates & target/self effect. }
  TGasAbilityDef = record
    AbilityId: String;
    CostAttrName: String;
    CostAmount: Single;
    CooldownSec: Single;
    RemainingCooldownSec: Single;
    RequiredTagPattern: String;
    BlockedByTagPattern: String;
    SelfEffectId: String;
    TargetEffectId: String;
    DirectTargetAttr: String;
    DirectTargetDelta: Single;
    class function CreateDefault(const AId: String): TGasAbilityDef; static;
  end;

  TGasAttributeList = {$ifdef FPC}specialize{$endif} TList<TGasAttributeDef>;
  TGasEffectDefList = {$ifdef FPC}specialize{$endif} TList<TGasEffectDef>;
  TGasActiveEffectList = {$ifdef FPC}specialize{$endif} TList<TGasActiveEffect>;
  TGasAbilityList = {$ifdef FPC}specialize{$endif} TList<TGasAbilityDef>;

  { Composable Gameplay Ability System (GAS) behavior attachable to any
    @link(TCastleTransform). Evaluates UE-style derived attributes
    (@code((Base + FlatAdd) * (1 + PercentAdd) * Multiply)), manages cooldowns
    and mana/stamina costs, ticks stacking periodic DoT/HoT status effects,
    and enforces hierarchical dot-boundary Gameplay Tag requirements & immunities. }
  TCastleAbilitySystemBehavior = class(TCastleBehavior)
  strict private
    FPreset: TGasArchetypePreset;
    FAttributes: TGasAttributeList;
    FEffectDefs: TGasEffectDefList;
    FActiveEffects: TGasActiveEffectList;
    FAbilities: TGasAbilityList;
    FOwnedTags: TStringList;
    FSyncWithCastleLiving: Boolean;
    FSimulateInEditor: Boolean;

    procedure SetPreset(const Value: TGasArchetypePreset);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    function FindAttributeIndex(const AName: String): Integer;
    function FindEffectDefIndex(const AId: String): Integer;
    function FindActiveEffectIndex(const AId: String): Integer;
    function FindAbilityIndex(const AId: String): Integer;
    function EffectiveMaxForAttribute(const ADef: TGasAttributeDef; const Depth: Integer = 0): Single;
    function InternalEvaluateAttribute(const AName: String; const Depth: Integer): Single;
    procedure ClampBaseAttribute(const AIdx: Integer);
    procedure PurgeImmunityMatchedEffects(const APattern: String);
    procedure SyncLivingIfNeeded;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TGasArchetypePreset);

    { Attribute accessors & mutators }
    property Attributes: TGasAttributeList read FAttributes;
    procedure DefineOrSetAttribute(const ADef: TGasAttributeDef);
    function HasAttribute(const AName: String): Boolean;
    function GetBaseValue(const AName: String): Single;
    procedure SetBaseValue(const AName: String; const AValue: Single);
    procedure ModifyBaseValue(const AName: String; const ADelta: Single);
    function GetCurrentValue(const AName: String): Single;

    { Gameplay Tag queries (includes owned tags + tags granted by active effects) }
    property OwnedTags: TStringList read FOwnedTags;
    procedure GrantTag(const ATag: String);
    procedure RevokeTag(const ATag: String);
    function HasMatchingTag(const APattern: String): Boolean;
    function IsImmuneToTag(const AEffectTag: String): Boolean;

    { Status effect registration & application }
    property EffectDefs: TGasEffectDefList read FEffectDefs;
    property ActiveEffects: TGasActiveEffectList read FActiveEffects;
    procedure RegisterEffectDef(const ADef: TGasEffectDef);
    function ApplyEffectById(const AEffectId: String; out OutReason: String): Boolean; overload;
    function ApplyEffectById(const AEffectId: String): Boolean; overload;
    function ApplyEffectDef(const ADef: TGasEffectDef; out OutReason: String): Boolean;
    function ActiveStacksOf(const AEffectId: String): Integer;
    procedure ClearActiveEffects;

    { Ability registration, cooldown queries & activation }
    property Abilities: TGasAbilityList read FAbilities;
    procedure RegisterAbility(const ADef: TGasAbilityDef);
    function CanActivateAbility(const AAbilityId: String; out OutReason: String): Boolean;
    function TryActivateAbility(const AAbilityId: String;
      const ATarget: TCastleAbilitySystemBehavior;
      out OutReason: String): Boolean; overload;
    function TryActivateAbility(const AAbilityId: String;
      const ATarget: TCastleAbilitySystemBehavior = nil): Boolean; overload;
    function GetRemainingCooldown(const AAbilityId: String): Single;
    procedure ResetAllCooldowns;

    { Deterministic simulation step (ticks cooldowns, periodic DoT/HoT, and durations). }
    procedure StepSimulation(const Dt: Single);

    function GasSummaryBadge: String;
  published
    property Preset: TGasArchetypePreset
      read FPreset write SetPreset default gapArcaneMage;
    property ConfigJson: String
      read GetConfigJson write SetConfigJson stored True;
    property SyncWithCastleLiving: Boolean
      read FSyncWithCastleLiving write FSyncWithCastleLiving default True;
    property SimulateInEditor: Boolean
      read FSimulateInEditor write FSimulateInEditor default False;
  end;

{ Strict dot-boundary hierarchical Gameplay Tag matcher:
  @code('Status.Debuff.*') matches @code('Status.Debuff') and @code('Status.Debuff.Fire.Burn'),
  but NEVER matches @code('Status.Debuff2'). }
function MatchesGasTagPattern(const AActualTag, APattern: String): Boolean;
function GasModifierOpToString(const AOp: TGasModifierOp): String;
function StringToGasModifierOp(const S: String): TGasModifierOp;
function GasPresetDisplayName(const APreset: TGasArchetypePreset): String;

implementation

uses
  Math, fpjson, jsonparser,
  CastleComponentSerialize, CastleLivingBehaviors, CastleApplicationProperties, CastleUtils;

function MatchesGasTagPattern(const AActualTag, APattern: String): Boolean;
var
  T, P, Prefix: String;
begin
  T := Trim(AActualTag);
  P := Trim(APattern);
  if (T = '') or (P = '') then
    Exit(False);
  if P = '*' then
    Exit(True);
  if SameText(T, P) then
    Exit(True);

  if (Length(P) >= 2) and (Copy(P, Length(P) - 1, 2) = '.*') then
  begin
    Prefix := Copy(P, 1, Length(P) - 2);
    if SameText(T, Prefix) then
      Exit(True);
    if (Length(T) > Length(Prefix) + 1) and
       SameText(Copy(T, 1, Length(Prefix) + 1), Prefix + '.') then
      Exit(True);
  end;
  Result := False;
end;

function GasModifierOpToString(const AOp: TGasModifierOp): String;
begin
  case AOp of
    gmoFlatAdd:    Result := 'FlatAdd';
    gmoPercentAdd: Result := 'PercentAdd';
    gmoMultiply:   Result := 'Multiply';
  end;
end;

function StringToGasModifierOp(const S: String): TGasModifierOp;
var
  L: String;
begin
  L := LowerCase(Trim(S));
  if (L = 'percentadd') or (L = 'pct') then
    Result := gmoPercentAdd
  else if (L = 'multiply') or (L = 'mul') then
    Result := gmoMultiply
  else
    Result := gmoFlatAdd;
end;

function GasPresetDisplayName(const APreset: TGasArchetypePreset): String;
begin
  case APreset of
    gapCustom:          Result := 'Custom';
    gapArcaneMage:      Result := 'ArcaneMage';
    gapVanguardPaladin: Result := 'VanguardPaladin';
    gapShadowRanger:    Result := 'ShadowRanger';
  end;
end;

{ Record constructors -------------------------------------------------------- }

class function TGasAttributeDef.CreateSimple(const AName: String;
  const ABase, AMin, AMax: Single; const AMaxAttr: String): TGasAttributeDef;
begin
  Result.AttrName := AName;
  Result.BaseValue := ABase;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.MaxAttrName := AMaxAttr;
end;

class function TGasEffectDef.CreateDefault(const AId: String): TGasEffectDef;
begin
  Result.EffectId := AId;
  Result.EffectTag := 'Status.Generic';
  Result.GrantedTag := '';
  Result.GrantsImmunityPattern := '';
  Result.DurationSec := 5.0;
  Result.MaxStacks := 1;
  Result.TargetAttrName := '';
  Result.ModOp := gmoFlatAdd;
  Result.ModMagnitude := 0.0;
  Result.PeriodSec := 0.0;
  Result.PeriodicAttrName := '';
  Result.PeriodicDeltaPerStack := 0.0;
end;

class function TGasAbilityDef.CreateDefault(const AId: String): TGasAbilityDef;
begin
  Result.AbilityId := AId;
  Result.CostAttrName := 'Mana';
  Result.CostAmount := 20.0;
  Result.CooldownSec := 4.0;
  Result.RemainingCooldownSec := 0.0;
  Result.RequiredTagPattern := '';
  Result.BlockedByTagPattern := 'Status.CrowdControl.*';
  Result.SelfEffectId := '';
  Result.TargetEffectId := '';
  Result.DirectTargetAttr := '';
  Result.DirectTargetDelta := 0.0;
end;

{ TCastleAbilitySystemBehavior ----------------------------------------------- }

constructor TCastleAbilitySystemBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAttributes := TGasAttributeList.Create;
  FEffectDefs := TGasEffectDefList.Create;
  FActiveEffects := TGasActiveEffectList.Create;
  FAbilities := TGasAbilityList.Create;
  FOwnedTags := TStringList.Create;
  FOwnedTags.CaseSensitive := False;
  FOwnedTags.Duplicates := dupIgnore;
  FSyncWithCastleLiving := True;
  FSimulateInEditor := False;

  ApplyPreset(gapArcaneMage);
end;

destructor TCastleAbilitySystemBehavior.Destroy;
begin
  FreeAndNil(FOwnedTags);
  FreeAndNil(FAbilities);
  FreeAndNil(FActiveEffects);
  FreeAndNil(FEffectDefs);
  FreeAndNil(FAttributes);
  inherited;
end;

function TCastleAbilitySystemBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'ConfigJson') or
     (PropertyName = 'SyncWithCastleLiving') or
     (PropertyName = 'SimulateInEditor') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleAbilitySystemBehavior.SetPreset(const Value: TGasArchetypePreset);
begin
  if FPreset <> Value then
  begin
    if Value = gapCustom then
      FPreset := gapCustom
    else
      ApplyPreset(Value);
  end;
end;

procedure TCastleAbilitySystemBehavior.ApplyPreset(const APreset: TGasArchetypePreset);
var
  Eff: TGasEffectDef;
  Ab: TGasAbilityDef;
begin
  FPreset := APreset;
  if APreset = gapCustom then
    Exit;

  FAttributes.Clear;
  FEffectDefs.Clear;
  FActiveEffects.Clear;
  FAbilities.Clear;
  FOwnedTags.Clear;

  case APreset of
    gapArcaneMage:
      begin
        FOwnedTags.Add('Class.ArcaneMage');
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('MaxHealth', 100.0, 1.0, 9999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('Health', 100.0, 0.0, 9999.0, 'MaxHealth'));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('MaxMana', 120.0, 0.0, 9999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('Mana', 120.0, 0.0, 9999.0, 'MaxMana'));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('AttackPower', 45.0, 0.0, 9999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('MoveSpeed', 6.0, 0.0, 50.0));

        Eff := TGasEffectDef.CreateDefault('IgniteBurnDoT');
        Eff.EffectTag := 'Status.Debuff.Fire.Burn';
        Eff.GrantedTag := 'Burning';
        Eff.DurationSec := 4.0;
        Eff.MaxStacks := 3;
        Eff.PeriodSec := 1.0;
        Eff.PeriodicAttrName := 'Health';
        Eff.PeriodicDeltaPerStack := -6.0;
        RegisterEffectDef(Eff);

        Eff := TGasEffectDef.CreateDefault('FireImmunityWard');
        Eff.EffectTag := 'Status.Buff.Arcane.Ward';
        Eff.GrantedTag := 'Buff.FireWard';
        Eff.GrantsImmunityPattern := 'Status.Debuff.Fire.*';
        Eff.DurationSec := 8.0;
        Eff.TargetAttrName := 'MaxHealth';
        Eff.ModOp := gmoFlatAdd;
        Eff.ModMagnitude := 25.0;
        RegisterEffectDef(Eff);

        Eff := TGasEffectDef.CreateDefault('ArcaneSurgeBuff');
        Eff.EffectTag := 'Status.Buff.Arcane.Surge';
        Eff.GrantedTag := 'Buff.ArcaneSurge';
        Eff.DurationSec := 6.0;
        Eff.MaxStacks := 2;
        Eff.TargetAttrName := 'AttackPower';
        Eff.ModOp := gmoPercentAdd;
        Eff.ModMagnitude := 0.25;
        RegisterEffectDef(Eff);

        Ab := TGasAbilityDef.CreateDefault('Fireball');
        Ab.CostAttrName := 'Mana';
        Ab.CostAmount := 25.0;
        Ab.CooldownSec := 3.0;
        Ab.DirectTargetAttr := 'Health';
        Ab.DirectTargetDelta := -28.0;
        Ab.TargetEffectId := 'IgniteBurnDoT';
        RegisterAbility(Ab);

        Ab := TGasAbilityDef.CreateDefault('ArcaneWard');
        Ab.CostAttrName := 'Mana';
        Ab.CostAmount := 30.0;
        Ab.CooldownSec := 10.0;
        Ab.SelfEffectId := 'FireImmunityWard';
        RegisterAbility(Ab);

        Ab := TGasAbilityDef.CreateDefault('ArcaneSurge');
        Ab.CostAttrName := 'Mana';
        Ab.CostAmount := 20.0;
        Ab.CooldownSec := 8.0;
        Ab.SelfEffectId := 'ArcaneSurgeBuff';
        RegisterAbility(Ab);
      end;

    gapVanguardPaladin:
      begin
        FOwnedTags.Add('Class.Paladin');
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('MaxHealth', 180.0, 1.0, 9999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('Health', 180.0, 0.0, 9999.0, 'MaxHealth'));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('MaxMana', 80.0, 0.0, 9999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('Mana', 80.0, 0.0, 9999.0, 'MaxMana'));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('Armor', 35.0, 0.0, 999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('AttackPower', 55.0, 0.0, 9999.0));

        Eff := TGasEffectDef.CreateDefault('RejuvenationHoT');
        Eff.EffectTag := 'Status.Buff.Holy.HoT';
        Eff.GrantedTag := 'Buff.Rejuvenation';
        Eff.DurationSec := 5.0;
        Eff.MaxStacks := 2;
        Eff.PeriodSec := 1.0;
        Eff.PeriodicAttrName := 'Health';
        Eff.PeriodicDeltaPerStack := 12.0;
        RegisterEffectDef(Eff);

        Eff := TGasEffectDef.CreateDefault('StunDebuff');
        Eff.EffectTag := 'Status.CrowdControl.Stun';
        Eff.GrantedTag := 'Status.CrowdControl.Stun';
        Eff.DurationSec := 2.5;
        RegisterEffectDef(Eff);

        Ab := TGasAbilityDef.CreateDefault('HolyLight');
        Ab.CostAttrName := 'Mana';
        Ab.CostAmount := 25.0;
        Ab.CooldownSec := 4.0;
        Ab.SelfEffectId := 'RejuvenationHoT';
        RegisterAbility(Ab);

        Ab := TGasAbilityDef.CreateDefault('ShieldBash');
        Ab.CostAttrName := 'Mana';
        Ab.CostAmount := 15.0;
        Ab.CooldownSec := 6.0;
        Ab.DirectTargetAttr := 'Health';
        Ab.DirectTargetDelta := -20.0;
        Ab.TargetEffectId := 'StunDebuff';
        RegisterAbility(Ab);
      end;

    gapShadowRanger:
      begin
        FOwnedTags.Add('Class.Ranger');
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('MaxHealth', 110.0, 1.0, 9999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('Health', 110.0, 0.0, 9999.0, 'MaxHealth'));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('MaxStamina', 100.0, 0.0, 999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('Stamina', 100.0, 0.0, 999.0, 'MaxStamina'));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('AttackPower', 60.0, 0.0, 9999.0));
        DefineOrSetAttribute(TGasAttributeDef.CreateSimple('MoveSpeed', 7.2, 0.0, 50.0));

        Eff := TGasEffectDef.CreateDefault('SprintHasteBuff');
        Eff.EffectTag := 'Status.Buff.Haste';
        Eff.GrantedTag := 'Buff.Sprint';
        Eff.DurationSec := 5.0;
        Eff.TargetAttrName := 'MoveSpeed';
        Eff.ModOp := gmoMultiply;
        Eff.ModMagnitude := 1.40;
        RegisterEffectDef(Eff);

        Ab := TGasAbilityDef.CreateDefault('AdrenalineSprint');
        Ab.CostAttrName := 'Stamina';
        Ab.CostAmount := 30.0;
        Ab.CooldownSec := 8.0;
        Ab.SelfEffectId := 'SprintHasteBuff';
        RegisterAbility(Ab);
      end;
  end;
  SyncLivingIfNeeded;
end;

function TCastleAbilitySystemBehavior.FindAttributeIndex(const AName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to FAttributes.Count - 1 do
    if SameText(FAttributes[I].AttrName, AName) then
      Exit(I);
  Result := -1;
end;

function TCastleAbilitySystemBehavior.FindEffectDefIndex(const AId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to FEffectDefs.Count - 1 do
    if SameText(FEffectDefs[I].EffectId, AId) then
      Exit(I);
  Result := -1;
end;

function TCastleAbilitySystemBehavior.FindActiveEffectIndex(const AId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to FActiveEffects.Count - 1 do
    if SameText(FActiveEffects[I].Def.EffectId, AId) then
      Exit(I);
  Result := -1;
end;

function TCastleAbilitySystemBehavior.FindAbilityIndex(const AId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to FAbilities.Count - 1 do
    if SameText(FAbilities[I].AbilityId, AId) then
      Exit(I);
  Result := -1;
end;

function TCastleAbilitySystemBehavior.EffectiveMaxForAttribute(
  const ADef: TGasAttributeDef; const Depth: Integer): Single;
begin
  Result := ADef.MaxValue;
  if (ADef.MaxAttrName <> '') and (not SameText(ADef.MaxAttrName, ADef.AttrName)) and
     (Depth < 4) and HasAttribute(ADef.MaxAttrName) then
    Result := Min(Result, InternalEvaluateAttribute(ADef.MaxAttrName, Depth + 1));
end;

function TCastleAbilitySystemBehavior.InternalEvaluateAttribute(
  const AName: String; const Depth: Integer): Single;
var
  Idx, I, Stacks: Integer;
  Def: TGasAttributeDef;
  FlatSum, PctSum, MulProd, EffMax: Single;
  Act: TGasActiveEffect;
begin
  Idx := FindAttributeIndex(AName);
  if Idx < 0 then
    Exit(0.0);

  Def := FAttributes[Idx];
  FlatSum := 0.0;
  PctSum := 0.0;
  MulProd := 1.0;

  for I := 0 to FActiveEffects.Count - 1 do
  begin
    Act := FActiveEffects[I];
    if SameText(Act.Def.TargetAttrName, AName) then
    begin
      Stacks := Max(1, Act.CurrentStacks);
      case Act.Def.ModOp of
        gmoFlatAdd:    FlatSum := FlatSum + Act.Def.ModMagnitude * Stacks;
        gmoPercentAdd: PctSum  := PctSum  + Act.Def.ModMagnitude * Stacks;
        gmoMultiply:   MulProd := MulProd * Power(Max(0.0, Act.Def.ModMagnitude), Stacks);
      end;
    end;
  end;

  EffMax := EffectiveMaxForAttribute(Def, Depth);
  Result := (Def.BaseValue + FlatSum) * Max(0.0, 1.0 + PctSum) * MulProd;
  Result := Clamped(Result, Def.MinValue, Max(Def.MinValue, EffMax));
end;

procedure TCastleAbilitySystemBehavior.ClampBaseAttribute(const AIdx: Integer);
var
  Def: TGasAttributeDef;
  EffMax: Single;
begin
  if (AIdx < 0) or (AIdx >= FAttributes.Count) then
    Exit;
  Def := FAttributes[AIdx];
  EffMax := EffectiveMaxForAttribute(Def, 0);
  Def.BaseValue := Clamped(Def.BaseValue, Def.MinValue, Max(Def.MinValue, EffMax));
  FAttributes[AIdx] := Def;
end;

procedure TCastleAbilitySystemBehavior.SyncLivingIfNeeded;
var
  Living: TCastleLiving;
begin
  if (not FSyncWithCastleLiving) or (Parent = nil) then
    Exit;
  Living := Parent.FindBehavior(TCastleLiving) as TCastleLiving;
  if Living = nil then
    Exit;
  if HasAttribute('MaxHealth') then
    Living.MaxLife := Max(0.01, GetCurrentValue('MaxHealth'));
  if HasAttribute('Health') then
    Living.Life := GetCurrentValue('Health');
end;

procedure TCastleAbilitySystemBehavior.DefineOrSetAttribute(const ADef: TGasAttributeDef);
var
  Idx: Integer;
begin
  Idx := FindAttributeIndex(ADef.AttrName);
  if Idx >= 0 then
    FAttributes[Idx] := ADef
  else
    Idx := FAttributes.Add(ADef);
  ClampBaseAttribute(Idx);
  SyncLivingIfNeeded;
end;

function TCastleAbilitySystemBehavior.HasAttribute(const AName: String): Boolean;
begin
  Result := FindAttributeIndex(AName) >= 0;
end;

function TCastleAbilitySystemBehavior.GetBaseValue(const AName: String): Single;
var
  Idx: Integer;
begin
  Idx := FindAttributeIndex(AName);
  if Idx >= 0 then
    Result := FAttributes[Idx].BaseValue
  else
    Result := 0.0;
end;

procedure TCastleAbilitySystemBehavior.SetBaseValue(const AName: String; const AValue: Single);
var
  Idx: Integer;
  Def: TGasAttributeDef;
begin
  Idx := FindAttributeIndex(AName);
  if Idx < 0 then
    Exit;
  Def := FAttributes[Idx];
  Def.BaseValue := AValue;
  FAttributes[Idx] := Def;
  ClampBaseAttribute(Idx);
  SyncLivingIfNeeded;
end;

procedure TCastleAbilitySystemBehavior.ModifyBaseValue(const AName: String; const ADelta: Single);
begin
  if HasAttribute(AName) then
    SetBaseValue(AName, GetBaseValue(AName) + ADelta);
end;

function TCastleAbilitySystemBehavior.GetCurrentValue(const AName: String): Single;
begin
  Result := InternalEvaluateAttribute(AName, 0);
end;

procedure TCastleAbilitySystemBehavior.GrantTag(const ATag: String);
var
  T: String;
begin
  T := Trim(ATag);
  if (T <> '') and (FOwnedTags.IndexOf(T) < 0) then
    FOwnedTags.Add(T);
end;

procedure TCastleAbilitySystemBehavior.RevokeTag(const ATag: String);
var
  Idx: Integer;
begin
  Idx := FOwnedTags.IndexOf(Trim(ATag));
  if Idx >= 0 then
    FOwnedTags.Delete(Idx);
end;

function TCastleAbilitySystemBehavior.HasMatchingTag(const APattern: String): Boolean;
var
  I: Integer;
begin
  if Trim(APattern) = '' then
    Exit(False);
  for I := 0 to FOwnedTags.Count - 1 do
    if MatchesGasTagPattern(FOwnedTags[I], APattern) then
      Exit(True);
  for I := 0 to FActiveEffects.Count - 1 do
  begin
    if (FActiveEffects[I].Def.GrantedTag <> '') and
       MatchesGasTagPattern(FActiveEffects[I].Def.GrantedTag, APattern) then
      Exit(True);
    if (FActiveEffects[I].Def.EffectTag <> '') and
       MatchesGasTagPattern(FActiveEffects[I].Def.EffectTag, APattern) then
      Exit(True);
  end;
  Result := False;
end;

function TCastleAbilitySystemBehavior.IsImmuneToTag(const AEffectTag: String): Boolean;
var
  I: Integer;
  Pat: String;
begin
  Result := False;
  if Trim(AEffectTag) = '' then
    Exit;
  for I := 0 to FActiveEffects.Count - 1 do
  begin
    Pat := FActiveEffects[I].Def.GrantsImmunityPattern;
    if (Pat <> '') and MatchesGasTagPattern(AEffectTag, Pat) then
      Exit(True);
  end;
end;

procedure TCastleAbilitySystemBehavior.PurgeImmunityMatchedEffects(const APattern: String);
var
  I: Integer;
begin
  if Trim(APattern) = '' then
    Exit;
  for I := FActiveEffects.Count - 1 downto 0 do
    if MatchesGasTagPattern(FActiveEffects[I].Def.EffectTag, APattern) then
      FActiveEffects.Delete(I);
end;

procedure TCastleAbilitySystemBehavior.RegisterEffectDef(const ADef: TGasEffectDef);
var
  Idx: Integer;
begin
  Idx := FindEffectDefIndex(ADef.EffectId);
  if Idx >= 0 then
    FEffectDefs[Idx] := ADef
  else
    FEffectDefs.Add(ADef);
end;

function TCastleAbilitySystemBehavior.ApplyEffectDef(
  const ADef: TGasEffectDef; out OutReason: String): Boolean;
var
  ActIdx: Integer;
  Act: TGasActiveEffect;
begin
  if IsImmuneToTag(ADef.EffectTag) then
  begin
    OutReason := Format('Blocked by tag immunity (%s)', [ADef.EffectTag]);
    Exit(False);
  end;

  { Instant effect (DurationSec <= 0) mutates BaseValue permanently }
  if ADef.DurationSec <= 0.0 then
  begin
    if (ADef.TargetAttrName <> '') and HasAttribute(ADef.TargetAttrName) then
    begin
      case ADef.ModOp of
        gmoFlatAdd:    ModifyBaseValue(ADef.TargetAttrName, ADef.ModMagnitude);
        gmoPercentAdd: SetBaseValue(ADef.TargetAttrName, GetBaseValue(ADef.TargetAttrName) * (1.0 + ADef.ModMagnitude));
        gmoMultiply:   SetBaseValue(ADef.TargetAttrName, GetBaseValue(ADef.TargetAttrName) * ADef.ModMagnitude);
      end;
    end;
    OutReason := 'Applied instant effect';
    Exit(True);
  end;

  { Durational effect: stack or insert }
  ActIdx := FindActiveEffectIndex(ADef.EffectId);
  if ActIdx >= 0 then
  begin
    Act := FActiveEffects[ActIdx];
    Act.Def := ADef;
    Act.RemainingSec := ADef.DurationSec;
    Act.CurrentStacks := Min(Max(1, ADef.MaxStacks), Act.CurrentStacks + 1);
    FActiveEffects[ActIdx] := Act;
  end else
  begin
    Act.Def := ADef;
    Act.RemainingSec := ADef.DurationSec;
    Act.PeriodAccumSec := 0.0;
    Act.CurrentStacks := 1;
    FActiveEffects.Add(Act);
  end;

  if ADef.GrantsImmunityPattern <> '' then
    PurgeImmunityMatchedEffects(ADef.GrantsImmunityPattern);

  SyncLivingIfNeeded;
  OutReason := 'Applied active effect';
  Result := True;
end;

function TCastleAbilitySystemBehavior.ApplyEffectById(
  const AEffectId: String; out OutReason: String): Boolean;
var
  Idx: Integer;
begin
  Idx := FindEffectDefIndex(AEffectId);
  if Idx < 0 then
  begin
    OutReason := Format('Unknown EffectId "%s"', [AEffectId]);
    Exit(False);
  end;
  Result := ApplyEffectDef(FEffectDefs[Idx], OutReason);
end;

function TCastleAbilitySystemBehavior.ApplyEffectById(const AEffectId: String): Boolean;
var
  Dummy: String;
begin
  Result := ApplyEffectById(AEffectId, Dummy);
end;

function TCastleAbilitySystemBehavior.ActiveStacksOf(const AEffectId: String): Integer;
var
  Idx: Integer;
begin
  Idx := FindActiveEffectIndex(AEffectId);
  if Idx >= 0 then
    Result := FActiveEffects[Idx].CurrentStacks
  else
    Result := 0;
end;

procedure TCastleAbilitySystemBehavior.ClearActiveEffects;
begin
  FActiveEffects.Clear;
  SyncLivingIfNeeded;
end;

procedure TCastleAbilitySystemBehavior.RegisterAbility(const ADef: TGasAbilityDef);
var
  Idx: Integer;
begin
  Idx := FindAbilityIndex(ADef.AbilityId);
  if Idx >= 0 then
    FAbilities[Idx] := ADef
  else
    FAbilities.Add(ADef);
end;

function TCastleAbilitySystemBehavior.CanActivateAbility(
  const AAbilityId: String; out OutReason: String): Boolean;
var
  Idx: Integer;
  Ab: TGasAbilityDef;
begin
  Idx := FindAbilityIndex(AAbilityId);
  if Idx < 0 then
  begin
    OutReason := Format('Unknown AbilityId "%s"', [AAbilityId]);
    Exit(False);
  end;
  Ab := FAbilities[Idx];

  if Ab.RemainingCooldownSec > 1.0e-4 then
  begin
    OutReason := Format('On cooldown (%.1fs remaining)', [Ab.RemainingCooldownSec]);
    Exit(False);
  end;

  if (Ab.BlockedByTagPattern <> '') and HasMatchingTag(Ab.BlockedByTagPattern) then
  begin
    OutReason := Format('Blocked by tag (%s)', [Ab.BlockedByTagPattern]);
    Exit(False);
  end;

  if (Ab.RequiredTagPattern <> '') and (not HasMatchingTag(Ab.RequiredTagPattern)) then
  begin
    OutReason := Format('Missing required tag (%s)', [Ab.RequiredTagPattern]);
    Exit(False);
  end;

  if (Ab.CostAttrName <> '') and (Ab.CostAmount > 0.0) then
  begin
    if GetCurrentValue(Ab.CostAttrName) + 1.0e-4 < Ab.CostAmount then
    begin
      OutReason := Format('Insufficient %s (%.1f / %.1f)',
        [Ab.CostAttrName, GetCurrentValue(Ab.CostAttrName), Ab.CostAmount]);
      Exit(False);
    end;
  end;

  OutReason := 'Ready';
  Result := True;
end;

function TCastleAbilitySystemBehavior.TryActivateAbility(
  const AAbilityId: String;
  const ATarget: TCastleAbilitySystemBehavior;
  out OutReason: String): Boolean;
var
  Idx, EffIdx: Integer;
  Ab: TGasAbilityDef;
  EffReason: String;
  TargetSys: TCastleAbilitySystemBehavior;
begin
  if not CanActivateAbility(AAbilityId, OutReason) then
    Exit(False);

  Idx := FindAbilityIndex(AAbilityId);
  Ab := FAbilities[Idx];

  { Commit cost & start cooldown }
  if (Ab.CostAttrName <> '') and (Ab.CostAmount > 0.0) then
    ModifyBaseValue(Ab.CostAttrName, -Ab.CostAmount);

  Ab.RemainingCooldownSec := Max(0.0, Ab.CooldownSec);
  FAbilities[Idx] := Ab;

  if Ab.SelfEffectId <> '' then
    ApplyEffectById(Ab.SelfEffectId, EffReason);

  if ATarget <> nil then
    TargetSys := ATarget
  else
    TargetSys := Self;

  if (Ab.DirectTargetAttr <> '') and (not IsZero(Ab.DirectTargetDelta)) then
    TargetSys.ModifyBaseValue(Ab.DirectTargetAttr, Ab.DirectTargetDelta);

  if Ab.TargetEffectId <> '' then
  begin
    EffIdx := FindEffectDefIndex(Ab.TargetEffectId);
    if EffIdx >= 0 then
      TargetSys.ApplyEffectDef(FEffectDefs[EffIdx], EffReason)
    else
      TargetSys.ApplyEffectById(Ab.TargetEffectId, EffReason);
  end;

  SyncLivingIfNeeded;
  OutReason := 'Activated';
  Result := True;
end;

function TCastleAbilitySystemBehavior.TryActivateAbility(
  const AAbilityId: String; const ATarget: TCastleAbilitySystemBehavior): Boolean;
var
  Dummy: String;
begin
  Result := TryActivateAbility(AAbilityId, ATarget, Dummy);
end;

function TCastleAbilitySystemBehavior.GetRemainingCooldown(const AAbilityId: String): Single;
var
  Idx: Integer;
begin
  Idx := FindAbilityIndex(AAbilityId);
  if Idx >= 0 then
    Result := FAbilities[Idx].RemainingCooldownSec
  else
    Result := 0.0;
end;

procedure TCastleAbilitySystemBehavior.ResetAllCooldowns;
var
  I: Integer;
  Ab: TGasAbilityDef;
begin
  for I := 0 to FAbilities.Count - 1 do
  begin
    Ab := FAbilities[I];
    Ab.RemainingCooldownSec := 0.0;
    FAbilities[I] := Ab;
  end;
end;

procedure TCastleAbilitySystemBehavior.StepSimulation(const Dt: Single);
var
  I: Integer;
  Ab: TGasAbilityDef;
  Act: TGasActiveEffect;
  StepSec, EffectiveWindow: Single;
begin
  if Dt <= 0.0 then
    Exit;

  { 1. Tick ability cooldowns }
  for I := 0 to FAbilities.Count - 1 do
  begin
    Ab := FAbilities[I];
    if Ab.RemainingCooldownSec > 0.0 then
    begin
      Ab.RemainingCooldownSec := Max(0.0, Ab.RemainingCooldownSec - Dt);
      FAbilities[I] := Ab;
    end;
  end;

  { 2. Tick active effects (periodic DoT/HoT + duration expiration) }
  for I := FActiveEffects.Count - 1 downto 0 do
  begin
    Act := FActiveEffects[I];
    EffectiveWindow := Min(Dt, Max(0.0, Act.RemainingSec));

    if (Act.Def.PeriodSec > 1.0e-4) and (Act.Def.PeriodicAttrName <> '') then
    begin
      Act.PeriodAccumSec := Act.PeriodAccumSec + EffectiveWindow;
      StepSec := Act.Def.PeriodSec;
      while Act.PeriodAccumSec + 1.0e-5 >= StepSec do
      begin
        ModifyBaseValue(Act.Def.PeriodicAttrName,
          Act.Def.PeriodicDeltaPerStack * Max(1, Act.CurrentStacks));
        Act.PeriodAccumSec := Max(0.0, Act.PeriodAccumSec - StepSec);
      end;
    end;

    Act.RemainingSec := Act.RemainingSec - Dt;
    if Act.RemainingSec <= 1.0e-5 then
      FActiveEffects.Delete(I)
    else
      FActiveEffects[I] := Act;
  end;

  { Re-clamp dependent attributes (e.g. if MaxHealth buff expired) }
  for I := 0 to FAttributes.Count - 1 do
    ClampBaseAttribute(I);

  SyncLivingIfNeeded;
end;

procedure TCastleAbilitySystemBehavior.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepSimulation(SecondsPassed);
end;

function TCastleAbilitySystemBehavior.GetConfigJson: String;
var
  Root: TJSONObject;
  ArrAttrs, ArrEffects, ArrAbilities, ArrTags: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  At: TGasAttributeDef;
  Ef: TGasEffectDef;
  Ab: TGasAbilityDef;
begin
  Root := TJSONObject.Create;
  try
    ArrTags := TJSONArray.Create;
    for I := 0 to FOwnedTags.Count - 1 do
      ArrTags.Add(FOwnedTags[I]);
    Root.Add('tags', ArrTags);

    ArrAttrs := TJSONArray.Create;
    for I := 0 to FAttributes.Count - 1 do
    begin
      At := FAttributes[I];
      Obj := TJSONObject.Create;
      Obj.Add('name', At.AttrName);
      Obj.Add('base', At.BaseValue);
      Obj.Add('min', At.MinValue);
      Obj.Add('max', At.MaxValue);
      Obj.Add('maxAttr', At.MaxAttrName);
      ArrAttrs.Add(Obj);
    end;
    Root.Add('attributes', ArrAttrs);

    ArrEffects := TJSONArray.Create;
    for I := 0 to FEffectDefs.Count - 1 do
    begin
      Ef := FEffectDefs[I];
      Obj := TJSONObject.Create;
      Obj.Add('id', Ef.EffectId);
      Obj.Add('tag', Ef.EffectTag);
      Obj.Add('grantedTag', Ef.GrantedTag);
      Obj.Add('immunity', Ef.GrantsImmunityPattern);
      Obj.Add('dur', Ef.DurationSec);
      Obj.Add('stacks', Ef.MaxStacks);
      Obj.Add('attr', Ef.TargetAttrName);
      Obj.Add('op', GasModifierOpToString(Ef.ModOp));
      Obj.Add('mag', Ef.ModMagnitude);
      Obj.Add('period', Ef.PeriodSec);
      Obj.Add('periodAttr', Ef.PeriodicAttrName);
      Obj.Add('periodDelta', Ef.PeriodicDeltaPerStack);
      ArrEffects.Add(Obj);
    end;
    Root.Add('effects', ArrEffects);

    ArrAbilities := TJSONArray.Create;
    for I := 0 to FAbilities.Count - 1 do
    begin
      Ab := FAbilities[I];
      Obj := TJSONObject.Create;
      Obj.Add('id', Ab.AbilityId);
      Obj.Add('costAttr', Ab.CostAttrName);
      Obj.Add('cost', Ab.CostAmount);
      Obj.Add('cd', Ab.CooldownSec);
      Obj.Add('reqTag', Ab.RequiredTagPattern);
      Obj.Add('blockTag', Ab.BlockedByTagPattern);
      Obj.Add('selfEff', Ab.SelfEffectId);
      Obj.Add('targetEff', Ab.TargetEffectId);
      Obj.Add('directAttr', Ab.DirectTargetAttr);
      Obj.Add('directDelta', Ab.DirectTargetDelta);
      ArrAbilities.Add(Obj);
    end;
    Root.Add('abilities', ArrAbilities);

    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleAbilitySystemBehavior.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  At: TGasAttributeDef;
  Ef: TGasEffectDef;
  Ab: TGasAbilityDef;
begin
  if Trim(Value) = '' then
    Exit;
  Data := nil;
  try
    try
      Data := GetJSON(Value);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then
      Exit;
    Root := TJSONObject(Data);

    FOwnedTags.Clear;
    Arr := Root.Find('tags', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        GrantTag(Arr.Strings[I]);

    FAttributes.Clear;
    Arr := Root.Find('attributes', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          At := TGasAttributeDef.CreateSimple(
            Obj.Get('name', 'Attr'),
            Obj.Get('base', 100.0),
            Obj.Get('min', 0.0),
            Obj.Get('max', 9999.0),
            Obj.Get('maxAttr', ''));
          FAttributes.Add(At);
        end;

    FEffectDefs.Clear;
    Arr := Root.Find('effects', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          Ef := TGasEffectDef.CreateDefault(Obj.Get('id', 'Effect'));
          Ef.EffectTag := Obj.Get('tag', '');
          Ef.GrantedTag := Obj.Get('grantedTag', '');
          Ef.GrantsImmunityPattern := Obj.Get('immunity', '');
          Ef.DurationSec := Obj.Get('dur', 5.0);
          Ef.MaxStacks := Max(1, Obj.Get('stacks', 1));
          Ef.TargetAttrName := Obj.Get('attr', '');
          Ef.ModOp := StringToGasModifierOp(Obj.Get('op', 'FlatAdd'));
          Ef.ModMagnitude := Obj.Get('mag', 0.0);
          Ef.PeriodSec := Obj.Get('period', 0.0);
          Ef.PeriodicAttrName := Obj.Get('periodAttr', '');
          Ef.PeriodicDeltaPerStack := Obj.Get('periodDelta', 0.0);
          FEffectDefs.Add(Ef);
        end;

    FAbilities.Clear;
    Arr := Root.Find('abilities', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          Ab := TGasAbilityDef.CreateDefault(Obj.Get('id', 'Ability'));
          Ab.CostAttrName := Obj.Get('costAttr', '');
          Ab.CostAmount := Obj.Get('cost', 0.0);
          Ab.CooldownSec := Obj.Get('cd', 0.0);
          Ab.RequiredTagPattern := Obj.Get('reqTag', '');
          Ab.BlockedByTagPattern := Obj.Get('blockTag', '');
          Ab.SelfEffectId := Obj.Get('selfEff', '');
          Ab.TargetEffectId := Obj.Get('targetEff', '');
          Ab.DirectTargetAttr := Obj.Get('directAttr', '');
          Ab.DirectTargetDelta := Obj.Get('directDelta', 0.0);
          FAbilities.Add(Ab);
        end;

    SyncLivingIfNeeded;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleAbilitySystemBehavior.GasSummaryBadge: String;
begin
  Result := Format('[GAS:%s %d attrs %d abilities %d active]', [
    GasPresetDisplayName(FPreset),
    FAttributes.Count,
    FAbilities.Count,
    FActiveEffects.Count
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleAbilitySystemBehavior,
    ['Gameplay Ability System (GAS)']);
end.
