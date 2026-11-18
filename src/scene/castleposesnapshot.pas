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

{ Skeletal Pose Snapshot, Dash Ghost Afterimage Trail & Petrified Statue Freeze (Phase 375).
  Captures character world/limb pose snapshots into a zero-allocation fixed-capacity
  ring buffer for high-speed dash afterimages with alpha/spectral decay, alongside
  petrified statue pose locking and transient 3D silhouette previews. }
unit CastlePoseSnapshot;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions, CastleColors,
  CastleClassUtils, CastleComponentSerialize;

const
  MaxPoseGhostSlots = 16;

type
  TPoseTrailPreset = (
    ptpCyberpunkCyanDash,
    ptpShadowStepViolet,
    ptpMedusaStonePetrify,
    ptpCustom
  );

  TPoseGhostEntry = record
    Active: Boolean;
    SequenceNumber: Integer;
    WorldPos: TVector3;
    YawRad: Single;
    StridePhase: Single;
    RemainingLifeSec: Single;
    InitialLifeSec: Single;
    CurrentAlpha: Single;
    TintColor: TVector3;
  end;

  { Fixed-ring skeletal pose snapshot & dash ghost afterimage trail controller. }
  TCastlePoseSnapshotTrail = class(TCastleTransform)
  private
    FPreset: TPoseTrailPreset;
    FMaxGhostCount: Integer;
    FGhostLifetimeSec: Single;
    FInitialAlpha: Single;
    FGhostTintR: Single;
    FGhostTintG: Single;
    FGhostTintB: Single;
    FShowPreviewSilhouettes: Boolean;
    FStatueFrozen: Boolean;
    FFrozenWorldPos: TVector3;
    FFrozenYawRad: Single;
    FFrozenStridePhase: Single;
    FNextRingSlot: Integer;
    FTotalCapturedCount: Integer;
    FGhosts: array[0..MaxPoseGhostSlots - 1] of TPoseGhostEntry;
    FPreviewRoot: TCastleTransform;
    FGhostBoxes: array[0..MaxPoseGhostSlots - 1] of TCastleBox;
    FStatueBox: TCastleBox;
    procedure SetPreset(const Value: TPoseTrailPreset);
    procedure SetMaxGhostCount(const Value: Integer);
    procedure SetGhostLifetimeSec(const Value: Single);
    procedure SetInitialAlpha(const Value: Single);
    procedure SetGhostTintR(const Value: Single);
    procedure SetGhostTintG(const Value: Single);
    procedure SetGhostTintB(const Value: Single);
    procedure SetShowPreviewSilhouettes(const Value: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure RebuildPreviewMeshes;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Capture a dash afterimage snapshot into the ring buffer. Returns slot index or -1 if statue-frozen. }
    function CaptureDashAfterimage(const AWorldPos: TVector3;
      const AYawRad, AStridePhase: Single): Integer;

    { Advance alpha & lifetime decay across active ghost snapshots. }
    procedure StepGhostDecay(const DtSec: Single);

    { Lock or unlock a petrified statue pose snapshot. }
    procedure FreezeStatuePose(const AWorldPos: TVector3; const AYawRad, AStridePhase: Single);
    procedure UnfreezeStatuePose;
    procedure ClearAllGhosts;

    function ActiveGhostCount: Integer;
    function GetGhostSlot(const SlotIndex: Integer): TPoseGhostEntry;
    function PoseSummaryBadge: String;

    property IsStatueFrozen: Boolean read FStatueFrozen;
    property FrozenWorldPos: TVector3 read FFrozenWorldPos;
    property FrozenYawRad: Single read FFrozenYawRad;
    property FrozenStridePhase: Single read FFrozenStridePhase;
    property TotalCapturedCount: Integer read FTotalCapturedCount;
  published
    property Preset: TPoseTrailPreset read FPreset write SetPreset default ptpCyberpunkCyanDash;
    property MaxGhostCount: Integer read FMaxGhostCount write SetMaxGhostCount default 6;
    property GhostLifetimeSec: Single read FGhostLifetimeSec write SetGhostLifetimeSec {$ifdef FPC}default 0.60{$endif};
    property InitialAlpha: Single read FInitialAlpha write SetInitialAlpha {$ifdef FPC}default 0.75{$endif};
    property GhostTintR: Single read FGhostTintR write SetGhostTintR {$ifdef FPC}default 0.15{$endif};
    property GhostTintG: Single read FGhostTintG write SetGhostTintG {$ifdef FPC}default 0.90{$endif};
    property GhostTintB: Single read FGhostTintB write SetGhostTintB {$ifdef FPC}default 1.00{$endif};
    property ShowPreviewSilhouettes: Boolean read FShowPreviewSilhouettes write SetShowPreviewSilhouettes default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

implementation

uses fpjson, jsonparser;

constructor TCastlePoseSnapshotTrail.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := ptpCyberpunkCyanDash;
  FMaxGhostCount := 6;
  FGhostLifetimeSec := 0.60;
  FInitialAlpha := 0.75;
  FGhostTintR := 0.15;
  FGhostTintG := 0.90;
  FGhostTintB := 1.00;
  FShowPreviewSilhouettes := True;
  FStatueFrozen := False;
  FFrozenWorldPos := TVector3.Zero;
  FFrozenYawRad := 0.0;
  FFrozenStridePhase := 0.0;
  FNextRingSlot := 0;
  FTotalCapturedCount := 0;
  FillChar(FGhosts, SizeOf(FGhosts), 0);
  RebuildPreviewMeshes;
end;

destructor TCastlePoseSnapshotTrail.Destroy;
begin
  inherited Destroy;
end;

function TCastlePoseSnapshotTrail.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'MaxGhostCount') or
     (PropertyName = 'GhostLifetimeSec') or
     (PropertyName = 'InitialAlpha') or
     (PropertyName = 'GhostTintR') or
     (PropertyName = 'GhostTintG') or
     (PropertyName = 'GhostTintB') or
     (PropertyName = 'ShowPreviewSilhouettes') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastlePoseSnapshotTrail.CaptureDashAfterimage(const AWorldPos: TVector3;
  const AYawRad, AStridePhase: Single): Integer;
var
  SlotIdx: Integer;
begin
  if FStatueFrozen then
    Exit(-1);

  SlotIdx := FNextRingSlot mod Max(1, FMaxGhostCount);
  Inc(FTotalCapturedCount);

  FGhosts[SlotIdx].Active := True;
  FGhosts[SlotIdx].SequenceNumber := FTotalCapturedCount;
  FGhosts[SlotIdx].WorldPos := AWorldPos;
  FGhosts[SlotIdx].YawRad := AYawRad;
  FGhosts[SlotIdx].StridePhase := AStridePhase;
  FGhosts[SlotIdx].InitialLifeSec := Max(0.05, FGhostLifetimeSec);
  FGhosts[SlotIdx].RemainingLifeSec := FGhosts[SlotIdx].InitialLifeSec;
  FGhosts[SlotIdx].CurrentAlpha := FInitialAlpha;
  FGhosts[SlotIdx].TintColor := Vector3(FGhostTintR, FGhostTintG, FGhostTintB);

  FNextRingSlot := (SlotIdx + 1) mod Max(1, FMaxGhostCount);
  Result := SlotIdx;
  RebuildPreviewMeshes;
end;

procedure TCastlePoseSnapshotTrail.StepGhostDecay(const DtSec: Single);
var
  I: Integer;
  StepDt, Ratio: Single;
begin
  StepDt := Max(0.0, DtSec);
  if StepDt <= 0.0 then Exit;

  for I := 0 to MaxPoseGhostSlots - 1 do
    if FGhosts[I].Active then
    begin
      FGhosts[I].RemainingLifeSec := FGhosts[I].RemainingLifeSec - StepDt;
      if FGhosts[I].RemainingLifeSec <= 1e-5 then
      begin
        FGhosts[I].Active := False;
        FGhosts[I].RemainingLifeSec := 0.0;
        FGhosts[I].CurrentAlpha := 0.0;
      end else
      begin
        Ratio := EnsureRange(FGhosts[I].RemainingLifeSec / Max(0.05, FGhosts[I].InitialLifeSec), 0.0, 1.0);
        FGhosts[I].CurrentAlpha := FInitialAlpha * Ratio;
      end;
    end;
  RebuildPreviewMeshes;
end;

procedure TCastlePoseSnapshotTrail.FreezeStatuePose(const AWorldPos: TVector3;
  const AYawRad, AStridePhase: Single);
begin
  FStatueFrozen := True;
  FFrozenWorldPos := AWorldPos;
  FFrozenYawRad := AYawRad;
  FFrozenStridePhase := AStridePhase;
  RebuildPreviewMeshes;
end;

procedure TCastlePoseSnapshotTrail.UnfreezeStatuePose;
begin
  if not FStatueFrozen then Exit;
  FStatueFrozen := False;
  RebuildPreviewMeshes;
end;

procedure TCastlePoseSnapshotTrail.ClearAllGhosts;
begin
  FillChar(FGhosts, SizeOf(FGhosts), 0);
  FNextRingSlot := 0;
  FTotalCapturedCount := 0;
  RebuildPreviewMeshes;
end;

function TCastlePoseSnapshotTrail.ActiveGhostCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FMaxGhostCount - 1 do
    if FGhosts[I].Active then
      Inc(Result);
end;

function TCastlePoseSnapshotTrail.GetGhostSlot(const SlotIndex: Integer): TPoseGhostEntry;
begin
  if (SlotIndex >= 0) and (SlotIndex < MaxPoseGhostSlots) then
    Result := FGhosts[SlotIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

function TCastlePoseSnapshotTrail.PoseSummaryBadge: String;
var
  StateTag: String;
begin
  if FStatueFrozen then
    StateTag := 'STATUE_FROZEN'
  else
    StateTag := Format('%d/%d ghosts', [ActiveGhostCount, FMaxGhostCount]);
  Result := Format('[PoseSnap:%s %.2fs]', [StateTag, FGhostLifetimeSec]);
end;

procedure TCastlePoseSnapshotTrail.RebuildPreviewMeshes;
var
  I: Integer;
begin
  if FPreviewRoot = nil then
  begin
    FPreviewRoot := TCastleTransform.Create(Self);
    FPreviewRoot.SetTransient;
    FPreviewRoot.Name := 'PoseSnapshotTransientRoot';
    Add(FPreviewRoot);

    for I := 0 to MaxPoseGhostSlots - 1 do
    begin
      FGhostBoxes[I] := TCastleBox.Create(FPreviewRoot);
      FGhostBoxes[I].SetTransient;
      FGhostBoxes[I].Material := pmUnlit;
      FGhostBoxes[I].Size := Vector3(0.62, 1.78, 0.36);
      FGhostBoxes[I].Exists := False;
      FPreviewRoot.Add(FGhostBoxes[I]);
    end;

    FStatueBox := TCastleBox.Create(FPreviewRoot);
    FStatueBox.SetTransient;
    FStatueBox.Material := pmPhysical;
    FStatueBox.Size := Vector3(0.70, 1.82, 0.42);
    FStatueBox.Color := Vector4(0.62, 0.64, 0.66, 1.0);
    FStatueBox.Exists := False;
    FPreviewRoot.Add(FStatueBox);
  end;

  FPreviewRoot.Exists := FShowPreviewSilhouettes;
  for I := 0 to MaxPoseGhostSlots - 1 do
  begin
    if (I < FMaxGhostCount) and FGhosts[I].Active and FShowPreviewSilhouettes then
    begin
      FGhostBoxes[I].Exists := True;
      FGhostBoxes[I].Translation := FGhosts[I].WorldPos + Vector3(0.0, 0.89, 0.0);
      FGhostBoxes[I].Rotation := Vector4(0.0, 1.0, 0.0, FGhosts[I].YawRad);
      FGhostBoxes[I].Color := Vector4(
        FGhosts[I].TintColor.X,
        FGhosts[I].TintColor.Y,
        FGhosts[I].TintColor.Z,
        EnsureRange(FGhosts[I].CurrentAlpha, 0.05, 1.0));
    end else
      FGhostBoxes[I].Exists := False;
  end;

  FStatueBox.Exists := FShowPreviewSilhouettes and FStatueFrozen;
  if FStatueFrozen then
  begin
    FStatueBox.Translation := FFrozenWorldPos + Vector3(0.0, 0.91, 0.0);
    FStatueBox.Rotation := Vector4(0.0, 1.0, 0.0, FFrozenYawRad);
  end;
end;

procedure TCastlePoseSnapshotTrail.SetPreset(const Value: TPoseTrailPreset);
begin
  if FPreset = Value then Exit;
  FPreset := Value;
  case Value of
    ptpCyberpunkCyanDash:
      begin
        FMaxGhostCount := 6;
        FGhostLifetimeSec := 0.60;
        FInitialAlpha := 0.75;
        FGhostTintR := 0.15;
        FGhostTintG := 0.90;
        FGhostTintB := 1.00;
        FStatueFrozen := False;
      end;
    ptpShadowStepViolet:
      begin
        FMaxGhostCount := 8;
        FGhostLifetimeSec := 0.95;
        FInitialAlpha := 0.82;
        FGhostTintR := 0.68;
        FGhostTintG := 0.22;
        FGhostTintB := 0.96;
        FStatueFrozen := False;
      end;
    ptpMedusaStonePetrify:
      begin
        FMaxGhostCount := 4;
        FGhostLifetimeSec := 0.40;
        FInitialAlpha := 0.55;
        FGhostTintR := 0.62;
        FGhostTintG := 0.64;
        FGhostTintB := 0.66;
        FreezeStatuePose(FFrozenWorldPos, FFrozenYawRad, FFrozenStridePhase);
      end;
    ptpCustom: ;
  end;
  RebuildPreviewMeshes;
end;

procedure TCastlePoseSnapshotTrail.SetMaxGhostCount(const Value: Integer);
var
  Clamped, I: Integer;
begin
  Clamped := EnsureRange(Value, 1, MaxPoseGhostSlots);
  if FMaxGhostCount = Clamped then Exit;
  FMaxGhostCount := Clamped;
  for I := FMaxGhostCount to MaxPoseGhostSlots - 1 do
    FGhosts[I].Active := False;
  FNextRingSlot := FNextRingSlot mod FMaxGhostCount;
  FPreset := ptpCustom;
  RebuildPreviewMeshes;
end;

procedure TCastlePoseSnapshotTrail.SetGhostLifetimeSec(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.05, 10.0);
  if SameValue(FGhostLifetimeSec, Clamped, 1e-4) then Exit;
  FGhostLifetimeSec := Clamped;
  FPreset := ptpCustom;
end;

procedure TCastlePoseSnapshotTrail.SetInitialAlpha(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.05, 1.0);
  if SameValue(FInitialAlpha, Clamped, 1e-4) then Exit;
  FInitialAlpha := Clamped;
  FPreset := ptpCustom;
end;

procedure TCastlePoseSnapshotTrail.SetGhostTintR(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FGhostTintR, Clamped, 1e-4) then Exit;
  FGhostTintR := Clamped;
  FPreset := ptpCustom;
end;

procedure TCastlePoseSnapshotTrail.SetGhostTintG(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FGhostTintG, Clamped, 1e-4) then Exit;
  FGhostTintG := Clamped;
  FPreset := ptpCustom;
end;

procedure TCastlePoseSnapshotTrail.SetGhostTintB(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.0, 1.0);
  if SameValue(FGhostTintB, Clamped, 1e-4) then Exit;
  FGhostTintB := Clamped;
  FPreset := ptpCustom;
end;

procedure TCastlePoseSnapshotTrail.SetShowPreviewSilhouettes(const Value: Boolean);
begin
  if FShowPreviewSilhouettes = Value then Exit;
  FShowPreviewSilhouettes := Value;
  RebuildPreviewMeshes;
end;

function TCastlePoseSnapshotTrail.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('maxGhostCount', FMaxGhostCount);
    Obj.Add('ghostLifetimeSec', FGhostLifetimeSec);
    Obj.Add('initialAlpha', FInitialAlpha);
    Obj.Add('ghostTintR', FGhostTintR);
    Obj.Add('ghostTintG', FGhostTintG);
    Obj.Add('ghostTintB', FGhostTintB);
    Obj.Add('statueFrozen', FStatueFrozen);
    Obj.Add('frozenX', FFrozenWorldPos.X);
    Obj.Add('frozenY', FFrozenWorldPos.Y);
    Obj.Add('frozenZ', FFrozenWorldPos.Z);
    Obj.Add('frozenYawRad', FFrozenYawRad);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastlePoseSnapshotTrail.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
  SavedPreset: Integer;
begin
  if Trim(Value) = '' then Exit;
  try
    Data := GetJSON(Value);
  except
    Exit;
  end;
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    FMaxGhostCount := EnsureRange(Obj.Get('maxGhostCount', FMaxGhostCount), 1, MaxPoseGhostSlots);
    FGhostLifetimeSec := EnsureRange(Obj.Get('ghostLifetimeSec', FGhostLifetimeSec), 0.05, 10.0);
    FInitialAlpha := EnsureRange(Obj.Get('initialAlpha', FInitialAlpha), 0.05, 1.0);
    FGhostTintR := EnsureRange(Obj.Get('ghostTintR', FGhostTintR), 0.0, 1.0);
    FGhostTintG := EnsureRange(Obj.Get('ghostTintG', FGhostTintG), 0.0, 1.0);
    FGhostTintB := EnsureRange(Obj.Get('ghostTintB', FGhostTintB), 0.0, 1.0);
    FStatueFrozen := Obj.Get('statueFrozen', FStatueFrozen);
    FFrozenWorldPos := Vector3(
      Obj.Get('frozenX', 0.0),
      Obj.Get('frozenY', 0.0),
      Obj.Get('frozenZ', 0.0));
    FFrozenYawRad := Obj.Get('frozenYawRad', 0.0);
    SavedPreset := Obj.Get('preset', Ord(FPreset));
    if (SavedPreset >= Ord(Low(TPoseTrailPreset))) and
       (SavedPreset <= Ord(High(TPoseTrailPreset))) then
      FPreset := TPoseTrailPreset(SavedPreset);
    RebuildPreviewMeshes;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastlePoseSnapshotTrail, 'Pose Snapshot & Dash Ghost Trail');
end.
