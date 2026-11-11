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

{ Automated tests for @link(TResponsiveUiSimulator) across Desktop 16:9,
  Ultrawide 21:9, Handheld 16:10, Mobile Notch 19.5:9, and Tablet 4:3
  (Phase 295 — UE 5.9 / 6.0 CommonUI Responsive Parity). }
unit TestToolResponsiveSim;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolResponsiveSim = class(TCastleTestCase)
  published
    procedure TestCleanAnchoredHudPassesAllFiveAspectAndNotchProfiles;
    procedure TestNotchIntrusionOffScreenSiblingOverlapAndTouchTargetViolations;
  end;

implementation

uses
  CastleVectors, CastleUIControls, CastleControls,
  ToolResponsiveSim;

procedure TTestToolResponsiveSim.TestCleanAnchoredHudPassesAllFiveAspectAndNotchProfiles;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  BtnPlay, BtnSettings: TCastleButton;
  LblTitle: TCastleLabel;
  Sum: TResponsiveAuditSummary;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootHud';
    RootUi.FullSize := true;

    { Centered title near top with generous safe margin }
    LblTitle := TCastleLabel.Create(DesignOwner);
    LblTitle.Name := 'LabelTitle';
    LblTitle.Caption := 'CASTLE CHRONICLES';
    LblTitle.FontSize := 36;
    LblTitle.HorizontalAnchorParent := hpMiddle;
    LblTitle.HorizontalAnchorSelf := hpMiddle;
    LblTitle.VerticalAnchorParent := vpTop;
    LblTitle.VerticalAnchorSelf := vpTop;
    LblTitle.Translation := Vector2(0, -80);
    RootUi.InsertFront(LblTitle);

    { Centered buttons well above bottom home bar and >= 80 px tall (> 44 px on 800p Deck) }
    BtnPlay := TCastleButton.Create(DesignOwner);
    BtnPlay.Name := 'ButtonPlay';
    BtnPlay.AutoSize := false;
    BtnPlay.Width := 280;
    BtnPlay.Height := 84;
    BtnPlay.HorizontalAnchorParent := hpMiddle;
    BtnPlay.HorizontalAnchorSelf := hpMiddle;
    BtnPlay.VerticalAnchorParent := vpMiddle;
    BtnPlay.VerticalAnchorSelf := vpMiddle;
    BtnPlay.Translation := Vector2(0, 60);
    RootUi.InsertFront(BtnPlay);

    BtnSettings := TCastleButton.Create(DesignOwner);
    BtnSettings.Name := 'ButtonSettings';
    BtnSettings.AutoSize := false;
    BtnSettings.Width := 280;
    BtnSettings.Height := 84;
    BtnSettings.HorizontalAnchorParent := hpMiddle;
    BtnSettings.HorizontalAnchorSelf := hpMiddle;
    BtnSettings.VerticalAnchorParent := vpMiddle;
    BtnSettings.VerticalAnchorSelf := vpMiddle;
    BtnSettings.Translation := Vector2(0, -60);
    RootUi.InsertFront(BtnSettings);

    Sum := TResponsiveUiSimulator.AuditAllProfiles(RootUi);
    AssertEquals(0, Sum.TotalIssueCount);
    AssertEquals(0, Sum.OffScreenCount);
    AssertEquals(0, Sum.SafeAreaCount);
    AssertEquals(0, Sum.OverlapCount);
    AssertEquals(0, Sum.TouchTargetCount);

    { Ultrawide 21:9 (2560x1080) should keep ButtonPlay centered at X = (2560 - 280)/2 = 1140 }
    AssertSameValue(1140.0, Sum.Results[rdpUltrawide21x9].Boxes[2].DeviceRect.Left, 1.0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolResponsiveSim.TestNotchIntrusionOffScreenSiblingOverlapAndTouchTargetViolations;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  BtnLeftEdge, BtnTinyTouch, BoxOverlapA, BoxOverlapB, LblOffScreen: TCastleUserInterface;
  Sum: TResponsiveAuditSummary;
  MobileRes: TResponsiveProfileSimResult;
  MdReport: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootHud';
    RootUi.FullSize := true;

    { 1. Flush left-edge button at X = 8 -> safe on Desktop 16:9, intrudes into 132 px Mobile Notch! }
    BtnLeftEdge := TCastleButton.Create(DesignOwner);
    BtnLeftEdge.Name := 'ButtonPauseFlushLeft';
    TCastleButton(BtnLeftEdge).AutoSize := false;
    BtnLeftEdge.Width := 90;
    BtnLeftEdge.Height := 72;
    BtnLeftEdge.HorizontalAnchorParent := hpLeft;
    BtnLeftEdge.HorizontalAnchorSelf := hpLeft;
    BtnLeftEdge.VerticalAnchorParent := vpTop;
    BtnLeftEdge.VerticalAnchorSelf := vpTop;
    BtnLeftEdge.Translation := Vector2(8, -20);
    RootUi.InsertFront(BtnLeftEdge);

    { 2. Tiny 24x24 px button -> violates 44 px minimum touch target on Handheld/Mobile/Tablet }
    BtnTinyTouch := TCastleButton.Create(DesignOwner);
    BtnTinyTouch.Name := 'ButtonTinyClose';
    TCastleButton(BtnTinyTouch).AutoSize := false;
    BtnTinyTouch.Width := 24;
    BtnTinyTouch.Height := 24;
    BtnTinyTouch.HorizontalAnchorParent := hpMiddle;
    BtnTinyTouch.HorizontalAnchorSelf := hpMiddle;
    BtnTinyTouch.VerticalAnchorParent := vpMiddle;
    BtnTinyTouch.VerticalAnchorSelf := vpMiddle;
    BtnTinyTouch.Translation := Vector2(300, 200);
    RootUi.InsertFront(BtnTinyTouch);

    { 3. Two overlapping sibling controls at center }
    BoxOverlapA := TCastleLabel.Create(DesignOwner);
    BoxOverlapA.Name := 'LabelScoreA';
    TCastleLabel(BoxOverlapA).AutoSize := false;
    BoxOverlapA.Width := 160;
    BoxOverlapA.Height := 60;
    BoxOverlapA.HorizontalAnchorParent := hpMiddle;
    BoxOverlapA.HorizontalAnchorSelf := hpMiddle;
    BoxOverlapA.VerticalAnchorParent := vpMiddle;
    BoxOverlapA.VerticalAnchorSelf := vpMiddle;
    RootUi.InsertFront(BoxOverlapA);

    BoxOverlapB := TCastleLabel.Create(DesignOwner);
    BoxOverlapB.Name := 'LabelScoreB';
    TCastleLabel(BoxOverlapB).AutoSize := false;
    BoxOverlapB.Width := 160;
    BoxOverlapB.Height := 60;
    BoxOverlapB.HorizontalAnchorParent := hpMiddle;
    BoxOverlapB.HorizontalAnchorSelf := hpMiddle;
    BoxOverlapB.VerticalAnchorParent := vpMiddle;
    BoxOverlapB.VerticalAnchorSelf := vpMiddle;
    BoxOverlapB.Translation := Vector2(20, 10);
    RootUi.InsertFront(BoxOverlapB);

    { 4. Hardcoded X = 1850 offset from left -> clips off-screen on 1920x1080 (1850 + 140 = 1990 > 1920) }
    LblOffScreen := TCastleLabel.Create(DesignOwner);
    LblOffScreen.Name := 'LabelHardcodedRight';
    TCastleLabel(LblOffScreen).AutoSize := false;
    LblOffScreen.Width := 140;
    LblOffScreen.Height := 50;
    LblOffScreen.Translation := Vector2(1850, 200);
    RootUi.InsertFront(LblOffScreen);

    MobileRes := TResponsiveUiSimulator.SimulateProfile(RootUi, rdpMobileNotch195x9);
    AssertTrue(Length(MobileRes.Issues) >= 3);

    Sum := TResponsiveUiSimulator.AuditAllProfiles(RootUi);
    AssertTrue(Sum.OffScreenCount > 0);
    AssertTrue(Sum.SafeAreaCount > 0);
    AssertTrue(Sum.OverlapCount > 0);
    AssertTrue(Sum.TouchTargetCount > 0);

    MdReport := TResponsiveUiSimulator.FormatResponsiveAuditMarkdown(RootUi);
    AssertTrue(Pos('# Castle Multi-Resolution Responsive UI & Safe-Area Audit', MdReport) > 0);
    AssertTrue(Pos('Mobile Notch Landscape', MdReport) > 0);
    AssertTrue(Pos('ButtonPauseFlushLeft', MdReport) > 0);
    AssertTrue(Pos('ButtonTinyClose', MdReport) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolResponsiveSim);
end.
