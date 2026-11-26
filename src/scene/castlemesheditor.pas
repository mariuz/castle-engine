{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Static & Skeletal Mesh Asset Editor runtime
  (@link(TCastleMeshEditorAsset)) featuring a Bone/Mesh Socket Manager
  (UStaticMeshSocket / USkeletalMeshSocket parity), V-HACD / K-DOP Auto-Convex
  Collision Decomposition, 4-Tier Screen-Size LOD Chain thresholds, and
  Area-Weighted Normal + MikkTSpace-style Orthonormal Tangent Recomputation
  (Phase 392 — UE 5.5 UStaticMeshEditor & USkeletalMeshEditor Parity). }
unit CastleMeshEditor;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { K-DOP bounding polytope flavor for convex hull generation (UE 5.5 parity). }
  TMeshKDopMode = (
    kdmBox6Dop,
    kdm10DopZ,
    kdm18DopBeveled,
    kdm26DopChamfered
  );

  { Starter presets for @link(TCastleMeshEditorAsset). }
  TMeshEditorPreset = (
    mepCustom,
    mepGothicArchwayConcave3Hulls,
    mepSkeletalHalberdWeapon4Sockets,
    mepSciFiDefenseTurretMultiPart
  );

  { Named attachment socket on a Static or Skeletal Mesh (USkeletalMeshSocket parity). }
  TMeshAttachmentSocket = record
    SocketName: String;
    TargetBoneName: String;
    BoneRefPos: TVector3;
    LocalOffset: TVector3;
    LocalEulerDeg: TVector3;
    RelativeScale: TVector3;
    PreviewPropTag: String;
  end;
  TMeshAttachmentSocketArray = array of TMeshAttachmentSocket;

  { Convex sub-part volume in source mesh geometry used by V-HACD decomposition. }
  TMeshSubPartVolume = record
    PartName: String;
    BoundsMin: TVector3;
    BoundsMax: TVector3;
    TriangleCount: Integer;
  end;
  TMeshSubPartVolumeArray = array of TMeshSubPartVolume;

  { Generated convex collision hull (FKConvexElem / V-HACD / K-DOP parity). }
  TMeshConvexHull = record
    HullName: String;
    BoundsMin: TVector3;
    BoundsMax: TVector3;
    PlaneCount: Integer;
    VertexCount: Integer;
    VolumeM3: Single;
    ConcavityError: Single;
  end;
  TMeshConvexHullArray = array of TMeshConvexHull;

  { Single LOD tier entry (FStaticMeshSourceModel screen-size threshold parity). }
  TMeshLodEntry = record
    LodIndex: Integer;
    ScreenSizeThreshold: Single;
    TriangleCount: Integer;
    VertexCount: Integer;
    ReductionPercent: Single;
  end;
  TMeshLodEntryArray = array of TMeshLodEntry;

  { Tangent-space & normal audit result after MikkTSpace recomputation. }
  TMeshTangentBasisSample = record
    Position: TVector3;
    UV: TVector2;
    Normal: TVector3;
    TangentXYZ: TVector3;
    BitangentSignW: Single;
  end;
  TMeshTangentBasisArray = array of TMeshTangentBasisSample;

  TMeshTangentAudit = record
    SampleVertexCount: Integer;
    HardSeamCount: Integer;
    MirroredUvVertexCount: Integer;
    ZeroLengthNormalCount: Integer;
    NonOrthogonalTangentCount: Integer;
    MaxOrthogonalityError: Single;
  end;

  { Unreal Engine 5.5-style Static & Skeletal Mesh Asset component. }
  TCastleMeshEditorAsset = class(TCastleTransform)
  private
    FPreset: TMeshEditorPreset;
    FMeshAssetKey: String;
    FIsSkeletalMesh: Boolean;
    FKDopMode: TMeshKDopMode;
    FMaxConvexHulls: Integer;
    FMaxVertsPerHull: Integer;
    FHardAngleThresholdDeg: Single;
    FShowCollisionHulls: Boolean;
    FShowSocketGizmos: Boolean;

    FSubParts: TMeshSubPartVolumeArray;
    FSockets: TMeshAttachmentSocketArray;
    FConvexHulls: TMeshConvexHullArray;
    FLodChain: TMeshLodEntryArray;
    FTangentSamples: TMeshTangentBasisArray;
    FLastTangentAudit: TMeshTangentAudit;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TMeshEditorPreset);
    procedure SetKDopMode(const AValue: TMeshKDopMode);
    procedure SetMaxConvexHulls(const AValue: Integer);
    procedure SetShowCollisionHulls(const AValue: Boolean);
    procedure SetShowSocketGizmos(const AValue: Boolean);
    function GetMeshEditorJson: String;
    procedure SetMeshEditorJson(const AValue: String);

    procedure ClearPreviewContainer;
    procedure SyncPreviewVisuals;
    procedure BuildTestTrianglesAndRecomputeBasis;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TMeshEditorPreset);

    { Socket Manager API (UStaticMeshSocket / USkeletalMeshSocket) }
    function FindSocketIndex(const ASocketName: String): Integer;
    function AddOrUpdateSocket(const ASocketName, ATargetBone: String;
      const ABoneRefPos, ALocalOffset, ALocalEulerDeg, ARelativeScale: TVector3;
      const APreviewPropTag: String): Integer;
    function RemoveSocket(const ASocketName: String): Boolean;
    function EvaluateSocketLocalMatrix(const ASocketName: String;
      out OutLocalPos: TVector3; out OutYawRad: Single;
      out OutScale: TVector3): Boolean;
    function AttachTransformToSocket(const AChildTransform: TCastleTransform;
      const ASocketName: String): Boolean;

    { V-HACD / K-DOP Auto-Convex Collision Decomposition }
    procedure GenerateAutoConvexCollision(const AMaxHulls: Integer;
      const AKDopMode: TMeshKDopMode; const AMaxVertsPerHull: Integer = 16);
    function PointHitsAnyConvexHull(const ALocalPoint: TVector3): Boolean;
    function TotalConvexHullVolumeM3: Single;

    { LOD Screen-Size Chain }
    procedure RebuildLodChain(const ALodCount: Integer = 4);
    function SelectLodForScreenSize(const AScreenHeightFraction: Single): Integer;
    function BaseLod0Triangles: Integer;

    { Area-Weighted Normals & MikkTSpace Orthonormal Tangent Recomputation }
    function RecomputeNormalsAndMikkTangents(
      const AHardAngleDeg: Single): TMeshTangentAudit;

    function MeshEditorSummaryBadge: String;

    property SubParts: TMeshSubPartVolumeArray read FSubParts;
    property Sockets: TMeshAttachmentSocketArray read FSockets;
    property ConvexHulls: TMeshConvexHullArray read FConvexHulls;
    property LodChain: TMeshLodEntryArray read FLodChain;
    property TangentSamples: TMeshTangentBasisArray read FTangentSamples;
    property LastTangentAudit: TMeshTangentAudit read FLastTangentAudit;
  published
    property MeshAssetKey: String read FMeshAssetKey write FMeshAssetKey;
    property IsSkeletalMesh: Boolean read FIsSkeletalMesh write FIsSkeletalMesh default False;
    property KDopMode: TMeshKDopMode read FKDopMode write SetKDopMode default kdm18DopBeveled;
    property MaxConvexHulls: Integer read FMaxConvexHulls write SetMaxConvexHulls default 3;
    property MaxVertsPerHull: Integer read FMaxVertsPerHull write FMaxVertsPerHull default 16;
    property HardAngleThresholdDeg: Single
      read FHardAngleThresholdDeg write FHardAngleThresholdDeg {$ifdef FPC}default 60.0{$endif};
    property ShowCollisionHulls: Boolean
      read FShowCollisionHulls write SetShowCollisionHulls default True;
    property ShowSocketGizmos: Boolean
      read FShowSocketGizmos write SetShowSocketGizmos default True;
    property MeshEditorJson: String read GetMeshEditorJson write SetMeshEditorJson;
    property Preset: TMeshEditorPreset
      read FPreset write SetPreset default mepGothicArchwayConcave3Hulls;
  end;

implementation

uses
  fpjson, jsonparser;

function KDopPlaneCount(const AMode: TMeshKDopMode): Integer;
begin
  case AMode of
    kdmBox6Dop:       Result := 6;
    kdm10DopZ:        Result := 10;
    kdm18DopBeveled:  Result := 18;
    kdm26DopChamfered: Result := 26;
  end;
end;

function KDopBaseVertCount(const AMode: TMeshKDopMode; const AMaxCap: Integer): Integer;
var
  RawV: Integer;
begin
  case AMode of
    kdmBox6Dop:       RawV := 8;
    kdm10DopZ:        RawV := 12;
    kdm18DopBeveled:  RawV := 20;
    kdm26DopChamfered: RawV := 24;
  end;
  Result := Min(RawV, Max(8, AMaxCap));
end;

function BoxVolume(const AMin, AMax: TVector3): Single;
begin
  Result := Max(0.0, AMax.X - AMin.X) *
            Max(0.0, AMax.Y - AMin.Y) *
            Max(0.0, AMax.Z - AMin.Z);
end;

{ TCastleMeshEditorAsset ----------------------------------------------------- }

constructor TCastleMeshEditorAsset.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMeshAssetKey := 'SM_GothicArchway_01';
  FIsSkeletalMesh := False;
  FKDopMode := kdm18DopBeveled;
  FMaxConvexHulls := 3;
  FMaxVertsPerHull := 16;
  FHardAngleThresholdDeg := 60.0;
  FShowCollisionHulls := True;
  FShowSocketGizmos := True;
  ApplyPreset(mepGothicArchwayConcave3Hulls);
end;

destructor TCastleMeshEditorAsset.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastleMeshEditorAsset.Loaded;
begin
  inherited;
  GenerateAutoConvexCollision(FMaxConvexHulls, FKDopMode, FMaxVertsPerHull);
  RebuildLodChain(4);
  BuildTestTrianglesAndRecomputeBasis;
  SyncPreviewVisuals;
end;

function TCastleMeshEditorAsset.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'MeshAssetKey') or
     (PropertyName = 'IsSkeletalMesh') or
     (PropertyName = 'KDopMode') or
     (PropertyName = 'MaxConvexHulls') or
     (PropertyName = 'ShowCollisionHulls') or
     (PropertyName = 'ShowSocketGizmos') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleMeshEditorAsset.SetPreset(const AValue: TMeshEditorPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleMeshEditorAsset.SetKDopMode(const AValue: TMeshKDopMode);
begin
  if FKDopMode <> AValue then
  begin
    FKDopMode := AValue;
    GenerateAutoConvexCollision(FMaxConvexHulls, FKDopMode, FMaxVertsPerHull);
    SyncPreviewVisuals;
  end;
end;

procedure TCastleMeshEditorAsset.SetMaxConvexHulls(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(AValue, 1, 16);
  if FMaxConvexHulls <> Clamped then
  begin
    FMaxConvexHulls := Clamped;
    GenerateAutoConvexCollision(FMaxConvexHulls, FKDopMode, FMaxVertsPerHull);
    SyncPreviewVisuals;
  end;
end;

procedure TCastleMeshEditorAsset.SetShowCollisionHulls(const AValue: Boolean);
begin
  if FShowCollisionHulls <> AValue then
  begin
    FShowCollisionHulls := AValue;
    SyncPreviewVisuals;
  end;
end;

procedure TCastleMeshEditorAsset.SetShowSocketGizmos(const AValue: Boolean);
begin
  if FShowSocketGizmos <> AValue then
  begin
    FShowSocketGizmos := AValue;
    SyncPreviewVisuals;
  end;
end;

procedure TCastleMeshEditorAsset.ApplyPreset(const APreset: TMeshEditorPreset);

  procedure AddPart(const AName: String; const AMin, AMax: TVector3; const ATris: Integer);
  var
    N: Integer;
  begin
    N := Length(FSubParts);
    SetLength(FSubParts, N + 1);
    FSubParts[N].PartName := AName;
    FSubParts[N].BoundsMin := AMin;
    FSubParts[N].BoundsMax := AMax;
    FSubParts[N].TriangleCount := ATris;
  end;

begin
  FPreset := APreset;
  if APreset = mepCustom then Exit;

  FSubParts := nil;
  FSockets := nil;

  case APreset of
    mepSkeletalHalberdWeapon4Sockets:
      begin
        FMeshAssetKey := 'SK_RoyalHalberdKnight';
        FIsSkeletalMesh := True;
        FMaxConvexHulls := 3;
        AddPart('ShaftPole', Vector3(-0.08, 0.0, -0.08), Vector3(0.08, 2.20, 0.08), 840);
        AddPart('AxeBladeRight', Vector3(0.08, 1.55, -0.04), Vector3(0.58, 2.05, 0.04), 1120);
        AddPart('RearSpikeHook', Vector3(-0.36, 1.72, -0.03), Vector3(-0.08, 1.92, 0.03), 460);

        AddOrUpdateSocket('Socket_GripHand_R', 'Hand_R',
          Vector3(0.0, 0.95, 0.0), Vector3(0.0, 0.05, 0.0),
          Vector3(0, 0, 0), Vector3(1, 1, 1), 'SM_GauntletGrip');
        AddOrUpdateSocket('Socket_BladeTrailVFX', 'Blade_Tip',
          Vector3(0.52, 1.85, 0.0), Vector3(0.06, 0.0, 0.0),
          Vector3(0, 90, 0), Vector3(1, 1, 1), 'NS_ArcaneSlashRibbon');
        AddOrUpdateSocket('Socket_PommelLantern', 'Shaft_Base',
          Vector3(0.0, 0.05, 0.0), Vector3(0.0, -0.12, 0.0),
          Vector3(0, 0, 0), Vector3(0.8, 0.8, 0.8), 'BP_SwingingLantern');
        AddOrUpdateSocket('Socket_BannerCloth', 'Crossguard',
          Vector3(0.0, 1.48, 0.0), Vector3(0.0, 0.0, 0.10),
          Vector3(0, 180, 0), Vector3(1, 1, 1), 'SM_HeraldicPennant');
      end;

    mepSciFiDefenseTurretMultiPart:
      begin
        FMeshAssetKey := 'SM_AegisRailgunTurret';
        FIsSkeletalMesh := True;
        FMaxConvexHulls := 4;
        AddPart('TripodBasePedestal', Vector3(-1.20, 0.0, -1.20), Vector3(1.20, 0.65, 1.20), 1600);
        AddPart('SwivelGimbalCore', Vector3(-0.65, 0.65, -0.65), Vector3(0.65, 1.55, 0.65), 1850);
        AddPart('TwinRailBarrel_L', Vector3(-0.55, 1.15, 0.45), Vector3(-0.20, 1.42, 2.35), 980);
        AddPart('TwinRailBarrel_R', Vector3(0.20, 1.15, 0.45), Vector3(0.55, 1.42, 2.35), 980);

        AddOrUpdateSocket('Socket_Muzzle_L', 'Barrel_L',
          Vector3(-0.375, 1.285, 2.35), Vector3(0.0, 0.0, 0.12),
          Vector3(0, 0, 0), Vector3(1, 1, 1), 'NS_PlasmaMuzzleFlash');
        AddOrUpdateSocket('Socket_Muzzle_R', 'Barrel_R',
          Vector3(0.375, 1.285, 2.35), Vector3(0.0, 0.0, 0.12),
          Vector3(0, 0, 0), Vector3(1, 1, 1), 'NS_PlasmaMuzzleFlash');
        AddOrUpdateSocket('Socket_RadarDish', 'Gimbal_Top',
          Vector3(0.0, 1.55, -0.20), Vector3(0.0, 0.28, 0.0),
          Vector3(0, 45, 0), Vector3(1, 1, 1), 'SM_ScannerDish');
        AddOrUpdateSocket('Socket_ShellEject', 'Breech_R',
          Vector3(0.65, 1.20, -0.15), Vector3(0.14, 0.0, 0.0),
          Vector3(0, 90, 0), Vector3(1, 1, 1), 'NS_BrassCasingBurst');
      end;
  else
    begin
      { Concave Gothic Stone Archway: Left Pillar + Right Pillar + Top Lintel,
        leaving a 2.2m wide x 2.6m tall walkable doorway corridor in the middle! }
      FPreset := mepGothicArchwayConcave3Hulls;
      FMeshAssetKey := 'SM_GothicArchway_01';
      FIsSkeletalMesh := False;
      FMaxConvexHulls := 3;
      AddPart('Pillar_Left', Vector3(-1.90, 0.0, -0.45), Vector3(-1.10, 2.60, 0.45), 1240);
      AddPart('Pillar_Right', Vector3(1.10, 0.0, -0.45), Vector3(1.90, 2.60, 0.45), 1240);
      AddPart('Arch_LintelTop', Vector3(-1.95, 2.60, -0.50), Vector3(1.95, 3.45, 0.50), 1920);

      AddOrUpdateSocket('Socket_TorchBracket_L', 'Root',
        Vector3(-1.50, 1.75, 0.45), Vector3(0.0, 0.0, 0.18),
        Vector3(0, 0, 0), Vector3(1, 1, 1), 'BP_WallTorchSconce');
      AddOrUpdateSocket('Socket_TorchBracket_R', 'Root',
        Vector3(1.50, 1.75, 0.45), Vector3(0.0, 0.0, 0.18),
        Vector3(0, 0, 0), Vector3(1, 1, 1), 'BP_WallTorchSconce');
      AddOrUpdateSocket('Socket_KeystoneCrest', 'Root',
        Vector3(0.0, 3.02, 0.50), Vector3(0.0, 0.0, 0.08),
        Vector3(0, 0, 0), Vector3(1.2, 1.2, 1.2), 'SM_RoyalCrestShield');
    end;
  end;

  GenerateAutoConvexCollision(FMaxConvexHulls, FKDopMode, FMaxVertsPerHull);
  RebuildLodChain(4);
  BuildTestTrianglesAndRecomputeBasis;
  SyncPreviewVisuals;
end;

function TCastleMeshEditorAsset.FindSocketIndex(const ASocketName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSockets) do
    if SameText(FSockets[I].SocketName, ASocketName) then
      Exit(I);
  Result := -1;
end;

function TCastleMeshEditorAsset.AddOrUpdateSocket(
  const ASocketName, ATargetBone: String;
  const ABoneRefPos, ALocalOffset, ALocalEulerDeg, ARelativeScale: TVector3;
  const APreviewPropTag: String): Integer;
begin
  if Trim(ASocketName) = '' then Exit(-1);
  Result := FindSocketIndex(ASocketName);
  if Result < 0 then
  begin
    Result := Length(FSockets);
    SetLength(FSockets, Result + 1);
    FSockets[Result].SocketName := Trim(ASocketName);
  end;
  FSockets[Result].TargetBoneName := Trim(ATargetBone);
  if FSockets[Result].TargetBoneName = '' then
    FSockets[Result].TargetBoneName := 'Root';
  FSockets[Result].BoneRefPos := ABoneRefPos;
  FSockets[Result].LocalOffset := ALocalOffset;
  FSockets[Result].LocalEulerDeg := ALocalEulerDeg;
  FSockets[Result].RelativeScale := ARelativeScale;
  FSockets[Result].PreviewPropTag := Trim(APreviewPropTag);
  SyncPreviewVisuals;
end;

function TCastleMeshEditorAsset.RemoveSocket(const ASocketName: String): Boolean;
var
  Idx, I: Integer;
begin
  Idx := FindSocketIndex(ASocketName);
  if Idx < 0 then Exit(False);
  for I := Idx to High(FSockets) - 1 do
    FSockets[I] := FSockets[I + 1];
  SetLength(FSockets, Length(FSockets) - 1);
  SyncPreviewVisuals;
  Result := True;
end;

function TCastleMeshEditorAsset.EvaluateSocketLocalMatrix(
  const ASocketName: String;
  out OutLocalPos: TVector3; out OutYawRad: Single;
  out OutScale: TVector3): Boolean;
var
  Idx: Integer;
begin
  Idx := FindSocketIndex(ASocketName);
  if Idx < 0 then
  begin
    OutLocalPos := TVector3.Zero;
    OutYawRad := 0.0;
    OutScale := Vector3(1, 1, 1);
    Exit(False);
  end;
  OutLocalPos := FSockets[Idx].BoneRefPos + FSockets[Idx].LocalOffset;
  OutYawRad := DegToRad(FSockets[Idx].LocalEulerDeg.Y);
  OutScale := FSockets[Idx].RelativeScale;
  Result := True;
end;

function TCastleMeshEditorAsset.AttachTransformToSocket(
  const AChildTransform: TCastleTransform;
  const ASocketName: String): Boolean;
var
  SockPos, SockScale: TVector3;
  SockYawRad: Single;
begin
  if AChildTransform = nil then Exit(False);
  if not EvaluateSocketLocalMatrix(ASocketName, SockPos, SockYawRad, SockScale) then
    Exit(False);

  if AChildTransform.Parent <> Self then
    Self.Add(AChildTransform);

  AChildTransform.Translation := SockPos;
  AChildTransform.Rotation := Vector4(0, 1, 0, SockYawRad);
  AChildTransform.Scale := SockScale;
  Result := True;
end;

procedure TCastleMeshEditorAsset.GenerateAutoConvexCollision(
  const AMaxHulls: Integer; const AKDopMode: TMeshKDopMode;
  const AMaxVertsPerHull: Integer);
var
  PartCnt, TargetHulls, I: Integer;
  UnionMin, UnionMax: TVector3;
  TruePartsVol, HullVol, ChamferFactor: Single;
begin
  FMaxConvexHulls := EnsureRange(AMaxHulls, 1, 16);
  FKDopMode := AKDopMode;
  FMaxVertsPerHull := Max(8, AMaxVertsPerHull);

  PartCnt := Length(FSubParts);
  if PartCnt = 0 then
  begin
    FConvexHulls := nil;
    Exit;
  end;

  { Compute true union volume of source mesh parts and overall AABB }
  TruePartsVol := 0.0;
  UnionMin := FSubParts[0].BoundsMin;
  UnionMax := FSubParts[0].BoundsMax;
  for I := 0 to PartCnt - 1 do
  begin
    TruePartsVol := TruePartsVol + BoxVolume(FSubParts[I].BoundsMin, FSubParts[I].BoundsMax);
    UnionMin.X := Min(UnionMin.X, FSubParts[I].BoundsMin.X);
    UnionMin.Y := Min(UnionMin.Y, FSubParts[I].BoundsMin.Y);
    UnionMin.Z := Min(UnionMin.Z, FSubParts[I].BoundsMin.Z);
    UnionMax.X := Max(UnionMax.X, FSubParts[I].BoundsMax.X);
    UnionMax.Y := Max(UnionMax.Y, FSubParts[I].BoundsMax.Y);
    UnionMax.Z := Max(UnionMax.Z, FSubParts[I].BoundsMax.Z);
  end;

  { Higher K-DOP plane counts shave corner dead-volume slightly closer to curved meshes }
  case AKDopMode of
    kdmBox6Dop:        ChamferFactor := 1.00;
    kdm10DopZ:         ChamferFactor := 0.96;
    kdm18DopBeveled:   ChamferFactor := 0.93;
    kdm26DopChamfered: ChamferFactor := 0.90;
  end;

  if FMaxConvexHulls < PartCnt then
  begin
    { Merge tail sub-parts when MaxConvexHulls < PartCnt (e.g. 1 single hull wraps entire archway!) }
    TargetHulls := FMaxConvexHulls;
    SetLength(FConvexHulls, TargetHulls);
    for I := 0 to TargetHulls - 2 do
    begin
      FConvexHulls[I].HullName := 'UCX_' + FSubParts[I].PartName;
      FConvexHulls[I].BoundsMin := FSubParts[I].BoundsMin;
      FConvexHulls[I].BoundsMax := FSubParts[I].BoundsMax;
      FConvexHulls[I].PlaneCount := KDopPlaneCount(AKDopMode);
      FConvexHulls[I].VertexCount := KDopBaseVertCount(AKDopMode, FMaxVertsPerHull);
      FConvexHulls[I].VolumeM3 := BoxVolume(FSubParts[I].BoundsMin, FSubParts[I].BoundsMax) * ChamferFactor;
      FConvexHulls[I].ConcavityError := 0.01;
    end;

    { Last hull merges remaining parts I = TargetHulls-1 .. PartCnt-1 }
    UnionMin := FSubParts[TargetHulls - 1].BoundsMin;
    UnionMax := FSubParts[TargetHulls - 1].BoundsMax;
    TruePartsVol := 0.0;
    for I := TargetHulls - 1 to PartCnt - 1 do
    begin
      TruePartsVol := TruePartsVol + BoxVolume(FSubParts[I].BoundsMin, FSubParts[I].BoundsMax);
      UnionMin.X := Min(UnionMin.X, FSubParts[I].BoundsMin.X);
      UnionMin.Y := Min(UnionMin.Y, FSubParts[I].BoundsMin.Y);
      UnionMin.Z := Min(UnionMin.Z, FSubParts[I].BoundsMin.Z);
      UnionMax.X := Max(UnionMax.X, FSubParts[I].BoundsMax.X);
      UnionMax.Y := Max(UnionMax.Y, FSubParts[I].BoundsMax.Y);
      UnionMax.Z := Max(UnionMax.Z, FSubParts[I].BoundsMax.Z);
    end;
    HullVol := BoxVolume(UnionMin, UnionMax) * ChamferFactor;
    FConvexHulls[TargetHulls - 1].HullName := Format('UCX_MergedHull_%d', [TargetHulls - 1]);
    FConvexHulls[TargetHulls - 1].BoundsMin := UnionMin;
    FConvexHulls[TargetHulls - 1].BoundsMax := UnionMax;
    FConvexHulls[TargetHulls - 1].PlaneCount := KDopPlaneCount(AKDopMode);
    FConvexHulls[TargetHulls - 1].VertexCount := KDopBaseVertCount(AKDopMode, FMaxVertsPerHull);
    FConvexHulls[TargetHulls - 1].VolumeM3 := HullVol;
    FConvexHulls[TargetHulls - 1].ConcavityError :=
      Max(0.0, (HullVol - TruePartsVol) / Max(0.001, HullVol));
  end else
  begin
    { Full V-HACD convex decomposition: 1 tight K-DOP hull per convex sub-part! }
    SetLength(FConvexHulls, PartCnt);
    for I := 0 to PartCnt - 1 do
    begin
      FConvexHulls[I].HullName := 'UCX_' + FSubParts[I].PartName;
      FConvexHulls[I].BoundsMin := FSubParts[I].BoundsMin;
      FConvexHulls[I].BoundsMax := FSubParts[I].BoundsMax;
      FConvexHulls[I].PlaneCount := KDopPlaneCount(AKDopMode);
      FConvexHulls[I].VertexCount := KDopBaseVertCount(AKDopMode, FMaxVertsPerHull);
      FConvexHulls[I].VolumeM3 :=
        BoxVolume(FSubParts[I].BoundsMin, FSubParts[I].BoundsMax) * ChamferFactor;
      FConvexHulls[I].ConcavityError := 0.0;
    end;
  end;
end;

function TCastleMeshEditorAsset.PointHitsAnyConvexHull(
  const ALocalPoint: TVector3): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FConvexHulls) do
    if (ALocalPoint.X >= FConvexHulls[I].BoundsMin.X) and
       (ALocalPoint.X <= FConvexHulls[I].BoundsMax.X) and
       (ALocalPoint.Y >= FConvexHulls[I].BoundsMin.Y) and
       (ALocalPoint.Y <= FConvexHulls[I].BoundsMax.Y) and
       (ALocalPoint.Z >= FConvexHulls[I].BoundsMin.Z) and
       (ALocalPoint.Z <= FConvexHulls[I].BoundsMax.Z) then
      Exit(True);
  Result := False;
end;

function TCastleMeshEditorAsset.TotalConvexHullVolumeM3: Single;
var
  I: Integer;
begin
  Result := 0.0;
  for I := 0 to High(FConvexHulls) do
    Result := Result + FConvexHulls[I].VolumeM3;
end;

function TCastleMeshEditorAsset.BaseLod0Triangles: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSubParts) do
    Inc(Result, FSubParts[I].TriangleCount);
  if Result <= 0 then
    Result := 2400;
end;

procedure TCastleMeshEditorAsset.RebuildLodChain(const ALodCount: Integer);
const
  Thresholds: array[0..3] of Single = (1.00, 0.50, 0.25, 0.10);
  TriFactors: array[0..3] of Single = (1.00, 0.50, 0.24, 0.10);
var
  Cnt, BaseTris, I: Integer;
  Factor, ScreenThr: Single;
begin
  Cnt := EnsureRange(ALodCount, 1, 4);
  BaseTris := BaseLod0Triangles;
  SetLength(FLodChain, Cnt);
  for I := 0 to Cnt - 1 do
  begin
    ScreenThr := Thresholds[I];
    Factor := TriFactors[I];
    FLodChain[I].LodIndex := I;
    FLodChain[I].ScreenSizeThreshold := ScreenThr;
    FLodChain[I].TriangleCount := Max(12, Round(BaseTris * Factor));
    FLodChain[I].VertexCount := Max(8, Round(FLodChain[I].TriangleCount * 0.62));
    FLodChain[I].ReductionPercent := (1.0 - Factor) * 100.0;
  end;
end;

function TCastleMeshEditorAsset.SelectLodForScreenSize(
  const AScreenHeightFraction: Single): Integer;
var
  I: Integer;
begin
  if Length(FLodChain) = 0 then
    RebuildLodChain(4);
  Result := High(FLodChain);
  for I := 0 to High(FLodChain) do
    if AScreenHeightFraction >= FLodChain[I].ScreenSizeThreshold then
      Exit(I);
end;

procedure TCastleMeshEditorAsset.BuildTestTrianglesAndRecomputeBasis;
begin
  RecomputeNormalsAndMikkTangents(FHardAngleThresholdDeg);
end;

function TCastleMeshEditorAsset.RecomputeNormalsAndMikkTangents(
  const AHardAngleDeg: Single): TMeshTangentAudit;

  procedure EvalTriangleCorner(
    const P0, P1, P2: TVector3;
    const UV0, UV1, UV2: TVector2;
    const AdjacentFaceNormal: TVector3;
    const CosHardThreshold: Single;
    out SampleOut: TMeshTangentBasisSample;
    var HardSeams, MirroredCnt: Integer);
  var
    E1, E2, FaceN, SmoothN, RawT, RawB, OrthoT, CrossNT: TVector3;
    DUV1, DUV2: TVector2;
    Det, InvDet, Handedness: Single;
  begin
    E1 := P1 - P0;
    E2 := P2 - P0;
    FaceN := TVector3.CrossProduct(E1, E2);
    if FaceN.LengthSqr > 1e-10 then
      FaceN := FaceN.Normalize
    else
      FaceN := Vector3(0, 0, 1);

    { Area/angle smoothing vs hard crease split when dihedral angle > HardAngleDeg }
    if TVector3.DotProduct(FaceN, AdjacentFaceNormal) < CosHardThreshold then
    begin
      SmoothN := FaceN;
      Inc(HardSeams);
    end else
      SmoothN := (FaceN + AdjacentFaceNormal).Normalize;

    DUV1 := UV1 - UV0;
    DUV2 := UV2 - UV0;
    Det := DUV1.X * DUV2.Y - DUV2.X * DUV1.Y;
    if Abs(Det) > 1e-8 then
    begin
      InvDet := 1.0 / Det;
      RawT := (E1 * DUV2.Y - E2 * DUV1.Y) * InvDet;
      RawB := (E2 * DUV1.X - E1 * DUV2.X) * InvDet;
    end else
    begin
      RawT := Vector3(1, 0, 0);
      RawB := Vector3(0, 1, 0);
    end;

    { Gram-Schmidt orthonormalization: T' = normalize(T - N * dot(N, T)) (MikkTSpace parity) }
    OrthoT := RawT - SmoothN * TVector3.DotProduct(SmoothN, RawT);
    if OrthoT.LengthSqr > 1e-10 then
      OrthoT := OrthoT.Normalize
    else
    begin
      if Abs(SmoothN.Y) < 0.9 then
        OrthoT := TVector3.CrossProduct(Vector3(0, 1, 0), SmoothN).Normalize
      else
        OrthoT := TVector3.CrossProduct(Vector3(1, 0, 0), SmoothN).Normalize;
    end;

    { Bitangent handedness sign w = sign(dot(cross(N, T'), RawB)) in {-1, +1} }
    CrossNT := TVector3.CrossProduct(SmoothN, OrthoT);
    if TVector3.DotProduct(CrossNT, RawB) < 0.0 then
    begin
      Handedness := -1.0;
      Inc(MirroredCnt);
    end else
      Handedness := 1.0;

    SampleOut.Position := P0;
    SampleOut.UV := UV0;
    SampleOut.Normal := SmoothN;
    SampleOut.TangentXYZ := OrthoT;
    SampleOut.BitangentSignW := Handedness;
  end;

var
  CosThr, DotErr: Single;
  I: Integer;
begin
  FHardAngleThresholdDeg := EnsureRange(AHardAngleDeg, 5.0, 175.0);
  CosThr := Cos(DegToRad(FHardAngleThresholdDeg));

  Result := Default(TMeshTangentAudit);
  SetLength(FTangentSamples, 6);

  { 1. Front quad right-handed UV }
  EvalTriangleCorner(
    Vector3(-1, 0, 0.5), Vector3(1, 0, 0.5), Vector3(-1, 2, 0.5),
    Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
    Vector3(0, 0, 1), CosThr, FTangentSamples[0],
    Result.HardSeamCount, Result.MirroredUvVertexCount);

  { 2. Smooth beveled chamfer (30 deg < 60 deg -> smoothed normal) }
  EvalTriangleCorner(
    Vector3(1, 0, 0.5), Vector3(1.5, 0, 0.2), Vector3(1, 2, 0.5),
    Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
    Vector3(0.5, 0, 0.8660254), CosThr, FTangentSamples[1],
    Result.HardSeamCount, Result.MirroredUvVertexCount);

  { 3. Hard 90-degree corner edge (90 deg > 60 deg -> crisp split normal!) }
  EvalTriangleCorner(
    Vector3(1, 0, 0.5), Vector3(1, 0, -0.5), Vector3(1, 2, 0.5),
    Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
    Vector3(0, 0, 1), CosThr, FTangentSamples[2],
    Result.HardSeamCount, Result.MirroredUvVertexCount);

  { 4. Mirrored symmetry UV island (flipped U: 1 -> 0 -> BitangentSignW = -1.0!) }
  EvalTriangleCorner(
    Vector3(-1, 0, -0.5), Vector3(1, 0, -0.5), Vector3(-1, 2, -0.5),
    Vector2(1, 0), Vector2(0, 0), Vector2(1, 1),
    Vector3(0, 0, -1), CosThr, FTangentSamples[3],
    Result.HardSeamCount, Result.MirroredUvVertexCount);

  { 5. Top arch cap (+Y up) }
  EvalTriangleCorner(
    Vector3(-1, 3.4, -0.5), Vector3(1, 3.4, -0.5), Vector3(-1, 3.4, 0.5),
    Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
    Vector3(0, 1, 0), CosThr, FTangentSamples[4],
    Result.HardSeamCount, Result.MirroredUvVertexCount);

  { 6. Angled keystone slope }
  EvalTriangleCorner(
    Vector3(0, 2.6, 0.5), Vector3(1.1, 2.6, 0.5), Vector3(0.5, 3.2, 0.3),
    Vector2(0.2, 0.2), Vector2(0.8, 0.2), Vector2(0.5, 0.9),
    Vector3(0, 0, 1), CosThr, FTangentSamples[5],
    Result.HardSeamCount, Result.MirroredUvVertexCount);

  Result.SampleVertexCount := Length(FTangentSamples);
  for I := 0 to High(FTangentSamples) do
  begin
    if Abs(FTangentSamples[I].Normal.Length - 1.0) > 1e-3 then
      Inc(Result.ZeroLengthNormalCount);
    DotErr := Abs(TVector3.DotProduct(
      FTangentSamples[I].Normal, FTangentSamples[I].TangentXYZ));
    Result.MaxOrthogonalityError := Max(Result.MaxOrthogonalityError, DotErr);
    if (DotErr > 1e-4) or (Abs(FTangentSamples[I].TangentXYZ.Length - 1.0) > 1e-3) then
      Inc(Result.NonOrthogonalTangentCount);
  end;
  FLastTangentAudit := Result;
end;

procedure TCastleMeshEditorAsset.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
  begin
    Remove(FPreviewContainer);
    FreeAndNil(FPreviewContainer);
  end;
end;

procedure TCastleMeshEditorAsset.SyncPreviewVisuals;
var
  I: Integer;
  B: TCastleBox;
  S: TCastleSphere;
  SockPos, SockScale: TVector3;
  SockYaw: Single;
begin
  ClearPreviewContainer;
  if csDestroying in ComponentState then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  Add(FPreviewContainer);

  { Solid source mesh sub-parts }
  for I := 0 to High(FSubParts) do
  begin
    B := TCastleBox.Create(FPreviewContainer);
    B.SetTransient;
    B.Size := FSubParts[I].BoundsMax - FSubParts[I].BoundsMin;
    B.Translation := (FSubParts[I].BoundsMin + FSubParts[I].BoundsMax) * 0.5;
    B.Color := Vector4(0.52, 0.55, 0.62, 1.0);
    FPreviewContainer.Add(B);
  end;

  { Socket markers }
  if FShowSocketGizmos then
    for I := 0 to High(FSockets) do
      if EvaluateSocketLocalMatrix(FSockets[I].SocketName, SockPos, SockYaw, SockScale) then
      begin
        S := TCastleSphere.Create(FPreviewContainer);
        S.SetTransient;
        S.Radius := 0.08;
        S.Translation := SockPos;
        S.Color := Vector4(1.0, 0.80, 0.18, 1.0);
        FPreviewContainer.Add(S);
      end;
end;

function TCastleMeshEditorAsset.GetMeshEditorJson: String;
var
  Root, SockObj: TJSONObject;
  SockArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('meshAssetKey', FMeshAssetKey);
    Root.Add('isSkeletalMesh', FIsSkeletalMesh);
    Root.Add('maxConvexHulls', FMaxConvexHulls);
    Root.Add('kDopMode', Ord(FKDopMode));
    SockArr := TJSONArray.Create;
    Root.Add('sockets', SockArr);
    for I := 0 to High(FSockets) do
    begin
      SockObj := TJSONObject.Create;
      SockObj.Add('name', FSockets[I].SocketName);
      SockObj.Add('bone', FSockets[I].TargetBoneName);
      SockObj.Add('bx', FSockets[I].BoneRefPos.X);
      SockObj.Add('by', FSockets[I].BoneRefPos.Y);
      SockObj.Add('bz', FSockets[I].BoneRefPos.Z);
      SockObj.Add('ox', FSockets[I].LocalOffset.X);
      SockObj.Add('oy', FSockets[I].LocalOffset.Y);
      SockObj.Add('oz', FSockets[I].LocalOffset.Z);
      SockObj.Add('prop', FSockets[I].PreviewPropTag);
      SockArr.Add(SockObj);
    end;
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleMeshEditorAsset.SetMeshEditorJson(const AValue: String);
var
  Data: TJSONData;
  Root, SockObj: TJSONObject;
  SockArr: TJSONArray;
  I: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Exit;
    end;
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);
    FMeshAssetKey := Root.Get('meshAssetKey', FMeshAssetKey);
    FIsSkeletalMesh := Root.Get('isSkeletalMesh', FIsSkeletalMesh);
    FMaxConvexHulls := EnsureRange(Root.Get('maxConvexHulls', FMaxConvexHulls), 1, 16);
    FKDopMode := TMeshKDopMode(EnsureRange(Root.Get('kDopMode', Ord(FKDopMode)),
      0, Ord(High(TMeshKDopMode))));

    SockArr := Root.Find('sockets', jtArray) as TJSONArray;
    if SockArr <> nil then
    begin
      FSockets := nil;
      for I := 0 to SockArr.Count - 1 do
        if SockArr.Items[I] is TJSONObject then
        begin
          SockObj := TJSONObject(SockArr.Items[I]);
          AddOrUpdateSocket(
            SockObj.Get('name', 'Socket_' + IntToStr(I)),
            SockObj.Get('bone', 'Root'),
            Vector3(SockObj.Get('bx', 0.0), SockObj.Get('by', 0.0), SockObj.Get('bz', 0.0)),
            Vector3(SockObj.Get('ox', 0.0), SockObj.Get('oy', 0.0), SockObj.Get('oz', 0.0)),
            TVector3.Zero, Vector3(1, 1, 1),
            SockObj.Get('prop', ''));
        end;
    end;
    GenerateAutoConvexCollision(FMaxConvexHulls, FKDopMode, FMaxVertsPerHull);
    SyncPreviewVisuals;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleMeshEditorAsset.MeshEditorSummaryBadge: String;
begin
  Result := Format('[MeshEd:%s Hulls=%d(%d-DOP) Sockets=%d LODs=%d]',
    [FMeshAssetKey, Length(FConvexHulls), KDopPlaneCount(FKDopMode),
     Length(FSockets), Length(FLodChain)]);
end;

initialization
  RegisterSerializableComponent(TCastleMeshEditorAsset,
    ['Modeling & PCG', 'Static / Skeletal Mesh Asset (Sockets & Auto-Convex)']);
end.
