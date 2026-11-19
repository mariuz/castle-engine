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

{ Automated tactical cover point scanner classifying waist crouch-peek barriers,
  full standing corner-lean pillars, and multi-threat flanking exposure via
  WorldRay queries (Phase 384). }
unit CastleCoverPointScanner;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Tactical posture afforded by an obstacle edge. }
  TCoverPostureKind = (
    cpkNoneExposed,
    cpkWaistCrouchOverPeek,
    cpkFullStandingCornerLean
  );

  { Tactical scanner sizing presets. }
  TCoverScannerPreset = (
    cspInfantryFirefightGrid,
    cspStealthInfiltrator,
    cspHeavyMechBarricade
  );

  { Discovered cover candidate with peek/lean affordances and multi-threat safety score. }
  TCoverNodeCandidate = record
    WorldPos: TVector3;
    WallNormal: TVector3;
    Posture: TCoverPostureKind;
    CanPeekOverTop: Boolean;
    CanLeanLeft: Boolean;
    CanLeanRight: Boolean;
    ProtectedFromThreats: Boolean;
    TacticalQualityScore01: Single;
  end;

  { Automated 3D cover-point bake and multi-threat flanking evaluator. }
  TCastleCoverPointScanner = class(TCastleTransform)
  private
    FPreset: TCoverScannerPreset;
    FScanHalfSpanMeters: Single;
    FGridStepMeters: Single;
    FAgentStandoffMeters: Single;
    FCrouchWaistHeightMeters: Single;
    FStandingEyeHeightMeters: Single;
    FCornerLeanOffsetMeters: Single;
    FCoverProbeMaxDistMeters: Single;
    FShowPreviewMarkers: Boolean;
    FCoverNodes: array of TCoverNodeCandidate;
    FWaistCoverCount: Integer;
    FFullCoverCount: Integer;
    FLastSafeNodeCount: Integer;
    FPreviewRoot: TCastleTransform;
    procedure SetPreset(const AValue: TCoverScannerPreset);
    procedure SetScanHalfSpanMeters(const AValue: Single);
    procedure SetGridStepMeters(const AValue: Single);
    procedure SetAgentStandoffMeters(const AValue: Single);
    procedure SetCrouchWaistHeightMeters(const AValue: Single);
    procedure SetStandingEyeHeightMeters(const AValue: Single);
    procedure SetCornerLeanOffsetMeters(const AValue: Single);
    procedure SetCoverProbeMaxDistMeters(const AValue: Single);
    procedure SetShowPreviewMarkers(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
    procedure RebuildPreviewMarkers;
    function RayHitsObstacleWithin(const AWorldRoot: TCastleAbstractRootTransform;
      const AOrigin, ADirUnit: TVector3; const AMaxDist: Single;
      out AHitDist: Single): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TCoverScannerPreset);
    procedure ClearCoverNodes;

    { Scan AWorldRoot on an XZ grid and classify waist vs. full standing cover points. }
    function BakeCoverNodes(const AWorldRoot: TCastleAbstractRootTransform): Integer;

    { Re-score all baked cover nodes against 1..N hostile threat positions.
      Returns count of un-flanked safe nodes and outputs highest-scoring ABestNode. }
    function EvaluateBestCoverAgainstThreats(
      const AWorldRoot: TCastleAbstractRootTransform;
      const AThreats: array of TVector3;
      out ABestNode: TCoverNodeCandidate): Integer;

    function CoverNodeCount: Integer;
    function GetCoverNode(const AIndex: Integer): TCoverNodeCandidate;
    function CoverSummaryBadge: String;

    property WaistCoverCount: Integer read FWaistCoverCount;
    property FullCoverCount: Integer read FFullCoverCount;
    property LastSafeNodeCount: Integer read FLastSafeNodeCount;
  published
    property Preset: TCoverScannerPreset read FPreset write SetPreset default cspInfantryFirefightGrid;
    property ScanHalfSpanMeters: Single read FScanHalfSpanMeters write SetScanHalfSpanMeters;
    property GridStepMeters: Single read FGridStepMeters write SetGridStepMeters;
    property AgentStandoffMeters: Single read FAgentStandoffMeters write SetAgentStandoffMeters;
    property CrouchWaistHeightMeters: Single read FCrouchWaistHeightMeters write SetCrouchWaistHeightMeters;
    property StandingEyeHeightMeters: Single read FStandingEyeHeightMeters write SetStandingEyeHeightMeters;
    property CornerLeanOffsetMeters: Single read FCornerLeanOffsetMeters write SetCornerLeanOffsetMeters;
    property CoverProbeMaxDistMeters: Single read FCoverProbeMaxDistMeters write SetCoverProbeMaxDistMeters;
    property ShowPreviewMarkers: Boolean read FShowPreviewMarkers write SetShowPreviewMarkers default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored False;
  end;

implementation

uses FpJson, JsonParser, CastleUtils;

{ TCastleCoverPointScanner --------------------------------------------------- }

constructor TCastleCoverPointScanner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FScanHalfSpanMeters := 10.0;
  FGridStepMeters := 1.5;
  FAgentStandoffMeters := 0.65;
  FCrouchWaistHeightMeters := 0.85;
  FStandingEyeHeightMeters := 1.65;
  FCornerLeanOffsetMeters := 0.85;
  FCoverProbeMaxDistMeters := 1.50;
  FShowPreviewMarkers := True;
  ApplyPreset(cspInfantryFirefightGrid);
end;

destructor TCastleCoverPointScanner.Destroy;
begin
  FreeAndNil(FPreviewRoot);
  SetLength(FCoverNodes, 0);
  inherited Destroy;
end;

function TCastleCoverPointScanner.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'ScanHalfSpanMeters', 'GridStepMeters', 'AgentStandoffMeters',
       'CrouchWaistHeightMeters', 'StandingEyeHeightMeters',
       'CornerLeanOffsetMeters', 'CoverProbeMaxDistMeters', 'ShowPreviewMarkers'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleCoverPointScanner.ApplyPreset(const APreset: TCoverScannerPreset);
begin
  FPreset := APreset;
  case APreset of
    cspInfantryFirefightGrid:
      begin
        FScanHalfSpanMeters := 10.0;
        FGridStepMeters := 1.5;
        FAgentStandoffMeters := 0.65;
        FCrouchWaistHeightMeters := 0.85;
        FStandingEyeHeightMeters := 1.65;
        FCornerLeanOffsetMeters := 0.85;
        FCoverProbeMaxDistMeters := 1.50;
      end;
    cspStealthInfiltrator:
      begin
        FScanHalfSpanMeters := 8.0;
        FGridStepMeters := 1.25;
        FAgentStandoffMeters := 0.50;
        FCrouchWaistHeightMeters := 0.70;
        FStandingEyeHeightMeters := 1.55;
        FCornerLeanOffsetMeters := 0.65;
        FCoverProbeMaxDistMeters := 1.25;
      end;
    cspHeavyMechBarricade:
      begin
        FScanHalfSpanMeters := 14.0;
        FGridStepMeters := 2.0;
        FAgentStandoffMeters := 1.10;
        FCrouchWaistHeightMeters := 1.60;
        FStandingEyeHeightMeters := 3.10;
        FCornerLeanOffsetMeters := 1.40;
        FCoverProbeMaxDistMeters := 2.20;
      end;
  end;
end;

procedure TCastleCoverPointScanner.SetPreset(const AValue: TCoverScannerPreset);
begin
  if FPreset <> AValue then
    ApplyPreset(AValue);
end;

procedure TCastleCoverPointScanner.SetScanHalfSpanMeters(const AValue: Single);
begin
  FScanHalfSpanMeters := Max(2.0, AValue);
end;

procedure TCastleCoverPointScanner.SetGridStepMeters(const AValue: Single);
begin
  FGridStepMeters := Max(0.4, AValue);
end;

procedure TCastleCoverPointScanner.SetAgentStandoffMeters(const AValue: Single);
begin
  FAgentStandoffMeters := Max(0.2, AValue);
end;

procedure TCastleCoverPointScanner.SetCrouchWaistHeightMeters(const AValue: Single);
begin
  FCrouchWaistHeightMeters := Max(0.25, AValue);
  if FStandingEyeHeightMeters < FCrouchWaistHeightMeters + 0.30 then
    FStandingEyeHeightMeters := FCrouchWaistHeightMeters + 0.30;
end;

procedure TCastleCoverPointScanner.SetStandingEyeHeightMeters(const AValue: Single);
begin
  FStandingEyeHeightMeters := Max(FCrouchWaistHeightMeters + 0.30, AValue);
end;

procedure TCastleCoverPointScanner.SetCornerLeanOffsetMeters(const AValue: Single);
begin
  FCornerLeanOffsetMeters := Max(0.2, AValue);
end;

procedure TCastleCoverPointScanner.SetCoverProbeMaxDistMeters(const AValue: Single);
begin
  FCoverProbeMaxDistMeters := Max(0.3, AValue);
end;

procedure TCastleCoverPointScanner.SetShowPreviewMarkers(const AValue: Boolean);
begin
  if FShowPreviewMarkers <> AValue then
  begin
    FShowPreviewMarkers := AValue;
    RebuildPreviewMarkers;
  end;
end;

procedure TCastleCoverPointScanner.ClearCoverNodes;
begin
  SetLength(FCoverNodes, 0);
  FWaistCoverCount := 0;
  FFullCoverCount := 0;
  FLastSafeNodeCount := 0;
  RebuildPreviewMarkers;
end;

function TCastleCoverPointScanner.RayHitsObstacleWithin(
  const AWorldRoot: TCastleAbstractRootTransform;
  const AOrigin, ADirUnit: TVector3; const AMaxDist: Single;
  out AHitDist: Single): Boolean;
var
  RayHit: TRayCollision;
  I: Integer;
  D: Single;
begin
  Result := False;
  AHitDist := AMaxDist + 1.0;
  if AWorldRoot = nil then Exit;
  RayHit := AWorldRoot.WorldRay(AOrigin, ADirUnit);
  try
    if RayHit <> nil then
      for I := 0 to RayHit.Count - 1 do
        if (RayHit[I].Item <> Self) and
           (not (csTransient in RayHit[I].Item.ComponentStyle)) then
        begin
          D := PointsDistance(AOrigin, RayHit[I].Point);
          if (D > 0.001) and (D <= AMaxDist) and ((not Result) or (D < AHitDist)) then
          begin
            AHitDist := D;
            Result := True;
          end;
        end;
  finally
    FreeAndNil(RayHit);
  end;
end;

function TCastleCoverPointScanner.BakeCoverNodes(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;
const
  Dirs: array[0..3] of TVector3 = (
    (X:  1; Y: 0; Z:  0),
    (X: -1; Y: 0; Z:  0),
    (X:  0; Y: 0; Z:  1),
    (X:  0; Y: 0; Z: -1)
  );
var
  SavedPreviewExists: Boolean;
  OriginW, ProbeDir, RightDir, StandPos, WaistOrig, EyeOrig: TVector3;
  StepsHalf, IX, IZ, DIdx, OutCount: Integer;
  WX, WZ, DownDist, GroundY, WaistDist, DummyDist: Single;
  EyeBlocked, LeftBlocked, RightBlocked: Boolean;
  Cand: TCoverNodeCandidate;
begin
  ClearCoverNodes;
  if AWorldRoot = nil then Exit(0);

  SavedPreviewExists := (FPreviewRoot <> nil) and FPreviewRoot.Exists;
  if FPreviewRoot <> nil then
    FPreviewRoot.Exists := False;
  try
    OriginW := WorldTranslation;
    StepsHalf := Max(1, Round(FScanHalfSpanMeters / FGridStepMeters));
    OutCount := 0;

    for IZ := -StepsHalf to StepsHalf do
      for IX := -StepsHalf to StepsHalf do
      begin
        WX := OriginW.X + IX * FGridStepMeters;
        WZ := OriginW.Z + IZ * FGridStepMeters;

        { 1. Find walkable floor and skip grid cells that land on top of tall obstacles }
        if not RayHitsObstacleWithin(AWorldRoot,
          Vector3(WX, OriginW.Y + 12.0, WZ), Vector3(0, -1, 0), 24.0, DownDist) then
          Continue;
        GroundY := (OriginW.Y + 12.0) - DownDist;
        if Abs(GroundY - OriginW.Y) > 0.60 then
          Continue;

        { 2. Probe 4 cardinal directions for adjacent waist or full cover walls }
        for DIdx := 0 to 3 do
        begin
          ProbeDir := Dirs[DIdx];
          WaistOrig := Vector3(WX, GroundY + FCrouchWaistHeightMeters, WZ);
          if not RayHitsObstacleWithin(AWorldRoot, WaistOrig, ProbeDir,
            FCoverProbeMaxDistMeters, WaistDist) then
            Continue;

          { Snap agent standoff flush against the cover face }
          StandPos := Vector3(WX, GroundY, WZ) +
            ProbeDir * (WaistDist - FAgentStandoffMeters);

          EyeOrig := Vector3(StandPos.X, GroundY + FStandingEyeHeightMeters, StandPos.Z);
          EyeBlocked := RayHitsObstacleWithin(AWorldRoot, EyeOrig, ProbeDir,
            FAgentStandoffMeters + 0.85, DummyDist);

          Cand := Default(TCoverNodeCandidate);
          Cand.WorldPos := StandPos;
          Cand.WallNormal := -ProbeDir;
          Cand.ProtectedFromThreats := True;

          if not EyeBlocked then
          begin
            Cand.Posture := cpkWaistCrouchOverPeek;
            Cand.CanPeekOverTop := True;
            Cand.TacticalQualityScore01 := 0.80;
            Inc(FWaistCoverCount);
          end else
          begin
            Cand.Posture := cpkFullStandingCornerLean;
            Cand.CanPeekOverTop := False;
            RightDir := TVector3.CrossProduct(ProbeDir, Vector3(0, 1, 0)).Normalize;
            LeftBlocked := RayHitsObstacleWithin(AWorldRoot,
              EyeOrig - RightDir * FCornerLeanOffsetMeters, ProbeDir,
              FAgentStandoffMeters + 0.85, DummyDist);
            RightBlocked := RayHitsObstacleWithin(AWorldRoot,
              EyeOrig + RightDir * FCornerLeanOffsetMeters, ProbeDir,
              FAgentStandoffMeters + 0.85, DummyDist);
            Cand.CanLeanLeft := not LeftBlocked;
            Cand.CanLeanRight := not RightBlocked;
            if Cand.CanLeanLeft or Cand.CanLeanRight then
              Cand.TacticalQualityScore01 := 0.92
            else
              Cand.TacticalQualityScore01 := 0.68;
            Inc(FFullCoverCount);
          end;

          SetLength(FCoverNodes, OutCount + 1);
          FCoverNodes[OutCount] := Cand;
          Inc(OutCount);
          Break;
        end;
      end;
  finally
    if FPreviewRoot <> nil then
      FPreviewRoot.Exists := SavedPreviewExists;
  end;

  FLastSafeNodeCount := Length(FCoverNodes);
  RebuildPreviewMarkers;
  Result := Length(FCoverNodes);
end;

function TCastleCoverPointScanner.EvaluateBestCoverAgainstThreats(
  const AWorldRoot: TCastleAbstractRootTransform;
  const AThreats: array of TVector3;
  out ABestNode: TCoverNodeCandidate): Integer;
var
  SavedPreviewExists, SafeFromAll: Boolean;
  I, TIdx: Integer;
  ToThreat, CrouchEyePos, ThreatAimPos: TVector3;
  ThreatDist, HitDist, DotCover, Score, BestScore: Single;
begin
  ABestNode := Default(TCoverNodeCandidate);
  Result := 0;
  BestScore := -1.0;
  if Length(FCoverNodes) = 0 then Exit;

  SavedPreviewExists := (FPreviewRoot <> nil) and FPreviewRoot.Exists;
  if FPreviewRoot <> nil then
    FPreviewRoot.Exists := False;
  try
    for I := 0 to High(FCoverNodes) do
    begin
      SafeFromAll := True;
      for TIdx := 0 to High(AThreats) do
      begin
        ToThreat := AThreats[TIdx] - FCoverNodes[I].WorldPos;
        ToThreat.Y := 0.0;
        ThreatDist := ToThreat.Length;
        if ThreatDist < 0.25 then
        begin
          SafeFromAll := False;
          Break;
        end;

        { Wall normal points from wall toward hiding agent, so ToThreat . WallNormal
          must be < -0.15 (wall sits between agent and threat, not behind agent) }
        DotCover := TVector3.DotProduct(ToThreat / ThreatDist, FCoverNodes[I].WallNormal);
        if DotCover > -0.15 then
        begin
          SafeFromAll := False;
          Break;
        end;

        { Confirm real crouch-height WorldRay line-of-sight is blocked by cover }
        if AWorldRoot <> nil then
        begin
          CrouchEyePos := FCoverNodes[I].WorldPos + Vector3(0, FCrouchWaistHeightMeters, 0);
          ThreatAimPos := Vector3(AThreats[TIdx].X, FCoverNodes[I].WorldPos.Y + FCrouchWaistHeightMeters, AThreats[TIdx].Z);
          if not RayHitsObstacleWithin(AWorldRoot, CrouchEyePos,
            (ThreatAimPos - CrouchEyePos).Normalize,
            PointsDistance(CrouchEyePos, ThreatAimPos) - 0.15, HitDist) then
          begin
            SafeFromAll := False;
            Break;
          end;
        end;
      end;

      FCoverNodes[I].ProtectedFromThreats := SafeFromAll;
      if not SafeFromAll then
        FCoverNodes[I].TacticalQualityScore01 := 0.0
      else
      begin
        Score := 0.65;
        if FCoverNodes[I].CanPeekOverTop then
          Score := Score + 0.18;
        if FCoverNodes[I].CanLeanLeft or FCoverNodes[I].CanLeanRight then
          Score := Score + 0.25;
        FCoverNodes[I].TacticalQualityScore01 := EnsureRange(Score, 0.0, 1.0);
        Inc(Result);
        if FCoverNodes[I].TacticalQualityScore01 > BestScore then
        begin
          BestScore := FCoverNodes[I].TacticalQualityScore01;
          ABestNode := FCoverNodes[I];
        end;
      end;
    end;
  finally
    if FPreviewRoot <> nil then
      FPreviewRoot.Exists := SavedPreviewExists;
  end;

  FLastSafeNodeCount := Result;
  RebuildPreviewMarkers;
end;

procedure TCastleCoverPointScanner.RebuildPreviewMarkers;
var
  InvWorld: TMatrix4;
  Marker: TCastleBox;
  I: Integer;
begin
  FreeAndNil(FPreviewRoot);
  if (not FShowPreviewMarkers) or (Length(FCoverNodes) = 0) then Exit;

  if not WorldTransform.TryInverse(InvWorld) then
    InvWorld := TMatrix4.Identity;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  FPreviewRoot.Name := 'TransientCoverMarkers';

  for I := 0 to High(FCoverNodes) do
  begin
    Marker := TCastleBox.Create(FPreviewRoot);
    Marker.SetTransient;
    Marker.Pickable := False;
    Marker.Collides := False;
    Marker.Size := Vector3(0.36, 0.36, 0.36);
    Marker.Translation := InvWorld.MultPoint(FCoverNodes[I].WorldPos + Vector3(0, 0.25, 0));
    if not FCoverNodes[I].ProtectedFromThreats then
      Marker.Color := Vector4(0.92, 0.24, 0.20, 0.85)
    else if FCoverNodes[I].Posture = cpkFullStandingCornerLean then
      Marker.Color := Vector4(0.22, 0.86, 0.94, 0.90)
    else
      Marker.Color := Vector4(0.32, 0.90, 0.42, 0.90);
    FPreviewRoot.Add(Marker);
  end;

  Add(FPreviewRoot);
end;

function TCastleCoverPointScanner.CoverNodeCount: Integer;
begin
  Result := Length(FCoverNodes);
end;

function TCastleCoverPointScanner.GetCoverNode(const AIndex: Integer): TCoverNodeCandidate;
begin
  if (AIndex >= 0) and (AIndex <= High(FCoverNodes)) then
    Result := FCoverNodes[AIndex]
  else
    Result := Default(TCoverNodeCandidate);
end;

function TCastleCoverPointScanner.CoverSummaryBadge: String;
begin
  Result := Format('[CoverAI:%d pts (%d waist / %d full)]', [
    Length(FCoverNodes), FWaistCoverCount, FFullCoverCount]);
end;

function TCastleCoverPointScanner.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('scanHalfSpanMeters', FScanHalfSpanMeters);
    Obj.Add('gridStepMeters', FGridStepMeters);
    Obj.Add('agentStandoffMeters', FAgentStandoffMeters);
    Obj.Add('crouchWaistHeightMeters', FCrouchWaistHeightMeters);
    Obj.Add('standingEyeHeightMeters', FStandingEyeHeightMeters);
    Obj.Add('cornerLeanOffsetMeters', FCornerLeanOffsetMeters);
    Obj.Add('coverProbeMaxDistMeters', FCoverProbeMaxDistMeters);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleCoverPointScanner.SetConfigJson(const AValue: String);
var
  Data: TJSONData;
  Obj: TJSONObject;
begin
  if Trim(AValue) = '' then Exit;
  Data := nil;
  try
    try
      Data := GetJSON(AValue);
    except
      Data := nil;
    end;
    if Data is TJSONObject then
    begin
      Obj := TJSONObject(Data);
      FPreset := TCoverScannerPreset(EnsureRange(Obj.Get('preset', Ord(FPreset)), 0, Ord(High(TCoverScannerPreset))));
      FScanHalfSpanMeters := Max(2.0, Obj.Get('scanHalfSpanMeters', FScanHalfSpanMeters));
      FGridStepMeters := Max(0.4, Obj.Get('gridStepMeters', FGridStepMeters));
      FAgentStandoffMeters := Max(0.2, Obj.Get('agentStandoffMeters', FAgentStandoffMeters));
      FCrouchWaistHeightMeters := Max(0.25, Obj.Get('crouchWaistHeightMeters', FCrouchWaistHeightMeters));
      FStandingEyeHeightMeters := Max(FCrouchWaistHeightMeters + 0.30,
        Obj.Get('standingEyeHeightMeters', FStandingEyeHeightMeters));
      FCornerLeanOffsetMeters := Max(0.2, Obj.Get('cornerLeanOffsetMeters', FCornerLeanOffsetMeters));
      FCoverProbeMaxDistMeters := Max(0.3, Obj.Get('coverProbeMaxDistMeters', FCoverProbeMaxDistMeters));
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleCoverPointScanner,
    ['AI & Gameplay', 'Tactical Cover Point Scanner (TCastleCoverPointScanner)']);

end.
