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

{ Stateless Editor & Headless Helper for 2D Locomotion Blend Spaces,
  Motion-Warped Combat Montages, Demo Rig Spawning & QA Diagnostics
  (@link(TBlendMontageHelper), @link(TBlendMontageAuditReport))
  (Phase 318 — UE 6.0+ BlendSpaces, Motion Warping & Anim Montages Parity). }
unit ToolBlendMontage;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleBlendMontage;

type
  TBlendSpaceArray = array of TCastleBlendSpace2DBehavior;
  TAnimMontageArray = array of TCastleAnimMontageBehavior;

  { QA summary across all 2D Blend Space and Anim Montage behaviors in a design. }
  TBlendMontageAuditReport = class
  public
    BlendSpaceCount: Integer;
    MontageCount: Integer;
    TotalSamples: Integer;
    TotalNotifies: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, stepping, and auditing
    @link(TCastleBlendSpace2DBehavior) and @link(TCastleAnimMontageBehavior). }
  TBlendMontageHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanBlendAndMontages(const RootComp, DesignOwner: TComponent;
      out OutBlendSpaces: TBlendSpaceArray; out OutMontages: TAnimMontageArray); static;

    class procedure SpawnHeroLocomotionAndMontageDemo(
      const RootComp, DesignOwner: TComponent;
      out OutHero, OutDummyTarget: TCastleTransform;
      out OutBlend: TCastleBlendSpace2DBehavior;
      out OutMontage: TCastleAnimMontageBehavior); static;

    class procedure StepAllBlendAndMontages(const RootComp, DesignOwner: TComponent;
      const Dt: Single); static;

    class function AuditBlendAndMontages(
      const RootComp, DesignOwner: TComponent): TBlendMontageAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleColors, CastleScene;

constructor TBlendMontageAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TBlendMontageAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TBlendMontageHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  Found: TCastleViewport;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  for I := 0 to RootComp.ComponentCount - 1 do
  begin
    Found := FindMainViewport(RootComp.Components[I]);
    if Found <> nil then
      Exit(Found);
  end;
end;

class procedure TBlendMontageHelper.ScanBlendAndMontages(
  const RootComp, DesignOwner: TComponent;
  out OutBlendSpaces: TBlendSpaceArray; out OutMontages: TAnimMontageArray);

  procedure AddBlendUnique(const B: TCastleBlendSpace2DBehavior);
  var
    K: Integer;
  begin
    if (B = nil) or (csTransient in B.ComponentStyle) then
      Exit;
    for K := 0 to High(OutBlendSpaces) do
      if OutBlendSpaces[K] = B then
        Exit;
    SetLength(OutBlendSpaces, Length(OutBlendSpaces) + 1);
    OutBlendSpaces[High(OutBlendSpaces)] := B;
  end;

  procedure AddMontageUnique(const M: TCastleAnimMontageBehavior);
  var
    K: Integer;
  begin
    if (M = nil) or (csTransient in M.ComponentStyle) then
      Exit;
    for K := 0 to High(OutMontages) do
      if OutMontages[K] = M then
        Exit;
    SetLength(OutMontages, Length(OutMontages) + 1);
    OutMontages[High(OutMontages)] := M;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleBlendSpace2DBehavior then
      AddBlendUnique(TCastleBlendSpace2DBehavior(C))
    else if C is TCastleAnimMontageBehavior then
      AddMontageUnique(TCastleAnimMontageBehavior(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Walk(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutBlendSpaces := nil;
  OutMontages := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TBlendMontageHelper.SpawnHeroLocomotionAndMontageDemo(
  const RootComp, DesignOwner: TComponent;
  out OutHero, OutDummyTarget: TCastleTransform;
  out OutBlend: TCastleBlendSpace2DBehavior;
  out OutMontage: TCastleAnimMontageBehavior);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  HeroBox, DummyBox: TCastleBox;
  Idx: Integer;
begin
  OutHero := nil;
  OutDummyTarget := nil;
  OutBlend := nil;
  OutMontage := nil;

  Vp := FindMainViewport(RootComp);
  if Vp <> nil then
    ParentTrans := Vp.Items
  else if RootComp is TCastleTransform then
    ParentTrans := TCastleTransform(RootComp)
  else
    Exit;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('HeroCombatActor' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  HeroBox := TCastleBox.Create(OwnerToUse);
  HeroBox.Name := 'HeroCombatActor' + IntToStr(Idx);
  HeroBox.Size := Vector3(0.75, 1.80, 0.55);
  HeroBox.Translation := Vector3(0.0, 0.90, 2.2);
  HeroBox.Color := Vector4(0.24, 0.68, 0.96, 1.0);
  ParentTrans.Add(HeroBox);

  DummyBox := TCastleBox.Create(OwnerToUse);
  DummyBox.Name := 'MontageCombatTarget' + IntToStr(Idx);
  DummyBox.Size := Vector3(0.80, 1.80, 0.80);
  DummyBox.Translation := Vector3(0.0, 0.90, -2.0);
  DummyBox.Color := Vector4(0.92, 0.34, 0.28, 1.0);
  ParentTrans.Add(DummyBox);

  OutBlend := TCastleBlendSpace2DBehavior.Create(OwnerToUse);
  OutBlend.Name := 'HeroLocomotionBlend2D_' + IntToStr(Idx);
  OutBlend.ApplyPreset(bspEightWayLocomotion);
  HeroBox.AddBehavior(OutBlend);

  OutMontage := TCastleAnimMontageBehavior.Create(OwnerToUse);
  OutMontage.Name := 'HeroComboMontage_' + IntToStr(Idx);
  OutMontage.ApplyPreset(mpThreeHitSwordCombo);
  OutMontage.SetWarpTarget(DummyBox, 1.20);
  HeroBox.AddBehavior(OutMontage);

  OutHero := HeroBox;
  OutDummyTarget := DummyBox;
end;

class procedure TBlendMontageHelper.StepAllBlendAndMontages(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Blends: TBlendSpaceArray;
  Montages: TAnimMontageArray;
  I: Integer;
begin
  ScanBlendAndMontages(RootComp, DesignOwner, Blends, Montages);
  for I := 0 to High(Blends) do
    Blends[I].StepBlendSpace(Dt);
  for I := 0 to High(Montages) do
    Montages[I].StepMontage(Dt);
end;

class function TBlendMontageHelper.AuditBlendAndMontages(
  const RootComp, DesignOwner: TComponent): TBlendMontageAuditReport;
var
  Blends: TBlendSpaceArray;
  Montages: TAnimMontageArray;
  I, K: Integer;
  M: TCastleAnimMontageBehavior;
  Sec: TMontageSectionDef;
  HasWarpNotify: Boolean;
begin
  Result := TBlendMontageAuditReport.Create;
  ScanBlendAndMontages(RootComp, DesignOwner, Blends, Montages);
  Result.BlendSpaceCount := Length(Blends);
  Result.MontageCount := Length(Montages);

  for I := 0 to High(Blends) do
  begin
    Result.TotalSamples := Result.TotalSamples + Blends[I].SampleCount;
    if Blends[I].SampleCount < 2 then
      Result.Warnings.Add(Format(
        'BlendSpace2D "%s" has fewer than 2 animation samples — add directional/speed clips for continuous blending.',
        [Blends[I].Name]));
  end;

  for I := 0 to High(Montages) do
  begin
    M := Montages[I];
    Result.TotalNotifies := Result.TotalNotifies + M.NotifyCount;
    for K := 0 to M.SectionCount - 1 do
    begin
      Sec := M.GetSection(K);
      if (Sec.NextComboSection <> '') and (M.FindSectionIndex(Sec.NextComboSection) < 0) then
        Result.Warnings.Add(Format(
          'AnimMontage "%s" section "%s" references missing NextComboSection "%s".',
          [M.Name, Sec.SectionName, Sec.NextComboSection]));
    end;

    HasWarpNotify := False;
    for K := 0 to M.NotifyCount - 1 do
      if M.GetNotify(K).IsMotionWarpWindow then
        HasWarpNotify := True;
    if HasWarpNotify and (M.WarpTargetTransform = nil) then
      Result.Warnings.Add(Format(
        'AnimMontage "%s" defines a Motion Warp window without a WarpTargetTransform assigned.',
        [M.Name]));
  end;
end;

class function TBlendMontageHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Blends: TBlendSpaceArray;
  Montages: TAnimMontageArray;
  Rep: TBlendMontageAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanBlendAndMontages(RootComp, DesignOwner, Blends, Montages);
  Rep := AuditBlendAndMontages(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# 2D Blend Space, Motion Warp & Anim Montage Studio Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **2D Blend Spaces:** %d (`%d` total samples)',
      [Rep.BlendSpaceCount, Rep.TotalSamples]));
    SB.AppendLine(Format('- **Anim Montages:** %d (`%d` total notifies)',
      [Rep.MontageCount, Rep.TotalNotifies]));
    SB.AppendLine('');
    for I := 0 to High(Blends) do
      SB.AppendLine(Format('- `%s`: %s', [Blends[I].Name, Blends[I].BlendSummaryBadge]));
    for I := 0 to High(Montages) do
      SB.AppendLine(Format('- `%s`: %s', [Montages[I].Name, Montages[I].MontageSummaryBadge]));
    if Rep.Warnings.Count > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('## QA Warnings');
      for I := 0 to Rep.Warnings.Count - 1 do
        SB.AppendLine('- ' + Rep.Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
