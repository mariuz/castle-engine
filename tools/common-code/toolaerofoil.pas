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

{ Stateless helper for Aerodynamic Wing / Sail Foil Polar & Stall Studio (Phase 369). }
unit ToolAeroFoil;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleAeroFoil;

type
  TAeroFoilHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindAeroFoilInHierarchy(const Root: TComponent): TCastleAeroFoilBehavior;
    class function SpawnGliderThermalCanyonDemo(const Root, DesignOwner: TComponent;
      out GliderActor: TCastleTransform;
      out Foil: TCastleAeroFoilBehavior): Boolean;
    class function GenerateAeroReport(const Foil: TCastleAeroFoilBehavior): String;
  end;

implementation

class function TAeroFoilHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TAeroFoilHelper.FindAeroFoilInHierarchy(
  const Root: TComponent): TCastleAeroFoilBehavior;

  function WalkTransform(const T: TCastleTransform): TCastleAeroFoilBehavior;
  var
    I: Integer;
  begin
    Result := T.FindBehavior(TCastleAeroFoilBehavior) as TCastleAeroFoilBehavior;
    if Result <> nil then Exit;
    for I := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[I]);
      if Result <> nil then Exit;
    end;
  end;

var
  Vp: TCastleViewport;
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleAeroFoilBehavior then Exit(TCastleAeroFoilBehavior(Root));
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
    if Root.Components[I] is TCastleAeroFoilBehavior then
      Exit(TCastleAeroFoilBehavior(Root.Components[I]));
end;

class function TAeroFoilHelper.SpawnGliderThermalCanyonDemo(
  const Root, DesignOwner: TComponent;
  out GliderActor: TCastleTransform;
  out Foil: TCastleAeroFoilBehavior): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  GliderBox, ThermalPillar: TCastleBox;
begin
  Result := False;
  GliderActor := nil;
  Foil := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('ThermalColumnMarker') = nil then
  begin
    ThermalPillar := TCastleBox.Create(OwnerComp);
    ThermalPillar.Name := 'ThermalColumnMarker';
    ThermalPillar.Size := Vector3(4.0, 18.0, 4.0);
    ThermalPillar.Translation := Vector3(0.0, 9.0, 0.0);
    ThermalPillar.Color := Vector4(1.0, 0.65, 0.18, 0.25);
    Vp.Items.Add(ThermalPillar);
  end;

  GliderActor := OwnerComp.FindComponent('SoaringGlider1') as TCastleTransform;
  if GliderActor = nil then
  begin
    GliderBox := TCastleBox.Create(OwnerComp);
    GliderBox.Name := 'SoaringGlider1';
    GliderBox.Size := Vector3(7.5, 0.25, 1.4);
    GliderBox.Translation := Vector3(0.0, 12.0, 4.0);
    GliderBox.Color := Vector4(0.24, 0.82, 0.98, 1.0);
    Vp.Items.Add(GliderBox);
    GliderActor := GliderBox;
  end;

  Foil := GliderActor.FindBehavior(TCastleAeroFoilBehavior) as TCastleAeroFoilBehavior;
  if Foil = nil then
  begin
    Foil := TCastleAeroFoilBehavior.Create(OwnerComp);
    Foil.Name := 'AeroFoilBehavior1';
    Foil.Preset := afpHangGliderHighAspectWing;
    GliderActor.AddBehavior(Foil);
  end;
  Result := True;
end;

class function TAeroFoilHelper.GenerateAeroReport(
  const Foil: TCastleAeroFoilBehavior): String;
var
  CruiseP, StallP: TAeroFoilPolarSample;
begin
  if Foil = nil then
    Exit('# Aerodynamic Wing / Sail Foil Polar Report' + LineEnding + LineEnding +
         '_No `TCastleAeroFoilBehavior` found in design._');

  CruiseP := Foil.EvaluatePolarAtAlphaDeg(8.0);
  StallP := Foil.EvaluatePolarAtAlphaDeg(28.0);

  Result :=
    '# Aerodynamic Wing / Sail Foil Polar & Stall Report (Phase 369)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [Foil.Name, AeroPresetToString(Foil.Preset)]) + LineEnding +
    Format('| **Geometry & Mass** | `Area=%.1f m^2` / `AR=%.1f` / `CD0=%.3f` / `Mass=%.0f kg` |', [
      Foil.WingAreaSqM, Foil.AspectRatio, Foil.ParasiticDragCD0, Foil.AirframeMassKg]) + LineEnding +
    Format('| **Critical Stall Gate** | `Alpha_stall = %.1f deg` (`Thermal = +%.1f m/s` inside `R=%.0fm`) |', [
      Foil.CriticalStallAngleDeg, Foil.ThermalUpdraftSpeedMps, Foil.ThermalRadiusMeters]) + LineEnding +
    Format('| **Attached Cruise (`Alpha=8 deg`)** | `CL=%.3f` / `CD=%.3f` / **`L/D = %.1f`** (`Stalled=%s`) |', [
      CruiseP.LiftCoeffCL, CruiseP.DragCoeffCD, CruiseP.LiftToDragRatio,
      BoolToStr(CruiseP.IsStalled, True)]) + LineEnding +
    Format('| **Post-Stall (`Alpha=28 deg`)** | `CL=%.3f` / `CD=%.3f` / **`L/D = %.2f`** (`Stalled=%s`) |', [
      StallP.LiftCoeffCL, StallP.DragCoeffCD, StallP.LiftToDragRatio,
      BoolToStr(StallP.IsStalled, True)]);
end;

end.
