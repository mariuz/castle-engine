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

{ Stateless helper for Mutable Modular Character Customizer Studio (Phase 360). }
unit ToolMutableStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleMutableCharacter;

type
  TMutableStudioHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindMutableInHierarchy(const Root: TComponent): TCastleMutableCharacter;
    class function SpawnMutableTurntablePedestal(const Root, DesignOwner: TComponent;
      out Hero: TCastleMutableCharacter): Boolean;
    class function GenerateMutableReport(const Hero: TCastleMutableCharacter): String;
  end;

implementation

class function TMutableStudioHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TMutableStudioHelper.FindMutableInHierarchy(const Root: TComponent): TCastleMutableCharacter;

  function WalkTransform(const T: TCastleTransform): TCastleMutableCharacter;
  var
    I: Integer;
  begin
    if T is TCastleMutableCharacter then
      Exit(TCastleMutableCharacter(T));
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
  if Root is TCastleMutableCharacter then Exit(TCastleMutableCharacter(Root));
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
    if Root.Components[I] is TCastleMutableCharacter then
      Exit(TCastleMutableCharacter(Root.Components[I]));
end;

class function TMutableStudioHelper.SpawnMutableTurntablePedestal(const Root, DesignOwner: TComponent;
  out Hero: TCastleMutableCharacter): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  Pedestal: TCastleCylinder;
begin
  Result := False;
  Hero := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  if OwnerComp.FindComponent('MutablePedestalDisk') = nil then
  begin
    Pedestal := TCastleCylinder.Create(OwnerComp);
    Pedestal.Name := 'MutablePedestalDisk';
    Pedestal.Radius := 1.4;
    Pedestal.Height := 0.20;
    Pedestal.Translation := Vector3(0.0, -0.10, 0.0);
    Pedestal.Color := Vector4(0.28, 0.30, 0.35, 1.0);
    Vp.Items.Add(Pedestal);
  end;

  Hero := FindMutableInHierarchy(Root);
  if Hero = nil then
  begin
    Hero := TCastleMutableCharacter.Create(OwnerComp);
    Hero.Name := 'MutableHeroCharacter1';
    Hero.Preset := mapPaladinPlateKnight;
    Vp.Items.Add(Hero);
  end;
  Result := True;
end;

class function TMutableStudioHelper.GenerateMutableReport(const Hero: TCastleMutableCharacter): String;
begin
  if Hero = nil then
    Exit('# Mutable Modular Character Customizer Report' + LineEnding + LineEnding +
         '_No `TCastleMutableCharacter` found in design._');

  Result :=
    '# Mutable Modular Character Customizer Report (Phase 360)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Component & Archetype** | `%s` (%s) |', [Hero.Name, MutablePresetToString(Hero.Preset)]) + LineEnding +
    Format('| **Shareable Recipe Code** | **`%s`** |', [Hero.ExportRecipeCode]) + LineEnding +
    Format('| **Merged Single-Draw Mesh** | `%d` modular parts -> `%d` triangles (`1` draw call) |', [
      Hero.MergedPartCount, Hero.GeneratedTriangleCount]) + LineEnding +
    Format('| **Helm vs. Hair Exclusion** | `Headgear=%d` / `Hair=%d` -> **`%s`** |', [
      Hero.HeadgearSlot, Hero.HairStyleSlot,
      BoolToStr(Hero.IsHairAutoHiddenByHelm, 'AUTO-HIDDEN (Closed Helm)', 'VISIBLE')]) + LineEnding +
    Format('| **Parametric Morphs** | `Height = %.2fx` (`%.2fm`), `ShoulderSpan = %.2fm`, `Build = %.2f` |', [
      Hero.HeightScale, Hero.TotalBoundsHeightMeters, Hero.ShoulderSpanMeters, Hero.BuildMuscularityMorph]);
end;

end.
