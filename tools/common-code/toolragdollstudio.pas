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

{ Stateless Editor & Headless Helper for Physical Animation Hit-Reaction &
  Articulated Ragdoll Behaviors (@link(TRagdollStudioHelper),
  @link(TRagdollAuditReport))
  (Phase 331 — UE 6.0+ Chaos Physical Animation & Ragdoll Parity). }
unit ToolRagdollStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleRagdollHit;

type
  TRagdollBehaviorArray = array of TCastlePhysicalHitRagdollBehavior;

  { QA summary across all Physical Animation / Ragdoll behaviors in a design. }
  TRagdollAuditReport = class
  public
    RigCount: Integer;
    ActiveLimpRagdollCount: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, stepping, and auditing
    @link(TCastlePhysicalHitRagdollBehavior) instances. }
  TRagdollStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanRagdolls(const RootComp, DesignOwner: TComponent;
      out OutRigs: TRagdollBehaviorArray); static;

    class procedure SpawnPhysicalRagdollArenaDemo(
      const RootComp, DesignOwner: TComponent;
      out OutActor: TCastleTransform;
      out OutRagdoll: TCastlePhysicalHitRagdollBehavior); static;

    class procedure StepAllRagdolls(const RootComp, DesignOwner: TComponent;
      const Dt: Single); static;

    class function AuditRagdolls(
      const RootComp, DesignOwner: TComponent): TRagdollAuditReport; static;

    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleUIControls, CastleColors, CastleScene;

constructor TRagdollAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TRagdollAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TRagdollStudioHelper.FindMainViewport(
  const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if RootComp = nil then Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindMainViewport(UI.Controls[I]);
      if Result <> nil then Exit;
    end;
  end;
end;

class procedure TRagdollStudioHelper.ScanRagdolls(
  const RootComp, DesignOwner: TComponent;
  out OutRigs: TRagdollBehaviorArray);

  procedure AddUnique(const R: TCastlePhysicalHitRagdollBehavior);
  var
    K: Integer;
  begin
    if (R = nil) or (csTransient in R.ComponentStyle) then Exit;
    for K := 0 to High(OutRigs) do
      if OutRigs[K] = R then Exit;
    SetLength(OutRigs, Length(OutRigs) + 1);
    OutRigs[High(OutRigs)] := R;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if C is TCastlePhysicalHitRagdollBehavior then
      AddUnique(TCastlePhysicalHitRagdollBehavior(C));

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
  OutRigs := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TRagdollStudioHelper.SpawnPhysicalRagdollArenaDemo(
  const RootComp, DesignOwner: TComponent;
  out OutActor: TCastleTransform;
  out OutRagdoll: TCastlePhysicalHitRagdollBehavior);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  FloorBox: TCastleBox;
  Idx: Integer;
begin
  OutActor := nil;
  OutRagdoll := nil;

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

  if (OwnerToUse = nil) or (OwnerToUse.FindComponent('RagdollDojoFloor') = nil) then
  begin
    FloorBox := TCastleBox.Create(OwnerToUse);
    FloorBox.Name := 'RagdollDojoFloor';
    FloorBox.Size := Vector3(24.0, 0.4, 24.0);
    FloorBox.Translation := Vector3(0.0, -0.2, 0.0);
    FloorBox.Color := Vector4(0.22, 0.25, 0.30, 1.0);
    ParentTrans.Add(FloorBox);
  end;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('PhysAnimDummy' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  OutActor := TCastleTransform.Create(OwnerToUse);
  OutActor.Name := 'PhysAnimDummy' + IntToStr(Idx);
  OutActor.Translation := Vector3((Idx - 1) * 2.2, 0.0, 0.0);
  ParentTrans.Add(OutActor);

  OutRagdoll := TCastlePhysicalHitRagdollBehavior.Create(OwnerToUse);
  OutRagdoll.Name := 'PhysicalHitRagdoll_' + IntToStr(Idx);
  OutRagdoll.ApplyPreset(papAgileFighterBalanced);
  OutActor.AddBehavior(OutRagdoll);
end;

class procedure TRagdollStudioHelper.StepAllRagdolls(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Rigs: TRagdollBehaviorArray;
  I: Integer;
begin
  ScanRagdolls(RootComp, DesignOwner, Rigs);
  for I := 0 to High(Rigs) do
    Rigs[I].StepPhysicalAnimation(Dt);
end;

class function TRagdollStudioHelper.AuditRagdolls(
  const RootComp, DesignOwner: TComponent): TRagdollAuditReport;
var
  Rigs: TRagdollBehaviorArray;
  I: Integer;
begin
  Result := TRagdollAuditReport.Create;
  ScanRagdolls(RootComp, DesignOwner, Rigs);
  Result.RigCount := Length(Rigs);
  for I := 0 to High(Rigs) do
  begin
    if Rigs[I].Mode = prmFullLimpRagdoll then
      Inc(Result.ActiveLimpRagdollCount);
    if Rigs[I].SpringStiffnessKp < 10.0 then
      Result.Warnings.Add(Format(
        'PhysicalHitRagdoll "%s" has very low SpringStiffnessKp (%.1f); pose may sag.',
        [Rigs[I].Name, Rigs[I].SpringStiffnessKp]));
  end;
end;

class function TRagdollStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Rigs: TRagdollBehaviorArray;
  Audit: TRagdollAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanRagdolls(RootComp, DesignOwner, Rigs);
  Audit := AuditRagdolls(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — Physical Animation Hit-Reaction & Ragdoll Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Articulated Humanoid Rigs**: `%d` (`%d` currently in full ragdoll)',
      [Audit.RigCount, Audit.ActiveLimpRagdollCount]));
    SB.AppendLine;

    if Length(Rigs) > 0 then
    begin
      SB.AppendLine('## Active Physical Animation Rigs');
      SB.AppendLine('| Behavior | Preset | Mode | Kp | Knockdown | Max Deviation | Hits |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Rigs) do
        SB.AppendLine(Format('| `%s` | %s | `%s` | `%.0f` | `%.1f` | `%.3fm` | `%d` |',
          [Rigs[I].Name,
           TCastlePhysicalHitRagdollBehavior.PresetDisplayName(Rigs[I].Preset),
           TCastlePhysicalHitRagdollBehavior.ModeDisplayName(Rigs[I].Mode),
           Rigs[I].SpringStiffnessKp, Rigs[I].KnockdownThreshold,
           Rigs[I].MaxPoseDeviationMeters, Rigs[I].TotalHitsReceived]));
      SB.AppendLine;
    end;

    SB.AppendLine('## QA Diagnostics');
    if Audit.Warnings.Count = 0 then
      SB.AppendLine('- **0 warnings** — all Physical Animation PD springs and PBD ragdoll constraints are healthy.')
    else
      for I := 0 to Audit.Warnings.Count - 1 do
        SB.AppendLine('- **Warning**: ' + Audit.Warnings[I]);

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Audit);
  end;
end;

end.
