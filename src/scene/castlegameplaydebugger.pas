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

{ GameplayDebugger Live 3D HUD Overlay, Numpad 0..5 Hotkey Channels &
  Multi-Subsystem Inspector (Phase 363 — UE 6.0+ AGameplayDebugger Parity). }
unit CastleGameplayDebugger;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleUtils, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Toggleable Numpad 0..5 diagnostic overlay channels matching UE AGameplayDebugger. }
  TGameplayDebugChannel = (
    gdcAiStateTree = 0,
    gdcTargetingLockOn = 1,
    gdcGasAbilities = 2,
    gdcMoverLocomotion = 3,
    gdcMassTraffic = 4,
    gdcSurfaceGi = 5
  );

  { World-space 3D diagnostic beacon emitted by an active GameplayDebugger channel. }
  TGameplayDebugMarker3D = record
    Channel: TGameplayDebugChannel;
    WorldPos: TVector3;
    RadiusMeters: Single;
    ColorRgb: TVector3;
    LabelText: String;
  end;

  { Live multi-subsystem GameplayDebugger aggregating AI StateTree, Targeting Lock-On,
    GAS Attributes/Tags, Mover 2.0 Locomotion, MassTraffic, and Surface GI probes
    across per-category Numpad 0..5 bitmask channels. }
  TCastleGameplayDebugger = class(TCastleTransform)
  private
    FOverlayActive: Boolean;
    FDebuggedActorName: String;
    FChannelMask: Integer;
    FShowWorldDebugMarkers: Boolean;
    FHudLines: TStringList;
    FMarkers: array of TGameplayDebugMarker3D;
    FResolvedActorName: String;
    FTransientScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetOverlayActive(const AValue: Boolean);
    procedure SetDebuggedActorName(const AValue: String);
    procedure SetChannelMask(const AValue: Integer);
    procedure SetShowWorldDebugMarkers(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure AddMarker(const AChannel: TGameplayDebugChannel;
      const AWorldPos: TVector3; const ARadius: Single;
      const AColorRgb: TVector3; const ALabel: String);
    procedure EnsureTransientScene;
    procedure ClearTransientScene;
    procedure RebuildDebugMarkersMesh;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function IsChannelEnabled(const AChannel: TGameplayDebugChannel): Boolean;
    procedure SetChannelEnabled(const AChannel: TGameplayDebugChannel; const AEnabled: Boolean);
    function ToggleChannelByNumpadKey(const ANumpadDigit: Integer): Boolean;
    procedure EnableAllChannels;
    procedure DisableAllChannels;
    function CollectSnapshotFromWorld(const RootWorld: TCastleTransform): Integer;
    function HudLineCount: Integer;
    function GetHudLine(const AIndex: Integer): String;
    function MarkerCount: Integer;
    function GetMarker(const AIndex: Integer): TGameplayDebugMarker3D;
    function ExportDiagnosticSnapshotJson: String;
    function DebuggerSummaryBadge: String;
    property ResolvedActorName: String read FResolvedActorName;
  published
    property OverlayActive: Boolean read FOverlayActive write SetOverlayActive default True;
    property DebuggedActorName: String read FDebuggedActorName write SetDebuggedActorName;
    property ChannelMask: Integer read FChannelMask write SetChannelMask default 7;
    property ShowWorldDebugMarkers: Boolean read FShowWorldDebugMarkers write SetShowWorldDebugMarkers default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

function GameplayDebugChannelName(const AChannel: TGameplayDebugChannel): String;

implementation

uses fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions,
  CastleStateTree, CastleTargetingSystem, CastleGameplayAbility,
  CastleMover2, CastleMassTraffic, CastleSurfaceGi;

function GameplayDebugChannelName(const AChannel: TGameplayDebugChannel): String;
begin
  case AChannel of
    gdcAiStateTree: Result := '[0] AI StateTree';
    gdcTargetingLockOn: Result := '[1] Targeting Lock-On';
    gdcGasAbilities: Result := '[2] GAS Abilities & Tags';
    gdcMoverLocomotion: Result := '[3] Mover 2.0 Locomotion';
    gdcMassTraffic: Result := '[4] MassTraffic Crossroads';
    gdcSurfaceGi: Result := '[5] Surface GI SH2 Probes';
  end;
end;

{ TCastleGameplayDebugger ----------------------------------------------------- }

constructor TCastleGameplayDebugger.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHudLines := TStringList.Create;
  FOverlayActive := True;
  FDebuggedActorName := '';
  FChannelMask := 7; { Channels 0 (AI), 1 (Targeting), 2 (GAS) enabled by default }
  FShowWorldDebugMarkers := True;
end;

destructor TCastleGameplayDebugger.Destroy;
begin
  ClearTransientScene;
  FreeAndNil(FHudLines);
  inherited Destroy;
end;

procedure TCastleGameplayDebugger.SetOverlayActive(const AValue: Boolean);
begin
  if FOverlayActive = AValue then Exit;
  FOverlayActive := AValue;
  if not FOverlayActive then
  begin
    FHudLines.Clear;
    SetLength(FMarkers, 0);
    ClearTransientScene;
  end;
end;

procedure TCastleGameplayDebugger.SetDebuggedActorName(const AValue: String);
begin
  if FDebuggedActorName = AValue then Exit;
  FDebuggedActorName := AValue;
end;

procedure TCastleGameplayDebugger.SetChannelMask(const AValue: Integer);
var
  V: Integer;
begin
  V := EnsureRange(AValue, 0, 63);
  if FChannelMask = V then Exit;
  FChannelMask := V;
end;

procedure TCastleGameplayDebugger.SetShowWorldDebugMarkers(const AValue: Boolean);
begin
  if FShowWorldDebugMarkers = AValue then Exit;
  FShowWorldDebugMarkers := AValue;
  if not FShowWorldDebugMarkers then
    ClearTransientScene
  else
    RebuildDebugMarkersMesh;
end;

function TCastleGameplayDebugger.IsChannelEnabled(const AChannel: TGameplayDebugChannel): Boolean;
begin
  Result := (FChannelMask and (1 shl Ord(AChannel))) <> 0;
end;

procedure TCastleGameplayDebugger.SetChannelEnabled(
  const AChannel: TGameplayDebugChannel; const AEnabled: Boolean);
var
  Bit: Integer;
begin
  Bit := 1 shl Ord(AChannel);
  if AEnabled then
    FChannelMask := FChannelMask or Bit
  else
    FChannelMask := FChannelMask and (not Bit);
end;

function TCastleGameplayDebugger.ToggleChannelByNumpadKey(const ANumpadDigit: Integer): Boolean;
var
  Ch: TGameplayDebugChannel;
begin
  if (ANumpadDigit < Ord(Low(TGameplayDebugChannel))) or
     (ANumpadDigit > Ord(High(TGameplayDebugChannel))) then
    Exit(False);
  Ch := TGameplayDebugChannel(ANumpadDigit);
  SetChannelEnabled(Ch, not IsChannelEnabled(Ch));
  Result := IsChannelEnabled(Ch);
end;

procedure TCastleGameplayDebugger.EnableAllChannels;
begin
  FChannelMask := 63;
end;

procedure TCastleGameplayDebugger.DisableAllChannels;
begin
  FChannelMask := 0;
end;

procedure TCastleGameplayDebugger.AddMarker(
  const AChannel: TGameplayDebugChannel; const AWorldPos: TVector3;
  const ARadius: Single; const AColorRgb: TVector3; const ALabel: String);
var
  N: Integer;
begin
  N := Length(FMarkers);
  SetLength(FMarkers, N + 1);
  FMarkers[N].Channel := AChannel;
  FMarkers[N].WorldPos := AWorldPos;
  FMarkers[N].RadiusMeters := Max(0.10, ARadius);
  FMarkers[N].ColorRgb := AColorRgb;
  FMarkers[N].LabelText := ALabel;
end;

function TCastleGameplayDebugger.CollectSnapshotFromWorld(
  const RootWorld: TCastleTransform): Integer;

  function FindActor(const ParentT: TCastleTransform): TCastleTransform;
  var
    J: Integer;
  begin
    Result := nil;
    if ParentT = nil then Exit;
    if (ParentT <> RootWorld) and (ParentT <> Self) and
       (not (csTransient in ParentT.ComponentStyle)) then
    begin
      if (FDebuggedActorName <> '') and SameText(ParentT.Name, FDebuggedActorName) then
        Exit(ParentT);
      if (FDebuggedActorName = '') and (
         (ParentT.FindBehavior(TCastleStateTreeBehavior) <> nil) or
         (ParentT.FindBehavior(TCastleTargetingBehavior) <> nil) or
         (ParentT.FindBehavior(TCastleAbilitySystemBehavior) <> nil) or
         (ParentT.FindBehavior(TCastleMoverBehavior) <> nil)) then
        Exit(ParentT);
    end;
    for J := 0 to ParentT.Count - 1 do
    begin
      Result := FindActor(ParentT[J]);
      if Result <> nil then Exit;
    end;
  end;

  function FindTrafficMgr(const ParentT: TCastleTransform): TCastleMassTrafficManager;
  var
    J: Integer;
  begin
    Result := nil;
    if ParentT = nil then Exit;
    if ParentT is TCastleMassTrafficManager then
      Exit(TCastleMassTrafficManager(ParentT));
    for J := 0 to ParentT.Count - 1 do
    begin
      Result := FindTrafficMgr(ParentT[J]);
      if Result <> nil then Exit;
    end;
  end;

  function FindSurfaceGi(const ParentT: TCastleTransform): TCastleSurfaceGiGrid;
  var
    J: Integer;
  begin
    Result := nil;
    if ParentT = nil then Exit;
    if ParentT is TCastleSurfaceGiGrid then
      Exit(TCastleSurfaceGiGrid(ParentT));
    for J := 0 to ParentT.Count - 1 do
    begin
      Result := FindSurfaceGi(ParentT[J]);
      if Result <> nil then Exit;
    end;
  end;

var
  Actor: TCastleTransform;
  ActorPos, SampledGi: TVector3;
  St: TCastleStateTreeBehavior;
  Targ: TCastleTargetingBehavior;
  Gas: TCastleAbilitySystemBehavior;
  Mov: TCastleMoverBehavior;
  Traf: TCastleMassTrafficManager;
  Gi: TCastleSurfaceGiGrid;
  TargetLabel: String;
begin
  FHudLines.Clear;
  SetLength(FMarkers, 0);
  FResolvedActorName := '';

  if (not FOverlayActive) or (RootWorld = nil) then
  begin
    ClearTransientScene;
    Exit(0);
  end;

  Actor := FindActor(RootWorld);
  if Actor <> nil then
  begin
    FResolvedActorName := Actor.Name;
    ActorPos := Actor.WorldTranslation;
  end else
  begin
    FResolvedActorName := '(None)';
    ActorPos := TVector3.Zero;
  end;

  { Channel 0: AI StateTree }
  if IsChannelEnabled(gdcAiStateTree) then
  begin
    if Actor <> nil then St := Actor.FindBehavior(TCastleStateTreeBehavior) as TCastleStateTreeBehavior else St := nil;
    if St <> nil then
    begin
      FHudLines.Add(Format('[0 AI StateTree] Actor=%s | StatePath=%s | Task=%s | Transitions=%d', [
        Actor.Name, St.ActiveStatePath, St.ActiveTaskAction, St.TransitionCount]));
      AddMarker(gdcAiStateTree, ActorPos + Vector3(0, 2.35, 0), 0.32,
        Vector3(1.0, 0.84, 0.18), 'AI:' + St.ActiveLeafStateName);
    end else
      FHudLines.Add('[0 AI StateTree] (No TCastleStateTreeBehavior on debugged actor)');
  end;

  { Channel 1: Targeting Lock-On }
  if IsChannelEnabled(gdcTargetingLockOn) then
  begin
    if Actor <> nil then Targ := Actor.FindBehavior(TCastleTargetingBehavior) as TCastleTargetingBehavior else Targ := nil;
    if Targ <> nil then
    begin
      if Targ.LockedTarget <> nil then TargetLabel := Targ.LockedTarget.Name else TargetLabel := 'NONE';
      FHudLines.Add(Format('[1 Targeting] Locked=%s | ValidCandidates=%d | Range=%.1fm', [
        TargetLabel, Targ.ValidCandidateCount, Targ.MaxLockRangeMeters]));
      if Targ.LockedTarget <> nil then
        AddMarker(gdcTargetingLockOn, Targ.LockedTarget.WorldTranslation + Vector3(0, 1.4, 0),
          0.42, Vector3(1.0, 0.22, 0.26), 'LOCK:' + TargetLabel);
    end else
      FHudLines.Add('[1 Targeting] (No TCastleTargetingBehavior on debugged actor)');
  end;

  { Channel 2: GAS Abilities & Attributes }
  if IsChannelEnabled(gdcGasAbilities) then
  begin
    if Actor <> nil then Gas := Actor.FindBehavior(TCastleAbilitySystemBehavior) as TCastleAbilitySystemBehavior else Gas := nil;
    if Gas <> nil then
    begin
      FHudLines.Add(Format('[2 GAS] HP=%.0f | Mana=%.0f | Atk=%.0f | Effects=%d | Tags=[%s]', [
        Gas.GetCurrentValue('Health'),
        Gas.GetCurrentValue('Mana'),
        Gas.GetCurrentValue('AttackPower'),
        Gas.ActiveEffects.Count,
        Gas.OwnedTags.CommaText]));
      AddMarker(gdcGasAbilities, ActorPos + Vector3(0, 1.0, 0), 0.55,
        Vector3(0.20, 0.94, 0.52), 'GAS');
    end else
      FHudLines.Add('[2 GAS] (No TCastleAbilitySystemBehavior on debugged actor)');
  end;

  { Channel 3: Mover 2.0 Rollback Locomotion }
  if IsChannelEnabled(gdcMoverLocomotion) then
  begin
    if Actor <> nil then Mov := Actor.FindBehavior(TCastleMoverBehavior) as TCastleMoverBehavior else Mov := nil;
    if Mov <> nil then
    begin
      FHudLines.Add(Format('[3 Mover2] %s | Speed=%.2fm/s | Tick=%d | Resims=%d', [
        Mov.MoverSummaryBadge,
        Mov.CurrentState.Velocity.Length,
        Mov.CurrentState.TickIndex,
        Mov.RollbackResimCount]));
      AddMarker(gdcMoverLocomotion, ActorPos + Vector3(0, 0.35, 0), 0.38,
        Vector3(0.26, 0.72, 1.0), 'MOVER2');
    end else
      FHudLines.Add('[3 Mover2] (No TCastleMoverBehavior on debugged actor)');
  end;

  { Channel 4: MassTraffic Multi-Lane Crossroads }
  if IsChannelEnabled(gdcMassTraffic) then
  begin
    Traf := FindTrafficMgr(RootWorld);
    if Traf <> nil then
    begin
      FHudLines.Add(Format('[4 MassTraffic] Vehicles=%d | MeanSpeed=%.1fm/s | Conflicts=%d | Overlaps=%d', [
        Traf.Stats.ActiveVehicles,
        Traf.Stats.MeanSpeedMps,
        Traf.Stats.SignalConflictCount,
        Traf.Stats.RearEndOverlapCount]));
      AddMarker(gdcMassTraffic, Traf.WorldTranslation + Vector3(0, 3.2, 0), 0.65,
        Vector3(1.0, 0.56, 0.14), 'TRAFFIC');
    end else
      FHudLines.Add('[4 MassTraffic] (No TCastleMassTrafficManager in world)');
  end;

  { Channel 5: Surface GI SH2 Irradiance Probes }
  if IsChannelEnabled(gdcSurfaceGi) then
  begin
    Gi := FindSurfaceGi(RootWorld);
    if Gi <> nil then
    begin
      SampledGi := Gi.SampleIrradianceAtWorld(ActorPos + Vector3(0, 1.2, 0), Vector3(0, 1, 0));
      FHudLines.Add(Format('[5 SurfaceGI] Probes=%d | SkyVis=%.0f%% | ActorIrradiance=(%.2f, %.2f, %.2f)', [
        Gi.ProbeCount,
        Gi.BakeStats.MeanSkyVisibility * 100.0,
        SampledGi.X, SampledGi.Y, SampledGi.Z]));
      AddMarker(gdcSurfaceGi, ActorPos + Vector3(0, 1.85, 0), 0.28,
        SampledGi, 'SH2-GI');
    end else
      FHudLines.Add('[5 SurfaceGI] (No TCastleSurfaceGiGrid in world)');
  end;

  if FShowWorldDebugMarkers then
    RebuildDebugMarkersMesh;

  Result := FHudLines.Count;
end;

function TCastleGameplayDebugger.HudLineCount: Integer;
begin
  Result := FHudLines.Count;
end;

function TCastleGameplayDebugger.GetHudLine(const AIndex: Integer): String;
begin
  if (AIndex >= 0) and (AIndex < FHudLines.Count) then
    Result := FHudLines[AIndex]
  else
    Result := '';
end;

function TCastleGameplayDebugger.MarkerCount: Integer;
begin
  Result := Length(FMarkers);
end;

function TCastleGameplayDebugger.GetMarker(const AIndex: Integer): TGameplayDebugMarker3D;
begin
  if (AIndex >= 0) and (AIndex < Length(FMarkers)) then
    Result := FMarkers[AIndex]
  else
    FillChar(Result, SizeOf(Result), 0);
end;

procedure TCastleGameplayDebugger.EnsureTransientScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  TriSet: TTriangleSetNode;
begin
  if FTransientScene <> nil then Exit;
  FTransientScene := TCastleScene.Create(nil);
  FTransientScene.Name := 'TransientGameplayDebuggerMarkers';
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

procedure TCastleGameplayDebugger.ClearTransientScene;
begin
  FCoordNode := nil;
  FColorNode := nil;
  if FTransientScene <> nil then
  begin
    Remove(FTransientScene);
    FreeAndNil(FTransientScene);
  end;
end;

procedure TCastleGameplayDebugger.RebuildDebugMarkersMesh;
var
  Verts, Cols: TVector3List;
  I: Integer;
  CenterLoc, TopPt, BotPt, E1, E2, E3, E4, C: TVector3;
  R: Single;
begin
  if (not FOverlayActive) or (not FShowWorldDebugMarkers) or (Length(FMarkers) = 0) then
  begin
    ClearTransientScene;
    Exit;
  end;

  Verts := TVector3List.Create;
  Cols := TVector3List.Create;
  try
    for I := 0 to High(FMarkers) do
    begin
      if Parent <> nil then
        CenterLoc := WorldToLocal(FMarkers[I].WorldPos)
      else
        CenterLoc := FMarkers[I].WorldPos - Translation;
      R := FMarkers[I].RadiusMeters;
      C := Vector3(
        EnsureRange(FMarkers[I].ColorRgb.X, 0.0, 1.0),
        EnsureRange(FMarkers[I].ColorRgb.Y, 0.0, 1.0),
        EnsureRange(FMarkers[I].ColorRgb.Z, 0.0, 1.0));
      TopPt := CenterLoc + Vector3(0, R, 0);
      BotPt := CenterLoc - Vector3(0, R, 0);
      E1 := CenterLoc + Vector3(R, 0, 0);
      E2 := CenterLoc + Vector3(0, 0, R);
      E3 := CenterLoc + Vector3(-R, 0, 0);
      E4 := CenterLoc + Vector3(0, 0, -R);

      Verts.Add(TopPt); Verts.Add(E1); Verts.Add(E2);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
      Verts.Add(TopPt); Verts.Add(E2); Verts.Add(E3);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
      Verts.Add(TopPt); Verts.Add(E3); Verts.Add(E4);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
      Verts.Add(TopPt); Verts.Add(E4); Verts.Add(E1);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
      Verts.Add(BotPt); Verts.Add(E2); Verts.Add(E1);
      Cols.Add(C); Cols.Add(C); Cols.Add(C);
      Verts.Add(BotPt); Verts.Add(E3); Verts.Add(E2);
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

function TCastleGameplayDebugger.ExportDiagnosticSnapshotJson: String;
var
  RootObj, MObj: TJSONObject;
  LinesArr, MarkersArr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('overlayActive', FOverlayActive);
    RootObj.Add('debuggedActor', FResolvedActorName);
    RootObj.Add('channelMask', FChannelMask);
    LinesArr := TJSONArray.Create;
    for I := 0 to FHudLines.Count - 1 do
      LinesArr.Add(FHudLines[I]);
    RootObj.Add('hudLines', LinesArr);

    MarkersArr := TJSONArray.Create;
    for I := 0 to High(FMarkers) do
    begin
      MObj := TJSONObject.Create;
      MObj.Add('channel', Ord(FMarkers[I].Channel));
      MObj.Add('label', FMarkers[I].LabelText);
      MObj.Add('x', FMarkers[I].WorldPos.X);
      MObj.Add('y', FMarkers[I].WorldPos.Y);
      MObj.Add('z', FMarkers[I].WorldPos.Z);
      MarkersArr.Add(MObj);
    end;
    RootObj.Add('markers', MarkersArr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

function TCastleGameplayDebugger.GetConfigJson: String;
var
  RootObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('active', FOverlayActive);
    RootObj.Add('actorName', FDebuggedActorName);
    RootObj.Add('mask', FChannelMask);
    RootObj.Add('showMarkers', FShowWorldDebugMarkers);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleGameplayDebugger.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  RootObj: TJSONObject;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    Data := GetJSON(AValue);
    if Data is TJSONObject then
    begin
      RootObj := TJSONObject(Data);
      FOverlayActive := RootObj.Get('active', FOverlayActive);
      FDebuggedActorName := RootObj.Get('actorName', FDebuggedActorName);
      FChannelMask := EnsureRange(RootObj.Get('mask', FChannelMask), 0, 63);
      FShowWorldDebugMarkers := RootObj.Get('showMarkers', FShowWorldDebugMarkers);
    end;
  except
    { Ignore malformed JSON }
  end;
  FreeAndNil(Data);
end;

function TCastleGameplayDebugger.DebuggerSummaryBadge: String;
begin
  Result := Format('[GDebug:%s Mask=%d Lines=%d]', [
    BoolToStr(FOverlayActive, 'ON', 'OFF'),
    FChannelMask,
    FHudLines.Count]);
end;

initialization
  RegisterSerializableComponent(TCastleGameplayDebugger, ['Profiling & QA', 'GameplayDebugger 3D HUD & Channels']);
end.
