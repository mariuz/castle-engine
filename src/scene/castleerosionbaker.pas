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

{ Landscape geological Thermal Talus & Lagrangian Raindrop Hydraulic Erosion
  heightfield solver, alluvial sediment & flow-channel accumulator, and
  4-channel RGBA partition-of-unity splatmap baker
  (Phase 340 — Unreal Engine 6.0+ Landscape Hydro/Thermal Erosion parity). }
unit CastleErosionBaker;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleImages, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Base geological landform presets before erosion. }
  TErosionTerrainPreset = (
    etpAlpineVolcanicCone,
    etpMesaPlateauEscarpment,
    etpTwinRidgesValley
  );

  { Procedural terrain erosion component supporting mass-conserving thermal
    talus slumping, Lagrangian raindrop hydraulic gully carving, 4-channel
    RGBA splatmap baking, and csTransient vertex-colored 3D terrain preview. }
  TCastleTerrainErosionBaker = class(TCastleTransform)
  private
    FPreset: TErosionTerrainPreset;
    FGridSize: Integer;
    FCellSpacingMeters: Single;
    FTalusAngleDeg: Single;
    FThermalTransferRate: Single;
    FErosionRate: Single;
    FDepositionRate: Single;
    FDropletInertia: Single;
    FRandomSeed: Integer;

    FHeight: array of Single;
    FSedimentAcc: array of Single;
    FFlowAcc: array of Single;
    FThermalPassesRun: Integer;
    FDropletsSimulated: Integer;
    FTotalErodedMeters: Double;
    FTotalDepositedMeters: Double;
    FGeneratedTriangleCount: Integer;
    FTransientScene: TCastleScene;

    procedure SetPreset(const AValue: TErosionTerrainPreset);
    procedure SetGridSize(const AValue: Integer);
    procedure SetCellSpacingMeters(const AValue: Single);
    procedure SetTalusAngleDeg(const AValue: Single);
    procedure SetThermalTransferRate(const AValue: Single);
    procedure SetErosionRate(const AValue: Single);
    procedure SetDepositionRate(const AValue: Single);
    procedure SetDropletInertia(const AValue: Single);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);

    function CellIdx(const AX, AZ: Integer): Integer; inline;
    procedure SampleBilinearHeightAndGrad(const PosX, PosZ: Single;
      out AHeight, AGradX, AGradZ: Single);
    procedure RebuildTerrainPreviewMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Reset heightfield to raw un-eroded geological preset. }
    procedure ResetHeightfieldToPreset;

    { Run exact mass-conserving Olsen thermal talus repose slumping steps. }
    procedure RunThermalErosionSteps(const AIterations: Integer = 15);

    { Simulate seeded Lagrangian raindrops carving downhill gullies and
      depositing alluvial sediment aprons. }
    procedure RunHydraulicDroplets(const ADropletCount: Integer = 1500);

    { Bake a 4-channel RGBA splatmap (R=Grass, G=CliffRock, B=Sediment, A=Flow)
      normalized to R + G + B + A = 255 at every texel. Caller owns result. }
    function ExportSplatmapRgbaImage: TRGBAlphaImage;

    function SampleHeight(const AX, AZ: Integer): Single;
    function SampleSediment(const AX, AZ: Integer): Single;
    function SampleFlow(const AX, AZ: Integer): Single;
    function TotalTerrainVolume: Double;
    function PeakElevation: Single;
    function MaxSlopeAngleDeg: Single;
    function ErosionSummaryBadge: String;

    property ThermalPassesRun: Integer read FThermalPassesRun;
    property DropletsSimulated: Integer read FDropletsSimulated;
    property TotalErodedMeters: Double read FTotalErodedMeters;
    property TotalDepositedMeters: Double read FTotalDepositedMeters;
    property GeneratedTriangleCount: Integer read FGeneratedTriangleCount;
  published
    property Preset: TErosionTerrainPreset read FPreset write SetPreset default etpAlpineVolcanicCone;
    property GridSize: Integer read FGridSize write SetGridSize default 48;
    property CellSpacingMeters: Single read FCellSpacingMeters write SetCellSpacingMeters {$ifdef FPC}default 1.25{$endif};
    property TalusAngleDeg: Single read FTalusAngleDeg write SetTalusAngleDeg {$ifdef FPC}default 34.0{$endif};
    property ThermalTransferRate: Single read FThermalTransferRate write SetThermalTransferRate {$ifdef FPC}default 0.42{$endif};
    property ErosionRate: Single read FErosionRate write SetErosionRate {$ifdef FPC}default 0.30{$endif};
    property DepositionRate: Single read FDepositionRate write SetDepositionRate {$ifdef FPC}default 0.30{$endif};
    property DropletInertia: Single read FDropletInertia write SetDropletInertia {$ifdef FPC}default 0.15{$endif};
    property RandomSeed: Integer read FRandomSeed write FRandomSeed default 4040;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

function ErosionPresetToDisplayName(const APreset: TErosionTerrainPreset): String;

implementation

uses
  fpjson, jsonparser,
  CastleComponentSerialize;

function ErosionPresetToDisplayName(const APreset: TErosionTerrainPreset): String;
begin
  case APreset of
    etpAlpineVolcanicCone:    Result := 'Alpine Volcanic Cone';
    etpMesaPlateauEscarpment: Result := 'Steep Mesa Escarpment';
    etpTwinRidgesValley:      Result := 'Twin Ridges River Valley';
  end;
end;

{$PUSH}{$Q-}{$R-}
function NextXorFloat01(var State: Cardinal): Single;
begin
  if State = 0 then
    State := 987654321;
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := (State and $FFFF) / 65535.0;
end;
{$POP}

{ TCastleTerrainErosionBaker ------------------------------------------------- }

constructor TCastleTerrainErosionBaker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := etpAlpineVolcanicCone;
  FGridSize := 48;
  FCellSpacingMeters := 1.25;
  FTalusAngleDeg := 34.0;
  FThermalTransferRate := 0.42;
  FErosionRate := 0.30;
  FDepositionRate := 0.30;
  FDropletInertia := 0.15;
  FRandomSeed := 4040;
  ResetHeightfieldToPreset;
end;

destructor TCastleTerrainErosionBaker.Destroy;
begin
  FreeAndNil(FTransientScene);
  SetLength(FHeight, 0);
  SetLength(FSedimentAcc, 0);
  SetLength(FFlowAcc, 0);
  inherited Destroy;
end;

function TCastleTerrainErosionBaker.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'GridSize', 'CellSpacingMeters', 'TalusAngleDeg',
       'ThermalTransferRate', 'ErosionRate', 'DepositionRate',
       'DropletInertia', 'RandomSeed', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleTerrainErosionBaker.CellIdx(const AX, AZ: Integer): Integer;
begin
  Result := AZ * FGridSize + AX;
end;

procedure TCastleTerrainErosionBaker.SetPreset(const AValue: TErosionTerrainPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  ResetHeightfieldToPreset;
end;

procedure TCastleTerrainErosionBaker.SetGridSize(const AValue: Integer);
var
  ClampedN: Integer;
begin
  ClampedN := EnsureRange(AValue, 16, 128);
  if ClampedN = FGridSize then Exit;
  FGridSize := ClampedN;
  ResetHeightfieldToPreset;
end;

procedure TCastleTerrainErosionBaker.SetCellSpacingMeters(const AValue: Single);
begin
  FCellSpacingMeters := Max(0.25, AValue);
end;

procedure TCastleTerrainErosionBaker.SetTalusAngleDeg(const AValue: Single);
begin
  FTalusAngleDeg := EnsureRange(AValue, 10.0, 80.0);
end;

procedure TCastleTerrainErosionBaker.SetThermalTransferRate(const AValue: Single);
begin
  FThermalTransferRate := EnsureRange(AValue, 0.05, 0.50);
end;

procedure TCastleTerrainErosionBaker.SetErosionRate(const AValue: Single);
begin
  FErosionRate := EnsureRange(AValue, 0.02, 0.90);
end;

procedure TCastleTerrainErosionBaker.SetDepositionRate(const AValue: Single);
begin
  FDepositionRate := EnsureRange(AValue, 0.02, 0.90);
end;

procedure TCastleTerrainErosionBaker.SetDropletInertia(const AValue: Single);
begin
  FDropletInertia := EnsureRange(AValue, 0.0, 0.95);
end;

procedure TCastleTerrainErosionBaker.ResetHeightfieldToPreset;
var
  X, Z, N, TotalCells: Integer;
  U, V, Dx, Dz, R, H, RidgeWave: Single;
begin
  N := FGridSize;
  TotalCells := N * N;
  SetLength(FHeight, TotalCells);
  SetLength(FSedimentAcc, TotalCells);
  SetLength(FFlowAcc, TotalCells);
  FThermalPassesRun := 0;
  FDropletsSimulated := 0;
  FTotalErodedMeters := 0.0;
  FTotalDepositedMeters := 0.0;

  for Z := 0 to N - 1 do
    for X := 0 to N - 1 do
    begin
      U := (X / Single(N - 1)) * 2.0 - 1.0;
      V := (Z / Single(N - 1)) * 2.0 - 1.0;
      Dx := U;
      Dz := V;
      R := Sqrt(Dx * Dx + Dz * Dz);
      RidgeWave := 0.85 * Sin(U * 6.5) * Cos(V * 5.5) + 0.45 * Sin((U + V) * 11.0);

      case FPreset of
        etpAlpineVolcanicCone:
          begin
            H := Max(0.0, (1.05 - R) * 18.5) + RidgeWave * Max(0.15, 1.0 - R);
          end;
        etpMesaPlateauEscarpment:
          begin
            { Steep vertical mesa step with sharp cliff rim > 75 deg }
            if R < 0.42 then
              H := 15.0 + 0.35 * RidgeWave
            else if R < 0.47 then
              H := Lerp((R - 0.42) / 0.05, 15.0, 2.0)
            else
              H := Max(0.0, 2.0 - (R - 0.47) * 2.2);
          end;
        etpTwinRidgesValley:
          begin
            H := 3.0 + 11.5 * Abs(U) + 1.8 * (1.0 - V) + 0.65 * RidgeWave;
          end;
      end;

      FHeight[CellIdx(X, Z)] := Max(0.0, H);
      FSedimentAcc[CellIdx(X, Z)] := 0.0;
      FFlowAcc[CellIdx(X, Z)] := 0.0;
    end;

  RebuildTerrainPreviewMesh;
end;

procedure TCastleTerrainErosionBaker.RunThermalErosionSteps(
  const AIterations: Integer);
const
  OffX: array[0..3] of Integer = (1, -1, 0, 0);
  OffZ: array[0..3] of Integer = (0, 0, 1, -1);
var
  DeltaBuf: array of Double;
  Pass, X, Z, K, Nx, Nz, N, Idx, NIdx: Integer;
  MaxDelta, Diff, ExcessSum, MoveTotal, Share: Double;
  LowerDiffs: array[0..3] of Double;
begin
  N := FGridSize;
  if (N < 4) or (AIterations <= 0) then
    Exit;
  SetLength(DeltaBuf, N * N);
  MaxDelta := FCellSpacingMeters * Tan(DegToRad(FTalusAngleDeg));

  for Pass := 1 to AIterations do
  begin
    for Idx := 0 to High(DeltaBuf) do
      DeltaBuf[Idx] := 0.0;

    for Z := 0 to N - 1 do
      for X := 0 to N - 1 do
      begin
        Idx := CellIdx(X, Z);
        ExcessSum := 0.0;
        for K := 0 to 3 do
        begin
          LowerDiffs[K] := 0.0;
          Nx := X + OffX[K];
          Nz := Z + OffZ[K];
          if (Nx < 0) or (Nx >= N) or (Nz < 0) or (Nz >= N) then
            Continue;
          Diff := Double(FHeight[Idx]) - Double(FHeight[CellIdx(Nx, Nz)]);
          if Diff > MaxDelta then
          begin
            LowerDiffs[K] := Diff - MaxDelta;
            ExcessSum := ExcessSum + LowerDiffs[K];
          end;
        end;

        if ExcessSum > 1e-6 then
        begin
          { Symmetric conservative flux: subtract from (X,Z) and add exact same sum to neighbors }
          MoveTotal := FThermalTransferRate * 0.5 * (ExcessSum / 4.0) * 2.0;
          MoveTotal := Min(MoveTotal, ExcessSum * 0.45);
          DeltaBuf[Idx] := DeltaBuf[Idx] - MoveTotal;
          FTotalErodedMeters := FTotalErodedMeters + MoveTotal;

          for K := 0 to 3 do
            if LowerDiffs[K] > 0.0 then
            begin
              Share := MoveTotal * (LowerDiffs[K] / ExcessSum);
              NIdx := CellIdx(X + OffX[K], Z + OffZ[K]);
              DeltaBuf[NIdx] := DeltaBuf[NIdx] + Share;
              FSedimentAcc[NIdx] := FSedimentAcc[NIdx] + Share;
              FTotalDepositedMeters := FTotalDepositedMeters + Share;
            end;
        end;
      end;

    for Idx := 0 to High(FHeight) do
      FHeight[Idx] := FHeight[Idx] + Single(DeltaBuf[Idx]);
    Inc(FThermalPassesRun);
  end;

  RebuildTerrainPreviewMesh;
end;

procedure TCastleTerrainErosionBaker.SampleBilinearHeightAndGrad(
  const PosX, PosZ: Single; out AHeight, AGradX, AGradZ: Single);
var
  X0, Z0, X1, Z1: Integer;
  Fx, Fz, H00, H10, H01, H11: Single;
begin
  X0 := EnsureRange(Floor(PosX), 0, FGridSize - 2);
  Z0 := EnsureRange(Floor(PosZ), 0, FGridSize - 2);
  X1 := X0 + 1;
  Z1 := Z0 + 1;
  Fx := EnsureRange(PosX - X0, 0.0, 1.0);
  Fz := EnsureRange(PosZ - Z0, 0.0, 1.0);

  H00 := FHeight[CellIdx(X0, Z0)];
  H10 := FHeight[CellIdx(X1, Z0)];
  H01 := FHeight[CellIdx(X0, Z1)];
  H11 := FHeight[CellIdx(X1, Z1)];

  AGradX := (H10 - H00) * (1.0 - Fz) + (H11 - H01) * Fz;
  AGradZ := (H01 - H00) * (1.0 - Fx) + (H11 - H10) * Fx;
  AHeight := H00 * (1.0 - Fx) * (1.0 - Fz)
           + H10 * Fx * (1.0 - Fz)
           + H01 * (1.0 - Fx) * Fz
           + H11 * Fx * Fz;
end;

procedure TCastleTerrainErosionBaker.RunHydraulicDroplets(
  const ADropletCount: Integer);
const
  MaxDropletSteps = 48;
  CapacityFactor = 3.6;
  MinSlopeCapacity = 0.01;
var
  Rng: Cardinal;
  D, Step, N, X0, Z0: Integer;
  Px, Pz, DirX, DirZ, DirLen, HOld, HNew, Gx, Gz, Dh,
  Speed, Water, Sediment, Cap, Amount, Fx, Fz, W00, W10, W01, W11: Single;

  procedure DepositBilinear(const CellX, CellZ: Integer; const FracX, FracZ, Val: Single);
  begin
    W00 := (1.0 - FracX) * (1.0 - FracZ);
    W10 := FracX * (1.0 - FracZ);
    W01 := (1.0 - FracX) * FracZ;
    W11 := FracX * FracZ;
    FHeight[CellIdx(CellX, CellZ)]         := FHeight[CellIdx(CellX, CellZ)] + Val * W00;
    FHeight[CellIdx(CellX + 1, CellZ)]     := FHeight[CellIdx(CellX + 1, CellZ)] + Val * W10;
    FHeight[CellIdx(CellX, CellZ + 1)]     := FHeight[CellIdx(CellX, CellZ + 1)] + Val * W01;
    FHeight[CellIdx(CellX + 1, CellZ + 1)] := FHeight[CellIdx(CellX + 1, CellZ + 1)] + Val * W11;

    if Val > 0.0 then
    begin
      FSedimentAcc[CellIdx(CellX, CellZ)]         := FSedimentAcc[CellIdx(CellX, CellZ)] + Val * W00;
      FSedimentAcc[CellIdx(CellX + 1, CellZ)]     := FSedimentAcc[CellIdx(CellX + 1, CellZ)] + Val * W10;
      FSedimentAcc[CellIdx(CellX, CellZ + 1)]     := FSedimentAcc[CellIdx(CellX, CellZ + 1)] + Val * W01;
      FSedimentAcc[CellIdx(CellX + 1, CellZ + 1)] := FSedimentAcc[CellIdx(CellX + 1, CellZ + 1)] + Val * W11;
      FTotalDepositedMeters := FTotalDepositedMeters + Val;
    end else
      FTotalErodedMeters := FTotalErodedMeters + Abs(Val);
  end;

begin
  N := FGridSize;
  if (N < 6) or (ADropletCount <= 0) then
    Exit;

  {$PUSH}{$Q-}{$R-}
  Rng := Cardinal((UInt64(Cardinal(Abs(Int64(FRandomSeed) + Int64(FDropletsSimulated)))) * UInt64(747796405) + UInt64(2891336453)) and $FFFFFFFF);
  {$POP}

  for D := 1 to ADropletCount do
  begin
    Px := 1.5 + NextXorFloat01(Rng) * (N - 4.0);
    Pz := 1.5 + NextXorFloat01(Rng) * (N - 4.0);
    DirX := 0.0;
    DirZ := 0.0;
    Speed := 1.0;
    Water := 1.0;
    Sediment := 0.0;

    for Step := 1 to MaxDropletSteps do
    begin
      X0 := EnsureRange(Floor(Px), 0, N - 2);
      Z0 := EnsureRange(Floor(Pz), 0, N - 2);
      Fx := EnsureRange(Px - X0, 0.0, 1.0);
      Fz := EnsureRange(Pz - Z0, 0.0, 1.0);

      SampleBilinearHeightAndGrad(Px, Pz, HOld, Gx, Gz);
      FFlowAcc[CellIdx(X0, Z0)] := FFlowAcc[CellIdx(X0, Z0)] + Water * 0.25;

      DirX := DirX * FDropletInertia - Gx * (1.0 - FDropletInertia);
      DirZ := DirZ * FDropletInertia - Gz * (1.0 - FDropletInertia);
      DirLen := Sqrt(DirX * DirX + DirZ * DirZ);
      if DirLen < 1e-5 then
        Break;
      DirX := DirX / DirLen;
      DirZ := DirZ / DirLen;

      Px := Px + DirX;
      Pz := Pz + DirZ;
      if (Px < 1.0) or (Px >= N - 2.0) or (Pz < 1.0) or (Pz >= N - 2.0) then
        Break;

      SampleBilinearHeightAndGrad(Px, Pz, HNew, Gx, Gz);
      Dh := HNew - HOld;

      if Dh > 0.0 then
      begin
        { Uphill pit: deposit sediment up to Dh }
        Amount := Min(Dh, Sediment);
        DepositBilinear(X0, Z0, Fx, Fz, Amount);
        Sediment := Sediment - Amount;
      end else
      begin
        Cap := Max(-Dh, MinSlopeCapacity) * Speed * Water * CapacityFactor;
        if Sediment > Cap then
        begin
          Amount := (Sediment - Cap) * FDepositionRate;
          DepositBilinear(X0, Z0, Fx, Fz, Amount);
          Sediment := Sediment - Amount;
        end else
        begin
          Amount := Min((Cap - Sediment) * FErosionRate, -Dh);
          DepositBilinear(X0, Z0, Fx, Fz, -Amount);
          Sediment := Sediment + Amount;
        end;
      end;

      Speed := Sqrt(Max(0.05, Speed * Speed - Dh * 4.0));
      Water := Water * 0.96;
    end;

    { Return any remaining suspended sediment to final resting cell to conserve mass }
    if Sediment > 1e-6 then
    begin
      X0 := EnsureRange(Floor(Px), 0, N - 2);
      Z0 := EnsureRange(Floor(Pz), 0, N - 2);
      DepositBilinear(X0, Z0, 0.5, 0.5, Sediment);
    end;
    Inc(FDropletsSimulated);
  end;

  RebuildTerrainPreviewMesh;
end;

function TCastleTerrainErosionBaker.ExportSplatmapRgbaImage: TRGBAlphaImage;
var
  X, Z, N: Integer;
  SlopeDeg, SedW, FlowW, RockW, GrassW, SumW: Single;
  Gx, Gz: Single;
  Pix: PVector4Byte;
  R, G, B, A: Integer;
begin
  N := FGridSize;
  Result := TRGBAlphaImage.Create(N, N);
  for Z := 0 to N - 1 do
    for X := 0 to N - 1 do
    begin
      Gx := (SampleHeight(Min(N - 1, X + 1), Z) - SampleHeight(Max(0, X - 1), Z)) /
            (2.0 * FCellSpacingMeters);
      Gz := (SampleHeight(X, Min(N - 1, Z + 1)) - SampleHeight(X, Max(0, Z - 1))) /
            (2.0 * FCellSpacingMeters);
      SlopeDeg := RadToDeg(ArcTan(Sqrt(Gx * Gx + Gz * Gz)));

      RockW  := EnsureRange((SlopeDeg - 22.0) / 28.0, 0.0, 1.0);
      SedW   := EnsureRange(SampleSediment(X, Z) * 2.8, 0.0, 1.0);
      FlowW  := EnsureRange(SampleFlow(X, Z) * 0.45, 0.0, 1.0);
      GrassW := Max(0.05, 1.0 - Max(RockW, Max(SedW, FlowW)));

      SumW := GrassW + RockW + SedW + FlowW;
      R := EnsureRange(Round(255.0 * (GrassW / SumW)), 0, 255);
      G := EnsureRange(Round(255.0 * (RockW / SumW)), 0, 255 - R);
      B := EnsureRange(Round(255.0 * (SedW / SumW)), 0, 255 - R - G);
      A := 255 - R - G - B;

      Pix := Result.PixelPtr(X, Z);
      Pix^ := Vector4Byte(Byte(R), Byte(G), Byte(B), Byte(A));
    end;
end;

procedure TCastleTerrainErosionBaker.RebuildTerrainPreviewMesh;
var
  RootNode: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
  Coord: TCoordinateNode;
  ColorNode: TColorNode;
  Verts, Colors: TVector3List;
  X, Z, N: Integer;
  HalfSpan: Single;

  function VertexPos(const GX, GZ: Integer): TVector3;
  begin
    Result := Vector3(
      GX * FCellSpacingMeters - HalfSpan,
      SampleHeight(GX, GZ),
      GZ * FCellSpacingMeters - HalfSpan);
  end;

  function VertexCol(const GX, GZ: Integer): TVector3;
  var
    Sed, Flw, H: Single;
  begin
    H := SampleHeight(GX, GZ);
    Sed := EnsureRange(SampleSediment(GX, GZ) * 2.2, 0.0, 1.0);
    Flw := EnsureRange(SampleFlow(GX, GZ) * 0.35, 0.0, 1.0);
    if H > 12.5 then
      Result := Vector3(0.72, 0.70, 0.68)
    else
      Result := Vector3(0.34, 0.56, 0.30);
    Result := Lerp(Sed, Result, Vector3(0.76, 0.64, 0.42));
    Result := Lerp(Flw, Result, Vector3(0.24, 0.50, 0.72));
  end;

var
  P00, P10, P11, P01, C00, C10, C11, C01: TVector3;
begin
  FreeAndNil(FTransientScene);
  N := FGridSize;
  if N < 2 then Exit;
  HalfSpan := 0.5 * (N - 1) * FCellSpacingMeters;

  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientErosionTerrainMesh';
  FTransientScene.PreciseCollisions := True;
  FTransientScene.Pickable := False;

  RootNode := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.Roughness := 0.88;
  Mat.Metallic := 0.02;
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  Coord := TCoordinateNode.Create;
  ColorNode := TColorNode.Create;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    Verts.Capacity := (N - 1) * (N - 1) * 6;
    Colors.Capacity := (N - 1) * (N - 1) * 6;
    for Z := 0 to N - 2 do
      for X := 0 to N - 2 do
      begin
        P00 := VertexPos(X, Z);     C00 := VertexCol(X, Z);
        P10 := VertexPos(X + 1, Z); C10 := VertexCol(X + 1, Z);
        P11 := VertexPos(X + 1, Z + 1); C11 := VertexCol(X + 1, Z + 1);
        P01 := VertexPos(X, Z + 1); C01 := VertexCol(X, Z + 1);

        Verts.Add(P00); Verts.Add(P01); Verts.Add(P11);
        Colors.Add(C00); Colors.Add(C01); Colors.Add(C11);

        Verts.Add(P00); Verts.Add(P11); Verts.Add(P10);
        Colors.Add(C00); Colors.Add(C11); Colors.Add(C10);
      end;
    Coord.SetPoint(Verts);
    ColorNode.SetColor(Colors);
    FGeneratedTriangleCount := Verts.Count div 3;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;

  TriSet.Coord := Coord;
  TriSet.Color := ColorNode;
  Shape.Geometry := TriSet;
  RootNode.AddChildren(Shape);
  FTransientScene.Load(RootNode, True);
  Add(FTransientScene);
end;

function TCastleTerrainErosionBaker.SampleHeight(const AX, AZ: Integer): Single;
begin
  if (AX >= 0) and (AX < FGridSize) and (AZ >= 0) and (AZ < FGridSize) then
    Result := FHeight[CellIdx(AX, AZ)]
  else
    Result := 0.0;
end;

function TCastleTerrainErosionBaker.SampleSediment(const AX, AZ: Integer): Single;
begin
  if (AX >= 0) and (AX < FGridSize) and (AZ >= 0) and (AZ < FGridSize) then
    Result := FSedimentAcc[CellIdx(AX, AZ)]
  else
    Result := 0.0;
end;

function TCastleTerrainErosionBaker.SampleFlow(const AX, AZ: Integer): Single;
begin
  if (AX >= 0) and (AX < FGridSize) and (AZ >= 0) and (AZ < FGridSize) then
    Result := FFlowAcc[CellIdx(AX, AZ)]
  else
    Result := 0.0;
end;

function TCastleTerrainErosionBaker.TotalTerrainVolume: Double;
var
  I: Integer;
  CellArea: Double;
begin
  Result := 0.0;
  CellArea := FCellSpacingMeters * FCellSpacingMeters;
  for I := 0 to High(FHeight) do
    Result := Result + Double(FHeight[I]) * CellArea;
end;

function TCastleTerrainErosionBaker.PeakElevation: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FHeight) do
    if FHeight[I] > Result then
      Result := FHeight[I];
end;

function TCastleTerrainErosionBaker.MaxSlopeAngleDeg: Single;
var
  X, Z: Integer;
  DhX, DhZ, Slope: Single;
begin
  Result := 0.0;
  for Z := 0 to FGridSize - 2 do
    for X := 0 to FGridSize - 2 do
    begin
      DhX := Abs(SampleHeight(X + 1, Z) - SampleHeight(X, Z)) / FCellSpacingMeters;
      DhZ := Abs(SampleHeight(X, Z + 1) - SampleHeight(X, Z)) / FCellSpacingMeters;
      Slope := RadToDeg(ArcTan(Max(DhX, DhZ)));
      if Slope > Result then
        Result := Slope;
    end;
end;

function TCastleTerrainErosionBaker.ErosionSummaryBadge: String;
begin
  Result := Format('[Erosion:%dx%d Therm=%d Drops=%d MaxSlope=%.1f°]', [
    FGridSize, FGridSize, FThermalPassesRun, FDropletsSimulated, MaxSlopeAngleDeg
  ]);
end;

function TCastleTerrainErosionBaker.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('gridSize', FGridSize);
    Obj.Add('thermalPasses', FThermalPassesRun);
    Obj.Add('droplets', FDropletsSimulated);
    Obj.Add('seed', FRandomSeed);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleTerrainErosionBaker.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  PresetOrd, SavedTherm, SavedDrops: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Data := nil;
    end;
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    PresetOrd := Obj.Get('preset', Ord(FPreset));
    if (PresetOrd >= Ord(Low(TErosionTerrainPreset))) and
       (PresetOrd <= Ord(High(TErosionTerrainPreset))) then
      FPreset := TErosionTerrainPreset(PresetOrd);
    FGridSize := EnsureRange(Obj.Get('gridSize', FGridSize), 16, 128);
    FRandomSeed := Obj.Get('seed', FRandomSeed);
    ResetHeightfieldToPreset;
    SavedTherm := Obj.Get('thermalPasses', 0);
    SavedDrops := Obj.Get('droplets', 0);
    if SavedTherm > 0 then
      RunThermalErosionSteps(Min(SavedTherm, 50));
    if SavedDrops > 0 then
      RunHydraulicDroplets(Min(SavedDrops, 5000));
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleTerrainErosionBaker,
    ['World & Crowds', 'Landscape Thermal & Hydraulic Erosion Baker (TCastleTerrainErosionBaker)']);

end.
