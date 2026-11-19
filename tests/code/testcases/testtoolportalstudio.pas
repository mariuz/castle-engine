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

{ Automated tests for Phase 377 Planar Portal & Seamless Mirror Studio. }
unit TestToolPortalStudio;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Math, CastleTester;

type
  TTestToolPortalStudio = class(TCastleTestCase)
  published
    procedure Test90DegreePortalTurnaroundVelocityRotationAndAntiPingPongCooldown;
    procedure TestPlanarMirrorReflectionObliqueClipPlaneApertureMissAndJsonRoundtrip;
  end;

implementation

uses CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastlePortalPair, ToolPortalStudio;

procedure TTestToolPortalStudio.Test90DegreePortalTurnaroundVelocityRotationAndAntiPingPongCooldown;
var
  RootOwner: TComponent;
  Vp: TCastleViewport;
  BlueP, OrangeP: TCastlePortalGateway;
  WarpedPos, WarpedVel: TVector3;
begin
  RootOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TPortalStudioHelper.SpawnLinkedBlueOrangePortalsDemo(Vp, RootOwner, BlueP, OrangeP));

    { BluePortal at (-6, 0, 0) faces +Z (Yaw=0).
      OrangePortal at (12, 4, -8) faces +X (Yaw=90 deg).
      Actor walks into BluePortal from front (Z = +0.5 -> Z = -0.3) with velocity (0, 0, -8) m/s.
      Must emerge +0.3m in front of OrangePortal (+X -> X = 12.3, Y = 5.0, Z = -8.0)
      with velocity rotated 90 deg out of OrangePortal (+8, 0, 0) m/s! }
    AssertTrue(BlueP.TryCrossPortal(Vp,
      Vector3(-6.0, 1.0, +0.5),
      Vector3(-6.0, 1.0, -0.3),
      Vector3(0.0, 0.0, -8.0),
      WarpedPos, WarpedVel));

    AssertSameValue(12.3, WarpedPos.X, 1e-4);
    AssertSameValue(5.0, WarpedPos.Y, 1e-4);
    AssertSameValue(-8.0, WarpedPos.Z, 1e-4);

    AssertSameValue(8.0, WarpedVel.X, 1e-4);
    AssertSameValue(0.0, WarpedVel.Y, 1e-4);
    AssertSameValue(0.0, WarpedVel.Z, 1e-4);
    AssertEquals(1, BlueP.TeleportCount);

    { Anti-ping-pong cooldown blocks immediate reverse crossing into OrangePortal until cooldown expires }
    AssertFalse('Immediate reverse crossing must be blocked during cooldown lockout',
      OrangeP.TryCrossPortal(Vp,
        Vector3(12.3, 5.0, -8.0),
        Vector3(11.8, 5.0, -8.0),
        Vector3(-8.0, 0.0, 0.0),
        WarpedPos, WarpedVel));

    { Step cooldown past 0.25s -> reverse crossing works cleanly! }
    BlueP.StepPortalCooldown(0.30);
    OrangeP.StepPortalCooldown(0.30);
    AssertTrue(OrangeP.TryCrossPortal(Vp,
      Vector3(12.3, 5.0, -8.0),
      Vector3(11.8, 5.0, -8.0),
      Vector3(-8.0, 0.0, 0.0),
      WarpedPos, WarpedVel));
    AssertSameValue(-6.0, WarpedPos.X, 1e-4);
    AssertSameValue(0.2, WarpedPos.Z, 1e-4);
    AssertSameValue(8.0, WarpedVel.Z, 1e-4);
  finally
    FreeAndNil(RootOwner);
  end;
end;

procedure TTestToolPortalStudio.TestPlanarMirrorReflectionObliqueClipPlaneApertureMissAndJsonRoundtrip;
var
  RootOwner, RestoredOwner: TComponent;
  Vp: TCastleViewport;
  BlueP, OrangeP, MirrorP, Restored: TCastlePortalGateway;
  MirrorSample: TPortalWarpSample;
  WarpedPos, WarpedVel: TVector3;
  JsonStr: String;
begin
  RootOwner := TComponent.Create(nil);
  RestoredOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(RootOwner);
    Vp.Name := 'MainViewport';
    AssertTrue(TPortalStudioHelper.SpawnLinkedBlueOrangePortalsDemo(Vp, RootOwner, BlueP, OrangeP));

    { 1. Segment crossing outside doorway width (X = -6 + 5.0m > 1.2m half-width) must NOT teleport }
    AssertFalse(BlueP.TryCrossPortal(Vp,
      Vector3(-1.0, 1.0, +0.5),
      Vector3(-1.0, 1.0, -0.5),
      Vector3(0.0, 0.0, -5.0),
      WarpedPos, WarpedVel));

    { 2. Planar mirror at Z = 0 facing +Z reflects eye (2, 1.7, 4) -> (2, 1.7, -4) and view (0, 0, -1) -> (0, 0, +1) }
    MirrorP := TCastlePortalGateway.Create(RootOwner);
    MirrorP.Name := 'HallMirror';
    MirrorP.Preset := ppGrandHallPlanarMirror;
    MirrorSample := MirrorP.EvaluateVirtualCameraView(Vp,
      Vector3(2.0, 1.7, 4.0),
      Vector3(0.0, 0.0, -1.0));
    AssertTrue(MirrorSample.ValidTarget);
    AssertSameValue(2.0, MirrorSample.VirtualEyePos.X, 1e-4);
    AssertSameValue(1.7, MirrorSample.VirtualEyePos.Y, 1e-4);
    AssertSameValue(-4.0, MirrorSample.VirtualEyePos.Z, 1e-4);
    AssertSameValue(1.0, MirrorSample.VirtualViewDir.Z, 1e-4);
    AssertSameValue(1.0, MirrorSample.ObliqueClipPlane.Z, 1e-4);

    { 3. Verify csTransient-clean JSON roundtrip }
    JsonStr := ComponentToString(MirrorP);
    AssertEquals('csTransient frame must not serialize into JSON', 0, Pos('PortalFrameTransient', JsonStr));
    Restored := StringToComponent(JsonStr, RestoredOwner) as TCastlePortalGateway;
    AssertTrue(Restored.MirrorMode);
    AssertEquals(Ord(ppGrandHallPlanarMirror), Ord(Restored.Preset));
    AssertSameValue(4.8, Restored.PortalWidthMeters, 1e-3);
  finally
    FreeAndNil(RestoredOwner);
    FreeAndNil(RootOwner);
  end;
end;

initialization
  RegisterTest(TTestToolPortalStudio);
end.
