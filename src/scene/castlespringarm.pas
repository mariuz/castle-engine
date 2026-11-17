{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Third-person Spring-Arm camera collision boom with 5-ray whisker occlusion
  sweeping, instant wall pull-in, asymmetric exponential ease-out recovery,
  over-the-shoulder offsets, and lagged target tracking
  (Phase 339 — Unreal Engine 6.0+ USpringArmComponent parity). }
unit CastleSpringArm;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils, CastleTriangles,
  CastleTransform, CastleScene, X3DNodes;

type
  { Result of a single whisker probe ray along the Spring-Arm boom. }
  TSpringArmWhiskerRay = record
    OriginWorld: TVector3;
    EndWorld: TVector3;
    Blocked: Boolean;
    HitDistance: Single;
  end;

  { Spring-Arm camera boom transform that tracks a target pivot with optional
    exponential lag, sweeps a 5-ray whisker bundle against world geometry,
    pulls in immediately on occlusion, and eases back smoothly when clear. }
  TCastleSpringArm = class(TCastleTransform)
  private
    FFollowTargetName: String;
    FTargetArmLength: Single;
    FMinArmLength: Single;
    FProbeRadius: Single;
    FSocketOffsetY: Single;
    FShoulderOffsetX: Single;
    FYawDeg: Single;
    FPitchDeg: Single;
    FEnablePositionLag: Boolean;
    FPositionLagSpeed: Single;
    FRecoveryExtendSpeed: Single;
    FShowDebugWhiskers: Boolean;
    FAutoStepInUpdate: Boolean;

    FLaggedPivotInitialized: Boolean;
    FLaggedPivotWorld: TVector3;
    FCurrentArmLength: Single;
    FIsOccluded: Boolean;
    FSolvedAnchorWorldPos: TVector3;
    FSolvedCameraWorldPos: TVector3;
    FSolvedLookDirection: TVector3;
    FWhiskers: array[0..4] of TSpringArmWhiskerRay;

    FTransientDebugScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;

    procedure SetTargetArmLength(const AValue: Single);
    procedure SetMinArmLength(const AValue: Single);
    procedure SetProbeRadius(const AValue: Single);
    procedure SetPitchDeg(const AValue: Single);
    procedure SetPositionLagSpeed(const AValue: Single);
    procedure SetRecoveryExtendSpeed(const AValue: Single);
    procedure SetShowDebugWhiskers(const AValue: Boolean);

    function ResolveRawTargetWorldPos(out ATargetTransform: TCastleTransform): TVector3;
    procedure EnsureDebugScene;
    procedure RebuildDebugMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Reset lagged pivot & boom length directly to TargetArmLength. }
    procedure SnapToTargetImmediately;

    { Step lagged pivot, cast the 5-ray whisker bundle against AWorld, apply
      instant pull-in vs. smooth exponential ease-out, and update SolvedCameraWorldPos. }
    procedure StepSpringArm(const Dt: Single;
      const AWorld: TCastleAbstractRootTransform);

    function GetWhisker(const AIndex: Integer): TSpringArmWhiskerRay;
    function BlockedWhiskerCount: Integer;
    function CompressionRatio: Single;
    function SpringArmSummaryBadge: String;

    property CurrentArmLength: Single read FCurrentArmLength;
    property IsOccluded: Boolean read FIsOccluded;
    property SolvedAnchorWorldPos: TVector3 read FSolvedAnchorWorldPos;
    property SolvedCameraWorldPos: TVector3 read FSolvedCameraWorldPos;
    property SolvedLookDirection: TVector3 read FSolvedLookDirection;
  published
    property FollowTargetName: String read FFollowTargetName write FFollowTargetName;
    property TargetArmLength: Single read FTargetArmLength write SetTargetArmLength {$ifdef FPC}default 4.50{$endif};
    property MinArmLength: Single read FMinArmLength write SetMinArmLength {$ifdef FPC}default 0.35{$endif};
    property ProbeRadius: Single read FProbeRadius write SetProbeRadius {$ifdef FPC}default 0.25{$endif};
    property SocketOffsetY: Single read FSocketOffsetY write FSocketOffsetY {$ifdef FPC}default 1.55{$endif};
    property ShoulderOffsetX: Single read FShoulderOffsetX write FShoulderOffsetX {$ifdef FPC}default 0.0{$endif};
    property YawDeg: Single read FYawDeg write FYawDeg {$ifdef FPC}default 0.0{$endif};
    property PitchDeg: Single read FPitchDeg write SetPitchDeg {$ifdef FPC}default 12.0{$endif};
    property EnablePositionLag: Boolean read FEnablePositionLag write FEnablePositionLag default True;
    property PositionLagSpeed: Single read FPositionLagSpeed write SetPositionLagSpeed {$ifdef FPC}default 10.0{$endif};
    property RecoveryExtendSpeed: Single read FRecoveryExtendSpeed write SetRecoveryExtendSpeed {$ifdef FPC}default 6.0{$endif};
    property ShowDebugWhiskers: Boolean read FShowDebugWhiskers write SetShowDebugWhiskers default True;
    property AutoStepInUpdate: Boolean read FAutoStepInUpdate write FAutoStepInUpdate default True;
  end;

implementation

uses
  CastleComponentSerialize;

constructor TCastleSpringArm.Create(AOwner: TComponent);
var
  I: Integer;
begin
  inherited Create(AOwner);
  FTargetArmLength := 4.50;
  FMinArmLength := 0.35;
  FProbeRadius := 0.25;
  FSocketOffsetY := 1.55;
  FShoulderOffsetX := 0.0;
  FYawDeg := 0.0;
  FPitchDeg := 12.0;
  FEnablePositionLag := True;
  FPositionLagSpeed := 10.0;
  FRecoveryExtendSpeed := 6.0;
  FShowDebugWhiskers := True;
  FAutoStepInUpdate := True;
  FCurrentArmLength := FTargetArmLength;
  FSolvedLookDirection := Vector3(0, 0, -1);
  for I := 0 to 4 do
    FWhiskers[I] := Default(TSpringArmWhiskerRay);
end;

destructor TCastleSpringArm.Destroy;
begin
  FreeAndNil(FTransientDebugScene);
  inherited Destroy;
end;

function TCastleSpringArm.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'FollowTargetName', 'TargetArmLength', 'MinArmLength', 'ProbeRadius',
       'SocketOffsetY', 'ShoulderOffsetX', 'YawDeg', 'PitchDeg',
       'EnablePositionLag', 'PositionLagSpeed', 'RecoveryExtendSpeed',
       'ShowDebugWhiskers', 'AutoStepInUpdate'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSpringArm.SetTargetArmLength(const AValue: Single);
begin
  FTargetArmLength := Max(0.25, AValue);
  if FCurrentArmLength > FTargetArmLength then
    FCurrentArmLength := FTargetArmLength;
end;

procedure TCastleSpringArm.SetMinArmLength(const AValue: Single);
begin
  FMinArmLength := Max(0.05, AValue);
end;

procedure TCastleSpringArm.SetProbeRadius(const AValue: Single);
begin
  FProbeRadius := Max(0.01, AValue);
end;

procedure TCastleSpringArm.SetPitchDeg(const AValue: Single);
begin
  FPitchDeg := EnsureRange(AValue, -85.0, 85.0);
end;

procedure TCastleSpringArm.SetPositionLagSpeed(const AValue: Single);
begin
  FPositionLagSpeed := Max(0.1, AValue);
end;

procedure TCastleSpringArm.SetRecoveryExtendSpeed(const AValue: Single);
begin
  FRecoveryExtendSpeed := Max(0.1, AValue);
end;

procedure TCastleSpringArm.SetShowDebugWhiskers(const AValue: Boolean);
begin
  if FShowDebugWhiskers = AValue then Exit;
  FShowDebugWhiskers := AValue;
  if not FShowDebugWhiskers then
    FreeAndNil(FTransientDebugScene)
  else
    RebuildDebugMesh;
end;

function TCastleSpringArm.ResolveRawTargetWorldPos(
  out ATargetTransform: TCastleTransform): TVector3;
var
  Comp: TComponent;
begin
  ATargetTransform := nil;
  if (FFollowTargetName <> '') and (Owner <> nil) then
  begin
    Comp := Owner.FindComponent(FFollowTargetName);
    if Comp is TCastleTransform then
    begin
      ATargetTransform := TCastleTransform(Comp);
      if ATargetTransform.HasParent then
        Exit(ATargetTransform.WorldTranslation)
      else
        Exit(ATargetTransform.Translation);
    end;
  end;
  if HasParent then
    Result := WorldTranslation
  else
    Result := Translation;
end;

procedure TCastleSpringArm.SnapToTargetImmediately;
var
  TargetT: TCastleTransform;
begin
  FLaggedPivotWorld := ResolveRawTargetWorldPos(TargetT);
  FLaggedPivotInitialized := True;
  FCurrentArmLength := FTargetArmLength;
  FIsOccluded := False;
end;

procedure TCastleSpringArm.StepSpringArm(const Dt: Single;
  const AWorld: TCastleAbstractRootTransform);
var
  TargetT: TCastleTransform;
  RawTargetPos, BoomDir, RightAxis, UpAxis, RayStart: TVector3;
  Offsets: array[0..4] of TVector3;
  YawR, PitchR, AlphaLag, AlphaRec, ClosestHitDist, AllowedLen, HitDist: Single;
  SavedTargetExists, SavedDebugExists: Boolean;
  RayHit: TRayCollision;
  I: Integer;
begin
  RawTargetPos := ResolveRawTargetWorldPos(TargetT);
  if (not FLaggedPivotInitialized) or (not FEnablePositionLag) or (Dt <= 0.0) then
  begin
    FLaggedPivotWorld := RawTargetPos;
    FLaggedPivotInitialized := True;
  end else
  begin
    AlphaLag := 1.0 - Exp(-FPositionLagSpeed * Dt);
    FLaggedPivotWorld := Lerp(AlphaLag, FLaggedPivotWorld, RawTargetPos);
  end;

  YawR := DegToRad(FYawDeg);
  PitchR := DegToRad(FPitchDeg);
  { Boom extends backward (+Z when Yaw=0, Pitch=0) and upward (+Y when Pitch>0) }
  BoomDir := Vector3(
    Sin(YawR) * Cos(PitchR),
    Sin(PitchR),
    Cos(YawR) * Cos(PitchR)).Normalize;
  RightAxis := Vector3(Cos(YawR), 0.0, -Sin(YawR)).Normalize;
  UpAxis := TVector3.CrossProduct(BoomDir, RightAxis).Normalize;

  FSolvedAnchorWorldPos := FLaggedPivotWorld
    + Vector3(0.0, FSocketOffsetY, 0.0)
    + RightAxis * FShoulderOffsetX;

  Offsets[0] := TVector3.Zero;
  Offsets[1] := RightAxis * FProbeRadius;
  Offsets[2] := -RightAxis * FProbeRadius;
  Offsets[3] := UpAxis * FProbeRadius;
  Offsets[4] := -UpAxis * FProbeRadius;

  ClosestHitDist := FTargetArmLength + FProbeRadius + 100.0;
  FIsOccluded := False;

  SavedTargetExists := (TargetT <> nil) and TargetT.Exists;
  SavedDebugExists := (FTransientDebugScene <> nil) and FTransientDebugScene.Exists;
  if TargetT <> nil then TargetT.Exists := False;
  if FTransientDebugScene <> nil then FTransientDebugScene.Exists := False;
  try
    for I := 0 to 4 do
    begin
      RayStart := FSolvedAnchorWorldPos + Offsets[I];
      FWhiskers[I] := Default(TSpringArmWhiskerRay);
      FWhiskers[I].OriginWorld := RayStart;
      FWhiskers[I].EndWorld := RayStart + BoomDir * FTargetArmLength;
      FWhiskers[I].HitDistance := FTargetArmLength;

      if AWorld <> nil then
      begin
        RayHit := AWorld.WorldRay(RayStart, BoomDir);
        try
          if RayHit <> nil then
          begin
            HitDist := RayHit.Distance;
            if (HitDist >= 0.0) and (HitDist <= FTargetArmLength + FProbeRadius) then
            begin
              FWhiskers[I].Blocked := True;
              FWhiskers[I].HitDistance := Min(FTargetArmLength, HitDist);
              FWhiskers[I].EndWorld := RayStart + BoomDir * FWhiskers[I].HitDistance;
              if HitDist < ClosestHitDist then
                ClosestHitDist := HitDist;
              FIsOccluded := True;
            end;
          end;
        finally
          FreeAndNil(RayHit);
        end;
      end;
    end;
  finally
    if FTransientDebugScene <> nil then FTransientDebugScene.Exists := SavedDebugExists;
    if TargetT <> nil then TargetT.Exists := SavedTargetExists;
  end;

  if FIsOccluded then
  begin
    AllowedLen := EnsureRange(ClosestHitDist - FProbeRadius, FMinArmLength, FTargetArmLength);
    if AllowedLen <= FCurrentArmLength then
      { Instant occlusion pull-in: never clip inside walls! }
      FCurrentArmLength := AllowedLen
    else if Dt > 0.0 then
    begin
      AlphaRec := 1.0 - Exp(-FRecoveryExtendSpeed * Dt);
      FCurrentArmLength := Lerp(AlphaRec, FCurrentArmLength, AllowedLen);
    end else
      FCurrentArmLength := AllowedLen;
  end else
  begin
    if Dt > 0.0 then
    begin
      AlphaRec := 1.0 - Exp(-FRecoveryExtendSpeed * Dt);
      FCurrentArmLength := Lerp(AlphaRec, FCurrentArmLength, FTargetArmLength);
    end;
  end;

  FSolvedCameraWorldPos := FSolvedAnchorWorldPos + BoomDir * FCurrentArmLength;
  FSolvedLookDirection := -BoomDir;
  RebuildDebugMesh;
end;

procedure TCastleSpringArm.EnsureDebugScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if not FShowDebugWhiskers then
    Exit;
  if FTransientDebugScene <> nil then
    Exit;

  FTransientDebugScene := TCastleScene.Create(nil);
  FTransientDebugScene.SetTransient;
  FTransientDebugScene.Name := 'TransientSpringArmMesh';
  FTransientDebugScene.Pickable := False;
  FTransientDebugScene.PreciseCollisions := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TUnlitMaterialNode.Create;
  Mat.EmissiveColor := Vector3(1, 1, 1);
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  TriSet.Coord := FCoordNode;
  TriSet.Color := FColorNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);

  FTransientDebugScene.Load(Root, True);
  Add(FTransientDebugScene);
end;

procedure TCastleSpringArm.RebuildDebugMesh;
var
  InvWorld: TMatrix4;
  Verts, Colors: TVector3List;
  I: Integer;
  Col: TVector3;

  procedure AddRibbonSeg(const A, B: TVector3; const HalfW: Single; const C: TVector3);
  var
    Off: TVector3;
  begin
    Off := Vector3(HalfW, HalfW, 0.0);
    Verts.Add(InvWorld.MultPoint(A - Off));
    Verts.Add(InvWorld.MultPoint(A + Off));
    Verts.Add(InvWorld.MultPoint(B + Off));
    Colors.Add(C); Colors.Add(C); Colors.Add(C);

    Verts.Add(InvWorld.MultPoint(A - Off));
    Verts.Add(InvWorld.MultPoint(B + Off));
    Verts.Add(InvWorld.MultPoint(B - Off));
    Colors.Add(C); Colors.Add(C); Colors.Add(C);
  end;

begin
  if not FShowDebugWhiskers then
    Exit;
  EnsureDebugScene;
  if FTransientDebugScene = nil then
    Exit;

  if (not HasParent) or (not WorldTransform.TryInverse(InvWorld)) then
    InvWorld := TMatrix4.Identity;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    { Active camera boom }
    if FIsOccluded then
      Col := Vector3(1.0, 0.35, 0.25)
    else
      Col := Vector3(0.28, 0.92, 0.52);
    AddRibbonSeg(FSolvedAnchorWorldPos, FSolvedCameraWorldPos, 0.035, Col);

    { 5 whisker probe rays }
    for I := 0 to 4 do
    begin
      if FWhiskers[I].Blocked then
        Col := Vector3(1.0, 0.55, 0.18)
      else
        Col := Vector3(0.45, 0.78, 1.0);
      AddRibbonSeg(FWhiskers[I].OriginWorld, FWhiskers[I].EndWorld, 0.012, Col);
    end;

    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;
end;

procedure TCastleSpringArm.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FAutoStepInUpdate then
    StepSpringArm(Min(SecondsPassed, 0.1), World);
end;

function TCastleSpringArm.GetWhisker(const AIndex: Integer): TSpringArmWhiskerRay;
begin
  if (AIndex >= 0) and (AIndex <= 4) then
    Result := FWhiskers[AIndex]
  else
    Result := Default(TSpringArmWhiskerRay);
end;

function TCastleSpringArm.BlockedWhiskerCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to 4 do
    if FWhiskers[I].Blocked then
      Inc(Result);
end;

function TCastleSpringArm.CompressionRatio: Single;
begin
  if FTargetArmLength <= 0.01 then
    Exit(0.0);
  Result := EnsureRange(1.0 - (FCurrentArmLength / FTargetArmLength), 0.0, 1.0);
end;

function TCastleSpringArm.SpringArmSummaryBadge: String;
begin
  if FIsOccluded then
    Result := Format('[SpringArm:PULLED %.2f/%.2fm (%d/5 hit)]', [
      FCurrentArmLength, FTargetArmLength, BlockedWhiskerCount])
  else
    Result := Format('[SpringArm:Clear %.2f/%.2fm]', [
      FCurrentArmLength, FTargetArmLength]);
end;

initialization
  RegisterSerializableComponent(TCastleSpringArm,
    ['Cameras & Cinematics', 'Spring-Arm Camera Boom (TCastleSpringArm)']);

end.
