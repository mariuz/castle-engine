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

{ Design-time emitter spawning, batch burst/simulation controls, and scene
  particle budget diagnostics for @link(TCastleParticleEmitter) (Phase 289). }
unit ToolParticleStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleTransform, CastleParticles;

type
  { Per-emitter telemetry entry inside @link(TParticleWorldBudgetReport). }
  TParticleEmitterBudgetInfo = record
    Emitter: TCastleParticleEmitter;
    EmitterName: String;
    PresetName: String;
    ShapeName: String;
    ActiveParticles: Integer;
    MaxParticles: Integer;
    SpawnRate: Single;
    PeakTriangles: Integer;
  end;
  TParticleEmitterBudgetInfoArray = array of TParticleEmitterBudgetInfo;

  { Aggregated VFX particle budget report across a live scene/UI design. }
  TParticleWorldBudgetReport = record
    Emitters: TParticleEmitterBudgetInfoArray;
    EmitterCount: Integer;
    TotalActiveParticles: Integer;
    TotalMaxParticles: Integer;
    TotalActiveTriangles: Integer;
    TotalPeakTriangles: Integer;
    OverBudgetWarning: Boolean;
    WarningMessage: String;
  end;

  { Static editor & CLI helper methods for @link(TCastleParticleEmitter). }
  TParticleStudioHelper = class
  public
    const
      RecommendedSceneMaxParticles = 2000;

    { Scan @code(DesignRoot) for all @link(TCastleParticleEmitter) instances
      and compute aggregate active/peak particle & triangle budgets. }
    class function ScanEmittersAndBudget(
      const DesignRoot: TComponent): TParticleWorldBudgetReport; static;

    { Create and mount a new @link(TCastleParticleEmitter) inside the first
      @code(TCastleViewport.Items) or @code(TCastleTransform) root. }
    class function CreateEmitterInDesign(
      const DesignRoot, DesignOwner: TComponent;
      const APreset: TVfxParticlePreset;
      const WorldPos: TVector3): TCastleParticleEmitter; static;

    { Trigger an immediate @code(EmitBurst) across all emitters in @code(DesignRoot). }
    class function TriggerAllBursts(const DesignRoot: TComponent;
      const BurstCount: Integer = 32): Integer; static;

    { Advance all emitters in @code(DesignRoot) by @code(DeltaSec). }
    class procedure StepAllEmitters(const DesignRoot: TComponent;
      const DeltaSec: Single); static;

    { Clear live particles across all emitters in @code(DesignRoot). }
    class procedure ClearAllEmitters(const DesignRoot: TComponent); static;

    { Export @code(Report) as a Markdown budget summary table. }
    class function FormatBudgetMarkdown(
      const Report: TParticleWorldBudgetReport): String; static;
  end;

implementation

uses
  CastleUIControls, CastleControls, CastleViewport, CastleUtils;

procedure CollectEmittersRecursive(const C: TComponent;
  var List: TParticleEmitterBudgetInfoArray);

  procedure AddEmitter(const E: TCastleParticleEmitter);
  var
    I, N: Integer;
    Info: TParticleEmitterBudgetInfo;
  begin
    if (E = nil) or (csTransient in E.ComponentStyle) then
      Exit;
    for I := 0 to High(List) do
      if List[I].Emitter = E then
        Exit;

    Info := Default(TParticleEmitterBudgetInfo);
    Info.Emitter := E;
    if E.Name <> '' then
      Info.EmitterName := E.Name
    else
      Info.EmitterName := E.ClassName;
    Info.PresetName := VfxPresetToString(E.Preset);
    Info.ShapeName := ParticleShapeToString(E.Shape);
    Info.ActiveParticles := E.ActiveParticleCount;
    Info.MaxParticles := E.MaxParticles;
    Info.SpawnRate := E.SpawnRate;
    Info.PeakTriangles := E.MaxParticles * 4;

    N := Length(List);
    SetLength(List, N + 1);
    List[N] := Info;
  end;

var
  I: Integer;
  T: TCastleTransform;
  UI: TCastleUserInterface;
  VP: TCastleViewport;
begin
  if (C = nil) or (csTransient in C.ComponentStyle) then
    Exit;

  if C is TCastleParticleEmitter then
    AddEmitter(TCastleParticleEmitter(C));

  for I := 0 to C.ComponentCount - 1 do
    CollectEmittersRecursive(C.Components[I], List);

  if C is TCastleTransform then
  begin
    T := TCastleTransform(C);
    for I := 0 to T.Count - 1 do
      CollectEmittersRecursive(T[I], List);
  end else
  if C is TCastleUserInterface then
  begin
    if C is TCastleViewport then
    begin
      VP := TCastleViewport(C);
      if VP.Items <> nil then
        CollectEmittersRecursive(VP.Items, List);
    end;
    UI := TCastleUserInterface(C);
    for I := 0 to UI.ControlsCount - 1 do
      CollectEmittersRecursive(UI.Controls[I], List);
  end;
end;

class function TParticleStudioHelper.ScanEmittersAndBudget(
  const DesignRoot: TComponent): TParticleWorldBudgetReport;
var
  I: Integer;
begin
  Result := Default(TParticleWorldBudgetReport);
  CollectEmittersRecursive(DesignRoot, Result.Emitters);
  Result.EmitterCount := Length(Result.Emitters);
  for I := 0 to High(Result.Emitters) do
  begin
    Inc(Result.TotalActiveParticles, Result.Emitters[I].ActiveParticles);
    Inc(Result.TotalMaxParticles, Result.Emitters[I].MaxParticles);
    Inc(Result.TotalActiveTriangles, Result.Emitters[I].Emitter.RenderedTriangleCount);
    Inc(Result.TotalPeakTriangles, Result.Emitters[I].PeakTriangles);
  end;

  if Result.TotalMaxParticles > RecommendedSceneMaxParticles then
  begin
    Result.OverBudgetWarning := true;
    Result.WarningMessage := Format(
      'Peak particle budget (%d) exceeds recommended scene budget (%d). Consider lowering MaxParticles on background emitters.',
      [Result.TotalMaxParticles, RecommendedSceneMaxParticles]);
  end;
end;

function FindParentTransformForEmitter(const C: TComponent): TCastleTransform;
var
  I: Integer;
  UI: TCastleUserInterface;
begin
  Result := nil;
  if C = nil then
    Exit;
  if C is TCastleViewport then
    Exit(TCastleViewport(C).Items);
  if C is TCastleTransform then
    Exit(TCastleTransform(C));
  if C is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(C);
    for I := 0 to UI.ControlsCount - 1 do
    begin
      Result := FindParentTransformForEmitter(UI.Controls[I]);
      if Result <> nil then
        Exit;
    end;
  end;
end;

function ProposeUniqueEmitterName(const AOwner: TComponent;
  const BaseName: String): String;
var
  Idx: Integer;
begin
  if (AOwner = nil) or (AOwner.FindComponent(BaseName) = nil) then
    Exit(BaseName);
  Idx := 1;
  repeat
    Result := BaseName + IntToStr(Idx);
    Inc(Idx);
  until AOwner.FindComponent(Result) = nil;
end;

class function TParticleStudioHelper.CreateEmitterInDesign(
  const DesignRoot, DesignOwner: TComponent;
  const APreset: TVfxParticlePreset;
  const WorldPos: TVector3): TCastleParticleEmitter;
var
  ParentT: TCastleTransform;
  UseOwner: TComponent;
begin
  Result := nil;
  ParentT := FindParentTransformForEmitter(DesignRoot);
  if ParentT = nil then
    Exit;
  if DesignOwner <> nil then
    UseOwner := DesignOwner
  else
    UseOwner := DesignRoot;

  Result := TCastleParticleEmitter.Create(UseOwner);
  Result.Name := ProposeUniqueEmitterName(UseOwner,
    'Particle' + VfxPresetToString(APreset));
  Result.ApplyPreset(APreset);
  Result.Translation := WorldPos;
  ParentT.Add(Result);
end;

class function TParticleStudioHelper.TriggerAllBursts(
  const DesignRoot: TComponent; const BurstCount: Integer): Integer;
var
  Rep: TParticleWorldBudgetReport;
  I: Integer;
begin
  Result := 0;
  Rep := ScanEmittersAndBudget(DesignRoot);
  for I := 0 to High(Rep.Emitters) do
    Inc(Result, Rep.Emitters[I].Emitter.EmitBurst(BurstCount));
end;

class procedure TParticleStudioHelper.StepAllEmitters(
  const DesignRoot: TComponent; const DeltaSec: Single);
var
  Rep: TParticleWorldBudgetReport;
  I: Integer;
begin
  Rep := ScanEmittersAndBudget(DesignRoot);
  for I := 0 to High(Rep.Emitters) do
    Rep.Emitters[I].Emitter.SimulateStep(DeltaSec);
end;

class procedure TParticleStudioHelper.ClearAllEmitters(const DesignRoot: TComponent);
var
  Rep: TParticleWorldBudgetReport;
  I: Integer;
begin
  Rep := ScanEmittersAndBudget(DesignRoot);
  for I := 0 to High(Rep.Emitters) do
    Rep.Emitters[I].Emitter.ClearParticles;
end;

class function TParticleStudioHelper.FormatBudgetMarkdown(
  const Report: TParticleWorldBudgetReport): String;
var
  SB: TStringBuilder;
  I: Integer;
  E: TParticleEmitterBudgetInfo;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('## 3D VFX Particle Budget Report');
    SB.AppendLine(Format('- **Emitters:** %d | **Active Particles:** %d / %d | **Peak Triangles:** %d',
      [Report.EmitterCount, Report.TotalActiveParticles,
       Report.TotalMaxParticles, Report.TotalPeakTriangles]));
    if Report.OverBudgetWarning then
      SB.AppendLine('- **Warning:** ' + Report.WarningMessage);
    SB.AppendLine;
    SB.AppendLine('| Emitter | Preset | Shape | Rate/s | Active / Max | Peak Tris |');
    SB.AppendLine('| :--- | :--- | :--- | ---: | ---: | ---: |');
    for I := 0 to High(Report.Emitters) do
    begin
      E := Report.Emitters[I];
      SB.AppendLine(Format('| `%s` | %s | %s | %.1f | %d / %d | %d |',
        [E.EmitterName, E.PresetName, E.ShapeName, E.SpawnRate,
         E.ActiveParticles, E.MaxParticles, E.PeakTriangles]));
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
