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

{ Hierarchy discovery, 1-click destructible Stone Pillar / Wooden Crate /
  Crystal Obelisk spawners, batch blast detonation, debris stepping, intact
  restoration, and Markdown reporting for @link(TCastleDestructibleBehavior)
  (Phase 305). }
unit ToolDestructible;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleClassUtils, CastleTransform, CastleUiControls, CastleViewport,
  CastleDestructible;

type
  TDestructibleBehaviorArray = array of TCastleDestructibleBehavior;

  { Hierarchy scan & summary for Destructible Voronoi Fracture Studio. }
  TDestructibleSummary = record
    Props: TDestructibleBehaviorArray;
    TotalConfiguredShards: Integer;
    FracturedPropCount: Integer;
    ActiveDebrisShardCount: Integer;
    Warnings: array of String;
  end;

  { Stateless editor helper for Destructible Voronoi Props & Debris Lifecycle. }
  TDestructibleHelper = class
  public
    class function ScanDestructibles(const ARoot: TComponent): TDestructibleSummary;

    class function CreateDestructiblePropInDesign(
      const ARoot, ADesignOwner: TComponent;
      const APreset: TDestructibleMaterialPreset;
      const ABasePos: TVector3): TCastleDestructibleBehavior;

    class function TriggerRadialBlastInHierarchy(
      const ARoot: TComponent;
      const ABlastOriginWorld: TVector3;
      const ABlastRadius, AMaxDamage: Single): Integer;

    class function StepAllDebrisInHierarchy(
      const ARoot: TComponent;
      const ADeltaSeconds: Single): Integer;

    class procedure ResetAllDestructiblesInHierarchy(const ARoot: TComponent);

    class function BuildMarkdownReport(const ARoot: TComponent): String;
  end;

implementation

uses
  Math, CastleColors, CastleScene;

function ProposeUniqueDestructibleName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function FindDestructibleWorldContainer(const ARoot: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
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
    UI := TCastleUserInterface(ARoot);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindDestructibleWorldContainer(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

{ TDestructibleHelper -------------------------------------------------------- }

class function TDestructibleHelper.ScanDestructibles(
  const ARoot: TComponent): TDestructibleSummary;

  procedure AddWarn(const S: String);
  var
    N: Integer;
  begin
    N := Length(Result.Warnings);
    SetLength(Result.Warnings, N + 1);
    Result.Warnings[N] := S;
  end;

  procedure Visit(const C: TComponent);
  var
    I, N: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    Vp: TCastleViewport;
    Dest: TCastleDestructibleBehavior;
  begin
    if C = nil then
      Exit;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      if not (csTransient in T.ComponentStyle) then
      begin
        for I := 0 to T.BehaviorsCount - 1 do
          if T.Behaviors[I] is TCastleDestructibleBehavior then
          begin
            Dest := TCastleDestructibleBehavior(T.Behaviors[I]);
            N := Length(Result.Props);
            SetLength(Result.Props, N + 1);
            Result.Props[N] := Dest;
            Inc(Result.TotalConfiguredShards, Dest.ShardCount);
            if Dest.IsFractured then
              Inc(Result.FracturedPropCount);
            Inc(Result.ActiveDebrisShardCount, Dest.ActiveShardCount);
            if Dest.ShardCount > 36 then
              AddWarn(Format('Prop "%s" has %d Voronoi shards (>36 recommended real-time mobile cap).',
                [T.Name, Dest.ShardCount]));
          end;
        for I := 0 to T.Count - 1 do
          Visit(T[I]);
      end;
    end else
    if C is TCastleViewport then
    begin
      Vp := TCastleViewport(C);
      Visit(Vp.Items);
      for I := 0 to Vp.ControlsCount - 1 do
        Visit(Vp.Controls[I]);
    end else
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;
  end;

begin
  Result := Default(TDestructibleSummary);
  Visit(ARoot);
end;

class function TDestructibleHelper.CreateDestructiblePropInDesign(
  const ARoot, ADesignOwner: TComponent;
  const APreset: TDestructibleMaterialPreset;
  const ABasePos: TVector3): TCastleDestructibleBehavior;
var
  Container: TCastleTransform;
  PropBox: TCastleBox;
  BoxSize: TVector3;
  Col: TCastleColor;
  BaseName: String;
  Shards: Integer;
  Hp: Single;
begin
  Result := nil;
  Container := FindDestructibleWorldContainer(ARoot);
  if Container = nil then
    Exit;

  case APreset of
    dmpStoneMasonry:
      begin
        BaseName := 'StoneColumnProp';
        BoxSize := Vector3(0.90, 2.20, 0.90);
        Col := Vector4(0.58, 0.57, 0.54, 1.0);
        Shards := 14;
        Hp := 150.0;
      end;
    dmpWoodenCrate:
      begin
        BaseName := 'WoodenSupplyCrate';
        BoxSize := Vector3(1.10, 1.10, 1.10);
        Col := Vector4(0.64, 0.43, 0.23, 1.0);
        Shards := 10;
        Hp := 60.0;
      end;
    dmpCrystalGlass:
      begin
        BaseName := 'CrystalSpireProp';
        BoxSize := Vector3(0.75, 1.85, 0.75);
        Col := Vector4(0.55, 0.86, 0.96, 1.0);
        Shards := 18;
        Hp := 40.0;
      end;
    dmpScrapMetal:
      begin
        BaseName := 'ArmoredBulkheadProp';
        BoxSize := Vector3(1.60, 1.40, 0.45);
        Col := Vector4(0.48, 0.51, 0.56, 1.0);
        Shards := 12;
        Hp := 220.0;
      end;
    dmpObsidianCore:
      begin
        BaseName := 'ObsidianMonolith';
        BoxSize := Vector3(1.00, 2.00, 1.00);
        Col := Vector4(0.18, 0.15, 0.22, 1.0);
        Shards := 16;
        Hp := 180.0;
      end;
  end;

  PropBox := TCastleBox.Create(ADesignOwner);
  PropBox.Name := ProposeUniqueDestructibleName(ADesignOwner, BaseName);
  PropBox.Size := BoxSize;
  PropBox.Color := Col;
  PropBox.Translation := ABasePos + Vector3(0.0, BoxSize.Y * 0.5, 0.0);
  Container.Add(PropBox);

  Result := TCastleDestructibleBehavior.Create(ADesignOwner);
  Result.Name := ProposeUniqueDestructibleName(ADesignOwner, 'VoronoiFracture');
  Result.MaterialPreset := APreset;
  Result.MaxHealth := Hp;
  Result.CurrentHealth := Hp;
  Result.ShardCount := Shards;
  Result.GroundFloorY := ABasePos.Y;
  Result.FractureBoxSize := BoxSize;
  PropBox.AddBehavior(Result);
end;

class function TDestructibleHelper.TriggerRadialBlastInHierarchy(
  const ARoot: TComponent;
  const ABlastOriginWorld: TVector3;
  const ABlastRadius, AMaxDamage: Single): Integer;
var
  Sum: TDestructibleSummary;
  I: Integer;
  PropPos: TVector3;
  Dist, SafeRad, AttenDmg: Single;
  Cur: TCastleTransform;
  M: TMatrix4;
begin
  Result := 0;
  SafeRad := Max(0.10, ABlastRadius);
  Sum := ScanDestructibles(ARoot);
  for I := 0 to High(Sum.Props) do
    if (Sum.Props[I].Parent <> nil) and (not Sum.Props[I].IsFractured) then
    begin
      M := TMatrix4.Identity;
      Cur := Sum.Props[I].Parent;
      while (Cur <> nil) and (not (Cur is TCastleAbstractRootTransform)) do
      begin
        M := Cur.Transform * M;
        Cur := Cur.Parent;
      end;
      PropPos := M.MultPoint(TVector3.Zero);
      Dist := PointsDistance(PropPos, ABlastOriginWorld);
      if Dist <= SafeRad then
      begin
        AttenDmg := AMaxDamage * (1.0 - (Dist / SafeRad) * 0.65);
        if Sum.Props[I].ApplyDamage(AttenDmg, ABlastOriginWorld) then
          Inc(Result);
      end;
    end;
end;

class function TDestructibleHelper.StepAllDebrisInHierarchy(
  const ARoot: TComponent; const ADeltaSeconds: Single): Integer;
var
  Sum: TDestructibleSummary;
  I: Integer;
begin
  Result := 0;
  Sum := ScanDestructibles(ARoot);
  for I := 0 to High(Sum.Props) do
    Inc(Result, Sum.Props[I].StepDebrisSimulation(ADeltaSeconds));
end;

class procedure TDestructibleHelper.ResetAllDestructiblesInHierarchy(
  const ARoot: TComponent);
var
  Sum: TDestructibleSummary;
  I: Integer;
begin
  Sum := ScanDestructibles(ARoot);
  for I := 0 to High(Sum.Props) do
    Sum.Props[I].ResetIntact;
end;

class function TDestructibleHelper.BuildMarkdownReport(const ARoot: TComponent): String;
var
  Sum: TDestructibleSummary;
  SB: TStringBuilder;
  I: Integer;
  D: TCastleDestructibleBehavior;
  PName: String;
begin
  Sum := ScanDestructibles(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Destructible Voronoi Fracture & Debris Lifecycle Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Destructible Props**: %d (Fractured: %d, Active Shards: %d)',
      [Length(Sum.Props), Sum.FracturedPropCount, Sum.ActiveDebrisShardCount]));
    SB.AppendLine(Format('- **Total Configured Voronoi Cells**: %d',
      [Sum.TotalConfiguredShards]));
    SB.AppendLine('');

    if Length(Sum.Props) > 0 then
    begin
      SB.AppendLine('## Destructible Prop Inventory');
      SB.AppendLine('| Prop Transform | Material | Health | Voronoi Cells | Seed | Blast Impulse | Lifetime | State |');
      SB.AppendLine('| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: |');
      for I := 0 to High(Sum.Props) do
      begin
        D := Sum.Props[I];
        if D.Parent <> nil then PName := D.Parent.Name else PName := '(nil)';
        SB.AppendLine(Format('| `%s` | %s | %.0f / %.0f | %d | %d | %.1f m/s | %.1f s | %s |',
          [PName, DestructiblePresetDisplayName(D.MaterialPreset),
           D.CurrentHealth, D.MaxHealth, D.ShardCount, D.FractureSeed,
           D.BlastImpulse, D.DebrisLifetimeSec,
           BoolToStr(D.IsFractured, 'Fractured', 'Intact')]));
      end;
      SB.AppendLine('');
    end;

    if Length(Sum.Warnings) > 0 then
    begin
      SB.AppendLine('## Diagnostics Warnings');
      for I := 0 to High(Sum.Warnings) do
        SB.AppendLine('- ' + Sum.Warnings[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
