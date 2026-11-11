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

{ Automated unit tests for @link(TCastleSequencePlayer) and
  @link(TSequencerHelper) (Phase 287 — UE 5.9 / 6.0 Sequencer Parity). }
unit TestToolSequencer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolSequencer = class(TCastleTestCase)
  strict private
    FCueLog: TStringList;
    procedure HandleCueEvent(Sender: TObject;
      const CueName, Payload: String; const TimeSec: Single);
  published
    procedure TestMultiTrackInterpolationCameraCutsAndJsonRoundtrip;
    procedure TestLiveCapturePlaybackModesAndEventCues;
  end;

implementation

uses
  CastleVectors, CastleComponentSerialize, CastleUIControls, CastleControls,
  CastleViewport, CastleCameras, CastleTransform, CastleScene,
  CastleSequencer, ToolSequencer;

procedure TTestToolSequencer.HandleCueEvent(Sender: TObject;
  const CueName, Payload: String; const TimeSec: Single);
begin
  if FCueLog <> nil then
    FCueLog.Add(CueName + ':' + Payload);
end;

procedure TTestToolSequencer.TestMultiTrackInterpolationCameraCutsAndJsonRoundtrip;
var
  DesignOwner, RestoredOwner: TComponent;
  RootUi: TCastleUserInterface;
  Vp, RestoredVp: TCastleViewport;
  HeroBox, RestoredHero: TCastleBox;
  KeyLight, RestoredLight: TCastlePointLight;
  WideCam, CloseupCam, RestoredCloseup: TCastleCamera;
  Subtitle, RestoredSub: TCastleLabel;
  Seq, RestoredSeq: TCastleSequencePlayer;
  SavedJson, MdText: String;
  AppliedCount: Integer;
begin
  DesignOwner := TComponent.Create(nil);
  try
    RootUi := TCastleUserInterface.Create(DesignOwner);
    RootUi.Name := 'CutsceneRoot';

    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainVp';
    RootUi.InsertFront(Vp);

    WideCam := TCastleCamera.Create(DesignOwner);
    WideCam.Name := 'WideCam';
    Vp.Items.Add(WideCam);

    CloseupCam := TCastleCamera.Create(DesignOwner);
    CloseupCam.Name := 'CloseupCam';
    Vp.Items.Add(CloseupCam);
    Vp.Camera := WideCam;

    HeroBox := TCastleBox.Create(DesignOwner);
    HeroBox.Name := 'HeroBox';
    Vp.Items.Add(HeroBox);

    KeyLight := TCastlePointLight.Create(DesignOwner);
    KeyLight.Name := 'KeyLight';
    KeyLight.Intensity := 1.0;
    Vp.Items.Add(KeyLight);

    Subtitle := TCastleLabel.Create(DesignOwner);
    Subtitle.Name := 'SubtitleLabel';
    Subtitle.Exists := false;
    Subtitle.Caption := '';
    RootUi.InsertFront(Subtitle);

    Seq := TSequencerHelper.CreateSequencePlayerInDesign(
      RootUi, DesignOwner, 'IntroCutscene', 4.0, true);
    AssertTrue(Seq <> nil);

    { 1. Vector3 Translation track (Linear 0..2s, SmoothStep 2..4s) }
    Seq.AddOrUpdateVector3Key('HeroBox', 'Translation', 0.0, Vector3(0, 0, 0), seLinear);
    Seq.AddOrUpdateVector3Key('HeroBox', 'Translation', 2.0, Vector3(10, 4, -6), seSmoothStep);
    Seq.AddOrUpdateVector3Key('HeroBox', 'Translation', 4.0, Vector3(20, 0, -12), seLinear);

    { 2. Float Intensity track (Linear 0..4s: 1.0 -> 5.0) }
    Seq.AddOrUpdateFloatKey('KeyLight', 'Intensity', 0.0, 1.0, seLinear);
    Seq.AddOrUpdateFloatKey('KeyLight', 'Intensity', 4.0, 5.0, seLinear);

    { 3. Bool Exists track }
    Seq.AddOrUpdateBoolKey('SubtitleLabel', 'Exists', 0.0, false);
    Seq.AddOrUpdateBoolKey('SubtitleLabel', 'Exists', 1.5, true);

    { 4. String Caption track }
    Seq.AddOrUpdateStringKey('SubtitleLabel', 'Caption', 0.0, 'Prologue');
    Seq.AddOrUpdateStringKey('SubtitleLabel', 'Caption', 2.0, 'The Gate Opens');

    { 5. CameraCut track }
    Seq.AddOrUpdateCameraCutKey('MainVp', 0.0, 'WideCam');
    Seq.AddOrUpdateCameraCutKey('MainVp', 2.5, 'CloseupCam');

    AssertEquals(5, Seq.TrackCount);
    AssertEquals(11, Seq.TotalKeyCount);

    { Scrub to t = 1.0s }
    AppliedCount := Seq.EvaluateAtTime(1.0);
    AssertEquals(5, AppliedCount);
    AssertVectorEquals(Vector3(5, 2, -3), HeroBox.Translation, 0.001);
    AssertSameValue(2.0, KeyLight.Intensity, 0.001);
    AssertFalse(Subtitle.Exists);
    AssertEquals('Prologue', Subtitle.Caption);
    AssertTrue(Vp.Camera = WideCam);

    { Scrub to t = 3.0s (midpoint of SmoothStep(0.5) = 0.5) }
    Seq.EvaluateAtTime(3.0);
    AssertVectorEquals(Vector3(15, 2, -9), HeroBox.Translation, 0.001);
    AssertSameValue(4.0, KeyLight.Intensity, 0.001);
    AssertTrue(Subtitle.Exists);
    AssertEquals('The Gate Opens', Subtitle.Caption);
    AssertTrue(Vp.Camera = CloseupCam);

    MdText := TSequencerHelper.FormatSequenceMarkdown(Seq);
    AssertTrue(Pos('IntroCutscene', MdText) > 0);
    AssertTrue(Pos('camera_cut', MdText) > 0);

    { Roundtrip entire UI + Viewport + SequencePlayer via JSON }
    SavedJson := ComponentToString(RootUi);
    RestoredOwner := TComponent.Create(nil);
    try
      StringToComponent(SavedJson, RestoredOwner);
      RestoredSeq := RestoredOwner.FindRequiredComponent(Seq.Name) as TCastleSequencePlayer;
      RestoredHero := RestoredOwner.FindRequiredComponent('HeroBox') as TCastleBox;
      RestoredLight := RestoredOwner.FindRequiredComponent('KeyLight') as TCastlePointLight;
      RestoredSub := RestoredOwner.FindRequiredComponent('SubtitleLabel') as TCastleLabel;
      RestoredVp := RestoredOwner.FindRequiredComponent('MainVp') as TCastleViewport;
      RestoredCloseup := RestoredOwner.FindRequiredComponent('CloseupCam') as TCastleCamera;

      AssertEquals(5, RestoredSeq.TrackCount);
      RestoredSeq.Rewind;
      AssertVectorEquals(Vector3(0, 0, 0), RestoredHero.Translation, 0.001);

      RestoredSeq.EvaluateAtTime(3.0);
      AssertVectorEquals(Vector3(15, 2, -9), RestoredHero.Translation, 0.001);
      AssertSameValue(4.0, RestoredLight.Intensity, 0.001);
      AssertTrue(RestoredSub.Exists);
      AssertEquals('The Gate Opens', RestoredSub.Caption);
      AssertTrue(RestoredVp.Camera = RestoredCloseup);
    finally
      FreeAndNil(RestoredOwner);
    end;
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolSequencer.TestLiveCapturePlaybackModesAndEventCues;
var
  OwnerComp: TComponent;
  RootT, DoorMesh: TCastleTransform;
  Seq: TCastleSequencePlayer;
begin
  FCueLog := TStringList.Create;
  OwnerComp := TComponent.Create(nil);
  try
    RootT := TCastleTransform.Create(OwnerComp);
    RootT.Name := 'DungeonRoot';

    DoorMesh := TCastleTransform.Create(OwnerComp);
    DoorMesh.Name := 'StoneDoor';
    RootT.Add(DoorMesh);

    Seq := TSequencerHelper.CreateSequencePlayerInDesign(
      RootT, OwnerComp, 'DoorOpenSeq', 2.0, false);
    Seq.OnCueEvent := {$ifdef FPC}@{$endif}HandleCueEvent;

    { Capture live keyframe at t=0 }
    DoorMesh.Translation := Vector3(0, 0, 0);
    AssertTrue(TSequencerHelper.CaptureLivePropertyKey(
      Seq, DoorMesh, 'Translation', 0.0, seLinear));

    { Move door and capture live keyframe at t=2.0 }
    DoorMesh.Translation := Vector3(0, 6, 0);
    AssertTrue(TSequencerHelper.CaptureLivePropertyKey(
      Seq, DoorMesh, 'Translation', 2.0, seLinear));

    Seq.AddEventCue(0.5, 'PlaySfx', 'stone_scrape');
    Seq.AddEventCue(1.5, 'CameraShake', 'heavy');
    AssertEquals(2, Seq.CueCount);

    { 1. spmOnce playback }
    Seq.PlaybackMode := spmOnce;
    Seq.Rewind;
    Seq.Play;
    Seq.Step(1.0);
    AssertVectorEquals(Vector3(0, 3, 0), DoorMesh.Translation, 0.001);
    AssertEquals(1, FCueLog.Count);
    AssertEquals('PlaySfx:stone_scrape', FCueLog[0]);

    Seq.Step(1.5);
    AssertFalse(Seq.Playing);
    AssertSameValue(2.0, Seq.CurrentTime, 0.001);
    AssertVectorEquals(Vector3(0, 6, 0), DoorMesh.Translation, 0.001);
    AssertEquals(2, FCueLog.Count);
    AssertEquals('CameraShake:heavy', FCueLog[1]);

    { 2. spmLoop wraparound }
    FCueLog.Clear;
    Seq.PlaybackMode := spmLoop;
    Seq.Rewind;
    Seq.Play;
    Seq.Step(2.6);
    AssertTrue(Seq.Playing);
    AssertSameValue(0.6, Seq.CurrentTime, 0.01);
    AssertEquals(3, FCueLog.Count);

    { 3. spmPingPong bounce }
    Seq.PlaybackMode := spmPingPong;
    Seq.Rewind;
    Seq.Play;
    Seq.Step(2.5);
    AssertSameValue(1.5, Seq.CurrentTime, 0.01);
    AssertVectorEquals(Vector3(0, 4.5, 0), DoorMesh.Translation, 0.05);
  finally
    FreeAndNil(OwnerComp);
    FreeAndNil(FCueLog);
  end;
end;

initialization
  RegisterTest(TTestToolSequencer);
end.
