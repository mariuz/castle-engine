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

{ Stateless helper for the Ambient Soundscape Biome Director, Elevation /
  Time-of-Day One-Shot Scatter & Acoustic Occlusion Studio (Phase 345). }
unit ToolSoundscape;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils,
  CastleVectors, CastleViewport, CastleTransform, CastleScene,
  CastleSoundscape;

type
  TSoundscapeStudioSummary = record
    DirectorCount: Integer;
    ActiveCalls: Integer;
    OccludedCalls: Integer;
    TotalSpawned: Integer;
    DominantLayerName: String;
    WarningsCount: Integer;
  end;

  TSoundscapeHelper = class
  public
    class function ResolveRootTransform(const ARoot: TComponent): TCastleTransform; static;
    class function FindFirstDirector(const ARoot: TComponent): TCastleSoundscapeDirector; static;

    { Spawn a forest/bunker acoustic testbed with an occluding stone shelter wall
      at Z = -6m and scatter 8 spatialized ambient biome calls around listener (0, 1.7, 0). }
    class function SpawnAcousticBiomeSoundscapeDemo(const ARoot: TComponent;
      const ADesignOwner: TComponent;
      out ADirector: TCastleSoundscapeDirector): Boolean; static;

    class function CollectSummary(const ARoot: TComponent;
      const AWarnings: TStrings): TSoundscapeStudioSummary; static;

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

class function TSoundscapeHelper.ResolveRootTransform(
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

class function TSoundscapeHelper.FindFirstDirector(
  const ARoot: TComponent): TCastleSoundscapeDirector;

  function ScanRec(const T: TCastleTransform): TCastleSoundscapeDirector;
  var
    I: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if T is TCastleSoundscapeDirector then
      Exit(TCastleSoundscapeDirector(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := ScanRec(T[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := ScanRec(ResolveRootTransform(ARoot));
end;

class function TSoundscapeHelper.SpawnAcousticBiomeSoundscapeDemo(
  const ARoot: TComponent; const ADesignOwner: TComponent;
  out ADirector: TCastleSoundscapeDirector): Boolean;
var
  RootT: TCastleTransform;
  StoneWall: TCastleBox;
  ListenerMarker: TCastleSphere;
  I: Integer;
begin
  ADirector := nil;
  RootT := ResolveRootTransform(ARoot);
  if RootT = nil then
    Exit(False);

  { Acoustic stone barrier wall blocking North (-Z) line of sight }
  StoneWall := TCastleBox.Create(ADesignOwner);
  StoneWall.Name := MakeUniqueName(ADesignOwner, 'AcousticBunkerWall');
  StoneWall.Size := Vector3(16.0, 7.0, 1.2);
  StoneWall.Translation := Vector3(0.0, 3.5, -5.5);
  StoneWall.Color := Vector4(0.46, 0.48, 0.54, 1.0);
  RootT.Add(StoneWall);

  ListenerMarker := TCastleSphere.Create(ADesignOwner);
  ListenerMarker.Name := MakeUniqueName(ADesignOwner, 'SoundscapeListenerHead');
  ListenerMarker.Radius := 0.32;
  ListenerMarker.Translation := Vector3(0.0, 1.7, 0.0);
  ListenerMarker.Pickable := False;
  ListenerMarker.Exists := False;
  RootT.Add(ListenerMarker);

  ADirector := TCastleSoundscapeDirector.Create(ADesignOwner);
  ADirector.Name := MakeUniqueName(ADesignOwner, 'BiomeSoundscapeDirector');
  ADirector.HourOfDay := 7.0;
  ADirector.ListenerAltitudeY := 4.0;
  ADirector.IndoorEnclosureRatio := 0.0;
  RootT.Add(ADirector);

  for I := 1 to 8 do
    ADirector.SpawnScatterCall(RootT, Vector3(0.0, 1.7, 0.0));

  Result := True;
end;

class function TSoundscapeHelper.CollectSummary(const ARoot: TComponent;
  const AWarnings: TStrings): TSoundscapeStudioSummary;
var
  D: TCastleSoundscapeDirector;
begin
  Result := Default(TSoundscapeStudioSummary);
  D := FindFirstDirector(ARoot);
  if D = nil then
  begin
    Result.DominantLayerName := 'None';
    Exit;
  end;

  Result.DirectorCount := 1;
  Result.ActiveCalls := D.ActiveCallCount;
  Result.OccludedCalls := D.OccludedCallCount;
  Result.TotalSpawned := D.TotalSpawnedCalls;
  Result.DominantLayerName := SoundscapeLayerToDisplayName(D.DominantBiomeLayer);

  if D.SpawnRadiusMin >= D.SpawnRadiusMax then
  begin
    Inc(Result.WarningsCount);
    if AWarnings <> nil then
      AWarnings.Add('SpawnRadiusMin >= SpawnRadiusMax; hemisphere scatter shell has zero thickness.');
  end;
end;

class function TSoundscapeHelper.BuildMarkdownReport(
  const ARoot: TComponent): String;
var
  Warnings: TStringList;
  Sum: TSoundscapeStudioSummary;
  D: TCastleSoundscapeDirector;
  SB: TStringBuilder;
  I: Integer;
  C: TSoundscapeActiveCall;
begin
  Warnings := TStringList.Create;
  SB := TStringBuilder.Create;
  try
    Sum := CollectSummary(ARoot, Warnings);
    D := FindFirstDirector(ARoot);
    SB.AppendLine('# Castle Game Engine — Ambient Soundscape Biome & Acoustic Occlusion Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Dominant Biome Palette**: `%s`', [Sum.DominantLayerName]));
    SB.AppendLine(Format('- **Active 3D Calls / Wall-Occluded / Total Spawned**: `%d / %d / %d`', [
      Sum.ActiveCalls, Sum.OccludedCalls, Sum.TotalSpawned]));
    if D <> nil then
    begin
      SB.AppendLine(Format('- **Context (`Hour` / `Altitude` / `Enclosure`)**: `%.1fh` / `%.1fm` / `%.2f`', [
        D.HourOfDay, D.ListenerAltitudeY, D.IndoorEnclosureRatio]));
      if D.ActiveCallCount > 0 then
      begin
        SB.AppendLine;
        SB.AppendLine('| Clip ID | Layer | World Pos `(m)` | Gain | LPF `(Hz)` | LOS |');
        SB.AppendLine('| :--- | :--- | :--- | ---: | ---: | :---: |');
        for I := 0 to D.CallPoolCapacity - 1 do
        begin
          C := D.GetActiveCall(I);
          if C.Active then
            SB.AppendLine(Format('| `%s` | %s | `(%.1f, %.1f, %.1f)` | `%.2f` | `%.0f` | %s |', [
              C.ClipId, SoundscapeLayerToDisplayName(C.LayerKind),
              C.WorldPos.X, C.WorldPos.Y, C.WorldPos.Z,
              C.EffectiveGain, C.LowPassCutoffHz,
              IfThen(C.Occluded, 'OCCLUDED', 'CLEAR')]));
        end;
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
