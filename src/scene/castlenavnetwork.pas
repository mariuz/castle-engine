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

{ AI Waypoint patrol networks (@link(TCastleWaypointNode)), obstacle-aware
  2D XZ A* pathfinding grids (@link(TCastleNavGrid)), and autonomous patrol +
  sight/hearing perception behaviors (@link(TCastlePatrolAgentBehavior))
  (Phase 290 — UE 5.9 / 6.0 MassAI, NavGrid & Perception Parity). }
unit CastleNavNetwork;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform;

const
  { Set @code(Transform.Tag := NavWalkableIgnoreTag) on floor/ground meshes so
    @link(TCastleNavGrid.BakeObstaclesFromWorld) treats them as walkable ground
    rather than blocking obstacles. }
  NavWalkableIgnoreTag = 7801;

type
  { Linked 3D patrol waypoint node with configurable dwell timer and acceptance
    radius. }
  TCastleWaypointNode = class(TCastleTransform)
  strict private
    FWaypointLabel: String;
    FNextWaypointName: String;
    FWaitTimeSec: Single;
    FAcceptanceRadius: Single;
    FShowLinkInViewport: Boolean;
    procedure SetWaitTimeSec(const Value: Single);
    procedure SetAcceptanceRadius(const Value: Single);
  public
    const
      DefaultWaitTimeSec = 0.0;
      DefaultAcceptanceRadius = 0.5;

    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;

    { Resolve @link(NextWaypointName) inside @code(ASearchRoot) (or @code(Owner)). }
    function ResolveNextWaypoint(const ASearchRoot: TComponent = nil): TCastleWaypointNode;

    { Compact Hierarchy & Viewport badge. }
    function WaypointSummaryBadge: String;
  published
    property WaypointLabel: String read FWaypointLabel write FWaypointLabel;
    property NextWaypointName: String read FNextWaypointName write FNextWaypointName;
    property WaitTimeSec: Single read FWaitTimeSec write SetWaitTimeSec
      {$ifdef FPC}default DefaultWaitTimeSec{$endif};
    property AcceptanceRadius: Single read FAcceptanceRadius write SetAcceptanceRadius
      {$ifdef FPC}default DefaultAcceptanceRadius{$endif};
    property ShowLinkInViewport: Boolean
      read FShowLinkInViewport write FShowLinkInViewport default true;
  end;

  { Obstacle-aware 2D XZ A* navigation grid centered at the transform's world
    origin. Supports automatic world AABB obstacle baking, manual cell painting,
    compact @link(BlockedCellsData) JSON persistence, and octile 8-way A*
    pathfinding with corner-cutting prevention. }
  TCastleNavGrid = class(TCastleTransform)
  strict private
    FCols: Integer;
    FRows: Integer;
    FCellSize: Single;
    FAgentRadius: Single;
    FMaxStepHeight: Single;
    FAllowDiagonal: Boolean;
    FBlocked: array of Boolean;
    FBlockedCellsData: String;
    FDataDirty: Boolean;

    procedure SetCols(const Value: Integer);
    procedure SetRows(const Value: Integer);
    procedure SetCellSize(const Value: Single);
    procedure SetAgentRadius(const Value: Single);
    procedure SetMaxStepHeight(const Value: Single);
    procedure SetBlockedCellsData(const Value: String);

    procedure EnsureGridAllocated;
    procedure RebuildBlockedString;
    function IsNonEmptyBlockedData: Boolean;
    function FindNearestWalkableCell(const StartCol, StartRow: Integer;
      out OutCol, OutRow: Integer): Boolean;
  protected
    procedure Loaded; override;
  public
    const
      DefaultCols = 32;
      DefaultRows = 32;
      DefaultCellSize = 1.0;
      DefaultAgentRadius = 0.35;
      DefaultMaxStepHeight = 2.0;

    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;

    procedure ClearBlockedCells;
    function IsCellInBounds(const ACol, ARow: Integer): Boolean;
    function IsCellBlocked(const ACol, ARow: Integer): Boolean;
    procedure SetCellBlocked(const ACol, ARow: Integer; const ABlocked: Boolean);
    function BlockedCellCount: Integer;

    function WorldToCell(const WorldPt: TVector3; out OutCol, OutRow: Integer): Boolean;
    function CellToWorldCenter(const ACol, ARow: Integer): TVector3;

    { Scan @code(AWorldRoot) for non-floor obstacle bounding boxes intersecting
      the vertical band @code([GridY + 0.15 .. GridY + MaxStepHeight]) and mark
      overlapping grid cells (expanded by @link(AgentRadius)) as blocked.
      Returns the total number of blocked cells after baking. }
    function BakeObstaclesFromWorld(const AWorldRoot: TCastleTransform): Integer;

    { Compute an obstacle-avoiding world-space path from @code(StartWorld) to
      @code(GoalWorld) into @code(OutPath) (cleared first). Returns @true when a
      valid path was found. }
    function FindPathWorld(const StartWorld, GoalWorld: TVector3;
      const OutPath: TVector3List): Boolean;

    function NavGridSummaryBadge: String;
  published
    property Cols: Integer read FCols write SetCols default DefaultCols;
    property Rows: Integer read FRows write SetRows default DefaultRows;
    property CellSize: Single read FCellSize write SetCellSize
      {$ifdef FPC}default DefaultCellSize{$endif};
    property AgentRadius: Single read FAgentRadius write SetAgentRadius
      {$ifdef FPC}default DefaultAgentRadius{$endif};
    property MaxStepHeight: Single read FMaxStepHeight write SetMaxStepHeight
      {$ifdef FPC}default DefaultMaxStepHeight{$endif};
    property AllowDiagonal: Boolean
      read FAllowDiagonal write FAllowDiagonal default true;
    property BlockedCellsData: String
      read FBlockedCellsData write SetBlockedCellsData stored IsNonEmptyBlockedData;
  end;

  { Composable AI patrol & sight/hearing perception behavior attachable to any
    @link(TCastleTransform). Follows @link(TCastleWaypointNode) chains directly
    or via @link(TCastleNavGrid) A* paths and exposes FOV cone & proximity
    hearing queries. }
  TCastlePatrolAgentBehavior = class(TCastleBehavior)
  strict private
    FMoveSpeed: Single;
    FTurnSpeedRad: Single;
    FCurrentWaypointName: String;
    FNavGridName: String;
    FAutoPatrolInRuntime: Boolean;
    FSightRadius: Single;
    FSightHalfAngleDeg: Single;
    FHearingRadius: Single;
    FShowPerceptionInViewport: Boolean;

    FDwellRemainingSec: Single;
    FReachedWaypointCount: Integer;
    FCurrentPath: TVector3List;
    FCurrentPathIndex: Integer;
    FCachedGoalWaypointName: String;

    procedure SetMoveSpeed(const Value: Single);
    procedure SetSightRadius(const Value: Single);
    procedure SetSightHalfAngleDeg(const Value: Single);
    procedure SetHearingRadius(const Value: Single);
    function ResolveSearchRoot: TComponent;
    function ResolveWaypoint(const AName: String): TCastleWaypointNode;
    function ResolveNavGrid: TCastleNavGrid;
  public
    const
      DefaultMoveSpeed = 4.0;
      DefaultTurnSpeedRad = 6.2831853;
      DefaultSightRadius = 14.0;
      DefaultSightHalfAngleDeg = 45.0;
      DefaultHearingRadius = 6.0;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Deterministic patrol step (also usable in editor preview & unit tests). }
    procedure StepPatrol(const DeltaSec: Single);
    procedure InvalidateCachedPath;

    { AI Perception: sight FOV cone + 360-degree hearing sphere queries. }
    function CanSeeWorldPoint(const TargetWorldPt: TVector3): Boolean;
    function CanHearWorldPoint(const TargetWorldPt: TVector3;
      const NoiseMultiplier: Single = 1.0): Boolean;
    function CanPerceiveTarget(const TargetTransform: TCastleTransform;
      out OutViaSight, OutViaHearing: Boolean): Boolean;

    property ReachedWaypointCount: Integer read FReachedWaypointCount;
    function AgentSummaryBadge: String;
  published
    property MoveSpeed: Single read FMoveSpeed write SetMoveSpeed
      {$ifdef FPC}default DefaultMoveSpeed{$endif};
    property TurnSpeedRad: Single read FTurnSpeedRad write FTurnSpeedRad
      {$ifdef FPC}default DefaultTurnSpeedRad{$endif};
    property CurrentWaypointName: String
      read FCurrentWaypointName write FCurrentWaypointName;
    property NavGridName: String read FNavGridName write FNavGridName;
    property AutoPatrolInRuntime: Boolean
      read FAutoPatrolInRuntime write FAutoPatrolInRuntime default true;
    property SightRadius: Single read FSightRadius write SetSightRadius
      {$ifdef FPC}default DefaultSightRadius{$endif};
    property SightHalfAngleDeg: Single
      read FSightHalfAngleDeg write SetSightHalfAngleDeg
      {$ifdef FPC}default DefaultSightHalfAngleDeg{$endif};
    property HearingRadius: Single read FHearingRadius write SetHearingRadius
      {$ifdef FPC}default DefaultHearingRadius{$endif};
    property ShowPerceptionInViewport: Boolean
      read FShowPerceptionInViewport write FShowPerceptionInViewport default true;
  end;

implementation

uses
  Math,
  CastleComponentSerialize, CastleScene, CastleStringUtils, CastleUIControls,
  CastleViewport;

function FindComponentByNameDeep(const ARoot: TComponent;
  const AName: String): TComponent;
var
  I: Integer;
  T: TCastleTransform;
  UI: TCastleUserInterface;
  VP: TCastleViewport;
begin
  Result := nil;
  if (ARoot = nil) or (AName = '') then
    Exit;
  if SameText(ARoot.Name, AName) then
    Exit(ARoot);
  Result := ARoot.FindComponent(AName);
  if Result <> nil then
    Exit;

  for I := 0 to ARoot.ComponentCount - 1 do
    if SameText(ARoot.Components[I].Name, AName) then
      Exit(ARoot.Components[I]);

  if ARoot is TCastleTransform then
  begin
    T := TCastleTransform(ARoot);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindComponentByNameDeep(T[I], AName);
      if Result <> nil then
        Exit;
    end;
  end else
  if ARoot is TCastleUserInterface then
  begin
    if ARoot is TCastleViewport then
    begin
      VP := TCastleViewport(ARoot);
      if VP.Items <> nil then
      begin
        Result := FindComponentByNameDeep(VP.Items, AName);
        if Result <> nil then
          Exit;
      end;
    end;
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindComponentByNameDeep(UI.Controls[I], AName);
      if Result <> nil then
        Exit;
    end;
  end;
end;

{ TCastleWaypointNode -------------------------------------------------------- }

constructor TCastleWaypointNode.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FWaypointLabel := '';
  FNextWaypointName := '';
  FWaitTimeSec := DefaultWaitTimeSec;
  FAcceptanceRadius := DefaultAcceptanceRadius;
  FShowLinkInViewport := true;
end;

function TCastleWaypointNode.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'WaypointLabel', 'NextWaypointName', 'WaitTimeSec',
       'AcceptanceRadius', 'ShowLinkInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleWaypointNode.LocalBoundingBox: TBox3D;
begin
  Result := inherited LocalBoundingBox;
  if CastleDesignMode then
    Result.Include(Box3D(Vector3(-0.35, 0.0, -0.35), Vector3(0.35, 0.7, 0.35)));
end;

procedure TCastleWaypointNode.SetWaitTimeSec(const Value: Single);
begin
  FWaitTimeSec := Max(0.0, Value);
end;

procedure TCastleWaypointNode.SetAcceptanceRadius(const Value: Single);
begin
  FAcceptanceRadius := Max(0.05, Value);
end;

function TCastleWaypointNode.ResolveNextWaypoint(
  const ASearchRoot: TComponent): TCastleWaypointNode;
var
  Root: TComponent;
  Found: TComponent;
begin
  Result := nil;
  if Trim(FNextWaypointName) = '' then
    Exit;
  if ASearchRoot <> nil then
    Root := ASearchRoot
  else if Owner <> nil then
    Root := Owner
  else
    Root := Parent;
  Found := FindComponentByNameDeep(Root, Trim(FNextWaypointName));
  if Found is TCastleWaypointNode then
    Result := TCastleWaypointNode(Found);
end;

function TCastleWaypointNode.WaypointSummaryBadge: String;
begin
  if Trim(FNextWaypointName) <> '' then
    Result := Format('[WP -> %s]', [FNextWaypointName])
  else
    Result := '[WP End]';
end;

{ TCastleNavGrid ------------------------------------------------------------- }

constructor TCastleNavGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCols := DefaultCols;
  FRows := DefaultRows;
  FCellSize := DefaultCellSize;
  FAgentRadius := DefaultAgentRadius;
  FMaxStepHeight := DefaultMaxStepHeight;
  FAllowDiagonal := true;
  FBlockedCellsData := '';
  FDataDirty := false;
  EnsureGridAllocated;
end;

function TCastleNavGrid.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Cols', 'Rows', 'CellSize', 'AgentRadius',
       'MaxStepHeight', 'AllowDiagonal', 'BlockedCellsData'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleNavGrid.LocalBoundingBox: TBox3D;
var
  HalfW, HalfD: Single;
begin
  Result := inherited LocalBoundingBox;
  if CastleDesignMode then
  begin
    HalfW := FCols * FCellSize * 0.5;
    HalfD := FRows * FCellSize * 0.5;
    Result.Include(Box3D(Vector3(-HalfW, -0.05, -HalfD), Vector3(HalfW, 0.15, HalfD)));
  end;
end;

procedure TCastleNavGrid.Loaded;
begin
  inherited Loaded;
  EnsureGridAllocated;
end;

procedure TCastleNavGrid.EnsureGridAllocated;
var
  Total, I, C, R, ColonPos: Integer;
  Tokens: TCastleStringList;
  Tok: String;
begin
  Total := FCols * FRows;
  if Length(FBlocked) <> Total then
  begin
    SetLength(FBlocked, Total);
    for I := 0 to Total - 1 do
      FBlocked[I] := false;
    FDataDirty := true;
  end;

  if not FDataDirty then
    Exit;
  FDataDirty := false;

  for I := 0 to Total - 1 do
    FBlocked[I] := false;
  if Trim(FBlockedCellsData) = '' then
    Exit;

  Tokens := CreateTokens(FBlockedCellsData, [';', ',', ' ']);
  try
    for I := 0 to Tokens.Count - 1 do
    begin
      Tok := Tokens[I];
      ColonPos := Pos(':', Tok);
      if (ColonPos > 1) and
         TryStrToInt(Copy(Tok, 1, ColonPos - 1), C) and
         TryStrToInt(Copy(Tok, ColonPos + 1, MaxInt), R) and
         (C >= 0) and (C < FCols) and (R >= 0) and (R < FRows) then
        FBlocked[R * FCols + C] := true;
    end;
  finally
    FreeAndNil(Tokens);
  end;
end;

procedure TCastleNavGrid.RebuildBlockedString;
var
  SB: TStringBuilder;
  R, C: Integer;
  First: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    First := true;
    for R := 0 to FRows - 1 do
      for C := 0 to FCols - 1 do
        if FBlocked[R * FCols + C] then
        begin
          if not First then
            SB.Append(';');
          SB.Append(IntToStr(C));
          SB.Append(':');
          SB.Append(IntToStr(R));
          First := false;
        end;
    FBlockedCellsData := SB.ToString;
    FDataDirty := false;
  finally
    FreeAndNil(SB);
  end;
end;

function TCastleNavGrid.IsNonEmptyBlockedData: Boolean;
begin
  Result := Trim(FBlockedCellsData) <> '';
end;

procedure TCastleNavGrid.SetCols(const Value: Integer);
var
  ClampedV: Integer;
begin
  ClampedV := Clamped(Value, 2, 512);
  if FCols = ClampedV then
    Exit;
  FCols := ClampedV;
  FDataDirty := true;
  EnsureGridAllocated;
end;

procedure TCastleNavGrid.SetRows(const Value: Integer);
var
  ClampedV: Integer;
begin
  ClampedV := Clamped(Value, 2, 512);
  if FRows = ClampedV then
    Exit;
  FRows := ClampedV;
  FDataDirty := true;
  EnsureGridAllocated;
end;

procedure TCastleNavGrid.SetCellSize(const Value: Single);
begin
  FCellSize := Max(0.1, Value);
end;

procedure TCastleNavGrid.SetAgentRadius(const Value: Single);
begin
  FAgentRadius := Max(0.0, Value);
end;

procedure TCastleNavGrid.SetMaxStepHeight(const Value: Single);
begin
  FMaxStepHeight := Max(0.2, Value);
end;

procedure TCastleNavGrid.SetBlockedCellsData(const Value: String);
begin
  if FBlockedCellsData = Value then
    Exit;
  FBlockedCellsData := Value;
  FDataDirty := true;
  EnsureGridAllocated;
end;

procedure TCastleNavGrid.ClearBlockedCells;
var
  I: Integer;
begin
  EnsureGridAllocated;
  for I := 0 to High(FBlocked) do
    FBlocked[I] := false;
  FBlockedCellsData := '';
  FDataDirty := false;
end;

function TCastleNavGrid.IsCellInBounds(const ACol, ARow: Integer): Boolean;
begin
  Result := (ACol >= 0) and (ACol < FCols) and (ARow >= 0) and (ARow < FRows);
end;

function TCastleNavGrid.IsCellBlocked(const ACol, ARow: Integer): Boolean;
begin
  EnsureGridAllocated;
  if not IsCellInBounds(ACol, ARow) then
    Exit(true);
  Result := FBlocked[ARow * FCols + ACol];
end;

procedure TCastleNavGrid.SetCellBlocked(const ACol, ARow: Integer;
  const ABlocked: Boolean);
begin
  EnsureGridAllocated;
  if not IsCellInBounds(ACol, ARow) then
    Exit;
  FBlocked[ARow * FCols + ACol] := ABlocked;
  RebuildBlockedString;
end;

function TCastleNavGrid.BlockedCellCount: Integer;
var
  I: Integer;
begin
  EnsureGridAllocated;
  Result := 0;
  for I := 0 to High(FBlocked) do
    if FBlocked[I] then
      Inc(Result);
end;

function TCastleNavGrid.WorldToCell(const WorldPt: TVector3;
  out OutCol, OutRow: Integer): Boolean;
var
  OriginW: TVector3;
  HalfW, HalfD, RelX, RelZ: Single;
begin
  OriginW := WorldTranslation;
  HalfW := FCols * FCellSize * 0.5;
  HalfD := FRows * FCellSize * 0.5;
  RelX := (WorldPt.X - (OriginW.X - HalfW)) / FCellSize;
  RelZ := (WorldPt.Z - (OriginW.Z - HalfD)) / FCellSize;
  OutCol := Floor(RelX);
  OutRow := Floor(RelZ);
  Result := IsCellInBounds(OutCol, OutRow);
end;

function TCastleNavGrid.CellToWorldCenter(const ACol, ARow: Integer): TVector3;
var
  OriginW: TVector3;
  HalfW, HalfD: Single;
begin
  OriginW := WorldTranslation;
  HalfW := FCols * FCellSize * 0.5;
  HalfD := FRows * FCellSize * 0.5;
  Result := Vector3(
    (OriginW.X - HalfW) + (ACol + 0.5) * FCellSize,
    OriginW.Y,
    (OriginW.Z - HalfD) + (ARow + 0.5) * FCellSize);
end;

function TCastleNavGrid.BakeObstaclesFromWorld(
  const AWorldRoot: TCastleTransform): Integer;
var
  GridOrigin: TVector3;
  HalfW, HalfD, MinBandY, MaxBandY: Single;

  function HasNonTransientChild(const Node: TCastleTransform): Boolean;
  var
    K: Integer;
  begin
    Result := false;
    for K := 0 to Node.Count - 1 do
      if not (csTransient in Node[K].ComponentStyle) then
        Exit(true);
  end;

  procedure ScanObstacleSubtree(const Node: TCastleTransform);
  var
    I, MinC, MaxC, MinR, MaxR, C, R: Integer;
    BoxW: TBox3D;
    MinPt, MaxPt: TVector3;
  begin
    if (Node = nil) or (not Node.Exists) or
       (Node = Self) or
       (csTransient in Node.ComponentStyle) or
       (Node.Tag = NavWalkableIgnoreTag) or
       (Node is TCastleCamera) or
       (Node is TCastleAbstractLight) or
       (Node is TCastleWaypointNode) or
       (Node is TCastleNavGrid) or
       (Node.FindBehavior(TCastlePatrolAgentBehavior) <> nil) then
      Exit;

    { Leaf/geometry check: inspect transforms that have no non-transient
      children (covering TCastleScene as well as TCastleAbstractPrimitive /
      TCastleBox / TCastleSphere whose internal FScene is csTransient), or
      extract transient primitive geometry if children are attached. }
    BoxW := TBox3D.Empty;
    if (Node <> AWorldRoot) and (not HasNonTransientChild(Node)) then
      BoxW := Node.WorldBoundingBox
    else if Node is TCastleAbstractPrimitive then
    begin
      for I := 0 to Node.Count - 1 do
        if csTransient in Node[I].ComponentStyle then
          BoxW.Include(Node[I].WorldBoundingBox);
    end;

    if not BoxW.IsEmpty then
    begin
      { Skip wide flat floor slabs whose top sits at or below GridOrigin.Y + 0.15 }
      if (BoxW.Data[1].Y > GridOrigin.Y + 0.15) and
         (BoxW.Data[0].Y < MaxBandY) and
         (BoxW.Data[1].Y > MinBandY) then
      begin
        MinPt := Vector3(BoxW.Data[0].X - FAgentRadius, GridOrigin.Y, BoxW.Data[0].Z - FAgentRadius);
        MaxPt := Vector3(BoxW.Data[1].X + FAgentRadius, GridOrigin.Y, BoxW.Data[1].Z + FAgentRadius);

        MinC := Clamped(Floor((MinPt.X - (GridOrigin.X - HalfW)) / FCellSize), 0, FCols - 1);
        MaxC := Clamped(Floor((MaxPt.X - (GridOrigin.X - HalfW)) / FCellSize), 0, FCols - 1);
        MinR := Clamped(Floor((MinPt.Z - (GridOrigin.Z - HalfD)) / FCellSize), 0, FRows - 1);
        MaxR := Clamped(Floor((MaxPt.Z - (GridOrigin.Z - HalfD)) / FCellSize), 0, FRows - 1);

        for R := MinR to MaxR do
          for C := MinC to MaxC do
            FBlocked[R * FCols + C] := true;
      end;
    end;

    for I := 0 to Node.Count - 1 do
      ScanObstacleSubtree(Node[I]);
  end;

begin
  EnsureGridAllocated;
  ClearBlockedCells;
  if AWorldRoot = nil then
    Exit(0);

  GridOrigin := WorldTranslation;
  HalfW := FCols * FCellSize * 0.5;
  HalfD := FRows * FCellSize * 0.5;
  MinBandY := GridOrigin.Y + 0.15;
  MaxBandY := GridOrigin.Y + FMaxStepHeight;

  ScanObstacleSubtree(AWorldRoot);
  RebuildBlockedString;
  Result := BlockedCellCount;
end;

function TCastleNavGrid.FindNearestWalkableCell(const StartCol, StartRow: Integer;
  out OutCol, OutRow: Integer): Boolean;
var
  ClampedC, ClampedR, Rad, DC, DR, C, R: Integer;
begin
  ClampedC := Clamped(StartCol, 0, FCols - 1);
  ClampedR := Clamped(StartRow, 0, FRows - 1);
  if not IsCellBlocked(ClampedC, ClampedR) then
  begin
    OutCol := ClampedC;
    OutRow := ClampedR;
    Exit(true);
  end;

  for Rad := 1 to Max(FCols, FRows) do
    for DR := -Rad to Rad do
      for DC := -Rad to Rad do
        if (Abs(DC) = Rad) or (Abs(DR) = Rad) then
        begin
          C := ClampedC + DC;
          R := ClampedR + DR;
          if IsCellInBounds(C, R) and (not IsCellBlocked(C, R)) then
          begin
            OutCol := C;
            OutRow := R;
            Exit(true);
          end;
        end;

  Result := false;
end;

function OctileHeuristic(const C1, R1, C2, R2: Integer): Single;
const
  DiagCost = 1.41421356;
var
  DX, DZ: Integer;
begin
  DX := Abs(C1 - C2);
  DZ := Abs(R1 - R2);
  Result := (DX + DZ) + (DiagCost - 2.0) * Min(DX, DZ);
end;

function TCastleNavGrid.FindPathWorld(const StartWorld, GoalWorld: TVector3;
  const OutPath: TVector3List): Boolean;
const
  DirX: array [0..7] of Integer = (1, -1, 0, 0, 1, 1, -1, -1);
  DirZ: array [0..7] of Integer = (0, 0, 1, -1, 1, -1, 1, -1);
  StepCost: array [0..7] of Single = (1.0, 1.0, 1.0, 1.0,
    1.41421356, 1.41421356, 1.41421356, 1.41421356);
var
  RawSC, RawSR, RawGC, RawGR, SC, SR, GC, GR: Integer;
  Total, StartIdx, GoalIdx, CurIdx, CurC, CurR, NC, NR, NIdx, I, DirMax, D: Integer;
  BestOpenSlot, BestNode: Integer;
  BestF, TentativeG: Single;
  GScores, FScores: array of Single;
  CameFrom: array of Integer;
  Closed: array of Boolean;
  OpenList: array of Integer;
  OpenCount: Integer;
  RevCells: array of Integer;
  RevCount: Integer;
  Pt: TVector3;
begin
  Result := false;
  if OutPath = nil then
    Exit;
  OutPath.Clear;
  EnsureGridAllocated;

  WorldToCell(StartWorld, RawSC, RawSR);
  WorldToCell(GoalWorld, RawGC, RawGR);
  if not FindNearestWalkableCell(RawSC, RawSR, SC, SR) then
    Exit;
  if not FindNearestWalkableCell(RawGC, RawGR, GC, GR) then
    Exit;

  StartIdx := SR * FCols + SC;
  GoalIdx := GR * FCols + GC;
  if StartIdx = GoalIdx then
  begin
    OutPath.Add(GoalWorld);
    Exit(true);
  end;

  Total := FCols * FRows;
  SetLength(GScores, Total);
  SetLength(FScores, Total);
  SetLength(CameFrom, Total);
  SetLength(Closed, Total);
  SetLength(OpenList, Total);
  for I := 0 to Total - 1 do
  begin
    GScores[I] := 1e30;
    FScores[I] := 1e30;
    CameFrom[I] := -1;
    Closed[I] := false;
  end;

  GScores[StartIdx] := 0.0;
  FScores[StartIdx] := OctileHeuristic(SC, SR, GC, GR);
  OpenList[0] := StartIdx;
  OpenCount := 1;
  DirMax := IfThen(FAllowDiagonal, 7, 3);

  while OpenCount > 0 do
  begin
    BestOpenSlot := 0;
    BestNode := OpenList[0];
    BestF := FScores[BestNode];
    for I := 1 to OpenCount - 1 do
      if FScores[OpenList[I]] < BestF then
      begin
        BestF := FScores[OpenList[I]];
        BestNode := OpenList[I];
        BestOpenSlot := I;
      end;

    CurIdx := BestNode;
    OpenList[BestOpenSlot] := OpenList[OpenCount - 1];
    Dec(OpenCount);

    if CurIdx = GoalIdx then
    begin
      SetLength(RevCells, Total);
      RevCount := 0;
      while (CurIdx >= 0) and (CurIdx <> StartIdx) do
      begin
        RevCells[RevCount] := CurIdx;
        Inc(RevCount);
        CurIdx := CameFrom[CurIdx];
      end;
      for I := RevCount - 1 downto 0 do
      begin
        Pt := CellToWorldCenter(RevCells[I] mod FCols, RevCells[I] div FCols);
        OutPath.Add(Pt);
      end;
      if OutPath.Count > 0 then
        OutPath.L[OutPath.Count - 1] := Vector3(GoalWorld.X, OutPath.L[OutPath.Count - 1].Y, GoalWorld.Z);
      Exit(true);
    end;

    Closed[CurIdx] := true;
    CurC := CurIdx mod FCols;
    CurR := CurIdx div FCols;

    for D := 0 to DirMax do
    begin
      NC := CurC + DirX[D];
      NR := CurR + DirZ[D];
      if not IsCellInBounds(NC, NR) then
        Continue;
      NIdx := NR * FCols + NC;
      if Closed[NIdx] or FBlocked[NIdx] then
        Continue;

      { Corner-cutting guard for diagonal moves }
      if D >= 4 then
      begin
        if FBlocked[CurR * FCols + NC] or FBlocked[NR * FCols + CurC] then
          Continue;
      end;

      TentativeG := GScores[CurIdx] + StepCost[D];
      if TentativeG < GScores[NIdx] then
      begin
        CameFrom[NIdx] := CurIdx;
        GScores[NIdx] := TentativeG;
        FScores[NIdx] := TentativeG + OctileHeuristic(NC, NR, GC, GR);
        BestOpenSlot := -1;
        for I := 0 to OpenCount - 1 do
          if OpenList[I] = NIdx then
          begin
            BestOpenSlot := I;
            Break;
          end;
        if BestOpenSlot < 0 then
        begin
          OpenList[OpenCount] := NIdx;
          Inc(OpenCount);
        end;
      end;
    end;
  end;
end;

function TCastleNavGrid.NavGridSummaryBadge: String;
begin
  Result := Format('[NavGrid:%dx%d Blocked:%d]',
    [FCols, FRows, BlockedCellCount]);
end;

{ TCastlePatrolAgentBehavior ------------------------------------------------- }

constructor TCastlePatrolAgentBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMoveSpeed := DefaultMoveSpeed;
  FTurnSpeedRad := DefaultTurnSpeedRad;
  FCurrentWaypointName := '';
  FNavGridName := '';
  FAutoPatrolInRuntime := true;
  FSightRadius := DefaultSightRadius;
  FSightHalfAngleDeg := DefaultSightHalfAngleDeg;
  FHearingRadius := DefaultHearingRadius;
  FShowPerceptionInViewport := true;
  FDwellRemainingSec := 0.0;
  FReachedWaypointCount := 0;
  FCurrentPath := TVector3List.Create;
  FCurrentPathIndex := 0;
  FCachedGoalWaypointName := '';
end;

destructor TCastlePatrolAgentBehavior.Destroy;
begin
  FreeAndNil(FCurrentPath);
  inherited Destroy;
end;

function TCastlePatrolAgentBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'MoveSpeed', 'TurnSpeedRad', 'CurrentWaypointName', 'NavGridName',
       'AutoPatrolInRuntime', 'SightRadius', 'SightHalfAngleDeg',
       'HearingRadius', 'ShowPerceptionInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastlePatrolAgentBehavior.SetMoveSpeed(const Value: Single);
begin
  FMoveSpeed := Max(0.0, Value);
end;

procedure TCastlePatrolAgentBehavior.SetSightRadius(const Value: Single);
begin
  FSightRadius := Max(0.0, Value);
end;

procedure TCastlePatrolAgentBehavior.SetSightHalfAngleDeg(const Value: Single);
begin
  FSightHalfAngleDeg := Clamped(Value, 1.0, 180.0);
end;

procedure TCastlePatrolAgentBehavior.SetHearingRadius(const Value: Single);
begin
  FHearingRadius := Max(0.0, Value);
end;

function TCastlePatrolAgentBehavior.ResolveSearchRoot: TComponent;
begin
  if Owner <> nil then
    Result := Owner
  else if (Parent <> nil) and (Parent.Parent <> nil) then
    Result := Parent.Parent
  else
    Result := Parent;
end;

function TCastlePatrolAgentBehavior.ResolveWaypoint(const AName: String): TCastleWaypointNode;
var
  Found: TComponent;
begin
  Result := nil;
  Found := FindComponentByNameDeep(ResolveSearchRoot, Trim(AName));
  if Found is TCastleWaypointNode then
    Result := TCastleWaypointNode(Found);
end;

function TCastlePatrolAgentBehavior.ResolveNavGrid: TCastleNavGrid;
var
  Found: TComponent;
begin
  Result := nil;
  if Trim(FNavGridName) = '' then
    Exit;
  Found := FindComponentByNameDeep(ResolveSearchRoot, Trim(FNavGridName));
  if Found is TCastleNavGrid then
    Result := TCastleNavGrid(Found);
end;

procedure TCastlePatrolAgentBehavior.InvalidateCachedPath;
begin
  FCurrentPath.Clear;
  FCurrentPathIndex := 0;
  FCachedGoalWaypointName := '';
end;

procedure TCastlePatrolAgentBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if CastleDesignMode or (not FAutoPatrolInRuntime) then
    Exit;
  StepPatrol(SecondsPassed);
end;

procedure TCastlePatrolAgentBehavior.StepPatrol(const DeltaSec: Single);
var
  WP, NextWP: TCastleWaypointNode;
  Grid: TCastleNavGrid;
  AgentPos, SteerGoal, Delta, HorizDir: TVector3;
  Dist, StepDist: Single;
begin
  if (Parent = nil) or (DeltaSec <= 0.0) then
    Exit;

  if FDwellRemainingSec > 0.0 then
  begin
    FDwellRemainingSec := Max(0.0, FDwellRemainingSec - DeltaSec);
    if FDwellRemainingSec > 0.0 then
      Exit;
  end;

  WP := ResolveWaypoint(FCurrentWaypointName);
  if WP = nil then
    Exit;

  AgentPos := Parent.Translation;
  Grid := ResolveNavGrid;

  if (Grid <> nil) and (not SameText(FCachedGoalWaypointName, WP.Name)) then
  begin
    FCachedGoalWaypointName := WP.Name;
    FCurrentPathIndex := 0;
    if not Grid.FindPathWorld(Parent.WorldTranslation, WP.WorldTranslation, FCurrentPath) then
      FCurrentPath.Clear;
  end;

  if (FCurrentPath.Count > 0) and (FCurrentPathIndex < FCurrentPath.Count) then
    SteerGoal := Vector3(FCurrentPath.L[FCurrentPathIndex].X, AgentPos.Y, FCurrentPath.L[FCurrentPathIndex].Z)
  else
    SteerGoal := Vector3(WP.WorldTranslation.X, AgentPos.Y, WP.WorldTranslation.Z);

  Delta := SteerGoal - AgentPos;
  Dist := Delta.Length;
  StepDist := FMoveSpeed * DeltaSec;

  if Dist > 0.001 then
  begin
    HorizDir := Vector3(Delta.X, 0.0, Delta.Z);
    if not HorizDir.IsZero then
      Parent.Direction := HorizDir.Normalize;
  end;

  { Advance along intermediate A* sub-nodes }
  if (FCurrentPath.Count > 0) and (FCurrentPathIndex < FCurrentPath.Count - 1) then
  begin
    if Dist <= Max(0.15, StepDist) then
    begin
      Parent.Translation := SteerGoal;
      Inc(FCurrentPathIndex);
    end else
      Parent.Translation := AgentPos + Delta.Normalize * StepDist;
    Exit;
  end;

  { Final approach to target waypoint }
  if Dist <= Max(WP.AcceptanceRadius, StepDist) then
  begin
    Parent.Translation := Vector3(WP.WorldTranslation.X, AgentPos.Y, WP.WorldTranslation.Z);
    Inc(FReachedWaypointCount);
    FDwellRemainingSec := WP.WaitTimeSec;
    InvalidateCachedPath;
    NextWP := WP.ResolveNextWaypoint(ResolveSearchRoot);
    if NextWP <> nil then
      FCurrentWaypointName := NextWP.Name
    else
      FCurrentWaypointName := '';
  end else
    Parent.Translation := AgentPos + Delta.Normalize * StepDist;
end;

function TCastlePatrolAgentBehavior.CanSeeWorldPoint(
  const TargetWorldPt: TVector3): Boolean;
var
  AgentPos, AgentDir, AgentUp, ToTarget, FwdXZ, ToTargetXZ: TVector3;
  DistSq, CosHalfAngle, DotVal: Single;
begin
  Result := false;
  if (Parent = nil) or (FSightRadius <= 0.0) then
    Exit;
  Parent.GetWorldView(AgentPos, AgentDir, AgentUp);
  ToTarget := TargetWorldPt - AgentPos;
  DistSq := ToTarget.LengthSqr;
  if DistSq > Sqr(FSightRadius) then
    Exit;
  if DistSq < 1e-6 then
    Exit(true);

  FwdXZ := Vector3(AgentDir.X, 0.0, AgentDir.Z);
  ToTargetXZ := Vector3(ToTarget.X, 0.0, ToTarget.Z);
  if FwdXZ.IsZero or ToTargetXZ.IsZero then
    Exit(true);

  CosHalfAngle := Cos(DegToRad(FSightHalfAngleDeg));
  DotVal := TVector3.DotProduct(FwdXZ.Normalize, ToTargetXZ.Normalize);
  Result := DotVal >= CosHalfAngle - 1e-4;
end;

function TCastlePatrolAgentBehavior.CanHearWorldPoint(
  const TargetWorldPt: TVector3; const NoiseMultiplier: Single): Boolean;
var
  EffRadius: Single;
begin
  Result := false;
  if Parent = nil then
    Exit;
  EffRadius := FHearingRadius * Max(0.0, NoiseMultiplier);
  if EffRadius <= 0.0 then
    Exit;
  Result := PointsDistanceSqr(Parent.WorldTranslation, TargetWorldPt) <= Sqr(EffRadius);
end;

function TCastlePatrolAgentBehavior.CanPerceiveTarget(
  const TargetTransform: TCastleTransform;
  out OutViaSight, OutViaHearing: Boolean): Boolean;
var
  TargetPt: TVector3;
begin
  OutViaSight := false;
  OutViaHearing := false;
  if TargetTransform = nil then
    Exit(false);
  TargetPt := TargetTransform.WorldTranslation;
  OutViaSight := CanSeeWorldPoint(TargetPt);
  OutViaHearing := CanHearWorldPoint(TargetPt, 1.0);
  Result := OutViaSight or OutViaHearing;
end;

function TCastlePatrolAgentBehavior.AgentSummaryBadge: String;
var
  WpPart: String;
begin
  if Trim(FCurrentWaypointName) <> '' then
    WpPart := '->' + FCurrentWaypointName
  else
    WpPart := ':Idle';
  Result := Format('[AI%s FOV:%.0fd]', [WpPart, FSightHalfAngleDeg * 2.0]);
end;

initialization
  RegisterSerializableComponent(TCastleWaypointNode,
    ['AI & Navigation', 'Waypoint Node']);
  RegisterSerializableComponent(TCastleNavGrid,
    ['AI & Navigation', 'Navigation Grid (A*)']);
  RegisterSerializableComponent(TCastlePatrolAgentBehavior,
    ['Behaviors', 'AI Patrol & Perception Agent']);
end.
