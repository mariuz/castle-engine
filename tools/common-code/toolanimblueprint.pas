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

{ Stateless scene authoring, pose stepper, and diagnostic helper for the Unreal
  Engine 5.5-style Animation Blueprint Editor (@link(TAnimBlueprintHelper),
  @link(TAnimBlueprintAuditReport)) (Phase 383 — UE 5.5 UAnimBlueprint Parity +
  26th MCP Tool). }
unit ToolAnimBlueprint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleAnimBlueprint;

type
  { Summary audit across all @link(TCastleAnimBlueprint) instances in the design. }
  TAnimBlueprintAuditReport = record
    AnimBpCount: Integer;
    ValidCount: Integer;
    ErrorCount: Integer;
    TotalPoseNodeCount: Integer;
    TotalNotifyTrackCount: Integer;
    TotalTriggeredNotifies: Integer;
  end;

  { Scene spawner, pose evaluator, and Markdown report builder. }
  TAnimBlueprintHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class function FindFirstAnimBlueprint(const ADesignRoot: TComponent): TCastleAnimBlueprint; static;
    class function FindAnimBlueprintByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleAnimBlueprint; static;
    class procedure CollectAnimBlueprints(const ADesignRoot: TComponent;
      const AList: TList); static;

    class function SpawnAnimBlueprintPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TAnimBlueprintPreset;
      const AWorldPos: TVector3): TCastleAnimBlueprint; static;

    class function AuditAnimBlueprintsInDesign(
      const ADesignRoot: TComponent): TAnimBlueprintAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedBp: TCastleAnimBlueprint): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleUIControls;

class function TAnimBlueprintHelper.FindParentViewportItems(
  const ADesignRoot: TComponent): TCastleTransform;

  function SearchVp(const C: TComponent): TCastleViewport;
  var
    UI: TCastleUserInterface;
    I: Integer;
  begin
    Result := nil;
    if C = nil then Exit;
    if C is TCastleViewport then Exit(TCastleViewport(C));
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
      begin
        Result := SearchVp(UI.Controls[I]);
        if Result <> nil then Exit;
      end;
    end;
  end;

var
  VP: TCastleViewport;
begin
  Result := nil;
  if ADesignRoot = nil then Exit;
  if ADesignRoot is TCastleTransform then
    Exit(TCastleTransform(ADesignRoot));
  VP := SearchVp(ADesignRoot);
  if VP <> nil then
    Result := VP.Items;
end;

class procedure TAnimBlueprintHelper.CollectAnimBlueprints(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleAnimBlueprint) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Scan(UI.Controls[I]);
    end;
    if C is TCastleViewport then
      Scan(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
  end;

begin
  if AList = nil then Exit;
  Scan(ADesignRoot);
end;

class function TAnimBlueprintHelper.FindFirstAnimBlueprint(
  const ADesignRoot: TComponent): TCastleAnimBlueprint;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectAnimBlueprints(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleAnimBlueprint(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TAnimBlueprintHelper.FindAnimBlueprintByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleAnimBlueprint;
var
  L: TList;
  I: Integer;
  Found: TComponent;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstAnimBlueprint(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleAnimBlueprint then
      Exit(TCastleAnimBlueprint(Found));
  end;

  L := TList.Create;
  try
    CollectAnimBlueprints(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleAnimBlueprint(L[I]).Name, AName) then
        Exit(TCastleAnimBlueprint(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TAnimBlueprintHelper.SpawnAnimBlueprintPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TAnimBlueprintPreset;
  const AWorldPos: TVector3): TCastleAnimBlueprint;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastleAnimBlueprint.Create(ADesignOwner);
  case APreset of
    abpCombatSlotMontageOverride: BaseName := 'ABP_CombatSlotRig';
    abpAirborneJumpStateCrossfade: BaseName := 'ABP_JumpStateRig';
  else
    BaseName := 'ABP_LocomotionAimIK';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleAnimBlueprint, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TAnimBlueprintHelper.AuditAnimBlueprintsInDesign(
  const ADesignRoot: TComponent): TAnimBlueprintAuditReport;
var
  L: TList;
  ABP: TCastleAnimBlueprint;
  I: Integer;
begin
  Result := Default(TAnimBlueprintAuditReport);
  L := TList.Create;
  try
    CollectAnimBlueprints(ADesignRoot, L);
    Result.AnimBpCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      ABP := TCastleAnimBlueprint(L[I]);
      if ABP.LastEvaluationValid then
        Inc(Result.ValidCount)
      else
        Inc(Result.ErrorCount);
      Inc(Result.TotalPoseNodeCount, Length(ABP.Nodes));
      Inc(Result.TotalNotifyTrackCount, Length(ABP.Notifies));
      Inc(Result.TotalTriggeredNotifies, ABP.TriggeredNotifies.Count);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TAnimBlueprintHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedBp: TCastleAnimBlueprint): String;
var
  Audit: TAnimBlueprintAuditReport;
  SB: TStringList;
  S: TAnimBoneSlot;
  I: Integer;
begin
  Audit := AuditAnimBlueprintsInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# Animation Blueprint Editor Report (Phase 383 — UE 5.5 UAnimBlueprint Parity)');
    SB.Add('');
    SB.Add(Format('- **Scene AnimBlueprints**: `%d` (`%d` Valid, `%d` Errors)',
      [Audit.AnimBpCount, Audit.ValidCount, Audit.ErrorCount]));
    SB.Add(Format('- **Total Pose Nodes / Notify Tracks**: `%d` / `%d`',
      [Audit.TotalPoseNodeCount, Audit.TotalNotifyTrackCount]));
    if ASelectedBp <> nil then
    begin
      SB.Add('');
      SB.Add('## Active AnimBlueprint: `' + ASelectedBp.Name + '` ' + ASelectedBp.AnimBlueprintSummaryBadge);
      SB.Add(Format('- **Playhead**: `%.2fs` | **State**: `%s` | **UpperAimWeight**: `%.2f`',
        [ASelectedBp.PlayheadTimeSec, ASelectedBp.ActiveLocomotionState, ASelectedBp.UpperBodyAimWeight]));
      for S in TAnimBoneSlot do
        SB.Add(Format('- Bone `%s`: Pos `(%.2f, %.2f, %.2f)` Euler `(%.1f, %.1f, %.1f)`',
          [TCastleAnimBlueprint.BoneSlotName(S),
           ASelectedBp.CurrentPose.Bones[S].LocalOffset.X,
           ASelectedBp.CurrentPose.Bones[S].LocalOffset.Y,
           ASelectedBp.CurrentPose.Bones[S].LocalOffset.Z,
           ASelectedBp.CurrentPose.Bones[S].EulerDeg.X,
           ASelectedBp.CurrentPose.Bones[S].EulerDeg.Y,
           ASelectedBp.CurrentPose.Bones[S].EulerDeg.Z]));
      if ASelectedBp.TriggeredNotifies.Count > 0 then
      begin
        SB.Add('');
        SB.Add('### Triggered AnimNotifies');
        for I := 0 to ASelectedBp.TriggeredNotifies.Count - 1 do
          SB.Add('- `' + ASelectedBp.TriggeredNotifies[I] + '`');
      end;
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
