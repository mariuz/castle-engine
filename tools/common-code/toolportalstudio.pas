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

{ Stateless helper for Planar Portal & Seamless Mirror Studio (Phase 377). }
unit ToolPortalStudio;

{$I castleconf.inc}

interface

uses SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastlePortalPair;

type
  TPortalStudioHelper = class
  public
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function FindPrimaryPortal(const Root: TComponent): TCastlePortalGateway;
    class function SpawnLinkedBlueOrangePortalsDemo(const Root, DesignOwner: TComponent;
      out BluePortal, OrangePortal: TCastlePortalGateway): Boolean;
    class function GeneratePortalReport(const Root: TComponent;
      const Portal: TCastlePortalGateway): String;
  end;

implementation

uses CastleUtils;

class function TPortalStudioHelper.FindViewport(const Root: TComponent): TCastleViewport;
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

class function TPortalStudioHelper.FindPrimaryPortal(
  const Root: TComponent): TCastlePortalGateway;

  function WalkTransform(const T: TCastleTransform): TCastlePortalGateway;
  var
    I: Integer;
  begin
    if T is TCastlePortalGateway then
      Exit(TCastlePortalGateway(T));
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
  if Root is TCastlePortalGateway then Exit(TCastlePortalGateway(Root));
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
    if Root.Components[I] is TCastlePortalGateway then
      Exit(TCastlePortalGateway(Root.Components[I]));
end;

class function TPortalStudioHelper.SpawnLinkedBlueOrangePortalsDemo(
  const Root, DesignOwner: TComponent;
  out BluePortal, OrangePortal: TCastlePortalGateway): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
begin
  Result := False;
  BluePortal := nil;
  OrangePortal := nil;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  BluePortal := OwnerComp.FindComponent('PortalBlueEntry') as TCastlePortalGateway;
  if BluePortal = nil then
  begin
    BluePortal := TCastlePortalGateway.Create(OwnerComp);
    BluePortal.Name := 'PortalBlueEntry';
    BluePortal.Preset := ppLinkedBlueOrangePair;
    BluePortal.Translation := Vector3(-6.0, 0.0, 0.0);
    BluePortal.PortalYawDeg := 0.0; // Outward normal +Z
    Vp.Items.Add(BluePortal);
  end;

  OrangePortal := OwnerComp.FindComponent('PortalOrangeExit') as TCastlePortalGateway;
  if OrangePortal = nil then
  begin
    OrangePortal := TCastlePortalGateway.Create(OwnerComp);
    OrangePortal.Name := 'PortalOrangeExit';
    OrangePortal.Preset := ppLinkedBlueOrangePair;
    OrangePortal.Translation := Vector3(12.0, 4.0, -8.0);
    OrangePortal.PortalYawDeg := 90.0; // Outward normal +X (90 deg turn!)
    Vp.Items.Add(OrangePortal);
  end;

  BluePortal.LinkedPortalName := OrangePortal.Name;
  OrangePortal.LinkedPortalName := BluePortal.Name;
  Result := True;
end;

class function TPortalStudioHelper.GeneratePortalReport(const Root: TComponent;
  const Portal: TCastlePortalGateway): String;
var
  Sample: TPortalWarpSample;
begin
  if Portal = nil then
    Exit('# Planar Portal & Seamless Mirror Report' + NL + NL +
      '_No `TCastlePortalGateway` in scene._');

  Sample := Portal.EvaluateVirtualCameraView(Root,
    Portal.Translation + Vector3(0.0, 1.7, 3.0),
    Vector3(0.0, 0.0, -1.0));

  Result :=
    '# Planar Portal & Seamless Mirror Report (Phase 377)' + NL + NL +
    Format('- **Portal**: `%s` %s', [Portal.Name, Portal.PortalSummaryBadge]) + NL +
    Format('- **Aperture**: `%.2f m x %.2f m` | Yaw `%.1f deg` | Max Recursion `%d`', [
      Portal.PortalWidthMeters, Portal.PortalHeightMeters, Portal.PortalYawDeg, Portal.MaxRecursionDepth]) + NL +
    Format('- **Completed Teleports**: `%d` (Cooldown Lockout Remaining: `%.2f s`)', [
      Portal.TeleportCount, Portal.CooldownRemainingSec]) + NL;

  if Sample.ValidTarget then
    Result := Result +
      Format('- **Virtual Camera Eye**: `(%.2f, %.2f, %.2f)` | Dir `(%.2f, %.2f, %.2f)`', [
        Sample.VirtualEyePos.X, Sample.VirtualEyePos.Y, Sample.VirtualEyePos.Z,
        Sample.VirtualViewDir.X, Sample.VirtualViewDir.Y, Sample.VirtualViewDir.Z]) + NL +
      Format('- **Lengyel Oblique Clip Plane**: `(%.3f, %.3f, %.3f, %.3f)`', [
        Sample.ObliqueClipPlane.X, Sample.ObliqueClipPlane.Y,
        Sample.ObliqueClipPlane.Z, Sample.ObliqueClipPlane.W]) + NL;
end;

end.
