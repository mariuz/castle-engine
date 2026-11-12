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

{ Smart Objects with Claimable Interaction Slots, Response-Curve Utility AI
  Scorer & RVO-Style Crowd Local Separation (@link(TCastleSmartObject),
  @link(TCastleUtilityAiBehavior))
  (Phase 314 — UE 6.0+ SmartObjects & Utility AI Parity). }
unit CastleUtilityAi;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Generics.Collections,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform,
  CastleBehaviors, CastleScene, X3DNodes;

type
  { Mathematical response curve mapping a normalized [0..1] Need value to [0..1] urgency. }
  TUtilityResponseCurve = (
    urcLinearDeficit,
    urcQuadraticUrgency,
    urcLogisticSigmoid,
    urcInverseAbundance
  );

  { Preset world station archetype for @link(TCastleSmartObject). }
  TSmartObjectPreset = (
    sopCustom,
    sopCampfireRestBench,
    sopTavernMealTable,
    sopBlacksmithWorkAnvil,
    sopWatchtowerPost
  );

  { Preset autonomous NPC profile for @link(TCastleUtilityAiBehavior). }
  TUtilityAgentPreset = (
    uapVillagerArtisan,
    uapTownGuard
  );

  { Normalized [0..1] homeostatic need tracked by @link(TCastleUtilityAiBehavior). }
  TUtilityNeedDef = class
  public
    NeedName: String;
    Value: Single;
    DecayPerSec: Single;
    constructor Create;
  end;
  TUtilityNeedDefList = {$ifdef FPC}specialize{$endif} TObjectList<TUtilityNeedDef>;

  { Scored candidate action in @link(TCastleUtilityAiBehavior). }
  TUtilityActionDef = class
  public
    ActionId: String;
    NeedName: String;
    Curve: TUtilityResponseCurve;
    Exponent: Single;
    Weight: Single;
    TargetSmartObjectTag: String;
    constructor Create;
  end;
  TUtilityActionDefList = {$ifdef FPC}specialize{$endif} TObjectList<TUtilityActionDef>;

  { Claimable interactive world station (@link(TCastleTransform)) advertising
    ranked interaction slots and need-restoration rates to nearby Utility AI agents. }
  TCastleSmartObject = class(TCastleTransform)
  public
    const
      DefaultMaxUsers = 2;
      DefaultInteractionRadius = 1.25;
      DefaultRestoreRatePerSec = 0.40;
      DefaultRecommendedUseDurationSec = 2.5;
  strict private
    FPreset: TSmartObjectPreset;
    FSmartObjectTag: String;
    FMaxUsers: Integer;
    FInteractionRadius: Single;
    FRestoresNeedName: String;
    FRestoreRatePerSec: Single;
    FRecommendedUseDurationSec: Single;
    FEnabledStation: Boolean;
    FMarkerColor: TCastleColorRGB;
    FMarkerColorPersistent: TCastleColorRGBPersistent;

    FSlotClaimants: array of TComponent;
    FRenderScene: TCastleScene;
    FRootNode: TX3DRootNode;
    FMaterialNode: TPhysicalMaterialNode;
    FTriSetNode: TTriangleSetNode;
    FCoordNode: TCoordinateNode;
    FNormalNode: TNormalNode;

    procedure SetPreset(const Value: TSmartObjectPreset);
    procedure SetMaxUsers(const Value: Integer);
    procedure SetInteractionRadius(const Value: Single);
    function GetMarkerColorForPersistent: TCastleColorRGB;
    procedure SetMarkerColorForPersistent(const AValue: TCastleColorRGB);
    procedure EnsureSlotCapacity;
    procedure EnsurePreviewMesh;
    procedure RebuildPreviewMesh;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TSmartObjectPreset);

    function ActiveUserCount: Integer;
    function HasFreeSlot: Boolean;
    function HasSlotForOrFree(const AClaimant: TComponent): Boolean;
    function GetSlotWorldPos(const ASlotIndex: Integer): TVector3;

    { Claim a free slot (or return the already-claimed slot) for @code(AClaimant). }
    function TryClaimSlot(const AClaimant: TComponent;
      out OutSlotIndex: Integer; out OutSlotWorldPos: TVector3): Boolean;
    procedure ReleaseSlot(const AClaimant: TComponent);
    procedure ReleaseAllSlots;

    function SmartObjectSummaryBadge: String;

    property MarkerColor: TCastleColorRGB read FMarkerColor write FMarkerColor;
  published
    property Preset: TSmartObjectPreset
      read FPreset write SetPreset default sopCampfireRestBench;
    property SmartObjectTag: String read FSmartObjectTag write FSmartObjectTag;
    property MaxUsers: Integer read FMaxUsers write SetMaxUsers default DefaultMaxUsers;
    property InteractionRadius: Single
      read FInteractionRadius write SetInteractionRadius {$ifdef FPC}default DefaultInteractionRadius{$endif};
    property RestoresNeedName: String read FRestoresNeedName write FRestoresNeedName;
    property RestoreRatePerSec: Single
      read FRestoreRatePerSec write FRestoreRatePerSec {$ifdef FPC}default DefaultRestoreRatePerSec{$endif};
    property RecommendedUseDurationSec: Single
      read FRecommendedUseDurationSec write FRecommendedUseDurationSec {$ifdef FPC}default DefaultRecommendedUseDurationSec{$endif};
    property EnabledStation: Boolean
      read FEnabledStation write FEnabledStation default True;
    property MarkerColorPersistent: TCastleColorRGBPersistent read FMarkerColorPersistent;
  end;

  { Response-curve Utility AI & RVO-style crowd separation behavior
    (@link(TCastleBehavior)) driving autonomous NPCs across claimable
    @link(TCastleSmartObject) stations. }
  TCastleUtilityAiBehavior = class(TCastleBehavior)
  public
    const
      DefaultMoveSpeed = 3.6;
      DefaultSeparationRadius = 1.65;
      DefaultSeparationWeight = 2.4;
      DefaultDecisionHysteresisBonus = 0.08;
  strict private
    FPresetName: String;
    FNeeds: TUtilityNeedDefList;
    FActions: TUtilityActionDefList;
    FMoveSpeed: Single;
    FSeparationRadius: Single;
    FSeparationWeight: Single;
    FDecisionHysteresisBonus: Single;
    FSimulateInEditor: Boolean;

    FCurrentActionId: String;
    FClaimedSmartObject: TCastleSmartObject;
    FClaimedSlotIndex: Integer;
    FIsUsingSmartObject: Boolean;
    FUseElapsedSec: Single;
    FLastVelocityWorld: TVector3;

    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    function FindNeedObj(const ANeedName: String): TUtilityNeedDef;
    function FindAvailableSmartObject(const ATagFilter: String): TCastleSmartObject;
    function ComputeCrowdSeparationDir(const MyWorldPos: TVector3): TVector3;
    procedure ReleaseCurrentClaim;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TUtilityAgentPreset);

    procedure SetNeed(const ANeedName: String; const AValue: Single;
      const ADecayPerSec: Single = -1.0);
    function GetNeed(const ANeedName: String): Single;

    function EvaluateActionScore(const AIndex: Integer): Single;
    procedure StepUtilityAi(const Dt: Single);

    function UtilitySummaryBadge: String;

    property Needs: TUtilityNeedDefList read FNeeds;
    property Actions: TUtilityActionDefList read FActions;
    property CurrentActionId: String read FCurrentActionId;
    property ClaimedSmartObject: TCastleSmartObject read FClaimedSmartObject;
    property ClaimedSlotIndex: Integer read FClaimedSlotIndex;
    property IsUsingSmartObject: Boolean read FIsUsingSmartObject;
    property LastVelocityWorld: TVector3 read FLastVelocityWorld;
  published
    property PresetName: String read FPresetName write FPresetName;
    property MoveSpeed: Single
      read FMoveSpeed write FMoveSpeed {$ifdef FPC}default DefaultMoveSpeed{$endif};
    property SeparationRadius: Single
      read FSeparationRadius write FSeparationRadius {$ifdef FPC}default DefaultSeparationRadius{$endif};
    property SeparationWeight: Single
      read FSeparationWeight write FSeparationWeight {$ifdef FPC}default DefaultSeparationWeight{$endif};
    property DecisionHysteresisBonus: Single
      read FDecisionHysteresisBonus write FDecisionHysteresisBonus {$ifdef FPC}default DefaultDecisionHysteresisBonus{$endif};
    property SimulateInEditor: Boolean
      read FSimulateInEditor write FSimulateInEditor default False;
    property ConfigJson: String read GetConfigJson write SetConfigJson;
  end;

{ Evaluate normalized [0..1] utility urgency from a normalized [0..1] Need value. }
function EvaluateUtilityCurve(const ANeedValue: Single;
  const ACurve: TUtilityResponseCurve; const AExponent: Single = 2.0): Single;

function UtilityCurveToString(const ACurve: TUtilityResponseCurve): String;
function StringToUtilityCurve(const S: String): TUtilityResponseCurve;

implementation

uses
  Math, fpjson, jsonparser,
  CastleComponentSerialize, CastleApplicationProperties, CastleUtils;

function GetUtilHierarchyMatrix(const T: TCastleTransform): TMatrix4;
var
  Cur: TCastleTransform;
begin
  Result := TMatrix4.Identity;
  Cur := T;
  while (Cur <> nil) and (not (Cur is TCastleAbstractRootTransform)) do
  begin
    Result := Cur.Transform * Result;
    Cur := Cur.Parent;
  end;
end;

function GetUtilWorldPos(const T: TCastleTransform): TVector3;
begin
  if T = nil then
    Exit(TVector3.Zero);
  Result := GetUtilHierarchyMatrix(T).MultPoint(TVector3.Zero);
end;

procedure SetUtilWorldPos(const T: TCastleTransform; const AWorldPos: TVector3);
var
  ParentM, InvM: TMatrix4;
begin
  if T = nil then
    Exit;
  if (T.Parent <> nil) and (not (T.Parent is TCastleAbstractRootTransform)) then
  begin
    ParentM := GetUtilHierarchyMatrix(T.Parent);
    if ParentM.TryInverse(InvM) then
    begin
      T.Translation := InvM.MultPoint(AWorldPos);
      Exit;
    end;
  end;
  T.Translation := AWorldPos;
end;

function EvaluateUtilityCurve(const ANeedValue: Single;
  const ACurve: TUtilityResponseCurve; const AExponent: Single): Single;
var
  U: Single;
begin
  U := Clamped(ANeedValue, 0.0, 1.0);
  case ACurve of
    urcLinearDeficit:
      Result := 1.0 - U;
    urcQuadraticUrgency:
      Result := Power(1.0 - U, Max(0.25, AExponent));
    urcLogisticSigmoid:
      Result := 1.0 / (1.0 + Exp(10.0 * (U - 0.35)));
    urcInverseAbundance:
      Result := U;
  end;
  Result := Clamped(Result, 0.0, 1.0);
end;

function UtilityCurveToString(const ACurve: TUtilityResponseCurve): String;
begin
  case ACurve of
    urcLinearDeficit:    Result := 'LinearDeficit';
    urcQuadraticUrgency: Result := 'QuadraticUrgency';
    urcLogisticSigmoid:  Result := 'LogisticSigmoid';
    urcInverseAbundance: Result := 'InverseAbundance';
  end;
end;

function StringToUtilityCurve(const S: String): TUtilityResponseCurve;
begin
  if SameText(S, 'QuadraticUrgency') then
    Result := urcQuadraticUrgency
  else if SameText(S, 'LogisticSigmoid') then
    Result := urcLogisticSigmoid
  else if SameText(S, 'InverseAbundance') then
    Result := urcInverseAbundance
  else
    Result := urcLinearDeficit;
end;

function MatchesSmartTag(const AActualTag, APattern: String): Boolean;
var
  Prefix: String;
begin
  if APattern = '' then
    Exit(True);
  if SameText(AActualTag, APattern) then
    Exit(True);
  if Copy(APattern, Length(APattern) - 1, 2) = '.*' then
  begin
    Prefix := Copy(APattern, 1, Length(APattern) - 2);
    Result := SameText(AActualTag, Prefix) or
      SameText(Copy(AActualTag, 1, Length(Prefix) + 1), Prefix + '.');
  end else
    Result := False;
end;

{ TUtilityNeedDef & TUtilityActionDef ---------------------------------------- }

constructor TUtilityNeedDef.Create;
begin
  inherited Create;
  NeedName := 'Energy';
  Value := 0.80;
  DecayPerSec := 0.04;
end;

constructor TUtilityActionDef.Create;
begin
  inherited Create;
  ActionId := 'RestAtCampfire';
  NeedName := 'Energy';
  Curve := urcQuadraticUrgency;
  Exponent := 2.0;
  Weight := 1.0;
  TargetSmartObjectTag := 'SmartObject.Rest';
end;

{ TCastleSmartObject --------------------------------------------------------- }

constructor TCastleSmartObject.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := sopCampfireRestBench;
  FMaxUsers := DefaultMaxUsers;
  FInteractionRadius := DefaultInteractionRadius;
  FRestoreRatePerSec := DefaultRestoreRatePerSec;
  FRecommendedUseDurationSec := DefaultRecommendedUseDurationSec;
  FEnabledStation := True;
  FMarkerColor := Vector3(0.92, 0.46, 0.16);

  FMarkerColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FMarkerColorPersistent.SetSubComponent(True);
  FMarkerColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetMarkerColorForPersistent;
  FMarkerColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetMarkerColorForPersistent;
  FMarkerColorPersistent.InternalDefaultValue := FMarkerColor;

  EnsureSlotCapacity;
  ApplyPreset(sopCampfireRestBench);
end;

destructor TCastleSmartObject.Destroy;
begin
  ReleaseAllSlots;
  if FRenderScene <> nil then
  begin
    Remove(FRenderScene);
    FreeAndNil(FRenderScene);
  end;
  FreeAndNil(FMarkerColorPersistent);
  inherited;
end;

procedure TCastleSmartObject.Notification(AComponent: TComponent; Operation: TOperation);
var
  I: Integer;
begin
  inherited;
  if Operation = opRemove then
    for I := 0 to High(FSlotClaimants) do
      if FSlotClaimants[I] = AComponent then
        FSlotClaimants[I] := nil;
end;

procedure TCastleSmartObject.Loaded;
begin
  inherited;
  EnsureSlotCapacity;
  RebuildPreviewMesh;
end;

function TCastleSmartObject.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'SmartObjectTag', 'MaxUsers', 'InteractionRadius',
       'RestoresNeedName', 'RestoreRatePerSec', 'RecommendedUseDurationSec',
       'EnabledStation', 'MarkerColorPersistent'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleSmartObject.GetMarkerColorForPersistent: TCastleColorRGB;
begin
  Result := FMarkerColor;
end;

procedure TCastleSmartObject.SetMarkerColorForPersistent(const AValue: TCastleColorRGB);
begin
  FMarkerColor := AValue;
  if FMaterialNode <> nil then
    FMaterialNode.BaseColor := FMarkerColor;
end;

procedure TCastleSmartObject.EnsureSlotCapacity;
var
  OldLen, I: Integer;
begin
  FMaxUsers := Clamped(FMaxUsers, 1, 8);
  OldLen := Length(FSlotClaimants);
  if OldLen > FMaxUsers then
    for I := FMaxUsers to OldLen - 1 do
      if FSlotClaimants[I] <> nil then
      begin
        FSlotClaimants[I].RemoveFreeNotification(Self);
        FSlotClaimants[I] := nil;
      end;
  SetLength(FSlotClaimants, FMaxUsers);
  for I := OldLen to FMaxUsers - 1 do
    FSlotClaimants[I] := nil;
end;

procedure TCastleSmartObject.SetPreset(const Value: TSmartObjectPreset);
begin
  if FPreset <> Value then
  begin
    if Value = sopCustom then
      FPreset := sopCustom
    else
      ApplyPreset(Value);
  end;
end;

procedure TCastleSmartObject.SetMaxUsers(const Value: Integer);
begin
  FMaxUsers := Clamped(Value, 1, 8);
  EnsureSlotCapacity;
end;

procedure TCastleSmartObject.SetInteractionRadius(const Value: Single);
begin
  FInteractionRadius := Clamped(Value, 0.3, 10.0);
end;

procedure TCastleSmartObject.ApplyPreset(const APreset: TSmartObjectPreset);
begin
  FPreset := APreset;
  case APreset of
    sopCampfireRestBench, sopCustom:
      begin
        FSmartObjectTag := 'SmartObject.Rest';
        FRestoresNeedName := 'Energy';
        FMaxUsers := 2;
        FInteractionRadius := 1.3;
        FRestoreRatePerSec := 0.42;
        FRecommendedUseDurationSec := 2.5;
        FMarkerColor := Vector3(0.92, 0.46, 0.16);
      end;

    sopTavernMealTable:
      begin
        FSmartObjectTag := 'SmartObject.Food';
        FRestoresNeedName := 'Hunger';
        FMaxUsers := 3;
        FInteractionRadius := 1.4;
        FRestoreRatePerSec := 0.45;
        FRecommendedUseDurationSec := 2.2;
        FMarkerColor := Vector3(0.82, 0.66, 0.22);
      end;

    sopBlacksmithWorkAnvil:
      begin
        FSmartObjectTag := 'SmartObject.Work';
        FRestoresNeedName := 'CraftProgress';
        FMaxUsers := 1;
        FInteractionRadius := 1.0;
        FRestoreRatePerSec := 0.30;
        FRecommendedUseDurationSec := 3.0;
        FMarkerColor := Vector3(0.36, 0.44, 0.56);
      end;

    sopWatchtowerPost:
      begin
        FSmartObjectTag := 'SmartObject.Guard';
        FRestoresNeedName := 'Duty';
        FMaxUsers := 1;
        FInteractionRadius := 1.1;
        FRestoreRatePerSec := 0.35;
        FRecommendedUseDurationSec := 3.0;
        FMarkerColor := Vector3(0.24, 0.68, 0.52);
      end;
  end;
  EnsureSlotCapacity;
  if not (csLoading in ComponentState) then
    RebuildPreviewMesh;
end;

procedure TCastleSmartObject.EnsurePreviewMesh;
var
  ShapeNode: TShapeNode;
  AppNode: TAppearanceNode;
begin
  if FRenderScene <> nil then
    Exit;

  FRenderScene := TCastleScene.Create(nil);
  FRenderScene.SetTransient;
  FRenderScene.Pickable := False;
  FRenderScene.Collides := False;

  FRootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  AppNode := TAppearanceNode.Create;
  FMaterialNode := TPhysicalMaterialNode.Create;
  FMaterialNode.BaseColor := FMarkerColor;
  FMaterialNode.Roughness := 0.55;
  AppNode.Material := FMaterialNode;
  ShapeNode.Appearance := AppNode;

  FTriSetNode := TTriangleSetNode.Create;
  FTriSetNode.Solid := False;
  FCoordNode := TCoordinateNode.Create;
  FTriSetNode.Coord := FCoordNode;
  FNormalNode := TNormalNode.Create;
  FTriSetNode.Normal := FNormalNode;

  ShapeNode.Geometry := FTriSetNode;
  FRootNode.AddChildren(ShapeNode);
  FRenderScene.Load(FRootNode, True);
  Add(FRenderScene);
end;

procedure TCastleSmartObject.RebuildPreviewMesh;
const
  Sides = 8;
var
  Verts, Norms: array of TVector3;
  S, NextS, OutIdx: Integer;
  A0, A1, RTop, HTop: Single;
  P0, P1, PTop0, PTop1, N0, N1: TVector3;
begin
  EnsurePreviewMesh;
  if FMaterialNode <> nil then
    FMaterialNode.BaseColor := FMarkerColor;

  RTop := 0.45;
  HTop := 0.65;
  SetLength(Verts, Sides * 9);
  SetLength(Norms, Sides * 9);
  OutIdx := 0;

  for S := 0 to Sides - 1 do
  begin
    NextS := (S + 1) mod Sides;
    A0 := (2.0 * Pi * S) / Sides;
    A1 := (2.0 * Pi * NextS) / Sides;
    N0 := Vector3(Cos(A0), 0.0, Sin(A0));
    N1 := Vector3(Cos(A1), 0.0, Sin(A1));
    P0 := N0 * RTop;
    P1 := N1 * RTop;
    PTop0 := P0 + Vector3(0.0, HTop, 0.0);
    PTop1 := P1 + Vector3(0.0, HTop, 0.0);

    Verts[OutIdx] := P0;    Norms[OutIdx] := N0; Inc(OutIdx);
    Verts[OutIdx] := PTop0; Norms[OutIdx] := N0; Inc(OutIdx);
    Verts[OutIdx] := P1;    Norms[OutIdx] := N1; Inc(OutIdx);

    Verts[OutIdx] := P1;    Norms[OutIdx] := N1; Inc(OutIdx);
    Verts[OutIdx] := PTop0; Norms[OutIdx] := N0; Inc(OutIdx);
    Verts[OutIdx] := PTop1; Norms[OutIdx] := N1; Inc(OutIdx);

    Verts[OutIdx] := Vector3(0.0, HTop, 0.0); Norms[OutIdx] := Vector3(0.0, 1.0, 0.0); Inc(OutIdx);
    Verts[OutIdx] := PTop1;                   Norms[OutIdx] := Vector3(0.0, 1.0, 0.0); Inc(OutIdx);
    Verts[OutIdx] := PTop0;                   Norms[OutIdx] := Vector3(0.0, 1.0, 0.0); Inc(OutIdx);
  end;

  FCoordNode.SetPoint(Verts);
  FNormalNode.SetVector(Norms);
end;

function TCastleSmartObject.ActiveUserCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FSlotClaimants) do
    if FSlotClaimants[I] <> nil then
      Inc(Result);
end;

function TCastleSmartObject.HasFreeSlot: Boolean;
begin
  Result := FEnabledStation and (ActiveUserCount < FMaxUsers);
end;

function TCastleSmartObject.HasSlotForOrFree(const AClaimant: TComponent): Boolean;
var
  I: Integer;
begin
  if (not FEnabledStation) or (not Exists) then
    Exit(False);
  for I := 0 to High(FSlotClaimants) do
    if (FSlotClaimants[I] = AClaimant) or (FSlotClaimants[I] = nil) then
      Exit(True);
  Result := False;
end;

function TCastleSmartObject.GetSlotWorldPos(const ASlotIndex: Integer): TVector3;
var
  Ang: Single;
  LocalSlot: TVector3;
begin
  EnsureSlotCapacity;
  Ang := (2.0 * Pi * Clamped(ASlotIndex, 0, FMaxUsers - 1)) / Max(1, FMaxUsers);
  LocalSlot := Vector3(Cos(Ang) * FInteractionRadius, 0.0, Sin(Ang) * FInteractionRadius);
  Result := GetUtilHierarchyMatrix(Self).MultPoint(LocalSlot);
end;

function TCastleSmartObject.TryClaimSlot(const AClaimant: TComponent;
  out OutSlotIndex: Integer; out OutSlotWorldPos: TVector3): Boolean;
var
  I: Integer;
begin
  OutSlotIndex := -1;
  OutSlotWorldPos := TVector3.Zero;
  if (AClaimant = nil) or (not FEnabledStation) or (not Exists) then
    Exit(False);

  EnsureSlotCapacity;
  { Already claimed by AClaimant? }
  for I := 0 to High(FSlotClaimants) do
    if FSlotClaimants[I] = AClaimant then
    begin
      OutSlotIndex := I;
      OutSlotWorldPos := GetSlotWorldPos(I);
      Exit(True);
    end;

  { Claim first free slot }
  for I := 0 to High(FSlotClaimants) do
    if FSlotClaimants[I] = nil then
    begin
      FSlotClaimants[I] := AClaimant;
      AClaimant.FreeNotification(Self);
      OutSlotIndex := I;
      OutSlotWorldPos := GetSlotWorldPos(I);
      Exit(True);
    end;

  Result := False;
end;

procedure TCastleSmartObject.ReleaseSlot(const AClaimant: TComponent);
var
  I: Integer;
begin
  if AClaimant = nil then
    Exit;
  for I := 0 to High(FSlotClaimants) do
    if FSlotClaimants[I] = AClaimant then
    begin
      AClaimant.RemoveFreeNotification(Self);
      FSlotClaimants[I] := nil;
    end;
end;

procedure TCastleSmartObject.ReleaseAllSlots;
var
  I: Integer;
begin
  for I := 0 to High(FSlotClaimants) do
    if FSlotClaimants[I] <> nil then
    begin
      FSlotClaimants[I].RemoveFreeNotification(Self);
      FSlotClaimants[I] := nil;
    end;
end;

function TCastleSmartObject.SmartObjectSummaryBadge: String;
begin
  Result := Format('[SmartObj:%s %d/%d %s]',
    [FSmartObjectTag, ActiveUserCount, FMaxUsers, FRestoresNeedName]);
end;

{ TCastleUtilityAiBehavior --------------------------------------------------- }

constructor TCastleUtilityAiBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FNeeds := TUtilityNeedDefList.Create(True);
  FActions := TUtilityActionDefList.Create(True);
  FMoveSpeed := DefaultMoveSpeed;
  FSeparationRadius := DefaultSeparationRadius;
  FSeparationWeight := DefaultSeparationWeight;
  FDecisionHysteresisBonus := DefaultDecisionHysteresisBonus;
  FSimulateInEditor := False;
  FClaimedSlotIndex := -1;
  FLastVelocityWorld := TVector3.Zero;

  ApplyPreset(uapVillagerArtisan);
end;

destructor TCastleUtilityAiBehavior.Destroy;
begin
  ReleaseCurrentClaim;
  FreeAndNil(FActions);
  FreeAndNil(FNeeds);
  inherited;
end;

procedure TCastleUtilityAiBehavior.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FClaimedSmartObject) then
  begin
    FClaimedSmartObject := nil;
    FClaimedSlotIndex := -1;
    FIsUsingSmartObject := False;
  end;
end;

function TCastleUtilityAiBehavior.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'PresetName', 'MoveSpeed', 'SeparationRadius', 'SeparationWeight',
       'DecisionHysteresisBonus', 'SimulateInEditor', 'ConfigJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleUtilityAiBehavior.ReleaseCurrentClaim;
begin
  if FClaimedSmartObject <> nil then
  begin
    FClaimedSmartObject.ReleaseSlot(Self);
    FClaimedSmartObject.RemoveFreeNotification(Self);
    FClaimedSmartObject := nil;
  end;
  FClaimedSlotIndex := -1;
  FIsUsingSmartObject := False;
  FUseElapsedSec := 0.0;
end;

procedure TCastleUtilityAiBehavior.ApplyPreset(const APreset: TUtilityAgentPreset);

  procedure AddNeedDef(const AName: String; const AVal, ADecay: Single);
  var
    ND: TUtilityNeedDef;
  begin
    ND := TUtilityNeedDef.Create;
    ND.NeedName := AName;
    ND.Value := AVal;
    ND.DecayPerSec := ADecay;
    FNeeds.Add(ND);
  end;

  procedure AddActDef(const AId, ANeed: String; const ACurve: TUtilityResponseCurve;
    const AWeight: Single; const ATag: String);
  var
    AD: TUtilityActionDef;
  begin
    AD := TUtilityActionDef.Create;
    AD.ActionId := AId;
    AD.NeedName := ANeed;
    AD.Curve := ACurve;
    AD.Exponent := 2.0;
    AD.Weight := AWeight;
    AD.TargetSmartObjectTag := ATag;
    FActions.Add(AD);
  end;

begin
  ReleaseCurrentClaim;
  FNeeds.Clear;
  FActions.Clear;

  case APreset of
    uapVillagerArtisan:
      begin
        FPresetName := 'VillagerArtisan';
        AddNeedDef('Energy', 0.75, 0.05);
        AddNeedDef('Hunger', 0.65, 0.06);
        AddNeedDef('CraftProgress', 0.30, 0.02);

        AddActDef('SleepAtCampfire', 'Energy', urcQuadraticUrgency, 1.15, 'SmartObject.Rest');
        AddActDef('EatAtTavern', 'Hunger', urcLogisticSigmoid, 1.05, 'SmartObject.Food');
        AddActDef('ForgeAtAnvil', 'Energy', urcInverseAbundance, 0.55, 'SmartObject.Work');
      end;

    uapTownGuard:
      begin
        FPresetName := 'TownGuard';
        AddNeedDef('Energy', 0.85, 0.04);
        AddNeedDef('Hunger', 0.80, 0.05);
        AddNeedDef('Duty', 0.25, 0.07);

        AddActDef('RestAtCampfire', 'Energy', urcQuadraticUrgency, 1.20, 'SmartObject.Rest');
        AddActDef('EatRations', 'Hunger', urcLinearDeficit, 1.00, 'SmartObject.Food');
        AddActDef('StandWatchtower', 'Duty', urcLinearDeficit, 0.90, 'SmartObject.Guard');
      end;
  end;
end;

function TCastleUtilityAiBehavior.FindNeedObj(const ANeedName: String): TUtilityNeedDef;
var
  I: Integer;
begin
  for I := 0 to FNeeds.Count - 1 do
    if SameText(FNeeds[I].NeedName, ANeedName) then
      Exit(FNeeds[I]);
  Result := nil;
end;

procedure TCastleUtilityAiBehavior.SetNeed(const ANeedName: String;
  const AValue: Single; const ADecayPerSec: Single);
var
  ND: TUtilityNeedDef;
begin
  ND := FindNeedObj(ANeedName);
  if ND = nil then
  begin
    ND := TUtilityNeedDef.Create;
    ND.NeedName := ANeedName;
    ND.DecayPerSec := 0.04;
    FNeeds.Add(ND);
  end;
  ND.Value := Clamped(AValue, 0.0, 1.0);
  if ADecayPerSec >= 0.0 then
    ND.DecayPerSec := ADecayPerSec;
end;

function TCastleUtilityAiBehavior.GetNeed(const ANeedName: String): Single;
var
  ND: TUtilityNeedDef;
begin
  ND := FindNeedObj(ANeedName);
  if ND <> nil then
    Result := ND.Value
  else
    Result := 0.0;
end;

function TCastleUtilityAiBehavior.FindAvailableSmartObject(
  const ATagFilter: String): TCastleSmartObject;
var
  MyPos: TVector3;
  BestDistSqr: Single;
  BestObj: TCastleSmartObject;

  procedure ConsiderStation(const SO: TCastleSmartObject);
  var
    DSqr: Single;
  begin
    if (SO = nil) or (not MatchesSmartTag(SO.SmartObjectTag, ATagFilter)) then
      Exit;
    if not SO.HasSlotForOrFree(Self) then
      Exit;
    DSqr := PointsDistanceSqr(MyPos, GetUtilWorldPos(SO));
    if (BestObj = nil) or (DSqr < BestDistSqr) then
    begin
      BestDistSqr := DSqr;
      BestObj := SO;
    end;
  end;

  procedure ScanHierarchy(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if (T = nil) or (csTransient in T.ComponentStyle) then
      Exit;
    if T is TCastleSmartObject then
      ConsiderStation(TCastleSmartObject(T));
    for I := 0 to T.Count - 1 do
      ScanHierarchy(T[I]);
  end;

var
  RootT: TCastleTransform;
  I: Integer;
begin
  BestObj := nil;
  BestDistSqr := MaxSingle;
  MyPos := GetUtilWorldPos(Parent);

  if Parent <> nil then
  begin
    RootT := Parent;
    while RootT.Parent <> nil do
      RootT := RootT.Parent;
    ScanHierarchy(RootT);
  end;
  if Owner <> nil then
    for I := 0 to Owner.ComponentCount - 1 do
      if Owner.Components[I] is TCastleSmartObject then
        ConsiderStation(TCastleSmartObject(Owner.Components[I]));

  Result := BestObj;
end;

function TCastleUtilityAiBehavior.ComputeCrowdSeparationDir(
  const MyWorldPos: TVector3): TVector3;
var
  RepelAccum: TVector3;

  procedure ConsiderTransform(const T: TCastleTransform);
  var
    OtherAI: TCastleUtilityAiBehavior;
    OtherPos, DiffXZ: TVector3;
    Dist, Strength: Single;
  begin
    if (T = nil) or (T = Parent) or (not T.Exists) then
      Exit;
    OtherAI := T.FindBehavior(TCastleUtilityAiBehavior) as TCastleUtilityAiBehavior;
    if OtherAI = nil then
      Exit;

    OtherPos := GetUtilWorldPos(T);
    DiffXZ := Vector3(MyWorldPos.X - OtherPos.X, 0.0, MyWorldPos.Z - OtherPos.Z);
    Dist := DiffXZ.Length;
    if Dist < FSeparationRadius then
    begin
      Strength := (FSeparationRadius - Dist) / Max(0.05, FSeparationRadius);
      if Dist < 1.0e-4 then
        DiffXZ := Vector3(1.0, 0.0, 0.0)
      else
        DiffXZ := DiffXZ / Dist;
      RepelAccum := RepelAccum + DiffXZ * Strength;
    end;
  end;

  procedure ScanHierarchy(const T: TCastleTransform);
  var
    I: Integer;
  begin
    if (T = nil) or (csTransient in T.ComponentStyle) then
      Exit;
    ConsiderTransform(T);
    for I := 0 to T.Count - 1 do
      ScanHierarchy(T[I]);
  end;

var
  RootT: TCastleTransform;
begin
  RepelAccum := TVector3.Zero;
  if (FSeparationRadius <= 0.01) or (Parent = nil) then
    Exit(TVector3.Zero);

  RootT := Parent;
  while RootT.Parent <> nil do
    RootT := RootT.Parent;
  ScanHierarchy(RootT);

  Result := RepelAccum;
end;

function TCastleUtilityAiBehavior.EvaluateActionScore(const AIndex: Integer): Single;
var
  AD: TUtilityActionDef;
  Station: TCastleSmartObject;
begin
  if (AIndex < 0) or (AIndex >= FActions.Count) then
    Exit(0.0);
  AD := FActions[AIndex];
  if AD.TargetSmartObjectTag <> '' then
  begin
    Station := FindAvailableSmartObject(AD.TargetSmartObjectTag);
    if Station = nil then
      Exit(0.0);
  end;
  Result := EvaluateUtilityCurve(GetNeed(AD.NeedName), AD.Curve, AD.Exponent) * AD.Weight;
  if SameText(AD.ActionId, FCurrentActionId) and (Result > 0.0) then
    Result := Result + FDecisionHysteresisBonus;
end;

procedure TCastleUtilityAiBehavior.StepUtilityAi(const Dt: Single);
var
  I, BestIdx, ClaimIdx: Integer;
  BestScore, CandScore, StepDist, DistToGoal: Single;
  BestAct: TUtilityActionDef;
  TargetSO: TCastleSmartObject;
  SlotWorldPos, MyPos, ToGoalXZ, SeekDir, SepDir, DesiredVel: TVector3;
  RestoredND: TUtilityNeedDef;
begin
  if (Dt <= 0.0) or (Parent = nil) then
    Exit;

  { 1. Passive homeostatic need decay (skip need currently being actively restored) }
  for I := 0 to FNeeds.Count - 1 do
  begin
    if FIsUsingSmartObject and (FClaimedSmartObject <> nil) and
       SameText(FNeeds[I].NeedName, FClaimedSmartObject.RestoresNeedName) then
      Continue;
    FNeeds[I].Value := Clamped(FNeeds[I].Value - FNeeds[I].DecayPerSec * Dt, 0.0, 1.0);
  end;

  { 2. Score actions and select winning behavior (unless actively committed in a station slot) }
  if not (FIsUsingSmartObject and (FClaimedSmartObject <> nil) and
          FClaimedSmartObject.EnabledStation and FClaimedSmartObject.Exists) then
  begin
    BestIdx := -1;
    BestScore := 0.0;
    for I := 0 to FActions.Count - 1 do
    begin
      CandScore := EvaluateActionScore(I);
      if CandScore > BestScore then
      begin
        BestScore := CandScore;
        BestIdx := I;
      end;
    end;

    if BestIdx < 0 then
    begin
      ReleaseCurrentClaim;
      FCurrentActionId := 'Idle';
      FLastVelocityWorld := TVector3.Zero;
      Exit;
    end;

    BestAct := FActions[BestIdx];
    if not SameText(BestAct.ActionId, FCurrentActionId) then
    begin
      ReleaseCurrentClaim;
      FCurrentActionId := BestAct.ActionId;
    end;

    { 3. Resolve & claim SmartObject interaction slot }
    TargetSO := FClaimedSmartObject;
    if (TargetSO = nil) or (not MatchesSmartTag(TargetSO.SmartObjectTag, BestAct.TargetSmartObjectTag)) then
    begin
      ReleaseCurrentClaim;
      TargetSO := FindAvailableSmartObject(BestAct.TargetSmartObjectTag);
      if (TargetSO <> nil) and TargetSO.TryClaimSlot(Self, ClaimIdx, SlotWorldPos) then
      begin
        FClaimedSmartObject := TargetSO;
        FClaimedSmartObject.FreeNotification(Self);
        FClaimedSlotIndex := ClaimIdx;
      end;
    end;
  end;

  MyPos := GetUtilWorldPos(Parent);
  if FClaimedSmartObject = nil then
  begin
    FLastVelocityWorld := TVector3.Zero;
    Exit;
  end;

  SlotWorldPos := FClaimedSmartObject.GetSlotWorldPos(FClaimedSlotIndex);
  ToGoalXZ := Vector3(SlotWorldPos.X - MyPos.X, 0.0, SlotWorldPos.Z - MyPos.Z);
  DistToGoal := ToGoalXZ.Length;

  { 4. Approach with RVO-style crowd separation, or interact in slot }
  if DistToGoal > 0.32 then
  begin
    FIsUsingSmartObject := False;
    SeekDir := ToGoalXZ / DistToGoal;
    SepDir := ComputeCrowdSeparationDir(MyPos) * FSeparationWeight;
    DesiredVel := SeekDir + SepDir;
    if DesiredVel.LengthSqr > 1.0e-6 then
      DesiredVel := DesiredVel.Normalize * FMoveSpeed
    else
      DesiredVel := SeekDir * FMoveSpeed;

    StepDist := Min(DistToGoal, FMoveSpeed * Dt);
    FLastVelocityWorld := DesiredVel;
    MyPos := MyPos + DesiredVel.Normalize * StepDist;
    SetUtilWorldPos(Parent, MyPos);
  end else
  begin
    FIsUsingSmartObject := True;
    FUseElapsedSec := FUseElapsedSec + Dt;
    FLastVelocityWorld := TVector3.Zero;

    RestoredND := FindNeedObj(FClaimedSmartObject.RestoresNeedName);
    if RestoredND <> nil then
    begin
      RestoredND.Value := Clamped(
        RestoredND.Value + FClaimedSmartObject.RestoreRatePerSec * Dt, 0.0, 1.0);
      if (RestoredND.Value >= 0.98) or
         (FUseElapsedSec >= FClaimedSmartObject.RecommendedUseDurationSec) then
      begin
        ReleaseCurrentClaim;
        FCurrentActionId := '';
      end;
    end;
  end;
end;

procedure TCastleUtilityAiBehavior.Update(
  const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepUtilityAi(SecondsPassed);
end;

function TCastleUtilityAiBehavior.GetConfigJson: String;
var
  RootObj, ItemObj: TJSONObject;
  NeedsArr, ActsArr: TJSONArray;
  I: Integer;
begin
  RootObj := TJSONObject.Create;
  try
    NeedsArr := TJSONArray.Create;
    for I := 0 to FNeeds.Count - 1 do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('name', FNeeds[I].NeedName);
      ItemObj.Add('val', FNeeds[I].Value);
      ItemObj.Add('decay', FNeeds[I].DecayPerSec);
      NeedsArr.Add(ItemObj);
    end;
    RootObj.Add('needs', NeedsArr);

    ActsArr := TJSONArray.Create;
    for I := 0 to FActions.Count - 1 do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.Add('id', FActions[I].ActionId);
      ItemObj.Add('need', FActions[I].NeedName);
      ItemObj.Add('curve', UtilityCurveToString(FActions[I].Curve));
      ItemObj.Add('exp', FActions[I].Exponent);
      ItemObj.Add('weight', FActions[I].Weight);
      ItemObj.Add('tag', FActions[I].TargetSmartObjectTag);
      ActsArr.Add(ItemObj);
    end;
    RootObj.Add('actions', ActsArr);
    Result := RootObj.AsJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleUtilityAiBehavior.SetConfigJson(const Value: String);
var
  Data: TJSONData;
  RootObj, ItemObj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  ND: TUtilityNeedDef;
  AD: TUtilityActionDef;
begin
  if Trim(Value) = '' then
    Exit;
  Data := GetJSON(Value);
  try
    if not (Data is TJSONObject) then
      Exit;
    RootObj := TJSONObject(Data);
    ReleaseCurrentClaim;
    FNeeds.Clear;
    FActions.Clear;

    Arr := RootObj.Find('needs', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(Arr.Items[I]);
          ND := TUtilityNeedDef.Create;
          ND.NeedName := ItemObj.Get('name', 'Energy');
          ND.Value := Clamped(ItemObj.Get('val', 0.8), 0.0, 1.0);
          ND.DecayPerSec := Max(0.0, ItemObj.Get('decay', 0.04));
          FNeeds.Add(ND);
        end;

    Arr := RootObj.Find('actions', jtArray) as TJSONArray;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if Arr.Items[I] is TJSONObject then
        begin
          ItemObj := TJSONObject(Arr.Items[I]);
          AD := TUtilityActionDef.Create;
          AD.ActionId := ItemObj.Get('id', 'Action');
          AD.NeedName := ItemObj.Get('need', 'Energy');
          AD.Curve := StringToUtilityCurve(ItemObj.Get('curve', 'LinearDeficit'));
          AD.Exponent := ItemObj.Get('exp', 2.0);
          AD.Weight := ItemObj.Get('weight', 1.0);
          AD.TargetSmartObjectTag := ItemObj.Get('tag', '');
          FActions.Add(AD);
        end;
  finally
    FreeAndNil(Data);
  end;
end;

function TCastleUtilityAiBehavior.UtilitySummaryBadge: String;
var
  ActTxt: String;
begin
  if FCurrentActionId <> '' then
    ActTxt := FCurrentActionId
  else
    ActTxt := 'Ready';
  Result := Format('[UtilAI:%s -> %s]', [FPresetName, ActTxt]);
end;

initialization
  RegisterSerializableComponent(TCastleSmartObject, ['Smart Object Station']);
  RegisterSerializableComponent(TCastleUtilityAiBehavior, ['Utility AI & Crowd Agent']);
end.
