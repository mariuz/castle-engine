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

{ Chaos Mover 2.0 stateless rollback-ready character locomotion behavior
  supporting GroundWalk, AirFalling, CrouchSlide, WallRun, BuoyantSwim, and
  GrappleZip with a 128-tick rewind & resimulation ring buffer
  (Phase 351 — Unreal Engine 5.8 / 6.0+ UMoverComponent Parity). }
unit CastleMover2;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleClassUtils, CastleUtils,
  CastleTransform;

type
  { Kinematic locomotion modes managed by Mover 2.0. }
  TMoverLocomotionMode = (
    mlmGroundWalk,
    mlmAirFalling,
    mlmCrouchSlide,
    mlmWallRun,
    mlmBuoyantSwim,
    mlmGrappleZip
  );

  { Per-tick player/AI input command fed into Mover 2.0's pure step function. }
  TMoverInputCmd = record
    MoveWishWorld: TVector3;
    JumpPressed: Boolean;
    CrouchSlideHeld: Boolean;
    WallRunHeld: Boolean;
    WallNormalXZ: TVector3;
    GrappleRequested: Boolean;
    GrappleTargetWorld: TVector3;
    class function WalkForward(const ADir: TVector3): TMoverInputCmd; static;
  end;

  { Complete serializable/rollbackable Mover 2.0 sync state at a discrete tick. }
  TMoverSyncState = record
    TickIndex: Integer;
    Mode: TMoverLocomotionMode;
    Position: TVector3;
    Velocity: TVector3;
    ModeElapsedSec: Single;
    GrappleAnchor: TVector3;
  end;

  { Entry in the 128-frame rollback history ring buffer. }
  TMoverHistoryEntry = record
    Valid: Boolean;
    InputCmd: TMoverInputCmd;
    BeforeState: TMoverSyncState;
    AfterState: TMoverSyncState;
  end;

  { Rollback-ready Mover 2.0 character locomotion behavior. }
  TCastleMoverBehavior = class(TCastleBehavior)
  public const
    HistoryCapacity = 128;
  private
    FWalkMaxSpeed: Single;
    FWalkAccel: Single;
    FGroundFriction: Single;
    FJumpImpulseSpeed: Single;
    FGravityAccel: Single;
    FSlideInitialBoost: Single;
    FSlideFriction: Single;
    FMaxWallRunDurationSec: Single;
    FWallRunSpeed: Single;
    FSwimMaxSpeed: Single;
    FGrapplePullSpeed: Single;
    FFloorHeightY: Single;
    FWaterSurfaceY: Single;
    FEnableWaterZone: Boolean;

    FCurrentState: TMoverSyncState;
    FHistory: array[0..HistoryCapacity - 1] of TMoverHistoryEntry;
    FHistoryHeadCount: Integer;
    FRollbackResimCount: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ResetStateAtPosition(const AWorldPos: TVector3;
      const AInitialMode: TMoverLocomotionMode = mlmGroundWalk);

    { Pure functional Mover 2.0 simulation step:
      (InputCmd, PrevSyncState, Dt) -> NextSyncState with zero hidden side effects. }
    function EvaluateStep(const AInput: TMoverInputCmd;
      const APrev: TMoverSyncState; const ADt: Single): TMoverSyncState;

    { Advance one authoritative tick, record into rollback ring, and sync Parent. }
    function AdvanceTick(const AInput: TMoverInputCmd;
      const ADt: Single = 1.0 / 60.0): TMoverSyncState;

    { Rewind to ATargetTick, replace its input with ACorrectedInput, and
      resimulate all buffered ticks up to CurrentState.TickIndex. }
    function RewindAndResimulateFromTick(const ATargetTick: Integer;
      const ACorrectedInput: TMoverInputCmd;
      const ADt: Single = 1.0 / 60.0): Boolean;

    function GetHistoryEntryByTick(const ATick: Integer;
      out AOutEntry: TMoverHistoryEntry): Boolean;
    function MoverSummaryBadge: String;

    property CurrentState: TMoverSyncState read FCurrentState write FCurrentState;
    property RollbackResimCount: Integer read FRollbackResimCount;
  published
    property WalkMaxSpeed: Single read FWalkMaxSpeed write FWalkMaxSpeed {$ifdef FPC}default 7.0{$endif};
    property WalkAccel: Single read FWalkAccel write FWalkAccel {$ifdef FPC}default 32.0{$endif};
    property GroundFriction: Single read FGroundFriction write FGroundFriction {$ifdef FPC}default 8.0{$endif};
    property JumpImpulseSpeed: Single read FJumpImpulseSpeed write FJumpImpulseSpeed {$ifdef FPC}default 6.8{$endif};
    property GravityAccel: Single read FGravityAccel write FGravityAccel {$ifdef FPC}default 16.0{$endif};
    property SlideInitialBoost: Single read FSlideInitialBoost write FSlideInitialBoost {$ifdef FPC}default 11.5{$endif};
    property SlideFriction: Single read FSlideFriction write FSlideFriction {$ifdef FPC}default 2.2{$endif};
    property MaxWallRunDurationSec: Single read FMaxWallRunDurationSec write FMaxWallRunDurationSec {$ifdef FPC}default 1.5{$endif};
    property WallRunSpeed: Single read FWallRunSpeed write FWallRunSpeed {$ifdef FPC}default 9.0{$endif};
    property SwimMaxSpeed: Single read FSwimMaxSpeed write FSwimMaxSpeed {$ifdef FPC}default 4.8{$endif};
    property GrapplePullSpeed: Single read FGrapplePullSpeed write FGrapplePullSpeed {$ifdef FPC}default 22.0{$endif};
    property FloorHeightY: Single read FFloorHeightY write FFloorHeightY {$ifdef FPC}default 0.0{$endif};
    property WaterSurfaceY: Single read FWaterSurfaceY write FWaterSurfaceY {$ifdef FPC}default -2.0{$endif};
    property EnableWaterZone: Boolean read FEnableWaterZone write FEnableWaterZone default False;
  end;

function MoverModeToDisplayName(const AMode: TMoverLocomotionMode): String;

implementation

uses
  CastleComponentSerialize;

function MoverModeToDisplayName(const AMode: TMoverLocomotionMode): String;
begin
  case AMode of
    mlmGroundWalk:  Result := 'Ground Walk/Sprint';
    mlmAirFalling:  Result := 'Airborne / Jump';
    mlmCrouchSlide: Result := 'Momentum Crouch-Slide';
    mlmWallRun:     Result := 'Parkour Wall-Run';
    mlmBuoyantSwim: Result := 'Buoyant Swim';
    mlmGrappleZip:  Result := 'Grapple-Hook Zip';
  end;
end;

{ TMoverInputCmd ------------------------------------------------------------- }

class function TMoverInputCmd.WalkForward(const ADir: TVector3): TMoverInputCmd;
begin
  Result := Default(TMoverInputCmd);
  Result.MoveWishWorld := ADir;
end;

{ TCastleMoverBehavior ------------------------------------------------------- }

constructor TCastleMoverBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWalkMaxSpeed := 7.0;
  FWalkAccel := 32.0;
  FGroundFriction := 8.0;
  FJumpImpulseSpeed := 6.8;
  FGravityAccel := 16.0;
  FSlideInitialBoost := 11.5;
  FSlideFriction := 2.2;
  FMaxWallRunDurationSec := 1.5;
  FWallRunSpeed := 9.0;
  FSwimMaxSpeed := 4.8;
  FGrapplePullSpeed := 22.0;
  FFloorHeightY := 0.0;
  FWaterSurfaceY := -2.0;
  FEnableWaterZone := False;
  ResetStateAtPosition(TVector3.Zero, mlmGroundWalk);
end;

function TCastleMoverBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'WalkMaxSpeed', 'WalkAccel', 'GroundFriction', 'JumpImpulseSpeed',
       'GravityAccel', 'SlideInitialBoost', 'SlideFriction',
       'MaxWallRunDurationSec', 'WallRunSpeed', 'SwimMaxSpeed',
       'GrapplePullSpeed', 'FloorHeightY', 'WaterSurfaceY', 'EnableWaterZone'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMoverBehavior.ResetStateAtPosition(const AWorldPos: TVector3;
  const AInitialMode: TMoverLocomotionMode);
var
  I: Integer;
begin
  FCurrentState := Default(TMoverSyncState);
  FCurrentState.TickIndex := 0;
  FCurrentState.Mode := AInitialMode;
  FCurrentState.Position := AWorldPos;
  FCurrentState.Velocity := TVector3.Zero;
  for I := 0 to High(FHistory) do
    FHistory[I] := Default(TMoverHistoryEntry);
  FHistoryHeadCount := 0;
  if Parent <> nil then
    Parent.Translation := AWorldPos;
end;

function ClampHorizontalSpeed(const AVel: TVector3; const AMaxSpeed: Single): TVector3;
var
  Horiz: TVector3;
  Spd: Single;
begin
  Horiz := Vector3(AVel.X, 0.0, AVel.Z);
  Spd := Horiz.Length;
  if (Spd > AMaxSpeed) and (Spd > 1e-6) then
  begin
    Horiz := Horiz * (AMaxSpeed / Spd);
    Result := Vector3(Horiz.X, AVel.Y, Horiz.Z);
  end else
    Result := AVel;
end;

function TCastleMoverBehavior.EvaluateStep(const AInput: TMoverInputCmd;
  const APrev: TMoverSyncState; const ADt: Single): TMoverSyncState;
var
  Dt, SubmergeDepth, DistToAnchor: Single;
  WishXZ, WallN, WallTan, ToAnchor: TVector3;
begin
  Result := APrev;
  Inc(Result.TickIndex);
  Dt := EnsureRange(ADt, 1e-4, 0.25);
  Result.ModeElapsedSec := Result.ModeElapsedSec + Dt;

  WishXZ := Vector3(AInput.MoveWishWorld.X, 0.0, AInput.MoveWishWorld.Z);
  if WishXZ.Length > 1.0 then
    WishXZ := WishXZ.Normalize;

  { Global grapple-hook override }
  if AInput.GrappleRequested then
  begin
    Result.Mode := mlmGrappleZip;
    Result.GrappleAnchor := AInput.GrappleTargetWorld;
    Result.ModeElapsedSec := 0.0;
  end;

  { Global water entry check }
  if FEnableWaterZone and (Result.Mode <> mlmGrappleZip) and
     (Result.Position.Y < FWaterSurfaceY - 0.25) then
  begin
    if Result.Mode <> mlmBuoyantSwim then
      Result.ModeElapsedSec := 0.0;
    Result.Mode := mlmBuoyantSwim;
  end;

  case Result.Mode of
    mlmGroundWalk:
      begin
        if AInput.CrouchSlideHeld and (WishXZ.LengthSqr > 0.05) then
        begin
          Result.Mode := mlmCrouchSlide;
          Result.ModeElapsedSec := 0.0;
          Result.Velocity := WishXZ.Normalize * FSlideInitialBoost;
        end else
        begin
          Result.Velocity := Result.Velocity * Max(0.0, 1.0 - FGroundFriction * Dt)
            + WishXZ * (FWalkAccel * Dt);
          Result.Velocity := ClampHorizontalSpeed(Result.Velocity, FWalkMaxSpeed);
          Result.Velocity.Y := 0.0;
          if AInput.JumpPressed then
          begin
            Result.Velocity.Y := FJumpImpulseSpeed;
            Result.Mode := mlmAirFalling;
            Result.ModeElapsedSec := 0.0;
          end;
        end;
        Result.Position := Result.Position + Result.Velocity * Dt;
        if Result.Mode = mlmGroundWalk then
          Result.Position.Y := FFloorHeightY;
      end;

    mlmCrouchSlide:
      begin
        Result.Velocity := Result.Velocity * Max(0.0, 1.0 - FSlideFriction * Dt);
        Result.Velocity.Y := 0.0;
        Result.Position := Result.Position + Result.Velocity * Dt;
        Result.Position.Y := FFloorHeightY;
        if AInput.JumpPressed then
        begin
          Result.Velocity.Y := FJumpImpulseSpeed * 1.05;
          Result.Mode := mlmAirFalling;
          Result.ModeElapsedSec := 0.0;
        end else if (not AInput.CrouchSlideHeld) or (Result.Velocity.Length < 2.2) then
        begin
          Result.Mode := mlmGroundWalk;
          Result.ModeElapsedSec := 0.0;
        end;
      end;

    mlmAirFalling:
      begin
        if AInput.WallRunHeld and (AInput.WallNormalXZ.LengthSqr > 0.1) then
        begin
          Result.Mode := mlmWallRun;
          Result.ModeElapsedSec := 0.0;
        end else
        begin
          Result.Velocity := Result.Velocity + WishXZ * (FWalkAccel * 0.35 * Dt);
          Result.Velocity := ClampHorizontalSpeed(Result.Velocity, FWalkMaxSpeed * 1.15);
          Result.Velocity.Y := Result.Velocity.Y - FGravityAccel * Dt;
          Result.Position := Result.Position + Result.Velocity * Dt;
          if (not FEnableWaterZone) and (Result.Position.Y <= FFloorHeightY) then
          begin
            Result.Position.Y := FFloorHeightY;
            Result.Velocity.Y := 0.0;
            Result.Mode := mlmGroundWalk;
            Result.ModeElapsedSec := 0.0;
          end;
        end;
      end;

    mlmWallRun:
      begin
        WallN := Vector3(AInput.WallNormalXZ.X, 0.0, AInput.WallNormalXZ.Z);
        if WallN.LengthSqr < 1e-6 then
          WallN := Vector3(1, 0, 0)
        else
          WallN := WallN.Normalize;
        WallTan := Vector3(-WallN.Z, 0.0, WallN.X);
        if TVector3.DotProduct(WallTan, WishXZ) < 0.0 then
          WallTan := -WallTan;

        Result.Velocity.X := WallTan.X * FWallRunSpeed;
        Result.Velocity.Z := WallTan.Z * FWallRunSpeed;
        { Counteracted 0.20x low-gravity wall friction glide }
        Result.Velocity.Y := Max(-1.2, Result.Velocity.Y - FGravityAccel * 0.20 * Dt);

        if AInput.JumpPressed then
        begin
          Result.Velocity := Result.Velocity + WallN * 5.5 + Vector3(0.0, FJumpImpulseSpeed, 0.0);
          Result.Mode := mlmAirFalling;
          Result.ModeElapsedSec := 0.0;
        end else if (not AInput.WallRunHeld) or (Result.ModeElapsedSec >= FMaxWallRunDurationSec) then
        begin
          Result.Mode := mlmAirFalling;
          Result.ModeElapsedSec := 0.0;
        end;
        Result.Position := Result.Position + Result.Velocity * Dt;
      end;

    mlmBuoyantSwim:
      begin
        SubmergeDepth := FWaterSurfaceY - Result.Position.Y;
        { Archimedes upward buoyancy + hydrodynamic drag + 3D swim wish }
        Result.Velocity := Result.Velocity * Max(0.0, 1.0 - 4.5 * Dt)
          + AInput.MoveWishWorld * (FWalkAccel * 0.55 * Dt)
          + Vector3(0.0, EnsureRange(SubmergeDepth * 14.0, -4.0, 12.0) * Dt, 0.0);
        if Result.Velocity.Length > FSwimMaxSpeed then
          Result.Velocity := Result.Velocity.Normalize * FSwimMaxSpeed;
        Result.Position := Result.Position + Result.Velocity * Dt;

        if AInput.JumpPressed and (Abs(Result.Position.Y - FWaterSurfaceY) < 0.65) then
        begin
          Result.Velocity.Y := FJumpImpulseSpeed;
          Result.Mode := mlmAirFalling;
          Result.ModeElapsedSec := 0.0;
        end;
      end;

    mlmGrappleZip:
      begin
        ToAnchor := Result.GrappleAnchor - Result.Position;
        DistToAnchor := ToAnchor.Length;
        if DistToAnchor <= Max(0.65, FGrapplePullSpeed * Dt * 1.2) then
        begin
          Result.Position := Result.GrappleAnchor;
          Result.Velocity := Result.Velocity * 0.35;
          if Result.Position.Y > FFloorHeightY + 0.10 then
            Result.Mode := mlmAirFalling
          else
            Result.Mode := mlmGroundWalk;
          Result.ModeElapsedSec := 0.0;
        end else
        begin
          Result.Velocity := (ToAnchor / DistToAnchor) * FGrapplePullSpeed;
          Result.Position := Result.Position + Result.Velocity * Dt;
        end;
      end;
  end;
end;

function TCastleMoverBehavior.AdvanceTick(const AInput: TMoverInputCmd;
  const ADt: Single): TMoverSyncState;
var
  SlotIdx: Integer;
  PrevS, NextS: TMoverSyncState;
begin
  PrevS := FCurrentState;
  NextS := EvaluateStep(AInput, PrevS, ADt);

  SlotIdx := NextS.TickIndex mod HistoryCapacity;
  FHistory[SlotIdx].Valid := True;
  FHistory[SlotIdx].InputCmd := AInput;
  FHistory[SlotIdx].BeforeState := PrevS;
  FHistory[SlotIdx].AfterState := NextS;
  Inc(FHistoryHeadCount);

  FCurrentState := NextS;
  if Parent <> nil then
    Parent.Translation := FCurrentState.Position;
  Result := FCurrentState;
end;

function TCastleMoverBehavior.GetHistoryEntryByTick(const ATick: Integer;
  out AOutEntry: TMoverHistoryEntry): Boolean;
var
  SlotIdx: Integer;
begin
  Result := False;
  AOutEntry := Default(TMoverHistoryEntry);
  if ATick <= 0 then Exit;
  SlotIdx := ATick mod HistoryCapacity;
  if FHistory[SlotIdx].Valid and (FHistory[SlotIdx].AfterState.TickIndex = ATick) then
  begin
    AOutEntry := FHistory[SlotIdx];
    Result := True;
  end;
end;

function TCastleMoverBehavior.RewindAndResimulateFromTick(
  const ATargetTick: Integer; const ACorrectedInput: TMoverInputCmd;
  const ADt: Single): Boolean;
var
  HeadTick, T, SlotIdx: Integer;
  Entry: TMoverHistoryEntry;
  RunState: TMoverSyncState;
  Cmd: TMoverInputCmd;
begin
  HeadTick := FCurrentState.TickIndex;
  if (ATargetTick <= 0) or (ATargetTick > HeadTick) then
    Exit(False);
  if not GetHistoryEntryByTick(ATargetTick, Entry) then
    Exit(False);

  RunState := Entry.BeforeState;
  for T := ATargetTick to HeadTick do
  begin
    SlotIdx := T mod HistoryCapacity;
    if T = ATargetTick then
      Cmd := ACorrectedInput
    else if FHistory[SlotIdx].Valid and (FHistory[SlotIdx].AfterState.TickIndex = T) then
      Cmd := FHistory[SlotIdx].InputCmd
    else
      Exit(False);

    FHistory[SlotIdx].InputCmd := Cmd;
    FHistory[SlotIdx].BeforeState := RunState;
    RunState := EvaluateStep(Cmd, RunState, ADt);
    FHistory[SlotIdx].AfterState := RunState;
  end;

  FCurrentState := RunState;
  Inc(FRollbackResimCount);
  if Parent <> nil then
    Parent.Translation := FCurrentState.Position;
  Result := True;
end;

function TCastleMoverBehavior.MoverSummaryBadge: String;
begin
  Result := Format('[Mover2:%s Tick=%d Resim=%d]', [
    MoverModeToDisplayName(FCurrentState.Mode),
    FCurrentState.TickIndex, FRollbackResimCount
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleMoverBehavior,
    ['AI & Gameplay', 'Chaos Mover 2.0 Rollback Locomotion (TCastleMoverBehavior)']);

end.
