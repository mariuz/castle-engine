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

{ Automated tests for TCastleStylizedShaderBehavior and TLightShadowBudgetAuditor (Phase 282). }
unit TestToolNprShaderStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolNprShaderStudio = class(TCastleTestCase)
  published
    procedure TestStylizedShaderPresetsGlslEffectsAndJsonRoundtrip;
    procedure TestLightShadowBudgetAuditHotspotsAndAutoFix;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleTransform, CastleScene, CastleNprShader,
  CastleViewport, CastleComponentSerialize, X3DNodes, ToolNprShaderStudio;

procedure TTestToolNprShaderStudio.TestStylizedShaderPresetsGlslEffectsAndJsonRoundtrip;
var
  OwnerComp: TComponent;
  Box: TCastleBox;
  Scene, ReloadedScene: TCastleScene;
  RootNode: TX3DRootNode;
  UserEffect: TEffectNode;
  Beh, ReloadedBeh: TCastleStylizedShaderBehavior;
  GlslSrc, JsonStr: String;
  P: TCastleStylizedShaderPreset;
begin
  OwnerComp := TComponent.Create(nil);
  try
    { 1. Attach to TCastleBox and verify all 5 NPR GLSL presets }
    Box := TCastleBox.Create(OwnerComp);
    Box.Name := 'StylizedBox';
    Beh := TLightShadowBudgetAuditor.AttachOrUpdateStylizedShader(
      Box, OwnerComp, sspCelToon);
    AssertTrue(Beh <> nil);
    AssertTrue(Beh.ActiveEffectNode <> nil);

    for P := Low(TCastleStylizedShaderPreset) to High(TCastleStylizedShaderPreset) do
    begin
      Beh.Preset := P;
      GlslSrc := Beh.BuildFragmentShaderSource;
      AssertTrue(Pos('void PLUG_lighting_apply', GlslSrc) > 0);
      if P = sspDissolve then
        AssertTrue(Pos('discard;', GlslSrc) > 0);
      if P = sspGoochTechnical then
        AssertTrue(Pos('goochRgb', GlslSrc) > 0);
    end;
    AssertTrue(TLightShadowBudgetAuditor.RemoveStylizedShader(Box));
    AssertTrue(Box.FindBehavior(TCastleStylizedShaderBehavior) = nil);

    { 2. Attach to TCastleScene BEFORE RootNode is loaded, then load RootNode with an existing user TEffectNode }
    Scene := TCastleScene.Create(OwnerComp);
    Scene.Name := 'HeroCharacter';
    Beh := TLightShadowBudgetAuditor.AttachOrUpdateStylizedShader(
      Scene, OwnerComp, sspSilhouetteOutline);
    Beh.CelBands := 5;
    Beh.OutlineThickness := 0.32;
    Beh.AccentColor := Vector3(0.95, 0.50, 0.15);
    Beh.SecondaryColor := Vector3(0.04, 0.05, 0.09);

    RootNode := TX3DRootNode.Create;
    UserEffect := TEffectNode.Create('CustomUserEffect');
    UserEffect.Language := slGLSL;
    RootNode.AddChildren(UserEffect);
    Scene.Load(RootNode, true);

    Beh.RebuildAndApplyEffect;
    { Both CustomUserEffect and CastleStylizedShaderEffect must coexist in Scene.RootNode! }
    AssertEquals(2, Scene.RootNode.FdChildren.Count);

    { 3. Verify CastleComponentSerialize JSON roundtrip of TCastleStylizedShaderBehavior }
    JsonStr := ComponentToString(Scene);
    ReloadedScene := StringToComponent(JsonStr, OwnerComp) as TCastleScene;
    ReloadedBeh := ReloadedScene.FindBehavior(TCastleStylizedShaderBehavior) as TCastleStylizedShaderBehavior;
    AssertTrue(ReloadedBeh <> nil);
    AssertTrue(ReloadedBeh.Preset = sspSilhouetteOutline);
    AssertEquals(5, ReloadedBeh.CelBands);
    AssertSameValue(0.32, ReloadedBeh.OutlineThickness, 1e-4);
    AssertVectorEquals(Vector3(0.95, 0.50, 0.15), ReloadedBeh.AccentColor, 1e-4);
    AssertVectorEquals(Vector3(0.04, 0.05, 0.09), ReloadedBeh.SecondaryColor, 1e-4);

    { 4. Detach cleanly while preserving CustomUserEffect }
    AssertTrue(TLightShadowBudgetAuditor.RemoveStylizedShader(Scene));
    AssertEquals(1, Scene.RootNode.FdChildren.Count);
    AssertEquals('CustomUserEffect', Scene.RootNode.FdChildren[0].X3DName);
  finally
    FreeAndNil(OwnerComp);
  end;
end;

procedure TTestToolNprShaderStudio.TestLightShadowBudgetAuditHotspotsAndAutoFix;
var
  OwnerComp: TComponent;
  Viewport: TCastleViewport;
  SunLight: TCastleDirectionalLight;
  TorchNear, TorchUnbounded: TCastlePointLight;
  SpotNear: TCastleSpotLight;
  HeroBox, DistantBox: TCastleBox;
  Report: TLightShadowBudgetReport;
  SummaryText: String;
begin
  OwnerComp := TComponent.Create(nil);
  try
    Viewport := TCastleViewport.Create(OwnerComp);

    SunLight := TCastleDirectionalLight.Create(OwnerComp);
    SunLight.Name := 'SunLight';
    SunLight.Intensity := 2.0;
    SunLight.Shadows := true;
    Viewport.Items.Add(SunLight);

    TorchNear := TCastlePointLight.Create(OwnerComp);
    TorchNear.Name := 'TorchNear';
    TorchNear.Translation := Vector3(2, 2, 0);
    TorchNear.Radius := 12.0;
    TorchNear.Shadows := true; { Intentional 2nd shadow-volume light conflict! }
    Viewport.Items.Add(TorchNear);

    TorchUnbounded := TCastlePointLight.Create(OwnerComp);
    TorchUnbounded.Name := 'TorchUnbounded';
    TorchUnbounded.Translation := Vector3(-3, 2, 0);
    TorchUnbounded.Radius := -1.0; { Unbounded punctual light! }
    Viewport.Items.Add(TorchUnbounded);

    SpotNear := TCastleSpotLight.Create(OwnerComp);
    SpotNear.Name := 'SpotNear';
    SpotNear.Translation := Vector3(0, 5, 0);
    SpotNear.Radius := 15.0;
    Viewport.Items.Add(SpotNear);

    HeroBox := TCastleBox.Create(OwnerComp);
    HeroBox.Name := 'HeroStatue';
    HeroBox.Translation := Vector3(0, 0, 0);
    HeroBox.CastShadows := true;
    Viewport.Items.Add(HeroBox);

    DistantBox := TCastleBox.Create(OwnerComp);
    DistantBox.Name := 'DistantOutpost';
    DistantBox.Translation := Vector3(100, 0, 0);
    DistantBox.CastShadows := false;
    Viewport.Items.Add(DistantBox);

    Report := TLightShadowBudgetAuditor.AnalyzeRoot(Viewport);
    try
      AssertEquals(4, Report.TotalLights);
      AssertEquals(1, Report.DirectionalLights);
      AssertEquals(2, Report.PointLights);
      AssertEquals(1, Report.SpotLights);
      AssertEquals(2, Report.ShadowCastingLights);
      AssertTrue(Report.HasMultipleShadowVolumeConflict);
      AssertEquals(1, Report.UnboundedPunctualLights);
      AssertEquals(2, Report.TotalReceivers);
      AssertEquals(1, Report.ShadowCasterReceivers);
      AssertEquals(4, Report.MaxLightsOnSingleReceiver);
      AssertEquals('HeroStatue', Report.Hotspots[0].ReceiverName);
      AssertEquals(4, Report.Hotspots[0].OverlappingLightCount);
      AssertTrue(Report.Hotspots[0].HeatTier = lhtCritical);
      { DistantOutpost is affected by SunLight + TorchUnbounded = 2 lights }
      AssertEquals('DistantOutpost', Report.Hotspots[1].ReceiverName);
      AssertEquals(2, Report.Hotspots[1].OverlappingLightCount);
      SummaryText := Report.FormatSummaryReport;
      AssertTrue(Pos('HeroStatue', SummaryText) > 0);
      AssertTrue(Report.Warnings.Count >= 2);
    finally
      FreeAndNil(Report);
    end;

    { Auto-fix: resolve multi-shadow conflict (keeps SunLight.Shadows=true, disables TorchNear.Shadows)
      and clamp unbounded punctual radii to 25.0 }
    AssertEquals(1, TLightShadowBudgetAuditor.EnsureSingleShadowVolumeLight(Viewport));
    AssertTrue(SunLight.Shadows);
    AssertTrue(not TorchNear.Shadows);
    AssertEquals(1, TLightShadowBudgetAuditor.ClampUnboundedLightRadii(Viewport, 25.0));
    AssertSameValue(25.0, TorchUnbounded.Radius, 1e-4);

    Report := TLightShadowBudgetAuditor.AnalyzeRoot(Viewport);
    try
      AssertTrue(not Report.HasMultipleShadowVolumeConflict);
      AssertEquals(1, Report.ShadowCastingLights);
      AssertEquals(0, Report.UnboundedPunctualLights);
      { DistantOutpost at X=100 is now hit ONLY by SunLight (1 light -> lhtCool)! }
      AssertEquals(1, Report.Hotspots[1].OverlappingLightCount);
      AssertTrue(Report.Hotspots[1].HeatTier = lhtCool);
    finally
      FreeAndNil(Report);
    end;
  finally
    FreeAndNil(OwnerComp);
  end;
end;

initialization
  RegisterTest(TTestToolNprShaderStudio);
end.
