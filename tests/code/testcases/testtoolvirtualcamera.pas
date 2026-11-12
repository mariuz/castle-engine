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

{ Automated unit tests for Phase 312 Virtual Camera Priority Blending,
  Spline Dolly Rail, Screen-Space Deadzone Composer & Trauma-Squared Perlin Shake
  (@link(CastleVirtualCamera), @link(ToolVirtualCamera)). }
unit TestToolVirtualCamera;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolVirtualCamera = class(TCastleTestCase)
  published
    procedure TestPriorityArbitrationSmoothStepBlendFovAndSplineDolly;
    procedure TestDeadzoneComposerTraumaSquaredShakeDecayAndJsonRoundtrip;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleViewport, CastleComponentSerialize,
  CastleSplinePath, CastleVirtualCamera, ToolVirtualCamera;

procedure TTestToolVirtualCamera.TestPriorityArbitrationSmoothStepBlendFovAndSplineDolly;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  Subject: TCastleTransform;
  Brain: TCastleVirtualCameraBrain;
  VCamWide, VCamDolly: TCastleVirtualCamera;
  P, D, U: TVector3;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'MainViewport';

    Subject := TCastleTransform.Create(DesignOwner);
    Subject.Name := 'HeroActor';
    Subject.Translation := Vector3(0.0, 1.5, 0.0);
    Vp.Items.Add(Subject);

    Brain := TVirtualCameraHelper.EnsureBrainOnViewportCamera(Vp, DesignOwner, 1.0);
    Brain.BlendCurve := vcbcSmoothStep;

    VCamWide := TVirtualCameraHelper.SpawnFixedEstablishingVCam(
      Vp, DesignOwner, Vector3(0.0, 4.0, 10.0), Subject, 10, 'VCamWide');
    VCamWide.FieldOfViewDeg := 60.0;

    VCamDolly := TVirtualCameraHelper.SpawnSplineDollyVCam(
      Vp, DesignOwner, Subject, 30, 'VCamDolly');
    VCamDolly.FieldOfViewDeg := 40.0;
    VCamDolly.ActiveRig := False;

    { Step 0: VCamWide (Prio 10) wins while VCamDolly is inactive }
    Brain.StepBrain(0.0);
    AssertTrue(Brain.ActiveVirtualCamera = VCamWide);
    AssertFalse(Brain.IsBlending);
    Vp.Camera.GetView(P, D, U);
    AssertVectorEquals(Vector3(0.0, 4.0, 10.0), P, 0.01);
    AssertSameValue(DegToRad(60.0), Vp.Camera.Perspective.FieldOfView, 0.002);

    { Activate VCamDolly (Prio 30 > 10) at DollyNormalizedT = 0.5 -> triggers SmoothStep 1.0s blend }
    VCamDolly.DollyNormalizedT := 0.5;
    VCamDolly.ActiveRig := True;

    Brain.StepBrain(0.5); // Halfway (u = 0.5 -> SmoothStep alpha = 0.5)
    AssertTrue(Brain.ActiveVirtualCamera = VCamDolly);
    AssertTrue(Brain.IsBlending);
    AssertSameValue(DegToRad(50.0), Vp.Camera.Perspective.FieldOfView, 0.01);

    { Finish remaining 0.5s of blend -> snaps onto spline midpoint & 40 deg FOV }
    Brain.StepBrain(0.5);
    AssertFalse(Brain.IsBlending);
    AssertSameValue(DegToRad(40.0), Vp.Camera.Perspective.FieldOfView, 0.002);
    Vp.Camera.GetView(P, D, U);
    AssertTrue(Abs(P.X) < 1.0);
    AssertTrue(P.Y > 3.0);

    { Advance DollyNormalizedT to 1.0 (end of rail at +8.0 X) }
    VCamDolly.DollyNormalizedT := 1.0;
    Brain.StepBrain(0.25);
    Brain.StepBrain(0.50);
    Vp.Camera.GetView(P, D, U);
    AssertTrue(P.X > 6.5);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolVirtualCamera.TestDeadzoneComposerTraumaSquaredShakeDecayAndJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  Vp: TCastleViewport;
  Subject, ReloadedRoot: TCastleTransform;
  VCam: TCastleVirtualCamera;
  Brain: TCastleVirtualCameraBrain;
  InitialPose, InnerPose, OuterPose: TVirtualCameraPose;
  BaseCamPos, ShakenCamPos, DirTmp, UpTmp: TVector3;
  JsonText, Md: String;
  Report: TVirtualCameraAuditReport;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'TestVp';

    Subject := TCastleTransform.Create(DesignOwner);
    Subject.Name := 'PlayerTarget';
    Subject.Translation := Vector3(0.0, 0.0, -10.0);
    Vp.Items.Add(Subject);

    VCam := TCastleVirtualCamera.Create(DesignOwner);
    VCam.Name := 'DeadzoneVCam';
    VCam.SetView(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0));
    VCam.BodyMode := vcbFixedTransform;
    VCam.AimMode := vcaDeadzoneComposer;
    VCam.LookAtTarget := Subject;
    VCam.AimTargetOffset := TVector3.Zero;
    VCam.DeadzoneWidthDeg := 20.0;  // +/- 10 deg horizontal deadzone
    VCam.DeadzoneHeightDeg := 16.0;
    VCam.AimDamping := 0.0;         // Immediate snap outside deadzone for crisp test assertion
    Vp.Items.Add(VCam);

    InitialPose := VCam.StepAndEvaluatePose(0.0);
    AssertVectorEquals(Vector3(0.0, 0.0, -1.0), InitialPose.Direction, 0.001);

    { Small 5 deg lateral movement stays INSIDE the +/- 10 deg deadzone -> camera does NOT pan! }
    Subject.Translation := Vector3(Tan(DegToRad(5.0)) * 10.0, 0.0, -10.0);
    InnerPose := VCam.StepAndEvaluatePose(0.1);
    AssertVectorEquals(Vector3(0.0, 0.0, -1.0), InnerPose.Direction, 0.001);

    { Large 25 deg lateral movement exceeds +/- 10 deg deadzone -> camera pans right (+X) }
    Subject.Translation := Vector3(Tan(DegToRad(25.0)) * 10.0, 0.0, -10.0);
    OuterPose := VCam.StepAndEvaluatePose(0.1);
    AssertTrue(OuterPose.Direction.X > 0.22);

    { Trauma^2 Perlin Shake amplitude & linear trauma decay }
    Brain := TVirtualCameraHelper.EnsureBrainOnViewportCamera(Vp, DesignOwner, 0.5);
    Brain.TraumaDecayPerSec := 1.0;
    Brain.ShakeMaxOffsetMeters := 0.50;
    Brain.ShakeFrequencyHz := 17.3;
    Brain.StepBrain(0.0);
    Vp.Camera.GetView(BaseCamPos, DirTmp, UpTmp);

    Brain.AddTrauma(0.8);
    AssertSameValue(0.8, Brain.Trauma, 0.001);
    Brain.StepBrain(0.25);
    Vp.Camera.GetView(ShakenCamPos, DirTmp, UpTmp);
    AssertSameValue(0.55, Brain.Trauma, 0.001);
    AssertTrue(PointsDistance(BaseCamPos, ShakenCamPos) > 0.001);

    { Decay remaining trauma completely -> returns cleanly to unshaken BasePose }
    Brain.StepBrain(1.0);
    AssertSameValue(0.0, Brain.Trauma, 0.0001);
    Vp.Camera.GetView(ShakenCamPos, DirTmp, UpTmp);
    AssertVectorEquals(BaseCamPos, ShakenCamPos, 0.001);

    { Audit & Markdown + JSON serialization roundtrip }
    Report := TVirtualCameraHelper.ScanDesign(Vp, DesignOwner);
    try
      AssertEquals(1, Length(Report.VCams));
      AssertEquals(1, Length(Report.Brains));
      AssertTrue(Report.WinningVCam = VCam);
    finally
      FreeAndNil(Report);
    end;
    Md := TVirtualCameraHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('DeadzoneVCam', Md) > 0);

    JsonText := ComponentToString(VCam);
    ReloadedRoot := StringToComponent(JsonText, ReloadOwner) as TCastleTransform;
    AssertTrue(ReloadedRoot is TCastleVirtualCamera);
    AssertSameValue(20.0, TCastleVirtualCamera(ReloadedRoot).DeadzoneWidthDeg, 0.01);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolVirtualCamera);
end.
