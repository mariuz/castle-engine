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

{ Spline Water River / Rapids component with continuity discharge acceleration
  (narrow gorge speedup), slope/waterfall whitewater foam, and kayak/raft drift
  advection (Phase 361 — UE 6.0+ WaterBodyRiver Parity). }
unit CastleRiverSpline;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Built-in river channel and waterfall topology presets. }
  TRiverSplinePreset = (
    rspCustom,
    rspMountainGorgeRapids,
    rspWaterfallPlungeCascade,
    rspMeanderingValleyStream
  );

  { Single river spline control knot with local 3D position, bank width, and bed depth. }
  TRiverControlKnot = record
    PositionLocal: TVector3;
    WidthMeters: Single;
    DepthMeters: Single;
  end;

  { Evaluated hydraulic cross-section at parameter U along the river spline. }
  TRiverCrossSectionSample = record
    ParamU: Single;
    CenterWorldPos: TVector3;
    FlowDirectionWorld: TVector3;
    WidthMeters: Single;
    DepthMeters: Single;
    SlopeSin: Single;
    FlowSpeedMps: Single;
    WhitewaterFoamFactor: Single;
  end;

  { Spline-guided river and rapids system matching Unreal Engine 6.0+ WaterBodyRiver
    with Q = A * v continuity gorge acceleration, slope drop rapids, foam shading,
    and world-space downstream drift queries. }
  TCastleRiverSpline = class(TCastleTransform)
  private
    FPreset: TRiverSplinePreset;
    FDischargeCubicMps: Single;
    FSlopeVelocityGain: Single;
    FFoamSpeedThreshold: Single;
    FRibbonSubdivisions: Integer;
    FShowRiverMesh: Boolean;
    FKnots: array of TRiverControlKnot;
    FPeakFlowSpeedMps: Single;
    FMeanFoamFactor: Single;
    FGeneratedTriangleCount: Integer;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TRiverSplinePreset);
    procedure SetDischargeCubicMps(const AValue: Single);
    procedure SetSlopeVelocityGain(const AValue: Single);
    procedure SetFoamSpeedThreshold(const AValue: Single);
    procedure SetRibbonSubdivisions(const AValue: Integer);
    procedure SetShowRiverMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetKnotsOnly(const APreset: TRiverSplinePreset);
    function LocalPointToWorldSafe(const LocalPt: TVector3): TVector3;
    function LocalDirToWorldSafe(const LocalDir: TVector3): TVector3;
    procedure EvaluateLocalKnotState(const U: Single; out OutPosLocal: TVector3;
      out OutWidth, OutDepth: Single);
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ClearKnots;
    procedure AddKnot(const APosLocal: TVector3; const AWidth, ADepth: Single);
    function KnotCount: Integer;
    function GetKnot(const AIndex: Integer): TRiverControlKnot;
    function SampleRiverAtParam(const U: Single): TRiverCrossSectionSample;
    function SampleRiverFlowAtWorldPoint(const AWorldPt: TVector3;
      out OutInsideChannel: Boolean): TRiverCrossSectionSample;
    function StepFloatingBodyAlongRiver(var BodyWorldPos, BodyVelocity: TVector3;
      const DragCoeff, Dt: Single): Boolean;
    procedure RebuildRiverRibbonMesh;
    function RiverSummaryBadge: String;
    property PeakFlowSpeedMps: Single read FPeakFlowSpeedMps;
    property MeanFoamFactor: Single read FMeanFoamFactor;
    property GeneratedTriangleCount: Integer read FGeneratedTriangleCount;
  published
    property Preset: TRiverSplinePreset read FPreset write SetPreset default rspMountainGorgeRapids;
    property DischargeCubicMps: Single read FDischargeCubicMps write SetDischargeCubicMps {$ifdef FPC}default 16.0{$endif};
    property SlopeVelocityGain: Single read FSlopeVelocityGain write SetSlopeVelocityGain {$ifdef FPC}default 5.5{$endif};
    property FoamSpeedThreshold: Single read FFoamSpeedThreshold write SetFoamSpeedThreshold {$ifdef FPC}default 4.2{$endif};
    property RibbonSubdivisions: Integer read FRibbonSubdivisions write SetRibbonSubdivisions default 48;
    property ShowRiverMesh: Boolean read FShowRiverMesh write SetShowRiverMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function RiverPresetToString(const APreset: TRiverSplinePreset): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function RiverPresetToString(const APreset: TRiverSplinePreset): String;
begin
  case APreset of
    rspCustom: Result := 'Custom River Spline';
    rspMountainGorgeRapids: Result := 'Mountain Gorge Narrowing Rapids';
    rspWaterfallPlungeCascade: Result := 'Steep Waterfall Plunge Cascade';
    rspMeanderingValleyStream: Result := 'Wide Meandering Valley Stream';
  end;
end;

function CatmullScalar(const A0, A1, A2, A3, T: Single): Single;
var
  T2, T3: Single;
begin
  T2 := T * T;
  T3 := T2 * T;
  Result := 0.5 * ((2.0 * A1) +
    (-A0 + A2) * T +
    (2.0 * A0 - 5.0 * A1 + 4.0 * A2 - A3) * T2 +
    (-A0 + 3.0 * A1 - 3.0 * A2 + A3) * T3);
end;

function CatmullVec3(const P0, P1, P2, P3: TVector3; const T: Single): TVector3;
begin
  Result := Vector3(
    CatmullScalar(P0.X, P1.X, P2.X, P3.X, T),
    CatmullScalar(P0.Y, P1.Y, P2.Y, P3.Y, T),
    CatmullScalar(P0.Z, P1.Z, P2.Z, P3.Z, T));
end;

{ TCastleRiverSpline --------------------------------------------------------- }

constructor TCastleRiverSpline.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := rspMountainGorgeRapids;
  FDischargeCubicMps := 16.0;
  FSlopeVelocityGain := 5.5;
  FFoamSpeedThreshold := 4.2;
  FRibbonSubdivisions := 48;
  FShowRiverMesh := True;
  ApplyPresetKnotsOnly(rspMountainGorgeRapids);
  RebuildRiverRibbonMesh;
end;

destructor TCastleRiverSpline.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleRiverSpline.ApplyPresetKnotsOnly(const APreset: TRiverSplinePreset);
begin
  SetLength(FKnots, 0);
  case APreset of
    rspMountainGorgeRapids, rspCustom:
      begin
        { Starts as a wide 9.0m placid headwater lake -> pinches into a narrow 2.2m steep gorge -> widens into a 10.0m basin! }
        AddKnot(Vector3(-18.0, 4.5, -14.0), 9.0, 2.2);
        AddKnot(Vector3(-8.0,  4.1, -6.0),  7.5, 1.9);
        AddKnot(Vector3( 0.0,  2.4,  0.0),  2.2, 1.1);
        AddKnot(Vector3( 9.0,  0.8,  6.5),  3.4, 1.4);
        AddKnot(Vector3( 19.0, 0.4,  14.0), 10.0, 2.5);
        FPreset := APreset;
      end;
    rspWaterfallPlungeCascade:
      begin
        AddKnot(Vector3(-12.0, 9.0, -10.0), 5.5, 1.6);
        AddKnot(Vector3(-3.0,  8.6, -3.0),  4.2, 1.3);
        AddKnot(Vector3( 1.5,  1.2,  1.5),  4.6, 1.2);
        AddKnot(Vector3( 12.0, 0.5,  10.0), 9.5, 2.8);
        FPreset := rspWaterfallPlungeCascade;
      end;
    rspMeanderingValleyStream:
      begin
        AddKnot(Vector3(-20.0, 1.6, -6.0),  7.0, 1.8);
        AddKnot(Vector3(-7.0,  1.3,  7.5),  7.5, 1.9);
        AddKnot(Vector3( 7.0,  1.0, -6.5),  7.2, 1.8);
        AddKnot(Vector3( 20.0, 0.7,  6.0),  8.0, 2.0);
        FPreset := rspMeanderingValleyStream;
      end;
  end;
end;

procedure TCastleRiverSpline.SetPreset(const AValue: TRiverSplinePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> rspCustom then
  begin
    ApplyPresetKnotsOnly(AValue);
    RebuildRiverRibbonMesh;
  end;
end;

procedure TCastleRiverSpline.SetDischargeCubicMps(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.5, 500.0);
  if SameValue(FDischargeCubicMps, V, 1e-4) then Exit;
  FDischargeCubicMps := V;
  RebuildRiverRibbonMesh;
end;

procedure TCastleRiverSpline.SetSlopeVelocityGain(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 30.0);
  if SameValue(FSlopeVelocityGain, V, 1e-4) then Exit;
  FSlopeVelocityGain := V;
  RebuildRiverRibbonMesh;
end;

procedure TCastleRiverSpline.SetFoamSpeedThreshold(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.5, 40.0);
  if SameValue(FFoamSpeedThreshold, V, 1e-4) then Exit;
  FFoamSpeedThreshold := V;
  RebuildRiverRibbonMesh;
end;

procedure TCastleRiverSpline.SetRibbonSubdivisions(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 8, 256);
  if FRibbonSubdivisions = V then Exit;
  FRibbonSubdivisions := V;
  RebuildRiverRibbonMesh;
end;

procedure TCastleRiverSpline.SetShowRiverMesh(const AValue: Boolean);
begin
  if FShowRiverMesh = AValue then Exit;
  FShowRiverMesh := AValue;
  if not FShowRiverMesh then
    ClearTransientScene
  else
    RebuildRiverRibbonMesh;
end;

procedure TCastleRiverSpline.ClearKnots;
begin
  SetLength(FKnots, 0);
  FPreset := rspCustom;
  RebuildRiverRibbonMesh;
end;

procedure TCastleRiverSpline.AddKnot(const APosLocal: TVector3; const AWidth, ADepth: Single);
var
  N: Integer;
begin
  N := Length(FKnots);
  SetLength(FKnots, N + 1);
  FKnots[N].PositionLocal := APosLocal;
  FKnots[N].WidthMeters := Max(0.4, AWidth);
  FKnots[N].DepthMeters := Max(0.15, ADepth);
  FPreset := rspCustom;
end;

function TCastleRiverSpline.KnotCount: Integer;
begin
  Result := Length(FKnots);
end;

function TCastleRiverSpline.GetKnot(const AIndex: Integer): TRiverControlKnot;
begin
  if (AIndex >= 0) and (AIndex < Length(FKnots)) then
    Result := FKnots[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleRiverSpline.LocalPointToWorldSafe(const LocalPt: TVector3): TVector3;
begin
  if Parent <> nil then
    Result := LocalToWorld(LocalPt)
  else
    Result := Translation + LocalPt;
end;

function TCastleRiverSpline.LocalDirToWorldSafe(const LocalDir: TVector3): TVector3;
begin
  if Parent <> nil then
    Result := LocalToWorldDirection(LocalDir)
  else
    Result := LocalDir;
end;

procedure TCastleRiverSpline.EvaluateLocalKnotState(const U: Single;
  out OutPosLocal: TVector3; out OutWidth, OutDepth: Single);
var
  N, SegCount, SegIdx, I0, I1, I2, I3: Integer;
  ClampedU, Scaled, LocalT: Single;
begin
  N := Length(FKnots);
  if N = 0 then
  begin
    OutPosLocal := TVector3.Zero;
    OutWidth := 4.0;
    OutDepth := 1.0;
    Exit;
  end;
  if N = 1 then
  begin
    OutPosLocal := FKnots[0].PositionLocal;
    OutWidth := FKnots[0].WidthMeters;
    OutDepth := FKnots[0].DepthMeters;
    Exit;
  end;

  ClampedU := EnsureRange(U, 0.0, 1.0);
  SegCount := N - 1;
  Scaled := ClampedU * SegCount;
  SegIdx := Min(SegCount - 1, Floor(Scaled));
  LocalT := Scaled - SegIdx;
  I0 := Max(0, SegIdx - 1);
  I1 := SegIdx;
  I2 := Min(N - 1, SegIdx + 1);
  I3 := Min(N - 1, SegIdx + 2);

  OutPosLocal := CatmullVec3(FKnots[I0].PositionLocal, FKnots[I1].PositionLocal,
    FKnots[I2].PositionLocal, FKnots[I3].PositionLocal, LocalT);
  OutWidth := Max(0.35, CatmullScalar(FKnots[I0].WidthMeters, FKnots[I1].WidthMeters,
    FKnots[I2].WidthMeters, FKnots[I3].WidthMeters, LocalT));
  OutDepth := Max(0.15, CatmullScalar(FKnots[I0].DepthMeters, FKnots[I1].DepthMeters,
    FKnots[I2].DepthMeters, FKnots[I3].DepthMeters, LocalT));
end;

function TCastleRiverSpline.SampleRiverAtParam(const U: Single): TRiverCrossSectionSample;
const
  Eps = 0.004;
var
  ClampedU, Area, WMinus, DMinus, WPlus, DPlus, ContSpeed, SlopeBoost: Single;
  PosLoc, PMinus, PPlus, RawTanW: TVector3;
begin
  ClampedU := EnsureRange(U, 0.0, 1.0);
  EvaluateLocalKnotState(ClampedU, PosLoc, Result.WidthMeters, Result.DepthMeters);
  EvaluateLocalKnotState(Max(0.0, ClampedU - Eps), PMinus, WMinus, DMinus);
  EvaluateLocalKnotState(Min(1.0, ClampedU + Eps), PPlus, WPlus, DPlus);

  Result.ParamU := ClampedU;
  Result.CenterWorldPos := LocalPointToWorldSafe(PosLoc);
  RawTanW := LocalDirToWorldSafe(PPlus - PMinus);
  if RawTanW.LengthSqr > 1e-8 then
    Result.FlowDirectionWorld := RawTanW.Normalize
  else
    Result.FlowDirectionWorld := Vector3(1, 0, 0);

  Result.SlopeSin := EnsureRange(-Result.FlowDirectionWorld.Y, 0.0, 1.0);

  { Conservation of discharge Q = CrossSectionArea * Velocity + gravitational slope drop }
  Area := Max(0.25, Result.WidthMeters * Result.DepthMeters * 0.78);
  ContSpeed := FDischargeCubicMps / Area;
  SlopeBoost := FSlopeVelocityGain * Sqrt(Result.SlopeSin);
  Result.FlowSpeedMps := ContSpeed + SlopeBoost;

  Result.WhitewaterFoamFactor := EnsureRange(
    ((Result.FlowSpeedMps - FFoamSpeedThreshold) / Max(0.5, FFoamSpeedThreshold)) +
    Result.SlopeSin * 1.15,
    0.0, 1.0);
end;

function TCastleRiverSpline.SampleRiverFlowAtWorldPoint(const AWorldPt: TVector3;
  out OutInsideChannel: Boolean): TRiverCrossSectionSample;
const
  Samples = 64;
var
  I: Integer;
  BestU, CandU, BestHorizSq, CandHorizSq, DX, DZ: Single;
  S: TRiverCrossSectionSample;
begin
  BestU := 0.0;
  BestHorizSq := 1e30;
  for I := 0 to Samples do
  begin
    CandU := I / Samples;
    S := SampleRiverAtParam(CandU);
    DX := AWorldPt.X - S.CenterWorldPos.X;
    DZ := AWorldPt.Z - S.CenterWorldPos.Z;
    CandHorizSq := DX * DX + DZ * DZ;
    if CandHorizSq < BestHorizSq then
    begin
      BestHorizSq := CandHorizSq;
      BestU := CandU;
    end;
  end;

  Result := SampleRiverAtParam(BestU);
  OutInsideChannel := Sqrt(BestHorizSq) <= (Result.WidthMeters * 0.5);
end;

function TCastleRiverSpline.StepFloatingBodyAlongRiver(
  var BodyWorldPos, BodyVelocity: TVector3;
  const DragCoeff, Dt: Single): Boolean;
var
  Flow: TRiverCrossSectionSample;
  Inside: Boolean;
  TargetVel: TVector3;
  Alpha: Single;
begin
  Flow := SampleRiverFlowAtWorldPoint(BodyWorldPos, Inside);
  Result := Inside;
  if (not Inside) or (Dt <= 0.0) then Exit;

  TargetVel := Flow.FlowDirectionWorld * Flow.FlowSpeedMps;
  Alpha := 1.0 - Exp(-Max(0.2, DragCoeff) * Dt);
  BodyVelocity := Lerp(Alpha, BodyVelocity, TargetVel);
  BodyWorldPos := BodyWorldPos + BodyVelocity * Dt;
  { Buoyant surface lock onto local river water elevation }
  BodyWorldPos.Y := Flow.CenterWorldPos.Y;
end;

procedure TCastleRiverSpline.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientRiverSplineMesh';
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

procedure TCastleRiverSpline.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleRiverSpline.RebuildRiverRibbonMesh;
var
  Verts, Cols: TVector3List;
  I: Integer;
  U0, U1, W0, D0, W1, D1, SumFoam: Single;
  P0, P1, Tan0, Tan1, Side0, Side1, Col0, Col1: TVector3;
  S0, S1: TRiverCrossSectionSample;
  DeepWaterCol, WhiteFoamCol: TVector3;
begin
  FPeakFlowSpeedMps := 0.0;
  FMeanFoamFactor := 0.0;
  FGeneratedTriangleCount := 0;
  if Length(FKnots) < 2 then Exit;

  DeepWaterCol := Vector3(0.08, 0.44, 0.74);
  WhiteFoamCol := Vector3(0.94, 0.98, 1.00);
  SumFoam := 0.0;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    for I := 0 to FRibbonSubdivisions - 1 do
    begin
      U0 := I / FRibbonSubdivisions;
      U1 := (I + 1) / FRibbonSubdivisions;
      EvaluateLocalKnotState(U0, P0, W0, D0);
      EvaluateLocalKnotState(U1, P1, W1, D1);
      S0 := SampleRiverAtParam(U0);
      S1 := SampleRiverAtParam(U1);

      if S0.FlowSpeedMps > FPeakFlowSpeedMps then FPeakFlowSpeedMps := S0.FlowSpeedMps;
      if S1.FlowSpeedMps > FPeakFlowSpeedMps then FPeakFlowSpeedMps := S1.FlowSpeedMps;
      SumFoam := SumFoam + S0.WhitewaterFoamFactor;

      Tan0 := P1 - P0;
      Tan0.Y := 0.0;
      if Tan0.LengthSqr < 1e-6 then Tan0 := Vector3(1, 0, 0) else Tan0 := Tan0.Normalize;
      Tan1 := Tan0;

      Side0 := TVector3.CrossProduct(Vector3(0, 1, 0), Tan0).Normalize * (W0 * 0.5);
      Side1 := TVector3.CrossProduct(Vector3(0, 1, 0), Tan1).Normalize * (W1 * 0.5);

      Col0 := Lerp(S0.WhitewaterFoamFactor, DeepWaterCol, WhiteFoamCol);
      Col1 := Lerp(S1.WhitewaterFoamFactor, DeepWaterCol, WhiteFoamCol);

      Verts.Add(P0 - Side0); Verts.Add(P0 + Side0); Verts.Add(P1 + Side1);
      Cols.Add(Col0); Cols.Add(Col0); Cols.Add(Col1);
      Verts.Add(P0 - Side0); Verts.Add(P1 + Side1); Verts.Add(P1 - Side1);
      Cols.Add(Col0); Cols.Add(Col1); Cols.Add(Col1);
    end;

    FMeanFoamFactor := SumFoam / Max(1, FRibbonSubdivisions);
    FGeneratedTriangleCount := Verts.Count div 3;

    if FShowRiverMesh then
    begin
      EnsureTransientScene;
      FCoordNode.SetPoint(Verts);
      FCoordNode.FdPoint.Changed;
      FColorNode.SetColor(Cols);
      FColorNode.FdColor.Changed;
    end;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleRiverSpline.GetConfigJson: String;
var
  RootObj, KObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('discharge', FDischargeCubicMps);
    RootObj.Add('slopeGain', FSlopeVelocityGain);
    RootObj.Add('subdiv', FRibbonSubdivisions);
    Arr := TJSONArray.Create;
    for I := 0 to High(FKnots) do
    begin
      KObj := TJSONObject.Create;
      KObj.Add('x', FKnots[I].PositionLocal.X);
      KObj.Add('y', FKnots[I].PositionLocal.Y);
      KObj.Add('z', FKnots[I].PositionLocal.Z);
      KObj.Add('w', FKnots[I].WidthMeters);
      KObj.Add('d', FKnots[I].DepthMeters);
      Arr.Add(KObj);
    end;
    RootObj.Add('knots', Arr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleRiverSpline.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, KObj: TJSONObject;
  Arr: TJSONArray;
  I, PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FDischargeCubicMps := EnsureRange(RootObj.Get('discharge', FDischargeCubicMps), 0.5, 500.0);
      FSlopeVelocityGain := EnsureRange(RootObj.Get('slopeGain', FSlopeVelocityGain), 0.0, 30.0);
      FRibbonSubdivisions := EnsureRange(RootObj.Get('subdiv', FRibbonSubdivisions), 8, 256);
      Arr := RootObj.Find('knots', jtArray) as TJSONArray;
      if (Arr <> nil) and (Arr.Count >= 2) then
      begin
        SetLength(FKnots, Arr.Count);
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            KObj := TJSONObject(Arr.Items[I]);
            FKnots[I].PositionLocal := Vector3(KObj.Get('x', 0.0), KObj.Get('y', 0.0), KObj.Get('z', 0.0));
            FKnots[I].WidthMeters := Max(0.4, KObj.Get('w', 4.0));
            FKnots[I].DepthMeters := Max(0.15, KObj.Get('d', 1.2));
          end;
      end;
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TRiverSplinePreset))) and
         (PresetOrd <= Ord(High(TRiverSplinePreset))) then
        FPreset := TRiverSplinePreset(PresetOrd);
      RebuildRiverRibbonMesh;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleRiverSpline.RiverSummaryBadge: String;
begin
  Result := Format('[River:Q=%.0fm3/s Peak=%.1fm/s Foam=%.0f%%]', [
    FDischargeCubicMps,
    FPeakFlowSpeedMps,
    FMeanFoamFactor * 100.0]);
end;

initialization
  RegisterSerializableComponent(TCastleRiverSpline, ['Water & Terrain', 'River Spline Rapids & Drift']);
end.
