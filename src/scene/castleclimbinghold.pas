{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Procedural free-climbing handhold/ledge scanner using WorldRay lip-depth
  detection, static vs. Dyno-leap BFS reachability graphs, and overhang/rain
  stamina drain modeling (Milestone Phase 410). }
unit CastleClimbingHold;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset climber physique, arm reach & stamina endurance profiles. }
  TClimbingHoldPreset = (
    chpAthleticRockClimber,
    chpHeavyArmoredMountaineer,
    chpAssassinSpeedScaler
  );

  { Extracted 3D handhold / ledge lip node on a cliff or tower facade. }
  TClimbingHoldNode = record
    HoldIndex: Integer;
    WorldGripPos: TVector3;
    LipDepthMeters: Single;
    StaticNeighborCount: Integer;
    DynoNeighborCount: Integer;
  end;

  { Procedural free-climbing hold scanner & route reachability component. }
  TCastleClimbingHoldScanner = class(TCastleTransform)
  private
    FPreset: TClimbingHoldPreset;
    FScanWidthMeters: Single;
    FScanHeightMeters: Single;
    FMaxWallProbeDistMeters: Single;
    FMinLedgeLipDepthMeters: Single;
    FMaxStaticLimbReachMeters: Single;
    FMaxDynoLeapReachMeters: Single;
    FBaseStaminaDrainPerSec: Single;
    FDynoBurstStaminaCost: Single;
    FShowPreview: Boolean;
    FHolds: array of TClimbingHoldNode;
    FStaticEdgeCount: Integer;
    FDynoEdgeCount: Integer;
    FPreviewRoot: TCastleTransform;
    FPreviewGraphScene: TCastleScene;
    procedure SetPreset(const AValue: TClimbingHoldPreset);
    procedure SetShowPreview(const AValue: Boolean);
    procedure RebuildReachEdges;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TClimbingHoldPreset);
    procedure ClearHolds;
    function AddManualHold(const AWorldGripPos: TVector3;
      const ALipDepthMeters: Single = 0.20): Integer;

    { Scan the cliff/tower face in front of -Z via paired horizontal + downward
      WorldRay probes, extracting only genuine protruding ledge lips while
      rejecting smooth sheer wall faces. }
    function ScanCliffLedgeHolds(
      const AWorldRoot: TCastleAbstractRootTransform): Integer;

    { Breadth-First Search from lowest base hold (Y <= ABaseMaxY) to summit
      elevation (Y >= ASummitMinY) using static reach or Dyno leaps. }
    function CanReachSummitBFS(const ABaseMaxY, ASummitMinY: Single;
      const AAllowDynoLeaps: Boolean; out AHopCount: Integer): Boolean;

    { Evaluate stamina drain rate [stamina/sec] for wall overhang angle
      (-30 deg inclined slab, 0 deg vertical, +40 deg ceiling overhang) & rain. }
    function ComputeStaminaDrainPerSec(
      const AOverhangAngleDeg, ARainWetness01: Single): Single;

    function HoldCount: Integer;
    function GetHold(const AIndex: Integer): TClimbingHoldNode;

    procedure RebuildPreview;
    procedure ClearPreview;
    function ClimbSummaryBadge: String;

    property StaticEdgeCount: Integer read FStaticEdgeCount;
    property DynoEdgeCount: Integer read FDynoEdgeCount;
  published
    property Preset: TClimbingHoldPreset
      read FPreset write SetPreset default chpAthleticRockClimber;
    property ScanWidthMeters: Single read FScanWidthMeters write FScanWidthMeters;
    property ScanHeightMeters: Single read FScanHeightMeters write FScanHeightMeters;
    property MaxWallProbeDistMeters: Single
      read FMaxWallProbeDistMeters write FMaxWallProbeDistMeters;
    property MinLedgeLipDepthMeters: Single
      read FMinLedgeLipDepthMeters write FMinLedgeLipDepthMeters;
    property MaxStaticLimbReachMeters: Single
      read FMaxStaticLimbReachMeters write FMaxStaticLimbReachMeters;
    property MaxDynoLeapReachMeters: Single
      read FMaxDynoLeapReachMeters write FMaxDynoLeapReachMeters;
    property BaseStaminaDrainPerSec: Single
      read FBaseStaminaDrainPerSec write FBaseStaminaDrainPerSec;
    property DynoBurstStaminaCost: Single
      read FDynoBurstStaminaCost write FDynoBurstStaminaCost;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function ClimbingHoldPresetToString(const APreset: TClimbingHoldPreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function ClimbingHoldPresetToString(const APreset: TClimbingHoldPreset): String;
begin
  case APreset of
    chpAthleticRockClimber:     Result := 'AthleticRockClimber';
    chpHeavyArmoredMountaineer: Result := 'HeavyArmoredMountaineer';
    chpAssassinSpeedScaler:     Result := 'AssassinSpeedScaler';
  end;
end;

constructor TCastleClimbingHoldScanner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FScanWidthMeters := 6.0;
  FScanHeightMeters := 8.0;
  FMaxWallProbeDistMeters := 5.0;
  ApplyPreset(chpAthleticRockClimber);
end;

destructor TCastleClimbingHoldScanner.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleClimbingHoldScanner.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'ScanWidthMeters', 'ScanHeightMeters',
       'MaxWallProbeDistMeters', 'MinLedgeLipDepthMeters',
       'MaxStaticLimbReachMeters', 'MaxDynoLeapReachMeters',
       'BaseStaminaDrainPerSec', 'DynoBurstStaminaCost', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleClimbingHoldScanner.SetPreset(const AValue: TClimbingHoldPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleClimbingHoldScanner.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleClimbingHoldScanner.ApplyPreset(const APreset: TClimbingHoldPreset);
begin
  FPreset := APreset;
  case APreset of
    chpAthleticRockClimber:
      begin
        FMinLedgeLipDepthMeters := 0.08;
        FMaxStaticLimbReachMeters := 1.70;
        FMaxDynoLeapReachMeters := 2.85;
        FBaseStaminaDrainPerSec := 6.5;
        FDynoBurstStaminaCost := 22.0;
      end;
    chpHeavyArmoredMountaineer:
      begin
        FMinLedgeLipDepthMeters := 0.16;
        FMaxStaticLimbReachMeters := 1.35;
        FMaxDynoLeapReachMeters := 1.90;
        FBaseStaminaDrainPerSec := 13.0;
        FDynoBurstStaminaCost := 38.0;
      end;
    chpAssassinSpeedScaler:
      begin
        FMinLedgeLipDepthMeters := 0.06;
        FMaxStaticLimbReachMeters := 1.85;
        FMaxDynoLeapReachMeters := 3.25;
        FBaseStaminaDrainPerSec := 4.2;
        FDynoBurstStaminaCost := 16.0;
      end;
  end;
  RebuildReachEdges;
  if FShowPreview then
    RebuildPreview;
end;

procedure TCastleClimbingHoldScanner.ClearHolds;
begin
  SetLength(FHolds, 0);
  FStaticEdgeCount := 0;
  FDynoEdgeCount := 0;
  ClearPreview;
end;

function TCastleClimbingHoldScanner.AddManualHold(
  const AWorldGripPos: TVector3; const ALipDepthMeters: Single): Integer;
var
  N: Integer;
begin
  N := Length(FHolds);
  SetLength(FHolds, N + 1);
  FHolds[N] := Default(TClimbingHoldNode);
  FHolds[N].HoldIndex := N;
  FHolds[N].WorldGripPos := AWorldGripPos;
  FHolds[N].LipDepthMeters := Max(0.02, ALipDepthMeters);
  RebuildReachEdges;
  if FShowPreview then
    RebuildPreview;
  Result := N;
end;

procedure TCastleClimbingHoldScanner.RebuildReachEdges;
var
  I, J, N: Integer;
  D, RStat, RDyno: Single;
begin
  N := Length(FHolds);
  FStaticEdgeCount := 0;
  FDynoEdgeCount := 0;
  RStat := Max(0.25, FMaxStaticLimbReachMeters);
  RDyno := Max(RStat, FMaxDynoLeapReachMeters);

  for I := 0 to N - 1 do
  begin
    FHolds[I].StaticNeighborCount := 0;
    FHolds[I].DynoNeighborCount := 0;
  end;

  for I := 0 to N - 2 do
    for J := I + 1 to N - 1 do
    begin
      D := PointsDistance(FHolds[I].WorldGripPos, FHolds[J].WorldGripPos);
      if D <= RStat then
      begin
        Inc(FHolds[I].StaticNeighborCount);
        Inc(FHolds[J].StaticNeighborCount);
        Inc(FStaticEdgeCount);
      end else
      if D <= RDyno then
      begin
        Inc(FHolds[I].DynoNeighborCount);
        Inc(FHolds[J].DynoNeighborCount);
        Inc(FDynoEdgeCount);
      end;
    end;
end;

function TCastleClimbingHoldScanner.ScanCliffLedgeHolds(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;
var
  ActiveRoot: TCastleAbstractRootTransform;

  function RayNearestDist(const AOrig, ADir: TVector3; const AMaxDist: Single;
    out AHitPoint: TVector3; out AHitDist: Single): Boolean;
  var
    RH: TRayCollision;
    K: Integer;
    Item: TCastleTransform;
    D: Single;
  begin
    Result := False;
    AHitPoint := AOrig;
    AHitDist := AMaxDist + 10.0;
    if ActiveRoot = nil then Exit;
    RH := ActiveRoot.WorldRay(AOrig, ADir);
    try
      if RH = nil then Exit;
      for K := 0 to RH.Count - 1 do
      begin
        Item := RH[K].Item;
        if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
        if csTransient in Item.ComponentStyle then Continue;
        D := PointsDistance(AOrig, RH[K].Point);
        if (D >= 0.02) and (D <= AMaxDist) and (D < AHitDist) then
        begin
          AHitDist := D;
          AHitPoint := RH[K].Point;
          Result := True;
        end;
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

  function TooCloseToExistingHold(const APos: TVector3): Boolean;
  var
    M: Integer;
  begin
    for M := 0 to High(FHolds) do
      if PointsDistance(FHolds[M].WorldGripPos, APos) < 0.32 then
        Exit(True);
    Result := False;
  end;

const
  Cols = 9;
  Rows = 32;
var
  WT: TMatrix4;
  FwdDir: TVector3;
  C, R, N: Integer;
  LX, LY, MaxProbe, MinLip, DLow, DHigh, LipDepth, DTop: Single;
  OrigLow, OrigHigh, HitLow, HitHigh, TopProbeOrig, LipWorld: TVector3;
  HasLow, HasHigh: Boolean;
begin
  ClearHolds;
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;
  if ActiveRoot = nil then Exit(0);

  if HasWorldTransform then WT := WorldTransform else WT := Transform;
  FwdDir := WT.MultDirection(Vector3(0.0, 0.0, -1.0));
  if FwdDir.LengthSqr > 1e-6 then
    FwdDir := FwdDir.Normalize
  else
    FwdDir := Vector3(0.0, 0.0, -1.0);

  MaxProbe := Max(0.5, FMaxWallProbeDistMeters);
  MinLip := Max(0.03, FMinLedgeLipDepthMeters);

  for C := 0 to Cols - 1 do
  begin
    LX := -FScanWidthMeters * 0.5 + C * (FScanWidthMeters / (Cols - 1));
    for R := 0 to Rows - 1 do
    begin
      LY := 0.25 + R * (FScanHeightMeters / Rows);
      OrigLow := WT.MultPoint(Vector3(LX, LY, 0.0));
      OrigHigh := WT.MultPoint(Vector3(LX, LY + 0.26, 0.0));

      HasLow := RayNearestDist(OrigLow, FwdDir, MaxProbe, HitLow, DLow);
      if not HasLow then Continue;

      HasHigh := RayNearestDist(OrigHigh, FwdDir, MaxProbe, HitHigh, DHigh);
      if HasHigh then
        LipDepth := DHigh - DLow
      else
        LipDepth := MaxProbe - DLow;

      if LipDepth >= MinLip then
      begin
        { Confirm exposed upward-facing horizontal ledge lip via downward ray }
        TopProbeOrig := OrigHigh + FwdDir * (DLow + Min(0.06, LipDepth * 0.5));
        if RayNearestDist(TopProbeOrig, Vector3(0.0, -1.0, 0.0), 0.40, LipWorld, DTop) then
        begin
          if not TooCloseToExistingHold(LipWorld) then
          begin
            N := Length(FHolds);
            SetLength(FHolds, N + 1);
            FHolds[N] := Default(TClimbingHoldNode);
            FHolds[N].HoldIndex := N;
            FHolds[N].WorldGripPos := LipWorld;
            FHolds[N].LipDepthMeters := LipDepth;
          end;
        end;
      end;
    end;
  end;

  RebuildReachEdges;
  if FShowPreview then
    RebuildPreview;
  Result := Length(FHolds);
end;

function TCastleClimbingHoldScanner.CanReachSummitBFS(
  const ABaseMaxY, ASummitMinY: Single; const AAllowDynoLeaps: Boolean;
  out AHopCount: Integer): Boolean;
var
  N, Head, Tail, Cur, J: Integer;
  Queue, DistHops: array of Integer;
  MaxEdgeLen: Single;
begin
  Result := False;
  AHopCount := -1;
  N := Length(FHolds);
  if N = 0 then Exit;

  if AAllowDynoLeaps then
    MaxEdgeLen := Max(FMaxStaticLimbReachMeters, FMaxDynoLeapReachMeters)
  else
    MaxEdgeLen := FMaxStaticLimbReachMeters;

  SetLength(Queue, N);
  SetLength(DistHops, N);
  Head := 0;
  Tail := 0;

  for J := 0 to N - 1 do
    if FHolds[J].WorldGripPos.Y <= ABaseMaxY then
    begin
      DistHops[J] := 0;
      Queue[Tail] := J;
      Inc(Tail);
    end else
      DistHops[J] := -1;

  while Head < Tail do
  begin
    Cur := Queue[Head];
    Inc(Head);
    if FHolds[Cur].WorldGripPos.Y >= ASummitMinY then
    begin
      AHopCount := DistHops[Cur];
      Exit(True);
    end;

    for J := 0 to N - 1 do
      if (DistHops[J] < 0) and
         (PointsDistance(FHolds[Cur].WorldGripPos, FHolds[J].WorldGripPos) <= MaxEdgeLen) then
      begin
        DistHops[J] := DistHops[Cur] + 1;
        Queue[Tail] := J;
        Inc(Tail);
      end;
  end;
end;

function TCastleClimbingHoldScanner.ComputeStaminaDrainPerSec(
  const AOverhangAngleDeg, ARainWetness01: Single): Single;
var
  AngFactor, RainFactor: Single;
begin
  { Inclined slab (< 0 deg) reduces arm load; negative roof overhang (> 0 deg)
    multiplies grip load up to 3.2x! }
  if AOverhangAngleDeg < 0.0 then
    AngFactor := Max(0.25, 1.0 + AOverhangAngleDeg * 0.018)
  else
    AngFactor := 1.0 + Power(AOverhangAngleDeg / 20.0, 1.35);

  RainFactor := 1.0 + 1.45 * Clamped(ARainWetness01, 0.0, 1.0);
  Result := Max(0.1, FBaseStaminaDrainPerSec) * AngFactor * RainFactor;
end;

function TCastleClimbingHoldScanner.HoldCount: Integer;
begin
  Result := Length(FHolds);
end;

function TCastleClimbingHoldScanner.GetHold(
  const AIndex: Integer): TClimbingHoldNode;
begin
  if (AIndex >= 0) and (AIndex < Length(FHolds)) then
    Result := FHolds[AIndex]
  else
    Result := Default(TClimbingHoldNode);
end;

procedure TCastleClimbingHoldScanner.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewGraphScene := nil;
  end;
end;

procedure TCastleClimbingHoldScanner.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  InvWT, WT: TMatrix4;
  Pts: array of TVector3;
  Counts: array of Int32;
  N, I, J, SegCount: Integer;
  D, RDyno: Single;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  N := Length(FHolds);
  if (not FShowPreview) or (N = 0) then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  RDyno := Max(FMaxStaticLimbReachMeters, FMaxDynoLeapReachMeters);
  SegCount := 0;
  for I := 0 to N - 2 do
    for J := I + 1 to N - 1 do
    begin
      D := PointsDistance(FHolds[I].WorldGripPos, FHolds[J].WorldGripPos);
      if D <= RDyno then
      begin
        SetLength(Pts, (SegCount + 1) * 2);
        SetLength(Counts, SegCount + 1);
        Pts[SegCount * 2] := InvWT.MultPoint(FHolds[I].WorldGripPos);
        Pts[SegCount * 2 + 1] := InvWT.MultPoint(FHolds[J].WorldGripPos);
        Counts[SegCount] := 2;
        Inc(SegCount);
      end;
    end;

  if SegCount = 0 then
  begin
    SetLength(Pts, 2);
    SetLength(Counts, 1);
    Pts[0] := InvWT.MultPoint(FHolds[0].WorldGripPos);
    Pts[1] := Pts[0] + Vector3(0.0, 0.2, 0.0);
    Counts[0] := 2;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'ClimbingHoldPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewGraphScene := TCastleScene.Create(FPreviewRoot);
  FPreviewGraphScene.SetTransient;
  FPreviewGraphScene.Name := 'ClimbingHoldPreviewGraph';
  FPreviewGraphScene.Pickable := False;
  FPreviewGraphScene.Collides := False;
  FPreviewRoot.Add(FPreviewGraphScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.35, 0.95, 0.52);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewGraphScene.Load(RootNode, True);
end;

function TCastleClimbingHoldScanner.ClimbSummaryBadge: String;
begin
  Result := Format('[FreeClimb:%d holds Edges=%d+%d]', [
    Length(FHolds), FStaticEdgeCount, FDynoEdgeCount]);
end;

initialization
  RegisterSerializableComponent(TCastleClimbingHoldScanner, 'Free-Climbing Hold Scanner');

end.
