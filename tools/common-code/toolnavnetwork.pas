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

{ Design-time AI waypoint loop builder, A* NavGrid world baker, and perception
  network inspector for @link(CastleNavNetwork) (Phase 290). }
unit ToolNavNetwork;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleNavNetwork;

type
  TCastleWaypointNodeArray = array of TCastleWaypointNode;
  TCastleNavGridArray = array of TCastleNavGrid;
  TCastlePatrolAgentArray = array of TCastlePatrolAgentBehavior;

  { Complete snapshot of AI navigation & perception objects inside a design. }
  TNavNetworkSummary = record
    Waypoints: TCastleWaypointNodeArray;
    NavGrids: TCastleNavGridArray;
    Agents: TCastlePatrolAgentArray;
    BrokenWaypointLinks: Integer;
  end;

  { Static editor & CLI helper methods for AI Navigation & Waypoint Studio. }
  TNavNetworkHelper = class
  public
    { Discover all waypoints, NavGrids, and patrol agents in @code(DesignRoot). }
    class function ScanNavNetwork(const DesignRoot: TComponent): TNavNetworkSummary; static;

    { Resolve the primary @code(TCastleViewport.Items) or @code(TCastleTransform)
      world container inside @code(DesignRoot). }
    class function FindWorldItemsRoot(const DesignRoot: TComponent): TCastleTransform; static;

    { Create a circular linked loop of @code(PointCount) @link(TCastleWaypointNode)
      instances around @code(CenterPos), returning the first waypoint. }
    class function CreatePatrolLoop(
      const DesignRoot, DesignOwner: TComponent;
      const CenterPos: TVector3;
      const Radius: Single = 8.0;
      const PointCount: Integer = 4): TCastleWaypointNode; static;

    { Find an existing @link(TCastleNavGrid) or create a new one in @code(DesignRoot)
      and immediately bake world obstacles into it. }
    class function CreateOrBakeNavGrid(
      const DesignRoot, DesignOwner: TComponent;
      const Cols: Integer = 32;
      const Rows: Integer = 32;
      const CellSize: Single = 1.0): TCastleNavGrid; static;

    { Attach a @link(TCastlePatrolAgentBehavior) to @code(TargetTransform) wired
      to @code(FirstWaypointName) and @code(NavGridName). }
    class function AttachPatrolAgent(
      const TargetTransform: TCastleTransform;
      const DesignOwner: TComponent;
      const FirstWaypointName: String = '';
      const NavGridName: String = ''): TCastlePatrolAgentBehavior; static;

    { Advance all @link(TCastlePatrolAgentBehavior) instances in @code(DesignRoot). }
    class procedure StepAllPatrolAgents(const DesignRoot: TComponent;
      const DeltaSec: Single); static;

    { Export @code(Summary) as a Markdown report. }
    class function FormatNavReportMarkdown(
      const Summary: TNavNetworkSummary;
      const SearchRoot: TComponent): String; static;
  end;

implementation

uses
  Math,
  CastleUIControls, CastleViewport, CastleUtils;

procedure CollectNavRecursive(const C: TComponent; var Sum: TNavNetworkSummary);

  procedure AddWaypoint(const WP: TCastleWaypointNode);
  var
    I, N: Integer;
  begin
    if (WP = nil) or (csTransient in WP.ComponentStyle) then
      Exit;
    for I := 0 to High(Sum.Waypoints) do
      if Sum.Waypoints[I] = WP then
        Exit;
    N := Length(Sum.Waypoints);
    SetLength(Sum.Waypoints, N + 1);
    Sum.Waypoints[N] := WP;
  end;

  procedure AddGrid(const G: TCastleNavGrid);
  var
    I, N: Integer;
  begin
    if (G = nil) or (csTransient in G.ComponentStyle) then
      Exit;
    for I := 0 to High(Sum.NavGrids) do
      if Sum.NavGrids[I] = G then
        Exit;
    N := Length(Sum.NavGrids);
    SetLength(Sum.NavGrids, N + 1);
    Sum.NavGrids[N] := G;
  end;

  procedure AddAgent(const A: TCastlePatrolAgentBehavior);
  var
    I, N: Integer;
  begin
    if (A = nil) or (csTransient in A.ComponentStyle) then
      Exit;
    for I := 0 to High(Sum.Agents) do
      if Sum.Agents[I] = A then
        Exit;
    N := Length(Sum.Agents);
    SetLength(Sum.Agents, N + 1);
    Sum.Agents[N] := A;
  end;

var
  I: Integer;
  T: TCastleTransform;
  UI: TCastleUserInterface;
  VP: TCastleViewport;
begin
  if (C = nil) or (csTransient in C.ComponentStyle) then
    Exit;

  if C is TCastleWaypointNode then
    AddWaypoint(TCastleWaypointNode(C))
  else if C is TCastleNavGrid then
    AddGrid(TCastleNavGrid(C))
  else if C is TCastlePatrolAgentBehavior then
    AddAgent(TCastlePatrolAgentBehavior(C));

  for I := 0 to C.ComponentCount - 1 do
    CollectNavRecursive(C.Components[I], Sum);

  if C is TCastleTransform then
  begin
    T := TCastleTransform(C);
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastlePatrolAgentBehavior then
        AddAgent(TCastlePatrolAgentBehavior(T.Behaviors[I]));
    for I := 0 to T.Count - 1 do
      CollectNavRecursive(T[I], Sum);
  end else
  if C is TCastleUserInterface then
  begin
    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      if VP.Items <> nil then
        CollectNavRecursive(VP.Items, Sum);
    end;
    UI := TCastleUserInterface(C);
    for I := 0 to UI.ControlsCount - 1 do
      CollectNavRecursive(UI.Controls[I], Sum);
  end;
end;

class function TNavNetworkHelper.ScanNavNetwork(
  const DesignRoot: TComponent): TNavNetworkSummary;
var
  I: Integer;
begin
  Result := Default(TNavNetworkSummary);
  CollectNavRecursive(DesignRoot, Result);
  for I := 0 to High(Result.Waypoints) do
    if (Trim(Result.Waypoints[I].NextWaypointName) <> '') and
       (Result.Waypoints[I].ResolveNextWaypoint(DesignRoot) = nil) then
      Inc(Result.BrokenWaypointLinks);
end;

class function TNavNetworkHelper.FindWorldItemsRoot(
  const DesignRoot: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if DesignRoot = nil then
    Exit;
  if DesignRoot is TCastleViewport then
    Exit(TCastleViewport(DesignRoot).Items);
  if DesignRoot is TCastleTransform then
    Exit(TCastleTransform(DesignRoot));
  if DesignRoot is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(DesignRoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindWorldItemsRoot(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

function ProposeUniqueNavName(const AOwner: TComponent;
  const BaseName: String): String;
var
  Idx: Integer;
begin
  if (AOwner = nil) or (AOwner.FindComponent(BaseName) = nil) then
    Exit(BaseName);
  Idx := 1;
  repeat
    Result := BaseName + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TNavNetworkHelper.CreatePatrolLoop(
  const DesignRoot, DesignOwner: TComponent;
  const CenterPos: TVector3;
  const Radius: Single;
  const PointCount: Integer): TCastleWaypointNode;
var
  WorldItems: TCastleTransform;
  UseOwner: TComponent;
  Nodes: array of TCastleWaypointNode;
  N, I: Integer;
  Angle: Single;
begin
  Result := nil;
  WorldItems := FindWorldItemsRoot(DesignRoot);
  if WorldItems = nil then
    Exit;
  if DesignOwner <> nil then
    UseOwner := DesignOwner
  else
    UseOwner := DesignRoot;

  N := Max(2, PointCount);
  SetLength(Nodes, N);
  for I := 0 to N - 1 do
  begin
    Angle := (2.0 * Pi * I) / N;
    Nodes[I] := TCastleWaypointNode.Create(UseOwner);
    Nodes[I].Name := ProposeUniqueNavName(UseOwner, Format('Waypoint%d', [I + 1]));
    Nodes[I].WaypointLabel := Format('Patrol Stop %d', [I + 1]);
    Nodes[I].Translation := Vector3(
      CenterPos.X + Cos(Angle) * Radius,
      CenterPos.Y,
      CenterPos.Z + Sin(Angle) * Radius);
    WorldItems.Add(Nodes[I]);
  end;

  for I := 0 to N - 1 do
    Nodes[I].NextWaypointName := Nodes[(I + 1) mod N].Name;

  Result := Nodes[0];
end;

class function TNavNetworkHelper.CreateOrBakeNavGrid(
  const DesignRoot, DesignOwner: TComponent;
  const Cols, Rows: Integer;
  const CellSize: Single): TCastleNavGrid;
var
  Sum: TNavNetworkSummary;
  WorldItems: TCastleTransform;
  UseOwner: TComponent;
begin
  Result := nil;
  WorldItems := FindWorldItemsRoot(DesignRoot);
  if WorldItems = nil then
    Exit;
  Sum := ScanNavNetwork(DesignRoot);
  if Length(Sum.NavGrids) > 0 then
    Result := Sum.NavGrids[0]
  else
  begin
    if DesignOwner <> nil then
      UseOwner := DesignOwner
    else
      UseOwner := DesignRoot;
    Result := TCastleNavGrid.Create(UseOwner);
    Result.Name := ProposeUniqueNavName(UseOwner, 'WorldNavGrid');
    Result.Cols := Cols;
    Result.Rows := Rows;
    Result.CellSize := CellSize;
    WorldItems.Add(Result);
  end;
  Result.BakeObstaclesFromWorld(WorldItems);
end;

class function TNavNetworkHelper.AttachPatrolAgent(
  const TargetTransform: TCastleTransform;
  const DesignOwner: TComponent;
  const FirstWaypointName, NavGridName: String): TCastlePatrolAgentBehavior;
var
  UseOwner: TComponent;
begin
  Result := nil;
  if TargetTransform = nil then
    Exit;
  Result := TargetTransform.FindBehavior(
    TCastlePatrolAgentBehavior) as TCastlePatrolAgentBehavior;
  if Result = nil then
  begin
    if DesignOwner <> nil then
      UseOwner := DesignOwner
    else
      UseOwner := TargetTransform.Owner;
    Result := TCastlePatrolAgentBehavior.Create(UseOwner);
    Result.Name := ProposeUniqueNavName(UseOwner, 'PatrolAgentBehavior');
    TargetTransform.AddBehavior(Result);
  end;
  if FirstWaypointName <> '' then
    Result.CurrentWaypointName := FirstWaypointName;
  if NavGridName <> '' then
    Result.NavGridName := NavGridName;
end;

class procedure TNavNetworkHelper.StepAllPatrolAgents(
  const DesignRoot: TComponent; const DeltaSec: Single);
var
  Sum: TNavNetworkSummary;
  I: Integer;
begin
  Sum := ScanNavNetwork(DesignRoot);
  for I := 0 to High(Sum.Agents) do
    Sum.Agents[I].StepPatrol(DeltaSec);
end;

class function TNavNetworkHelper.FormatNavReportMarkdown(
  const Summary: TNavNetworkSummary;
  const SearchRoot: TComponent): String;
var
  SB: TStringBuilder;
  I: Integer;
  WP: TCastleWaypointNode;
  G: TCastleNavGrid;
  A: TCastlePatrolAgentBehavior;
  ParentName: String;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('## AI Navigation, Waypoints & Perception Report');
    SB.AppendLine(Format('- **Waypoints:** %d (%d broken links) | **NavGrids:** %d | **Patrol Agents:** %d',
      [Length(Summary.Waypoints), Summary.BrokenWaypointLinks,
       Length(Summary.NavGrids), Length(Summary.Agents)]));
    SB.AppendLine;

    if Length(Summary.NavGrids) > 0 then
    begin
      SB.AppendLine('### A* Navigation Grids');
      for I := 0 to High(Summary.NavGrids) do
      begin
        G := Summary.NavGrids[I];
        SB.AppendLine(Format('- `%s`: `%dx%d` cells (`%.2fm`), Blocked: `%d`',
          [G.Name, G.Cols, G.Rows, G.CellSize, G.BlockedCellCount]));
      end;
      SB.AppendLine;
    end;

    if Length(Summary.Waypoints) > 0 then
    begin
      SB.AppendLine('### Patrol Waypoints');
      for I := 0 to High(Summary.Waypoints) do
      begin
        WP := Summary.Waypoints[I];
        SB.AppendLine(Format('- `%s` -> `%s` (Wait: `%.1fs`, Pos: `%s`)',
          [WP.Name, WP.NextWaypointName, WP.WaitTimeSec,
           WP.WorldTranslation.ToString]));
      end;
      SB.AppendLine;
    end;

    if Length(Summary.Agents) > 0 then
    begin
      SB.AppendLine('### AI Patrol & Perception Agents');
      for I := 0 to High(Summary.Agents) do
      begin
        A := Summary.Agents[I];
        if (A.Parent <> nil) and (A.Parent.Name <> '') then
          ParentName := A.Parent.Name
        else
          ParentName := '<detached>';
        SB.AppendLine(Format('- `%s` on `%s`: Target `%s`, Speed `%.1f m/s`, Sight `%.1fm / %.0f°`, Hearing `%.1fm`',
          [A.Name, ParentName, A.CurrentWaypointName, A.MoveSpeed,
           A.SightRadius, A.SightHalfAngleDeg * 2.0, A.HearingRadius]));
      end;
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
