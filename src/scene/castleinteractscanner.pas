{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Gameplay player interaction focus scanner scoring nearby interactable
  transforms by gaze-cone alignment + proximity + priority tag, rejecting
  through-wall exploits via WorldRay line-of-sight gating, and driving tap vs.
  hold-to-interact progress with early-release decay (Phase 394). }
unit CastleInteractScanner;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Preset camera gaze vs. third-person proximity interaction profiles. }
  TInteractScannerPreset = (
    ispFirstPersonPrecisionGaze,
    ispThirdPersonActionCone,
    ispSurvivalTimedSabotage
  );

  { Current state of the focus & hold-to-interact state machine. }
  TInteractHoldStatus = (
    ihsIdleNoTarget,
    ihsFocusedReady,
    ihsHoldingInProgress,
    ihsCompletedCooldown
  );

  { Diagnostic score entry for a candidate interactable transform. }
  TInteractCandidateScore = record
    TargetName: String;
    WorldPos: TVector3;
    DistanceMeters: Single;
    GazeAngleDeg: Single;
    ObstructedByWall: Boolean;
    TotalScore: Single;
  end;

  { Scene transform attached to a player camera/character that selects the
    highest-scoring unobstructed interactable and manages hold-progress state. }
  TCastleInteractScanner = class(TCastleTransform)
  private
    FPreset: TInteractScannerPreset;
    FMaxInteractRangeMeters: Single;
    FMaxGazeHalfConeDeg: Single;
    FGazeAngleWeight: Single;
    FProximityWeight: Single;
    FInteractableNamePrefix: String;
    FRequireUnobstructedLoS: Boolean;
    FHoldDurationSec: Single;
    FReleaseDecayRatePerSec: Single;
    FRepeatCooldownSec: Single;
    FShowPreview: Boolean;
    FFocusedTargetName: String;
    FFocusedWorldPos: TVector3;
    FHoldProgress01: Single;
    FCooldownRemainingSec: Single;
    FHoldStatus: TInteractHoldStatus;
    FCompletedInteractionsCount: Integer;
    FWasHoldingPrevStep: Boolean;
    FCandidates: array of TInteractCandidateScore;
    FPreviewRoot: TCastleTransform;
    FPreviewConeScene: TCastleScene;
    procedure SetPreset(const AValue: TInteractScannerPreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TInteractScannerPreset);

    { Scan AWorldRoot for interactable transforms (matching InteractableNamePrefix
      or Tag > 0) inside MaxInteractRangeMeters & MaxGazeHalfConeDeg, rejecting
      WorldRay wall-occluded targets when RequireUnobstructedLoS = True. }
    function ScanBestInteractable(
      const AWorldRoot: TCastleAbstractRootTransform): String;

    { Advance tap or hold-to-interact state machine by ADtSec; returns True and
      populates ATriggeredTargetName on the exact completion step. }
    function StepHoldInteraction(const AWorldRoot: TCastleAbstractRootTransform;
      const AIsHoldingButton: Boolean; const ADtSec: Single;
      out ATriggeredTargetName: String): Boolean;

    function CandidateCount: Integer;
    function GetCandidate(const AIndex: Integer): TInteractCandidateScore;
    procedure RebuildPreview;
    procedure ClearPreview;
    function InteractSummaryBadge: String;

    property FocusedTargetName: String read FFocusedTargetName;
    property HoldProgress01: Single read FHoldProgress01;
    property HoldStatus: TInteractHoldStatus read FHoldStatus;
    property CompletedInteractionsCount: Integer read FCompletedInteractionsCount;
  published
    property Preset: TInteractScannerPreset
      read FPreset write SetPreset default ispFirstPersonPrecisionGaze;
    property MaxInteractRangeMeters: Single
      read FMaxInteractRangeMeters write FMaxInteractRangeMeters;
    property MaxGazeHalfConeDeg: Single
      read FMaxGazeHalfConeDeg write FMaxGazeHalfConeDeg;
    property GazeAngleWeight: Single
      read FGazeAngleWeight write FGazeAngleWeight;
    property ProximityWeight: Single
      read FProximityWeight write FProximityWeight;
    property InteractableNamePrefix: String
      read FInteractableNamePrefix write FInteractableNamePrefix;
    property RequireUnobstructedLoS: Boolean
      read FRequireUnobstructedLoS write FRequireUnobstructedLoS default True;
    property HoldDurationSec: Single
      read FHoldDurationSec write FHoldDurationSec;
    property ReleaseDecayRatePerSec: Single
      read FReleaseDecayRatePerSec write FReleaseDecayRatePerSec;
    property RepeatCooldownSec: Single
      read FRepeatCooldownSec write FRepeatCooldownSec;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function InteractPresetToString(const APreset: TInteractScannerPreset): String;
function InteractStatusToString(const AStatus: TInteractHoldStatus): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function InteractPresetToString(const APreset: TInteractScannerPreset): String;
begin
  case APreset of
    ispFirstPersonPrecisionGaze: Result := 'FirstPersonPrecisionGaze';
    ispThirdPersonActionCone:    Result := 'ThirdPersonActionCone';
    ispSurvivalTimedSabotage:    Result := 'SurvivalTimedSabotage';
  end;
end;

function InteractStatusToString(const AStatus: TInteractHoldStatus): String;
begin
  case AStatus of
    ihsIdleNoTarget:      Result := 'IdleNoTarget';
    ihsFocusedReady:      Result := 'FocusedReady';
    ihsHoldingInProgress: Result := 'HoldingInProgress';
    ihsCompletedCooldown: Result := 'CompletedCooldown';
  end;
end;

{ TCastleInteractScanner ----------------------------------------------------- }

constructor TCastleInteractScanner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInteractableNamePrefix := 'Interact_';
  FRequireUnobstructedLoS := True;
  FShowPreview := True;
  FFocusedTargetName := '';
  FFocusedWorldPos := TVector3.Zero;
  FHoldProgress01 := 0.0;
  FCooldownRemainingSec := 0.0;
  FHoldStatus := ihsIdleNoTarget;
  FCompletedInteractionsCount := 0;
  FWasHoldingPrevStep := False;
  ApplyPreset(ispFirstPersonPrecisionGaze);
end;

destructor TCastleInteractScanner.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleInteractScanner.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'MaxInteractRangeMeters', 'MaxGazeHalfConeDeg',
       'GazeAngleWeight', 'ProximityWeight', 'InteractableNamePrefix',
       'RequireUnobstructedLoS', 'HoldDurationSec',
       'ReleaseDecayRatePerSec', 'RepeatCooldownSec', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleInteractScanner.SetPreset(const AValue: TInteractScannerPreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleInteractScanner.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleInteractScanner.ApplyPreset(const APreset: TInteractScannerPreset);
begin
  FPreset := APreset;
  case APreset of
    ispFirstPersonPrecisionGaze:
      begin
        FMaxInteractRangeMeters := 3.8;
        FMaxGazeHalfConeDeg := 26.0;
        FGazeAngleWeight := 0.72;
        FProximityWeight := 0.28;
        FHoldDurationSec := 0.0;
        FReleaseDecayRatePerSec := 2.0;
        FRepeatCooldownSec := 0.35;
      end;
    ispThirdPersonActionCone:
      begin
        FMaxInteractRangeMeters := 5.5;
        FMaxGazeHalfConeDeg := 58.0;
        FGazeAngleWeight := 0.42;
        FProximityWeight := 0.58;
        FHoldDurationSec := 0.45;
        FReleaseDecayRatePerSec := 1.8;
        FRepeatCooldownSec := 0.40;
      end;
    ispSurvivalTimedSabotage:
      begin
        FMaxInteractRangeMeters := 4.2;
        FMaxGazeHalfConeDeg := 32.0;
        FGazeAngleWeight := 0.65;
        FProximityWeight := 0.35;
        FHoldDurationSec := 1.20;
        FReleaseDecayRatePerSec := 1.50;
        FRepeatCooldownSec := 0.60;
      end;
  end;
  RebuildPreview;
end;

function TCastleInteractScanner.ScanBestInteractable(
  const AWorldRoot: TCastleAbstractRootTransform): String;
var
  WT: TMatrix4;
  EyePos, GazeFwd: TVector3;
  RangeSafe, ConeDegSafe, BestScore: Single;
  PrevFocus, PrefixLower: String;
  CandCount: Integer;
  BestPos: TVector3;

  function IsBlockedByWall(const ATarget: TCastleTransform;
    const ATargetPos: TVector3; const ADist: Single): Boolean;
  var
    Dir: TVector3;
    RH: TRayCollision;
    K: Integer;
    HitT: TCastleTransform;
    D: Single;
  begin
    Result := False;
    if (AWorldRoot = nil) or (ADist < 0.08) then Exit;
    Dir := (ATargetPos - EyePos) / ADist;
    RH := AWorldRoot.WorldRay(EyePos, Dir);
    try
      if RH = nil then Exit;
      for K := 0 to RH.Count - 1 do
      begin
        HitT := RH[K].Item;
        if (HitT = nil) or (HitT = AWorldRoot) or (HitT = Self) or
           (HitT = ATarget) then
          Continue;
        if csTransient in HitT.ComponentStyle then
          Continue;
        D := PointsDistance(EyePos, RH[K].Point);
        if (D > 0.04) and (D < ADist - 0.12) then
          Exit(True);
      end;
    finally
      FreeAndNil(RH);
    end;
  end;

  procedure Traverse(const AParent: TCastleTransform);
  var
    I, Idx: Integer;
    Child: TCastleTransform;
    ItemWT: TMatrix4;
    ItemPos, ToItem: TVector3;
    Dist, CosAng, AngDeg, GazeNorm, ProxNorm, TagBonus, Score: Single;
    Blocked, IsMatch: Boolean;
  begin
    if AParent = nil then Exit;
    for I := 0 to AParent.Count - 1 do
    begin
      Child := AParent[I];
      if (Child = nil) or (Child = Self) or (not Child.Exists) then Continue;
      if csTransient in Child.ComponentStyle then Continue;

      IsMatch := (Child.Tag > 0) or
        ((PrefixLower <> '') and (Pos(PrefixLower, LowerCase(Child.Name)) = 1));

      if IsMatch then
      begin
        if Child.HasWorldTransform then
          ItemWT := Child.WorldTransform
        else
          ItemWT := Child.Transform;
        ItemPos := ItemWT.MultPoint(TVector3.Zero);
        ToItem := ItemPos - EyePos;
        Dist := ToItem.Length;
        if (Dist >= 0.01) and (Dist <= RangeSafe) then
        begin
          CosAng := Clamped(TVector3.DotProduct(ToItem / Dist, GazeFwd), -1.0, 1.0);
          AngDeg := RadToDeg(ArcCos(CosAng));
          if AngDeg <= ConeDegSafe then
          begin
            Blocked := FRequireUnobstructedLoS and IsBlockedByWall(Child, ItemPos, Dist);
            GazeNorm := 1.0 - (AngDeg / Max(1.0, ConeDegSafe));
            ProxNorm := 1.0 - (Dist / RangeSafe);
            TagBonus := Clamped(Child.Tag * 0.02, 0.0, 0.40);
            if Blocked then
              Score := -1.0
            else
              Score := FGazeAngleWeight * GazeNorm + FProximityWeight * ProxNorm + TagBonus;

            Idx := CandCount;
            Inc(CandCount);
            if Idx >= Length(FCandidates) then
              SetLength(FCandidates, Max(16, Length(FCandidates) * 2));
            FCandidates[Idx].TargetName := Child.Name;
            FCandidates[Idx].WorldPos := ItemPos;
            FCandidates[Idx].DistanceMeters := Dist;
            FCandidates[Idx].GazeAngleDeg := AngDeg;
            FCandidates[Idx].ObstructedByWall := Blocked;
            FCandidates[Idx].TotalScore := Score;

            if (not Blocked) and (Score > BestScore) then
            begin
              BestScore := Score;
              Result := Child.Name;
              BestPos := ItemPos;
            end;
          end;
        end;
      end;

      Traverse(Child);
    end;
  end;

begin
  PrevFocus := FFocusedTargetName;
  Result := '';
  BestScore := -1e9;
  BestPos := TVector3.Zero;
  CandCount := 0;
  SetLength(FCandidates, 16);

  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;
  EyePos := WT.MultPoint(TVector3.Zero);
  GazeFwd := WT.MultDirection(Vector3(0.0, 0.0, -1.0));
  if GazeFwd.LengthSqr < 1e-8 then
    GazeFwd := Vector3(0.0, 0.0, -1.0)
  else
    GazeFwd := GazeFwd.Normalize;

  RangeSafe := Max(0.25, FMaxInteractRangeMeters);
  ConeDegSafe := Clamped(FMaxGazeHalfConeDeg, 2.0, 179.0);
  PrefixLower := LowerCase(Trim(FInteractableNamePrefix));

  if AWorldRoot <> nil then
    Traverse(AWorldRoot);

  SetLength(FCandidates, CandCount);
  FFocusedTargetName := Result;
  FFocusedWorldPos := BestPos;

  { Switching focus to a different target resets any partial hold progress }
  if FFocusedTargetName <> PrevFocus then
    FHoldProgress01 := 0.0;

  if FCooldownRemainingSec > 0.001 then
    FHoldStatus := ihsCompletedCooldown
  else if FFocusedTargetName = '' then
    FHoldStatus := ihsIdleNoTarget
  else if FHoldProgress01 > 0.001 then
    FHoldStatus := ihsHoldingInProgress
  else
    FHoldStatus := ihsFocusedReady;

  if FShowPreview then
    RebuildPreview;
end;

function TCastleInteractScanner.StepHoldInteraction(
  const AWorldRoot: TCastleAbstractRootTransform;
  const AIsHoldingButton: Boolean; const ADtSec: Single;
  out ATriggeredTargetName: String): Boolean;
var
  Dt: Single;
  RisingEdge: Boolean;
begin
  Result := False;
  ATriggeredTargetName := '';
  Dt := Max(0.0, ADtSec);

  if FCooldownRemainingSec > 0.0 then
    FCooldownRemainingSec := Max(0.0, FCooldownRemainingSec - Dt);

  ScanBestInteractable(AWorldRoot);
  RisingEdge := AIsHoldingButton and (not FWasHoldingPrevStep);
  FWasHoldingPrevStep := AIsHoldingButton;

  if FCooldownRemainingSec > 0.001 then
  begin
    FHoldStatus := ihsCompletedCooldown;
    Exit(False);
  end;

  if FFocusedTargetName = '' then
  begin
    FHoldProgress01 := 0.0;
    FHoldStatus := ihsIdleNoTarget;
    Exit(False);
  end;

  if AIsHoldingButton then
  begin
    if FHoldDurationSec <= 0.001 then
    begin
      if RisingEdge or (FHoldProgress01 = 0.0) then
      begin
        FHoldProgress01 := 1.0;
        Inc(FCompletedInteractionsCount);
        ATriggeredTargetName := FFocusedTargetName;
        FCooldownRemainingSec := Max(0.05, FRepeatCooldownSec);
        FHoldProgress01 := 0.0;
        FHoldStatus := ihsCompletedCooldown;
        Exit(True);
      end;
    end else
    begin
      FHoldProgress01 := Clamped(FHoldProgress01 + (Dt / FHoldDurationSec), 0.0, 1.0);
      if FHoldProgress01 >= 0.9999 then
      begin
        Inc(FCompletedInteractionsCount);
        ATriggeredTargetName := FFocusedTargetName;
        FCooldownRemainingSec := Max(0.05, FRepeatCooldownSec);
        FHoldProgress01 := 0.0;
        FHoldStatus := ihsCompletedCooldown;
        Exit(True);
      end else
        FHoldStatus := ihsHoldingInProgress;
    end;
  end else
  begin
    FHoldProgress01 := Max(0.0, FHoldProgress01 - Max(0.1, FReleaseDecayRatePerSec) * Dt);
    if FHoldProgress01 > 0.001 then
      FHoldStatus := ihsHoldingInProgress
    else
      FHoldStatus := ihsFocusedReady;
  end;
end;

function TCastleInteractScanner.CandidateCount: Integer;
begin
  Result := Length(FCandidates);
end;

function TCastleInteractScanner.GetCandidate(
  const AIndex: Integer): TInteractCandidateScore;
begin
  if (AIndex >= 0) and (AIndex < Length(FCandidates)) then
    Result := FCandidates[AIndex]
  else
    Result := Default(TInteractCandidateScore);
end;

procedure TCastleInteractScanner.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewConeScene := nil;
  end;
end;

procedure TCastleInteractScanner.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  MatNode: TUnlitMaterialNode;
  Pts: array of TVector3;
  Counts: array of Int32;
  R, ConeRad, RingR, Ang: Single;
  I: Integer;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if not FShowPreview then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'InteractScannerPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;

  FPreviewConeScene := TCastleScene.Create(FPreviewRoot);
  FPreviewConeScene.SetTransient;
  FPreviewConeScene.Pickable := False;
  FPreviewConeScene.Collides := False;
  FPreviewRoot.Add(FPreviewConeScene);

  R := Max(0.5, FMaxInteractRangeMeters);
  ConeRad := DegToRad(Clamped(FMaxGazeHalfConeDeg, 2.0, 80.0));
  RingR := R * Sin(ConeRad);
  SetLength(Pts, 8 + 17);
  SetLength(Counts, 5);
  for I := 0 to 3 do
  begin
    Ang := I * Pi * 0.5;
    Pts[I * 2] := TVector3.Zero;
    Pts[I * 2 + 1] := Vector3(Cos(Ang) * RingR, Sin(Ang) * RingR, -R * Cos(ConeRad));
    Counts[I] := 2;
  end;
  for I := 0 to 16 do
  begin
    Ang := (2.0 * Pi * I) / 16.0;
    Pts[8 + I] := Vector3(Cos(Ang) * RingR, Sin(Ang) * RingR, -R * Cos(ConeRad));
  end;
  Counts[4] := 17;

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  if FFocusedTargetName <> '' then
    MatNode.EmissiveColor := Vector3(0.28, 0.96, 0.58)
  else
    MatNode.EmissiveColor := Vector3(0.52, 0.72, 0.95);
  ShapeNode.Material := MatNode;
  LineSet := TLineSetNode.Create;
  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewConeScene.Load(RootNode, True);

  Add(FPreviewRoot);
end;

function TCastleInteractScanner.InteractSummaryBadge: String;
var
  Tgt: String;
begin
  if FFocusedTargetName = '' then Tgt := 'None' else Tgt := FFocusedTargetName;
  Result := FormatDot('[Interact:%s Hold=%.0f%% Done=%d]', [
    Tgt, FHoldProgress01 * 100.0, FCompletedInteractionsCount]);
end;

initialization
  RegisterSerializableComponent(TCastleInteractScanner, 'Gameplay Interaction Focus Scanner');

end.
