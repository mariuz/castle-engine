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

{ Stateless editor & headless test helpers for the Gerstner Ocean / River Water
  System, Shoreline Foam & Multi-Pontoon Buoyancy Studio (@link(TWaterStudioHelper))
  (Phase 308 — UE 6.0+ Water System & Chaos Buoyancy Parity). }
unit ToolWaterStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleTransform, CastleScene,
  CastleViewport, CastleUIControls, CastleWaterSystem;

type
  { Audit report across all @link(TCastleWaterVolume) and
    @link(TCastleBuoyancyBehavior) instances in a design. }
  TWaterStudioAuditReport = class
  public
    WaterVolumes: array of TCastleWaterVolume;
    BuoyantHulls: array of TCastleBuoyancyBehavior;
    SubmergedHullCount: Integer;
    DryHullCount: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless studio operations for @link(TCastleWaterVolume) and
    @link(TCastleBuoyancyBehavior). }
  TWaterStudioHelper = class
  public
    class function ScanDesign(const RootComp, DesignOwner: TComponent): TWaterStudioAuditReport; static;

    class function SpawnWaterVolume(
      const RootComp, DesignOwner: TComponent;
      const APreset: TWaterBodyPreset;
      const SpawnPos: TVector3): TCastleWaterVolume; static;

    class function AttachBuoyancyToTransform(
      const Target: TCastleTransform;
      const DesignOwner: TComponent;
      const AWater: TCastleWaterVolume = nil): TCastleBuoyancyBehavior; static;

    class function SpawnFloatingCrate(
      const RootComp, DesignOwner: TComponent;
      const AWater: TCastleWaterVolume;
      const SpawnPos: TVector3): TCastleBox; static;

    class procedure StepAllWaterAndBuoyancy(
      const RootComp, DesignOwner: TComponent;
      const Dt: Single); static;

    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleStringUtils;

function MakeUniqueWaterName(const OwnerComp: TComponent; const Base: String): String;
var
  Idx: Integer;
begin
  if (OwnerComp = nil) or (OwnerComp.FindComponent(Base) = nil) then
    Exit(Base);
  Idx := 1;
  repeat
    Result := Base + IntToStr(Idx);
    Inc(Idx);
  until OwnerComp.FindComponent(Result) = nil;
end;

function ResolveParentTransform(const RootComp: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp).Items);
  if RootComp is TCastleTransform then
    Exit(TCastleTransform(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := ResolveParentTransform(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
  for I := 0 to RootComp.ComponentCount - 1 do
    if RootComp.Components[I] is TCastleViewport then
      Exit(TCastleViewport(RootComp.Components[I]).Items);
end;

{ TWaterStudioAuditReport ---------------------------------------------------- }

constructor TWaterStudioAuditReport.Create;
begin
  inherited;
  Warnings := TStringList.Create;
end;

destructor TWaterStudioAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

{ TWaterStudioHelper --------------------------------------------------------- }

class function TWaterStudioHelper.ScanDesign(
  const RootComp, DesignOwner: TComponent): TWaterStudioAuditReport;
var
  Visited: array of TComponent;

  function Seen(const C: TComponent): Boolean;
  var
    I: Integer;
  begin
    if C = nil then
      Exit(true);
    for I := 0 to High(Visited) do
      if Visited[I] = C then
        Exit(true);
    SetLength(Visited, Length(Visited) + 1);
    Visited[High(Visited)] := C;
    Result := false;
  end;

  procedure InspectComp(const C: TComponent);
  var
    W: TCastleWaterVolume;
    B: TCastleBuoyancyBehavior;
    PW: array[0..3] of TVector3;
    PY: array[0..3] of Single;
    AvgN, AvgF: TVector3;
    SubCnt: Integer;
  begin
    if Seen(C) then
      Exit;
    if C is TCastleWaterVolume then
    begin
      W := TCastleWaterVolume(C);
      SetLength(Result.WaterVolumes, Length(Result.WaterVolumes) + 1);
      Result.WaterVolumes[High(Result.WaterVolumes)] := W;
    end else
    if C is TCastleBuoyancyBehavior then
    begin
      B := TCastleBuoyancyBehavior(C);
      SetLength(Result.BuoyantHulls, Length(Result.BuoyantHulls) + 1);
      Result.BuoyantHulls[High(Result.BuoyantHulls)] := B;
      SubCnt := B.SampleHullPontoons(PW, PY, AvgN, AvgF);
      if SubCnt > 0 then
        Inc(Result.SubmergedHullCount)
      else
      begin
        Inc(Result.DryHullCount);
        if B.Parent <> nil then
          Result.Warnings.Add(Format(
            'Buoyant hull "%s" (%s) currently has 0/4 submerged pontoons (above or outside water volume).',
            [B.Parent.Name, B.Name]));
      end;
    end;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
  begin
    if C = nil then
      Exit;
    InspectComp(C);
    if (C is TCastleViewport) and (TCastleViewport(C).Items <> nil) then
      Walk(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Walk(UI.Controls[I]);
      for I := 0 to UI.NonVisualComponentsCount - 1 do
        Walk(UI.NonVisualComponents[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.BehaviorsCount - 1 do
        Walk(T.Behaviors[I]);
      for I := 0 to T.Count - 1 do
        Walk(T.Items[I]);
    end;
  end;

var
  I: Integer;
begin
  Result := TWaterStudioAuditReport.Create;
  Walk(RootComp);
  if DesignOwner <> nil then
    for I := 0 to DesignOwner.ComponentCount - 1 do
      Walk(DesignOwner.Components[I]);
end;

class function TWaterStudioHelper.SpawnWaterVolume(
  const RootComp, DesignOwner: TComponent;
  const APreset: TWaterBodyPreset;
  const SpawnPos: TVector3): TCastleWaterVolume;
var
  ParentT: TCastleTransform;
  OwnerToUse: TComponent;
begin
  ParentT := ResolveParentTransform(RootComp);
  if ParentT = nil then
    Exit(nil);
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleWaterVolume.Create(OwnerToUse);
  Result.Name := MakeUniqueWaterName(OwnerToUse, 'WaterVolume');
  Result.Translation := SpawnPos;
  Result.ApplyPreset(APreset);
  ParentT.Add(Result);
end;

class function TWaterStudioHelper.AttachBuoyancyToTransform(
  const Target: TCastleTransform;
  const DesignOwner: TComponent;
  const AWater: TCastleWaterVolume): TCastleBuoyancyBehavior;
var
  OwnerToUse: TComponent;
begin
  if Target = nil then
    Exit(nil);
  Result := Target.FindBehavior(TCastleBuoyancyBehavior) as TCastleBuoyancyBehavior;
  if Result = nil then
  begin
    if DesignOwner <> nil then
      OwnerToUse := DesignOwner
    else
      OwnerToUse := Target.Owner;
    Result := TCastleBuoyancyBehavior.Create(OwnerToUse);
    Result.Name := MakeUniqueWaterName(OwnerToUse, 'BuoyancyHull');
    Target.AddBehavior(Result);
  end;
  if AWater <> nil then
    Result.WaterVolume := AWater;
  Result.Enabled := true;
end;

class function TWaterStudioHelper.SpawnFloatingCrate(
  const RootComp, DesignOwner: TComponent;
  const AWater: TCastleWaterVolume;
  const SpawnPos: TVector3): TCastleBox;
var
  ParentT: TCastleTransform;
  OwnerToUse: TComponent;
  Behav: TCastleBuoyancyBehavior;
begin
  ParentT := ResolveParentTransform(RootComp);
  if ParentT = nil then
    Exit(nil);
  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Result := TCastleBox.Create(OwnerToUse);
  Result.Name := MakeUniqueWaterName(OwnerToUse, 'FloatingHull');
  Result.Size := Vector3(1.6, 0.8, 2.6);
  Result.Color := Vector4(0.72, 0.48, 0.24, 1.0);
  Result.Translation := SpawnPos;
  ParentT.Add(Result);

  Behav := AttachBuoyancyToTransform(Result, OwnerToUse, AWater);
  if Behav <> nil then
  begin
    Behav.HullWidth := 1.6;
    Behav.HullLength := 2.6;
    Behav.HullDraft := 0.8;
  end;
end;

class procedure TWaterStudioHelper.StepAllWaterAndBuoyancy(
  const RootComp, DesignOwner: TComponent;
  const Dt: Single);
var
  Report: TWaterStudioAuditReport;
  I: Integer;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  try
    for I := 0 to High(Report.WaterVolumes) do
      Report.WaterVolumes[I].StepSimulation(Dt);
    for I := 0 to High(Report.BuoyantHulls) do
      Report.BuoyantHulls[I].StepBuoyancy(Dt);
  finally
    FreeAndNil(Report);
  end;
end;

class function TWaterStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TWaterStudioAuditReport;
  SB: TStringBuilder;
  I: Integer;
  W: TCastleWaterVolume;
  B: TCastleBuoyancyBehavior;
begin
  Report := ScanDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Gerstner Water & 4-Pontoon Buoyancy Studio Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Water Volumes**: `%d`', [Length(Report.WaterVolumes)]));
    SB.AppendLine(Format('- **Buoyant Hulls**: `%d` (`%d` floating/submerged, `%d` dry/airborne)',
      [Length(Report.BuoyantHulls), Report.SubmergedHullCount, Report.DryHullCount]));
    SB.AppendLine;

    if Length(Report.WaterVolumes) > 0 then
    begin
      SB.AppendLine('## Water Volumes');
      SB.AppendLine('| Name | Preset | Footprint (m) | Amp (m) | Length (m) | Flow XZ (m/s) |');
      SB.AppendLine('| :--- | :--- | :---: | :---: | :---: | :---: |');
      for I := 0 to High(Report.WaterVolumes) do
      begin
        W := Report.WaterVolumes[I];
        SB.AppendLine(Format('| `%s` | %s | %.1f x %.1f | %.2f | %.1f | (%.2f, %.2f) |',
          [W.Name, TCastleWaterVolume.PresetDisplayName(W.Preset),
           W.SizeX, W.SizeZ, W.WaveAmplitude, W.WaveLength,
           W.FlowSpeedX, W.FlowSpeedZ]));
      end;
      SB.AppendLine;
    end;

    if Length(Report.BuoyantHulls) > 0 then
    begin
      SB.AppendLine('## Buoyant Hulls');
      SB.AppendLine('| Hull | Behavior | Dimensions (W x L x Draft) | Pontoons Submerged | Avg Submergence |');
      SB.AppendLine('| :--- | :--- | :---: | :---: | :---: |');
      for I := 0 to High(Report.BuoyantHulls) do
      begin
        B := Report.BuoyantHulls[I];
        if B.Parent <> nil then
          SB.AppendLine(Format('| `%s` | `%s` | %.1f x %.1f x %.2fm | %d / 4 | %.2f |',
            [B.Parent.Name, B.Name, B.HullWidth, B.HullLength, B.HullDraft,
             B.SubmergedPontoonCount, B.AverageSubmergence]));
      end;
      SB.AppendLine;
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Report);
  end;
end;

end.
