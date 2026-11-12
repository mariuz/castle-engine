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

{ Automated unit tests for Phase 313 Verlet Cloth / Cape / Banner & Catenary
  Rope Soft-Body Wind Simulation (@link(CastleClothRope), @link(ToolClothStudio)). }
unit TestToolClothStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolClothStudio = class(TCastleTestCase)
  published
    procedure TestVerletClothPinningWindDeflectionSphereRepulsionAndJson;
    procedure TestCatenaryRopeSagPendulumSwingStretchRatioAndAudit;
  end;

implementation

uses
  Math,
  CastleVectors, CastleTransform, CastleScene, CastleViewport,
  CastleComponentSerialize, CastleTimeOfDayWeather,
  CastleClothRope, ToolClothStudio;

procedure TTestToolClothStudio.TestVerletClothPinningWindDeflectionSphereRepulsionAndJson;
var
  DesignOwner, ReloadOwner: TComponent;
  Vp: TCastleViewport;
  Cape: TCastleClothSurface;
  ReloadedT: TCastleTransform;
  Sphere: TCastleSphere;
  ToD: TCastleTimeOfDayWeather;
  SphereCenter, PartW, HemMid: TVector3;
  C, R: Integer;
  JsonText: String;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);
    Vp.Name := 'TestVp';

    Cape := TClothStudioHelper.SpawnClothInDesign(
      Vp, DesignOwner, cpHeroShoulderCape, Vector3(0.0, 3.0, 0.0), 'HeroCape');
    Cape.WindVelocity := Vector3(0.0, 0.0, 7.5);
    Cape.GustTurbulence := 0.0;

    SphereCenter := Vector3(0.0, 2.1, -0.35);
    Sphere := TClothStudioHelper.SpawnColliderSphereForCloth(
      Vp, DesignOwner, Cape, SphereCenter, 0.60);
    AssertTrue(Sphere <> nil);

    Cape.StepSimulation(0.80);

    { Top edge row (R = 0) must stay strictly pinned at Y = 3.0, Z = 0.0 }
    for C := 0 to Cape.Cols - 1 do
    begin
      AssertTrue(Cape.IsParticlePinned(C, 0));
      PartW := Cape.GetParticleWorldPos(C, 0);
      AssertSameValue(3.0, PartW.Y, 0.001);
      AssertSameValue(0.0, PartW.Z, 0.001);
    end;

    { Lower hem deflects into +Z wind and every unpinned particle stays outside the 0.60m sphere }
    HemMid := Cape.GetParticleWorldPos(Cape.Cols div 2, Cape.Rows - 1);
    AssertTrue(HemMid.Z > 0.25);
    AssertTrue(Cape.OutputTriangleCount = (Cape.Cols - 1) * (Cape.Rows - 1) * 2);

    for R := 1 to Cape.Rows - 1 do
      for C := 0 to Cape.Cols - 1 do
      begin
        PartW := Cape.GetParticleWorldPos(C, R);
        AssertTrue(PointsDistance(PartW, SphereCenter) >= 0.595);
      end;

    { Weather wind coupling }
    ToD := TCastleTimeOfDayWeather.Create(DesignOwner);
    ToD.Name := 'WeatherCtrl';
    ToD.ApplyPresetWithRecommendedHour(wpRainStorm);
    Vp.Items.Add(ToD);
    Cape.WeatherController := ToD;
    Cape.SyncWithWeather := True;
    AssertTrue(Cape.EffectiveWindWorld.Length > 5.0);

    { Serialization must not bake csTransient FRenderScene children }
    Cape.WeatherController := nil;
    Cape.ColliderTransform := nil;
    JsonText := ComponentToString(Cape);
    AssertEquals(0, Pos('TCastleScene', JsonText));
    ReloadedT := StringToComponent(JsonText, ReloadOwner) as TCastleTransform;
    AssertTrue(ReloadedT is TCastleClothSurface);
    AssertEquals(Cape.Cols, TCastleClothSurface(ReloadedT).Cols);
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolClothStudio.TestCatenaryRopeSagPendulumSwingStretchRatioAndAudit;
var
  DesignOwner: TComponent;
  Vp: TCastleViewport;
  CatRope, PendRope: TCastleVerletRope;
  Report: TClothStudioAuditReport;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    Vp := TCastleViewport.Create(DesignOwner);

    CatRope := TClothStudioHelper.SpawnVerletRopeInDesign(
      Vp, DesignOwner, rpmBothEndsCatenary,
      Vector3(0.0, 4.0, 0.0), Vector3(4.0, 0.0, 0.0), 6.0, 'BridgeCable');
    CatRope.WindVelocity := TVector3.Zero;
    CatRope.SolverIterations := 16;

    { Step 1.5s to catenary sag equilibrium }
    CatRope.StepSimulation(0.5);
    CatRope.StepSimulation(0.5);
    CatRope.StepSimulation(0.5);

    AssertVectorEquals(TVector3.Zero, CatRope.GetNodeLocalPos(0), 0.001);
    AssertVectorEquals(Vector3(4.0, 0.0, 0.0),
      CatRope.GetNodeLocalPos(CatRope.NodeCount - 1), 0.001);
    AssertTrue(CatRope.LowestSagLocalY < -1.10);
    AssertTrue(CatRope.MaxStretchRatio < 1.12);

    { Pendulum rope swings in +X wind }
    PendRope := TClothStudioHelper.SpawnVerletRopeInDesign(
      Vp, DesignOwner, rpmStartOnlyPendulum,
      Vector3(5.0, 5.0, 0.0), Vector3(0.0, -3.0, 0.0), 3.0, 'PendulumCable');
    PendRope.WindVelocity := Vector3(8.0, 0.0, 0.0);
    PendRope.StepSimulation(0.5);
    AssertTrue(PendRope.GetNodeLocalPos(PendRope.NodeCount - 1).X > 0.20);

    { Audit & Markdown report }
    Report := TClothStudioHelper.ScanDesign(Vp, DesignOwner);
    try
      AssertEquals(2, Length(Report.Ropes));
      AssertTrue(Report.TotalTriangles > 200);
    finally
      FreeAndNil(Report);
    end;

    Md := TClothStudioHelper.BuildMarkdownReport(Vp, DesignOwner);
    AssertTrue(Pos('BridgeCable', Md) > 0);
    AssertTrue(Pos('PendulumCable', Md) > 0);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolClothStudio);
end.
