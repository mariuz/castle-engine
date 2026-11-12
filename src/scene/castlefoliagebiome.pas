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

{ Seeded Halton/Poisson procedural foliage biome volumes
  (@link(TCastleFoliageBiomeVolume)), road/building exclusion masks
  (@link(TCastleFoliageExclusionVolume)), and hysteresis multi-tier distance LOD
  proxies (@link(TCastleLodProxyBehavior))
  (Phase 303 — UE 6.0 Procedural Foliage Volumes & HLOD Proxy Parity). }
unit CastleFoliageBiome;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleVectors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, CastleTriangles, X3DNodes;

const
  FoliageGeneratedInstanceTag = 7803;

type
  { Built-in procedural silhouette archetypes when @code(AssetUrl = ''). }
  TFoliageArchetype = (
    faPineTree,
    faBroadleafOak,
    faBushShrub,
    faBoulderRock,
    faWildGrass,
    faCustomUrl
  );

  { Distance LOD band evaluated by @link(TCastleLodProxyBehavior). }
  TFoliageLodLevel = (
    fllHigh,
    fllMedium,
    fllLow,
    fllCulled
  );

  { Weighted species rule inside @link(TCastleFoliageBiomeVolume). }
  TFoliageSpeciesEntry = record
    SpeciesId: String;
    Archetype: TFoliageArchetype;
    AssetUrl: String;
    MediumLodUrl: String;
    LowLodUrl: String;
    Weight: Single;
    MinScale: Single;
    MaxScale: Single;
    MinRadiusSpacing: Single;
    AlignToSlopeFactor: Single;
    MinAltitude: Single;
    MaxAltitude: Single;
    MaxSlopeDeg: Single;
  end;

  { Oriented 3D exclusion volume carving roads, foundations, or clearings out of
    any @link(TCastleFoliageBiomeVolume) scatter pass. }
  TCastleFoliageExclusionVolume = class(TCastleTransform)
  public const
    DefaultFalloffMargin = Single(0.5);
  strict private
    FExclusionSize: TVector3;
    FExclusionSizePersistent: TCastleVector3Persistent;
    FFalloffMargin: Single;
    FShowVolumeInViewport: Boolean;

    function GetExclusionSizeForPersistent: TVector3;
    procedure SetExclusionSizeForPersistent(const AValue: TVector3);
    procedure SetExclusionSize(const Value: TVector3);
    procedure SetFalloffMargin(const Value: Single);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Return @true if @code(AWorldPt) falls inside this exclusion box (plus
      @link(FalloffMargin)), honoring full 3D hierarchy translation/rotation/scale. }
    function ContainsWorldPoint(const AWorldPt: TVector3): Boolean;

    function ExclusionSummaryBadge: String;

    property ExclusionSize: TVector3 read FExclusionSize write SetExclusionSize;
  published
    property ExclusionSizePersistent: TCastleVector3Persistent
      read FExclusionSizePersistent;
    property FalloffMargin: Single
      read FFalloffMargin write SetFalloffMargin
      {$ifdef FPC}default DefaultFalloffMargin{$endif};
    property ShowVolumeInViewport: Boolean
      read FShowVolumeInViewport write FShowVolumeInViewport default true;
  end;

  { Multi-tier distance LOD & cull proxy behavior with bidirectional hysteresis
    to prevent boundary LOD popping/thrashing. }
  TCastleLodProxyBehavior = class(TCastleBehavior)
  public const
    DefaultMediumDistance = Single(25.0);
    DefaultLowDistance = Single(60.0);
    DefaultCullDistance = Single(140.0);
    DefaultHysteresisMargin = Single(2.5);
  strict private
    FHighUrl: String;
    FMediumUrl: String;
    FLowUrl: String;
    FMediumDistance: Single;
    FLowDistance: Single;
    FCullDistance: Single;
    FHysteresisMargin: Single;
    FAutoEvaluateFromCamera: Boolean;
    FCurrentLodLevel: TFoliageLodLevel;

    procedure SetMediumDistance(const Value: Single);
    procedure SetLowDistance(const Value: Single);
    procedure SetCullDistance(const Value: Single);
    procedure SetHysteresisMargin(const Value: Single);
    procedure ApplyLodVisualState;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    class function LodLevelToName(const ALevel: TFoliageLodLevel): String; static;

    { Evaluate and update @link(CurrentLodLevel) for @code(ADistance) using
      bidirectional @link(HysteresisMargin) thresholds. }
    function EvaluateForDistance(const ADistance: Single): TFoliageLodLevel;

    { Return the active URL (@link(HighUrl), @link(MediumUrl), @link(LowUrl), or
      @code('') when culled) corresponding to @link(CurrentLodLevel). }
    function ActiveResolvedUrl: String;

    function LodSummaryBadge: String;

    property CurrentLodLevel: TFoliageLodLevel read FCurrentLodLevel;
  published
    property HighUrl: String read FHighUrl write FHighUrl;
    property MediumUrl: String read FMediumUrl write FMediumUrl;
    property LowUrl: String read FLowUrl write FLowUrl;
    property MediumDistance: Single
      read FMediumDistance write SetMediumDistance
      {$ifdef FPC}default DefaultMediumDistance{$endif};
    property LowDistance: Single
      read FLowDistance write SetLowDistance
      {$ifdef FPC}default DefaultLowDistance{$endif};
    property CullDistance: Single
      read FCullDistance write SetCullDistance
      {$ifdef FPC}default DefaultCullDistance{$endif};
    property HysteresisMargin: Single
      read FHysteresisMargin write SetHysteresisMargin
      {$ifdef FPC}default DefaultHysteresisMargin{$endif};
    property AutoEvaluateFromCamera: Boolean
      read FAutoEvaluateFromCamera write FAutoEvaluateFromCamera default true;
  end;

  { Seeded procedural foliage biome volume filtering Halton/Poisson scatter
    candidates by elevation, surface slope, species spacing, and exclusion masks. }
  TCastleFoliageBiomeVolume = class(TCastleTransform)
  public const
    DefaultSeed = 2026;
    DefaultTargetInstanceCount = 48;
    DefaultGlobalMinAltitude = Single(-100.0);
    DefaultGlobalMaxAltitude = Single(500.0);
    DefaultGlobalMaxSlopeDeg = Single(40.0);
  strict private
    FBiomeTitle: String;
    FVolumeSize: TVector3;
    FVolumeSizePersistent: TCastleVector3Persistent;
    FSeed: Integer;
    FTargetInstanceCount: Integer;
    FGlobalMinAltitude: Single;
    FGlobalMaxAltitude: Single;
    FGlobalMaxSlopeDeg: Single;
    FShowVolumeInViewport: Boolean;
    FSpecies: array of TFoliageSpeciesEntry;

    function GetVolumeSizeForPersistent: TVector3;
    procedure SetVolumeSizeForPersistent(const AValue: TVector3);
    procedure SetVolumeSize(const Value: TVector3);
    procedure SetTargetInstanceCount(const Value: Integer);
    procedure SetGlobalMaxSlopeDeg(const Value: Single);
    function GetSpeciesJson: String;
    procedure SetSpeciesJson(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function ArchetypeToName(const AArch: TFoliageArchetype): String; static;
    class function NameToArchetype(const S: String): TFoliageArchetype; static;

    procedure ClearSpecies;
    function SpeciesCount: Integer;
    function GetSpecies(const AIndex: Integer): TFoliageSpeciesEntry;
    function AddOrUpdateSpecies(const AEntry: TFoliageSpeciesEntry): Integer;

    { Load built-in biome palette:
      @code(0) = Alpine Pine Forest, @code(1) = Temperate Oak Meadow,
      @code(2) = Rocky Canyon Scrub. }
    procedure LoadBiomePreset(const APresetIndex: Integer);

    { Remove previously generated foliage children (@code(Tag = FoliageGeneratedInstanceTag)). }
    function ClearGeneratedInstances: Integer;

    { Count currently spawned foliage children inside this volume. }
    function GeneratedInstanceCount: Integer;

    { Deterministically scatter up to @link(TargetInstanceCount) foliage instances
      onto underlying world geometry (respecting @code(AExclusions), altitude bands,
      slope cutoffs, and Poisson @code(MinRadiusSpacing)). }
    function PopulateBiomeInstances(const ADesignOwner: TComponent;
      const AExclusions: array of TCastleFoliageExclusionVolume): Integer;

    function BiomeSummaryBadge: String;

    property VolumeSize: TVector3 read FVolumeSize write SetVolumeSize;
  published
    property BiomeTitle: String read FBiomeTitle write FBiomeTitle;
    property VolumeSizePersistent: TCastleVector3Persistent
      read FVolumeSizePersistent;
    property Seed: Integer read FSeed write FSeed default DefaultSeed;
    property TargetInstanceCount: Integer
      read FTargetInstanceCount write SetTargetInstanceCount
      default DefaultTargetInstanceCount;
    property GlobalMinAltitude: Single
      read FGlobalMinAltitude write FGlobalMinAltitude
      {$ifdef FPC}default DefaultGlobalMinAltitude{$endif};
    property GlobalMaxAltitude: Single
      read FGlobalMaxAltitude write FGlobalMaxAltitude
      {$ifdef FPC}default DefaultGlobalMaxAltitude{$endif};
    property GlobalMaxSlopeDeg: Single
      read FGlobalMaxSlopeDeg write SetGlobalMaxSlopeDeg
      {$ifdef FPC}default DefaultGlobalMaxSlopeDeg{$endif};
    property SpeciesJson: String read GetSpeciesJson write SetSpeciesJson;
    property ShowVolumeInViewport: Boolean
      read FShowVolumeInViewport write FShowVolumeInViewport default true;
  end;

implementation

uses
  fpjson, jsonparser,
  CastleComponentSerialize;

function GetFoliageHierarchyMatrix(const T: TCastleTransform): TMatrix4;
var
  Cur: TCastleTransform;
begin
  Result := TMatrix4.Identity;
  Cur := T;
  while (Cur <> nil) and (not (Cur is TCastleAbstractRootTransform)) do
  begin
    if Cur.Parent = nil then
      Break;
    Result := Cur.Transform * Result;
    Cur := Cur.Parent;
  end;
end;

function HaltonRadicalInverse(AIndex: Integer; const ABase: Integer): Single;
var
  F, R: Single;
begin
  F := 1.0;
  R := 0.0;
  while AIndex > 0 do
  begin
    F := F / ABase;
    R := R + F * (AIndex mod ABase);
    AIndex := AIndex div ABase;
  end;
  Result := R;
end;

function NextFoliageXorShift(var AState: Cardinal): Cardinal;
begin
  if AState = 0 then
    AState := 2463534242;
  AState := AState xor (AState shl 13);
  AState := AState xor (AState shr 17);
  AState := AState xor (AState shl 5);
  Result := AState;
end;

function NextFoliageUnitFloat(var AState: Cardinal): Single;
begin
  Result := (NextFoliageXorShift(AState) and $FFFFFF) / 16777216.0;
end;

procedure AttachTransientFoliageMesh(const AInstance: TCastleTransform;
  const AArchetype: TFoliageArchetype);
var
  PreviewScene: TCastleScene;
  RootNode: TX3DRootNode;
  ShapeTrunk, ShapeCanopy: TShapeNode;
  TrunkTrans, CanopyTrans: TTransformNode;
  TrunkCyl: TCylinderNode;
  ConeCanopy: TConeNode;
  SphereCanopy: TSphereNode;
  BoxRock: TBoxNode;
  AppTrunk, AppCanopy: TAppearanceNode;
  MatTrunk, MatCanopy: TPhysicalMaterialNode;
begin
  if AInstance = nil then
    Exit;

  PreviewScene := TCastleScene.Create(AInstance);
  PreviewScene.SetTransient;
  PreviewScene.Pickable := false;
  PreviewScene.Collides := false;

  RootNode := TX3DRootNode.Create;

  case AArchetype of
    faPineTree:
      begin
        TrunkCyl := TCylinderNode.CreateWithTransform(ShapeTrunk, TrunkTrans);
        TrunkCyl.Radius := 0.16;
        TrunkCyl.Height := 1.2;
        TrunkTrans.Translation := Vector3(0.0, 0.6, 0.0);
        AppTrunk := TAppearanceNode.Create;
        MatTrunk := TPhysicalMaterialNode.Create;
        MatTrunk.BaseColor := Vector3(0.36, 0.24, 0.14);
        MatTrunk.Roughness := 0.9;
        AppTrunk.Material := MatTrunk;
        ShapeTrunk.Appearance := AppTrunk;
        RootNode.AddChildren(TrunkTrans);

        ConeCanopy := TConeNode.CreateWithTransform(ShapeCanopy, CanopyTrans);
        ConeCanopy.BottomRadius := 1.05;
        ConeCanopy.Height := 3.2;
        CanopyTrans.Translation := Vector3(0.0, 2.5, 0.0);
        AppCanopy := TAppearanceNode.Create;
        MatCanopy := TPhysicalMaterialNode.Create;
        MatCanopy.BaseColor := Vector3(0.14, 0.42, 0.20);
        MatCanopy.Roughness := 0.82;
        AppCanopy.Material := MatCanopy;
        ShapeCanopy.Appearance := AppCanopy;
        RootNode.AddChildren(CanopyTrans);
      end;
    faBroadleafOak:
      begin
        TrunkCyl := TCylinderNode.CreateWithTransform(ShapeTrunk, TrunkTrans);
        TrunkCyl.Radius := 0.22;
        TrunkCyl.Height := 1.6;
        TrunkTrans.Translation := Vector3(0.0, 0.8, 0.0);
        AppTrunk := TAppearanceNode.Create;
        MatTrunk := TPhysicalMaterialNode.Create;
        MatTrunk.BaseColor := Vector3(0.38, 0.26, 0.16);
        AppTrunk.Material := MatTrunk;
        ShapeTrunk.Appearance := AppTrunk;
        RootNode.AddChildren(TrunkTrans);

        SphereCanopy := TSphereNode.CreateWithTransform(ShapeCanopy, CanopyTrans);
        SphereCanopy.Radius := 1.35;
        CanopyTrans.Translation := Vector3(0.0, 2.55, 0.0);
        AppCanopy := TAppearanceNode.Create;
        MatCanopy := TPhysicalMaterialNode.Create;
        MatCanopy.BaseColor := Vector3(0.24, 0.54, 0.18);
        MatCanopy.Roughness := 0.80;
        AppCanopy.Material := MatCanopy;
        ShapeCanopy.Appearance := AppCanopy;
        RootNode.AddChildren(CanopyTrans);
      end;
    faBushShrub:
      begin
        SphereCanopy := TSphereNode.CreateWithTransform(ShapeCanopy, CanopyTrans);
        SphereCanopy.Radius := 0.65;
        CanopyTrans.Translation := Vector3(0.0, 0.45, 0.0);
        AppCanopy := TAppearanceNode.Create;
        MatCanopy := TPhysicalMaterialNode.Create;
        MatCanopy.BaseColor := Vector3(0.28, 0.58, 0.24);
        AppCanopy.Material := MatCanopy;
        ShapeCanopy.Appearance := AppCanopy;
        RootNode.AddChildren(CanopyTrans);
      end;
    faBoulderRock:
      begin
        BoxRock := TBoxNode.CreateWithTransform(ShapeCanopy, CanopyTrans);
        BoxRock.Size := Vector3(1.1, 0.75, 0.95);
        CanopyTrans.Translation := Vector3(0.0, 0.35, 0.0);
        AppCanopy := TAppearanceNode.Create;
        MatCanopy := TPhysicalMaterialNode.Create;
        MatCanopy.BaseColor := Vector3(0.46, 0.45, 0.43);
        MatCanopy.Roughness := 0.92;
        AppCanopy.Material := MatCanopy;
        ShapeCanopy.Appearance := AppCanopy;
        RootNode.AddChildren(CanopyTrans);
      end;
  else
    begin
      ConeCanopy := TConeNode.CreateWithTransform(ShapeCanopy, CanopyTrans);
      ConeCanopy.BottomRadius := 0.32;
      ConeCanopy.Height := 0.65;
      CanopyTrans.Translation := Vector3(0.0, 0.32, 0.0);
      AppCanopy := TAppearanceNode.Create;
      MatCanopy := TPhysicalMaterialNode.Create;
      MatCanopy.BaseColor := Vector3(0.42, 0.68, 0.22);
      AppCanopy.Material := MatCanopy;
      ShapeCanopy.Appearance := AppCanopy;
      RootNode.AddChildren(CanopyTrans);
    end;
  end;

  PreviewScene.Load(RootNode, true);
  AInstance.Add(PreviewScene);
end;

{ TCastleFoliageExclusionVolume ---------------------------------------------- }

constructor TCastleFoliageExclusionVolume.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FExclusionSize := Vector3(8.0, 8.0, 8.0);
  FFalloffMargin := DefaultFalloffMargin;
  FShowVolumeInViewport := true;

  FExclusionSizePersistent := TCastleVector3Persistent.Create(nil);
  FExclusionSizePersistent.InternalGetValue := @GetExclusionSizeForPersistent;
  FExclusionSizePersistent.InternalSetValue := @SetExclusionSizeForPersistent;
  FExclusionSizePersistent.InternalDefaultValue := FExclusionSize;
end;

destructor TCastleFoliageExclusionVolume.Destroy;
begin
  FreeAndNil(FExclusionSizePersistent);
  inherited;
end;

function TCastleFoliageExclusionVolume.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'ExclusionSizePersistent', 'FalloffMargin', 'ShowVolumeInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleFoliageExclusionVolume.GetExclusionSizeForPersistent: TVector3;
begin
  Result := FExclusionSize;
end;

procedure TCastleFoliageExclusionVolume.SetExclusionSizeForPersistent(
  const AValue: TVector3);
begin
  SetExclusionSize(AValue);
end;

procedure TCastleFoliageExclusionVolume.SetExclusionSize(const Value: TVector3);
begin
  FExclusionSize := Vector3(
    Max(0.25, Value.X),
    Max(0.25, Value.Y),
    Max(0.25, Value.Z));
end;

procedure TCastleFoliageExclusionVolume.SetFalloffMargin(const Value: Single);
begin
  FFalloffMargin := Max(0.0, Value);
end;

function TCastleFoliageExclusionVolume.ContainsWorldPoint(
  const AWorldPt: TVector3): Boolean;
var
  M, InvM: TMatrix4;
  LocalPt: TVector3;
begin
  if not Exists then
    Exit(false);
  M := GetFoliageHierarchyMatrix(Self);
  if M.TryInverse(InvM) then
    LocalPt := InvM.MultPoint(AWorldPt)
  else
    LocalPt := AWorldPt - Translation;

  Result :=
    (Abs(LocalPt.X) <= FExclusionSize.X * 0.5 + FFalloffMargin) and
    (Abs(LocalPt.Y) <= FExclusionSize.Y * 0.5 + FFalloffMargin) and
    (Abs(LocalPt.Z) <= FExclusionSize.Z * 0.5 + FFalloffMargin);
end;

function TCastleFoliageExclusionVolume.ExclusionSummaryBadge: String;
begin
  Result := Format('[Exclude:%.0fx%.0fm]', [FExclusionSize.X, FExclusionSize.Z]);
end;

{ TCastleLodProxyBehavior ---------------------------------------------------- }

constructor TCastleLodProxyBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHighUrl := '';
  FMediumUrl := '';
  FLowUrl := '';
  FMediumDistance := DefaultMediumDistance;
  FLowDistance := DefaultLowDistance;
  FCullDistance := DefaultCullDistance;
  FHysteresisMargin := DefaultHysteresisMargin;
  FAutoEvaluateFromCamera := true;
  FCurrentLodLevel := fllHigh;
end;

function TCastleLodProxyBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'HighUrl', 'MediumUrl', 'LowUrl',
       'MediumDistance', 'LowDistance', 'CullDistance',
       'HysteresisMargin', 'AutoEvaluateFromCamera'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleLodProxyBehavior.SetMediumDistance(const Value: Single);
begin
  FMediumDistance := Max(0.5, Value);
end;

procedure TCastleLodProxyBehavior.SetLowDistance(const Value: Single);
begin
  FLowDistance := Max(1.0, Value);
end;

procedure TCastleLodProxyBehavior.SetCullDistance(const Value: Single);
begin
  FCullDistance := Max(2.0, Value);
end;

procedure TCastleLodProxyBehavior.SetHysteresisMargin(const Value: Single);
begin
  FHysteresisMargin := Clamped(Value, 0.0, 50.0);
end;

class function TCastleLodProxyBehavior.LodLevelToName(
  const ALevel: TFoliageLodLevel): String;
begin
  case ALevel of
    fllHigh: Result := 'High';
    fllMedium: Result := 'Medium';
    fllLow: Result := 'Low';
    fllCulled: Result := 'Culled';
  end;
end;

function TCastleLodProxyBehavior.EvaluateForDistance(
  const ADistance: Single): TFoliageLodLevel;
var
  D, H, MedD, LowD, CullD: Single;
  PrevLevel: TFoliageLodLevel;
begin
  D := Max(0.0, ADistance);
  MedD := Max(0.5, FMediumDistance);
  LowD := Max(MedD + 0.5, FLowDistance);
  CullD := Max(LowD + 0.5, FCullDistance);
  H := Min(FHysteresisMargin, (LowD - MedD) * 0.45);

  PrevLevel := FCurrentLodLevel;
  case PrevLevel of
    fllHigh:
      begin
        if D > CullD + H then
          FCurrentLodLevel := fllCulled
        else if D > LowD + H then
          FCurrentLodLevel := fllLow
        else if D > MedD + H then
          FCurrentLodLevel := fllMedium;
      end;
    fllMedium:
      begin
        if D < MedD - H then
          FCurrentLodLevel := fllHigh
        else if D > CullD + H then
          FCurrentLodLevel := fllCulled
        else if D > LowD + H then
          FCurrentLodLevel := fllLow;
      end;
    fllLow:
      begin
        if D < MedD - H then
          FCurrentLodLevel := fllHigh
        else if D < LowD - H then
          FCurrentLodLevel := fllMedium
        else if D > CullD + H then
          FCurrentLodLevel := fllCulled;
      end;
    fllCulled:
      begin
        if D < MedD - H then
          FCurrentLodLevel := fllHigh
        else if D < LowD - H then
          FCurrentLodLevel := fllMedium
        else if D < CullD - H then
          FCurrentLodLevel := fllLow;
      end;
  end;

  if FCurrentLodLevel <> PrevLevel then
    ApplyLodVisualState;
  Result := FCurrentLodLevel;
end;

function TCastleLodProxyBehavior.ActiveResolvedUrl: String;
begin
  case FCurrentLodLevel of
    fllHigh: Result := FHighUrl;
    fllMedium:
      if FMediumUrl <> '' then
        Result := FMediumUrl
      else
        Result := FHighUrl;
    fllLow:
      if FLowUrl <> '' then
        Result := FLowUrl
      else if FMediumUrl <> '' then
        Result := FMediumUrl
      else
        Result := FHighUrl;
    fllCulled: Result := '';
  end;
end;

procedure TCastleLodProxyBehavior.ApplyLodVisualState;
var
  S: TCastleScene;
  TargetUrl: String;
begin
  if (Parent = nil) or CastleDesignMode then
    Exit;

  Parent.Visible := FCurrentLodLevel <> fllCulled;
  if (FCurrentLodLevel <> fllCulled) and (Parent is TCastleScene) then
  begin
    S := TCastleScene(Parent);
    TargetUrl := ActiveResolvedUrl;
    if (TargetUrl <> '') and (S.Url <> TargetUrl) then
      S.Url := TargetUrl;
  end;
end;

procedure TCastleLodProxyBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
var
  CamPos, ObjPos: TVector3;
begin
  inherited;
  if FAutoEvaluateFromCamera and (not CastleDesignMode) and
     (Parent <> nil) and (Parent.World <> nil) and
     (Parent.World.MainCamera <> nil) then
  begin
    CamPos := Parent.World.MainCamera.WorldTranslation;
    ObjPos := Parent.WorldTranslation;
    EvaluateForDistance(PointsDistance(CamPos, ObjPos));
  end;
end;

function TCastleLodProxyBehavior.LodSummaryBadge: String;
begin
  Result := Format('[LOD:%s %.0f/%.0f/%.0fm]',
    [LodLevelToName(FCurrentLodLevel), FMediumDistance, FLowDistance, FCullDistance]);
end;

{ TCastleFoliageBiomeVolume -------------------------------------------------- }

constructor TCastleFoliageBiomeVolume.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBiomeTitle := 'Alpine Pine Forest';
  FVolumeSize := Vector3(40.0, 24.0, 40.0);
  FSeed := DefaultSeed;
  FTargetInstanceCount := DefaultTargetInstanceCount;
  FGlobalMinAltitude := DefaultGlobalMinAltitude;
  FGlobalMaxAltitude := DefaultGlobalMaxAltitude;
  FGlobalMaxSlopeDeg := DefaultGlobalMaxSlopeDeg;
  FShowVolumeInViewport := true;

  FVolumeSizePersistent := TCastleVector3Persistent.Create(nil);
  FVolumeSizePersistent.InternalGetValue := @GetVolumeSizeForPersistent;
  FVolumeSizePersistent.InternalSetValue := @SetVolumeSizeForPersistent;
  FVolumeSizePersistent.InternalDefaultValue := FVolumeSize;

  LoadBiomePreset(0);
end;

destructor TCastleFoliageBiomeVolume.Destroy;
begin
  FreeAndNil(FVolumeSizePersistent);
  inherited;
end;

function TCastleFoliageBiomeVolume.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'BiomeTitle', 'VolumeSizePersistent', 'Seed', 'TargetInstanceCount',
       'GlobalMinAltitude', 'GlobalMaxAltitude', 'GlobalMaxSlopeDeg',
       'SpeciesJson', 'ShowVolumeInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleFoliageBiomeVolume.GetVolumeSizeForPersistent: TVector3;
begin
  Result := FVolumeSize;
end;

procedure TCastleFoliageBiomeVolume.SetVolumeSizeForPersistent(
  const AValue: TVector3);
begin
  SetVolumeSize(AValue);
end;

procedure TCastleFoliageBiomeVolume.SetVolumeSize(const Value: TVector3);
begin
  FVolumeSize := Vector3(
    Max(1.0, Value.X),
    Max(1.0, Value.Y),
    Max(1.0, Value.Z));
end;

procedure TCastleFoliageBiomeVolume.SetTargetInstanceCount(const Value: Integer);
begin
  FTargetInstanceCount := Clamped(Value, 1, 2000);
end;

procedure TCastleFoliageBiomeVolume.SetGlobalMaxSlopeDeg(const Value: Single);
begin
  FGlobalMaxSlopeDeg := Clamped(Value, 1.0, 90.0);
end;

class function TCastleFoliageBiomeVolume.ArchetypeToName(
  const AArch: TFoliageArchetype): String;
begin
  case AArch of
    faPineTree: Result := 'PineTree';
    faBroadleafOak: Result := 'BroadleafOak';
    faBushShrub: Result := 'BushShrub';
    faBoulderRock: Result := 'BoulderRock';
    faWildGrass: Result := 'WildGrass';
    faCustomUrl: Result := 'CustomUrl';
  end;
end;

class function TCastleFoliageBiomeVolume.NameToArchetype(
  const S: String): TFoliageArchetype;
var
  T: String;
begin
  T := LowerCase(Trim(S));
  if T = 'broadleafoak' then Result := faBroadleafOak
  else if T = 'bushshrub' then Result := faBushShrub
  else if T = 'boulderrock' then Result := faBoulderRock
  else if T = 'wildgrass' then Result := faWildGrass
  else if T = 'customurl' then Result := faCustomUrl
  else Result := faPineTree;
end;

procedure TCastleFoliageBiomeVolume.ClearSpecies;
begin
  FSpecies := nil;
end;

function TCastleFoliageBiomeVolume.SpeciesCount: Integer;
begin
  Result := Length(FSpecies);
end;

function TCastleFoliageBiomeVolume.GetSpecies(
  const AIndex: Integer): TFoliageSpeciesEntry;
begin
  if (AIndex >= 0) and (AIndex < Length(FSpecies)) then
    Result := FSpecies[AIndex]
  else
    Result := Default(TFoliageSpeciesEntry);
end;

function TCastleFoliageBiomeVolume.AddOrUpdateSpecies(
  const AEntry: TFoliageSpeciesEntry): Integer;
var
  I: Integer;
  CleanId: String;
begin
  CleanId := Trim(AEntry.SpeciesId);
  if CleanId = '' then
    Exit(-1);
  Result := -1;
  for I := 0 to High(FSpecies) do
    if SameText(FSpecies[I].SpeciesId, CleanId) then
    begin
      Result := I;
      Break;
    end;
  if Result < 0 then
  begin
    Result := Length(FSpecies);
    SetLength(FSpecies, Result + 1);
  end;
  FSpecies[Result] := AEntry;
  FSpecies[Result].SpeciesId := CleanId;
  FSpecies[Result].Weight := Max(0.01, AEntry.Weight);
  FSpecies[Result].MinScale := Max(0.1, AEntry.MinScale);
  FSpecies[Result].MaxScale := Max(FSpecies[Result].MinScale, AEntry.MaxScale);
  FSpecies[Result].MinRadiusSpacing := Max(0.1, AEntry.MinRadiusSpacing);
  FSpecies[Result].AlignToSlopeFactor := Clamped(AEntry.AlignToSlopeFactor, 0.0, 1.0);
  FSpecies[Result].MaxSlopeDeg := Clamped(AEntry.MaxSlopeDeg, 1.0, 90.0);
end;

procedure TCastleFoliageBiomeVolume.LoadBiomePreset(const APresetIndex: Integer);
var
  E: TFoliageSpeciesEntry;
begin
  ClearSpecies;
  case APresetIndex of
    1:
      begin
        FBiomeTitle := 'Temperate Oak Meadow';
        E := Default(TFoliageSpeciesEntry);
        E.SpeciesId := 'AncientOak'; E.Archetype := faBroadleafOak;
        E.Weight := 1.0; E.MinScale := 0.9; E.MaxScale := 1.35;
        E.MinRadiusSpacing := 3.5; E.AlignToSlopeFactor := 0.12;
        E.MinAltitude := -50.0; E.MaxAltitude := 180.0; E.MaxSlopeDeg := 28.0;
        AddOrUpdateSpecies(E);

        E.SpeciesId := 'MeadowShrub'; E.Archetype := faBushShrub;
        E.Weight := 2.2; E.MinScale := 0.8; E.MaxScale := 1.25;
        E.MinRadiusSpacing := 1.4; E.AlignToSlopeFactor := 0.35;
        E.MinAltitude := -50.0; E.MaxAltitude := 220.0; E.MaxSlopeDeg := 38.0;
        AddOrUpdateSpecies(E);

        E.SpeciesId := 'TallGrass'; E.Archetype := faWildGrass;
        E.Weight := 3.5; E.MinScale := 0.8; E.MaxScale := 1.3;
        E.MinRadiusSpacing := 0.75; E.AlignToSlopeFactor := 0.75;
        E.MinAltitude := -50.0; E.MaxAltitude := 250.0; E.MaxSlopeDeg := 42.0;
        AddOrUpdateSpecies(E);
      end;
    2:
      begin
        FBiomeTitle := 'Rocky Canyon Scrub';
        E := Default(TFoliageSpeciesEntry);
        E.SpeciesId := 'GraniteBoulder'; E.Archetype := faBoulderRock;
        E.Weight := 1.8; E.MinScale := 0.75; E.MaxScale := 1.65;
        E.MinRadiusSpacing := 2.2; E.AlignToSlopeFactor := 0.80;
        E.MinAltitude := -100.0; E.MaxAltitude := 450.0; E.MaxSlopeDeg := 55.0;
        AddOrUpdateSpecies(E);

        E.SpeciesId := 'CanyonScrub'; E.Archetype := faBushShrub;
        E.Weight := 2.5; E.MinScale := 0.7; E.MaxScale := 1.15;
        E.MinRadiusSpacing := 1.3; E.AlignToSlopeFactor := 0.45;
        E.MinAltitude := -100.0; E.MaxAltitude := 350.0; E.MaxSlopeDeg := 40.0;
        AddOrUpdateSpecies(E);
      end;
  else
    begin
      FBiomeTitle := 'Alpine Pine Forest';
      E := Default(TFoliageSpeciesEntry);
      E.SpeciesId := 'NordicPine'; E.Archetype := faPineTree;
      E.Weight := 2.0; E.MinScale := 0.85; E.MaxScale := 1.35;
      E.MinRadiusSpacing := 2.4; E.AlignToSlopeFactor := 0.15;
      E.MinAltitude := -50.0; E.MaxAltitude := 300.0; E.MaxSlopeDeg := 32.0;
      AddOrUpdateSpecies(E);

      E.SpeciesId := 'Underbrush'; E.Archetype := faBushShrub;
      E.Weight := 2.0; E.MinScale := 0.8; E.MaxScale := 1.2;
      E.MinRadiusSpacing := 1.3; E.AlignToSlopeFactor := 0.35;
      E.MinAltitude := -50.0; E.MaxAltitude := 260.0; E.MaxSlopeDeg := 38.0;
      AddOrUpdateSpecies(E);

      E.SpeciesId := 'MossBoulder'; E.Archetype := faBoulderRock;
      E.Weight := 0.8; E.MinScale := 0.75; E.MaxScale := 1.4;
      E.MinRadiusSpacing := 2.0; E.AlignToSlopeFactor := 0.75;
      E.MinAltitude := -50.0; E.MaxAltitude := 400.0; E.MaxSlopeDeg := 50.0;
      AddOrUpdateSpecies(E);
    end;
  end;
end;

function TCastleFoliageBiomeVolume.ClearGeneratedInstances: Integer;
var
  I: Integer;
  Child: TCastleTransform;
begin
  Result := 0;
  for I := Count - 1 downto 0 do
  begin
    Child := Items[I];
    if (Child <> nil) and (Child.Tag = FoliageGeneratedInstanceTag) then
    begin
      Remove(Child);
      FreeAndNil(Child);
      Inc(Result);
    end;
  end;
end;

function TCastleFoliageBiomeVolume.GeneratedInstanceCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    if (Items[I] <> nil) and (Items[I].Tag = FoliageGeneratedInstanceTag) then
      Inc(Result);
end;

function TCastleFoliageBiomeVolume.PopulateBiomeInstances(
  const ADesignOwner: TComponent;
  const AExclusions: array of TCastleFoliageExclusionVolume): Integer;
type
  TSpawnRecord = record
    WorldPos: TVector3;
    Radius: Single;
  end;
var
  OwnerToUse: TComponent;
  Rng: Cardinal;
  VolMat, VolInvMat: TMatrix4;
  Spawned: array of TSpawnRecord;
  TotalWeight, PickW, AccW, U, V, LocalX, LocalZ, ScaleS, YawRad, SlopeDeg: Single;
  CandidateTopLocal, CandidateBotLocal, RayStartW, RayEndW, HitPosW, HitNormW: TVector3;
  InstLocalPos, BlendedUp, FwdDir: TVector3;
  SpanLen: Single;
  MaxAttempts, Attempt, SpecIdx, I, ExIdx, NameCounter: Integer;
  Spec: TFoliageSpeciesEntry;
  SavedPickable, Blocked: Boolean;
  Inst: TCastleTransform;
  LodBeh: TCastleLodProxyBehavior;

  function SampleGroundAt(const ATopW: TVector3; const ASpan: Single;
    out OutHitW, OutNormW: TVector3): Boolean;
  var
    RayHit, RayX, RayZ: TRayCollision;
    PX, PZ, V1, V2: TVector3;
  begin
    Result := false;
    if World <> nil then
    begin
      RayHit := World.WorldRay(ATopW, Vector3(0.0, -1.0, 0.0));
      if RayHit <> nil then
      try
        if (RayHit.Transform <> nil) and (RayHit.Distance <= ASpan + 0.05) then
        begin
          OutHitW := ATopW + Vector3(0.0, -RayHit.Distance, 0.0);
          OutNormW := Vector3(0.0, 1.0, 0.0);
          if (RayHit.Count > 0) and (RayHit.First.Triangle <> nil) and
             (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
          begin
            OutNormW := RayHit.First.Item.LocalToWorldDirection(
              RayHit.First.Triangle^.SceneSpace.Normal);
            if OutNormW.LengthSqr < 1e-8 then
              OutNormW := Vector3(0.0, 1.0, 0.0)
            else
              OutNormW := OutNormW.Normalize;
            if OutNormW.Y < 0.0 then
              OutNormW := -OutNormW;
          end else
          begin
            { Finite-difference fallback for analytical primitives }
            RayX := World.WorldRay(ATopW + Vector3(0.06, 0.0, 0.0), Vector3(0.0, -1.0, 0.0));
            RayZ := World.WorldRay(ATopW + Vector3(0.0, 0.0, 0.06), Vector3(0.0, -1.0, 0.0));
            try
              if (RayX <> nil) and (RayZ <> nil) and
                 (RayX.Transform <> nil) and (RayZ.Transform <> nil) then
              begin
                PX := ATopW + Vector3(0.06, -RayX.Distance, 0.0);
                PZ := ATopW + Vector3(0.0, -RayZ.Distance, 0.06);
                V1 := PZ - OutHitW;
                V2 := PX - OutHitW;
                OutNormW := TVector3.CrossProduct(V1, V2);
                if OutNormW.LengthSqr > 1e-10 then
                  OutNormW := OutNormW.Normalize
                else
                  OutNormW := Vector3(0.0, 1.0, 0.0);
                if OutNormW.Y < 0.0 then
                  OutNormW := -OutNormW;
              end;
            finally
              FreeAndNil(RayX);
              FreeAndNil(RayZ);
            end;
          end;
          Result := true;
        end;
      finally
        FreeAndNil(RayHit);
      end;
    end else
    begin
      { Headless fallback when volume is not inside a TCastleViewport: flat volume floor }
      OutHitW := ATopW + Vector3(0.0, -ASpan * 0.5, 0.0);
      OutNormW := Vector3(0.0, 1.0, 0.0);
      Result := true;
    end;
  end;

  function ProposeInstName(const ABase: String): String;
  begin
    repeat
      Inc(NameCounter);
      Result := Format('%s_%s_%d', [Name, ABase, NameCounter]);
    until (OwnerToUse = nil) or (OwnerToUse.FindComponent(Result) = nil);
  end;

begin
  Result := 0;
  ClearGeneratedInstances;
  if Length(FSpecies) = 0 then
    Exit;

  if ADesignOwner <> nil then
    OwnerToUse := ADesignOwner
  else
    OwnerToUse := Owner;

  TotalWeight := 0.0;
  for I := 0 to High(FSpecies) do
    TotalWeight := TotalWeight + Max(0.01, FSpecies[I].Weight);

  VolMat := GetFoliageHierarchyMatrix(Self);
  if not VolMat.TryInverse(VolInvMat) then
    VolInvMat := TMatrix4.Identity;

  Rng := Cardinal(Max(1, Abs(FSeed)));
  Spawned := nil;
  NameCounter := 0;
  MaxAttempts := Max(64, FTargetInstanceCount * 10);

  SavedPickable := Pickable;
  Pickable := false;
  try
    for Attempt := 1 to MaxAttempts do
    begin
      if Length(Spawned) >= FTargetInstanceCount then
        Break;

      { Low-discrepancy 2D Halton (bases 2, 3) shifted by Seed }
      U := Frac(HaltonRadicalInverse(Attempt + Abs(FSeed) * 17, 2));
      V := Frac(HaltonRadicalInverse(Attempt + Abs(FSeed) * 31, 3));
      LocalX := (U - 0.5) * FVolumeSize.X;
      LocalZ := (V - 0.5) * FVolumeSize.Z;

      { Weighted species selection }
      PickW := NextFoliageUnitFloat(Rng) * TotalWeight;
      AccW := 0.0;
      SpecIdx := High(FSpecies);
      for I := 0 to High(FSpecies) do
      begin
        AccW := AccW + Max(0.01, FSpecies[I].Weight);
        if PickW <= AccW then
        begin
          SpecIdx := I;
          Break;
        end;
      end;
      Spec := FSpecies[SpecIdx];

      CandidateTopLocal := Vector3(LocalX, FVolumeSize.Y * 0.5, LocalZ);
      CandidateBotLocal := Vector3(LocalX, -FVolumeSize.Y * 0.5, LocalZ);
      RayStartW := VolMat.MultPoint(CandidateTopLocal);
      RayEndW := VolMat.MultPoint(CandidateBotLocal);
      SpanLen := PointsDistance(RayStartW, RayEndW);

      if not SampleGroundAt(RayStartW, SpanLen, HitPosW, HitNormW) then
        Continue;

      { 1. Altitude filter (global + species) }
      if (HitPosW.Y < FGlobalMinAltitude) or (HitPosW.Y > FGlobalMaxAltitude) or
         (HitPosW.Y < Spec.MinAltitude) or (HitPosW.Y > Spec.MaxAltitude) then
        Continue;

      { 2. Surface slope filter }
      SlopeDeg := RadToDeg(ArcCos(Clamped(HitNormW.Y, -1.0, 1.0)));
      if (SlopeDeg > FGlobalMaxSlopeDeg) or (SlopeDeg > Spec.MaxSlopeDeg) then
        Continue;

      { 3. Exclusion volume mask filter }
      Blocked := false;
      for ExIdx := Low(AExclusions) to High(AExclusions) do
        if (AExclusions[ExIdx] <> nil) and AExclusions[ExIdx].ContainsWorldPoint(HitPosW) then
        begin
          Blocked := true;
          Break;
        end;
      if Blocked then
        Continue;

      { 4. Poisson minimum radius spacing check }
      for I := 0 to High(Spawned) do
        if PointsDistanceSqr(HitPosW, Spawned[I].WorldPos) <
           Sqr(Max(Spec.MinRadiusSpacing, Spawned[I].Radius)) then
        begin
          Blocked := true;
          Break;
        end;
      if Blocked then
        Continue;

      { 5. Spawn foliage instance }
      ScaleS := Lerp(NextFoliageUnitFloat(Rng), Spec.MinScale, Spec.MaxScale);
      YawRad := NextFoliageUnitFloat(Rng) * 2.0 * Pi;
      InstLocalPos := VolInvMat.MultPoint(HitPosW);

      if (Spec.AssetUrl <> '') then
      begin
        Inst := TCastleScene.Create(OwnerToUse);
        TCastleScene(Inst).Url := Spec.AssetUrl;
      end else
      begin
        Inst := TCastleTransform.Create(OwnerToUse);
        AttachTransientFoliageMesh(Inst, Spec.Archetype);
      end;
      Inst.Name := ProposeInstName(Spec.SpeciesId);
      Inst.Tag := FoliageGeneratedInstanceTag;

      BlendedUp := Lerp(Spec.AlignToSlopeFactor, Vector3(0.0, 1.0, 0.0), HitNormW);
      if BlendedUp.LengthSqr < 1e-8 then
        BlendedUp := Vector3(0.0, 1.0, 0.0)
      else
        BlendedUp := BlendedUp.Normalize;
      FwdDir := Vector3(Sin(YawRad), 0.0, Cos(YawRad));
      MakeVectorsOrthoOnTheirPlane(FwdDir, BlendedUp);
      if FwdDir.LengthSqr < 1e-8 then
        FwdDir := Vector3(0.0, 0.0, 1.0)
      else
        FwdDir := FwdDir.Normalize;

      Inst.SetView(InstLocalPos, FwdDir, BlendedUp);
      Inst.Scale := Vector3(ScaleS, ScaleS, ScaleS);

      if (Spec.MediumLodUrl <> '') or (Spec.LowLodUrl <> '') then
      begin
        LodBeh := TCastleLodProxyBehavior.Create(OwnerToUse);
        LodBeh.Name := ProposeInstName('LodProxy');
        LodBeh.HighUrl := Spec.AssetUrl;
        LodBeh.MediumUrl := Spec.MediumLodUrl;
        LodBeh.LowUrl := Spec.LowLodUrl;
        Inst.AddBehavior(LodBeh);
      end;

      Add(Inst);

      SetLength(Spawned, Length(Spawned) + 1);
      Spawned[High(Spawned)].WorldPos := HitPosW;
      Spawned[High(Spawned)].Radius := Spec.MinRadiusSpacing;
    end;
  finally
    Pickable := SavedPickable;
  end;

  Result := Length(Spawned);
end;

function TCastleFoliageBiomeVolume.GetSpeciesJson: String;
var
  RootObj, SObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  if Length(FSpecies) = 0 then
    Exit('');
  RootObj := TJSONObject.Create;
  try
    Arr := TJSONArray.Create;
    for I := 0 to High(FSpecies) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('id', FSpecies[I].SpeciesId);
      SObj.Add('arch', ArchetypeToName(FSpecies[I].Archetype));
      SObj.Add('url', FSpecies[I].AssetUrl);
      SObj.Add('medUrl', FSpecies[I].MediumLodUrl);
      SObj.Add('lowUrl', FSpecies[I].LowLodUrl);
      SObj.Add('weight', FSpecies[I].Weight);
      SObj.Add('minS', FSpecies[I].MinScale);
      SObj.Add('maxS', FSpecies[I].MaxScale);
      SObj.Add('spacing', FSpecies[I].MinRadiusSpacing);
      SObj.Add('align', FSpecies[I].AlignToSlopeFactor);
      SObj.Add('minAlt', FSpecies[I].MinAltitude);
      SObj.Add('maxAlt', FSpecies[I].MaxAltitude);
      SObj.Add('maxSlope', FSpecies[I].MaxSlopeDeg);
      Arr.Add(SObj);
    end;
    RootObj.Add('species', Arr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleFoliageBiomeVolume.SetSpeciesJson(const Value: String);
var
  Data: TJSONData;
  RootObj, SObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  E: TFoliageSpeciesEntry;
begin
  if Trim(Value) = '' then
  begin
    FSpecies := nil;
    Exit;
  end;

  Data := nil;
  try
    try
      Data := GetJSON(Value);
    except
      Data := nil;
    end;
    if not (Data is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Data);
    Arr := RootObj.Find('species', jtArray) as TJSONArray;
    if Arr = nil then
      Exit;

    FSpecies := nil;
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
      begin
        SObj := TJSONObject(Arr.Items[I]);
        E := Default(TFoliageSpeciesEntry);
        E.SpeciesId := SObj.Get('id', '');
        E.Archetype := NameToArchetype(SObj.Get('arch', 'PineTree'));
        E.AssetUrl := SObj.Get('url', '');
        E.MediumLodUrl := SObj.Get('medUrl', '');
        E.LowLodUrl := SObj.Get('lowUrl', '');
        E.Weight := SObj.Get('weight', 1.0);
        E.MinScale := SObj.Get('minS', 0.85);
        E.MaxScale := SObj.Get('maxS', 1.25);
        E.MinRadiusSpacing := SObj.Get('spacing', 2.0);
        E.AlignToSlopeFactor := SObj.Get('align', 0.2);
        E.MinAltitude := SObj.Get('minAlt', -100.0);
        E.MaxAltitude := SObj.Get('maxAlt', 500.0);
        E.MaxSlopeDeg := SObj.Get('maxSlope', 35.0);
        AddOrUpdateSpecies(E);
      end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleFoliageBiomeVolume.BiomeSummaryBadge: String;
begin
  Result := Format('[Biome:%s %d inst]', [FBiomeTitle, GeneratedInstanceCount]);
end;

initialization
  RegisterSerializableComponent(TCastleFoliageBiomeVolume,
    ['Environment & Biomes', 'Foliage Biome Volume']);
  RegisterSerializableComponent(TCastleFoliageExclusionVolume,
    ['Environment & Biomes', 'Foliage Exclusion Volume']);
  RegisterSerializableComponent(TCastleLodProxyBehavior,
    ['Environment & Biomes', 'LOD Proxy Behavior']);
end.
