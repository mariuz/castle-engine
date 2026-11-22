{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Animation Blueprint (@link(TCastleAnimBlueprint))
  featuring a composable visual AnimGraph pose evaluation DAG (State Machine,
  Sequence Player, BlendSpace Player, Layered Blend Per Bone, Slot, Two-Bone IK,
  Save/Use Cached Pose, Output Pose), frame-accurate looping AnimNotify and
  AnimNotifyState [Begin/Tick/End] tracks, and transient 3D articulated bone
  visualization (Phase 383 — UE 5.5 UAnimBlueprint Parity). }
unit CastleAnimBlueprint;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Canonical humanoid bone slots evaluated across the AnimGraph pose pipeline. }
  TAnimBoneSlot = (
    absRoot,
    absPelvis,
    absSpineLower,
    absSpineUpper,
    absNeckHead,
    absLeftArm,
    absRightArm,
    absLeftLeg,
    absRightLeg
  );

  { Body mask partition used by Layered Blend Per Bone (UE5 BranchFilter parity). }
  TAnimBodyMask = (
    abmFullBody,
    abmLowerBodyOnly,
    abmUpperBodyOnly
  );

  { Built-in procedural skeletal animation clips for Sequence / BlendSpace nodes. }
  TAnimClipKind = (
    ackIdleBreathe,
    ackWalkCycle,
    ackSprintForward,
    ackUpperBodyAimRifle,
    ackMeleeSlashMontage,
    ackJumpApexAir
  );

  { AnimGraph pose node kinds matching Unreal Engine 5.5 UAnimBlueprint nodes. }
  TAnimGraphNodeKind = (
    ankSequencePlayer,
    ankBlendSpacePlayer,
    ankStateMachine,
    ankLayeredBlendPerBone,
    ankSlotOverride,
    ankTwoBoneIk,
    ankSaveCachedPose,
    ankUseCachedPose,
    ankOutputPose
  );

  { Instant AnimNotify vs. duration AnimNotifyState [Begin..End] window. }
  TAnimNotifyKind = (
    ankInstantNotify,
    ankNotifyStateWindow
  );

  { Built-in UE 5.5 Animation Blueprint starter presets. }
  TAnimBlueprintPreset = (
    abpCustom,
    abpLocomotionUpperBodyAimAndFootIk,
    abpCombatSlotMontageOverride,
    abpAirborneJumpStateCrossfade
  );

  { Local bone transform inside a skeletal @link(TAnimPose). }
  TAnimBonePose = record
    LocalOffset: TVector3;
    EulerDeg: TVector3; { Pitch (X), Yaw (Y), Roll (Z) in degrees }
  end;

  { Full 9-bone humanoid pose passed along AnimGraph pose wires. }
  TAnimPose = record
    Bones: array[TAnimBoneSlot] of TAnimBonePose;
    class function IdentityPose: TAnimPose; static;
    class function BlendPoses(const A, B: TAnimPose; const Alpha: Single): TAnimPose; static;
    class function LayeredBlend(const ABasePose, ABlendPose: TAnimPose;
      const AMask: TAnimBodyMask; const ABlendWeight: Single): TAnimPose; static;
  end;

  { Single AnimNotify or AnimNotifyState track event on a clip timeline. }
  TAnimNotifyEvent = record
    NotifyName: String;
    Kind: TAnimNotifyKind;
    Clip: TAnimClipKind;
    TriggerTimeSec: Single;
    EndTimeSec: Single;
    ActiveWindowNow: Boolean;
  end;
  TAnimNotifyEventArray = array of TAnimNotifyEvent;

  { Node instance inside a @link(TCastleAnimBlueprint) AnimGraph pose DAG. }
  TAnimGraphNode = record
    NodeId: String;
    Kind: TAnimGraphNodeKind;
    PosX: Single;
    PosY: Single;
    Clip: TAnimClipKind;
    PlayRate: Single;
    Looping: Boolean;
    BlendWeight: Single;
    BodyMask: TAnimBodyMask;
    CachePoseName: String;
    IkOffsetLeftFootY: Single;
    IkOffsetRightFootY: Single;
    { Upstream pose NodeIds (Pin 0 = BasePose/Source, Pin 1 = BlendPose/Override) }
    InputPoseNode0: String;
    InputPoseNode1: String;
    { Diagnostics: how many times this node actually evaluated during the current tick }
    EvalCountThisTick: Integer;
  end;
  TAnimGraphNodeArray = array of TAnimGraphNode;

  { Unreal Engine 5.5-style Animation Blueprint component evaluating a directed
    AnimGraph pose pipeline and frame-accurate AnimNotify tracks onto a 3D rig. }
  TCastleAnimBlueprint = class(TCastleTransform)
  public
    const
      DefaultClipDurationSec = 1.0;
  private
    FPreset: TAnimBlueprintPreset;
    FSpeedMps: Single;
    FDirectionDeg: Single;
    FIsInAir: Boolean;
    FUpperBodyAimWeight: Single;
    FSlotMontageWeight: Single;
    FFootIkAlpha: Single;
    FShowPreviewSkeleton: Boolean;

    FNodes: TAnimGraphNodeArray;
    FNotifies: TAnimNotifyEventArray;

    { Transient runtime & diagnostic state }
    FPlayheadTimeSec: Single;
    FActiveLocomotionState: String;
    FStateBlendAlpha: Single;
    FCurrentPose: TAnimPose;
    FValidationErrors: TStringList;
    FTriggeredNotifies: TStringList;
    FPreviewRoot: TCastleTransform;
    FBoneBoxes: array[TAnimBoneSlot] of TCastleBox;
    FLastEvaluationValid: Boolean;

    procedure SetPreset(const AValue: TAnimBlueprintPreset);
    procedure SetShowPreviewSkeleton(const AValue: Boolean);
    function GetGraphJson: String;
    procedure SetGraphJson(const AValue: String);

    procedure ClearPreviewSkeleton;
    procedure EnsurePreviewSkeleton;
    procedure SyncPreviewSkeletonFromPose;

    class function SampleProceduralClip(const AClip: TAnimClipKind;
      const ATimeSec: Single): TAnimPose; static;
    procedure DispatchClipNotifies(const AClip: TAnimClipKind;
      const AOldTimeSec, ANewTimeSec, ADurationSec: Single; const ALooping: Boolean);
    function EvaluatePoseNodeRecursive(const ANodeIdx: Integer;
      var VisitState: array of Byte;
      var NodeCachedValid: array of Boolean;
      var NodeCachedPoses: array of TAnimPose): TAnimPose;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Static metadata }
    class function NodeKindTitle(const AKind: TAnimGraphNodeKind): String; static;
    class function NodeInputCount(const AKind: TAnimGraphNodeKind): Integer; static;
    class function BoneSlotName(const ASlot: TAnimBoneSlot): String; static;
    class function BoneIsUpperBody(const ASlot: TAnimBoneSlot): Boolean; static;
    class function MakeDefaultNode(const ANodeId: String; const AKind: TAnimGraphNodeKind;
      const AX: Single = 60; const AY: Single = 80): TAnimGraphNode; static;

    { Authoring API }
    procedure ClearAll;
    procedure ApplyPreset(const APreset: TAnimBlueprintPreset);
    function FindNodeIndex(const ANodeId: String): Integer;
    function FindOutputNodeIndex: Integer;
    function AddOrUpdateNode(const ANode: TAnimGraphNode): Integer;
    function SetNodePosition(const ANodeId: String; const AX, AY: Single): Boolean;
    function ConnectPoseNodes(const AFromNodeId, AToNodeId: String;
      const AToInputPin: Integer = 0): Boolean;

    function AddNotifyEvent(const AName: String; const AKind: TAnimNotifyKind;
      const AClip: TAnimClipKind; const ATriggerSec: Single;
      const AEndSec: Single = 0.0): Integer;
    procedure ClearNotifyHistory;

    { Validation & Pose Evaluation }
    function ValidateAnimGraph: Boolean;
    procedure ResetPlayback;
    function StepAnimBlueprint(const ADeltaSeconds: Single): Boolean;

    function AnimBlueprintSummaryBadge: String;

    property Nodes: TAnimGraphNodeArray read FNodes;
    property Notifies: TAnimNotifyEventArray read FNotifies;
    property CurrentPose: TAnimPose read FCurrentPose;
    property PlayheadTimeSec: Single read FPlayheadTimeSec;
    property ActiveLocomotionState: String read FActiveLocomotionState;
    property ValidationErrors: TStringList read FValidationErrors;
    property TriggeredNotifies: TStringList read FTriggeredNotifies;
    property LastEvaluationValid: Boolean read FLastEvaluationValid;
  published
    property SpeedMps: Single read FSpeedMps write FSpeedMps;
    property DirectionDeg: Single read FDirectionDeg write FDirectionDeg;
    property IsInAir: Boolean read FIsInAir write FIsInAir default False;
    property UpperBodyAimWeight: Single read FUpperBodyAimWeight write FUpperBodyAimWeight;
    property SlotMontageWeight: Single read FSlotMontageWeight write FSlotMontageWeight;
    property FootIkAlpha: Single read FFootIkAlpha write FFootIkAlpha;
    property ShowPreviewSkeleton: Boolean read FShowPreviewSkeleton write SetShowPreviewSkeleton default True;
    property GraphJson: String read GetGraphJson write SetGraphJson;
    property Preset: TAnimBlueprintPreset read FPreset write SetPreset default abpLocomotionUpperBodyAimAndFootIk;
  end;

implementation

uses
  fpjson, jsonparser;

{ TAnimPose ------------------------------------------------------------------ }

class function TAnimPose.IdentityPose: TAnimPose;
var
  S: TAnimBoneSlot;
begin
  Result := Default(TAnimPose);
  Result.Bones[absRoot].LocalOffset := Vector3(0, 0, 0);
  Result.Bones[absPelvis].LocalOffset := Vector3(0, 0.95, 0);
  Result.Bones[absSpineLower].LocalOffset := Vector3(0, 1.20, 0);
  Result.Bones[absSpineUpper].LocalOffset := Vector3(0, 1.48, 0);
  Result.Bones[absNeckHead].LocalOffset := Vector3(0, 1.78, 0);
  Result.Bones[absLeftArm].LocalOffset := Vector3(-0.36, 1.44, 0);
  Result.Bones[absRightArm].LocalOffset := Vector3(0.36, 1.44, 0);
  Result.Bones[absLeftLeg].LocalOffset := Vector3(-0.18, 0.48, 0);
  Result.Bones[absRightLeg].LocalOffset := Vector3(0.18, 0.48, 0);
  for S in TAnimBoneSlot do
    Result.Bones[S].EulerDeg := Vector3(0, 0, 0);
end;

class function TAnimPose.BlendPoses(const A, B: TAnimPose;
  const Alpha: Single): TAnimPose;
var
  T: Single;
  S: TAnimBoneSlot;
begin
  T := EnsureRange(Alpha, 0.0, 1.0);
  for S in TAnimBoneSlot do
  begin
    Result.Bones[S].LocalOffset := Lerp(T, A.Bones[S].LocalOffset, B.Bones[S].LocalOffset);
    Result.Bones[S].EulerDeg := Lerp(T, A.Bones[S].EulerDeg, B.Bones[S].EulerDeg);
  end;
end;

class function TAnimPose.LayeredBlend(const ABasePose, ABlendPose: TAnimPose;
  const AMask: TAnimBodyMask; const ABlendWeight: Single): TAnimPose;
var
  W: Single;
  S: TAnimBoneSlot;
  ApplySlot: Boolean;
begin
  W := EnsureRange(ABlendWeight, 0.0, 1.0);
  Result := ABasePose;
  if W <= 1e-5 then Exit;

  for S in TAnimBoneSlot do
  begin
    case AMask of
      abmFullBody:      ApplySlot := True;
      abmUpperBodyOnly: ApplySlot := TCastleAnimBlueprint.BoneIsUpperBody(S);
      abmLowerBodyOnly: ApplySlot := not TCastleAnimBlueprint.BoneIsUpperBody(S);
    end;
    if ApplySlot then
    begin
      Result.Bones[S].LocalOffset := Lerp(W, ABasePose.Bones[S].LocalOffset, ABlendPose.Bones[S].LocalOffset);
      Result.Bones[S].EulerDeg := Lerp(W, ABasePose.Bones[S].EulerDeg, ABlendPose.Bones[S].EulerDeg);
    end;
  end;
end;

{ TCastleAnimBlueprint ------------------------------------------------------- }

constructor TCastleAnimBlueprint.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSpeedMps := 5.5;
  FDirectionDeg := 0.0;
  FIsInAir := False;
  FUpperBodyAimWeight := 1.0;
  FSlotMontageWeight := 0.0;
  FFootIkAlpha := 1.0;
  FShowPreviewSkeleton := True;
  FActiveLocomotionState := 'Idle';
  FValidationErrors := TStringList.Create;
  FTriggeredNotifies := TStringList.Create;
  FCurrentPose := TAnimPose.IdentityPose;
  ApplyPreset(abpLocomotionUpperBodyAimAndFootIk);
end;

destructor TCastleAnimBlueprint.Destroy;
begin
  ClearPreviewSkeleton;
  FreeAndNil(FTriggeredNotifies);
  FreeAndNil(FValidationErrors);
  inherited;
end;

procedure TCastleAnimBlueprint.Loaded;
begin
  inherited;
  StepAnimBlueprint(0.0);
end;

function TCastleAnimBlueprint.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'SpeedMps') or
     (PropertyName = 'DirectionDeg') or
     (PropertyName = 'IsInAir') or
     (PropertyName = 'UpperBodyAimWeight') or
     (PropertyName = 'SlotMontageWeight') or
     (PropertyName = 'FootIkAlpha') or
     (PropertyName = 'ShowPreviewSkeleton') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleAnimBlueprint.SetPreset(const AValue: TAnimBlueprintPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleAnimBlueprint.SetShowPreviewSkeleton(const AValue: Boolean);
begin
  if FShowPreviewSkeleton <> AValue then
  begin
    FShowPreviewSkeleton := AValue;
    if not FShowPreviewSkeleton then
      ClearPreviewSkeleton
    else
      SyncPreviewSkeletonFromPose;
  end;
end;

class function TCastleAnimBlueprint.NodeKindTitle(const AKind: TAnimGraphNodeKind): String;
begin
  case AKind of
    ankSequencePlayer:      Result := 'Sequence Player';
    ankBlendSpacePlayer:    Result := 'BlendSpace 2D';
    ankStateMachine:        Result := 'State Machine';
    ankLayeredBlendPerBone: Result := 'Layered Blend / Bone';
    ankSlotOverride:        Result := 'Slot Montage';
    ankTwoBoneIk:           Result := 'Two-Bone Foot IK';
    ankSaveCachedPose:      Result := 'Save Cached Pose';
    ankUseCachedPose:       Result := 'Use Cached Pose';
    ankOutputPose:          Result := 'Output Pose';
  end;
end;

class function TCastleAnimBlueprint.NodeInputCount(const AKind: TAnimGraphNodeKind): Integer;
begin
  case AKind of
    ankSequencePlayer, ankBlendSpacePlayer, ankStateMachine, ankUseCachedPose:
      Result := 0;
    ankLayeredBlendPerBone, ankSlotOverride:
      Result := 2;
  else
    Result := 1;
  end;
end;

class function TCastleAnimBlueprint.BoneSlotName(const ASlot: TAnimBoneSlot): String;
begin
  case ASlot of
    absRoot:       Result := 'Root';
    absPelvis:     Result := 'Pelvis';
    absSpineLower: Result := 'SpineLower';
    absSpineUpper: Result := 'SpineUpper';
    absNeckHead:   Result := 'NeckHead';
    absLeftArm:    Result := 'LeftArm';
    absRightArm:   Result := 'RightArm';
    absLeftLeg:    Result := 'LeftLeg';
    absRightLeg:   Result := 'RightLeg';
  end;
end;

class function TCastleAnimBlueprint.BoneIsUpperBody(const ASlot: TAnimBoneSlot): Boolean;
begin
  Result := ASlot in [absSpineLower, absSpineUpper, absNeckHead, absLeftArm, absRightArm];
end;

class function TCastleAnimBlueprint.MakeDefaultNode(const ANodeId: String;
  const AKind: TAnimGraphNodeKind; const AX, AY: Single): TAnimGraphNode;
begin
  Result := Default(TAnimGraphNode);
  Result.NodeId := ANodeId;
  Result.Kind := AKind;
  Result.PosX := AX;
  Result.PosY := AY;
  Result.Clip := ackIdleBreathe;
  Result.PlayRate := 1.0;
  Result.Looping := True;
  Result.BlendWeight := 1.0;
  Result.BodyMask := abmUpperBodyOnly;
  Result.CachePoseName := 'LocomotionCache';
end;

class function TCastleAnimBlueprint.SampleProceduralClip(
  const AClip: TAnimClipKind; const ATimeSec: Single): TAnimPose;
var
  PhaseRad, SinP, CosP: Single;
begin
  Result := TAnimPose.IdentityPose;
  PhaseRad := ATimeSec * 2.0 * Pi;
  SinP := Sin(PhaseRad);
  CosP := Cos(PhaseRad);

  case AClip of
    ackIdleBreathe:
      begin
        Result.Bones[absSpineUpper].EulerDeg := Vector3(2.5 * SinP, 0, 0);
        Result.Bones[absLeftArm].EulerDeg := Vector3(4.0 * SinP, 0, -6.0);
        Result.Bones[absRightArm].EulerDeg := Vector3(-4.0 * SinP, 0, 6.0);
      end;

    ackWalkCycle:
      begin
        Result.Bones[absPelvis].LocalOffset.Y := 0.95 + 0.03 * Abs(SinP);
        Result.Bones[absLeftLeg].EulerDeg := Vector3(24.0 * SinP, 0, 0);
        Result.Bones[absRightLeg].EulerDeg := Vector3(-24.0 * SinP, 0, 0);
        Result.Bones[absLeftArm].EulerDeg := Vector3(-18.0 * SinP, 0, -5.0);
        Result.Bones[absRightArm].EulerDeg := Vector3(18.0 * SinP, 0, 5.0);
      end;

    ackSprintForward:
      begin
        Result.Bones[absPelvis].LocalOffset.Y := 0.92 + 0.06 * Abs(SinP);
        Result.Bones[absSpineLower].EulerDeg := Vector3(14.0, 6.0 * SinP, 0);
        Result.Bones[absLeftLeg].EulerDeg := Vector3(48.0 * SinP, 0, 0);
        Result.Bones[absRightLeg].EulerDeg := Vector3(-48.0 * SinP, 0, 0);
        Result.Bones[absLeftArm].EulerDeg := Vector3(-42.0 * SinP, 0, -8.0);
        Result.Bones[absRightArm].EulerDeg := Vector3(42.0 * SinP, 0, 8.0);
      end;

    ackUpperBodyAimRifle:
      begin
        { Distinct aimed torso & raised rifle arms while legs stay untouched }
        Result.Bones[absSpineLower].EulerDeg := Vector3(-4.0, 22.0, 0);
        Result.Bones[absSpineUpper].EulerDeg := Vector3(-8.0, 25.0, 0);
        Result.Bones[absNeckHead].EulerDeg := Vector3(0.0, -12.0, 0);
        Result.Bones[absLeftArm].EulerDeg := Vector3(-68.0, 28.0, 12.0);
        Result.Bones[absRightArm].EulerDeg := Vector3(-75.0, -14.0, -10.0);
      end;

    ackMeleeSlashMontage:
      begin
        Result.Bones[absSpineUpper].EulerDeg := Vector3(12.0, -45.0 * CosP, 0);
        Result.Bones[absRightArm].EulerDeg := Vector3(-85.0 + 60.0 * SinP, -35.0 * CosP, 20.0);
        Result.Bones[absLeftArm].EulerDeg := Vector3(-25.0, 20.0, -15.0);
      end;

    ackJumpApexAir:
      begin
        Result.Bones[absPelvis].LocalOffset.Y := 1.18;
        Result.Bones[absLeftLeg].EulerDeg := Vector3(-38.0, 0, -4.0);
        Result.Bones[absRightLeg].EulerDeg := Vector3(22.0, 0, 4.0);
        Result.Bones[absLeftArm].EulerDeg := Vector3(-55.0, 0, -24.0);
        Result.Bones[absRightArm].EulerDeg := Vector3(-55.0, 0, 24.0);
      end;
  end;
end;

procedure TCastleAnimBlueprint.ClearPreviewSkeleton;
var
  S: TAnimBoneSlot;
begin
  if FPreviewRoot <> nil then
    FreeAndNil(FPreviewRoot);
  for S in TAnimBoneSlot do
    FBoneBoxes[S] := nil;
end;

procedure TCastleAnimBlueprint.EnsurePreviewSkeleton;
var
  S: TAnimBoneSlot;
  B: TCastleBox;
begin
  if FPreviewRoot <> nil then Exit;
  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  FPreviewRoot.Name := 'AnimBP_PreviewSkeleton';
  Add(FPreviewRoot);

  for S in TAnimBoneSlot do
  begin
    B := TCastleBox.Create(FPreviewRoot);
    B.SetTransient;
    B.Pickable := False;
    B.Collides := False;
    B.Name := 'Bone_' + BoneSlotName(S);
    if S in [absLeftLeg, absRightLeg, absLeftArm, absRightArm] then
      B.Size := Vector3(0.14, 0.42, 0.14)
    else if S = absNeckHead then
      B.Size := Vector3(0.22, 0.24, 0.22)
    else
      B.Size := Vector3(0.32, 0.24, 0.20);

    if BoneIsUpperBody(S) then
      B.Color := Vector4(0.26, 0.68, 0.96, 1.0)
    else
      B.Color := Vector4(0.28, 0.86, 0.52, 1.0);
    FBoneBoxes[S] := B;
    FPreviewRoot.Add(B);
  end;
end;

procedure TCastleAnimBlueprint.SyncPreviewSkeletonFromPose;
var
  S: TAnimBoneSlot;
begin
  if not FShowPreviewSkeleton then Exit;
  EnsurePreviewSkeleton;
  for S in TAnimBoneSlot do
    if FBoneBoxes[S] <> nil then
    begin
      FBoneBoxes[S].Translation := FCurrentPose.Bones[S].LocalOffset;
      FBoneBoxes[S].Rotation := Vector4(1, 0, 0, DegToRad(FCurrentPose.Bones[S].EulerDeg.X));
    end;
end;

procedure TCastleAnimBlueprint.ClearAll;
begin
  FNodes := nil;
  FNotifies := nil;
  FPlayheadTimeSec := 0.0;
  FStateBlendAlpha := 0.0;
  FValidationErrors.Clear;
  FTriggeredNotifies.Clear;
  FLastEvaluationValid := False;
end;

function TCastleAnimBlueprint.FindNodeIndex(const ANodeId: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if SameText(FNodes[I].NodeId, ANodeId) then
      Exit(I);
  Result := -1;
end;

function TCastleAnimBlueprint.FindOutputNodeIndex: Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNodes) do
    if FNodes[I].Kind = ankOutputPose then
      Exit(I);
  Result := -1;
end;

function TCastleAnimBlueprint.AddOrUpdateNode(const ANode: TAnimGraphNode): Integer;
begin
  Result := FindNodeIndex(ANode.NodeId);
  if Result < 0 then
  begin
    Result := Length(FNodes);
    SetLength(FNodes, Result + 1);
  end;
  FNodes[Result] := ANode;
end;

function TCastleAnimBlueprint.SetNodePosition(const ANodeId: String;
  const AX, AY: Single): Boolean;
var
  Idx: Integer;
begin
  Idx := FindNodeIndex(ANodeId);
  if Idx < 0 then Exit(False);
  FNodes[Idx].PosX := AX;
  FNodes[Idx].PosY := AY;
  Result := True;
end;

function TCastleAnimBlueprint.ConnectPoseNodes(const AFromNodeId, AToNodeId: String;
  const AToInputPin: Integer): Boolean;
var
  ToIdx: Integer;
begin
  if FindNodeIndex(AFromNodeId) < 0 then Exit(False);
  ToIdx := FindNodeIndex(AToNodeId);
  if ToIdx < 0 then Exit(False);
  if AToInputPin = 1 then
    FNodes[ToIdx].InputPoseNode1 := AFromNodeId
  else
    FNodes[ToIdx].InputPoseNode0 := AFromNodeId;
  Result := True;
end;

function TCastleAnimBlueprint.AddNotifyEvent(const AName: String;
  const AKind: TAnimNotifyKind; const AClip: TAnimClipKind;
  const ATriggerSec, AEndSec: Single): Integer;
begin
  Result := Length(FNotifies);
  SetLength(FNotifies, Result + 1);
  FNotifies[Result].NotifyName := AName;
  FNotifies[Result].Kind := AKind;
  FNotifies[Result].Clip := AClip;
  FNotifies[Result].TriggerTimeSec := EnsureRange(ATriggerSec, 0.0, DefaultClipDurationSec);
  FNotifies[Result].EndTimeSec := EnsureRange(Max(ATriggerSec, AEndSec), 0.0, DefaultClipDurationSec);
  FNotifies[Result].ActiveWindowNow := False;
end;

procedure TCastleAnimBlueprint.ClearNotifyHistory;
var
  I: Integer;
begin
  FTriggeredNotifies.Clear;
  for I := 0 to High(FNotifies) do
    FNotifies[I].ActiveWindowNow := False;
end;

procedure TCastleAnimBlueprint.ResetPlayback;
begin
  FPlayheadTimeSec := 0.0;
  FStateBlendAlpha := 0.0;
  ClearNotifyHistory;
end;

{ Validation ----------------------------------------------------------------- }

function TCastleAnimBlueprint.ValidateAnimGraph: Boolean;
var
  I, J: Integer;
  Colors: array of Byte;

  function FindSaveCacheIndex(const ACacheName: String): Integer;
  var
    K: Integer;
  begin
    for K := 0 to High(FNodes) do
      if (FNodes[K].Kind = ankSaveCachedPose) and
         SameText(FNodes[K].CachePoseName, ACacheName) then
        Exit(K);
    Result := -1;
  end;

  function HasCycleDfs(const Idx: Integer): Boolean;
  var
    NextIdx: Integer;
  begin
    Result := False;
    Colors[Idx] := 1;
    if FNodes[Idx].InputPoseNode0 <> '' then
    begin
      NextIdx := FindNodeIndex(FNodes[Idx].InputPoseNode0);
      if NextIdx >= 0 then
      begin
        if Colors[NextIdx] = 1 then Exit(True);
        if (Colors[NextIdx] = 0) and HasCycleDfs(NextIdx) then Exit(True);
      end;
    end;
    if FNodes[Idx].InputPoseNode1 <> '' then
    begin
      NextIdx := FindNodeIndex(FNodes[Idx].InputPoseNode1);
      if NextIdx >= 0 then
      begin
        if Colors[NextIdx] = 1 then Exit(True);
        if (Colors[NextIdx] = 0) and HasCycleDfs(NextIdx) then Exit(True);
      end;
    end;
    if FNodes[Idx].Kind = ankUseCachedPose then
    begin
      NextIdx := FindSaveCacheIndex(FNodes[Idx].CachePoseName);
      if NextIdx >= 0 then
      begin
        if Colors[NextIdx] = 1 then Exit(True);
        if (Colors[NextIdx] = 0) and HasCycleDfs(NextIdx) then Exit(True);
      end;
    end;
    Colors[Idx] := 2;
  end;

begin
  FValidationErrors.Clear;
  if FindOutputNodeIndex < 0 then
    FValidationErrors.Add('AnimGraph is missing an Output Pose (ankOutputPose) node.');

  for I := 0 to High(FNodes) do
  begin
    for J := I + 1 to High(FNodes) do
      if SameText(FNodes[I].NodeId, FNodes[J].NodeId) then
        FValidationErrors.Add(Format('Duplicate AnimGraph NodeId "%s".', [FNodes[I].NodeId]));

    if (FNodes[I].InputPoseNode0 <> '') and (FindNodeIndex(FNodes[I].InputPoseNode0) < 0) then
      FValidationErrors.Add(Format('Node "%s" Input 0 references missing node "%s".',
        [FNodes[I].NodeId, FNodes[I].InputPoseNode0]));

    if (FNodes[I].InputPoseNode1 <> '') and (FindNodeIndex(FNodes[I].InputPoseNode1) < 0) then
      FValidationErrors.Add(Format('Node "%s" Input 1 references missing node "%s".',
        [FNodes[I].NodeId, FNodes[I].InputPoseNode1]));

    if (FNodes[I].Kind = ankUseCachedPose) and
       (FindSaveCacheIndex(FNodes[I].CachePoseName) < 0) then
      FValidationErrors.Add(Format('UseCachedPose "%s" references undeclared cache "%s".',
        [FNodes[I].NodeId, FNodes[I].CachePoseName]));
  end;

  SetLength(Colors, Length(FNodes));
  for I := 0 to High(Colors) do Colors[I] := 0;
  for I := 0 to High(FNodes) do
    if (Colors[I] = 0) and HasCycleDfs(I) then
      FValidationErrors.Add(Format('Pose dependency cycle detected at node "%s".',
        [FNodes[I].NodeId]));

  Result := FValidationErrors.Count = 0;
end;

{ AnimNotify & AnimNotifyState Frame-Accurate Dispatcher --------------------- }

procedure TCastleAnimBlueprint.DispatchClipNotifies(const AClip: TAnimClipKind;
  const AOldTimeSec, ANewTimeSec, ADurationSec: Single; const ALooping: Boolean);
var
  I: Integer;
  TTrig, TStart, TEnd: Single;
  CrossedInstant, InsideWindowNow, WasInside: Boolean;
begin
  if Abs(ANewTimeSec - AOldTimeSec) < 1e-6 then Exit;

  for I := 0 to High(FNotifies) do
    if FNotifies[I].Clip = AClip then
      case FNotifies[I].Kind of
        ankInstantNotify:
          begin
            TTrig := FNotifies[I].TriggerTimeSec;
            if ANewTimeSec >= AOldTimeSec then
              CrossedInstant := (TTrig > AOldTimeSec + 1e-6) and (TTrig <= ANewTimeSec + 1e-6)
            else if ALooping then
              { Wrapped around clip end [AOldTimeSec..ADurationSec] U [0..ANewTimeSec] }
              CrossedInstant := (TTrig > AOldTimeSec + 1e-6) or (TTrig <= ANewTimeSec + 1e-6)
            else
              CrossedInstant := False;

            if CrossedInstant then
              FTriggeredNotifies.Add('NOTIFY:' + FNotifies[I].NotifyName);
          end;

        ankNotifyStateWindow:
          begin
            TStart := FNotifies[I].TriggerTimeSec;
            TEnd := FNotifies[I].EndTimeSec;
            WasInside := FNotifies[I].ActiveWindowNow;
            InsideWindowNow := (ANewTimeSec >= TStart - 1e-6) and (ANewTimeSec <= TEnd + 1e-6);

            if (not WasInside) and InsideWindowNow then
            begin
              FNotifies[I].ActiveWindowNow := True;
              FTriggeredNotifies.Add('STATE_BEGIN:' + FNotifies[I].NotifyName);
            end else if WasInside and InsideWindowNow then
            begin
              FTriggeredNotifies.Add('STATE_TICK:' + FNotifies[I].NotifyName);
            end else if WasInside and (not InsideWindowNow) then
            begin
              FNotifies[I].ActiveWindowNow := False;
              FTriggeredNotifies.Add('STATE_END:' + FNotifies[I].NotifyName);
            end;
          end;
      end;
end;

{ Pose Pipeline Evaluation --------------------------------------------------- }

function TCastleAnimBlueprint.EvaluatePoseNodeRecursive(const ANodeIdx: Integer;
  var VisitState: array of Byte;
  var NodeCachedValid: array of Boolean;
  var NodeCachedPoses: array of TAnimPose): TAnimPose;
var
  N: TAnimGraphNode;
  In0Idx, In1Idx, SaveIdx, K: Integer;
  Pose0, Pose1, WalkP, SprintP: TAnimPose;
  RunAlpha, EffectiveWeight, EffectiveIkAlpha: Single;
begin
  Result := TAnimPose.IdentityPose;
  if (ANodeIdx < 0) or (ANodeIdx > High(FNodes)) then Exit;
  if NodeCachedValid[ANodeIdx] then
    Exit(NodeCachedPoses[ANodeIdx]);
  if VisitState[ANodeIdx] = 1 then
    Exit;

  VisitState[ANodeIdx] := 1;
  Inc(FNodes[ANodeIdx].EvalCountThisTick);
  N := FNodes[ANodeIdx];

  Pose0 := TAnimPose.IdentityPose;
  Pose1 := TAnimPose.IdentityPose;
  if (NodeInputCount(N.Kind) >= 1) and (N.InputPoseNode0 <> '') then
  begin
    In0Idx := FindNodeIndex(N.InputPoseNode0);
    if In0Idx >= 0 then
      Pose0 := EvaluatePoseNodeRecursive(In0Idx, VisitState, NodeCachedValid, NodeCachedPoses);
  end;
  if (NodeInputCount(N.Kind) >= 2) and (N.InputPoseNode1 <> '') then
  begin
    In1Idx := FindNodeIndex(N.InputPoseNode1);
    if In1Idx >= 0 then
      Pose1 := EvaluatePoseNodeRecursive(In1Idx, VisitState, NodeCachedValid, NodeCachedPoses);
  end;

  case N.Kind of
    ankSequencePlayer:
      Result := SampleProceduralClip(N.Clip, FPlayheadTimeSec * Max(0.0, N.PlayRate));

    ankBlendSpacePlayer:
      begin
        if FSpeedMps <= 0.1 then
          Result := SampleProceduralClip(ackIdleBreathe, FPlayheadTimeSec)
        else if FSpeedMps <= 3.0 then
        begin
          RunAlpha := FSpeedMps / 3.0;
          Result := TAnimPose.BlendPoses(
            SampleProceduralClip(ackIdleBreathe, FPlayheadTimeSec),
            SampleProceduralClip(ackWalkCycle, FPlayheadTimeSec), RunAlpha);
        end else
        begin
          RunAlpha := EnsureRange((FSpeedMps - 3.0) / 3.0, 0.0, 1.0);
          WalkP := SampleProceduralClip(ackWalkCycle, FPlayheadTimeSec);
          SprintP := SampleProceduralClip(ackSprintForward, FPlayheadTimeSec);
          Result := TAnimPose.BlendPoses(WalkP, SprintP, RunAlpha);
        end;
      end;

    ankStateMachine:
      begin
        if FIsInAir then
        begin
          FActiveLocomotionState := 'JumpAir';
          Result := SampleProceduralClip(ackJumpApexAir, FPlayheadTimeSec);
        end else if FSpeedMps > 0.25 then
        begin
          FActiveLocomotionState := 'Locomotion';
          RunAlpha := EnsureRange(FSpeedMps / 6.0, 0.0, 1.0);
          Result := TAnimPose.BlendPoses(
            SampleProceduralClip(ackIdleBreathe, FPlayheadTimeSec),
            SampleProceduralClip(ackSprintForward, FPlayheadTimeSec), RunAlpha);
        end else
        begin
          FActiveLocomotionState := 'Idle';
          Result := SampleProceduralClip(ackIdleBreathe, FPlayheadTimeSec);
        end;
      end;

    ankLayeredBlendPerBone:
      begin
        EffectiveWeight := EnsureRange(N.BlendWeight * FUpperBodyAimWeight, 0.0, 1.0);
        Result := TAnimPose.LayeredBlend(Pose0, Pose1, N.BodyMask, EffectiveWeight);
      end;

    ankSlotOverride:
      begin
        EffectiveWeight := EnsureRange(N.BlendWeight * FSlotMontageWeight, 0.0, 1.0);
        Result := TAnimPose.BlendPoses(Pose0, Pose1, EffectiveWeight);
      end;

    ankTwoBoneIk:
      begin
        Result := Pose0;
        EffectiveIkAlpha := EnsureRange(N.BlendWeight * FFootIkAlpha, 0.0, 1.0);
        Result.Bones[absLeftLeg].LocalOffset.Y :=
          Result.Bones[absLeftLeg].LocalOffset.Y + N.IkOffsetLeftFootY * EffectiveIkAlpha;
        Result.Bones[absRightLeg].LocalOffset.Y :=
          Result.Bones[absRightLeg].LocalOffset.Y + N.IkOffsetRightFootY * EffectiveIkAlpha;
      end;

    ankSaveCachedPose:
      Result := Pose0;

    ankUseCachedPose:
      begin
        SaveIdx := -1;
        for K := 0 to High(FNodes) do
          if (FNodes[K].Kind = ankSaveCachedPose) and
             SameText(FNodes[K].CachePoseName, N.CachePoseName) then
          begin
            SaveIdx := K;
            Break;
          end;
        if SaveIdx >= 0 then
          Result := EvaluatePoseNodeRecursive(SaveIdx, VisitState, NodeCachedValid, NodeCachedPoses);
      end;

    ankOutputPose:
      Result := Pose0;
  end;

  NodeCachedPoses[ANodeIdx] := Result;
  NodeCachedValid[ANodeIdx] := True;
  VisitState[ANodeIdx] := 2;
end;

function TCastleAnimBlueprint.StepAnimBlueprint(const ADeltaSeconds: Single): Boolean;
var
  OutIdx, I: Integer;
  OldTime, RawNewTime, WrappedTime: Single;
  VisitState: array of Byte;
  NodeCachedValid: array of Boolean;
  NodeCachedPoses: array of TAnimPose;
  ActivePrimaryClip: TAnimClipKind;
begin
  if not ValidateAnimGraph then
  begin
    FLastEvaluationValid := False;
    Exit(False);
  end;

  OldTime := FPlayheadTimeSec;
  RawNewTime := OldTime + Max(0.0, ADeltaSeconds);
  if RawNewTime >= DefaultClipDurationSec then
    WrappedTime := Frac(RawNewTime / DefaultClipDurationSec) * DefaultClipDurationSec
  else
    WrappedTime := RawNewTime;
  FPlayheadTimeSec := WrappedTime;

  { Determine active locomotion clip for AnimNotify track dispatch }
  if FIsInAir then
    ActivePrimaryClip := ackJumpApexAir
  else if FSpeedMps > 0.25 then
    ActivePrimaryClip := ackSprintForward
  else
    ActivePrimaryClip := ackIdleBreathe;

  if ADeltaSeconds > 0.0 then
  begin
    DispatchClipNotifies(ActivePrimaryClip, OldTime, WrappedTime, DefaultClipDurationSec, True);
    if FSlotMontageWeight > 0.05 then
      DispatchClipNotifies(ackMeleeSlashMontage, OldTime, WrappedTime, DefaultClipDurationSec, True);
  end;

  SetLength(VisitState, Length(FNodes));
  SetLength(NodeCachedValid, Length(FNodes));
  SetLength(NodeCachedPoses, Length(FNodes));
  for I := 0 to High(FNodes) do
  begin
    VisitState[I] := 0;
    NodeCachedValid[I] := False;
    FNodes[I].EvalCountThisTick := 0;
  end;

  OutIdx := FindOutputNodeIndex;
  FCurrentPose := EvaluatePoseNodeRecursive(OutIdx, VisitState, NodeCachedValid, NodeCachedPoses);
  FLastEvaluationValid := True;
  SyncPreviewSkeletonFromPose;
  Result := True;
end;

{ Built-In UE 5.5 Presets ---------------------------------------------------- }

procedure TCastleAnimBlueprint.ApplyPreset(const APreset: TAnimBlueprintPreset);
var
  N: TAnimGraphNode;
begin
  FPreset := APreset;
  if APreset = abpCustom then Exit;

  ClearAll;
  FPreset := APreset;

  case APreset of
    abpLocomotionUpperBodyAimAndFootIk:
      begin
        FSpeedMps := 5.5;
        FIsInAir := False;
        FUpperBodyAimWeight := 1.0;
        FSlotMontageWeight := 0.0;
        FFootIkAlpha := 1.0;

        AddOrUpdateNode(MakeDefaultNode('SM_Locomotion', ankStateMachine, 30, 55));

        N := MakeDefaultNode('Save_LocoCache', ankSaveCachedPose, 225, 55);
        N.CachePoseName := 'LocoCache';
        N.InputPoseNode0 := 'SM_Locomotion';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Use_LocoBase', ankUseCachedPose, 420, 35);
        N.CachePoseName := 'LocoCache';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Seq_AimRifle', ankSequencePlayer, 420, 145);
        N.Clip := ackUpperBodyAimRifle;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Layered_UpperAim', ankLayeredBlendPerBone, 630, 80);
        N.BodyMask := abmUpperBodyOnly;
        N.BlendWeight := 1.0;
        N.InputPoseNode0 := 'Use_LocoBase';
        N.InputPoseNode1 := 'Seq_AimRifle';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('IK_FootPlant', ankTwoBoneIk, 835, 80);
        N.BlendWeight := 1.0;
        N.IkOffsetLeftFootY := 0.06;
        N.IkOffsetRightFootY := 0.0;
        N.InputPoseNode0 := 'Layered_UpperAim';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Out_FinalPose', ankOutputPose, 1025, 80);
        N.InputPoseNode0 := 'IK_FootPlant';
        AddOrUpdateNode(N);

        AddNotifyEvent('Footstep_L', ankInstantNotify, ackSprintForward, 0.25);
        AddNotifyEvent('Footstep_R', ankInstantNotify, ackSprintForward, 0.75);
        AddNotifyEvent('WeaponHitboxActive', ankNotifyStateWindow, ackSprintForward, 0.20, 0.55);
      end;

    abpCombatSlotMontageOverride:
      begin
        FSpeedMps := 3.0;
        FSlotMontageWeight := 1.0;
        AddOrUpdateNode(MakeDefaultNode('BS_Locomotion', ankBlendSpacePlayer, 40, 60));

        N := MakeDefaultNode('Seq_SlashMontage', ankSequencePlayer, 40, 175);
        N.Clip := ackMeleeSlashMontage;
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Slot_FullBody', ankSlotOverride, 280, 110);
        N.BlendWeight := 1.0;
        N.InputPoseNode0 := 'BS_Locomotion';
        N.InputPoseNode1 := 'Seq_SlashMontage';
        AddOrUpdateNode(N);

        N := MakeDefaultNode('Out_FinalPose', ankOutputPose, 520, 110);
        N.InputPoseNode0 := 'Slot_FullBody';
        AddOrUpdateNode(N);

        AddNotifyEvent('SlashTrailWindow', ankNotifyStateWindow, ackMeleeSlashMontage, 0.15, 0.60);
      end;

    abpAirborneJumpStateCrossfade:
      begin
        FSpeedMps := 0.0;
        FIsInAir := True;
        AddOrUpdateNode(MakeDefaultNode('SM_JumpGraph', ankStateMachine, 60, 90));
        N := MakeDefaultNode('Out_FinalPose', ankOutputPose, 300, 90);
        N.InputPoseNode0 := 'SM_JumpGraph';
        AddOrUpdateNode(N);
      end;
  end;

  if not (csLoading in ComponentState) then
    StepAnimBlueprint(0.0);
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastleAnimBlueprint.GetGraphJson: String;
var
  Root, Obj: TJSONObject;
  NodesArr, NotifArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    NodesArr := TJSONArray.Create;
    for I := 0 to High(FNodes) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('id', FNodes[I].NodeId);
      Obj.Add('kind', Ord(FNodes[I].Kind));
      Obj.Add('x', FNodes[I].PosX);
      Obj.Add('y', FNodes[I].PosY);
      Obj.Add('clip', Ord(FNodes[I].Clip));
      Obj.Add('rate', FNodes[I].PlayRate);
      Obj.Add('loop', FNodes[I].Looping);
      Obj.Add('w', FNodes[I].BlendWeight);
      Obj.Add('mask', Ord(FNodes[I].BodyMask));
      Obj.Add('cache', FNodes[I].CachePoseName);
      Obj.Add('ikl', FNodes[I].IkOffsetLeftFootY);
      Obj.Add('ikr', FNodes[I].IkOffsetRightFootY);
      Obj.Add('in0', FNodes[I].InputPoseNode0);
      Obj.Add('in1', FNodes[I].InputPoseNode1);
      NodesArr.Add(Obj);
    end;
    Root.Add('nodes', NodesArr);

    NotifArr := TJSONArray.Create;
    for I := 0 to High(FNotifies) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('name', FNotifies[I].NotifyName);
      Obj.Add('kind', Ord(FNotifies[I].Kind));
      Obj.Add('clip', Ord(FNotifies[I].Clip));
      Obj.Add('t0', FNotifies[I].TriggerTimeSec);
      Obj.Add('t1', FNotifies[I].EndTimeSec);
      NotifArr.Add(Obj);
    end;
    Root.Add('notifies', NotifArr);

    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleAnimBlueprint.SetGraphJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  N: TAnimGraphNode;
begin
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    Parsed := GetJSON(AValue);
  except
    Exit;
  end;
  try
    if not (Parsed is TJSONObject) then Exit;
    Root := TJSONObject(Parsed);
    ClearAll;
    FPreset := abpCustom;

    Arr := Root.Find('nodes', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          N := MakeDefaultNode(
            Obj.Get('id', 'AnimNode_' + IntToStr(I)),
            TAnimGraphNodeKind(EnsureRange(Obj.Get('kind', 0), 0, Ord(High(TAnimGraphNodeKind)))),
            Obj.Get('x', 60.0),
            Obj.Get('y', 80.0));
          N.Clip := TAnimClipKind(EnsureRange(Obj.Get('clip', 0), 0, Ord(High(TAnimClipKind))));
          N.PlayRate := Obj.Get('rate', 1.0);
          N.Looping := Obj.Get('loop', True);
          N.BlendWeight := Obj.Get('w', 1.0);
          N.BodyMask := TAnimBodyMask(EnsureRange(Obj.Get('mask', 0), 0, Ord(High(TAnimBodyMask))));
          N.CachePoseName := Obj.Get('cache', 'LocoCache');
          N.IkOffsetLeftFootY := Obj.Get('ikl', 0.0);
          N.IkOffsetRightFootY := Obj.Get('ikr', 0.0);
          N.InputPoseNode0 := Obj.Get('in0', '');
          N.InputPoseNode1 := Obj.Get('in1', '');
          AddOrUpdateNode(N);
        end;

    Arr := Root.Find('notifies', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          AddNotifyEvent(
            Obj.Get('name', 'Notify_' + IntToStr(I)),
            TAnimNotifyKind(EnsureRange(Obj.Get('kind', 0), 0, Ord(High(TAnimNotifyKind)))),
            TAnimClipKind(EnsureRange(Obj.Get('clip', 0), 0, Ord(High(TAnimClipKind)))),
            Obj.Get('t0', 0.25),
            Obj.Get('t1', 0.50));
        end;

    if not (csLoading in ComponentState) then
      StepAnimBlueprint(0.0);
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleAnimBlueprint.AnimBlueprintSummaryBadge: String;
var
  HealthStr: String;
begin
  if FLastEvaluationValid then
    HealthStr := FActiveLocomotionState
  else
    HealthStr := Format('ERR:%d', [FValidationErrors.Count]);
  Result := Format('[AnimBP:%s Speed=%.1fm/s Nodes=%d Notifies=%d]',
    [HealthStr, FSpeedMps, Length(FNodes), Length(FNotifies)]);
end;

initialization
  RegisterSerializableComponent(TCastleAnimBlueprint, 'Animation Blueprint (AnimGraph & Notifies)');
end.
