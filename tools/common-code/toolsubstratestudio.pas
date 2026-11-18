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

{ Stateless helper for Substrate Multi-Slab Layered Material Studio (Phase 367). }
unit ToolSubstrateStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleSubstrateMaterial;

type
  TSubstrateStudioHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindSubstrateInHierarchy(const Root: TComponent): TCastleSubstrateMaterial;
    class function SpawnSubstrateShaderBallDemo(const Root, DesignOwner: TComponent;
      out Mat: TCastleSubstrateMaterial): Boolean;
    class function GenerateSubstrateReport(const Mat: TCastleSubstrateMaterial): String;
  end;

implementation

class function TSubstrateStudioHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TSubstrateStudioHelper.FindSubstrateInHierarchy(const Root: TComponent): TCastleSubstrateMaterial;

  function WalkTransform(const T: TCastleTransform): TCastleSubstrateMaterial;
  var
    I: Integer;
  begin
    if T is TCastleSubstrateMaterial then
      Exit(TCastleSubstrateMaterial(T));
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
  if Root is TCastleSubstrateMaterial then Exit(TCastleSubstrateMaterial(Root));
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
    if Root.Components[I] is TCastleSubstrateMaterial then
      Exit(TCastleSubstrateMaterial(Root.Components[I]));
end;

class function TSubstrateStudioHelper.SpawnSubstrateShaderBallDemo(
  const Root, DesignOwner: TComponent;
  out Mat: TCastleSubstrateMaterial): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  Plinth: TCastleBox;
begin
  Result := False;
  Mat := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('SubstratePlinth') = nil then
  begin
    Plinth := TCastleBox.Create(OwnerComp);
    Plinth.Name := 'SubstratePlinth';
    Plinth.Size := Vector3(3.2, 0.35, 3.2);
    Plinth.Translation := Vector3(0.0, -0.18, 0.0);
    Plinth.Color := Vector4(0.18, 0.19, 0.22, 1.0);
    Vp.Items.Add(Plinth);
  end;

  Mat := FindSubstrateInHierarchy(Root);
  if Mat = nil then
  begin
    Mat := TCastleSubstrateMaterial.Create(OwnerComp);
    Mat.Name := 'SubstrateMaterial1';
    Mat.Translation := Vector3(0.0, 1.30, 0.0);
    Mat.Preset := subpAutomotiveCandyClearCoat;
    Vp.Items.Add(Mat);
  end;
  Result := True;
end;

class function TSubstrateStudioHelper.GenerateSubstrateReport(
  const Mat: TCastleSubstrateMaterial): String;
var
  NormalS, GrazingS: TSubstrateEvalSample;
begin
  if Mat = nil then
    Exit('# Substrate Multi-Slab Material Report' + LineEnding + LineEnding +
         '_No `TCastleSubstrateMaterial` found in design._');

  NormalS := Mat.EvaluateSlabAtCosTheta(1.0);
  GrazingS := Mat.EvaluateSlabAtCosTheta(0.15);

  Result :=
    '# Substrate Multi-Slab Material & Energy Conservation Report (Phase 367)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Preset** | `%s` (%s) |', [Mat.Name, SubstratePresetToString(Mat.Preset)]) + LineEnding +
    Format('| **Clear-Coat Slab** | `Coverage=%.0f%%` / `IOR=%.2f` / `Thickness=%.1f um` / `Rough=%.2f` |', [
      Mat.TopCoatCoverage * 100.0, Mat.TopCoatIor, Mat.TopCoatThicknessMicrons, Mat.TopCoatRoughness]) + LineEnding +
    Format('| **Thin-Film & Velvet Fuzz** | `Film=%.0f nm` / `FuzzCoverage=%.0f%%` |', [
      Mat.ThinFilmNanometers, Mat.FuzzCoverage * 100.0]) + LineEnding +
    Format('| **Normal Incidence (`Cos=1.0`)** | `RGB=(%.3f, %.3f, %.3f)` (`F_coat=%.3f`) |', [
      NormalS.TotalReflectanceRgb.X, NormalS.TotalReflectanceRgb.Y, NormalS.TotalReflectanceRgb.Z,
      NormalS.TopCoatFresnel]) + LineEnding +
    Format('| **Grazing Angle (`Cos=0.15`)** | `RGB=(%.3f, %.3f, %.3f)` (`Fuzz=%.3f`) |', [
      GrazingS.TotalReflectanceRgb.X, GrazingS.TotalReflectanceRgb.Y, GrazingS.TotalReflectanceRgb.Z,
      GrazingS.FuzzRimFactor]) + LineEnding +
    Format('| **Energy Conservation Gate** | **`%s`** (`PeakDirectionalAlbedo = %.3f <= 1.000`) |', [
      BoolToStr(Mat.EnergyConservedAcrossAngles, 'PASS (100% CONSERVED)', 'FAIL'),
      Mat.PeakDirectionalAlbedo]);
end;

end.
