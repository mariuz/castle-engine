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

{ Design-time & runtime helper operations for projected surface decals &
  weathering stamps (Phase 298 — UE 6.0 UDecalComponent & Mesh Decals Parity). }
unit ToolDecalStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleDecalProjector;

type
  TDecalProjectorArray = array of TCastleDecalProjector;

  TDecalStudioSummary = record
    DecalCount: Integer;
    TotalProjectedTriangles: Integer;
    EmptyProjectionCount: Integer;
    Decals: TDecalProjectorArray;
    Warnings: array of String;
  end;

  TDecalStudioHelper = class
  public
    { Scan @code(ARoot) for all @link(TCastleDecalProjector) instances, sorted
      by @code(SortOrder) ascending, with triangle & alignment diagnostics. }
    class function ScanDecals(const ARoot: TComponent): TDecalStudioSummary; static;

    { Spawn a new @link(TCastleDecalProjector) at @code(ASpawnPos), orienting its
      local @code(+Y) anti-projection axis to @code(ASurfaceNormal) so local
      @code(-Y) projects perpendicularly into the surface, and conform its mesh. }
    class function CreateDecalInDesign(const ARoot, AOwner: TComponent;
      const APreset: TDecalPreset; const ASpawnPos, ASurfaceNormal: TVector3): TCastleDecalProjector; static;

    { Cast a 3D ray against @code(AWorld); on hit, spawn and align a new
      @link(TCastleDecalProjector) at the exact surface hit point and conform it. }
    class function StampDecalAlongRay(const ARoot, AOwner: TComponent;
      const AWorld: TCastleAbstractRootTransform;
      const ARayOrigin, ARayDir: TVector3;
      const APreset: TDecalPreset): TCastleDecalProjector; static;

    { Re-run @code(ConformAndRebuildMesh) across all decals in @code(ARoot).
      Returns total generated conformal triangles. }
    class function ConformAllDecalsInHierarchy(const ARoot: TComponent): Integer; static;

    { Generate a Markdown summary & diagnostics report for all decals in @code(ARoot). }
    class function FormatDecalStudioMarkdown(const ARoot: TComponent): String; static;
  end;

implementation

uses
  Math,
  CastleUtils, CastleUriUtils, CastleUiControls, CastleViewport;

function UniqueDecalName(const AOwner, ARoot: TComponent;
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

function FindTransformRoot(const ARoot: TComponent): TCastleTransform;
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
      Result := FindTransformRoot(U.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindTransformRoot(ARoot.Components[I]);
    if Result <> nil then
      Exit;
  end;
end;

procedure AlignDecalLocalYToNormal(const ADecal: TCastleDecalProjector;
  const AWorldNormal: TVector3);
var
  Norm, RefFwd, RightVec, TangentFwd: TVector3;
begin
  if ADecal = nil then
    Exit;
  if AWorldNormal.LengthSqr < 1e-8 then
    Norm := Vector3(0.0, 1.0, 0.0)
  else
    Norm := AWorldNormal.Normalize;

  RefFwd := Vector3(0.0, 0.0, -1.0);
  if Abs(TVector3.DotProduct(Norm, RefFwd)) > 0.96 then
    RefFwd := Vector3(1.0, 0.0, 0.0);

  RightVec := TVector3.CrossProduct(RefFwd, Norm).Normalize;
  TangentFwd := TVector3.CrossProduct(Norm, RightVec).Normalize;
  ADecal.SetView(TangentFwd, Norm);
end;

{ TDecalStudioHelper --------------------------------------------------------- }

class function TDecalStudioHelper.ScanDecals(
  const ARoot: TComponent): TDecalStudioSummary;
var
  Visited: TFPList;
  OutSum: TDecalStudioSummary;

  procedure AddWarning(const Msg: String);
  begin
    SetLength(OutSum.Warnings, Length(OutSum.Warnings) + 1);
    OutSum.Warnings[High(OutSum.Warnings)] := Msg;
  end;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    U: TCastleUserInterface;
    D: TCastleDecalProjector;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if Visited.IndexOf(C) >= 0 then
      Exit;
    Visited.Add(C);

    if C is TCastleDecalProjector then
    begin
      D := TCastleDecalProjector(C);
      SetLength(OutSum.Decals, Length(OutSum.Decals) + 1);
      OutSum.Decals[High(OutSum.Decals)] := D;
      Inc(OutSum.DecalCount);
      Inc(OutSum.TotalProjectedTriangles, D.ProjectedTriangleCount);
      if D.ProjectToWorldGeometry and (D.ProjectedTriangleCount = 0) then
      begin
        Inc(OutSum.EmptyProjectionCount);
        AddWarning(Format(
          'Decal "%s" projected 0 triangles — move closer to a receiving surface or increase BoxExtents.Y (%.2fm).',
          [D.Name, D.BoxExtents.Y]));
      end;
      if (Trim(D.TextureUrl) <> '') and (not URIFileExists(D.TextureUrl)) then
        AddWarning(Format('Decal "%s" references missing TextureUrl "%s".',
          [D.Name, D.TextureUrl]));
    end;

    if C is TCastleViewport then
      Visit(TCastleViewport(C).Items);

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Visit(T[I]);
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
  I, J: Integer;
  Tmp: TCastleDecalProjector;
begin
  OutSum := Default(TDecalStudioSummary);
  if ARoot = nil then
    Exit(OutSum);

  Visited := TFPList.Create;
  try
    Visit(ARoot);
  finally
    FreeAndNil(Visited);
  end;

  { Sort by SortOrder ascending }
  for I := 0 to High(OutSum.Decals) - 1 do
    for J := I + 1 to High(OutSum.Decals) do
      if OutSum.Decals[J].SortOrder < OutSum.Decals[I].SortOrder then
      begin
        Tmp := OutSum.Decals[I];
        OutSum.Decals[I] := OutSum.Decals[J];
        OutSum.Decals[J] := Tmp;
      end;

  Result := OutSum;
end;

class function TDecalStudioHelper.CreateDecalInDesign(
  const ARoot, AOwner: TComponent; const APreset: TDecalPreset;
  const ASpawnPos, ASurfaceNormal: TVector3): TCastleDecalProjector;
var
  Container: TCastleTransform;
  Prefix: String;
begin
  Result := nil;
  Container := FindTransformRoot(ARoot);
  if Container = nil then
    Exit;

  case APreset of
    dpScorchMark:   Prefix := 'DecalScorch';
    dpBulletImpact: Prefix := 'DecalImpact';
    dpMossGrowth:   Prefix := 'DecalMoss';
    dpHazardStripe: Prefix := 'DecalHazard';
    dpMagicRune:    Prefix := 'DecalRune';
  else
    Prefix := 'DecalPuddle';
  end;

  Result := TCastleDecalProjector.Create(AOwner);
  Result.Name := UniqueDecalName(AOwner, ARoot, Prefix);
  Result.ApplyPreset(APreset);
  Result.Translation := ASpawnPos;
  AlignDecalLocalYToNormal(Result, ASurfaceNormal);
  Container.Add(Result);
  Result.ConformAndRebuildMesh;
end;

class function TDecalStudioHelper.StampDecalAlongRay(
  const ARoot, AOwner: TComponent;
  const AWorld: TCastleAbstractRootTransform;
  const ARayOrigin, ARayDir: TVector3;
  const APreset: TDecalPreset): TCastleDecalProjector;
var
  DirNorm, HitPos, HitNormal: TVector3;
  RayHit: TRayCollision;
begin
  Result := nil;
  if (AWorld = nil) or (ARayDir.LengthSqr < 1e-8) then
    Exit;

  DirNorm := ARayDir.Normalize;
  RayHit := AWorld.WorldRay(ARayOrigin, DirNorm);
  if RayHit = nil then
    Exit;
  try
    if RayHit.Transform = nil then
      Exit;
    HitPos := ARayOrigin + DirNorm * RayHit.Distance;
    if (RayHit.Count > 0) and (RayHit.First.Triangle <> nil) and
       (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
      HitNormal := RayHit.First.Item.LocalToWorldDirection(
        RayHit.First.Triangle^.SceneSpace.Normal)
    else
      HitNormal := -DirNorm;
    if HitNormal.LengthSqr < 1e-8 then
      HitNormal := Vector3(0.0, 1.0, 0.0)
    else
      HitNormal := HitNormal.Normalize;
    { Flip normal toward incoming ray if backfacing }
    if TVector3.DotProduct(HitNormal, -DirNorm) < 0.0 then
      HitNormal := -HitNormal;
  finally
    FreeAndNil(RayHit);
  end;

  Result := CreateDecalInDesign(ARoot, AOwner, APreset, HitPos, HitNormal);
end;

class function TDecalStudioHelper.ConformAllDecalsInHierarchy(
  const ARoot: TComponent): Integer;
var
  Sum: TDecalStudioSummary;
  I: Integer;
begin
  Result := 0;
  Sum := ScanDecals(ARoot);
  for I := 0 to High(Sum.Decals) do
    Inc(Result, Sum.Decals[I].ConformAndRebuildMesh);
end;

class function TDecalStudioHelper.FormatDecalStudioMarkdown(
  const ARoot: TComponent): String;
var
  Sum: TDecalStudioSummary;
  SB: TStringBuilder;
  I: Integer;
  D: TCastleDecalProjector;
begin
  Sum := ScanDecals(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Surface Decal & Weathering Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Decal Projectors**: %d', [Sum.DecalCount]));
    SB.AppendLine(Format('- **Total Conformal Triangles**: %d', [Sum.TotalProjectedTriangles]));
    SB.AppendLine(Format('- **Unmatched / Empty Projectors**: %d', [Sum.EmptyProjectionCount]));
    SB.AppendLine;
    SB.AppendLine('| Decal Name | Preset | Blend | SortOrder | Extents (m) | Cutoff (°) | Triangles |');
    SB.AppendLine('| :--- | :--- | :--- | :---: | :---: | :---: | :---: |');
    for I := 0 to High(Sum.Decals) do
    begin
      D := Sum.Decals[I];
      SB.AppendLine(Format('| `%s` | %s | %s | %d | %.2fx%.2fx%.2f | %.0f° | %d |', [
        D.Name,
        DecalPresetToString(D.Preset),
        DecalBlendStyleToString(D.BlendStyle),
        D.SortOrder,
        D.BoxExtents.X, D.BoxExtents.Y, D.BoxExtents.Z,
        D.NormalAngleCutoffDeg,
        D.ProjectedTriangleCount
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
