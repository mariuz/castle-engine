{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Design-time helper for 2.5D Atmospheric Cloud Shadow Scroller & Crepuscular
  Light-Shaft Studio (Phase 382). }
unit ToolCloudShadows;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleScene, CastleColors,
  CastleCloudShadows;

type
  TCloudShadowStudioSummary = record
    ProjectorCount: Integer;
    AvgCoveragePct: Single;
    AvgWindMps: Single;
    ShadowedGridFractionPct: Single;
  end;

  TCloudShadowsHelper = class
  public
    class function FindFirstProjector(const ARoot: TComponent): TCastleCloudShadowProjector;
    class function SpawnValleyCloudShadowDemo(const ADesignRoot, ADesignOwner: TComponent;
      out AProjector: TCastleCloudShadowProjector): Boolean;
    class function CollectSummary(const ADesignRoot: TComponent): TCloudShadowStudioSummary;
    class function BuildMarkdownReport(const ADesignRoot: TComponent): String;
  end;

implementation

uses CastleUtils;

function FindViewport(const ARoot: TComponent): TCastleViewport;
var
  I: Integer;
begin
  if ARoot = nil then Exit(nil);
  if ARoot is TCastleViewport then Exit(TCastleViewport(ARoot));
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindViewport(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
  Result := nil;
end;

class function TCloudShadowsHelper.FindFirstProjector(
  const ARoot: TComponent): TCastleCloudShadowProjector;
var
  I: Integer;
  T: TCastleTransform;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if (ARoot is TCastleCloudShadowProjector) and (not (csTransient in ARoot.ComponentStyle)) then
    Exit(TCastleCloudShadowProjector(ARoot));
  if ARoot is TCastleTransform then
  begin
    T := TCastleTransform(ARoot);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindFirstProjector(T[I]);
      if Result <> nil then Exit;
    end;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindFirstProjector(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TCloudShadowsHelper.SpawnValleyCloudShadowDemo(
  const ADesignRoot, ADesignOwner: TComponent;
  out AProjector: TCastleCloudShadowProjector): Boolean;
var
  Vp: TCastleViewport;
  OwnerToUse: TComponent;
  GroundMeadow: TCastleBox;
begin
  AProjector := nil;
  Vp := FindViewport(ADesignRoot);
  if Vp = nil then Exit(False);
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := Vp;

  GroundMeadow := TCastleBox.Create(OwnerToUse);
  GroundMeadow.Name := 'CloudShadowMeadowFloor';
  GroundMeadow.Size := Vector3(160.0, 0.5, 160.0);
  GroundMeadow.Translation := Vector3(0.0, -0.25, 0.0);
  GroundMeadow.Color := Vector4(0.32, 0.54, 0.28, 1.0);
  Vp.Items.Add(GroundMeadow);

  AProjector := TCastleCloudShadowProjector.Create(OwnerToUse);
  AProjector.Name := 'ValleyCloudShadowDeck';
  AProjector.ApplyPreset(cspSummerCumulusDrift);
  Vp.Items.Add(AProjector);

  Result := True;
end;

class function TCloudShadowsHelper.CollectSummary(
  const ADesignRoot: TComponent): TCloudShadowStudioSummary;
var
  SumCov, SumWind: Single;

  procedure Scan(const ANode: TComponent);
  var
    I: Integer;
    P: TCastleCloudShadowProjector;
    T: TCastleTransform;
  begin
    if ANode = nil then Exit;
    if (ANode is TCastleCloudShadowProjector) and (not (csTransient in ANode.ComponentStyle)) then
    begin
      P := TCastleCloudShadowProjector(ANode);
      Inc(Result.ProjectorCount);
      SumCov := SumCov + P.CloudCoverage01 * 100.0;
      SumWind := SumWind + P.WindSpeedMps;
      if Result.ProjectorCount = 1 then
        Result.ShadowedGridFractionPct := P.ComputeCoverageFractionOverGrid(200.0, 16) * 100.0;
    end;
    if ANode is TCastleTransform then
    begin
      T := TCastleTransform(ANode);
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
    for I := 0 to ANode.ComponentCount - 1 do
      if not (ANode.Components[I] is TCastleTransform) or
         (TCastleTransform(ANode.Components[I]).Parent = nil) then
        Scan(ANode.Components[I]);
  end;

begin
  Result := Default(TCloudShadowStudioSummary);
  SumCov := 0.0;
  SumWind := 0.0;
  Scan(ADesignRoot);
  if Result.ProjectorCount > 0 then
  begin
    Result.AvgCoveragePct := SumCov / Result.ProjectorCount;
    Result.AvgWindMps := SumWind / Result.ProjectorCount;
  end;
end;

class function TCloudShadowsHelper.BuildMarkdownReport(
  const ADesignRoot: TComponent): String;
var
  Sum: TCloudShadowStudioSummary;
  Proj: TCastleCloudShadowProjector;
  OriginS: TCloudShadowSample;
begin
  Sum := CollectSummary(ADesignRoot);
  Proj := FindFirstProjector(ADesignRoot);
  if Proj <> nil then
    OriginS := Proj.SampleGroundShadowAt(TVector3.Zero, Proj.EvaluateSunDirectionToSky)
  else
    OriginS := Default(TCloudShadowSample);

  Result :=
    '# 2.5D Atmospheric Cloud Shadow & Crepuscular God-Ray Report (Phase 382)' + NL + NL +
    Format('- **Active Cloud Projectors**: `%d`' + NL, [Sum.ProjectorCount]) +
    Format('- **Mean Cloud Coverage / Wind**: `%0.1f%%` | `%0.1f m/s`' + NL,
      [Sum.AvgCoveragePct, Sum.AvgWindMps]) +
    Format('- **Shadowed Ground Grid Fraction**: `%0.1f%%`' + NL,
      [Sum.ShadowedGridFractionPct]) +
    Format('- **Origin Probe `(0, 0, 0)`**: Transmittance = `%0.2f` | God-Ray Shaft = `%0.2f` | CanopyXZ = `(%0.1f, %0.1f)`' + NL,
      [OriginS.DirectSunTransmittance01, OriginS.CrepuscularShaftIntensity,
       OriginS.ProjectedCanopyXZ.X, OriginS.ProjectedCanopyXZ.Y]);
end;

end.
