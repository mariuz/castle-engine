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

{ Unreal Engine 5.5-style 3D Polygonal Recast NavMesh Volume & NavLinkProxy
  Off-Mesh Links runtime (@link(TCastleRecastNavMesh)) featuring multi-floor 3D
  headroom-aware polygon generation (stacked overpass bridges + underpass tunnels
  at identical XZ coordinates), walkable slope & step-height filtering,
  AgentRadius wall erosion, directional ANavLinkProxy off-mesh jump/drop/climb
  links, and portal-smoothed 3D A* pathfinding
  (Phase 393 — UE 5.5 ANavMeshBoundsVolume, ARecastNavMesh & ANavLinkProxy Parity). }
unit CastleRecastNavMesh;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Directional traversal mode of an @link(TRecastNavLink) (ANavLinkProxy parity). }
  TNavLinkDirection = (
    nldBothWays,
    nldLeftToRightOnly,
    nldRightToLeftOnly
  );

  { NavArea cost class (UNavArea_Default / Road / Mud / Null parity). }
  TRecastAreaKind = (
    rakDefault,
    rakRoadFast,
    rakHazardMud,
    rakNullBlocked
  );

  { Built-in multi-floor starter presets for @link(TCastleRecastNavMesh). }
  TRecastNavPreset = (
    rnpCustom,
    rnpTwoStoryBridgeAndStairs,
    rnpMultiFloorDungeonKeep,
    rnpSteepCanyonParkourLinks
  );

  { Input 3D architectural floor, ramp, or bridge slab inside the NavMesh volume. }
  TRecastSourceSlab = record
    SlabName: String;
    BoundsMin: TVector3; { BoundsMin.Y = underside of slab; BoundsMax.Y = walkable top surface! }
    BoundsMax: TVector3;
    SlopeDeg: Single;
    IsRampX: Boolean;    { True if top surface rises linearly from StartTopY (Min.X) to EndTopY (Max.X) }
    RampStartTopY: Single;
    RampEndTopY: Single;
    AreaKind: TRecastAreaKind;
  end;
  TRecastSourceSlabArray = array of TRecastSourceSlab;

  { Generated walkable convex 3D NavMesh polygon (Detour dtPoly parity). }
  TRecastNavPoly = record
    PolyId: Integer;
    SourceSlabName: String;
    FloorTier: Integer;
    MinXZ: TVector2;
    MaxXZ: TVector2;
    ElevMinY: Single;
    ElevMaxY: Single;
    Center3D: TVector3;
    TriangleCount: Integer;
    AreaM2: Single;
    AreaKind: TRecastAreaKind;
    CostMultiplier: Single;
  end;
  TRecastNavPolyArray = array of TRecastNavPoly;

  { Shared walkable portal or directional off-mesh link edge between two NavPolys. }
  TRecastNavEdge = record
    FromPolyId: Integer;
    ToPolyId: Integer;
    PortalPointA: TVector3;
    PortalPointB: TVector3;
    PortalMidpoint: TVector3;
    IsOffMeshLink: Boolean;
    LinkIndex: Integer;
    EdgeCost: Single;
  end;
  TRecastNavEdgeArray = array of TRecastNavEdge;

  { Off-mesh jump / drop / climb link (UE 5.5 ANavLinkProxy parity). }
  TRecastNavLink = record
    LinkName: String;
    LeftPos: TVector3;
    RightPos: TVector3;
    Direction: TNavLinkDirection;
    ActionTag: String;
    CostMultiplier: Single;
    Enabled: Boolean;
  end;
  TRecastNavLinkArray = array of TRecastNavLink;

  { Output 3D waypoint from portal-smoothed A* pathfinding. }
  TRecastPathPoint = record
    Position: TVector3;
    PolyId: Integer;
    ViaNavLink: Boolean;
    LinkActionTag: String;
  end;
  TRecastPathPointArray = array of TRecastPathPoint;

  { Pathfinding result summary. }
  TRecastPathResult = record
    Found: Boolean;
    TotalDistanceM: Single;
    TotalWeightedCost: Single;
    VisitedPolyCount: Integer;
    UsedLinkCount: Integer;
    Points: TRecastPathPointArray;
  end;

  { Unreal Engine 5.5-style 3D Polygonal Recast NavMesh Volume component. }
  TCastleRecastNavMesh = class(TCastleTransform)
  private
    FPreset: TRecastNavPreset;
    FNavVolumeKey: String;
    FAgentRadius: Single;
    FAgentHeight: Single;
    FAgentMaxSlopeDeg: Single;
    FAgentMaxStepHeight: Single;
    FShowNavMeshOverlay: Boolean;

    FSourceSlabs: TRecastSourceSlabArray;
    FNavLinks: TRecastNavLinkArray;
    FPolys: TRecastNavPolyArray;
    FEdges: TRecastNavEdgeArray;
    FLastPath: TRecastPathResult;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TRecastNavPreset);
    procedure SetAgentRadius(const AValue: Single);
    procedure SetAgentHeight(const AValue: Single);
    procedure SetAgentMaxSlopeDeg(const AValue: Single);
    procedure SetAgentMaxStepHeight(const AValue: Single);
    procedure SetShowNavMeshOverlay(const AValue: Boolean);
    function GetNavConfigJson: String;
    procedure SetNavConfigJson(const AValue: String);

    procedure ClearPreviewContainer;
    procedure SyncPreviewVisuals;
    function HasCeilingHeadroom(const ASlabIdx: Integer;
      const AErodedMinXZ, AErodedMaxXZ: TVector2): Boolean;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TRecastNavPreset);

    { Source Geometry & ANavLinkProxy Authoring }
    procedure ClearGeometryAndLinks;
    function AddSourceSlab(const AName: String; const AMin, AMax: TVector3;
      const ASlopeDeg: Single = 0.0; const AArea: TRecastAreaKind = rakDefault;
      const AIsRampX: Boolean = False; const ARampStartY: Single = 0.0;
      const ARampEndY: Single = 0.0): Integer;
    function AddOrUpdateNavLink(const ALinkName: String;
      const ALeftPos, ARightPos: TVector3;
      const ADirection: TNavLinkDirection;
      const AActionTag: String;
      const ACostMultiplier: Single = 1.15;
      const AEnabled: Boolean = True): Integer;
    function SetNavLinkEnabled(const ALinkName: String; const AEnabled: Boolean): Boolean;

    { Multi-Floor 3D Polygonal NavMesh Builder }
    procedure BuildPolygonalNavMesh;
    function TotalWalkableAreaM2: Single;
    function TotalNavTriangles: Integer;
    function CountStackedMultiFloorPairs: Integer;
    function FindContainingOrNearestPoly(const AWorldOrLocalPos: TVector3;
      const AMaxSearchDist: Single = 2.5): Integer;

    { 3D Portal-Smoothed A* Pathfinding Across Polygons + Directional NavLinks }
    function FindPath3D(const AStartPos, AGoalPos: TVector3): TRecastPathResult;

    function RecastSummaryBadge: String;

    property SourceSlabs: TRecastSourceSlabArray read FSourceSlabs;
    property NavLinks: TRecastNavLinkArray read FNavLinks;
    property Polys: TRecastNavPolyArray read FPolys;
    property Edges: TRecastNavEdgeArray read FEdges;
    property LastPath: TRecastPathResult read FLastPath;
  published
    property NavVolumeKey: String read FNavVolumeKey write FNavVolumeKey;
    property AgentRadius: Single read FAgentRadius write SetAgentRadius {$ifdef FPC}default 0.35{$endif};
    property AgentHeight: Single read FAgentHeight write SetAgentHeight {$ifdef FPC}default 1.80{$endif};
    property AgentMaxSlopeDeg: Single read FAgentMaxSlopeDeg write SetAgentMaxSlopeDeg {$ifdef FPC}default 45.0{$endif};
    property AgentMaxStepHeight: Single read FAgentMaxStepHeight write SetAgentMaxStepHeight {$ifdef FPC}default 0.45{$endif};
    property ShowNavMeshOverlay: Boolean read FShowNavMeshOverlay write SetShowNavMeshOverlay default True;
    property NavConfigJson: String read GetNavConfigJson write SetNavConfigJson;
    property Preset: TRecastNavPreset
      read FPreset write SetPreset default rnpTwoStoryBridgeAndStairs;
  end;

implementation

uses
  fpjson, jsonparser;

function AreaCostForKind(const AKind: TRecastAreaKind): Single;
begin
  case AKind of
    rakRoadFast:    Result := 0.65;
    rakHazardMud:   Result := 3.50;
    rakNullBlocked: Result := 0.0;
  else
    Result := 1.00;
  end;
end;

function Overlap1D(const AMin, AMax, BMin, BMax: Single;
  out OutLo, OutHi: Single): Boolean;
begin
  OutLo := Max(AMin, BMin);
  OutHi := Min(AMax, BMax);
  Result := OutHi >= OutLo - 1e-3;
end;

{ TCastleRecastNavMesh ------------------------------------------------------- }

constructor TCastleRecastNavMesh.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNavVolumeKey := 'NavBounds_CitadelCourtyard';
  FAgentRadius := 0.35;
  FAgentHeight := 1.80;
  FAgentMaxSlopeDeg := 45.0;
  FAgentMaxStepHeight := 0.45;
  FShowNavMeshOverlay := True;
  ApplyPreset(rnpTwoStoryBridgeAndStairs);
end;

destructor TCastleRecastNavMesh.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastleRecastNavMesh.Loaded;
begin
  inherited;
  BuildPolygonalNavMesh;
  SyncPreviewVisuals;
end;

function TCastleRecastNavMesh.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'NavVolumeKey') or
     (PropertyName = 'AgentRadius') or
     (PropertyName = 'AgentHeight') or
     (PropertyName = 'AgentMaxSlopeDeg') or
     (PropertyName = 'AgentMaxStepHeight') or
     (PropertyName = 'ShowNavMeshOverlay') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleRecastNavMesh.SetPreset(const AValue: TRecastNavPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleRecastNavMesh.SetAgentRadius(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.05, 2.50);
  if not SameValue(FAgentRadius, V, 1e-4) then
  begin
    FAgentRadius := V;
    BuildPolygonalNavMesh;
    SyncPreviewVisuals;
  end;
end;

procedure TCastleRecastNavMesh.SetAgentHeight(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.40, 5.00);
  if not SameValue(FAgentHeight, V, 1e-4) then
  begin
    FAgentHeight := V;
    BuildPolygonalNavMesh;
    SyncPreviewVisuals;
  end;
end;

procedure TCastleRecastNavMesh.SetAgentMaxSlopeDeg(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 5.0, 85.0);
  if not SameValue(FAgentMaxSlopeDeg, V, 1e-4) then
  begin
    FAgentMaxSlopeDeg := V;
    BuildPolygonalNavMesh;
    SyncPreviewVisuals;
  end;
end;

procedure TCastleRecastNavMesh.SetAgentMaxStepHeight(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.05, 2.00);
  if not SameValue(FAgentMaxStepHeight, V, 1e-4) then
  begin
    FAgentMaxStepHeight := V;
    BuildPolygonalNavMesh;
    SyncPreviewVisuals;
  end;
end;

procedure TCastleRecastNavMesh.SetShowNavMeshOverlay(const AValue: Boolean);
begin
  if FShowNavMeshOverlay <> AValue then
  begin
    FShowNavMeshOverlay := AValue;
    SyncPreviewVisuals;
  end;
end;

procedure TCastleRecastNavMesh.ClearGeometryAndLinks;
begin
  FSourceSlabs := nil;
  FNavLinks := nil;
  FPolys := nil;
  FEdges := nil;
  FLastPath := Default(TRecastPathResult);
end;

function TCastleRecastNavMesh.AddSourceSlab(const AName: String;
  const AMin, AMax: TVector3; const ASlopeDeg: Single;
  const AArea: TRecastAreaKind; const AIsRampX: Boolean;
  const ARampStartY, ARampEndY: Single): Integer;
begin
  Result := Length(FSourceSlabs);
  SetLength(FSourceSlabs, Result + 1);
  FSourceSlabs[Result].SlabName := AName;
  FSourceSlabs[Result].BoundsMin := AMin;
  FSourceSlabs[Result].BoundsMax := AMax;
  FSourceSlabs[Result].SlopeDeg := ASlopeDeg;
  FSourceSlabs[Result].AreaKind := AArea;
  FSourceSlabs[Result].IsRampX := AIsRampX;
  FSourceSlabs[Result].RampStartTopY := ARampStartY;
  FSourceSlabs[Result].RampEndTopY := ARampEndY;
end;

function TCastleRecastNavMesh.AddOrUpdateNavLink(const ALinkName: String;
  const ALeftPos, ARightPos: TVector3; const ADirection: TNavLinkDirection;
  const AActionTag: String; const ACostMultiplier: Single;
  const AEnabled: Boolean): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FNavLinks) do
    if SameText(FNavLinks[I].LinkName, ALinkName) then
    begin
      Result := I;
      Break;
    end;
  if Result < 0 then
  begin
    Result := Length(FNavLinks);
    SetLength(FNavLinks, Result + 1);
    FNavLinks[Result].LinkName := ALinkName;
  end;
  FNavLinks[Result].LeftPos := ALeftPos;
  FNavLinks[Result].RightPos := ARightPos;
  FNavLinks[Result].Direction := ADirection;
  FNavLinks[Result].ActionTag := AActionTag;
  FNavLinks[Result].CostMultiplier := Max(0.1, ACostMultiplier);
  FNavLinks[Result].Enabled := AEnabled;
end;

function TCastleRecastNavMesh.SetNavLinkEnabled(
  const ALinkName: String; const AEnabled: Boolean): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FNavLinks) do
    if SameText(FNavLinks[I].LinkName, ALinkName) then
    begin
      FNavLinks[I].Enabled := AEnabled;
      BuildPolygonalNavMesh;
      SyncPreviewVisuals;
      Exit(True);
    end;
  Result := False;
end;

procedure TCastleRecastNavMesh.ApplyPreset(const APreset: TRecastNavPreset);
begin
  FPreset := APreset;
  if APreset = rnpCustom then Exit;

  ClearGeometryAndLinks;
  FAgentRadius := 0.35;
  FAgentHeight := 1.80;
  FAgentMaxSlopeDeg := 45.0;
  FAgentMaxStepHeight := 0.45;

  case APreset of
    rnpMultiFloorDungeonKeep:
      begin
        FNavVolumeKey := 'NavBounds_DungeonKeep3Floors';
        AddSourceSlab('Crypt_Floor0', Vector3(-8, -0.5, -5), Vector3(8, 0.0, 5), 0.0, rakDefault);
        AddSourceSlab('GuardHall_Floor1', Vector3(-8, 2.8, -5), Vector3(4, 3.2, 5), 0.0, rakRoadFast);
        AddSourceSlab('Battlement_Floor2', Vector3(-8, 6.0, -5), Vector3(0, 6.4, 5), 0.0, rakDefault);
        AddSourceSlab('LadderShaft_LinkOnly', Vector3(4, 2.8, -2), Vector3(8, 3.2, 2), 0.0, rakDefault);

        AddOrUpdateNavLink('NL_CryptLadderUp',
          Vector3(6.0, 0.0, 0.0), Vector3(6.0, 3.2, 0.0),
          nldBothWays, 'ClimbLadder', 1.25, True);
        AddOrUpdateNavLink('NL_BattlementVaultJump',
          Vector3(-2.0, 3.2, 0.0), Vector3(-2.0, 6.4, 0.0),
          nldBothWays, 'MantleClimb', 1.35, True);
        AddOrUpdateNavLink('NL_EmergencyDropChute',
          Vector3(-6.0, 6.4, 3.0), Vector3(-6.0, 0.0, 3.0),
          nldLeftToRightOnly, 'DropChute', 0.80, True);
      end;

    rnpSteepCanyonParkourLinks:
      begin
        FNavVolumeKey := 'NavBounds_CanyonParkour';
        AddSourceSlab('WestMesa', Vector3(-12, -1.0, -4), Vector3(-3, 2.0, 4), 0.0, rakDefault);
        AddSourceSlab('EastMesa', Vector3(3, -1.0, -4), Vector3(12, 2.0, 4), 0.0, rakDefault);
        { 62-degree sheer cliff wall — automatically rejected when MaxSlope=45 deg! }
        AddSourceSlab('SheerCliffSlope62Deg', Vector3(-3, 0.0, -4), Vector3(3, 2.0, 4), 62.0, rakDefault);

        AddOrUpdateNavLink('NL_GrappleZipCanyon',
          Vector3(-3.6, 2.0, 0.0), Vector3(3.6, 2.0, 0.0),
          nldBothWays, 'ParkourJumpGap', 1.10, True);
      end;
  else
    begin
      { Flagship 2-Story Overpass Bridge + Underpass Courtyard + Stairs + Drop + Jump Tower:
        - Courtyard_West (-10..-2), Underpass_Tunnel (-2..+3, top Y=0.0m), Courtyard_East (+3..+9)
        - Overpass_Bridge (-2..+4, underside Y=2.55m -> 2.55m headroom >= 1.80m AgentHeight, top Y=3.00m!)
        - West_StairRamp (-7..-2, Z=1.5..4.5, rising smoothly from Y=0.0m -> Y=3.0m at 31 deg!)
        - Steep_RubbleWall (58 deg -> rejected by 45 deg slope filter!)
        - Isolated_SniperTower (+6.5..+10.5, top Y=3.00m) reachable via bidirectional JumpGap NavLink!
        - One-Way East Drop Ledge from Overpass_Bridge (+3.4, 3.0, 0) -> Courtyard_East (+4.4, 0.0, 0)! }
      FPreset := rnpTwoStoryBridgeAndStairs;
      FNavVolumeKey := 'NavBounds_CitadelBridge2Story';

      AddSourceSlab('Courtyard_West', Vector3(-10.0, -0.5, -5.0), Vector3(-2.0, 0.0, 1.5), 0.0, rakDefault);
      AddSourceSlab('Underpass_Tunnel', Vector3(-2.0, -0.5, -3.5), Vector3(3.5, 0.0, 2.0), 0.0, rakDefault);
      AddSourceSlab('Courtyard_East', Vector3(3.5, -0.5, -5.0), Vector3(10.0, 0.0, 5.0), 0.0, rakDefault);

      { West Staircase Ramp rising from (-8.0, Y=0.0) up to (-2.0, Y=3.0) -> Slope = arctan(3/6) = 26.6 deg }
      AddSourceSlab('West_StairRamp', Vector3(-8.0, 0.0, 1.5), Vector3(-2.0, 3.0, 4.8),
        26.6, rakRoadFast, True, 0.0, 3.0);
      { Connect Courtyard_West to bottom of West_StairRamp }
      AddSourceSlab('West_StairLanding', Vector3(-10.0, -0.5, 1.5), Vector3(-8.0, 0.0, 4.8),
        0.0, rakDefault);

      { Elevated Stone Overpass Bridge directly ABOVE Underpass_Tunnel!
        Underside Y = 2.55m (2.55m vertical clearance above Y=0.0m Tunnel!), Top Y = 3.00m }
      AddSourceSlab('Overpass_BridgeDeck', Vector3(-2.0, 2.55, -2.5), Vector3(4.0, 3.0, 4.8),
        0.0, rakRoadFast);

      { Non-walkable 58-degree collapsed rubble slope (rejected by AgentMaxSlopeDeg = 45) }
      AddSourceSlab('CollapsedRubble_58Deg', Vector3(1.5, 0.0, -5.0), Vector3(3.5, 3.0, -2.5),
        58.0, rakDefault);

      { Isolated Upper Sniper Bastion separated by a 2.5m chasm }
      AddSourceSlab('SniperBastion_Upper', Vector3(6.2, 2.55, 0.5), Vector3(10.2, 3.0, 4.8),
        0.0, rakDefault);

      { 1. Bidirectional Parkour Jump Link across chasm (Bridge <-> SniperBastion) }
      AddOrUpdateNavLink('NL_BridgeToBastionJump',
        Vector3(3.5, 3.0, 2.6), Vector3(6.7, 3.0, 2.6),
        nldBothWays, 'JumpChasm', 1.15, True);

      { 2. One-Way Ledge Drop Link (Overpass_Bridge Y=3.0 -> Courtyard_East Y=0.0 ONLY!) }
      AddOrUpdateNavLink('NL_BridgeEastDropDown',
        Vector3(3.5, 3.0, -1.0), Vector3(4.6, 0.0, -1.0),
        nldLeftToRightOnly, 'DropDownLedge', 0.90, True);
    end;
  end;

  BuildPolygonalNavMesh;
  { Pre-compute a default showcase 3D path from Underpass/East up to Sniper Bastion }
  if Length(FPolys) >= 2 then
    FindPath3D(Vector3(6.5, 0.0, -2.5), Vector3(8.2, 3.0, 2.6));
  SyncPreviewVisuals;
end;

function TCastleRecastNavMesh.HasCeilingHeadroom(const ASlabIdx: Integer;
  const AErodedMinXZ, AErodedMaxXZ: TVector2): Boolean;
var
  FloorTopY, CeilingUndersideY, OvX0, OvX1, OvZ0, OvZ1: Single;
  J: Integer;
begin
  Result := True;
  FloorTopY := FSourceSlabs[ASlabIdx].BoundsMax.Y;
  for J := 0 to High(FSourceSlabs) do
  begin
    if J = ASlabIdx then Continue;
    CeilingUndersideY := FSourceSlabs[J].BoundsMin.Y;
    { Check overhead slabs whose underside sits above this floor's walking surface }
    if CeilingUndersideY > FloorTopY + 0.05 then
    begin
      if Overlap1D(AErodedMinXZ.X, AErodedMaxXZ.X,
                   FSourceSlabs[J].BoundsMin.X, FSourceSlabs[J].BoundsMax.X, OvX0, OvX1) and
         Overlap1D(AErodedMinXZ.Y, AErodedMaxXZ.Y,
                   FSourceSlabs[J].BoundsMin.Z, FSourceSlabs[J].BoundsMax.Z, OvZ0, OvZ1) and
         ((OvX1 - OvX0) > 0.25) and ((OvZ1 - OvZ0) > 0.25) then
      begin
        if (CeilingUndersideY - FloorTopY) < FAgentHeight then
          Exit(False);
      end;
    end;
  end;
end;

procedure TCastleRecastNavMesh.BuildPolygonalNavMesh;

  procedure AppendEdge(const AFrom, ATo: Integer;
    const PA, PB, PMid: TVector3; const AIsLink: Boolean;
    const ALinkIdx: Integer; const ACost: Single);
  var
    N: Integer;
  begin
    N := Length(FEdges);
    SetLength(FEdges, N + 1);
    FEdges[N].FromPolyId := AFrom;
    FEdges[N].ToPolyId := ATo;
    FEdges[N].PortalPointA := PA;
    FEdges[N].PortalPointB := PB;
    FEdges[N].PortalMidpoint := PMid;
    FEdges[N].IsOffMeshLink := AIsLink;
    FEdges[N].LinkIndex := ALinkIdx;
    FEdges[N].EdgeCost := Max(0.05, ACost);
  end;

  function EdgeElevationOnPoly(const APolyIdx: Integer; const AX: Single): Single;
  var
    SlabIdx: Integer;
    T: Single;
  begin
    Result := FPolys[APolyIdx].Center3D.Y;
    for SlabIdx := 0 to High(FSourceSlabs) do
      if SameText(FSourceSlabs[SlabIdx].SlabName, FPolys[APolyIdx].SourceSlabName) then
      begin
        if FSourceSlabs[SlabIdx].IsRampX then
        begin
          T := EnsureRange(
            (AX - FSourceSlabs[SlabIdx].BoundsMin.X) /
            Max(0.01, FSourceSlabs[SlabIdx].BoundsMax.X - FSourceSlabs[SlabIdx].BoundsMin.X),
            0.0, 1.0);
          Exit(FSourceSlabs[SlabIdx].RampStartTopY +
            (FSourceSlabs[SlabIdx].RampEndTopY - FSourceSlabs[SlabIdx].RampStartTopY) * T);
        end else
          Exit(FSourceSlabs[SlabIdx].BoundsMax.Y);
      end;
  end;

var
  I, J, PCount, PolyL, PolyR: Integer;
  RawMin, RawMax: TVector3;
  ErMin, ErMax: TVector2;
  SpanW, SpanD, OvLo, OvHi, SharedX, SharedZ, YA, YB, BaseDist, CostMul: Single;
  P1, P2, PMid: TVector3;
begin
  FPolys := nil;
  FEdges := nil;
  PCount := 0;

  { Step 1: Filter by Slope, AreaKind, AgentRadius Erosion & 3D AgentHeight Ceiling Clearance }
  for I := 0 to High(FSourceSlabs) do
  begin
    if FSourceSlabs[I].AreaKind = rakNullBlocked then Continue;
    if FSourceSlabs[I].SlopeDeg > FAgentMaxSlopeDeg then Continue;

    RawMin := FSourceSlabs[I].BoundsMin;
    RawMax := FSourceSlabs[I].BoundsMax;

    { Erode outer perimeter inward by AgentRadius, while keeping shared interior seams flush
      within AgentRadius tolerance during portal linking }
    ErMin := Vector2(RawMin.X + FAgentRadius, RawMin.Z + FAgentRadius);
    ErMax := Vector2(RawMax.X - FAgentRadius, RawMax.Z - FAgentRadius);
    SpanW := ErMax.X - ErMin.X;
    SpanD := ErMax.Y - ErMin.Y;
    if (SpanW <= 0.15) or (SpanD <= 0.15) then Continue;

    if not HasCeilingHeadroom(I, ErMin, ErMax) then Continue;

    SetLength(FPolys, PCount + 1);
    FPolys[PCount].PolyId := PCount;
    FPolys[PCount].SourceSlabName := FSourceSlabs[I].SlabName;
    FPolys[PCount].MinXZ := ErMin;
    FPolys[PCount].MaxXZ := ErMax;
    if FSourceSlabs[I].IsRampX then
    begin
      FPolys[PCount].ElevMinY := Min(FSourceSlabs[I].RampStartTopY, FSourceSlabs[I].RampEndTopY);
      FPolys[PCount].ElevMaxY := Max(FSourceSlabs[I].RampStartTopY, FSourceSlabs[I].RampEndTopY);
      FPolys[PCount].Center3D := Vector3(
        (ErMin.X + ErMax.X) * 0.5,
        (FSourceSlabs[I].RampStartTopY + FSourceSlabs[I].RampEndTopY) * 0.5,
        (ErMin.Y + ErMax.Y) * 0.5);
    end else
    begin
      FPolys[PCount].ElevMinY := RawMax.Y;
      FPolys[PCount].ElevMaxY := RawMax.Y;
      FPolys[PCount].Center3D := Vector3(
        (ErMin.X + ErMax.X) * 0.5, RawMax.Y, (ErMin.Y + ErMax.Y) * 0.5);
    end;
    FPolys[PCount].FloorTier := Round(FPolys[PCount].ElevMaxY / 2.5);
    FPolys[PCount].AreaM2 := SpanW * SpanD;
    FPolys[PCount].TriangleCount := Max(2, Round(FPolys[PCount].AreaM2 / 2.2) * 2);
    FPolys[PCount].AreaKind := FSourceSlabs[I].AreaKind;
    FPolys[PCount].CostMultiplier := AreaCostForKind(FSourceSlabs[I].AreaKind);
    Inc(PCount);
  end;

  { Step 2: Build Walkable Portal Adjacency Edges (touching XZ boundary + StepHeight check) }
  for I := 0 to High(FPolys) do
    for J := I + 1 to High(FPolys) do
    begin
      { Case A: Shared X seam (e.g. Left/Right neighbors separated only by 2*AgentRadius erosion) }
      if (Abs(FPolys[I].MaxXZ.X - FPolys[J].MinXZ.X) <= 2.0 * FAgentRadius + 0.12) or
         (Abs(FPolys[J].MaxXZ.X - FPolys[I].MinXZ.X) <= 2.0 * FAgentRadius + 0.12) then
      begin
        if Overlap1D(FPolys[I].MinXZ.Y, FPolys[I].MaxXZ.Y,
                     FPolys[J].MinXZ.Y, FPolys[J].MaxXZ.Y, OvLo, OvHi) and
           ((OvHi - OvLo) >= 0.25) then
        begin
          if Abs(FPolys[I].MaxXZ.X - FPolys[J].MinXZ.X) <=
             Abs(FPolys[J].MaxXZ.X - FPolys[I].MinXZ.X) then
            SharedX := (FPolys[I].MaxXZ.X + FPolys[J].MinXZ.X) * 0.5
          else
            SharedX := (FPolys[J].MaxXZ.X + FPolys[I].MinXZ.X) * 0.5;

          YA := EdgeElevationOnPoly(I, SharedX);
          YB := EdgeElevationOnPoly(J, SharedX);
          if Abs(YA - YB) <= FAgentMaxStepHeight + 0.05 then
          begin
            P1 := Vector3(SharedX, (YA + YB) * 0.5, OvLo);
            P2 := Vector3(SharedX, (YA + YB) * 0.5, OvHi);
            PMid := (P1 + P2) * 0.5;
            BaseDist := (FPolys[I].Center3D - FPolys[J].Center3D).Length;
            CostMul := 0.5 * (FPolys[I].CostMultiplier + FPolys[J].CostMultiplier);
            AppendEdge(I, J, P1, P2, PMid, False, -1, BaseDist * CostMul);
            AppendEdge(J, I, P1, P2, PMid, False, -1, BaseDist * CostMul);
          end;
        end;
      end;

      { Case B: Shared Z seam (North/South neighbors) }
      if (Abs(FPolys[I].MaxXZ.Y - FPolys[J].MinXZ.Y) <= 2.0 * FAgentRadius + 0.12) or
         (Abs(FPolys[J].MaxXZ.Y - FPolys[I].MinXZ.Y) <= 2.0 * FAgentRadius + 0.12) then
      begin
        if Overlap1D(FPolys[I].MinXZ.X, FPolys[I].MaxXZ.X,
                     FPolys[J].MinXZ.X, FPolys[J].MaxXZ.X, OvLo, OvHi) and
           ((OvHi - OvLo) >= 0.25) then
        begin
          if Abs(FPolys[I].MaxXZ.Y - FPolys[J].MinXZ.Y) <=
             Abs(FPolys[J].MaxXZ.Y - FPolys[I].MinXZ.Y) then
            SharedZ := (FPolys[I].MaxXZ.Y + FPolys[J].MinXZ.Y) * 0.5
          else
            SharedZ := (FPolys[J].MaxXZ.Y + FPolys[I].MinXZ.Y) * 0.5;

          YA := EdgeElevationOnPoly(I, (OvLo + OvHi) * 0.5);
          YB := EdgeElevationOnPoly(J, (OvLo + OvHi) * 0.5);
          if Abs(YA - YB) <= FAgentMaxStepHeight + 0.05 then
          begin
            P1 := Vector3(OvLo, (YA + YB) * 0.5, SharedZ);
            P2 := Vector3(OvHi, (YA + YB) * 0.5, SharedZ);
            PMid := (P1 + P2) * 0.5;
            BaseDist := (FPolys[I].Center3D - FPolys[J].Center3D).Length;
            CostMul := 0.5 * (FPolys[I].CostMultiplier + FPolys[J].CostMultiplier);
            AppendEdge(I, J, P1, P2, PMid, False, -1, BaseDist * CostMul);
            AppendEdge(J, I, P1, P2, PMid, False, -1, BaseDist * CostMul);
          end;
        end;
      end;
    end;

  { Step 3: Bind Enabled ANavLinkProxy Off-Mesh Links (BothWays / LeftToRight / RightToLeft) }
  for I := 0 to High(FNavLinks) do
  begin
    if not FNavLinks[I].Enabled then Continue;
    PolyL := FindContainingOrNearestPoly(FNavLinks[I].LeftPos, 2.0);
    PolyR := FindContainingOrNearestPoly(FNavLinks[I].RightPos, 2.0);
    if (PolyL < 0) or (PolyR < 0) or (PolyL = PolyR) then Continue;

    BaseDist := (FNavLinks[I].RightPos - FNavLinks[I].LeftPos).Length *
      FNavLinks[I].CostMultiplier;

    if FNavLinks[I].Direction in [nldBothWays, nldLeftToRightOnly] then
      AppendEdge(PolyL, PolyR, FNavLinks[I].LeftPos, FNavLinks[I].RightPos,
        FNavLinks[I].RightPos, True, I, BaseDist);

    if FNavLinks[I].Direction in [nldBothWays, nldRightToLeftOnly] then
      AppendEdge(PolyR, PolyL, FNavLinks[I].RightPos, FNavLinks[I].LeftPos,
        FNavLinks[I].LeftPos, True, I, BaseDist);
  end;
end;

function TCastleRecastNavMesh.TotalWalkableAreaM2: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FPolys) do
    Result := Result + FPolys[I].AreaM2;
end;

function TCastleRecastNavMesh.TotalNavTriangles: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FPolys) do
    Inc(Result, FPolys[I].TriangleCount);
end;

function TCastleRecastNavMesh.CountStackedMultiFloorPairs: Integer;
var
  I, J: Integer;
  LoX, HiX, LoZ, HiZ: Single;
begin
  Result := 0;
  for I := 0 to High(FPolys) do
    for J := I + 1 to High(FPolys) do
      if (Abs(FPolys[I].Center3D.Y - FPolys[J].Center3D.Y) >= 1.5) and
         Overlap1D(FPolys[I].MinXZ.X, FPolys[I].MaxXZ.X,
                   FPolys[J].MinXZ.X, FPolys[J].MaxXZ.X, LoX, HiX) and
         Overlap1D(FPolys[I].MinXZ.Y, FPolys[I].MaxXZ.Y,
                   FPolys[J].MinXZ.Y, FPolys[J].MaxXZ.Y, LoZ, HiZ) and
         ((HiX - LoX) > 0.2) and ((HiZ - LoZ) > 0.2) then
        Inc(Result);
end;

function TCastleRecastNavMesh.FindContainingOrNearestPoly(
  const AWorldOrLocalPos: TVector3; const AMaxSearchDist: Single): Integer;
var
  I: Integer;
  DX, DZ, DY, Score, BestScore: Single;
begin
  Result := -1;
  BestScore := 1e30;
  for I := 0 to High(FPolys) do
  begin
    if AWorldOrLocalPos.X < FPolys[I].MinXZ.X then
      DX := FPolys[I].MinXZ.X - AWorldOrLocalPos.X
    else if AWorldOrLocalPos.X > FPolys[I].MaxXZ.X then
      DX := AWorldOrLocalPos.X - FPolys[I].MaxXZ.X
    else
      DX := 0.0;

    if AWorldOrLocalPos.Z < FPolys[I].MinXZ.Y then
      DZ := FPolys[I].MinXZ.Y - AWorldOrLocalPos.Z
    else if AWorldOrLocalPos.Z > FPolys[I].MaxXZ.Y then
      DZ := AWorldOrLocalPos.Z - FPolys[I].MaxXZ.Y
    else
      DZ := 0.0;

    if AWorldOrLocalPos.Y < FPolys[I].ElevMinY then
      DY := FPolys[I].ElevMinY - AWorldOrLocalPos.Y
    else if AWorldOrLocalPos.Y > FPolys[I].ElevMaxY then
      DY := AWorldOrLocalPos.Y - FPolys[I].ElevMaxY
    else
      DY := 0.0;

    { Weight vertical Y separation strongly so stacked floors (Y=0 vs Y=3.0) never mis-snap! }
    if (Sqrt(DX * DX + DZ * DZ) <= AMaxSearchDist) and (DY <= 1.4) then
    begin
      Score := Sqrt(DX * DX + DZ * DZ) + DY * 3.0;
      if Score < BestScore then
      begin
        BestScore := Score;
        Result := I;
      end;
    end;
  end;
end;

function TCastleRecastNavMesh.FindPath3D(
  const AStartPos, AGoalPos: TVector3): TRecastPathResult;
var
  StartPoly, GoalPoly, NPolys, Cur, NextP, BestOpenIdx, I, EIdx, StepCnt: Integer;
  GScore, FScore: array of Single;
  CameFromPoly, CameViaEdge: array of Integer;
  InOpen, InClosed: array of Boolean;
  RevEdges: array of Integer;
  TentativeG: Single;
  ClampedStart, ClampedGoal, CurAnchor, PortalTarget: TVector3;

  procedure PushPoint(const P: TVector3; const APoly: Integer;
    const AViaLink: Boolean; const ATag: String);
  var
    K: Integer;
  begin
    K := Length(Result.Points);
    if (K > 0) and ((Result.Points[K - 1].Position - P).Length < 1e-3) and
       (not AViaLink) then
      Exit;
    SetLength(Result.Points, K + 1);
    Result.Points[K].Position := P;
    Result.Points[K].PolyId := APoly;
    Result.Points[K].ViaNavLink := AViaLink;
    Result.Points[K].LinkActionTag := ATag;
  end;

  function ClampOntoSegment(const RefPt, SegA, SegB: TVector3): TVector3;
  var
    AB: TVector3;
    LenSq, T: Single;
  begin
    AB := SegB - SegA;
    LenSq := AB.LengthSqr;
    if LenSq < 1e-6 then Exit(SegA);
    T := EnsureRange(TVector3.DotProduct(RefPt - SegA, AB) / LenSq, 0.12, 0.88);
    Result := SegA + AB * T;
  end;

begin
  Result := Default(TRecastPathResult);
  NPolys := Length(FPolys);
  if NPolys = 0 then Exit;

  StartPoly := FindContainingOrNearestPoly(AStartPos, 3.0);
  GoalPoly := FindContainingOrNearestPoly(AGoalPos, 3.0);
  if (StartPoly < 0) or (GoalPoly < 0) then Exit;

  ClampedStart := Vector3(
    EnsureRange(AStartPos.X, FPolys[StartPoly].MinXZ.X, FPolys[StartPoly].MaxXZ.X),
    EnsureRange(AStartPos.Y, FPolys[StartPoly].ElevMinY, FPolys[StartPoly].ElevMaxY),
    EnsureRange(AStartPos.Z, FPolys[StartPoly].MinXZ.Y, FPolys[StartPoly].MaxXZ.Y));
  ClampedGoal := Vector3(
    EnsureRange(AGoalPos.X, FPolys[GoalPoly].MinXZ.X, FPolys[GoalPoly].MaxXZ.X),
    EnsureRange(AGoalPos.Y, FPolys[GoalPoly].ElevMinY, FPolys[GoalPoly].ElevMaxY),
    EnsureRange(AGoalPos.Z, FPolys[GoalPoly].MinXZ.Y, FPolys[GoalPoly].MaxXZ.Y));

  if StartPoly = GoalPoly then
  begin
    Result.Found := True;
    Result.VisitedPolyCount := 1;
    PushPoint(ClampedStart, StartPoly, False, '');
    PushPoint(ClampedGoal, GoalPoly, False, '');
    Result.TotalDistanceM := (ClampedGoal - ClampedStart).Length;
    Result.TotalWeightedCost := Result.TotalDistanceM * FPolys[StartPoly].CostMultiplier;
    FLastPath := Result;
    Exit;
  end;

  SetLength(GScore, NPolys);
  SetLength(FScore, NPolys);
  SetLength(CameFromPoly, NPolys);
  SetLength(CameViaEdge, NPolys);
  SetLength(InOpen, NPolys);
  SetLength(InClosed, NPolys);
  for I := 0 to NPolys - 1 do
  begin
    GScore[I] := 1e30;
    FScore[I] := 1e30;
    CameFromPoly[I] := -1;
    CameViaEdge[I] := -1;
    InOpen[I] := False;
    InClosed[I] := False;
  end;

  GScore[StartPoly] := 0.0;
  FScore[StartPoly] := (FPolys[GoalPoly].Center3D - FPolys[StartPoly].Center3D).Length * 0.65;
  InOpen[StartPoly] := True;

  while True do
  begin
    BestOpenIdx := -1;
    for I := 0 to NPolys - 1 do
      if InOpen[I] and ((BestOpenIdx < 0) or (FScore[I] < FScore[BestOpenIdx])) then
        BestOpenIdx := I;

    if BestOpenIdx < 0 then Break;
    Cur := BestOpenIdx;
    InOpen[Cur] := False;
    InClosed[Cur] := True;
    Inc(Result.VisitedPolyCount);

    if Cur = GoalPoly then
    begin
      Result.Found := True;
      Result.TotalWeightedCost := GScore[GoalPoly];
      Break;
    end;

    for EIdx := 0 to High(FEdges) do
      if FEdges[EIdx].FromPolyId = Cur then
      begin
        NextP := FEdges[EIdx].ToPolyId;
        if InClosed[NextP] then Continue;
        TentativeG := GScore[Cur] + FEdges[EIdx].EdgeCost;
        if TentativeG < GScore[NextP] then
        begin
          CameFromPoly[NextP] := Cur;
          CameViaEdge[NextP] := EIdx;
          GScore[NextP] := TentativeG;
          FScore[NextP] := TentativeG +
            (FPolys[GoalPoly].Center3D - FPolys[NextP].Center3D).Length * 0.65;
          InOpen[NextP] := True;
        end;
      end;
  end;

  if not Result.Found then
  begin
    FLastPath := Result;
    Exit;
  end;

  { Reconstruct edge sequence & portal-funnel smooth 3D waypoints }
  RevEdges := nil;
  Cur := GoalPoly;
  StepCnt := 0;
  while (Cur <> StartPoly) and (CameViaEdge[Cur] >= 0) and (StepCnt <= NPolys) do
  begin
    SetLength(RevEdges, Length(RevEdges) + 1);
    RevEdges[High(RevEdges)] := CameViaEdge[Cur];
    Cur := CameFromPoly[Cur];
    Inc(StepCnt);
  end;

  PushPoint(ClampedStart, StartPoly, False, '');
  CurAnchor := ClampedStart;
  for I := High(RevEdges) downto 0 do
  begin
    EIdx := RevEdges[I];
    if FEdges[EIdx].IsOffMeshLink then
    begin
      { Emit exact takeoff & landing endpoints for ANavLinkProxy traversal }
      PushPoint(FEdges[EIdx].PortalPointA, FEdges[EIdx].FromPolyId, False, '');
      PushPoint(FEdges[EIdx].PortalPointB, FEdges[EIdx].ToPolyId, True,
        FNavLinks[FEdges[EIdx].LinkIndex].ActionTag);
      CurAnchor := FEdges[EIdx].PortalPointB;
      Inc(Result.UsedLinkCount);
    end else
    begin
      { Funnel string-pulling onto shared portal segment toward ClampedGoal }
      PortalTarget := ClampOntoSegment(
        (CurAnchor + ClampedGoal) * 0.5,
        FEdges[EIdx].PortalPointA, FEdges[EIdx].PortalPointB);
      PushPoint(PortalTarget, FEdges[EIdx].ToPolyId, False, '');
      CurAnchor := PortalTarget;
    end;
  end;
  PushPoint(ClampedGoal, GoalPoly, False, '');

  Result.TotalDistanceM := 0.0;
  for I := 1 to High(Result.Points) do
    Result.TotalDistanceM := Result.TotalDistanceM +
      (Result.Points[I].Position - Result.Points[I - 1].Position).Length;

  FLastPath := Result;
end;

procedure TCastleRecastNavMesh.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
  begin
    Remove(FPreviewContainer);
    FreeAndNil(FPreviewContainer);
  end;
end;

procedure TCastleRecastNavMesh.SyncPreviewVisuals;
var
  I: Integer;
  B: TCastleBox;
  S: TCastleSphere;
begin
  ClearPreviewContainer;
  if (not FShowNavMeshOverlay) or (csDestroying in ComponentState) then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  Add(FPreviewContainer);

  { UE 'P'-key emerald-green NavMesh polygon overlays }
  for I := 0 to High(FPolys) do
  begin
    B := TCastleBox.Create(FPreviewContainer);
    B.SetTransient;
    B.Size := Vector3(
      Max(0.2, FPolys[I].MaxXZ.X - FPolys[I].MinXZ.X),
      0.06,
      Max(0.2, FPolys[I].MaxXZ.Y - FPolys[I].MinXZ.Y));
    B.Translation := FPolys[I].Center3D + Vector3(0, 0.04, 0);
    if FPolys[I].FloorTier > 0 then
      B.Color := Vector4(0.18, 0.88, 0.58, 1.0)
    else
      B.Color := Vector4(0.14, 0.72, 0.36, 1.0);
    FPreviewContainer.Add(B);
  end;

  { NavLinkProxy endpoint markers }
  for I := 0 to High(FNavLinks) do
    if FNavLinks[I].Enabled then
    begin
      S := TCastleSphere.Create(FPreviewContainer);
      S.SetTransient;
      S.Radius := 0.16;
      S.Translation := FNavLinks[I].LeftPos + Vector3(0, 0.18, 0);
      S.Color := Vector4(0.20, 0.82, 1.0, 1.0);
      FPreviewContainer.Add(S);

      S := TCastleSphere.Create(FPreviewContainer);
      S.SetTransient;
      S.Radius := 0.16;
      S.Translation := FNavLinks[I].RightPos + Vector3(0, 0.18, 0);
      S.Color := Vector4(1.0, 0.68, 0.20, 1.0);
      FPreviewContainer.Add(S);
    end;
end;

function TCastleRecastNavMesh.GetNavConfigJson: String;
var
  Root, LinkObj: TJSONObject;
  LinkArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('navVolumeKey', FNavVolumeKey);
    Root.Add('agentRadius', FAgentRadius);
    Root.Add('agentHeight', FAgentHeight);
    Root.Add('agentMaxSlopeDeg', FAgentMaxSlopeDeg);
    Root.Add('agentMaxStepHeight', FAgentMaxStepHeight);
    LinkArr := TJSONArray.Create;
    Root.Add('navLinks', LinkArr);
    for I := 0 to High(FNavLinks) do
    begin
      LinkObj := TJSONObject.Create;
      LinkObj.Add('name', FNavLinks[I].LinkName);
      LinkObj.Add('lx', FNavLinks[I].LeftPos.X);
      LinkObj.Add('ly', FNavLinks[I].LeftPos.Y);
      LinkObj.Add('lz', FNavLinks[I].LeftPos.Z);
      LinkObj.Add('rx', FNavLinks[I].RightPos.X);
      LinkObj.Add('ry', FNavLinks[I].RightPos.Y);
      LinkObj.Add('rz', FNavLinks[I].RightPos.Z);
      LinkObj.Add('dir', Ord(FNavLinks[I].Direction));
      LinkObj.Add('tag', FNavLinks[I].ActionTag);
      LinkObj.Add('cost', FNavLinks[I].CostMultiplier);
      LinkObj.Add('enabled', FNavLinks[I].Enabled);
      LinkArr.Add(LinkObj);
    end;
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleRecastNavMesh.SetNavConfigJson(const AValue: String);
var
  Data: TJSONData;
  Root, LinkObj: TJSONObject;
  LinkArr: TJSONArray;
  I: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    FNavVolumeKey := Root.Get('navVolumeKey', FNavVolumeKey);
    FAgentRadius := Root.Get('agentRadius', FAgentRadius);
    FAgentHeight := Root.Get('agentHeight', FAgentHeight);
    FAgentMaxSlopeDeg := Root.Get('agentMaxSlopeDeg', FAgentMaxSlopeDeg);
    FAgentMaxStepHeight := Root.Get('agentMaxStepHeight', FAgentMaxStepHeight);

    LinkArr := Root.Find('navLinks', jtArray) as TJSONArray;
    if LinkArr <> nil then
    begin
      FNavLinks := nil;
      for I := 0 to LinkArr.Count - 1 do
        if LinkArr.Items[I] is TJSONObject then
        begin
          LinkObj := TJSONObject(LinkArr.Items[I]);
          AddOrUpdateNavLink(
            LinkObj.Get('name', 'NL_' + IntToStr(I)),
            Vector3(LinkObj.Get('lx', 0.0), LinkObj.Get('ly', 0.0), LinkObj.Get('lz', 0.0)),
            Vector3(LinkObj.Get('rx', 0.0), LinkObj.Get('ry', 0.0), LinkObj.Get('rz', 0.0)),
            TNavLinkDirection(EnsureRange(LinkObj.Get('dir', 0), 0, Ord(High(TNavLinkDirection)))),
            LinkObj.Get('tag', 'Jump'),
            LinkObj.Get('cost', 1.15),
            LinkObj.Get('enabled', True));
        end;
    end;
    BuildPolygonalNavMesh;
    SyncPreviewVisuals;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleRecastNavMesh.RecastSummaryBadge: String;
begin
  Result := Format('[Recast3D:%s Polys=%d Links=%d Stacked=%d Area=%.0fm^2]',
    [FNavVolumeKey, Length(FPolys), Length(FNavLinks),
     CountStackedMultiFloorPairs, TotalWalkableAreaM2]);
end;

initialization
  RegisterSerializableComponent(TCastleRecastNavMesh,
    ['AI & Navigation', '3D Recast NavMesh Volume & NavLinkProxy']);
end.
