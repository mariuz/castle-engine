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

{ Procedural Content Generation (PCG) spline-road settlement, crossroads graph,
  zero-overlap setback building parcel slicer, multi-story gabled-roof mesh
  synthesizer, streetlamp placer, and perimeter palisade fence generator
  (Phase 335 — Unreal Engine 6.0+ PCG Biome Settlements parity). }
unit CastlePcgSettlement;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils, CastleTriangles,
  CastleTransform, CastleScene, X3DNodes;

type
  { Architectural layout topology presets for TCastlePcgSettlement. }
  TPcgSettlementPreset = (
    pspCrossroadsHamlet,
    pspWalledMarketTown,
    pspLinearHighwayOutpost
  );

  { 2D XZ road segment centerline and width. }
  TPcgRoadSegment = record
    StartXZ: TVector2;
    EndXZ: TVector2;
    WidthMeters: Single;
  end;

  { Non-overlapping subdivided building parcel and procedural house parameters. }
  TPcgBuildingLot = record
    CenterWorld: TVector3;
    HeadingRad: Single;
    WidthX: Single;
    DepthZ: Single;
    WallHeight: Single;
    RoofPeakHeight: Single;
    FloorsCount: Integer;
    AabbMinXZ: TVector2;
    AabbMaxXZ: TVector2;
    WallColorRGB: TVector3;
    RoofColorRGB: TVector3;
  end;

  { Roadside streetlamp or perimeter palisade fence post. }
  TPcgStreetProp = record
    PosWorld: TVector3;
    IsFencePost: Boolean;
    HeightMeters: Single;
  end;

  { Procedural village / town generator that builds a road network, subdivides
    non-overlapping setback building parcels, snaps foundations to terrain via
    WorldRay, and emits a single batched csTransient X3D mesh. }
  TCastlePcgSettlement = class(TCastleTransform)
  private
    FPreset: TPcgSettlementPreset;
    FRandomSeed: Integer;
    FSettlementRadius: Single;
    FRoadWidth: Single;
    FRoadSetbackMargin: Single;
    FLotWidthMeters: Single;
    FLotDepthMeters: Single;
    FLotSpacingGap: Single;
    FMaxBuildingFloors: Integer;
    FGenerateStreetlamps: Boolean;
    FGeneratePerimeterFence: Boolean;

    FRoads: array of TPcgRoadSegment;
    FLots: array of TPcgBuildingLot;
    FProps: array of TPcgStreetProp;
    FStreetlampCount: Integer;
    FFencePostCount: Integer;
    FGeneratedTriangleCount: Integer;
    FTransientScene: TCastleScene;

    procedure SetPreset(const AValue: TPcgSettlementPreset);
    procedure SetRandomSeed(const AValue: Integer);
    procedure SetSettlementRadius(const AValue: Single);
    procedure SetRoadWidth(const AValue: Single);
    procedure SetRoadSetbackMargin(const AValue: Single);
    procedure SetLotWidthMeters(const AValue: Single);
    procedure SetLotDepthMeters(const AValue: Single);
    procedure SetLotSpacingGap(const AValue: Single);
    procedure SetMaxBuildingFloors(const AValue: Integer);
    procedure SetGenerateStreetlamps(const AValue: Boolean);
    procedure SetGeneratePerimeterFence(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);

    procedure GenerateRoadGraphForPreset;
    function SampleGroundHeight(const AWorldForSnap: TCastleAbstractRootTransform;
      const AX, AZ, ADefaultY: Single): Single;
    procedure BuildBatchedSettlementMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Rebuild roads, non-overlapping setback building parcels, streetlamps, and
      perimeter fence. Pass AWorldForSnap (e.g. Viewport.Items) to raycast
      downward and snap every foundation onto underlying scene/terrain meshes. }
    procedure RebuildSettlement(const AWorldForSnap: TCastleAbstractRootTransform = nil);

    function RoadSegmentCount: Integer;
    function GetRoadSegment(const AIndex: Integer): TPcgRoadSegment;
    function BuildingLotCount: Integer;
    function GetBuildingLot(const AIndex: Integer): TPcgBuildingLot;
    function PropCount: Integer;
    function GetProp(const AIndex: Integer): TPcgStreetProp;

    { Exact verification invariants: pairwise AABB overlap count & road intrusion count. }
    function CountOverlappingLotPairs: Integer;
    function CountRoadIntrudingLots: Integer;
    function SettlementSummaryBadge: String;

    property StreetlampCount: Integer read FStreetlampCount;
    property FencePostCount: Integer read FFencePostCount;
    property GeneratedTriangleCount: Integer read FGeneratedTriangleCount;
  published
    property Preset: TPcgSettlementPreset read FPreset write SetPreset default pspCrossroadsHamlet;
    property RandomSeed: Integer read FRandomSeed write SetRandomSeed default 2026;
    property SettlementRadius: Single read FSettlementRadius write SetSettlementRadius {$ifdef FPC}default 32.0{$endif};
    property RoadWidth: Single read FRoadWidth write SetRoadWidth {$ifdef FPC}default 5.0{$endif};
    property RoadSetbackMargin: Single read FRoadSetbackMargin write SetRoadSetbackMargin {$ifdef FPC}default 1.8{$endif};
    property LotWidthMeters: Single read FLotWidthMeters write SetLotWidthMeters {$ifdef FPC}default 7.0{$endif};
    property LotDepthMeters: Single read FLotDepthMeters write SetLotDepthMeters {$ifdef FPC}default 6.5{$endif};
    property LotSpacingGap: Single read FLotSpacingGap write SetLotSpacingGap {$ifdef FPC}default 2.2{$endif};
    property MaxBuildingFloors: Integer read FMaxBuildingFloors write SetMaxBuildingFloors default 3;
    property GenerateStreetlamps: Boolean read FGenerateStreetlamps write SetGenerateStreetlamps default True;
    property GeneratePerimeterFence: Boolean read FGeneratePerimeterFence write SetGeneratePerimeterFence default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

function PcgSettlementPresetToDisplayName(const APreset: TPcgSettlementPreset): String;
function PointToSegmentDistance2D(const P, A, B: TVector2): Single;

implementation

uses
  fpjson, jsonparser,
  CastleComponentSerialize;

function PcgSettlementPresetToDisplayName(const APreset: TPcgSettlementPreset): String;
begin
  case APreset of
    pspCrossroadsHamlet: Result := 'Crossroads Hamlet';
    pspWalledMarketTown: Result := 'Walled Market Town';
    pspLinearHighwayOutpost: Result := 'Linear Highway Outpost';
  end;
end;

function PointToSegmentDistance2D(const P, A, B: TVector2): Single;
var
  AB, AP: TVector2;
  LenSq, T: Single;
  Closest: TVector2;
begin
  AB := B - A;
  LenSq := AB.LengthSqr;
  if LenSq < 1e-6 then
    Exit(PointsDistance(P, A));
  AP := P - A;
  T := EnsureRange(TVector2.DotProduct(AP, AB) / LenSq, 0.0, 1.0);
  Closest := A + AB * T;
  Result := PointsDistance(P, Closest);
end;

{$PUSH}{$Q-}{$R-}
function NextSeedFloat01(var State: Cardinal): Single;
begin
  if State = 0 then
    State := 195827341;
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := (State and $FFFF) / 65535.0;
end;
{$POP}

function Aabb2DOverlapWithMargin(const MinA, MaxA, MinB, MaxB: TVector2;
  const Margin: Single): Boolean;
begin
  Result :=
    (MinA.X < MaxB.X + Margin) and (MaxA.X + Margin > MinB.X) and
    (MinA.Y < MaxB.Y + Margin) and (MaxA.Y + Margin > MinB.Y);
end;

function AabbToSegmentMinDistance2D(const BoxMin, BoxMax, SegA, SegB: TVector2): Single;
var
  Corners: array[0..3] of TVector2;
  Center: TVector2;
  I: Integer;
begin
  { Check all 4 corners, 4 edge midpoints, and box center against road segment }
  Corners[0] := Vector2(BoxMin.X, BoxMin.Y);
  Corners[1] := Vector2(BoxMax.X, BoxMin.Y);
  Corners[2] := Vector2(BoxMax.X, BoxMax.Y);
  Corners[3] := Vector2(BoxMin.X, BoxMax.Y);
  Center := 0.5 * (BoxMin + BoxMax);
  Result := PointToSegmentDistance2D(Center, SegA, SegB);
  for I := 0 to 3 do
  begin
    Result := Min(Result, PointToSegmentDistance2D(Corners[I], SegA, SegB));
    Result := Min(Result, PointToSegmentDistance2D(
      0.5 * (Corners[I] + Corners[(I + 1) mod 4]), SegA, SegB));
  end;
end;

{ TCastlePcgSettlement ------------------------------------------------------- }

constructor TCastlePcgSettlement.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := pspCrossroadsHamlet;
  FRandomSeed := 2026;
  FSettlementRadius := 32.0;
  FRoadWidth := 5.0;
  FRoadSetbackMargin := 1.8;
  FLotWidthMeters := 7.0;
  FLotDepthMeters := 6.5;
  FLotSpacingGap := 2.2;
  FMaxBuildingFloors := 3;
  FGenerateStreetlamps := True;
  FGeneratePerimeterFence := True;
  RebuildSettlement(nil);
end;

destructor TCastlePcgSettlement.Destroy;
begin
  FreeAndNil(FTransientScene);
  SetLength(FRoads, 0);
  SetLength(FLots, 0);
  SetLength(FProps, 0);
  inherited Destroy;
end;

function TCastlePcgSettlement.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'RandomSeed', 'SettlementRadius', 'RoadWidth',
       'RoadSetbackMargin', 'LotWidthMeters', 'LotDepthMeters',
       'LotSpacingGap', 'MaxBuildingFloors', 'GenerateStreetlamps',
       'GeneratePerimeterFence', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastlePcgSettlement.SetPreset(const AValue: TPcgSettlementPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  RebuildSettlement(nil);
end;

procedure TCastlePcgSettlement.SetRandomSeed(const AValue: Integer);
begin
  if FRandomSeed = AValue then Exit;
  FRandomSeed := AValue;
  RebuildSettlement(nil);
end;

procedure TCastlePcgSettlement.SetSettlementRadius(const AValue: Single);
begin
  FSettlementRadius := Max(14.0, AValue);
end;

procedure TCastlePcgSettlement.SetRoadWidth(const AValue: Single);
begin
  FRoadWidth := Max(2.0, AValue);
end;

procedure TCastlePcgSettlement.SetRoadSetbackMargin(const AValue: Single);
begin
  FRoadSetbackMargin := Max(0.5, AValue);
end;

procedure TCastlePcgSettlement.SetLotWidthMeters(const AValue: Single);
begin
  FLotWidthMeters := Max(3.5, AValue);
end;

procedure TCastlePcgSettlement.SetLotDepthMeters(const AValue: Single);
begin
  FLotDepthMeters := Max(3.5, AValue);
end;

procedure TCastlePcgSettlement.SetLotSpacingGap(const AValue: Single);
begin
  FLotSpacingGap := Max(0.5, AValue);
end;

procedure TCastlePcgSettlement.SetMaxBuildingFloors(const AValue: Integer);
begin
  FMaxBuildingFloors := EnsureRange(AValue, 1, 5);
end;

procedure TCastlePcgSettlement.SetGenerateStreetlamps(const AValue: Boolean);
begin
  if FGenerateStreetlamps = AValue then Exit;
  FGenerateStreetlamps := AValue;
  RebuildSettlement(nil);
end;

procedure TCastlePcgSettlement.SetGeneratePerimeterFence(const AValue: Boolean);
begin
  if FGeneratePerimeterFence = AValue then Exit;
  FGeneratePerimeterFence := AValue;
  RebuildSettlement(nil);
end;

procedure TCastlePcgSettlement.GenerateRoadGraphForPreset;
var
  R, SideZ: Single;

  procedure AddRoad(const AX1, AZ1, AX2, AZ2, AWidth: Single);
  var
    Idx: Integer;
  begin
    Idx := Length(FRoads);
    SetLength(FRoads, Idx + 1);
    FRoads[Idx] := Default(TPcgRoadSegment);
    FRoads[Idx].StartXZ := Vector2(AX1, AZ1);
    FRoads[Idx].EndXZ := Vector2(AX2, AZ2);
    FRoads[Idx].WidthMeters := AWidth;
  end;

begin
  SetLength(FRoads, 0);
  R := FSettlementRadius;
  case FPreset of
    pspCrossroadsHamlet:
      begin
        AddRoad(-R, 0.0, +R, 0.0, FRoadWidth);
        AddRoad(0.0, -R, 0.0, +R, FRoadWidth);
      end;
    pspWalledMarketTown:
      begin
        SideZ := R * 0.52;
        AddRoad(-R, 0.0, +R, 0.0, FRoadWidth);
        AddRoad(0.0, -R, 0.0, +R, FRoadWidth);
        AddRoad(-R * 0.85, -SideZ, +R * 0.85, -SideZ, FRoadWidth * 0.82);
        AddRoad(-R * 0.85, +SideZ, +R * 0.85, +SideZ, FRoadWidth * 0.82);
      end;
    pspLinearHighwayOutpost:
      begin
        AddRoad(-R, 0.0, +R, 0.0, FRoadWidth * 1.15);
      end;
  end;
end;

function TCastlePcgSettlement.SampleGroundHeight(
  const AWorldForSnap: TCastleAbstractRootTransform;
  const AX, AZ, ADefaultY: Single): Single;
var
  RayHit: TRayCollision;
  SavedExists: Boolean;
begin
  Result := ADefaultY;
  if AWorldForSnap = nil then
    Exit;

  SavedExists := (FTransientScene <> nil) and FTransientScene.Exists;
  if FTransientScene <> nil then
    FTransientScene.Exists := False;
  try
    RayHit := AWorldForSnap.WorldRay(Vector3(AX, ADefaultY + 80.0, AZ), Vector3(0, -1, 0));
    try
      if (RayHit <> nil) and (RayHit.Count > 0) then
        Result := RayHit.First.Point.Y;
    finally
      FreeAndNil(RayHit);
    end;
  finally
    if FTransientScene <> nil then
      FTransientScene.Exists := SavedExists;
  end;
end;

procedure TCastlePcgSettlement.RebuildSettlement(
  const AWorldForSnap: TCastleAbstractRootTransform);
var
  Rng: Cardinal;
  BaseOrigin: TVector3;
  RIdx, SideSign, ExistingIdx, Floors, I, FenceSteps: Integer;
  SegA, SegB, Dir2, Perp2, CenterXZ, CandMin, CandMax: TVector2;
  SegLen, AlongDist, StepStride, OffsetFromRoad, W, D, CosH, SinH, ExtX, ExtZ: Single;
  Interfere: Boolean;
  Lot: TPcgBuildingLot;
  Prop: TPcgStreetProp;
  Ang, FenceR, GateDist: Single;
begin
  if HasParent then
    BaseOrigin := WorldTranslation
  else
    BaseOrigin := Translation;

  {$PUSH}{$Q-}{$R-}
  Rng := Cardinal((UInt64(Cardinal(Abs(FRandomSeed))) * UInt64(1664525) + UInt64(1013904223)) and $FFFFFFFF);
  {$POP}
  GenerateRoadGraphForPreset;
  SetLength(FLots, 0);
  SetLength(FProps, 0);
  FStreetlampCount := 0;
  FFencePostCount := 0;

  StepStride := FLotWidthMeters + FLotSpacingGap;

  for RIdx := 0 to High(FRoads) do
  begin
    SegA := FRoads[RIdx].StartXZ + Vector2(BaseOrigin.X, BaseOrigin.Z);
    SegB := FRoads[RIdx].EndXZ + Vector2(BaseOrigin.X, BaseOrigin.Z);
    Dir2 := SegB - SegA;
    SegLen := Dir2.Length;
    if SegLen < StepStride then
      Continue;
    Dir2 := Dir2 / SegLen;
    Perp2 := Vector2(-Dir2.Y, Dir2.X);

    for SideSign := -1 to 1 do
    begin
      if SideSign = 0 then
        Continue;
      AlongDist := 0.5 * FLotWidthMeters + 2.5;
      while AlongDist <= (SegLen - 0.5 * FLotWidthMeters - 2.5) do
      begin
        W := FLotWidthMeters * (0.86 + 0.22 * NextSeedFloat01(Rng));
        D := FLotDepthMeters * (0.86 + 0.22 * NextSeedFloat01(Rng));
        OffsetFromRoad := 0.5 * FRoads[RIdx].WidthMeters + FRoadSetbackMargin + 0.5 * D;
        CenterXZ := SegA + Dir2 * AlongDist + Perp2 * (SideSign * OffsetFromRoad);

        { Keep inside settlement perimeter margin }
        if PointsDistance(CenterXZ, Vector2(BaseOrigin.X, BaseOrigin.Z)) <= (FSettlementRadius - 0.6 * Max(W, D) - 1.5) then
        begin
          Lot := Default(TPcgBuildingLot);
          { Face toward road centerline }
          Lot.HeadingRad := ArcTan2(-SideSign * Perp2.X, -SideSign * Perp2.Y);
          Lot.WidthX := W;
          Lot.DepthZ := D;
          CosH := Abs(Cos(Lot.HeadingRad));
          SinH := Abs(Sin(Lot.HeadingRad));
          ExtX := 0.5 * (W * CosH + D * SinH);
          ExtZ := 0.5 * (W * SinH + D * CosH);
          CandMin := Vector2(CenterXZ.X - ExtX, CenterXZ.Y - ExtZ);
          CandMax := Vector2(CenterXZ.X + ExtX, CenterXZ.Y + ExtZ);

          { 1. Check strict clearance against EVERY road segment }
          Interfere := False;
          for ExistingIdx := 0 to High(FRoads) do
          begin
            if AabbToSegmentMinDistance2D(CandMin, CandMax,
                 FRoads[ExistingIdx].StartXZ + Vector2(BaseOrigin.X, BaseOrigin.Z),
                 FRoads[ExistingIdx].EndXZ + Vector2(BaseOrigin.X, BaseOrigin.Z)) <
               (0.5 * FRoads[ExistingIdx].WidthMeters + 0.35) then
            begin
              Interfere := True;
              Break;
            end;
          end;

          { 2. Check strict pairwise non-overlap against all placed lots }
          if not Interfere then
            for ExistingIdx := 0 to High(FLots) do
              if Aabb2DOverlapWithMargin(CandMin, CandMax,
                   FLots[ExistingIdx].AabbMinXZ, FLots[ExistingIdx].AabbMaxXZ, 0.35) then
              begin
                Interfere := True;
                Break;
              end;

          if not Interfere then
          begin
            Floors := 1 + Trunc(NextSeedFloat01(Rng) * FMaxBuildingFloors);
            Floors := EnsureRange(Floors, 1, FMaxBuildingFloors);
            Lot.FloorsCount := Floors;
            Lot.WallHeight := 2.85 * Floors;
            Lot.RoofPeakHeight := 1.65 + 0.25 * NextSeedFloat01(Rng);
            Lot.AabbMinXZ := CandMin;
            Lot.AabbMaxXZ := CandMax;
            Lot.CenterWorld := Vector3(
              CenterXZ.X,
              SampleGroundHeight(AWorldForSnap, CenterXZ.X, CenterXZ.Y, BaseOrigin.Y),
              CenterXZ.Y);
            Lot.WallColorRGB := Vector3(
              0.76 + 0.14 * NextSeedFloat01(Rng),
              0.71 + 0.12 * NextSeedFloat01(Rng),
              0.62 + 0.12 * NextSeedFloat01(Rng));
            Lot.RoofColorRGB := Vector3(
              0.56 + 0.20 * NextSeedFloat01(Rng),
              0.24 + 0.10 * NextSeedFloat01(Rng),
              0.16 + 0.08 * NextSeedFloat01(Rng));

            SetLength(FLots, Length(FLots) + 1);
            FLots[High(FLots)] := Lot;
          end;
        end;

        AlongDist := AlongDist + StepStride;
      end;

      { Place roadside streetlamps every ~14m along road shoulder }
      if FGenerateStreetlamps then
      begin
        AlongDist := 6.0;
        while AlongDist <= (SegLen - 4.0) do
        begin
          CenterXZ := SegA + Dir2 * AlongDist + Perp2 * (SideSign * (0.5 * FRoads[RIdx].WidthMeters + 0.65));
          Interfere := False;
          for ExistingIdx := 0 to High(FRoads) do
            if ExistingIdx <> RIdx then
              if PointToSegmentDistance2D(CenterXZ,
                   FRoads[ExistingIdx].StartXZ + Vector2(BaseOrigin.X, BaseOrigin.Z),
                   FRoads[ExistingIdx].EndXZ + Vector2(BaseOrigin.X, BaseOrigin.Z)) <
                 (0.5 * FRoads[ExistingIdx].WidthMeters + 0.3) then
              begin
                Interfere := True;
                Break;
              end;
          if not Interfere then
          begin
            Prop := Default(TPcgStreetProp);
            Prop.PosWorld := Vector3(
              CenterXZ.X,
              SampleGroundHeight(AWorldForSnap, CenterXZ.X, CenterXZ.Y, BaseOrigin.Y),
              CenterXZ.Y);
            Prop.IsFencePost := False;
            Prop.HeightMeters := 3.4;
            SetLength(FProps, Length(FProps) + 1);
            FProps[High(FProps)] := Prop;
            Inc(FStreetlampCount);
          end;
          AlongDist := AlongDist + 14.0;
        end;
      end;
    end;
  end;

  { Place perimeter palisade fence posts around settlement boundary, leaving road gates open }
  if FGeneratePerimeterFence then
  begin
    FenceR := FSettlementRadius - 0.6;
    FenceSteps := Max(16, Round((2.0 * Pi * FenceR) / 4.2));
    for I := 0 to FenceSteps - 1 do
    begin
      Ang := (2.0 * Pi * I) / FenceSteps;
      CenterXZ := Vector2(BaseOrigin.X + Cos(Ang) * FenceR, BaseOrigin.Z + Sin(Ang) * FenceR);
      Interfere := False;
      for ExistingIdx := 0 to High(FRoads) do
      begin
        GateDist := PointToSegmentDistance2D(CenterXZ,
          FRoads[ExistingIdx].StartXZ + Vector2(BaseOrigin.X, BaseOrigin.Z),
          FRoads[ExistingIdx].EndXZ + Vector2(BaseOrigin.X, BaseOrigin.Z));
        if GateDist < (0.5 * FRoads[ExistingIdx].WidthMeters + 1.4) then
        begin
          Interfere := True;
          Break;
        end;
      end;
      if not Interfere then
      begin
        Prop := Default(TPcgStreetProp);
        Prop.PosWorld := Vector3(
          CenterXZ.X,
          SampleGroundHeight(AWorldForSnap, CenterXZ.X, CenterXZ.Y, BaseOrigin.Y),
          CenterXZ.Y);
        Prop.IsFencePost := True;
        Prop.HeightMeters := 1.85;
        SetLength(FProps, Length(FProps) + 1);
        FProps[High(FProps)] := Prop;
        Inc(FFencePostCount);
      end;
    end;
  end;

  BuildBatchedSettlementMesh;
end;

procedure TCastlePcgSettlement.BuildBatchedSettlementMesh;
var
  RootNode: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
  Coord: TCoordinateNode;
  ColorNode: TColorNode;
  Verts, Colors: TVector3List;
  BaseOrigin: TVector3;
  InvWorld: TMatrix4;
  I: Integer;

  procedure AddTriW(const A, B, C, Col: TVector3);
  begin
    Verts.Add(InvWorld.MultPoint(A));
    Verts.Add(InvWorld.MultPoint(B));
    Verts.Add(InvWorld.MultPoint(C));
    Colors.Add(Col);
    Colors.Add(Col);
    Colors.Add(Col);
  end;

  procedure AddQuadW(const A, B, C, D, Col: TVector3);
  begin
    AddTriW(A, B, C, Col);
    AddTriW(A, C, D, Col);
  end;

  procedure EmitGabledHouse(const L: TPcgBuildingLot);
  var
    C, S, Hw, Hd, Y0, Y1, YPeak: Single;
    RightV, FwdV: TVector3;
    B00, B10, B11, B01, T00, T10, T11, T01, RidgeF, RidgeB: TVector3;
    WallLight, WallSide, RoofCol: TVector3;
  begin
    C := Cos(L.HeadingRad);
    S := Sin(L.HeadingRad);
    RightV := Vector3(C, 0.0, -S);
    FwdV := Vector3(S, 0.0, C);
    Hw := 0.5 * L.WidthX;
    Hd := 0.5 * L.DepthZ;
    Y0 := L.CenterWorld.Y;
    Y1 := Y0 + L.WallHeight;
    YPeak := Y1 + L.RoofPeakHeight;

    B00 := Vector3(L.CenterWorld.X, Y0, L.CenterWorld.Z) - RightV * Hw - FwdV * Hd;
    B10 := Vector3(L.CenterWorld.X, Y0, L.CenterWorld.Z) + RightV * Hw - FwdV * Hd;
    B11 := Vector3(L.CenterWorld.X, Y0, L.CenterWorld.Z) + RightV * Hw + FwdV * Hd;
    B01 := Vector3(L.CenterWorld.X, Y0, L.CenterWorld.Z) - RightV * Hw + FwdV * Hd;

    T00 := B00 + Vector3(0, L.WallHeight, 0);
    T10 := B10 + Vector3(0, L.WallHeight, 0);
    T11 := B11 + Vector3(0, L.WallHeight, 0);
    T01 := B01 + Vector3(0, L.WallHeight, 0);

    RidgeB := Vector3(L.CenterWorld.X, YPeak, L.CenterWorld.Z) - FwdV * Hd;
    RidgeF := Vector3(L.CenterWorld.X, YPeak, L.CenterWorld.Z) + FwdV * Hd;

    WallLight := L.WallColorRGB;
    WallSide := L.WallColorRGB * 0.84;
    RoofCol := L.RoofColorRGB;

    { 4 exterior walls }
    AddQuadW(B01, B11, T11, T01, WallLight);
    AddQuadW(B10, B00, T00, T10, WallLight);
    AddQuadW(B11, B10, T10, T11, WallSide);
    AddQuadW(B00, B01, T01, T00, WallSide);

    { 2 triangular gable walls + 2 pitched roof slopes }
    AddTriW(T01, T11, RidgeF, WallLight * 0.94);
    AddTriW(T10, T00, RidgeB, WallLight * 0.94);
    AddQuadW(T11, T10, RidgeB, RidgeF, RoofCol);
    AddQuadW(T00, T01, RidgeF, RidgeB, RoofCol * 0.90);
  end;

  procedure EmitPillarPost(const Pos: TVector3; const HalfW, H: Single;
    const PostCol: TVector3; const WithLantern: Boolean);
  var
    P00, P10, P11, P01, Q00, Q10, Q11, Q01: TVector3;
  begin
    P00 := Pos + Vector3(-HalfW, 0, -HalfW);
    P10 := Pos + Vector3(+HalfW, 0, -HalfW);
    P11 := Pos + Vector3(+HalfW, 0, +HalfW);
    P01 := Pos + Vector3(-HalfW, 0, +HalfW);
    Q00 := P00 + Vector3(0, H, 0);
    Q10 := P10 + Vector3(0, H, 0);
    Q11 := P11 + Vector3(0, H, 0);
    Q01 := P01 + Vector3(0, H, 0);
    AddQuadW(P01, P11, Q11, Q01, PostCol);
    AddQuadW(P10, P00, Q00, Q10, PostCol);
    AddQuadW(P11, P10, Q10, Q11, PostCol * 0.86);
    AddQuadW(P00, P01, Q01, Q00, PostCol * 0.86);
    if WithLantern then
      AddQuadW(Q01, Q11, Q10, Q00, Vector3(1.0, 0.86, 0.35))
    else
      AddQuadW(Q01, Q11, Q10, Q00, PostCol);
  end;

var
  SegA, SegB, Dir2, Perp2: TVector2;
  HalfRW: Single;
  R0, R1, R2, R3: TVector3;
begin
  FreeAndNil(FTransientScene);

  if HasParent then
    BaseOrigin := WorldTranslation
  else
    BaseOrigin := Translation;
  if (not HasParent) or (not WorldTransform.TryInverse(InvWorld)) then
    InvWorld := TMatrix4.Identity;

  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientSettlementMesh';
  FTransientScene.PreciseCollisions := True;
  FTransientScene.Pickable := False;

  RootNode := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.Roughness := 0.85;
  Mat.Metallic := 0.05;
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  Coord := TCoordinateNode.Create;
  ColorNode := TColorNode.Create;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    { 1. Cobblestone road ribbons }
    for I := 0 to High(FRoads) do
    begin
      SegA := FRoads[I].StartXZ + Vector2(BaseOrigin.X, BaseOrigin.Z);
      SegB := FRoads[I].EndXZ + Vector2(BaseOrigin.X, BaseOrigin.Z);
      Dir2 := SegB - SegA;
      if Dir2.LengthSqr < 1e-4 then
        Continue;
      Dir2 := Dir2.Normalize;
      Perp2 := Vector2(-Dir2.Y, Dir2.X);
      HalfRW := 0.5 * FRoads[I].WidthMeters;
      R0 := Vector3(SegA.X - Perp2.X * HalfRW, BaseOrigin.Y + 0.03, SegA.Y - Perp2.Y * HalfRW);
      R1 := Vector3(SegA.X + Perp2.X * HalfRW, BaseOrigin.Y + 0.03, SegA.Y + Perp2.Y * HalfRW);
      R2 := Vector3(SegB.X + Perp2.X * HalfRW, BaseOrigin.Y + 0.03, SegB.Y + Perp2.Y * HalfRW);
      R3 := Vector3(SegB.X - Perp2.X * HalfRW, BaseOrigin.Y + 0.03, SegB.Y - Perp2.Y * HalfRW);
      AddQuadW(R0, R1, R2, R3, Vector3(0.38, 0.37, 0.35));
    end;

    { 2. Subdivided gabled-roof buildings }
    for I := 0 to High(FLots) do
      EmitGabledHouse(FLots[I]);

    { 3. Streetlamps & perimeter fence posts }
    for I := 0 to High(FProps) do
      if FProps[I].IsFencePost then
        EmitPillarPost(FProps[I].PosWorld, 0.12, FProps[I].HeightMeters,
          Vector3(0.46, 0.33, 0.20), False)
      else
        EmitPillarPost(FProps[I].PosWorld, 0.10, FProps[I].HeightMeters,
          Vector3(0.24, 0.26, 0.30), True);

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

function TCastlePcgSettlement.RoadSegmentCount: Integer;
begin
  Result := Length(FRoads);
end;

function TCastlePcgSettlement.GetRoadSegment(const AIndex: Integer): TPcgRoadSegment;
begin
  if (AIndex >= 0) and (AIndex <= High(FRoads)) then
    Result := FRoads[AIndex]
  else
    Result := Default(TPcgRoadSegment);
end;

function TCastlePcgSettlement.BuildingLotCount: Integer;
begin
  Result := Length(FLots);
end;

function TCastlePcgSettlement.GetBuildingLot(const AIndex: Integer): TPcgBuildingLot;
begin
  if (AIndex >= 0) and (AIndex <= High(FLots)) then
    Result := FLots[AIndex]
  else
    Result := Default(TPcgBuildingLot);
end;

function TCastlePcgSettlement.PropCount: Integer;
begin
  Result := Length(FProps);
end;

function TCastlePcgSettlement.GetProp(const AIndex: Integer): TPcgStreetProp;
begin
  if (AIndex >= 0) and (AIndex <= High(FProps)) then
    Result := FProps[AIndex]
  else
    Result := Default(TPcgStreetProp);
end;

function TCastlePcgSettlement.CountOverlappingLotPairs: Integer;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 0 to High(FLots) do
    for J := I + 1 to High(FLots) do
      if Aabb2DOverlapWithMargin(FLots[I].AabbMinXZ, FLots[I].AabbMaxXZ,
           FLots[J].AabbMinXZ, FLots[J].AabbMaxXZ, -0.001) then
        Inc(Result);
end;

function TCastlePcgSettlement.CountRoadIntrudingLots: Integer;
var
  I, R: Integer;
  BaseOrigin: TVector3;
begin
  Result := 0;
  if HasParent then
    BaseOrigin := WorldTranslation
  else
    BaseOrigin := Translation;

  for I := 0 to High(FLots) do
    for R := 0 to High(FRoads) do
      if AabbToSegmentMinDistance2D(FLots[I].AabbMinXZ, FLots[I].AabbMaxXZ,
           FRoads[R].StartXZ + Vector2(BaseOrigin.X, BaseOrigin.Z),
           FRoads[R].EndXZ + Vector2(BaseOrigin.X, BaseOrigin.Z)) <
         (0.5 * FRoads[R].WidthMeters) then
      begin
        Inc(Result);
        Break;
      end;
end;

function TCastlePcgSettlement.SettlementSummaryBadge: String;
begin
  Result := Format('[Settlement:%s %d lots %d lamps %d tris]', [
    PcgSettlementPresetToDisplayName(FPreset),
    Length(FLots),
    FStreetlampCount,
    FGeneratedTriangleCount
  ]);
end;

function TCastlePcgSettlement.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('seed', FRandomSeed);
    Obj.Add('lotCount', Length(FLots));
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastlePcgSettlement.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
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
    if Data is TJSONObject then
      FRandomSeed := TJSONObject(Data).Get('seed', FRandomSeed);
    RebuildSettlement(nil);
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastlePcgSettlement,
    ['World & Crowds', 'PCG Village & Road Settlement (TCastlePcgSettlement)']);

end.
