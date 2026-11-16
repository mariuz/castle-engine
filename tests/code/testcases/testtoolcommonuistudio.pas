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

{ Automated unit tests for Phase 332 CommonUI Gamepad Spatial 2D Focus Router,
  Activatable Modal Layer Stack, Input-Device Prompt Glyph Switcher & Two-Way
  MVVM ViewModel RTTI Binder Studio (@link(CastleCommonUiMvvm),
  @link(ToolCommonUiStudio)). }
unit TestToolCommonUiStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolCommonUiStudio = class(TCastleTestCase)
  published
    procedure TestSpatialDPadConeNavigationModalStackIsolationAndDevicePromptGlyphs;
    procedure TestMvvmFormattedOneWayPushTwoWaySliderCheckboxPullAndJsonRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleUIControls, CastleControls, CastleComponentSerialize,
  CastleCommonUiMvvm, ToolCommonUiStudio;

procedure TTestToolCommonUiStudio.TestSpatialDPadConeNavigationModalStackIsolationAndDevicePromptGlyphs;
var
  DesignOwner: TComponent;
  RootUi, MenuRoot, PopupLayer: TCastleUserInterface;
  Router: TCastleCommonUiRouter;
  Binder: TCastleMvvmBinder;
  PromptLbl: TCastleLabel;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    TCommonUiStudioHelper.SpawnCommonUiMenuAndMvvmHudDemo(
      RootUi, DesignOwner, MenuRoot, PopupLayer, Router, Binder);

    AssertTrue(Router <> nil);
    AssertTrue(Router.FocusedControl <> nil);
    AssertEquals('BtnPlayCampaign', Router.FocusedControl.Name);

    { 1. 2x2 Spatial D-Pad Cone Navigation: TopLeft -> TopRight -> BottomRight -> BottomLeft -> TopLeft }
    AssertTrue(Router.NavigateDirection(cndRight));
    AssertEquals('BtnLoadoutArmory', Router.FocusedControl.Name);

    AssertTrue(Router.NavigateDirection(cndDown));
    AssertEquals('BtnSettingsOptions', Router.FocusedControl.Name);

    AssertTrue(Router.NavigateDirection(cndLeft));
    AssertEquals('BtnCoopMultiplayer', Router.FocusedControl.Name);

    AssertTrue(Router.NavigateDirection(cndUp));
    AssertEquals('BtnPlayCampaign', Router.FocusedControl.Name);

    { 2. Push Activatable Modal Layer -> isolates D-Pad inside popup & restores prior focus on Pop! }
    Router.NavigateDirection(cndRight);
    AssertEquals('BtnLoadoutArmory', Router.FocusedControl.Name);

    Router.PushActivatableLayer(PopupLayer);
    AssertEquals(1, Router.ModalStackDepth);
    AssertEquals(2, Router.FocusableCountInActiveLayer);
    AssertEquals('BtnPopupConfirm', Router.FocusedControl.Name);

    AssertTrue(Router.NavigateDirection(cndRight));
    AssertEquals('BtnPopupCancel', Router.FocusedControl.Name);
    { Up/Down inside 2-button horizontal modal cannot leak to background menu buttons }
    AssertFalse(Router.NavigateDirection(cndDown));
    AssertEquals('BtnPopupCancel', Router.FocusedControl.Name);

    AssertTrue(Router.PopActivatableLayer);
    AssertEquals(0, Router.ModalStackDepth);
    AssertFalse(PopupLayer.Exists);
    AssertEquals('BtnLoadoutArmory', Router.FocusedControl.Name);

    { 3. Dynamic Input-Device Prompt Glyph Switching (KB/Mouse -> Xbox -> PS5 DualSense) }
    PromptLbl := DesignOwner.FindComponent('LabelCommonPromptLegend') as TCastleLabel;
    AssertTrue(PromptLbl <> nil);
    AssertTrue(Pos('[Enter]', PromptLbl.Caption) > 0);

    Router.ActiveDevice := idfXboxController;
    Router.RefreshPromptLabels(DesignOwner);
    AssertTrue(Pos('(A)', PromptLbl.Caption) > 0);
    AssertTrue(Pos('[LB]/[RB]', PromptLbl.Caption) > 0);

    Router.ActiveDevice := idfPlayStationDualSense;
    Router.RefreshPromptLabels(DesignOwner);
    AssertTrue(Pos('(Cross)', PromptLbl.Caption) > 0);
    AssertTrue(Pos('(Circle)', PromptLbl.Caption) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolCommonUiStudio.TestMvvmFormattedOneWayPushTwoWaySliderCheckboxPullAndJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  RootUi, MenuRoot, PopupLayer: TCastleUserInterface;
  Router: TCastleCommonUiRouter;
  Binder, RestoredBinder: TCastleMvvmBinder;
  HpBar: TCastleRectangleControl;
  HpLbl: TCastleLabel;
  VolSlider: TCastleFloatSlider;
  ChkSub: TCastleCheckbox;
  SavedJson, Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    TCommonUiStudioHelper.SpawnCommonUiMenuAndMvvmHudDemo(
      RootUi, DesignOwner, MenuRoot, PopupLayer, Router, Binder);

    HpBar := DesignOwner.FindComponent('MvvmHealthBarFill') as TCastleRectangleControl;
    HpLbl := DesignOwner.FindComponent('MvvmHealthLabel') as TCastleLabel;
    VolSlider := DesignOwner.FindComponent('MvvmMasterVolumeSlider') as TCastleFloatSlider;
    ChkSub := DesignOwner.FindComponent('MvvmSubtitlesCheckbox') as TCastleCheckbox;

    { 1. One-way scaled & formatted ViewModel -> UI push }
    Binder.SetFloat('HealthRatio', 0.35);
    AssertEquals(4, Binder.PushViewModelToUi(MenuRoot, DesignOwner));
    AssertSameValue(84.0, HpBar.Width, 0.01); // 0.35 * 240.0
    AssertEquals('HP: 35%', HpLbl.Caption);

    { 2. Two-way UI -> ViewModel pull on Slider.Value & Checkbox.Checked }
    VolSlider.Value := 0.42;
    ChkSub.Checked := False;
    AssertEquals(2, Binder.PullUiToViewModel(MenuRoot, DesignOwner));
    AssertSameValue(0.42, Binder.GetFloat('MasterVolume', 0.0), 1e-4);
    AssertFalse(Binder.GetBool('SubtitlesEnabled', True));

    { 3. JSON serialization roundtrip }
    SavedJson := ComponentToString(Binder);
    RestoredOwner := TComponent.Create(nil);
    try
      RestoredBinder := StringToComponent(SavedJson, RestoredOwner) as TCastleMvvmBinder;
      AssertEquals(4, RestoredBinder.BindingCount);
      AssertSameValue(0.42, RestoredBinder.GetFloat('MasterVolume', 0.0), 1e-4);
      AssertFalse(RestoredBinder.GetBool('SubtitlesEnabled', True));
    finally
      FreeAndNil(RestoredOwner);
    end;

    Md := TCommonUiStudioHelper.BuildMarkdownReport(RootUi, DesignOwner);
    AssertTrue(Pos('CommonUI Gamepad Focus & MVVM ViewModel Report', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolCommonUiStudio);
end.
