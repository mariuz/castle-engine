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

{ Real-time 3D VFX particle emitter (@link(TCastleParticleEmitter)) with
  Point/Sphere/Cone/Box/Ring spawn volumes, continuous & burst emission,
  size/color/alpha over lifetime, gravity/drag/turbulence physics, and
  built-in VFX presets (Phase 289 — UE 5.9 / 6.0 Niagara VFX Parity). }
unit CastleParticles;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { 3D volume/surface from which particles originate in local emitter space. }
  TParticleEmitterShape = (
    pesPoint,
    pesSphere,
    pesCone,
    pesBox,
    pesCircleRing
  );

  { GPU alpha compositing mode for rendered particle quads. }
  TParticleBlendMode = (
    pbmAlphaBlend,
    pbmAdditive
  );

  { Built-in 1-click VFX presets. }
  TVfxParticlePreset = (
    vfxCustom,
    vfxFire,
    vfxSmoke,
    vfxSparks,
    vfxMagicPortal,
    vfxSnowRain,
    vfxExplosionBurst
  );

  { Per-particle simulation state in local emitter space. }
  TLiveParticleData = record
    Position: TVector3;
    Velocity: TVector3;
    Age: Single;
    Lifetime: Single;
    SeedPhase: Single;
  end;
  TLiveParticleDataArray = array of TLiveParticleData;

  { Native 3D VFX particle emitter component.
    Renders live crossed-billboard quads inside an internal @code(csTransient)
    @link(TCastleScene) so editor saves and @code(ComponentToString) roundtrips
    serialize only compact emitter settings without baking transient particle
    geometry into @code(.castle-transform) or @code(.castle-user-interface) files. }
  TCastleParticleEmitter = class(TCastleTransform)
  strict private
    FPreset: TVfxParticlePreset;
    FShape: TParticleEmitterShape;
    FBlendMode: TParticleBlendMode;
    FEmitting: Boolean;
    FPreviewInEditor: Boolean;
    FMaxParticles: Integer;
    FSpawnRate: Single;
    FShapeRadius: Single;
    FConeAngleDeg: Single;
    FBoxExtents: TVector3;
    FBoxExtentsPersistent: TCastleVector3Persistent;
    FLifetimeMin: Single;
    FLifetimeMax: Single;
    FSpeedMin: Single;
    FSpeedMax: Single;
    FSizeStart: Single;
    FSizeEnd: Single;
    FColorStart: TCastleColor;
    FColorStartPersistent: TCastleColorPersistent;
    FColorEnd: TCastleColor;
    FColorEndPersistent: TCastleColorPersistent;
    FGravityFactor: Single;
    FDrag: Single;
    FTurbulence: Single;

    FParticles: TLiveParticleDataArray;
    FActiveCount: Integer;
    FSpawnAccumulator: Single;
    FSimClock: Single;
    FRngState: Cardinal;

    FRenderScene: TCastleScene;
    FRootNode: TX3DRootNode;
    FAppearanceNode: TAppearanceNode;
    FBlendModeNode: TBlendModeNode;
    FTriSetNode: TTriangleSetNode;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorRGBANode;
    FVertexBuffer: TVector3List;
    FColorBuffer: TVector4List;

    procedure SetPreset(const Value: TVfxParticlePreset);
    procedure SetBlendMode(const Value: TParticleBlendMode);
    procedure SetMaxParticles(const Value: Integer);
    procedure SetSpawnRate(const Value: Single);
    procedure SetShapeRadius(const Value: Single);
    procedure SetConeAngleDeg(const Value: Single);
    procedure SetLifetimeMin(const Value: Single);
    procedure SetLifetimeMax(const Value: Single);
    procedure SetSpeedMin(const Value: Single);
    procedure SetSpeedMax(const Value: Single);
    procedure SetSizeStart(const Value: Single);
    procedure SetSizeEnd(const Value: Single);
    procedure SetDrag(const Value: Single);
    procedure SetTurbulence(const Value: Single);

    function GetBoxExtentsForPersistent: TVector3;
    procedure SetBoxExtentsForPersistent(const AValue: TVector3);
    function GetColorStartForPersistent: TCastleColor;
    procedure SetColorStartForPersistent(const AValue: TCastleColor);
    function GetColorEndForPersistent: TCastleColor;
    procedure SetColorEndForPersistent(const AValue: TCastleColor);

    function NextRandom01: Single;
    function NextRandomRange(const AMin, AMax: Single): Single;
    procedure SpawnSingleParticle;
    procedure EnsureRenderScene;
    procedure SyncBlendModeNodes;
    procedure RebuildMeshBuffers;
  protected
    procedure Loaded; override;
  public
    const
      DefaultMaxParticles = 256;
      DefaultSpawnRate = 32.0;
      DefaultShapeRadius = 0.35;
      DefaultConeAngleDeg = 22.0;
      DefaultLifetimeMin = 0.8;
      DefaultLifetimeMax = 1.6;
      DefaultSpeedMin = 1.8;
      DefaultSpeedMax = 3.4;
      DefaultSizeStart = 0.28;
      DefaultSizeEnd = 0.05;
      DefaultGravityFactor = -0.15;
      DefaultDrag = 0.35;
      DefaultTurbulence = 0.8;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Apply one of the built-in VFX parameter presets. }
    procedure ApplyPreset(const APreset: TVfxParticlePreset);

    { Immediately spawn up to @code(ABurstCount) particles (capped by @link(MaxParticles)),
      returning the number of newly spawned particles. }
    function EmitBurst(const ABurstCount: Integer): Integer;

    { Remove all currently live particles and clear the transient render mesh. }
    procedure ClearParticles;

    { Deterministically advance particle simulation by @code(DeltaSec) seconds
      and refresh the internal @code(csTransient) X3D quad mesh. }
    procedure SimulateStep(const DeltaSec: Single);

    { Inspect a live particle (@code(0 .. ActiveParticleCount - 1)). }
    function GetLiveParticle(const Index: Integer): TLiveParticleData;

    { Live telemetry & Hierarchy badge. }
    property ActiveParticleCount: Integer read FActiveCount;
    function RenderedTriangleCount: Integer;
    function EmitterSummaryBadge: String;

    property BoxExtents: TVector3 read FBoxExtents write SetBoxExtentsForPersistent;
    property ColorStart: TCastleColor read FColorStart write SetColorStartForPersistent;
    property ColorEnd: TCastleColor read FColorEnd write SetColorEndForPersistent;
  published
    property Preset: TVfxParticlePreset
      read FPreset write SetPreset default vfxFire;
    property Shape: TParticleEmitterShape
      read FShape write FShape default pesCone;
    property BlendMode: TParticleBlendMode
      read FBlendMode write SetBlendMode default pbmAdditive;
    property Emitting: Boolean read FEmitting write FEmitting default true;
    property PreviewInEditor: Boolean
      read FPreviewInEditor write FPreviewInEditor default true;
    property MaxParticles: Integer
      read FMaxParticles write SetMaxParticles default DefaultMaxParticles;
    property SpawnRate: Single read FSpawnRate write SetSpawnRate
      {$ifdef FPC}default DefaultSpawnRate{$endif};
    property ShapeRadius: Single read FShapeRadius write SetShapeRadius
      {$ifdef FPC}default DefaultShapeRadius{$endif};
    property ConeAngleDeg: Single read FConeAngleDeg write SetConeAngleDeg
      {$ifdef FPC}default DefaultConeAngleDeg{$endif};
    property BoxExtentsPersistent: TCastleVector3Persistent read FBoxExtentsPersistent;
    property LifetimeMin: Single read FLifetimeMin write SetLifetimeMin
      {$ifdef FPC}default DefaultLifetimeMin{$endif};
    property LifetimeMax: Single read FLifetimeMax write SetLifetimeMax
      {$ifdef FPC}default DefaultLifetimeMax{$endif};
    property SpeedMin: Single read FSpeedMin write SetSpeedMin
      {$ifdef FPC}default DefaultSpeedMin{$endif};
    property SpeedMax: Single read FSpeedMax write SetSpeedMax
      {$ifdef FPC}default DefaultSpeedMax{$endif};
    property SizeStart: Single read FSizeStart write SetSizeStart
      {$ifdef FPC}default DefaultSizeStart{$endif};
    property SizeEnd: Single read FSizeEnd write SetSizeEnd
      {$ifdef FPC}default DefaultSizeEnd{$endif};
    property ColorStartPersistent: TCastleColorPersistent read FColorStartPersistent;
    property ColorEndPersistent: TCastleColorPersistent read FColorEndPersistent;
    property GravityFactor: Single read FGravityFactor write FGravityFactor
      {$ifdef FPC}default DefaultGravityFactor{$endif};
    property Drag: Single read FDrag write SetDrag
      {$ifdef FPC}default DefaultDrag{$endif};
    property Turbulence: Single read FTurbulence write SetTurbulence
      {$ifdef FPC}default DefaultTurbulence{$endif};
  end;

function VfxPresetToString(const P: TVfxParticlePreset): String;
function ParticleShapeToString(const S: TParticleEmitterShape): String;

implementation

uses
  Math,
  CastleComponentSerialize, CastleRenderOptions;

function VfxPresetToString(const P: TVfxParticlePreset): String;
begin
  case P of
    vfxCustom:         Result := 'Custom';
    vfxFire:           Result := 'Fire';
    vfxSmoke:          Result := 'Smoke';
    vfxSparks:         Result := 'Sparks';
    vfxMagicPortal:    Result := 'MagicPortal';
    vfxSnowRain:       Result := 'SnowRain';
    vfxExplosionBurst: Result := 'Explosion';
  end;
end;

function ParticleShapeToString(const S: TParticleEmitterShape): String;
begin
  case S of
    pesPoint:      Result := 'Point';
    pesSphere:     Result := 'Sphere';
    pesCone:       Result := 'Cone';
    pesBox:        Result := 'Box';
    pesCircleRing: Result := 'CircleRing';
  end;
end;

{ TCastleParticleEmitter ----------------------------------------------------- }

constructor TCastleParticleEmitter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRngState := $A341316C;
  FActiveCount := 0;
  FSpawnAccumulator := 0.0;
  FSimClock := 0.0;

  FVertexBuffer := TVector3List.Create;
  FColorBuffer := TVector4List.Create;

  FBoxExtents := Vector3(1.0, 1.0, 1.0);
  FColorStart := Vector4(1.0, 0.72, 0.18, 0.95);
  FColorEnd := Vector4(0.85, 0.12, 0.02, 0.0);

  FBoxExtentsPersistent := TCastleVector3Persistent.Create(nil);
  FBoxExtentsPersistent.SetSubComponent(true);
  FBoxExtentsPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetBoxExtentsForPersistent;
  FBoxExtentsPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetBoxExtentsForPersistent;
  FBoxExtentsPersistent.InternalDefaultValue := FBoxExtents;

  FColorStartPersistent := TCastleColorPersistent.Create(nil);
  FColorStartPersistent.SetSubComponent(true);
  FColorStartPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetColorStartForPersistent;
  FColorStartPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetColorStartForPersistent;
  FColorStartPersistent.InternalDefaultValue := FColorStart;

  FColorEndPersistent := TCastleColorPersistent.Create(nil);
  FColorEndPersistent.SetSubComponent(true);
  FColorEndPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetColorEndForPersistent;
  FColorEndPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetColorEndForPersistent;
  FColorEndPersistent.InternalDefaultValue := FColorEnd;

  FEmitting := true;
  FPreviewInEditor := true;
  ApplyPreset(vfxFire);
end;

destructor TCastleParticleEmitter.Destroy;
begin
  if FRenderScene <> nil then
  begin
    Remove(FRenderScene);
    FreeAndNil(FRenderScene);
  end;
  FreeAndNil(FVertexBuffer);
  FreeAndNil(FColorBuffer);
  FreeAndNil(FBoxExtentsPersistent);
  FreeAndNil(FColorStartPersistent);
  FreeAndNil(FColorEndPersistent);
  inherited Destroy;
end;

function TCastleParticleEmitter.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'Shape', 'BlendMode', 'Emitting', 'PreviewInEditor',
       'MaxParticles', 'SpawnRate', 'ShapeRadius', 'ConeAngleDeg',
       'BoxExtentsPersistent', 'LifetimeMin', 'LifetimeMax',
       'SpeedMin', 'SpeedMax', 'SizeStart', 'SizeEnd',
       'ColorStartPersistent', 'ColorEndPersistent',
       'GravityFactor', 'Drag', 'Turbulence'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleParticleEmitter.LocalBoundingBox: TBox3D;
var
  HalfExt: TVector3;
  R: Single;
begin
  Result := inherited LocalBoundingBox;
  if CastleDesignMode then
  begin
    if FShape = pesBox then
      HalfExt := Vector3(
        Max(0.25, FBoxExtents.X * 0.5),
        Max(0.25, FBoxExtents.Y * 0.5),
        Max(0.25, FBoxExtents.Z * 0.5))
    else
    begin
      R := Max(0.35, FShapeRadius);
      HalfExt := Vector3(R, Max(R, 0.5), R);
    end;
    Result.Include(Box3D(-HalfExt, HalfExt));
  end;
end;

procedure TCastleParticleEmitter.Loaded;
begin
  inherited Loaded;
  SyncBlendModeNodes;
end;

procedure TCastleParticleEmitter.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if CastleDesignMode and (not FPreviewInEditor) then
    Exit;
  if SecondsPassed > 0.0 then
    SimulateStep(Min(SecondsPassed, 0.1));
end;

function TCastleParticleEmitter.NextRandom01: Single;
begin
  { Deterministic Xorshift32 PRNG }
  FRngState := FRngState xor (FRngState shl 13);
  FRngState := FRngState xor (FRngState shr 17);
  FRngState := FRngState xor (FRngState shl 5);
  if FRngState = 0 then
    FRngState := 1;
  Result := (FRngState and $00FFFFFF) / 16777216.0;
end;

function TCastleParticleEmitter.NextRandomRange(const AMin, AMax: Single): Single;
begin
  if AMax <= AMin then
    Result := AMin
  else
    Result := AMin + (AMax - AMin) * NextRandom01;
end;

procedure TCastleParticleEmitter.SetPreset(const Value: TVfxParticlePreset);
begin
  if FPreset = Value then
    Exit;
  FPreset := Value;
  if (not (csLoading in ComponentState)) and (Value <> vfxCustom) then
    ApplyPreset(Value);
end;

procedure TCastleParticleEmitter.SetBlendMode(const Value: TParticleBlendMode);
begin
  if FBlendMode = Value then
    Exit;
  FBlendMode := Value;
  SyncBlendModeNodes;
end;

procedure TCastleParticleEmitter.SetMaxParticles(const Value: Integer);
begin
  FMaxParticles := Clamped(Value, 1, 8192);
  if FActiveCount > FMaxParticles then
    FActiveCount := FMaxParticles;
  if Length(FParticles) > FMaxParticles then
    SetLength(FParticles, FMaxParticles);
end;

procedure TCastleParticleEmitter.SetSpawnRate(const Value: Single);
begin
  FSpawnRate := Max(0.0, Value);
end;

procedure TCastleParticleEmitter.SetShapeRadius(const Value: Single);
begin
  FShapeRadius := Max(0.0, Value);
end;

procedure TCastleParticleEmitter.SetConeAngleDeg(const Value: Single);
begin
  FConeAngleDeg := Clamped(Value, 0.0, 89.0);
end;

procedure TCastleParticleEmitter.SetLifetimeMin(const Value: Single);
begin
  FLifetimeMin := Max(0.02, Value);
  if FLifetimeMax < FLifetimeMin then
    FLifetimeMax := FLifetimeMin;
end;

procedure TCastleParticleEmitter.SetLifetimeMax(const Value: Single);
begin
  FLifetimeMax := Max(FLifetimeMin, Max(0.02, Value));
end;

procedure TCastleParticleEmitter.SetSpeedMin(const Value: Single);
begin
  FSpeedMin := Max(0.0, Value);
  if FSpeedMax < FSpeedMin then
    FSpeedMax := FSpeedMin;
end;

procedure TCastleParticleEmitter.SetSpeedMax(const Value: Single);
begin
  FSpeedMax := Max(FSpeedMin, Max(0.0, Value));
end;

procedure TCastleParticleEmitter.SetSizeStart(const Value: Single);
begin
  FSizeStart := Max(0.005, Value);
end;

procedure TCastleParticleEmitter.SetSizeEnd(const Value: Single);
begin
  FSizeEnd := Max(0.0, Value);
end;

procedure TCastleParticleEmitter.SetDrag(const Value: Single);
begin
  FDrag := Max(0.0, Value);
end;

procedure TCastleParticleEmitter.SetTurbulence(const Value: Single);
begin
  FTurbulence := Max(0.0, Value);
end;

function TCastleParticleEmitter.GetBoxExtentsForPersistent: TVector3;
begin
  Result := FBoxExtents;
end;

procedure TCastleParticleEmitter.SetBoxExtentsForPersistent(const AValue: TVector3);
begin
  FBoxExtents := Vector3(Max(0.01, AValue.X), Max(0.01, AValue.Y), Max(0.01, AValue.Z));
end;

function TCastleParticleEmitter.GetColorStartForPersistent: TCastleColor;
begin
  Result := FColorStart;
end;

procedure TCastleParticleEmitter.SetColorStartForPersistent(const AValue: TCastleColor);
begin
  FColorStart := AValue;
end;

function TCastleParticleEmitter.GetColorEndForPersistent: TCastleColor;
begin
  Result := FColorEnd;
end;

procedure TCastleParticleEmitter.SetColorEndForPersistent(const AValue: TCastleColor);
begin
  FColorEnd := AValue;
end;

procedure TCastleParticleEmitter.ApplyPreset(const APreset: TVfxParticlePreset);
begin
  FPreset := APreset;
  case APreset of
    vfxFire:
      begin
        FShape := pesCone;
        FBlendMode := pbmAdditive;
        FMaxParticles := DefaultMaxParticles;
        FSpawnRate := DefaultSpawnRate;
        FShapeRadius := DefaultShapeRadius;
        FConeAngleDeg := DefaultConeAngleDeg;
        FLifetimeMin := DefaultLifetimeMin;
        FLifetimeMax := DefaultLifetimeMax;
        FSpeedMin := DefaultSpeedMin;
        FSpeedMax := DefaultSpeedMax;
        FSizeStart := DefaultSizeStart;
        FSizeEnd := DefaultSizeEnd;
        FColorStart := Vector4(1.0, 0.72, 0.18, 0.95);
        FColorEnd := Vector4(0.85, 0.12, 0.02, 0.0);
        FGravityFactor := DefaultGravityFactor;
        FDrag := DefaultDrag;
        FTurbulence := DefaultTurbulence;
      end;

    vfxSmoke:
      begin
        FShape := pesCone;
        FBlendMode := pbmAlphaBlend;
        FMaxParticles := 180;
        FSpawnRate := 16.0;
        FShapeRadius := 0.45;
        FConeAngleDeg := 28.0;
        FLifetimeMin := 2.2;
        FLifetimeMax := 3.8;
        FSpeedMin := 0.8;
        FSpeedMax := 1.6;
        FSizeStart := 0.35;
        FSizeEnd := 1.15;
        FColorStart := Vector4(0.32, 0.32, 0.35, 0.55);
        FColorEnd := Vector4(0.18, 0.18, 0.20, 0.0);
        FGravityFactor := -0.08;
        FDrag := 0.45;
        FTurbulence := 0.65;
      end;

    vfxSparks:
      begin
        FShape := pesCone;
        FBlendMode := pbmAdditive;
        FMaxParticles := 300;
        FSpawnRate := 45.0;
        FShapeRadius := 0.12;
        FConeAngleDeg := 42.0;
        FLifetimeMin := 0.45;
        FLifetimeMax := 1.1;
        FSpeedMin := 4.5;
        FSpeedMax := 8.5;
        FSizeStart := 0.09;
        FSizeEnd := 0.02;
        FColorStart := Vector4(1.0, 0.92, 0.45, 1.0);
        FColorEnd := Vector4(1.0, 0.28, 0.04, 0.0);
        FGravityFactor := 1.0;
        FDrag := 0.15;
        FTurbulence := 0.25;
      end;

    vfxMagicPortal:
      begin
        FShape := pesCircleRing;
        FBlendMode := pbmAdditive;
        FMaxParticles := 320;
        FSpawnRate := 55.0;
        FShapeRadius := 1.6;
        FConeAngleDeg := 12.0;
        FLifetimeMin := 1.0;
        FLifetimeMax := 2.0;
        FSpeedMin := 0.6;
        FSpeedMax := 1.5;
        FSizeStart := 0.22;
        FSizeEnd := 0.04;
        FColorStart := Vector4(0.28, 0.82, 1.0, 0.95);
        FColorEnd := Vector4(0.68, 0.18, 1.0, 0.0);
        FGravityFactor := -0.05;
        FDrag := 0.2;
        FTurbulence := 1.6;
      end;

    vfxSnowRain:
      begin
        FShape := pesBox;
        FBlendMode := pbmAlphaBlend;
        FBoxExtents := Vector3(12.0, 0.5, 12.0);
        FMaxParticles := 500;
        FSpawnRate := 65.0;
        FLifetimeMin := 3.0;
        FLifetimeMax := 5.0;
        FSpeedMin := 1.2;
        FSpeedMax := 2.4;
        FSizeStart := 0.11;
        FSizeEnd := 0.09;
        FColorStart := Vector4(0.92, 0.96, 1.0, 0.85);
        FColorEnd := Vector4(0.85, 0.92, 1.0, 0.0);
        FGravityFactor := 0.35;
        FDrag := 0.25;
        FTurbulence := 0.9;
      end;

    vfxExplosionBurst:
      begin
        FShape := pesSphere;
        FBlendMode := pbmAdditive;
        FMaxParticles := 240;
        FSpawnRate := 8.0;
        FShapeRadius := 0.25;
        FLifetimeMin := 0.5;
        FLifetimeMax := 1.3;
        FSpeedMin := 5.0;
        FSpeedMax := 11.0;
        FSizeStart := 0.42;
        FSizeEnd := 0.08;
        FColorStart := Vector4(1.0, 0.88, 0.35, 1.0);
        FColorEnd := Vector4(0.75, 0.08, 0.02, 0.0);
        FGravityFactor := 0.45;
        FDrag := 1.4;
        FTurbulence := 1.1;
      end;
  end;
  SyncBlendModeNodes;
end;

procedure TCastleParticleEmitter.EnsureRenderScene;
var
  ShapeNode: TShapeNode;
  MatNode: TUnlitMaterialNode;
begin
  if FRenderScene <> nil then
    Exit;

  FRenderScene := TCastleScene.Create(nil);
  FRenderScene.SetTransient;
  FRenderScene.Pickable := false;
  FRenderScene.Collides := false;
  FRenderScene.CastShadows := false;

  FRootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;

  FAppearanceNode := TAppearanceNode.Create;
  FAppearanceNode.AlphaMode := amBlend;
  FAppearanceNode.ShadowCaster := false;

  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(1.0, 1.0, 1.0);
  FAppearanceNode.Material := MatNode;

  FBlendModeNode := TBlendModeNode.Create;
  FAppearanceNode.BlendMode := FBlendModeNode;
  ShapeNode.Appearance := FAppearanceNode;

  FTriSetNode := TTriangleSetNode.Create;
  FTriSetNode.Solid := false;

  FCoordNode := TCoordinateNode.Create;
  FTriSetNode.Coord := FCoordNode;

  FColorNode := TColorRGBANode.Create;
  FTriSetNode.Color := FColorNode;

  ShapeNode.Geometry := FTriSetNode;
  FRootNode.AddChildren(ShapeNode);

  SyncBlendModeNodes;
  FRenderScene.Load(FRootNode, true);
  Add(FRenderScene);
end;

procedure TCastleParticleEmitter.SyncBlendModeNodes;
begin
  if FBlendModeNode = nil then
    Exit;
  FBlendModeNode.SrcFactor := bsSrcAlpha;
  if FBlendMode = pbmAdditive then
    FBlendModeNode.DestFactor := bdOne
  else
    FBlendModeNode.DestFactor := bdOneMinusSrcAlpha;
end;

procedure TCastleParticleEmitter.SpawnSingleParticle;
var
  P: TLiveParticleData;
  Theta, Phi, R, ConeRad, SinP, CosP, Speed: Single;
  Dir: TVector3;
begin
  if FActiveCount >= FMaxParticles then
    Exit;
  if Length(FParticles) < FMaxParticles then
    SetLength(FParticles, FMaxParticles);

  P := Default(TLiveParticleData);
  P.Age := 0.0;
  P.Lifetime := NextRandomRange(FLifetimeMin, FLifetimeMax);
  P.SeedPhase := NextRandom01 * (2.0 * Pi);
  Speed := NextRandomRange(FSpeedMin, FSpeedMax);

  case FShape of
    pesPoint:
      begin
        P.Position := TVector3.Zero;
        Theta := NextRandom01 * (2.0 * Pi);
        Phi := ArcCos(1.0 - 2.0 * NextRandom01);
        SinCos(Phi, SinP, CosP);
        Dir := Vector3(SinP * Cos(Theta), CosP, SinP * Sin(Theta));
      end;

    pesSphere:
      begin
        Theta := NextRandom01 * (2.0 * Pi);
        Phi := ArcCos(1.0 - 2.0 * NextRandom01);
        SinCos(Phi, SinP, CosP);
        Dir := Vector3(SinP * Cos(Theta), CosP, SinP * Sin(Theta));
        R := FShapeRadius * Power(NextRandom01, 1.0 / 3.0);
        P.Position := Dir * R;
      end;

    pesCone:
      begin
        Theta := NextRandom01 * (2.0 * Pi);
        R := FShapeRadius * Sqrt(NextRandom01);
        P.Position := Vector3(Cos(Theta) * R, 0.0, Sin(Theta) * R);
        ConeRad := DegToRad(FConeAngleDeg) * Sqrt(NextRandom01);
        SinCos(ConeRad, SinP, CosP);
        Dir := Vector3(SinP * Cos(Theta), CosP, SinP * Sin(Theta));
      end;

    pesBox:
      begin
        P.Position := Vector3(
          (NextRandom01 - 0.5) * FBoxExtents.X,
          (NextRandom01 - 0.5) * FBoxExtents.Y,
          (NextRandom01 - 0.5) * FBoxExtents.Z);
        if FGravityFactor > 0.05 then
          Dir := Vector3(0.0, -1.0, 0.0)
        else
          Dir := Vector3(0.0, 1.0, 0.0);
      end;

    pesCircleRing:
      begin
        Theta := NextRandom01 * (2.0 * Pi);
        P.Position := Vector3(Cos(Theta) * FShapeRadius, 0.0, Sin(Theta) * FShapeRadius);
        { Tangential + upward swirl }
        Dir := Vector3(-Sin(Theta) * 0.65, 0.75, Cos(Theta) * 0.65).Normalize;
      end;
  end;

  P.Velocity := Dir * Speed;
  FParticles[FActiveCount] := P;
  Inc(FActiveCount);
end;

procedure TCastleParticleEmitter.RebuildMeshBuffers;
var
  I, BaseV, K: Integer;
  P: TLiveParticleData;
  T, HalfS: Single;
  Col: TCastleColor;
  C, V0, V1, V2, V3: TVector3;
begin
  EnsureRenderScene;

  { Two perpendicular vertical quads per particle = 4 triangles = 12 vertices }
  FVertexBuffer.Count := FActiveCount * 12;
  FColorBuffer.Count := FActiveCount * 12;

  for I := 0 to FActiveCount - 1 do
  begin
    P := FParticles[I];
    if P.Lifetime > 0.0001 then
      T := Clamped(P.Age / P.Lifetime, 0.0, 1.0)
    else
      T := 1.0;

    HalfS := Max(0.002, Lerp(T, FSizeStart, FSizeEnd) * 0.5);
    Col := Lerp(T, FColorStart, FColorEnd);
    C := P.Position;
    BaseV := I * 12;

    { Quad 1 in XY plane }
    V0 := Vector3(C.X - HalfS, C.Y - HalfS, C.Z);
    V1 := Vector3(C.X + HalfS, C.Y - HalfS, C.Z);
    V2 := Vector3(C.X + HalfS, C.Y + HalfS, C.Z);
    V3 := Vector3(C.X - HalfS, C.Y + HalfS, C.Z);
    FVertexBuffer.L[BaseV + 0] := V0;
    FVertexBuffer.L[BaseV + 1] := V1;
    FVertexBuffer.L[BaseV + 2] := V2;
    FVertexBuffer.L[BaseV + 3] := V0;
    FVertexBuffer.L[BaseV + 4] := V2;
    FVertexBuffer.L[BaseV + 5] := V3;

    { Quad 2 in ZY plane }
    V0 := Vector3(C.X, C.Y - HalfS, C.Z - HalfS);
    V1 := Vector3(C.X, C.Y - HalfS, C.Z + HalfS);
    V2 := Vector3(C.X, C.Y + HalfS, C.Z + HalfS);
    V3 := Vector3(C.X, C.Y + HalfS, C.Z - HalfS);
    FVertexBuffer.L[BaseV + 6]  := V0;
    FVertexBuffer.L[BaseV + 7]  := V1;
    FVertexBuffer.L[BaseV + 8]  := V2;
    FVertexBuffer.L[BaseV + 9]  := V0;
    FVertexBuffer.L[BaseV + 10] := V2;
    FVertexBuffer.L[BaseV + 11] := V3;

    for K := 0 to 11 do
      FColorBuffer.L[BaseV + K] := Col;
  end;

  FCoordNode.SetPoint(FVertexBuffer);
  FColorNode.SetColor(FColorBuffer);
end;

function TCastleParticleEmitter.EmitBurst(const ABurstCount: Integer): Integer;
var
  I, BeforeCount: Integer;
begin
  BeforeCount := FActiveCount;
  for I := 1 to Max(0, ABurstCount) do
  begin
    if FActiveCount >= FMaxParticles then
      Break;
    SpawnSingleParticle;
  end;
  Result := FActiveCount - BeforeCount;
  RebuildMeshBuffers;
end;

procedure TCastleParticleEmitter.ClearParticles;
begin
  FActiveCount := 0;
  FSpawnAccumulator := 0.0;
  if FCoordNode <> nil then
  begin
    FVertexBuffer.Count := 0;
    FColorBuffer.Count := 0;
    FCoordNode.SetPoint(FVertexBuffer);
    FColorNode.SetColor(FColorBuffer);
  end;
end;

procedure TCastleParticleEmitter.SimulateStep(const DeltaSec: Single);
var
  Dt, Damping: Single;
  WriteIdx, I, ToSpawn: Integer;
  P: TLiveParticleData;
  GravVec, TurbVec: TVector3;
begin
  Dt := Max(0.0, DeltaSec);
  if Dt <= 0.0 then
    Exit;

  FSimClock := FSimClock + Dt;
  GravVec := Vector3(0.0, -9.81 * FGravityFactor, 0.0);
  Damping := Max(0.0, 1.0 - FDrag * Dt);

  { 1. Advance existing particles & compact survivors }
  WriteIdx := 0;
  for I := 0 to FActiveCount - 1 do
  begin
    P := FParticles[I];
    P.Age := P.Age + Dt;
    if P.Age >= P.Lifetime then
      Continue;

    P.Velocity := (P.Velocity + GravVec * Dt) * Damping;
    if FTurbulence > 0.0001 then
    begin
      TurbVec := Vector3(
        Sin(FSimClock * 3.7 + P.SeedPhase + P.Position.Y * 1.9),
        Cos(FSimClock * 2.9 + P.SeedPhase * 1.3 + P.Position.X * 1.5) * 0.5,
        Cos(FSimClock * 4.1 + P.SeedPhase * 0.7 + P.Position.Z * 1.7));
      P.Velocity := P.Velocity + TurbVec * (FTurbulence * Dt);
    end;
    P.Position := P.Position + P.Velocity * Dt;

    FParticles[WriteIdx] := P;
    Inc(WriteIdx);
  end;
  FActiveCount := WriteIdx;

  { 2. Continuous rate spawning }
  if FEmitting and (FSpawnRate > 0.0) then
  begin
    FSpawnAccumulator := FSpawnAccumulator + FSpawnRate * Dt;
    ToSpawn := Trunc(FSpawnAccumulator);
    if ToSpawn > 0 then
    begin
      FSpawnAccumulator := FSpawnAccumulator - ToSpawn;
      for I := 1 to ToSpawn do
      begin
        if FActiveCount >= FMaxParticles then
          Break;
        SpawnSingleParticle;
      end;
    end;
  end;

  RebuildMeshBuffers;
end;

function TCastleParticleEmitter.GetLiveParticle(const Index: Integer): TLiveParticleData;
begin
  if (Index >= 0) and (Index < FActiveCount) then
    Result := FParticles[Index]
  else
    Result := Default(TLiveParticleData);
end;

function TCastleParticleEmitter.RenderedTriangleCount: Integer;
begin
  Result := FActiveCount * 4;
end;

function TCastleParticleEmitter.EmitterSummaryBadge: String;
begin
  Result := Format('[VFX:%s %d/%d]',
    [VfxPresetToString(FPreset), FActiveCount, FMaxParticles]);
end;

initialization
  RegisterSerializableComponent(TCastleParticleEmitter,
    ['VFX & Particles', 'Particle Emitter (3D VFX)']);
end.
