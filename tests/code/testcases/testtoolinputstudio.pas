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

{ Automated unit tests for Phase 311: Enhanced Input Action Mapping,
  Chord/Combo Triggers & Gamepad/Keyboard Rebinding Studio
  (@link(CastleEnhancedInput), @link(ToolInputStudio)). }
unit TestToolInputStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolInputStudio = class(TCastleTestCase)
  published
    procedure TestPriorityContextConsumptionTapHoldChordAndDiagonalNormalization;
    procedure TestRadialDeadzone2DUserRebindJsonConflictDetectorAndRoundtrip;
  end;

implementation

uses
  CastleVectors, CastleComponentSerialize,
  CastleUIControls, CastleEnhancedInput, ToolInputStudio;

procedure TTestToolInputStudio.TestPriorityContextConsumptionTapHoldChordAndDiagonalNormalization;
var
  DesignOwner: TComponent;
  RootUi: TCastleUserInterface;
  Mgr: TCastleInputMapManager;
  MoveVec: TVector2;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';
    Mgr := TInputStudioHelper.CreateInputManagerInDesign(
      RootUi, DesignOwner, ipkActionRpgThirdPerson, 'RpgInput');
    AssertTrue(Mgr <> nil);

    { 1. Diagonal W+D 2D movement normalizes to unit length 1.0 (0.7071, 0.7071) }
    Mgr.SetKeyState('KeyW', True);
    Mgr.SetKeyState('KeyD', True);
    Mgr.StepInputFrame(0.016);
    MoveVec := Mgr.GetActionAxis2D('Move2D');
    AssertSameValue(1.0, MoveVec.Length, 1e-4);
    AssertSameValue(0.7071, MoveVec.X, 1e-3);
    AssertSameValue(0.7071, MoveVec.Y, 1e-3);
    Mgr.ReleaseAllInputs;

    { 2. Tap trigger (<= 0.22s fires on release; > 0.22s long hold does NOT fire Tap) }
    Mgr.SetKeyState('KeySpace', True);
    Mgr.StepInputFrame(0.12);
    AssertFalse(Mgr.WasActionTriggered('DodgeRoll'));
    Mgr.SetKeyState('KeySpace', False);
    Mgr.StepInputFrame(0.016);
    AssertTrue(Mgr.WasActionTriggered('DodgeRoll'));

    Mgr.SetKeyState('KeySpace', True);
    Mgr.StepInputFrame(0.40);
    Mgr.SetKeyState('KeySpace', False);
    Mgr.StepInputFrame(0.016);
    AssertFalse(Mgr.WasActionTriggered('DodgeRoll'));

    { 3. Hold trigger (>= 0.45s fires once while held and does not re-fire until released) }
    Mgr.SetKeyState('MouseLeft', True);
    Mgr.StepInputFrame(0.25);
    AssertFalse(Mgr.WasActionTriggered('HeavyCharge'));
    Mgr.StepInputFrame(0.25);
    AssertTrue(Mgr.WasActionTriggered('HeavyCharge'));
    Mgr.StepInputFrame(0.20);
    AssertFalse(Mgr.WasActionTriggered('HeavyCharge'));
    Mgr.ReleaseAllInputs;

    { 4. Chord trigger: KeyQ alone ignored; LeftShift + KeyQ triggers UltimateBurst }
    Mgr.SetKeyState('KeyQ', True);
    Mgr.StepInputFrame(0.016);
    AssertFalse(Mgr.WasActionTriggered('UltimateBurst'));
    Mgr.ReleaseAllInputs;

    Mgr.SetKeyState('LeftShift', True);
    Mgr.SetKeyState('KeyQ', True);
    Mgr.StepInputFrame(0.016);
    AssertTrue(Mgr.WasActionTriggered('UltimateBurst'));
    Mgr.ReleaseAllInputs;

    { 5. Priority-layered context key consumption:
         DialogueOverlay (Prio 50) consumes KeyE so GameplayDefault (Prio 0) InteractWorld stays False }
    Mgr.SetKeyState('KeyE', True);
    Mgr.StepInputFrame(0.016);
    AssertTrue(Mgr.WasActionTriggered('InteractWorld'));
    AssertFalse(Mgr.WasActionTriggered('AdvanceDialogue'));
    Mgr.ReleaseAllInputs;

    Mgr.SetContextActive('DialogueOverlay', True);
    Mgr.SetKeyState('KeyE', True);
    Mgr.StepInputFrame(0.016);
    AssertTrue(Mgr.WasActionTriggered('AdvanceDialogue'));
    AssertFalse(Mgr.WasActionTriggered('InteractWorld'));
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolInputStudio.TestRadialDeadzone2DUserRebindJsonConflictDetectorAndRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  RootUi: TCastleUserInterface;
  Mgr, ReloadedMgr: TCastleInputMapManager;
  DzZero, DzHalf: TVector2;
  RebindJson, FullJson, Md: String;
  ReloadedRoot: TComponent;
  Report: TInputStudioAuditReport;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    { 1. Exact radial deadzone + power-curve sensitivity }
    DzZero := EvaluateRadialDeadzone2D(Vector2(0.12, 0.10), 0.20, 0.95, 2.0);
    AssertSameValue(0.0, DzZero.Length, 1e-5);

    { Raw X = 0.575 is exactly 50% between Inner=0.20 and Outer=0.95 -> 0.5^2 = 0.25 }
    DzHalf := EvaluateRadialDeadzone2D(Vector2(0.575, 0.0), 0.20, 0.95, 2.0);
    AssertSameValue(0.25, DzHalf.X, 1e-4);
    AssertSameValue(0.0, DzHalf.Y, 1e-5);

    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'RootUi';
    Mgr := TInputStudioHelper.CreateInputManagerInDesign(
      RootUi, DesignOwner, ipkActionRpgThirdPerson, 'UserInputMgr');

    { 2. User key rebinding -> JSON profile export -> reset -> re-import }
    AssertTrue(Mgr.RebindByAction('GameplayDefault', 'InteractWorld', 'KeyF'));
    RebindJson := Mgr.ExportUserRebindsJson;
    AssertTrue(Pos('KeyF', RebindJson) > 0);

    Mgr.ResetAllRebindsToDefault;
    Mgr.SetKeyState('KeyF', True);
    Mgr.StepInputFrame(0.016);
    AssertFalse(Mgr.WasActionTriggered('InteractWorld'));
    Mgr.ReleaseAllInputs;

    AssertEquals(1, Mgr.ImportUserRebindsJson(RebindJson));
    Mgr.SetKeyState('KeyF', True);
    Mgr.StepInputFrame(0.016);
    AssertTrue(Mgr.WasActionTriggered('InteractWorld'));
    Mgr.ReleaseAllInputs;

    { 3. Conflict detection: Tap + Hold on same key is valid (0 conflicts),
         while binding QuickHeal (Pressed) onto KeyF (Pressed) triggers 1 conflict! }
    Mgr.AddBinding(TInputBindingDef.CreateDigital(
      'GameplayDefault', 'HeavyJump', 'KeySpace', itkHold, 0.50));
    AssertEquals(0, Mgr.DetectBindingConflicts(nil));

    Mgr.AddBinding(TInputBindingDef.CreateDigital(
      'GameplayDefault', 'QuickHeal', 'KeyF', itkPressed));
    Report := TInputStudioHelper.ScanDesign(RootUi, DesignOwner);
    try
      AssertEquals(1, Report.ConflictCount);
      AssertEquals(1, Report.Warnings.Count);
      AssertTrue(Pos('KeyF', Report.Warnings[0]) > 0);
    finally
      FreeAndNil(Report);
    end;

    Md := TInputStudioHelper.BuildMarkdownReport(RootUi, DesignOwner);
    AssertTrue(Pos('QuickHeal', Md) > 0);

    { 4. Full design JSON serialization roundtrip }
    FullJson := ComponentToString(RootUi);
    ReloadedRoot := StringToComponent(FullJson, ReloadOwner);
    AssertTrue(ReloadedRoot is TCastleUserInterface);
    ReloadedMgr := ReloadOwner.FindComponent('UserInputMgr') as TCastleInputMapManager;
    AssertTrue(ReloadedMgr <> nil);
    AssertEquals(Mgr.Contexts.Count, ReloadedMgr.Contexts.Count);
    AssertEquals(Mgr.Bindings.Count, ReloadedMgr.Bindings.Count);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolInputStudio);
end.
