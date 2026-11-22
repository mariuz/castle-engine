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

{ Stateless scene authoring, cross-skeleton pose driver, and audit helper for
  the Unreal Engine 5.5-style Skeletal IK Retargeter
  (@link(TIkRetargeterHelper), @link(TIkRetargetSceneAuditReport))
  (Phase 387 — UE 5.5 UIKRetargeter Parity + 30th MCP Tool). }
unit ToolIkRetargeter;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleIkRetargeter;

type
  { Summary audit across all @link(TCastleIkRetargeter) rigs in a design. }
  TIkRetargetSceneAuditReport = record
    RetargeterCount: Integer;
    TotalMappedChains: Integer;
    IkEnabledChainCount: Integer;
    RefDeltaCompensatedCount: Integer;
    MaxLimbLengthErrorMeters: Single;
  end;

  { Scene spawner, batch IK retargeter auditor, and Markdown report builder. }
  TIkRetargeterHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectIkRetargeters(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstIkRetargeter(const ADesignRoot: TComponent): TCastleIkRetargeter; static;
    class function FindIkRetargeterByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleIkRetargeter; static;

    class function SpawnIkRetargetPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TIkRetargetPreset;
      const AWorldPos: TVector3): TCastleIkRetargeter; static;

    class function AuditIkRetargetersInDesign(
      const ADesignRoot: TComponent): TIkRetargetSceneAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedRig: TCastleIkRetargeter): String; static;
  end;

implementation

uses
  Math, CastleUtils, CastleClassUtils, CastleUIControls;

class function TIkRetargeterHelper.FindParentViewportItems(
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

class procedure TIkRetargeterHelper.CollectIkRetargeters(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleIkRetargeter) and (AList.IndexOf(C) < 0) then
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

class function TIkRetargeterHelper.FindFirstIkRetargeter(
  const ADesignRoot: TComponent): TCastleIkRetargeter;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectIkRetargeters(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleIkRetargeter(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TIkRetargeterHelper.FindIkRetargeterByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleIkRetargeter;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstIkRetargeter(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleIkRetargeter then
      Exit(TCastleIkRetargeter(Found));
  end;

  L := TList.Create;
  try
    CollectIkRetargeters(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleIkRetargeter(L[I]).Name, AName) then
        Exit(TCastleIkRetargeter(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TIkRetargeterHelper.SpawnIkRetargetPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TIkRetargetPreset;
  const AWorldPos: TVector3): TCastleIkRetargeter;
var
  ParentT: TCastleTransform;
  BaseName: String;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  Result := TCastleIkRetargeter.Create(ADesignOwner);
  case APreset of
    irpMannequinToBruteOgre:     BaseName := 'RTG_MannequinToOgre';
    irpTwoHandedGripIkRetarget: BaseName := 'RTG_TwoHandedGripIK';
  else
    BaseName := 'RTG_MannequinToStylized';
  end;
  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleIkRetargeter, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TIkRetargeterHelper.AuditIkRetargetersInDesign(
  const ADesignRoot: TComponent): TIkRetargetSceneAuditReport;
var
  L: TList;
  Rtg: TCastleIkRetargeter;
  I, C: Integer;
begin
  Result := Default(TIkRetargetSceneAuditReport);
  L := TList.Create;
  try
    CollectIkRetargeters(ADesignRoot, L);
    Result.RetargeterCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      Rtg := TCastleIkRetargeter(L[I]);
      Inc(Result.TotalMappedChains, Length(Rtg.Chains));
      if Rtg.CompensateRefPoseDelta then
        Inc(Result.RefDeltaCompensatedCount);
      for C := 0 to High(Rtg.Chains) do
        if Rtg.Chains[C].IkBlendWeight > 0.01 then
          Inc(Result.IkEnabledChainCount);
      Result.MaxLimbLengthErrorMeters := Max(
        Result.MaxLimbLengthErrorMeters, Rtg.MaxTargetLimbLengthError);
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TIkRetargeterHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedRig: TCastleIkRetargeter): String;
var
  Audit: TIkRetargetSceneAuditReport;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditIkRetargetersInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# Skeletal IK Retargeter Report (Phase 387 — UE 5.5 UIKRetargeter Parity)');
    SB.Add('');
    SB.Add(Format('- **IK Retargeters**: `%d` | **Mapped Chains**: `%d` | **IK-Active Chains**: `%d`',
      [Audit.RetargeterCount, Audit.TotalMappedChains, Audit.IkEnabledChainCount]));
    SB.Add(Format('- **Ref-Pose Delta Compensated**: `%d` | **Max Limb Drift**: `%.5f m`',
      [Audit.RefDeltaCompensatedCount, Audit.MaxLimbLengthErrorMeters]));
    if ASelectedRig <> nil then
    begin
      SB.Add('');
      SB.Add(Format('## Active Retargeter: `%s` (%s -> %s) %s',
        [ASelectedRig.Name,
         TCastleIkRetargeter.ProfileTitle(ASelectedRig.SourceProfile),
         TCastleIkRetargeter.ProfileTitle(ASelectedRig.TargetProfile),
         ASelectedRig.IkRetargetSummaryBadge]));
      for I := 0 to High(ASelectedRig.Chains) do
        SB.Add(Format('- **%s**: FK=`%.2f` IK=`%.2f` Stride=`%.2fx`',
          [TCastleIkRetargeter.ChainTitle(ASelectedRig.Chains[I].ChainId),
           ASelectedRig.Chains[I].FkRotationWeight,
           ASelectedRig.Chains[I].IkBlendWeight,
           ASelectedRig.Chains[I].StrideScale]));
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
