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

{ Stateless editor & headless test helpers for the Gameplay Ability, Cooldown,
  Status Buff/Debuff & Attribute System (GAS) Studio (@link(TAbilityStudioHelper))
  (Phase 310 — UE 6.0+ GAS Parity). }
unit ToolAbilityStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleTransform, CastleScene,
  CastleViewport, CastleUIControls, CastleLivingBehaviors,
  CastleGameplayAbility;

type
  { Audit summary across all @link(TCastleAbilitySystemBehavior) instances in a design. }
  TAbilityStudioAuditReport = class
  public
    Systems: array of TCastleAbilitySystemBehavior;
    TotalAttributes: Integer;
    TotalAbilities: Integer;
    TotalActiveEffects: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless authoring, combat-arena spawner, simulation stepper & auditor for GAS. }
  TAbilityStudioHelper = class
  public
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TAbilityStudioAuditReport; static;

    class function AttachGasToTransform(
      const Target: TCastleTransform;
      const DesignOwner: TComponent;
      const APreset: TGasArchetypePreset): TCastleAbilitySystemBehavior; static;

    class function SpawnCombatActorWithGas(
      const RootComp, DesignOwner: TComponent;
      const AActorBaseName: String;
      const APreset: TGasArchetypePreset;
      const SpawnPos: TVector3;
      const AAttachLiving: Boolean = True): TCastleAbilitySystemBehavior; static;

    class procedure StepAllGasSystems(
      const RootComp, DesignOwner: TComponent;
      const Dt: Single); static;

    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleStringUtils;

function MakeUniqueGasName(const OwnerComp: TComponent; const Base: String): String;
var
  Idx: Integer;
begin
  if (OwnerComp = nil) or (OwnerComp.FindComponent(Base) = nil) then
    Exit(Base);
  Idx := 1;
  repeat
    Result := Base + IntToStr(Idx);
    Inc(Idx);
  until OwnerComp.FindComponent(Result) = nil;
end;

function ResolveParentTransform(const RootComp: TComponent): TCastleTransform;
var
  I: Integer;
  Sub: TCastleTransform;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp).Items);
  if RootComp is TCastleTransform then
    Exit(TCastleTransform(RootComp));
  if RootComp is TCastleUserInterface then
    for I := 0 to TCastleUserInterface(RootComp).ControlsCount - 1 do
    begin
      Sub := ResolveParentTransform(TCastleUserInterface(RootComp).Controls[I]);
      if Sub <> nil then
        Exit(Sub);
    end;
end;

procedure CollectGasFromTransform(const T: TCastleTransform; const OutList: TList);
var
  I: Integer;
  B: TCastleBehavior;
begin
  if (T = nil) or (csTransient in T.ComponentStyle) then
    Exit;
  for I := 0 to T.BehaviorsCount - 1 do
  begin
    B := T.Behaviors[I];
    if (B is TCastleAbilitySystemBehavior) and (OutList.IndexOf(B) < 0) then
      OutList.Add(B);
  end;
  for I := 0 to T.Count - 1 do
    CollectGasFromTransform(T[I], OutList);
end;

procedure GatherGasSystems(const RootComp, DesignOwner: TComponent; const OutList: TList);
var
  I: Integer;
begin
  if RootComp is TCastleTransform then
    CollectGasFromTransform(TCastleTransform(RootComp), OutList)
  else if RootComp is TCastleUserInterface then
  begin
    if RootComp is TCastleViewport then
      CollectGasFromTransform(TCastleViewport(RootComp).Items, OutList);
    for I := 0 to TCastleUserInterface(RootComp).ControlsCount - 1 do
      GatherGasSystems(TCastleUserInterface(RootComp).Controls[I], nil, OutList);
  end;

  if DesignOwner <> nil then
    for I := 0 to DesignOwner.ComponentCount - 1 do
      if (DesignOwner.Components[I] is TCastleAbilitySystemBehavior) and
         (OutList.IndexOf(DesignOwner.Components[I]) < 0) then
        OutList.Add(DesignOwner.Components[I]);
end;

function HasEffectInSystem(const Sys: TCastleAbilitySystemBehavior; const EffId: String): Boolean;
var
  I: Integer;
begin
  for I := 0 to Sys.EffectDefs.Count - 1 do
    if SameText(Sys.EffectDefs[I].EffectId, EffId) then
      Exit(True);
  Result := False;
end;

{ TAbilityStudioAuditReport -------------------------------------------------- }

constructor TAbilityStudioAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TAbilityStudioAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TAbilityStudioHelper ------------------------------------------------------- }

class function TAbilityStudioHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TAbilityStudioAuditReport;
var
  Found: TList;
  I, J: Integer;
  Sys: TCastleAbilitySystemBehavior;
  Ab: TGasAbilityDef;
  OwnerLabel: String;
begin
  Result := TAbilityStudioAuditReport.Create;
  Found := TList.Create;
  try
    GatherGasSystems(RootComp, DesignOwner, Found);
    SetLength(Result.Systems, Found.Count);
    for I := 0 to Found.Count - 1 do
    begin
      Sys := TCastleAbilitySystemBehavior(Found[I]);
      Result.Systems[I] := Sys;
      Inc(Result.TotalAttributes, Sys.Attributes.Count);
      Inc(Result.TotalAbilities, Sys.Abilities.Count);
      Inc(Result.TotalActiveEffects, Sys.ActiveEffects.Count);

      if Sys.Parent <> nil then
        OwnerLabel := Sys.Parent.Name + '.' + Sys.Name
      else
        OwnerLabel := Sys.Name;

      for J := 0 to Sys.Abilities.Count - 1 do
      begin
        Ab := Sys.Abilities[J];
        if (Ab.CostAttrName <> '') and (not Sys.HasAttribute(Ab.CostAttrName)) then
          Result.Warnings.Add(Format(
            '%s ability "%s" references missing CostAttrName "%s".',
            [OwnerLabel, Ab.AbilityId, Ab.CostAttrName]));
        if (Ab.SelfEffectId <> '') and (not HasEffectInSystem(Sys, Ab.SelfEffectId)) then
          Result.Warnings.Add(Format(
            '%s ability "%s" references undeclared SelfEffectId "%s".',
            [OwnerLabel, Ab.AbilityId, Ab.SelfEffectId]));
      end;
    end;
  finally
    FreeAndNil(Found);
  end;
end;

class function TAbilityStudioHelper.AttachGasToTransform(
  const Target: TCastleTransform;
  const DesignOwner: TComponent;
  const APreset: TGasArchetypePreset): TCastleAbilitySystemBehavior;
begin
  if Target = nil then
    Exit(nil);
  Result := Target.FindBehavior(TCastleAbilitySystemBehavior) as TCastleAbilitySystemBehavior;
  if Result = nil then
  begin
    Result := TCastleAbilitySystemBehavior.Create(DesignOwner);
    Result.Name := MakeUniqueGasName(DesignOwner, 'AbilitySystem');
    Target.AddBehavior(Result);
  end;
  Result.ApplyPreset(APreset);
end;

class function TAbilityStudioHelper.SpawnCombatActorWithGas(
  const RootComp, DesignOwner: TComponent;
  const AActorBaseName: String;
  const APreset: TGasArchetypePreset;
  const SpawnPos: TVector3;
  const AAttachLiving: Boolean): TCastleAbilitySystemBehavior;
var
  ParentTrans: TCastleTransform;
  ActorBox: TCastleBox;
  Living: TCastleLiving;
begin
  Result := nil;
  ParentTrans := ResolveParentTransform(RootComp);
  if ParentTrans = nil then
    Exit;

  ActorBox := TCastleBox.Create(DesignOwner);
  ActorBox.Name := MakeUniqueGasName(DesignOwner, AActorBaseName);
  ActorBox.Size := Vector3(0.9, 1.8, 0.9);
  ActorBox.Translation := SpawnPos + Vector3(0.0, 0.9, 0.0);
  case APreset of
    gapArcaneMage:      ActorBox.Color := Vector4(0.32, 0.56, 0.96, 1.0);
    gapVanguardPaladin: ActorBox.Color := Vector4(0.94, 0.80, 0.34, 1.0);
    gapShadowRanger:    ActorBox.Color := Vector4(0.34, 0.82, 0.52, 1.0);
  else
    ActorBox.Color := Vector4(0.76, 0.78, 0.84, 1.0);
  end;
  ParentTrans.Add(ActorBox);

  if AAttachLiving then
  begin
    Living := TCastleLiving.Create(DesignOwner);
    Living.Name := MakeUniqueGasName(DesignOwner, AActorBaseName + 'Living');
    ActorBox.AddBehavior(Living);
  end;

  Result := AttachGasToTransform(ActorBox, DesignOwner, APreset);
end;

class procedure TAbilityStudioHelper.StepAllGasSystems(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Report: TAbilityStudioAuditReport;
  I: Integer;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    for I := 0 to High(Report.Systems) do
      Report.Systems[I].StepSimulation(Dt);
  finally
    FreeAndNil(Report);
  end;
end;

class function TAbilityStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TAbilityStudioAuditReport;
  SB: TStringBuilder;
  I, J: Integer;
  Sys: TCastleAbilitySystemBehavior;
  At: TGasAttributeDef;
  Ab: TGasAbilityDef;
  Act: TGasActiveEffect;
  Reason, ParentName: String;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Gameplay Ability System (GAS) Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **GAS Behaviors**: %d | **Attributes**: %d | **Abilities**: %d | **Active Effects**: %d',
      [Length(Report.Systems), Report.TotalAttributes, Report.TotalAbilities, Report.TotalActiveEffects]));
    SB.AppendLine;

    for I := 0 to High(Report.Systems) do
    begin
      Sys := Report.Systems[I];
      if Sys.Parent <> nil then
        ParentName := Sys.Parent.Name
      else
        ParentName := '<detached>';
      SB.AppendLine(Format('## `%s` on `%s` %s', [Sys.Name, ParentName, Sys.GasSummaryBadge]));
      SB.AppendLine('| Attribute | Base | Current | Bounds |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for J := 0 to Sys.Attributes.Count - 1 do
      begin
        At := Sys.Attributes[J];
        SB.AppendLine(Format('| `%s` | `%.1f` | **`%.1f`** | `[%.0f .. %.0f]` %s |',
          [At.AttrName, At.BaseValue, Sys.GetCurrentValue(At.AttrName),
           At.MinValue, At.MaxValue, At.MaxAttrName]));
      end;
      SB.AppendLine;

      SB.AppendLine('| Ability | Cost | Cooldown | Status |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for J := 0 to Sys.Abilities.Count - 1 do
      begin
        Ab := Sys.Abilities[J];
        Sys.CanActivateAbility(Ab.AbilityId, Reason);
        SB.AppendLine(Format('| `%s` | `%.0f %s` | `%.1fs / %.1fs` | %s |',
          [Ab.AbilityId, Ab.CostAmount, Ab.CostAttrName,
           Ab.RemainingCooldownSec, Ab.CooldownSec, Reason]));
      end;

      if Sys.ActiveEffects.Count > 0 then
      begin
        SB.AppendLine;
        SB.AppendLine('**Active Buffs / Debuffs:**');
        for J := 0 to Sys.ActiveEffects.Count - 1 do
        begin
          Act := Sys.ActiveEffects[J];
          SB.AppendLine(Format('- `%s` (`%s`) — `%dx` stack(s), `%.1fs` remaining',
            [Act.Def.EffectId, Act.Def.EffectTag, Act.CurrentStacks, Act.RemainingSec]));
        end;
      end;
      SB.AppendLine;
    end;

    if Report.Warnings.Count > 0 then
    begin
      SB.AppendLine('## Warnings');
      for I := 0 to Report.Warnings.Count - 1 do
        SB.AppendLine('- ' + Report.Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Report);
  end;
end;

end.
