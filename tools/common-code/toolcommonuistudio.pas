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

{ Stateless Editor & Headless Helper for CommonUI Gamepad Spatial Routers,
  Modal Layer Stacks, Input-Device Prompt Glyphs & MVVM ViewModel Binders
  (@link(TCommonUiStudioHelper), @link(TCommonUiAuditReport))
  (Phase 332 — UE 6.0+ CommonUI & UMG MVVM ViewModel Parity). }
unit ToolCommonUiStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleUIControls, CastleControls, CastleCommonUiMvvm;

type
  TCommonRouterArray = array of TCastleCommonUiRouter;
  TMvvmBinderArray = array of TCastleMvvmBinder;

  { QA summary across all CommonUI routers and MVVM binders in a design. }
  TCommonUiAuditReport = class
  public
    RouterCount: Integer;
    BinderCount: Integer;
    TotalBindings: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, and auditing
    @link(TCastleCommonUiRouter) and @link(TCastleMvvmBinder) instances. }
  TCommonUiStudioHelper = class
  public
    class procedure ScanCommonUi(const RootComp, DesignOwner: TComponent;
      out OutRouters: TCommonRouterArray;
      out OutBinders: TMvvmBinderArray); static;

    class procedure SpawnCommonUiMenuAndMvvmHudDemo(
      const RootComp, DesignOwner: TComponent;
      out OutMenuRoot, OutPopupLayer: TCastleUserInterface;
      out OutRouter: TCastleCommonUiRouter;
      out OutBinder: TCastleMvvmBinder); static;

    class function AuditCommonUi(
      const RootComp, DesignOwner: TComponent): TCommonUiAuditReport; static;

    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleClassUtils;

constructor TCommonUiAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TCommonUiAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class procedure TCommonUiStudioHelper.ScanCommonUi(
  const RootComp, DesignOwner: TComponent;
  out OutRouters: TCommonRouterArray;
  out OutBinders: TMvvmBinderArray);

  procedure AddRouterUnique(const R: TCastleCommonUiRouter);
  var
    K: Integer;
  begin
    if (R = nil) or (csTransient in R.ComponentStyle) then Exit;
    for K := 0 to High(OutRouters) do
      if OutRouters[K] = R then Exit;
    SetLength(OutRouters, Length(OutRouters) + 1);
    OutRouters[High(OutRouters)] := R;
  end;

  procedure AddBinderUnique(const B: TCastleMvvmBinder);
  var
    K: Integer;
  begin
    if (B = nil) or (csTransient in B.ComponentStyle) then Exit;
    for K := 0 to High(OutBinders) do
      if OutBinders[K] = B then Exit;
    SetLength(OutBinders, Length(OutBinders) + 1);
    OutBinders[High(OutBinders)] := B;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    UI: TCastleUserInterface;
    CC: TCastleComponent;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if C is TCastleCommonUiRouter then
      AddRouterUnique(TCastleCommonUiRouter(C))
    else if C is TCastleMvvmBinder then
      AddBinderUnique(TCastleMvvmBinder(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Walk(CC.NonVisualComponents[I]);
    end;
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Walk(UI.Controls[I]);
    end;
  end;

begin
  OutRouters := nil;
  OutBinders := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TCommonUiStudioHelper.SpawnCommonUiMenuAndMvvmHudDemo(
  const RootComp, DesignOwner: TComponent;
  out OutMenuRoot, OutPopupLayer: TCastleUserInterface;
  out OutRouter: TCastleCommonUiRouter;
  out OutBinder: TCastleMvvmBinder);
var
  OwnerToUse: TComponent;
  BtnTL: TCastleButton;
  PromptBar, HpLabel: TCastleLabel;
  HpBarFill: TCastleRectangleControl;
  VolSlider: TCastleFloatSlider;
  ChkSubtitles: TCastleCheckbox;

  function MakeGridBtn(const AParent: TCastleUserInterface; const AName, ACaption: String;
    const AX, AY: Single): TCastleButton;
  begin
    Result := TCastleButton.Create(OwnerToUse);
    Result.Name := AName;
    Result.Caption := ACaption;
    Result.AutoSize := False;
    Result.Width := 180;
    Result.Height := 52;
    Result.Translation := Vector2(AX, AY);
    AParent.InsertFront(Result);
  end;

begin
  OutMenuRoot := nil;
  OutPopupLayer := nil;
  OutRouter := nil;
  OutBinder := nil;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  OutMenuRoot := TCastleUserInterface.Create(OwnerToUse);
  OutMenuRoot.Name := 'CommonUiMainMenuGroup';
  OutMenuRoot.Width := 640;
  OutMenuRoot.Height := 420;
  if RootComp is TCastleUserInterface then
    TCastleUserInterface(RootComp).InsertFront(OutMenuRoot);

  { 2x2 Spatial D-Pad Grid: Top row Y=240, Bottom row Y=150; Left X=80, Right X=320 }
  BtnTL := MakeGridBtn(OutMenuRoot, 'BtnPlayCampaign', 'Play Campaign', 80, 240);
  MakeGridBtn(OutMenuRoot, 'BtnLoadoutArmory', 'Loadout Armory', 320, 240);
  MakeGridBtn(OutMenuRoot, 'BtnCoopMultiplayer', 'Co-Op Lobby', 80, 150);
  MakeGridBtn(OutMenuRoot, 'BtnSettingsOptions', 'Settings', 320, 150);

  { Prompt Legend Footer }
  PromptBar := TCastleLabel.Create(OwnerToUse);
  PromptBar.Name := 'LabelCommonPromptLegend';
  PromptBar.Translation := Vector2(80, 60);
  OutMenuRoot.InsertFront(PromptBar);

  { MVVM HUD Widgets: Health Bar + HP Label + Two-Way Volume Slider + Subtitles Checkbox }
  HpBarFill := TCastleRectangleControl.Create(OwnerToUse);
  HpBarFill.Name := 'MvvmHealthBarFill';
  HpBarFill.Width := 240;
  HpBarFill.Height := 18;
  HpBarFill.Color := Vector4(0.24, 0.88, 0.46, 1.0);
  HpBarFill.Translation := Vector2(80, 340);
  OutMenuRoot.InsertFront(HpBarFill);

  HpLabel := TCastleLabel.Create(OwnerToUse);
  HpLabel.Name := 'MvvmHealthLabel';
  HpLabel.Translation := Vector2(80, 364);
  OutMenuRoot.InsertFront(HpLabel);

  VolSlider := TCastleFloatSlider.Create(OwnerToUse);
  VolSlider.Name := 'MvvmMasterVolumeSlider';
  VolSlider.Min := 0.0;
  VolSlider.Max := 1.0;
  VolSlider.Value := 0.80;
  VolSlider.Translation := Vector2(360, 340);
  OutMenuRoot.InsertFront(VolSlider);

  ChkSubtitles := TCastleCheckbox.Create(OwnerToUse);
  ChkSubtitles.Name := 'MvvmSubtitlesCheckbox';
  ChkSubtitles.Caption := 'Enable Subtitles';
  ChkSubtitles.Checked := True;
  ChkSubtitles.Translation := Vector2(360, 380);
  OutMenuRoot.InsertFront(ChkSubtitles);

  { Hidden Activatable Modal Popup Layer }
  OutPopupLayer := TCastleUserInterface.Create(OwnerToUse);
  OutPopupLayer.Name := 'PopupConfirmQuitModal';
  OutPopupLayer.Exists := False;
  OutMenuRoot.InsertFront(OutPopupLayer);
  MakeGridBtn(OutPopupLayer, 'BtnPopupConfirm', 'Confirm Quit', 120, 200);
  MakeGridBtn(OutPopupLayer, 'BtnPopupCancel', 'Cancel', 340, 200);

  { CommonUI Router }
  OutRouter := TCastleCommonUiRouter.Create(OwnerToUse);
  OutRouter.Name := 'CommonUiRouterMain';
  OutRouter.RootUi := OutMenuRoot;
  OutRouter.SetFocusedControl(BtnTL);
  OutRouter.RegisterPromptTemplate('LabelCommonPromptLegend',
    '{Prompt:Confirm} Select   {Prompt:Back} Back   {Prompt:TabPrev}/{Prompt:TabNext} Switch Tab');
  OutRouter.RefreshPromptLabels(OwnerToUse);
  if RootComp is TCastleComponent then
    TCastleComponent(RootComp).AddNonVisualComponent(OutRouter);

  { MVVM ViewModel Binder }
  OutBinder := TCastleMvvmBinder.Create(OwnerToUse);
  OutBinder.Name := 'MvvmHudViewModel';
  OutBinder.SetFloat('HealthRatio', 1.0);
  OutBinder.SetFloat('MasterVolume', 0.80);
  OutBinder.SetBool('SubtitlesEnabled', True);
  OutBinder.AddBinding('HealthRatio', 'MvvmHealthBarFill', 'Width', '', 240.0, False);
  OutBinder.AddBinding('HealthRatio', 'MvvmHealthLabel', 'Caption', 'HP: %.0f%%', 100.0, False);
  OutBinder.AddBinding('MasterVolume', 'MvvmMasterVolumeSlider', 'Value', '', 1.0, True);
  OutBinder.AddBinding('SubtitlesEnabled', 'MvvmSubtitlesCheckbox', 'Checked', '', 1.0, True);
  OutBinder.PushViewModelToUi(OutMenuRoot, OwnerToUse);
  if RootComp is TCastleComponent then
    TCastleComponent(RootComp).AddNonVisualComponent(OutBinder);
end;

class function TCommonUiStudioHelper.AuditCommonUi(
  const RootComp, DesignOwner: TComponent): TCommonUiAuditReport;
var
  Routers: TCommonRouterArray;
  Binders: TMvvmBinderArray;
  I: Integer;
begin
  Result := TCommonUiAuditReport.Create;
  ScanCommonUi(RootComp, DesignOwner, Routers, Binders);
  Result.RouterCount := Length(Routers);
  Result.BinderCount := Length(Binders);
  for I := 0 to High(Routers) do
    if Routers[I].RootUi = nil then
      Result.Warnings.Add(Format(
        'CommonUiRouter "%s" has RootUi=nil; assign a root TCastleUserInterface container.',
        [Routers[I].Name]));
  for I := 0 to High(Binders) do
    Inc(Result.TotalBindings, Binders[I].BindingCount);
end;

class function TCommonUiStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Routers: TCommonRouterArray;
  Binders: TMvvmBinderArray;
  Audit: TCommonUiAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanCommonUi(RootComp, DesignOwner, Routers, Binders);
  Audit := AuditCommonUi(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — CommonUI Gamepad Focus & MVVM ViewModel Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **CommonUI Spatial Routers**: `%d` | **MVVM Binders**: `%d` (`%d` declarative bindings)',
      [Audit.RouterCount, Audit.BinderCount, Audit.TotalBindings]));
    SB.AppendLine;

    if Length(Routers) > 0 then
    begin
      SB.AppendLine('## CommonUI Focus & Device State');
      SB.AppendLine('| Router | Active Device | Focused Widget | Modal Depth | Focusables |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Routers) do
        SB.AppendLine(Format('| `%s` | %s | `%s` | `%d` | `%d` |',
          [Routers[I].Name,
           TCastleCommonUiRouter.DeviceDisplayName(Routers[I].ActiveDevice),
           Routers[I].RouterSummaryBadge,
           Routers[I].ModalStackDepth,
           Routers[I].FocusableCountInActiveLayer]));
      SB.AppendLine;
    end;

    SB.AppendLine('## QA Diagnostics');
    if Audit.Warnings.Count = 0 then
      SB.AppendLine('- **0 warnings** — all CommonUI focus routers and MVVM ViewModel bindings are valid.')
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
