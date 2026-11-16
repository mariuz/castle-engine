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

{ Stateless Editor & Headless Helper for Volumetric Exponential Height Fog,
  Anisotropic God-Ray Scattering & Priority-Blended Box-Parallax Reflection
  Probes (@link(TVolumetricStudioHelper), @link(TVolumetricAuditReport))
  (Phase 324 — UE 6.0+ Volumetric Fog & Box Reflection Captures Parity). }
unit ToolVolumetricStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleTransform, CastleViewport, CastleVolumetrics;

type
  TVolumetricAtmosphereArray = array of TCastleVolumetricAtmosphere;
  TReflectionProbeArray = array of TCastleReflectionProbe;

  { QA summary across all volumetric height fog and reflection probe nodes. }
  TVolumetricAuditReport = class
  public
    AtmosphereCount: Integer;
    ProbeCount: Integer;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
  end;

  { Stateless helper for discovering, spawning, priority-blending probes, and
    auditing @link(TCastleVolumetricAtmosphere) & @link(TCastleReflectionProbe). }
  TVolumetricStudioHelper = class
  public
    class function FindMainViewport(const RootComp: TComponent): TCastleViewport; static;

    class procedure ScanVolumetrics(const RootComp, DesignOwner: TComponent;
      out OutAtmospheres: TVolumetricAtmosphereArray;
      out OutProbes: TReflectionProbeArray); static;

    class procedure SpawnVolumetricValleyAndProbesDemo(
      const RootComp, DesignOwner: TComponent;
      out OutAtmos: TCastleVolumetricAtmosphere;
      out OutOutdoorProbe, OutInteriorProbe: TCastleReflectionProbe); static;

    { Priority-ordered smooth probe irradiance & dominant probe blending at @code(WorldPos). }
    class function BlendReflectionProbesAtPoint(
      const RootComp, DesignOwner: TComponent; const WorldPos: TVector3;
      out OutDominantProbe: TCastleReflectionProbe;
      out OutBlendedIrradiance: TCastleColorRGB): Single; static;

    class function AuditVolumetrics(
      const RootComp, DesignOwner: TComponent): TVolumetricAuditReport; static;

    class function BuildMarkdownReport(const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  Math;

constructor TVolumetricAuditReport.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
end;

destructor TVolumetricAuditReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

class function TVolumetricStudioHelper.FindMainViewport(const RootComp: TComponent): TCastleViewport;
var
  I: Integer;
  Found: TCastleViewport;
begin
  Result := nil;
  if RootComp = nil then
    Exit;
  if RootComp is TCastleViewport then
    Exit(TCastleViewport(RootComp));
  for I := 0 to RootComp.ComponentCount - 1 do
  begin
    Found := FindMainViewport(RootComp.Components[I]);
    if Found <> nil then
      Exit(Found);
  end;
end;

class procedure TVolumetricStudioHelper.ScanVolumetrics(
  const RootComp, DesignOwner: TComponent;
  out OutAtmospheres: TVolumetricAtmosphereArray;
  out OutProbes: TReflectionProbeArray);

  procedure AddAtm(const A: TCastleVolumetricAtmosphere);
  var K: Integer;
  begin
    for K := 0 to High(OutAtmospheres) do if OutAtmospheres[K] = A then Exit;
    SetLength(OutAtmospheres, Length(OutAtmospheres) + 1);
    OutAtmospheres[High(OutAtmospheres)] := A;
  end;

  procedure AddPrb(const P: TCastleReflectionProbe);
  var K: Integer;
  begin
    for K := 0 to High(OutProbes) do if OutProbes[K] = P then Exit;
    SetLength(OutProbes, Length(OutProbes) + 1);
    OutProbes[High(OutProbes)] := P;
  end;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;
    if C is TCastleVolumetricAtmosphere then
      AddAtm(TCastleVolumetricAtmosphere(C))
    else if C is TCastleReflectionProbe then
      AddPrb(TCastleReflectionProbe(C));

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
  OutAtmospheres := nil;
  OutProbes := nil;
  Walk(RootComp);
  if (DesignOwner <> nil) and (DesignOwner <> RootComp) then
    Walk(DesignOwner);
end;

class procedure TVolumetricStudioHelper.SpawnVolumetricValleyAndProbesDemo(
  const RootComp, DesignOwner: TComponent;
  out OutAtmos: TCastleVolumetricAtmosphere;
  out OutOutdoorProbe, OutInteriorProbe: TCastleReflectionProbe);
var
  Vp: TCastleViewport;
  ParentTrans: TCastleTransform;
  OwnerToUse: TComponent;
  Idx: Integer;
begin
  OutAtmos := nil;
  OutOutdoorProbe := nil;
  OutInteriorProbe := nil;

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
  while (OwnerToUse <> nil) and (OwnerToUse.FindComponent('VolumetricAtmos_' + IntToStr(Idx)) <> nil) do
    Inc(Idx);

  OutAtmos := TCastleVolumetricAtmosphere.Create(OwnerToUse);
  OutAtmos.Name := 'VolumetricAtmos_' + IntToStr(Idx);
  OutAtmos.ApplyPreset(vpGoldenHourGodRays);
  ParentTrans.Add(OutAtmos);

  OutOutdoorProbe := TCastleReflectionProbe.Create(OwnerToUse);
  OutOutdoorProbe.Name := 'OutdoorCourtyardProbe_' + IntToStr(Idx);
  OutOutdoorProbe.Priority := 5;
  OutOutdoorProbe.HalfExtents := Vector3(18.0, 10.0, 18.0);
  OutOutdoorProbe.BlendDistance := 4.0;
  OutOutdoorProbe.IrradianceTint := Vector3(0.72, 0.84, 1.00);
  ParentTrans.Add(OutOutdoorProbe);

  OutInteriorProbe := TCastleReflectionProbe.Create(OwnerToUse);
  OutInteriorProbe.Name := 'InteriorTorchHallProbe_' + IntToStr(Idx);
  OutInteriorProbe.Priority := 25;
  OutInteriorProbe.HalfExtents := Vector3(4.5, 3.5, 4.5);
  OutInteriorProbe.BlendDistance := 2.0;
  OutInteriorProbe.IrradianceTint := Vector3(1.00, 0.72, 0.42);
  ParentTrans.Add(OutInteriorProbe);
end;

class function TVolumetricStudioHelper.BlendReflectionProbesAtPoint(
  const RootComp, DesignOwner: TComponent; const WorldPos: TVector3;
  out OutDominantProbe: TCastleReflectionProbe;
  out OutBlendedIrradiance: TCastleColorRGB): Single;
var
  Atms: TVolumetricAtmosphereArray;
  Probes: TReflectionProbeArray;
  TmpP: TCastleReflectionProbe;
  I, J: Integer;
  RemainingBudget, W, Contrib, BestContrib: Single;
begin
  OutDominantProbe := nil;
  OutBlendedIrradiance := Vector3(0.5, 0.5, 0.5);
  ScanVolumetrics(RootComp, DesignOwner, Atms, Probes);
  if Length(Probes) = 0 then
    Exit(0.0);

  { Sort descending by Priority }
  for I := 0 to High(Probes) - 1 do
    for J := I + 1 to High(Probes) do
      if Probes[J].Priority > Probes[I].Priority then
      begin
        TmpP := Probes[I];
        Probes[I] := Probes[J];
        Probes[J] := TmpP;
      end;

  RemainingBudget := 1.0;
  BestContrib := 0.0;
  OutBlendedIrradiance := TVector3.Zero;

  for I := 0 to High(Probes) do
  begin
    if RemainingBudget <= 1e-5 then
      Break;
    W := Probes[I].EvaluateInfluenceWeight(WorldPos);
    if W <= 1e-5 then
      Continue;
    Contrib := Min(RemainingBudget, W * RemainingBudget);
    OutBlendedIrradiance := OutBlendedIrradiance + Probes[I].IrradianceTint * Contrib;
    RemainingBudget := RemainingBudget - Contrib;
    if Contrib > BestContrib then
    begin
      BestContrib := Contrib;
      OutDominantProbe := Probes[I];
    end;
  end;

  Result := 1.0 - RemainingBudget;
  if Result > 1e-5 then
    OutBlendedIrradiance := OutBlendedIrradiance / Result
  else
    OutBlendedIrradiance := Vector3(0.5, 0.5, 0.5);
end;

class function TVolumetricStudioHelper.AuditVolumetrics(
  const RootComp, DesignOwner: TComponent): TVolumetricAuditReport;
var
  Atms: TVolumetricAtmosphereArray;
  Probes: TReflectionProbeArray;
begin
  Result := TVolumetricAuditReport.Create;
  ScanVolumetrics(RootComp, DesignOwner, Atms, Probes);
  Result.AtmosphereCount := Length(Atms);
  Result.ProbeCount := Length(Probes);

  if Result.AtmosphereCount > 1 then
    Result.Warnings.Add(Format(
      'Design contains %d TCastleVolumetricAtmosphere nodes — keep a single primary atmosphere manager per level.',
      [Result.AtmosphereCount]));
end;

class function TVolumetricStudioHelper.BuildMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Atms: TVolumetricAtmosphereArray;
  Probes: TReflectionProbeArray;
  Rep: TVolumetricAuditReport;
  SB: TStringBuilder;
  I: Integer;
begin
  ScanVolumetrics(RootComp, DesignOwner, Atms, Probes);
  Rep := AuditVolumetrics(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Volumetric Height Fog, God-Rays & Reflection Probe Studio Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Volumetric Atmospheres:** %d  |  **Local Reflection Probes:** %d',
      [Rep.AtmosphereCount, Rep.ProbeCount]));
    SB.AppendLine('');
    for I := 0 to High(Atms) do
      SB.AppendLine(Format('- `%s`: %s', [Atms[I].Name, Atms[I].VolumetricSummaryBadge]));
    for I := 0 to High(Probes) do
      SB.AppendLine(Format('- `%s`: %s', [Probes[I].Name, Probes[I].ProbeSummaryBadge]));
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Rep);
  end;
end;

end.
