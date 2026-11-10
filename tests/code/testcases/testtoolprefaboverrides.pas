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

{ Automated unit tests for Phase 285 Scene-Graph Non-Destructive Prefab
  Property Overrides (CastlePrefabOverrides & ToolPrefabOverrides). }
unit TestToolPrefabOverrides;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolPrefabOverrides = class(TCastleTestCase)
  published
    procedure Test3DTransformDesignOverridesJsonRoundtripAndSelectiveRevert;
    procedure Test2DUiDesignOverridesAndApplyToSourcePrefab;
  end;

implementation

uses
  CastleVectors, CastleFilesUtils, CastleUriUtils,
  CastleTransform, CastleScene, CastleViewport, CastleUIControls, CastleControls,
  CastleComponentSerialize, CastlePrefabOverrides, ToolPrefabOverrides;

procedure TTestToolPrefabOverrides.Test3DTransformDesignOverridesJsonRoundtripAndSelectiveRevert;
var
  TempDir, PrefabUrl, SceneJson: String;
  PrefabOwner, LevelOwner, LoadedOwner: TComponent;
  PrefabRoot: TCastleTransform;
  TowerBase: TCastleBox;
  RoofBeacon: TCastlePointLight;
  Vp, LoadedVp: TCastleViewport;
  TowerNorth, TowerSouth, LoadedNorth: TCastleTransformDesign;
  LiveBeacon: TCastlePointLight;
  LiveBase: TCastleBox;
begin
  TempDir := IncludeTrailingPathDelimiter(GetTempDir(false)) +
    'cge_prefab3d_' + IntToStr(GetTickCount64);
  ForceDirectories(TempDir);
  PrefabUrl := FilenameToUriSafe(TempDir + PathDelim + 'guard_tower.castle-transform');

  PrefabOwner := TComponent.Create(nil);
  LevelOwner := TComponent.Create(nil);
  LoadedOwner := TComponent.Create(nil);
  try
    { 1. Author & save 3D source prefab }
    PrefabRoot := TCastleTransform.Create(PrefabOwner);
    PrefabRoot.Name := 'GuardTowerRoot';

    TowerBase := TCastleBox.Create(PrefabOwner);
    TowerBase.Name := 'TowerBase';
    TowerBase.Size := Vector3(4, 8, 4);
    PrefabRoot.Add(TowerBase);

    RoofBeacon := TCastlePointLight.Create(PrefabOwner);
    RoofBeacon.Name := 'RoofBeacon';
    RoofBeacon.Translation := Vector3(0, 8, 0);
    RoofBeacon.Intensity := 1.0;
    PrefabRoot.Add(RoofBeacon);

    TransformSave(PrefabRoot, PrefabUrl);

    { 2. Instantiate two prefab instances in a parent Viewport }
    Vp := TCastleViewport.Create(LevelOwner);
    Vp.Name := 'LevelViewport';

    TowerNorth := TCastleTransformDesign.Create(LevelOwner);
    TowerNorth.Name := 'TowerNorth';
    TowerNorth.Url := PrefabUrl;
    Vp.Items.Add(TowerNorth);

    TowerSouth := TCastleTransformDesign.Create(LevelOwner);
    TowerSouth.Name := 'TowerSouth';
    TowerSouth.Url := PrefabUrl;
    Vp.Items.Add(TowerSouth);

    { 3. Mutate children in-memory on TowerNorth and capture overrides }
    LiveBase := TowerNorth.DesignedComponent('TowerBase') as TCastleBox;
    LiveBeacon := TowerNorth.DesignedComponent('RoofBeacon') as TCastlePointLight;
    LiveBase.Exists := false;
    LiveBeacon.Translation := Vector3(0, 14, 0);

    AssertTrue(TPrefabOverrideManager.CaptureLiveEditsFromInstance(TowerNorth, LevelOwner) >= 2);
    AssertTrue(TPrefabOverrideManager.SetOverrideFromString(
      TowerNorth, LevelOwner, 'RoofBeacon', 'Intensity', '4.5'));
    AssertSameValue(4.5, LiveBeacon.Intensity, 1e-4);

    { Sibling instance TowerSouth remains untouched at prefab defaults }
    AssertTrue((TowerSouth.DesignedComponent('TowerBase') as TCastleBox).Exists);
    AssertSameValue(1.0, (TowerSouth.DesignedComponent('RoofBeacon') as TCastlePointLight).Intensity, 1e-4);

    { 4. Full parent scene JSON roundtrip preserves & auto-applies overrides }
    SceneJson := ComponentToString(Vp);
    LoadedVp := StringToComponent(SceneJson, LoadedOwner) as TCastleViewport;
    LoadedNorth := LoadedOwner.FindComponent('TowerNorth') as TCastleTransformDesign;
    AssertTrue(LoadedNorth <> nil);
    AssertEquals(PrefabUrl, LoadedNorth.Url);
    AssertFalse((LoadedNorth.DesignedComponent('TowerBase') as TCastleBox).Exists);
    AssertSameValue(14.0, (LoadedNorth.DesignedComponent('RoofBeacon') as TCastlePointLight).Translation.Y, 1e-4);
    AssertSameValue(4.5, (LoadedNorth.DesignedComponent('RoofBeacon') as TCastlePointLight).Intensity, 1e-4);

    { 5. Selective revert of TowerBase.Exists restores Exists=true while keeping RoofBeacon overrides }
    AssertTrue(TPrefabOverrideManager.RevertSingleOverride(TowerNorth, 'TowerBase', 'Exists'));
    AssertTrue((TowerNorth.DesignedComponent('TowerBase') as TCastleBox).Exists);
    AssertSameValue(4.5, (TowerNorth.DesignedComponent('RoofBeacon') as TCastlePointLight).Intensity, 1e-4);
    AssertSameValue(14.0, (TowerNorth.DesignedComponent('RoofBeacon') as TCastlePointLight).Translation.Y, 1e-4);
  finally
    FreeAndNil(LoadedOwner);
    FreeAndNil(LevelOwner);
    FreeAndNil(PrefabOwner);
    if DirectoryExists(TempDir) then
      RemoveNonEmptyDir(TempDir, true);
  end;
end;

procedure TTestToolPrefabOverrides.Test2DUiDesignOverridesAndApplyToSourcePrefab;
var
  TempDir, PrefabUrl, SavedUrl: String;
  PrefabOwner, ScreenOwner: TComponent;
  CardRoot: TCastleUserInterface;
  CardTitle: TCastleLabel;
  ScreenRoot: TCastleUserInterface;
  CardA, CardB: TCastleDesign;
  Rows: TPrefabOverrideRowArray;
begin
  TempDir := IncludeTrailingPathDelimiter(GetTempDir(false)) +
    'cge_prefab2d_' + IntToStr(GetTickCount64);
  ForceDirectories(TempDir);
  PrefabUrl := FilenameToUriSafe(TempDir + PathDelim + 'item_card.castle-user-interface');

  PrefabOwner := TComponent.Create(nil);
  ScreenOwner := TComponent.Create(nil);
  try
    CardRoot := TCastleUserInterface.Create(PrefabOwner);
    CardRoot.Name := 'ItemCardRoot';
    CardRoot.Width := 240;
    CardRoot.Height := 80;

    CardTitle := TCastleLabel.Create(PrefabOwner);
    CardTitle.Name := 'CardTitle';
    CardTitle.Caption := 'Default Item';
    CardTitle.FontSize := 18;
    CardRoot.InsertFront(CardTitle);

    UserInterfaceSave(CardRoot, PrefabUrl);

    ScreenRoot := TCastleUserInterface.Create(ScreenOwner);
    ScreenRoot.Name := 'InventoryScreen';

    CardA := TCastleDesign.Create(ScreenOwner);
    CardA.Name := 'CardA';
    CardA.Url := PrefabUrl;
    ScreenRoot.InsertFront(CardA);

    CardB := TCastleDesign.Create(ScreenOwner);
    CardB.Name := 'CardB';
    CardB.Url := PrefabUrl;
    ScreenRoot.InsertFront(CardB);

    AssertTrue(TPrefabOverrideManager.SetOverrideFromString(
      CardA, ScreenOwner, 'CardTitle', 'Caption', 'Legendary Sword'));
    AssertTrue(TPrefabOverrideManager.SetOverrideFromString(
      CardA, ScreenOwner, 'CardTitle', 'FontSize', '28'));

    AssertEquals(2, TPrefabOverrideManager.DescribeActiveOverrides(CardA, Rows));
    AssertEquals('"Default Item"', Rows[0].SourceDefaultText);
    AssertEquals('"Legendary Sword"', Rows[0].OverriddenValueText);

    { Promote CardA overrides into source prefab file on disk }
    AssertTrue(TPrefabOverrideManager.ApplyOverridesToSourcePrefab(CardA, SavedUrl));
    AssertEquals(PrefabUrl, SavedUrl);
    AssertEquals(0, TPrefabOverrideManager.ActiveOverrideCount(CardA));
    AssertTrue(TPrefabOverrideManager.FindOverrideComponent(CardA) = nil);

    { Reloading sibling CardB now picks up the promoted source prefab values! }
    CardB.ReloadUrl;
    AssertEquals('Legendary Sword', (CardB.DesignedComponent('CardTitle') as TCastleLabel).Caption);
    AssertSameValue(28.0, (CardB.DesignedComponent('CardTitle') as TCastleLabel).FontSize, 1e-4);
  finally
    FreeAndNil(ScreenOwner);
    FreeAndNil(PrefabOwner);
    if DirectoryExists(TempDir) then
      RemoveNonEmptyDir(TempDir, true);
  end;
end;

initialization
  RegisterTest(TTestToolPrefabOverrides);
end.
