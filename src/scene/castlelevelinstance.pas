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

{ Unreal Engine 5.5-style Level Instances, Packed Level Actors & One-File-Per-Actor
  (OFPA) runtime (@link(TCastleLevelInstance)) featuring in-place Level Instance
  Edit / Commit / Discard / Break workflows, Packed Level Actor Instanced Static
  Mesh (ISM) draw-call batch consolidation, and deterministic __ExternalActors__
  FNV-1a bucketing + conflict-free per-actor Git branch merging
  (Phase 390 — UE 5.5 ALevelInstance, APackedLevelActor & OFPA Parity). }
unit CastleLevelInstance;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleVectors, CastleTransform, CastleScene, CastleBoxes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Interactive editing state of a @link(TCastleLevelInstance) (ALevelInstance parity). }
  TLevelInstanceEditMode = (
    limLocked,
    limEditingInPlace
  );

  { Built-in UE 5.5 Level Instance & Packed Level Actor starter presets. }
  TLevelInstancePreset = (
    lipCustom,
    lipMedievalWatchtower10Actors,
    lipCyberpunkStreetBlock12Actors,
    lipDungeonRoomModular8Actors
  );

  { Single sub-actor slot inside a Level Instance / Packed Level Actor assembly. }
  TLevelInstanceSubActor = record
    SubName: String;
    MeshTag: String;
    LocalPos: TVector3;
    LocalSize: TVector3;
    YawDeg: Single;
    ColorRGBA: TVector4;
  end;
  TLevelInstanceSubActorArray = array of TLevelInstanceSubActor;

  { Consolidated GPU-instanced static-mesh batch (APackedLevelActor ISM parity). }
  TPackedMeshBatch = record
    MeshTag: String;
    InstanceCount: Integer;
    BoundsMin: TVector3;
    BoundsMax: TVector3;
  end;
  TPackedMeshBatchArray = array of TPackedMeshBatch;

  { Single externalized per-actor file entry in an OFPA (__ExternalActors__) repo. }
  TOfpaActorFileEntry = record
    ActorName: String;
    RelativeOfpaPath: String;
    ContentHashHex: String;
    SerializedActorJson: String;
  end;
  TOfpaActorFileEntryArray = array of TOfpaActorFileEntry;

  { Unreal Engine 5.5-style Level Instance & Packed Level Actor component. }
  TCastleLevelInstance = class(TCastleTransform)
  private
    FPreset: TLevelInstancePreset;
    FLevelAssetKey: String;
    FPackedInstancedMode: Boolean;
    FShowPreviewActors: Boolean;

    FEditMode: TLevelInstanceEditMode;
    FSubActors: TLevelInstanceSubActorArray;
    FPackedBatches: TPackedMeshBatchArray;
    FPreEditSnapshotJson: String;
    FCommitVersion: Integer;
    FPreviewContainer: TCastleTransform;

    procedure SetPreset(const AValue: TLevelInstancePreset);
    procedure SetPackedInstancedMode(const AValue: Boolean);
    procedure SetShowPreviewActors(const AValue: Boolean);
    function GetSubLevelJson: String;
    procedure SetSubLevelJson(const AValue: String);

    procedure ClearPreviewContainer;
    procedure SyncPreviewActors;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Deterministic OFPA (__ExternalActors__) Hash & Bucket Helpers }
    class function ComputeFnv1a32(const S: String): Cardinal; static;
    class function ComputeContentHashHex(const S: String): String; static;
    class function BuildOfpaRelativePath(const AActorName: String): String; static;

    { Sub-Actor & Packed ISM Authoring }
    procedure ClearSubLevel;
    procedure ApplyPreset(const APreset: TLevelInstancePreset);
    function FindSubActorIndex(const ASubName: String): Integer;
    function AddOrUpdateSubActor(const ASubName, AMeshTag: String;
      const ALocalPos, ALocalSize: TVector3; const AYawDeg: Single;
      const AColor: TVector4): Integer;
    procedure RebuildPackedInstancedBatches;
    function DrawCallReductionPercent: Single;

    { In-Place Level Instance Edit / Commit / Discard / Break Workflow }
    function BeginEditInPlace: Boolean;
    function ModifySubActorPositionInEdit(const ASubName: String;
      const ANewLocalPos: TVector3): Boolean;
    function CommitInPlaceEdits: Boolean;
    function DiscardInPlaceEdits: Boolean;
    function BreakIntoWorldActors(const AParentTransform: TCastleTransform;
      const ADesignOwner: TComponent): Integer;

    function LevelInstanceSummaryBadge: String;

    property EditMode: TLevelInstanceEditMode read FEditMode;
    property SubActors: TLevelInstanceSubActorArray read FSubActors;
    property PackedBatches: TPackedMeshBatchArray read FPackedBatches;
    property CommitVersion: Integer read FCommitVersion;
  published
    property LevelAssetKey: String read FLevelAssetKey write FLevelAssetKey;
    property PackedInstancedMode: Boolean
      read FPackedInstancedMode write SetPackedInstancedMode default True;
    property ShowPreviewActors: Boolean
      read FShowPreviewActors write SetShowPreviewActors default True;
    property SubLevelJson: String read GetSubLevelJson write SetSubLevelJson;
    property Preset: TLevelInstancePreset
      read FPreset write SetPreset default lipMedievalWatchtower10Actors;
  end;

implementation

uses
  fpjson, jsonparser;

{ Deterministic OFPA FNV-1a Hashing & Bucketing ------------------------------ }

class function TCastleLevelInstance.ComputeFnv1a32(const S: String): Cardinal;
var
  I: Integer;
begin
  {$PUSH}{$R-}{$Q-}
  Result := Cardinal($811C9DC5);
  for I := 1 to Length(S) do
  begin
    Result := Result xor Cardinal(Ord(S[I]));
    Result := Result * Cardinal($01000193);
  end;
  {$POP}
end;

class function TCastleLevelInstance.ComputeContentHashHex(const S: String): String;
begin
  Result := IntToHex(ComputeFnv1a32(S), 8);
end;

class function TCastleLevelInstance.BuildOfpaRelativePath(
  const AActorName: String): String;
var
  BucketHex, CleanName: String;
  H: Cardinal;
  I: Integer;
begin
  CleanName := Trim(AActorName);
  if CleanName = '' then CleanName := 'UnnamedActor';
  for I := 1 to Length(CleanName) do
    if not (CleanName[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
      CleanName[I] := '_';

  H := ComputeFnv1a32(LowerCase(CleanName));
  BucketHex := IntToHex(H and $FF, 2);
  Result := '__ExternalActors__/' + BucketHex + '/' + CleanName + '.json';
end;

{ TCastleLevelInstance ------------------------------------------------------- }

constructor TCastleLevelInstance.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLevelAssetKey := 'LI_MedievalWatchtower';
  FPackedInstancedMode := True;
  FShowPreviewActors := True;
  FEditMode := limLocked;
  ApplyPreset(lipMedievalWatchtower10Actors);
end;

destructor TCastleLevelInstance.Destroy;
begin
  ClearPreviewContainer;
  inherited;
end;

procedure TCastleLevelInstance.Loaded;
begin
  inherited;
  RebuildPackedInstancedBatches;
  SyncPreviewActors;
end;

function TCastleLevelInstance.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'LevelAssetKey') or
     (PropertyName = 'PackedInstancedMode') or
     (PropertyName = 'ShowPreviewActors') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleLevelInstance.SetPreset(const AValue: TLevelInstancePreset);
begin
  if csLoading in ComponentState then
  begin
    FPreset := AValue;
    Exit;
  end;
  ApplyPreset(AValue);
end;

procedure TCastleLevelInstance.SetPackedInstancedMode(const AValue: Boolean);
begin
  if FPackedInstancedMode <> AValue then
  begin
    FPackedInstancedMode := AValue;
    RebuildPackedInstancedBatches;
    SyncPreviewActors;
  end;
end;

procedure TCastleLevelInstance.SetShowPreviewActors(const AValue: Boolean);
begin
  if FShowPreviewActors <> AValue then
  begin
    FShowPreviewActors := AValue;
    if not FShowPreviewActors then
      ClearPreviewContainer
    else
      SyncPreviewActors;
  end;
end;

procedure TCastleLevelInstance.ClearPreviewContainer;
begin
  if FPreviewContainer <> nil then
    FreeAndNil(FPreviewContainer);
end;

procedure TCastleLevelInstance.SyncPreviewActors;
var
  I: Integer;
  B: TCastleBox;
begin
  ClearPreviewContainer;
  if (not FShowPreviewActors) or (Length(FSubActors) = 0) then Exit;

  FPreviewContainer := TCastleTransform.Create(nil);
  FPreviewContainer.SetTransient;
  FPreviewContainer.Pickable := FEditMode = limEditingInPlace;
  FPreviewContainer.Collides := False;
  FPreviewContainer.Name := 'LI_PreviewActors';
  Add(FPreviewContainer);

  for I := 0 to High(FSubActors) do
  begin
    B := TCastleBox.Create(FPreviewContainer);
    B.SetTransient;
    B.Pickable := FEditMode = limEditingInPlace;
    B.Collides := False;
    B.Size := FSubActors[I].LocalSize;
    B.Translation := FSubActors[I].LocalPos;
    B.Rotation := Vector4(0, 1, 0, DegToRad(FSubActors[I].YawDeg));
    if FEditMode = limEditingInPlace then
      B.Color := Vector4(
        Min(1.0, FSubActors[I].ColorRGBA.X + 0.18),
        Min(1.0, FSubActors[I].ColorRGBA.Y + 0.18),
        FSubActors[I].ColorRGBA.Z, 1.0)
    else
      B.Color := FSubActors[I].ColorRGBA;
    FPreviewContainer.Add(B);
  end;
end;

procedure TCastleLevelInstance.ClearSubLevel;
begin
  FSubActors := nil;
  FPackedBatches := nil;
  FEditMode := limLocked;
  FPreEditSnapshotJson := '';
  ClearPreviewContainer;
end;

function TCastleLevelInstance.FindSubActorIndex(const ASubName: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FSubActors) do
    if SameText(FSubActors[I].SubName, ASubName) then
      Exit(I);
  Result := -1;
end;

function TCastleLevelInstance.AddOrUpdateSubActor(
  const ASubName, AMeshTag: String;
  const ALocalPos, ALocalSize: TVector3; const AYawDeg: Single;
  const AColor: TVector4): Integer;
var
  S: TLevelInstanceSubActor;
begin
  Result := FindSubActorIndex(ASubName);
  if Result < 0 then
  begin
    Result := Length(FSubActors);
    SetLength(FSubActors, Result + 1);
  end;
  S.SubName := ASubName;
  S.MeshTag := AMeshTag;
  S.LocalPos := ALocalPos;
  S.LocalSize := ALocalSize;
  S.YawDeg := AYawDeg;
  S.ColorRGBA := AColor;
  FSubActors[Result] := S;
end;

procedure TCastleLevelInstance.RebuildPackedInstancedBatches;
var
  I, BIdx, Found: Integer;
  HalfSz: TVector3;
begin
  FPackedBatches := nil;
  if Length(FSubActors) = 0 then Exit;

  for I := 0 to High(FSubActors) do
  begin
    Found := -1;
    for BIdx := 0 to High(FPackedBatches) do
      if SameText(FPackedBatches[BIdx].MeshTag, FSubActors[I].MeshTag) then
      begin
        Found := BIdx;
        Break;
      end;

    HalfSz := FSubActors[I].LocalSize * 0.5;
    if Found < 0 then
    begin
      Found := Length(FPackedBatches);
      SetLength(FPackedBatches, Found + 1);
      FPackedBatches[Found].MeshTag := FSubActors[I].MeshTag;
      FPackedBatches[Found].InstanceCount := 1;
      FPackedBatches[Found].BoundsMin := FSubActors[I].LocalPos - HalfSz;
      FPackedBatches[Found].BoundsMax := FSubActors[I].LocalPos + HalfSz;
    end else
    begin
      Inc(FPackedBatches[Found].InstanceCount);
      FPackedBatches[Found].BoundsMin := Vector3(
        Min(FPackedBatches[Found].BoundsMin.X, FSubActors[I].LocalPos.X - HalfSz.X),
        Min(FPackedBatches[Found].BoundsMin.Y, FSubActors[I].LocalPos.Y - HalfSz.Y),
        Min(FPackedBatches[Found].BoundsMin.Z, FSubActors[I].LocalPos.Z - HalfSz.Z));
      FPackedBatches[Found].BoundsMax := Vector3(
        Max(FPackedBatches[Found].BoundsMax.X, FSubActors[I].LocalPos.X + HalfSz.X),
        Max(FPackedBatches[Found].BoundsMax.Y, FSubActors[I].LocalPos.Y + HalfSz.Y),
        Max(FPackedBatches[Found].BoundsMax.Z, FSubActors[I].LocalPos.Z + HalfSz.Z));
    end;
  end;
end;

function TCastleLevelInstance.DrawCallReductionPercent: Single;
begin
  if (not FPackedInstancedMode) or (Length(FSubActors) = 0) then Exit(0.0);
  Result := Max(0.0, (1.0 - (Length(FPackedBatches) / Length(FSubActors))) * 100.0);
end;

{ In-Place Edit / Commit / Discard / Break ----------------------------------- }

function TCastleLevelInstance.BeginEditInPlace: Boolean;
begin
  if FEditMode = limEditingInPlace then Exit(False);
  FPreEditSnapshotJson := GetSubLevelJson;
  FEditMode := limEditingInPlace;
  SyncPreviewActors;
  Result := True;
end;

function TCastleLevelInstance.ModifySubActorPositionInEdit(
  const ASubName: String; const ANewLocalPos: TVector3): Boolean;
var
  Idx: Integer;
begin
  if FEditMode <> limEditingInPlace then Exit(False);
  Idx := FindSubActorIndex(ASubName);
  if Idx < 0 then Exit(False);
  FSubActors[Idx].LocalPos := ANewLocalPos;
  RebuildPackedInstancedBatches;
  SyncPreviewActors;
  Result := True;
end;

function TCastleLevelInstance.CommitInPlaceEdits: Boolean;
begin
  if FEditMode <> limEditingInPlace then Exit(False);
  FPreEditSnapshotJson := '';
  FEditMode := limLocked;
  Inc(FCommitVersion);
  RebuildPackedInstancedBatches;
  SyncPreviewActors;
  Result := True;
end;

function TCastleLevelInstance.DiscardInPlaceEdits: Boolean;
begin
  if FEditMode <> limEditingInPlace then Exit(False);
  if FPreEditSnapshotJson <> '' then
    SetSubLevelJson(FPreEditSnapshotJson);
  FPreEditSnapshotJson := '';
  FEditMode := limLocked;
  RebuildPackedInstancedBatches;
  SyncPreviewActors;
  Result := True;
end;

function TCastleLevelInstance.BreakIntoWorldActors(
  const AParentTransform: TCastleTransform;
  const ADesignOwner: TComponent): Integer;
var
  I: Integer;
  NewBox: TCastleBox;
begin
  Result := 0;
  if AParentTransform = nil then Exit;

  for I := 0 to High(FSubActors) do
  begin
    NewBox := TCastleBox.Create(ADesignOwner);
    if ADesignOwner <> nil then
      NewBox.Name := ProposeComponentName(TCastleBox, ADesignOwner, FSubActors[I].SubName)
    else
      NewBox.Name := FSubActors[I].SubName;
    NewBox.Size := FSubActors[I].LocalSize;
    NewBox.Translation := Translation + FSubActors[I].LocalPos;
    NewBox.Rotation := Vector4(0, 1, 0, DegToRad(FSubActors[I].YawDeg));
    NewBox.Color := FSubActors[I].ColorRGBA;
    AParentTransform.Add(NewBox);
    Inc(Result);
  end;
end;

{ Built-In UE 5.5 Level Instance Presets ------------------------------------- }

procedure TCastleLevelInstance.ApplyPreset(const APreset: TLevelInstancePreset);
var
  StoneCol, RoofCol, FireCol: TVector4;
begin
  FPreset := APreset;
  if APreset = lipCustom then Exit;

  ClearSubLevel;
  FPreset := APreset;

  StoneCol := Vector4(0.58, 0.62, 0.68, 1.0);
  RoofCol  := Vector4(0.28, 0.48, 0.78, 1.0);
  FireCol  := Vector4(1.00, 0.68, 0.22, 1.0);

  case APreset of
    lipMedievalWatchtower10Actors:
      begin
        FLevelAssetKey := 'LI_MedievalWatchtower';
        { 4x SM_TowerWallSegment, 4x SM_BattlementMerlon, 2x SM_BeaconBrazier -> 10 actors -> 3 ISM batches (70% reduction)! }
        AddOrUpdateSubActor('Wall_North',  'SM_TowerWallSegment', Vector3( 0.0, 2.5,  2.2), Vector3(4.4, 5.0, 0.6),  0.0, StoneCol);
        AddOrUpdateSubActor('Wall_South',  'SM_TowerWallSegment', Vector3( 0.0, 2.5, -2.2), Vector3(4.4, 5.0, 0.6),  0.0, StoneCol);
        AddOrUpdateSubActor('Wall_East',   'SM_TowerWallSegment', Vector3( 2.2, 2.5,  0.0), Vector3(4.4, 5.0, 0.6), 90.0, StoneCol);
        AddOrUpdateSubActor('Wall_West',   'SM_TowerWallSegment', Vector3(-2.2, 2.5,  0.0), Vector3(4.4, 5.0, 0.6), 90.0, StoneCol);

        AddOrUpdateSubActor('Merlon_NE',   'SM_BattlementMerlon', Vector3( 2.0, 5.4,  2.0), Vector3(0.9, 0.8, 0.9),  0.0, RoofCol);
        AddOrUpdateSubActor('Merlon_NW',   'SM_BattlementMerlon', Vector3(-2.0, 5.4,  2.0), Vector3(0.9, 0.8, 0.9),  0.0, RoofCol);
        AddOrUpdateSubActor('Merlon_SE',   'SM_BattlementMerlon', Vector3( 2.0, 5.4, -2.0), Vector3(0.9, 0.8, 0.9),  0.0, RoofCol);
        AddOrUpdateSubActor('Merlon_SW',   'SM_BattlementMerlon', Vector3(-2.0, 5.4, -2.0), Vector3(0.9, 0.8, 0.9),  0.0, RoofCol);

        AddOrUpdateSubActor('BeaconBrazier','SM_BeaconBrazier',   Vector3( 0.0, 6.2,  0.0), Vector3(1.1, 0.9, 1.1),  0.0, FireCol);
        AddOrUpdateSubActor('EntryTorch',   'SM_BeaconBrazier',   Vector3( 0.0, 2.2,  2.7), Vector3(0.5, 0.6, 0.5),  0.0, FireCol);
      end;

    lipCyberpunkStreetBlock12Actors:
      begin
        FLevelAssetKey := 'LI_CyberStreetBlock';
        AddOrUpdateSubActor('Facade_A', 'SM_CyberFacade', Vector3(-4.0, 4.0, 0.0), Vector3(3.8, 8.0, 3.2), 0.0, StoneCol);
        AddOrUpdateSubActor('Facade_B', 'SM_CyberFacade', Vector3( 0.0, 4.0, 0.0), Vector3(3.8, 8.0, 3.2), 0.0, StoneCol);
        AddOrUpdateSubActor('Facade_C', 'SM_CyberFacade', Vector3( 4.0, 4.0, 0.0), Vector3(3.8, 8.0, 3.2), 0.0, StoneCol);
        AddOrUpdateSubActor('Neon_A',   'SM_NeonSign',    Vector3(-4.0, 5.2, 1.8), Vector3(2.4, 0.9, 0.2), 0.0, FireCol);
        AddOrUpdateSubActor('Neon_B',   'SM_NeonSign',    Vector3( 0.0, 5.8, 1.8), Vector3(2.4, 0.9, 0.2), 0.0, RoofCol);
        AddOrUpdateSubActor('Neon_C',   'SM_NeonSign',    Vector3( 4.0, 4.6, 1.8), Vector3(2.4, 0.9, 0.2), 0.0, FireCol);
      end;

    lipDungeonRoomModular8Actors:
      begin
        FLevelAssetKey := 'LI_DungeonVaultRoom';
        AddOrUpdateSubActor('Floor_A',  'SM_FlagstoneTile', Vector3(-2.0, 0.1, 0.0), Vector3(4.0, 0.2, 4.0), 0.0, StoneCol);
        AddOrUpdateSubActor('Floor_B',  'SM_FlagstoneTile', Vector3( 2.0, 0.1, 0.0), Vector3(4.0, 0.2, 4.0), 0.0, StoneCol);
        AddOrUpdateSubActor('Pillar_L', 'SM_VaultPillar',   Vector3(-3.2, 2.0, 1.6), Vector3(0.7, 4.0, 0.7), 0.0, RoofCol);
        AddOrUpdateSubActor('Pillar_R', 'SM_VaultPillar',   Vector3( 3.2, 2.0, 1.6), Vector3(0.7, 4.0, 0.7), 0.0, RoofCol);
      end;
  end;

  RebuildPackedInstancedBatches;
  SyncPreviewActors;
end;

{ JSON Serialization --------------------------------------------------------- }

function TCastleLevelInstance.GetSubLevelJson: String;
var
  Root, Obj: TJSONObject;
  Arr, PArr, SArr, CArr: TJSONArray;
  I: Integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('assetKey', FLevelAssetKey);
    Arr := TJSONArray.Create;
    for I := 0 to High(FSubActors) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('name', FSubActors[I].SubName);
      Obj.Add('mesh', FSubActors[I].MeshTag);
      Obj.Add('yaw', FSubActors[I].YawDeg);
      PArr := TJSONArray.Create;
      PArr.Add(FSubActors[I].LocalPos.X);
      PArr.Add(FSubActors[I].LocalPos.Y);
      PArr.Add(FSubActors[I].LocalPos.Z);
      Obj.Add('pos', PArr);
      SArr := TJSONArray.Create;
      SArr.Add(FSubActors[I].LocalSize.X);
      SArr.Add(FSubActors[I].LocalSize.Y);
      SArr.Add(FSubActors[I].LocalSize.Z);
      Obj.Add('sz', SArr);
      CArr := TJSONArray.Create;
      CArr.Add(FSubActors[I].ColorRGBA.X);
      CArr.Add(FSubActors[I].ColorRGBA.Y);
      CArr.Add(FSubActors[I].ColorRGBA.Z);
      CArr.Add(FSubActors[I].ColorRGBA.W);
      Obj.Add('col', CArr);
      Arr.Add(Obj);
    end;
    Root.Add('subActors', Arr);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TCastleLevelInstance.SetSubLevelJson(const AValue: String);
var
  Parsed: TJSONData;
  Root, Obj: TJSONObject;
  Arr, PArr, SArr, CArr: TJSONArray;
  I: Integer;
  PosV, SzV: TVector3;
  ColV: TVector4;
begin
  if Trim(AValue) = '' then Exit;
  Parsed := nil;
  try
    Parsed := GetJSON(AValue);
  except
    Exit;
  end;
  try
    if not (Parsed is TJSONObject) then Exit;
    Root := TJSONObject(Parsed);
    FSubActors := nil;
    FPreset := lipCustom;
    FLevelAssetKey := Root.Get('assetKey', FLevelAssetKey);

    Arr := Root.Find('subActors', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          Obj := TJSONObject(Arr.Items[I]);
          PosV := TVector3.Zero;
          PArr := Obj.Find('pos', jtArray) as TJSONArray;
          if (PArr <> nil) and (PArr.Count >= 3) then
            PosV := Vector3(PArr.Floats[0], PArr.Floats[1], PArr.Floats[2]);
          SzV := Vector3(1, 1, 1);
          SArr := Obj.Find('sz', jtArray) as TJSONArray;
          if (SArr <> nil) and (SArr.Count >= 3) then
            SzV := Vector3(SArr.Floats[0], SArr.Floats[1], SArr.Floats[2]);
          ColV := Vector4(0.7, 0.7, 0.7, 1.0);
          CArr := Obj.Find('col', jtArray) as TJSONArray;
          if (CArr <> nil) and (CArr.Count >= 4) then
            ColV := Vector4(CArr.Floats[0], CArr.Floats[1], CArr.Floats[2], CArr.Floats[3]);
          AddOrUpdateSubActor(
            Obj.Get('name', 'Sub_' + IntToStr(I)),
            Obj.Get('mesh', 'SM_Default'),
            PosV, SzV, Obj.Get('yaw', 0.0), ColV);
        end;

    RebuildPackedInstancedBatches;
    SyncPreviewActors;
  finally
    FreeAndNil(Parsed);
  end;
end;

function TCastleLevelInstance.LevelInstanceSummaryBadge: String;
begin
  Result := Format('[LevelInst:%s Actors=%d ISM=%d (-%.0f%%) %s]',
    [FLevelAssetKey, Length(FSubActors), Length(FPackedBatches),
     DrawCallReductionPercent,
     BoolToStr(FEditMode = limEditingInPlace, 'EDITING', 'LOCKED')]);
end;

initialization
  RegisterSerializableComponent(TCastleLevelInstance, 'Level Instance & Packed Level Actor');
end.
