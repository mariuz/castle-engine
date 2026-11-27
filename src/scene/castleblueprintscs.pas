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

{ Unreal Engine 5.5-style Blueprint Components Viewport & Inherited Subobject
  Tree runtime (@link(TCastleBlueprintScsActor)) modeling USimpleConstructionScript
  (USCS_Node) and UInheritableComponentHandler: parent-to-child Blueprint class
  component inheritance, non-deletable [Inherited] parent components, child
  component attachment onto inherited sockets/nodes, per-subobject archetype
  delta overrides & Revert-to-Parent, and SpringArm -> Camera boom kinematics
  (Phase 395 — UE 5.5 Blueprint Components Viewport & USimpleConstructionScript Parity). }
unit CastleBlueprintScs;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Blueprint subobject component archetype kind (USCS_Node class parity). }
  TScsComponentKind = (
    sckSceneRoot,
    sckCapsuleCollider,
    sckSkeletalMesh,
    sckStaticMesh,
    sckSpringArm,
    sckFollowCamera,
    sckSpotLight,
    sckBoxTrigger
  );

  { Starter Blueprint SCS class presets. }
  TBlueprintScsPreset = (
    bspCustom,
    bspBaseThirdPersonCharacter,
    bspChildBossPaladinOverrides,
    bspModularInteractableChestBp
  );

  { Local USCS_Node subobject declared on a Blueprint class. }
  TScsSubobjectNode = record
    NodeName: String;
    ParentNodeName: String;
    Kind: TScsComponentKind;
    LocalPos: TVector3;
    LocalScale: TVector3;
    PrimaryParam: Single;   { CapsuleHeight / TargetArmLength / FovDeg / LightConeDeg }
    SecondaryParam: Single; { CapsuleRadius / SpringArmPitchDeg / LightIntensity }
    ColorRGBA: TVector4;
  end;
  TScsSubobjectNodeArray = array of TScsSubobjectNode;

  { UInheritableComponentHandler delta override on an [Inherited] parent node. }
  TScsInheritedOverride = record
    TargetNodeName: String;
    OverrideTransform: Boolean;
    LocalPosOverride: TVector3;
    LocalScaleOverride: TVector3;
    OverrideParams: Boolean;
    PrimaryParamOverride: Single;
    SecondaryParamOverride: Single;
  end;
  TScsInheritedOverrideArray = array of TScsInheritedOverride;

  { Final assembled component instance in Blueprint actor space. }
  TScsAssembledComponent = record
    NodeName: String;
    ParentNodeName: String;
    SourceBlueprintName: String;
    Kind: TScsComponentKind;
    TreeDepth: Integer;
    IsInherited: Boolean;
    IsOverriddenInChild: Boolean;
    LocalPos: TVector3;
    LocalScale: TVector3;
    ActorSpacePos: TVector3;
    ActorSpaceTipPos: TVector3; { Endpoint for SpringArm boom or SpotLight cone }
    PrimaryParam: Single;
    SecondaryParam: Single;
    ColorRGBA: TVector4;
  end;
  TScsAssembledComponentArray = array of TScsAssembledComponent;

  { Unreal Engine 5.5-style Blueprint Components & SimpleConstructionScript actor. }
  TCastleBlueprintScsActor = class(TCastleTransform)
  private
    FPreset: TBlueprintScsPreset;
    FBlueprintClassKey: String;
    FParentBlueprintScs: TCastleBlueprintScsActor;
    FShowViewportPreview: Boolean;

    FLocalNodes: TScsSubobjectNodeArray;
    FInheritedOverrides: TScsInheritedOverrideArray;
    FAssembled: TScsAssembledComponentArray;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TBlueprintScsPreset);
    procedure SetParentBlueprintScs(const AValue: TCastleBlueprintScsActor);
    procedure SetShowViewportPreview(const AValue: Boolean);
    function GetScsJson: String;
    procedure SetScsJson(const AValue: String);

    function WouldCreateParentCycle(const ACandidate: TCastleBlueprintScsActor): Boolean;
    procedure ClearPreviewContainer;
    procedure SyncPreviewVisuals;
  protected
    procedure Loaded; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TBlueprintScsPreset);

    { USCS_Node Local Subobject Authoring }
    procedure ClearLocalScs;
    function FindLocalNodeIndex(const ANodeName: String): Integer;
    function AddOrUpdateLocalSubobject(const ANodeName, AParentNodeName: String;
      const AKind: TScsComponentKind;
      const ALocalPos, ALocalScale: TVector3;
      const APrimaryParam, ASecondaryParam: Single;
      const AColor: TVector4): Integer;
    { Returns False if ANodeName is an [Inherited] component from ParentBlueprintScs! }
    function RemoveSubobject(const ANodeName: String): Boolean;

    { UInheritableComponentHandler Delta Overrides on [Inherited] Nodes }
    function FindOverrideIndex(const ATargetNodeName: String): Integer;
    function OverrideInheritedTransform(const ATargetNodeName: String;
      const ANewLocalPos, ANewLocalScale: TVector3): Boolean;
    function OverrideInheritedParams(const ATargetNodeName: String;
      const ANewPrimary, ANewSecondary: Single): Boolean;
    function RevertInheritedOverride(const ATargetNodeName: String): Boolean;
    procedure RevertAllInheritedOverrides;

    { Full USimpleConstructionScript Hierarchy Assembly }
    procedure RebuildAssembledComponents;
    function FindAssembledIndex(const ANodeName: String): Integer;
    function InheritedComponentCount: Integer;
    function OverriddenInheritedCount: Integer;

    function BlueprintScsSummaryBadge: String;

    property LocalNodes: TScsSubobjectNodeArray read FLocalNodes;
    property InheritedOverrides: TScsInheritedOverrideArray read FInheritedOverrides;
    property Assembled: TScsAssembledComponentArray read FAssembled;
  published
    property BlueprintClassKey: String read FBlueprintClassKey write FBlueprintClassKey;
    property ParentBlueprintScs: TCastleBlueprintScsActor
      read FParentBlueprintScs write SetParentBlueprintScs;
    property ShowViewportPreview: Boolean
      read FShowViewportPreview write SetShowViewportPreview default True;
    property ScsJson: String read GetScsJson write SetScsJson;
    property Preset: TBlueprintScsPreset
      read FPreset write SetPreset default bspBaseThirdPersonCharacter;
  end;

function ScsKindDisplayName(const AKind: TScsComponentKind): String;

implementation

uses
  fpjson, jsonparser;

function ScsKindDisplayName(const AKind: TScsComponentKind): String;
begin
  case AKind of
    sckSceneRoot:       Result := 'USceneComponent';
    sckCapsuleCollider: Result := 'UCapsuleComponent';
    sckSkeletalMesh:    Result := 'USkeletalMeshComponent';
    sckStaticMesh:      Result := 'UStaticMeshComponent';
    sckSpringArm:       Result := 'USpringArmComponent';
    sckFollowCamera:    Result := 'UCameraComponent';
    sckSpotLight:       Result := 'USpotLightComponent';
    sckBoxTrigger:      Result := 'UBoxComponent';
  end;
end;

{ TCastleBlueprintScsActor --------------------------------------------------- }

constructor TCastleBlueprintScsActor.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBlueprintClassKey := 'BP_BaseCharacter';
  FShowViewportPreview := True;
  ApplyPreset(bspBaseThirdPersonCharacter);
end;

destructor TCastleBlueprintScsActor.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastleBlueprintScsActor.Loaded;
begin
  inherited;
  RebuildAssembledComponents;
  SyncPreviewVisuals;
end;

procedure TCastleBlueprintScsActor.Notification(
  AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FParentBlueprintScs) then
  begin
    FParentBlueprintScs := nil;
    RebuildAssembledComponents;
    SyncPreviewVisuals;
  end;
end;

function TCastleBlueprintScsActor.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'BlueprintClassKey') or
     (PropertyName = 'ParentBlueprintScs') or
     (PropertyName = 'ShowViewportPreview') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleBlueprintScsActor.WouldCreateParentCycle(
  const ACandidate: TCastleBlueprintScsActor): Boolean;
var
  Cur: TCastleBlueprintScsActor;
  Steps: Integer;
begin
  Result := False;
  Cur := ACandidate;
  Steps := 0;
  while (Cur <> nil) and (Steps < 32) do
  begin
    if Cur = Self then Exit(True);
    Cur := Cur.ParentBlueprintScs;
    Inc(Steps);
  end;
end;

procedure TCastleBlueprintScsActor.SetParentBlueprintScs(
  const AValue: TCastleBlueprintScsActor);
begin
  if FParentBlueprintScs = AValue then Exit;
  if WouldCreateParentCycle(AValue) then Exit;

  if FParentBlueprintScs <> nil then
    FParentBlueprintScs.RemoveFreeNotification(Self);
  FParentBlueprintScs := AValue;
  if FParentBlueprintScs <> nil then
    FParentBlueprintScs.FreeNotification(Self);

  RebuildAssembledComponents;
  SyncPreviewVisuals;
end;

procedure TCastleBlueprintScsActor.SetPreset(const AValue: TBlueprintScsPreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleBlueprintScsActor.SetShowViewportPreview(const AValue: Boolean);
begin
  if FShowViewportPreview <> AValue then
  begin
    FShowViewportPreview := AValue;
    SyncPreviewVisuals;
  end;
end;

procedure TCastleBlueprintScsActor.ClearLocalScs;
begin
  FLocalNodes := nil;
  FInheritedOverrides := nil;
end;

function TCastleBlueprintScsActor.FindLocalNodeIndex(const ANodeName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FLocalNodes) do
    if SameText(FLocalNodes[I].NodeName, ANodeName) then
      Exit(I);
  Result := -1;
end;

function TCastleBlueprintScsActor.AddOrUpdateLocalSubobject(
  const ANodeName, AParentNodeName: String;
  const AKind: TScsComponentKind;
  const ALocalPos, ALocalScale: TVector3;
  const APrimaryParam, ASecondaryParam: Single;
  const AColor: TVector4): Integer;
begin
  if Trim(ANodeName) = '' then Exit(-1);
  Result := FindLocalNodeIndex(ANodeName);
  if Result < 0 then
  begin
    Result := Length(FLocalNodes);
    SetLength(FLocalNodes, Result + 1);
    FLocalNodes[Result].NodeName := Trim(ANodeName);
  end;
  FLocalNodes[Result].ParentNodeName := Trim(AParentNodeName);
  FLocalNodes[Result].Kind := AKind;
  FLocalNodes[Result].LocalPos := ALocalPos;
  FLocalNodes[Result].LocalScale := ALocalScale;
  FLocalNodes[Result].PrimaryParam := APrimaryParam;
  FLocalNodes[Result].SecondaryParam := ASecondaryParam;
  FLocalNodes[Result].ColorRGBA := AColor;
  RebuildAssembledComponents;
  SyncPreviewVisuals;
end;

function TCastleBlueprintScsActor.RemoveSubobject(const ANodeName: String): Boolean;
var
  AIdx, LIdx, I: Integer;
begin
  { UE 5.5 rule: [Inherited] parent components CANNOT be deleted in a Child Blueprint! }
  AIdx := FindAssembledIndex(ANodeName);
  if (AIdx >= 0) and FAssembled[AIdx].IsInherited then
    Exit(False);

  LIdx := FindLocalNodeIndex(ANodeName);
  if LIdx < 0 then Exit(False);
  for I := LIdx to High(FLocalNodes) - 1 do
    FLocalNodes[I] := FLocalNodes[I + 1];
  SetLength(FLocalNodes, Length(FLocalNodes) - 1);
  RebuildAssembledComponents;
  SyncPreviewVisuals;
  Result := True;
end;

function TCastleBlueprintScsActor.FindOverrideIndex(
  const ATargetNodeName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FInheritedOverrides) do
    if SameText(FInheritedOverrides[I].TargetNodeName, ATargetNodeName) then
      Exit(I);
  Result := -1;
end;

function TCastleBlueprintScsActor.OverrideInheritedTransform(
  const ATargetNodeName: String;
  const ANewLocalPos, ANewLocalScale: TVector3): Boolean;
var
  AIdx, OvIdx: Integer;
begin
  RebuildAssembledComponents;
  AIdx := FindAssembledIndex(ATargetNodeName);
  if (AIdx < 0) or (not FAssembled[AIdx].IsInherited) then
    Exit(False);

  OvIdx := FindOverrideIndex(ATargetNodeName);
  if OvIdx < 0 then
  begin
    OvIdx := Length(FInheritedOverrides);
    SetLength(FInheritedOverrides, OvIdx + 1);
    FInheritedOverrides[OvIdx] := Default(TScsInheritedOverride);
    FInheritedOverrides[OvIdx].TargetNodeName := ATargetNodeName;
  end;
  FInheritedOverrides[OvIdx].OverrideTransform := True;
  FInheritedOverrides[OvIdx].LocalPosOverride := ANewLocalPos;
  FInheritedOverrides[OvIdx].LocalScaleOverride := ANewLocalScale;
  RebuildAssembledComponents;
  SyncPreviewVisuals;
  Result := True;
end;

function TCastleBlueprintScsActor.OverrideInheritedParams(
  const ATargetNodeName: String;
  const ANewPrimary, ANewSecondary: Single): Boolean;
var
  AIdx, OvIdx: Integer;
begin
  RebuildAssembledComponents;
  AIdx := FindAssembledIndex(ATargetNodeName);
  if (AIdx < 0) or (not FAssembled[AIdx].IsInherited) then
    Exit(False);

  OvIdx := FindOverrideIndex(ATargetNodeName);
  if OvIdx < 0 then
  begin
    OvIdx := Length(FInheritedOverrides);
    SetLength(FInheritedOverrides, OvIdx + 1);
    FInheritedOverrides[OvIdx] := Default(TScsInheritedOverride);
    FInheritedOverrides[OvIdx].TargetNodeName := ATargetNodeName;
  end;
  FInheritedOverrides[OvIdx].OverrideParams := True;
  FInheritedOverrides[OvIdx].PrimaryParamOverride := ANewPrimary;
  FInheritedOverrides[OvIdx].SecondaryParamOverride := ANewSecondary;
  RebuildAssembledComponents;
  SyncPreviewVisuals;
  Result := True;
end;

function TCastleBlueprintScsActor.RevertInheritedOverride(
  const ATargetNodeName: String): Boolean;
var
  OvIdx, I: Integer;
begin
  OvIdx := FindOverrideIndex(ATargetNodeName);
  if OvIdx < 0 then Exit(False);
  for I := OvIdx to High(FInheritedOverrides) - 1 do
    FInheritedOverrides[I] := FInheritedOverrides[I + 1];
  SetLength(FInheritedOverrides, Length(FInheritedOverrides) - 1);
  RebuildAssembledComponents;
  SyncPreviewVisuals;
  Result := True;
end;

procedure TCastleBlueprintScsActor.RevertAllInheritedOverrides;
begin
  FInheritedOverrides := nil;
  RebuildAssembledComponents;
  SyncPreviewVisuals;
end;

procedure TCastleBlueprintScsActor.ApplyPreset(const APreset: TBlueprintScsPreset);
begin
  FPreset := APreset;
  if APreset = bspCustom then Exit;

  ClearLocalScs;
  case APreset of
    bspChildBossPaladinOverrides:
      begin
        FBlueprintClassKey := 'BP_BossPaladin_Child';
        AddOrUpdateLocalSubobject('GreatSword_R', 'CharacterMesh0', sckStaticMesh,
          Vector3(0.62, 0.35, 0.20), Vector3(0.18, 1.55, 0.14), 1.55, 0.0,
          Vector4(0.96, 0.78, 0.26, 1.0));
        AddOrUpdateLocalSubobject('AegisShield_L', 'CharacterMesh0', sckStaticMesh,
          Vector3(-0.58, 0.22, 0.18), Vector3(0.16, 0.92, 0.68), 0.92, 0.0,
          Vector4(0.36, 0.68, 0.98, 1.0));
        AddOrUpdateLocalSubobject('HolyAuraSpotLight', 'CapsuleComponent', sckSpotLight,
          Vector3(0.0, 1.75, 0.0), Vector3(1, 1, 1), 38.0, 12.0,
          Vector4(1.0, 0.90, 0.42, 1.0));

        if FParentBlueprintScs <> nil then
        begin
          OverrideInheritedParams('CapsuleComponent', 2.45, 0.56);
          OverrideInheritedParams('CameraBoom', 5.40, 22.0);
        end;
      end;

    bspModularInteractableChestBp:
      begin
        FBlueprintClassKey := 'BP_TreasureChest_Actor';
        AddOrUpdateLocalSubobject('DefaultSceneRoot', '', sckSceneRoot,
          Vector3(0, 0, 0), Vector3(1, 1, 1), 0.25, 0.0,
          Vector4(0.85, 0.88, 0.95, 1.0));
        AddOrUpdateLocalSubobject('ChestBaseBox', 'DefaultSceneRoot', sckStaticMesh,
          Vector3(0, 0.40, 0), Vector3(1.30, 0.80, 0.90), 0.80, 0.0,
          Vector4(0.56, 0.38, 0.22, 1.0));
        AddOrUpdateLocalSubobject('HingedVaultLid', 'ChestBaseBox', sckStaticMesh,
          Vector3(0, 0.52, 0), Vector3(1.34, 0.32, 0.94), 0.32, 0.0,
          Vector4(0.84, 0.66, 0.24, 1.0));
        AddOrUpdateLocalSubobject('LootBeaconLight', 'ChestBaseBox', sckSpotLight,
          Vector3(0, 0.95, 0), Vector3(1, 1, 1), 45.0, 8.0,
          Vector4(1.0, 0.84, 0.28, 1.0));
        AddOrUpdateLocalSubobject('InteractProximityBox', 'DefaultSceneRoot', sckBoxTrigger,
          Vector3(0, 0.75, 0.40), Vector3(2.40, 1.50, 2.20), 2.40, 1.50,
          Vector4(0.28, 0.92, 0.56, 1.0));
      end;
  else
    begin
      FPreset := bspBaseThirdPersonCharacter;
      FBlueprintClassKey := 'BP_BaseCharacter';
      AddOrUpdateLocalSubobject('CapsuleComponent', '', sckCapsuleCollider,
        Vector3(0.0, 0.95, 0.0), Vector3(1, 1, 1), 1.90, 0.42,
        Vector4(0.98, 0.62, 0.24, 1.0));
      AddOrUpdateLocalSubobject('CharacterMesh0', 'CapsuleComponent', sckSkeletalMesh,
        Vector3(0.0, 0.0, 0.0), Vector3(0.68, 1.72, 0.44), 1.72, 0.0,
        Vector4(0.36, 0.62, 0.92, 1.0));
      AddOrUpdateLocalSubobject('CameraBoom', 'CapsuleComponent', sckSpringArm,
        Vector3(0.0, 0.58, 0.0), Vector3(1, 1, 1), 3.60, 18.0,
        Vector4(0.98, 0.28, 0.32, 1.0));
      AddOrUpdateLocalSubobject('FollowCamera', 'CameraBoom', sckFollowCamera,
        Vector3(0.0, 0.0, 0.0), Vector3(1, 1, 1), 90.0, 0.0,
        Vector4(1.0, 0.82, 0.26, 1.0));
    end;
  end;

  RebuildAssembledComponents;
  SyncPreviewVisuals;
end;

procedure TCastleBlueprintScsActor.RebuildAssembledComponents;
var
  Chain: array of TCastleBlueprintScsActor;
  CurBp: TCastleBlueprintScsActor;
  RawNodes: TScsSubobjectNodeArray;
  RawSource: array of String;
  RawIsInh: array of Boolean;
  RawIsOv: array of Boolean;
  Placed: array of Boolean;
  CIdx, NIdx, OvIdx, Pass, OutCnt, ParentAIdx, Steps: Integer;
  PitchRad, ArmLen: Single;
  BoomOffset: TVector3;

  procedure ApplyChildOverridesAlongChain(var NodeRec: TScsSubobjectNode;
    var WasOverridden: Boolean; const FromChainIdx: Integer);
  var
    DescIdx, K: Integer;
    DescBp: TCastleBlueprintScsActor;
  begin
    for DescIdx := FromChainIdx - 1 downto 0 do
    begin
      DescBp := Chain[DescIdx];
      K := DescBp.FindOverrideIndex(NodeRec.NodeName);
      if K >= 0 then
      begin
        WasOverridden := True;
        if DescBp.FInheritedOverrides[K].OverrideTransform then
        begin
          NodeRec.LocalPos := DescBp.FInheritedOverrides[K].LocalPosOverride;
          NodeRec.LocalScale := DescBp.FInheritedOverrides[K].LocalScaleOverride;
        end;
        if DescBp.FInheritedOverrides[K].OverrideParams then
        begin
          NodeRec.PrimaryParam := DescBp.FInheritedOverrides[K].PrimaryParamOverride;
          NodeRec.SecondaryParam := DescBp.FInheritedOverrides[K].SecondaryParamOverride;
        end;
      end;
    end;
  end;

begin
  Chain := nil;
  CurBp := Self;
  Steps := 0;
  while (CurBp <> nil) and (Steps < 16) do
  begin
    SetLength(Chain, Length(Chain) + 1);
    Chain[High(Chain)] := CurBp;
    CurBp := CurBp.ParentBlueprintScs;
    Inc(Steps);
  end;

  RawNodes := nil;
  RawSource := nil;
  RawIsInh := nil;
  RawIsOv := nil;
  for CIdx := High(Chain) downto 0 do
  begin
    CurBp := Chain[CIdx];
    for NIdx := 0 to High(CurBp.FLocalNodes) do
    begin
      OvIdx := Length(RawNodes);
      SetLength(RawNodes, OvIdx + 1);
      SetLength(RawSource, OvIdx + 1);
      SetLength(RawIsInh, OvIdx + 1);
      SetLength(RawIsOv, OvIdx + 1);

      RawNodes[OvIdx] := CurBp.FLocalNodes[NIdx];
      RawSource[OvIdx] := CurBp.BlueprintClassKey;
      RawIsInh[OvIdx] := (CIdx > 0);
      RawIsOv[OvIdx] := False;
      if CIdx > 0 then
        ApplyChildOverridesAlongChain(RawNodes[OvIdx], RawIsOv[OvIdx], CIdx);
    end;
  end;

  FAssembled := nil;
  SetLength(Placed, Length(RawNodes));
  for NIdx := 0 to High(Placed) do
    Placed[NIdx] := False;

  for Pass := 0 to Length(RawNodes) do
    for NIdx := 0 to High(RawNodes) do
      if not Placed[NIdx] then
      begin
        if RawNodes[NIdx].ParentNodeName = '' then
          ParentAIdx := -1
        else
        begin
          ParentAIdx := FindAssembledIndex(RawNodes[NIdx].ParentNodeName);
          if ParentAIdx < 0 then
          begin
            Steps := -1;
            for CIdx := 0 to High(RawNodes) do
              if SameText(RawNodes[CIdx].NodeName, RawNodes[NIdx].ParentNodeName) then
              begin
                Steps := CIdx;
                Break;
              end;
            if Steps >= 0 then Continue;
          end;
        end;

        Placed[NIdx] := True;
        OutCnt := Length(FAssembled);
        SetLength(FAssembled, OutCnt + 1);
        FAssembled[OutCnt].NodeName := RawNodes[NIdx].NodeName;
        FAssembled[OutCnt].ParentNodeName := RawNodes[NIdx].ParentNodeName;
        FAssembled[OutCnt].SourceBlueprintName := RawSource[NIdx];
        FAssembled[OutCnt].Kind := RawNodes[NIdx].Kind;
        FAssembled[OutCnt].IsInherited := RawIsInh[NIdx];
        FAssembled[OutCnt].IsOverriddenInChild := RawIsOv[NIdx];
        FAssembled[OutCnt].LocalPos := RawNodes[NIdx].LocalPos;
        FAssembled[OutCnt].LocalScale := RawNodes[NIdx].LocalScale;
        FAssembled[OutCnt].PrimaryParam := RawNodes[NIdx].PrimaryParam;
        FAssembled[OutCnt].SecondaryParam := RawNodes[NIdx].SecondaryParam;
        FAssembled[OutCnt].ColorRGBA := RawNodes[NIdx].ColorRGBA;

        if ParentAIdx < 0 then
        begin
          FAssembled[OutCnt].TreeDepth := 0;
          FAssembled[OutCnt].ActorSpacePos := RawNodes[NIdx].LocalPos;
        end else
        begin
          FAssembled[OutCnt].TreeDepth := FAssembled[ParentAIdx].TreeDepth + 1;
          if FAssembled[ParentAIdx].Kind = sckSpringArm then
            FAssembled[OutCnt].ActorSpacePos :=
              FAssembled[ParentAIdx].ActorSpaceTipPos + RawNodes[NIdx].LocalPos
          else
            FAssembled[OutCnt].ActorSpacePos :=
              FAssembled[ParentAIdx].ActorSpacePos + RawNodes[NIdx].LocalPos;
        end;

        if RawNodes[NIdx].Kind = sckSpringArm then
        begin
          ArmLen := Max(0.2, RawNodes[NIdx].PrimaryParam);
          PitchRad := DegToRad(RawNodes[NIdx].SecondaryParam);
          BoomOffset := Vector3(-ArmLen * Cos(PitchRad), ArmLen * Sin(PitchRad), 0.0);
          FAssembled[OutCnt].ActorSpaceTipPos :=
            FAssembled[OutCnt].ActorSpacePos + BoomOffset;
        end else
        if RawNodes[NIdx].Kind = sckSpotLight then
          FAssembled[OutCnt].ActorSpaceTipPos :=
            FAssembled[OutCnt].ActorSpacePos + Vector3(0.0, -1.6, 0.0)
        else
          FAssembled[OutCnt].ActorSpaceTipPos := FAssembled[OutCnt].ActorSpacePos;
      end;
end;

function TCastleBlueprintScsActor.FindAssembledIndex(const ANodeName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FAssembled) do
    if SameText(FAssembled[I].NodeName, ANodeName) then
      Exit(I);
  Result := -1;
end;

function TCastleBlueprintScsActor.InheritedComponentCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FAssembled) do
    if FAssembled[I].IsInherited then
      Inc(Result);
end;

function TCastleBlueprintScsActor.OverriddenInheritedCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FAssembled) do
    if FAssembled[I].IsInherited and FAssembled[I].IsOverriddenInChild then
      Inc(Result);
end;

procedure TCastleBlueprintScsActor.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
  begin
    Remove(FPreviewContainer);
    FreeAndNil(FPreviewContainer);
  end;
end;

procedure TCastleBlueprintScsActor.SyncPreviewVisuals;
var
  I: Integer;
  B: TCastleBox;
  S: TCastleSphere;
begin
  ClearPreviewContainer;
  if (not FShowViewportPreview) or (csDestroying in ComponentState) then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  Add(FPreviewContainer);

  for I := 0 to High(FAssembled) do
    case FAssembled[I].Kind of
      sckCapsuleCollider:
        begin
          B := TCastleBox.Create(FPreviewContainer);
          B.SetTransient;
          B.Size := Vector3(
            FAssembled[I].SecondaryParam * 2.0,
            FAssembled[I].PrimaryParam,
            FAssembled[I].SecondaryParam * 2.0);
          B.Translation := FAssembled[I].ActorSpacePos;
          B.Color := FAssembled[I].ColorRGBA;
          FPreviewContainer.Add(B);
        end;
      sckSkeletalMesh, sckStaticMesh, sckBoxTrigger:
        begin
          B := TCastleBox.Create(FPreviewContainer);
          B.SetTransient;
          B.Size := FAssembled[I].LocalScale;
          B.Translation := FAssembled[I].ActorSpacePos;
          B.Color := FAssembled[I].ColorRGBA;
          FPreviewContainer.Add(B);
        end;
      sckFollowCamera, sckSpotLight, sckSpringArm:
        begin
          S := TCastleSphere.Create(FPreviewContainer);
          S.SetTransient;
          S.Radius := 0.16;
          S.Translation := FAssembled[I].ActorSpacePos;
          S.Color := FAssembled[I].ColorRGBA;
          FPreviewContainer.Add(S);
        end;
    else
      ;
    end;
end;

function TCastleBlueprintScsActor.GetScsJson: String;
var
  Root, ItemObj: TJSONObject;
  NodesArr, OvArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('blueprintClassKey', FBlueprintClassKey);
    NodesArr := TJSONArray.Create;
    Root.Add('localNodes', NodesArr);
    for I := 0 to High(FLocalNodes) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('name', FLocalNodes[I].NodeName);
      ItemObj.Add('parent', FLocalNodes[I].ParentNodeName);
      ItemObj.Add('kind', Ord(FLocalNodes[I].Kind));
      ItemObj.Add('px', FLocalNodes[I].LocalPos.X);
      ItemObj.Add('py', FLocalNodes[I].LocalPos.Y);
      ItemObj.Add('pz', FLocalNodes[I].LocalPos.Z);
      ItemObj.Add('sx', FLocalNodes[I].LocalScale.X);
      ItemObj.Add('sy', FLocalNodes[I].LocalScale.Y);
      ItemObj.Add('sz', FLocalNodes[I].LocalScale.Z);
      ItemObj.Add('p1', FLocalNodes[I].PrimaryParam);
      ItemObj.Add('p2', FLocalNodes[I].SecondaryParam);
      NodesArr.Add(ItemObj);
    end;

    OvArr := TJSONArray.Create;
    Root.Add('inheritedOverrides', OvArr);
    for I := 0 to High(FInheritedOverrides) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('target', FInheritedOverrides[I].TargetNodeName);
      ItemObj.Add('ovTrans', FInheritedOverrides[I].OverrideTransform);
      ItemObj.Add('ovParams', FInheritedOverrides[I].OverrideParams);
      ItemObj.Add('p1', FInheritedOverrides[I].PrimaryParamOverride);
      ItemObj.Add('p2', FInheritedOverrides[I].SecondaryParamOverride);
      OvArr.Add(ItemObj);
    end;
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleBlueprintScsActor.SetScsJson(const AValue: String);
var
  Data: TJSONData;
  Root, ItemObj: TJSONObject;
  NodesArr, OvArr: TJSONArray;
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
    FBlueprintClassKey := Root.Get('blueprintClassKey', FBlueprintClassKey);

    NodesArr := Root.Find('localNodes', jtArray) as TJSONArray;
    if NodesArr <> nil then
    begin
      FLocalNodes := nil;
      for I := 0 to NodesArr.Count - 1 do
        if NodesArr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(NodesArr.Items[I]);
          AddOrUpdateLocalSubobject(
            ItemObj.Get('name', 'Comp' + IntToStr(I)),
            ItemObj.Get('parent', ''),
            TScsComponentKind(EnsureRange(ItemObj.Get('kind', 0), 0, Ord(High(TScsComponentKind)))),
            Vector3(ItemObj.Get('px', 0.0), ItemObj.Get('py', 0.0), ItemObj.Get('pz', 0.0)),
            Vector3(ItemObj.Get('sx', 1.0), ItemObj.Get('sy', 1.0), ItemObj.Get('sz', 1.0)),
            ItemObj.Get('p1', 1.0),
            ItemObj.Get('p2', 0.0),
            Vector4(0.5, 0.7, 0.9, 1.0));
        end;
    end;

    OvArr := Root.Find('inheritedOverrides', jtArray) as TJSONArray;
    if OvArr <> nil then
    begin
      SetLength(FInheritedOverrides, OvArr.Count);
      for I := 0 to OvArr.Count - 1 do
        if OvArr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(OvArr.Items[I]);
          FInheritedOverrides[I] := Default(TScsInheritedOverride);
          FInheritedOverrides[I].TargetNodeName := ItemObj.Get('target', '');
          FInheritedOverrides[I].OverrideTransform := ItemObj.Get('ovTrans', False);
          FInheritedOverrides[I].OverrideParams := ItemObj.Get('ovParams', False);
          FInheritedOverrides[I].PrimaryParamOverride := ItemObj.Get('p1', 1.0);
          FInheritedOverrides[I].SecondaryParamOverride := ItemObj.Get('p2', 0.0);
        end;
    end;
    RebuildAssembledComponents;
    SyncPreviewVisuals;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleBlueprintScsActor.BlueprintScsSummaryBadge: String;
begin
  Result := Format('[BP_SCS:%s Total=%d Inh=%d Ov=%d]',
    [FBlueprintClassKey, Length(FAssembled),
     InheritedComponentCount, OverriddenInheritedCount]);
end;

initialization
  RegisterSerializableComponent(TCastleBlueprintScsActor,
    ['Blueprints & Scripting', 'Blueprint SCS Component Tree & Viewport']);
end.
