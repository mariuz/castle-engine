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

{ Unified Editor Studio Hub Catalog, Multi-Keyword Search Palette & Cross-Studio
  World Integration Readiness Auditor (@link(TStudioHubManager),
  @link(TStudioWorldHealthReport))
  (Phase 316 — UE 6.0+ Unified Editor Mode Hub & World QA Parity). }
unit ToolStudioHub;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleClassUtils;

type
  { Six high-level domain categories organizing all Horizon 2–5 studios. }
  TStudioHubCategory = (
    shcWorldEnvironment,
    shcMaterialsVfxLighting,
    shcArchitecturePcg,
    shcCharactersAiGas,
    shcCinematicsAudioInput,
    shcPerformanceQaDeploy
  );

  { Metadata card for a single specialized studio or interactive viewport mode. }
  TStudioCatalogEntry = record
    StudioId: String;
    Title: String;
    ShortBadge: String;
    Category: TStudioHubCategory;
    PhaseNumber: Integer;
    Keywords: String;
    Summary: String;
  end;
  TStudioCatalogEntryArray = array of TStudioCatalogEntry;

  { Cross-studio integration warning with a 1-click recommended target StudioId. }
  TStudioIntegrationIssue = record
    SeverityPoints: Integer;
    RecommendedStudioId: String;
    MessageText: String;
  end;

  { Holistic world-readiness & multi-studio inventory report. }
  TStudioWorldHealthReport = class
  public
    ReadinessScore: Integer;
    ReadinessGrade: String;
    TotalTransforms: Integer;
    TotalUserInterfaces: Integer;
    TotalModernSubsystems: Integer;
    CategorySubsystemCounts: array [TStudioHubCategory] of Integer;
    Issues: array of TStudioIntegrationIssue;
    Warnings: TStringList;

    constructor Create;
    destructor Destroy; override;
    procedure AddIssue(const APenalty: Integer; const AStudioId, AMessage: String);
  end;

  { Stateless catalog manager, multi-token studio search engine & cross-studio
    integration auditor consolidating all 36 Horizon 2–5 editor studios. }
  TStudioHubManager = class
  public
    class function CategoryDisplayName(const ACat: TStudioHubCategory): String; static;
    class function CategoryShortLabel(const ACat: TStudioHubCategory): String; static;

    class function AllStudios: TStudioCatalogEntryArray; static;
    class function StudioCount: Integer; static;
    class function FindStudioById(const AStudioId: String;
      out OutEntry: TStudioCatalogEntry): Boolean; static;

    { Filter studios by @code(ACategoryFilter) (@code(-1) = All, @code(0..5) =
      @code(Ord(TStudioHubCategory))) and case-insensitive multi-token @code(ASearchQuery). }
    class procedure FilterStudios(const ACategoryFilter: Integer;
      const ASearchQuery: String;
      out OutEntries: TStudioCatalogEntryArray); static;

    { Perform a cross-studio world integration & readiness audit across
      @code(RootComp) and @code(DesignOwner). }
    class function AuditEntireDesign(
      const RootComp, DesignOwner: TComponent): TStudioWorldHealthReport; static;

    class function BuildExecutiveMarkdownReport(
      const RootComp, DesignOwner: TComponent): String; static;
  end;

implementation

uses
  Math, StrUtils,
  CastleUtils, CastleTransform, CastleViewport, CastleUIControls,
  CastleNprShader, CastleDesignAnnotations, CastlePrefabOverrides,
  CastleStreamingZone, CastleSequencer, CastleStateGraph, CastleParticles,
  CastleNavNetwork, CastleAudioMixer, CastlePostProcessVolume,
  CastleLocalizationTable, CastleVariantSet, CastleSplinePath,
  CastleDecalProjector, CastleTimeOfDayWeather, CastleDataTable,
  CastleModularSnap, CastleDialogueQuest, CastleFoliageBiome, CastleIkRig,
  CastleDestructible, CastleScalability, CastleMaterialGraph,
  CastleWaterSystem, CastleCsgModeler, CastleGameplayAbility,
  CastleEnhancedInput, CastleVirtualCamera, CastleClothRope,
  CastleUtilityAi, CastleSaveReplay;

{ TStudioWorldHealthReport --------------------------------------------------- }

constructor TStudioWorldHealthReport.Create;
var
  C: TStudioHubCategory;
begin
  inherited Create;
  ReadinessScore := 100;
  ReadinessGrade := 'A+ Ship-Ready';
  Warnings := TStringList.Create;
  for C in TStudioHubCategory do
    CategorySubsystemCounts[C] := 0;
end;

destructor TStudioWorldHealthReport.Destroy;
begin
  FreeAndNil(Warnings);
  inherited;
end;

procedure TStudioWorldHealthReport.AddIssue(
  const APenalty: Integer; const AStudioId, AMessage: String);
var
  N: Integer;
begin
  N := Length(Issues);
  SetLength(Issues, N + 1);
  Issues[N].SeverityPoints := APenalty;
  Issues[N].RecommendedStudioId := AStudioId;
  Issues[N].MessageText := AMessage;
  Warnings.Add(Format('[Fix -> %s] %s', [AStudioId, AMessage]));
end;

{ TStudioHubManager ---------------------------------------------------------- }

class function TStudioHubManager.CategoryDisplayName(const ACat: TStudioHubCategory): String;
begin
  case ACat of
    shcWorldEnvironment:     Result := 'World, Terrain, Water & Atmosphere';
    shcMaterialsVfxLighting: Result := 'Materials, Shaders, VFX & PostFX';
    shcArchitecturePcg:      Result := 'Architecture, CSG, Splines & Soft-Body';
    shcCharactersAiGas:      Result := 'Characters, IK, AI, GAS & Narrative';
    shcCinematicsAudioInput: Result := 'Cinematics, Virtual Cameras, Audio & Input';
    shcPerformanceQaDeploy:  Result := 'Performance, Save/Replay, L10n & QA';
  end;
end;

class function TStudioHubManager.CategoryShortLabel(const ACat: TStudioHubCategory): String;
begin
  case ACat of
    shcWorldEnvironment:     Result := 'World & Env';
    shcMaterialsVfxLighting: Result := 'Mat & VFX';
    shcArchitecturePcg:      Result := 'Arch & PCG';
    shcCharactersAiGas:      Result := 'AI, GAS & IK';
    shcCinematicsAudioInput: Result := 'Cine & Input';
    shcPerformanceQaDeploy:  Result := 'Perf & QA';
  end;
end;

class function TStudioHubManager.AllStudios: TStudioCatalogEntryArray;
var
  CountAdded: Integer;

  procedure Reg(const AId, ATitle, ABadge: String; const ACat: TStudioHubCategory;
    const APhase: Integer; const AKeywords, ASummary: String);
  begin
    SetLength(Result, CountAdded + 1);
    Result[CountAdded].StudioId := AId;
    Result[CountAdded].Title := ATitle;
    Result[CountAdded].ShortBadge := ABadge;
    Result[CountAdded].Category := ACat;
    Result[CountAdded].PhaseNumber := APhase;
    Result[CountAdded].Keywords := AKeywords;
    Result[CountAdded].Summary := ASummary;
    Inc(CountAdded);
  end;

begin
  Result := nil;
  CountAdded := 0;

  { 1. World, Terrain, Water & Atmosphere (6 studios) }
  Reg('terrain_brush', 'Terrain Sculpting & Splatmap Paint Brush Mode', 'Terrain',
    shcWorldEnvironment, 280, 'terrain heightmap sculpt splatmap raise lower smooth flatten',
    'Interactive 3D viewport terrain raise/lower/smooth/flatten & 4-layer splatmap brush.');
  Reg('scatter_brush', 'PCG / Foliage Poisson Scatter Brush Mode', 'Scatter',
    shcWorldEnvironment, 281, 'pcg scatter foliage poisson slope pin instances brush',
    'Poisson-disk surface scatter brush with slope filtering and artist [Pinned] locks.');
  Reg('world_minimap', 'World Partition 2D Minimap & Streaming Zones', 'Minimap',
    shcWorldEnvironment, 286, 'world partition minimap streaming zone load unload radius',
    'Top-down 2D world minimap with hysteresis streaming zones and behavior cards.');
  Reg('time_of_day', 'Solar Time-of-Day, Sky Atmosphere & Weather Studio', 'Sky/ToD',
    shcWorldEnvironment, 299, 'sun moon sky fog weather rain storm snow time of day ephemeris',
    '24-hour solar/lunar ephemeris, sky/fog atmosphere curves, and storm wind presets.');
  Reg('foliage_biome', 'Procedural Biome Foliage Volume & Hysteresis LOD Studio', 'Biomes',
    shcWorldEnvironment, 303, 'biome foliage altitude slope road exclusion lod proxy halton',
    'Altitude/slope-filtered biome volumes with road clearings and hysteresis LOD proxies.');
  Reg('water_studio', 'Gerstner Ocean / River Water & 4-Pontoon Buoyancy Studio', 'Water',
    shcWorldEnvironment, 308, 'ocean river water gerstner wave foam pontoon buoyancy float',
    '4-octave Gerstner wave spectrum, river drift currents, and Archimedes hull buoyancy.');

  { 2. Materials, Shaders, VFX & PostFX (6 studios) }
  Reg('material_graph', 'Node-Based PBR Material & X3D Shader Effect Graph Studio', 'MatGraph',
    shcMaterialsVfxLighting, 307, 'material shader graph node pbr glsl plugsubstrate voronoi fresnel',
    'Visual DAG shader graph compiling topological GLSL into CGE X3D TEffectNode.');
  Reg('npr_shader', 'Stylized / NPR Shader Studio & Light Shadow Budget Audit', 'NPR/Lights',
    shcMaterialsVfxLighting, 282, 'npr toon cel outline rim hatching light shadow budget',
    'Toon/cel/outline/hatching X3D shaders and multi-light shadow overlap auditing.');
  Reg('particle_studio', 'Real-Time 3D VFX Particle Emitter & Preset Studio', 'Particles',
    shcMaterialsVfxLighting, 289, 'vfx particle emitter fire smoke sparks magic rain snow',
    'Real-time 3D particle emitters with 6 VFX presets and over-budget diagnostics.');
  Reg('post_process', 'Priority-Blended Post-Process Volumes & Look-Dev Studio', 'PostFX',
    shcMaterialsVfxLighting, 293, 'post process bloom exposure vignette color grade screen effect',
    'Global and bounded Hermite-blended post-process volumes with GLSL screen effects.');
  Reg('decal_studio', '3D Surface Decal Projector & Normal-Cutoff Stamp Studio', 'Decals',
    shcMaterialsVfxLighting, 298, 'decal projector puddle blood rune scorch normal cutoff stamp',
    'Conformal 3D mesh decal projection with grazing-angle rejection and PBR presets.');
  Reg('variant_manager', 'Variant Sets & Atomic Scene Configuration Studio', 'Variants',
    shcMaterialsVfxLighting, 296, 'variant set configuration preset lighting props switcher',
    'UE Variant Manager-style atomic multi-component property configuration sets.');

  { 3. Architecture, CSG, Splines & Soft-Body (6 studios) }
  Reg('csg_studio', 'CSG / Boolean Greybox Architecture & Mesh Modeler Studio', 'CSG',
    shcArchitecturePcg, 309, 'csg boolean union subtract intersect room arch stairwell greybox',
    'Exact 3D BSP boolean brush stack with triplanar UVs and triangle octree colliders.');
  Reg('modular_snap', 'Modular Architecture Socket Snap & Seeded Dungeon Studio', 'Modular',
    shcArchitecturePcg, 301, 'modular socket snap doorway corridor room seeded dungeon layout',
    'Opposing doorway/pipe socket snapping and zero-overlap seeded dungeon generation.');
  Reg('spline_studio', '3D Catmull-Rom Spline Road/Cable Extruder & Scatter Studio', 'Splines',
    shcArchitecturePcg, 297, 'spline catmull rom road river cable ribbon extrude follower',
    'Arc-length LUT Catmull-Rom splines with banked road/cable meshes and followers.');
  Reg('prefab_overrides', 'Non-Destructive Prefab Property Overrides Studio', 'Prefabs',
    shcArchitecturePcg, 285, 'prefab instance override revert apply castletransformdesign',
    'Per-instance child property overrides on TCastleTransformDesign and TCastleDesign.');
  Reg('destructible', '3D Voronoi Fracture & Destructible Debris Physics Studio', 'Fracture',
    shcArchitecturePcg, 305, 'voronoi fracture destructible shatter blast debris impulse',
    'Exact 3D convex Voronoi cell fracture with radial blast waves and timed debris.');
  Reg('cloth_studio', 'Verlet Cloth / Cape / Banner & Catenary Rope Wind Studio', 'Cloth',
    shcArchitecturePcg, 313, 'verlet cloth cape banner flag catenary rope wind sphere collider',
    'Pinned Verlet soft-body cloth grids and catenary/pendulum ropes with wind & colliders.');

  { 4. Characters, IK, AI, GAS & Narrative (7 studios) }
  Reg('ability_studio', 'Gameplay Ability, Cooldown, Buff/Debuff & Attribute (GAS) Studio', 'Abilities',
    shcCharactersAiGas, 310, 'gas gameplay ability attribute mana cooldown dot hot buff immunity',
    'Derived attributes, mana/cooldown abilities, stacking DoT/HoTs & tag immunities.');
  Reg('utility_ai', 'Smart Objects, RVO Crowd Separation & Utility AI Studio', 'UtilAI',
    shcCharactersAiGas, 314, 'smart object slot utility ai response curve crowd rvo separation',
    'Claimable world interaction stations, need urgency curves, and crowd separation.');
  Reg('nav_network', 'AI Waypoint Patrol, A* NavGrid & Sight/Hearing Studio', 'NavAI',
    shcCharactersAiGas, 290, 'navgrid astar pathfinding waypoint patrol sight cone hearing',
    'Octile A* obstacle navigation grids, patrol loops, and FOV/hearing perception.');
  Reg('state_graph', 'Visual State Machine & Blackboard Behavior Graph Studio', 'States',
    shcCharactersAiGas, 288, 'state machine graph transition blackboard patrol chase mermaid',
    'Blackboard-driven finite state machines with Any-State interrupts and Mermaid export.');
  Reg('ik_rig', 'Two-Bone Limb IK, Ground Foot-Plant & Look-At Rig Studio', 'IK Rig',
    shcCharactersAiGas, 304, 'ik two bone knee elbow pole foot plant look at head aim',
    'Analytical law-of-cosines limb IK, raycast foot planting, and cone-clamped Look-At.');
  Reg('dialogue_quest', 'Branching Dialogue Trees, Quest Tracker & XP Studio', 'Quests',
    shcCharactersAiGas, 302, 'dialogue conversation choice quest objective xp narrative csv',
    'Condition-gated dialogue graphs, multi-objective quests, and CSV L10n export.');
  Reg('data_table', 'Structured DataTables, Gameplay Tags & Balance Curve Studio', 'Tables',
    shcCharactersAiGas, 300, 'datatable csv schema gameplay tag progression curve rtti',
    'Typed schema DataTables, dot-boundary Gameplay Tag queries, and stat curves.');

  { 5. Cinematics, Virtual Cameras, Audio & Input (4 studios) }
  Reg('sequencer', 'Non-Linear Cinematic Sequencer & Multi-Track Timeline Studio', 'Sequencer',
    shcCinematicsAudioInput, 287, 'sequencer timeline keyframe camera cut animation cue cinematic',
    'Multi-track property interpolation, camera cuts, easing curves, and cue events.');
  Reg('virtual_camera', 'Virtual Camera Priority Blending, Dolly Rail & Shake Studio', 'VCam',
    shcCinematicsAudioInput, 312, 'virtual camera cinemachine priority blend dolly deadzone trauma shake',
    'Priority-blended virtual cameras, spline dolly rails, deadzones, and Perlin shake.');
  Reg('audio_mixer', 'Spatial Audio Bus Mixer, Sidechain Ducking & Reverb Studio', 'Audio',
    shcCinematicsAudioInput, 291, 'audio sound bus mixer solo mute sidechain ducking reverb zone',
    '5-bus gain/solo/mute routing, Voice->Music sidechain ducking, and 3D audio zones.');
  Reg('input_studio', 'Enhanced Input Action Contexts, Chords & Rebinding Studio', 'Input',
    shcCinematicsAudioInput, 311, 'enhanced input context tap hold chord deadzone key rebind',
    'Priority input contexts, Tap/Hold/Chord triggers, radial deadzones & user rebinds.');

  { 6. Performance, Save/Replay, L10n & QA (7 studios) }
  Reg('frame_profiler', 'Frame Budget Profiler & 1-Click Scalability Tier Studio', 'Profiler',
    shcPerformanceQaDeploy, 306, 'frame budget profiler scalability low medium high epic mobile fps',
    '60/90/120 Hz draw/triangle/light budget auditing and reversible scalability tiers.');
  Reg('save_replay', 'SaveGame Slot Manager, World Checkpoints & Replay Studio', 'Replay',
    shcPerformanceQaDeploy, 315, 'savegame slot checkpoint schema migration replay scrub slerp',
    'Schema-versioned multi-system world snapshots and deterministic replay scrubbing.');
  Reg('review_pins', 'Spatial 3D/2D Review Pins ("Canvas Pins") & Bookmarks', 'Pins',
    shcPerformanceQaDeploy, 283, 'review pin annotation bug todo camera bookmark qa checklist',
    'Zero-runtime-cost 3D & 2D spatial QA pins with saved camera viewpoint bookmarks.');
  Reg('sandboxes_diff', 'Design Sandboxes, Visual Diff & Selective Property Merge', 'Diff',
    shcPerformanceQaDeploy, 279, 'sandbox branch diff merge revert snapshot comparison',
    'Non-destructive design sandboxes with component/property diff and selective revert.');
  Reg('asset_graph', 'Bidirectional Asset Reference Graph & Broken-URL Auto-Repair', 'Assets',
    shcPerformanceQaDeploy, 292, 'asset dependency reference orphan trash broken url repair',
    'Multi-hop dependency indexing, broken castle-data:/ repair, and orphan quarantine.');
  Reg('localization', 'Localization (i18n) String Extractor & Pseudo-L10n Auditor', 'L10n',
    shcPerformanceQaDeploy, 294, 'localization i18n l10n locale csv translate pseudo overflow',
    'UI & 3D string extraction, live locale switching, pseudo-L10n, and overflow checks.');
  Reg('responsive_sim', 'Responsive UI Safe-Area, Notch & Touch-Target Simulator', 'SafeArea',
    shcPerformanceQaDeploy, 295, 'responsive ui aspect ratio mobile notch safe area touch target',
    '16:9 / 21:9 / Mobile Notch / Tablet safe-area & 44px touch-target layout auditor.');
end;

class function TStudioHubManager.StudioCount: Integer;
begin
  Result := Length(AllStudios);
end;

class function TStudioHubManager.FindStudioById(const AStudioId: String;
  out OutEntry: TStudioCatalogEntry): Boolean;
var
  Catalog: TStudioCatalogEntryArray;
  I: Integer;
begin
  Catalog := AllStudios;
  for I := 0 to High(Catalog) do
    if SameText(Catalog[I].StudioId, AStudioId) then
    begin
      OutEntry := Catalog[I];
      Exit(True);
    end;
  Result := False;
end;

class procedure TStudioHubManager.FilterStudios(const ACategoryFilter: Integer;
  const ASearchQuery: String;
  out OutEntries: TStudioCatalogEntryArray);
var
  Catalog: TStudioCatalogEntryArray;
  Tokens: TStringList;
  Haystack, Tok: String;
  I, TIdx, OutCount: Integer;
  MatchesAll: Boolean;
begin
  Catalog := AllStudios;
  OutEntries := nil;
  OutCount := 0;

  Tokens := TStringList.Create;
  try
    ExtractStrings([' ', #9], [], PChar(LowerCase(Trim(ASearchQuery))), Tokens);

    for I := 0 to High(Catalog) do
    begin
      if (ACategoryFilter >= 0) and (Ord(Catalog[I].Category) <> ACategoryFilter) then
        Continue;

      MatchesAll := True;
      if Tokens.Count > 0 then
      begin
        Haystack := LowerCase(
          Catalog[I].StudioId + ' ' +
          Catalog[I].Title + ' ' +
          Catalog[I].ShortBadge + ' ' +
          Catalog[I].Keywords + ' ' +
          Catalog[I].Summary + ' ' +
          CategoryDisplayName(Catalog[I].Category) + ' ' +
          'phase ' + IntToStr(Catalog[I].PhaseNumber) + ' ' +
          IntToStr(Catalog[I].PhaseNumber));

        for TIdx := 0 to Tokens.Count - 1 do
        begin
          Tok := Trim(Tokens[TIdx]);
          if (Tok <> '') and (Pos(Tok, Haystack) = 0) then
          begin
            MatchesAll := False;
            Break;
          end;
        end;
      end;

      if MatchesAll then
      begin
        SetLength(OutEntries, OutCount + 1);
        OutEntries[OutCount] := Catalog[I];
        Inc(OutCount);
      end;
    end;
  finally
    FreeAndNil(Tokens);
  end;
end;

class function TStudioHubManager.AuditEntireDesign(
  const RootComp, DesignOwner: TComponent): TStudioWorldHealthReport;
var
  Visited: Classes.TList;
  VCamCount, VCamBrainCount: Integer;
  WeatherRigCount, ClothWeatherSyncCount: Integer;
  WaterVolCount, BuoyancyCount: Integer;
  SmartObjCount, UtilAgentCount: Integer;
  OpenBugPinCount: Integer;
  InputConflicts: TStringList;

  procedure BumpSub(const ACat: TStudioHubCategory);
  begin
    Inc(Result.CategorySubsystemCounts[ACat]);
    Inc(Result.TotalModernSubsystems);
  end;

  procedure InspectSingle(const C: TComponent);
  begin
    if (C = nil) or (Visited.IndexOf(C) >= 0) then
      Exit;
    Visited.Add(C);

    if (C is TCastleTransform) and (not (C is TCastleAbstractRootTransform)) and
       (not (csTransient in C.ComponentStyle)) then
      Inc(Result.TotalTransforms);
    if (C is TCastleUserInterface) and (not (csTransient in C.ComponentStyle)) then
      Inc(Result.TotalUserInterfaces);

    { World & Environment }
    if C is TCastleStreamingZone then BumpSub(shcWorldEnvironment);
    if C is TCastleTimeOfDayWeather then
    begin
      Inc(WeatherRigCount);
      BumpSub(shcWorldEnvironment);
    end;
    if (C is TCastleFoliageBiomeVolume) or (C is TCastleLodProxyBehavior) then
      BumpSub(shcWorldEnvironment);
    if C is TCastleWaterVolume then
    begin
      Inc(WaterVolCount);
      BumpSub(shcWorldEnvironment);
    end;
    if C is TCastleBuoyancyBehavior then
    begin
      Inc(BuoyancyCount);
      BumpSub(shcWorldEnvironment);
    end;

    { Materials, Shaders, VFX & PostFX }
    if (C is TCastleMaterialGraph) or (C is TCastleMaterialGraphBehavior) then
      BumpSub(shcMaterialsVfxLighting);
    if C is TCastleStylizedShaderBehavior then BumpSub(shcMaterialsVfxLighting);
    if C is TCastleParticleEmitter then BumpSub(shcMaterialsVfxLighting);
    if (C is TCastlePostProcessVolume) or (C is TCastlePostProcessStack) then
      BumpSub(shcMaterialsVfxLighting);
    if C is TCastleDecalProjector then BumpSub(shcMaterialsVfxLighting);
    if C is TCastleVariantSetManager then BumpSub(shcMaterialsVfxLighting);

    { Architecture, CSG, Splines & Soft-Body }
    if C is TCastleCsgModeler then BumpSub(shcArchitecturePcg);
    if (C is TCastleModularPieceBehavior) or (C is TCastleSnapSocket) then
      BumpSub(shcArchitecturePcg);
    if (C is TCastleSplinePath) or (C is TCastleSplineFollowerBehavior) then
      BumpSub(shcArchitecturePcg);
    if C is TCastlePrefabOverride then
      BumpSub(shcArchitecturePcg);
    if C is TCastleDestructibleBehavior then BumpSub(shcArchitecturePcg);
    if C is TCastleClothSurface then
    begin
      BumpSub(shcArchitecturePcg);
      if TCastleClothSurface(C).SyncWithWeather and
         (TCastleClothSurface(C).WeatherController = nil) then
        Inc(ClothWeatherSyncCount);
    end;
    if C is TCastleVerletRope then BumpSub(shcArchitecturePcg);

    { Characters, IK, AI, GAS & Narrative }
    if C is TCastleAbilitySystemBehavior then BumpSub(shcCharactersAiGas);
    if C is TCastleSmartObject then
    begin
      Inc(SmartObjCount);
      BumpSub(shcCharactersAiGas);
    end;
    if C is TCastleUtilityAiBehavior then
    begin
      Inc(UtilAgentCount);
      BumpSub(shcCharactersAiGas);
    end;
    if (C is TCastleNavGrid) or (C is TCastleWaypointNode) or (C is TCastlePatrolAgentBehavior) then
      BumpSub(shcCharactersAiGas);
    if C is TCastleStateGraphBehavior then BumpSub(shcCharactersAiGas);
    if (C is TCastleTwoBoneIkBehavior) or (C is TCastleLookAtConstraintBehavior) then
      BumpSub(shcCharactersAiGas);
    if (C is TCastleDialogueTree) or (C is TCastleQuestTracker) then
      BumpSub(shcCharactersAiGas);
    if C is TCastleDataTable then BumpSub(shcCharactersAiGas);

    { Cinematics, Virtual Cameras, Audio & Input }
    if C is TCastleSequencePlayer then BumpSub(shcCinematicsAudioInput);
    if C is TCastleVirtualCamera then
    begin
      Inc(VCamCount);
      BumpSub(shcCinematicsAudioInput);
    end;
    if C is TCastleVirtualCameraBrain then
    begin
      Inc(VCamBrainCount);
      BumpSub(shcCinematicsAudioInput);
    end;
    if (C is TCastleAudioBusMixer) or (C is TCastleAudioZone) then
      BumpSub(shcCinematicsAudioInput);
    if C is TCastleInputMapManager then
    begin
      BumpSub(shcCinematicsAudioInput);
      TCastleInputMapManager(C).DetectBindingConflicts(InputConflicts);
    end;

    { Performance, Save/Replay, L10n & QA }
    if C is TCastleScalabilityManager then BumpSub(shcPerformanceQaDeploy);
    if (C is TCastleSaveSlotManager) or (C is TCastleReplayRecorder) then
      BumpSub(shcPerformanceQaDeploy);
    if C is TCastleLocalizationManager then BumpSub(shcPerformanceQaDeploy);
    if C is TCastleDesignAnnotation then
    begin
      BumpSub(shcPerformanceQaDeploy);
      if (TCastleDesignAnnotation(C).Category = dacBug) and
         (TCastleDesignAnnotation(C).Status <> dasResolved) then
        Inc(OpenBugPinCount);
    end;
    if C is TCastleDesignAnnotationUi then
    begin
      BumpSub(shcPerformanceQaDeploy);
      if (TCastleDesignAnnotationUi(C).Category = dacBug) and
         (TCastleDesignAnnotationUi(C).Status <> dasResolved) then
        Inc(OpenBugPinCount);
    end;
  end;

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    CC: TCastleComponent;
    UI: TCastleUserInterface;
    T: TCastleTransform;
  begin
    if C = nil then
      Exit;
    InspectSingle(C);

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Traverse(CC.NonVisualComponents[I]);
    end;
    if C is TCastleViewport then
      Traverse(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Traverse(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      if not (csTransient in T.ComponentStyle) then
      begin
        for I := 0 to T.BehaviorsCount - 1 do
          Traverse(T.Behaviors[I]);
        for I := 0 to T.Count - 1 do
          Traverse(T[I]);
      end;
    end;
  end;

var
  I, TotalPenalty: Integer;
begin
  Result := TStudioWorldHealthReport.Create;
  Visited := Classes.TList.Create;
  InputConflicts := TStringList.Create;
  try
    VCamCount := 0;
    VCamBrainCount := 0;
    WeatherRigCount := 0;
    ClothWeatherSyncCount := 0;
    WaterVolCount := 0;
    BuoyancyCount := 0;
    SmartObjCount := 0;
    UtilAgentCount := 0;
    OpenBugPinCount := 0;

    Traverse(RootComp);
    if DesignOwner <> nil then
      for I := 0 to DesignOwner.ComponentCount - 1 do
        Traverse(DesignOwner.Components[I]);

    { Cross-Studio Integration Checks }
    if (VCamCount > 0) and (VCamBrainCount = 0) then
      Result.AddIssue(15, 'virtual_camera',
        Format('%d TCastleVirtualCamera rig(s) exist without a TCastleVirtualCameraBrain director on the viewport camera.',
          [VCamCount]));

    if (ClothWeatherSyncCount > 0) and (WeatherRigCount = 0) then
      Result.AddIssue(15, 'time_of_day',
        Format('%d TCastleClothSurface component(s) have SyncWithWeather=True without any TCastleTimeOfDayWeather controller.',
          [ClothWeatherSyncCount]));

    if (BuoyancyCount > 0) and (WaterVolCount = 0) then
      Result.AddIssue(15, 'water_studio',
        Format('%d TCastleBuoyancyBehavior hull(s) exist without any TCastleWaterVolume ocean/river body.',
          [BuoyancyCount]));

    if (UtilAgentCount > 0) and (SmartObjCount = 0) then
      Result.AddIssue(15, 'utility_ai',
        Format('%d TCastleUtilityAiBehavior NPC(s) exist without any TCastleSmartObject stations.',
          [UtilAgentCount]));

    if InputConflicts.Count > 0 then
      Result.AddIssue(15, 'input_studio',
        Format('%d Enhanced Input key-binding conflict(s) detected (%s).',
          [InputConflicts.Count, InputConflicts[0]]));

    if OpenBugPinCount > 0 then
      Result.AddIssue(Min(25, OpenBugPinCount * 15), 'review_pins',
        Format('%d unresolved Bug/Blocker spatial review pin(s) remain open before release.',
          [OpenBugPinCount]));

    TotalPenalty := 0;
    for I := 0 to High(Result.Issues) do
      Inc(TotalPenalty, Result.Issues[I].SeverityPoints);

    Result.ReadinessScore := Clamped(100 - TotalPenalty, 0, 100);
    if Result.ReadinessScore = 100 then
      Result.ReadinessGrade := 'A+ Ship-Ready'
    else if Result.ReadinessScore >= 90 then
      Result.ReadinessGrade := 'A Ready'
    else if Result.ReadinessScore >= 75 then
      Result.ReadinessGrade := 'B Minor Warnings'
    else if Result.ReadinessScore >= 55 then
      Result.ReadinessGrade := 'C Integration Fixes Needed'
    else
      Result.ReadinessGrade := 'D Action Required';
  finally
    FreeAndNil(InputConflicts);
    FreeAndNil(Visited);
  end;
end;

class function TStudioHubManager.BuildExecutiveMarkdownReport(
  const RootComp, DesignOwner: TComponent): String;
var
  Report: TStudioWorldHealthReport;
  SB: TStringBuilder;
  Cat: TStudioHubCategory;
  I: Integer;
begin
  Report := AuditEntireDesign(RootComp, DesignOwner);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — Unified Studio Hub & World Readiness Executive Report');
    SB.AppendLine;
    SB.AppendLine(Format('- **World Readiness Score**: **%d / 100** (`%s`)',
      [Report.ReadinessScore, Report.ReadinessGrade]));
    SB.AppendLine(Format('- **Cataloged Editor Studios**: `%d` across `6` domains',
      [StudioCount]));
    SB.AppendLine(Format('- **Active Hierarchy**: `%d` 3D Transforms | `%d` 2D UI Controls | `%d` Active Studio Subsystems',
      [Report.TotalTransforms, Report.TotalUserInterfaces, Report.TotalModernSubsystems]));
    SB.AppendLine;

    SB.AppendLine('## Domain Subsystem Footprint');
    SB.AppendLine('| Studio Domain | Active Components / Behaviors |');
    SB.AppendLine('| :--- | :--- |');
    for Cat in TStudioHubCategory do
      SB.AppendLine(Format('| %s | %d |',
        [CategoryDisplayName(Cat), Report.CategorySubsystemCounts[Cat]]));
    SB.AppendLine;

    SB.AppendLine('## Cross-Studio Integration Audit');
    if Length(Report.Issues) = 0 then
      SB.AppendLine('- **0 issues detected** — all active studio subsystems are properly wired and ship-ready.')
    else
      for I := 0 to High(Report.Issues) do
        SB.AppendLine(Format('- **[-%d pts | Open `%s`]**: %s',
          [Report.Issues[I].SeverityPoints,
           Report.Issues[I].RecommendedStudioId,
           Report.Issues[I].MessageText]));

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
    FreeAndNil(Report);
  end;
end;

end.
