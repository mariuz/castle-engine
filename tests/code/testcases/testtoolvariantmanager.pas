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

{ Automated tests for @link(TCastleVariantSetManager) and
  @link(TVariantManagerHelper) (Phase 296 — UE 5.9 / 6.0 Variant Manager Parity). }
unit TestToolVariantManager;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolVariantManager = class(TCastleTestCase)
  published
    procedure TestAtomicMultiComponentVariantSetsSwitchingAndJsonRoundtrip;
    procedure TestAutoDiffCapturePersistentVectorsAndMarkdownMatrix;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleComponentSerialize,
  CastleTransform, CastleScene, CastleUIControls, CastleControls, CastleViewport,
  CastleVariantSet, ToolVariantManager;

procedure TTestToolVariantManager.TestAtomicMultiComponentVariantSetsSwitchingAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  RootUi, ReloadRoot: TCastleUserInterface;
  Vp: TCastleViewport;
  SunLight: TCastleDirectionalLight;
  RuinsIntact, RuinsBroken: TCastleBox;
  HudBanner: TCastleLabel;
  Mgr, ReloadMgr: TCastleVariantSetManager;
  AppliedCount: Integer;
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

    SunLight := TCastleDirectionalLight.Create(DesignOwner);
    SunLight.Name := 'SunLight';
    SunLight.Intensity := 2.4;
    SunLight.Color := Vector3(1.0, 0.98, 0.92);
    Vp.Items.Add(SunLight);

    RuinsIntact := TCastleBox.Create(DesignOwner);
    RuinsIntact.Name := 'TowerIntact';
    RuinsIntact.Exists := true;
    Vp.Items.Add(RuinsIntact);

    RuinsBroken := TCastleBox.Create(DesignOwner);
    RuinsBroken.Name := 'TowerRuined';
    RuinsBroken.Exists := false;
    Vp.Items.Add(RuinsBroken);

    HudBanner := TCastleLabel.Create(DesignOwner);
    HudBanner.Name := 'BannerTimeOfDay';
    HudBanner.Caption := 'High Noon';
    RootUi.InsertFront(HudBanner);

    Mgr := TVariantManagerHelper.EnsureManagerInDesign(RootUi, DesignOwner);
    AssertTrue(Mgr <> nil);

    { Set 1: Lighting -> Day / Sunset / Night }
    Mgr.CaptureComponentPropertyIntoVariant(RootUi, 'Lighting', 'Day', 'SunLight', 'Intensity');
    Mgr.CaptureComponentPropertyIntoVariant(RootUi, 'Lighting', 'Day', 'SunLight', 'ColorPersistent.Red');
    Mgr.CaptureComponentPropertyIntoVariant(RootUi, 'Lighting', 'Day', 'SunLight', 'ColorPersistent.Blue');
    Mgr.CaptureComponentPropertyIntoVariant(RootUi, 'Lighting', 'Day', 'BannerTimeOfDay', 'Caption');

    Mgr.SetVariantBinding('Lighting', 'Night', 'SunLight', 'Intensity', '0.18');
    Mgr.SetVariantBinding('Lighting', 'Night', 'SunLight', 'ColorPersistent.Red', '0.35');
    Mgr.SetVariantBinding('Lighting', 'Night', 'SunLight', 'ColorPersistent.Blue', '0.95');
    Mgr.SetVariantBinding('Lighting', 'Night', 'BannerTimeOfDay', 'Caption', '"Midnight Watch"');

    { Set 2: Props -> Intact / Ruined }
    Mgr.SetVariantBinding('Props', 'Intact', 'TowerIntact', 'Exists', 'true');
    Mgr.SetVariantBinding('Props', 'Intact', 'TowerRuined', 'Exists', 'false');
    Mgr.SetVariantBinding('Props', 'Ruined', 'TowerIntact', 'Exists', 'false');
    Mgr.SetVariantBinding('Props', 'Ruined', 'TowerRuined', 'Exists', 'true');

    { Switch atomically to Night + Ruined }
    AppliedCount := Mgr.ApplyVariant(RootUi, 'Lighting', 'Night');
    AssertEquals(4, AppliedCount);
    AssertSameValue(0.18, SunLight.Intensity, 0.001);
    AssertSameValue(0.35, SunLight.Color.X, 0.001);
    AssertSameValue(0.95, SunLight.Color.Z, 0.001);
    AssertEquals('Midnight Watch', HudBanner.Caption);

    AppliedCount := Mgr.ApplyVariant(RootUi, 'Props', 'Ruined');
    AssertEquals(2, AppliedCount);
    AssertFalse(RuinsIntact.Exists);
    AssertTrue(RuinsBroken.Exists);

    { Switch back to Day }
    Mgr.ApplyVariant(RootUi, 'Lighting', 'Day');
    AssertSameValue(2.4, SunLight.Intensity, 0.001);
    AssertEquals('High Noon', HudBanner.Caption);

    { Serialize & reload full design with VariantSetsJson }
    JsonStr := ComponentToString(RootUi);
    ReloadRoot := StringToComponent(JsonStr, ReloadOwner) as TCastleUserInterface;
    AssertTrue(ReloadRoot <> nil);
    ReloadMgr := TVariantManagerHelper.FindManagerInDesign(ReloadRoot);
    AssertTrue(ReloadMgr <> nil);
    AssertEquals(2, ReloadMgr.SetCount);

    ReloadMgr.ApplyVariant(ReloadRoot, 'Lighting', 'Night');
    AssertEquals('Midnight Watch',
      (ReloadOwner.FindComponent('BannerTimeOfDay') as TCastleLabel).Caption);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolVariantManager.TestAutoDiffCapturePersistentVectorsAndMarkdownMatrix;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  Vp: TCastleViewport;
  GateTransform: TCastleBox;
  Mgr: TCastleVariantSetManager;
  BaselineJson, MdReport: String;
  DiffCount: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';
    RootUi.InsertFront(Vp);

    GateTransform := TCastleBox.Create(DesignOwner);
    GateTransform.Name := 'PortcullisGate';
    GateTransform.Translation := Vector3(0.0, 0.0, 0.0);
    GateTransform.Scale := Vector3(1.0, 1.0, 1.0);
    Vp.Items.Add(GateTransform);

    Mgr := TVariantManagerHelper.EnsureManagerInDesign(RootUi, DesignOwner);
    Mgr.CaptureComponentSnapshotIntoVariant(GateTransform, 'GateState', 'Closed');

    { 1. Take baseline snapshot, raise gate to Y = 6.5 and widen X scale to 1.25 }
    BaselineJson := ComponentToString(RootUi);
    GateTransform.Translation := Vector3(0.0, 6.5, 0.0);
    GateTransform.Scale := Vector3(1.25, 1.0, 1.0);

    DiffCount := TVariantManagerHelper.CaptureHierarchyDifferenceIntoVariant(
      BaselineJson, RootUi, Mgr, 'GateState', 'Open');
    { Only TranslationPersistent.Y and ScalePersistent.X changed! }
    AssertEquals(2, DiffCount);

    { 2. Switch Closed <-> Open live }
    Mgr.ApplyVariant(RootUi, 'GateState', 'Closed');
    AssertSameValue(0.0, GateTransform.Translation.Y, 0.001);
    AssertSameValue(1.0, GateTransform.Scale.X, 0.001);

    Mgr.ApplyVariant(RootUi, 'GateState', 'Open');
    AssertSameValue(6.5, GateTransform.Translation.Y, 0.001);
    AssertSameValue(1.25, GateTransform.Scale.X, 0.001);

    MdReport := TVariantManagerHelper.FormatVariantManagerMarkdown(RootUi);
    AssertTrue(Pos('# Castle Scene Variant Manager Configuration Report', MdReport) > 0);
    AssertTrue(Pos('PortcullisGate.TranslationPersistent.Y', MdReport) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolVariantManager);
end.
