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

{ Stateless helper for Skeletal Footstep Decal & Acoustic Surface Studio (Phase 380). }
unit ToolFootstepDirector;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions,
  CastleViewport, CastleFootstepDirector;

type
  TFootstepDirectorHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindDirectorInHierarchy(const Root: TComponent): TCastleFootstepDirector;
    class function SpawnMultiSurfaceWalkwayDemo(const Root, DesignOwner: TComponent;
      out Director: TCastleFootstepDirector): Boolean;
    class function GenerateFootstepReport(const Director: TCastleFootstepDirector): String;
  end;

implementation

uses CastleUtils;

class function TFootstepDirectorHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TFootstepDirectorHelper.FindDirectorInHierarchy(
  const Root: TComponent): TCastleFootstepDirector;

  function WalkTransform(const T: TCastleTransform): TCastleFootstepDirector;
  var
    I: Integer;
  begin
    if T is TCastleFootstepDirector then
      Exit(TCastleFootstepDirector(T));
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
  if Root is TCastleFootstepDirector then Exit(TCastleFootstepDirector(Root));
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
    if Root.Components[I] is TCastleFootstepDirector then
      Exit(TCastleFootstepDirector(Root.Components[I]));
end;

class function TFootstepDirectorHelper.SpawnMultiSurfaceWalkwayDemo(
  const Root, DesignOwner: TComponent;
  out Director: TCastleFootstepDirector): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;

  procedure EnsureSlab(const SlabName: String; const ZCenter: Single; const Col: TVector4);
  var
    B: TCastleBox;
  begin
    if OwnerComp.FindComponent(SlabName) <> nil then Exit;
    B := TCastleBox.Create(OwnerComp);
    B.Name := SlabName;
    B.Size := Vector3(3.0, 0.30, 4.0);
    B.Translation := Vector3(0.0, -0.15, ZCenter);
    B.Material := pmPhysical;
    B.Color := Col;
    Vp.Items.Add(B);
  end;

begin
  Result := False;
  Director := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  EnsureSlab('WalkwaySnowSlab', 2.0, Vector4(0.90, 0.95, 1.0, 1.0));
  EnsureSlab('WalkwayPuddleSlab', 6.0, Vector4(0.20, 0.55, 0.85, 1.0));
  EnsureSlab('WalkwayMetalGratingSlab', 10.0, Vector4(0.55, 0.58, 0.62, 1.0));

  Director := FindDirectorInHierarchy(Root);
  if Director = nil then
  begin
    Director := TCastleFootstepDirector.Create(OwnerComp);
    Director.Name := 'FootstepDirector1';
    Director.Preset := fdpArmoredKnightMarch;
    Vp.Items.Add(Director);
  end;
  Result := True;
end;

class function TFootstepDirectorHelper.GenerateFootstepReport(
  const Director: TCastleFootstepDirector): String;
var
  Last: TFootprintDecalEntry;
begin
  if Director = nil then
    Exit('# Skeletal Footstep & Surface Decal Report' + NL + NL +
      '_No `TCastleFootstepDirector` in scene._');

  Last := Director.LastFootstep;
  Result :=
    '# Skeletal Footstep Decal & Acoustic Surface Report (Phase 380)' + NL + NL +
    Format('- **Director**: `%s` %s', [Director.Name, Director.FootstepSummaryBadge]) + NL +
    Format('- **Gait Parameters**: Stride `%.2f m` | Stance Width `%.2f m` | Armor Mult `%.2fx` | Phase `%.2f`', [
      Director.StrideLengthMeters, Director.StanceWidthMeters,
      Director.ArmorWeightAcousticMult, Director.GaitPhase01]) + NL +
    Format('- **Last Strike**: `%s` on **`%s`** — Acoustic Gain `%.0f%%`, Splash/Dust Particles `%d`', [
      BoolToStr(Last.FootSide = fsLeftFoot, 'LEFT_BOOT', 'RIGHT_BOOT'),
      TCastleFootstepDirector.SurfaceMaterialName(Last.SurfaceMaterial),
      Last.AcousticGain01 * 100.0, Last.ParticleCount]) + NL;
end;

end.
