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

{ Gerstner Ocean / River Water Volume, Shoreline Crest Foam & 4-Pontoon
  Archimedes Buoyancy Behavior (@link(TCastleWaterVolume),
  @link(TCastleBuoyancyBehavior)) (Phase 308 — UE 6.0+ Water System & Chaos Buoyancy Parity). }
unit CastleWaterSystem;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform,
  CastleBehaviors, CastleScene, X3DNodes;

type
  { Built-in ocean, lake, river, storm, and swamp presets. }
  TWaterBodyPreset = (
    wbpCustom,
    wbpCalmLake,
    wbpOpenOceanSwell,
    wbpFlowingRiver,
    wbpStormyHighSeas,
    wbpToxicSwamp
  );

  { 3D Gerstner wave & directional river-current water body volume.
    Generates a @code(csTransient) animated PBR translucent water surface mesh
    with crest foam vertex coloring and exposes analytical @link(SampleSurfaceWorld)
    queries for @link(TCastleBuoyancyBehavior), gameplay triggers, and VFX. }
  TCastleWaterVolume = class(TCastleTransform)
  public
    const
      DefaultSizeX = 40.0;
      DefaultSizeZ = 40.0;
      DefaultDepth = 8.0;
      DefaultGridSubdivisions = 20;
      DefaultWaveAmplitude = 0.45;
      DefaultWaveLength = 12.0;
      DefaultWaveSteepness = 0.45;
      DefaultWaveSpeed = 1.0;
      DefaultWaterOpacity = 0.78;
      DefaultFoamCrestThreshold = 0.62;
      DefaultLinearWaterDrag = 2.4;
      DefaultAngularWaterDrag = 3.0;
  strict private
    FPreset: TWaterBodyPreset;
    FInfiniteOcean: Boolean;
    FSizeX: Single;
    FSizeZ: Single;
    FDepth: Single;
    FGridSubdivisions: Integer;
    FWaveAmplitude: Single;
    FWaveLength: Single;
    FWaveSteepness: Single;
    FWaveSpeed: Single;
    FFlowSpeedX: Single;
    FFlowSpeedZ: Single;
    FWaterOpacity: Single;
    FFoamCrestThreshold: Single;
    FLinearWaterDrag: Single;
    FAngularWaterDrag: Single;
    FShallowColor: TCastleColorRGB;
    FDeepColor: TCastleColorRGB;
    FFoamColor: TCastleColorRGB;
    FShallowColorPersistent: TCastleColorRGBPersistent;
    FDeepColorPersistent: TCastleColorRGBPersistent;
    FFoamColorPersistent: TCastleColorRGBPersistent;
    FElapsedTime: Single;
    FAnimateInEditor: Boolean;

    FRenderScene: TCastleScene;
    FRootNode: TX3DRootNode;
    FAppearanceNode: TAppearanceNode;
    FMaterialNode: TPhysicalMaterialNode;
    FTriSetNode: TTriangleSetNode;
    FCoordNode: TCoordinateNode;
    FNormalNode: TNormalNode;
    FColorNode: TColorRGBANode;

    procedure SetPreset(const Value: TWaterBodyPreset);
    procedure SetInfiniteOcean(const Value: Boolean);
    procedure SetSizeX(const Value: Single);
    procedure SetSizeZ(const Value: Single);
    procedure SetDepth(const Value: Single);
    procedure SetGridSubdivisions(const Value: Integer);
    procedure SetWaveAmplitude(const Value: Single);
    procedure SetWaveLength(const Value: Single);
    procedure SetWaveSteepness(const Value: Single);
    procedure SetWaveSpeed(const Value: Single);
    procedure SetFlowSpeedX(const Value: Single);
    procedure SetFlowSpeedZ(const Value: Single);
    procedure SetWaterOpacity(const Value: Single);
    procedure SetFoamCrestThreshold(const Value: Single);
    procedure SetLinearWaterDrag(const Value: Single);
    procedure SetAngularWaterDrag(const Value: Single);
    procedure SetShallowColor(const Value: TCastleColorRGB);
    procedure SetDeepColor(const Value: TCastleColorRGB);
    procedure SetFoamColor(const Value: TCastleColorRGB);
    function GetShallowColorForPersistent: TCastleColorRGB;
    procedure SetShallowColorForPersistent(const AValue: TCastleColorRGB);
    function GetDeepColorForPersistent: TCastleColorRGB;
    procedure SetDeepColorForPersistent(const AValue: TCastleColorRGB);
    function GetFoamColorForPersistent: TCastleColorRGB;
    procedure SetFoamColorForPersistent(const AValue: TCastleColorRGB);

    procedure EnsureRenderScene;
    procedure SyncMaterialProperties;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PresetDisplayName(const APreset: TWaterBodyPreset): String; static;

    property ShallowColor: TCastleColorRGB read FShallowColor write SetShallowColor;
    property DeepColor: TCastleColorRGB read FDeepColor write SetDeepColor;
    property FoamColor: TCastleColorRGB read FFoamColor write SetFoamColor;
    property ElapsedTime: Single read FElapsedTime write FElapsedTime;

    procedure ApplyPreset(const APreset: TWaterBodyPreset);
    procedure RebuildWaterMesh;
    procedure StepSimulation(const Dt: Single);

    { Analytical 4-octave directional Gerstner wave evaluation in local volume coordinates. }
    procedure SampleSurfaceLocal(const LocalX, LocalZ, AtTimeSec: Single;
      out OutLocalPos, OutLocalNormal: TVector3; out OutFoamFactor: Single);

    { Analytical world-space water surface query at @code(WorldPos).
      Returns @false when @code(WorldPos) lies outside the XZ footprint (unless
      @link(InfiniteOcean) is @true) or below @code(-Depth). }
    function SampleSurfaceWorld(const WorldPos: TVector3; const AtTimeSec: Single;
      out OutSurfaceWorldY: Single; out OutWorldNormal, OutWorldFlowVel: TVector3;
      out OutFoamFactor: Single): Boolean;

    function WaterSummaryBadge: String;
  published
    property Preset: TWaterBodyPreset read FPreset write SetPreset default wbpOpenOceanSwell;
    property InfiniteOcean: Boolean read FInfiniteOcean write SetInfiniteOcean default false;
    property SizeX: Single read FSizeX write SetSizeX {$ifdef FPC}default DefaultSizeX{$endif};
    property SizeZ: Single read FSizeZ write SetSizeZ {$ifdef FPC}default DefaultSizeZ{$endif};
    property Depth: Single read FDepth write SetDepth {$ifdef FPC}default DefaultDepth{$endif};
    property GridSubdivisions: Integer read FGridSubdivisions write SetGridSubdivisions
      default DefaultGridSubdivisions;
    property WaveAmplitude: Single read FWaveAmplitude write SetWaveAmplitude
      {$ifdef FPC}default DefaultWaveAmplitude{$endif};
    property WaveLength: Single read FWaveLength write SetWaveLength
      {$ifdef FPC}default DefaultWaveLength{$endif};
    property WaveSteepness: Single read FWaveSteepness write SetWaveSteepness
      {$ifdef FPC}default DefaultWaveSteepness{$endif};
    property WaveSpeed: Single read FWaveSpeed write SetWaveSpeed
      {$ifdef FPC}default DefaultWaveSpeed{$endif};
    property FlowSpeedX: Single read FFlowSpeedX write SetFlowSpeedX {$ifdef FPC}default 0.0{$endif};
    property FlowSpeedZ: Single read FFlowSpeedZ write SetFlowSpeedZ {$ifdef FPC}default 0.0{$endif};
    property WaterOpacity: Single read FWaterOpacity write SetWaterOpacity
      {$ifdef FPC}default DefaultWaterOpacity{$endif};
    property FoamCrestThreshold: Single read FFoamCrestThreshold write SetFoamCrestThreshold
      {$ifdef FPC}default DefaultFoamCrestThreshold{$endif};
    property LinearWaterDrag: Single read FLinearWaterDrag write SetLinearWaterDrag
      {$ifdef FPC}default DefaultLinearWaterDrag{$endif};
    property AngularWaterDrag: Single read FAngularWaterDrag write SetAngularWaterDrag
      {$ifdef FPC}default DefaultAngularWaterDrag{$endif};
    property AnimateInEditor: Boolean read FAnimateInEditor write FAnimateInEditor default true;
    property ShallowColorPersistent: TCastleColorRGBPersistent read FShallowColorPersistent;
    property DeepColorPersistent: TCastleColorRGBPersistent read FDeepColorPersistent;
    property FoamColorPersistent: TCastleColorRGBPersistent read FFoamColorPersistent;
  end;

  { 4-Pontoon Archimedes buoyancy, hydrodynamic drag, Gerstner wave pitch/roll
    alignment, and river current drift behavior for floating hulls, crates,
    barrels, and boats. }
  TCastleBuoyancyBehavior = class(TCastleBehavior)
  public
    const
      DefaultHullWidth = 1.6;
      DefaultHullLength = 2.8;
      DefaultHullDraft = 0.8;
      DefaultBuoyancyMultiplier = 2.2;
      DefaultPitchRollStrength = 5.5;
  strict private
    FEnabled: Boolean;
    FWaterVolume: TCastleWaterVolume;
    FHullWidth: Single;
    FHullLength: Single;
    FHullDraft: Single;
    FBuoyancyMultiplier: Single;
    FPitchRollStrength: Single;
    FApplyFlowDrift: Boolean;
    FVelocity: TVector3;
    FSubmergedPontoonCount: Integer;
    FAverageSubmergence: Single;

    procedure SetWaterVolume(const Value: TCastleWaterVolume);
    procedure SetHullWidth(const Value: Single);
    procedure SetHullLength(const Value: Single);
    procedure SetHullDraft(const Value: Single);
    procedure SetBuoyancyMultiplier(const Value: Single);
    procedure SetPitchRollStrength(const Value: Single);
    function ResolveActiveWaterVolume(const WorldPos: TVector3): TCastleWaterVolume;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    function CanAttachToParent(const NewParent: TCastleTransform;
      out ReasonWhyCannot: String): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    property Velocity: TVector3 read FVelocity write FVelocity;
    property SubmergedPontoonCount: Integer read FSubmergedPontoonCount;
    property AverageSubmergence: Single read FAverageSubmergence;

    procedure ResetMotion;

    { Sample the 4 hull corner pontoons against @link(WaterVolume) (or an
      auto-discovered water volume in the hierarchy). Returns the number of
      currently submerged pontoons (@code(0..4)). }
    function SampleHullPontoons(
      out OutPontoonWorld: array of TVector3;
      out OutPontoonWaterY: array of Single;
      out OutAvgNormal, OutAvgFlow: TVector3): Integer;

    { Advance 4-pontoon buoyancy, gravity, water drag, flow drift, and wave
      normal pitch/roll alignment by @code(Dt) seconds. }
    procedure StepBuoyancy(const Dt: Single);

    function BuoyancySummaryBadge: String;
  published
    property Enabled: Boolean read FEnabled write FEnabled default true;
    property WaterVolume: TCastleWaterVolume read FWaterVolume write SetWaterVolume;
    property HullWidth: Single read FHullWidth write SetHullWidth
      {$ifdef FPC}default DefaultHullWidth{$endif};
    property HullLength: Single read FHullLength write SetHullLength
      {$ifdef FPC}default DefaultHullLength{$endif};
    property HullDraft: Single read FHullDraft write SetHullDraft
      {$ifdef FPC}default DefaultHullDraft{$endif};
    property BuoyancyMultiplier: Single read FBuoyancyMultiplier write SetBuoyancyMultiplier
      {$ifdef FPC}default DefaultBuoyancyMultiplier{$endif};
    property PitchRollStrength: Single read FPitchRollStrength write SetPitchRollStrength
      {$ifdef FPC}default DefaultPitchRollStrength{$endif};
    property ApplyFlowDrift: Boolean read FApplyFlowDrift write FApplyFlowDrift default true;
  end;

implementation

uses
  Math,
  CastleUtils, CastleStringUtils, CastleRenderOptions, CastleComponentSerialize;

{ Hierarchy-invariant transform helpers (safe even when World = nil) --------- }

procedure GetWaterHierarchyMatrices(const T: TCastleTransform;
  out M, MInv: TMatrix4);
var
  Cur: TCastleTransform;
begin
  M := TMatrix4.Identity;
  Cur := T;
  while (Cur <> nil) and (not (Cur is TCastleAbstractRootTransform)) do
  begin
    M := Cur.Transform * M;
    Cur := Cur.Parent;
  end;
  if not M.TryInverse(MInv) then
    MInv := TMatrix4.Identity;
end;

function SafeTransformLocalToWorld(const T: TCastleTransform; const P: TVector3): TVector3;
var
  M, MInv: TMatrix4;
begin
  GetWaterHierarchyMatrices(T, M, MInv);
  Result := M.MultPoint(P);
end;

function SafeTransformWorldToLocal(const T: TCastleTransform; const P: TVector3): TVector3;
var
  M, MInv: TMatrix4;
begin
  GetWaterHierarchyMatrices(T, M, MInv);
  Result := MInv.MultPoint(P);
end;

function SafeTransformLocalDirToWorld(const T: TCastleTransform; const D: TVector3): TVector3;
var
  M, MInv: TMatrix4;
begin
  GetWaterHierarchyMatrices(T, M, MInv);
  Result := M.MultDirection(D);
end;

{ TCastleWaterVolume --------------------------------------------------------- }

constructor TCastleWaterVolume.Create(AOwner: TComponent);
begin
  inherited;
  FInfiniteOcean := false;
  FSizeX := DefaultSizeX;
  FSizeZ := DefaultSizeZ;
  FDepth := DefaultDepth;
  FGridSubdivisions := DefaultGridSubdivisions;
  FWaveAmplitude := DefaultWaveAmplitude;
  FWaveLength := DefaultWaveLength;
  FWaveSteepness := DefaultWaveSteepness;
  FWaveSpeed := DefaultWaveSpeed;
  FFlowSpeedX := 0.0;
  FFlowSpeedZ := 0.0;
  FWaterOpacity := DefaultWaterOpacity;
  FFoamCrestThreshold := DefaultFoamCrestThreshold;
  FLinearWaterDrag := DefaultLinearWaterDrag;
  FAngularWaterDrag := DefaultAngularWaterDrag;
  FShallowColor := Vector3(0.10, 0.58, 0.68);
  FDeepColor := Vector3(0.03, 0.18, 0.36);
  FFoamColor := Vector3(0.92, 0.96, 1.00);
  FElapsedTime := 0.0;
  FAnimateInEditor := true;

  FShallowColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FShallowColorPersistent.SetSubComponent(true);
  FShallowColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetShallowColorForPersistent;
  FShallowColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetShallowColorForPersistent;
  FShallowColorPersistent.InternalDefaultValue := FShallowColor;

  FDeepColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FDeepColorPersistent.SetSubComponent(true);
  FDeepColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetDeepColorForPersistent;
  FDeepColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetDeepColorForPersistent;
  FDeepColorPersistent.InternalDefaultValue := FDeepColor;

  FFoamColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FFoamColorPersistent.SetSubComponent(true);
  FFoamColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetFoamColorForPersistent;
  FFoamColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetFoamColorForPersistent;
  FFoamColorPersistent.InternalDefaultValue := FFoamColor;

  ApplyPreset(wbpOpenOceanSwell);
end;

destructor TCastleWaterVolume.Destroy;
begin
  if FRenderScene <> nil then
  begin
    Remove(FRenderScene);
    FreeAndNil(FRenderScene);
  end;
  FreeAndNil(FShallowColorPersistent);
  FreeAndNil(FDeepColorPersistent);
  FreeAndNil(FFoamColorPersistent);
  inherited;
end;

procedure TCastleWaterVolume.Loaded;
begin
  inherited;
  RebuildWaterMesh;
end;

function TCastleWaterVolume.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'InfiniteOcean', 'SizeX', 'SizeZ', 'Depth', 'GridSubdivisions',
       'WaveAmplitude', 'WaveLength', 'WaveSteepness', 'WaveSpeed',
       'FlowSpeedX', 'FlowSpeedZ', 'WaterOpacity', 'FoamCrestThreshold',
       'LinearWaterDrag', 'AngularWaterDrag', 'AnimateInEditor',
       'ShallowColorPersistent', 'DeepColorPersistent', 'FoamColorPersistent'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleWaterVolume.PresetDisplayName(
  const APreset: TWaterBodyPreset): String;
begin
  case APreset of
    wbpCustom: Result := 'Custom Water';
    wbpCalmLake: Result := 'Calm Alpine Lake';
    wbpOpenOceanSwell: Result := 'Open Ocean Swell';
    wbpFlowingRiver: Result := 'Flowing River Current';
    wbpStormyHighSeas: Result := 'Stormy High Seas';
    wbpToxicSwamp: Result := 'Viscous Toxic Swamp';
  end;
end;

function TCastleWaterVolume.GetShallowColorForPersistent: TCastleColorRGB;
begin
  Result := FShallowColor;
end;

procedure TCastleWaterVolume.SetShallowColorForPersistent(const AValue: TCastleColorRGB);
begin
  ShallowColor := AValue;
end;

function TCastleWaterVolume.GetDeepColorForPersistent: TCastleColorRGB;
begin
  Result := FDeepColor;
end;

procedure TCastleWaterVolume.SetDeepColorForPersistent(const AValue: TCastleColorRGB);
begin
  DeepColor := AValue;
end;

function TCastleWaterVolume.GetFoamColorForPersistent: TCastleColorRGB;
begin
  Result := FFoamColor;
end;

procedure TCastleWaterVolume.SetFoamColorForPersistent(const AValue: TCastleColorRGB);
begin
  FoamColor := AValue;
end;

procedure TCastleWaterVolume.SetPreset(const Value: TWaterBodyPreset);
begin
  if FPreset <> Value then
  begin
    if Value = wbpCustom then
      FPreset := wbpCustom
    else
      ApplyPreset(Value);
  end;
end;

procedure TCastleWaterVolume.ApplyPreset(const APreset: TWaterBodyPreset);
begin
  FPreset := APreset;
  case APreset of
    wbpCalmLake:
      begin
        FWaveAmplitude := 0.10;
        FWaveLength := 8.0;
        FWaveSteepness := 0.22;
        FWaveSpeed := 0.75;
        FFlowSpeedX := 0.0;
        FFlowSpeedZ := 0.0;
        FWaterOpacity := 0.72;
        FFoamCrestThreshold := 0.82;
        FLinearWaterDrag := 2.0;
        FAngularWaterDrag := 2.8;
        FShallowColor := Vector3(0.14, 0.66, 0.72);
        FDeepColor := Vector3(0.04, 0.24, 0.42);
        FFoamColor := Vector3(0.92, 0.97, 1.00);
      end;

    wbpOpenOceanSwell, wbpCustom:
      begin
        if APreset = wbpCustom then
          FPreset := wbpCustom
        else
          FPreset := wbpOpenOceanSwell;
        FWaveAmplitude := 0.55;
        FWaveLength := 14.0;
        FWaveSteepness := 0.48;
        FWaveSpeed := 1.0;
        FFlowSpeedX := 0.25;
        FFlowSpeedZ := 0.0;
        FWaterOpacity := 0.80;
        FFoamCrestThreshold := 0.60;
        FLinearWaterDrag := 2.4;
        FAngularWaterDrag := 3.0;
        FShallowColor := Vector3(0.09, 0.54, 0.66);
        FDeepColor := Vector3(0.02, 0.14, 0.32);
        FFoamColor := Vector3(0.94, 0.97, 1.00);
      end;

    wbpFlowingRiver:
      begin
        FWaveAmplitude := 0.18;
        FWaveLength := 6.5;
        FWaveSteepness := 0.35;
        FWaveSpeed := 1.35;
        FFlowSpeedX := 2.8;
        FFlowSpeedZ := 0.0;
        FWaterOpacity := 0.75;
        FFoamCrestThreshold := 0.55;
        FLinearWaterDrag := 2.6;
        FAngularWaterDrag := 3.2;
        FShallowColor := Vector3(0.16, 0.60, 0.58);
        FDeepColor := Vector3(0.05, 0.26, 0.34);
        FFoamColor := Vector3(0.90, 0.95, 0.98);
      end;

    wbpStormyHighSeas:
      begin
        FWaveAmplitude := 1.35;
        FWaveLength := 20.0;
        FWaveSteepness := 0.68;
        FWaveSpeed := 1.30;
        FFlowSpeedX := 0.90;
        FFlowSpeedZ := 0.45;
        FWaterOpacity := 0.88;
        FFoamCrestThreshold := 0.44;
        FLinearWaterDrag := 2.8;
        FAngularWaterDrag := 3.5;
        FShallowColor := Vector3(0.08, 0.32, 0.40);
        FDeepColor := Vector3(0.02, 0.08, 0.16);
        FFoamColor := Vector3(0.92, 0.95, 0.98);
      end;

    wbpToxicSwamp:
      begin
        FWaveAmplitude := 0.07;
        FWaveLength := 5.0;
        FWaveSteepness := 0.18;
        FWaveSpeed := 0.45;
        FFlowSpeedX := 0.0;
        FFlowSpeedZ := 0.0;
        FWaterOpacity := 0.92;
        FFoamCrestThreshold := 0.72;
        FLinearWaterDrag := 5.2;
        FAngularWaterDrag := 5.8;
        FShallowColor := Vector3(0.36, 0.68, 0.16);
        FDeepColor := Vector3(0.10, 0.24, 0.06);
        FFoamColor := Vector3(0.68, 0.92, 0.34);
      end;
  end;

  if not (csLoading in ComponentState) then
  begin
    SyncMaterialProperties;
    RebuildWaterMesh;
  end;
end;

procedure TCastleWaterVolume.SetInfiniteOcean(const Value: Boolean);
begin
  FInfiniteOcean := Value;
end;

procedure TCastleWaterVolume.SetSizeX(const Value: Single);
var
  V: Single;
begin
  V := Max(1.0, Value);
  if not SameValue(FSizeX, V) then
  begin
    FSizeX := V;
    if not (csLoading in ComponentState) then
      RebuildWaterMesh;
  end;
end;

procedure TCastleWaterVolume.SetSizeZ(const Value: Single);
var
  V: Single;
begin
  V := Max(1.0, Value);
  if not SameValue(FSizeZ, V) then
  begin
    FSizeZ := V;
    if not (csLoading in ComponentState) then
      RebuildWaterMesh;
  end;
end;

procedure TCastleWaterVolume.SetDepth(const Value: Single);
begin
  FDepth := Max(0.2, Value);
end;

procedure TCastleWaterVolume.SetGridSubdivisions(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 4, 80);
  if FGridSubdivisions <> V then
  begin
    FGridSubdivisions := V;
    if not (csLoading in ComponentState) then
      RebuildWaterMesh;
  end;
end;

procedure TCastleWaterVolume.SetWaveAmplitude(const Value: Single);
var
  V: Single;
begin
  V := Clamped(Value, 0.0, 20.0);
  if not SameValue(FWaveAmplitude, V) then
  begin
    FWaveAmplitude := V;
    if not (csLoading in ComponentState) then
      RebuildWaterMesh;
  end;
end;

procedure TCastleWaterVolume.SetWaveLength(const Value: Single);
var
  V: Single;
begin
  V := Max(0.5, Value);
  if not SameValue(FWaveLength, V) then
  begin
    FWaveLength := V;
    if not (csLoading in ComponentState) then
      RebuildWaterMesh;
  end;
end;

procedure TCastleWaterVolume.SetWaveSteepness(const Value: Single);
var
  V: Single;
begin
  V := Clamped(Value, 0.0, 1.0);
  if not SameValue(FWaveSteepness, V) then
  begin
    FWaveSteepness := V;
    if not (csLoading in ComponentState) then
      RebuildWaterMesh;
  end;
end;

procedure TCastleWaterVolume.SetWaveSpeed(const Value: Single);
begin
  FWaveSpeed := Clamped(Value, 0.0, 10.0);
end;

procedure TCastleWaterVolume.SetFlowSpeedX(const Value: Single);
begin
  FFlowSpeedX := Clamped(Value, -50.0, 50.0);
end;

procedure TCastleWaterVolume.SetFlowSpeedZ(const Value: Single);
begin
  FFlowSpeedZ := Clamped(Value, -50.0, 50.0);
end;

procedure TCastleWaterVolume.SetWaterOpacity(const Value: Single);
begin
  FWaterOpacity := Clamped(Value, 0.05, 1.0);
  SyncMaterialProperties;
end;

procedure TCastleWaterVolume.SetFoamCrestThreshold(const Value: Single);
begin
  FFoamCrestThreshold := Clamped(Value, 0.05, 0.99);
  if not (csLoading in ComponentState) then
    RebuildWaterMesh;
end;

procedure TCastleWaterVolume.SetLinearWaterDrag(const Value: Single);
begin
  FLinearWaterDrag := Clamped(Value, 0.0, 30.0);
end;

procedure TCastleWaterVolume.SetAngularWaterDrag(const Value: Single);
begin
  FAngularWaterDrag := Clamped(Value, 0.0, 30.0);
end;

procedure TCastleWaterVolume.SetShallowColor(const Value: TCastleColorRGB);
begin
  FShallowColor := Value;
  if not (csLoading in ComponentState) then
    RebuildWaterMesh;
end;

procedure TCastleWaterVolume.SetDeepColor(const Value: TCastleColorRGB);
begin
  FDeepColor := Value;
  if not (csLoading in ComponentState) then
    RebuildWaterMesh;
end;

procedure TCastleWaterVolume.SetFoamColor(const Value: TCastleColorRGB);
begin
  FFoamColor := Value;
  if not (csLoading in ComponentState) then
    RebuildWaterMesh;
end;

procedure TCastleWaterVolume.SampleSurfaceLocal(
  const LocalX, LocalZ, AtTimeSec: Single;
  out OutLocalPos, OutLocalNormal: TVector3; out OutFoamFactor: Single);
const
  DirX: array[0..3] of Single = (1.0000, 0.7660, 0.8660, 0.3420);
  DirZ: array[0..3] of Single = (0.0000, 0.6428, -0.5000, 0.9397);
  LenRatio: array[0..3] of Single = (1.00, 0.58, 0.33, 0.19);
  AmpWeight: array[0..3] of Single = (0.50, 0.25, 0.15, 0.10);
var
  I: Integer;
  BaseLen, DispX, DispY, DispZ, dYdX, dYdZ, PinchAccum: Single;
  L, K, Omega, Amp, Q, Phase, S, C: Single;
  NormH: Single;
begin
  DispX := 0.0;
  DispY := 0.0;
  DispZ := 0.0;
  dYdX := 0.0;
  dYdZ := 0.0;
  PinchAccum := 0.0;

  BaseLen := Max(0.5, FWaveLength);
  if FWaveAmplitude > 1e-5 then
  begin
    for I := 0 to 3 do
    begin
      L := Max(0.25, BaseLen * LenRatio[I]);
      K := (2.0 * Pi) / L;
      Omega := Sqrt(9.81 * K) * FWaveSpeed;
      Amp := FWaveAmplitude * AmpWeight[I];
      Q := Clamped(FWaveSteepness / Max(0.001, K * Amp * 4.0), 0.0, 0.24);
      Phase := K * (DirX[I] * LocalX + DirZ[I] * LocalZ) - Omega * AtTimeSec;
      SinCos(Phase, S, C);

      DispX := DispX + (Q * Amp * DirX[I]) * C;
      DispZ := DispZ + (Q * Amp * DirZ[I]) * C;
      DispY := DispY + Amp * S;

      dYdX := dYdX + Amp * K * DirX[I] * C;
      dYdZ := dYdZ + Amp * K * DirZ[I] * C;
      PinchAccum := PinchAccum + Q * K * Amp * S;
    end;
  end;

  OutLocalPos := Vector3(LocalX + DispX, DispY, LocalZ + DispZ);
  OutLocalNormal := Vector3(-dYdX, 1.0, -dYdZ).Normalize;

  if FWaveAmplitude > 1e-4 then
  begin
    NormH := Clamped(0.5 + 0.5 * (DispY / FWaveAmplitude), 0.0, 1.0);
    NormH := Clamped(NormH + Max(0.0, PinchAccum) * 0.35, 0.0, 1.0);
    if NormH <= FFoamCrestThreshold then
      OutFoamFactor := 0.0
    else
      OutFoamFactor := Clamped((NormH - FFoamCrestThreshold) /
        Max(0.02, 1.0 - FFoamCrestThreshold), 0.0, 1.0);
  end else
    OutFoamFactor := 0.0;
end;

function TCastleWaterVolume.SampleSurfaceWorld(
  const WorldPos: TVector3; const AtTimeSec: Single;
  out OutSurfaceWorldY: Single; out OutWorldNormal, OutWorldFlowVel: TVector3;
  out OutFoamFactor: Single): Boolean;
var
  LocalQuery, SurfLocal, NormLocal, SurfWorld: TVector3;
begin
  LocalQuery := SafeTransformWorldToLocal(Self, WorldPos);
  if not FInfiniteOcean then
  begin
    if (Abs(LocalQuery.X) > FSizeX * 0.5) or
       (Abs(LocalQuery.Z) > FSizeZ * 0.5) or
       (LocalQuery.Y < -FDepth) then
    begin
      OutSurfaceWorldY := 0.0;
      OutWorldNormal := Vector3(0, 1, 0);
      OutWorldFlowVel := TVector3.Zero;
      OutFoamFactor := 0.0;
      Exit(false);
    end;
  end;

  SampleSurfaceLocal(LocalQuery.X, LocalQuery.Z, AtTimeSec,
    SurfLocal, NormLocal, OutFoamFactor);
  SurfWorld := SafeTransformLocalToWorld(Self, Vector3(LocalQuery.X, SurfLocal.Y, LocalQuery.Z));
  OutSurfaceWorldY := SurfWorld.Y;
  OutWorldNormal := SafeTransformLocalDirToWorld(Self, NormLocal);
  if OutWorldNormal.LengthSqr > 1e-8 then
    OutWorldNormal := OutWorldNormal.Normalize
  else
    OutWorldNormal := Vector3(0, 1, 0);
  OutWorldFlowVel := SafeTransformLocalDirToWorld(Self, Vector3(FFlowSpeedX, 0.0, FFlowSpeedZ));
  Result := true;
end;

procedure TCastleWaterVolume.EnsureRenderScene;
var
  ShapeNode: TShapeNode;
begin
  if FRenderScene <> nil then
    Exit;

  FRenderScene := TCastleScene.Create(nil);
  FRenderScene.SetTransient;
  FRenderScene.Pickable := false;
  FRenderScene.Collides := false;

  FRootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;

  FAppearanceNode := TAppearanceNode.Create;
  FMaterialNode := TPhysicalMaterialNode.Create;
  FAppearanceNode.Material := FMaterialNode;
  ShapeNode.Appearance := FAppearanceNode;

  FTriSetNode := TTriangleSetNode.Create;
  FTriSetNode.Solid := false;

  FCoordNode := TCoordinateNode.Create;
  FTriSetNode.Coord := FCoordNode;

  FNormalNode := TNormalNode.Create;
  FTriSetNode.Normal := FNormalNode;

  FColorNode := TColorRGBANode.Create;
  FTriSetNode.Color := FColorNode;

  ShapeNode.Geometry := FTriSetNode;
  FRootNode.AddChildren(ShapeNode);

  SyncMaterialProperties;
  FRenderScene.Load(FRootNode, true);
  Add(FRenderScene);
end;

procedure TCastleWaterVolume.SyncMaterialProperties;
begin
  if (FMaterialNode = nil) or (FAppearanceNode = nil) then
    Exit;
  FMaterialNode.BaseColor := Vector3(1.0, 1.0, 1.0);
  FMaterialNode.Roughness := 0.09;
  FMaterialNode.Metallic := 0.06;
  FMaterialNode.Transparency := Clamped(1.0 - FWaterOpacity, 0.0, 0.95);
  if FWaterOpacity < 0.99 then
    FAppearanceNode.AlphaMode := amBlend
  else
    FAppearanceNode.AlphaMode := amOpaque;
end;

procedure TCastleWaterVolume.RebuildWaterMesh;
var
  N, GX, GZ, RowStride, VIdx, OutIdx, TriVertCount: Integer;
  GridPos, GridNorm: array of TVector3;
  GridCol: array of TVector4;
  Verts, Norms: array of TVector3;
  Cols: array of TVector4;
  LX, LZ, Foam, HeightT: Single;
  BaseWaterRgb, FinalRgb: TVector3;
  I00, I10, I01, I11: Integer;
begin
  EnsureRenderScene;
  N := Clamped(FGridSubdivisions, 4, 80);
  RowStride := N + 1;
  SetLength(GridPos, RowStride * RowStride);
  SetLength(GridNorm, RowStride * RowStride);
  SetLength(GridCol, RowStride * RowStride);

  for GZ := 0 to N do
  begin
    LZ := -FSizeZ * 0.5 + (GZ / N) * FSizeZ;
    for GX := 0 to N do
    begin
      LX := -FSizeX * 0.5 + (GX / N) * FSizeX;
      VIdx := GZ * RowStride + GX;
      SampleSurfaceLocal(LX, LZ, FElapsedTime, GridPos[VIdx], GridNorm[VIdx], Foam);
      if FWaveAmplitude > 1e-4 then
        HeightT := Clamped(0.5 + 0.5 * (GridPos[VIdx].Y / FWaveAmplitude), 0.0, 1.0)
      else
        HeightT := 0.5;
      BaseWaterRgb := Lerp(HeightT, FDeepColor, FShallowColor);
      FinalRgb := Lerp(Foam, BaseWaterRgb, FFoamColor);
      GridCol[VIdx] := Vector4(FinalRgb.X, FinalRgb.Y, FinalRgb.Z, FWaterOpacity);
    end;
  end;

  TriVertCount := N * N * 6;
  SetLength(Verts, TriVertCount);
  SetLength(Norms, TriVertCount);
  SetLength(Cols, TriVertCount);
  OutIdx := 0;

  for GZ := 0 to N - 1 do
    for GX := 0 to N - 1 do
    begin
      I00 := GZ * RowStride + GX;
      I10 := I00 + 1;
      I01 := (GZ + 1) * RowStride + GX;
      I11 := I01 + 1;

      Verts[OutIdx] := GridPos[I00]; Norms[OutIdx] := GridNorm[I00]; Cols[OutIdx] := GridCol[I00]; Inc(OutIdx);
      Verts[OutIdx] := GridPos[I01]; Norms[OutIdx] := GridNorm[I01]; Cols[OutIdx] := GridCol[I01]; Inc(OutIdx);
      Verts[OutIdx] := GridPos[I10]; Norms[OutIdx] := GridNorm[I10]; Cols[OutIdx] := GridCol[I10]; Inc(OutIdx);

      Verts[OutIdx] := GridPos[I10]; Norms[OutIdx] := GridNorm[I10]; Cols[OutIdx] := GridCol[I10]; Inc(OutIdx);
      Verts[OutIdx] := GridPos[I01]; Norms[OutIdx] := GridNorm[I01]; Cols[OutIdx] := GridCol[I01]; Inc(OutIdx);
      Verts[OutIdx] := GridPos[I11]; Norms[OutIdx] := GridNorm[I11]; Cols[OutIdx] := GridCol[I11]; Inc(OutIdx);
    end;

  FCoordNode.SetPoint(Verts);
  FNormalNode.SetVector(Norms);
  FColorNode.SetColor(Cols);
end;

procedure TCastleWaterVolume.StepSimulation(const Dt: Single);
begin
  if Dt <= 0.0 then
    Exit;
  FElapsedTime := FElapsedTime + Dt;
  RebuildWaterMesh;
end;

procedure TCastleWaterVolume.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if FAnimateInEditor or (CastleApplicationMode = appRunning) then
    StepSimulation(Min(0.1, SecondsPassed));
end;

function TCastleWaterVolume.WaterSummaryBadge: String;
begin
  Result := Format('[Water:%s %.0fx%.0fm A=%.2fm]',
    [PresetDisplayName(FPreset), FSizeX, FSizeZ, FWaveAmplitude]);
end;

{ TCastleBuoyancyBehavior ---------------------------------------------------- }

constructor TCastleBuoyancyBehavior.Create(AOwner: TComponent);
begin
  inherited;
  FEnabled := true;
  FWaterVolume := nil;
  FHullWidth := DefaultHullWidth;
  FHullLength := DefaultHullLength;
  FHullDraft := DefaultHullDraft;
  FBuoyancyMultiplier := DefaultBuoyancyMultiplier;
  FPitchRollStrength := DefaultPitchRollStrength;
  FApplyFlowDrift := true;
  FVelocity := TVector3.Zero;
  FSubmergedPontoonCount := 0;
  FAverageSubmergence := 0.0;
end;

destructor TCastleBuoyancyBehavior.Destroy;
begin
  SetWaterVolume(nil);
  inherited;
end;

procedure TCastleBuoyancyBehavior.Notification(
  AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FWaterVolume) then
    FWaterVolume := nil;
end;

function TCastleBuoyancyBehavior.CanAttachToParent(
  const NewParent: TCastleTransform; out ReasonWhyCannot: String): Boolean;
begin
  Result := inherited;
  if not Result then
    Exit;
  if NewParent.FindBehavior(TCastleBuoyancyBehavior) <> nil then
  begin
    ReasonWhyCannot := 'Only one TCastleBuoyancyBehavior can be attached to a given TCastleTransform';
    Result := false;
  end;
end;

function TCastleBuoyancyBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Enabled', 'WaterVolume', 'HullWidth', 'HullLength', 'HullDraft',
       'BuoyancyMultiplier', 'PitchRollStrength', 'ApplyFlowDrift'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleBuoyancyBehavior.SetWaterVolume(const Value: TCastleWaterVolume);
begin
  if FWaterVolume <> Value then
  begin
    if FWaterVolume <> nil then
      FWaterVolume.RemoveFreeNotification(Self);
    FWaterVolume := Value;
    if FWaterVolume <> nil then
      FWaterVolume.FreeNotification(Self);
  end;
end;

procedure TCastleBuoyancyBehavior.SetHullWidth(const Value: Single);
begin
  FHullWidth := Max(0.1, Value);
end;

procedure TCastleBuoyancyBehavior.SetHullLength(const Value: Single);
begin
  FHullLength := Max(0.1, Value);
end;

procedure TCastleBuoyancyBehavior.SetHullDraft(const Value: Single);
begin
  FHullDraft := Max(0.05, Value);
end;

procedure TCastleBuoyancyBehavior.SetBuoyancyMultiplier(const Value: Single);
begin
  FBuoyancyMultiplier := Clamped(Value, 0.1, 20.0);
end;

procedure TCastleBuoyancyBehavior.SetPitchRollStrength(const Value: Single);
begin
  FPitchRollStrength := Clamped(Value, 0.0, 30.0);
end;

procedure TCastleBuoyancyBehavior.ResetMotion;
begin
  FVelocity := TVector3.Zero;
  FSubmergedPontoonCount := 0;
  FAverageSubmergence := 0.0;
end;

function TCastleBuoyancyBehavior.ResolveActiveWaterVolume(
  const WorldPos: TVector3): TCastleWaterVolume;

  function SearchTransformTree(const RootT: TCastleTransform): TCastleWaterVolume;
  var
    I: Integer;
    DummyY, DummyFoam: Single;
    DummyN, DummyFlow: TVector3;
  begin
    Result := nil;
    if RootT = nil then
      Exit;
    if (RootT is TCastleWaterVolume) and
       TCastleWaterVolume(RootT).SampleSurfaceWorld(WorldPos,
         TCastleWaterVolume(RootT).ElapsedTime, DummyY, DummyN, DummyFlow, DummyFoam) then
      Exit(TCastleWaterVolume(RootT));
    for I := 0 to RootT.Count - 1 do
    begin
      Result := SearchTransformTree(RootT.Items[I]);
      if Result <> nil then
        Exit;
    end;
  end;

var
  TopRoot: TCastleTransform;
begin
  if FWaterVolume <> nil then
    Exit(FWaterVolume);
  Result := nil;
  if Parent = nil then
    Exit;
  TopRoot := Parent;
  while TopRoot.Parent <> nil do
    TopRoot := TopRoot.Parent;
  Result := SearchTransformTree(TopRoot);
end;

function TCastleBuoyancyBehavior.SampleHullPontoons(
  out OutPontoonWorld: array of TVector3;
  out OutPontoonWaterY: array of Single;
  out OutAvgNormal, OutAvgFlow: TVector3): Integer;
var
  ActiveWater: TCastleWaterVolume;
  ParentWorldOrigin, PLocal, PWorld, SampleNorm, SampleFlow: TVector3;
  PontoonOffsets: array[0..3] of TVector3;
  I: Integer;
  SurfY, Foam, SubRatio, SumSub: Single;
begin
  Result := 0;
  OutAvgNormal := Vector3(0, 1, 0);
  OutAvgFlow := TVector3.Zero;
  FSubmergedPontoonCount := 0;
  FAverageSubmergence := 0.0;
  if Parent = nil then
    Exit;

  ParentWorldOrigin := SafeTransformLocalToWorld(Parent, TVector3.Zero);
  ActiveWater := ResolveActiveWaterVolume(ParentWorldOrigin);
  if ActiveWater = nil then
    Exit;

  PontoonOffsets[0] := Vector3(-FHullWidth * 0.5, -FHullDraft * 0.5, -FHullLength * 0.5);
  PontoonOffsets[1] := Vector3( FHullWidth * 0.5, -FHullDraft * 0.5, -FHullLength * 0.5);
  PontoonOffsets[2] := Vector3(-FHullWidth * 0.5, -FHullDraft * 0.5,  FHullLength * 0.5);
  PontoonOffsets[3] := Vector3( FHullWidth * 0.5, -FHullDraft * 0.5,  FHullLength * 0.5);

  OutAvgNormal := TVector3.Zero;
  SumSub := 0.0;
  for I := 0 to 3 do
  begin
    PLocal := PontoonOffsets[I];
    PWorld := SafeTransformLocalToWorld(Parent, PLocal);
    if I <= High(OutPontoonWorld) then
      OutPontoonWorld[I] := PWorld;
    if ActiveWater.SampleSurfaceWorld(PWorld, ActiveWater.ElapsedTime,
         SurfY, SampleNorm, SampleFlow, Foam) then
    begin
      if I <= High(OutPontoonWaterY) then
        OutPontoonWaterY[I] := SurfY;
      OutAvgNormal := OutAvgNormal + SampleNorm;
      OutAvgFlow := OutAvgFlow + SampleFlow * 0.25;
      if SurfY > PWorld.Y then
      begin
        Inc(Result);
        SubRatio := Clamped((SurfY - PWorld.Y) / Max(0.05, FHullDraft), 0.0, 1.5);
        SumSub := SumSub + SubRatio;
      end;
    end else
    begin
      if I <= High(OutPontoonWaterY) then
        OutPontoonWaterY[I] := PWorld.Y - 10.0;
      OutAvgNormal := OutAvgNormal + Vector3(0, 1, 0);
    end;
  end;

  if OutAvgNormal.LengthSqr > 1e-8 then
    OutAvgNormal := OutAvgNormal.Normalize
  else
    OutAvgNormal := Vector3(0, 1, 0);

  FSubmergedPontoonCount := Result;
  FAverageSubmergence := SumSub * 0.25;
end;

procedure TCastleBuoyancyBehavior.StepBuoyancy(const Dt: Single);
const
  Gravity = 9.81;
var
  ActiveWater: TCastleWaterVolume;
  PontoonW: array[0..3] of TVector3;
  PontoonSurfY: array[0..3] of Single;
  AvgNorm, AvgFlow, Accel, CurPos, CurDir, CurUp, NewUp, NewDir, RightVec: TVector3;
  StepDt, DragFactor, BlendAlpha, LinDrag: Single;
begin
  if (not FEnabled) or (Parent = nil) or (Dt <= 0.0) then
    Exit;
  StepDt := Min(0.1, Dt);

  ActiveWater := ResolveActiveWaterVolume(SafeTransformLocalToWorld(Parent, TVector3.Zero));
  SampleHullPontoons(PontoonW, PontoonSurfY, AvgNorm, AvgFlow);

  Accel := Vector3(0.0, -Gravity, 0.0);
  if FAverageSubmergence > 0.0 then
  begin
    Accel.Y := Accel.Y + Gravity * FBuoyancyMultiplier * FAverageSubmergence;
    if ActiveWater <> nil then
      LinDrag := ActiveWater.LinearWaterDrag
    else
      LinDrag := TCastleWaterVolume.DefaultLinearWaterDrag;

    if FApplyFlowDrift then
    begin
      Accel.X := Accel.X + (AvgFlow.X - FVelocity.X) * LinDrag * Clamped(FAverageSubmergence, 0.15, 1.0);
      Accel.Z := Accel.Z + (AvgFlow.Z - FVelocity.Z) * LinDrag * Clamped(FAverageSubmergence, 0.15, 1.0);
    end else
    begin
      Accel.X := Accel.X - FVelocity.X * LinDrag * Clamped(FAverageSubmergence, 0.15, 1.0);
      Accel.Z := Accel.Z - FVelocity.Z * LinDrag * Clamped(FAverageSubmergence, 0.15, 1.0);
    end;
    { Vertical hydrodynamic damping }
    DragFactor := Exp(-LinDrag * 1.35 * Clamped(FAverageSubmergence, 0.2, 1.0) * StepDt);
    FVelocity.Y := FVelocity.Y * DragFactor;
  end;

  FVelocity := FVelocity + Accel * StepDt;
  Parent.Translation := Parent.Translation + FVelocity * StepDt;

  { Align pitch & roll smoothly toward the sampled Gerstner wave normal }
  if (FPitchRollStrength > 0.01) and (FSubmergedPontoonCount > 0) then
  begin
    Parent.GetView(CurPos, CurDir, CurUp);
    BlendAlpha := 1.0 - Exp(-FPitchRollStrength * StepDt);
    NewUp := Lerp(BlendAlpha, CurUp, AvgNorm);
    if NewUp.LengthSqr > 1e-6 then
    begin
      NewUp := NewUp.Normalize;
      RightVec := TVector3.CrossProduct(CurDir, NewUp);
      if RightVec.LengthSqr < 1e-6 then
        RightVec := TVector3.CrossProduct(Vector3(0, 0, -1), NewUp);
      if RightVec.LengthSqr > 1e-6 then
      begin
        RightVec := RightVec.Normalize;
        NewDir := TVector3.CrossProduct(NewUp, RightVec).Normalize;
        Parent.SetView(CurPos, NewDir, NewUp);
      end;
    end;
  end;
end;

procedure TCastleBuoyancyBehavior.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if FEnabled and (CastleApplicationMode = appRunning) then
    StepBuoyancy(SecondsPassed);
end;

function TCastleBuoyancyBehavior.BuoyancySummaryBadge: String;
begin
  Result := Format('[Buoyancy:4pt %.1fx%.1fm]', [FHullWidth, FHullLength]);
end;

initialization
  RegisterSerializableComponent(TCastleWaterVolume, 'Water Volume (Gerstner & River)');
  RegisterSerializableComponent(TCastleBuoyancyBehavior, 'Buoyancy (4-Pontoon Hull)');
end.
