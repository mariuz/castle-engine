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

{ 1D/2D Gradient-Band Locomotion Blend Spaces, Motion-Warped Root Motion &
  Frame-Exact Animation Montage / Notify Windows
  (@link(TCastleBlendSpace2DBehavior), @link(TCastleAnimMontageBehavior),
  @link(EvaluateGradientBandWeights2D))
  (Phase 318 — UE 6.0+ BlendSpaces, Motion Warping & Anim Montages Parity). }
unit CastleBlendMontage;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleBehaviors;

type
  TSingleWeightArray = array of Single;

  { Built-in 2D Blend Space locomotion presets. }
  TBlendSpacePreset = (
    bspCustom,
    bspEightWayLocomotion,
    bspSwordShieldStrafe,
    bspFlightHoverPitchYaw
  );

  { Single animation clip sample placed at (ParamX, ParamY) in a 2D Blend Space. }
  TBlendSampleDef = record
    SampleName: String;
    AnimationClipName: String;
    ParamX: Single; // e.g. DirectionDeg in [-180..180]
    ParamY: Single; // e.g. Speed in [0..8]
    RateScale: Single;
    ComputedWeight: Single;
  end;
  TBlendSampleDefArray = array of TBlendSampleDef;

  { Built-in layered combat / traversal Anim Montage presets. }
  TMontagePreset = (
    mpCustom,
    mpThreeHitSwordCombo,
    mpDodgeRollInvuln,
    mpVaultMantleLedge
  );

  { Named section span inside an Animation Montage. }
  TMontageSectionDef = record
    SectionName: String;
    StartTimeSec: Single;
    EndTimeSec: Single;
    NextComboSection: String; // Chained only if QueueComboInput was pressed during a ComboWindow
  end;
  TMontageSectionDefArray = array of TMontageSectionDef;

  { Instant cue or durational state/tag window along an Animation Montage timeline. }
  TAnimNotifyDef = record
    NotifyName: String;
    TriggerTimeSec: Single;
    DurationSec: Single;       // 0 = instant cue; > 0 = window [TriggerTimeSec .. TriggerTimeSec + DurationSec]
    GrantedTag: String;        // e.g. 'Montage.ComboWindow', 'Combat.HitboxActive', 'Status.Immunity.DodgeIframe'
    IsMotionWarpWindow: Boolean;
  end;
  TAnimNotifyDefArray = array of TAnimNotifyDef;

  TAnimNotifyCallback = procedure(Sender: TObject; const NotifyName, SectionName: String;
    const AtTimeSec: Single) of object;

  { 2D Freeform Cartesian Blend Space behavior evaluating Rune Johansen
    Gradient Band Interpolation (GBI) across arbitrary 2D locomotion samples
    (such as DirectionDeg x SpeedMps) with smooth exponential parameter damping. }
  TCastleBlendSpace2DBehavior = class(TCastleBehavior)
  public
    const
      DefaultRangeX = 180.0;
      DefaultRangeY = 8.0;
      DefaultDampingSpeed = 10.0;
  strict private
    FPreset: TBlendSpacePreset;
    FAxisXName: String;
    FAxisYName: String;
    FRangeX: Single;
    FRangeY: Single;
    FTargetParamX: Single;
    FTargetParamY: Single;
    FCurrentParamX: Single;
    FCurrentParamY: Single;
    FDampingSpeed: Single;
    FAutoDriveSceneAnimation: Boolean;
    FSamples: TBlendSampleDefArray;
    FDominantSampleIndex: Integer;
    FDominantAnimationName: String;
    FEffectivePlaySpeed: Single;
    FLastDrivenClip: String;

    procedure SetPreset(const Value: TBlendSpacePreset);
    procedure SetRangeX(const Value: Single);
    procedure SetRangeY(const Value: Single);
    procedure SetTargetParamX(const Value: Single);
    procedure SetTargetParamY(const Value: Single);
    procedure SetDampingSpeed(const Value: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TBlendSpacePreset): String; static;

    procedure ApplyPreset(const APreset: TBlendSpacePreset);
    procedure ClearSamples;
    procedure AddSample(const ASampleName, AClipName: String;
      const AParamX, AParamY: Single; const ARateScale: Single = 1.0);
    function SampleCount: Integer;
    function GetSample(const Index: Integer): TBlendSampleDef;

    { Immediately snap CurrentParamX/Y to TargetParamX/Y and evaluate weights. }
    procedure EvaluateImmediate(const AParamX, AParamY: Single);
    { Advance damped parameters by Dt and recompute sample weights. }
    procedure StepBlendSpace(const Dt: Single);

    function BlendSummaryBadge: String;

    property CurrentParamX: Single read FCurrentParamX;
    property CurrentParamY: Single read FCurrentParamY;
    property DominantSampleIndex: Integer read FDominantSampleIndex;
    property DominantAnimationName: String read FDominantAnimationName;
    property EffectivePlaySpeed: Single read FEffectivePlaySpeed;
  published
    property Preset: TBlendSpacePreset read FPreset write SetPreset default bspEightWayLocomotion;
    property AxisXName: String read FAxisXName write FAxisXName;
    property AxisYName: String read FAxisYName write FAxisYName;
    property RangeX: Single read FRangeX write SetRangeX {$ifdef FPC}default DefaultRangeX{$endif};
    property RangeY: Single read FRangeY write SetRangeY {$ifdef FPC}default DefaultRangeY{$endif};
    property TargetParamX: Single read FTargetParamX write SetTargetParamX {$ifdef FPC}default 0.0{$endif};
    property TargetParamY: Single read FTargetParamY write SetTargetParamY {$ifdef FPC}default 0.0{$endif};
    property DampingSpeed: Single read FDampingSpeed write SetDampingSpeed {$ifdef FPC}default DefaultDampingSpeed{$endif};
    property AutoDriveSceneAnimation: Boolean read FAutoDriveSceneAnimation write FAutoDriveSceneAnimation default false;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

  { Layered Animation Montage behavior supporting multi-section combo branching,
    frame-exact instant & window notifies, active Gameplay Tag windows, and
    Hermite root-motion target warping (@code(WarpTargetTransform)). }
  TCastleAnimMontageBehavior = class(TCastleBehavior)
  public
    const
      DefaultWarpStandoffDist = 1.20;
  strict private
    FPreset: TMontagePreset;
    FSections: TMontageSectionDefArray;
    FNotifies: TAnimNotifyDefArray;
    FFiredFlags: array of Boolean;
    FActiveTags: TStringList;

    FIsPlaying: Boolean;
    FCurrentSectionIndex: Integer;
    FCurrentTimeSec: Single;
    FPlayRate: Single;
    FComboQueued: Boolean;

    FWarpTargetTransform: TCastleTransform;
    FWarpStandoffDist: Single;
    FWarpOriginSet: Boolean;
    FWarpOriginWorldPos: TVector3;
    FWarpWindowStartSec: Single;
    FWarpWindowEndSec: Single;

    FOnNotifyTriggered: TAnimNotifyCallback;

    procedure SetPreset(const Value: TMontagePreset);
    procedure SetPlayRate(const Value: Single);
    procedure SetWarpTargetTransform(const Value: TCastleTransform);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    procedure RefreshActiveWindowTags;
    procedure ApplyMotionWarpAtCurrentTime;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TMontagePreset): String; static;

    procedure ApplyPreset(const APreset: TMontagePreset);
    procedure ClearMontage;
    procedure AddSection(const AName: String; const AStartSec, AEndSec: Single;
      const ANextComboSection: String = '');
    procedure AddNotify(const AName: String; const ATriggerSec, ADurationSec: Single;
      const AGrantedTag: String = ''; const AIsMotionWarp: Boolean = False);

    function SectionCount: Integer;
    function GetSection(const Index: Integer): TMontageSectionDef;
    function FindSectionIndex(const AName: String): Integer;
    function NotifyCount: Integer;
    function GetNotify(const Index: Integer): TAnimNotifyDef;
    function TotalDurationSec: Single;

    function PlayMontageSection(const ASectionName: String): Boolean;
    procedure StopMontage;
    { Queue next combo section if currently inside an active 'Montage.ComboWindow' window. }
    function QueueComboInput: Boolean;
    procedure SetWarpTarget(const ATarget: TCastleTransform;
      const AStandoffDist: Single = DefaultWarpStandoffDist);

    procedure StepMontage(const Dt: Single);

    function HasActiveMontageTag(const ATag: String): Boolean;
    function CurrentSectionName: String;
    function MontageSummaryBadge: String;

    property IsPlaying: Boolean read FIsPlaying;
    property CurrentTimeSec: Single read FCurrentTimeSec;
    property ComboQueued: Boolean read FComboQueued;
    property ActiveTags: TStringList read FActiveTags;
    property OnNotifyTriggered: TAnimNotifyCallback read FOnNotifyTriggered write FOnNotifyTriggered;
  published
    property Preset: TMontagePreset read FPreset write SetPreset default mpThreeHitSwordCombo;
    property PlayRate: Single read FPlayRate write SetPlayRate {$ifdef FPC}default 1.0{$endif};
    property WarpTargetTransform: TCastleTransform read FWarpTargetTransform write SetWarpTargetTransform;
    property WarpStandoffDist: Single read FWarpStandoffDist write FWarpStandoffDist {$ifdef FPC}default DefaultWarpStandoffDist{$endif};
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Evaluate normalized 2D Gradient Band Interpolation (GBI) weights across
  @code(ASamples). Guaranteed non-negative partition of unity (sum = 1.0),
  exact Kronecker delta (w_i = 1) on every sample coordinate, and collinear
  outer-ring shadowing. }
procedure EvaluateGradientBandWeights2D(
  const ASamples: TBlendSampleDefArray;
  const AParamX, AParamY, ARangeX, ARangeY: Single;
  out OutWeights: TSingleWeightArray);

implementation

uses
  Math, fpjson, jsonparser,
  CastleUtils, CastleComponentSerialize, CastleApplicationProperties,
  CastleScene;

procedure EvaluateGradientBandWeights2D(
  const ASamples: TBlendSampleDefArray;
  const AParamX, AParamY, ARangeX, ARangeY: Single;
  out OutWeights: TSingleWeightArray);
var
  N, I, J: Integer;
  InvX, InvY, TotalW, MinInfluence, BandVal, LenSqr, DotVal: Single;
  QueryPt, PiPt, PjPt, VecIToQuery, VecIToJ: TVector2;
begin
  N := Length(ASamples);
  OutWeights := nil;
  SetLength(OutWeights, N);
  if N = 0 then
    Exit;
  if N = 1 then
  begin
    OutWeights[0] := 1.0;
    Exit;
  end;

  InvX := 1.0 / Max(1e-4, Abs(ARangeX));
  InvY := 1.0 / Max(1e-4, Abs(ARangeY));
  QueryPt := Vector2(AParamX * InvX, AParamY * InvY);

  TotalW := 0.0;
  for I := 0 to N - 1 do
  begin
    PiPt := Vector2(ASamples[I].ParamX * InvX, ASamples[I].ParamY * InvY);
    VecIToQuery := QueryPt - PiPt;
    if VecIToQuery.LengthSqr < 1e-10 then
    begin
      for J := 0 to N - 1 do
        OutWeights[J] := 0.0;
      OutWeights[I] := 1.0;
      Exit;
    end;

    MinInfluence := 1.0;
    for J := 0 to N - 1 do
    begin
      if I = J then
        Continue;
      PjPt := Vector2(ASamples[J].ParamX * InvX, ASamples[J].ParamY * InvY);
      VecIToJ := PjPt - PiPt;
      LenSqr := VecIToJ.LengthSqr;
      if LenSqr < 1e-10 then
        Continue;
      DotVal := TVector2.DotProduct(VecIToQuery, VecIToJ);
      BandVal := Clamped(1.0 - (DotVal / LenSqr), 0.0, 1.0);
      if BandVal < MinInfluence then
        MinInfluence := BandVal;
      if MinInfluence <= 0.0 then
        Break;
    end;

    OutWeights[I] := MinInfluence;
    TotalW := TotalW + MinInfluence;
  end;

  if TotalW > 1e-6 then
  begin
    for I := 0 to N - 1 do
      OutWeights[I] := OutWeights[I] / TotalW;
  end else
  begin
    { Fallback to nearest sample if degenerate }
    J := 0;
    MinInfluence := MaxSingle;
    for I := 0 to N - 1 do
    begin
      PiPt := Vector2(ASamples[I].ParamX * InvX, ASamples[I].ParamY * InvY);
      LenSqr := (QueryPt - PiPt).LengthSqr;
      if LenSqr < MinInfluence then
      begin
        MinInfluence := LenSqr;
        J := I;
      end;
      OutWeights[I] := 0.0;
    end;
    OutWeights[J] := 1.0;
  end;
end;

{ TCastleBlendSpace2DBehavior ------------------------------------------------ }

constructor TCastleBlendSpace2DBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAxisXName := 'DirectionDeg';
  FAxisYName := 'SpeedMps';
  FRangeX := DefaultRangeX;
  FRangeY := DefaultRangeY;
  FDampingSpeed := DefaultDampingSpeed;
  FAutoDriveSceneAnimation := False;
  ApplyPreset(bspEightWayLocomotion);
end;

class function TCastleBlendSpace2DBehavior.PresetDisplayName(const APreset: TBlendSpacePreset): String;
begin
  case APreset of
    bspCustom:              Result := 'Custom 2D Space';
    bspEightWayLocomotion:  Result := '8-Way Locomotion (Dir x Speed)';
    bspSwordShieldStrafe:   Result := 'Sword & Shield Combat Strafe';
    bspFlightHoverPitchYaw: Result := 'Aerial Hover / Pitch-Yaw';
  end;
end;

procedure TCastleBlendSpace2DBehavior.ClearSamples;
begin
  FSamples := nil;
  FDominantSampleIndex := -1;
  FDominantAnimationName := '';
  FEffectivePlaySpeed := 1.0;
end;

procedure TCastleBlendSpace2DBehavior.AddSample(
  const ASampleName, AClipName: String;
  const AParamX, AParamY: Single; const ARateScale: Single);
var
  N: Integer;
begin
  N := Length(FSamples);
  SetLength(FSamples, N + 1);
  FSamples[N].SampleName := ASampleName;
  FSamples[N].AnimationClipName := AClipName;
  FSamples[N].ParamX := AParamX;
  FSamples[N].ParamY := AParamY;
  FSamples[N].RateScale := Max(0.05, ARateScale);
  FSamples[N].ComputedWeight := 0.0;
  EvaluateImmediate(FCurrentParamX, FCurrentParamY);
end;

procedure TCastleBlendSpace2DBehavior.ApplyPreset(const APreset: TBlendSpacePreset);
begin
  FPreset := APreset;
  case APreset of
    bspEightWayLocomotion:
      begin
        ClearSamples;
        FAxisXName := 'DirectionDeg';
        FAxisYName := 'SpeedMps';
        FRangeX := 180.0;
        FRangeY := 8.0;
        AddSample('Idle', 'idle', 0.0, 0.0, 1.0);
        AddSample('WalkForward', 'walk_fwd', 0.0, 2.2, 1.0);
        AddSample('RunForward', 'run_fwd', 0.0, 5.5, 1.15);
        AddSample('SprintForward', 'sprint_fwd', 0.0, 8.0, 1.35);
        AddSample('StrafeLeft', 'strafe_left', -90.0, 2.8, 1.0);
        AddSample('StrafeRight', 'strafe_right', 90.0, 2.8, 1.0);
        AddSample('WalkBackwardL', 'walk_back', -180.0, 2.0, 0.95);
        AddSample('WalkBackwardR', 'walk_back', 180.0, 2.0, 0.95);
        EvaluateImmediate(0.0, 0.0);
      end;
    bspSwordShieldStrafe:
      begin
        ClearSamples;
        FAxisXName := 'StrafeDirDeg';
        FAxisYName := 'GuardSpeed';
        FRangeX := 180.0;
        FRangeY := 4.5;
        AddSample('GuardIdle', 'shield_idle', 0.0, 0.0, 1.0);
        AddSample('AdvanceGuard', 'shield_walk_fwd', 0.0, 2.0, 1.0);
        AddSample('ChargeDash', 'shield_charge', 0.0, 4.5, 1.25);
        AddSample('CircleLeft', 'shield_circle_l', -90.0, 1.8, 1.0);
        AddSample('CircleRight', 'shield_circle_r', 90.0, 1.8, 1.0);
        AddSample('RetreatGuard', 'shield_retreat', 180.0, 1.6, 0.9);
        EvaluateImmediate(0.0, 0.0);
      end;
    bspFlightHoverPitchYaw:
      begin
        ClearSamples;
        FAxisXName := 'BankYawDeg';
        FAxisYName := 'ClimbPitchDeg';
        FRangeX := 90.0;
        FRangeY := 60.0;
        AddSample('HoverLevel', 'fly_hover', 0.0, 0.0, 1.0);
        AddSample('ClimbSteep', 'fly_climb', 0.0, 60.0, 1.1);
        AddSample('DiveFast', 'fly_dive', 0.0, -60.0, 1.3);
        AddSample('BankLeft', 'fly_bank_l', -90.0, 0.0, 1.05);
        AddSample('BankRight', 'fly_bank_r', 90.0, 0.0, 1.05);
        EvaluateImmediate(0.0, 0.0);
      end;
    bspCustom: ;
  end;
end;

function TCastleBlendSpace2DBehavior.SampleCount: Integer;
begin
  Result := Length(FSamples);
end;

function TCastleBlendSpace2DBehavior.GetSample(const Index: Integer): TBlendSampleDef;
begin
  Result := FSamples[Clamped(Index, 0, Max(0, High(FSamples)))];
end;

procedure TCastleBlendSpace2DBehavior.EvaluateImmediate(const AParamX, AParamY: Single);
var
  Weights: TSingleWeightArray;
  I, BestIdx: Integer;
  BestW, RateAccum: Single;
begin
  FCurrentParamX := AParamX;
  FCurrentParamY := AParamY;
  FTargetParamX := AParamX;
  FTargetParamY := AParamY;

  EvaluateGradientBandWeights2D(FSamples, FCurrentParamX, FCurrentParamY,
    FRangeX, FRangeY, Weights);

  BestIdx := -1;
  BestW := -1.0;
  RateAccum := 0.0;
  for I := 0 to High(FSamples) do
  begin
    FSamples[I].ComputedWeight := Weights[I];
    RateAccum := RateAccum + Weights[I] * FSamples[I].RateScale;
    if Weights[I] > BestW then
    begin
      BestW := Weights[I];
      BestIdx := I;
    end;
  end;

  FDominantSampleIndex := BestIdx;
  if BestIdx >= 0 then
    FDominantAnimationName := FSamples[BestIdx].AnimationClipName
  else
    FDominantAnimationName := '';
  if RateAccum > 0.01 then
    FEffectivePlaySpeed := RateAccum
  else
    FEffectivePlaySpeed := 1.0;
end;

procedure TCastleBlendSpace2DBehavior.StepBlendSpace(const Dt: Single);
var
  Alpha, SavedTargetX, SavedTargetY: Single;
  SceneChild: TCastleScene;
  I: Integer;
begin
  if Dt <= 0.0 then
    Exit;
  SavedTargetX := FTargetParamX;
  SavedTargetY := FTargetParamY;
  if FDampingSpeed <= 0.01 then
    Alpha := 1.0
  else
    Alpha := 1.0 - Exp(-FDampingSpeed * Dt);

  EvaluateImmediate(
    Lerp(Alpha, FCurrentParamX, SavedTargetX),
    Lerp(Alpha, FCurrentParamY, SavedTargetY));
  FTargetParamX := SavedTargetX;
  FTargetParamY := SavedTargetY;

  if FAutoDriveSceneAnimation and (Parent <> nil) and (FDominantAnimationName <> '') then
  begin
    SceneChild := nil;
    if Parent is TCastleScene then
      SceneChild := TCastleScene(Parent)
    else
      for I := 0 to Parent.Count - 1 do
        if Parent[I] is TCastleScene then
        begin
          SceneChild := TCastleScene(Parent[I]);
          Break;
        end;
    if (SceneChild <> nil) and (FLastDrivenClip <> FDominantAnimationName) and
       (SceneChild.AnimationsList.IndexOf(FDominantAnimationName) >= 0) then
    begin
      FLastDrivenClip := FDominantAnimationName;
      SceneChild.PlayAnimation(FDominantAnimationName, True);
    end;
  end;
end;

procedure TCastleBlendSpace2DBehavior.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleApplicationMode = appRunning then
    StepBlendSpace(SecondsPassed);
end;

function TCastleBlendSpace2DBehavior.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'RangeX') or
     (PropertyName = 'RangeY') or
     (PropertyName = 'TargetParamX') or
     (PropertyName = 'TargetParamY') or
     (PropertyName = 'DampingSpeed') or
     (PropertyName = 'AutoDriveSceneAnimation') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleBlendSpace2DBehavior.BlendSummaryBadge: String;
begin
  Result := Format('[Blend2D:%s (%.0f, %.1f) -> %s %.2fx]', [
    PresetDisplayName(FPreset),
    FCurrentParamX, FCurrentParamY,
    FDominantAnimationName, FEffectivePlaySpeed]);
end;

procedure TCastleBlendSpace2DBehavior.SetPreset(const Value: TBlendSpacePreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

procedure TCastleBlendSpace2DBehavior.SetRangeX(const Value: Single);
begin
  FRangeX := Max(1.0, Value);
end;

procedure TCastleBlendSpace2DBehavior.SetRangeY(const Value: Single);
begin
  FRangeY := Max(0.1, Value);
end;

procedure TCastleBlendSpace2DBehavior.SetTargetParamX(const Value: Single);
begin
  FTargetParamX := Clamped(Value, -FRangeX, FRangeX);
end;

procedure TCastleBlendSpace2DBehavior.SetTargetParamY(const Value: Single);
begin
  FTargetParamY := Clamped(Value, -FRangeY, FRangeY);
end;

procedure TCastleBlendSpace2DBehavior.SetDampingSpeed(const Value: Single);
begin
  FDampingSpeed := Max(0.0, Value);
end;

function TCastleBlendSpace2DBehavior.GetConfigJson: String;
var
  Root, SObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('axisX', FAxisXName);
    Root.Add('axisY', FAxisYName);
    Root.Add('rangeX', FRangeX);
    Root.Add('rangeY', FRangeY);
    Arr := TJSONArray.Create;
    for I := 0 to High(FSamples) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('name', FSamples[I].SampleName);
      SObj.Add('clip', FSamples[I].AnimationClipName);
      SObj.Add('x', FSamples[I].ParamX);
      SObj.Add('y', FSamples[I].ParamY);
      SObj.Add('rate', FSamples[I].RateScale);
      Arr.Add(SObj);
    end;
    Root.Add('samples', Arr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleBlendSpace2DBehavior.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, SObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FPreset := TBlendSpacePreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TBlendSpacePreset))));
      FAxisXName := Root.Get('axisX', FAxisXName);
      FAxisYName := Root.Get('axisY', FAxisYName);
      FRangeX := Max(1.0, Root.Get('rangeX', FRangeX));
      FRangeY := Max(0.1, Root.Get('rangeY', FRangeY));
      Arr := Root.Find('samples', jtArray) as TJSONArray;
      if Arr <> nil then
      begin
        ClearSamples;
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            SObj := TJSONObject(Arr.Items[I]);
            AddSample(
              SObj.Get('name', 'Sample' + IntToStr(I)),
              SObj.Get('clip', 'idle'),
              SObj.Get('x', 0.0),
              SObj.Get('y', 0.0),
              SObj.Get('rate', 1.0));
          end;
      end;
      EvaluateImmediate(FCurrentParamX, FCurrentParamY);
    end;
  finally
    FreeAndNil(Data);
  end;
end;

{ TCastleAnimMontageBehavior ------------------------------------------------- }

constructor TCastleAnimMontageBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActiveTags := TStringList.Create;
  FActiveTags.CaseSensitive := False;
  FPlayRate := 1.0;
  FWarpStandoffDist := DefaultWarpStandoffDist;
  FCurrentSectionIndex := -1;
  ApplyPreset(mpThreeHitSwordCombo);
end;

destructor TCastleAnimMontageBehavior.Destroy;
begin
  SetWarpTargetTransform(nil);
  FreeAndNil(FActiveTags);
  inherited;
end;

procedure TCastleAnimMontageBehavior.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FWarpTargetTransform) then
    FWarpTargetTransform := nil;
end;

class function TCastleAnimMontageBehavior.PresetDisplayName(const APreset: TMontagePreset): String;
begin
  case APreset of
    mpCustom:             Result := 'Custom Montage';
    mpThreeHitSwordCombo: Result := '3-Hit Sword Combo + Lunge Warp';
    mpDodgeRollInvuln:    Result := 'Dodge Roll (i-Frame Window)';
    mpVaultMantleLedge:   Result := 'Parkour Vault / Mantle';
  end;
end;

procedure TCastleAnimMontageBehavior.ClearMontage;
begin
  StopMontage;
  FSections := nil;
  FNotifies := nil;
  FFiredFlags := nil;
end;

procedure TCastleAnimMontageBehavior.AddSection(const AName: String;
  const AStartSec, AEndSec: Single; const ANextComboSection: String);
var
  N: Integer;
begin
  N := Length(FSections);
  SetLength(FSections, N + 1);
  FSections[N].SectionName := AName;
  FSections[N].StartTimeSec := Max(0.0, AStartSec);
  FSections[N].EndTimeSec := Max(FSections[N].StartTimeSec + 0.05, AEndSec);
  FSections[N].NextComboSection := ANextComboSection;
end;

procedure TCastleAnimMontageBehavior.AddNotify(const AName: String;
  const ATriggerSec, ADurationSec: Single;
  const AGrantedTag: String; const AIsMotionWarp: Boolean);
var
  N: Integer;
begin
  N := Length(FNotifies);
  SetLength(FNotifies, N + 1);
  SetLength(FFiredFlags, N + 1);
  FNotifies[N].NotifyName := AName;
  FNotifies[N].TriggerTimeSec := Max(0.0, ATriggerSec);
  FNotifies[N].DurationSec := Max(0.0, ADurationSec);
  FNotifies[N].GrantedTag := AGrantedTag;
  FNotifies[N].IsMotionWarpWindow := AIsMotionWarp;
  FFiredFlags[N] := False;
end;

procedure TCastleAnimMontageBehavior.ApplyPreset(const APreset: TMontagePreset);
begin
  FPreset := APreset;
  case APreset of
    mpThreeHitSwordCombo:
      begin
        ClearMontage;
        AddSection('Slash1', 0.00, 0.55, 'Slash2');
        AddSection('Slash2', 0.55, 1.15, 'HeavyFinisher');
        AddSection('HeavyFinisher', 1.15, 1.90, '');

        AddNotify('LungeMotionWarp', 0.05, 0.30, 'Montage.MotionWarp', True);
        AddNotify('Cue.SwordWhoosh1', 0.16, 0.0, '', False);
        AddNotify('HitboxSlash1', 0.18, 0.14, 'Combat.HitboxActive', False);
        AddNotify('ComboWindow1', 0.30, 0.24, 'Montage.ComboWindow', False);

        AddNotify('Cue.SwordWhoosh2', 0.72, 0.0, '', False);
        AddNotify('HitboxSlash2', 0.74, 0.16, 'Combat.HitboxActive', False);
        AddNotify('ComboWindow2', 0.90, 0.23, 'Montage.ComboWindow', False);

        AddNotify('Cue.HeavySlamImpact', 1.48, 0.0, '', False);
        AddNotify('HitboxFinisher', 1.42, 0.22, 'Combat.HitboxActive', False);
      end;
    mpDodgeRollInvuln:
      begin
        ClearMontage;
        AddSection('DodgeRoll', 0.00, 0.65, '');
        AddNotify('Cue.DodgeDash', 0.02, 0.0, '', False);
        AddNotify('IframeInvulnWindow', 0.06, 0.36, 'Status.Immunity.DodgeIframe', False);
        AddNotify('RecoveryFootstep', 0.56, 0.0, '', False);
      end;
    mpVaultMantleLedge:
      begin
        ClearMontage;
        AddSection('VaultApproach', 0.00, 0.45, '');
        AddNotify('MantleMotionWarp', 0.04, 0.36, 'Montage.MotionWarp', True);
        AddNotify('Cue.HandPlant', 0.20, 0.0, '', False);
      end;
    mpCustom: ;
  end;
end;

function TCastleAnimMontageBehavior.SectionCount: Integer;
begin
  Result := Length(FSections);
end;

function TCastleAnimMontageBehavior.GetSection(const Index: Integer): TMontageSectionDef;
begin
  Result := FSections[Clamped(Index, 0, Max(0, High(FSections)))];
end;

function TCastleAnimMontageBehavior.FindSectionIndex(const AName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSections) do
    if SameText(FSections[I].SectionName, AName) then
      Exit(I);
  Result := -1;
end;

function TCastleAnimMontageBehavior.NotifyCount: Integer;
begin
  Result := Length(FNotifies);
end;

function TCastleAnimMontageBehavior.GetNotify(const Index: Integer): TAnimNotifyDef;
begin
  Result := FNotifies[Clamped(Index, 0, Max(0, High(FNotifies)))];
end;

function TCastleAnimMontageBehavior.TotalDurationSec: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FSections) do
    Result := Max(Result, FSections[I].EndTimeSec);
end;

function TCastleAnimMontageBehavior.PlayMontageSection(const ASectionName: String): Boolean;
var
  Idx, I: Integer;
begin
  Idx := FindSectionIndex(ASectionName);
  if Idx < 0 then
    Exit(False);

  FCurrentSectionIndex := Idx;
  FCurrentTimeSec := FSections[Idx].StartTimeSec;
  FIsPlaying := True;
  FComboQueued := False;
  FWarpOriginSet := False;

  for I := 0 to High(FFiredFlags) do
    FFiredFlags[I] := FNotifies[I].TriggerTimeSec < FCurrentTimeSec - 1e-5;

  RefreshActiveWindowTags;
  Result := True;
end;

procedure TCastleAnimMontageBehavior.StopMontage;
begin
  FIsPlaying := False;
  FCurrentSectionIndex := -1;
  FComboQueued := False;
  FWarpOriginSet := False;
  if FActiveTags <> nil then
    FActiveTags.Clear;
end;

function TCastleAnimMontageBehavior.QueueComboInput: Boolean;
begin
  if FIsPlaying and HasActiveMontageTag('Montage.ComboWindow') and
     (FCurrentSectionIndex >= 0) and (FCurrentSectionIndex <= High(FSections)) and
     (FSections[FCurrentSectionIndex].NextComboSection <> '') then
  begin
    FComboQueued := True;
    Exit(True);
  end;
  Result := False;
end;

procedure TCastleAnimMontageBehavior.SetWarpTarget(
  const ATarget: TCastleTransform; const AStandoffDist: Single);
begin
  SetWarpTargetTransform(ATarget);
  FWarpStandoffDist := Max(0.0, AStandoffDist);
end;

procedure TCastleAnimMontageBehavior.RefreshActiveWindowTags;
var
  I: Integer;
begin
  FActiveTags.Clear;
  if not FIsPlaying then
    Exit;
  for I := 0 to High(FNotifies) do
    if (FNotifies[I].DurationSec > 0.0) and (FNotifies[I].GrantedTag <> '') and
       (FCurrentTimeSec >= FNotifies[I].TriggerTimeSec - 1e-5) and
       (FCurrentTimeSec <= FNotifies[I].TriggerTimeSec + FNotifies[I].DurationSec + 1e-5) then
    begin
      if FActiveTags.IndexOf(FNotifies[I].GrantedTag) < 0 then
        FActiveTags.Add(FNotifies[I].GrantedTag);
    end;
end;

procedure TCastleAnimMontageBehavior.ApplyMotionWarpAtCurrentTime;
var
  I: Integer;
  WarpN: TAnimNotifyDef;
  FoundWarp: Boolean;
  TargetPos, ToTargetFlat, DesiredEndPos: TVector3;
  DistFlat, TNorm, SmoothT, YawRad: Single;
begin
  if (Parent = nil) or (FWarpTargetTransform = nil) then
    Exit;

  FoundWarp := False;
  for I := 0 to High(FNotifies) do
    if FNotifies[I].IsMotionWarpWindow and (FNotifies[I].DurationSec > 1e-4) and
       (FCurrentTimeSec >= FNotifies[I].TriggerTimeSec - 1e-5) then
    begin
      WarpN := FNotifies[I];
      FoundWarp := True;
      Break;
    end;

  if not FoundWarp then
    Exit;

  if not FWarpOriginSet then
  begin
    FWarpOriginSet := True;
    FWarpOriginWorldPos := Parent.Translation;
    FWarpWindowStartSec := WarpN.TriggerTimeSec;
    FWarpWindowEndSec := WarpN.TriggerTimeSec + WarpN.DurationSec;
  end;

  if FCurrentTimeSec > FWarpWindowEndSec + 0.05 then
    Exit;

  TargetPos := FWarpTargetTransform.Translation;
  ToTargetFlat := Vector3(TargetPos.X - FWarpOriginWorldPos.X, 0.0,
    TargetPos.Z - FWarpOriginWorldPos.Z);
  DistFlat := ToTargetFlat.Length;
  if DistFlat > 1e-4 then
  begin
    ToTargetFlat := ToTargetFlat / DistFlat;
    DesiredEndPos := Vector3(
      TargetPos.X - ToTargetFlat.X * FWarpStandoffDist,
      FWarpOriginWorldPos.Y,
      TargetPos.Z - ToTargetFlat.Z * FWarpStandoffDist);
    YawRad := ArcTan2(-ToTargetFlat.X, -ToTargetFlat.Z);
    Parent.Rotation := Vector4(0.0, 1.0, 0.0, YawRad);
  end else
    DesiredEndPos := FWarpOriginWorldPos;

  TNorm := Clamped(
    (FCurrentTimeSec - FWarpWindowStartSec) /
    Max(1e-4, FWarpWindowEndSec - FWarpWindowStartSec), 0.0, 1.0);
  SmoothT := TNorm * TNorm * (3.0 - 2.0 * TNorm);
  Parent.Translation := Lerp(SmoothT, FWarpOriginWorldPos, DesiredEndPos);
end;

procedure TCastleAnimMontageBehavior.StepMontage(const Dt: Single);
var
  PrevTime, NextTime, SecEnd: Single;
  I, NextIdx: Integer;
  SecName: String;
begin
  if (not FIsPlaying) or (Dt <= 0.0) or
     (FCurrentSectionIndex < 0) or (FCurrentSectionIndex > High(FSections)) then
    Exit;

  PrevTime := FCurrentTimeSec;
  NextTime := PrevTime + Dt * FPlayRate;
  SecEnd := FSections[FCurrentSectionIndex].EndTimeSec;
  SecName := FSections[FCurrentSectionIndex].SectionName;

  { Fire any instant/window notifies crossed up to min(NextTime, SecEnd) }
  for I := 0 to High(FNotifies) do
    if (not FFiredFlags[I]) and
       (FNotifies[I].TriggerTimeSec >= PrevTime - 1e-5) and
       (FNotifies[I].TriggerTimeSec <= Min(NextTime, SecEnd) + 1e-5) then
    begin
      FFiredFlags[I] := True;
      if Assigned(FOnNotifyTriggered) then
        FOnNotifyTriggered(Self, FNotifies[I].NotifyName, SecName, FNotifies[I].TriggerTimeSec);
    end;

  if NextTime >= SecEnd then
  begin
    FCurrentTimeSec := SecEnd;
    ApplyMotionWarpAtCurrentTime;

    if FComboQueued and (FSections[FCurrentSectionIndex].NextComboSection <> '') then
    begin
      NextIdx := FindSectionIndex(FSections[FCurrentSectionIndex].NextComboSection);
      if NextIdx >= 0 then
      begin
        FCurrentSectionIndex := NextIdx;
        FComboQueued := False;
        FWarpOriginSet := False;
        FCurrentTimeSec := FSections[NextIdx].StartTimeSec;
        for I := 0 to High(FFiredFlags) do
          FFiredFlags[I] := FNotifies[I].TriggerTimeSec < FCurrentTimeSec - 1e-5;
        RefreshActiveWindowTags;
        if NextTime > SecEnd + 1e-6 then
          StepMontage((NextTime - SecEnd) / Max(0.05, FPlayRate));
        Exit;
      end;
    end;

    StopMontage;
    Exit;
  end;

  FCurrentTimeSec := NextTime;
  RefreshActiveWindowTags;
  ApplyMotionWarpAtCurrentTime;
end;

procedure TCastleAnimMontageBehavior.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleApplicationMode = appRunning then
    StepMontage(SecondsPassed);
end;

function TCastleAnimMontageBehavior.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'PlayRate') or
     (PropertyName = 'WarpTargetTransform') or
     (PropertyName = 'WarpStandoffDist') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleAnimMontageBehavior.HasActiveMontageTag(const ATag: String): Boolean;
begin
  Result := FIsPlaying and (FActiveTags <> nil) and (FActiveTags.IndexOf(ATag) >= 0);
end;

function TCastleAnimMontageBehavior.CurrentSectionName: String;
begin
  if FIsPlaying and (FCurrentSectionIndex >= 0) and (FCurrentSectionIndex <= High(FSections)) then
    Result := FSections[FCurrentSectionIndex].SectionName
  else
    Result := 'Idle';
end;

function TCastleAnimMontageBehavior.MontageSummaryBadge: String;
begin
  if FIsPlaying then
    Result := Format('[Montage:%s %.2fs/%d tags]', [
      CurrentSectionName, FCurrentTimeSec, FActiveTags.Count])
  else
    Result := Format('[Montage:%s %d secs %d notifies]', [
      PresetDisplayName(FPreset), Length(FSections), Length(FNotifies)]);
end;

procedure TCastleAnimMontageBehavior.SetPreset(const Value: TMontagePreset);
begin
  if FPreset <> Value then
    ApplyPreset(Value);
end;

procedure TCastleAnimMontageBehavior.SetPlayRate(const Value: Single);
begin
  FPlayRate := Clamped(Value, 0.05, 5.0);
end;

procedure TCastleAnimMontageBehavior.SetWarpTargetTransform(const Value: TCastleTransform);
begin
  if FWarpTargetTransform <> Value then
  begin
    if FWarpTargetTransform <> nil then
      FWarpTargetTransform.RemoveFreeNotification(Self);
    FWarpTargetTransform := Value;
    if FWarpTargetTransform <> nil then
      FWarpTargetTransform.FreeNotification(Self);
  end;
end;

function TCastleAnimMontageBehavior.GetConfigJson: String;
var
  Root, Obj: TJSONObject;
  SecArr, NotArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    Root.Add('playRate', FPlayRate);
    Root.Add('warpStandoff', FWarpStandoffDist);
    SecArr := TJSONArray.Create;
    for I := 0 to High(FSections) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('name', FSections[I].SectionName);
      Obj.Add('start', FSections[I].StartTimeSec);
      Obj.Add('end', FSections[I].EndTimeSec);
      Obj.Add('next', FSections[I].NextComboSection);
      SecArr.Add(Obj);
    end;
    Root.Add('sections', SecArr);

    NotArr := TJSONArray.Create;
    for I := 0 to High(FNotifies) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('name', FNotifies[I].NotifyName);
      Obj.Add('t', FNotifies[I].TriggerTimeSec);
      Obj.Add('dur', FNotifies[I].DurationSec);
      Obj.Add('tag', FNotifies[I].GrantedTag);
      Obj.Add('warp', FNotifies[I].IsMotionWarpWindow);
      NotArr.Add(Obj);
    end;
    Root.Add('notifies', NotArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleAnimMontageBehavior.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, Obj: TJSONObject;
  SecArr, NotArr: TJSONArray;
  I: Integer;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      FPreset := TMontagePreset(Clamped(Root.Get('preset', Ord(FPreset)),
        0, Ord(High(TMontagePreset))));
      FPlayRate := Clamped(Root.Get('playRate', FPlayRate), 0.05, 5.0);
      FWarpStandoffDist := Max(0.0, Root.Get('warpStandoff', FWarpStandoffDist));
      SecArr := Root.Find('sections', jtArray) as TJSONArray;
      NotArr := Root.Find('notifies', jtArray) as TJSONArray;
      if (SecArr <> nil) or (NotArr <> nil) then
      begin
        ClearMontage;
        if SecArr <> nil then
          for I := 0 to SecArr.Count - 1 do
            if SecArr.Items[I] is TJSONObject then
            begin
              Obj := TJSONObject(SecArr.Items[I]);
              AddSection(Obj.Get('name', 'Sec' + IntToStr(I)),
                Obj.Get('start', 0.0), Obj.Get('end', 0.5), Obj.Get('next', ''));
            end;
        if NotArr <> nil then
          for I := 0 to NotArr.Count - 1 do
            if NotArr.Items[I] is TJSONObject then
            begin
              Obj := TJSONObject(NotArr.Items[I]);
              AddNotify(Obj.Get('name', 'Notify' + IntToStr(I)),
                Obj.Get('t', 0.1), Obj.Get('dur', 0.0),
                Obj.Get('tag', ''), Obj.Get('warp', False));
            end;
      end;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleBlendSpace2DBehavior,
    ['Animation & Cinematics', '2D Locomotion Blend Space (Gradient Band)']);
  RegisterSerializableComponent(TCastleAnimMontageBehavior,
    ['Animation & Cinematics', 'Anim Montage, Combo & Motion Warp']);
end.
