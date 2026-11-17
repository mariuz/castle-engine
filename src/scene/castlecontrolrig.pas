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

{ Control Rig procedural multi-bone chain solver featuring N-joint Forward-And-
  Backward Reaching Inverse Kinematics (FABRIK), anti-candy-wrapper progressive
  twist roll distribution, and sinusoidal tail/tentacle wave rigs
  (Phase 338 — Unreal Engine 6.0+ UControlRig parity). }
unit CastleControlRig;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Built-in procedural Control Rig presets. }
  TControlRigPreset = (
    crpRoboticArmFabrik,
    crpProceduralTailWave,
    crpDragonNeckAim
  );

  { Solved world-space joint state in an N-bone Control Rig chain. }
  TControlRigJoint = record
    Name: String;
    RestSegmentLength: Single;
    WorldPos: TVector3;
    TwistRollDeg: Single;
  end;

  { Procedural multi-bone FABRIK, twist-distribution, and additive wave rig
    behavior attachable to any TCastleTransform. }
  TCastleControlRigBehavior = class(TCastleBehavior)
  private
    FPreset: TControlRigPreset;
    FEffectorTargetName: String;
    FMaxFabrikIterations: Integer;
    FToleranceMeters: Single;
    FEndEffectorTwistDeg: Single;
    FEnableProceduralWave: Boolean;
    FWaveAmplitudeDeg: Single;
    FWaveFrequencyHz: Single;
    FWavePhaseRad: Single;
    FBuildVisualRigMesh: Boolean;
    FAutoSolveInUpdate: Boolean;

    FJoints: array of TControlRigJoint;
    FTotalChainLength: Single;
    FLastIterationsUsed: Integer;
    FLastTipErrorMeters: Single;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;

    procedure SetPreset(const AValue: TControlRigPreset);
    procedure SetMaxFabrikIterations(const AValue: Integer);
    procedure SetToleranceMeters(const AValue: Single);
    procedure SetEndEffectorTwistDeg(const AValue: Single);
    procedure SetBuildVisualRigMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);

    function ResolveRootWorldPos: TVector3;
    function ResolveEffectorWorldPos(out AHasTarget: Boolean): TVector3;
    procedure RecomputeChainTotalLength;
    procedure UpdateProgressiveTwistAngles;
    procedure EnsureVisualScene;
    procedure RebuildVisualMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TControlRigPreset);

    { Configure an N-joint chain with uniform segment lengths along +Z. }
    procedure ConfigureUniformChain(const AJointCount: Integer;
      const ASegmentLength: Single);

    { Solve FABRIK toward EffectorTargetName (or explicit target), apply
      progressive twist distribution and optional sinusoidal wave, and refresh
      the csTransient visual debug rig. }
    procedure SolveRig(const Dt: Single);
    procedure SolveFabrikToWorldTarget(const ATargetWorld: TVector3);

    function JointCount: Integer;
    function GetJoint(const AIndex: Integer): TControlRigJoint;
    function JointWorldPos(const AIndex: Integer): TVector3;
    function MaxSegmentLengthDrift: Single;
    function ControlRigSummaryBadge: String;

    property TotalChainLength: Single read FTotalChainLength;
    property LastIterationsUsed: Integer read FLastIterationsUsed;
    property LastTipErrorMeters: Single read FLastTipErrorMeters;
  published
    property Preset: TControlRigPreset read FPreset write SetPreset default crpRoboticArmFabrik;
    property EffectorTargetName: String read FEffectorTargetName write FEffectorTargetName;
    property MaxFabrikIterations: Integer read FMaxFabrikIterations write SetMaxFabrikIterations default 16;
    property ToleranceMeters: Single read FToleranceMeters write SetToleranceMeters {$ifdef FPC}default 0.001{$endif};
    property EndEffectorTwistDeg: Single read FEndEffectorTwistDeg write SetEndEffectorTwistDeg {$ifdef FPC}default 0.0{$endif};
    property EnableProceduralWave: Boolean read FEnableProceduralWave write FEnableProceduralWave default False;
    property WaveAmplitudeDeg: Single read FWaveAmplitudeDeg write FWaveAmplitudeDeg {$ifdef FPC}default 18.0{$endif};
    property WaveFrequencyHz: Single read FWaveFrequencyHz write FWaveFrequencyHz {$ifdef FPC}default 1.5{$endif};
    property BuildVisualRigMesh: Boolean read FBuildVisualRigMesh write SetBuildVisualRigMesh default True;
    property AutoSolveInUpdate: Boolean read FAutoSolveInUpdate write FAutoSolveInUpdate default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

function ComputeProgressiveTwistDeg(const ATotalTwistDeg: Single;
  const AJointIndex, AJointCount: Integer): Single;
function ControlRigPresetToDisplayName(const APreset: TControlRigPreset): String;

implementation

uses
  fpjson, jsonparser,
  CastleComponentSerialize;

function ComputeProgressiveTwistDeg(const ATotalTwistDeg: Single;
  const AJointIndex, AJointCount: Integer): Single;
begin
  if AJointCount <= 1 then
    Exit(ATotalTwistDeg);
  Result := ATotalTwistDeg * (EnsureRange(AJointIndex, 0, AJointCount - 1) / Single(AJointCount - 1));
end;

function ControlRigPresetToDisplayName(const APreset: TControlRigPreset): String;
begin
  case APreset of
    crpRoboticArmFabrik:   Result := '6-Joint FABRIK Arm';
    crpProceduralTailWave: Result := '8-Joint Sine Tail Wave';
    crpDragonNeckAim:      Result := '7-Joint Dragon Neck Aim';
  end;
end;

{ TCastleControlRigBehavior -------------------------------------------------- }

constructor TCastleControlRigBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxFabrikIterations := 16;
  FToleranceMeters := 0.001;
  FEndEffectorTwistDeg := 0.0;
  FWaveAmplitudeDeg := 18.0;
  FWaveFrequencyHz := 1.5;
  FBuildVisualRigMesh := True;
  FAutoSolveInUpdate := True;
  ApplyPreset(crpRoboticArmFabrik);
end;

destructor TCastleControlRigBehavior.Destroy;
begin
  FreeAndNil(FTransientScene);
  SetLength(FJoints, 0);
  inherited Destroy;
end;

function TCastleControlRigBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'EffectorTargetName', 'MaxFabrikIterations',
       'ToleranceMeters', 'EndEffectorTwistDeg', 'EnableProceduralWave',
       'WaveAmplitudeDeg', 'WaveFrequencyHz', 'BuildVisualRigMesh',
       'AutoSolveInUpdate', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleControlRigBehavior.ConfigureUniformChain(
  const AJointCount: Integer; const ASegmentLength: Single);
var
  I, N: Integer;
  RootPos: TVector3;
  SegLen: Single;
begin
  N := EnsureRange(AJointCount, 2, 24);
  SegLen := Max(0.05, ASegmentLength);
  RootPos := ResolveRootWorldPos;
  SetLength(FJoints, N);
  for I := 0 to N - 1 do
  begin
    FJoints[I] := Default(TControlRigJoint);
    FJoints[I].Name := Format('Joint_%d', [I]);
    if I < N - 1 then
      FJoints[I].RestSegmentLength := SegLen
    else
      FJoints[I].RestSegmentLength := 0.0;
    FJoints[I].WorldPos := RootPos + Vector3(0.0, 0.0, SegLen * I);
  end;
  RecomputeChainTotalLength;
  UpdateProgressiveTwistAngles;
end;

procedure TCastleControlRigBehavior.RecomputeChainTotalLength;
var
  I: Integer;
begin
  FTotalChainLength := 0.0;
  for I := 0 to High(FJoints) - 1 do
    FTotalChainLength := FTotalChainLength + FJoints[I].RestSegmentLength;
end;

procedure TCastleControlRigBehavior.UpdateProgressiveTwistAngles;
var
  I, N: Integer;
begin
  N := Length(FJoints);
  for I := 0 to N - 1 do
    FJoints[I].TwistRollDeg := ComputeProgressiveTwistDeg(FEndEffectorTwistDeg, I, N);
end;

procedure TCastleControlRigBehavior.ApplyPreset(const APreset: TControlRigPreset);
begin
  FPreset := APreset;
  case APreset of
    crpRoboticArmFabrik:
      begin
        FEnableProceduralWave := False;
        ConfigureUniformChain(6, 0.80); { 5 * 0.80m = 4.00m reach }
      end;
    crpProceduralTailWave:
      begin
        FEnableProceduralWave := True;
        FWaveAmplitudeDeg := 22.0;
        FWaveFrequencyHz := 1.6;
        ConfigureUniformChain(8, 0.45);
      end;
    crpDragonNeckAim:
      begin
        FEnableProceduralWave := False;
        ConfigureUniformChain(7, 0.65);
      end;
  end;
  RebuildVisualMesh;
end;

procedure TCastleControlRigBehavior.SetPreset(const AValue: TControlRigPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleControlRigBehavior.SetMaxFabrikIterations(const AValue: Integer);
begin
  FMaxFabrikIterations := EnsureRange(AValue, 1, 64);
end;

procedure TCastleControlRigBehavior.SetToleranceMeters(const AValue: Single);
begin
  FToleranceMeters := Max(0.00005, AValue);
end;

procedure TCastleControlRigBehavior.SetEndEffectorTwistDeg(const AValue: Single);
begin
  FEndEffectorTwistDeg := AValue;
  UpdateProgressiveTwistAngles;
  RebuildVisualMesh;
end;

procedure TCastleControlRigBehavior.SetBuildVisualRigMesh(const AValue: Boolean);
begin
  if FBuildVisualRigMesh = AValue then Exit;
  FBuildVisualRigMesh := AValue;
  if not FBuildVisualRigMesh then
    FreeAndNil(FTransientScene)
  else
    RebuildVisualMesh;
end;

function TCastleControlRigBehavior.ResolveRootWorldPos: TVector3;
begin
  if Parent = nil then
    Exit(TVector3.Zero);
  if Parent.HasParent then
    Result := Parent.WorldTranslation
  else
    Result := Parent.Translation;
end;

function TCastleControlRigBehavior.ResolveEffectorWorldPos(
  out AHasTarget: Boolean): TVector3;
var
  SearchOwner: TComponent;
  Comp: TComponent;
  T: TCastleTransform;
begin
  AHasTarget := False;
  Result := ResolveRootWorldPos + Vector3(0.0, 1.5, Max(0.5, FTotalChainLength * 0.7));
  if FEffectorTargetName = '' then
    Exit;
  SearchOwner := Owner;
  if (SearchOwner = nil) and (Parent <> nil) then
    SearchOwner := Parent.Owner;
  if SearchOwner = nil then
    Exit;
  Comp := SearchOwner.FindComponent(FEffectorTargetName);
  if Comp is TCastleTransform then
  begin
    T := TCastleTransform(Comp);
    AHasTarget := True;
    if T.HasParent then
      Result := T.WorldTranslation
    else
      Result := T.Translation;
  end;
end;

procedure TCastleControlRigBehavior.SolveFabrikToWorldTarget(
  const ATargetWorld: TVector3);
var
  N, Iter, I: Integer;
  RootPos, DirVec: TVector3;
  DistToRoot, SegLen, SegDist: Single;
begin
  N := Length(FJoints);
  if N < 2 then
    Exit;
  RootPos := ResolveRootWorldPos;
  RecomputeChainTotalLength;
  UpdateProgressiveTwistAngles;

  { Anchor root before measuring }
  DistToRoot := PointsDistance(RootPos, ATargetWorld);
  if DistToRoot >= FTotalChainLength - 1e-5 then
  begin
    { Out-of-reach target: stretch straight toward target preserving exact lengths }
    if DistToRoot < 1e-6 then
      DirVec := Vector3(0, 0, 1)
    else
      DirVec := (ATargetWorld - RootPos) / DistToRoot;
    FJoints[0].WorldPos := RootPos;
    for I := 0 to N - 2 do
      FJoints[I + 1].WorldPos := FJoints[I].WorldPos + DirVec * FJoints[I].RestSegmentLength;
    FLastIterationsUsed := 1;
    FLastTipErrorMeters := PointsDistance(FJoints[N - 1].WorldPos, ATargetWorld);
    RebuildVisualMesh;
    Exit;
  end;

  { Reachable target: forward-and-backward reaching iterations }
  FJoints[0].WorldPos := RootPos;
  for I := 0 to N - 2 do
    if PointsDistance(FJoints[I + 1].WorldPos, FJoints[I].WorldPos) < 1e-5 then
      FJoints[I + 1].WorldPos := FJoints[I].WorldPos + Vector3(0.0, 0.05 * (I + 1), FJoints[I].RestSegmentLength);

  FLastIterationsUsed := 0;
  for Iter := 1 to FMaxFabrikIterations do
  begin
    FLastIterationsUsed := Iter;
    FLastTipErrorMeters := PointsDistance(FJoints[N - 1].WorldPos, ATargetWorld);
    if FLastTipErrorMeters <= FToleranceMeters then
      Break;

    { Stage 1: Backward reaching (tip -> root) }
    FJoints[N - 1].WorldPos := ATargetWorld;
    for I := N - 2 downto 0 do
    begin
      SegLen := FJoints[I].RestSegmentLength;
      SegDist := PointsDistance(FJoints[I].WorldPos, FJoints[I + 1].WorldPos);
      if SegDist < 1e-6 then
        DirVec := Vector3(0, 0, -1)
      else
        DirVec := (FJoints[I].WorldPos - FJoints[I + 1].WorldPos) / SegDist;
      FJoints[I].WorldPos := FJoints[I + 1].WorldPos + DirVec * SegLen;
    end;

    { Stage 2: Forward reaching (root -> tip) }
    FJoints[0].WorldPos := RootPos;
    for I := 0 to N - 2 do
    begin
      SegLen := FJoints[I].RestSegmentLength;
      SegDist := PointsDistance(FJoints[I + 1].WorldPos, FJoints[I].WorldPos);
      if SegDist < 1e-6 then
        DirVec := Vector3(0, 0, 1)
      else
        DirVec := (FJoints[I + 1].WorldPos - FJoints[I].WorldPos) / SegDist;
      FJoints[I + 1].WorldPos := FJoints[I].WorldPos + DirVec * SegLen;
    end;
  end;

  FLastTipErrorMeters := PointsDistance(FJoints[N - 1].WorldPos, ATargetWorld);
  RebuildVisualMesh;
end;

procedure TCastleControlRigBehavior.SolveRig(const Dt: Single);
var
  HasTarget: Boolean;
  TargetW, RootPos: TVector3;
  I, N: Integer;
  YawAngle, PitchAngle: Single;
  SegDir: TVector3;
begin
  N := Length(FJoints);
  if N < 2 then
    Exit;

  if FEnableProceduralWave then
  begin
    FWavePhaseRad := FWavePhaseRad + Max(0.0, Dt) * FWaveFrequencyHz * 2.0 * Pi;
    RootPos := ResolveRootWorldPos;
    FJoints[0].WorldPos := RootPos;
    for I := 0 to N - 2 do
    begin
      YawAngle := DegToRad(FWaveAmplitudeDeg) * Sin(FWavePhaseRad - I * 0.65);
      PitchAngle := DegToRad(FWaveAmplitudeDeg * 0.35) * Cos(FWavePhaseRad - I * 0.50);
      SegDir := Vector3(
        Sin(YawAngle) * Cos(PitchAngle),
        Sin(PitchAngle),
        Cos(YawAngle) * Cos(PitchAngle)).Normalize;
      FJoints[I + 1].WorldPos := FJoints[I].WorldPos + SegDir * FJoints[I].RestSegmentLength;
    end;
    UpdateProgressiveTwistAngles;
    FLastIterationsUsed := 1;
    FLastTipErrorMeters := 0.0;
    RebuildVisualMesh;
  end else
  begin
    TargetW := ResolveEffectorWorldPos(HasTarget);
    SolveFabrikToWorldTarget(TargetW);
  end;
end;

procedure TCastleControlRigBehavior.EnsureVisualScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if (not FBuildVisualRigMesh) or (Parent = nil) then
    Exit;
  if FTransientScene <> nil then
  begin
    if FTransientScene.Parent <> Parent then
      Parent.Add(FTransientScene);
    Exit;
  end;

  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientControlRigMesh';
  FTransientScene.Pickable := False;
  FTransientScene.PreciseCollisions := False;

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

  FTransientScene.Load(Root, True);
  Parent.Add(FTransientScene);
end;

procedure TCastleControlRigBehavior.RebuildVisualMesh;
var
  InvWorld: TMatrix4;
  Verts, Colors: TVector3List;
  I: Integer;
  A, B, SegDir, SideA, SideB, Col: TVector3;
  HalfW, Frac: Single;

  procedure AddQuad(const P0, P1, Off, C: TVector3);
  begin
    Verts.Add(InvWorld.MultPoint(P0 - Off));
    Verts.Add(InvWorld.MultPoint(P0 + Off));
    Verts.Add(InvWorld.MultPoint(P1 + Off));
    Colors.Add(C); Colors.Add(C); Colors.Add(C);

    Verts.Add(InvWorld.MultPoint(P0 - Off));
    Verts.Add(InvWorld.MultPoint(P1 + Off));
    Verts.Add(InvWorld.MultPoint(P1 - Off));
    Colors.Add(C); Colors.Add(C); Colors.Add(C);
  end;

begin
  if (not FBuildVisualRigMesh) or (Parent = nil) then
    Exit;
  EnsureVisualScene;
  if FTransientScene = nil then
    Exit;

  if (not Parent.HasParent) or (not Parent.WorldTransform.TryInverse(InvWorld)) then
    InvWorld := TMatrix4.Identity;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    for I := 0 to High(FJoints) - 1 do
    begin
      A := FJoints[I].WorldPos;
      B := FJoints[I + 1].WorldPos;
      SegDir := B - A;
      if SegDir.LengthSqr < 1e-6 then Continue;
      SegDir := SegDir.Normalize;
      SideA := TVector3.CrossProduct(SegDir, Vector3(0, 1, 0));
      if SideA.LengthSqr < 1e-4 then
        SideA := TVector3.CrossProduct(SegDir, Vector3(1, 0, 0));
      SideA := SideA.Normalize;
      SideB := TVector3.CrossProduct(SegDir, SideA).Normalize;

      Frac := I / Single(Max(1, Length(FJoints) - 1));
      HalfW := Lerp(Frac, 0.08, 0.035);
      Col := Lerp(Frac, Vector3(0.25, 0.85, 0.95), Vector3(1.0, 0.72, 0.22));
      AddQuad(A, B, SideA * HalfW, Col);
      AddQuad(A, B, SideB * HalfW, Col * 0.85);
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

procedure TCastleControlRigBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FAutoSolveInUpdate then
    SolveRig(Min(SecondsPassed, 0.1));
end;

function TCastleControlRigBehavior.JointCount: Integer;
begin
  Result := Length(FJoints);
end;

function TCastleControlRigBehavior.GetJoint(const AIndex: Integer): TControlRigJoint;
begin
  if (AIndex >= 0) and (AIndex <= High(FJoints)) then
    Result := FJoints[AIndex]
  else
    Result := Default(TControlRigJoint);
end;

function TCastleControlRigBehavior.JointWorldPos(const AIndex: Integer): TVector3;
begin
  Result := GetJoint(AIndex).WorldPos;
end;

function TCastleControlRigBehavior.MaxSegmentLengthDrift: Single;
var
  I: Integer;
  ActualLen, Drift: Single;
begin
  Result := 0.0;
  for I := 0 to High(FJoints) - 1 do
  begin
    ActualLen := PointsDistance(FJoints[I].WorldPos, FJoints[I + 1].WorldPos);
    Drift := Abs(ActualLen - FJoints[I].RestSegmentLength);
    if Drift > Result then
      Result := Drift;
  end;
end;

function TCastleControlRigBehavior.ControlRigSummaryBadge: String;
begin
  Result := Format('[CtrlRig:%d joints L=%.2fm Err=%.3fm Twist=%.0f°]', [
    Length(FJoints), FTotalChainLength, FLastTipErrorMeters, FEndEffectorTwistDeg
  ]);
end;

function TCastleControlRigBehavior.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('jointCount', Length(FJoints));
    if Length(FJoints) >= 2 then
      Obj.Add('segLen', FJoints[0].RestSegmentLength);
    Obj.Add('twistDeg', FEndEffectorTwistDeg);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleControlRigBehavior.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  PresetOrd, JCount: Integer;
  SegLen: Single;
begin
  if Trim(AValue) = '' then
    Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Data := nil;
    end;
    if not (Data is TJSONObject) then
      Exit;
    Obj := TJSONObject(Data);
    PresetOrd := Obj.Get('preset', Ord(FPreset));
    if (PresetOrd >= Ord(Low(TControlRigPreset))) and
       (PresetOrd <= Ord(High(TControlRigPreset))) then
      ApplyPreset(TControlRigPreset(PresetOrd));

    JCount := Obj.Get('jointCount', Length(FJoints));
    SegLen := Obj.Get('segLen', 0.80);
    if (JCount >= 2) and (SegLen > 0.01) then
      ConfigureUniformChain(JCount, SegLen);
    FEndEffectorTwistDeg := Obj.Get('twistDeg', FEndEffectorTwistDeg);
    UpdateProgressiveTwistAngles;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleControlRigBehavior,
    ['Animation & IK', 'Control Rig Multi-Bone FABRIK & Twist (TCastleControlRigBehavior)']);

end.
