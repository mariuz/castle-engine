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

{ Automated tests for @link(TCastlePostProcessVolume),
  @link(TCastlePostProcessStack), and @link(TPostProcessStudioHelper)
  (Phase 293 — UE 5.9 / 6.0 Priority-Blended Post-Process Volume Parity). }
unit TestToolPostProcessStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolPostProcessStudio = class(TCastleTestCase)
  published
    procedure TestPriorityBlendingBoundedFalloffAndJsonRoundtrip;
    procedure TestPresetsScreenEffectAttachmentGlslAndCpuPreview;
  end;

implementation

uses
  CastleVectors, CastleComponentSerialize,
  CastleTransform, CastleUIControls, CastleViewport,
  CastlePostProcessVolume, ToolPostProcessStudio;

procedure TTestToolPostProcessStudio.TestPriorityBlendingBoundedFalloffAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  RootUi, ReloadRoot: TCastleUserInterface;
  Vp: TCastleViewport;
  GlobalVol, LocalVol, ReloadLocal: TCastlePostProcessVolume;
  Stack: TCastlePostProcessStack;
  ActiveCount: Integer;
  BlendedCenter, BlendedMidFalloff, BlendedOutside: TPostProcessSettings;
  Sum: TPostProcessStudioSummary;
  JsonStr: String;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';
    RootUi.InsertFront(Vp);

    Stack := TPostProcessStudioHelper.EnsureStackInDesign(RootUi, DesignOwner);
    AssertTrue(Stack <> nil);

    { Global unbound Warm Sunset volume (Priority 0) }
    GlobalVol := TPostProcessStudioHelper.CreateVolumeInDesign(
      RootUi, DesignOwner, pppWarmSunset, true, TVector3.Zero);
    AssertTrue(GlobalVol <> nil);
    GlobalVol.Priority := 0;
    AssertSameValue(0.35, GlobalVol.ExposureEV, 0.001);

    { Local bounded Horror Vignette volume at (20, 0, 0), Core=6m, Blend=4m (Outer=10m), Priority 10 }
    LocalVol := TPostProcessStudioHelper.CreateVolumeInDesign(
      RootUi, DesignOwner, pppHorrorVignette, false, Vector3(20.0, 0.0, 0.0));
    AssertTrue(LocalVol <> nil);
    LocalVol.Priority := 10;
    LocalVol.CoreRadius := 6.0;
    LocalVol.BlendRadius := 4.0;

    { 1. Far outside local volume (0, 0, 0) -> pure Global Warm Sunset }
    BlendedOutside := TCastlePostProcessStack.EvaluateBlendedWorldSettings(
      RootUi, TVector3.Zero, ActiveCount);
    AssertEquals(1, ActiveCount);
    AssertSameValue(0.35, BlendedOutside.ExposureEV, 0.001);
    AssertSameValue(0.25, BlendedOutside.VignetteIntensity, 0.001);

    { 2. Inside local volume core (22, 0, 0) -> Priority 10 overrides Global (weight 1.0) }
    BlendedCenter := TCastlePostProcessStack.EvaluateBlendedWorldSettings(
      RootUi, Vector3(22.0, 0.0, 0.0), ActiveCount);
    AssertEquals(2, ActiveCount);
    AssertSameValue(-0.65, BlendedCenter.ExposureEV, 0.001);
    AssertSameValue(0.85, BlendedCenter.VignetteIntensity, 0.001);

    { 3. Exact midpoint of Hermite falloff ring (dist = 8.0m -> T = 0.5 -> Hermite weight = 0.5) }
    BlendedMidFalloff := TCastlePostProcessStack.EvaluateBlendedWorldSettings(
      RootUi, Vector3(28.0, 0.0, 0.0), ActiveCount);
    AssertEquals(2, ActiveCount);
    { Midpoint between +0.35 EV and -0.65 EV = -0.15 EV }
    AssertSameValue(-0.15, BlendedMidFalloff.ExposureEV, 0.01);
    { Midpoint between 0.25 and 0.85 vignette = 0.55 }
    AssertSameValue(0.55, BlendedMidFalloff.VignetteIntensity, 0.01);

    { Serialize & reload full hierarchy including non-visual stack & volumes }
    JsonStr := ComponentToString(RootUi);
    ReloadRoot := StringToComponent(JsonStr, ReloadOwner) as TCastleUserInterface;
    AssertTrue(ReloadRoot <> nil);

    Sum := TPostProcessStudioHelper.ScanVolumesAndBlend(ReloadRoot, Vector3(22.0, 0.0, 0.0));
    AssertEquals(2, Length(Sum.Volumes));
    AssertEquals(1, Length(Sum.Stacks));
    AssertSameValue(-0.65, Sum.Blended.ExposureEV, 0.001);

    ReloadLocal := ReloadOwner.FindComponent(LocalVol.Name) as TCastlePostProcessVolume;
    AssertTrue(ReloadLocal <> nil);
    AssertFalse(ReloadLocal.IsUnbound);
    AssertEquals(10, ReloadLocal.Priority);
    AssertTrue(Pos('Horror Vignette', ReloadLocal.VolumeSummaryBadge) > 0);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolPostProcessStudio.TestPresetsScreenEffectAttachmentGlslAndCpuPreview;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  Vp: TCastleViewport;
  Vol: TCastlePostProcessVolume;
  Stack: TCastlePostProcessStack;
  Pr: TCastlePostProcessPreset;
  Applied: TPostProcessSettings;
  NeutralSample, NoirSample, EdgeVignetteSample: TVector3;
  GlslSrc, MdReport: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    Vp := TCastleViewport.Create(DesignOwner);
    RootUi.InsertFront(Vp);

    Stack := TPostProcessStudioHelper.EnsureStackInDesign(RootUi, DesignOwner);
    Vol := TPostProcessStudioHelper.CreateVolumeInDesign(
      RootUi, DesignOwner, pppNeutral, true, TVector3.Zero);

    { Verify all 6 presets populate valid non-empty names and distinct settings }
    for Pr := Low(TCastlePostProcessPreset) to High(TCastlePostProcessPreset) do
    begin
      AssertTrue(PostProcessPresetToDisplayName(Pr) <> '');
      Vol.ApplyLookPreset(Pr);
      if Pr = pppNeutral then
        AssertTrue(Vol.ToSettings.IsEffectivelyNeutral)
      else
        AssertFalse(Vol.ToSettings.IsEffectivelyNeutral);
    end;

    { Apply Noir High-Contrast to live viewport ScreenEffectNode }
    Vol.ApplyLookPreset(pppNoirHighContrast);
    Applied := Stack.ApplyToViewport(RootUi, Vp, TVector3.Zero);
    AssertSameValue(1.55, Applied.Contrast, 0.001);
    AssertTrue(Stack.AttachedViewport = Vp);
    AssertTrue(Stack.ScreenEffectNode <> nil);
    AssertTrue(Stack.ScreenEffectNode.Enabled);

    { Disabling stack disables X3D ScreenEffectNode cleanly }
    Stack.StackEnabled := false;
    Applied := Stack.ApplyToViewport(RootUi, Vp, TVector3.Zero);
    AssertTrue(Applied.IsEffectivelyNeutral);
    AssertFalse(Stack.ScreenEffectNode.Enabled);
    Stack.StackEnabled := true;
    Stack.ApplyToViewport(RootUi, Vp, TVector3.Zero);
    AssertTrue(Stack.ScreenEffectNode.Enabled);

    { Verify CPU preview matches expected color-grading math }
    NeutralSample := TPostProcessStudioHelper.EvaluateColorGradeCpuPreview(
      TPostProcessSettings.Neutral, Vector3(0.8, 0.4, 0.2), Vector2(0.5, 0.5));
    AssertSameValue(0.8, NeutralSample.X, 0.001);
    AssertSameValue(0.4, NeutralSample.Y, 0.001);
    AssertSameValue(0.2, NeutralSample.Z, 0.001);

    NoirSample := TPostProcessStudioHelper.EvaluateColorGradeCpuPreview(
      Vol.ToSettings, Vector3(0.8, 0.2, 0.1), Vector2(0.5, 0.5));
    { Noir has Saturation=0.05 -> R/G chroma spread drops from 0.60 to < 0.10 }
    AssertTrue(Abs(NoirSample.X - NoirSample.Y) < 0.10);

    EdgeVignetteSample := TPostProcessStudioHelper.EvaluateColorGradeCpuPreview(
      Vol.ToSettings, Vector3(0.8, 0.2, 0.1), Vector2(0.0, 0.0));
    { Corner UV (0,0) must be darker than center UV (0.5,0.5) under vignette }
    AssertTrue(EdgeVignetteSample.X < NoirSample.X);

    { Verify GLSL & Markdown report }
    GlslSrc := TCastlePostProcessStack.BuildPostProcessFragmentGlsl;
    AssertTrue(Pos('screen_get_color', GlslSrc) > 0);
    AssertTrue(Pos('cge_aces_filmic', GlslSrc) > 0);
    AssertTrue(Pos('u_pp_chromatic_px', GlslSrc) > 0);

    MdReport := TPostProcessStudioHelper.FormatPostProcessMarkdown(RootUi, TVector3.Zero);
    AssertTrue(Pos('# Castle Post-Processing Volume Stack Report', MdReport) > 0);
    AssertTrue(Pos('Noir High-Contrast', MdReport) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolPostProcessStudio);
end.
