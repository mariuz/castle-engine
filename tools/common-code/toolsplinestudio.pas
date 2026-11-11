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

{ Design-time & runtime helper operations for 3D Catmull-Rom spline paths,
  ribbon/tube extrusion, arc-length fence/pillar instancing, and spline
  followers (Phase 297 — UE 6.0 USplineComponent & Landscape Splines Parity). }
unit ToolSplineStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleSplinePath;

type
  TSplinePathArray = array of TCastleSplinePath;
  TSplineFollowerArray = array of TCastleSplineFollowerBehavior;

  TSplineStudioSummary = record
    SplineCount: Integer;
    TotalControlPoints: Integer;
    TotalGeneratedTriangles: Integer;
    FollowerCount: Integer;
    GeneratedInstanceCount: Integer;
    TotalArcLengthMeters: Single;
    Splines: TSplinePathArray;
    Followers: TSplineFollowerArray;
    Warnings: array of String;
  end;

  TSplineStudioHelper = class
  public
    { Recursively scan @code(ARoot) for @link(TCastleSplinePath) and
      @link(TCastleSplineFollowerBehavior) instances and compute diagnostics. }
    class function ScanSplines(const ARoot: TComponent): TSplineStudioSummary; static;

    { Spawn a new @link(TCastleSplinePath) into the first @code(TCastleViewport.Items)
      (or @code(TCastleTransform) root) inside @code(ARoot). }
    class function CreateSplineInDesign(const ARoot, AOwner: TComponent;
      const APreset: TSplinePreset; const ASpawnPos: TVector3): TCastleSplinePath; static;

    { Attach or update a @link(TCastleSplineFollowerBehavior) on @code(ATarget). }
    class function AttachFollowerToTransform(const ATarget: TCastleTransform;
      const AOwner: TComponent; const ASplineName: String;
      const ASpeed: Single = 5.0): TCastleSplineFollowerBehavior; static;

    { Remove generated spline instances (@code(Tag = SplineGeneratedInstanceTag))
      from @code(ASpline). Returns number of removed children. }
    class function ClearGeneratedSplineInstances(
      const ASpline: TCastleSplinePath): Integer; static;

    { Populate evenly spaced child instances along @code(ASpline) at exact
      arc-length intervals @code(ASpacingMeters), with optional @code(ALateralOffset)
      (e.g. guardrail/bollard offset along @code(Sample.Right)).
      When @code(APrefabUrl) is empty, spawns @code(TCastleBox) marker posts;
      otherwise spawns @code(TCastleScene) instances referencing @code(APrefabUrl). }
    class function PopulateInstancesAlongSpline(const ASpline: TCastleSplinePath;
      const AOwner: TComponent; const APrefabUrl: String;
      const ASpacingMeters: Single; const ALateralOffset: Single = 0.0;
      const AAlignToTangent: Boolean = true): Integer; static;

    { Export a Markdown audit report of all splines, followers, and budgets. }
    class function FormatSplineStudioMarkdown(const ARoot: TComponent): String; static;
  end;

implementation

uses
  Math,
  CastleUtils, CastleUiControls, CastleViewport, CastleScene;

function UniqueComponentName(const AOwner, ARoot: TComponent;
  const ABaseName: String): String;

  function ExistsInTree(const C: TComponent; const Candidate: String): Boolean;
  var
    I: Integer;
    T: TCastleTransform;
    U: TCastleUserInterface;
  begin
    Result := false;
    if C = nil then
      Exit;
    if SameText(C.Name, Candidate) then
      Exit(true);
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        if ExistsInTree(T[I], Candidate) then
          Exit(true);
    end;
    if C is TCastleUserInterface then
    begin
      U := TCastleUserInterface(C);
      for I := 0 to U.ControlsCount - 1 do
        if ExistsInTree(U.Controls[I], Candidate) then
          Exit(true);
    end;
    for I := 0 to C.ComponentCount - 1 do
      if ExistsInTree(C.Components[I], Candidate) then
        Exit(true);
  end;

var
  Idx: Integer;
begin
  Idx := 1;
  repeat
    Result := ABaseName + IntToStr(Idx);
    Inc(Idx);
  until ((AOwner = nil) or (AOwner.FindComponent(Result) = nil)) and
        ((ARoot = nil) or (not ExistsInTree(ARoot, Result)));
end;

function FindParentTransformContainer(const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
  U: TCastleUserInterface;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleUserInterface then
  begin
    U := TCastleUserInterface(ARoot);
    for I := 0 to U.ControlsCount - 1 do
    begin
      Result := FindParentTransformContainer(U.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindParentTransformContainer(ARoot.Components[I]);
    if Result <> nil then
      Exit;
  end;
end;

{ TSplineStudioHelper -------------------------------------------------------- }

class function TSplineStudioHelper.ScanSplines(
  const ARoot: TComponent): TSplineStudioSummary;
var
  Visited: TFPList;
  OutSum: TSplineStudioSummary;

  procedure AddWarning(const Msg: String);
  begin
    SetLength(OutSum.Warnings, Length(OutSum.Warnings) + 1);
    OutSum.Warnings[High(OutSum.Warnings)] := Msg;
  end;

  function HasSplineNamed(const AName: String): Boolean;
  var
    K: Integer;
  begin
    Result := false;
    for K := 0 to High(OutSum.Splines) do
      if SameText(OutSum.Splines[K].Name, AName) then
        Exit(true);
  end;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    U: TCastleUserInterface;
    Sp: TCastleSplinePath;
    Fol: TCastleSplineFollowerBehavior;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if Visited.IndexOf(C) >= 0 then
      Exit;
    Visited.Add(C);

    if C is TCastleSplinePath then
    begin
      Sp := TCastleSplinePath(C);
      SetLength(OutSum.Splines, Length(OutSum.Splines) + 1);
      OutSum.Splines[High(OutSum.Splines)] := Sp;
      Inc(OutSum.SplineCount);
      Inc(OutSum.TotalControlPoints, Sp.ControlPointCount);
      Inc(OutSum.TotalGeneratedTriangles, Sp.GeneratedTriangleCount);
      OutSum.TotalArcLengthMeters := OutSum.TotalArcLengthMeters + Sp.TotalLength;
      if Sp.ControlPointCount < 2 then
        AddWarning(Format('Spline "%s" has fewer than 2 control points (%d).',
          [Sp.Name, Sp.ControlPointCount]));
    end;

    if C is TCastleSplineFollowerBehavior then
    begin
      Fol := TCastleSplineFollowerBehavior(C);
      SetLength(OutSum.Followers, Length(OutSum.Followers) + 1);
      OutSum.Followers[High(OutSum.Followers)] := Fol;
      Inc(OutSum.FollowerCount);
    end;

    if (C is TCastleTransform) and (C.Tag = SplineGeneratedInstanceTag) then
      Inc(OutSum.GeneratedInstanceCount);

    if C is TCastleViewport then
      Visit(TCastleViewport(C).Items);

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Visit(T[I]);
      for I := 0 to T.BehaviorsCount - 1 do
        Visit(T.Behaviors[I]);
    end;

    if C is TCastleUserInterface then
    begin
      U := TCastleUserInterface(C);
      for I := 0 to U.ControlsCount - 1 do
        Visit(U.Controls[I]);
    end;

    for I := 0 to C.ComponentCount - 1 do
      Visit(C.Components[I]);
  end;

var
  I: Integer;
  ParentName: String;
begin
  OutSum := Default(TSplineStudioSummary);
  if ARoot = nil then
    Exit(OutSum);

  Visited := TFPList.Create;
  try
    Visit(ARoot);
  finally
    FreeAndNil(Visited);
  end;

  if OutSum.TotalGeneratedTriangles > 8000 then
    AddWarning(Format('Total procedural spline mesh triangles (%d) exceed 8,000 budget hint; consider lowering SubdivisionsPerSegment.',
      [OutSum.TotalGeneratedTriangles]));

  for I := 0 to High(OutSum.Followers) do
  begin
    if OutSum.Followers[I].Parent <> nil then
      ParentName := OutSum.Followers[I].Parent.Name
    else
      ParentName := '<unattached>';
    if Trim(OutSum.Followers[I].SplineName) = '' then
      AddWarning(Format('SplineFollower on "%s" has an empty SplineName.', [ParentName]))
    else
    if not HasSplineNamed(OutSum.Followers[I].SplineName) then
      AddWarning(Format('SplineFollower on "%s" references missing spline "%s".',
        [ParentName, OutSum.Followers[I].SplineName]));
  end;
  Result := OutSum;
end;

class function TSplineStudioHelper.CreateSplineInDesign(
  const ARoot, AOwner: TComponent; const APreset: TSplinePreset;
  const ASpawnPos: TVector3): TCastleSplinePath;
var
  Container: TCastleTransform;
  BasePrefix: String;
begin
  Result := nil;
  Container := FindParentTransformContainer(ARoot);
  if Container = nil then
    Exit;

  case APreset of
    spMeanderingRiver: BasePrefix := 'RiverSpline';
    spHangingCable:    BasePrefix := 'CableSpline';
    spClosedRaceTrack: BasePrefix := 'TrackSpline';
  else
    BasePrefix := 'RoadSpline';
  end;

  Result := TCastleSplinePath.Create(AOwner);
  Result.Name := UniqueComponentName(AOwner, ARoot, BasePrefix);
  Result.Translation := ASpawnPos;
  if APreset <> spCustom then
    Result.ApplyPreset(APreset);
  Container.Add(Result);
end;

class function TSplineStudioHelper.AttachFollowerToTransform(
  const ATarget: TCastleTransform; const AOwner: TComponent;
  const ASplineName: String; const ASpeed: Single): TCastleSplineFollowerBehavior;
begin
  Result := nil;
  if ATarget = nil then
    Exit;
  Result := ATarget.FindBehavior(TCastleSplineFollowerBehavior) as TCastleSplineFollowerBehavior;
  if Result = nil then
  begin
    Result := TCastleSplineFollowerBehavior.Create(AOwner);
    Result.Name := UniqueComponentName(AOwner, ATarget, 'SplineFollower');
    ATarget.AddBehavior(Result);
  end;
  Result.SplineName := ASplineName;
  Result.SpeedMetersPerSec := ASpeed;
  Result.StepFollow(0.0, AOwner);
end;

class function TSplineStudioHelper.ClearGeneratedSplineInstances(
  const ASpline: TCastleSplinePath): Integer;
var
  I: Integer;
  Child: TCastleTransform;
begin
  Result := 0;
  if ASpline = nil then
    Exit;
  for I := ASpline.Count - 1 downto 0 do
  begin
    Child := ASpline[I];
    if (not (csTransient in Child.ComponentStyle)) and
       (Child.Tag = SplineGeneratedInstanceTag) then
    begin
      ASpline.Remove(Child);
      FreeAndNil(Child);
      Inc(Result);
    end;
  end;
end;

class function TSplineStudioHelper.PopulateInstancesAlongSpline(
  const ASpline: TCastleSplinePath; const AOwner: TComponent;
  const APrefabUrl: String; const ASpacingMeters: Single;
  const ALateralOffset: Single; const AAlignToTangent: Boolean): Integer;
var
  StepDist, TotalLen, MaxDist, D: Single;
  Sample: TSplineSample;
  Inst: TCastleTransform;
  SceneInst: TCastleScene;
  BoxInst: TCastleBox;
  Idx: Integer;
begin
  Result := 0;
  if ASpline = nil then
    Exit;

  ClearGeneratedSplineInstances(ASpline);
  StepDist := Max(0.25, ASpacingMeters);
  TotalLen := ASpline.TotalLength;
  if TotalLen <= 0.01 then
    Exit;

  if ASpline.ClosedLoop then
    MaxDist := Max(0.0, TotalLen - StepDist * 0.35)
  else
    MaxDist := TotalLen + 0.001;

  D := 0.0;
  Idx := 1;
  while D <= MaxDist do
  begin
    Sample := ASpline.EvaluateLocalAtDistance(Min(D, TotalLen));
    if Trim(APrefabUrl) <> '' then
    begin
      SceneInst := TCastleScene.Create(AOwner);
      SceneInst.Url := APrefabUrl;
      Inst := SceneInst;
    end else
    begin
      BoxInst := TCastleBox.Create(AOwner);
      BoxInst.Size := Vector3(0.28, 1.0, 0.28);
      BoxInst.Color := Vector4(0.82, 0.76, 0.64, 1.0);
      Inst := BoxInst;
    end;

    Inst.Name := UniqueComponentName(AOwner, ASpline,
      ASpline.Name + '_Post' + IntToStr(Idx) + '_');
    Inst.Tag := SplineGeneratedInstanceTag;
    Inst.Translation := Sample.Position + Sample.Right * ALateralOffset +
      Sample.Up * 0.5;
    if AAlignToTangent then
      Inst.SetView(Sample.Tangent, Sample.Up);

    ASpline.Add(Inst);
    Inc(Result);
    Inc(Idx);
    D := D + StepDist;
    if Result >= 512 then
      Break;
  end;
end;

class function TSplineStudioHelper.FormatSplineStudioMarkdown(
  const ARoot: TComponent): String;
var
  Sum: TSplineStudioSummary;
  SB: TStringBuilder;
  I: Integer;
  Sp: TCastleSplinePath;
begin
  Sum := ScanSplines(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Spline Path & Extrusion Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Spline Paths**: %d', [Sum.SplineCount]));
    SB.AppendLine(Format('- **Total Control Knots**: %d', [Sum.TotalControlPoints]));
    SB.AppendLine(Format('- **Total Arc Length**: %.2f m', [Sum.TotalArcLengthMeters]));
    SB.AppendLine(Format('- **Generated Ribbon/Tube Triangles**: %d', [Sum.TotalGeneratedTriangles]));
    SB.AppendLine(Format('- **Spline Followers**: %d', [Sum.FollowerCount]));
    SB.AppendLine(Format('- **Instanced Posts/Props**: %d', [Sum.GeneratedInstanceCount]));
    SB.AppendLine;
    SB.AppendLine('| Spline Name | Mode | Closed | Knots | Arc Length (m) | Width (m) | Triangles |');
    SB.AppendLine('| :--- | :--- | :---: | :---: | :---: | :---: | :---: |');
    for I := 0 to High(Sum.Splines) do
    begin
      Sp := Sum.Splines[I];
      SB.AppendLine(Format('| `%s` | %s | %s | %d | %.2f | %.2f | %d |', [
        Sp.Name,
        SplineMeshModeToString(Sp.MeshMode),
        BoolToStr(Sp.ClosedLoop, 'Yes', 'No'),
        Sp.ControlPointCount,
        Sp.TotalLength,
        Sp.RibbonWidth,
        Sp.GeneratedTriangleCount
      ]));
    end;
    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine;
      SB.AppendLine('## Diagnostics & Warnings');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- ' + Sum.Warnings[I]);
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
