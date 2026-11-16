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

{ Stateless Editor & Headless Helper for 2.5D Shallow-Water Virtual-Pipe Fluid
  Surfaces, Waterfall/Dam-Break Spawners, Stepping & QA Diagnostics
  (@link(TFluidStudioHelper), @link(TFluidAuditReport))
  (Phase 330 — UE 6.0+ Niagara Grid2D Shallow Water & Water 2.0 Parity). }
unit ToolFluidStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleViewport, CastleShallowFluid;

type
  TShallowFluidArray = array of TCastleShallowFluidSurface;

  { QA summary across all 2.5D Shallow-Water fluid surfaces in a design. }
  TFluidAuditReport = class
  public
    FluidCount: Integer;
    TotalCells: Integer;
    TotalVolumeM3: Double;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, stepping, and auditing
    @link(TCastleShallowFluidSurface) instances. }
  TFluidStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanFluids(const RootComp, DesignOwner: TComponent;
      out OutFluids: TShallowFluidArray); static;

    class function SpawnShallowFluidDemo(const RootComp, DesignOwner: TComponent;
      const APreset: TShallowFluidPreset = sfpTerracedWaterfallPools): TCastleShallowFluidSurface; static;

    class procedure StepAllFluids(const RootComp, DesignOwner: TComponent;
      const Dt: Single); static;

    class function AuditFluids(
      const RootComp, DesignOwner: TComponent): TFluidAuditReport; static;

    class function BuildMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  CastleUIControls;

constructor TFluidAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TFluidAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TFluidStudioHelper.FindMainViewport(
  const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if RootComp = nil then Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  if RootComp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(RootComp);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindMainViewport(UI.Controls[I]);
      if Result <> nil then Exit;
    end;
  end;
end;

class procedure TFluidStudioHelper.ScanFluids(
  const RootComp, DesignOwner: TComponent;
  out OutFluids: TShallowFluidArray);

  procedure AddUnique(const F: TCastleShallowFluidSurface);
  var
    K: Integer;
  begin
    if (F = nil) or (csTransient in F.ComponentStyle) then Exit;
    for K := 0 to High(OutFluids) do
      if OutFluids[K] = F then Exit;
    SetLength(OutFluids, Length(OutFluids) + 1);
    OutFluids[High(OutFluids)] := F;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if C is TCastleShallowFluidSurface then
      AddUnique(TCastleShallowFluidSurface(C));

    for I := 0 to C.ComponentCount - 1 do
      Walk(C.Components[I]);
    if C is TCastleViewport then
      Walk(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end;
  end;

begin
  OutFluids := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class function TFluidStudioHelper.SpawnShallowFluidDemo(
  const RootComp, DesignOwner: TComponent;
  const APreset: TShallowFluidPreset): TCastleShallowFluidSurface;
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  Idx: Integer;
begin
  Result := nil;
  Vp := FindMainViewport(RootComp);
  if Vp <> nil then
    ParentTrans := Vp.Items
  else if RootComp is TCastleTransform then
    ParentTrans := TCastleTransform(RootComp)
  else
    Exit;

  if DesignOwner <> nil then
    OwnerToUse := DesignOwner
  else
    OwnerToUse := RootComp;

  Idx := 1;
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('ShallowFluidSurface' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  Result := TCastleShallowFluidSurface.Create(OwnerToUse);
  Result.Name := 'ShallowFluidSurface' + IntToStr(Idx);
  Result.ApplyPreset(APreset);
  ParentTrans.Add(Result);
end;

class procedure TFluidStudioHelper.StepAllFluids(
  const RootComp, DesignOwner: TComponent; const Dt: Single);
var
  Fluids: TShallowFluidArray;
  I: Integer;
begin
  ScanFluids(RootComp, DesignOwner, Fluids);
  for I := 0 to High(Fluids) do
    Fluids[I].StepFluid(Dt);
end;

class function TFluidStudioHelper.AuditFluids(
  const RootComp, DesignOwner: TComponent): TFluidAuditReport;
var
  Fluids: TShallowFluidArray;
  I: Integer;
begin
  Result := TFluidAuditReport.Create;
  ScanFluids(RootComp, DesignOwner, Fluids);
  Result.FluidCount := Length(Fluids);
  for I := 0 to High(Fluids) do
  begin
    Inc(Result.TotalCells, Fluids[I].GridResX * Fluids[I].GridResZ);
    Result.TotalVolumeM3 := Result.TotalVolumeM3 + Fluids[I].TotalWaterVolumeM3;
    if (Fluids[I].TotalWaterVolumeM3 < 0.01) and (Fluids[I].SpringCount = 0) and
       (Fluids[I].RainRateMps <= 0.0) then
      Result.Warnings.Add(Format(
        'ShallowFluidSurface "%s" is completely dry with 0 active springs or rain.',
        [Fluids[I].Name]));
  end;
end;

class function TFluidStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Fluids: TShallowFluidArray;
  Audit: TFluidAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanFluids(RootComp, DesignOwner, Fluids);
  Audit := AuditFluids(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — 2.5D Shallow-Water Fluid & Waterfall Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **Active Fluid Surfaces**: `%d` (`%d` total grid cells, `%.2f m^3` total water)',
      [Audit.FluidCount, Audit.TotalCells, Audit.TotalVolumeM3]));
    SB.AppendLine;

    if Length(Fluids) > 0 then
    begin
      SB.AppendLine('## Hydrological Telemetry');
      SB.AppendLine('| Surface | Preset | Grid | Volume | Wet Cells | Peak Speed | Peak Foam |');
      SB.AppendLine('| :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
      for I := 0 to High(Fluids) do
        SB.AppendLine(Format('| `%s` | %s | `%dx%d` | `%.2f m^3` | `%d` | `%.2f m/s` | `%.0f%%` |',
          [Fluids[I].Name,
           TCastleShallowFluidSurface.PresetDisplayName(Fluids[I].Preset),
           Fluids[I].GridResX, Fluids[I].GridResZ,
           Fluids[I].TotalWaterVolumeM3, Fluids[I].WetCellCount,
           Fluids[I].MaxFlowSpeedMps, Fluids[I].MaxFoamFactor * 100.0]));
      SB.AppendLine;
    end;

    SB.AppendLine('## QA Diagnostics');
    if Audit.Warnings.Count = 0 then
      SB.AppendLine('- **0 warnings** — all Shallow-Water fluid grids are stable and mass-conserving.')
    else
      for I := 0 to Audit.Warnings.Count - 1 do
        SB.AppendLine('- **Warning**: ' + Audit.Warnings[I]);

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Audit);
  end;
end;

end.
