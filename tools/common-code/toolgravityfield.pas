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

{ Design-time helper for Dynamic Gravity Well, Planetary Walk & Tube Studio (Phase 381). }
unit ToolGravityField;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleViewport, CastleTransform, CastleGravityField;

type
  TGravityStudioSummary = record
    FieldCount: Integer;
    PlanetCount: Integer;
    TubeCount: Integer;
    BoxZoneCount: Integer;
    HighestPriority: Integer;
  end;

  TGravityFieldHelper = class
  public
    class function FindFirstGravityField(const ARoot: TComponent): TCastleGravityField;
    class function SpawnPlanetoidAndInversionDemo(const ADesignRoot, ADesignOwner: TComponent;
      out APlanetField, AInversionZone: TCastleGravityField): Boolean;
    class function CollectSummary(const ADesignRoot: TComponent): TGravityStudioSummary;
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

class function TGravityFieldHelper.FindFirstGravityField(
  const ARoot: TComponent): TCastleGravityField;
var
  I: Integer;
  T: TCastleTransform;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if (ARoot is TCastleGravityField) and (not (csTransient in ARoot.ComponentStyle)) then
    Exit(TCastleGravityField(ARoot));
  if ARoot is TCastleTransform then
  begin
    T := TCastleTransform(ARoot);
    for I := 0 to T.Count - 1 do
    begin
      Result := FindFirstGravityField(T[I]);
      if Result <> nil then Exit;
    end;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindFirstGravityField(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TGravityFieldHelper.SpawnPlanetoidAndInversionDemo(
  const ADesignRoot, ADesignOwner: TComponent;
  out APlanetField, AInversionZone: TCastleGravityField): Boolean;
var
  Vp: TCastleViewport;
  OwnerToUse: TComponent;
begin
  APlanetField := nil;
  AInversionZone := nil;
  Vp := FindViewport(ADesignRoot);
  if Vp = nil then Exit(False);
  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := Vp;

  APlanetField := TCastleGravityField.Create(OwnerToUse);
  APlanetField.Name := 'PlanetoidAttractorCore';
  APlanetField.ApplyPreset(gfpMarioPlanetoidWalk);
  APlanetField.Translation := Vector3(0, 0, 0);
  Vp.Items.Add(APlanetField);

  AInversionZone := TCastleGravityField.Create(OwnerToUse);
  AInversionZone.Name := 'CorridorCeilingInversion';
  AInversionZone.ApplyPreset(gfpZeroGCorridorInversion);
  AInversionZone.Translation := Vector3(28.0, 4.0, 0.0);
  Vp.Items.Add(AInversionZone);

  Result := True;
end;

class function TGravityFieldHelper.CollectSummary(
  const ADesignRoot: TComponent): TGravityStudioSummary;

  procedure Scan(const ANode: TComponent);
  var
    I: Integer;
    F: TCastleGravityField;
    T: TCastleTransform;
  begin
    if ANode = nil then Exit;
    if (ANode is TCastleGravityField) and (not (csTransient in ANode.ComponentStyle)) then
    begin
      F := TCastleGravityField(ANode);
      Inc(Result.FieldCount);
      case F.ShapeKind of
        gskSphericalPlanet: Inc(Result.PlanetCount);
        gskHollowCylinderInterior: Inc(Result.TubeCount);
        gskDirectionalBoxZone: Inc(Result.BoxZoneCount);
      end;
      if (Result.FieldCount = 1) or (F.Priority > Result.HighestPriority) then
        Result.HighestPriority := F.Priority;
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
  Result := Default(TGravityStudioSummary);
  Scan(ADesignRoot);
end;

class function TGravityFieldHelper.BuildMarkdownReport(
  const ADesignRoot: TComponent): String;
var
  Sum: TGravityStudioSummary;
  NorthS, SouthS, InvS: TGravitySample;
begin
  Sum := CollectSummary(ADesignRoot);
  NorthS := TCastleGravityField.EvaluateCompositeWorldGravity(ADesignRoot, Vector3(0, 8.0, 0));
  SouthS := TCastleGravityField.EvaluateCompositeWorldGravity(ADesignRoot, Vector3(0, -8.0, 0));
  InvS := TCastleGravityField.EvaluateCompositeWorldGravity(ADesignRoot, Vector3(28.0, 4.0, 0));

  Result :=
    '# Dynamic Gravity Well & Planetary Walk Report (Phase 381)' + NL + NL +
    Format('- **Total Gravity Fields**: `%d` (`%d` Planets, `%d` Ringworld Tubes, `%d` Box Zones)' + NL,
      [Sum.FieldCount, Sum.PlanetCount, Sum.TubeCount, Sum.BoxZoneCount]) +
    Format('- **Highest Priority Layer**: `%d`' + NL, [Sum.HighestPriority]) +
    Format('- **North Pole Probe `(0, +8, 0)`**: `Up = (%0.2f, %0.2f, %0.2f)` | `g = %0.2f m/s^2`' + NL,
      [NorthS.UpVector.X, NorthS.UpVector.Y, NorthS.UpVector.Z, NorthS.AccelMagnitudeMps2]) +
    Format('- **South Pole Probe `(0, -8, 0)`**: `Up = (%0.2f, %0.2f, %0.2f)` | `g = %0.2f m/s^2`' + NL,
      [SouthS.UpVector.X, SouthS.UpVector.Y, SouthS.UpVector.Z, SouthS.AccelMagnitudeMps2]) +
    Format('- **Corridor Probe `(28, +4, 0)`**: `Up = (%0.2f, %0.2f, %0.2f)` | `Priority = %d`' + NL,
      [InvS.UpVector.X, InvS.UpVector.Y, InvS.UpVector.Z, InvS.SourcePriority]);
end;

end.
