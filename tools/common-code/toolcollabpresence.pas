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

{ Multi-User Collaborative Presence Locks, Ancestor/Descendant Subtree
  Conflict Broker & Lease Heartbeat Manager (Phase 366 — UE 6.0+ Multi-User
  Editing / ConcertSync Parity). }
unit ToolCollabPresence;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleUIControls,
  CastleColors;

type
  { Exclusive subtree edit reservation lease held by a collaborator or AI agent. }
  TCollabSubtreeLock = record
    LockId: String;
    UserId: String;
    UserDisplayName: String;
    SubtreeRootName: String;
    AcquiredAtSec: Double;
    LeaseExpiresAtSec: Double;
    HeartbeatCount: Integer;
  end;

  { Live collaborator viewport presence cursor & selection state. }
  TCollabPresencePeer = record
    UserId: String;
    DisplayName: String;
    SelectedComponentName: String;
    CameraWorldPos: TVector3;
  end;

  { Multi-user / multi-agent subtree lock broker enforcing ancestor/descendant
    hierarchy exclusion, idempotent owner lease renewal, and stale-lease expiry. }
  TCollabPresenceBroker = class
  private
    FLocks: array of TCollabSubtreeLock;
    FPeers: array of TCollabPresencePeer;
    FCurrentTimeSec: Double;
    FNextLockSeq: Integer;
    class function FindComponentInDesign(const RootComp: TComponent;
      const AName: String): TComponent;
    class function IsDescendantInHierarchy(const PotentialChild, PotentialAncestor: TComponent): Boolean;
  public
    constructor Create;
    procedure ResetAll;
    procedure AdvanceClockSeconds(const ADeltaSec: Double);
    function AcquireSubtreeLock(const RootComp: TComponent;
      const AUserId, ADisplayName, ASubtreeRootName: String;
      const ALeaseDurationSec: Double;
      out OutConflictReason: String): Boolean;
    function RenewHeartbeat(const AUserId, ASubtreeRootName: String;
      const ALeaseDurationSec: Double): Boolean;
    function ReleaseSubtreeLock(const AUserId, ASubtreeRootName: String): Boolean;
    function ExpireStaleLocks: Integer;
    procedure UpdatePeerPresence(const AUserId, ADisplayName, ASelectedCompName: String;
      const ACameraWorldPos: TVector3);
    function ActiveLockCount: Integer;
    function GetLock(const AIndex: Integer): TCollabSubtreeLock;
    function FindLockOnSubtree(const ASubtreeRootName: String;
      out OutLock: TCollabSubtreeLock): Boolean;
    function PeerCount: Integer;
    function GetPeer(const AIndex: Integer): TCollabPresencePeer;
    function ExportSessionJson: String;
    function ImportSessionJson(const AJson: String): Boolean;
    function GenerateCollabReport(const RootComp: TComponent): String;
    class function SharedBroker: TCollabPresenceBroker;
    class function FindViewport(const Root: TComponent): TCastleViewport;
    class function SpawnCollaborativeKeepDemo(const Root, DesignOwner: TComponent): Boolean;
    property CurrentTimeSec: Double read FCurrentTimeSec write FCurrentTimeSec;
  end;

implementation

uses fpjson, jsonparser, CastleComponentSerialize, ToolStudioHub;

var
  GSharedCollabBroker: TCollabPresenceBroker = nil;

{ TCollabPresenceBroker ------------------------------------------------------- }

constructor TCollabPresenceBroker.Create;
begin
  inherited Create;
  FCurrentTimeSec := 0.0;
  FNextLockSeq := 1;
end;

class function TCollabPresenceBroker.SharedBroker: TCollabPresenceBroker;
begin
  if GSharedCollabBroker = nil then
    GSharedCollabBroker := TCollabPresenceBroker.Create;
  Result := GSharedCollabBroker;
end;

procedure TCollabPresenceBroker.ResetAll;
begin
  SetLength(FLocks, 0);
  SetLength(FPeers, 0);
  FCurrentTimeSec := 0.0;
  FNextLockSeq := 1;
end;

procedure TCollabPresenceBroker.AdvanceClockSeconds(const ADeltaSec: Double);
begin
  if ADeltaSec > 0.0 then
    FCurrentTimeSec := FCurrentTimeSec + ADeltaSec;
end;

class function TCollabPresenceBroker.FindViewport(const Root: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if Root = nil then Exit;
  if Root is TCastleViewport then Exit(TCastleViewport(Root));
  for I := 0 to Root.ComponentCount - 1 do
  begin
    Result := FindViewport(Root.Components[I]);
    if Result <> nil then Exit;
  end;
end;

class function TCollabPresenceBroker.FindComponentInDesign(
  const RootComp: TComponent; const AName: String): TComponent;

  function WalkTransform(const T: TCastleTransform): TComponent;
  var
    J: Integer;
  begin
    Result := nil;
    if T = nil then Exit;
    if SameText(T.Name, AName) then Exit(T);
    for J := 0 to T.Count - 1 do
    begin
      Result := WalkTransform(T[J]);
      if Result <> nil then Exit;
    end;
  end;

  function WalkUi(const U: TCastleUserInterface): TComponent;
  var
    J: Integer;
  begin
    Result := nil;
    if U = nil then Exit;
    if SameText(U.Name, AName) then Exit(U);
    if U is TCastleViewport then
    begin
      Result := WalkTransform(TCastleViewport(U).Items);
      if Result <> nil then Exit;
    end;
    for J := 0 to U.ControlsCount - 1 do
    begin
      Result := WalkUi(U.Controls[J]);
      if Result <> nil then Exit;
    end;
  end;

var
  I: Integer;
begin
  Result := nil;
  if (RootComp = nil) or (Trim(AName) = '') then Exit;
  if SameText(RootComp.Name, AName) then Exit(RootComp);
  if RootComp is TCastleTransform then
  begin
    Result := WalkTransform(TCastleTransform(RootComp));
    if Result <> nil then Exit;
  end;
  if RootComp is TCastleUserInterface then
  begin
    Result := WalkUi(TCastleUserInterface(RootComp));
    if Result <> nil then Exit;
  end;
  if RootComp.Owner <> nil then
  begin
    Result := RootComp.Owner.FindComponent(AName);
    if Result <> nil then Exit;
  end;
  for I := 0 to RootComp.ComponentCount - 1 do
    if SameText(RootComp.Components[I].Name, AName) then
      Exit(RootComp.Components[I]);
end;

class function TCollabPresenceBroker.IsDescendantInHierarchy(
  const PotentialChild, PotentialAncestor: TComponent): Boolean;
var
  CurrT: TCastleTransform;
  CurrUi: TCastleUserInterface;
begin
  Result := False;
  if (PotentialChild = nil) or (PotentialAncestor = nil) then Exit;
  if PotentialChild = PotentialAncestor then Exit(True);

  if (PotentialChild is TCastleTransform) and (PotentialAncestor is TCastleTransform) then
  begin
    CurrT := TCastleTransform(PotentialChild).Parent;
    while CurrT <> nil do
    begin
      if CurrT = PotentialAncestor then Exit(True);
      CurrT := CurrT.Parent;
    end;
  end;

  if (PotentialChild is TCastleUserInterface) and (PotentialAncestor is TCastleUserInterface) then
  begin
    CurrUi := TCastleUserInterface(PotentialChild).Parent;
    while CurrUi <> nil do
    begin
      if CurrUi = PotentialAncestor then Exit(True);
      CurrUi := CurrUi.Parent;
    end;
  end;
end;

function TCollabPresenceBroker.AcquireSubtreeLock(const RootComp: TComponent;
  const AUserId, ADisplayName, ASubtreeRootName: String;
  const ALeaseDurationSec: Double;
  out OutConflictReason: String): Boolean;
var
  I, N: Integer;
  ReqComp, HeldComp: TComponent;
  EffLease: Double;
  Disp: String;
begin
  OutConflictReason := '';
  if (Trim(AUserId) = '') or (Trim(ASubtreeRootName) = '') then
  begin
    OutConflictReason := 'INVALID_EMPTY_USER_OR_SUBTREE';
    Exit(False);
  end;

  ExpireStaleLocks;
  EffLease := Max(1.0, ALeaseDurationSec);
  if Trim(ADisplayName) <> '' then Disp := ADisplayName else Disp := AUserId;
  ReqComp := FindComponentInDesign(RootComp, ASubtreeRootName);

  for I := 0 to High(FLocks) do
  begin
    if SameText(FLocks[I].UserId, AUserId) and
       SameText(FLocks[I].SubtreeRootName, ASubtreeRootName) then
    begin
      { Idempotent lease renewal by the existing lock owner }
      FLocks[I].LeaseExpiresAtSec := FCurrentTimeSec + EffLease;
      Inc(FLocks[I].HeartbeatCount);
      Exit(True);
    end;

    if not SameText(FLocks[I].UserId, AUserId) then
    begin
      if SameText(FLocks[I].SubtreeRootName, ASubtreeRootName) then
      begin
        OutConflictReason := Format('EXACT_LOCK_HELD_BY_%s_ON_%s', [
          FLocks[I].UserId, FLocks[I].SubtreeRootName]);
        Exit(False);
      end;

      HeldComp := FindComponentInDesign(RootComp, FLocks[I].SubtreeRootName);
      if (ReqComp <> nil) and (HeldComp <> nil) then
      begin
        if IsDescendantInHierarchy(ReqComp, HeldComp) then
        begin
          OutConflictReason := Format('ANCESTOR_SUBTREE_LOCKED_BY_%s_ON_%s', [
            FLocks[I].UserId, FLocks[I].SubtreeRootName]);
          Exit(False);
        end;
        if IsDescendantInHierarchy(HeldComp, ReqComp) then
        begin
          OutConflictReason := Format('DESCENDANT_SUBTREE_LOCKED_BY_%s_ON_%s', [
            FLocks[I].UserId, FLocks[I].SubtreeRootName]);
          Exit(False);
        end;
      end;
    end;
  end;

  N := Length(FLocks);
  SetLength(FLocks, N + 1);
  FLocks[N].LockId := Format('LOCK-%d', [FNextLockSeq]);
  Inc(FNextLockSeq);
  FLocks[N].UserId := AUserId;
  FLocks[N].UserDisplayName := Disp;
  FLocks[N].SubtreeRootName := ASubtreeRootName;
  FLocks[N].AcquiredAtSec := FCurrentTimeSec;
  FLocks[N].LeaseExpiresAtSec := FCurrentTimeSec + EffLease;
  FLocks[N].HeartbeatCount := 1;
  Result := True;
end;

function TCollabPresenceBroker.RenewHeartbeat(
  const AUserId, ASubtreeRootName: String;
  const ALeaseDurationSec: Double): Boolean;
var
  I: Integer;
begin
  ExpireStaleLocks;
  for I := 0 to High(FLocks) do
    if SameText(FLocks[I].UserId, AUserId) and
       SameText(FLocks[I].SubtreeRootName, ASubtreeRootName) then
    begin
      FLocks[I].LeaseExpiresAtSec := FCurrentTimeSec + Max(1.0, ALeaseDurationSec);
      Inc(FLocks[I].HeartbeatCount);
      Exit(True);
    end;
  Result := False;
end;

function TCollabPresenceBroker.ReleaseSubtreeLock(
  const AUserId, ASubtreeRootName: String): Boolean;
var
  I, J: Integer;
begin
  for I := 0 to High(FLocks) do
    if SameText(FLocks[I].UserId, AUserId) and
       SameText(FLocks[I].SubtreeRootName, ASubtreeRootName) then
    begin
      for J := I to High(FLocks) - 1 do
        FLocks[J] := FLocks[J + 1];
      SetLength(FLocks, Length(FLocks) - 1);
      Exit(True);
    end;
  Result := False;
end;

function TCollabPresenceBroker.ExpireStaleLocks: Integer;
var
  I, WriteIdx: Integer;
begin
  Result := 0;
  WriteIdx := 0;
  for I := 0 to High(FLocks) do
    if FCurrentTimeSec >= FLocks[I].LeaseExpiresAtSec then
      Inc(Result)
    else
    begin
      FLocks[WriteIdx] := FLocks[I];
      Inc(WriteIdx);
    end;
  SetLength(FLocks, WriteIdx);
end;

procedure TCollabPresenceBroker.UpdatePeerPresence(
  const AUserId, ADisplayName, ASelectedCompName: String;
  const ACameraWorldPos: TVector3);
var
  I, N: Integer;
begin
  for I := 0 to High(FPeers) do
    if SameText(FPeers[I].UserId, AUserId) then
    begin
      FPeers[I].DisplayName := ADisplayName;
      FPeers[I].SelectedComponentName := ASelectedCompName;
      FPeers[I].CameraWorldPos := ACameraWorldPos;
      Exit;
    end;
  N := Length(FPeers);
  SetLength(FPeers, N + 1);
  FPeers[N].UserId := AUserId;
  FPeers[N].DisplayName := ADisplayName;
  FPeers[N].SelectedComponentName := ASelectedCompName;
  FPeers[N].CameraWorldPos := ACameraWorldPos;
end;

function TCollabPresenceBroker.ActiveLockCount: Integer;
begin
  Result := Length(FLocks);
end;

function TCollabPresenceBroker.GetLock(const AIndex: Integer): TCollabSubtreeLock;
begin
  if (AIndex >= 0) and (AIndex < Length(FLocks)) then
    Result := FLocks[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCollabPresenceBroker.FindLockOnSubtree(const ASubtreeRootName: String;
  out OutLock: TCollabSubtreeLock): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FLocks) do
    if SameText(FLocks[I].SubtreeRootName, ASubtreeRootName) then
    begin
      OutLock := FLocks[I];
      Exit(True);
    end;
  FillChar(OutLock, SizeOf(OutLock), 0);
  Result := False;
end;

function TCollabPresenceBroker.PeerCount: Integer;
begin
  Result := Length(FPeers);
end;

function TCollabPresenceBroker.GetPeer(const AIndex: Integer): TCollabPresencePeer;
begin
  if (AIndex >= 0) and (AIndex < Length(FPeers)) then
    Result := FPeers[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCollabPresenceBroker.ExportSessionJson: String;
var
  RootObj, LObj, PObj: TJSONObject;
  LocksArr, PeersArr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('currentTimeSec', FCurrentTimeSec);
    LocksArr := TJSONArray.Create;
    for I := 0 to High(FLocks) do
    begin
      LObj := TJSONObject.Create;
      LObj.Add('id', FLocks[I].LockId);
      LObj.Add('user', FLocks[I].UserId);
      LObj.Add('display', FLocks[I].UserDisplayName);
      LObj.Add('subtree', FLocks[I].SubtreeRootName);
      LObj.Add('acquiredAt', FLocks[I].AcquiredAtSec);
      LObj.Add('expiresAt', FLocks[I].LeaseExpiresAtSec);
      LObj.Add('heartbeats', FLocks[I].HeartbeatCount);
      LocksArr.Add(LObj);
    end;
    RootObj.Add('locks', LocksArr);

    PeersArr := TJSONArray.Create;
    for I := 0 to High(FPeers) do
    begin
      PObj := TJSONObject.Create;
      PObj.Add('user', FPeers[I].UserId);
      PObj.Add('display', FPeers[I].DisplayName);
      PObj.Add('selected', FPeers[I].SelectedComponentName);
      PObj.Add('camX', FPeers[I].CameraWorldPos.X);
      PObj.Add('camY', FPeers[I].CameraWorldPos.Y);
      PObj.Add('camZ', FPeers[I].CameraWorldPos.Z);
      PeersArr.Add(PObj);
    end;
    RootObj.Add('peers', PeersArr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

function TCollabPresenceBroker.ImportSessionJson(const AJson: String): Boolean;
var
  Data: TJSONData;
  RootObj, LObj, PObj: TJSONObject;
  LocksArr, PeersArr: TJSONArray;
  I: Integer;
begin
  Result := False;
  if Trim(AJson) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AJson);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FCurrentTimeSec := RootObj.Get('currentTimeSec', 0.0);
      LocksArr := RootObj.Find('locks', jtArray) as TJSONArray;
      if LocksArr <> nil then
      begin
        SetLength(FLocks, LocksArr.Count);
        for I := 0 to LocksArr.Count - 1 do
          if LocksArr.Items[I] is TJSONObject then
          begin
            LObj := TJSONObject(LocksArr.Items[I]);
            FLocks[I].LockId := LObj.Get('id', Format('LOCK-%d', [I + 1]));
            FLocks[I].UserId := LObj.Get('user', '');
            FLocks[I].UserDisplayName := LObj.Get('display', '');
            FLocks[I].SubtreeRootName := LObj.Get('subtree', '');
            FLocks[I].AcquiredAtSec := LObj.Get('acquiredAt', 0.0);
            FLocks[I].LeaseExpiresAtSec := LObj.Get('expiresAt', 30.0);
            FLocks[I].HeartbeatCount := LObj.Get('heartbeats', 1);
          end;
      end;

      PeersArr := RootObj.Find('peers', jtArray) as TJSONArray;
      if PeersArr <> nil then
      begin
        SetLength(FPeers, PeersArr.Count);
        for I := 0 to PeersArr.Count - 1 do
          if PeersArr.Items[I] is TJSONObject then
          begin
            PObj := TJSONObject(PeersArr.Items[I]);
            FPeers[I].UserId := PObj.Get('user', '');
            FPeers[I].DisplayName := PObj.Get('display', '');
            FPeers[I].SelectedComponentName := PObj.Get('selected', '');
            FPeers[I].CameraWorldPos := Vector3(
              PObj.Get('camX', 0.0), PObj.Get('camY', 0.0), PObj.Get('camZ', 0.0));
          end;
      end;
      Result := True;
    end;
  except
    Result := False;
  end;
  FreeAndNil(Data);
end;

class function TCollabPresenceBroker.SpawnCollaborativeKeepDemo(
  const Root, DesignOwner: TComponent): Boolean;
var
  Vp: TCastleViewport;
  OwnerComp: TComponent;
  GateBox, HingeBox, SignBox, BellBox: TCastleBox;
begin
  Result := False;
  Vp := FindViewport(Root);
  if (Vp = nil) or (Vp.Items = nil) then Exit;
  if DesignOwner <> nil then
    OwnerComp := DesignOwner
  else
    OwnerComp := Root;

  GateBox := OwnerComp.FindComponent('CastleGate') as TCastleBox;
  if GateBox = nil then
  begin
    GateBox := TCastleBox.Create(OwnerComp);
    GateBox.Name := 'CastleGate';
    GateBox.Size := Vector3(4.0, 3.8, 0.6);
    GateBox.Translation := Vector3(-4.0, 1.9, 0.0);
    GateBox.Color := Vector4(0.64, 0.48, 0.30, 1.0);
    Vp.Items.Add(GateBox);

    HingeBox := TCastleBox.Create(OwnerComp);
    HingeBox.Name := 'GateHinge';
    HingeBox.Size := Vector3(0.45, 0.65, 0.75);
    HingeBox.Translation := Vector3(-1.85, 0.0, 0.0);
    HingeBox.Color := Vector4(0.82, 0.78, 0.24, 1.0);
    GateBox.Add(HingeBox);
  end;

  if OwnerComp.FindComponent('TavernSign') = nil then
  begin
    SignBox := TCastleBox.Create(OwnerComp);
    SignBox.Name := 'TavernSign';
    SignBox.Size := Vector3(1.8, 1.2, 0.3);
    SignBox.Translation := Vector3(4.2, 2.4, 0.0);
    SignBox.Color := Vector4(0.24, 0.74, 0.92, 1.0);
    Vp.Items.Add(SignBox);
  end;

  if OwnerComp.FindComponent('WatchtowerBell') = nil then
  begin
    BellBox := TCastleBox.Create(OwnerComp);
    BellBox.Name := 'WatchtowerBell';
    BellBox.Size := Vector3(1.1, 1.4, 1.1);
    BellBox.Translation := Vector3(0.0, 4.6, -4.5);
    BellBox.Color := Vector4(0.94, 0.72, 0.20, 1.0);
    Vp.Items.Add(BellBox);
  end;
  Result := True;
end;

function TCollabPresenceBroker.GenerateCollabReport(const RootComp: TComponent): String;
var
  I: Integer;
  L: TCollabSubtreeLock;
  RemSec: Double;
  RootLabel: String;
begin
  if (RootComp <> nil) and (RootComp.Name <> '') then
    RootLabel := RootComp.Name
  else
    RootLabel := '(Open Design)';
  Result :=
    '# Multi-User Collaborative Presence & Sub-Scene Lock Report (Phase 366)' + LineEnding + LineEnding +
    '| Metric | Value |' + LineEnding +
    '| :--- | :--- |' + LineEnding +
    Format('| **Design Root & Hub Catalog** | `%s` — **`%d` Studios** across `6` Domains (`18` MCP Tools) |', [
      RootLabel, TStudioHubManager.StudioCount]) + LineEnding +
    Format('| **Session Clock & Active Locks** | `t = %.1fs` / **`%d` active subtree locks** (`%d` peers) |', [
      FCurrentTimeSec, ActiveLockCount, PeerCount]) + LineEnding + LineEnding +
    '## Active Subtree Reservation Leases' + LineEnding +
    '| Lock ID | Collaborator / Agent | Subtree Root | Remaining Lease | Heartbeats |' + LineEnding +
    '| :--- | :--- | :--- | :--- | :--- |' + LineEnding;

  if ActiveLockCount = 0 then
    Result := Result + '| _(None — all subtrees unlocked)_ | `-` | `-` | `-` | `0` |' + LineEnding
  else
    for I := 0 to ActiveLockCount - 1 do
    begin
      L := GetLock(I);
      RemSec := Max(0.0, L.LeaseExpiresAtSec - FCurrentTimeSec);
      Result := Result + Format('| `%s` | `%s` (`%s`) | **`%s`** | `%.1fs` | `%d` |', [
        L.LockId, L.UserDisplayName, L.UserId, L.SubtreeRootName, RemSec, L.HeartbeatCount]) + LineEnding;
    end;
end;

finalization
  FreeAndNil(GSharedCollabBroker);
end.
