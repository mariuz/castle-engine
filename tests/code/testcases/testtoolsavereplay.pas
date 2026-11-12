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

{ Automated unit tests for Phase 315 SaveGame Slot Manager, Versioned
  World-State Snapshot & Deterministic Replay Recorder
  (@link(CastleSaveReplay), @link(ToolSaveReplay)). }
unit TestToolSaveReplay;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolSaveReplay = class(TCastleTestCase)
  strict private
    FFiredCueIds: TStringList;
    procedure HandleReplayCue(Sender: TObject;
      const ATimeSec: Single; const ACueId, APayload: String);
  published
    procedure TestSaveSlotMultiSystemWorldCheckpointRestoreAndSchemaMigration;
    procedure TestDeterministicReplayKeyframeScrubSlerpCuesAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleComponentSerialize, CastleGameplayAbility, CastleDialogueQuest,
  CastleSaveReplay, ToolSaveReplay;

procedure TTestToolSaveReplay.HandleReplayCue(Sender: TObject;
  const ATimeSec: Single; const ACueId, APayload: String);
begin
  if FFiredCueIds <> nil then
    FFiredCueIds.Add(ACueId + ':' + APayload);
end;

procedure TTestToolSaveReplay.TestSaveSlotMultiSystemWorldCheckpointRestoreAndSchemaMigration;
var
  DesignOwner, ReloadOwner: TComponent;
  Vp: TCastleViewport;
  Hero: TCastleBox;
  Chest: TCastleSphere;
  HeroGas: TCastleAbilitySystemBehavior;
  Quests: TCastleQuestTracker;
  SaveMgr, ReloadedMgr: TCastleSaveSlotManager;
  V1SnapshotJson, SerializedMgr: String;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);

    Hero := TCastleBox.Create(DesignOwner);
    Hero.Name := 'HeroActor';
    Hero.Translation := Vector3(2.0, 1.0, -4.0);
    Hero.Scale := Vector3(1.0, 1.0, 1.0);
    Vp.Items.Add(Hero);

    HeroGas := TCastleAbilitySystemBehavior.Create(DesignOwner);
    HeroGas.Name := 'HeroGas';
    HeroGas.Preset := gapArcaneMage;
    HeroGas.SetBaseValue('Health', 95.0);
    HeroGas.SetBaseValue('Mana', 120.0);
    HeroGas.GrantTag('Buff.Sanctuary');
    Hero.AddBehavior(HeroGas);

    Chest := TCastleSphere.Create(DesignOwner);
    Chest.Name := 'LootChest';
    Chest.Translation := Vector3(6.0, 0.5, -2.0);
    Chest.Exists := True;
    Vp.Items.Add(Chest);

    Quests := TCastleQuestTracker.Create(DesignOwner);
    Quests.Name := 'MainQuestTracker';
    Quests.AddOrUpdateQuest('Q_DragonRelic', 'Dragon Relic', 'Recover the relic', qsActive, 250, 'Quest.Done');
    Quests.AddObjective('Q_DragonRelic', 'Obj_FindKey', 'Find Vault Key', 1, False);

    SaveMgr := TSaveReplayHelper.EnsureSaveSlotManagerInDesign(Vp, DesignOwner);
    SaveMgr.SchemaVersion := 1;
    SaveMgr.PlaytimeSec := 42.5;
    SaveMgr.SetWorldVar('PlayerGold', '350');
    SaveMgr.SaveSlot('Checkpoint_Shrine', 'Before Boss Gate', Vp, DesignOwner);
    V1SnapshotJson := SaveMgr.FindSlot('Checkpoint_Shrine').SnapshotJson;

    { Mutate world state heavily after checkpoint (including triggering Fireball cooldown!) }
    AssertTrue(HeroGas.TryActivateAbility('Fireball', HeroGas));
    AssertTrue(HeroGas.Abilities[0].RemainingCooldownSec > 1.0);
    Hero.Translation := Vector3(25.0, 0.0, 18.0);
    Hero.Scale := Vector3(2.0, 2.0, 2.0);
    HeroGas.SetBaseValue('Health', 12.0);
    HeroGas.SetBaseValue('Mana', 5.0);
    HeroGas.RevokeTag('Buff.Sanctuary');
    Chest.Exists := False;
    Quests.CompleteQuest('Q_DragonRelic');
    SaveMgr.SetWorldVar('PlayerGold', '0');

    { Upgrade manager schema to v2 & restore v1 checkpoint -> auto-migrates PlayerGold -> Economy.Gold! }
    SaveMgr.SchemaVersion := 2;
    AssertTrue(SaveMgr.LoadSlot('Checkpoint_Shrine', Vp, DesignOwner));

    AssertVectorEquals(Vector3(2.0, 1.0, -4.0), Hero.Translation, 0.001);
    AssertVectorEquals(Vector3(1.0, 1.0, 1.0), Hero.Scale, 0.001);
    AssertSameValue(95.0, HeroGas.GetBaseValue('Health'), 0.01);
    AssertSameValue(120.0, HeroGas.GetBaseValue('Mana'), 0.01);
    AssertTrue(HeroGas.HasMatchingTag('Buff.Sanctuary'));
    AssertSameValue(0.0, HeroGas.Abilities[0].RemainingCooldownSec, 0.001);
    AssertTrue(Chest.Exists);
    AssertTrue(Quests.GetQuestState('Q_DragonRelic') = qsActive);
    AssertEquals('350', SaveMgr.GetWorldVar('Economy.Gold'));
    AssertEquals('1', SaveMgr.GetWorldVar('__MigratedFromSchema'));

    { ComponentToString JSON roundtrip of TCastleSaveSlotManager }
    SerializedMgr := ComponentToString(SaveMgr);
    ReloadedMgr := StringToComponent(SerializedMgr, ReloadOwner) as TCastleSaveSlotManager;
    AssertEquals(1, ReloadedMgr.Slots.Count);
    AssertTrue(V1SnapshotJson <> '');
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolSaveReplay.TestDeterministicReplayKeyframeScrubSlerpCuesAndJsonRoundtrip;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Ship: TCastleBox;
  Rec, RecReloaded: TCastleReplayRecorder;
  ExportedJson, Md: String;
  Report: TSaveReplayAuditReport;
begin
  DesignOwner := TComponent.Create(nil);
  FFiredCueIds := TStringList.Create;
  try
    Vp := TCastleViewport.Create(DesignOwner);

    Ship := TCastleBox.Create(DesignOwner);
    Ship.Name := 'Airship';
    Vp.Items.Add(Ship);

    Rec := TSaveReplayHelper.EnsureReplayRecorderInDesign(Vp, DesignOwner);
    Rec.OnCueFired := {$ifdef FPC}@{$endif}HandleReplayCue;

    { Frame 0 at t = 0.0s }
    Ship.Translation := Vector3(0.0, 5.0, 0.0);
    Ship.Rotation := Vector4(0.0, 1.0, 0.0, 0.0);
    Rec.RecordFrame(Vp, 0.0, DesignOwner);

    { Frame 1 at t = 1.0s + Cue }
    Ship.Translation := Vector3(10.0, 5.0, 0.0);
    Ship.Rotation := Vector4(0.0, 1.0, 0.0, Pi * 0.5);
    Rec.RecordFrame(Vp, 1.0, DesignOwner);
    Rec.RecordCue('SFX.Afterburner', 'Stage1');

    { Frame 2 at t = 2.0s }
    Ship.Translation := Vector3(20.0, 9.0, 0.0);
    Ship.Rotation := Vector4(0.0, 1.0, 0.0, Pi);
    Rec.RecordFrame(Vp, 1.0, DesignOwner);

    AssertEquals(3, Rec.FrameCount);
    AssertSameValue(2.0, Rec.DurationSec, 0.001);

    { Export & import into a fresh ReplayRecorder }
    ExportedJson := Rec.ExportReplayJson;
    RecReloaded := TCastleReplayRecorder.Create(DesignOwner);
    RecReloaded.Name := 'ReplayReloaded';
    RecReloaded.OnCueFired := {$ifdef FPC}@{$endif}HandleReplayCue;
    RecReloaded.ImportReplayJson(ExportedJson);
    AssertEquals(3, RecReloaded.FrameCount);
    AssertEquals(1, RecReloaded.CueEvents.Count);

    { Scrub from 0.0 -> 0.5s (midpoint between Frame 0 and Frame 1): X=5.0, Yaw=45 deg }
    RecReloaded.ScrubToTime(Vp, 0.0, DesignOwner);
    FFiredCueIds.Clear;
    RecReloaded.ScrubToTime(Vp, 0.5, DesignOwner);
    AssertVectorEquals(Vector3(5.0, 5.0, 0.0), Ship.Translation, 0.01);
    AssertSameValue(Pi * 0.25, Abs(Ship.Rotation.W), 0.02);
    AssertEquals(0, FFiredCueIds.Count);

    { Scrub from 0.5s -> 1.5s: crosses t=1.0s cue 'SFX.Afterburner:Stage1' & interpolates Y=7.0! }
    RecReloaded.ScrubToTime(Vp, 1.5, DesignOwner);
    AssertVectorEquals(Vector3(15.0, 7.0, 0.0), Ship.Translation, 0.01);
    AssertEquals(1, FFiredCueIds.Count);
    AssertEquals('SFX.Afterburner:Stage1', FFiredCueIds[0]);

    Report := TSaveReplayHelper.ScanDesign(Vp, DesignOwner);
    try
      AssertEquals(2, Length(Report.ReplayRecorders));
      AssertEquals(6, Report.TotalReplayFrames);
    finally
      FreeAndNil(Report);
    end;

    Md := TSaveReplayHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('ReplayRecorder', Md) > 0);
  finally
    FreeAndNil(FFiredCueIds);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolSaveReplay);
end.
