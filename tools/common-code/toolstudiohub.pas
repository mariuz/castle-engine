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
  (Phases 316 & 326 — UE 6.0+ Unified 46-Studio Editor Hub & World QA Parity). }
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
    integration auditor consolidating all 46 Horizon 2–6 editor studios. }
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
  CastleUtilityAi, CastleSaveReplay,
  CastleVehicleSystem, CastleBlendMontage, CastleEqsTactical,
  CastleInventoryCraft, CastleNetcodeIris, CastleMetaSound,
  CastleTilemap2DPlus, CastleVolumetrics, CastleGeometryScript,
  CastleMotionMatching, CastleMassEntity, CastleVoxelTerrain,
  CastleShallowFluid, CastleRagdollHit, CastleCommonUiMvvm,
  CastleHlodBaker, CastleRibbonTrail, CastlePcgSettlement,
  CastleStateTree, CastleControlRig, CastleSpringArm, CastleErosionBaker,
  CastleMegaLights, CastleGameplayCue, CastleDataLayers, CastleJiggleBone,
  CastleSoundscape,
  CastleChooserTable, CastleGroomHair, CastleTraversalParkour, CastleRuntimeVt,
  CastleMover2, CastleCameraRigRail, CastleMeshletCluster, CastleTetSoftBody,
  CastleMassTraffic,
  CastleSurfaceGi, CastleContextualAnim, CastleTargetingSystem,
  CastleMutableCharacter, CastleRiverSpline, CastleOccluderFader,
  CastleGameplayDebugger, CastleWindField, CastleAssetPreloader,
  CastleSubstrateMaterial, CastleSmartObjectSlots, CastleAeroFoil,
  CastleCreviceClutter, CastleCameraShake, CastleFireGrid2D,
  CastleGameplayMessenger, CastleOctahedralImpostor, CastlePoseSnapshot,
  CastlePortalPair, CastleSensoryPerception, CastleIvyClimber,
  CastleFootstepDirector, CastleGravityField, CastleCloudShadows,
  CastleTrailStamper, CastleCoverPointScanner, CastleCatenaryCable;

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
  Reg('volumetric_studio', 'Volumetric Height Fog, God-Rays & Box-Parallax Probe Studio', 'VolFog',
    shcWorldEnvironment, 324, 'volumetric height fog god ray light shaft henyey greenstein reflection probe parallax',
    'Closed-form altitude optical depth, Henyey-Greenstein sun shafts, and box-parallax probes.');
  Reg('tilemap_studio', '2D / 2.5D Bitmask Auto-Tilemap, Greedy Collider & Flipbook Studio', 'Tile2D',
    shcWorldEnvironment, 323, 'tilemap 2d autotile wang blob bitmask greedy collider paper2d flipbook sprite',
    '4-bit/8-bit Wang auto-tiles, greedy rectangle 3D colliders, and Paper2D sprite flipbooks.');

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
  Reg('geometry_script', 'Geometry Script Procedural Mesh Stack & 3D L-System Botanical Studio', 'GeoMesh',
    shcArchitecturePcg, 325, 'geometry script procedural mesh subdivide twist solidify displace lsystem tree botanical',
    'Non-destructive Subdivide/Twist/Displace/Solidify stacks and 3D turtle L-System trees.');

  { 4. Characters, IK, AI, GAS & Narrative (11 studios) }
  Reg('ability_studio', 'Gameplay Ability, Cooldown, Buff/Debuff & Attribute (GAS) Studio', 'Abilities',
    shcCharactersAiGas, 310, 'gas gameplay ability attribute mana cooldown dot hot buff immunity',
    'Derived attributes, mana/cooldown abilities, stacking DoT/HoTs & tag immunities.');
  Reg('vehicle_studio', 'Chaos Wheeled Vehicle, Suspension, Ackermann & Pacejka Drivetrain Studio', 'Vehicle',
    shcCharactersAiGas, 317, 'chaos wheeled vehicle raycast suspension ackermann steering pacejka tire drift torque gear',
    '4-wheel WorldRay suspension, exact Ackermann steering, 6-speed gears & Pacejka drift.');
  Reg('blend_montage', '2D Locomotion Blend Space, Motion Warping & Anim Montage Studio', 'Blend2D',
    shcCharactersAiGas, 318, 'blendspace 2d gradient band locomotion anim montage combo notify motion warp root',
    '2D Gradient Band locomotion pads, combo-window Anim Montages, and Hermite motion warping.');
  Reg('eqs_studio', 'Environment Query System (EQS) Tactical Cover & Flank Scoring Studio', 'EQS',
    shcCharactersAiGas, 319, 'eqs environment query tactical cover line of sight sniper flank ring grid ai',
    'Concentric ring/grid EQS candidates with WorldRay LoS cover, elevation & flank scoring.');
  Reg('inventory_studio', 'RPG Inventory Grid, Paperdoll GAS Modifiers, Crafting & Loot Studio', 'Items',
    shcCharactersAiGas, 320, 'inventory bag stack weight paperdoll equipment crafting recipe loot table rarity pity',
    'Weight/slot-capped bags, 5-slot GAS paperdolls, atomic crafting & pity-protected loot.');
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
  Reg('metasound_studio', 'MetaSound Procedural PCM Synth, Surface Footsteps & Quartz Music Studio', 'MetaSnd',
    shcCinematicsAudioInput, 322, 'metasound procedural pcm wav synth biquad adsr footstep surface quartz music stem bpm',
    '16-bit RIFF/WAVE synth, downward-raycast footsteps, and BPM bar/beat music stems.');

  { 6. Performance, Save/Replay, L10n & QA (9 studios) }
  Reg('frame_profiler', 'Frame Budget Profiler & 1-Click Scalability Tier Studio', 'Profiler',
    shcPerformanceQaDeploy, 306, 'frame budget profiler scalability low medium high epic mobile fps',
    '60/90/120 Hz draw/triangle/light budget auditing and reversible scalability tiers.');
  Reg('playtest_gauntlet', 'Gauntlet Automated Playtest Bot Runner, Smoke Assertions & CI Export', 'Gauntlet',
    shcPerformanceQaDeploy, 326, 'gauntlet playtest automation bot smoke test killz nan junit xml ci qa',
    'Deterministic multi-system smoke-test bot, Kill-Z/NaN guards, world restore & JUnit XML.');
  Reg('netcode_studio', 'Iris Netcode Replication, Spatial Relevancy & Hitbox Rewind Studio', 'NetIris',
    shcPerformanceQaDeploy, 321, 'iris netcode replication relevancy priority bandwidth sLerp lag compensation hitbox rewind',
    'Spatial relevancy culling, priority bandwidth budgets, client SLerp & server hitbox rewind.');
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

  { Horizon 7 (Phases 327-336 — UE 6.0+ Next-Gen Runtime & Telemetry Parity, +10 -> 56 studios) }
  Reg('motion_matching', 'Motion Matching, Pose Search Trajectory & Inertialization Studio', 'MotMatch',
    shcCharactersAiGas, 327, 'motion matching pose search trajectory inertialization stride warp locomotion',
    'Closed-form spring trajectory k-NN Pose Search, Holden Inertialization, and Stride Warping.');
  Reg('mass_entity', 'MassEntity Data-Oriented SoA Crowd, Spatial Hash & Flow-Field Studio', 'MassECS',
    shcCharactersAiGas, 328, 'masseCS massentity soa crowd boids dijkstra flowfield spatialhash',
    '1,000+ entity SoA crowds with O(1) spatial hash separation, Dijkstra flow fields & 4-tier LODs.');
  Reg('voxel_studio', '3D Voxel SDF Cave, Overhang & Marching-Tetrahedra Studio', 'Voxel3D',
    shcWorldEnvironment, 329, 'voxel sdf marching tetrahedra cubes cave overhang arch sky island',
    'Non-destructive 3D SDF brush stacks extracting watertight Marching-Tetrahedra cave meshes.');
  Reg('fluid_studio', '2.5D Shallow-Water Pipe-Model Fluid, Waterfall & Foam Studio', 'Fluid2D',
    shcWorldEnvironment, 330, 'shallowfluid pipe hydrostatic waterfall dam break foam wetness spring',
    'Mass-conserving Virtual-Pipe shallow water solver with springs, WorldRay bed bake & foam.');
  Reg('ragdoll_studio', 'Physical Animation Hit-Reaction & Articulated Ragdoll Studio', 'PhysAnim',
    shcCharactersAiGas, 331, 'physanim hit reaction impulse pd motor ragdoll collapse recovery',
    '11-bone humanoid hit-reaction impulses, critically-damped PD motors & PBD ragdoll recovery.');
  Reg('commonui_mvvm', 'CommonUI Gamepad Focus Router, Prompt Glyphs & MVVM Studio', 'CommonUI',
    shcCinematicsAudioInput, 332, 'commonui gamepad dpad spatial focus modal glyph mvvm viewmodel',
    '2D D-Pad cone navigation, modal focus stacks, 5-device glyph swap & two-way MVVM bindings.');
  Reg('hlod_studio', 'World Partition HLOD Spatial Cluster & Draw-Call Merger Studio', 'HLOD',
    shcWorldEnvironment, 333, 'hlod hierarchical lod spatial cluster cell proxy draw call hysteresis',
    'Spatial XZ grid prop clustering, single-draw-call merged cell proxies & camera hysteresis.');
  Reg('ribbon_studio', 'Niagara Sword-Slash Ribbon Trail & Arc Lightning VFX Studio', 'RibbonVFX',
    shcMaterialsVfxLighting, 334, 'niagara ribbon sword slash blade trail catmull lightning bolt beam',
    'Dual-socket weapon slash arcs, Catmull-Rom subdivided ribbons & midpoint-displaced lightning.');
  Reg('settlement_studio', 'PCG Biome Settlement, Road Graph & Building Lot Studio', 'Village',
    shcArchitecturePcg, 335, 'settlement village crossroads town building parcel lot gabled fence',
    'Road-intersection graphs, zero-overlap setback building lots, gabled houses & palisade fences.');
  Reg('telemetry_insights', 'Unreal Insights Live Telemetry Ring-Buffer & Flame-Graph Studio', 'Insights',
    shcPerformanceQaDeploy, 336, 'unreal insights telemetry ringbuffer flamegraph p50 p95 p99 chrometrace perfetto',
    '120-frame ring-buffer flame-graph profiler, P50/P95/P99 hitch detector & Perfetto JSON export.');

  { Horizon 8 (Phases 337-346 — UE 6.0+ StateTree, Control Rig, MegaLights, Erosion, Data Layers & Golden QA Parity, +10 -> 66 studios) }
  Reg('state_tree', 'StateTree Hierarchical AI Decision Tree, Evaluators & Task Studio', 'StateTree',
    shcCharactersAiGas, 337, 'statetree hierarchical ai selector enter condition evaluator preemption mermaid',
    'Hierarchical selector trees, spatial evaluators, ancestor transition preemption & Mermaid export.');
  Reg('control_rig', 'Control Rig Procedural Multi-Bone FABRIK & Twist Distribution Studio', 'CtrlRig',
    shcCharactersAiGas, 338, 'control rig procedural multi bone fabrik ik solver twist roll tail tentacle',
    'Arbitrary N-joint FABRIK solver, anti-candy-wrapper twist roll & sinusoidal tail waves.');
  Reg('spring_arm', 'Spring-Arm Camera Collision Whisker Probe & Lagged Boom Studio', 'SpringArm',
    shcCinematicsAudioInput, 339, 'spring arm camera boom whisker ray collision pull in lag shoulder',
    '5-whisker WorldRay camera occlusion pull-in, asymmetric ease-out recovery & chase lag.');
  Reg('erosion_studio', 'Landscape Thermal Talus & Droplet Hydraulic Erosion Baker Studio', 'Erosion',
    shcWorldEnvironment, 340, 'terrain landscape thermal talus hydraulic raindrop erosion sediment splatmap',
    'Mass-conserving Olsen thermal repose slumping, Beyer hydraulic gullies & RGBA splatmaps.');
  Reg('mega_lights', 'MegaLights Clustered 3D Light-Grid Culler, Gobo Cookie & Flicker Studio', 'MegaLight',
    shcMaterialsVfxLighting, 341, 'megalights clustered tile light grid culler gobo cookie venetian caustic flicker',
    '16x8x16 clustered 3D light-grid hotspot culler, procedural gobo cookies & torch flicker.');
  Reg('gameplay_cue', 'Gameplay Cue Combat Feedback, Hit-Stop & Floating Damage-Number Studio', 'GameCue',
    shcCharactersAiGas, 342, 'gameplay cue combat hit stop freeze timescale camera punch floating damage crit pool',
    'Tag-routed combat cues, 0.05x hit-stop freezes, camera punch & zero-alloc damage popups.');
  Reg('data_layers', 'World Partition Runtime Data Layers & Sub-Layer Inheritance Studio', 'DataLayer',
    shcWorldEnvironment, 343, 'world partition runtime data layer unloaded hidden activated scenario inheritance',
    'Hierarchical Unloaded/LoadedHidden/Activated Data Layers and 1-click scenario presets.');
  Reg('jiggle_bone', 'Secondary-Motion Jiggle Bone Springs & Spherical Limit Cone Studio', 'Jiggle',
    shcCharactersAiGas, 344, 'jiggle bone spring secondary motion inertia damping gravity spherical cone ear pouch',
    'Sub-stepped inertial world-space tip springs, gravity sag & spherical limit-cone clamping.');
  Reg('soundscape_studio', 'Ambient Soundscape Biome Director & Acoustic Ray Occlusion Studio', 'SndScape',
    shcCinematicsAudioInput, 345, 'soundscape ambient biome birds crickets wind cavern ray acoustic occlusion lpf',
    'Context-reactive biome palettes, 3D hemisphere call scatter & WorldRay wall muffling.');
  Reg('regression_harness', 'Deterministic Golden-Snapshot State Hasher & Drift Auditor Studio', 'Regress',
    shcPerformanceQaDeploy, 346, 'determinism golden snapshot fnv1a hash replay drift regression qa audit',
    '64-bit FNV-1a world-state hasher, dual-run seeded replay verifier & per-actor drift diff.');

  { Horizon 9 (Phases 347-356 — UE 6.0+ Choosers, Groom, Parkour, RVT, Mover 2.0, Camera Rail, Meshlets, Tet Flesh, MassTraffic & Live Cook Parity, +10 -> 76 studios) }
  Reg('chooser_table', 'Chooser Tables Context-Driven Multi-Column Asset Selector Studio', 'Chooser',
    shcCharactersAiGas, 347, 'chooser table context tag prefix range priority weighted asset montage bark',
    'Hierarchical GameplayTag prefix columns, numeric ranges, priority tiers & weighted tie-breaking.');
  Reg('groom_studio', 'Groom Strand Hair / Fur Clump Cards & Inertial Wind Studio', 'Groom',
    shcMaterialsVfxLighting, 348, 'groom strand hair fur clump card curl frizz scalp collision verlet wind',
    'Fibonacci scalp guides, progressive root-to-tip lock clumping, scalp anti-clip & Verlet wind.');
  Reg('traversal_studio', 'Parkour Traversal Vault, Mantle, Ledge Scanner & Warp Studio', 'Parkour',
    shcCharactersAiGas, 349, 'parkour traversal vault mantle step climb worldray obstacle bezier motion warp gasp',
    'Multi-height WorldRay obstacle classifier (Step/Vault/Mantle/Climb) & Bezier root-motion warp.');
  Reg('rvt_studio', 'Runtime Virtual Texture (RVT) LRU Tile Cache & Snow/Mud Trail Studio', 'RVT/Snow',
    shcWorldEnvironment, 350, 'rvt runtime virtual texture lru page tile snow mud sand footprint rut berm',
    'LRU virtual page residency table, deformable snow/mud sinkage + berms & heightmap PNG export.');
  Reg('mover_studio', 'Chaos Mover 2.0 Rollback-Ready Kinematic Character Modes Studio', 'Mover2',
    shcCharactersAiGas, 351, 'chaos mover 2 rollback syncstate walk slide wallrun swim grapple rewind netcode',
    'Stateless InputCmd + SyncState locomotion across 6 modes with 128-tick rollback resimulation.');
  Reg('camera_rail', 'Camera Rig Rail Closest-Point Auto-Dolly & Co-Op Framing Studio', 'CamRail',
    shcCinematicsAudioInput, 352, 'camera rig rail catmull auto dolly look ahead deadzone coop split merge fov',
    'Closest-point Catmull-Rom auto-dolly, velocity look-ahead, deadzone aim & 2P split hysteresis.');
  Reg('meshlet_studio', 'Nanite-Style Meshlet Cluster Builder & Normal-Cone Culler Studio', 'Meshlet',
    shcMaterialsVfxLighting, 353, 'nanite meshlet cluster 64v 124t bounding sphere normal cone backface cull pixel error lod',
    'Greedy 64v/124t spatial meshlets, perspective normal-cone backface rejection & pixel-error LOD.');
  Reg('tet_softbody', 'Chaos Flesh Tetrahedral Volume-Preserving XPBD Soft-Body Studio', 'TetFlesh',
    shcArchitecturePcg, 354, 'chaos flesh tetrahedral xpbd softbody signed volume 6v inversion free tendon',
    '5-tet-per-cell 3D deformable lattices with exact signed-volume 6V XPBD & 0 tet inversions.');
  Reg('mass_traffic', 'MassTraffic Multi-Lane Road Network, Signal Phases & IDM Studio', 'Traffic',
    shcCharactersAiGas, 355, 'masstraffic road lane intersection signal nema red green yellow idm headway car',
    '8-lane urban crossroads, conflict-free NEMA 4-way signal interlocks & IDM safe car-following.');
  Reg('live_cook_auditor', 'Live Coding RTTI State Broker & Release Package Cook Auditor Studio', 'CookLive',
    shcPerformanceQaDeploy, 356, 'live coding rtti hot reload snapshot rehydrate coreredirect alias package cook audit',
    'Live RTTI snapshot/rehydrate with field-rename aliases & Release Package Cook readiness gate.');

  { Horizon 10 (Phases 357-366 — UE 6.0+ Surface GI SH2, Contextual Anim, Targeting Presets, Mutable Customizer, River Spline, Camera Cutaway, GameplayDebugger, Wind/Shockwave, Async Preloader & Collaborative Presence, +10 -> 86 studios) }
  Reg('surface_gi', 'Lumen-Style Surface Cache SH2 GI Probes & Sky-Occlusion Studio', 'GI-SH2',
    shcMaterialsVfxLighting, 357, 'lumen surface cache sh2 spherical harmonics gi irradiance probe sky occlusion color bleed',
    '3D SH2 irradiance probe volume with WorldRay sky-occlusion baking & trilinear color bleed.');
  Reg('contextual_anim', 'Contextual Anim Paired Finisher, Takedown & Co-Op Lift Studio', 'CtxAnim',
    shcCharactersAiGas, 358, 'contextual animation paired finisher stealth takedown parry coop boost ik warp dock',
    '2-actor relative docking slots, approach-cone & WorldRay wall gates, Hermite warp & IK sync.');
  Reg('targeting_studio', 'Targeting System Preset Lock-On Cone, Magnetism & Threat Studio', 'LockOn',
    shcCharactersAiGas, 359, 'targeting system preset lock on cone aim assist magnetism line of sight threat stick flick',
    'Multi-stage Gather/Filter/Score lock-on pipeline, right-stick target flick & aim magnetism.');
  Reg('mutable_studio', 'Mutable Modular Character Customizer, Morphs & Recipe Studio', 'Mutable',
    shcCharactersAiGas, 360, 'mutable character customizer modular armor hair helm clip morph slider swatch recipe',
    'Modular equipment slots, closed-helm hair exclusion, stature/bulk morphs & MUT1 recipe codes.');
  Reg('river_studio', 'Spline Water River / Rapids Flow, Width/Depth & Drift Studio', 'River',
    shcWorldEnvironment, 361, 'river spline water rapids waterfall gorge width depth continuity foam kayak drift',
    'Catmull-Rom variable-width river splines, Q = A * v gorge speedup, whitewater foam & drift.');
  Reg('occluder_fader', 'Smart Camera Occluder Cutaway / Dither Fade & Foliage Parting Studio', 'Cutaway',
    shcCinematicsAudioInput, 362, 'camera occluder cutaway roof wall fade dither alpha foliage grass parting arpg',
    '5-ray WorldRay wall/roof cutaway opacity fader & length-preserving radial tall-grass parting.');
  Reg('gameplay_debugger', 'GameplayDebugger Live 3D HUD & Numpad 0..5 Channels Studio', 'GDebug',
    shcPerformanceQaDeploy, 363, 'gameplay debugger hud numpad channel ai statetree targeting gas mover traffic gi snapshot',
    'Toggleable Numpad 0..5 3D diagnostic overlay & JSON snapshot across AI, LockOn, GAS, Mover & GI.');
  Reg('wind_studio', 'Procedural Foliage Wind Gust Field & Radial Shockwave Studio', 'WindFX',
    shcWorldEnvironment, 364, 'wind directional gust beaufort pivot painter trunk branch leaf sway radial shockwave blast',
    'Beaufort harmonic gusts, finite-speed radial blast shockwave rings & 3-tier trunk/branch sway.');
  Reg('preload_studio', 'Async Asset Preloader, Frame-Budgeted Warmup & VRAM Studio', 'Preload',
    shcPerformanceQaDeploy, 365, 'async asset preloader streamable warmup priority frame budget hitch free vram lru pinned',
    'Priority warmup queue with strict ms/frame hitch prevention & pinned-aware LRU VRAM eviction.');
  Reg('collab_presence', 'Multi-User Collaborative Presence Locks & Sub-Scene Conflict Studio', 'Collab',
    shcPerformanceQaDeploy, 366, 'multi user collaborative presence subtree lock conflict ancestor descendant lease heartbeat',
    'Hierarchical ancestor/descendant subtree reservation locks, lease heartbeats & 86-Studio Hub.');

  { Horizon 11 (Phases 367-376 — UE 6.0+ Substrate Slabs, SmartObject Queues, Aero Foil, Crevice Clutter, Camera Shake/Recoil, Grid2D Fire Spread, Gameplay Message Bus, Octahedral Impostors, Pose Snapshot Trails & Editor Macro Recorder, +10 -> 96 studios) }
  Reg('substrate_studio', 'Substrate Multi-Slab Layered Material Mixer & Energy Studio', 'Substr',
    shcMaterialsVfxLighting, 367, 'substrate multi slab layered material clear coat dust water transmittance fresnel energy conservation',
    'Multi-slab vertical Fresnel/Beer-Lambert material mixer with strict energy conservation.');
  Reg('smart_object_slots', 'Multi-Slot SmartObject Claiming, FIFO Queue & Lockout Studio', 'SmartQ',
    shcCharactersAiGas, 368, 'smart object multi slot claiming fifo wait queue preemption lockout bench anvil',
    'Capacity-bounded multi-slot workstation claiming with FIFO wait-queue & per-slot lockouts.');
  Reg('aero_foil', 'Aerodynamic Wing / Sail Foil Polar, Stall & Thermal Updraft Studio', 'AeroFoil',
    shcWorldEnvironment, 369, 'aerodynamic wing sail glider foil lift drag polar angle of attack critical stall thermal updraft',
    'Real-time C_L/C_D angle-of-attack wing/sail solver with post-stall drop & thermal columns.');
  Reg('crevice_clutter', 'Procedural Wall-Crevice & Seam Micro-Clutter Skirt Studio', 'Crevice',
    shcArchitecturePcg, 370, 'wall crevice seam corner floor skirt micro clutter pebbles moss rubble worldray',
    'WorldRay floor-wall concave corner & crevice detector scattering pebbles, moss & debris skirts.');
  Reg('camera_shake', 'Cinematic Camera Shake Envelope, Recoil & FOV Kickback Studio', 'CamShake',
    shcCinematicsAudioInput, 371, 'camera shake trauma perlin directional weapon recoil recovery fov kickback accessibility',
    'Trauma^2 shake envelopes, damped spring weapon recoil, FOV kickback & 0% accessibility toggle.');
  Reg('fire_grid_2d', 'Niagara Grid2D Cellular Fire Spread, Wind Front & Rain Studio', 'Fire2D',
    shcMaterialsVfxLighting, 372, 'niagara grid2d fire spread combustion cellular downwind flame stone firebreak rain douse ash',
    '2D fuel/temperature cellular fire propagation with wind advection, firebreaks & rain douse.');
  Reg('gameplay_messenger', 'Gameplay Message Bus & Squad Bark Priority Preemption Studio', 'MsgBus',
    shcCharactersAiGas, 373, 'gameplay message bus pub sub hierarchical tag squad radio bark priority preemption antispam',
    'Dot-boundary GameplayTag pub/sub router & squad voice bark arbiter with emergency preemption.');
  Reg('octahedral_impostor', 'Octahedral Billboard Impostor Atlas & 3-View Blend Studio', 'Impostor',
    shcMaterialsVfxLighting, 374, 'octahedral billboard impostor hemi uv atlas 3 view barycentric simplex lod card',
    'Bijective upper-hemisphere octahedral UV projection & 3-tile barycentric LOD card blending.');
  Reg('pose_snapshot', 'Skeletal Pose Snapshot, Dash Ghost Trail & Statue Freeze Studio', 'PoseSnap',
    shcCharactersAiGas, 375, 'pose snapshot skeletal dash ghost afterimage trail ring buffer alpha decay petrified statue',
    'Zero-allocation ring-buffer dash ghost silhouettes, spectral decay & petrified statue freeze.');
  Reg('macro_recorder', 'Editor Action Macro Recorder & 96-Studio Hub Studio', 'Macro',
    shcPerformanceQaDeploy, 376, 'editor action macro recorder batch transform replay parameterized json 96 studio hub mcp',
    'Multi-step filtered transform macro recording, JSON export/import, replay & 96-Studio Hub.');

  { Horizon 12 (Phases 377-386 — Planar Portals, AI Sensory Perception, Procedural Ivy Climber, Footstep Director, Dynamic Gravity, Cloud Shadows, Snow/Mud Trail Stamper, Tactical Cover Scanner, Catenary Cables & 3-Way Scene Diff/Merge, +10 -> 106 studios) }
  Reg('portal_studio', 'Planar Portal & Seamless Mirror Oblique Teleport Studio', 'Portal',
    shcWorldEnvironment, 377, 'planar portal doorway mirror oblique frustum clip plane teleport turnaround lockout',
    'SE(3) 180-degree doorway turnaround portals, planar mirrors & Lengyel oblique clip planes.');
  Reg('sensory_perception', 'AI Sensory Perception Sight, Hearing & Scent Studio', 'Sense',
    shcCharactersAiGas, 378, 'ai sensory perception foveal peripheral sight worldray wall muffled hearing decibel scent',
    'Dual-cone foveal/peripheral sight occlusion, wall-muffled dB hearing & olfactory scent trails.');
  Reg('ivy_climber', 'Procedural Ivy, Vine & Root Surface Climber Studio', 'Ivy',
    shcArchitecturePcg, 379, 'procedural ivy vine creeper root climber thigmotropism phototropism masonry wall leaf',
    'WorldRay thigmotropic botanical tendril growth, lateral branching & leaf clusters.');
  Reg('footstep_director', 'Skeletal Footstep Decal, Splash & Acoustic Surface Studio', 'Footstep',
    shcCinematicsAudioInput, 380, 'skeletal footstep gait phase boot print decal snow puddle metal acoustic surface splash',
    'Alternating Left/Right stride crossings, WorldRay surface lookup & speed/armor audio scaling.');
  Reg('gravity_field', 'Dynamic Gravity Well, Planetary Walk & Ringworld Tube Studio', 'Gravity',
    shcWorldEnvironment, 381, 'dynamic gravity well spherical planet walk hollow cylinder ringworld ceiling slerp priority',
    'Spherical planetoid attractors, O''Neill spinning cylinder interiors & antipodal-safe Up slerp.');
  Reg('cloud_shadows', '2.5D Atmospheric Cloud Shadow & Crepuscular God-Ray Studio', 'Clouds',
    shcMaterialsVfxLighting, 382, 'atmospheric cloud shadow scroller wind dual octave solar offset mie crepuscular god ray',
    'Solar-offset wind-advected dual-octave cloud transmittance & Henyey-Greenstein light shafts.');
  Reg('trail_stamper', 'Interactive Snow, Mud & Sand Deformation Trail Studio', 'SnowTrk',
    shcWorldEnvironment, 383, 'snow mud sand deformation trail stamper furrow rut rim berm compaction weather refill',
    'Persistent 2D depression & raised collar berm grid with bilinear normals & snowfall refill.');
  Reg('cover_point_scanner', 'Tactical Cover Point Scanner, Peek/Lean & Crossfire Studio', 'CoverAI',
    shcCharactersAiGas, 384, 'tactical cover scanner waist crouch peek standing pillar corner lean flank crossfire',
    'Automated WorldRay waist over-peek & pillar corner-lean baking with multi-threat crossfire.');
  Reg('catenary_cable', 'Procedural Catenary Cable, Powerline Sag & Lantern Studio', 'Cable',
    shcArchitecturePcg, 385, 'catenary cable powerline hyperbolic cosh sag pendulum sway lantern garland insulator',
    'Exact hyperbolic cosine sag solver, lateral wind sway & arc-length lantern attachments.');
  Reg('prefab_diff_merge', 'Three-Way Scene & Prefab Diff/Merge & 106-Studio Hub', 'Merge3',
    shcPerformanceQaDeploy, 386, 'three way scene prefab diff merge ancestor ours theirs conflict resolution 106 studio hub',
    'Structural 3-way Ancestor/Ours/Theirs JSON merge, conflict policies & 106-Studio Hub / 20 MCP.');
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
  NetMgrCount, ReplicatedCount, UnboundEqsCount: Integer;
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
    if (C is TCastleVolumetricAtmosphere) or (C is TCastleReflectionProbe) or
       (C is TCastleAutoTilemap) or (C is TCastleFlipbook2D) or
       (C is TCastleVoxelVolume) or (C is TCastleShallowFluidSurface) or
       (C is TCastleHlodClusterManager) then
      BumpSub(shcWorldEnvironment);

    { Materials, Shaders, VFX & PostFX }
    if (C is TCastleMaterialGraph) or (C is TCastleMaterialGraphBehavior) then
      BumpSub(shcMaterialsVfxLighting);
    if C is TCastleStylizedShaderBehavior then BumpSub(shcMaterialsVfxLighting);
    if C is TCastleParticleEmitter then BumpSub(shcMaterialsVfxLighting);
    if (C is TCastlePostProcessVolume) or (C is TCastlePostProcessStack) then
      BumpSub(shcMaterialsVfxLighting);
    if C is TCastleDecalProjector then BumpSub(shcMaterialsVfxLighting);
    if C is TCastleVariantSetManager then BumpSub(shcMaterialsVfxLighting);
    if (C is TCastleRibbonTrail) or (C is TCastleLightningBeam) then BumpSub(shcMaterialsVfxLighting);
    if C is TCastlePcgSettlement then BumpSub(shcArchitecturePcg);
    if (C is TCastlePoseSearchDatabase) or (C is TCastleMotionMatchingBehavior) or
       (C is TCastleMassEntityManager) or (C is TCastlePhysicalHitRagdollBehavior) then
      BumpSub(shcCharactersAiGas);
    if (C is TCastleCommonUiRouter) or (C is TCastleMvvmBinder) or
       (C is TCastleSpringArm) or (C is TCastleSoundscapeDirector) then
      BumpSub(shcCinematicsAudioInput);
    if (C is TCastleTerrainErosionBaker) or (C is TCastleDataLayerManager) or
       (C is TCastleDataLayerTagBehavior) then
      BumpSub(shcWorldEnvironment);
    if (C is TCastleMegaLightsManager) or (C is TCastleLightFunctionBehavior) then
      BumpSub(shcMaterialsVfxLighting);
    if (C is TCastleStateTreeBehavior) or (C is TCastleControlRigBehavior) or
       (C is TCastleGameplayCueDirector) or (C is TCastleJiggleBoneBehavior) then
      BumpSub(shcCharactersAiGas);
    if C is TCastleRuntimeVirtualTexture then
      BumpSub(shcWorldEnvironment);
    if (C is TCastleGroomComponent) or (C is TCastleMeshletClusterer) then
      BumpSub(shcMaterialsVfxLighting);
    if C is TCastleTetSoftBody then
      BumpSub(shcArchitecturePcg);
    if C is TCastleCameraRigRail then
      BumpSub(shcCinematicsAudioInput);
    if (C is TCastleChooserTable) or (C is TCastleTraversalBehavior) or
       (C is TCastleMoverBehavior) or (C is TCastleMassTrafficManager) then
      BumpSub(shcCharactersAiGas);
    if C is TCastleSurfaceGiGrid then
      BumpSub(shcMaterialsVfxLighting);
    if (C is TCastleContextualAnimScene) or (C is TCastleTargetingBehavior) or
       (C is TCastleMutableCharacter) then
      BumpSub(shcCharactersAiGas);
    if (C is TCastleRiverSpline) or (C is TCastleWindFieldDirector) then
      BumpSub(shcWorldEnvironment);
    if C is TCastleCameraOccluderFader then
      BumpSub(shcCinematicsAudioInput);
    if (C is TCastleGameplayDebugger) or (C is TCastleAssetPreloadQueue) then
      BumpSub(shcPerformanceQaDeploy);

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
    if (C is TCastleGeometryScriptMesh) or (C is TCastleLSystemBotanical) then
      BumpSub(shcArchitecturePcg);

    { Characters, IK, AI, GAS & Narrative }
    if C is TCastleAbilitySystemBehavior then BumpSub(shcCharactersAiGas);
    if (C is TCastleWheeledVehicle) or (C is TCastleBlendSpace2DBehavior) or
       (C is TCastleAnimMontageBehavior) or (C is TCastleInventoryBehavior) or
       (C is TCastleLootTable) then
      BumpSub(shcCharactersAiGas);
    if C is TCastleEqsQueryBehavior then
    begin
      BumpSub(shcCharactersAiGas);
      if (TCastleEqsQueryBehavior(C).ThreatTransform = nil) and
         (TCastleEqsQueryBehavior(C).Preset in [epTakeCoverFromThreat, epSniperLineOfSightVantage, epFlankRearSurround]) then
        Inc(UnboundEqsCount);
    end;
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
    if (C is TCastleAudioBusMixer) or (C is TCastleAudioZone) or
       (C is TCastleMetaSoundSynth) or (C is TCastleFootstepSurfaceBehavior) or
       (C is TCastleMusicStemDirector) then
      BumpSub(shcCinematicsAudioInput);
    if C is TCastleInputMapManager then
    begin
      BumpSub(shcCinematicsAudioInput);
      TCastleInputMapManager(C).DetectBindingConflicts(InputConflicts);
    end;

    { Performance, Save/Replay, L10n & QA }
    if C is TCastleScalabilityManager then BumpSub(shcPerformanceQaDeploy);
    if C is TCastleNetReplicationManager then
    begin
      Inc(NetMgrCount);
      BumpSub(shcPerformanceQaDeploy);
    end;
    if C is TCastleReplicatedBehavior then
    begin
      Inc(ReplicatedCount);
      BumpSub(shcPerformanceQaDeploy);
    end;
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

    { Horizon 11 Subsystems }
    if (C is TCastleSubstrateMaterial) or (C is TCastleFireSpreadGrid) or
       (C is TCastleOctahedralImpostor) then
      BumpSub(shcMaterialsVfxLighting);
    if (C is TCastleMultiSlotSmartObject) or (C is TCastleGameplayMessenger) or
       (C is TCastlePoseSnapshotTrail) then
      BumpSub(shcCharactersAiGas);
    if C is TCastleAeroFoilBehavior then BumpSub(shcWorldEnvironment);
    if C is TCastleCreviceClutterVolume then BumpSub(shcArchitecturePcg);
    if C is TCastleCameraShakeDirector then BumpSub(shcCinematicsAudioInput);

    { Horizon 12 Subsystems }
    if (C is TCastlePortalGateway) or (C is TCastleGravityField) or
       (C is TCastleTrailStamper) then
      BumpSub(shcWorldEnvironment);
    if C is TCastleCloudShadowProjector then BumpSub(shcMaterialsVfxLighting);
    if (C is TCastleIvyClimber) or (C is TCastleCatenaryCable) then
      BumpSub(shcArchitecturePcg);
    if (C is TCastleSensoryPerception) or (C is TCastleCoverPointScanner) then
      BumpSub(shcCharactersAiGas);
    if C is TCastleFootstepDirector then BumpSub(shcCinematicsAudioInput);
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
    NetMgrCount := 0;
    ReplicatedCount := 0;
    UnboundEqsCount := 0;
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

    if (ReplicatedCount > 0) and (NetMgrCount = 0) then
      Result.AddIssue(15, 'netcode_studio',
        Format('%d TCastleReplicatedBehavior actor(s) exist without a TCastleNetReplicationManager in the design.',
          [ReplicatedCount]));

    if UnboundEqsCount > 0 then
      Result.AddIssue(10, 'eqs_studio',
        Format('%d TCastleEqsQueryBehavior agent(s) have ThreatTransform=nil for tactical LoS/Flank scoring.',
          [UnboundEqsCount]));

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
