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

{ Niagara-Style Grid2D Cellular Fire Spread, Wind-Tilted Flame Front, Stone
  Firebreak Containment & Rain Extinguishing Grid (Phase 372 — UE 6.0+ Grid2D
  Combustion Parity). }
unit CastleFireGrid2D;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Combustion lifecycle state of a 2D grid cell. }
  TFireCellState = (
    fcsUnburnedFuel,
    fcsBurningActive,
    fcsCharredAsh,
    fcsNonFlammableStone
  );

  { Built-in combustion & firebreak scenarios. }
  TFireGridPreset = (
    fgpCustom,
    fgpDryGrasslandPrairie,
    fgpStoneFirebreakTrench,
    fgpMonsoonDousedMeadow
  );

  { Per-cell fuel, temperature, wetness, and state. }
  TFireGridCell = record
    FuelRemaining: Single;
    TemperatureC: Single;
    Wetness: Single;
    State: TFireCellState;
  end;

  { Aggregate telemetry across the entire combustion grid. }
  TFireGridStats = record
    BurningCells: Integer;
    CharredAshCells: Integer;
    UnburnedFuelCells: Integer;
    StoneFirebreakCells: Integer;
    MaxTemperatureC: Single;
  end;

  { 2D cellular fuel/heat combustion grid with wind-driven directional flame
    advection, stone firebreaks, rain/water dousing, and 3D flame column preview. }
  TCastleFireSpreadGrid = class(TCastleTransform)
  private
    FPreset: TFireGridPreset;
    FGridResolution: Integer;
    FWorldSizeMeters: Single;
    FIgnitionThresholdC: Single;
    FWindDirectionDeg: Single;
    FWindSpeedMps: Single;
    FRainIntensity: Single;
    FShowFireGridMesh: Boolean;
    FCells: array of TFireGridCell;
    FStats: TFireGridStats;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TFireGridPreset);
    procedure SetGridResolution(const AValue: Integer);
    procedure SetWorldSizeMeters(const AValue: Single);
    procedure SetIgnitionThresholdC(const AValue: Single);
    procedure SetWindDirectionDeg(const AValue: Single);
    procedure SetWindSpeedMps(const AValue: Single);
    procedure SetRainIntensity(const AValue: Single);
    procedure SetShowFireGridMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetScenario(const APreset: TFireGridPreset);
    function CellIdx(const IX, IZ: Integer): Integer;
    procedure RecountStats;
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ResetFuelGrid;
    function IgniteCell(const IX, IZ: Integer): Boolean;
    procedure PaintStoneFirebreakColumn(const IX: Integer);
    procedure DouseWaterSplash(const IX, IZ, ARadiusCells: Integer);
    function StepCombustion(const Dt: Single): TFireGridStats;
    function GetCell(const IX, IZ: Integer): TFireGridCell;
    procedure RebuildFirePreviewMesh;
    function FireSummaryBadge: String;
    property Stats: TFireGridStats read FStats;
  published
    property Preset: TFireGridPreset read FPreset write SetPreset default fgpDryGrasslandPrairie;
    property GridResolution: Integer read FGridResolution write SetGridResolution default 16;
    property WorldSizeMeters: Single read FWorldSizeMeters write SetWorldSizeMeters {$ifdef FPC}default 16.0{$endif};
    property IgnitionThresholdC: Single read FIgnitionThresholdC write SetIgnitionThresholdC {$ifdef FPC}default 260.0{$endif};
    property WindDirectionDeg: Single read FWindDirectionDeg write SetWindDirectionDeg {$ifdef FPC}default 0.0{$endif};
    property WindSpeedMps: Single read FWindSpeedMps write SetWindSpeedMps {$ifdef FPC}default 8.5{$endif};
    property RainIntensity: Single read FRainIntensity write SetRainIntensity {$ifdef FPC}default 0.0{$endif};
    property ShowFireGridMesh: Boolean read FShowFireGridMesh write SetShowFireGridMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function FirePresetToString(const APreset: TFireGridPreset): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

const
  AmbientTempC = 22.0;

function FirePresetToString(const APreset: TFireGridPreset): String;
begin
  case APreset of
    fgpCustom: Result := 'Custom Grid2D Combustion';
    fgpDryGrasslandPrairie: Result := 'Dry Grassland Prairie (+X East Wind 8.5 m/s)';
    fgpStoneFirebreakTrench: Result := 'Stone Trench Firebreak Containment';
    fgpMonsoonDousedMeadow: Result := 'Monsoon Cloudburst Extinguish (Rain 100%)';
  end;
end;

{ TCastleFireSpreadGrid ------------------------------------------------------- }

constructor TCastleFireSpreadGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGridResolution := 16;
  FWorldSizeMeters := 16.0;
  FIgnitionThresholdC := 260.0;
  FShowFireGridMesh := True;
  ApplyPresetScenario(fgpDryGrasslandPrairie);
  RebuildFirePreviewMesh;
end;

destructor TCastleFireSpreadGrid.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

function TCastleFireSpreadGrid.CellIdx(const IX, IZ: Integer): Integer;
begin
  Result := IZ * FGridResolution + IX;
end;

procedure TCastleFireSpreadGrid.ResetFuelGrid;
var
  I: Integer;
begin
  SetLength(FCells, FGridResolution * FGridResolution);
  for I := 0 to High(FCells) do
  begin
    FCells[I].FuelRemaining := 1.0;
    FCells[I].TemperatureC := AmbientTempC;
    FCells[I].Wetness := 0.0;
    FCells[I].State := fcsUnburnedFuel;
  end;
  RecountStats;
end;

procedure TCastleFireSpreadGrid.ApplyPresetScenario(const APreset: TFireGridPreset);
begin
  ResetFuelGrid;
  case APreset of
    fgpDryGrasslandPrairie, fgpCustom:
      begin
        FWindDirectionDeg := 0.0;
        FWindSpeedMps := 8.5;
        FRainIntensity := 0.0;
        IgniteCell(FGridResolution div 3, FGridResolution div 2);
        FPreset := APreset;
      end;
    fgpStoneFirebreakTrench:
      begin
        FWindDirectionDeg := 0.0;
        FWindSpeedMps := 10.0;
        FRainIntensity := 0.0;
        PaintStoneFirebreakColumn((FGridResolution * 3) div 5);
        IgniteCell(FGridResolution div 4, FGridResolution div 2);
        FPreset := fgpStoneFirebreakTrench;
      end;
    fgpMonsoonDousedMeadow:
      begin
        FWindDirectionDeg := 0.0;
        FWindSpeedMps := 4.0;
        FRainIntensity := 1.0;
        IgniteCell(FGridResolution div 2, FGridResolution div 2);
        FPreset := fgpMonsoonDousedMeadow;
      end;
  end;
  RecountStats;
end;

procedure TCastleFireSpreadGrid.SetPreset(const AValue: TFireGridPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> fgpCustom then
  begin
    ApplyPresetScenario(AValue);
    RebuildFirePreviewMesh;
  end;
end;

procedure TCastleFireSpreadGrid.SetGridResolution(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 6, 64);
  if FGridResolution = V then Exit;
  FGridResolution := V;
  ResetFuelGrid;
  RebuildFirePreviewMesh;
end;

procedure TCastleFireSpreadGrid.SetWorldSizeMeters(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 2.0, 200.0);
  if SameValue(FWorldSizeMeters, V, 1e-4) then Exit;
  FWorldSizeMeters := V;
  RebuildFirePreviewMesh;
end;

procedure TCastleFireSpreadGrid.SetIgnitionThresholdC(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 80.0, 600.0);
  if SameValue(FIgnitionThresholdC, V, 1e-3) then Exit;
  FIgnitionThresholdC := V;
  FPreset := fgpCustom;
end;

procedure TCastleFireSpreadGrid.SetWindDirectionDeg(const AValue: Single);
begin
  if SameValue(FWindDirectionDeg, AValue, 1e-4) then Exit;
  FWindDirectionDeg := AValue;
  FPreset := fgpCustom;
end;

procedure TCastleFireSpreadGrid.SetWindSpeedMps(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 40.0);
  if SameValue(FWindSpeedMps, V, 1e-4) then Exit;
  FWindSpeedMps := V;
  FPreset := fgpCustom;
end;

procedure TCastleFireSpreadGrid.SetRainIntensity(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 1.0);
  if SameValue(FRainIntensity, V, 1e-4) then Exit;
  FRainIntensity := V;
  FPreset := fgpCustom;
end;

procedure TCastleFireSpreadGrid.SetShowFireGridMesh(const AValue: Boolean);
begin
  if FShowFireGridMesh = AValue then Exit;
  FShowFireGridMesh := AValue;
  if not FShowFireGridMesh then
    ClearTransientScene
  else
    RebuildFirePreviewMesh;
end;

function TCastleFireSpreadGrid.IgniteCell(const IX, IZ: Integer): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if (IX < 0) or (IX >= FGridResolution) or (IZ < 0) or (IZ >= FGridResolution) then
    Exit;
  Idx := CellIdx(IX, IZ);
  if FCells[Idx].State <> fcsUnburnedFuel then
    Exit;
  FCells[Idx].State := fcsBurningActive;
  FCells[Idx].TemperatureC := 760.0;
  FCells[Idx].Wetness := 0.0;
  RecountStats;
  RebuildFirePreviewMesh;
  Result := True;
end;

procedure TCastleFireSpreadGrid.PaintStoneFirebreakColumn(const IX: Integer);
var
  IZ, Idx: Integer;
begin
  if (IX < 0) or (IX >= FGridResolution) then Exit;
  for IZ := 0 to FGridResolution - 1 do
  begin
    Idx := CellIdx(IX, IZ);
    FCells[Idx].State := fcsNonFlammableStone;
    FCells[Idx].FuelRemaining := 0.0;
    FCells[Idx].TemperatureC := AmbientTempC;
  end;
  RecountStats;
  RebuildFirePreviewMesh;
end;

procedure TCastleFireSpreadGrid.DouseWaterSplash(const IX, IZ, ARadiusCells: Integer);
var
  X, Z, Idx: Integer;
begin
  for Z := Max(0, IZ - ARadiusCells) to Min(FGridResolution - 1, IZ + ARadiusCells) do
    for X := Max(0, IX - ARadiusCells) to Min(FGridResolution - 1, IX + ARadiusCells) do
    begin
      Idx := CellIdx(X, Z);
      FCells[Idx].Wetness := 1.0;
      FCells[Idx].TemperatureC := AmbientTempC;
      if FCells[Idx].State = fcsBurningActive then
        FCells[Idx].State := fcsUnburnedFuel;
    end;
  RecountStats;
  RebuildFirePreviewMesh;
end;

function TCastleFireSpreadGrid.StepCombustion(const Dt: Single): TFireGridStats;
var
  NextCells: array of TFireGridCell;
  WindRad, WindX, WindZ, StepLen, Align, NeighborWeight, HeatIn, NewTemp, NewWet, NewFuel: Single;
  IX, IZ, DX, DZ, NX, NZ, Idx, NIdx: Integer;
  Cell: TFireGridCell;
begin
  if Dt <= 0.0 then
  begin
    RecountStats;
    Exit(FStats);
  end;

  WindRad := DegToRad(FWindDirectionDeg);
  WindX := Cos(WindRad);
  WindZ := Sin(WindRad);
  SetLength(NextCells, Length(FCells));

  for IZ := 0 to FGridResolution - 1 do
    for IX := 0 to FGridResolution - 1 do
    begin
      Idx := CellIdx(IX, IZ);
      Cell := FCells[Idx];
      NextCells[Idx] := Cell;

      if Cell.State = fcsNonFlammableStone then
        Continue;

      NewWet := EnsureRange(Cell.Wetness + FRainIntensity * 0.55 * Dt - 0.04 * Dt, 0.0, 1.0);
      NextCells[Idx].Wetness := NewWet;

      case Cell.State of
        fcsUnburnedFuel:
          begin
            HeatIn := 0.0;
            for DZ := -1 to 1 do
              for DX := -1 to 1 do
              begin
                if (DX = 0) and (DZ = 0) then Continue;
                NX := IX + DX;
                NZ := IZ + DZ;
                if (NX < 0) or (NX >= FGridResolution) or (NZ < 0) or (NZ >= FGridResolution) then
                  Continue;
                NIdx := CellIdx(NX, NZ);
                if FCells[NIdx].State = fcsBurningActive then
                begin
                  { Vector from burning neighbor (NX, NZ) to target cell (IX, IZ) = (-DX, -DZ) }
                  StepLen := Sqrt(Sqr(Single(DX)) + Sqr(Single(DZ)));
                  Align := ((-DX * WindX) + (-DZ * WindZ)) / StepLen;
                  if Align >= 0.0 then
                    NeighborWeight := (1.0 + Align * FWindSpeedMps * 0.45) / StepLen
                  else
                    NeighborWeight := Max(0.08, 1.0 + Align * FWindSpeedMps * 0.11) / StepLen;
                  HeatIn := HeatIn + 210.0 * NeighborWeight;
                end;
              end;

            NewTemp := Cell.TemperatureC +
              HeatIn * (1.0 - NewWet * 0.90) * Dt -
              (28.0 + FRainIntensity * 260.0) * Dt;
            NewTemp := Max(AmbientTempC, NewTemp);
            NextCells[Idx].TemperatureC := NewTemp;

            if (NewTemp >= FIgnitionThresholdC) and (NewWet < 0.75) then
            begin
              NextCells[Idx].State := fcsBurningActive;
              NextCells[Idx].TemperatureC := 760.0;
            end;
          end;

        fcsBurningActive:
          begin
            NewFuel := Cell.FuelRemaining - 0.28 * Dt;
            NewTemp := Cell.TemperatureC - FRainIntensity * 480.0 * Dt;
            NextCells[Idx].FuelRemaining := Max(0.0, NewFuel);
            NextCells[Idx].TemperatureC := Max(AmbientTempC, NewTemp);
            if NewFuel <= 0.0 then
            begin
              NextCells[Idx].State := fcsCharredAsh;
              NextCells[Idx].TemperatureC := 140.0;
            end else if (NewTemp < FIgnitionThresholdC * 0.75) or (NewWet >= 0.80) then
            begin
              NextCells[Idx].State := fcsUnburnedFuel;
              NextCells[Idx].TemperatureC := AmbientTempC;
            end;
          end;

        fcsCharredAsh:
          NextCells[Idx].TemperatureC := Max(AmbientTempC, Cell.TemperatureC - 65.0 * Dt);
      end;
    end;

  FCells := NextCells;
  RecountStats;
  RebuildFirePreviewMesh;
  Result := FStats;
end;

procedure TCastleFireSpreadGrid.RecountStats;
var
  I: Integer;
begin
  FillChar(FStats, SizeOf(FStats), 0);
  FStats.MaxTemperatureC := AmbientTempC;
  for I := 0 to High(FCells) do
  begin
    if FCells[I].TemperatureC > FStats.MaxTemperatureC then
      FStats.MaxTemperatureC := FCells[I].TemperatureC;
    case FCells[I].State of
      fcsUnburnedFuel:      Inc(FStats.UnburnedFuelCells);
      fcsBurningActive:     Inc(FStats.BurningCells);
      fcsCharredAsh:        Inc(FStats.CharredAshCells);
      fcsNonFlammableStone: Inc(FStats.StoneFirebreakCells);
    end;
  end;
end;

function TCastleFireSpreadGrid.GetCell(const IX, IZ: Integer): TFireGridCell;
begin
  if (IX >= 0) and (IX < FGridResolution) and (IZ >= 0) and (IZ < FGridResolution) then
    Result := FCells[CellIdx(IX, IZ)]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleFireSpreadGrid.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientFireGridMesh';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;
  FTransientScene.RenderOptions.Lighting := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
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

procedure TCastleFireSpreadGrid.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleFireSpreadGrid.RebuildFirePreviewMesh;
var
  Verts, Cols: TVector3List;
  IX, IZ: Integer;
  HalfExt, StepSz, X0, X1, Z0, Z1, YTop: Single;
  Cell: TFireGridCell;
  C: TVector3;
begin
  if (not FShowFireGridMesh) or (Length(FCells) = 0) then
  begin
    ClearTransientScene;
    Exit;
  end;

  HalfExt := FWorldSizeMeters * 0.5;
  StepSz := FWorldSizeMeters / Max(1, FGridResolution);
  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    for IZ := 0 to FGridResolution - 1 do
      for IX := 0 to FGridResolution - 1 do
      begin
        Cell := FCells[CellIdx(IX, IZ)];
        X0 := -HalfExt + IX * StepSz;
        X1 := X0 + StepSz * 0.94;
        Z0 := -HalfExt + IZ * StepSz;
        Z1 := Z0 + StepSz * 0.94;
        case Cell.State of
          fcsUnburnedFuel:
            begin
              YTop := 0.06;
              C := Lerp(Cell.Wetness, Vector3(0.24, 0.62, 0.22), Vector3(0.14, 0.42, 0.56));
            end;
          fcsBurningActive:
            begin
              YTop := 0.45 + 0.85 * Cell.FuelRemaining;
              C := Vector3(1.0, 0.52, 0.08);
            end;
          fcsCharredAsh:
            begin
              YTop := 0.03;
              C := Vector3(0.16, 0.15, 0.16);
            end;
          fcsNonFlammableStone:
            begin
              YTop := 0.24;
              C := Vector3(0.55, 0.56, 0.60);
            end;
        end;

        Verts.Add(Vector3(X0, YTop, Z0));
        Verts.Add(Vector3(X1, YTop, Z0));
        Verts.Add(Vector3(X1, YTop, Z1));
        Cols.Add(C); Cols.Add(C); Cols.Add(C);

        Verts.Add(Vector3(X0, YTop, Z0));
        Verts.Add(Vector3(X1, YTop, Z1));
        Verts.Add(Vector3(X0, YTop, Z1));
        Cols.Add(C); Cols.Add(C); Cols.Add(C);
      end;

    EnsureTransientScene;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleFireSpreadGrid.GetConfigJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('res', FGridResolution);
    RootObj.Add('sizeM', FWorldSizeMeters);
    RootObj.Add('igniteC', FIgnitionThresholdC);
    RootObj.Add('windDeg', FWindDirectionDeg);
    RootObj.Add('windMps', FWindSpeedMps);
    RootObj.Add('rain', FRainIntensity);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleFireSpreadGrid.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj: TJSONObject;
  PresetOrd, NewRes: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      NewRes := EnsureRange(RootObj.Get('res', FGridResolution), 6, 64);
      if NewRes <> FGridResolution then
        FGridResolution := NewRes;
      FWorldSizeMeters := EnsureRange(RootObj.Get('sizeM', FWorldSizeMeters), 2.0, 200.0);
      FIgnitionThresholdC := EnsureRange(RootObj.Get('igniteC', FIgnitionThresholdC), 80.0, 600.0);
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TFireGridPreset))) and
         (PresetOrd <= Ord(High(TFireGridPreset))) then
        FPreset := TFireGridPreset(PresetOrd);
      if FPreset <> fgpCustom then
        ApplyPresetScenario(FPreset)
      else
        ResetFuelGrid;
      FWindDirectionDeg := RootObj.Get('windDeg', FWindDirectionDeg);
      FWindSpeedMps := EnsureRange(RootObj.Get('windMps', FWindSpeedMps), 0.0, 40.0);
      FRainIntensity := EnsureRange(RootObj.Get('rain', FRainIntensity), 0.0, 1.0);
      RebuildFirePreviewMesh;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleFireSpreadGrid.FireSummaryBadge: String;
begin
  Result := Format('[Fire2D:%d burning %d ash Wind=%.0fm/s]', [
    FStats.BurningCells,
    FStats.CharredAshCells,
    FWindSpeedMps]);
end;

initialization
  RegisterSerializableComponent(TCastleFireSpreadGrid, ['VFX & Simulation', 'Grid2D Cellular Fire Spread']);
end.
