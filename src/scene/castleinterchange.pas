{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Unreal Engine 5.5-style Interchange Asset Import Pipeline & Non-Destructive
  Reimport Manager (UInterchangeManager / UInterchangePipelineStack) featuring
  DCC Z-Up/Y-Up & cm/mm/m coordinate conversion, UCX_/UBX_/USP_/UCP_ collision
  hull & SOCKET_ attachment extraction, LOD Group chain rules, PBR texture
  color-space classification (sRGB Albedo vs Linear ORM & DirectX Normal -Y
  green flip), auto-Material Instance generation, override-preserving 1-click
  Reimport, and lossless JSON serialization (Phase 398). }
unit CastleInterchange;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils, fpjson, jsonparser,
  CastleUtils, CastleClassUtils, CastleVectors,
  CastleComponentSerialize, CastleTransform;

type
  TInterchangePipelinePreset = (
    ippModularArchitectureProps,
    ippSkeletalHeroRigAndAnimations,
    ippFoliageWindAndBillboardLod
  );

  TInterchangeSourceAxisSystem = (
    iasBlenderZUpRightHanded,
    iasMayaYUpRightHanded,
    ias3dsMaxZUpLeftHanded
  );

  TInterchangeSourceUnit = (
    isuCentimeters,
    isuMeters,
    isuMillimeters
  );

  TInterchangeLodGroupKind = (
    ilgLevelArchitecture,
    ilgSmallProp,
    ilgFoliage,
    ilgCharacterSkeletal
  );

  TInterchangeNodeRole = (
    inrVisualRenderMesh,
    inrConvexCollisionUcx,
    inrBoxCollisionUbx,
    inrSphereCollisionUsp,
    inrCapsuleCollisionUcp,
    inrAttachmentSocket,
    inrTextureMap
  );

  TInterchangeDccSourceNode = record
    NodeName: String;
    DccLocation: TVector3;
    DccBoundsExtent: TVector3;
    TriangleCount: Integer;
    MaterialSlotName: String;
    IsTexture: Boolean;
    TexResolution: Integer;
  end;
  TInterchangeDccSourceNodeArray = array of TInterchangeDccSourceNode;

  TInterchangeSlotOverride = record
    SlotName: String;
    DefaultMiUrl: String;
    ActiveMiUrl: String;
    IsUserLocked: Boolean;
  end;
  TInterchangeSlotOverrideArray = array of TInterchangeSlotOverride;

  TInterchangeTranslatedAsset = record
    AssetName: String;
    AssetClass: String; { StaticMesh, SkeletalMesh, MaterialInstance, Texture2D }
    VisualTriangleCount: Integer;
    ColliderCount: Integer;
    SocketCount: Integer;
    LodTierCount: Integer;
    CgeBoundsMeters: TVector3;
    IsSrgbGamma: Boolean;
    FlipNormalGreenChannel: Boolean;
    Notes: String;
  end;
  TInterchangeTranslatedAssetArray = array of TInterchangeTranslatedAsset;

  TCastleInterchangePipeline = class(TCastleTransform)
  private
    FPreset: TInterchangePipelinePreset;
    FSourceFileUrl: String;
    FSourceAxisSystem: TInterchangeSourceAxisSystem;
    FSourceUnit: TInterchangeSourceUnit;
    FLodGroup: TInterchangeLodGroupKind;
    FExtractCollisionPrefixes: Boolean;
    FExtractSocketPrefixes: Boolean;
    FAutoCreateMaterialInstances: Boolean;
    FPreserveUserOverridesOnReimport: Boolean;
    FReimportRevision: Integer;

    FDccNodes: TInterchangeDccSourceNodeArray;
    FSlotOverrides: TInterchangeSlotOverrideArray;
    FTranslatedAssets: TInterchangeTranslatedAssetArray;
    FExtractedSocketNames: array of String;
    FExtractedColliderNames: array of String;
    FPipelineDataJson: String;

    procedure SetPreset(const AValue: TInterchangePipelinePreset);
    procedure SetSourceAxisSystem(const AValue: TInterchangeSourceAxisSystem);
    procedure SetSourceUnit(const AValue: TInterchangeSourceUnit);
    procedure SetLodGroup(const AValue: TInterchangeLodGroupKind);
    procedure SetExtractCollisionPrefixes(const AValue: Boolean);
    procedure SetExtractSocketPrefixes(const AValue: Boolean);
    procedure SetAutoCreateMaterialInstances(const AValue: Boolean);
    function GetPipelineDataJson: String;
    procedure SetPipelineDataJson(const AValue: String);

    procedure BuildPresetDccContainer;
    procedure EnsureMaterialSlot(const ASlotName: String);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function ClassifyNodeNamingConvention(const ANodeName: String;
      const AIsTexture: Boolean = False): TInterchangeNodeRole; static;
    class function LodCountForGroup(const AGroup: TInterchangeLodGroupKind): Integer; static;

    function UnitToMetersFactor: Single;
    function ConvertDccPositionToCgeMeters(const V: TVector3): TVector3;
    function ConvertDccExtentToCgeMeters(const V: TVector3): TVector3;

    { Execute the 3-stage UE Interchange Pipeline Stack (Mesh + Material + Texture) }
    procedure ExecuteImportPipeline;

    { Lock an artist Material Instance override on a slot so 1-click Reimport preserves it }
    procedure SetUserMaterialSlotOverride(const ASlotName, ACustomMiUrl: String);
    function GetEffectiveMaterialSlotUrl(const ASlotName: String): String;
    procedure ClearAllUserSlotOverrides;

    { Simulate a DCC v2+ file update & run UE 1-click Reimport }
    procedure SimulateReimportUpdatedDccSource(const AAddedTriangles: Integer = 420;
      const ANewSocketName: String = 'SOCKET_BannerPole');

    function TranslatedAssetCount: Integer;
    function TotalVisualTriangles: Integer;
    function ExtractedColliderCount: Integer;
    function ExtractedSocketCount: Integer;
    function LockedSlotOverrideCount: Integer;
    function PrimaryMeshBoundsMeters: TVector3;
    function InterchangeSummaryBadge: String;

    property DccNodes: TInterchangeDccSourceNodeArray read FDccNodes;
    property SlotOverrides: TInterchangeSlotOverrideArray read FSlotOverrides;
    property TranslatedAssets: TInterchangeTranslatedAssetArray read FTranslatedAssets;
  published
    property Preset: TInterchangePipelinePreset
      read FPreset write SetPreset default ippModularArchitectureProps;
    property SourceFileUrl: String read FSourceFileUrl write FSourceFileUrl;
    property SourceAxisSystem: TInterchangeSourceAxisSystem
      read FSourceAxisSystem write SetSourceAxisSystem default iasBlenderZUpRightHanded;
    property SourceUnit: TInterchangeSourceUnit
      read FSourceUnit write SetSourceUnit default isuCentimeters;
    property LodGroup: TInterchangeLodGroupKind
      read FLodGroup write SetLodGroup default ilgLevelArchitecture;
    property ExtractCollisionPrefixes: Boolean
      read FExtractCollisionPrefixes write SetExtractCollisionPrefixes default True;
    property ExtractSocketPrefixes: Boolean
      read FExtractSocketPrefixes write SetExtractSocketPrefixes default True;
    property AutoCreateMaterialInstances: Boolean
      read FAutoCreateMaterialInstances write SetAutoCreateMaterialInstances default True;
    property PreserveUserOverridesOnReimport: Boolean
      read FPreserveUserOverridesOnReimport write FPreserveUserOverridesOnReimport default True;
    property ReimportRevision: Integer read FReimportRevision write FReimportRevision default 1;
    property PipelineDataJson: String read GetPipelineDataJson write SetPipelineDataJson stored True;
  end;

function InterchangePresetDisplayName(const APreset: TInterchangePipelinePreset): String;
function InterchangeAxisDisplayName(const AAxis: TInterchangeSourceAxisSystem): String;
function InterchangeUnitDisplayName(const AUnit: TInterchangeSourceUnit): String;

implementation

function InterchangePresetDisplayName(const APreset: TInterchangePipelinePreset): String;
begin
  case APreset of
    ippModularArchitectureProps:     Result := 'Modular Architecture FBX (Z-Up cm, UCX_ + SOCKET_ + ORM)';
    ippSkeletalHeroRigAndAnimations: Result := 'Skeletal Hero Character glTF (Y-Up m, Character LODs)';
    ippFoliageWindAndBillboardLod:   Result := 'Botanical Canopy Tree FBX (Foliage 4-LOD + Subsurface)';
  end;
end;

function InterchangeAxisDisplayName(const AAxis: TInterchangeSourceAxisSystem): String;
begin
  case AAxis of
    iasBlenderZUpRightHanded: Result := 'Blender / UE Z-Up (RH -> CGE Y-Up)';
    iasMayaYUpRightHanded:    Result := 'Maya / glTF Y-Up (Native CGE Y-Up)';
    ias3dsMaxZUpLeftHanded:   Result := '3ds Max Z-Up (LH -> CGE Y-Up)';
  end;
end;

function InterchangeUnitDisplayName(const AUnit: TInterchangeSourceUnit): String;
begin
  case AUnit of
    isuCentimeters: Result := 'Centimeters (0.01x -> m)';
    isuMeters:      Result := 'Meters (1.00x -> m)';
    isuMillimeters: Result := 'Millimeters (0.001x -> m)';
  end;
end;

{ TCastleInterchangePipeline }

constructor TCastleInterchangePipeline.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := ippModularArchitectureProps;
  FSourceFileUrl := 'raw-dcc:/fortress/SM_FortressGate_v01.fbx';
  FSourceAxisSystem := iasBlenderZUpRightHanded;
  FSourceUnit := isuCentimeters;
  FLodGroup := ilgLevelArchitecture;
  FExtractCollisionPrefixes := True;
  FExtractSocketPrefixes := True;
  FAutoCreateMaterialInstances := True;
  FPreserveUserOverridesOnReimport := True;
  FReimportRevision := 1;

  BuildPresetDccContainer;
  ExecuteImportPipeline;
end;

function TCastleInterchangePipeline.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'SourceFileUrl') or
     (PropertyName = 'SourceAxisSystem') or
     (PropertyName = 'SourceUnit') or
     (PropertyName = 'LodGroup') or
     (PropertyName = 'ExtractCollisionPrefixes') or
     (PropertyName = 'ExtractSocketPrefixes') or
     (PropertyName = 'AutoCreateMaterialInstances') or
     (PropertyName = 'PreserveUserOverridesOnReimport') or
     (PropertyName = 'ReimportRevision') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleInterchangePipeline.ClassifyNodeNamingConvention(
  const ANodeName: String; const AIsTexture: Boolean): TInterchangeNodeRole;
var
  Upper: String;
begin
  if AIsTexture then
    Exit(inrTextureMap);
  Upper := UpperCase(Trim(ANodeName));
  if StartsStr('UCX_', Upper) then
    Result := inrConvexCollisionUcx
  else if StartsStr('UBX_', Upper) then
    Result := inrBoxCollisionUbx
  else if StartsStr('USP_', Upper) then
    Result := inrSphereCollisionUsp
  else if StartsStr('UCP_', Upper) then
    Result := inrCapsuleCollisionUcp
  else if StartsStr('SOCKET_', Upper) then
    Result := inrAttachmentSocket
  else
    Result := inrVisualRenderMesh;
end;

class function TCastleInterchangePipeline.LodCountForGroup(
  const AGroup: TInterchangeLodGroupKind): Integer;
begin
  case AGroup of
    ilgLevelArchitecture: Result := 4;
    ilgSmallProp:         Result := 3;
    ilgFoliage:           Result := 4;
    ilgCharacterSkeletal: Result := 4;
  end;
end;

function TCastleInterchangePipeline.UnitToMetersFactor: Single;
begin
  case FSourceUnit of
    isuCentimeters: Result := 0.01;
    isuMeters:      Result := 1.0;
    isuMillimeters: Result := 0.001;
  end;
end;

function TCastleInterchangePipeline.ConvertDccPositionToCgeMeters(
  const V: TVector3): TVector3;
var
  S: Single;
begin
  S := UnitToMetersFactor;
  case FSourceAxisSystem of
    iasBlenderZUpRightHanded:
      { DCC (X_right, Y_forward, Z_up) -> CGE (X_right, Z_up, -Y_forward) }
      Result := Vector3(V.X * S, V.Z * S, -V.Y * S);
    ias3dsMaxZUpLeftHanded:
      Result := Vector3(V.X * S, V.Z * S, V.Y * S);
    iasMayaYUpRightHanded:
      Result := V * S;
  end;
end;

function TCastleInterchangePipeline.ConvertDccExtentToCgeMeters(
  const V: TVector3): TVector3;
var
  S: Single;
begin
  S := UnitToMetersFactor;
  case FSourceAxisSystem of
    iasBlenderZUpRightHanded, ias3dsMaxZUpLeftHanded:
      Result := Vector3(Abs(V.X) * S, Abs(V.Z) * S, Abs(V.Y) * S);
    iasMayaYUpRightHanded:
      Result := Vector3(Abs(V.X) * S, Abs(V.Y) * S, Abs(V.Z) * S);
  end;
end;

procedure TCastleInterchangePipeline.SetPreset(const AValue: TInterchangePipelinePreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  FReimportRevision := 1;
  SetLength(FSlotOverrides, 0);
  case FPreset of
    ippModularArchitectureProps:
      begin
        FSourceFileUrl := 'raw-dcc:/fortress/SM_FortressGate_v01.fbx';
        FSourceAxisSystem := iasBlenderZUpRightHanded;
        FSourceUnit := isuCentimeters;
        FLodGroup := ilgLevelArchitecture;
      end;
    ippSkeletalHeroRigAndAnimations:
      begin
        FSourceFileUrl := 'raw-dcc:/characters/SK_PaladinHero_v01.gltf';
        FSourceAxisSystem := iasMayaYUpRightHanded;
        FSourceUnit := isuMeters;
        FLodGroup := ilgCharacterSkeletal;
      end;
    ippFoliageWindAndBillboardLod:
      begin
        FSourceFileUrl := 'raw-dcc:/foliage/SM_AncientOakCanopy_v01.fbx';
        FSourceAxisSystem := iasBlenderZUpRightHanded;
        FSourceUnit := isuCentimeters;
        FLodGroup := ilgFoliage;
      end;
  end;
  BuildPresetDccContainer;
  ExecuteImportPipeline;
end;

procedure TCastleInterchangePipeline.SetSourceAxisSystem(
  const AValue: TInterchangeSourceAxisSystem);
begin
  if FSourceAxisSystem = AValue then Exit;
  FSourceAxisSystem := AValue;
  ExecuteImportPipeline;
end;

procedure TCastleInterchangePipeline.SetSourceUnit(const AValue: TInterchangeSourceUnit);
begin
  if FSourceUnit = AValue then Exit;
  FSourceUnit := AValue;
  ExecuteImportPipeline;
end;

procedure TCastleInterchangePipeline.SetLodGroup(const AValue: TInterchangeLodGroupKind);
begin
  if FLodGroup = AValue then Exit;
  FLodGroup := AValue;
  ExecuteImportPipeline;
end;

procedure TCastleInterchangePipeline.SetExtractCollisionPrefixes(const AValue: Boolean);
begin
  if FExtractCollisionPrefixes = AValue then Exit;
  FExtractCollisionPrefixes := AValue;
  ExecuteImportPipeline;
end;

procedure TCastleInterchangePipeline.SetExtractSocketPrefixes(const AValue: Boolean);
begin
  if FExtractSocketPrefixes = AValue then Exit;
  FExtractSocketPrefixes := AValue;
  ExecuteImportPipeline;
end;

procedure TCastleInterchangePipeline.SetAutoCreateMaterialInstances(const AValue: Boolean);
begin
  if FAutoCreateMaterialInstances = AValue then Exit;
  FAutoCreateMaterialInstances := AValue;
  ExecuteImportPipeline;
end;

procedure TCastleInterchangePipeline.EnsureMaterialSlot(const ASlotName: String);
var
  I, N: Integer;
  DefUrl: String;
begin
  if Trim(ASlotName) = '' then Exit;
  for I := 0 to High(FSlotOverrides) do
    if SameText(FSlotOverrides[I].SlotName, ASlotName) then
      Exit;

  DefUrl := 'castle-data:/materials/MI_' + ASlotName + '.castle-material';
  N := Length(FSlotOverrides);
  SetLength(FSlotOverrides, N + 1);
  FSlotOverrides[N].SlotName := ASlotName;
  FSlotOverrides[N].DefaultMiUrl := DefUrl;
  FSlotOverrides[N].ActiveMiUrl := DefUrl;
  FSlotOverrides[N].IsUserLocked := False;
end;

procedure TCastleInterchangePipeline.BuildPresetDccContainer;

  procedure AddNode(const AName: String; const ALoc, AExt: TVector3;
    const ATris: Integer; const ASlot: String;
    const AIsTex: Boolean = False; const ATexRes: Integer = 0);
  var
    N: Integer;
  begin
    N := Length(FDccNodes);
    SetLength(FDccNodes, N + 1);
    FDccNodes[N].NodeName := AName;
    FDccNodes[N].DccLocation := ALoc;
    FDccNodes[N].DccBoundsExtent := AExt;
    FDccNodes[N].TriangleCount := ATris;
    FDccNodes[N].MaterialSlotName := ASlot;
    FDccNodes[N].IsTexture := AIsTex;
    FDccNodes[N].TexResolution := ATexRes;
  end;

begin
  SetLength(FDccNodes, 0);
  case FPreset of
    ippModularArchitectureProps:
      begin
        { Main visual meshes (450cm wide, 40cm deep along Y, 520cm tall along Z-Up!) }
        AddNode('SM_FortressGate_Arch', Vector3(0, 0, 260), Vector3(450, 40, 520),
          1920, 'Slot_AshlarStone');
        AddNode('SM_FortressGate_Grate', Vector3(0, 0, 210), Vector3(260, 14, 380),
          920, 'Slot_PortcullisIron');
        { UE Collision Hulls (220 tris total — stripped from visual render tris!) }
        AddNode('UCX_FortressGate_PillarL', Vector3(-175, 0, 260), Vector3(95, 42, 520), 64, '');
        AddNode('UCX_FortressGate_PillarR', Vector3(175, 0, 260), Vector3(95, 42, 520), 64, '');
        AddNode('UBX_FortressGate_Lintel', Vector3(0, 0, 450), Vector3(450, 42, 130), 12, '');
        AddNode('USP_LanternRing', Vector3(-140, -24, 310), Vector3(28, 28, 28), 80, '');
        { UE Attachment Sockets }
        AddNode('SOCKET_TorchMount_L', Vector3(-145, -25, 305), TVector3.Zero, 0, '');
        AddNode('SOCKET_KeystoneCrest', Vector3(0, -22, 495), TVector3.Zero, 0, '');
        { PBR Textures (_BC = sRGB, _N_DX = Linear + FlipGreen, _ORM = Linear) }
        AddNode('T_FortressStone_BC', TVector3.Zero, TVector3.Zero, 0, '', True, 2048);
        AddNode('T_FortressStone_N_DX', TVector3.Zero, TVector3.Zero, 0, '', True, 2048);
        AddNode('T_FortressStone_ORM', TVector3.Zero, TVector3.Zero, 0, '', True, 2048);
      end;

    ippSkeletalHeroRigAndAnimations:
      begin
        AddNode('SK_PaladinHero_Body', Vector3(0, 0.95, 0), Vector3(0.85, 1.90, 0.52),
          14800, 'Slot_PaladinPlate');
        AddNode('UCP_PaladinRootCapsule', Vector3(0, 0.95, 0), Vector3(0.70, 1.90, 0.70), 48, '');
        AddNode('SOCKET_Hand_R_Weapon', Vector3(0.42, 1.05, 0.14), TVector3.Zero, 0, '');
        AddNode('SOCKET_Back_Shield', Vector3(0.0, 1.35, -0.22), TVector3.Zero, 0, '');
        AddNode('T_PaladinPlate_BC', TVector3.Zero, TVector3.Zero, 0, '', True, 4096);
        AddNode('T_PaladinPlate_N', TVector3.Zero, TVector3.Zero, 0, '', True, 4096);
        AddNode('T_PaladinPlate_ORM', TVector3.Zero, TVector3.Zero, 0, '', True, 2048);
      end;

    ippFoliageWindAndBillboardLod:
      begin
        AddNode('SM_AncientOak_Trunk', Vector3(0, 0, 420), Vector3(220, 210, 840),
          3400, 'Slot_OakBark');
        AddNode('SM_AncientOak_Canopy', Vector3(0, 0, 620), Vector3(680, 660, 520),
          6200, 'Slot_OakLeavesSubsurface');
        AddNode('UCP_AncientOak_TrunkCollider', Vector3(0, 0, 250), Vector3(90, 90, 500), 48, '');
        AddNode('T_OakLeaves_BC', TVector3.Zero, TVector3.Zero, 0, '', True, 2048);
        AddNode('T_OakLeaves_ORM', TVector3.Zero, TVector3.Zero, 0, '', True, 1024);
      end;
  end;
end;

procedure TCastleInterchangePipeline.ExecuteImportPipeline;
var
  I, VisTris, Colliders, Sockets, NOut: Integer;
  MaxBounds, NodeBounds: TVector3;
  Role: TInterchangeNodeRole;
  PrimaryAsset: TInterchangeTranslatedAsset;
  UpperTex, PrimaryName, PrimaryClass: String;
  IsSrgb, FlipG: Boolean;
begin
  SetLength(FTranslatedAssets, 0);
  SetLength(FExtractedSocketNames, 0);
  SetLength(FExtractedColliderNames, 0);

  VisTris := 0;
  Colliders := 0;
  Sockets := 0;
  MaxBounds := TVector3.Zero;
  PrimaryName := 'SM_ImportedAsset';
  if FPreset = ippSkeletalHeroRigAndAnimations then
    PrimaryClass := 'SkeletalMesh'
  else
    PrimaryClass := 'StaticMesh';

  { Stage 1 & 2: Translate DCC Nodes & Separate Visual vs UCX_/UBX_/USP_/UCP_ & SOCKET_ }
  for I := 0 to High(FDccNodes) do
  begin
    Role := ClassifyNodeNamingConvention(FDccNodes[I].NodeName, FDccNodes[I].IsTexture);
    if Role = inrTextureMap then
      Continue;

    if (Role in [inrConvexCollisionUcx, inrBoxCollisionUbx, inrSphereCollisionUsp, inrCapsuleCollisionUcp]) and
       FExtractCollisionPrefixes then
    begin
      Inc(Colliders);
      SetLength(FExtractedColliderNames, Colliders);
      FExtractedColliderNames[Colliders - 1] := FDccNodes[I].NodeName;
      Continue;
    end;

    if (Role = inrAttachmentSocket) and FExtractSocketPrefixes then
    begin
      Inc(Sockets);
      SetLength(FExtractedSocketNames, Sockets);
      FExtractedSocketNames[Sockets - 1] := FDccNodes[I].NodeName;
      Continue;
    end;

    { Visual Render Geometry }
    if VisTris = 0 then
      PrimaryName := FDccNodes[I].NodeName;
    Inc(VisTris, FDccNodes[I].TriangleCount);

    NodeBounds := ConvertDccExtentToCgeMeters(FDccNodes[I].DccBoundsExtent);
    MaxBounds.X := Max(MaxBounds.X, NodeBounds.X);
    MaxBounds.Y := Max(MaxBounds.Y, NodeBounds.Y);
    MaxBounds.Z := Max(MaxBounds.Z, NodeBounds.Z);

    if FDccNodes[I].MaterialSlotName <> '' then
      EnsureMaterialSlot(FDccNodes[I].MaterialSlotName);
  end;

  { Emit Primary Mesh Translated Asset }
  PrimaryAsset := Default(TInterchangeTranslatedAsset);
  PrimaryAsset.AssetName := PrimaryName;
  PrimaryAsset.AssetClass := PrimaryClass;
  PrimaryAsset.VisualTriangleCount := VisTris;
  PrimaryAsset.ColliderCount := Colliders;
  PrimaryAsset.SocketCount := Sockets;
  PrimaryAsset.LodTierCount := LodCountForGroup(FLodGroup);
  PrimaryAsset.CgeBoundsMeters := MaxBounds;
  PrimaryAsset.Notes := Format('Rev v%d | %.2fx%.2fx%.2fm Y-Up | %d LODs',
    [FReimportRevision, MaxBounds.X, MaxBounds.Y, MaxBounds.Z, PrimaryAsset.LodTierCount]);
  SetLength(FTranslatedAssets, 1);
  FTranslatedAssets[0] := PrimaryAsset;

  { Stage 3A: Emit Material Instance Assets (preserving user overrides!) }
  if FAutoCreateMaterialInstances then
    for I := 0 to High(FSlotOverrides) do
    begin
      if not FPreserveUserOverridesOnReimport then
      begin
        FSlotOverrides[I].ActiveMiUrl := FSlotOverrides[I].DefaultMiUrl;
        FSlotOverrides[I].IsUserLocked := False;
      end;

      NOut := Length(FTranslatedAssets);
      SetLength(FTranslatedAssets, NOut + 1);
      FTranslatedAssets[NOut] := Default(TInterchangeTranslatedAsset);
      FTranslatedAssets[NOut].AssetName := 'MI_' + FSlotOverrides[I].SlotName;
      FTranslatedAssets[NOut].AssetClass := 'MaterialInstance';
      if FSlotOverrides[I].IsUserLocked then
        FTranslatedAssets[NOut].Notes := 'LOCKED OVERRIDE -> ' + FSlotOverrides[I].ActiveMiUrl
      else
        FTranslatedAssets[NOut].Notes := 'Auto-Generated -> ' + FSlotOverrides[I].ActiveMiUrl;
    end;

  { Stage 3B: Emit Texture2D Assets with UE Color-Space & DirectX Normal Green-Flip Rules }
  for I := 0 to High(FDccNodes) do
    if FDccNodes[I].IsTexture then
    begin
      UpperTex := UpperCase(FDccNodes[I].NodeName);
      IsSrgb := EndsStr('_BC', UpperTex) or EndsStr('_D', UpperTex) or
                EndsStr('_ALBEDO', UpperTex) or EndsStr('_BASECOLOR', UpperTex);
      FlipG := EndsStr('_N_DX', UpperTex) or (Pos('_NORMAL_DX', UpperTex) > 0);

      NOut := Length(FTranslatedAssets);
      SetLength(FTranslatedAssets, NOut + 1);
      FTranslatedAssets[NOut] := Default(TInterchangeTranslatedAsset);
      FTranslatedAssets[NOut].AssetName := FDccNodes[I].NodeName;
      FTranslatedAssets[NOut].AssetClass := 'Texture2D';
      FTranslatedAssets[NOut].IsSrgbGamma := IsSrgb;
      FTranslatedAssets[NOut].FlipNormalGreenChannel := FlipG;
      FTranslatedAssets[NOut].Notes := Format('%dx%d | sRGB=%s | FlipGreen=%s',
        [FDccNodes[I].TexResolution, FDccNodes[I].TexResolution,
         BoolToStr(IsSrgb, 'True', 'False (Linear)'),
         BoolToStr(FlipG, 'True (DX->GL)', 'False')]);
    end;
end;

procedure TCastleInterchangePipeline.SetUserMaterialSlotOverride(
  const ASlotName, ACustomMiUrl: String);
var
  I: Integer;
begin
  EnsureMaterialSlot(ASlotName);
  for I := 0 to High(FSlotOverrides) do
    if SameText(FSlotOverrides[I].SlotName, ASlotName) then
    begin
      FSlotOverrides[I].ActiveMiUrl := ACustomMiUrl;
      FSlotOverrides[I].IsUserLocked := True;
      Break;
    end;
  ExecuteImportPipeline;
end;

function TCastleInterchangePipeline.GetEffectiveMaterialSlotUrl(
  const ASlotName: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(FSlotOverrides) do
    if SameText(FSlotOverrides[I].SlotName, ASlotName) then
      Exit(FSlotOverrides[I].ActiveMiUrl);
end;

procedure TCastleInterchangePipeline.ClearAllUserSlotOverrides;
var
  I: Integer;
begin
  for I := 0 to High(FSlotOverrides) do
  begin
    FSlotOverrides[I].ActiveMiUrl := FSlotOverrides[I].DefaultMiUrl;
    FSlotOverrides[I].IsUserLocked := False;
  end;
  ExecuteImportPipeline;
end;

procedure TCastleInterchangePipeline.SimulateReimportUpdatedDccSource(
  const AAddedTriangles: Integer; const ANewSocketName: String);
var
  I, N: Integer;
  AlreadyHasSocket: Boolean;
begin
  Inc(FReimportRevision);

  { Update primary visual DCC mesh geometry }
  for I := 0 to High(FDccNodes) do
    if ClassifyNodeNamingConvention(FDccNodes[I].NodeName, FDccNodes[I].IsTexture) = inrVisualRenderMesh then
    begin
      Inc(FDccNodes[I].TriangleCount, Max(0, AAddedTriangles));
      Break;
    end;

  { Optionally append a newly authored DCC SOCKET_ node }
  if Trim(ANewSocketName) <> '' then
  begin
    AlreadyHasSocket := False;
    for I := 0 to High(FDccNodes) do
      if SameText(FDccNodes[I].NodeName, ANewSocketName) then
        AlreadyHasSocket := True;
    if not AlreadyHasSocket then
    begin
      N := Length(FDccNodes);
      SetLength(FDccNodes, N + 1);
      FDccNodes[N].NodeName := ANewSocketName;
      FDccNodes[N].DccLocation := Vector3(145, -25, 420);
      FDccNodes[N].DccBoundsExtent := TVector3.Zero;
      FDccNodes[N].TriangleCount := 0;
      FDccNodes[N].MaterialSlotName := '';
      FDccNodes[N].IsTexture := False;
      FDccNodes[N].TexResolution := 0;
    end;
  end;

  ExecuteImportPipeline;
end;

function TCastleInterchangePipeline.TranslatedAssetCount: Integer;
begin
  Result := Length(FTranslatedAssets);
end;

function TCastleInterchangePipeline.TotalVisualTriangles: Integer;
begin
  if Length(FTranslatedAssets) > 0 then
    Result := FTranslatedAssets[0].VisualTriangleCount
  else
    Result := 0;
end;

function TCastleInterchangePipeline.ExtractedColliderCount: Integer;
begin
  Result := Length(FExtractedColliderNames);
end;

function TCastleInterchangePipeline.ExtractedSocketCount: Integer;
begin
  Result := Length(FExtractedSocketNames);
end;

function TCastleInterchangePipeline.LockedSlotOverrideCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSlotOverrides) do
    if FSlotOverrides[I].IsUserLocked then
      Inc(Result);
end;

function TCastleInterchangePipeline.PrimaryMeshBoundsMeters: TVector3;
begin
  if Length(FTranslatedAssets) > 0 then
    Result := FTranslatedAssets[0].CgeBoundsMeters
  else
    Result := TVector3.Zero;
end;

function TCastleInterchangePipeline.GetPipelineDataJson: String;
var
  RootObj, SObj: TJSONObject;
  SlotsArr, NodesArr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    SlotsArr := TJSONArray.Create;
    for I := 0 to High(FSlotOverrides) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('slot', FSlotOverrides[I].SlotName);
      SObj.Add('defUrl', FSlotOverrides[I].DefaultMiUrl);
      SObj.Add('actUrl', FSlotOverrides[I].ActiveMiUrl);
      SObj.Add('locked', FSlotOverrides[I].IsUserLocked);
      SlotsArr.Add(SObj);
    end;
    RootObj.Add('slots', SlotsArr);

    NodesArr := TJSONArray.Create;
    for I := 0 to High(FDccNodes) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('name', FDccNodes[I].NodeName);
      SObj.Add('tris', FDccNodes[I].TriangleCount);
      SObj.Add('slot', FDccNodes[I].MaterialSlotName);
      SObj.Add('isTex', FDccNodes[I].IsTexture);
      SObj.Add('texRes', FDccNodes[I].TexResolution);
      SObj.Add('extX', FDccNodes[I].DccBoundsExtent.X);
      SObj.Add('extY', FDccNodes[I].DccBoundsExtent.Y);
      SObj.Add('extZ', FDccNodes[I].DccBoundsExtent.Z);
      NodesArr.Add(SObj);
    end;
    RootObj.Add('dccNodes', NodesArr);

    FPipelineDataJson := RootObj.AsJSON;
    Result := FPipelineDataJson;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleInterchangePipeline.SetPipelineDataJson(const AValue: String);
var
  Parsed: TJSONData;
  RootObj, SObj: TJSONObject;
  SlotsArr, NodesArr: TJSONArray;
  I: Integer;
begin
  FPipelineDataJson := AValue;
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    try
      Parsed := GetJSON(AValue);
    except
      Exit;
    end;
    if not (Parsed is TJSONObject) then Exit;
    RootObj := TJSONObject(Parsed);

    if RootObj.Find('dccNodes') is TJSONArray then
    begin
      NodesArr := TJSONArray(RootObj.Find('dccNodes'));
      SetLength(FDccNodes, NodesArr.Count);
      for I := 0 to NodesArr.Count - 1 do
        if NodesArr.Items[I] is TJSONObject then
        begin
          SObj := TJSONObject(NodesArr.Items[I]);
          FDccNodes[I] := Default(TInterchangeDccSourceNode);
          FDccNodes[I].NodeName := SObj.Get('name', '');
          FDccNodes[I].TriangleCount := SObj.Get('tris', 0);
          FDccNodes[I].MaterialSlotName := SObj.Get('slot', '');
          FDccNodes[I].IsTexture := SObj.Get('isTex', False);
          FDccNodes[I].TexResolution := SObj.Get('texRes', 0);
          FDccNodes[I].DccBoundsExtent := Vector3(
            SObj.Get('extX', 0.0), SObj.Get('extY', 0.0), SObj.Get('extZ', 0.0));
        end;
    end;

    if RootObj.Find('slots') is TJSONArray then
    begin
      SlotsArr := TJSONArray(RootObj.Find('slots'));
      SetLength(FSlotOverrides, SlotsArr.Count);
      for I := 0 to SlotsArr.Count - 1 do
        if SlotsArr.Items[I] is TJSONObject then
        begin
          SObj := TJSONObject(SlotsArr.Items[I]);
          FSlotOverrides[I].SlotName := SObj.Get('slot', '');
          FSlotOverrides[I].DefaultMiUrl := SObj.Get('defUrl', '');
          FSlotOverrides[I].ActiveMiUrl := SObj.Get('actUrl', '');
          FSlotOverrides[I].IsUserLocked := SObj.Get('locked', False);
        end;
    end;

    ExecuteImportPipeline;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleInterchangePipeline.InterchangeSummaryBadge: String;
begin
  Result := Format('[Interchange:v%d %dt %dCol %dSock %dLockedMI]',
    [FReimportRevision,
     TotalVisualTriangles,
     ExtractedColliderCount,
     ExtractedSocketCount,
     LockedSlotOverrideCount]);
end;

initialization
  RegisterSerializableComponent(TCastleInterchangePipeline,
    ['Asset Pipeline', 'Interchange Asset Import Pipeline (TCastleInterchangePipeline)']);

end.
