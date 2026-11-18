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

{ Stateless helper for the Parkour Traversal Ledge/Vault/Mantle Scanner &
  Root-Motion Warp Anchor Studio (Phase 349). }
unit ToolTraversalStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleTraversalParkour;

type
  TTraversalStudioSummary = record
    ScannerCount: Integer;
    LastActionName: String;
    LastMontageId: String;
    LastObstacleHeight: Single;
    LastObstacleDepth: Single;
    WarningsCount: Integer;
  end;

  TTraversalStudioHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleAbstractRootTransform; static;
    class function FindFirstTraversal(const ARoot: TComponent): TCastleTraversalBehavior; static;

    { Spawn a 5-lane parkour obstacle course along X (-8, -4, 0, +4, +8) facing -Z:
      Lane 0: 0.40m Curb StepUp
      Lane 1: 1.05m x 0.45m Thin Vault Barrier
      Lane 2: 1.20m x 2.60m Thick Mantle Platform
      Lane 3: 2.20m High Ledge Wall
      Lane 4: 3.80m Sheer Unclimbable Tower }
    class function SpawnParkourGymCourseDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ARunner: TCastleTransform;
      out ATraversal: TCastleTraversalBehavior): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TTraversalStudioSummary; static;

    class function BuildMarkdownReport(const ARoot: TComponent): String; static;
  end;

implementation

function MakeUniqueName(const AOwner: TComponent; const ABase: String): String;
var
  Idx: Integer;
begin
  Result := ABase;
  if (AOwner = nil) or (AOwner.FindComponent(Result) = nil) then
    Exit;
  Idx := 1;
  repeat
    Result := ABase + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TTraversalStudioHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleAbstractRootTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleAbstractRootTransform then
    Exit(TCastleAbstractRootTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function TTraversalStudioHelper.FindFirstTraversal(
  const ARoot: TComponent): TCastleTraversalBehavior;

  function ScanRec(const T: TCastleTransform): TCastleTraversalBehavior;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    for I := 0 to T.BehaviorsCount - 1 do
      if T.Behaviors[I] is TCastleTraversalBehavior then
        Exit(TCastleTraversalBehavior(T.Behaviors[I]));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TTraversalStudioHelper.SpawnParkourGymCourseDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ARunner: TCastleTransform;
  out ATraversal: TCastleTraversalBehavior): Boolean;
var
  RootT: TCastleAbstractRootTransform;
  FloorBox: TCastleBox;
  RunnerCyl: TCastleCylinder;

  procedure AddObstacleBox(const AName: String; const AX, AHeight, ADepthZ: Single;
    const AColor: TVector4);
  var
    B: TCastleBox;
  begin
    B := TCastleBox.Create(ADesignOwner);
    B.Name := MakeUniqueName(ADesignOwner, AName);
    B.Size := Vector3(2.4, AHeight, ADepthZ);
    { Front face aligned at Z = -1.0m across all 5 lanes }
    B.Translation := Vector3(AX, AHeight * 0.5, -1.0 - ADepthZ * 0.5);
    B.Color := AColor;
    RootT.Add(B);
  end;

begin
  ARunner := nil;
  ATraversal := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  FloorBox := TCastleBox.Create(ADesignOwner);
  FloorBox.Name := MakeUniqueName(ADesignOwner, 'ParkourGymFloor');
  FloorBox.Size := Vector3(28.0, 0.5, 24.0);
  FloorBox.Translation := Vector3(0.0, -0.25, -4.0);
  FloorBox.Color := Vector4(0.28, 0.30, 0.34, 1.0);
  RootT.Add(FloorBox);

  AddObstacleBox('Parkour_CurbStep',   -8.0, 0.40, 1.80, Vector4(0.32, 0.78, 0.52, 1.0));
  AddObstacleBox('Parkour_VaultFence', -4.0, 1.05, 0.45, Vector4(0.28, 0.68, 0.94, 1.0));
  AddObstacleBox('Parkour_MantleBox',   0.0, 1.20, 2.60, Vector4(0.92, 0.68, 0.24, 1.0));
  AddObstacleBox('Parkour_HighLedge',  +4.0, 2.20, 2.20, Vector4(0.88, 0.44, 0.26, 1.0));
  AddObstacleBox('Parkour_SheerTower', +8.0, 3.80, 2.00, Vector4(0.72, 0.28, 0.32, 1.0));

  RunnerCyl := TCastleCylinder.Create(ADesignOwner);
  RunnerCyl.Name := MakeUniqueName(ADesignOwner, 'ParkourRunner');
  RunnerCyl.Radius := 0.32;
  RunnerCyl.Height := 1.75;
  RunnerCyl.Translation := Vector3(-4.0, 0.0, 0.0);
  RunnerCyl.Color := Vector4(0.94, 0.88, 0.36, 1.0);
  RootT.Add(RunnerCyl);
  ARunner := RunnerCyl;

  ATraversal := TCastleTraversalBehavior.Create(ADesignOwner);
  ATraversal.Name := MakeUniqueName(ADesignOwner, 'ParkourScanner');
  RunnerCyl.AddBehavior(ATraversal);

  ATraversal.ScanFromParent(RootT, Vector3(0.0, 0.0, -1.0));
  Result := True;
end;

class function TTraversalStudioHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TTraversalStudioSummary;
var
  T: TCastleTraversalBehavior;
begin
  Result := Default(TTraversalStudioSummary);
  T := FindFirstTraversal(ARoot);
  if T = nil then
  begin
    Result.LastActionName := 'None';
    Exit;
  end;

  Result.ScannerCount := 1;
  Result.LastActionName := TraversalActionToDisplayName(T.LastProbe.Action);
  Result.LastMontageId := T.LastProbe.SuggestedMontageId;
  Result.LastObstacleHeight := T.LastProbe.ObstacleHeightAboveFeet;
  Result.LastObstacleDepth := T.LastProbe.ObstacleTopDepth;

  if T.MaxStepUpHeight >= T.MaxLowMantleHeight then
  begin
    Inc(Result.WarningsCount);
    if AWarnings <> nil then
      AWarnings.Add('MaxStepUpHeight >= MaxLowMantleHeight; low mantles and vaults will be classified as step-ups.');
  end;
end;

class function TTraversalStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TTraversalStudioSummary;
  T: TCastleTraversalBehavior;
  P: TTraversalProbeResult;
  SB: TStringBuilder;
  I: Integer;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    T := FindFirstTraversal(ARoot);
    SB.AppendLine('# Castle Game Engine — Parkour Traversal & Root-Motion Warp Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Classified Action**: **%s** (`%s`)', [
      Sum.LastActionName, IfThen(Sum.LastMontageId <> '', Sum.LastMontageId, 'no montage')]));
    if T <> nil then
    begin
      P := T.LastProbe;
      SB.AppendLine(Format('- **Obstacle Geometry (`Dist` / `Height` / `Depth`)**: `%.2fm` / `%.2fm` / `%.2fm`', [
        P.ForwardDistance, P.ObstacleHeightAboveFeet, P.ObstacleTopDepth]));
      SB.AppendLine(Format('- **Front-Edge Hand-Plant Anchor**: `(%.2f, %.2f, %.2f)`', [
        P.FrontEdgeAnchorWorld.X, P.FrontEdgeAnchorWorld.Y, P.FrontEdgeAnchorWorld.Z]));
      SB.AppendLine(Format('- **Landing Root-Motion Warp Anchor**: `(%.2f, %.2f, %.2f)`', [
        P.LandingAnchorWorld.X, P.LandingAnchorWorld.Y, P.LandingAnchorWorld.Z]));
    end;
    if Warnings.Count > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('## Diagnostics');
      for I := 0 to Warnings.Count - 1 do
        SB.AppendLine('- ' + Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Warnings);
  end;
end;

end.
