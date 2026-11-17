{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine contributors.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Gameplay Cue combat feedback director providing tag-routed impact cues,
  melee/crit Hit-Stop time-dilation freeze frames, damped camera punch, and a
  fixed-capacity zero-allocation floating damage/heal popup & burst pool
  (Phase 342 — Unreal Engine 6.0+ UGameplayCueManager parity). }
unit CastleGameplayCue;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math, StrUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Visual & kinematical style resolved from a GameplayCue.* tag. }
  TGameplayCueKind = (
    gckPhysicalDamage,
    gckCriticalStrike,
    gckHealRestore,
    gckShieldBlock
  );

  { Pooled floating combat number / status popup & impact ring. }
  TGameplayCuePopupSlot = record
    Active: Boolean;
    CueTag: String;
    Kind: TGameplayCueKind;
    DisplayText: String;
    Magnitude: Single;
    WorldPos: TVector3;
    Velocity: TVector3;
    ColorRGB: TVector3;
    ScaleFactor: Single;
    AgeSec: Single;
    LifetimeSec: Single;
  end;

  { Centralized Gameplay Cue combat-feel director managing Hit-Stop time scale,
    camera punch, and pooled 3D floating damage/heal/block popups. }
  TCastleGameplayCueDirector = class(TCastleTransform)
  private
    FMaxPooledPopups: Integer;
    FDefaultPopupLifetimeSec: Single;
    FPopupGravity: Single;
    FHitStopTimeScale: Single;
    FCritHitStopDurationSec: Single;
    FLightHitStopDurationSec: Single;
    FCameraPunchDamping: Single;
    FBuildVisualBurstMesh: Boolean;
    FAutoStepInUpdate: Boolean;

    FPool: array of TGameplayCuePopupSlot;
    FActivePopupCount: Integer;
    FTotalCuesTriggered: Integer;
    FRngState: Cardinal;
    FHitStopRemainingSec: Single;
    FCameraPunchOffset: TVector3;

    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;

    procedure SetMaxPooledPopups(const AValue: Integer);
    procedure SetDefaultPopupLifetimeSec(const AValue: Single);
    procedure SetHitStopTimeScale(const AValue: Single);
    procedure SetBuildVisualBurstMesh(const AValue: Boolean);
    function GetEffectiveWorldTimeScale: Single;

    function AcquirePoolSlotIndex: Integer;
    procedure RecountActiveSlots;
    procedure EnsureVisualScene;
    procedure RebuildVisualMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ClearAllPopups;

    { Dispatch a GameplayCue.* tag at AWorldPos, triggering pooled popup arc,
      hit-stop freeze frames, and camera punch. Returns pool slot index. }
    function TriggerGameplayCue(const ACueTag: String; const AWorldPos: TVector3;
      const AMagnitude: Single; const AForceCritical: Boolean = False): Integer;

    { Step hit-stop timer, camera punch decay, and popup ballistic arcs using
      unscaled real-time Dt so popups remain crisp during hit-stop freezes. }
    procedure StepDirector(const AUnscaledDt: Single);

    function PoolCapacity: Integer;
    function GetPopupSlot(const AIndex: Integer): TGameplayCuePopupSlot;
    function GameplayCueSummaryBadge: String;

    property ActivePopupCount: Integer read FActivePopupCount;
    property TotalCuesTriggered: Integer read FTotalCuesTriggered;
    property HitStopRemainingSec: Single read FHitStopRemainingSec;
    property EffectiveWorldTimeScale: Single read GetEffectiveWorldTimeScale;
    property CameraPunchOffset: TVector3 read FCameraPunchOffset;
  published
    property MaxPooledPopups: Integer read FMaxPooledPopups write SetMaxPooledPopups default 48;
    property DefaultPopupLifetimeSec: Single read FDefaultPopupLifetimeSec write SetDefaultPopupLifetimeSec {$ifdef FPC}default 1.15{$endif};
    property PopupGravity: Single read FPopupGravity write FPopupGravity {$ifdef FPC}default 9.5{$endif};
    property HitStopTimeScale: Single read FHitStopTimeScale write SetHitStopTimeScale {$ifdef FPC}default 0.05{$endif};
    property CritHitStopDurationSec: Single read FCritHitStopDurationSec write FCritHitStopDurationSec {$ifdef FPC}default 0.09{$endif};
    property LightHitStopDurationSec: Single read FLightHitStopDurationSec write FLightHitStopDurationSec {$ifdef FPC}default 0.03{$endif};
    property CameraPunchDamping: Single read FCameraPunchDamping write FCameraPunchDamping {$ifdef FPC}default 14.0{$endif};
    property BuildVisualBurstMesh: Boolean read FBuildVisualBurstMesh write SetBuildVisualBurstMesh default True;
    property AutoStepInUpdate: Boolean read FAutoStepInUpdate write FAutoStepInUpdate default True;
  end;

function ClassifyGameplayCueTag(const ACueTag: String;
  const AForceCritical: Boolean = False): TGameplayCueKind;

implementation

uses
  CastleComponentSerialize;

function ClassifyGameplayCueTag(const ACueTag: String;
  const AForceCritical: Boolean): TGameplayCueKind;
begin
  if AForceCritical or AnsiContainsText(ACueTag, 'Crit') then
    Exit(gckCriticalStrike);
  if AnsiContainsText(ACueTag, 'Heal') or AnsiContainsText(ACueTag, 'Regen') then
    Exit(gckHealRestore);
  if AnsiContainsText(ACueTag, 'Block') or AnsiContainsText(ACueTag, 'Shield') or
     AnsiContainsText(ACueTag, 'Parry') then
    Exit(gckShieldBlock);
  Result := gckPhysicalDamage;
end;

function NextSignedSpread(var State: Cardinal): Single;
begin
  if State = 0 then
    State := 314159265;
  State := State xor (State shl 13);
  State := State xor (State shr 17);
  State := State xor (State shl 5);
  Result := ((State and $FFFF) / 32767.5) - 1.0;
end;

{ TCastleGameplayCueDirector ------------------------------------------------- }

constructor TCastleGameplayCueDirector.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxPooledPopups := 48;
  FDefaultPopupLifetimeSec := 1.15;
  FPopupGravity := 9.5;
  FHitStopTimeScale := 0.05;
  FCritHitStopDurationSec := 0.09;
  FLightHitStopDurationSec := 0.03;
  FCameraPunchDamping := 14.0;
  FBuildVisualBurstMesh := True;
  FAutoStepInUpdate := True;
  FRngState := 20260342;
  SetLength(FPool, FMaxPooledPopups);
  ClearAllPopups;
end;

destructor TCastleGameplayCueDirector.Destroy;
begin
  FCoordNode := nil;
  FColorNode := nil;
  FreeAndNil(FTransientScene);
  ClearAllPopups;
  SetLength(FPool, 0);
  inherited Destroy;
end;

function TCastleGameplayCueDirector.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'MaxPooledPopups', 'DefaultPopupLifetimeSec', 'PopupGravity',
       'HitStopTimeScale', 'CritHitStopDurationSec', 'LightHitStopDurationSec',
       'CameraPunchDamping', 'BuildVisualBurstMesh', 'AutoStepInUpdate'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleGameplayCueDirector.SetMaxPooledPopups(const AValue: Integer);
var
  NewCap, I: Integer;
begin
  NewCap := EnsureRange(AValue, 4, 256);
  if NewCap = FMaxPooledPopups then Exit;
  for I := NewCap to High(FPool) do
    FPool[I] := Default(TGameplayCuePopupSlot);
  FMaxPooledPopups := NewCap;
  SetLength(FPool, FMaxPooledPopups);
  RecountActiveSlots;
end;

procedure TCastleGameplayCueDirector.SetDefaultPopupLifetimeSec(const AValue: Single);
begin
  FDefaultPopupLifetimeSec := Max(0.15, AValue);
end;

procedure TCastleGameplayCueDirector.SetHitStopTimeScale(const AValue: Single);
begin
  FHitStopTimeScale := EnsureRange(AValue, 0.0, 1.0);
end;

procedure TCastleGameplayCueDirector.SetBuildVisualBurstMesh(const AValue: Boolean);
begin
  if FBuildVisualBurstMesh = AValue then Exit;
  FBuildVisualBurstMesh := AValue;
  if not FBuildVisualBurstMesh then
  begin
    FCoordNode := nil;
    FColorNode := nil;
    FreeAndNil(FTransientScene);
  end
  else
    RebuildVisualMesh;
end;

function TCastleGameplayCueDirector.GetEffectiveWorldTimeScale: Single;
begin
  if FHitStopRemainingSec > 0.0 then
    Result := FHitStopTimeScale
  else
    Result := 1.0;
end;

procedure TCastleGameplayCueDirector.ClearAllPopups;
var
  I: Integer;
begin
  for I := 0 to High(FPool) do
    FPool[I] := Default(TGameplayCuePopupSlot);
  FActivePopupCount := 0;
  FHitStopRemainingSec := 0.0;
  FCameraPunchOffset := TVector3.Zero;
  if FCoordNode <> nil then
  begin
    FCoordNode.FdPoint.Count := 0;
    FCoordNode.FdPoint.Changed;
  end;
  if FColorNode <> nil then
  begin
    FColorNode.FdColor.Count := 0;
    FColorNode.FdColor.Changed;
  end;
end;

function TCastleGameplayCueDirector.AcquirePoolSlotIndex: Integer;
var
  I, OldestIdx: Integer;
  OldestAge: Single;
begin
  if Length(FPool) <> FMaxPooledPopups then
    SetLength(FPool, FMaxPooledPopups);

  for I := 0 to High(FPool) do
    if not FPool[I].Active then
      Exit(I);

  { Pool full: deterministically recycle oldest active slot with 0 heap growth }
  OldestIdx := 0;
  OldestAge := -1.0;
  for I := 0 to High(FPool) do
    if FPool[I].AgeSec > OldestAge then
    begin
      OldestAge := FPool[I].AgeSec;
      OldestIdx := I;
    end;
  Result := OldestIdx;
end;

procedure TCastleGameplayCueDirector.RecountActiveSlots;
var
  I: Integer;
begin
  FActivePopupCount := 0;
  for I := 0 to High(FPool) do
    if FPool[I].Active then
      Inc(FActivePopupCount);
end;

function TCastleGameplayCueDirector.TriggerGameplayCue(const ACueTag: String;
  const AWorldPos: TVector3; const AMagnitude: Single;
  const AForceCritical: Boolean): Integer;
var
  Slot: TGameplayCuePopupSlot;
  Kind: TGameplayCueKind;
  JitterX, JitterZ: Single;
begin
  Result := AcquirePoolSlotIndex;
  Kind := ClassifyGameplayCueTag(ACueTag, AForceCritical);
  JitterX := NextSignedSpread(FRngState) * 1.6;
  JitterZ := NextSignedSpread(FRngState) * 0.8;

  Slot := Default(TGameplayCuePopupSlot);
  Slot.Active := True;
  Slot.CueTag := ACueTag;
  Slot.Kind := Kind;
  Slot.Magnitude := AMagnitude;
  Slot.WorldPos := AWorldPos;
  Slot.AgeSec := 0.0;
  Slot.LifetimeSec := FDefaultPopupLifetimeSec;

  case Kind of
    gckCriticalStrike:
      begin
        Slot.DisplayText := Format('%.0f CRIT!', [AMagnitude]);
        Slot.ColorRGB := Vector3(1.00, 0.80, 0.16);
        Slot.ScaleFactor := 1.85;
        Slot.Velocity := Vector3(JitterX * 1.4, 5.4, JitterZ);
        FHitStopRemainingSec := Max(FHitStopRemainingSec, FCritHitStopDurationSec);
        FCameraPunchOffset := FCameraPunchOffset + Vector3(JitterX * 0.12, 0.16, 0.28);
      end;
    gckHealRestore:
      begin
        Slot.DisplayText := Format('+%.0f HP', [AMagnitude]);
        Slot.ColorRGB := Vector3(0.24, 0.96, 0.46);
        Slot.ScaleFactor := 1.15;
        Slot.Velocity := Vector3(JitterX * 0.35, 2.6, 0.0);
      end;
    gckShieldBlock:
      begin
        Slot.DisplayText := 'BLOCKED!';
        Slot.ColorRGB := Vector3(0.32, 0.84, 1.00);
        Slot.ScaleFactor := 1.25;
        Slot.Velocity := Vector3(JitterX * 0.8, 3.2, JitterZ);
        FHitStopRemainingSec := Max(FHitStopRemainingSec, FLightHitStopDurationSec * 1.2);
        FCameraPunchOffset := FCameraPunchOffset + Vector3(0.0, 0.05, 0.14);
      end;
  else
    begin
      Slot.DisplayText := Format('%.0f', [AMagnitude]);
      Slot.ColorRGB := Vector3(0.96, 0.94, 0.90);
      Slot.ScaleFactor := 1.0;
      Slot.Velocity := Vector3(JitterX, 4.0, JitterZ);
      FHitStopRemainingSec := Max(FHitStopRemainingSec, FLightHitStopDurationSec);
      FCameraPunchOffset := FCameraPunchOffset + Vector3(0.0, 0.04, 0.09);
    end;
  end;

  FPool[Result] := Slot;
  Inc(FTotalCuesTriggered);
  RecountActiveSlots;
  RebuildVisualMesh;
end;

procedure TCastleGameplayCueDirector.StepDirector(const AUnscaledDt: Single);
var
  I: Integer;
  Dt: Single;
begin
  Dt := Max(0.0, AUnscaledDt);
  if Dt <= 0.0 then
    Exit;

  if FHitStopRemainingSec > 0.0 then
    FHitStopRemainingSec := Max(0.0, FHitStopRemainingSec - Dt);

  FCameraPunchOffset := FCameraPunchOffset * Exp(-FCameraPunchDamping * Dt);

  for I := 0 to High(FPool) do
    if FPool[I].Active then
    begin
      FPool[I].AgeSec := FPool[I].AgeSec + Dt;
      if FPool[I].AgeSec >= FPool[I].LifetimeSec then
        FPool[I] := Default(TGameplayCuePopupSlot)
      else
      begin
        FPool[I].WorldPos := FPool[I].WorldPos + FPool[I].Velocity * Dt;
        if FPool[I].Kind <> gckHealRestore then
          FPool[I].Velocity.Y := FPool[I].Velocity.Y - FPopupGravity * Dt;
      end;
    end;

  RecountActiveSlots;
  RebuildVisualMesh;
end;

procedure TCastleGameplayCueDirector.EnsureVisualScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  TriSet: TTriangleSetNode;
begin
  if not FBuildVisualBurstMesh then Exit;
  if FTransientScene <> nil then Exit;

  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.SetTransient;
  FTransientScene.Name := 'TransientGameplayCueMesh';
  FTransientScene.Pickable := False;
  FTransientScene.PreciseCollisions := False;

  Root := TX3DRootNode.Create;
  Shape := TShapeNode.Create;
  App := TAppearanceNode.Create;
  Mat := TUnlitMaterialNode.Create;
  Mat.EmissiveColor := Vector3(1, 1, 1);
  App.Material := Mat;
  Shape.Appearance := App;

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

procedure TCastleGameplayCueDirector.RebuildVisualMesh;
var
  InvWorld: TMatrix4;
  Verts, Colors: TVector3List;
  I: Integer;
  C, Col: TVector3;
  R, Fade: Single;
begin
  if not FBuildVisualBurstMesh then Exit;
  EnsureVisualScene;
  if FTransientScene = nil then Exit;

  if (not HasParent) or (not WorldTransform.TryInverse(InvWorld)) then
    InvWorld := TMatrix4.Identity;

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    for I := 0 to High(FPool) do
      if FPool[I].Active then
      begin
        C := InvWorld.MultPoint(FPool[I].WorldPos);
        Fade := Max(0.0, 1.0 - (FPool[I].AgeSec / Max(0.05, FPool[I].LifetimeSec)));
        R := 0.16 * FPool[I].ScaleFactor * (0.5 + 0.5 * Fade);
        Col := FPool[I].ColorRGB * Fade;

        { Emissive 3D diamond burst marker }
        Verts.Add(C + Vector3(0, +R, 0)); Verts.Add(C + Vector3(-R, 0, 0)); Verts.Add(C + Vector3(+R, 0, 0));
        Colors.Add(Col); Colors.Add(Col); Colors.Add(Col);
        Verts.Add(C + Vector3(0, -R, 0)); Verts.Add(C + Vector3(+R, 0, 0)); Verts.Add(C + Vector3(-R, 0, 0));
        Colors.Add(Col); Colors.Add(Col); Colors.Add(Col);
      end;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;
end;

procedure TCastleGameplayCueDirector.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FAutoStepInUpdate then
    StepDirector(Min(SecondsPassed, 0.1));
end;

function TCastleGameplayCueDirector.PoolCapacity: Integer;
begin
  Result := Length(FPool);
end;

function TCastleGameplayCueDirector.GetPopupSlot(
  const AIndex: Integer): TGameplayCuePopupSlot;
begin
  if (AIndex >= 0) and (AIndex <= High(FPool)) then
    Result := FPool[AIndex]
  else
    Result := Default(TGameplayCuePopupSlot);
end;

function TCastleGameplayCueDirector.GameplayCueSummaryBadge: String;
begin
  Result := Format('[GameCue:%d/%d pool TimeScale=%.2fx #%d]', [
    FActivePopupCount, FMaxPooledPopups,
    GetEffectiveWorldTimeScale, FTotalCuesTriggered
  ]);
end;

initialization
  RegisterSerializableComponent(TCastleGameplayCueDirector,
    ['AI & Gameplay', 'Gameplay Cue, Hit-Stop & Popup Director (TCastleGameplayCueDirector)']);

end.
