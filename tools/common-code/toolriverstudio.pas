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

{ Stateless helper for River Spline Rapids, Width/Depth & Drift Studio (Phase 361). }
unit ToolRiverStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleRiverSpline;

type
  TRiverStudioHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindRiverInHierarchy(const Root: TComponent): TCastleRiverSpline;
    class function SpawnMountainGorgeRiverDemo(const Root, DesignOwner: TComponent;
      out River: TCastleRiverSpline;
      out KayakTransform: TCastleTransform): Boolean;
    class function GenerateRiverReport(const River: TCastleRiverSpline): String;
  end;

implementation

class function TRiverStudioHelper.FindViewport(const Root: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleViewport then Exit(TCastleViewport(Root));
  for I := 0 to Root.ComponentCount - 1 do
  begin
    Result := FindViewport(Root.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TRiverStudioHelper.FindRiverInHierarchy(const Root: TComponent): TCastleRiverSpline;

  function WalkTransform(const T: TCastleTransform): TCastleRiverSpline;
  var
    I: Integer;
  begin
    if T is TCastleRiverSpline then
      Exit(TCastleRiverSpline(T));
    for I := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[I]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

var
  Vp: TCastleViewport;
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleRiverSpline then Exit(TCastleRiverSpline(Root));
  if Root is TCastleTransform then
  begin
    Result := WalkTransform(TCastleTransform(Root));
    if Result <> nil then Exit;
  end;
  Vp := FindViewport(Root);
  if (Vp <> nil) and (Vp.Items <> nil) then
  begin
    Result := WalkTransform(Vp.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to Root.ComponentCount - 1 do
    if Root.Components[I] is TCastleRiverSpline then
      Exit(TCastleRiverSpline(Root.Components[I]));
end;

class function TRiverStudioHelper.SpawnMountainGorgeRiverDemo(const Root, DesignOwner: TComponent;
  out River: TCastleRiverSpline;
  out KayakTransform: TCastleTransform): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  KayakBox: TCastleBox;
  Headwater: TRiverCrossSectionSample;
begin
  Result := False;
  River := nil;
  KayakTransform := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  River := FindRiverInHierarchy(Root);
  if River = nil then
  begin
    River := TCastleRiverSpline.Create(OwnerComp);
    River.Name := 'RiverSpline1';
    River.Preset := rspMountainGorgeRapids;
    Vp.Items.Add(River);
  end;

  Headwater := River.SampleRiverAtParam(0.08);
  KayakTransform := OwnerComp.FindComponent('RiverKayak1') as TCastleTransform;
  if KayakTransform = nil then
  begin
    KayakBox := TCastleBox.Create(OwnerComp);
    KayakBox.Name := 'RiverKayak1';
    KayakBox.Size := Vector3(0.85, 0.45, 2.20);
    KayakBox.Translation := Headwater.CenterWorldPos;
    KayakBox.Color := Vector4(1.0, 0.58, 0.14, 1.0);
    Vp.Items.Add(KayakBox);
    KayakTransform := KayakBox;
  end;
  Result := True;
end;

class function TRiverStudioHelper.GenerateRiverReport(const River: TCastleRiverSpline): String;
var
  HeadS, GorgeS, BasinS: TRiverCrossSectionSample;
begin
  if River = nil then
    Exit('# River Spline Rapids & Drift Report' + LineEnding + LineEnding +
         '_No `TCastleRiverSpline` found in design._');

  HeadS := River.SampleRiverAtParam(0.05);
  GorgeS := River.SampleRiverAtParam(0.50);
  BasinS := River.SampleRiverAtParam(0.95);

  Result :=
    '# River Spline Rapids, Variable Width & Whitewater Report (Phase 361)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [River.Name, RiverPresetToString(River.Preset)]) + LineEnding +
    Format('| **Discharge `Q`** | **`%.1f m^3/s`** (`%d` knots, `%d` ribbon tris) |', [
      River.DischargeCubicMps, River.KnotCount, River.GeneratedTriangleCount]) + LineEnding +
    Format('| **Headwater (`u=0.05`)** | `Width=%.1fm` / `Speed=%.2f m/s` / `Foam=%.0f%%` |', [
      HeadS.WidthMeters, HeadS.FlowSpeedMps, HeadS.WhitewaterFoamFactor * 100.0]) + LineEnding +
    Format('| **Gorge Rapids (`u=0.50`)** | `Width=%.1fm` / **`Speed=%.2f m/s`** / `Foam=%.0f%%` |', [
      GorgeS.WidthMeters, GorgeS.FlowSpeedMps, GorgeS.WhitewaterFoamFactor * 100.0]) + LineEnding +
    Format('| **Outflow Basin (`u=0.95`)** | `Width=%.1fm` / `Speed=%.2f m/s` / `Foam=%.0f%%` |', [
      BasinS.WidthMeters, BasinS.FlowSpeedMps, BasinS.WhitewaterFoamFactor * 100.0]) + LineEnding +
    Format('| **Peak Flow Speed** | **`%.2f m/s`** (`MeanFoam = %.1f%%`) |', [
      River.PeakFlowSpeedMps, River.MeanFoamFactor * 100.0]);
end;

end.
