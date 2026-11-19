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

{ Design-time helper for the Ballistic Trajectory, Drag, Magnus Wind Drift &
  Ricochet/Penetration Studio (Phase 387). }
unit ToolBallisticStudio;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleBoxes, CastleColors,
  CastleBallisticSolver;

type
  TBallisticStudioHelper = class
  public
    class function FindFirstLauncher(const ARoot: TComponent): TCastleBallisticLauncher;
    class function SpawnFiringRangeDemo(const ARoot: TComponent;
      const AOwner: TComponent;
      out ALauncher: TCastleBallisticLauncher): Boolean;
    class function FireGrazingRicochetTest(
      const ALauncher: TCastleBallisticLauncher;
      const ARoot: TComponent): TBallisticTraceResult;
    class function FireThinCoverPenetrationTest(
      const ALauncher: TCastleBallisticLauncher;
      const ARoot: TComponent): TBallisticTraceResult;
    class function ExportLauncherJson(const ALauncher: TCastleBallisticLauncher): String;
    class function ImportLauncherJson(const ALauncher: TCastleBallisticLauncher;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(
      const ALauncher: TCastleBallisticLauncher): String;
  end;

implementation

uses
  CastleUtils;

function FindViewportInTree(const ARoot: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleViewport then
    Exit(TCastleViewport(ARoot));
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindViewportInTree(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TBallisticStudioHelper.FindFirstLauncher(
  const ARoot: TComponent): TCastleBallisticLauncher;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleBallisticLauncher;
  var
    J: Integer;
  begin
    if T is TCastleBallisticLauncher then
      Exit(TCastleBallisticLauncher(T));
    for J := 0 to T.Count - 1 do
    begin
      Result := SearchTransform(T[J]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleBallisticLauncher then
    Exit(TCastleBallisticLauncher(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleBallisticLauncher then
      Exit(TCastleBallisticLauncher(ARoot.Components[I]));
end;

class function TBallisticStudioHelper.SpawnFiringRangeDemo(
  const ARoot: TComponent; const AOwner: TComponent;
  out ALauncher: TCastleBallisticLauncher): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  RangePlate, PlywoodCover, BackstopBunker: TCastleBox;
begin
  Result := False;
  ALauncher := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  { Angled steel ricochet floor slab at Y = 0 }
  RangePlate := TCastleBox.Create(Own);
  RangePlate.Name := 'SteelRicochetFloor';
  RangePlate.Size := Vector3(16.0, 0.5, 48.0);
  RangePlate.Translation := Vector3(0.0, -0.25, -20.0);
  RangePlate.Color := Vector4(0.32, 0.35, 0.40, 1.0);
  VP.Items.Add(RangePlate);

  { Thin 0.18m plywood/plaster barricade at Z = -10m }
  PlywoodCover := TCastleBox.Create(Own);
  PlywoodCover.Name := 'ThinPlywoodBarricade';
  PlywoodCover.Size := Vector3(4.0, 2.4, 0.18);
  PlywoodCover.Translation := Vector3(0.0, 1.2, -10.0);
  PlywoodCover.Color := Vector4(0.68, 0.50, 0.28, 1.0);
  VP.Items.Add(PlywoodCover);

  { Thick 2.2m reinforced concrete bunker backstop at Z = -24m }
  BackstopBunker := TCastleBox.Create(Own);
  BackstopBunker.Name := 'ConcreteBackstopWall';
  BackstopBunker.Size := Vector3(6.0, 3.2, 2.2);
  BackstopBunker.Translation := Vector3(0.0, 1.6, -24.0);
  BackstopBunker.Color := Vector4(0.45, 0.46, 0.48, 1.0);
  VP.Items.Add(BackstopBunker);

  ALauncher := TCastleBallisticLauncher.Create(Own);
  ALauncher.Name := 'BallisticRifleBench';
  ALauncher.Translation := Vector3(0.0, 1.45, 0.0);
  ALauncher.ApplyPreset(blpSniper762Supersonic);
  ALauncher.WindVelocityMps := Vector3(6.5, 0.0, 0.0);
  VP.Items.Add(ALauncher);

  ALauncher.SimulateFromTransform(VP.Items);
  Result := True;
end;

class function TBallisticStudioHelper.FireGrazingRicochetTest(
  const ALauncher: TCastleBallisticLauncher;
  const ARoot: TComponent): TBallisticTraceResult;
var
  VP: TCastleViewport;
  PitchRad: Single;
  Dir: TVector3;
begin
  Result := Default(TBallisticTraceResult);
  if ALauncher = nil then Exit;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  PitchRad := DegToRad(-10.0);
  Dir := Vector3(0.0, Sin(PitchRad), -Cos(PitchRad)).Normalize;
  Result := ALauncher.SimulateTrajectory(
    VP.Items, Vector3(0.0, 1.45, -11.0), Dir);
  ALauncher.RebuildPreview;
end;

class function TBallisticStudioHelper.FireThinCoverPenetrationTest(
  const ALauncher: TCastleBallisticLauncher;
  const ARoot: TComponent): TBallisticTraceResult;
var
  VP: TCastleViewport;
begin
  Result := Default(TBallisticTraceResult);
  if ALauncher = nil then Exit;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  Result := ALauncher.SimulateTrajectory(
    VP.Items, Vector3(0.0, 1.45, 0.0), Vector3(0.0, 0.0, -1.0));
  ALauncher.RebuildPreview;
end;

class function TBallisticStudioHelper.ExportLauncherJson(
  const ALauncher: TCastleBallisticLauncher): String;
var
  Obj: TJSONObject;
begin
  if ALauncher = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(ALauncher.Preset));
    Obj.Add('muzzleSpeedMps', ALauncher.MuzzleSpeedMps);
    Obj.Add('projectileMassKg', ALauncher.ProjectileMassKg);
    Obj.Add('dragCoefficient', ALauncher.DragCoefficient);
    Obj.Add('crossSectionAreaM2', ALauncher.CrossSectionAreaM2);
    Obj.Add('spinRateRps', ALauncher.SpinRateRps);
    Obj.Add('ricochetMaxGrazingDeg', ALauncher.RicochetMaxGrazingDeg);
    Obj.Add('penetrationBallisticLimitMps', ALauncher.PenetrationBallisticLimitMps);
    Obj.Add('maxPenetrationThicknessMeters', ALauncher.MaxPenetrationThicknessMeters);
    Obj.Add('windX', ALauncher.WindVelocityMps.X);
    Obj.Add('windY', ALauncher.WindVelocityMps.Y);
    Obj.Add('windZ', ALauncher.WindVelocityMps.Z);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TBallisticStudioHelper.ImportLauncherJson(
  const ALauncher: TCastleBallisticLauncher; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (ALauncher = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(ALauncher.Preset));
    if (POrd >= Ord(Low(TBallisticPreset))) and (POrd <= Ord(High(TBallisticPreset))) then
      ALauncher.Preset := TBallisticPreset(POrd);
    ALauncher.MuzzleSpeedMps := Obj.Get('muzzleSpeedMps', ALauncher.MuzzleSpeedMps);
    ALauncher.ProjectileMassKg := Obj.Get('projectileMassKg', ALauncher.ProjectileMassKg);
    ALauncher.DragCoefficient := Obj.Get('dragCoefficient', ALauncher.DragCoefficient);
    ALauncher.CrossSectionAreaM2 := Obj.Get('crossSectionAreaM2', ALauncher.CrossSectionAreaM2);
    ALauncher.SpinRateRps := Obj.Get('spinRateRps', ALauncher.SpinRateRps);
    ALauncher.RicochetMaxGrazingDeg := Obj.Get('ricochetMaxGrazingDeg', ALauncher.RicochetMaxGrazingDeg);
    ALauncher.PenetrationBallisticLimitMps := Obj.Get('penetrationBallisticLimitMps', ALauncher.PenetrationBallisticLimitMps);
    ALauncher.MaxPenetrationThicknessMeters := Obj.Get('maxPenetrationThicknessMeters', ALauncher.MaxPenetrationThicknessMeters);
    ALauncher.WindVelocityMps := Vector3(
      Obj.Get('windX', ALauncher.WindVelocityMps.X),
      Obj.Get('windY', ALauncher.WindVelocityMps.Y),
      Obj.Get('windZ', ALauncher.WindVelocityMps.Z));
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TBallisticStudioHelper.GenerateMarkdownReport(
  const ALauncher: TCastleBallisticLauncher): String;
var
  SL: TStringList;
  T: TBallisticTraceResult;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Ballistic Trajectory & Terminal Ricochet/Penetration Report');
    SL.Add('');
    if ALauncher = nil then
    begin
      SL.Add('_No `TCastleBallisticLauncher` found in the active design._');
      Exit(SL.Text);
    end;
    T := ALauncher.LastTrace;
    SL.Add('- **Launcher Name**: `' + ALauncher.Name + '`');
    SL.Add('- **Preset**: `' + BallisticPresetToString(ALauncher.Preset) + '`');
    SL.Add(FormatDot('- **Muzzle Speed / Mass**: `%.1f m/s` / `%.4f kg`',
      [ALauncher.MuzzleSpeedMps, ALauncher.ProjectileMassKg]));
    SL.Add(FormatDot('- **Crosswind Vector**: `(%.1f, %.1f, %.1f) m/s`',
      [ALauncher.WindVelocityMps.X, ALauncher.WindVelocityMps.Y, ALauncher.WindVelocityMps.Z]));
    SL.Add(FormatDot('- **Sampled Arc**: `%d` pts, Range `%.2f m`, Apex `%.2f m`, Drift `%.3f m`',
      [T.SampleCount, T.HorizontalRangeMeters, T.MaxApexY, T.LateralWindSpinDriftMeters]));
    SL.Add(FormatDot('- **Terminal Summary**: Outcome `%s`, Ricochets `%d`, Penetrations `%d`, Terminal `%.1f m/s`',
      [BallisticOutcomeToString(T.FinalOutcome), T.RicochetCount, T.PenetrationCount, T.TerminalSpeedMps]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
