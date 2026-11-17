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

{ Stateless helper for the Niagara-Style Sword-Slash / Projectile Ribbon Trail,
  Catmull-Rom UV Subdivider & Beam Arc Lightning VFX Studio (Phase 334). }
unit ToolRibbonStudio;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleColors, CastleViewport, CastleTransform, CastleScene,
  CastleRibbonTrail;

type
  TRibbonStudioSummary = record
    RibbonCount: Integer;
    LightningCount: Integer;
    TotalActiveSamples: Integer;
    TotalRibbonTriangles: Integer;
    TotalLightningTriangles: Integer;
    TotalArcLengthMeters: Single;
    WarningsCount: Integer;
  end;

  TRibbonStudioHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstRibbon(const ARoot: TComponent): TCastleRibbonTrail; static;
    class function FindFirstLightning(const ARoot: TComponent): TCastleLightningBeam; static;

    { Simulates a 3D sweeping sword-slash arc into ARibbon across ASteps samples. }
    class procedure SimulateSwordSlashArc(const ARibbon: TCastleRibbonTrail;
      const ASteps: Integer = 10; const ASweepDeg: Single = 135.0); static;

    { Spawns a Katana Sunfire Slash ribbon trail (pre-populated with a sweeping
      135-degree slash arc) and a Tesla Arc Lightning Beam striking a target
      conduit pillar. }
    class function SpawnKatanaSlashAndLightningDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ARibbon: TCastleRibbonTrail;
      out ABeam: TCastleLightningBeam;
      out ATargetPillar: TCastleTransform): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TRibbonStudioSummary; static;

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

class function TRibbonStudioHelper.ResolveRootTransform(
  const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  if ARoot is TCastleTransform then
    Exit(TCastleTransform(ARoot));
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot).Items);
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(ARoot.Components[I]).Items);
end;

class function TRibbonStudioHelper.FindFirstRibbon(
  const ARoot: TComponent): TCastleRibbonTrail;

  function ScanRec(const T: TCastleTransform): TCastleRibbonTrail;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleRibbonTrail then
      Exit(TCastleRibbonTrail(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TRibbonStudioHelper.FindFirstLightning(
  const ARoot: TComponent): TCastleLightningBeam;

  function ScanRec(const T: TCastleTransform): TCastleLightningBeam;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleLightningBeam then
      Exit(TCastleLightningBeam(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class procedure TRibbonStudioHelper.SimulateSwordSlashArc(
  const ARibbon: TCastleRibbonTrail; const ASteps: Integer;
  const ASweepDeg: Single);
var
  I, N: Integer;
  FracT, AngRad, HiltR, TipR, YWave: Single;
  Pivot, DirXZ, HiltW, TipW: TVector3;
begin
  if ARibbon = nil then
    Exit;
  ARibbon.ClearTrail;
  N := Max(3, ASteps);
  Pivot := ARibbon.WorldTranslation + Vector3(0.0, 1.15, 0.0);
  HiltR := Max(0.35, ARibbon.BladeHiltOffset + 0.45);
  TipR := HiltR + ARibbon.BladeLength;

  for I := 0 to N - 1 do
  begin
    { Age existing samples slightly before pushing next frame along the arc }
    if I > 0 then
      ARibbon.StepTrail(0.018, False);
    FracT := I / Single(N - 1);
    AngRad := DegToRad(-0.5 * ASweepDeg + FracT * ASweepDeg);
    YWave := 0.25 * Sin((FracT - 0.5) * Pi);
    DirXZ := Vector3(Sin(AngRad), YWave, -Cos(AngRad)).Normalize;
    HiltW := Pivot + DirXZ * HiltR;
    TipW := Pivot + DirXZ * TipR;
    ARibbon.RecordBladeSampleWorld(HiltW, TipW);
  end;
end;

class function TRibbonStudioHelper.SpawnKatanaSlashAndLightningDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ARibbon: TCastleRibbonTrail; out ABeam: TCastleLightningBeam;
  out ATargetPillar: TCastleTransform): Boolean;
var
  RootT: TCastleTransform;
  Pillar: TCastleCylinder;
begin
  ARibbon := nil;
  ABeam := nil;
  ATargetPillar := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  ARibbon := TCastleRibbonTrail.Create(ADesignOwner);
  ARibbon.Name := MakeUniqueName(ADesignOwner, 'KatanaSlashTrail');
  ARibbon.Translation := Vector3(-2.5, 0.0, 0.0);
  ARibbon.LifetimeSec := 0.45;
  ARibbon.CatmullSubdivisions := 3;
  ARibbon.BladeLength := 1.30;
  ARibbon.ApplyPreset(rtpKatanaSunfireSlash);
  RootT.Add(ARibbon);
  SimulateSwordSlashArc(ARibbon, 10, 135.0);

  Pillar := TCastleCylinder.Create(ADesignOwner);
  Pillar.Name := MakeUniqueName(ADesignOwner, 'ArcTargetPillar');
  Pillar.Radius := 0.35;
  Pillar.Height := 2.6;
  Pillar.Translation := Vector3(4.5, 1.3, -6.5);
  Pillar.Color := Vector4(0.35, 0.55, 0.78, 1.0);
  RootT.Add(Pillar);
  ATargetPillar := Pillar;

  ABeam := TCastleLightningBeam.Create(ADesignOwner);
  ABeam.Name := MakeUniqueName(ADesignOwner, 'TeslaArcEmitter');
  ABeam.Translation := Vector3(2.0, 2.1, 1.5);
  ABeam.TargetTransformName := Pillar.Name;
  ABeam.SubdivisionDepth := 4;
  ABeam.JitterAmplitude := 0.75;
  ABeam.BranchCount := 3;
  RootT.Add(ABeam);
  ABeam.StrikeNow(1337);

  Result := True;
end;

class function TRibbonStudioHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TRibbonStudioSummary;

  procedure ScanRec(const T: TCastleTransform);
  var
    I: Integer;
    R: TCastleRibbonTrail;
    L: TCastleLightningBeam;
  begin
    if T = nil then
      Exit;
    if T is TCastleRibbonTrail then
    begin
      R := TCastleRibbonTrail(T);
      Inc(Result.RibbonCount);
      Result.TotalActiveSamples := Result.TotalActiveSamples + R.ActiveSampleCount;
      Result.TotalRibbonTriangles := Result.TotalRibbonTriangles + R.GeneratedTriangleCount;
      Result.TotalArcLengthMeters := Result.TotalArcLengthMeters + R.TotalArcLengthMeters;
      if R.CatmullSubdivisions > 6 then
      begin
        Inc(Result.WarningsCount);
        if AWarnings <> nil then
          AWarnings.Add(Format('%s uses CatmullSubdivisions = %d (> 6); 3–4 suffices for smooth 60 Hz arcs.', [
            R.Name, R.CatmullSubdivisions]));
      end;
    end else
    if T is TCastleLightningBeam then
    begin
      L := TCastleLightningBeam(T);
      Inc(Result.LightningCount);
      Result.TotalLightningTriangles := Result.TotalLightningTriangles + L.TotalBoltTriangles;
    end;
    for I := 0 to T.Count - 1 do
      ScanRec(T[I]);
  end;

begin
  Result := Default(TRibbonStudioSummary);
  ScanRec(ResolveRootTransform(ARoot));
end;

class function TRibbonStudioHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TRibbonStudioSummary;
  SB: TStringBuilder;
  I: Integer;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    SB.AppendLine('# Castle Game Engine — Niagara Ribbon Trail & Arc Lightning VFX Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Ribbon Trails (`TCastleRibbonTrail`)**: `%d` (`%d` samples, `%d` tris, `%.2f m` arc length)', [
      Sum.RibbonCount, Sum.TotalActiveSamples, Sum.TotalRibbonTriangles, Sum.TotalArcLengthMeters]));
    SB.AppendLine(Format('- **Lightning Beams (`TCastleLightningBeam`)**: `%d` (`%d` crossed-quad tris)', [
      Sum.LightningCount, Sum.TotalLightningTriangles]));
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
