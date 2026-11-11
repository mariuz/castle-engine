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

{ Automated tests for @link(TCastleParticleEmitter) and
  @link(TParticleStudioHelper) (Phase 289 — UE 5.9 / 6.0 Niagara VFX Parity). }
unit TestToolParticleStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolParticleStudio = class(TCastleTestCase)
  published
    procedure TestParticleShapesPhysicsLifecycleAndTransientJsonRoundtrip;
    procedure TestPresetsBurstCapBudgetDiagnosticsAndMarkdown;
  end;

implementation

uses
  CastleVectors, CastleColors, CastleComponentSerialize,
  CastleTransform, CastleViewport,
  CastleParticles, ToolParticleStudio;

procedure TTestToolParticleStudio.TestParticleShapesPhysicsLifecycleAndTransientJsonRoundtrip;
var
  DesignOwner, ReloadOwner: TComponent;
  Emitter, ReloadedEmitter: TCastleParticleEmitter;
  P: TLiveParticleData;
  I: Integer;
  SerializedJson: String;
  ReloadedComp: TComponent;
begin
  DesignOwner := TComponent.Create(nil);
  ReloadOwner := TComponent.Create(nil);
  try
    Emitter := TCastleParticleEmitter.Create(DesignOwner);
    Emitter.Name := 'CampfireEmitter';

    { 1. CircleRing shape spawns particles on radius R in XZ plane }
    Emitter.Shape := pesCircleRing;
    Emitter.ShapeRadius := 4.0;
    Emitter.Emitting := false;
    Emitter.LifetimeMin := 2.0;
    Emitter.LifetimeMax := 2.0;
    Emitter.SpeedMin := 0.0;
    Emitter.SpeedMax := 0.0;
    Emitter.GravityFactor := 0.0;
    Emitter.Turbulence := 0.0;

    AssertEquals(16, Emitter.EmitBurst(16));
    AssertEquals(16, Emitter.ActiveParticleCount);
    AssertEquals(64, Emitter.RenderedTriangleCount);

    for I := 0 to Emitter.ActiveParticleCount - 1 do
    begin
      P := Emitter.GetLiveParticle(I);
      AssertSameValue(0.0, P.Position.Y, 0.001);
      AssertSameValue(4.0, Sqrt(Sqr(P.Position.X) + Sqr(P.Position.Z)), 0.01);
    end;

    { 2. Downward gravity integration moves particles downward (-Y) }
    Emitter.GravityFactor := 1.0; // -9.81 m/s^2 along Y
    Emitter.Drag := 0.0;
    Emitter.SimulateStep(0.5);
    AssertEquals(16, Emitter.ActiveParticleCount);
    AssertTrue(Emitter.GetLiveParticle(0).Position.Y < -1.0);

    { 3. Advancing past Lifetime (2.0s) expires all burst particles cleanly }
    Emitter.SimulateStep(1.6);
    AssertEquals(0, Emitter.ActiveParticleCount);
    AssertEquals(0, Emitter.RenderedTriangleCount);

    { 4. Continuous SpawnRate accumulation }
    Emitter.Emitting := true;
    Emitter.SpawnRate := 20.0;
    Emitter.SimulateStep(0.5); // 20 * 0.5 = 10 particles
    AssertEquals(10, Emitter.ActiveParticleCount);

    { 5. Serialize while 10 live particles & transient TCastleScene exist ->
         JSON must NOT bake transient render scene as a serialized child! }
    Emitter.ColorStart := Vector4(0.2, 0.9, 0.5, 0.85);
    SerializedJson := ComponentToString(Emitter);
    AssertEquals(0, Pos('TCastleScene', SerializedJson));

    ReloadedComp := StringToComponent(SerializedJson, ReloadOwner);
    AssertTrue(ReloadedComp is TCastleParticleEmitter);
    ReloadedEmitter := TCastleParticleEmitter(ReloadedComp);
    AssertEquals(Ord(pesCircleRing), Ord(ReloadedEmitter.Shape));
    AssertSameValue(4.0, ReloadedEmitter.ShapeRadius, 0.001);
    AssertSameValue(0.9, ReloadedEmitter.ColorStart.Y, 0.001);
    AssertEquals(0, ReloadedEmitter.Count); // zero serialized children
  finally
    FreeAndNil(ReloadOwner);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolParticleStudio.TestPresetsBurstCapBudgetDiagnosticsAndMarkdown;
var
  DesignOwner: TComponent;
  VP: TCastleViewport;
  EFire, EPortal, ESnow: TCastleParticleEmitter;
  Preset: TVfxParticlePreset;
  Rep: TParticleWorldBudgetReport;
  Md: String;
begin
  DesignOwner := TComponent.Create(nil);
  try
    VP := TCastleViewport.Create(DesignOwner);
    VP.Name := 'ViewportMain';

    { Verify all 6 presets configure valid non-degenerate ranges }
    EFire := TParticleStudioHelper.CreateEmitterInDesign(
      VP, DesignOwner, vfxFire, Vector3(0, 1, 0));
    AssertTrue(EFire <> nil);
    for Preset in [vfxFire, vfxSmoke, vfxSparks, vfxMagicPortal, vfxSnowRain, vfxExplosionBurst] do
    begin
      EFire.ApplyPreset(Preset);
      AssertTrue(EFire.MaxParticles > 0);
      AssertTrue(EFire.LifetimeMax >= EFire.LifetimeMin);
      AssertTrue(EFire.SpeedMax >= EFire.SpeedMin);
    end;
    EFire.ApplyPreset(vfxFire);
    EFire.MaxParticles := 30;
    { Burst cap: requesting 100 spawns at most MaxParticles (30) }
    AssertEquals(30, EFire.EmitBurst(100));
    AssertEquals(30, EFire.ActiveParticleCount);

    EPortal := TParticleStudioHelper.CreateEmitterInDesign(
      VP, DesignOwner, vfxMagicPortal, Vector3(5, 1, 0));
    AssertTrue(EPortal <> nil);
    ESnow := TParticleStudioHelper.CreateEmitterInDesign(
      VP, DesignOwner, vfxSnowRain, Vector3(0, 12, 0));
    ESnow.MaxParticles := 2100; // pushes scene peak > 2000 budget threshold

    TParticleStudioHelper.TriggerAllBursts(VP, 15);
    Rep := TParticleStudioHelper.ScanEmittersAndBudget(VP);
    AssertEquals(3, Rep.EmitterCount);
    AssertEquals(30 + 15 + 15, Rep.TotalActiveParticles);
    AssertTrue(Rep.OverBudgetWarning);
    AssertTrue(Rep.TotalPeakTriangles = Rep.TotalMaxParticles * 4);

    Md := TParticleStudioHelper.FormatBudgetMarkdown(Rep);
    AssertTrue(Pos('3D VFX Particle Budget Report', Md) > 0);
    AssertTrue(Pos('MagicPortal', Md) > 0);

    TParticleStudioHelper.ClearAllEmitters(VP);
    Rep := TParticleStudioHelper.ScanEmittersAndBudget(VP);
    AssertEquals(0, Rep.TotalActiveParticles);
  finally
    FreeAndNil(DesignOwner);
  end;
end;

initialization
  RegisterTest(TTestToolParticleStudio);
end.
