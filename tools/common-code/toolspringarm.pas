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

{ Stateless helper for the Spring-Arm Camera Collision Whisker Probe,
  Instant Pull-In & Smooth Lagged Boom Recovery Studio (Phase 339). }
unit ToolSpringArm;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene, X3DNodes,
  CastleSpringArm;

type
  TSpringArmStudioSummary = record
    SpringArmCount: Integer;
    OccludedCount: Integer;
    MeanCompressionPercent: Single;
    WarningsCount: Integer;
  end;

  TSpringArmHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstSpringArm(const ARoot: TComponent): TCastleSpringArm; static;

    { Creates a double-sided PreciseCollisions vertical wall mesh at APosition
      for deterministic WorldRay whisker testing in both editor & headless tests. }
    class function CreateColliderWallScene(const AOwner: TComponent;
      const AName: String; const AHalfWidthX, AHeightY: Single;
      const APosition: TVector3): TCastleScene; static;

    class function SpawnThirdPersonSpringArmCorridorDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out AHero, AWallObstacle: TCastleTransform;
      out ASpringArm: TCastleSpringArm): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TSpringArmStudioSummary; static;

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

class function TSpringArmHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function TSpringArmHelper.FindFirstSpringArm(
  const ARoot: TComponent): TCastleSpringArm;

  function ScanRec(const T: TCastleTransform): TCastleSpringArm;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleSpringArm then
      Exit(TCastleSpringArm(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TSpringArmHelper.CreateColliderWallScene(
  const AOwner: TComponent; const AName: String;
  const AHalfWidthX, AHeightY: Single; const APosition: TVector3): TCastleScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TPhysicalMaterialNode;
  TriSet: TTriangleSetNode;
  Coord: TCoordinateNode;
  Pts: TVector3List;
begin
  Result := TCastleScene.Create(AOwner);
  Result.Name := MakeUniqueName(AOwner, AName);
  Result.PreciseCollisions := True;
  Result.Translation := APosition;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TPhysicalMaterialNode.Create;
  Mat.BaseColor := Vector3(0.55, 0.50, 0.46);
  Mat.Roughness := 0.85;
  App.Material := Mat;
  Shape.Appearance := App;

  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  Coord := TCoordinateNode.Create;
  Pts := TVector3List.Create;
  try
    Pts.Add(Vector3(-AHalfWidthX, 0.0, 0.0));
    Pts.Add(Vector3(+AHalfWidthX, 0.0, 0.0));
    Pts.Add(Vector3(+AHalfWidthX, AHeightY, 0.0));

    Pts.Add(Vector3(-AHalfWidthX, 0.0, 0.0));
    Pts.Add(Vector3(+AHalfWidthX, AHeightY, 0.0));
    Pts.Add(Vector3(-AHalfWidthX, AHeightY, 0.0));
    Coord.SetPoint(Pts);
  finally
    FreeAndNil(Pts);
  end;
  TriSet.Coord := Coord;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);
  Result.Load(Root, True);
end;

class function TSpringArmHelper.SpawnThirdPersonSpringArmCorridorDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out AHero, AWallObstacle: TCastleTransform;
  out ASpringArm: TCastleSpringArm): Boolean;
var
  RootT: TCastleTransform;
  HeroCyl: TCastleCylinder;
  WallSc: TCastleScene;
begin
  AHero := nil;
  AWallObstacle := nil;
  ASpringArm := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  HeroCyl := TCastleCylinder.Create(ADesignOwner);
  HeroCyl.Name := MakeUniqueName(ADesignOwner, 'SpringArmHero');
  HeroCyl.Radius := 0.40;
  HeroCyl.Height := 1.80;
  HeroCyl.Translation := Vector3(0.0, 0.0, 0.0);
  HeroCyl.Color := Vector4(0.30, 0.76, 0.92, 1.0);
  RootT.Add(HeroCyl);
  AHero := HeroCyl;

  { Start wall clear at Z = 12.0m so initial boom is unblocked (4.50m) }
  WallSc := CreateColliderWallScene(ADesignOwner, 'SpringArmCorridorWall',
    3.5, 4.0, Vector3(0.0, 0.0, 12.0));
  RootT.Add(WallSc);
  AWallObstacle := WallSc;

  ASpringArm := TCastleSpringArm.Create(ADesignOwner);
  ASpringArm.Name := MakeUniqueName(ADesignOwner, 'ThirdPersonSpringArm');
  ASpringArm.FollowTargetName := HeroCyl.Name;
  ASpringArm.TargetArmLength := 4.50;
  ASpringArm.ProbeRadius := 0.25;
  ASpringArm.SocketOffsetY := 1.55;
  ASpringArm.PitchDeg := 0.0;
  ASpringArm.YawDeg := 0.0;
  RootT.Add(ASpringArm);
  ASpringArm.SnapToTargetImmediately;
  ASpringArm.StepSpringArm(0.0, RootT.World);
  Result := True;
end;

class function TSpringArmHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TSpringArmStudioSummary;
var
  SumComp: Single;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    SA: TCastleSpringArm;
  begin
    if T = nil then Exit;
    if T is TCastleSpringArm then
    begin
      SA := TCastleSpringArm(T);
      Inc(Result.SpringArmCount);
      if SA.IsOccluded then
        Inc(Result.OccludedCount);
      SumComp := SumComp + SA.CompressionRatio * 100.0;
      if SA.FollowTargetName = '' then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s has empty FollowTargetName.', [SA.Name]));
      end;
    end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TSpringArmStudioSummary);
  SumComp := 0.0;
  ScanRec(ResolveRootTransform(ARoot));
  if Result.SpringArmCount > 0 then
    Result.MeanCompressionPercent := SumComp / Result.SpringArmCount;
end;

class function TSpringArmHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TSpringArmStudioSummary;
  SA: TCastleSpringArm;
  SB: TStringBuilder;
  I: Integer;
  W: TSpringArmWhiskerRay;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    SA := FindFirstSpringArm(ARoot);
    SB.AppendLine('# Castle Game Engine — Spring-Arm Camera Whisker & Occlusion Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Spring-Arm Booms (`TCastleSpringArm`)**: `%d` (`%d` occluded, `%.1f%%` compression)', [
      Sum.SpringArmCount, Sum.OccludedCount, Sum.MeanCompressionPercent]));
    if SA <> nil then
    begin
      SB.AppendLine(Format('- **Current / Target Arm Length**: `%.2f m / %.2f m` (`%d / 5` whiskers hit)', [
        SA.CurrentArmLength, SA.TargetArmLength, SA.BlockedWhiskerCount]));
      SB.AppendLine(Format('- **Solved Camera World Position**: `(%.2f, %.2f, %.2f)`', [
        SA.SolvedCameraWorldPos.X, SA.SolvedCameraWorldPos.Y, SA.SolvedCameraWorldPos.Z]));
      SB.AppendLine;
      SB.AppendLine('| Whisker Ray | Blocked | Distance `(m)` |');
      SB.AppendLine('| :--- | :--- | ---: |');
      for I := 0 to 4 do
      begin
        W := SA.GetWhisker(I);
        SB.AppendLine(Format('| Whisker #%d | %s | %.2f |', [
          I, BoolToStr(W.Blocked, 'HIT', 'Clear'), W.HitDistance]));
      end;
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
