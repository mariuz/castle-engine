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

{ Static & live scene frame-budget profiler (@link(TFrameBudgetProfiler))
  auditing draw calls, triangles, texture VRAM, punctual/shadow lights,
  particle budgets, foliage instances, and audio sources against 60 Hz hardware
  budgets (`Mobile`, `Handheld`, `Desktop`, `WebAssembly`), ranking top heavy
  offenders, and applying 5-tier @link(TCastleScalabilityManager) quality
  profiles (Phase 306). }
unit ToolFrameProfiler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  CastleClassUtils, CastleScalability;

type
  { Ranked heavy component offender entry in a @link(TFrameBudgetAuditReport). }
  TSceneOffenderEntry = record
    ComponentName: String;
    ClassNameText: String;
    Category: String;
    EstimatedDrawCalls: Integer;
    EstimatedTriangles: Int64;
    EstimatedVramBytes: Int64;
    CostScore: Single;
    Note: String;
  end;
  TSceneOffenderEntryArray = array of TSceneOffenderEntry;

  { Complete 60 Hz hardware frame-budget audit snapshot for a design hierarchy. }
  TFrameBudgetAuditReport = record
    TargetPlatform: TPlatformBudgetProfile;
    BudgetSpec: TPlatformFrameBudgetSpec;
    ActiveScalabilityManager: TCastleScalabilityManager;

    RawUnbatchedDrawCalls: Integer;
    EstimatedDrawCalls: Integer;
    EstimatedTriangles: Int64;
    EstimatedTextureVramBytes: Int64;
    EstimatedTextureVramMB: Single;
    PunctualLightsCount: Integer;
    ShadowCastingLightsCount: Integer;
    ActiveParticleBudget: Integer;
    FoliageInstancesCount: Integer;
    AudioSourcesCount: Integer;
    EstimatedGpuFrameMs: Single;

    OverallPassBudget: Boolean;
    RecommendedTier: TScalabilityTier;
    TopOffenders: TSceneOffenderEntryArray;
    BudgetViolations: array of String;
  end;

  { Stateless scene profiler & scalability helper for Castle Game Engine Editor. }
  TFrameBudgetProfiler = class
  public
    class function AuditHierarchy(
      const ARoot: TComponent;
      const APlatform: TPlatformBudgetProfile): TFrameBudgetAuditReport;

    class function EnsureScalabilityManagerInDesign(
      const ARoot, ADesignOwner: TComponent): TCastleScalabilityManager;

    class function ApplyScalabilityTierToDesign(
      const ARoot, ADesignOwner: TComponent;
      const ATier: TScalabilityTier): Integer;

    class function BuildMarkdownReport(
      const ARoot: TComponent;
      const APlatform: TPlatformBudgetProfile): String;
  end;

implementation

uses
  Math, CastleUtils, CastleUriUtils, CastleFilesUtils,
  CastleTransform, CastleUiControls, CastleControls, CastleViewport,
  CastleScene, CastleBehaviors, CastleSoundEngine, CastleParticles, CastleFoliageBiome,
  CastlePostProcessVolume, CastleDecalProjector;

function ProposeUniqueScalabilityName(const AOwner: TComponent;
  const ABaseName: String): String;
var
  Idx: Integer;
begin
  Result := ABaseName;
  if AOwner = nil then
    Exit;
  Idx := 1;
  while AOwner.FindComponent(Result) <> nil do
  begin
    Inc(Idx);
    Result := ABaseName + IntToStr(Idx);
  end;
end;

function EstimateUrlVramBytes(const AUrl: String): Int64;
var
  Fn, Ext: String;
  SR: TSearchRec;
begin
  Result := 0;
  if AUrl = '' then
    Exit;
  Fn := UriToFilenameSafe(AUrl);
  if (Fn <> '') and (FindFirst(Fn, faAnyFile, SR) = 0) then
  begin
    try
      Ext := LowerCase(ExtractFileExt(Fn));
      if (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.webp') then
        { Compressed PNG/JPG expands ~5x in uncompressed RGBA8 + mipmaps VRAM }
        Result := Max(Int64(65536), Int64(SR.Size) * 5)
      else
        Result := Max(Int64(32768), Int64(SR.Size) * 2);
    finally
      SysUtils.FindClose(SR);
    end;
  end else
    Result := 512 * 1024; { Conservative 512 KB placeholder estimate }
end;

{ TFrameBudgetProfiler ------------------------------------------------------- }

class function TFrameBudgetProfiler.AuditHierarchy(
  const ARoot: TComponent;
  const APlatform: TPlatformBudgetProfile): TFrameBudgetAuditReport;
var
  HasDynamicBatching: Boolean;
  BatchablePrimitiveCount: Integer;

  procedure AddOffender(const AName, AClass, ACat: String;
    const ADraws: Integer; const ATris, AVram: Int64;
    const AScore: Single; const ANote: String);
  var
    N: Integer;
  begin
    N := Length(Result.TopOffenders);
    SetLength(Result.TopOffenders, N + 1);
    Result.TopOffenders[N].ComponentName := AName;
    Result.TopOffenders[N].ClassNameText := AClass;
    Result.TopOffenders[N].Category := ACat;
    Result.TopOffenders[N].EstimatedDrawCalls := ADraws;
    Result.TopOffenders[N].EstimatedTriangles := ATris;
    Result.TopOffenders[N].EstimatedVramBytes := AVram;
    Result.TopOffenders[N].CostScore := AScore;
    Result.TopOffenders[N].Note := ANote;
  end;

  procedure AddViolation(const S: String);
  var
    N: Integer;
  begin
    N := Length(Result.BudgetViolations);
    SetLength(Result.BudgetViolations, N + 1);
    Result.BudgetViolations[N] := S;
  end;

  procedure Visit(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    Vp: TCastleViewport;
    Sc: TCastleScene;
    Light: TCastlePunctualLight;
    Part: TCastleParticleEmitter;
    Biome: TCastleFoliageBiomeVolume;
    Decal: TCastleDecalProjector;
    PpVol: TCastlePostProcessVolume;
    ImgCtrl: TCastleImageControl;
    Tris, Vram: Int64;
    Draws: Integer;
  begin
    if C = nil then
      Exit;

    if C is TCastleScalabilityManager then
    begin
      if Result.ActiveScalabilityManager = nil then
        Result.ActiveScalabilityManager := TCastleScalabilityManager(C);
      Exit;
    end;

    for I := 0 to C.ComponentCount - 1 do
      if C.Components[I] is TCastleScalabilityManager then
        if Result.ActiveScalabilityManager = nil then
          Result.ActiveScalabilityManager := TCastleScalabilityManager(C.Components[I]);

    if C is TCastleViewport then
    begin
      Vp := TCastleViewport(C);
      if not Vp.Exists then
        Exit;
      if Vp.DynamicBatching then
        HasDynamicBatching := true;
      for I := 0 to Vp.NonVisualComponentsCount - 1 do
        Visit(Vp.NonVisualComponents[I]);
      Visit(Vp.Items);
      for I := 0 to Vp.ControlsCount - 1 do
        Visit(Vp.Controls[I]);
      Exit;
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      if (not T.Exists) or (csTransient in T.ComponentStyle) then
        Exit;

      for I := 0 to T.NonVisualComponentsCount - 1 do
        Visit(T.NonVisualComponents[I]);

      for I := 0 to T.BehaviorsCount - 1 do
        if T.Behaviors[I] is TCastleSoundSource then
          Inc(Result.AudioSourcesCount);

      if T is TCastlePunctualLight then
      begin
        Light := TCastlePunctualLight(T);
        Inc(Result.PunctualLightsCount);
        if Light.Shadows then
        begin
          Inc(Result.ShadowCastingLightsCount);
          AddOffender(Light.Name, Light.ClassName, 'Shadow Light',
            12, 0, 4 * 1024 * 1024, 45.0, 'Shadow-casting punctual light pass');
        end;
      end else
      if T is TCastleParticleEmitter then
      begin
        Part := TCastleParticleEmitter(T);
        if Part.Emitting then
        begin
          Inc(Result.RawUnbatchedDrawCalls, 1);
          Tris := Part.MaxParticles * 4;
          Inc(Result.EstimatedTriangles, Tris);
          Inc(Result.ActiveParticleBudget, Part.MaxParticles);
          AddOffender(Part.Name, Part.ClassName, 'VFX Particles',
            1, Tris, 256 * 1024, Part.MaxParticles * 0.08,
            Format('%d max particles (%.0f/s)', [Part.MaxParticles, Part.SpawnRate]));
        end;
      end else
      if T is TCastleFoliageBiomeVolume then
      begin
        Biome := TCastleFoliageBiomeVolume(T);
        Inc(Result.FoliageInstancesCount, Max(Biome.GeneratedInstanceCount, Biome.TargetInstanceCount));
      end else
      if T is TCastleDecalProjector then
      begin
        Decal := TCastleDecalProjector(T);
        Tris := Sqr(Decal.GridResolution) * 2;
        Vram := EstimateUrlVramBytes(Decal.TextureUrl);
        Inc(Result.RawUnbatchedDrawCalls, 1);
        Inc(Result.EstimatedTriangles, Tris);
        Inc(Result.EstimatedTextureVramBytes, Vram);
      end else
      if T is TCastlePostProcessVolume then
      begin
        PpVol := TCastlePostProcessVolume(T);
        if PpVol.VolumeEnabled then
        begin
          Inc(Result.RawUnbatchedDrawCalls, 1);
          AddOffender(PpVol.Name, PpVol.ClassName, 'Post-Process',
            1, 2, 8 * 1024 * 1024,
            12.0 + IfThen(PpVol.ChromaticAberrationPx > 0.01, 8.0, 0.0),
            'Full-screen color-grading pass');
        end;
      end else
      if T is TCastleScene then
      begin
        Sc := TCastleScene(T);
        if Sc.Visible then
        begin
          Tris := Max(Int64(12), Int64(Sc.TrianglesCount));
          Vram := EstimateUrlVramBytes(Sc.Url);
          Draws := Max(1, Integer(Tris div 8000) + 1);
          Inc(Result.RawUnbatchedDrawCalls, Draws);
          Inc(Result.EstimatedTriangles, Tris);
          Inc(Result.EstimatedTextureVramBytes, Vram);
          AddOffender(Sc.Name, Sc.ClassName, '3D Mesh Scene',
            Draws, Tris, Vram,
            Draws * 2.5 + (Tris / 5000.0) + (Vram / (1024.0 * 1024.0)),
            Sc.Url);
        end;
      end else
      if T is TCastleAbstractPrimitive then
      begin
        if T.Visible then
        begin
          if T is TCastleBox then Tris := 12
          else if T is TCastlePlane then Tris := 2
          else Tris := 128;
          Inc(Result.RawUnbatchedDrawCalls, 1);
          Inc(BatchablePrimitiveCount);
          Inc(Result.EstimatedTriangles, Tris);
        end;
      end;

      for I := 0 to T.Count - 1 do
        Visit(T[I]);
      Exit;
    end;

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      if not UI.Exists then
        Exit;
      for I := 0 to UI.NonVisualComponentsCount - 1 do
        Visit(UI.NonVisualComponents[I]);
      if UI is TCastleImageControl then
      begin
        ImgCtrl := TCastleImageControl(UI);
        Vram := EstimateUrlVramBytes(ImgCtrl.Url);
        Inc(Result.RawUnbatchedDrawCalls, 1);
        Inc(Result.EstimatedTriangles, 2);
        Inc(Result.EstimatedTextureVramBytes, Vram);
      end;
      for I := 0 to UI.ControlsCount - 1 do
        Visit(UI.Controls[I]);
    end;
  end;

var
  I, J, BatchedSavings: Integer;
  Tmp: TSceneOffenderEntry;
  MaxRatio: Single;
begin
  Result := Default(TFrameBudgetAuditReport);
  Result.TargetPlatform := APlatform;
  Result.BudgetSpec := GetPlatformFrameBudgetSpec(APlatform);
  HasDynamicBatching := false;
  BatchablePrimitiveCount := 0;

  Visit(ARoot);

  if HasDynamicBatching and (BatchablePrimitiveCount > 2) then
    BatchedSavings := Round(BatchablePrimitiveCount * 0.70)
  else
    BatchedSavings := 0;

  Result.EstimatedDrawCalls := Max(0,
    Result.RawUnbatchedDrawCalls - BatchedSavings + Result.ShadowCastingLightsCount * 8);
  Result.EstimatedTextureVramMB :=
    Result.EstimatedTextureVramBytes / (1024.0 * 1024.0);

  { Estimate GPU frame cost in ms relative to platform ceilings }
  Result.EstimatedGpuFrameMs :=
    2.2 +
    (Result.EstimatedDrawCalls / Max(1, Result.BudgetSpec.MaxDrawCalls)) * 5.2 +
    (Result.EstimatedTriangles / Max(1, Result.BudgetSpec.MaxTriangles)) * 4.0 +
    (Result.ShadowCastingLightsCount / Max(1, Result.BudgetSpec.MaxShadowLights)) * 3.2 +
    (Result.ActiveParticleBudget / Max(1, Result.BudgetSpec.MaxActiveParticles)) * 2.0;

  if Result.EstimatedDrawCalls > Result.BudgetSpec.MaxDrawCalls then
    AddViolation(Format('Draw calls (%d) exceed %s budget (%d).',
      [Result.EstimatedDrawCalls, PlatformBudgetDisplayName(APlatform), Result.BudgetSpec.MaxDrawCalls]));
  if Result.EstimatedTriangles > Result.BudgetSpec.MaxTriangles then
    AddViolation(Format('Triangles (%d) exceed %s budget (%d).',
      [Result.EstimatedTriangles, PlatformBudgetDisplayName(APlatform), Result.BudgetSpec.MaxTriangles]));
  if Result.EstimatedTextureVramMB > Result.BudgetSpec.MaxTextureVramMB then
    AddViolation(Format('Estimated VRAM (%.1f MB) exceeds %s budget (%.0f MB).',
      [Result.EstimatedTextureVramMB, PlatformBudgetDisplayName(APlatform), Result.BudgetSpec.MaxTextureVramMB]));
  if Result.ShadowCastingLightsCount > Result.BudgetSpec.MaxShadowLights then
    AddViolation(Format('Shadow-casting lights (%d) exceed %s budget (%d).',
      [Result.ShadowCastingLightsCount, PlatformBudgetDisplayName(APlatform), Result.BudgetSpec.MaxShadowLights]));
  if Result.ActiveParticleBudget > Result.BudgetSpec.MaxActiveParticles then
    AddViolation(Format('Active particle budget (%d) exceeds %s cap (%d).',
      [Result.ActiveParticleBudget, PlatformBudgetDisplayName(APlatform), Result.BudgetSpec.MaxActiveParticles]));
  if Result.AudioSourcesCount > Result.BudgetSpec.MaxAudioSources then
    AddViolation(Format('Spatial audio sources (%d) exceed %s cap (%d).',
      [Result.AudioSourcesCount, PlatformBudgetDisplayName(APlatform), Result.BudgetSpec.MaxAudioSources]));

  Result.OverallPassBudget := Length(Result.BudgetViolations) = 0;

  { Sort TopOffenders descending by CostScore }
  for I := 0 to High(Result.TopOffenders) - 1 do
    for J := I + 1 to High(Result.TopOffenders) do
      if Result.TopOffenders[J].CostScore > Result.TopOffenders[I].CostScore then
      begin
        Tmp := Result.TopOffenders[I];
        Result.TopOffenders[I] := Result.TopOffenders[J];
        Result.TopOffenders[J] := Tmp;
      end;

  MaxRatio := Max(
    Max(Result.EstimatedDrawCalls / Max(1, Result.BudgetSpec.MaxDrawCalls),
        Result.ShadowCastingLightsCount / Max(1, Result.BudgetSpec.MaxShadowLights)),
    Result.ActiveParticleBudget / Max(1, Result.BudgetSpec.MaxActiveParticles));

  if MaxRatio > 1.75 then
    Result.RecommendedTier := stLow
  else if MaxRatio > 1.00 then
    Result.RecommendedTier := stMedium
  else if MaxRatio > 0.60 then
    Result.RecommendedTier := stHigh
  else if MaxRatio > 0.30 then
    Result.RecommendedTier := stEpic
  else
    Result.RecommendedTier := stCinematic;
end;

class function TFrameBudgetProfiler.EnsureScalabilityManagerInDesign(
  const ARoot, ADesignOwner: TComponent): TCastleScalabilityManager;
var
  Rep: TFrameBudgetAuditReport;
begin
  Result := nil;
  if ARoot = nil then
    Exit;
  Rep := AuditHierarchy(ARoot, pbpDesktop60Hz);
  if Rep.ActiveScalabilityManager <> nil then
    Exit(Rep.ActiveScalabilityManager);

  Result := TCastleScalabilityManager.Create(ADesignOwner);
  Result.Name := ProposeUniqueScalabilityName(ADesignOwner, 'ScalabilityManager');
  if ARoot is TCastleUserInterface then
    TCastleUserInterface(ARoot).AddNonVisualComponent(Result)
  else if ARoot is TCastleTransform then
    TCastleTransform(ARoot).AddNonVisualComponent(Result);
end;

class function TFrameBudgetProfiler.ApplyScalabilityTierToDesign(
  const ARoot, ADesignOwner: TComponent;
  const ATier: TScalabilityTier): Integer;
var
  Mgr: TCastleScalabilityManager;
begin
  Mgr := EnsureScalabilityManagerInDesign(ARoot, ADesignOwner);
  if Mgr <> nil then
    Result := Mgr.ApplyTierToHierarchy(ARoot, ATier)
  else
    Result := 0;
end;

class function TFrameBudgetProfiler.BuildMarkdownReport(
  const ARoot: TComponent;
  const APlatform: TPlatformBudgetProfile): String;
var
  Rep: TFrameBudgetAuditReport;
  SB: TStringBuilder;
  I, CapCount: Integer;
begin
  Rep := AuditHierarchy(ARoot, APlatform);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Real-Time Frame Budget & Scalability Audit Report');
    SB.AppendLine('');
    SB.AppendLine(Format('- **Target Hardware Envelope**: `%s` (Target: `%.2f ms`)',
      [PlatformBudgetDisplayName(APlatform), Rep.BudgetSpec.TargetFrameTimeMs]));
    SB.AppendLine(Format('- **Estimated GPU Frame Cost**: `%.2f ms` (%s)',
      [Rep.EstimatedGpuFrameMs, BoolToStr(Rep.OverallPassBudget, 'PASS', 'OVER BUDGET')]));
    SB.AppendLine(Format('- **Recommended Scalability Tier**: `%s`',
      [ScalabilityTierDisplayName(Rep.RecommendedTier)]));
    SB.AppendLine('');
    SB.AppendLine('## Category Budget Utilization');
    SB.AppendLine('| Metric | Scene Actual | Platform Budget | Utilization |');
    SB.AppendLine('| :--- | :---: | :---: | :---: |');
    SB.AppendLine(Format('| Draw Calls | %d | %d | %.0f%% |',
      [Rep.EstimatedDrawCalls, Rep.BudgetSpec.MaxDrawCalls,
       (Rep.EstimatedDrawCalls / Max(1, Rep.BudgetSpec.MaxDrawCalls)) * 100.0]));
    SB.AppendLine(Format('| Triangles | %d | %d | %.0f%% |',
      [Rep.EstimatedTriangles, Rep.BudgetSpec.MaxTriangles,
       (Rep.EstimatedTriangles / Max(1, Rep.BudgetSpec.MaxTriangles)) * 100.0]));
    SB.AppendLine(Format('| Texture VRAM | %.2f MB | %.0f MB | %.0f%% |',
      [Rep.EstimatedTextureVramMB, Rep.BudgetSpec.MaxTextureVramMB,
       (Rep.EstimatedTextureVramMB / Max(1.0, Rep.BudgetSpec.MaxTextureVramMB)) * 100.0]));
    SB.AppendLine(Format('| Shadow-Casting Lights | %d | %d | %.0f%% |',
      [Rep.ShadowCastingLightsCount, Rep.BudgetSpec.MaxShadowLights,
       (Rep.ShadowCastingLightsCount / Max(1, Rep.BudgetSpec.MaxShadowLights)) * 100.0]));
    SB.AppendLine(Format('| Active Particles | %d | %d | %.0f%% |',
      [Rep.ActiveParticleBudget, Rep.BudgetSpec.MaxActiveParticles,
       (Rep.ActiveParticleBudget / Max(1, Rep.BudgetSpec.MaxActiveParticles)) * 100.0]));
    SB.AppendLine('');

    if Length(Rep.BudgetViolations) > 0 then
    begin
      SB.AppendLine('## Budget Violations');
      for I := 0 to High(Rep.BudgetViolations) do
        SB.AppendLine('- ' + Rep.BudgetViolations[I]);
      SB.AppendLine('');
    end;

    if Length(Rep.TopOffenders) > 0 then
    begin
      SB.AppendLine('## Top Heavy Scene Offenders');
      SB.AppendLine('| Rank | Component | Category | Draws | Triangles | VRAM (KB) | Score |');
      SB.AppendLine('| :---: | :--- | :--- | :---: | :---: | :---: | :---: |');
      CapCount := Min(10, Length(Rep.TopOffenders));
      for I := 0 to CapCount - 1 do
        SB.AppendLine(Format('| %d | `%s` | %s | %d | %d | %d | %.1f |',
          [I + 1, Rep.TopOffenders[I].ComponentName, Rep.TopOffenders[I].Category,
           Rep.TopOffenders[I].EstimatedDrawCalls, Rep.TopOffenders[I].EstimatedTriangles,
           Rep.TopOffenders[I].EstimatedVramBytes div 1024, Rep.TopOffenders[I].CostScore]));
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
