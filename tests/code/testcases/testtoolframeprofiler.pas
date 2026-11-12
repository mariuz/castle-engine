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

{ Automated tests for Phase 306 Real-Time Frame Budget Profiler, Draw-Call /
  VRAM Analyzer & 5-Tier Scalability Studio (@link(CastleScalability),
  @link(ToolFrameProfiler)). }
unit TestToolFrameProfiler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleTester, CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleComponentSerialize, CastleParticles, CastleFoliageBiome,
  CastlePostProcessVolume, CastleScalability, ToolFrameProfiler;

type
  TTestToolFrameProfiler = class(TCastleTestCase)
  published
    procedure TestFrameBudgetAuditViolationsOffenderRankingAndLowTierRemediation;
    procedure TestIdempotentFiveTierSwitchingLodScalingAndJsonRoundtrip;
  end;

implementation

procedure TTestToolFrameProfiler.TestFrameBudgetAuditViolationsOffenderRankingAndLowTierRemediation;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  L1, L2, L3: TCastlePointLight;
  Part: TCastleParticleEmitter;
  PpVol: TCastlePostProcessVolume;
  BoxProp: TCastleBox;
  I: Integer;
  MobileBefore, MobileAfter: TFrameBudgetAuditReport;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';
    Vp.DynamicBatching := false;

    { 3 shadow-casting punctual lights (exceeds Mobile 60Hz limit of 1) }
    L1 := TCastlePointLight.Create(DesignOwner);
    L1.Name := 'ShadowLight1'; L1.Shadows := true; Vp.Items.Add(L1);
    L2 := TCastlePointLight.Create(DesignOwner);
    L2.Name := 'ShadowLight2'; L2.Shadows := true; Vp.Items.Add(L2);
    L3 := TCastlePointLight.Create(DesignOwner);
    L3.Name := 'ShadowLight3'; L3.Shadows := true; Vp.Items.Add(L3);

    { Heavy VFX particle emitter (1200 max particles > 250 Mobile cap) }
    Part := TCastleParticleEmitter.Create(DesignOwner);
    Part.Name := 'VolcanoEmbers';
    Part.MaxParticles := 1200;
    Part.SpawnRate := 180.0;
    Vp.Items.Add(Part);

    { Post-process volume with chromatic aberration }
    PpVol := TCastlePostProcessVolume.Create(DesignOwner);
    PpVol.Name := 'GlobalLookVolume';
    PpVol.VolumeEnabled := true;
    PpVol.ChromaticAberrationPx := 3.5;
    Vp.Items.Add(PpVol);

    { 20 unbatched box props }
    for I := 1 to 20 do
    begin
      BoxProp := TCastleBox.Create(DesignOwner);
      BoxProp.Name := 'CrateProp' + IntToStr(I);
      Vp.Items.Add(BoxProp);
    end;

    MobileBefore := TFrameBudgetProfiler.AuditHierarchy(Vp, pbpMobile60Hz);
    AssertFalse(MobileBefore.OverallPassBudget);
    AssertEquals(3, MobileBefore.ShadowCastingLightsCount);
    AssertEquals(1200, MobileBefore.ActiveParticleBudget);
    AssertTrue(Length(MobileBefore.BudgetViolations) >= 2);
    AssertTrue(Length(MobileBefore.TopOffenders) >= 4);
    { Highest-cost offender should be either VolcanoEmbers (96 score) or ShadowLight (45 score) }
    AssertEquals('VolcanoEmbers', MobileBefore.TopOffenders[0].ComponentName);
    AssertTrue(MobileBefore.RecommendedTier in [stLow, stMedium]);

    { Apply stLow scalability tier -> disables shadows, caps particles to 25% (300),
      enables DynamicBatching, and disables PostProcessVolume }
    AssertTrue(TFrameBudgetProfiler.ApplyScalabilityTierToDesign(Vp, DesignOwner, stLow) >= 5);
    AssertTrue(Vp.DynamicBatching);
    AssertFalse(Vp.ShadowVolumes);
    AssertFalse(PpVol.VolumeEnabled);

    MobileAfter := TFrameBudgetProfiler.AuditHierarchy(Vp, pbpMobile60Hz);
    AssertEquals(0, MobileAfter.ShadowCastingLightsCount);
    AssertEquals(300, MobileAfter.ActiveParticleBudget);
    AssertTrue(MobileAfter.EstimatedDrawCalls < MobileBefore.EstimatedDrawCalls - 20);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolFrameProfiler.TestIdempotentFiveTierSwitchingLodScalingAndJsonRoundtrip;
var
  DesignOwner, LoadedOwner: TComponent;
  Vp: TCastleViewport;
  TreeHolder: TCastleTransform;
  Lod: TCastleLodProxyBehavior;
  Part: TCastleParticleEmitter;
  Mgr: TCastleScalabilityManager;
  SerializedJson, MdReport: String;
  LoadedRoot: TComponent;
  Rep: TFrameBudgetAuditReport;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    TreeHolder := TCastleTransform.Create(DesignOwner);
    TreeHolder.Name := 'HeroOakTree';
    Vp.Items.Add(TreeHolder);

    Lod := TCastleLodProxyBehavior.Create(DesignOwner);
    Lod.Name := 'OakLodProxy';
    Lod.MediumDistance := 30.0;
    Lod.LowDistance := 80.0;
    Lod.CullDistance := 160.0;
    TreeHolder.AddBehavior(Lod);

    Part := TCastleParticleEmitter.Create(DesignOwner);
    Part.Name := 'CampfireSparks';
    Part.MaxParticles := 400;
    Part.SpawnRate := 60.0;
    Vp.Items.Add(Part);

    { Apply stLow TWICE -> idempotent baseline ensures 0.25x & 0.50x (NOT 0.0625x / 0.25x) }
    TFrameBudgetProfiler.ApplyScalabilityTierToDesign(Vp, DesignOwner, stLow);
    TFrameBudgetProfiler.ApplyScalabilityTierToDesign(Vp, DesignOwner, stLow);
    AssertEquals(100, Part.MaxParticles);
    AssertSameValue(15.0, Part.SpawnRate, 1e-3);
    AssertSameValue(15.0, Lod.MediumDistance, 1e-3);
    AssertSameValue(40.0, Lod.LowDistance, 1e-3);
    AssertSameValue(80.0, Lod.CullDistance, 1e-3);

    { Switch to stCinematic (2.0x) }
    TFrameBudgetProfiler.ApplyScalabilityTierToDesign(Vp, DesignOwner, stCinematic);
    AssertEquals(800, Part.MaxParticles);
    AssertSameValue(120.0, Part.SpawnRate, 1e-3);
    AssertSameValue(60.0, Lod.MediumDistance, 1e-3);
    AssertSameValue(160.0, Lod.LowDistance, 1e-3);
    AssertSameValue(320.0, Lod.CullDistance, 1e-3);

    { Switch back to stHigh (1.0x) -> exact original values restored! }
    TFrameBudgetProfiler.ApplyScalabilityTierToDesign(Vp, DesignOwner, stHigh);
    AssertEquals(400, Part.MaxParticles);
    AssertSameValue(60.0, Part.SpawnRate, 1e-3);
    AssertSameValue(30.0, Lod.MediumDistance, 1e-3);
    AssertSameValue(80.0, Lod.LowDistance, 1e-3);
    AssertSameValue(160.0, Lod.CullDistance, 1e-3);

    Mgr := TFrameBudgetProfiler.EnsureScalabilityManagerInDesign(Vp, DesignOwner);
    AssertTrue(Mgr <> nil);
    Mgr.ActiveTier := stEpic;
    Mgr.TargetPlatform := pbpHandheld60Hz;

    MdReport := TFrameBudgetProfiler.BuildMarkdownReport(Vp, pbpHandheld60Hz);
    AssertTrue(Pos('Handheld 60Hz', MdReport) > 0);
    AssertTrue(Pos('CampfireSparks', MdReport) > 0);

    SerializedJson := ComponentToString(Vp);
    LoadedOwner := TComponent.Create(nil);
    try
      LoadedRoot := StringToComponent(SerializedJson, LoadedOwner);
      Rep := TFrameBudgetProfiler.AuditHierarchy(LoadedRoot, pbpHandheld60Hz);
      AssertTrue(Rep.ActiveScalabilityManager <> nil);
      AssertTrue(Rep.ActiveScalabilityManager.ActiveTier = stEpic);
      AssertTrue(Rep.ActiveScalabilityManager.TargetPlatform = pbpHandheld60Hz);
    finally
      FreeAndNil(LoadedOwner);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolFrameProfiler);
end.
