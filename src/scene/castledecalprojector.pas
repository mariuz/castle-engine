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

{ Oriented 3D surface decal projector (@link(TCastleDecalProjector)) with
  conformal world-raycast mesh draping, grazing normal-angle cutoff,
  Z-fight-free @code(SurfaceOffset) + @code(SortOrder) layering, optional
  custom @code(TextureUrl), and procedural weathering presets
  (Phase 298 — UE 6.0 UDecalComponent & Mesh Decals Parity). }
unit CastleDecalProjector;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Built-in 1-click surface decal & weathering presets. }
  TDecalPreset = (
    dpCustom,
    dpPuddleWet,
    dpScorchMark,
    dpBulletImpact,
    dpMossGrowth,
    dpHazardStripe,
    dpMagicRune
  );

  { GPU alpha / compositing mode for projected decal geometry. }
  TDecalBlendStyle = (
    dbsAlphaBlend,
    dbsAdditiveGlow,
    dbsMultiplyStain
  );

  { Oriented 3D projection volume casting along local @code(-Y) onto world
    surfaces within @code([-BoxExtents/2 .. +BoxExtents/2]).
    Generates a @code(csTransient) conformal mesh child so editor saves never
    bloat @code(.castle-transform) or @code(.castle-user-interface) files. }
  TCastleDecalProjector = class(TCastleTransform)
  strict private
    FPreset: TDecalPreset;
    FBlendStyle: TDecalBlendStyle;
    FBoxExtents: TVector3;
    FBoxExtentsPersistent: TCastleVector3Persistent;
    FBaseColor: TCastleColor;
    FBaseColorPersistent: TCastleColorPersistent;
    FTextureUrl: String;
    FOpacity: Single;
    FRoughness: Single;
    FMetallic: Single;
    FNormalAngleCutoffDeg: Single;
    FRadialEdgeFade: Single;
    FSurfaceOffset: Single;
    FSortOrder: Integer;
    FGridResolution: Integer;
    FProjectToWorldGeometry: Boolean;
    FShowProjectorBoxInViewport: Boolean;

    FProjectedTriangleCount: Integer;
    FLastAcceptedCellCount: Integer;
    FLastRejectedAngleCellCount: Integer;

    FRenderScene: TCastleScene;
    FRootNode: TX3DRootNode;
    FAppearanceNode: TAppearanceNode;
    FMaterialNode: TPhysicalMaterialNode;
    FImageTexNode: TImageTextureNode;
    FBlendModeNode: TBlendModeNode;
    FTriSetNode: TTriangleSetNode;
    FCoordNode: TCoordinateNode;
    FNormalNode: TNormalNode;
    FTexCoordNode: TTextureCoordinateNode;
    FColorNode: TColorRGBANode;

    FVertexBuffer: TVector3List;
    FNormalBuffer: TVector3List;
    FTexCoordBuffer: TVector2List;
    FColorBuffer: TVector4List;

    procedure SetPreset(const Value: TDecalPreset);
    procedure SetBlendStyle(const Value: TDecalBlendStyle);
    procedure SetBoxExtents(const Value: TVector3);
    function GetBoxExtentsForPersistent: TVector3;
    procedure SetBoxExtentsForPersistent(const AValue: TVector3);
    procedure SetBaseColor(const Value: TCastleColor);
    function GetBaseColorForPersistent: TCastleColor;
    procedure SetBaseColorForPersistent(const AValue: TCastleColor);
    procedure SetTextureUrl(const Value: String);
    procedure SetOpacity(const Value: Single);
    procedure SetRoughness(const Value: Single);
    procedure SetMetallic(const Value: Single);
    procedure SetNormalAngleCutoffDeg(const Value: Single);
    procedure SetRadialEdgeFade(const Value: Single);
    procedure SetSurfaceOffset(const Value: Single);
    procedure SetSortOrder(const Value: Integer);
    procedure SetGridResolution(const Value: Integer);
    procedure SetProjectToWorldGeometry(const Value: Boolean);

    function OpacityStored: Boolean;
    function RoughnessStored: Boolean;
    function MetallicStored: Boolean;
    function NormalAngleCutoffStored: Boolean;
    function RadialEdgeFadeStored: Boolean;
    function SurfaceOffsetStored: Boolean;

    procedure EnsureRenderScene;
    procedure SyncMaterialAndBlendNodes;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;

    { Apply one of the built-in weathering/decal presets. }
    procedure ApplyPreset(const APreset: TDecalPreset);

    { Evaluate procedural RGBA color & alpha falloff at normalized UV in [0..1]^2
      (used both for mesh vertex coloring and editor 2D stamp preview). }
    function EvaluateProceduralSample(const AU, AV: Single): TCastleColor;

    { Project the decal grid onto @code(World) geometry (when
      @link(ProjectToWorldGeometry) is @true and @code(World <> nil)) or build a
      local preview quad, rejecting cells steeper than @link(NormalAngleCutoffDeg).
      Returns the number of generated triangles. }
    function ConformAndRebuildMesh: Integer;

    property BoxExtents: TVector3 read FBoxExtents write SetBoxExtents;
    property BaseColor: TCastleColor read FBaseColor write SetBaseColor;
    property ProjectedTriangleCount: Integer read FProjectedTriangleCount;
    property LastAcceptedCellCount: Integer read FLastAcceptedCellCount;
    property LastRejectedAngleCellCount: Integer read FLastRejectedAngleCellCount;

    function DecalSummaryBadge: String;
  published
    property Preset: TDecalPreset read FPreset write SetPreset default dpPuddleWet;
    property BlendStyle: TDecalBlendStyle
      read FBlendStyle write SetBlendStyle default dbsAlphaBlend;
    property BoxExtentsPersistent: TCastleVector3Persistent read FBoxExtentsPersistent;
    property BaseColorPersistent: TCastleColorPersistent read FBaseColorPersistent;
    property TextureUrl: String read FTextureUrl write SetTextureUrl;
    property Opacity: Single read FOpacity write SetOpacity stored OpacityStored;
    property Roughness: Single read FRoughness write SetRoughness stored RoughnessStored;
    property Metallic: Single read FMetallic write SetMetallic stored MetallicStored;
    property NormalAngleCutoffDeg: Single
      read FNormalAngleCutoffDeg write SetNormalAngleCutoffDeg stored NormalAngleCutoffStored;
    property RadialEdgeFade: Single
      read FRadialEdgeFade write SetRadialEdgeFade stored RadialEdgeFadeStored;
    property SurfaceOffset: Single
      read FSurfaceOffset write SetSurfaceOffset stored SurfaceOffsetStored;
    property SortOrder: Integer read FSortOrder write SetSortOrder default 0;
    property GridResolution: Integer
      read FGridResolution write SetGridResolution default 8;
    property ProjectToWorldGeometry: Boolean
      read FProjectToWorldGeometry write SetProjectToWorldGeometry default true;
    property ShowProjectorBoxInViewport: Boolean
      read FShowProjectorBoxInViewport write FShowProjectorBoxInViewport default true;
  end;

function DecalPresetToString(const APreset: TDecalPreset): String;
function DecalBlendStyleToString(const AStyle: TDecalBlendStyle): String;

implementation

uses
  Math,
  CastleComponentSerialize, CastleRenderOptions;

const
  DefaultOpacity = 0.88;
  DefaultRoughness = 0.08;
  DefaultMetallic = 0.05;
  DefaultNormalCutoffDeg = 65.0;
  DefaultRadialEdgeFade = 0.35;
  DefaultSurfaceOffset = 0.012;

function DecalPresetToString(const APreset: TDecalPreset): String;
begin
  case APreset of
    dpCustom:       Result := 'Custom';
    dpPuddleWet:    Result := 'Wet Puddle';
    dpScorchMark:   Result := 'Scorch Mark';
    dpBulletImpact: Result := 'Bullet Impact';
    dpMossGrowth:   Result := 'Moss Growth';
    dpHazardStripe: Result := 'Hazard Stripe';
    dpMagicRune:    Result := 'Magic Rune';
  end;
end;

function DecalBlendStyleToString(const AStyle: TDecalBlendStyle): String;
begin
  case AStyle of
    dbsAlphaBlend:    Result := 'Alpha Blend';
    dbsAdditiveGlow:  Result := 'Additive Glow';
    dbsMultiplyStain: Result := 'Multiply Stain';
  end;
end;

{ TCastleDecalProjector ------------------------------------------------------ }

constructor TCastleDecalProjector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBoxExtents := Vector3(2.2, 1.5, 2.2);
  FBaseColor := Vector4(0.10, 0.16, 0.22, 1.0);
  FTextureUrl := '';
  FOpacity := DefaultOpacity;
  FRoughness := DefaultRoughness;
  FMetallic := DefaultMetallic;
  FNormalAngleCutoffDeg := DefaultNormalCutoffDeg;
  FRadialEdgeFade := DefaultRadialEdgeFade;
  FSurfaceOffset := DefaultSurfaceOffset;
  FSortOrder := 0;
  FGridResolution := 8;
  FProjectToWorldGeometry := true;
  FShowProjectorBoxInViewport := true;

  FVertexBuffer := TVector3List.Create;
  FNormalBuffer := TVector3List.Create;
  FTexCoordBuffer := TVector2List.Create;
  FColorBuffer := TVector4List.Create;

  FBoxExtentsPersistent := TCastleVector3Persistent.Create(nil);
  FBoxExtentsPersistent.SetSubComponent(true);
  FBoxExtentsPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetBoxExtentsForPersistent;
  FBoxExtentsPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetBoxExtentsForPersistent;
  FBoxExtentsPersistent.InternalDefaultValue := FBoxExtents;

  FBaseColorPersistent := TCastleColorPersistent.Create(nil);
  FBaseColorPersistent.SetSubComponent(true);
  FBaseColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetBaseColorForPersistent;
  FBaseColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetBaseColorForPersistent;
  FBaseColorPersistent.InternalDefaultValue := FBaseColor;

  ApplyPreset(dpPuddleWet);
end;

destructor TCastleDecalProjector.Destroy;
begin
  if FRenderScene <> nil then
  begin
    Remove(FRenderScene);
    FreeAndNil(FRenderScene);
  end;
  FreeAndNil(FVertexBuffer);
  FreeAndNil(FNormalBuffer);
  FreeAndNil(FTexCoordBuffer);
  FreeAndNil(FColorBuffer);
  FreeAndNil(FBoxExtentsPersistent);
  FreeAndNil(FBaseColorPersistent);
  inherited Destroy;
end;

function TCastleDecalProjector.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'BlendStyle', 'BoxExtentsPersistent', 'BaseColorPersistent',
       'TextureUrl', 'Opacity', 'Roughness', 'Metallic',
       'NormalAngleCutoffDeg', 'RadialEdgeFade', 'SurfaceOffset',
       'SortOrder', 'GridResolution', 'ProjectToWorldGeometry',
       'ShowProjectorBoxInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleDecalProjector.LocalBoundingBox: TBox3D;
var
  HalfExt: TVector3;
begin
  Result := inherited LocalBoundingBox;
  if CastleDesignMode then
  begin
    HalfExt := Vector3(
      Max(0.1, FBoxExtents.X * 0.5),
      Max(0.1, FBoxExtents.Y * 0.5),
      Max(0.1, FBoxExtents.Z * 0.5));
    Result.Include(Box3D(-HalfExt, HalfExt));
  end;
end;

procedure TCastleDecalProjector.Loaded;
begin
  inherited Loaded;
  ConformAndRebuildMesh;
end;

function TCastleDecalProjector.OpacityStored: Boolean;
begin
  Result := not SameValue(FOpacity, DefaultOpacity, 0.0001);
end;

function TCastleDecalProjector.RoughnessStored: Boolean;
begin
  Result := not SameValue(FRoughness, DefaultRoughness, 0.0001);
end;

function TCastleDecalProjector.MetallicStored: Boolean;
begin
  Result := not SameValue(FMetallic, DefaultMetallic, 0.0001);
end;

function TCastleDecalProjector.NormalAngleCutoffStored: Boolean;
begin
  Result := not SameValue(FNormalAngleCutoffDeg, DefaultNormalCutoffDeg, 0.001);
end;

function TCastleDecalProjector.RadialEdgeFadeStored: Boolean;
begin
  Result := not SameValue(FRadialEdgeFade, DefaultRadialEdgeFade, 0.0001);
end;

function TCastleDecalProjector.SurfaceOffsetStored: Boolean;
begin
  Result := not SameValue(FSurfaceOffset, DefaultSurfaceOffset, 0.00001);
end;

procedure TCastleDecalProjector.SetPreset(const Value: TDecalPreset);
begin
  if FPreset = Value then
    Exit;
  if Value = dpCustom then
    FPreset := dpCustom
  else
    ApplyPreset(Value);
end;

procedure TCastleDecalProjector.ApplyPreset(const APreset: TDecalPreset);
begin
  FPreset := APreset;
  case APreset of
    dpPuddleWet:
      begin
        FBlendStyle := dbsAlphaBlend;
        FBoxExtents := Vector3(2.2, 1.5, 2.2);
        FBaseColor := Vector4(0.10, 0.18, 0.26, 1.0);
        FOpacity := 0.82;
        FRoughness := 0.05;
        FMetallic := 0.12;
        FRadialEdgeFade := 0.40;
      end;

    dpScorchMark:
      begin
        FBlendStyle := dbsAlphaBlend;
        FBoxExtents := Vector3(2.6, 1.8, 2.6);
        FBaseColor := Vector4(0.06, 0.05, 0.05, 1.0);
        FOpacity := 0.94;
        FRoughness := 0.94;
        FMetallic := 0.0;
        FRadialEdgeFade := 0.45;
      end;

    dpBulletImpact:
      begin
        FBlendStyle := dbsAlphaBlend;
        FBoxExtents := Vector3(0.45, 0.8, 0.45);
        FBaseColor := Vector4(0.14, 0.13, 0.12, 1.0);
        FOpacity := 0.95;
        FRoughness := 0.88;
        FMetallic := 0.18;
        FRadialEdgeFade := 0.30;
      end;

    dpMossGrowth:
      begin
        FBlendStyle := dbsAlphaBlend;
        FBoxExtents := Vector3(2.4, 1.6, 2.4);
        FBaseColor := Vector4(0.18, 0.42, 0.14, 1.0);
        FOpacity := 0.88;
        FRoughness := 0.90;
        FMetallic := 0.0;
        FRadialEdgeFade := 0.38;
      end;

    dpHazardStripe:
      begin
        FBlendStyle := dbsAlphaBlend;
        FBoxExtents := Vector3(3.0, 1.2, 1.0);
        FBaseColor := Vector4(0.95, 0.74, 0.08, 1.0);
        FOpacity := 0.95;
        FRoughness := 0.55;
        FMetallic := 0.05;
        FRadialEdgeFade := 0.05;
      end;

    dpMagicRune:
      begin
        FBlendStyle := dbsAdditiveGlow;
        FBoxExtents := Vector3(2.8, 1.5, 2.8);
        FBaseColor := Vector4(0.22, 0.86, 1.0, 1.0);
        FOpacity := 0.92;
        FRoughness := 0.25;
        FMetallic := 0.10;
        FRadialEdgeFade := 0.25;
      end;
  else
    ;
  end;
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetBlendStyle(const Value: TDecalBlendStyle);
begin
  if FBlendStyle = Value then
    Exit;
  FBlendStyle := Value;
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetBoxExtents(const Value: TVector3);
begin
  FBoxExtents := Vector3(
    Max(0.05, Value.X),
    Max(0.05, Value.Y),
    Max(0.05, Value.Z));
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

function TCastleDecalProjector.GetBoxExtentsForPersistent: TVector3;
begin
  Result := FBoxExtents;
end;

procedure TCastleDecalProjector.SetBoxExtentsForPersistent(const AValue: TVector3);
begin
  SetBoxExtents(AValue);
end;

procedure TCastleDecalProjector.SetBaseColor(const Value: TCastleColor);
begin
  FBaseColor := Value;
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

function TCastleDecalProjector.GetBaseColorForPersistent: TCastleColor;
begin
  Result := FBaseColor;
end;

procedure TCastleDecalProjector.SetBaseColorForPersistent(const AValue: TCastleColor);
begin
  SetBaseColor(AValue);
end;

procedure TCastleDecalProjector.SetTextureUrl(const Value: String);
begin
  if FTextureUrl = Value then
    Exit;
  FTextureUrl := Value;
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetOpacity(const Value: Single);
begin
  FOpacity := Clamped(Value, 0.0, 1.0);
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetRoughness(const Value: Single);
begin
  FRoughness := Clamped(Value, 0.0, 1.0);
  if not (csLoading in ComponentState) then
    SyncMaterialAndBlendNodes;
end;

procedure TCastleDecalProjector.SetMetallic(const Value: Single);
begin
  FMetallic := Clamped(Value, 0.0, 1.0);
  if not (csLoading in ComponentState) then
    SyncMaterialAndBlendNodes;
end;

procedure TCastleDecalProjector.SetNormalAngleCutoffDeg(const Value: Single);
begin
  FNormalAngleCutoffDeg := Clamped(Value, 5.0, 180.0);
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetRadialEdgeFade(const Value: Single);
begin
  FRadialEdgeFade := Clamped(Value, 0.0, 1.0);
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetSurfaceOffset(const Value: Single);
begin
  FSurfaceOffset := Clamped(Value, 0.0005, 0.5);
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetSortOrder(const Value: Integer);
begin
  if FSortOrder = Value then
    Exit;
  FSortOrder := Value;
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetGridResolution(const Value: Integer);
var
  ClampedV: Integer;
begin
  ClampedV := Clamped(Value, 1, 24);
  if FGridResolution = ClampedV then
    Exit;
  FGridResolution := ClampedV;
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

procedure TCastleDecalProjector.SetProjectToWorldGeometry(const Value: Boolean);
begin
  if FProjectToWorldGeometry = Value then
    Exit;
  FProjectToWorldGeometry := Value;
  if not (csLoading in ComponentState) then
    ConformAndRebuildMesh;
end;

function TCastleDecalProjector.EvaluateProceduralSample(
  const AU, AV: Single): TCastleColor;
var
  DX, DZ, Dist, InnerR, AlphaMask, Stripe, Ring, Angle: Single;
  RGB: TVector3;
begin
  DX := (AU - 0.5) * 2.0;
  DZ := (AV - 0.5) * 2.0;
  Dist := Sqrt(DX * DX + DZ * DZ);
  RGB := Vector3(FBaseColor.X, FBaseColor.Y, FBaseColor.Z);

  if FRadialEdgeFade <= 0.001 then
    AlphaMask := 1.0
  else
  begin
    InnerR := Max(0.05, 1.0 - FRadialEdgeFade);
    if Dist <= InnerR then
      AlphaMask := 1.0
    else if Dist >= 1.05 then
      AlphaMask := 0.0
    else
      AlphaMask := 1.0 - SmoothStep(InnerR, 1.05, Dist);
  end;

  case FPreset of
    dpScorchMark:
      begin
        { Charred core with warm orange-amber ember ring around Dist ~ 0.45 }
        Ring := Exp(-Sqr((Dist - 0.42) / 0.14));
        RGB := RGB + Vector3(0.75, 0.24, 0.03) * (Ring * 0.65);
      end;

    dpBulletImpact:
      begin
        if Dist < 0.28 then
          RGB := RGB * 0.25
        else
          RGB := RGB * (0.75 + 0.25 * Cos(ArcTan2(DZ, DX) * 7.0));
      end;

    dpMossGrowth:
      begin
        Stripe := 0.5 + 0.5 * Sin(AU * 15.0) * Cos(AV * 13.0);
        RGB := Lerp(Stripe, RGB * 0.68, RGB * 1.28);
        AlphaMask := AlphaMask * (0.65 + 0.35 * Stripe);
      end;

    dpHazardStripe:
      begin
        { Crisp 45-degree alternating caution yellow / dark slate stripes }
        Stripe := Frac((AU * 4.0) + (AV * 1.5));
        if Stripe < 0.0 then
          Stripe := Stripe + 1.0;
        if Stripe < 0.5 then
          RGB := Vector3(FBaseColor.X, FBaseColor.Y, FBaseColor.Z)
        else
          RGB := Vector3(0.09, 0.09, 0.10);
        AlphaMask := 1.0;
      end;

    dpMagicRune:
      begin
        Angle := ArcTan2(DZ, DX);
        Ring := Max(
          Exp(-Sqr((Dist - 0.78) / 0.09)),
          Exp(-Sqr((Dist - 0.44) / 0.08)) * (0.6 + 0.4 * Cos(Angle * 6.0)));
        RGB := Lerp(Clamped(Ring, 0.0, 1.0), RGB * 0.45, Vector3(0.85, 0.96, 1.0));
        AlphaMask := Clamped(Max(AlphaMask * 0.35, Ring), 0.0, 1.0);
      end;
  else
    ;
  end;

  Result := Vector4(
    Clamped(RGB.X, 0.0, 1.0),
    Clamped(RGB.Y, 0.0, 1.0),
    Clamped(RGB.Z, 0.0, 1.0),
    Clamped(FOpacity * FBaseColor.W * AlphaMask, 0.0, 1.0));
end;

procedure TCastleDecalProjector.EnsureRenderScene;
var
  ShapeNode: TShapeNode;
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

  FMaterialNode := TPhysicalMaterialNode.Create;
  FMaterialNode.BaseColor := Vector3(1.0, 1.0, 1.0);
  FAppearanceNode.Material := FMaterialNode;

  FBlendModeNode := TBlendModeNode.Create;
  FAppearanceNode.BlendMode := FBlendModeNode;
  ShapeNode.Appearance := FAppearanceNode;

  FTriSetNode := TTriangleSetNode.Create;
  FTriSetNode.Solid := false;

  FCoordNode := TCoordinateNode.Create;
  FTriSetNode.Coord := FCoordNode;

  FNormalNode := TNormalNode.Create;
  FTriSetNode.Normal := FNormalNode;

  FTexCoordNode := TTextureCoordinateNode.Create;
  FTriSetNode.TexCoord := FTexCoordNode;

  FColorNode := TColorRGBANode.Create;
  FTriSetNode.Color := FColorNode;

  ShapeNode.Geometry := FTriSetNode;
  FRootNode.AddChildren(ShapeNode);

  SyncMaterialAndBlendNodes;
  FRenderScene.Load(FRootNode, true);
  Add(FRenderScene);
end;

procedure TCastleDecalProjector.SyncMaterialAndBlendNodes;
begin
  if (FMaterialNode = nil) or (FBlendModeNode = nil) then
    Exit;

  FMaterialNode.Roughness := FRoughness;
  FMaterialNode.Metallic := FMetallic;
  FMaterialNode.Transparency := 0.0;

  if Trim(FTextureUrl) <> '' then
  begin
    if FImageTexNode = nil then
    begin
      FImageTexNode := TImageTextureNode.Create;
      FMaterialNode.BaseTexture := FImageTexNode;
    end;
    FImageTexNode.SetUrl([FTextureUrl]);
  end else
  if FImageTexNode <> nil then
  begin
    FMaterialNode.BaseTexture := nil;
    FImageTexNode := nil;
  end;

  case FBlendStyle of
    dbsAlphaBlend:
      begin
        FBlendModeNode.SrcFactor := bsSrcAlpha;
        FBlendModeNode.DestFactor := bdOneMinusSrcAlpha;
      end;
    dbsAdditiveGlow:
      begin
        FBlendModeNode.SrcFactor := bsSrcAlpha;
        FBlendModeNode.DestFactor := bdOne;
      end;
    dbsMultiplyStain:
      begin
        FBlendModeNode.SrcFactor := bsDstColor;
        FBlendModeNode.DestFactor := bdOneMinusSrcAlpha;
      end;
  end;
end;

function TCastleDecalProjector.ConformAndRebuildMesh: Integer;
type
  TGridSample = record
    RawHitWorld: TVector3;
    NormWorld: TVector3;
    PosLocal: TVector3;
    NormLocal: TVector3;
    UV: TVector2;
    Col: TCastleColor;
    HasRawHit: Boolean;
    HasTriangleNorm: Boolean;
    Valid: Boolean;
    RejectedByAngle: Boolean;
  end;
var
  N, RowStride, IX, IZ, BaseV, X0, X1, Z0, Z1: Integer;
  Samples: array of TGridSample;
  SavedPickable, DoWorldProject: Boolean;
  U, V, LocalX, LocalZ, HalfY, WorldSpan, CosCutoff, EffOffset: Single;
  TopLocal, BotLocal, RayStartWorld, ProjDirWorld, AntiProjWorld: TVector3;
  HitWorld, HitNormWorld, DU, DV, CrossN: TVector3;
  RayHit: TRayCollision;
  S00, S10, S11, S01: TGridSample;

  function Idx(const AX, AZ: Integer): Integer; inline;
  begin
    Result := AZ * RowStride + AX;
  end;

  procedure AppendTri(const A, B, C: TGridSample);
  begin
    FVertexBuffer.L[BaseV + 0] := A.PosLocal;
    FVertexBuffer.L[BaseV + 1] := B.PosLocal;
    FVertexBuffer.L[BaseV + 2] := C.PosLocal;
    FNormalBuffer.L[BaseV + 0] := A.NormLocal;
    FNormalBuffer.L[BaseV + 1] := B.NormLocal;
    FNormalBuffer.L[BaseV + 2] := C.NormLocal;
    FTexCoordBuffer.L[BaseV + 0] := A.UV;
    FTexCoordBuffer.L[BaseV + 1] := B.UV;
    FTexCoordBuffer.L[BaseV + 2] := C.UV;
    FColorBuffer.L[BaseV + 0] := A.Col;
    FColorBuffer.L[BaseV + 1] := B.Col;
    FColorBuffer.L[BaseV + 2] := C.Col;
    Inc(BaseV, 3);
  end;

begin
  EnsureRenderScene;
  SyncMaterialAndBlendNodes;

  N := Clamped(FGridResolution, 1, 24);
  RowStride := N + 1;
  SetLength(Samples, RowStride * RowStride);

  EffOffset := FSurfaceOffset + FSortOrder * 0.0005;
  HalfY := Max(0.025, FBoxExtents.Y * 0.5);
  CosCutoff := Cos(DegToRad(Clamped(FNormalAngleCutoffDeg, 5.0, 180.0)));
  DoWorldProject := FProjectToWorldGeometry and (World <> nil) and HasWorldTransform;

  if DoWorldProject then
  begin
    AntiProjWorld := LocalToWorldDirection(Vector3(0.0, 1.0, 0.0));
    if AntiProjWorld.LengthSqr < 1e-8 then
      AntiProjWorld := Vector3(0.0, 1.0, 0.0)
    else
      AntiProjWorld := AntiProjWorld.Normalize;
    ProjDirWorld := -AntiProjWorld;
    WorldSpan := PointsDistance(
      LocalToWorld(Vector3(0.0, HalfY, 0.0)),
      LocalToWorld(Vector3(0.0, -HalfY, 0.0)));
  end else
  begin
    AntiProjWorld := Vector3(0.0, 1.0, 0.0);
    ProjDirWorld := Vector3(0.0, -1.0, 0.0);
    WorldSpan := FBoxExtents.Y;
  end;

  SavedPickable := Pickable;
  Pickable := false;
  try
    for IZ := 0 to N do
      for IX := 0 to N do
      begin
        U := IX / N;
        V := IZ / N;
        LocalX := (U - 0.5) * FBoxExtents.X;
        LocalZ := (V - 0.5) * FBoxExtents.Z;

        Samples[Idx(IX, IZ)] := Default(TGridSample);
        Samples[Idx(IX, IZ)].UV := Vector2(U, 1.0 - V);
        Samples[Idx(IX, IZ)].Col := EvaluateProceduralSample(U, V);

        if DoWorldProject then
        begin
          TopLocal := Vector3(LocalX, HalfY, LocalZ);
          BotLocal := Vector3(LocalX, -HalfY, LocalZ);
          RayStartWorld := LocalToWorld(TopLocal);
          WorldSpan := PointsDistance(RayStartWorld, LocalToWorld(BotLocal));

          RayHit := World.WorldRay(RayStartWorld, ProjDirWorld);
          if RayHit <> nil then
          try
            if (RayHit.Transform <> nil) and (RayHit.Distance <= WorldSpan + 0.01) then
            begin
              Samples[Idx(IX, IZ)].HasRawHit := true;
              Samples[Idx(IX, IZ)].RawHitWorld :=
                RayStartWorld + ProjDirWorld * RayHit.Distance;
              if (RayHit.Count > 0) and (RayHit.First.Triangle <> nil) and
                 (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
              begin
                HitNormWorld := RayHit.First.Item.LocalToWorldDirection(
                  RayHit.First.Triangle^.SceneSpace.Normal);
                if HitNormWorld.LengthSqr >= 1e-8 then
                begin
                  Samples[Idx(IX, IZ)].NormWorld := HitNormWorld.Normalize;
                  Samples[Idx(IX, IZ)].HasTriangleNorm := true;
                end;
              end;
            end;
          finally
            FreeAndNil(RayHit);
          end;
        end else
        begin
          Samples[Idx(IX, IZ)].PosLocal := Vector3(LocalX, EffOffset, LocalZ);
          Samples[Idx(IX, IZ)].NormLocal := Vector3(0.0, 1.0, 0.0);
          Samples[Idx(IX, IZ)].Valid := true;
        end;
      end;
  finally
    Pickable := SavedPickable;
  end;

  { Pass 2: Resolve surface normals (including analytical primitives without
    triangle octrees via grid finite differences) and apply NormalAngleCutoffDeg }
  if DoWorldProject then
    for IZ := 0 to N do
      for IX := 0 to N do
        if Samples[Idx(IX, IZ)].HasRawHit then
        begin
          if Samples[Idx(IX, IZ)].HasTriangleNorm then
            HitNormWorld := Samples[Idx(IX, IZ)].NormWorld
          else
          begin
            X0 := Max(0, IX - 1);
            X1 := Min(N, IX + 1);
            Z0 := Max(0, IZ - 1);
            Z1 := Min(N, IZ + 1);
            if Samples[Idx(X1, IZ)].HasRawHit and Samples[Idx(X0, IZ)].HasRawHit and
               Samples[Idx(IX, Z1)].HasRawHit and Samples[Idx(IX, Z0)].HasRawHit then
            begin
              DU := Samples[Idx(X1, IZ)].RawHitWorld - Samples[Idx(X0, IZ)].RawHitWorld;
              DV := Samples[Idx(IX, Z1)].RawHitWorld - Samples[Idx(IX, Z0)].RawHitWorld;
              CrossN := TVector3.CrossProduct(DV, DU);
              if CrossN.LengthSqr >= 1e-10 then
              begin
                HitNormWorld := CrossN.Normalize;
                if TVector3.DotProduct(HitNormWorld, AntiProjWorld) < 0.0 then
                  HitNormWorld := -HitNormWorld;
              end else
                HitNormWorld := AntiProjWorld;
            end else
              HitNormWorld := AntiProjWorld;
          end;

          if TVector3.DotProduct(HitNormWorld, AntiProjWorld) < CosCutoff then
            Samples[Idx(IX, IZ)].RejectedByAngle := true
          else
          begin
            HitWorld := Samples[Idx(IX, IZ)].RawHitWorld + HitNormWorld * EffOffset;
            Samples[Idx(IX, IZ)].PosLocal := WorldToLocal(HitWorld);
            Samples[Idx(IX, IZ)].NormLocal :=
              WorldToLocalDirection(HitNormWorld).Normalize;
            Samples[Idx(IX, IZ)].Valid := true;
          end;
        end;

  FLastAcceptedCellCount := 0;
  FLastRejectedAngleCellCount := 0;
  for IZ := 0 to N - 1 do
    for IX := 0 to N - 1 do
    begin
      S00 := Samples[Idx(IX, IZ)];
      S10 := Samples[Idx(IX + 1, IZ)];
      S11 := Samples[Idx(IX + 1, IZ + 1)];
      S01 := Samples[Idx(IX, IZ + 1)];
      if S00.Valid and S10.Valid and S11.Valid and S01.Valid then
        Inc(FLastAcceptedCellCount)
      else
      if S00.RejectedByAngle or S10.RejectedByAngle or
         S11.RejectedByAngle or S01.RejectedByAngle then
        Inc(FLastRejectedAngleCellCount);
    end;

  FProjectedTriangleCount := FLastAcceptedCellCount * 2;
  FVertexBuffer.Count := FProjectedTriangleCount * 3;
  FNormalBuffer.Count := FProjectedTriangleCount * 3;
  FTexCoordBuffer.Count := FProjectedTriangleCount * 3;
  FColorBuffer.Count := FProjectedTriangleCount * 3;

  BaseV := 0;
  for IZ := 0 to N - 1 do
    for IX := 0 to N - 1 do
    begin
      S00 := Samples[Idx(IX, IZ)];
      S10 := Samples[Idx(IX + 1, IZ)];
      S11 := Samples[Idx(IX + 1, IZ + 1)];
      S01 := Samples[Idx(IX, IZ + 1)];
      if S00.Valid and S10.Valid and S11.Valid and S01.Valid then
      begin
        { Counter-clockwise facing +Y local anti-projection normal }
        AppendTri(S00, S01, S11);
        AppendTri(S00, S11, S10);
      end;
    end;

  FCoordNode.SetPoint(FVertexBuffer);
  FNormalNode.SetVector(FNormalBuffer);
  FTexCoordNode.SetPoint(FTexCoordBuffer);
  FColorNode.SetColor(FColorBuffer);
  Result := FProjectedTriangleCount;
end;

function TCastleDecalProjector.DecalSummaryBadge: String;
begin
  Result := Format('[Decal:%s Prio=%d %dtri]', [
    DecalPresetToString(FPreset),
    FSortOrder,
    FProjectedTriangleCount
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleDecalProjector, 'Decal Projector (Surface Weathering)');
end.
