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

{ Stateless helper for the Groom Strand Hair / Fur Clump Cards, Guide-Curve
  Clumping & Inertial Wind Studio (Phase 348). }
unit ToolGroomStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleGroomHair;

type
  TGroomStudioSummary = record
    GroomCount: Integer;
    TotalGuides: Integer;
    TotalStrands: Integer;
    TotalTriangles: Integer;
    WarningsCount: Integer;
  end;

  TGroomStudioHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstGroom(const ARoot: TComponent): TCastleGroomComponent; static;

    class function SpawnScalpHeadGroomDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out AHeadBust: TCastleTransform;
      out AGroom: TCastleGroomComponent): Boolean; static;

    class procedure StepAllGrooms(const ARoot: TComponent; const ADt: Single); static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TGroomStudioSummary; static;

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

class function TGroomStudioHelper.ResolveRootTransform(
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

class function TGroomStudioHelper.FindFirstGroom(
  const ARoot: TComponent): TCastleGroomComponent;

  function ScanRec(const T: TCastleTransform): TCastleGroomComponent;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleGroomComponent then
      Exit(TCastleGroomComponent(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TGroomStudioHelper.SpawnScalpHeadGroomDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out AHeadBust: TCastleTransform;
  out AGroom: TCastleGroomComponent): Boolean;
var
  RootT: TCastleTransform;
  HeadSphere: TCastleSphere;
begin
  AHeadBust := nil;
  AGroom := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  HeadSphere := TCastleSphere.Create(ADesignOwner);
  HeadSphere.Name := MakeUniqueName(ADesignOwner, 'GroomHeadBust');
  HeadSphere.Radius := 0.255;
  HeadSphere.Translation := Vector3(0.0, 1.65, 0.0);
  HeadSphere.Color := Vector4(0.84, 0.72, 0.64, 1.0);
  RootT.Add(HeadSphere);
  AHeadBust := HeadSphere;

  AGroom := TCastleGroomComponent.Create(ADesignOwner);
  AGroom.Name := MakeUniqueName(ADesignOwner, 'HeroHairGroom');
  AGroom.ApplyStylePreset(gspStylizedHeroBob);
  HeadSphere.Add(AGroom);
  Result := True;
end;

class procedure TGroomStudioHelper.StepAllGrooms(const ARoot: TComponent;
  const ADt: Single);

  procedure StepRec(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if T = nil then Exit;
    if T is TCastleGroomComponent then
      TCastleGroomComponent(T).StepGroomPhysics(ADt);
    for I := 0 to T.Count - 1 do
      StepRec(T[I]);
  end;

begin
  StepRec(ResolveRootTransform(ARoot));
end;

class function TGroomStudioHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TGroomStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    G: TCastleGroomComponent;
  begin
    if T = nil then Exit;
    if T is TCastleGroomComponent then
    begin
      G := TCastleGroomComponent(T);
      Inc(Result.GroomCount);
      Result.TotalGuides := Result.TotalGuides + G.GuideCount;
      Result.TotalStrands := Result.TotalStrands + G.TotalStrandCount;
      Result.TotalTriangles := Result.TotalTriangles + G.GeneratedTriangleCount;
      if G.GeneratedTriangleCount > 12000 then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s generates %d hair card triangles (> 12,000 mobile budget).', [
            G.Name, G.GeneratedTriangleCount]));
      end;
    end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TGroomStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TGroomStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TGroomStudioSummary;
  G: TCastleGroomComponent;
  SB: TStringBuilder;
  I: Integer;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    G := FindFirstGroom(ARoot);
    SB.AppendLine('# Castle Game Engine — Groom Strand Hair & Fur Clump Cards Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Groom Components**: `%d` (`%d` guides -> `%d` clumped strands, `%d` card triangles)', [
      Sum.GroomCount, Sum.TotalGuides, Sum.TotalStrands, Sum.TotalTriangles]));
    if G <> nil then
    begin
      SB.AppendLine(Format('- **Style Preset**: `%s` (`ClumpTightness = %.2f`, `CurlAmplitude = %.3fm`, `CurlTurns = %.1f`)', [
        GroomPresetToDisplayName(G.Preset), G.ClumpTightness, G.CurlAmplitude, G.CurlTurns]));
      SB.AppendLine(Format('- **Scalp Anti-Clip Clearance**: `minDist = %.3fm` vs. `ScalpRadius = %.3fm`', [
        G.MinDistanceFromScalpCenter, G.ScalpRadius]));
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
