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

{ Tactical squad & crowd formation controller solving 1..64 unit Cavalry V-Wedge,
  Hoplite Phalanx Grid, Outward-Facing VIP Shield-Circle, and Double Column
  slots with downward WorldRay terrain projection and lateral boulder/pillar
  split-around avoidance (Phase 405). }
unit CastleCrowdFormation;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Tactical squad geometry topologies. }
  TSquadFormationShape = (
    sfsCavalryVWedge,
    sfsHoplitesPhalanxGrid,
    sfsVipOutwardShieldCircle,
    sfsTacticalDoubleColumn
  );

  { Computed world-space slot for one squad member. }
  TSquadFormationSlot = record
    UnitIndex: Integer;
    IdealLocalOffset: TVector3;
    WorldPosition: TVector3;
    WorldForward: TVector3;
    GroundSnapped: Boolean;
    ObstacleDeflected: Boolean;
  end;

  { Tactical squad & crowd formation component. }
  TCastleCrowdFormation = class(TCastleTransform)
  private
    FFormationShape: TSquadFormationShape;
    FUnitCount: Integer;
    FSlotSpacingMeters: Single;
    FPhalanxColumns: Integer;
    FMaxStepHeightMeters: Single;
    FShowPreview: Boolean;
    FSlots: array of TSquadFormationSlot;
    FObstacleAvoidedSlotCount: Integer;
    FGroundSnappedSlotCount: Integer;
    FPreviewRoot: TCastleTransform;
    FPreviewMarkersScene: TCastleScene;
    procedure SetFormationShape(const AValue: TSquadFormationShape);
    procedure SetUnitCount(const AValue: Integer);
    procedure SetPhalanxColumns(const AValue: Integer);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Compute ideal tactical slots, project onto walkable terrain via downward
      WorldRay, and split laterally around tall boulders/pillars. }
    function SolveFormationSlots(
      const AWorldRoot: TCastleAbstractRootTransform): Integer;

    function SlotCount: Integer;
    function GetSlot(const AIndex: Integer): TSquadFormationSlot;

    procedure RebuildPreview;
    procedure ClearPreview;
    function FormationSummaryBadge: String;

    property ObstacleAvoidedSlotCount: Integer read FObstacleAvoidedSlotCount;
    property GroundSnappedSlotCount: Integer read FGroundSnappedSlotCount;
  published
    property FormationShape: TSquadFormationShape
      read FFormationShape write SetFormationShape default sfsCavalryVWedge;
    property UnitCount: Integer
      read FUnitCount write SetUnitCount default 12;
    property SlotSpacingMeters: Single
      read FSlotSpacingMeters write FSlotSpacingMeters;
    property PhalanxColumns: Integer
      read FPhalanxColumns write SetPhalanxColumns default 4;
    property MaxStepHeightMeters: Single
      read FMaxStepHeightMeters write FMaxStepHeightMeters;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function SquadFormationShapeToString(const AShape: TSquadFormationShape): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function SquadFormationShapeToString(const AShape: TSquadFormationShape): String;
begin
  case AShape of
    sfsCavalryVWedge:          Result := 'CavalryVWedge';
    sfsHoplitesPhalanxGrid:    Result := 'HoplitesPhalanxGrid';
    sfsVipOutwardShieldCircle: Result := 'VipOutwardShieldCircle';
    sfsTacticalDoubleColumn:   Result := 'TacticalDoubleColumn';
  end;
end;

constructor TCastleCrowdFormation.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFormationShape := sfsCavalryVWedge;
  FUnitCount := 12;
  FSlotSpacingMeters := 1.80;
  FPhalanxColumns := 4;
  FMaxStepHeightMeters := 1.25;
  FShowPreview := True;
  SolveFormationSlots(nil);
end;

destructor TCastleCrowdFormation.Destroy;
begin
  ClearPreview;
  inherited Destroy;
end;

function TCastleCrowdFormation.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'FormationShape', 'UnitCount', 'SlotSpacingMeters',
       'PhalanxColumns', 'MaxStepHeightMeters', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleCrowdFormation.SetFormationShape(const AValue: TSquadFormationShape);
begin
  if FFormationShape = AValue then Exit;
  FFormationShape := AValue;
  SolveFormationSlots(World);
end;

procedure TCastleCrowdFormation.SetUnitCount(const AValue: Integer);
begin
  FUnitCount := Clamped(AValue, 1, 64);
end;

procedure TCastleCrowdFormation.SetPhalanxColumns(const AValue: Integer);
begin
  FPhalanxColumns := Clamped(AValue, 2, 16);
end;

procedure TCastleCrowdFormation.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

function TCastleCrowdFormation.SlotCount: Integer;
begin
  Result := Length(FSlots);
end;

function TCastleCrowdFormation.GetSlot(const AIndex: Integer): TSquadFormationSlot;
begin
  if (AIndex >= 0) and (AIndex < Length(FSlots)) then
    Result := FSlots[AIndex]
  else
    Result := Default(TSquadFormationSlot);
end;

function TCastleCrowdFormation.SolveFormationSlots(
  const AWorldRoot: TCastleAbstractRootTransform): Integer;
var
  ActiveRoot: TCastleAbstractRootTransform;

  { Cast a downward ray from (AX, ABaseY + 14.0, AZ) and return the highest
    non-transient hit Y in [ABaseY - 12.0 .. ABaseY + 13.5]. }
  function ProbeHighestSurfaceY(const AX, ABaseY, AZ: Single;
    out ATopY: Single): Boolean;
  var
    Orig: TVector3;
    RH: TRayCollision;
    K: Integer;
    Item: TCastleTransform;
    PY: Single;
  begin
    Result := False;
    ATopY := ABaseY;
    if ActiveRoot = nil then Exit;
    Orig := Vector3(AX, ABaseY + 14.0, AZ);
    RH := ActiveRoot.WorldRay(Orig, Vector3(0.0, -1.0, 0.0));
    try
      if RH = nil then Exit;
      ATopY := -1e9;
      for K := 0 to RH.Count - 1 do
      begin
        Item := RH[K].Item;
        if (Item = nil) or (Item = ActiveRoot) or (Item = Self) then Continue;
        if csTransient in Item.ComponentStyle then Continue;
        PY := RH[K].Point.Y;
        if (PY >= ABaseY - 12.0) and (PY <= ABaseY + 13.5) and (PY > ATopY) then
        begin
          ATopY := PY;
          Result := True;
        end;
      end;
      if not Result then
        ATopY := ABaseY;
    finally
      FreeAndNil(RH);
    end;
  end;

var
  WT: TMatrix4;
  RightWorld, BasePos, CandidatePos, LocalFwd, WorldFwd: TVector3;
  N, I, Cols, Row, Col, Rank, RingCount, StepK, SidePref, SignTry, Pass: Integer;
  S, LX, LZ, Ang, RingRad, HitY, MaxClimb, ShiftDist: Single;
  FoundBypass: Boolean;
begin
  if AWorldRoot <> nil then
    ActiveRoot := AWorldRoot
  else
    ActiveRoot := World;

  N := Clamped(FUnitCount, 1, 64);
  S := Max(0.45, FSlotSpacingMeters);
  Cols := Clamped(FPhalanxColumns, 2, 16);
  MaxClimb := Max(0.20, FMaxStepHeightMeters);

  if HasWorldTransform then WT := WorldTransform else WT := Transform;
  RightWorld := WT.MultDirection(Vector3(1.0, 0.0, 0.0));
  if RightWorld.LengthSqr > 1e-6 then
    RightWorld := RightWorld.Normalize
  else
    RightWorld := Vector3(1.0, 0.0, 0.0);

  SetLength(FSlots, N);
  FObstacleAvoidedSlotCount := 0;
  FGroundSnappedSlotCount := 0;

  for I := 0 to N - 1 do
  begin
    LX := 0.0;
    LZ := 0.0;
    LocalFwd := Vector3(0.0, 0.0, -1.0);

    case FFormationShape of
      sfsCavalryVWedge:
        if I > 0 then
        begin
          Rank := (I + 1) div 2;
          if Odd(I) then
            LX := Rank * S * 0.85
          else
            LX := -Rank * S * 0.85;
          LZ := Rank * S * 0.90;
        end;

      sfsHoplitesPhalanxGrid:
        begin
          Row := I div Cols;
          Col := I mod Cols;
          LX := (Col - (Cols - 1) * 0.5) * S;
          LZ := Row * S * 0.95;
        end;

      sfsVipOutwardShieldCircle:
        if I > 0 then
        begin
          RingCount := Max(1, N - 1);
          Ang := 2.0 * Pi * (I - 1) / RingCount;
          RingRad := Max(S, (RingCount * S) / (2.0 * Pi));
          LX := Sin(Ang) * RingRad;
          LZ := -Cos(Ang) * RingRad;
          LocalFwd := Vector3(Sin(Ang), 0.0, -Cos(Ang));
        end;

      sfsTacticalDoubleColumn:
        begin
          Row := I div 2;
          if Odd(I) then LX := 0.5 * S else LX := -0.5 * S;
          LZ := Row * S;
        end;
    end;

    WorldFwd := WT.MultDirection(LocalFwd);
    if WorldFwd.LengthSqr > 1e-6 then
      WorldFwd := WorldFwd.Normalize
    else
      WorldFwd := Vector3(0.0, 0.0, -1.0);

    BasePos := WT.MultPoint(Vector3(LX, 0.0, LZ));
    FSlots[I].UnitIndex := I;
    FSlots[I].IdealLocalOffset := Vector3(LX, 0.0, LZ);
    FSlots[I].WorldPosition := BasePos;
    FSlots[I].WorldForward := WorldFwd;
    FSlots[I].GroundSnapped := False;
    FSlots[I].ObstacleDeflected := False;

    if ActiveRoot <> nil then
    begin
      if ProbeHighestSurfaceY(BasePos.X, BasePos.Y, BasePos.Z, HitY) then
      begin
        if HitY > BasePos.Y + MaxClimb then
        begin
          { Tall boulder / pillar blocks this slot! Split laterally around it. }
          FSlots[I].ObstacleDeflected := True;
          Inc(FObstacleAvoidedSlotCount);
          if LX >= 0.0 then SidePref := 1 else SidePref := -1;
          FoundBypass := False;

          for StepK := 1 to 12 do
          begin
            ShiftDist := StepK * 0.65 * S;
            for Pass := 0 to 1 do
            begin
              if Pass = 0 then SignTry := SidePref else SignTry := -SidePref;
              CandidatePos := BasePos + RightWorld * (SignTry * ShiftDist);
              if ProbeHighestSurfaceY(CandidatePos.X, BasePos.Y, CandidatePos.Z, HitY) then
              begin
                if HitY <= BasePos.Y + MaxClimb then
                begin
                  CandidatePos.Y := HitY;
                  FSlots[I].WorldPosition := CandidatePos;
                  FSlots[I].GroundSnapped := True;
                  Inc(FGroundSnappedSlotCount);
                  FoundBypass := True;
                  Break;
                end;
              end else
              begin
                FSlots[I].WorldPosition := CandidatePos;
                FoundBypass := True;
                Break;
              end;
            end;
            if FoundBypass then Break;
          end;
        end else
        begin
          FSlots[I].WorldPosition.Y := HitY;
          FSlots[I].GroundSnapped := True;
          Inc(FGroundSnappedSlotCount);
        end;
      end;
    end;
  end;

  if FShowPreview then
    RebuildPreview;
  Result := N;
end;

procedure TCastleCrowdFormation.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewMarkersScene := nil;
  end;
end;

procedure TCastleCrowdFormation.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  InvWT, WT: TMatrix4;
  Pts: array of TVector3;
  Counts: array of Int32;
  I, N: Integer;
  LocalP, LocalDir: TVector3;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  N := Length(FSlots);
  if (not FShowPreview) or (N = 0) then Exit;

  if HasWorldTransform then
    InvWT := WorldInverseTransform
  else
  begin
    WT := Transform;
    if not WT.TryInverse(InvWT) then InvWT := TMatrix4.Identity;
  end;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'CrowdFormationPreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewMarkersScene := TCastleScene.Create(FPreviewRoot);
  FPreviewMarkersScene.SetTransient;
  FPreviewMarkersScene.Name := 'CrowdFormationPreviewSlots';
  FPreviewMarkersScene.Pickable := False;
  FPreviewMarkersScene.Collides := False;
  FPreviewRoot.Add(FPreviewMarkersScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  MatNode.EmissiveColor := Vector3(0.32, 0.88, 0.65);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  SetLength(Pts, N * 2);
  SetLength(Counts, N);
  for I := 0 to N - 1 do
  begin
    LocalP := InvWT.MultPoint(FSlots[I].WorldPosition) + Vector3(0.0, 0.15, 0.0);
    LocalDir := InvWT.MultDirection(FSlots[I].WorldForward);
    Pts[I * 2] := LocalP;
    Pts[I * 2 + 1] := LocalP + LocalDir * 0.65;
    Counts[I] := 2;
  end;

  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewMarkersScene.Load(RootNode, True);
end;

function TCastleCrowdFormation.FormationSummaryBadge: String;
begin
  Result := Format('[Squad:%s %d units Split=%d]', [
    SquadFormationShapeToString(FFormationShape),
    Length(FSlots),
    FObstacleAvoidedSlotCount]);
end;

initialization
  RegisterSerializableComponent(TCastleCrowdFormation, 'Crowd Squad Formation');

end.
