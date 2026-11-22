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

{ Stateless scene authoring, timeline playback driver, and audit helper for the
  Unreal Engine 5.5-style UMG Widget Animation Timeline & Anchor Slot Designer
  (@link(TWidgetAnimHelper), @link(TUmgWidgetSceneAuditReport))
  (Phase 386 — UE 5.5 UWidgetBlueprint Parity + 29th MCP Tool). }
unit ToolWidgetAnim;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleUIControls, CastleViewport,
  CastleWidgetAnim;

type
  { Summary audit across all @link(TCastleWidgetAnimator) instances in a design. }
  TUmgWidgetSceneAuditReport = record
    AnimatorCount: Integer;
    SlotCount: Integer;
    ClipCount: Integer;
    TrackCount: Integer;
    KeyframeCount: Integer;
    BindingCount: Integer;
  end;

  { Scene spawner, batch UMG auditor, and Markdown report builder. }
  TWidgetAnimHelper = class
  public
    class function FindParentUiHost(const ADesignRoot: TComponent): TCastleUserInterface; static;
    class procedure CollectWidgetAnimators(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstWidgetAnimator(const ADesignRoot: TComponent): TCastleWidgetAnimator; static;
    class function FindWidgetAnimatorByName(const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleWidgetAnimator; static;

    class function SpawnWidgetAnimPresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TUmgWidgetAnimPreset): TCastleWidgetAnimator; static;

    class function AuditWidgetAnimatorsInDesign(
      const ADesignRoot: TComponent): TUmgWidgetSceneAuditReport; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const ASelectedAnim: TCastleWidgetAnimator): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleTransform;

class function TWidgetAnimHelper.FindParentUiHost(
  const ADesignRoot: TComponent): TCastleUserInterface;
begin
  Result := nil;
  if ADesignRoot is TCastleUserInterface then
    Result := TCastleUserInterface(ADesignRoot);
end;

class procedure TWidgetAnimHelper.CollectWidgetAnimators(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleWidgetAnimator) and (AList.IndexOf(C) < 0) then
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

class function TWidgetAnimHelper.FindFirstWidgetAnimator(
  const ADesignRoot: TComponent): TCastleWidgetAnimator;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectWidgetAnimators(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleWidgetAnimator(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TWidgetAnimHelper.FindWidgetAnimatorByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleWidgetAnimator;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstWidgetAnimator(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleWidgetAnimator then
      Exit(TCastleWidgetAnimator(Found));
  end;

  L := TList.Create;
  try
    CollectWidgetAnimators(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleWidgetAnimator(L[I]).Name, AName) then
        Exit(TCastleWidgetAnimator(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TWidgetAnimHelper.SpawnWidgetAnimPresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TUmgWidgetAnimPreset): TCastleWidgetAnimator;
var
  HostUi: TCastleUserInterface;
  BaseName: String;
begin
  Result := nil;
  HostUi := FindParentUiHost(ADesignRoot);
  if HostUi = nil then Exit;

  Result := TCastleWidgetAnimator.Create(ADesignOwner);
  case APreset of
    uwapHudDamageToastAndHealthFlash: BaseName := 'WBP_HudDamageAndToast';
    uwapBossHealthBannerStretchReveal: BaseName := 'WBP_BossStretchBanner';
  else
    BaseName := 'WBP_ModalDialogAnim';
  end;

  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleWidgetAnimator, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  HostUi.InsertFront(Result);
  Result.ApplyPreset(APreset);
end;

class function TWidgetAnimHelper.AuditWidgetAnimatorsInDesign(
  const ADesignRoot: TComponent): TUmgWidgetSceneAuditReport;
var
  L: TList;
  WA: TCastleWidgetAnimator;
  I: Integer;
begin
  Result := Default(TUmgWidgetSceneAuditReport);
  L := TList.Create;
  try
    CollectWidgetAnimators(ADesignRoot, L);
    Result.AnimatorCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      WA := TCastleWidgetAnimator(L[I]);
      Inc(Result.SlotCount, Length(WA.Slots));
      Inc(Result.ClipCount, Length(WA.Clips));
      Inc(Result.TrackCount, WA.TotalTrackCount);
      Inc(Result.KeyframeCount, WA.TotalKeyframeCount);
      Inc(Result.BindingCount, Length(WA.Bindings));
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TWidgetAnimHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const ASelectedAnim: TCastleWidgetAnimator): String;
var
  Audit: TUmgWidgetSceneAuditReport;
  SB: TStringList;
  I: Integer;
begin
  Audit := AuditWidgetAnimatorsInDesign(ADesignRoot);
  SB := TStringList.Create;
  try
    SB.Add('# UMG Widget Animation Timeline & Anchor Slot Report (Phase 386 — UWidgetBlueprint Parity)');
    SB.Add('');
    SB.Add(Format('- **Widget Animators**: `%d` | **Slots**: `%d` | **Clips**: `%d`',
      [Audit.AnimatorCount, Audit.SlotCount, Audit.ClipCount]));
    SB.Add(Format('- **Tracks**: `%d` | **Keyframes**: `%d` | **UI Event Bindings**: `%d`',
      [Audit.TrackCount, Audit.KeyframeCount, Audit.BindingCount]));
    if ASelectedAnim <> nil then
    begin
      SB.Add('');
      SB.Add('## Active Widget Blueprint: `' + ASelectedAnim.Name + '` ' +
        ASelectedAnim.WidgetAnimSummaryBadge);
      for I := 0 to High(ASelectedAnim.Slots) do
        SB.Add(Format('- Slot **%s** (`%s`) Pos=`(%.1f, %.1f)` Scale=`%.2f` Opacity=`%.2f`',
          [ASelectedAnim.Slots[I].WidgetName,
           TCastleWidgetAnimator.AnchorPresetTitle(ASelectedAnim.Slots[I].AnchorPreset),
           ASelectedAnim.Slots[I].EvalTransX,
           ASelectedAnim.Slots[I].EvalTransY,
           ASelectedAnim.Slots[I].EvalScale,
           ASelectedAnim.Slots[I].EvalOpacity]));
    end;
    Result := SB.Text;
  finally
    FreeAndNil(SB);
  end;
end;

end.
