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

{ 2.5D Shallow-Water Virtual-Pipe Hydrostatic Fluid Solver, Terrain-Conforming
  Waterfall/Basin Pooling, Spring/Drain Sources, Turbulent Foam & Wetness Map
  Runtime (@link(TCastleShallowFluidSurface))
  (Phase 330 — UE 6.0+ Niagara Grid2D Shallow Water & Water 2.0 Parity). }
unit CastleShallowFluid;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform, CastleScene, X3DNodes;

type
  { Built-in 2.5D Shallow-Water hydrological presets. }
  TShallowFluidPreset = (
    sfpCustom,
    sfpTerracedWaterfallPools,
    sfpCraterLakeDamBreak,
    sfpCanyonRiverRapids
  );

  { Localized water springemitter (>0 m^3/s) or sinkhole drain (<0 m^3/s). }
  TFluidSpringSource = record
    LocalX: Single;
    LocalZ: Single;
    FlowRateM3PerSec: Single;
    Radius: Single;
    Enabled: Boolean;
  end;
  TFluidSpringSourceArray = array of TFluidSpringSource;

  { Per-cell hydrological telemetry sample. }
  TFluidCellSample = record
    TerrainHeight: Single;
    WaterDepth: Single;
    SurfaceElevation: Single;
    VelX: Single;
    VelZ: Single;
    Foam: Single;
    Wetness: Single;
  end;

  { 2.5D Virtual-Pipe Hydrostatic Shallow-Water fluid simulation surface
    (@link(TCastleTransform)) conserving water volume across arbitrary terrain
    heights, waterfalls, springs, rain, and basins. }
  TCastleShallowFluidSurface = class(TCastleTransform)
  public
    const
      DefaultGridResX = 32;
      DefaultGridResZ = 32;
      DefaultCellSize = 0.75;
      DefaultGravity = 9.81;
      DefaultPipeDamping = 0.985;
      DefaultWetnessDryRate = 0.08;
  strict private
    FPreset: TShallowFluidPreset;
    FGridResX: Integer;
    FGridResZ: Integer;
    FCellSize: Single;
    FGravity: Single;
    FPipeDamping: Single;
    FRainRateMps: Single;
    FEvaporationRateMps: Single;
    FWetnessDryRate: Single;
    FWaterColor: TCastleColorRGB;
    FWaterColorPersistent: TCastleColorRGBPersistent;
    FBuildVisualMesh: Boolean;
    FShowBedMesh: Boolean;
    FSimulateInEditor: Boolean;

    FSprings: TFluidSpringSourceArray;

    { Flat 2D grid arrays (size = GridResX * GridResZ) }
    FBedH: array of Single;
    FDepth: array of Single;
    FFluxL: array of Single;
    FFluxR: array of Single;
    FFluxD: array of Single;
    FFluxU: array of Single;
    FVelX: array of Single;
    FVelZ: array of Single;
    FFoam: array of Single;
    FWetness: array of Single;

    FWaterScene: TCastleScene;
    FWaterCoordNode: TCoordinateNode;
    FWaterColorNode: TColorNode;
    FBedScene: TCastleScene;

    procedure SetPreset(const Value: TShallowFluidPreset);
    procedure SetGridResX(const Value: Integer);
    procedure SetGridResZ(const Value: Integer);
    procedure SetCellSize(const Value: Single);
    procedure SetWaterColor(const Value: TCastleColorRGB);
    function GetWaterColorForPersistent: TCastleColorRGB;
    procedure SetWaterColorForPersistent(const AValue: TCastleColorRGB);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);

    function Idx(const IX, IZ: Integer): Integer; inline;
    function CellLocalXZ(const IX, IZ: Integer): TVector2; inline;
    procedure AllocateGrids;
    procedure StepSingleSubstep(const SubDt: Single);
    procedure RebuildVisualMeshes(const RebuildBedToo: Boolean);
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TShallowFluidPreset): String; static;

    procedure ApplyPreset(const APreset: TShallowFluidPreset);
    procedure ClearAllWaterAndFluxes;
    procedure SetCellTerrainAndWater(const IX, IZ: Integer;
      const ATerrainH, AWaterDepth: Single);
    procedure AddRainBurstDepth(const AAddedDepthMeters: Single);

    procedure ClearSprings;
    function AddSpringSource(const ALocalX, ALocalZ, AFlowRateM3PerSec,
      ARadius: Single; const AEnabled: Boolean = True): Integer;
    function SpringCount: Integer;
    function GetSpring(const Index: Integer): TFluidSpringSource;

    { Sample underlying scene colliders in @code(World) via downward @code(WorldRay)
      casts to bake @code(TerrainHeight) directly from level geometry. }
    procedure BakeTerrainBedFromWorld(const RayStartLocalY: Single = 25.0);

    { Advance the Virtual-Pipe Shallow-Water simulation by @code(TotalDt) seconds
      using CFL-safe substeps. }
    procedure StepFluid(const TotalDt: Single);

    function GetCellSample(const IX, IZ: Integer): TFluidCellSample;
    function TotalWaterVolumeM3: Double;
    function WetCellCount(const MinDepth: Single = 0.005): Integer;
    function MaxFlowSpeedMps: Single;
    function MaxFoamFactor: Single;
    function FluidSummaryBadge: String;

    property WaterColor: TCastleColorRGB read FWaterColor write SetWaterColor;
  published
    property Preset: TShallowFluidPreset
      read FPreset write SetPreset default sfpTerracedWaterfallPools;
    property GridResX: Integer read FGridResX write SetGridResX default DefaultGridResX;
    property GridResZ: Integer read FGridResZ write SetGridResZ default DefaultGridResZ;
    property CellSize: Single read FCellSize write SetCellSize {$ifdef FPC}default DefaultCellSize{$endif};
    property Gravity: Single read FGravity write FGravity {$ifdef FPC}default DefaultGravity{$endif};
    property PipeDamping: Single read FPipeDamping write FPipeDamping {$ifdef FPC}default DefaultPipeDamping{$endif};
    property RainRateMps: Single read FRainRateMps write FRainRateMps {$ifdef FPC}default 0.0{$endif};
    property EvaporationRateMps: Single read FEvaporationRateMps write FEvaporationRateMps {$ifdef FPC}default 0.0{$endif};
    property WetnessDryRate: Single read FWetnessDryRate write FWetnessDryRate {$ifdef FPC}default DefaultWetnessDryRate{$endif};
    property WaterColorPersistent: TCastleColorRGBPersistent read FWaterColorPersistent;
    property BuildVisualMesh: Boolean read FBuildVisualMesh write FBuildVisualMesh default True;
    property ShowBedMesh: Boolean read FShowBedMesh write FShowBedMesh default True;
    property SimulateInEditor: Boolean read FSimulateInEditor write FSimulateInEditor default False;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

implementation

uses
  Math, FpJson, JsonParser,
  CastleUtils, CastleTriangles, CastleComponentSerialize;

{ TCastleShallowFluidSurface ------------------------------------------------- }

constructor TCastleShallowFluidSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGridResX := DefaultGridResX;
  FGridResZ := DefaultGridResZ;
  FCellSize := DefaultCellSize;
  FGravity := DefaultGravity;
  FPipeDamping := DefaultPipeDamping;
  FRainRateMps := 0.0;
  FEvaporationRateMps := 0.0;
  FWetnessDryRate := DefaultWetnessDryRate;
  FWaterColor := Vector3(0.12, 0.56, 0.86);
  FBuildVisualMesh := True;
  FShowBedMesh := True;
  FSimulateInEditor := False;

  FWaterColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FWaterColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetWaterColorForPersistent;
  FWaterColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetWaterColorForPersistent;
  FWaterColorPersistent.InternalDefaultValue := FWaterColor;

  ApplyPreset(sfpTerracedWaterfallPools);
end;

destructor TCastleShallowFluidSurface.Destroy;
begin
  FreeAndNil(FWaterColorPersistent);
  inherited;
end;

procedure TCastleShallowFluidSurface.Loaded;
begin
  inherited;
  if FBuildVisualMesh then
    RebuildVisualMeshes(True);
end;

function TCastleShallowFluidSurface.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'GridResX', 'GridResZ', 'CellSize', 'Gravity', 'PipeDamping',
       'RainRateMps', 'EvaporationRateMps', 'WetnessDryRate',
       'WaterColorPersistent', 'BuildVisualMesh', 'ShowBedMesh',
       'SimulateInEditor', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleShallowFluidSurface.PresetDisplayName(
  const APreset: TShallowFluidPreset): String;
begin
  case APreset of
    sfpCustom:                  Result := 'Custom Shallow-Water Grid';
    sfpTerracedWaterfallPools:  Result := 'Terraced Waterfall & Plunge Pools';
    sfpCraterLakeDamBreak:      Result := 'Sloped Basin Dam-Break Surge';
    sfpCanyonRiverRapids:       Result := 'S-Curve Canyon River Rapids';
  end;
end;

function TCastleShallowFluidSurface.Idx(const IX, IZ: Integer): Integer;
begin
  Result := IZ * FGridResX + IX;
end;

function TCastleShallowFluidSurface.CellLocalXZ(const IX, IZ: Integer): TVector2;
var
  HalfX, HalfZ: Single;
begin
  HalfX := ((FGridResX - 1) * FCellSize) * 0.5;
  HalfZ := ((FGridResZ - 1) * FCellSize) * 0.5;
  Result := Vector2(IX * FCellSize - HalfX, IZ * FCellSize - HalfZ);
end;

procedure TCastleShallowFluidSurface.AllocateGrids;
var
  N, I: Integer;
begin
  N := Max(4, FGridResX) * Max(4, FGridResZ);
  SetLength(FBedH, N);
  SetLength(FDepth, N);
  SetLength(FFluxL, N);
  SetLength(FFluxR, N);
  SetLength(FFluxD, N);
  SetLength(FFluxU, N);
  SetLength(FVelX, N);
  SetLength(FVelZ, N);
  SetLength(FFoam, N);
  SetLength(FWetness, N);
  for I := 0 to N - 1 do
  begin
    FBedH[I] := 0.0;
    FDepth[I] := 0.0;
    FFluxL[I] := 0.0;
    FFluxR[I] := 0.0;
    FFluxD[I] := 0.0;
    FFluxU[I] := 0.0;
    FVelX[I] := 0.0;
    FVelZ[I] := 0.0;
    FFoam[I] := 0.0;
    FWetness[I] := 0.0;
  end;
end;

procedure TCastleShallowFluidSurface.SetPreset(const Value: TShallowFluidPreset);
begin
  if FPreset = Value then Exit;
  ApplyPreset(Value);
end;

procedure TCastleShallowFluidSurface.SetGridResX(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 6, 96);
  if FGridResX = V then Exit;
  FGridResX := V;
  ApplyPreset(FPreset);
end;

procedure TCastleShallowFluidSurface.SetGridResZ(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 6, 96);
  if FGridResZ = V then Exit;
  FGridResZ := V;
  ApplyPreset(FPreset);
end;

procedure TCastleShallowFluidSurface.SetCellSize(const Value: Single);
var
  V: Single;
begin
  V := Clamped(Value, 0.15, 5.0);
  if SameValue(FCellSize, V) then Exit;
  FCellSize := V;
  if FBuildVisualMesh then
    RebuildVisualMeshes(True);
end;

procedure TCastleShallowFluidSurface.SetWaterColor(const Value: TCastleColorRGB);
begin
  if TVector3.Equals(FWaterColor, Value) then Exit;
  FWaterColor := Value;
  if FBuildVisualMesh then
    RebuildVisualMeshes(False);
end;

function TCastleShallowFluidSurface.GetWaterColorForPersistent: TCastleColorRGB;
begin
  Result := FWaterColor;
end;

procedure TCastleShallowFluidSurface.SetWaterColorForPersistent(const AValue: TCastleColorRGB);
begin
  WaterColor := AValue;
end;

procedure TCastleShallowFluidSurface.ClearAllWaterAndFluxes;
var
  I: Integer;
begin
  for I := 0 to High(FDepth) do
  begin
    FDepth[I] := 0.0;
    FFluxL[I] := 0.0;
    FFluxR[I] := 0.0;
    FFluxD[I] := 0.0;
    FFluxU[I] := 0.0;
    FVelX[I] := 0.0;
    FVelZ[I] := 0.0;
    FFoam[I] := 0.0;
    FWetness[I] := 0.0;
  end;
end;

procedure TCastleShallowFluidSurface.SetCellTerrainAndWater(
  const IX, IZ: Integer; const ATerrainH, AWaterDepth: Single);
var
  C: Integer;
begin
  if (IX < 0) or (IX >= FGridResX) or (IZ < 0) or (IZ >= FGridResZ) then
    Exit;
  C := Idx(IX, IZ);
  FBedH[C] := ATerrainH;
  FDepth[C] := Max(0.0, AWaterDepth);
  if FDepth[C] > 1e-3 then
    FWetness[C] := 1.0;
end;

procedure TCastleShallowFluidSurface.AddRainBurstDepth(
  const AAddedDepthMeters: Single);
var
  I: Integer;
  D: Single;
begin
  D := Max(0.0, AAddedDepthMeters);
  if D <= 0.0 then Exit;
  for I := 0 to High(FDepth) do
  begin
    FDepth[I] := FDepth[I] + D;
    FWetness[I] := 1.0;
  end;
  if FBuildVisualMesh then
    RebuildVisualMeshes(False);
end;

procedure TCastleShallowFluidSurface.ClearSprings;
begin
  FSprings := nil;
end;

function TCastleShallowFluidSurface.AddSpringSource(
  const ALocalX, ALocalZ, AFlowRateM3PerSec, ARadius: Single;
  const AEnabled: Boolean): Integer;
begin
  Result := Length(FSprings);
  SetLength(FSprings, Result + 1);
  FSprings[Result].LocalX := ALocalX;
  FSprings[Result].LocalZ := ALocalZ;
  FSprings[Result].FlowRateM3PerSec := AFlowRateM3PerSec;
  FSprings[Result].Radius := Max(0.25, ARadius);
  FSprings[Result].Enabled := AEnabled;
end;

function TCastleShallowFluidSurface.SpringCount: Integer;
begin
  Result := Length(FSprings);
end;

function TCastleShallowFluidSurface.GetSpring(
  const Index: Integer): TFluidSpringSource;
begin
  if (Index >= 0) and (Index < Length(FSprings)) then
    Result := FSprings[Index]
  else
    Result := Default(TFluidSpringSource);
end;

procedure TCastleShallowFluidSurface.ApplyPreset(const APreset: TShallowFluidPreset);
var
  IX, IZ, C: Integer;
  P: TVector2;
  RimWall, ChannelCenterX, DistToChannel, TerraceH: Single;
begin
  AllocateGrids;
  FPreset := APreset;
  if APreset = sfpCustom then
  begin
    if FBuildVisualMesh then
      RebuildVisualMeshes(True);
    Exit;
  end;

  ClearSprings;
  FRainRateMps := 0.0;
  FEvaporationRateMps := 0.0;

  for IZ := 0 to FGridResZ - 1 do
    for IX := 0 to FGridResX - 1 do
    begin
      C := Idx(IX, IZ);
      P := CellLocalXZ(IX, IZ);
      RimWall := 0.0;
      if (IX = 0) or (IX = FGridResX - 1) or (IZ = 0) or (IZ = FGridResZ - 1) then
        RimWall := 2.5;

      case APreset of
        sfpTerracedWaterfallPools:
          begin
            if P.Y < -3.0 then
              TerraceH := 3.6
            else if P.Y < 3.0 then
              TerraceH := 1.8
            else
              TerraceH := 0.0;
            { Carve central channel along X=0 }
            if Abs(P.X) > 4.2 then
              TerraceH := TerraceH + 1.4;
            FBedH[C] := TerraceH + RimWall;
            if (P.Y < -4.0) and (Abs(P.X) < 3.5) and (RimWall = 0.0) then
              FDepth[C] := 0.85
            else
              FDepth[C] := 0.0;
          end;

        sfpCraterLakeDamBreak:
          begin
            { Sloped basin from high West plateau (X<0) to low East basin (X>0) }
            TerraceH := Max(0.0, -P.X * 0.22) + RimWall;
            FBedH[C] := TerraceH;
            if (P.X < -2.5) and (RimWall = 0.0) then
              FDepth[C] := 1.65
            else
              FDepth[C] := 0.0;
          end;

        sfpCanyonRiverRapids:
          begin
            ChannelCenterX := Sin(P.Y * 0.28) * 3.8;
            DistToChannel := Abs(P.X - ChannelCenterX);
            TerraceH := Max(0.0, (10.0 - P.Y) * 0.14) + Max(0.0, DistToChannel - 2.4) * 0.85 + RimWall;
            FBedH[C] := TerraceH;
            if (DistToChannel < 2.2) and (RimWall = 0.0) then
              FDepth[C] := 0.55
            else
              FDepth[C] := 0.0;
          end;
      end;

      if FDepth[C] > 1e-3 then
        FWetness[C] := 1.0;
    end;

  if APreset = sfpTerracedWaterfallPools then
    AddSpringSource(0.0, -7.5, 2.40, 2.0, True)
  else if APreset = sfpCanyonRiverRapids then
    AddSpringSource(Sin(-8.0 * 0.28) * 3.8, -8.0, 2.80, 2.0, True);

  if FBuildVisualMesh then
    RebuildVisualMeshes(True);
end;

procedure TCastleShallowFluidSurface.BakeTerrainBedFromWorld(
  const RayStartLocalY: Single);
var
  SavedWaterExists, SavedBedExists: Boolean;
  IX, IZ, C: Integer;
  P: TVector2;
  WorldOrig, WorldDown, LocalHit: TVector3;
  RayHit: TRayCollision;
begin
  if World = nil then
    Exit;

  SavedWaterExists := (FWaterScene <> nil) and FWaterScene.Exists;
  SavedBedExists := (FBedScene <> nil) and FBedScene.Exists;
  if FWaterScene <> nil then FWaterScene.Exists := False;
  if FBedScene <> nil then FBedScene.Exists := False;
  try
    WorldDown := Vector3(0.0, -1.0, 0.0);
    for IZ := 0 to FGridResZ - 1 do
      for IX := 0 to FGridResX - 1 do
      begin
        C := Idx(IX, IZ);
        P := CellLocalXZ(IX, IZ);
        WorldOrig := LocalToWorld(Vector3(P.X, RayStartLocalY, P.Y));
        RayHit := World.WorldRay(WorldOrig, WorldDown);
        try
          if RayHit <> nil then
          begin
            LocalHit := WorldToLocal(WorldOrig + WorldDown * RayHit.Distance);
            FBedH[C] := LocalHit.Y;
          end;
        finally
          FreeAndNil(RayHit);
        end;
      end;
  finally
    if FWaterScene <> nil then FWaterScene.Exists := SavedWaterExists;
    if FBedScene <> nil then FBedScene.Exists := SavedBedExists;
  end;

  if FBuildVisualMesh then
    RebuildVisualMeshes(True);
end;

procedure TCastleShallowFluidSurface.StepSingleSubstep(const SubDt: Single);
var
  CellArea, InvCellSize, PipeAccelScale, DampingStep: Single;
  IX, IZ, C, SIdx, WeightCells: Integer;
  P: TVector2;
  EtaSelf, OutSum, ScaleK, InFromL, InFromR, InFromD, InFromU, OldD, NewD, AvgD,
    FlowX, FlowZ, SpeedMps, DropGrad: Single;
begin
  CellArea := FCellSize * FCellSize;
  InvCellSize := 1.0 / Max(0.05, FCellSize);

  { 1. Apply localized Springs/Drains + Global Rain }
  for SIdx := 0 to High(FSprings) do
    if FSprings[SIdx].Enabled and (Abs(FSprings[SIdx].FlowRateM3PerSec) > 1e-6) then
    begin
      WeightCells := 0;
      for IZ := 0 to FGridResZ - 1 do
        for IX := 0 to FGridResX - 1 do
        begin
          P := CellLocalXZ(IX, IZ);
          if Sqr(P.X - FSprings[SIdx].LocalX) + Sqr(P.Y - FSprings[SIdx].LocalZ) <=
             Sqr(FSprings[SIdx].Radius) then
            Inc(WeightCells);
        end;
      if WeightCells > 0 then
        for IZ := 0 to FGridResZ - 1 do
          for IX := 0 to FGridResX - 1 do
          begin
            P := CellLocalXZ(IX, IZ);
            if Sqr(P.X - FSprings[SIdx].LocalX) + Sqr(P.Y - FSprings[SIdx].LocalZ) <=
               Sqr(FSprings[SIdx].Radius) then
            begin
              C := Idx(IX, IZ);
              FDepth[C] := Max(0.0, FDepth[C] +
                (FSprings[SIdx].FlowRateM3PerSec * SubDt) / (WeightCells * CellArea));
            end;
          end;
    end;

  if FRainRateMps > 0.0 then
    for C := 0 to High(FDepth) do
      FDepth[C] := FDepth[C] + FRainRateMps * SubDt;

  { 2. Hydrostatic Virtual-Pipe Outflow Acceleration + Exact Non-Negative Scaling K }
  PipeAccelScale := SubDt * FCellSize * FGravity; // A_pipe / dx = dx^2 / dx = dx
  DampingStep := Power(Clamped(FPipeDamping, 0.50, 1.0), SubDt * 60.0);

  for IZ := 0 to FGridResZ - 1 do
    for IX := 0 to FGridResX - 1 do
    begin
      C := Idx(IX, IZ);
      if FDepth[C] <= 1e-7 then
      begin
        FFluxL[C] := 0.0;
        FFluxR[C] := 0.0;
        FFluxD[C] := 0.0;
        FFluxU[C] := 0.0;
        Continue;
      end;

      EtaSelf := FBedH[C] + FDepth[C];

      if IX > 0 then
        FFluxL[C] := Max(0.0, FFluxL[C] * DampingStep +
          PipeAccelScale * (EtaSelf - (FBedH[Idx(IX - 1, IZ)] + FDepth[Idx(IX - 1, IZ)])))
      else
        FFluxL[C] := 0.0;

      if IX < FGridResX - 1 then
        FFluxR[C] := Max(0.0, FFluxR[C] * DampingStep +
          PipeAccelScale * (EtaSelf - (FBedH[Idx(IX + 1, IZ)] + FDepth[Idx(IX + 1, IZ)])))
      else
        FFluxR[C] := 0.0;

      if IZ > 0 then
        FFluxD[C] := Max(0.0, FFluxD[C] * DampingStep +
          PipeAccelScale * (EtaSelf - (FBedH[Idx(IX, IZ - 1)] + FDepth[Idx(IX, IZ - 1)])))
      else
        FFluxD[C] := 0.0;

      if IZ < FGridResZ - 1 then
        FFluxU[C] := Max(0.0, FFluxU[C] * DampingStep +
          PipeAccelScale * (EtaSelf - (FBedH[Idx(IX, IZ + 1)] + FDepth[Idx(IX, IZ + 1)])))
      else
        FFluxU[C] := 0.0;

      OutSum := FFluxL[C] + FFluxR[C] + FFluxD[C] + FFluxU[C];
      if OutSum * SubDt > FDepth[C] * CellArea then
      begin
        ScaleK := (FDepth[C] * CellArea) / Max(1e-12, OutSum * SubDt);
        FFluxL[C] := FFluxL[C] * ScaleK;
        FFluxR[C] := FFluxR[C] * ScaleK;
        FFluxD[C] := FFluxD[C] * ScaleK;
        FFluxU[C] := FFluxU[C] * ScaleK;
      end;
    end;

  { 3. Exact Volume Conservation Depth Update + Velocity, Foam & Wetness }
  for IZ := 0 to FGridResZ - 1 do
    for IX := 0 to FGridResX - 1 do
    begin
      C := Idx(IX, IZ);
      OldD := FDepth[C];

      if IX > 0 then InFromL := FFluxR[Idx(IX - 1, IZ)] else InFromL := 0.0;
      if IX < FGridResX - 1 then InFromR := FFluxL[Idx(IX + 1, IZ)] else InFromR := 0.0;
      if IZ > 0 then InFromD := FFluxU[Idx(IX, IZ - 1)] else InFromD := 0.0;
      if IZ < FGridResZ - 1 then InFromU := FFluxD[Idx(IX, IZ + 1)] else InFromU := 0.0;

      OutSum := FFluxL[C] + FFluxR[C] + FFluxD[C] + FFluxU[C];
      NewD := Max(0.0, OldD + (SubDt * ((InFromL + InFromR + InFromD + InFromU) - OutSum)) / CellArea);
      if FEvaporationRateMps > 0.0 then
        NewD := Max(0.0, NewD - FEvaporationRateMps * SubDt);
      FDepth[C] := NewD;

      AvgD := Max(0.02, 0.5 * (OldD + NewD));
      if NewD > 1e-4 then
      begin
        FlowX := 0.5 * ((InFromL - FFluxL[C]) + (FFluxR[C] - InFromR));
        FlowZ := 0.5 * ((InFromD - FFluxD[C]) + (FFluxU[C] - InFromU));
        FVelX[C] := (FlowX * InvCellSize) / AvgD;
        FVelZ[C] := (FlowZ * InvCellSize) / AvgD;
      end else
      begin
        FVelX[C] := 0.0;
        FVelZ[C] := 0.0;
      end;

      SpeedMps := Hypot(FVelX[C], FVelZ[C]);
      DropGrad := 0.0;
      if IX < FGridResX - 1 then
        DropGrad := Max(DropGrad, Abs(FBedH[C] - FBedH[Idx(IX + 1, IZ)]) * InvCellSize);
      if IZ < FGridResZ - 1 then
        DropGrad := Max(DropGrad, Abs(FBedH[C] - FBedH[Idx(IX, IZ + 1)]) * InvCellSize);

      FFoam[C] := Clamped(
        FFoam[C] * Exp(-2.2 * SubDt) + (SpeedMps * (0.35 + DropGrad * 0.45)) * SubDt,
        0.0, 1.0);

      if NewD > 1e-3 then
        FWetness[C] := 1.0
      else
        FWetness[C] := Max(0.0, FWetness[C] - FWetnessDryRate * SubDt);
    end;
end;

procedure TCastleShallowFluidSurface.StepFluid(const TotalDt: Single);
const
  MaxSafeSubDt = 0.0125;
var
  SafeTotal: Single;
  Steps, I: Integer;
begin
  SafeTotal := Clamped(TotalDt, 0.0, 0.50);
  if SafeTotal <= 0.0 then Exit;
  Steps := Max(1, Ceil(SafeTotal / MaxSafeSubDt));
  for I := 1 to Steps do
    StepSingleSubstep(SafeTotal / Steps);
  if FBuildVisualMesh then
    RebuildVisualMeshes(False);
end;

procedure TCastleShallowFluidSurface.RebuildVisualMeshes(const RebuildBedToo: Boolean);
var
  VertCount, IX, IZ, BaseV, C00, C10, C11, C01: Integer;
  P00, P10, P11, P01: TVector2;
  RootNode, BedRoot: TX3DRootNode;
  Shape, BedShape: TShapeNode;
  App, BedApp: TAppearanceNode;
  Mat, BedMat: TPhysicalMaterialNode;
  TriSet, BedTriSet: TTriangleSetNode;
  BedCoord: TCoordinateNode;
  BedVerts: array of TVector3;

  function SurfY(const CellIdx: Integer): Single; inline;
  begin
    if FDepth[CellIdx] > 1e-3 then
      Result := FBedH[CellIdx] + FDepth[CellIdx]
    else
      Result := FBedH[CellIdx] - 0.03;
  end;

  function CellVisualColor(const CellIdx: Integer): TVector3; inline;
  var
    FoamF: Single;
  begin
    FoamF := Clamped(FFoam[CellIdx], 0.0, 1.0);
    Result := Lerp(FoamF, FWaterColor, Vector3(0.95, 0.98, 1.0));
  end;

begin
  if (FGridResX < 2) or (FGridResZ < 2) or (Length(FDepth) = 0) then
    Exit;

  VertCount := (FGridResX - 1) * (FGridResZ - 1) * 6;

  if FWaterScene = nil then
  begin
    FWaterScene := TCastleScene.Create(Self);
    FWaterScene.SetTransient;
    FWaterScene.Pickable := False;
    Add(FWaterScene);

    RootNode := TX3DRootNode.Create;
    Shape := TShapeNode.Create;
    App := TAppearanceNode.Create;
    Mat := TPhysicalMaterialNode.Create;
    Mat.BaseColor := Vector3(1.0, 1.0, 1.0);
    Mat.Roughness := 0.14;
    Mat.Transparency := 0.22;
    App.Material := Mat;
    Shape.Appearance := App;

    TriSet := TTriangleSetNode.Create;
    TriSet.Solid := False;
    FWaterCoordNode := TCoordinateNode.Create;
    FWaterColorNode := TColorNode.Create;
    TriSet.Coord := FWaterCoordNode;
    TriSet.Color := FWaterColorNode;
    Shape.Geometry := TriSet;
    RootNode.AddChildren(Shape);
    FWaterScene.Load(RootNode, True);
  end;

  if (FWaterCoordNode <> nil) and (FWaterColorNode <> nil) then
  begin
    FWaterCoordNode.FdPoint.Count := VertCount;
    FWaterColorNode.FdColor.Count := VertCount;
    BaseV := 0;
    for IZ := 0 to FGridResZ - 2 do
      for IX := 0 to FGridResX - 2 do
      begin
        C00 := Idx(IX, IZ);
        C10 := Idx(IX + 1, IZ);
        C11 := Idx(IX + 1, IZ + 1);
        C01 := Idx(IX, IZ + 1);
        P00 := CellLocalXZ(IX, IZ);
        P10 := CellLocalXZ(IX + 1, IZ);
        P11 := CellLocalXZ(IX + 1, IZ + 1);
        P01 := CellLocalXZ(IX, IZ + 1);

        FWaterCoordNode.FdPoint.Items.L[BaseV]     := Vector3(P00.X, SurfY(C00), P00.Y);
        FWaterCoordNode.FdPoint.Items.L[BaseV + 1] := Vector3(P01.X, SurfY(C01), P01.Y);
        FWaterCoordNode.FdPoint.Items.L[BaseV + 2] := Vector3(P11.X, SurfY(C11), P11.Y);
        FWaterCoordNode.FdPoint.Items.L[BaseV + 3] := Vector3(P00.X, SurfY(C00), P00.Y);
        FWaterCoordNode.FdPoint.Items.L[BaseV + 4] := Vector3(P11.X, SurfY(C11), P11.Y);
        FWaterCoordNode.FdPoint.Items.L[BaseV + 5] := Vector3(P10.X, SurfY(C10), P10.Y);

        FWaterColorNode.FdColor.Items.L[BaseV]     := CellVisualColor(C00);
        FWaterColorNode.FdColor.Items.L[BaseV + 1] := CellVisualColor(C01);
        FWaterColorNode.FdColor.Items.L[BaseV + 2] := CellVisualColor(C11);
        FWaterColorNode.FdColor.Items.L[BaseV + 3] := CellVisualColor(C00);
        FWaterColorNode.FdColor.Items.L[BaseV + 4] := CellVisualColor(C11);
        FWaterColorNode.FdColor.Items.L[BaseV + 5] := CellVisualColor(C10);
        Inc(BaseV, 6);
      end;
    FWaterCoordNode.FdPoint.Changed;
    FWaterColorNode.FdColor.Changed;
  end;

  if RebuildBedToo and FShowBedMesh then
  begin
    if FBedScene = nil then
    begin
      FBedScene := TCastleScene.Create(Self);
      FBedScene.SetTransient;
      FBedScene.Pickable := False;
      Add(FBedScene);
    end;
    SetLength(BedVerts, VertCount);
    BaseV := 0;
    for IZ := 0 to FGridResZ - 2 do
      for IX := 0 to FGridResX - 2 do
      begin
        C00 := Idx(IX, IZ);
        C10 := Idx(IX + 1, IZ);
        C11 := Idx(IX + 1, IZ + 1);
        C01 := Idx(IX, IZ + 1);
        P00 := CellLocalXZ(IX, IZ);
        P10 := CellLocalXZ(IX + 1, IZ);
        P11 := CellLocalXZ(IX + 1, IZ + 1);
        P01 := CellLocalXZ(IX, IZ + 1);

        BedVerts[BaseV]     := Vector3(P00.X, FBedH[C00], P00.Y);
        BedVerts[BaseV + 1] := Vector3(P01.X, FBedH[C01], P01.Y);
        BedVerts[BaseV + 2] := Vector3(P11.X, FBedH[C11], P11.Y);
        BedVerts[BaseV + 3] := Vector3(P00.X, FBedH[C00], P00.Y);
        BedVerts[BaseV + 4] := Vector3(P11.X, FBedH[C11], P11.Y);
        BedVerts[BaseV + 5] := Vector3(P10.X, FBedH[C10], P10.Y);
        Inc(BaseV, 6);
      end;

    BedRoot := TX3DRootNode.Create;
    BedShape := TShapeNode.Create;
    BedApp := TAppearanceNode.Create;
    BedMat := TPhysicalMaterialNode.Create;
    BedMat.BaseColor := Vector3(0.36, 0.33, 0.29);
    BedMat.Roughness := 0.90;
    BedApp.Material := BedMat;
    BedShape.Appearance := BedApp;
    BedTriSet := TTriangleSetNode.Create;
    BedTriSet.Solid := False;
    BedCoord := TCoordinateNode.Create;
    BedCoord.SetPoint(BedVerts);
    BedTriSet.Coord := BedCoord;
    BedShape.Geometry := BedTriSet;
    BedRoot.AddChildren(BedShape);
    FBedScene.Load(BedRoot, True);
  end;
end;

procedure TCastleShallowFluidSurface.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepFluid(SecondsPassed);
end;

function TCastleShallowFluidSurface.GetCellSample(
  const IX, IZ: Integer): TFluidCellSample;
var
  C: Integer;
begin
  if (IX >= 0) and (IX < FGridResX) and (IZ >= 0) and (IZ < FGridResZ) and
     (Length(FDepth) > 0) then
  begin
    C := Idx(IX, IZ);
    Result.TerrainHeight := FBedH[C];
    Result.WaterDepth := FDepth[C];
    Result.SurfaceElevation := FBedH[C] + FDepth[C];
    Result.VelX := FVelX[C];
    Result.VelZ := FVelZ[C];
    Result.Foam := FFoam[C];
    Result.Wetness := FWetness[C];
  end else
    Result := Default(TFluidCellSample);
end;

function TCastleShallowFluidSurface.TotalWaterVolumeM3: Double;
var
  I: Integer;
  SumD: Double;
begin
  SumD := 0.0;
  for I := 0 to High(FDepth) do
    SumD := SumD + FDepth[I];
  Result := SumD * FCellSize * FCellSize;
end;

function TCastleShallowFluidSurface.WetCellCount(const MinDepth: Single): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FDepth) do
    if FDepth[I] >= MinDepth then
      Inc(Result);
end;

function TCastleShallowFluidSurface.MaxFlowSpeedMps: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FVelX) do
    Result := Max(Result, Hypot(FVelX[I], FVelZ[I]));
end;

function TCastleShallowFluidSurface.MaxFoamFactor: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FFoam) do
    Result := Max(Result, FFoam[I]);
end;

function TCastleShallowFluidSurface.GetConfigJson: String;
var
  Root, SObj: TJSONObject;
  SArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('preset', Ord(FPreset));
    SArr := TJSONArray.Create;
    for I := 0 to High(FSprings) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('x', FSprings[I].LocalX);
      SObj.Add('z', FSprings[I].LocalZ);
      SObj.Add('q', FSprings[I].FlowRateM3PerSec);
      SObj.Add('r', FSprings[I].Radius);
      SObj.Add('en', FSprings[I].Enabled);
      SArr.Add(SObj);
    end;
    Root.Add('springs', SArr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleShallowFluidSurface.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Root, SObj: TJSONObject;
  SArr: TJSONArray;
  I, POrd: Integer;
begin
  if Trim(Value) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(Value);
    if Data is TJSONObject then
    begin
      Root := TJSONObject(Data);
      POrd := Root.Get('preset', Ord(FPreset));
      if (POrd >= Ord(Low(TShallowFluidPreset))) and
         (POrd <= Ord(High(TShallowFluidPreset))) then
        ApplyPreset(TShallowFluidPreset(POrd));
      if Root.Find('springs') is TJSONArray then
      begin
        ClearSprings;
        SArr := TJSONArray(Root.Find('springs'));
        for I := 0 to SArr.Count - 1 do
          if SArr.Items[I] is TJSONObject then
          begin
            SObj := TJSONObject(SArr.Items[I]);
            AddSpringSource(SObj.Get('x', 0.0), SObj.Get('z', 0.0),
              SObj.Get('q', 1.5), SObj.Get('r', 1.5), SObj.Get('en', True));
          end;
      end;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleShallowFluidSurface.FluidSummaryBadge: String;
begin
  Result := Format('[ShallowFluid:%dx%d %.1f m^3 Vmax=%.1f m/s]',
    [FGridResX, FGridResZ, TotalWaterVolumeM3, MaxFlowSpeedMps]);
end;

initialization
  RegisterSerializableComponent(TCastleShallowFluidSurface,
    ['World & Terrain', '2.5D Shallow-Water Fluid & Waterfall Surface']);
end.
