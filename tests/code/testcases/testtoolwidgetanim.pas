{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automated tests for Phase 386: UMG Widget Animation Timeline & Anchor Slot
  Designer (UWidgetBlueprint Parity: Multi-Track Opacity/Translation/Scale/Color
  Timeline, BackOvershoot & BounceOut Easing, Forward/Reverse/PingPong
  PlayAnimation, UI Event Bindings, 14-Mode 9-Point + Stretch Anchor Flower,
  106-Studio Hub & 29th MCP Tool cge_animate_umg_widget). }
unit TestToolWidgetAnim;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolWidgetAnim = class(TCastleTestCase)
  published
    procedure TestModalSlideBounceBackOvershootForwardReverseHoverAndCleanJsonRoundtrip;
    procedure Test9PointAnchorFlowerPresetsStretchSlotsAndPingPongPlayback;
    procedure TestUnified106StudioHubAnd29thMcpAnimateUmgWidgetTool;
  end;

implementation

uses
  Math, fpjson, jsonparser,
  CastleVectors, CastleUIControls, CastleControls, CastleComponentSerialize,
  CastleWidgetAnim, ToolWidgetAnim, ToolStudioHub, ToolMcpServer;

procedure TTestToolWidgetAnim.TestModalSlideBounceBackOvershootForwardReverseHoverAndCleanJsonRoundtrip;
var
  Root, LoadOwner: TComponent;
  UiHost: TCastleUserInterface;
  Anim, LoadedAnim: TCastleWidgetAnimator;
  ModalIdx, BtnIdx: Integer;
  JsonStr: String;
begin
  { 1. Verify BackOvershoot (> 1.0 mid-curve) & BounceOut exact endpoint invariants }
  AssertSameValue(0.0, TCastleWidgetAnimator.EvaluateUmgEasing(uaeBackOvershootOut, 0.0), 1e-4);
  AssertSameValue(1.0, TCastleWidgetAnimator.EvaluateUmgEasing(uaeBackOvershootOut, 1.0), 1e-4);
  AssertTrue('BackOvershoot exceeds 1.0 before settling at 1.0',
    TCastleWidgetAnimator.EvaluateUmgEasing(uaeBackOvershootOut, 0.65) > 1.04);
  AssertSameValue(1.0, TCastleWidgetAnimator.EvaluateUmgEasing(uaeBounceOut, 1.0), 1e-4);

  Root := TComponent.Create(nil);
  try
    UiHost := TCastleUserInterface.Create(Root);
    UiHost.Name := 'RootUiCanvas';

    Anim := TWidgetAnimHelper.SpawnWidgetAnimPresetInDesign(
      UiHost, Root, uwapModalPopupSlideBounceAndFade);
    AssertTrue(Anim <> nil);
    AssertEquals(3, Length(Anim.Slots));
    AssertEquals(2, Length(Anim.Clips));

    ModalIdx := Anim.FindSlotIndex('ModalCard');
    BtnIdx := Anim.FindSlotIndex('ConfirmBtn');
    AssertTrue((ModalIdx >= 0) and (BtnIdx >= 0));

    { 2. Trigger OnShow -> plays Anim_ModalOpen forward (0.60s) }
    AssertEquals(1, Anim.FireUiEvent('', uetOnShow));
    AssertTrue(Anim.Playing);
    AssertSameValue(0.0, Anim.Slots[ModalIdx].EvalOpacity, 1e-3);
    AssertSameValue(-140.0, Anim.Slots[ModalIdx].EvalTransY, 1e-3);

    { Mid-animation at 0.39s (65% of 0.60s) -> Scale overshoots > 1.00! }
    Anim.StepAnimator(0.39);
    AssertTrue('ModalCard scale overshoots > 1.00 during BackOvershootOut',
      Anim.Slots[ModalIdx].EvalScale > 1.01);

    { Finish remaining 0.25s -> clamps cleanly at 0.60s settled target }
    Anim.StepAnimator(0.25);
    AssertFalse(Anim.Playing);
    AssertSameValue(1.0, Anim.Slots[ModalIdx].EvalOpacity, 1e-3);
    AssertSameValue(0.0, Anim.Slots[ModalIdx].EvalTransY, 1e-3);
    AssertSameValue(1.0, Anim.Slots[ModalIdx].EvalScale, 1e-3);

    { 3. HoverEnter plays Anim_ButtonHover Forward (1.0 -> 1.15); HoverLeave plays Reverse (1.15 -> 1.0)! }
    AssertEquals(1, Anim.FireUiEvent('ConfirmBtn', uetOnHoverEnter));
    Anim.StepAnimator(0.20);
    AssertSameValue(1.15, Anim.Slots[BtnIdx].EvalScale, 1e-3);

    AssertEquals(1, Anim.FireUiEvent('ConfirmBtn', uetOnHoverLeave));
    AssertTrue(Anim.PlayMode = upmReverse);
    Anim.StepAnimator(0.20);
    AssertSameValue(1.00, Anim.Slots[BtnIdx].EvalScale, 1e-3);

    { 4. SetTransient-clean JSON serialization roundtrip }
    JsonStr := ComponentToString(Anim);
    AssertTrue('SetTransient UMG_PreviewRoot must not leak into serialized JSON',
      Pos('UMG_PreviewRoot', JsonStr) = 0);

    LoadOwner := TComponent.Create(nil);
    try
      LoadedAnim := StringToComponent(JsonStr, LoadOwner) as TCastleWidgetAnimator;
      AssertTrue(LoadedAnim <> nil);
      AssertEquals(3, Length(LoadedAnim.Slots));
      AssertEquals(2, Length(LoadedAnim.Clips));
      AssertEquals(3, Length(LoadedAnim.Bindings));
    finally
      FreeAndNil(LoadOwner);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolWidgetAnim.Test9PointAnchorFlowerPresetsStretchSlotsAndPingPongPlayback;
var
  Root: TComponent;
  UiHost: TCastleUserInterface;
  TestBox: TCastleRectangleControl;
  HudAnim: TCastleWidgetAnimator;
  MinUV, MaxUV: TVector2;
  HpIdx: Integer;
begin
  Root := TComponent.Create(nil);
  try
    UiHost := TCastleUserInterface.Create(Root);
    UiHost.Name := 'RootUiCanvas';

    TestBox := TCastleRectangleControl.Create(Root);
    TestBox.Name := 'HudCard';
    TestBox.Width := 200;
    TestBox.Height := 60;
    UiHost.InsertFront(TestBox);

    { 1. Verify Top-Right (1,1), Center (0.5,0.5), Horizontal-Top Stretch, and FullScreen Stretch }
    TCastleWidgetAnimator.NormalizedAnchorFlowerMinMax(uapTopRight, MinUV, MaxUV);
    AssertSameValue(1.0, MinUV.X, 1e-4);
    AssertSameValue(1.0, MinUV.Y, 1e-4);
    TCastleWidgetAnimator.ApplyAnchorPresetToControl(TestBox, uapTopRight, Vector2(-24, -16));
    AssertTrue(TestBox.HorizontalAnchorParent = hpRight);
    AssertTrue(TestBox.VerticalAnchorParent = vpTop);
    AssertSameValue(-24.0, TestBox.Translation.X, 1e-3);
    AssertSameValue(-16.0, TestBox.Translation.Y, 1e-3);

    TCastleWidgetAnimator.ApplyAnchorPresetToControl(TestBox, uapStretchHorizontalTop, Vector2(0, -12));
    AssertSameValue(1.0, TestBox.WidthFraction, 1e-4);
    AssertFalse(TestBox.FullSize);

    TCastleWidgetAnimator.ApplyAnchorPresetToControl(TestBox, uapStretchFullScreen, TVector2.Zero);
    AssertTrue(TestBox.FullSize);
    TCastleWidgetAnimator.NormalizedAnchorFlowerMinMax(uapStretchFullScreen, MinUV, MaxUV);
    AssertSameValue(0.0, MinUV.X, 1e-4);
    AssertSameValue(1.0, MaxUV.X, 1e-4);

    { 2. Verify PingPong playback on HUD Damage Flash (0.40s out -> red peak -> 0.40s back -> green rest) }
    HudAnim := TWidgetAnimHelper.SpawnWidgetAnimPresetInDesign(
      UiHost, Root, uwapHudDamageToastAndHealthFlash);
    HpIdx := HudAnim.FindSlotIndex('HealthBarCard');
    AssertTrue(HpIdx >= 0);

    AssertEquals(1, HudAnim.FireUiEvent('HealthBarCard', uetOnDamagePulse));
    AssertTrue(HudAnim.PlayMode = upmPingPong);

    HudAnim.StepAnimator(0.40);
    AssertSameValue(1.00, HudAnim.Slots[HpIdx].EvalColorRGB.X, 1e-3);
    AssertTrue('Still playing return leg of PingPong', HudAnim.Playing);

    HudAnim.StepAnimator(0.40);
    AssertFalse('PingPong 1-cycle finished cleanly at t=0', HudAnim.Playing);
    AssertSameValue(0.20, HudAnim.Slots[HpIdx].EvalColorRGB.X, 1e-3);
    AssertSameValue(0.82, HudAnim.Slots[HpIdx].EvalColorRGB.Y, 1e-3);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestToolWidgetAnim.TestUnified106StudioHubAnd29thMcpAnimateUmgWidgetTool;
var
  Root: TComponent;
  UiHost: TCastleUserInterface;
  Entry: TStudioCatalogEntry;
  Srv: TCastleMcpServer;
  ListResp, CallResp, InnerText: String;
  OuterJson, InnerJson: TJSONData;
  ToolsArr: TJSONArray;
  PayloadObj: TJSONObject;
begin
  { 1. Verify 106 UE Studios in Studio Hub (Phase 386 umg_widget_anim) }
  AssertEquals(115, TStudioHubManager.StudioCount);
  AssertTrue(TStudioHubManager.FindStudioById('umg_widget_anim', Entry));
  AssertEquals(386, Entry.PhaseNumber);

  { 2. Verify 29th MCP tool cge_animate_umg_widget }
  Root := TComponent.Create(nil);
  try
    UiHost := TCastleUserInterface.Create(Root);
    UiHost.Name := 'RootUiCanvas';

    Srv := TCastleMcpServer.Create(Root);
    Srv.AutonomyMode := mamEditWithUndo;
    Srv.StandaloneDesignRoot := UiHost;
    Srv.StandaloneDesignOwner := Root;

    ListResp := Srv.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
    OuterJson := GetJSON(ListResp);
    try
      ToolsArr := OuterJson.FindPath('result.tools') as TJSONArray;
      AssertTrue(ToolsArr <> nil);
      AssertEquals(38, ToolsArr.Count);
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cge_animate_umg_widget","arguments":{"action":"spawn_preset","preset":"modal_bounce"}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertEquals(1, PayloadObj.Integers['animatorCount']);
        AssertEquals(3, PayloadObj.Integers['slotCount']);
        AssertEquals(2, PayloadObj.Integers['clipCount']);
        AssertEquals(6, PayloadObj.Integers['trackCount']);
        AssertEquals(115, PayloadObj.Integers['studioCatalogCount']);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;

    CallResp := Srv.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"cge_animate_umg_widget","arguments":{"action":"scrub","timeSec":0.45}}}');
    OuterJson := GetJSON(CallResp);
    try
      InnerText := OuterJson.FindPath('result.content[0].text').AsString;
      InnerJson := GetJSON(InnerText);
      try
        PayloadObj := InnerJson as TJSONObject;
        AssertSameValue(0.45, PayloadObj.Floats['currentTimeSec'], 1e-3);
      finally
        FreeAndNil(InnerJson);
      end;
    finally
      FreeAndNil(OuterJson);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

initialization
  RegisterTest(TTestToolWidgetAnim);
end.
