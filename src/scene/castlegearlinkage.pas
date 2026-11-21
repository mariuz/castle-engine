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

{ Mechanical gear train, compound shaft reduction, belt/chain pulley,
  rack-and-pinion portcullis lift, and contradictory odd-cycle loop jam
  solver (Phase 415). }
unit CastleGearLinkage;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleClassUtils,
  CastleColors, X3DNodes;

type
  { Coupling topologies between two mechanical elements. }
  TGearLinkKind = (
    glkExternalSpurMesh,
    glkUncrossedBeltPulley,
    glkCoaxialCompoundShaft,
    glkRackAndPinionLinear
  );

  { Preset mechanical machinery templates. }
  TGearLinkagePreset = (
    glpPortcullisWinchCompoundTrain,
    glpCathedralClocktowerEscapement,
    glpBeltDrivenSawmillPulley
  );

  { Rotary wheel or linear rack node in the linkage graph. }
  TGearWheelNode = record
    NodeIndex: Integer;
    Name: String;
    LocalCenter: TVector3;
    ToothCount: Integer;
    PitchRadiusMeters: Single;
    IsLinearRack: Boolean;
    SolvedRpm: Single;
    SolvedTorqueNm: Single;
    AngleRad: Single;
    LinearPositionMeters: Single;
  end;

  { Directed/undirected mechanical transmission coupling edge. }
  TGearLinkEdge = record
    FromNode: Integer;
    ToNode: Integer;
    Kind: TGearLinkKind;
  end;

  { Mechanical gear train, rack-and-pinion & jam detector component. }
  TCastleGearLinkage = class(TCastleTransform)
  private
    FPreset: TGearLinkagePreset;
    FMotorInputRpm: Single;
    FMotorInputTorqueNm: Single;
    FStageEfficiency01: Single;
    FShowPreview: Boolean;
    FNodes: array of TGearWheelNode;
    FLinks: array of TGearLinkEdge;
    FIsJammedLoop: Boolean;
    FJammedReason: String;
    FPreviewRoot: TCastleTransform;
    FPreviewGearsScene: TCastleScene;
    procedure SetPreset(const AValue: TGearLinkagePreset);
    procedure SetShowPreview(const AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    procedure ApplyPreset(const APreset: TGearLinkagePreset);
    procedure ClearMechanism;

    function AddGearWheel(const AName: String; const ALocalCenter: TVector3;
      const AToothCount: Integer; const APitchRadiusMeters: Single): Integer;
    function AddLinearRack(const AName: String;
      const ALocalCenter: TVector3): Integer;
    function AddCouplingLink(const AFromNode, AToNode: Integer;
      const AKind: TGearLinkKind): Integer;

    { Breadth-First Search kinematic & torque solver from Node 0; detects
      contradictory odd-cycle spur meshes or mismatched ratio loops. }
    function SolveGearTrainKinematics: Boolean;

    { Advance wheel angles & rack linear lift by ADtSec (frozen if jammed). }
    procedure StepClockwork(const ADtSec: Single);

    function NodeCount: Integer;
    function LinkCount: Integer;
    function GetNode(const AIndex: Integer): TGearWheelNode;

    procedure RebuildPreview;
    procedure ClearPreview;
    function GearSummaryBadge: String;

    property IsJammedLoop: Boolean read FIsJammedLoop;
    property JammedReason: String read FJammedReason;
  published
    property Preset: TGearLinkagePreset
      read FPreset write SetPreset default glpPortcullisWinchCompoundTrain;
    property MotorInputRpm: Single read FMotorInputRpm write FMotorInputRpm;
    property MotorInputTorqueNm: Single
      read FMotorInputTorqueNm write FMotorInputTorqueNm;
    property StageEfficiency01: Single
      read FStageEfficiency01 write FStageEfficiency01;
    property ShowPreview: Boolean
      read FShowPreview write SetShowPreview default True;
  end;

function GearLinkagePresetToString(const APreset: TGearLinkagePreset): String;

implementation

uses
  CastleComponentSerialize, CastleUtils;

function GearLinkagePresetToString(const APreset: TGearLinkagePreset): String;
begin
  case APreset of
    glpPortcullisWinchCompoundTrain:  Result := 'PortcullisWinchCompoundTrain';
    glpCathedralClocktowerEscapement: Result := 'CathedralClocktowerEscapement';
    glpBeltDrivenSawmillPulley:       Result := 'BeltDrivenSawmillPulley';
  end;
end;

constructor TCastleGearLinkage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShowPreview := True;
  FMotorInputRpm := 120.0;
  FMotorInputTorqueNm := 10.0;
  FStageEfficiency01 := 0.95;
  ApplyPreset(glpPortcullisWinchCompoundTrain);
end;

destructor TCastleGearLinkage.Destroy;
begin
  ClearMechanism;
  inherited Destroy;
end;

function TCastleGearLinkage.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'MotorInputRpm', 'MotorInputTorqueNm',
       'StageEfficiency01', 'ShowPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleGearLinkage.SetPreset(const AValue: TGearLinkagePreset);
begin
  if FPreset = AValue then Exit;
  ApplyPreset(AValue);
end;

procedure TCastleGearLinkage.SetShowPreview(const AValue: Boolean);
begin
  if FShowPreview = AValue then Exit;
  FShowPreview := AValue;
  if FShowPreview then
    RebuildPreview
  else
    ClearPreview;
end;

procedure TCastleGearLinkage.ClearMechanism;
begin
  SetLength(FNodes, 0);
  SetLength(FLinks, 0);
  FIsJammedLoop := False;
  FJammedReason := '';
  ClearPreview;
end;

function TCastleGearLinkage.AddGearWheel(const AName: String;
  const ALocalCenter: TVector3; const AToothCount: Integer;
  const APitchRadiusMeters: Single): Integer;
var
  N: Integer;
begin
  N := Length(FNodes);
  SetLength(FNodes, N + 1);
  FNodes[N] := Default(TGearWheelNode);
  FNodes[N].NodeIndex := N;
  FNodes[N].Name := AName;
  FNodes[N].LocalCenter := ALocalCenter;
  FNodes[N].ToothCount := Max(4, AToothCount);
  FNodes[N].PitchRadiusMeters := Max(0.05, APitchRadiusMeters);
  FNodes[N].IsLinearRack := False;
  Result := N;
end;

function TCastleGearLinkage.AddLinearRack(const AName: String;
  const ALocalCenter: TVector3): Integer;
var
  N: Integer;
begin
  N := Length(FNodes);
  SetLength(FNodes, N + 1);
  FNodes[N] := Default(TGearWheelNode);
  FNodes[N].NodeIndex := N;
  FNodes[N].Name := AName;
  FNodes[N].LocalCenter := ALocalCenter;
  FNodes[N].ToothCount := 1;
  FNodes[N].PitchRadiusMeters := 1.0;
  FNodes[N].IsLinearRack := True;
  Result := N;
end;

function TCastleGearLinkage.AddCouplingLink(const AFromNode, AToNode: Integer;
  const AKind: TGearLinkKind): Integer;
var
  M: Integer;
begin
  M := Length(FLinks);
  SetLength(FLinks, M + 1);
  FLinks[M].FromNode := AFromNode;
  FLinks[M].ToNode := AToNode;
  FLinks[M].Kind := AKind;
  Result := M;
end;

procedure TCastleGearLinkage.ApplyPreset(const APreset: TGearLinkagePreset);
begin
  FPreset := APreset;
  ClearMechanism;
  case APreset of
    glpPortcullisWinchCompoundTrain:
      begin
        { 12T Hand-Crank (120 RPM) -> 36T Spur (-40 RPM) -> Coaxial 12T Pinion
          -> 48T Output Drum (+10 RPM, 12x Torque) -> Iron Portcullis Rack! }
        FMotorInputRpm := 120.0;
        FMotorInputTorqueNm := 10.0;
        FStageEfficiency01 := 0.95;
        AddGearWheel('MotorPinion_12T', Vector3(-1.8, 1.5, 0.0), 12, 0.25);
        AddGearWheel('ReductionGear_36T', Vector3(-0.8, 1.5, 0.0), 36, 0.75);
        AddGearWheel('CompoundPinion_12T', Vector3(-0.8, 1.5, 0.2), 12, 0.25);
        AddGearWheel('WinchDrum_48T', Vector3(0.45, 1.5, 0.2), 48, 1.00);
        AddLinearRack('IronPortcullisGateRack', Vector3(1.55, 1.5, 0.2));
        AddCouplingLink(0, 1, glkExternalSpurMesh);
        AddCouplingLink(1, 2, glkCoaxialCompoundShaft);
        AddCouplingLink(2, 3, glkExternalSpurMesh);
        AddCouplingLink(3, 4, glkRackAndPinionLinear);
      end;

    glpCathedralClocktowerEscapement:
      begin
        FMotorInputRpm := 60.0;
        FMotorInputTorqueNm := 4.0;
        FStageEfficiency01 := 0.98;
        AddGearWheel('EscapePinion_10T', Vector3(-1.2, 2.0, 0.0), 10, 0.20);
        AddGearWheel('MinuteWheel_60T', Vector3(0.0, 2.0, 0.0), 60, 1.20);
        AddCouplingLink(0, 1, glkExternalSpurMesh);
      end;

    glpBeltDrivenSawmillPulley:
      begin
        FMotorInputRpm := 180.0;
        FMotorInputTorqueNm := 25.0;
        FStageEfficiency01 := 0.92;
        AddGearWheel('WaterwheelSheave_40T', Vector3(-2.0, 1.5, 0.0), 40, 0.90);
        AddGearWheel('SawArborSheave_20T', Vector3(1.6, 1.5, 0.0), 20, 0.45);
        AddCouplingLink(0, 1, glkUncrossedBeltPulley);
      end;
  end;
  SolveGearTrainKinematics;
end;

function TCastleGearLinkage.SolveGearTrainKinematics: Boolean;
var
  N, Head, Tail, Cur, E, Other, ZCur, ZOther: Integer;
  Visited: array of Boolean;
  Queue: array of Integer;
  Eta, Ratio, ImpliedRpm, ImpliedTorque: Single;
  Kind: TGearLinkKind;
begin
  FIsJammedLoop := False;
  FJammedReason := '';
  N := Length(FNodes);
  if N = 0 then Exit(True);

  Eta := Clamped(FStageEfficiency01, 0.10, 1.00);
  SetLength(Visited, N);
  SetLength(Queue, N);
  for Cur := 0 to N - 1 do
  begin
    Visited[Cur] := False;
    FNodes[Cur].SolvedRpm := 0.0;
    FNodes[Cur].SolvedTorqueNm := 0.0;
  end;

  Visited[0] := True;
  FNodes[0].SolvedRpm := FMotorInputRpm;
  FNodes[0].SolvedTorqueNm := FMotorInputTorqueNm;
  Head := 0;
  Tail := 1;
  Queue[0] := 0;

  while Head < Tail do
  begin
    Cur := Queue[Head];
    Inc(Head);

    for E := 0 to High(FLinks) do
    begin
      if FLinks[E].FromNode = Cur then
        Other := FLinks[E].ToNode
      else if FLinks[E].ToNode = Cur then
        Other := FLinks[E].FromNode
      else
        Continue;

      if (Other < 0) or (Other >= N) then Continue;
      Kind := FLinks[E].Kind;
      ZCur := Max(1, FNodes[Cur].ToothCount);
      ZOther := Max(1, FNodes[Other].ToothCount);

      case Kind of
        glkExternalSpurMesh:
          begin
            Ratio := ZCur / ZOther;
            ImpliedRpm := -FNodes[Cur].SolvedRpm * Ratio;
            ImpliedTorque := FNodes[Cur].SolvedTorqueNm * (ZOther / ZCur) * Eta;
          end;
        glkUncrossedBeltPulley:
          begin
            Ratio := ZCur / ZOther;
            ImpliedRpm := FNodes[Cur].SolvedRpm * Ratio;
            ImpliedTorque := FNodes[Cur].SolvedTorqueNm * (ZOther / ZCur) * Eta;
          end;
        glkCoaxialCompoundShaft:
          begin
            ImpliedRpm := FNodes[Cur].SolvedRpm;
            ImpliedTorque := FNodes[Cur].SolvedTorqueNm;
          end;
        glkRackAndPinionLinear:
          if FNodes[Cur].IsLinearRack then
          begin
            { Linear rack [m/s] -> driving pinion [RPM] }
            ImpliedRpm := (FNodes[Cur].SolvedRpm /
              Max(0.05, FNodes[Other].PitchRadiusMeters)) * (60.0 / (2.0 * Pi));
            ImpliedTorque := FNodes[Cur].SolvedTorqueNm *
              FNodes[Other].PitchRadiusMeters * Eta;
          end else
          begin
            { Driving pinion [RPM] -> linear rack translational speed [m/s] }
            ImpliedRpm := (FNodes[Cur].SolvedRpm * 2.0 * Pi / 60.0) *
                          FNodes[Cur].PitchRadiusMeters;
            ImpliedTorque := (FNodes[Cur].SolvedTorqueNm /
                              Max(0.05, FNodes[Cur].PitchRadiusMeters)) * Eta;
          end;
      end;

      if not Visited[Other] then
      begin
        Visited[Other] := True;
        FNodes[Other].SolvedRpm := ImpliedRpm;
        FNodes[Other].SolvedTorqueNm := ImpliedTorque;
        Queue[Tail] := Other;
        Inc(Tail);
      end else
      begin
        if Abs(FNodes[Other].SolvedRpm - ImpliedRpm) > 0.02 then
        begin
          FIsJammedLoop := True;
          FJammedReason := Format(
            'Kinematic jam on %s: %.2f RPM vs %.2f RPM',
            [FNodes[Other].Name, FNodes[Other].SolvedRpm, ImpliedRpm]);
          Break;
        end;
      end;
    end;
    if FIsJammedLoop then Break;
  end;

  if FIsJammedLoop then
    for Cur := 0 to N - 1 do
    begin
      FNodes[Cur].SolvedRpm := 0.0;
      FNodes[Cur].SolvedTorqueNm := 0.0;
    end;

  if FShowPreview then
    RebuildPreview;
  Result := not FIsJammedLoop;
end;

procedure TCastleGearLinkage.StepClockwork(const ADtSec: Single);
var
  I: Integer;
  OmegaRadSec: Single;
begin
  if (ADtSec <= 0.0) or FIsJammedLoop then Exit;
  for I := 0 to High(FNodes) do
    if FNodes[I].IsLinearRack then
      FNodes[I].LinearPositionMeters :=
        FNodes[I].LinearPositionMeters + FNodes[I].SolvedRpm * ADtSec
    else
    begin
      OmegaRadSec := FNodes[I].SolvedRpm * 2.0 * Pi / 60.0;
      FNodes[I].AngleRad := FNodes[I].AngleRad + OmegaRadSec * ADtSec;
    end;
  if FShowPreview then
    RebuildPreview;
end;

function TCastleGearLinkage.NodeCount: Integer;
begin
  Result := Length(FNodes);
end;

function TCastleGearLinkage.LinkCount: Integer;
begin
  Result := Length(FLinks);
end;

function TCastleGearLinkage.GetNode(const AIndex: Integer): TGearWheelNode;
begin
  if (AIndex >= 0) and (AIndex < Length(FNodes)) then
    Result := FNodes[AIndex]
  else
    Result := Default(TGearWheelNode);
end;

procedure TCastleGearLinkage.ClearPreview;
begin
  if FPreviewRoot <> nil then
  begin
    Remove(FPreviewRoot);
    FreeAndNil(FPreviewRoot);
    FPreviewGearsScene := nil;
  end;
end;

procedure TCastleGearLinkage.RebuildPreview;
var
  RootNode: TX3DRootNode;
  ShapeNode: TShapeNode;
  App: TAppearanceNode;
  MatNode: TUnlitMaterialNode;
  LineSet: TLineSetNode;
  CoordNode: TCoordinateNode;
  Pts: array of TVector3;
  Counts: array of Int32;
  I, Seg, WheelCount, WIdx: Integer;
  R, Ang: Single;
  C: TVector3;
begin
  if csDestroying in ComponentState then Exit;
  ClearPreview;
  if (not FShowPreview) or (Length(FNodes) = 0) then Exit;

  WheelCount := 0;
  for I := 0 to High(FNodes) do
    if not FNodes[I].IsLinearRack then
      Inc(WheelCount);
  if WheelCount = 0 then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Name := 'GearLinkagePreviewRoot';
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  Add(FPreviewRoot);

  FPreviewGearsScene := TCastleScene.Create(FPreviewRoot);
  FPreviewGearsScene.SetTransient;
  FPreviewGearsScene.Name := 'GearLinkagePreviewWheels';
  FPreviewGearsScene.Pickable := False;
  FPreviewGearsScene.Collides := False;
  FPreviewRoot.Add(FPreviewGearsScene);

  RootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;
  App := TAppearanceNode.Create;
  MatNode := TUnlitMaterialNode.Create;
  if FIsJammedLoop then
    MatNode.EmissiveColor := Vector3(1.0, 0.25, 0.22)
  else
    MatNode.EmissiveColor := Vector3(0.95, 0.78, 0.35);
  App.Material := MatNode;
  ShapeNode.Appearance := App;

  SetLength(Pts, WheelCount * 17);
  SetLength(Counts, WheelCount);
  WIdx := 0;
  for I := 0 to High(FNodes) do
    if not FNodes[I].IsLinearRack then
    begin
      C := FNodes[I].LocalCenter;
      R := FNodes[I].PitchRadiusMeters;
      for Seg := 0 to 16 do
      begin
        Ang := FNodes[I].AngleRad + 2.0 * Pi * Seg / 16.0;
        Pts[WIdx * 17 + Seg] := C + Vector3(Cos(Ang) * R, Sin(Ang) * R, 0.0);
      end;
      Counts[WIdx] := 17;
      Inc(WIdx);
    end;

  CoordNode := TCoordinateNode.Create;
  CoordNode.SetPoint(Pts);
  LineSet := TLineSetNode.Create;
  LineSet.Coord := CoordNode;
  LineSet.SetVertexCount(Counts);
  ShapeNode.Geometry := LineSet;
  RootNode.AddChildren(ShapeNode);
  FPreviewGearsScene.Load(RootNode, True);
end;

function TCastleGearLinkage.GearSummaryBadge: String;
begin
  if FIsJammedLoop then
    Result := Format('[Gears:JAMMED %d nodes]', [Length(FNodes)])
  else
    Result := FormatDot('[Gears:%d nodes In=%.0fRPM]', [
      Length(FNodes), FMotorInputRpm]);
end;

initialization
  RegisterSerializableComponent(TCastleGearLinkage, 'Mechanical Gear & Rack Train');

end.
