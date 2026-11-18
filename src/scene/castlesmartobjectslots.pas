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

{ Multi-Slot SmartObject Definition with Claim/Use/Release Lifecycle, Per-Slot
  Cooldowns, Hierarchical GameplayTag Gates & FIFO Wait-Queue Promotion
  (Phase 368 — UE 6.0+ USmartObjectDefinition Parity). }
unit CastleSmartObjectSlots;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Per-slot reservation lifecycle state. }
  TSmartSlotState = (
    sssFreeAvailable,
    sssClaimedApproach,
    sssInUseActive,
    sssCoolingDown,
    sssDisabledLocked
  );

  { Built-in multi-slot SmartObject station archetypes. }
  TSmartMultiSlotPreset = (
    smspCustom,
    smspTavernFourSeatTable,
    smspBlacksmithDualForgeAnvil,
    smspSiegeBallistaCrewPair
  );

  { Individual interaction docking slot on a SmartObject. }
  TSmartObjectSlotEntry = record
    SlotId: String;
    LocalOffset: TVector3;
    FacingYawDeg: Single;
    RequiredUserTag: String;
    CooldownDurationSec: Single;
    RemainingCooldownSec: Single;
    State: TSmartSlotState;
    ActiveUserId: String;
  end;

  { FIFO queued agent waiting for a compatible slot to finish cooldown. }
  TSmartObjectWaiter = record
    UserId: String;
    UserTagsCsv: String;
  end;

  { Multi-slot interactive station matching Unreal Engine 6.0+ USmartObjectDefinition
    with GameplayTag role filtering, per-slot cooldowns, and FIFO wait-queue promotion. }
  TCastleMultiSlotSmartObject = class(TCastleTransform)
  private
    FPreset: TSmartMultiSlotPreset;
    FDefaultSlotCooldownSec: Single;
    FMaxWaitQueueCapacity: Integer;
    FShowSlotMarkersMesh: Boolean;
    FSlots: array of TSmartObjectSlotEntry;
    FWaitQueue: array of TSmartObjectWaiter;
    FTotalPromotions: Integer;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TSmartMultiSlotPreset);
    procedure SetDefaultSlotCooldownSec(const AValue: Single);
    procedure SetMaxWaitQueueCapacity(const AValue: Integer);
    procedure SetShowSlotMarkersMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure ApplyPresetStation(const APreset: TSmartMultiSlotPreset);
    class function UserTagsSatisfyRequirement(const AUserTagsCsv, ARequiredTag: String): Boolean;
    function PromoteWaitingAgentsInternal: Integer;
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ClearSlotsAndQueue;
    function AddInteractionSlot(const ASlotId: String; const ALocalOffset: TVector3;
      const AFacingYawDeg: Single; const ARequiredUserTag: String = '';
      const ACooldownSec: Single = -1.0): Integer;
    function RequestClaimOrEnqueue(const AUserId, AUserTagsCsv: String;
      out OutSlotIndex: Integer; out OutStatusReason: String): Boolean;
    function BeginUsingClaimedSlot(const AUserId: String): Boolean;
    function ReleaseSlotAndStartCooldown(const AUserId: String): Boolean;
    function StepSlotsAndPromoteQueue(const Dt: Single): Integer;
    function GetSlotWorldPose(const ASlotIndex: Integer;
      out OutWorldPos, OutWorldForward: TVector3): Boolean;
    function SlotCount: Integer;
    function FreeSlotCount: Integer;
    function WaitQueueCount: Integer;
    function GetSlot(const AIndex: Integer): TSmartObjectSlotEntry;
    function GetWaiter(const AIndex: Integer): TSmartObjectWaiter;
    procedure RebuildSlotMarkersMesh;
    function SmartObjectSummaryBadge: String;
    property TotalPromotions: Integer read FTotalPromotions;
  published
    property Preset: TSmartMultiSlotPreset read FPreset write SetPreset default smspTavernFourSeatTable;
    property DefaultSlotCooldownSec: Single read FDefaultSlotCooldownSec write SetDefaultSlotCooldownSec {$ifdef FPC}default 4.0{$endif};
    property MaxWaitQueueCapacity: Integer read FMaxWaitQueueCapacity write SetMaxWaitQueueCapacity default 8;
    property ShowSlotMarkersMesh: Boolean read FShowSlotMarkersMesh write SetShowSlotMarkersMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function SmartMultiSlotPresetToString(const APreset: TSmartMultiSlotPreset): String;
function SmartSlotStateToString(const AState: TSmartSlotState): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions;

function SmartMultiSlotPresetToString(const APreset: TSmartMultiSlotPreset): String;
begin
  case APreset of
    smspCustom: Result := 'Custom Multi-Slot SmartObject';
    smspTavernFourSeatTable: Result := 'Tavern 4-Seat Feast Table (Any Villager)';
    smspBlacksmithDualForgeAnvil: Result := 'Blacksmith Forge (Master Anvil + Apprentice Bellows)';
    smspSiegeBallistaCrewPair: Result := 'Siege Ballista Crew (Gunner + Loader)';
  end;
end;

function SmartSlotStateToString(const AState: TSmartSlotState): String;
begin
  case AState of
    sssFreeAvailable: Result := 'FREE';
    sssClaimedApproach: Result := 'CLAIMED';
    sssInUseActive: Result := 'IN_USE';
    sssCoolingDown: Result := 'COOLDOWN';
    sssDisabledLocked: Result := 'DISABLED';
  end;
end;

{ TCastleMultiSlotSmartObject ------------------------------------------------- }

constructor TCastleMultiSlotSmartObject.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDefaultSlotCooldownSec := 4.0;
  FMaxWaitQueueCapacity := 8;
  FShowSlotMarkersMesh := True;
  FTotalPromotions := 0;
  ApplyPresetStation(smspTavernFourSeatTable);
  RebuildSlotMarkersMesh;
end;

destructor TCastleMultiSlotSmartObject.Destroy;
begin
  ClearTransientScene;
  inherited Destroy;
end;

procedure TCastleMultiSlotSmartObject.ApplyPresetStation(const APreset: TSmartMultiSlotPreset);
begin
  SetLength(FSlots, 0);
  SetLength(FWaitQueue, 0);
  FTotalPromotions := 0;
  case APreset of
    smspTavernFourSeatTable, smspCustom:
      begin
        FDefaultSlotCooldownSec := 4.0;
        AddInteractionSlot('Seat_North', Vector3( 0.0, 0.0, -1.35),   0.0, '', 4.0);
        AddInteractionSlot('Seat_South', Vector3( 0.0, 0.0,  1.35), 180.0, '', 4.0);
        AddInteractionSlot('Seat_West',  Vector3(-1.35, 0.0, 0.0),   90.0, '', 4.0);
        AddInteractionSlot('Seat_East',  Vector3( 1.35, 0.0, 0.0),  -90.0, '', 4.0);
        FPreset := APreset;
      end;
    smspBlacksmithDualForgeAnvil:
      begin
        FDefaultSlotCooldownSec := 5.0;
        AddInteractionSlot('Master_Anvil', Vector3(-0.95, 0.0, 0.85), 180.0, 'Role.Blacksmith', 5.0);
        AddInteractionSlot('Forge_Bellows', Vector3( 0.95, 0.0, 0.85), 180.0, 'Role.Apprentice', 3.0);
        FPreset := smspBlacksmithDualForgeAnvil;
      end;
    smspSiegeBallistaCrewPair:
      begin
        FDefaultSlotCooldownSec := 6.0;
        AddInteractionSlot('Ballista_Gunner', Vector3(-0.65, 0.0, 1.40), 0.0, 'Role.Artillery', 6.0);
        AddInteractionSlot('Ballista_WinchLoader', Vector3(0.65, 0.0, 1.40), 0.0, 'Role.Artillery', 6.0);
        FPreset := smspSiegeBallistaCrewPair;
      end;
  end;
end;

procedure TCastleMultiSlotSmartObject.SetPreset(const AValue: TSmartMultiSlotPreset);
begin
  if FPreset = AValue then Exit;
  FPreset := AValue;
  if AValue <> smspCustom then
  begin
    ApplyPresetStation(AValue);
    RebuildSlotMarkersMesh;
  end;
end;

procedure TCastleMultiSlotSmartObject.SetDefaultSlotCooldownSec(const AValue: Single);
var
  V: Single;
begin
  V := EnsureRange(AValue, 0.0, 120.0);
  if SameValue(FDefaultSlotCooldownSec, V, 1e-4) then Exit;
  FDefaultSlotCooldownSec := V;
  FPreset := smspCustom;
end;

procedure TCastleMultiSlotSmartObject.SetMaxWaitQueueCapacity(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 0, 64);
  if FMaxWaitQueueCapacity = V then Exit;
  FMaxWaitQueueCapacity := V;
end;

procedure TCastleMultiSlotSmartObject.SetShowSlotMarkersMesh(const AValue: Boolean);
begin
  if FShowSlotMarkersMesh = AValue then Exit;
  FShowSlotMarkersMesh := AValue;
  if not FShowSlotMarkersMesh then
    ClearTransientScene
  else
    RebuildSlotMarkersMesh;
end;

procedure TCastleMultiSlotSmartObject.ClearSlotsAndQueue;
begin
  SetLength(FSlots, 0);
  SetLength(FWaitQueue, 0);
  FPreset := smspCustom;
  RebuildSlotMarkersMesh;
end;

function TCastleMultiSlotSmartObject.AddInteractionSlot(
  const ASlotId: String; const ALocalOffset: TVector3;
  const AFacingYawDeg: Single; const ARequiredUserTag: String;
  const ACooldownSec: Single): Integer;
begin
  Result := Length(FSlots);
  SetLength(FSlots, Result + 1);
  FSlots[Result].SlotId := ASlotId;
  FSlots[Result].LocalOffset := ALocalOffset;
  FSlots[Result].FacingYawDeg := AFacingYawDeg;
  FSlots[Result].RequiredUserTag := Trim(ARequiredUserTag);
  if ACooldownSec >= 0.0 then
    FSlots[Result].CooldownDurationSec := ACooldownSec
  else
    FSlots[Result].CooldownDurationSec := FDefaultSlotCooldownSec;
  FSlots[Result].RemainingCooldownSec := 0.0;
  FSlots[Result].State := sssFreeAvailable;
  FSlots[Result].ActiveUserId := '';
  FPreset := smspCustom;
end;

class function TCastleMultiSlotSmartObject.UserTagsSatisfyRequirement(
  const AUserTagsCsv, ARequiredTag: String): Boolean;
var
  Req, Cand: String;
  Tags: TStringList;
  I, ReqLen: Integer;
begin
  Req := LowerCase(Trim(ARequiredTag));
  if Req = '' then Exit(True);
  ReqLen := Length(Req);

  Tags := TStringList.Create;
  try
    ExtractStrings([',', ';', ' '], [], PChar(AUserTagsCsv), Tags);
    for I := 0 to Tags.Count - 1 do
    begin
      Cand := LowerCase(Trim(Tags[I]));
      if (Cand = Req) or
         ((Length(Cand) > ReqLen) and (Copy(Cand, 1, ReqLen + 1) = Req + '.')) then
        Exit(True);
    end;
    Result := False;
  finally
    FreeAndNil(Tags);
  end;
end;

function TCastleMultiSlotSmartObject.RequestClaimOrEnqueue(
  const AUserId, AUserTagsCsv: String;
  out OutSlotIndex: Integer; out OutStatusReason: String): Boolean;
var
  I, N: Integer;
  AnyCompatibleSlotExists: Boolean;
begin
  OutSlotIndex := -1;
  OutStatusReason := '';
  if Trim(AUserId) = '' then
  begin
    OutStatusReason := 'INVALID_EMPTY_USER';
    Exit(False);
  end;

  { 1. Idempotent check if user already holds a slot }
  for I := 0 to High(FSlots) do
    if SameText(FSlots[I].ActiveUserId, AUserId) and
       (FSlots[I].State in [sssClaimedApproach, sssInUseActive]) then
    begin
      OutSlotIndex := I;
      OutStatusReason := 'ALREADY_HOLDING_SLOT';
      Exit(True);
    end;

  { 2. Scan free compatible slots }
  AnyCompatibleSlotExists := False;
  for I := 0 to High(FSlots) do
    if FSlots[I].State <> sssDisabledLocked then
      if UserTagsSatisfyRequirement(AUserTagsCsv, FSlots[I].RequiredUserTag) then
      begin
        AnyCompatibleSlotExists := True;
        if FSlots[I].State = sssFreeAvailable then
        begin
          FSlots[I].State := sssClaimedApproach;
          FSlots[I].ActiveUserId := AUserId;
          OutSlotIndex := I;
          OutStatusReason := 'CLAIMED_SLOT';
          RebuildSlotMarkersMesh;
          Exit(True);
        end;
      end;

  if not AnyCompatibleSlotExists then
  begin
    OutStatusReason := 'REJECTED_MISSING_REQUIRED_TAG';
    Exit(False);
  end;

  { 3. Compatible slots exist but all are busy/cooling -> enqueue into FIFO wait queue }
  for I := 0 to High(FWaitQueue) do
    if SameText(FWaitQueue[I].UserId, AUserId) then
    begin
      OutStatusReason := 'QUEUED_WAITING_FIFO';
      Exit(False);
    end;

  if Length(FWaitQueue) >= FMaxWaitQueueCapacity then
  begin
    OutStatusReason := 'REJECTED_WAIT_QUEUE_FULL';
    Exit(False);
  end;

  N := Length(FWaitQueue);
  SetLength(FWaitQueue, N + 1);
  FWaitQueue[N].UserId := AUserId;
  FWaitQueue[N].UserTagsCsv := AUserTagsCsv;
  OutStatusReason := 'QUEUED_WAITING_FIFO';
  Result := False;
end;

function TCastleMultiSlotSmartObject.BeginUsingClaimedSlot(const AUserId: String): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FSlots) do
    if SameText(FSlots[I].ActiveUserId, AUserId) and
       (FSlots[I].State in [sssClaimedApproach, sssInUseActive]) then
    begin
      FSlots[I].State := sssInUseActive;
      RebuildSlotMarkersMesh;
      Exit(True);
    end;
  Result := False;
end;

function TCastleMultiSlotSmartObject.PromoteWaitingAgentsInternal: Integer;
var
  SIdx, QIdx, ShiftIdx: Integer;
begin
  Result := 0;
  for SIdx := 0 to High(FSlots) do
    if FSlots[SIdx].State = sssFreeAvailable then
    begin
      for QIdx := 0 to High(FWaitQueue) do
        if UserTagsSatisfyRequirement(FWaitQueue[QIdx].UserTagsCsv, FSlots[SIdx].RequiredUserTag) then
        begin
          FSlots[SIdx].State := sssClaimedApproach;
          FSlots[SIdx].ActiveUserId := FWaitQueue[QIdx].UserId;
          for ShiftIdx := QIdx to High(FWaitQueue) - 1 do
            FWaitQueue[ShiftIdx] := FWaitQueue[ShiftIdx + 1];
          SetLength(FWaitQueue, Length(FWaitQueue) - 1);
          Inc(Result);
          Inc(FTotalPromotions);
          Break;
        end;
    end;
end;

function TCastleMultiSlotSmartObject.ReleaseSlotAndStartCooldown(const AUserId: String): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(FSlots) do
    if SameText(FSlots[I].ActiveUserId, AUserId) and
       (FSlots[I].State in [sssClaimedApproach, sssInUseActive]) then
    begin
      FSlots[I].ActiveUserId := '';
      if FSlots[I].CooldownDurationSec > 0.001 then
      begin
        FSlots[I].State := sssCoolingDown;
        FSlots[I].RemainingCooldownSec := FSlots[I].CooldownDurationSec;
      end else
      begin
        FSlots[I].State := sssFreeAvailable;
        FSlots[I].RemainingCooldownSec := 0.0;
        PromoteWaitingAgentsInternal;
      end;
      RebuildSlotMarkersMesh;
      Exit(True);
    end;
end;

function TCastleMultiSlotSmartObject.StepSlotsAndPromoteQueue(const Dt: Single): Integer;
var
  I: Integer;
begin
  if Dt > 0.0 then
    for I := 0 to High(FSlots) do
      if FSlots[I].State = sssCoolingDown then
      begin
        FSlots[I].RemainingCooldownSec := FSlots[I].RemainingCooldownSec - Dt;
        if FSlots[I].RemainingCooldownSec <= 0.0 then
        begin
          FSlots[I].RemainingCooldownSec := 0.0;
          FSlots[I].State := sssFreeAvailable;
        end;
      end;

  Result := PromoteWaitingAgentsInternal;
  RebuildSlotMarkersMesh;
end;

function TCastleMultiSlotSmartObject.GetSlotWorldPose(const ASlotIndex: Integer;
  out OutWorldPos, OutWorldForward: TVector3): Boolean;
var
  YawRad: Single;
  FwdLocal: TVector3;
begin
  Result := (ASlotIndex >= 0) and (ASlotIndex < Length(FSlots));
  if not Result then
  begin
    OutWorldPos := TVector3.Zero;
    OutWorldForward := Vector3(0, 0, -1);
    Exit;
  end;

  YawRad := DegToRad(FSlots[ASlotIndex].FacingYawDeg);
  FwdLocal := Vector3(Sin(YawRad), 0.0, -Cos(YawRad));
  if Parent <> nil then
  begin
    OutWorldPos := LocalToWorld(FSlots[ASlotIndex].LocalOffset);
    OutWorldForward := LocalToWorldDirection(FwdLocal).Normalize;
  end else
  begin
    OutWorldPos := Translation + FSlots[ASlotIndex].LocalOffset;
    OutWorldForward := FwdLocal.Normalize;
  end;
end;

function TCastleMultiSlotSmartObject.SlotCount: Integer;
begin
  Result := Length(FSlots);
end;

function TCastleMultiSlotSmartObject.FreeSlotCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSlots) do
    if FSlots[I].State = sssFreeAvailable then
      Inc(Result);
end;

function TCastleMultiSlotSmartObject.WaitQueueCount: Integer;
begin
  Result := Length(FWaitQueue);
end;

function TCastleMultiSlotSmartObject.GetSlot(const AIndex: Integer): TSmartObjectSlotEntry;
begin
  if (AIndex >= 0) and (AIndex < Length(FSlots)) then
    Result := FSlots[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastleMultiSlotSmartObject.GetWaiter(const AIndex: Integer): TSmartObjectWaiter;
begin
  if (AIndex >= 0) and (AIndex < Length(FWaitQueue)) then
    Result := FWaitQueue[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleMultiSlotSmartObject.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientSmartSlotMarkers';
  FTransientScene.SetTransient;
  FTransientScene.Pickable := False;
  FTransientScene.Collides := False;
  FTransientScene.RenderOptions.Lighting := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  TriSet := TTriangleSetNode.Create;
  TriSet.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FColorNode := TColorNode.Create;
  TriSet.Coord := FCoordNode;
  TriSet.Color := FColorNode;
  Shape.Geometry := TriSet;
  Root.AddChildren(Shape);
  FTransientScene.Load(Root, True);
  Add(FTransientScene);
end;

procedure TCastleMultiSlotSmartObject.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleMultiSlotSmartObject.RebuildSlotMarkersMesh;
var
  Verts, Cols: TVector3List;
  I: Integer;
  P, Fwd, Side, C: TVector3;
  YawRad: Single;
begin
  if (not FShowSlotMarkersMesh) or (Length(FSlots) = 0) then
  begin
    ClearTransientScene;
    Exit;
  end;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    for I := 0 to High(FSlots) do
    begin
      P := FSlots[I].LocalOffset + Vector3(0.0, 0.08, 0.0);
      YawRad := DegToRad(FSlots[I].FacingYawDeg);
      Fwd := Vector3(Sin(YawRad), 0.0, -Cos(YawRad)) * 0.48;
      Side := Vector3(Cos(YawRad), 0.0, Sin(YawRad)) * 0.34;
      case FSlots[I].State of
        sssFreeAvailable:   C := Vector3(0.22, 0.88, 0.42);
        sssClaimedApproach: C := Vector3(0.22, 0.78, 0.98);
        sssInUseActive:     C := Vector3(0.98, 0.82, 0.18);
        sssCoolingDown:     C := Vector3(0.96, 0.44, 0.18);
        sssDisabledLocked:  C := Vector3(0.45, 0.45, 0.50);
      end;

      Verts.Add(P - Side);
      Verts.Add(P + Side);
      Verts.Add(P + Fwd);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
    end;

    EnsureTransientScene;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Cols);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Cols);
    FreeAndNil(Verts);
  end;
end;

function TCastleMultiSlotSmartObject.GetConfigJson: String;
var
  RootObj, SObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('preset', Ord(FPreset));
    RootObj.Add('defCooldown', FDefaultSlotCooldownSec);
    RootObj.Add('maxQueue', FMaxWaitQueueCapacity);
    Arr := TJSONArray.Create;
    for I := 0 to High(FSlots) do
    begin
      SObj := TJSONObject.Create;
      SObj.Add('id', FSlots[I].SlotId);
      SObj.Add('x', FSlots[I].LocalOffset.X);
      SObj.Add('y', FSlots[I].LocalOffset.Y);
      SObj.Add('z', FSlots[I].LocalOffset.Z);
      SObj.Add('yaw', FSlots[I].FacingYawDeg);
      SObj.Add('tag', FSlots[I].RequiredUserTag);
      SObj.Add('cd', FSlots[I].CooldownDurationSec);
      Arr.Add(SObj);
    end;
    RootObj.Add('slots', Arr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleMultiSlotSmartObject.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj, SObj: TJSONObject;
  Arr: TJSONArray;
  I, PresetOrd: Integer;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FDefaultSlotCooldownSec := EnsureRange(RootObj.Get('defCooldown', FDefaultSlotCooldownSec), 0.0, 120.0);
      FMaxWaitQueueCapacity := EnsureRange(RootObj.Get('maxQueue', FMaxWaitQueueCapacity), 0, 64);
      Arr := RootObj.Find('slots', jtArray) as TJSONArray;
      if (Arr <> nil) and (Arr.Count > 0) then
      begin
        SetLength(FSlots, Arr.Count);
        SetLength(FWaitQueue, 0);
        for I := 0 to Arr.Count - 1 do
          if Arr.Items[I] is TJSONObject then
          begin
            SObj := TJSONObject(Arr.Items[I]);
            FSlots[I].SlotId := SObj.Get('id', Format('Slot_%d', [I]));
            FSlots[I].LocalOffset := Vector3(SObj.Get('x', 0.0), SObj.Get('y', 0.0), SObj.Get('z', 0.0));
            FSlots[I].FacingYawDeg := SObj.Get('yaw', 0.0);
            FSlots[I].RequiredUserTag := SObj.Get('tag', '');
            FSlots[I].CooldownDurationSec := Max(0.0, SObj.Get('cd', FDefaultSlotCooldownSec));
            FSlots[I].RemainingCooldownSec := 0.0;
            FSlots[I].State := sssFreeAvailable;
            FSlots[I].ActiveUserId := '';
          end;
      end;
      PresetOrd := RootObj.Get('preset', Ord(FPreset));
      if (PresetOrd >= Ord(Low(TSmartMultiSlotPreset))) and
         (PresetOrd <= Ord(High(TSmartMultiSlotPreset))) then
        FPreset := TSmartMultiSlotPreset(PresetOrd);
      RebuildSlotMarkersMesh;
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleMultiSlotSmartObject.SmartObjectSummaryBadge: String;
begin
  Result := Format('[SmartSlots:%d/%d free Q=%d]', [
    FreeSlotCount,
    SlotCount,
    WaitQueueCount]);
end;

initialization
  RegisterSerializableComponent(TCastleMultiSlotSmartObject, ['AI & Gameplay', 'Multi-Slot SmartObject & Queue']);
end.
