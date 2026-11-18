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

{ Chaos Flesh 3D tetrahedral XPBD soft-body simulation with exact signed-volume
  6V constraints, 0-inversion crush recovery, and strain shading (Phase 354). }
unit CastleTetSoftBody;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Soft-body compliance and pinning presets. }
  TTetSoftBodyPreset = (
    tsbpCustom,
    tsbpRubberBouncyCube,
    tsbpGelatinJelloBlob,
    tsbpHangingFleshPillar,
    tsbpFirmMuscleBlock
  );

  { Single tetrahedral element connecting 4 particle indices with positive rest volume. }
  TTetElement = record
    V0, V1, V2, V3: Integer;
    RestVolume: Single;
    LastStrain: Single;
  end;

  { Unique distance edge constraint between two tetrahedral vertices. }
  TTetEdgeConstraint = record
    A, B: Integer;
    RestLength: Single;
  end;

  { Per-step volumetric telemetry for XPBD tetrahedral soft-bodies. }
  TTetSoftBodyStats = record
    VertexCount: Integer;
    TetrahedronCount: Integer;
    EdgeCount: Integer;
    RestTotalVolume: Single;
    CurrentTotalVolume: Single;
    VolumeRatioPercent: Single;
    InvertedTetCount: Integer;
    MinVertexLocalY: Single;
    MaxVertexLocalY: Single;
    SimulationSteps: Integer;
  end;

  { 3D volumetric soft-body component matching Unreal Engine 6.0+ Chaos Flesh
    (UDeformableTetrahedralComponent) using alternating 5-tet-per-cell lattices
    and analytical XPBD edge + signed-volume 6V projection. }
  TCastleTetSoftBody = class(TCastleTransform)
  private
    FPreset: TTetSoftBodyPreset;
    FCellsX: Integer;
    FCellsY: Integer;
    FCellsZ: Integer;
    FBodySize: TVector3;
    FDropStartHeight: Single;
    FFloorLocalY: Single;
    FEdgeCompliance: Single;
    FVolumeCompliance: Single;
    FDamping: Single;
    FGravityY: Single;
    FSubsteps: Integer;
    FPinTopFace: Boolean;
    FShowDeformableMesh: Boolean;
    FPositions: array of TVector3;
    FRestPositions: array of TVector3;
    FVelocities: array of TVector3;
    FInvMasses: array of Single;
    FTets: array of TTetElement;
    FEdges: array of TTetEdgeConstraint;
    FStats: TTetSoftBodyStats;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TTetSoftBodyPreset);
    procedure SetCellsX(const AValue: Integer);
    procedure SetCellsY(const AValue: Integer);
    procedure SetCellsZ(const AValue: Integer);
    procedure SetDropStartHeight(const AValue: Single);
    procedure SetFloorLocalY(const AValue: Single);
    procedure SetEdgeCompliance(const AValue: Single);
    procedure SetVolumeCompliance(const AValue: Single);
    procedure SetDamping(const AValue: Single);
    procedure SetGravityY(const AValue: Single);
    procedure SetSubsteps(const AValue: Integer);
    procedure SetPinTopFace(const AValue: Boolean);
    procedure SetShowDeformableMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetParamsOnly(const APreset: TTetSoftBodyPreset);
    function GridIndex(const IX, IY, IZ: Integer): Integer;
    procedure UpdateStatsAndVisuals;
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
    procedure RebuildBoundaryMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RebuildTetrahedralLattice;
    procedure ResetToRestState;
    procedure StepSimulation(const Dt: Single);
    procedure ApplyRadialImpactImpulse(const LocalOrigin: TVector3;
      const Radius: Single; const ImpulseVelocity: TVector3);
    function GetVertexPositionLocal(const AIndex: Integer): TVector3;
    function ComputeTetSignedVolume(const ATetIndex: Integer): Single;
    function TetSummaryBadge: String;
    property Stats: TTetSoftBodyStats read FStats;
  published
    property Preset: TTetSoftBodyPreset read FPreset write SetPreset default tsbpRubberBouncyCube;
    property CellsX: Integer read FCellsX write SetCellsX default 3;
    property CellsY: Integer read FCellsY write SetCellsY default 3;
    property CellsZ: Integer read FCellsZ write SetCellsZ default 3;
    property DropStartHeight: Single read FDropStartHeight write SetDropStartHeight {$ifdef FPC}default 1.80{$endif};
    property FloorLocalY: Single read FFloorLocalY write SetFloorLocalY {$ifdef FPC}default 0.0{$endif};
    property EdgeCompliance: Single read FEdgeCompliance write SetEdgeCompliance {$ifdef FPC}default 0.0008{$endif};
    property VolumeCompliance: Single read FVolumeCompliance write SetVolumeCompliance {$ifdef FPC}default 0.00005{$endif};
    property Damping: Single read FDamping write SetDamping {$ifdef FPC}default 1.20{$endif};
    property GravityY: Single read FGravityY write SetGravityY {$ifdef FPC}default -9.81{$endif};
    property Substeps: Integer read FSubsteps write SetSubsteps default 8;
    property PinTopFace: Boolean read FPinTopFace write SetPinTopFace default False;
    property ShowDeformableMesh: Boolean read FShowDeformableMesh write SetShowDeformableMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function TetPresetToString(const APreset: TTetSoftBodyPreset): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function TetPresetToString(const APreset: TTetSoftBodyPreset): String;
begin
  case APreset of
    tsbpCustom: Result := 'Custom XPBD Flesh';
    tsbpRubberBouncyCube: Result := 'Rubber Bouncy Cube (3x3x3)';
    tsbpGelatinJelloBlob: Result := 'Soft Gelatin Jello Blob';
    tsbpHangingFleshPillar: Result := 'Pinned Hanging Flesh Tendon';
    tsbpFirmMuscleBlock: Result := 'Firm Muscle Tissue Block';
  end;
end;

function SignedVolumeOf4(const P0, P1, P2, P3: TVector3): Single;
begin
  Result := TVector3.DotProduct(P1 - P0,
    TVector3.CrossProduct(P2 - P0, P3 - P0)) * (1.0 / 6.0);
end;

{ TCastleTetSoftBody --------------------------------------------------------- }

constructor TCastleTetSoftBody.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := tsbpRubberBouncyCube;
  FCellsX := 3;
  FCellsY := 3;
  FCellsZ := 3;
  FBodySize := Vector3(2.0, 2.0, 2.0);
  FDropStartHeight := 1.80;
  FFloorLocalY := 0.0;
  FEdgeCompliance := 0.0008;
  FVolumeCompliance := 0.00005;
  FDamping := 1.20;
  FGravityY := -9.81;
  FSubsteps := 8;
  FPinTopFace := False;
  FShowDeformableMesh := True;
  ApplyPresetParamsOnly(tsbpRubberBouncyCube);
  RebuildTetrahedralLattice;
end;

destructor TCastleTetSoftBody.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleTetSoftBody.ApplyPresetParamsOnly(const APreset: TTetSoftBodyPreset);
begin
  case APreset of
    tsbpRubberBouncyCube, tsbpCustom:
      begin
        FBodySize := Vector3(2.0, 2.0, 2.0);
        FDropStartHeight := 1.80;
        FEdgeCompliance := 0.0008;
        FVolumeCompliance := 0.00005;
        FDamping := 1.20;
        FPinTopFace := False;
      end;
    tsbpGelatinJelloBlob:
      begin
        FBodySize := Vector3(2.2, 1.8, 2.2);
        FDropStartHeight := 1.50;
        FEdgeCompliance := 0.0065;
        FVolumeCompliance := 0.00010;
        FDamping := 0.90;
        FPinTopFace := False;
      end;
    tsbpHangingFleshPillar:
      begin
        FBodySize := Vector3(1.4, 3.0, 1.4);
        FDropStartHeight := 3.60;
        FEdgeCompliance := 0.0025;
        FVolumeCompliance := 0.00008;
        FDamping := 1.40;
        FPinTopFace := True;
      end;
    tsbpFirmMuscleBlock:
      begin
        FBodySize := Vector3(2.4, 1.6, 1.8);
        FDropStartHeight := 1.20;
        FEdgeCompliance := 0.0002;
        FVolumeCompliance := 0.00002;
        FDamping := 1.80;
        FPinTopFace := False;
      end;
  end;
end;

procedure TCastleTetSoftBody.SetPreset(const AValue: TTetSoftBodyPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> tsbpCustom then
  begin
    ApplyPresetParamsOnly(AValue);
    RebuildTetrahedralLattice;
  end;
end;

procedure TCastleTetSoftBody.SetCellsX(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 1, 8);
  if FCellsX = V then Exit;
  FCellsX := V;
  RebuildTetrahedralLattice;
end;

procedure TCastleTetSoftBody.SetCellsY(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 1, 8);
  if FCellsY = V then Exit;
  FCellsY := V;
  RebuildTetrahedralLattice;
end;

procedure TCastleTetSoftBody.SetCellsZ(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 1, 8);
  if FCellsZ = V then Exit;
  FCellsZ := V;
  RebuildTetrahedralLattice;
end;

procedure TCastleTetSoftBody.SetDropStartHeight(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, -5.0, 20.0);
  if SameValue(FDropStartHeight, V, 1e-5) then Exit;
  FDropStartHeight := V;
  FPreset := tsbpCustom;
  RebuildTetrahedralLattice;
end;

procedure TCastleTetSoftBody.SetFloorLocalY(const AValue: Single);
begin
  FFloorLocalY := EnsureRange(AValue, -20.0, 20.0);
end;

procedure TCastleTetSoftBody.SetEdgeCompliance(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1.0);
  if SameValue(FEdgeCompliance, V, 1e-7) then Exit;
  FEdgeCompliance := V;
  FPreset := tsbpCustom;
end;

procedure TCastleTetSoftBody.SetVolumeCompliance(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 0.5);
  if SameValue(FVolumeCompliance, V, 1e-8) then Exit;
  FVolumeCompliance := V;
  FPreset := tsbpCustom;
end;

procedure TCastleTetSoftBody.SetDamping(const AValue: Single);
begin
  FDamping := EnsureRange(AValue, 0.0, 20.0);
end;

procedure TCastleTetSoftBody.SetGravityY(const AValue: Single);
begin
  FGravityY := EnsureRange(AValue, -50.0, 50.0);
end;

procedure TCastleTetSoftBody.SetSubsteps(const AValue: Integer);
begin
  FSubsteps := EnsureRange(AValue, 1, 32);
end;

procedure TCastleTetSoftBody.SetPinTopFace(const AValue: Boolean);
begin
  if FPinTopFace = AValue then Exit;
  FPinTopFace := AValue;
  FPreset := tsbpCustom;
  RebuildTetrahedralLattice;
end;

procedure TCastleTetSoftBody.SetShowDeformableMesh(const AValue: Boolean);
begin
  if FShowDeformableMesh = AValue then Exit;
  FShowDeformableMesh := AValue;
  if not FShowDeformableMesh then
    ClearTransientScene
  else
    RebuildBoundaryMesh;
end;

function TCastleTetSoftBody.GridIndex(const IX, IY, IZ: Integer): Integer;
begin
  Result := (IY * (FCellsZ + 1) + IZ) * (FCellsX + 1) + IX;
end;

procedure TCastleTetSoftBody.RebuildTetrahedralLattice;
var
  NX, NY, NZ, TotalV, IX, IY, IZ, VIdx, TetIdx: Integer;
  P: TVector3;
  C000, C100, C010, C110, C001, C101, C011, C111: Integer;

  procedure AddPositiveTet(A0, A1, A2, A3: Integer);
  var
    Vol: Single;
    Tmp: Integer;
  begin
    Vol := SignedVolumeOf4(FRestPositions[A0], FRestPositions[A1],
      FRestPositions[A2], FRestPositions[A3]);
    if Vol < 0.0 then
    begin
      Tmp := A2;
      A2 := A3;
      A3 := Tmp;
      Vol := -Vol;
    end;
    FTets[TetIdx].V0 := A0;
    FTets[TetIdx].V1 := A1;
    FTets[TetIdx].V2 := A2;
    FTets[TetIdx].V3 := A3;
    FTets[TetIdx].RestVolume := Max(1e-6, Vol);
    FTets[TetIdx].LastStrain := 0.0;
    Inc(TetIdx);
  end;

  procedure AddUniqueEdge(const U, V: Integer);
  var
    LoIdx, HiIdx, K: Integer;
  begin
    if U = V then Exit;
    if U < V then begin LoIdx := U; HiIdx := V; end
    else begin LoIdx := V; HiIdx := U; end;
    for K := 0 to High(FEdges) do
      if (FEdges[K].A = LoIdx) and (FEdges[K].B = HiIdx) then
        Exit;
    K := Length(FEdges);
    SetLength(FEdges, K + 1);
    FEdges[K].A := LoIdx;
    FEdges[K].B := HiIdx;
    FEdges[K].RestLength := PointsDistance(FRestPositions[LoIdx], FRestPositions[HiIdx]);
  end;

var
  K: Integer;
begin
  NX := FCellsX + 1;
  NY := FCellsY + 1;
  NZ := FCellsZ + 1;
  TotalV := NX * NY * NZ;
  SetLength(FPositions, TotalV);
  SetLength(FRestPositions, TotalV);
  SetLength(FVelocities, TotalV);
  SetLength(FInvMasses, TotalV);

  for IY := 0 to FCellsY do
    for IZ := 0 to FCellsZ do
      for IX := 0 to FCellsX do
      begin
        VIdx := GridIndex(IX, IY, IZ);
        P := Vector3(
          ((IX / FCellsX) - 0.5) * FBodySize.X,
          FDropStartHeight + (IY / FCellsY) * FBodySize.Y,
          ((IZ / FCellsZ) - 0.5) * FBodySize.Z);
        FRestPositions[VIdx] := P;
        FPositions[VIdx] := P;
        FVelocities[VIdx] := TVector3.Zero;
        if FPinTopFace and (IY = FCellsY) then
          FInvMasses[VIdx] := 0.0
        else
          FInvMasses[VIdx] := 1.0;
      end;

  SetLength(FTets, FCellsX * FCellsY * FCellsZ * 5);
  TetIdx := 0;
  for IY := 0 to FCellsY - 1 do
    for IZ := 0 to FCellsZ - 1 do
      for IX := 0 to FCellsX - 1 do
      begin
        C000 := GridIndex(IX, IY, IZ);
        C100 := GridIndex(IX + 1, IY, IZ);
        C010 := GridIndex(IX, IY + 1, IZ);
        C110 := GridIndex(IX + 1, IY + 1, IZ);
        C001 := GridIndex(IX, IY, IZ + 1);
        C101 := GridIndex(IX + 1, IY, IZ + 1);
        C011 := GridIndex(IX, IY + 1, IZ + 1);
        C111 := GridIndex(IX + 1, IY + 1, IZ + 1);

        if ((IX + IY + IZ) and 1) = 0 then
        begin
          AddPositiveTet(C000, C100, C010, C001);
          AddPositiveTet(C110, C010, C100, C111);
          AddPositiveTet(C101, C100, C111, C001);
          AddPositiveTet(C011, C010, C001, C111);
          AddPositiveTet(C100, C010, C001, C111);
        end else
        begin
          AddPositiveTet(C100, C000, C110, C101);
          AddPositiveTet(C010, C110, C000, C011);
          AddPositiveTet(C001, C000, C011, C101);
          AddPositiveTet(C111, C110, C101, C011);
          AddPositiveTet(C000, C110, C101, C011);
        end;
      end;

  SetLength(FEdges, 0);
  for K := 0 to High(FTets) do
  begin
    AddUniqueEdge(FTets[K].V0, FTets[K].V1);
    AddUniqueEdge(FTets[K].V0, FTets[K].V2);
    AddUniqueEdge(FTets[K].V0, FTets[K].V3);
    AddUniqueEdge(FTets[K].V1, FTets[K].V2);
    AddUniqueEdge(FTets[K].V1, FTets[K].V3);
    AddUniqueEdge(FTets[K].V2, FTets[K].V3);
  end;

  FStats.SimulationSteps := 0;
  UpdateStatsAndVisuals;
end;

procedure TCastleTetSoftBody.ResetToRestState;
var
  I: Integer;
begin
  for I := 0 to High(FPositions) do
  begin
    FPositions[I] := FRestPositions[I];
    FVelocities[I] := TVector3.Zero;
  end;
  FStats.SimulationSteps := 0;
  UpdateStatsAndVisuals;
end;

procedure TCastleTetSoftBody.StepSimulation(const Dt: Single);
var
  SubDt, AlphaEdge, AlphaVol, DampFactor, Len, CEdge, Denom, DLambda, CurVol, CVol: Single;
  PredPos: array of TVector3;
  Step, I, E, T, Iter: Integer;
  IA, IB, I0, I1, I2, I3: Integer;
  WA, WB, W0, W1, W2, W3: Single;
  Diff, Dir, G0, G1, G2, G3: TVector3;
begin
  if (Dt <= 0.0) or (Length(FPositions) = 0) then Exit;
  SubDt := Min(Dt, 0.05) / FSubsteps;
  if SubDt <= 1e-6 then Exit;

  SetLength(PredPos, Length(FPositions));
  AlphaEdge := FEdgeCompliance / Sqr(SubDt);
  AlphaVol := FVolumeCompliance / Sqr(SubDt);
  DampFactor := Max(0.0, 1.0 - FDamping * SubDt);

  for Step := 1 to FSubsteps do
  begin
    { 1. Predict particle positions under gravity }
    for I := 0 to High(FPositions) do
    begin
      if FInvMasses[I] > 0.0 then
      begin
        FVelocities[I].Y := FVelocities[I].Y + FGravityY * SubDt;
        FVelocities[I] := FVelocities[I] * DampFactor;
        PredPos[I] := FPositions[I] + FVelocities[I] * SubDt;
      end else
        PredPos[I] := FPositions[I];
    end;

    { 2. Gauss-Seidel XPBD edge + signed-volume 6V + floor projection }
    for Iter := 1 to 2 do
    begin
      for E := 0 to High(FEdges) do
      begin
        IA := FEdges[E].A;
        IB := FEdges[E].B;
        WA := FInvMasses[IA];
        WB := FInvMasses[IB];
        if WA + WB <= 0.0 then Continue;
        Diff := PredPos[IA] - PredPos[IB];
        Len := Diff.Length;
        if Len < 1e-7 then Continue;
        CEdge := Len - FEdges[E].RestLength;
        DLambda := -CEdge / (WA + WB + AlphaEdge);
        Dir := Diff * (1.0 / Len);
        PredPos[IA] := PredPos[IA] + Dir * (WA * DLambda);
        PredPos[IB] := PredPos[IB] - Dir * (WB * DLambda);
      end;

      for T := 0 to High(FTets) do
      begin
        I0 := FTets[T].V0;
        I1 := FTets[T].V1;
        I2 := FTets[T].V2;
        I3 := FTets[T].V3;
        W0 := FInvMasses[I0];
        W1 := FInvMasses[I1];
        W2 := FInvMasses[I2];
        W3 := FInvMasses[I3];
        if W0 + W1 + W2 + W3 <= 0.0 then Continue;

        G1 := TVector3.CrossProduct(PredPos[I2] - PredPos[I0], PredPos[I3] - PredPos[I0]) * (1.0 / 6.0);
        G2 := TVector3.CrossProduct(PredPos[I3] - PredPos[I0], PredPos[I1] - PredPos[I0]) * (1.0 / 6.0);
        G3 := TVector3.CrossProduct(PredPos[I1] - PredPos[I0], PredPos[I2] - PredPos[I0]) * (1.0 / 6.0);
        G0 := -(G1 + G2 + G3);

        CurVol := TVector3.DotProduct(PredPos[I1] - PredPos[I0], G1);
        CVol := CurVol - FTets[T].RestVolume;
        Denom := W0 * G0.LengthSqr + W1 * G1.LengthSqr +
                 W2 * G2.LengthSqr + W3 * G3.LengthSqr + AlphaVol;
        if Denom > 1e-12 then
        begin
          DLambda := -CVol / Denom;
          PredPos[I0] := PredPos[I0] + G0 * (W0 * DLambda);
          PredPos[I1] := PredPos[I1] + G1 * (W1 * DLambda);
          PredPos[I2] := PredPos[I2] + G2 * (W2 * DLambda);
          PredPos[I3] := PredPos[I3] + G3 * (W3 * DLambda);
        end;
      end;

      { Floor contact clamp with tangential friction }
      for I := 0 to High(PredPos) do
        if (FInvMasses[I] > 0.0) and (PredPos[I].Y < FFloorLocalY) then
        begin
          PredPos[I].Y := FFloorLocalY;
          PredPos[I].X := Lerp(0.25, PredPos[I].X, FPositions[I].X);
          PredPos[I].Z := Lerp(0.25, PredPos[I].Z, FPositions[I].Z);
        end;
    end;

    { 3. Finalize velocities & positions }
    for I := 0 to High(FPositions) do
    begin
      if FInvMasses[I] > 0.0 then
      begin
        FVelocities[I] := (PredPos[I] - FPositions[I]) * (1.0 / SubDt);
        FPositions[I] := PredPos[I];
      end;
    end;
  end;

  Inc(FStats.SimulationSteps);
  UpdateStatsAndVisuals;
end;

procedure TCastleTetSoftBody.ApplyRadialImpactImpulse(const LocalOrigin: TVector3;
  const Radius: Single; const ImpulseVelocity: TVector3);
var
  I: Integer;
  Dist, Weight: Single;
begin
  if Radius <= 0.01 then Exit;
  for I := 0 to High(FPositions) do
    if FInvMasses[I] > 0.0 then
    begin
      Dist := PointsDistance(FPositions[I], LocalOrigin);
      if Dist <= Radius then
      begin
        Weight := 1.0 - (Dist / Radius);
        FVelocities[I] := FVelocities[I] + ImpulseVelocity * Weight;
      end;
    end;
end;

function TCastleTetSoftBody.GetVertexPositionLocal(const AIndex: Integer): TVector3;
begin
  if (AIndex >= 0) and (AIndex < Length(FPositions)) then
    Result := FPositions[AIndex]
  else
    Result := TVector3.Zero;
end;

function TCastleTetSoftBody.ComputeTetSignedVolume(const ATetIndex: Integer): Single;
begin
  if (ATetIndex >= 0) and (ATetIndex < Length(FTets)) then
    Result := SignedVolumeOf4(
      FPositions[FTets[ATetIndex].V0],
      FPositions[FTets[ATetIndex].V1],
      FPositions[FTets[ATetIndex].V2],
      FPositions[FTets[ATetIndex].V3])
  else
    Result := 0.0;
end;

procedure TCastleTetSoftBody.UpdateStatsAndVisuals;
var
  I: Integer;
  V: Single;
begin
  FStats.VertexCount := Length(FPositions);
  FStats.TetrahedronCount := Length(FTets);
  FStats.EdgeCount := Length(FEdges);
  FStats.RestTotalVolume := 0.0;
  FStats.CurrentTotalVolume := 0.0;
  FStats.InvertedTetCount := 0;

  for I := 0 to High(FTets) do
  begin
    V := ComputeTetSignedVolume(I);
    FStats.RestTotalVolume := FStats.RestTotalVolume + FTets[I].RestVolume;
    FStats.CurrentTotalVolume := FStats.CurrentTotalVolume + V;
    if V <= 0.0 then
      Inc(FStats.InvertedTetCount);
    FTets[I].LastStrain := Abs(V - FTets[I].RestVolume) / Max(1e-6, FTets[I].RestVolume);
  end;

  if FStats.RestTotalVolume > 1e-6 then
    FStats.VolumeRatioPercent := 100.0 * (FStats.CurrentTotalVolume / FStats.RestTotalVolume)
  else
    FStats.VolumeRatioPercent := 100.0;

  if Length(FPositions) > 0 then
  begin
    FStats.MinVertexLocalY := FPositions[0].Y;
    FStats.MaxVertexLocalY := FPositions[0].Y;
    for I := 1 to High(FPositions) do
    begin
      if FPositions[I].Y < FStats.MinVertexLocalY then
        FStats.MinVertexLocalY := FPositions[I].Y;
      if FPositions[I].Y > FStats.MaxVertexLocalY then
        FStats.MaxVertexLocalY := FPositions[I].Y;
    end;
  end else
  begin
    FStats.MinVertexLocalY := 0.0;
    FStats.MaxVertexLocalY := 0.0;
  end;

  if FShowDeformableMesh then
    RebuildBoundaryMesh;
end;

procedure TCastleTetSoftBody.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientTetFleshMesh';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := Vector3(1, 1, 1);
  Mat.Roughness := 0.35;
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
  Add(FTransientScene);
end;

procedure TCastleTetSoftBody.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleTetSoftBody.RebuildBoundaryMesh;
var
  Verts, Cols: TVector3List;
  IX, IY, IZ: Integer;

  procedure EmitQuad(const A, B, C, D: Integer);
  var
    DispStrain: Single;
    Col: TVector3;
  begin
    DispStrain := EnsureRange(
      (PointsDistance(FPositions[A], FPositions[C]) - PointsDistance(FRestPositions[A], FRestPositions[C])) * 1.8,
      -1.0, 1.0);
    if DispStrain < 0.0 then
      Col := Lerp(-DispStrain, Vector3(0.24, 0.78, 0.66), Vector3(0.98, 0.36, 0.28))
    else
      Col := Lerp(DispStrain, Vector3(0.24, 0.78, 0.66), Vector3(0.98, 0.82, 0.24));

    Verts.Add(FPositions[A]); Verts.Add(FPositions[B]); Verts.Add(FPositions[C]);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
    Verts.Add(FPositions[A]); Verts.Add(FPositions[C]); Verts.Add(FPositions[D]);
    Cols.Add(Col); Cols.Add(Col); Cols.Add(Col);
  end;

begin
  if not FShowDeformableMesh then Exit;
  if Length(FPositions) = 0 then Exit;
  EnsureTransientScene;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    { -Y and +Y faces }
    for IZ := 0 to FCellsZ - 1 do
      for IX := 0 to FCellsX - 1 do
      begin
        EmitQuad(GridIndex(IX, 0, IZ), GridIndex(IX + 1, 0, IZ),
                 GridIndex(IX + 1, 0, IZ + 1), GridIndex(IX, 0, IZ + 1));
        EmitQuad(GridIndex(IX, FCellsY, IZ), GridIndex(IX, FCellsY, IZ + 1),
                 GridIndex(IX + 1, FCellsY, IZ + 1), GridIndex(IX + 1, FCellsY, IZ));
      end;

    { -Z and +Z faces }
    for IY := 0 to FCellsY - 1 do
      for IX := 0 to FCellsX - 1 do
      begin
        EmitQuad(GridIndex(IX, IY, 0), GridIndex(IX, IY + 1, 0),
                 GridIndex(IX + 1, IY + 1, 0), GridIndex(IX + 1, IY, 0));
        EmitQuad(GridIndex(IX, IY, FCellsZ), GridIndex(IX + 1, IY, FCellsZ),
                 GridIndex(IX + 1, IY + 1, FCellsZ), GridIndex(IX, IY + 1, FCellsZ));
      end;

    { -X and +X faces }
    for IY := 0 to FCellsY - 1 do
      for IZ := 0 to FCellsZ - 1 do
      begin
        EmitQuad(GridIndex(0, IY, IZ), GridIndex(0, IY, IZ + 1),
                 GridIndex(0, IY + 1, IZ + 1), GridIndex(0, IY + 1, IZ));
        EmitQuad(GridIndex(FCellsX, IY, IZ), GridIndex(FCellsX, IY + 1, IZ),
                 GridIndex(FCellsX, IY + 1, IZ + 1), GridIndex(FCellsX, IY, IZ + 1));
      end;

    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleTetSoftBody.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('cx', FCellsX);
    Obj.Add('cy', FCellsY);
    Obj.Add('cz', FCellsZ);
    Obj.Add('sx', FBodySize.X);
    Obj.Add('sy', FBodySize.Y);
    Obj.Add('sz', FBodySize.Z);
    Obj.Add('dropH', FDropStartHeight);
    Obj.Add('edgeComp', FEdgeCompliance);
    Obj.Add('volComp', FVolumeCompliance);
    Obj.Add('pinTop', FPinTopFace);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleTetSoftBody.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      PresetOrd := Obj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TTetSoftBodyPreset))) and
         (PresetOrd <= Ord(High(TTetSoftBodyPreset))) then
        FPreset := TTetSoftBodyPreset(PresetOrd);
      FCellsX := EnsureRange(Obj.Get('cx', FCellsX), 1, 8);
      FCellsY := EnsureRange(Obj.Get('cy', FCellsY), 1, 8);
      FCellsZ := EnsureRange(Obj.Get('cz', FCellsZ), 1, 8);
      FBodySize.X := EnsureRange(Obj.Get('sx', FBodySize.X), 0.2, 20.0);
      FBodySize.Y := EnsureRange(Obj.Get('sy', FBodySize.Y), 0.2, 20.0);
      FBodySize.Z := EnsureRange(Obj.Get('sz', FBodySize.Z), 0.2, 20.0);
      FDropStartHeight := EnsureRange(Obj.Get('dropH', FDropStartHeight), -5.0, 20.0);
      FEdgeCompliance := EnsureRange(Obj.Get('edgeComp', FEdgeCompliance), 0.0, 1.0);
      FVolumeCompliance := EnsureRange(Obj.Get('volComp', FVolumeCompliance), 0.0, 0.5);
      FPinTopFace := Obj.Get('pinTop', FPinTopFace);
      RebuildTetrahedralLattice;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleTetSoftBody.TetSummaryBadge: String;
begin
  Result := Format('[TetFlesh:%dt Vol=%.1f%% Inv=%d]', [
    FStats.TetrahedronCount,
    FStats.VolumeRatioPercent,
    FStats.InvertedTetCount]);
end;

initialization
  RegisterSerializableComponent(TCastleTetSoftBody, ['Physics', 'Chaos Flesh Tetrahedral Soft-Body (XPBD)']);
end.
