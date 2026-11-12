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

{ Virtual Camera Priority Blending, Spline Dolly Rail, Screen-Space Deadzone
  Aim Composer & Trauma-Squared Perlin Shake (@link(TCastleVirtualCamera),
  @link(TCastleVirtualCameraBrain))
  (Phase 312 — UE 6.0+ Gameplay Cameras & Cinemachine Parity). }
unit CastleVirtualCamera;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleBehaviors,
  CastleSplinePath;

type
  { Camera body placement algorithm for @link(TCastleVirtualCamera). }
  TVirtualCameraBodyMode = (
    vcbFixedTransform,
    vcbThirdPersonFollow,
    vcbSplineDollyRail
  );

  { Camera orientation / framing composer for @link(TCastleVirtualCamera). }
  TVirtualCameraAimMode = (
    vcaFixedDirection,
    vcaHardLookAt,
    vcaDeadzoneComposer
  );

  { Transition curve used by @link(TCastleVirtualCameraBrain) when switching rigs. }
  TVirtualCameraBlendCurve = (
    vcbcHardCut,
    vcbcLinear,
    vcbcSmoothStep,
    vcbcEaseInOutCubic
  );

  { Evaluated world-space camera pose + lens state. }
  TVirtualCameraPose = record
    Position: TVector3;
    Direction: TVector3;
    Up: TVector3;
    FieldOfViewDeg: Single;
  end;

  { Composable Virtual Camera rig (@link(TCastleTransform)).
    Multiple @link(TCastleVirtualCamera) rigs can coexist in a scene; the
    highest-@link(Priority) active rig is smoothly blended onto the live
    @link(TCastleCamera) by @link(TCastleVirtualCameraBrain). }
  TCastleVirtualCamera = class(TCastleTransform)
  public
    const
      DefaultPriority = 10;
      DefaultFieldOfViewDeg = 55.0;
      DefaultFollowDamping = 8.0;
      DefaultAimDamping = 10.0;
      DefaultDeadzoneWidthDeg = 12.0;
      DefaultDeadzoneHeightDeg = 8.0;
  strict private
    FActiveRig: Boolean;
    FPriority: Integer;
    FBodyMode: TVirtualCameraBodyMode;
    FAimMode: TVirtualCameraAimMode;
    FFieldOfViewDeg: Single;
    FDutchRollDeg: Single;

    FFollowTarget: TCastleTransform;
    FFollowOffset: TVector3;
    FFollowOffsetPersistent: TCastleVector3Persistent;
    FFollowDamping: Single;

    FDollySpline: TCastleSplinePath;
    FDollyNormalizedT: Single;
    FAutoDollyToFollowTarget: Boolean;

    FLookAtTarget: TCastleTransform;
    FAimTargetOffset: TVector3;
    FAimTargetOffsetPersistent: TCastleVector3Persistent;
    FAimDamping: Single;
    FDeadzoneWidthDeg: Single;
    FDeadzoneHeightDeg: Single;

    FHasState: Boolean;
    FCurWorldPos: TVector3;
    FCurWorldDir: TVector3;
    FCurWorldUp: TVector3;

    procedure SetFollowTarget(const Value: TCastleTransform);
    procedure SetLookAtTarget(const Value: TCastleTransform);
    procedure SetDollySpline(const Value: TCastleSplinePath);
    procedure SetFieldOfViewDeg(const Value: Single);
    procedure SetDollyNormalizedT(const Value: Single);
    function GetFollowOffsetForPersistent: TVector3;
    procedure SetFollowOffsetForPersistent(const AValue: TVector3);
    function GetAimTargetOffsetForPersistent: TVector3;
    procedure SetAimTargetOffsetForPersistent(const AValue: TVector3);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Reset internal damped follow/aim state to immediate target values. }
    procedure SnapStateImmediate;

    { Step body follow/dolly and aim composer by @code(Dt) and return world pose. }
    function StepAndEvaluatePose(const Dt: Single): TVirtualCameraPose;

    function VCamSummaryBadge: String;

    property FollowOffset: TVector3 read FFollowOffset write FFollowOffset;
    property AimTargetOffset: TVector3 read FAimTargetOffset write FAimTargetOffset;
  published
    property ActiveRig: Boolean read FActiveRig write FActiveRig default True;
    property Priority: Integer read FPriority write FPriority default DefaultPriority;
    property BodyMode: TVirtualCameraBodyMode
      read FBodyMode write FBodyMode default vcbFixedTransform;
    property AimMode: TVirtualCameraAimMode
      read FAimMode write FAimMode default vcaFixedDirection;
    property FieldOfViewDeg: Single
      read FFieldOfViewDeg write SetFieldOfViewDeg {$ifdef FPC}default DefaultFieldOfViewDeg{$endif};
    property DutchRollDeg: Single
      read FDutchRollDeg write FDutchRollDeg {$ifdef FPC}default 0.0{$endif};

    property FollowTarget: TCastleTransform read FFollowTarget write SetFollowTarget;
    property FollowOffsetPersistent: TCastleVector3Persistent read FFollowOffsetPersistent;
    property FollowDamping: Single
      read FFollowDamping write FFollowDamping {$ifdef FPC}default DefaultFollowDamping{$endif};

    property DollySpline: TCastleSplinePath read FDollySpline write SetDollySpline;
    property DollyNormalizedT: Single
      read FDollyNormalizedT write SetDollyNormalizedT {$ifdef FPC}default 0.0{$endif};
    property AutoDollyToFollowTarget: Boolean
      read FAutoDollyToFollowTarget write FAutoDollyToFollowTarget default False;

    property LookAtTarget: TCastleTransform read FLookAtTarget write SetLookAtTarget;
    property AimTargetOffsetPersistent: TCastleVector3Persistent read FAimTargetOffsetPersistent;
    property AimDamping: Single
      read FAimDamping write FAimDamping {$ifdef FPC}default DefaultAimDamping{$endif};
    property DeadzoneWidthDeg: Single
      read FDeadzoneWidthDeg write FDeadzoneWidthDeg {$ifdef FPC}default DefaultDeadzoneWidthDeg{$endif};
    property DeadzoneHeightDeg: Single
      read FDeadzoneHeightDeg write FDeadzoneHeightDeg {$ifdef FPC}default DefaultDeadzoneHeightDeg{$endif};
  end;

  { Director behavior (@link(TCastleBehavior)) that arbitrates all active
    @link(TCastleVirtualCamera) rigs by @code(Priority), performs cut or
    smooth curve blends across rigs, layers trauma-squared Perlin 3D shake,
    and drives the output @link(TCastleCamera). }
  TCastleVirtualCameraBrain = class(TCastleBehavior)
  public
    const
      DefaultBlendDurationSec = 1.0;
      DefaultTraumaDecayPerSec = 0.85;
      DefaultShakeFrequencyHz = 14.0;
      DefaultShakeMaxAngleDeg = 6.0;
      DefaultShakeMaxOffsetMeters = 0.22;
  strict private
    FTargetCamera: TCastleCamera;
    FBlendCurve: TVirtualCameraBlendCurve;
    FBlendDurationSec: Single;
    FTrauma: Single;
    FTraumaDecayPerSec: Single;
    FShakeFrequencyHz: Single;
    FShakeMaxAngleDeg: Single;
    FShakeMaxOffsetMeters: Single;
    FSimulateInEditor: Boolean;

    FActiveVCam: TCastleVirtualCamera;
    FIsBlending: Boolean;
    FBlendElapsedSec: Single;
    FBlendStartPose: TVirtualCameraPose;
    FLastOutputPose: TVirtualCameraPose;
    FHasLastPose: Boolean;
    FNoiseTime: Single;

    procedure SetTargetCamera(const Value: TCastleCamera);
    procedure SetTrauma(const Value: Single);
    function ResolveDrivenCamera: TCastleCamera;
    function SelectWinningVCam: TCastleVirtualCamera;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Add normalized camera shake trauma in [0..1]; shake amplitude scales with Trauma^2. }
    procedure AddTrauma(const AAmount: Single);

    { Deterministic step of rig arbitration, blend transition, Perlin trauma shake & camera sync. }
    procedure StepBrain(const Dt: Single);

    property ActiveVirtualCamera: TCastleVirtualCamera read FActiveVCam;
    property IsBlending: Boolean read FIsBlending;
    property LastOutputPose: TVirtualCameraPose read FLastOutputPose;

    function BrainSummaryBadge: String;
  published
    property TargetCamera: TCastleCamera read FTargetCamera write SetTargetCamera;
    property BlendCurve: TVirtualCameraBlendCurve
      read FBlendCurve write FBlendCurve default vcbcSmoothStep;
    property BlendDurationSec: Single
      read FBlendDurationSec write FBlendDurationSec {$ifdef FPC}default DefaultBlendDurationSec{$endif};
    property Trauma: Single
      read FTrauma write SetTrauma {$ifdef FPC}default 0.0{$endif};
    property TraumaDecayPerSec: Single
      read FTraumaDecayPerSec write FTraumaDecayPerSec {$ifdef FPC}default DefaultTraumaDecayPerSec{$endif};
    property ShakeFrequencyHz: Single
      read FShakeFrequencyHz write FShakeFrequencyHz {$ifdef FPC}default DefaultShakeFrequencyHz{$endif};
    property ShakeMaxAngleDeg: Single
      read FShakeMaxAngleDeg write FShakeMaxAngleDeg {$ifdef FPC}default DefaultShakeMaxAngleDeg{$endif};
    property ShakeMaxOffsetMeters: Single
      read FShakeMaxOffsetMeters write FShakeMaxOffsetMeters {$ifdef FPC}default DefaultShakeMaxOffsetMeters{$endif};
    property SimulateInEditor: Boolean
      read FSimulateInEditor write FSimulateInEditor default False;
  end;

{ Smooth 1D gradient noise in [-1..+1] used by trauma-squared camera shake. }
function SampleCameraPerlin1D(const X: Single; const Seed: Integer): Single;

implementation

uses
  Math,
  CastleComponentSerialize, CastleApplicationProperties, CastleUtils;

{ Hierarchy-invariant transform helpers (safe even when World = nil) --------- }

function GetVCamHierarchyMatrix(const T: TCastleTransform): TMatrix4;
var
  Cur: TCastleTransform;
begin
  Result := TMatrix4.Identity;
  Cur := T;
  while (Cur <> nil) and (not (Cur is TCastleAbstractRootTransform)) do
  begin
    Result := Cur.Transform * Result;
    Cur := Cur.Parent;
  end;
end;

procedure GetVCamWorldView(const T: TCastleTransform; out OutPos, OutDir, OutUp: TVector3);
var
  M: TMatrix4;
  P, D, U: TVector3;
begin
  if T = nil then
  begin
    OutPos := TVector3.Zero;
    OutDir := Vector3(0.0, 0.0, -1.0);
    OutUp := Vector3(0.0, 1.0, 0.0);
    Exit;
  end;
  T.GetView(P, D, U);
  if T.Parent <> nil then
    M := GetVCamHierarchyMatrix(T.Parent)
  else
    M := TMatrix4.Identity;
  OutPos := M.MultPoint(P);
  OutDir := M.MultDirection(D);
  OutUp := M.MultDirection(U);
  if OutDir.LengthSqr > 1.0e-10 then
    OutDir := OutDir.Normalize
  else
    OutDir := Vector3(0.0, 0.0, -1.0);
  if OutUp.LengthSqr > 1.0e-10 then
    OutUp := OutUp.Normalize
  else
    OutUp := Vector3(0.0, 1.0, 0.0);
end;

procedure ApplyWorldPoseToCamera(const Cam: TCastleCamera; const APose: TVirtualCameraPose);
var
  ParentM, InvM: TMatrix4;
  LocalPos, LocalDir, LocalUp: TVector3;
begin
  if Cam = nil then
    Exit;
  LocalPos := APose.Position;
  LocalDir := APose.Direction;
  LocalUp := APose.Up;
  if Cam.Parent <> nil then
  begin
    ParentM := GetVCamHierarchyMatrix(Cam.Parent);
    if ParentM.TryInverse(InvM) then
    begin
      LocalPos := InvM.MultPoint(APose.Position);
      LocalDir := InvM.MultDirection(APose.Direction);
      LocalUp := InvM.MultDirection(APose.Up);
    end;
  end;
  if LocalDir.LengthSqr < 1.0e-10 then
    LocalDir := Vector3(0.0, 0.0, -1.0)
  else
    LocalDir := LocalDir.Normalize;
  if LocalUp.LengthSqr < 1.0e-10 then
    LocalUp := Vector3(0.0, 1.0, 0.0)
  else
    LocalUp := LocalUp.Normalize;

  Cam.SetView(LocalPos, LocalDir, LocalUp);
  if Cam.Perspective <> nil then
    Cam.Perspective.FieldOfView := DegToRad(Clamped(APose.FieldOfViewDeg, 5.0, 160.0));
end;

function SampleCameraPerlin1D(const X: Single; const Seed: Integer): Single;

  function HashGrad(const IX: Integer): Single;
  var
    H: Cardinal;
  begin
    {$push}{$R-}{$Q-}
    H := LongWord(IX) * LongWord(374761393) + LongWord(Seed) * LongWord(668265263);
    H := (H xor (H shr 13)) * LongWord(1274126177);
    H := H xor (H shr 16);
    {$pop}
    Result := ( (H and $FFFF) / 32767.5 ) - 1.0;
  end;

var
  X0: Integer;
  FracX, U, G0, G1: Single;
begin
  X0 := Floor(X);
  FracX := X - X0;
  U := FracX * FracX * FracX * (FracX * (FracX * 6.0 - 15.0) + 10.0);
  G0 := HashGrad(X0) * FracX;
  G1 := HashGrad(X0 + 1) * (FracX - 1.0);
  Result := Clamped(Lerp(U, G0, G1) * 2.0, -1.0, 1.0);
end;

function EvaluateBlendAlpha(const T: Single; const Curve: TVirtualCameraBlendCurve): Single;
var
  U: Single;
begin
  U := Clamped(T, 0.0, 1.0);
  case Curve of
    vcbcHardCut:        Result := 1.0;
    vcbcLinear:         Result := U;
    vcbcSmoothStep:     Result := U * U * (3.0 - 2.0 * U);
    vcbcEaseInOutCubic:
      if U < 0.5 then
        Result := 4.0 * U * U * U
      else
        Result := 1.0 - Power(-2.0 * U + 2.0, 3) * 0.5;
  end;
end;

function BlendPoses(const A, B: TVirtualCameraPose; const Alpha: Single): TVirtualCameraPose;
begin
  Result.Position := Lerp(Alpha, A.Position, B.Position);
  Result.Direction := Lerp(Alpha, A.Direction, B.Direction);
  if Result.Direction.LengthSqr > 1.0e-10 then
    Result.Direction := Result.Direction.Normalize
  else
    Result.Direction := B.Direction;
  Result.Up := Lerp(Alpha, A.Up, B.Up);
  if Result.Up.LengthSqr > 1.0e-10 then
    Result.Up := Result.Up.Normalize
  else
    Result.Up := B.Up;
  Result.FieldOfViewDeg := Lerp(Alpha, A.FieldOfViewDeg, B.FieldOfViewDeg);
end;

{ TCastleVirtualCamera ------------------------------------------------------- }

constructor TCastleVirtualCamera.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FActiveRig := True;
  FPriority := DefaultPriority;
  FBodyMode := vcbFixedTransform;
  FAimMode := vcaFixedDirection;
  FFieldOfViewDeg := DefaultFieldOfViewDeg;
  FDutchRollDeg := 0.0;

  FFollowOffset := Vector3(0.0, 2.2, 5.5);
  FFollowDamping := DefaultFollowDamping;
  FDollyNormalizedT := 0.0;
  FAutoDollyToFollowTarget := False;

  FAimTargetOffset := Vector3(0.0, 1.2, 0.0);
  FAimDamping := DefaultAimDamping;
  FDeadzoneWidthDeg := DefaultDeadzoneWidthDeg;
  FDeadzoneHeightDeg := DefaultDeadzoneHeightDeg;
  FHasState := False;

  FFollowOffsetPersistent := TCastleVector3Persistent.Create(nil);
  FFollowOffsetPersistent.SetSubComponent(True);
  FFollowOffsetPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetFollowOffsetForPersistent;
  FFollowOffsetPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetFollowOffsetForPersistent;
  FFollowOffsetPersistent.InternalDefaultValue := FFollowOffset;

  FAimTargetOffsetPersistent := TCastleVector3Persistent.Create(nil);
  FAimTargetOffsetPersistent.SetSubComponent(True);
  FAimTargetOffsetPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetAimTargetOffsetForPersistent;
  FAimTargetOffsetPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetAimTargetOffsetForPersistent;
  FAimTargetOffsetPersistent.InternalDefaultValue := FAimTargetOffset;
end;

destructor TCastleVirtualCamera.Destroy;
begin
  SetFollowTarget(nil);
  SetLookAtTarget(nil);
  SetDollySpline(nil);
  FreeAndNil(FAimTargetOffsetPersistent);
  FreeAndNil(FFollowOffsetPersistent);
  inherited;
end;

procedure TCastleVirtualCamera.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FFollowTarget then
      FFollowTarget := nil;
    if AComponent = FLookAtTarget then
      FLookAtTarget := nil;
    if AComponent = FDollySpline then
      FDollySpline := nil;
  end;
end;

function TCastleVirtualCamera.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'ActiveRig', 'Priority', 'BodyMode', 'AimMode',
       'FieldOfViewDeg', 'DutchRollDeg', 'FollowTarget', 'FollowOffsetPersistent',
       'FollowDamping', 'DollySpline', 'DollyNormalizedT', 'AutoDollyToFollowTarget',
       'LookAtTarget', 'AimTargetOffsetPersistent', 'AimDamping',
       'DeadzoneWidthDeg', 'DeadzoneHeightDeg'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleVirtualCamera.SetFollowTarget(const Value: TCastleTransform);
begin
  if FFollowTarget <> Value then
  begin
    if FFollowTarget <> nil then
      FFollowTarget.RemoveFreeNotification(Self);
    FFollowTarget := Value;
    if FFollowTarget <> nil then
      FFollowTarget.FreeNotification(Self);
  end;
end;

procedure TCastleVirtualCamera.SetLookAtTarget(const Value: TCastleTransform);
begin
  if FLookAtTarget <> Value then
  begin
    if FLookAtTarget <> nil then
      FLookAtTarget.RemoveFreeNotification(Self);
    FLookAtTarget := Value;
    if FLookAtTarget <> nil then
      FLookAtTarget.FreeNotification(Self);
  end;
end;

procedure TCastleVirtualCamera.SetDollySpline(const Value: TCastleSplinePath);
begin
  if FDollySpline <> Value then
  begin
    if FDollySpline <> nil then
      FDollySpline.RemoveFreeNotification(Self);
    FDollySpline := Value;
    if FDollySpline <> nil then
      FDollySpline.FreeNotification(Self);
  end;
end;

procedure TCastleVirtualCamera.SetFieldOfViewDeg(const Value: Single);
begin
  FFieldOfViewDeg := Clamped(Value, 5.0, 160.0);
end;

procedure TCastleVirtualCamera.SetDollyNormalizedT(const Value: Single);
begin
  FDollyNormalizedT := Clamped(Value, 0.0, 1.0);
end;

function TCastleVirtualCamera.GetFollowOffsetForPersistent: TVector3;
begin
  Result := FFollowOffset;
end;

procedure TCastleVirtualCamera.SetFollowOffsetForPersistent(const AValue: TVector3);
begin
  FFollowOffset := AValue;
end;

function TCastleVirtualCamera.GetAimTargetOffsetForPersistent: TVector3;
begin
  Result := FAimTargetOffset;
end;

procedure TCastleVirtualCamera.SetAimTargetOffsetForPersistent(const AValue: TVector3);
begin
  FAimTargetOffset := AValue;
end;

procedure TCastleVirtualCamera.SnapStateImmediate;
begin
  FHasState := False;
  StepAndEvaluatePose(0.0);
end;

function TCastleVirtualCamera.StepAndEvaluatePose(const Dt: Single): TVirtualCameraPose;
var
  SelfPos, SelfDir, SelfUp, DesiredPos, DesiredDir, TargetW, ToTarget: TVector3;
  SplineM: TMatrix4;
  Sample: TSplineSample;
  BestDistSqr, CandDistSqr, TotalLen, AlphaBody, AlphaAim: Single;
  I: Integer;
  CurRight, CurOrthoUp, GoalDir: TVector3;
  YawErrRad, PitchErrRad, HalfW, HalfH, ExcessYaw, ExcessPitch: Single;
  RolledUp: TVector3;
begin
  GetVCamWorldView(Self, SelfPos, SelfDir, SelfUp);

  { 1. Desired Body Position }
  DesiredPos := SelfPos;
  case FBodyMode of
    vcbFixedTransform:
      DesiredPos := SelfPos;

    vcbThirdPersonFollow:
      if FFollowTarget <> nil then
      begin
        TargetW := GetVCamHierarchyMatrix(FFollowTarget).MultPoint(TVector3.Zero);
        DesiredPos := TargetW + FFollowOffset;
      end;

    vcbSplineDollyRail:
      if (FDollySpline <> nil) and (FDollySpline.ControlPointCount >= 2) then
      begin
        SplineM := GetVCamHierarchyMatrix(FDollySpline);
        TotalLen := Max(0.001, FDollySpline.TotalLength);
        if FAutoDollyToFollowTarget and (FFollowTarget <> nil) then
        begin
          TargetW := GetVCamHierarchyMatrix(FFollowTarget).MultPoint(TVector3.Zero);
          BestDistSqr := MaxSingle;
          for I := 0 to 32 do
          begin
            Sample := FDollySpline.EvaluateLocalAtDistance(TotalLen * (I / 32.0));
            CandDistSqr := PointsDistanceSqr(SplineM.MultPoint(Sample.Position), TargetW);
            if CandDistSqr < BestDistSqr then
            begin
              BestDistSqr := CandDistSqr;
              FDollyNormalizedT := I / 32.0;
            end;
          end;
        end;
        Sample := FDollySpline.EvaluateLocalAtDistance(TotalLen * Clamped(FDollyNormalizedT, 0.0, 1.0));
        DesiredPos := SplineM.MultPoint(Sample.Position);
      end;
  end;

  if (not FHasState) or (Dt <= 0.0) or (FFollowDamping <= 0.0) or (FBodyMode = vcbFixedTransform) then
    FCurWorldPos := DesiredPos
  else
  begin
    AlphaBody := 1.0 - Exp(-FFollowDamping * Dt);
    FCurWorldPos := Lerp(AlphaBody, FCurWorldPos, DesiredPos);
  end;

  { 2. Desired Aim Orientation }
  if not FHasState then
  begin
    FCurWorldDir := SelfDir;
    FCurWorldUp := Vector3(0.0, 1.0, 0.0);
  end;

  case FAimMode of
    vcaFixedDirection:
      FCurWorldDir := SelfDir;

    vcaHardLookAt:
      if FLookAtTarget <> nil then
      begin
        TargetW := GetVCamHierarchyMatrix(FLookAtTarget).MultPoint(TVector3.Zero) + FAimTargetOffset;
        ToTarget := TargetW - FCurWorldPos;
        if ToTarget.LengthSqr > 1.0e-8 then
          FCurWorldDir := ToTarget.Normalize;
      end else
        FCurWorldDir := SelfDir;

    vcaDeadzoneComposer:
      if FLookAtTarget <> nil then
      begin
        TargetW := GetVCamHierarchyMatrix(FLookAtTarget).MultPoint(TVector3.Zero) + FAimTargetOffset;
        ToTarget := TargetW - FCurWorldPos;
        if ToTarget.LengthSqr > 1.0e-8 then
        begin
          ToTarget := ToTarget.Normalize;
          CurRight := TVector3.CrossProduct(FCurWorldDir, Vector3(0.0, 1.0, 0.0));
          if CurRight.LengthSqr < 1.0e-8 then
            CurRight := Vector3(1.0, 0.0, 0.0)
          else
            CurRight := CurRight.Normalize;
          CurOrthoUp := TVector3.CrossProduct(CurRight, FCurWorldDir).Normalize;

          YawErrRad := ArcTan2(
            TVector3.DotProduct(ToTarget, CurRight),
            Max(1.0e-5, TVector3.DotProduct(ToTarget, FCurWorldDir)));
          PitchErrRad := ArcSin(Clamped(TVector3.DotProduct(ToTarget, CurOrthoUp), -1.0, 1.0));

          HalfW := DegToRad(Max(0.0, FDeadzoneWidthDeg) * 0.5);
          HalfH := DegToRad(Max(0.0, FDeadzoneHeightDeg) * 0.5);

          if Abs(YawErrRad) > HalfW then
            ExcessYaw := Sign(YawErrRad) * (Abs(YawErrRad) - HalfW)
          else
            ExcessYaw := 0.0;

          if Abs(PitchErrRad) > HalfH then
            ExcessPitch := Sign(PitchErrRad) * (Abs(PitchErrRad) - HalfH)
          else
            ExcessPitch := 0.0;

          if (Abs(ExcessYaw) > 1.0e-5) or (Abs(ExcessPitch) > 1.0e-5) then
          begin
            GoalDir := RotatePointAroundAxisRad( -ExcessYaw, FCurWorldDir, Vector3(0.0, 1.0, 0.0));
            GoalDir := RotatePointAroundAxisRad( ExcessPitch, GoalDir, CurRight);
            if GoalDir.LengthSqr > 1.0e-8 then
              GoalDir := GoalDir.Normalize;
            if (Dt <= 0.0) or (FAimDamping <= 0.0) then
              DesiredDir := GoalDir
            else
            begin
              AlphaAim := 1.0 - Exp(-FAimDamping * Dt);
              DesiredDir := Lerp(AlphaAim, FCurWorldDir, GoalDir);
              if DesiredDir.LengthSqr > 1.0e-8 then
                DesiredDir := DesiredDir.Normalize;
            end;
            FCurWorldDir := DesiredDir;
          end;
        end;
      end;
  end;

  FHasState := True;

  { Orthogonalize Up and apply Dutch roll }
  CurRight := TVector3.CrossProduct(FCurWorldDir, Vector3(0.0, 1.0, 0.0));
  if CurRight.LengthSqr < 1.0e-8 then
    CurRight := Vector3(1.0, 0.0, 0.0)
  else
    CurRight := CurRight.Normalize;
  RolledUp := TVector3.CrossProduct(CurRight, FCurWorldDir).Normalize;
  if not IsZero(FDutchRollDeg) then
    RolledUp := RotatePointAroundAxisRad(DegToRad(FDutchRollDeg), RolledUp, FCurWorldDir).Normalize;

  Result.Position := FCurWorldPos;
  Result.Direction := FCurWorldDir;
  Result.Up := RolledUp;
  Result.FieldOfViewDeg := FFieldOfViewDeg;
end;

function TCastleVirtualCamera.VCamSummaryBadge: String;
var
  ModeStr: String;
begin
  case FBodyMode of
    vcbFixedTransform:    ModeStr := 'Fixed';
    vcbThirdPersonFollow: ModeStr := 'Follow';
    vcbSplineDollyRail:   ModeStr := 'SplineDolly';
  end;
  Result := Format('[VCam:Prio %d FOV %.0f° %s%s]', [
    FPriority, FFieldOfViewDeg, ModeStr,
    specialize IfThen<String>(FActiveRig, '', ' OFF')
  ]);
end;

{ TCastleVirtualCameraBrain -------------------------------------------------- }

constructor TCastleVirtualCameraBrain.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBlendCurve := vcbcSmoothStep;
  FBlendDurationSec := DefaultBlendDurationSec;
  FTrauma := 0.0;
  FTraumaDecayPerSec := DefaultTraumaDecayPerSec;
  FShakeFrequencyHz := DefaultShakeFrequencyHz;
  FShakeMaxAngleDeg := DefaultShakeMaxAngleDeg;
  FShakeMaxOffsetMeters := DefaultShakeMaxOffsetMeters;
  FSimulateInEditor := False;
  FActiveVCam := nil;
  FIsBlending := False;
  FBlendElapsedSec := 0.0;
  FHasLastPose := False;
  FNoiseTime := 0.0;
end;

procedure TCastleVirtualCameraBrain.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FTargetCamera then
      FTargetCamera := nil;
    if AComponent = FActiveVCam then
      FActiveVCam := nil;
  end;
end;

function TCastleVirtualCameraBrain.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'TargetCamera', 'BlendCurve', 'BlendDurationSec', 'Trauma',
       'TraumaDecayPerSec', 'ShakeFrequencyHz', 'ShakeMaxAngleDeg',
       'ShakeMaxOffsetMeters', 'SimulateInEditor'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleVirtualCameraBrain.SetTargetCamera(const Value: TCastleCamera);
begin
  if FTargetCamera <> Value then
  begin
    if FTargetCamera <> nil then
      FTargetCamera.RemoveFreeNotification(Self);
    FTargetCamera := Value;
    if FTargetCamera <> nil then
      FTargetCamera.FreeNotification(Self);
  end;
end;

procedure TCastleVirtualCameraBrain.SetTrauma(const Value: Single);
begin
  FTrauma := Clamped(Value, 0.0, 1.0);
end;

procedure TCastleVirtualCameraBrain.AddTrauma(const AAmount: Single);
begin
  FTrauma := Clamped(FTrauma + Max(0.0, AAmount), 0.0, 1.0);
end;

function TCastleVirtualCameraBrain.ResolveDrivenCamera: TCastleCamera;
begin
  if FTargetCamera <> nil then
    Exit(FTargetCamera);
  if Parent is TCastleCamera then
    Exit(TCastleCamera(Parent));
  if (World <> nil) and (World.MainCamera <> nil) then
    Exit(World.MainCamera);
  Result := nil;
end;

function TCastleVirtualCameraBrain.SelectWinningVCam: TCastleVirtualCamera;
var
  Best: TCastleVirtualCamera;

  procedure ConsiderVCam(const V: TCastleVirtualCamera);
  begin
    if (V = nil) or (not V.ActiveRig) or (not V.Exists) then
      Exit;
    if (Best = nil) or (V.Priority > Best.Priority) then
      Best := V;
  end;

  procedure ScanTree(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if (T = nil) or (csTransient in T.ComponentStyle) then
      Exit;
    if T is TCastleVirtualCamera then
      ConsiderVCam(TCastleVirtualCamera(T));
    for I := 0 to T.Count - 1 do
      ScanTree(T[I]);
  end;

var
  RootT: TCastleTransform;
  I: Integer;
begin
  Best := nil;
  if Parent <> nil then
  begin
    RootT := Parent;
    while RootT.Parent <> nil do
      RootT := RootT.Parent;
    ScanTree(RootT);
  end;
  if Owner <> nil then
    for I := 0 to Owner.ComponentCount - 1 do
      if Owner.Components[I] is TCastleVirtualCamera then
        ConsiderVCam(TCastleVirtualCamera(Owner.Components[I]));
  Result := Best;
end;

procedure TCastleVirtualCameraBrain.StepBrain(const Dt: Single);
var
  Winner: TCastleVirtualCamera;
  GoalPose, BasePose, FinalPose: TVirtualCameraPose;
  Alpha, ShakeAmp, TNoise, YawShake, PitchShake, RollShake, OffX, OffY: Single;
  RightAxis, UpAxis: TVector3;
  Cam: TCastleCamera;
begin
  Winner := SelectWinningVCam;
  if Winner = nil then
    Exit;

  if Winner <> FActiveVCam then
  begin
    if FActiveVCam <> nil then
      FActiveVCam.RemoveFreeNotification(Self);
    Winner.FreeNotification(Self);

    if FHasLastPose and (FBlendCurve <> vcbcHardCut) and (FBlendDurationSec > 1.0e-4) then
    begin
      FBlendStartPose := FLastOutputPose;
      FIsBlending := True;
      FBlendElapsedSec := 0.0;
    end else
      FIsBlending := False;

    FActiveVCam := Winner;
  end;

  GoalPose := FActiveVCam.StepAndEvaluatePose(Max(0.0, Dt));

  if FIsBlending then
  begin
    FBlendElapsedSec := FBlendElapsedSec + Max(0.0, Dt);
    if FBlendElapsedSec + 1.0e-5 >= FBlendDurationSec then
    begin
      FIsBlending := False;
      BasePose := GoalPose;
    end else
    begin
      Alpha := EvaluateBlendAlpha(FBlendElapsedSec / FBlendDurationSec, FBlendCurve);
      BasePose := BlendPoses(FBlendStartPose, GoalPose, Alpha);
    end;
  end else
    BasePose := GoalPose;

  FLastOutputPose := BasePose;
  FHasLastPose := True;

  { Layer Trauma^2 Perlin 3D Shake without polluting underlying blend snapshot }
  FinalPose := BasePose;
  if Dt > 0.0 then
    FTrauma := Max(0.0, FTrauma - FTraumaDecayPerSec * Dt);
  if FTrauma > 1.0e-4 then
  begin
    FNoiseTime := FNoiseTime + Max(0.0, Dt) * Max(0.5, FShakeFrequencyHz);
    ShakeAmp := FTrauma * FTrauma;
    TNoise := FNoiseTime;

    YawShake   := DegToRad(FShakeMaxAngleDeg * ShakeAmp * SampleCameraPerlin1D(TNoise, 101));
    PitchShake := DegToRad(FShakeMaxAngleDeg * ShakeAmp * SampleCameraPerlin1D(TNoise, 211));
    RollShake  := DegToRad(FShakeMaxAngleDeg * ShakeAmp * SampleCameraPerlin1D(TNoise, 307));
    OffX       := FShakeMaxOffsetMeters * ShakeAmp * SampleCameraPerlin1D(TNoise, 401);
    OffY       := FShakeMaxOffsetMeters * ShakeAmp * SampleCameraPerlin1D(TNoise, 503);

    RightAxis := TVector3.CrossProduct(FinalPose.Direction, FinalPose.Up);
    if RightAxis.LengthSqr < 1.0e-8 then
      RightAxis := Vector3(1.0, 0.0, 0.0)
    else
      RightAxis := RightAxis.Normalize;
    UpAxis := FinalPose.Up;

    FinalPose.Position := FinalPose.Position + RightAxis * OffX + UpAxis * OffY;
    FinalPose.Direction := RotatePointAroundAxisRad(YawShake, FinalPose.Direction, UpAxis);
    FinalPose.Direction := RotatePointAroundAxisRad(PitchShake, FinalPose.Direction, RightAxis).Normalize;
    FinalPose.Up := RotatePointAroundAxisRad(RollShake, UpAxis, FinalPose.Direction).Normalize;
  end;

  Cam := ResolveDrivenCamera;
  if Cam <> nil then
    ApplyWorldPoseToCamera(Cam, FinalPose);
end;

procedure TCastleVirtualCameraBrain.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepBrain(SecondsPassed);
end;

function TCastleVirtualCameraBrain.BrainSummaryBadge: String;
var
  WinName: String;
begin
  if FActiveVCam <> nil then
    WinName := FActiveVCam.Name
  else
    WinName := 'None';
  Result := Format('[VCamBrain:%s %.1fs]', [WinName, FBlendDurationSec]);
end;

initialization
  RegisterSerializableComponent(TCastleVirtualCamera, ['Virtual Camera Rig']);
  RegisterSerializableComponent(TCastleVirtualCameraBrain, ['Virtual Camera Director Brain']);
end.
