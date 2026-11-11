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

{ 3D Catmull-Rom / Cardinal spline path (@link(TCastleSplinePath)) with
  arc-length parameterization, banked @code(RollDeg) & @code(WidthScale) knots,
  transient PBR road/river ribbon & cable tube extrusion, terrain projection,
  and @link(TCastleSplineFollowerBehavior) motion along splines
  (Phase 297 — UE 6.0 USplineComponent & Landscape Splines Parity). }
unit CastleSplinePath;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

const
  { Tag assigned to child instances spawned along a spline by
    @code(TSplineStudioHelper.PopulateInstancesAlongSpline) so re-populating
    cleanly replaces generated instances while preserving hand-authored children. }
  SplineGeneratedInstanceTag = 7797;

type
  { Procedural transient 3D geometry extruded along @link(TCastleSplinePath). }
  TSplineMeshMode = (
    smNone,
    smRoadRibbon,
    smRiverRibbon,
    smCableTube
  );

  { Built-in 1-click spline presets. }
  TSplinePreset = (
    spCustom,
    spWindingRoad,
    spMeanderingRiver,
    spHangingCable,
    spClosedRaceTrack
  );

  { Playback wrap mode for @link(TCastleSplineFollowerBehavior). }
  TSplineFollowLoopMode = (
    sflmOnce,
    sflmLoop,
    sflmPingPong
  );

  { Single 3D knot on a @link(TCastleSplinePath) in local spline coordinates. }
  TSplineControlPoint = record
    Position: TVector3;
    RollDeg: Single;
    WidthScale: Single;
  end;
  TSplineControlPointArray = array of TSplineControlPoint;

  { Evaluated 3D frame and scalar attributes at a point along a spline. }
  TSplineSample = record
    Position: TVector3;
    Tangent: TVector3;
    Up: TVector3;
    Right: TVector3;
    RollDeg: Single;
    Width: Single;
    Distance: Single;
    NormalizedT: Single;
  end;
  TSplineSampleArray = array of TSplineSample;

  { 3D Catmull-Rom / Cardinal spline component with arc-length LUT and
    non-destructive @code(csTransient) ribbon/tube mesh generation. }
  TCastleSplinePath = class(TCastleTransform)
  strict private
    FPreset: TSplinePreset;
    FMeshMode: TSplineMeshMode;
    FClosedLoop: Boolean;
    FTension: Single;
    FRibbonWidth: Single;
    FTubeSides: Integer;
    FSubdivisionsPerSegment: Integer;
    FRibbonOffsetY: Single;
    FShowSplineInViewport: Boolean;
    FRibbonColor: TCastleColor;
    FRibbonColorPersistent: TCastleColorPersistent;

    FPoints: TSplineControlPointArray;
    FLutSamples: TSplineSampleArray;
    FLutDirty: Boolean;
    FTotalLength: Single;
    FGeneratedTriangleCount: Integer;

    FRenderScene: TCastleScene;
    FRootNode: TX3DRootNode;
    FAppearanceNode: TAppearanceNode;
    FMaterialNode: TPhysicalMaterialNode;
    FTriSetNode: TTriangleSetNode;
    FCoordNode: TCoordinateNode;
    FNormalNode: TNormalNode;
    FColorNode: TColorRGBANode;
    FVertexBuffer: TVector3List;
    FNormalBuffer: TVector3List;
    FColorBuffer: TVector4List;

    procedure SetPreset(const Value: TSplinePreset);
    procedure SetMeshMode(const Value: TSplineMeshMode);
    procedure SetClosedLoop(const Value: Boolean);
    procedure SetTension(const Value: Single);
    procedure SetRibbonWidth(const Value: Single);
    procedure SetTubeSides(const Value: Integer);
    procedure SetSubdivisionsPerSegment(const Value: Integer);
    procedure SetRibbonOffsetY(const Value: Single);
    procedure SetRibbonColor(const Value: TCastleColor);
    function GetRibbonColorForPersistent: TCastleColor;
    procedure SetRibbonColorForPersistent(const AValue: TCastleColor);
    function GetControlPointsJson: String;
    procedure SetControlPointsJson(const Value: String);

    function TensionStored: Boolean;
    function RibbonWidthStored: Boolean;
    function RibbonOffsetYStored: Boolean;
    function ControlPointsJsonStored: Boolean;

    function SegmentCount: Integer;
    function WrapOrClampPointIndex(const AIndex: Integer): Integer;
    procedure MarkSplineDirty;
    procedure EnsureArcLengthLut;
    procedure EnsureRenderScene;
    procedure SyncMaterialProperties;
  protected
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;

    { Apply one of the built-in spline presets (@code(spWindingRoad),
      @code(spMeanderingRiver), @code(spHangingCable), @code(spClosedRaceTrack)). }
    procedure ApplyPreset(const APreset: TSplinePreset);

    function ControlPointCount: Integer;
    function GetControlPoint(const AIndex: Integer): TSplineControlPoint;
    procedure SetControlPoint(const AIndex: Integer; const APoint: TSplineControlPoint);
    function AddControlPoint(const APosition: TVector3;
      const ARollDeg: Single = 0.0; const AWidthScale: Single = 1.0): Integer;
    procedure InsertControlPoint(const AIndex: Integer; const APosition: TVector3;
      const ARollDeg: Single = 0.0; const AWidthScale: Single = 1.0);
    procedure DeleteControlPoint(const AIndex: Integer);
    procedure ClearControlPoints;

    { Total arc length of the spline in local coordinates. }
    function TotalLength: Single;

    { Number of triangles currently built in the transient ribbon/tube mesh. }
    property GeneratedTriangleCount: Integer read FGeneratedTriangleCount;

    { Evaluate local spline frame at normalized parameter @code(AT) in [0..1]. }
    function EvaluateLocalAtNormalizedT(const AT: Single): TSplineSample;

    { Evaluate local spline frame at uniform arc-length distance @code(ADistance)
      in [0 .. @link(TotalLength)]. }
    function EvaluateLocalAtDistance(const ADistance: Single): TSplineSample;

    { Evaluate world-space spline frame at arc-length distance @code(ADistance). }
    function EvaluateWorldAtDistance(const ADistance: Single): TSplineSample;

    { Raycast downward through @code(World) from @code(+AVerticalRaySpan) above
      each control point (ignoring @code(Self) and its children) to snap knots
      onto underlying terrain or floor meshes. Returns number of snapped knots. }
    function ProjectControlPointsToWorld(const AVerticalRaySpan: Single = 50.0;
      const AGroundOffsetY: Single = 0.05): Integer;

    { Rebuild the @code(csTransient) ribbon/tube X3D geometry. }
    procedure RebuildTransientMesh;

    { Compact badge displayed in the Castle Editor Hierarchy tree. }
    function SplineSummaryBadge: String;

    property RibbonColor: TCastleColor read FRibbonColor write SetRibbonColor;
  published
    property Preset: TSplinePreset read FPreset write SetPreset default spCustom;
    property MeshMode: TSplineMeshMode read FMeshMode write SetMeshMode default smRoadRibbon;
    property ClosedLoop: Boolean read FClosedLoop write SetClosedLoop default false;
    property Tension: Single read FTension write SetTension stored TensionStored;
    property RibbonWidth: Single read FRibbonWidth write SetRibbonWidth stored RibbonWidthStored;
    property TubeSides: Integer read FTubeSides write SetTubeSides default 8;
    property SubdivisionsPerSegment: Integer
      read FSubdivisionsPerSegment write SetSubdivisionsPerSegment default 12;
    property RibbonOffsetY: Single
      read FRibbonOffsetY write SetRibbonOffsetY stored RibbonOffsetYStored;
    property ShowSplineInViewport: Boolean
      read FShowSplineInViewport write FShowSplineInViewport default true;
    property RibbonColorPersistent: TCastleColorPersistent read FRibbonColorPersistent;
    property ControlPointsJson: String
      read GetControlPointsJson write SetControlPointsJson stored ControlPointsJsonStored;
  end;

  { Behavior that moves and banks its parent @link(TCastleTransform) smoothly
    along a named @link(TCastleSplinePath) at uniform arc-length speed. }
  TCastleSplineFollowerBehavior = class(TCastleBehavior)
  strict private
    FSplineName: String;
    FSpeedMetersPerSec: Single;
    FCurrentDistance: Single;
    FLoopMode: TSplineFollowLoopMode;
    FAlignToTangent: Boolean;
    FVerticalOffset: Single;
    FPlaying: Boolean;
    FPingPongDirection: Integer;
    function SpeedStored: Boolean;
    function CurrentDistanceStored: Boolean;
    function VerticalOffsetStored: Boolean;
    function ResolveSpline(const ARoot: TComponent): TCastleSplinePath;
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    { Advance follower by @code(ASecondsPassed) (may be 0 to snap immediately to
      @link(CurrentDistance)) and apply position + banked orientation to @code(Parent). }
    function StepFollow(const ASecondsPassed: Single;
      const ARoot: TComponent = nil): Boolean;

    function FollowerSummaryBadge: String;
  published
    property SplineName: String read FSplineName write FSplineName;
    property SpeedMetersPerSec: Single
      read FSpeedMetersPerSec write FSpeedMetersPerSec stored SpeedStored;
    property CurrentDistance: Single
      read FCurrentDistance write FCurrentDistance stored CurrentDistanceStored;
    property LoopMode: TSplineFollowLoopMode
      read FLoopMode write FLoopMode default sflmLoop;
    property AlignToTangent: Boolean
      read FAlignToTangent write FAlignToTangent default true;
    property VerticalOffset: Single
      read FVerticalOffset write FVerticalOffset stored VerticalOffsetStored;
    property Playing: Boolean read FPlaying write FPlaying default true;
  end;

function SplineMeshModeToString(const AMode: TSplineMeshMode): String;
function SplinePresetToString(const APreset: TSplinePreset): String;

implementation

uses
  Math, fpjson, jsonparser,
  CastleComponentSerialize, CastleRenderOptions, CastleApplicationProperties;

const
  DefaultTension = 0.5;
  DefaultRibbonWidth = 3.0;
  DefaultRibbonOffsetY = 0.02;
  DefaultFollowerSpeed = 4.0;

function SplineMeshModeToString(const AMode: TSplineMeshMode): String;
begin
  case AMode of
    smNone:        Result := 'None';
    smRoadRibbon:  Result := 'Road';
    smRiverRibbon: Result := 'River';
    smCableTube:   Result := 'Cable';
  end;
end;

function SplinePresetToString(const APreset: TSplinePreset): String;
begin
  case APreset of
    spCustom:          Result := 'Custom';
    spWindingRoad:     Result := 'Winding Road';
    spMeanderingRiver: Result := 'Meandering River';
    spHangingCable:    Result := 'Hanging Cable';
    spClosedRaceTrack: Result := 'Closed Race Track';
  end;
end;

function MakeSplineKnot(const APos: TVector3;
  const ARollDeg: Single = 0.0; const AWidthScale: Single = 1.0): TSplineControlPoint;
begin
  Result.Position := APos;
  Result.RollDeg := ARollDeg;
  Result.WidthScale := Max(0.05, AWidthScale);
end;

{ TCastleSplinePath ---------------------------------------------------------- }

constructor TCastleSplinePath.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := spCustom;
  FMeshMode := smRoadRibbon;
  FClosedLoop := false;
  FTension := DefaultTension;
  FRibbonWidth := DefaultRibbonWidth;
  FTubeSides := 8;
  FSubdivisionsPerSegment := 12;
  FRibbonOffsetY := DefaultRibbonOffsetY;
  FShowSplineInViewport := true;
  FRibbonColor := Vector4(0.24, 0.25, 0.28, 1.0);
  FLutDirty := true;
  FTotalLength := 0.0;
  FGeneratedTriangleCount := 0;

  FVertexBuffer := TVector3List.Create;
  FNormalBuffer := TVector3List.Create;
  FColorBuffer := TVector4List.Create;

  FRibbonColorPersistent := TCastleColorPersistent.Create(nil);
  FRibbonColorPersistent.SetSubComponent(true);
  FRibbonColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetRibbonColorForPersistent;
  FRibbonColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetRibbonColorForPersistent;
  FRibbonColorPersistent.InternalDefaultValue := FRibbonColor;

  { Default 4-knot gentle S-road }
  SetLength(FPoints, 4);
  FPoints[0] := MakeSplineKnot(Vector3(0.0, 0.0, 0.0), 0.0, 1.0);
  FPoints[1] := MakeSplineKnot(Vector3(6.0, 0.0, -8.0), 0.0, 1.0);
  FPoints[2] := MakeSplineKnot(Vector3(-4.0, 0.0, -18.0), 0.0, 1.0);
  FPoints[3] := MakeSplineKnot(Vector3(2.0, 0.0, -28.0), 0.0, 1.0);
  RebuildTransientMesh;
end;

destructor TCastleSplinePath.Destroy;
begin
  if FRenderScene <> nil then
  begin
    Remove(FRenderScene);
    FreeAndNil(FRenderScene);
  end;
  FreeAndNil(FVertexBuffer);
  FreeAndNil(FNormalBuffer);
  FreeAndNil(FColorBuffer);
  FreeAndNil(FRibbonColorPersistent);
  inherited Destroy;
end;

function TCastleSplinePath.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'MeshMode', 'ClosedLoop', 'Tension', 'RibbonWidth',
       'TubeSides', 'SubdivisionsPerSegment', 'RibbonOffsetY',
       'ShowSplineInViewport', 'RibbonColorPersistent', 'ControlPointsJson'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleSplinePath.LocalBoundingBox: TBox3D;
var
  I: Integer;
  HalfW: Single;
  MinP, MaxP, P: TVector3;
begin
  Result := inherited LocalBoundingBox;
  if Length(FPoints) > 0 then
  begin
    HalfW := Max(0.35, FRibbonWidth * 0.5);
    MinP := FPoints[0].Position - Vector3(HalfW, HalfW, HalfW);
    MaxP := FPoints[0].Position + Vector3(HalfW, HalfW, HalfW);
    for I := 1 to High(FPoints) do
    begin
      P := FPoints[I].Position;
      MinP.X := Min(MinP.X, P.X - HalfW);
      MinP.Y := Min(MinP.Y, P.Y - HalfW);
      MinP.Z := Min(MinP.Z, P.Z - HalfW);
      MaxP.X := Max(MaxP.X, P.X + HalfW);
      MaxP.Y := Max(MaxP.Y, P.Y + HalfW);
      MaxP.Z := Max(MaxP.Z, P.Z + HalfW);
    end;
    Result.Include(Box3D(MinP, MaxP));
  end else
  if CastleDesignMode then
    Result.Include(Box3D(Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5)));
end;

procedure TCastleSplinePath.Loaded;
begin
  inherited Loaded;
  MarkSplineDirty;
  RebuildTransientMesh;
end;

function TCastleSplinePath.TensionStored: Boolean;
begin
  Result := not SameValue(FTension, DefaultTension, 0.0001);
end;

function TCastleSplinePath.RibbonWidthStored: Boolean;
begin
  Result := not SameValue(FRibbonWidth, DefaultRibbonWidth, 0.0001);
end;

function TCastleSplinePath.RibbonOffsetYStored: Boolean;
begin
  Result := not SameValue(FRibbonOffsetY, DefaultRibbonOffsetY, 0.0001);
end;

function TCastleSplinePath.ControlPointsJsonStored: Boolean;
begin
  Result := true;
end;

procedure TCastleSplinePath.SetPreset(const Value: TSplinePreset);
begin
  if FPreset = Value then
    Exit;
  if Value = spCustom then
    FPreset := spCustom
  else
    ApplyPreset(Value);
end;

procedure TCastleSplinePath.ApplyPreset(const APreset: TSplinePreset);
begin
  FPreset := APreset;
  case APreset of
    spWindingRoad:
      begin
        FMeshMode := smRoadRibbon;
        FClosedLoop := false;
        FTension := 0.5;
        FRibbonWidth := 4.0;
        FRibbonOffsetY := 0.03;
        FRibbonColor := Vector4(0.24, 0.25, 0.28, 1.0);
        SetLength(FPoints, 5);
        FPoints[0] := MakeSplineKnot(Vector3(0.0, 0.0, 0.0), 0.0, 1.0);
        FPoints[1] := MakeSplineKnot(Vector3(8.0, 0.5, -10.0), 6.0, 1.0);
        FPoints[2] := MakeSplineKnot(Vector3(-6.0, 1.2, -22.0), -8.0, 1.1);
        FPoints[3] := MakeSplineKnot(Vector3(7.0, 0.4, -34.0), 5.0, 1.0);
        FPoints[4] := MakeSplineKnot(Vector3(0.0, 0.0, -46.0), 0.0, 1.0);
      end;

    spMeanderingRiver:
      begin
        FMeshMode := smRiverRibbon;
        FClosedLoop := false;
        FTension := 0.5;
        FRibbonWidth := 5.5;
        FRibbonOffsetY := 0.04;
        FRibbonColor := Vector4(0.14, 0.52, 0.78, 0.78);
        SetLength(FPoints, 5);
        FPoints[0] := MakeSplineKnot(Vector3(-12.0, 0.0, 12.0), 0.0, 0.8);
        FPoints[1] := MakeSplineKnot(Vector3(-3.0, 0.0, 4.0), 0.0, 1.0);
        FPoints[2] := MakeSplineKnot(Vector3(6.0, 0.0, -3.0), 0.0, 1.35);
        FPoints[3] := MakeSplineKnot(Vector3(-2.0, 0.0, -14.0), 0.0, 1.15);
        FPoints[4] := MakeSplineKnot(Vector3(10.0, 0.0, -24.0), 0.0, 1.5);
      end;

    spHangingCable:
      begin
        FMeshMode := smCableTube;
        FClosedLoop := false;
        FTension := 0.5;
        FRibbonWidth := 0.24;
        FTubeSides := 8;
        FRibbonOffsetY := 0.0;
        FRibbonColor := Vector4(0.72, 0.44, 0.20, 1.0);
        SetLength(FPoints, 5);
        FPoints[0] := MakeSplineKnot(Vector3(-10.0, 6.0, 0.0), 0.0, 1.0);
        FPoints[1] := MakeSplineKnot(Vector3(-5.0, 3.6, 0.0), 0.0, 1.0);
        FPoints[2] := MakeSplineKnot(Vector3(0.0, 2.7, 0.0), 0.0, 1.0);
        FPoints[3] := MakeSplineKnot(Vector3(5.0, 3.6, 0.0), 0.0, 1.0);
        FPoints[4] := MakeSplineKnot(Vector3(10.0, 6.0, 0.0), 0.0, 1.0);
      end;

    spClosedRaceTrack:
      begin
        FMeshMode := smRoadRibbon;
        FClosedLoop := true;
        FTension := 0.5;
        FRibbonWidth := 5.0;
        FRibbonOffsetY := 0.03;
        FRibbonColor := Vector4(0.20, 0.21, 0.24, 1.0);
        SetLength(FPoints, 6);
        FPoints[0] := MakeSplineKnot(Vector3(18.0, 0.0, 0.0), 12.0, 1.0);
        FPoints[1] := MakeSplineKnot(Vector3(10.0, 1.5, -16.0), 15.0, 1.1);
        FPoints[2] := MakeSplineKnot(Vector3(-10.0, 1.5, -16.0), 15.0, 1.1);
        FPoints[3] := MakeSplineKnot(Vector3(-18.0, 0.0, 0.0), 12.0, 1.0);
        FPoints[4] := MakeSplineKnot(Vector3(-10.0, 0.0, 16.0), 8.0, 1.0);
        FPoints[5] := MakeSplineKnot(Vector3(10.0, 0.0, 16.0), 8.0, 1.0);
      end;
  else
    ;
  end;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.SetMeshMode(const Value: TSplineMeshMode);
begin
  if FMeshMode = Value then
    Exit;
  FMeshMode := Value;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.SetClosedLoop(const Value: Boolean);
begin
  if FClosedLoop = Value then
    Exit;
  FClosedLoop := Value;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.SetTension(const Value: Single);
var
  ClampedV: Single;
begin
  ClampedV := Clamped(Value, 0.0, 1.0);
  if SameValue(FTension, ClampedV, 0.0001) then
    Exit;
  FTension := ClampedV;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.SetRibbonWidth(const Value: Single);
var
  ClampedV: Single;
begin
  ClampedV := Max(0.02, Value);
  if SameValue(FRibbonWidth, ClampedV, 0.0001) then
    Exit;
  FRibbonWidth := ClampedV;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.SetTubeSides(const Value: Integer);
var
  ClampedV: Integer;
begin
  ClampedV := Clamped(Value, 3, 24);
  if FTubeSides = ClampedV then
    Exit;
  FTubeSides := ClampedV;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.SetSubdivisionsPerSegment(const Value: Integer);
var
  ClampedV: Integer;
begin
  ClampedV := Clamped(Value, 2, 64);
  if FSubdivisionsPerSegment = ClampedV then
    Exit;
  FSubdivisionsPerSegment := ClampedV;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.SetRibbonOffsetY(const Value: Single);
begin
  if SameValue(FRibbonOffsetY, Value, 0.0001) then
    Exit;
  FRibbonOffsetY := Value;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.SetRibbonColor(const Value: TCastleColor);
begin
  FRibbonColor := Value;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

function TCastleSplinePath.GetRibbonColorForPersistent: TCastleColor;
begin
  Result := FRibbonColor;
end;

procedure TCastleSplinePath.SetRibbonColorForPersistent(const AValue: TCastleColor);
begin
  SetRibbonColor(AValue);
end;

function TCastleSplinePath.GetControlPointsJson: String;
var
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
begin
  Arr := TJSONArray.Create;
  try
    for I := 0 to High(FPoints) do
    begin
      Obj := TJSONObject.Create;
      Obj.Add('x', Double(FPoints[I].Position.X));
      Obj.Add('y', Double(FPoints[I].Position.Y));
      Obj.Add('z', Double(FPoints[I].Position.Z));
      if not SameValue(FPoints[I].RollDeg, 0.0, 0.001) then
        Obj.Add('roll', Double(FPoints[I].RollDeg));
      if not SameValue(FPoints[I].WidthScale, 1.0, 0.001) then
        Obj.Add('widthScale', Double(FPoints[I].WidthScale));
      Arr.Add(Obj);
    end;
    Result := Arr.AsJSON;
  finally
    FreeAndNil(Arr);
  end;
end;

procedure TCastleSplinePath.SetControlPointsJson(const Value: String);
var
  Parsed: TJSONData;
  Arr: TJSONArray;
  Obj: TJSONObject;
  I: Integer;
  Pt: TSplineControlPoint;
begin
  if Trim(Value) = '' then
  begin
    SetLength(FPoints, 0);
    MarkSplineDirty;
    if not (csLoading in ComponentState) then
      RebuildTransientMesh;
    Exit;
  end;

  Parsed := nil;
  try
    try
      Parsed := GetJSON(Value);
    except
      Exit;
    end;
    if not (Parsed is TJSONArray) then
      Exit;
    Arr := TJSONArray(Parsed);
    SetLength(FPoints, 0);
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONObject then
      begin
        Obj := TJSONObject(Arr.Items[I]);
        Pt.Position := Vector3(
          Obj.Get('x', 0.0),
          Obj.Get('y', 0.0),
          Obj.Get('z', 0.0));
        Pt.RollDeg := Obj.Get('roll', 0.0);
        Pt.WidthScale := Max(0.05, Obj.Get('widthScale', 1.0));
        SetLength(FPoints, Length(FPoints) + 1);
        FPoints[High(FPoints)] := Pt;
      end;
  finally
    FreeAndNil(Parsed);
  end;

  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

function TCastleSplinePath.ControlPointCount: Integer;
begin
  Result := Length(FPoints);
end;

function TCastleSplinePath.GetControlPoint(const AIndex: Integer): TSplineControlPoint;
begin
  if (AIndex >= 0) and (AIndex < Length(FPoints)) then
    Result := FPoints[AIndex]
  else
    Result := MakeSplineKnot(TVector3.Zero, 0.0, 1.0);
end;

procedure TCastleSplinePath.SetControlPoint(const AIndex: Integer;
  const APoint: TSplineControlPoint);
begin
  if (AIndex < 0) or (AIndex >= Length(FPoints)) then
    Exit;
  FPoints[AIndex] := APoint;
  FPoints[AIndex].WidthScale := Max(0.05, FPoints[AIndex].WidthScale);
  FPreset := spCustom;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

function TCastleSplinePath.AddControlPoint(const APosition: TVector3;
  const ARollDeg: Single; const AWidthScale: Single): Integer;
begin
  Result := Length(FPoints);
  SetLength(FPoints, Result + 1);
  FPoints[Result] := MakeSplineKnot(APosition, ARollDeg, AWidthScale);
  FPreset := spCustom;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.InsertControlPoint(const AIndex: Integer;
  const APosition: TVector3; const ARollDeg: Single; const AWidthScale: Single);
var
  Idx, I: Integer;
begin
  Idx := Clamped(AIndex, 0, Length(FPoints));
  SetLength(FPoints, Length(FPoints) + 1);
  for I := High(FPoints) downto Idx + 1 do
    FPoints[I] := FPoints[I - 1];
  FPoints[Idx] := MakeSplineKnot(APosition, ARollDeg, AWidthScale);
  FPreset := spCustom;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.DeleteControlPoint(const AIndex: Integer);
var
  I: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FPoints)) then
    Exit;
  for I := AIndex to High(FPoints) - 1 do
    FPoints[I] := FPoints[I + 1];
  SetLength(FPoints, Length(FPoints) - 1);
  FPreset := spCustom;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

procedure TCastleSplinePath.ClearControlPoints;
begin
  SetLength(FPoints, 0);
  FPreset := spCustom;
  MarkSplineDirty;
  if not (csLoading in ComponentState) then
    RebuildTransientMesh;
end;

function TCastleSplinePath.SegmentCount: Integer;
begin
  if Length(FPoints) < 2 then
    Result := 0
  else
  if FClosedLoop then
    Result := Length(FPoints)
  else
    Result := Length(FPoints) - 1;
end;

function TCastleSplinePath.WrapOrClampPointIndex(const AIndex: Integer): Integer;
var
  N: Integer;
begin
  N := Length(FPoints);
  if N <= 0 then
    Exit(0);
  if FClosedLoop then
  begin
    Result := AIndex mod N;
    if Result < 0 then
      Result := Result + N;
  end else
    Result := Clamped(AIndex, 0, N - 1);
end;

procedure TCastleSplinePath.MarkSplineDirty;
begin
  FLutDirty := true;
end;

function TCastleSplinePath.EvaluateLocalAtNormalizedT(const AT: Single): TSplineSample;
var
  Segs, SegIdx: Integer;
  ClampedT, Scaled, U, U2, U3, S, H00, H10, H01, H11: Single;
  DH00, DH10, DH01, DH11, RollRad: Single;
  K0, K1, K2, K3: TSplineControlPoint;
  M1, M2, RawTan, RefUp, BaseRight, BaseUp: TVector3;
begin
  Result := Default(TSplineSample);
  Result.Up := Vector3(0.0, 1.0, 0.0);
  Result.Tangent := Vector3(0.0, 0.0, -1.0);
  Result.Right := Vector3(1.0, 0.0, 0.0);
  Result.Width := FRibbonWidth;

  if Length(FPoints) = 0 then
    Exit;
  if Length(FPoints) = 1 then
  begin
    Result.Position := FPoints[0].Position;
    Result.RollDeg := FPoints[0].RollDeg;
    Result.Width := FRibbonWidth * FPoints[0].WidthScale;
    Exit;
  end;

  Segs := SegmentCount;
  if FClosedLoop then
  begin
    ClampedT := Frac(AT);
    if ClampedT < 0.0 then
      ClampedT := ClampedT + 1.0;
    if (AT >= 1.0) and SameValue(ClampedT, 0.0, 0.000001) then
      ClampedT := 1.0;
  end else
    ClampedT := Clamped(AT, 0.0, 1.0);

  Scaled := ClampedT * Segs;
  SegIdx := Floor(Scaled);
  if SegIdx >= Segs then
  begin
    SegIdx := Segs - 1;
    U := 1.0;
  end else
    U := Scaled - SegIdx;

  K1 := FPoints[WrapOrClampPointIndex(SegIdx)];
  K2 := FPoints[WrapOrClampPointIndex(SegIdx + 1)];
  if FClosedLoop then
  begin
    K0 := FPoints[WrapOrClampPointIndex(SegIdx - 1)];
    K3 := FPoints[WrapOrClampPointIndex(SegIdx + 2)];
  end else
  begin
    { Phantom reflected endpoints on open splines preserve straight end tangents }
    if SegIdx = 0 then
      K0 := MakeSplineKnot(K1.Position * 2.0 - K2.Position, K1.RollDeg, K1.WidthScale)
    else
      K0 := FPoints[SegIdx - 1];
    if SegIdx + 2 >= Length(FPoints) then
      K3 := MakeSplineKnot(K2.Position * 2.0 - K1.Position, K2.RollDeg, K2.WidthScale)
    else
      K3 := FPoints[SegIdx + 2];
  end;

  { Cardinal / Catmull-Rom tangents (FTension = 0.5 -> standard Catmull-Rom) }
  S := FTension;
  M1 := (K2.Position - K0.Position) * S;
  M2 := (K3.Position - K1.Position) * S;

  U2 := U * U;
  U3 := U2 * U;
  H00 :=  2.0 * U3 - 3.0 * U2 + 1.0;
  H10 :=        U3 - 2.0 * U2 + U;
  H01 := -2.0 * U3 + 3.0 * U2;
  H11 :=        U3 -       U2;

  Result.Position :=
    (K1.Position * H00) +
    (M1          * H10) +
    (K2.Position * H01) +
    (M2          * H11);

  { Analytical cubic Hermite derivative wrt U }
  DH00 :=  6.0 * U2 - 6.0 * U;
  DH10 :=  3.0 * U2 - 4.0 * U + 1.0;
  DH01 := -6.0 * U2 + 6.0 * U;
  DH11 :=  3.0 * U2 - 2.0 * U;

  RawTan :=
    (K1.Position * DH00) +
    (M1          * DH10) +
    (K2.Position * DH01) +
    (M2          * DH11);
  if RawTan.LengthSqr < 1e-8 then
    RawTan := K2.Position - K1.Position;
  if RawTan.LengthSqr < 1e-8 then
    RawTan := Vector3(0.0, 0.0, -1.0);
  Result.Tangent := RawTan.Normalize;

  RefUp := Vector3(0.0, 1.0, 0.0);
  if Abs(TVector3.DotProduct(Result.Tangent, RefUp)) > 0.995 then
    RefUp := Vector3(0.0, 0.0, 1.0);
  BaseRight := TVector3.CrossProduct(Result.Tangent, RefUp).Normalize;
  BaseUp := TVector3.CrossProduct(BaseRight, Result.Tangent).Normalize;

  { Smooth Hermite interpolation for RollDeg and WidthScale }
  Result.RollDeg := Lerp(SmoothStep(0.0, 1.0, U), K1.RollDeg, K2.RollDeg);
  Result.Width := FRibbonWidth * Max(0.05,
    Lerp(SmoothStep(0.0, 1.0, U), K1.WidthScale, K2.WidthScale));
  Result.NormalizedT := ClampedT;

  if not SameValue(Result.RollDeg, 0.0, 0.001) then
  begin
    RollRad := DegToRad(Result.RollDeg);
    Result.Right := RotatePointAroundAxisRad(RollRad, BaseRight, Result.Tangent).Normalize;
    Result.Up := RotatePointAroundAxisRad(RollRad, BaseUp, Result.Tangent).Normalize;
  end else
  begin
    Result.Right := BaseRight;
    Result.Up := BaseUp;
  end;
end;

procedure TCastleSplinePath.EnsureArcLengthLut;
var
  Segs, TotalSteps, I: Integer;
  T: Single;
  AccumDist: Single;
begin
  if not FLutDirty then
    Exit;
  FLutDirty := false;
  FTotalLength := 0.0;

  Segs := SegmentCount;
  if Segs <= 0 then
  begin
    SetLength(FLutSamples, 0);
    Exit;
  end;

  TotalSteps := Max(2, Segs * FSubdivisionsPerSegment);
  SetLength(FLutSamples, TotalSteps + 1);
  AccumDist := 0.0;
  for I := 0 to TotalSteps do
  begin
    T := I / TotalSteps;
    FLutSamples[I] := EvaluateLocalAtNormalizedT(T);
    if I > 0 then
      AccumDist := AccumDist +
        PointsDistance(FLutSamples[I - 1].Position, FLutSamples[I].Position);
    FLutSamples[I].Distance := AccumDist;
  end;
  FTotalLength := AccumDist;
end;

function TCastleSplinePath.TotalLength: Single;
begin
  EnsureArcLengthLut;
  Result := FTotalLength;
end;

function TCastleSplinePath.EvaluateLocalAtDistance(const ADistance: Single): TSplineSample;
var
  TargetD, SegLen, Alpha, InterpT: Single;
  Lo, Hi, Mid: Integer;
begin
  EnsureArcLengthLut;
  if Length(FLutSamples) = 0 then
  begin
    Result := EvaluateLocalAtNormalizedT(0.0);
    Exit;
  end;
  if FTotalLength <= 1e-6 then
  begin
    Result := FLutSamples[0];
    Exit;
  end;

  if FClosedLoop then
  begin
    TargetD := Frac(ADistance / FTotalLength) * FTotalLength;
    if TargetD < 0.0 then
      TargetD := TargetD + FTotalLength;
    if (ADistance >= FTotalLength) and SameValue(TargetD, 0.0, 0.0001) then
      TargetD := FTotalLength;
  end else
    TargetD := Clamped(ADistance, 0.0, FTotalLength);

  Lo := 0;
  Hi := High(FLutSamples);
  while Hi - Lo > 1 do
  begin
    Mid := (Lo + Hi) div 2;
    if FLutSamples[Mid].Distance <= TargetD then
      Lo := Mid
    else
      Hi := Mid;
  end;

  SegLen := FLutSamples[Hi].Distance - FLutSamples[Lo].Distance;
  if SegLen > 1e-6 then
    Alpha := Clamped((TargetD - FLutSamples[Lo].Distance) / SegLen, 0.0, 1.0)
  else
    Alpha := 0.0;

  InterpT := Lerp(Alpha, FLutSamples[Lo].NormalizedT, FLutSamples[Hi].NormalizedT);
  Result := EvaluateLocalAtNormalizedT(InterpT);
  Result.Distance := TargetD;
end;

function TCastleSplinePath.EvaluateWorldAtDistance(const ADistance: Single): TSplineSample;
begin
  Result := EvaluateLocalAtDistance(ADistance);
  if HasWorldTransform then
  begin
    Result.Position := LocalToWorld(Result.Position);
    Result.Tangent := LocalToWorldDirection(Result.Tangent).Normalize;
    Result.Up := LocalToWorldDirection(Result.Up).Normalize;
    Result.Right := LocalToWorldDirection(Result.Right).Normalize;
  end;
end;

function TCastleSplinePath.ProjectControlPointsToWorld(
  const AVerticalRaySpan: Single; const AGroundOffsetY: Single): Integer;
var
  SavedPickable: Boolean;
  I: Integer;
  WorldKnot, RayOrigin, HitWorld: TVector3;
  RayHit: TRayCollision;
  Span: Single;
begin
  Result := 0;
  if (World = nil) or (Length(FPoints) = 0) then
    Exit;

  Span := Max(1.0, AVerticalRaySpan);
  SavedPickable := Pickable;
  Pickable := false;
  try
    for I := 0 to High(FPoints) do
    begin
      if HasWorldTransform then
        WorldKnot := LocalToWorld(FPoints[I].Position)
      else
        WorldKnot := FPoints[I].Position;
      RayOrigin := WorldKnot + Vector3(0.0, Span, 0.0);
      RayHit := World.WorldRay(RayOrigin, Vector3(0.0, -1.0, 0.0));
      if RayHit <> nil then
      try
        if RayHit.Transform <> nil then
        begin
          HitWorld := RayOrigin + Vector3(0.0, -RayHit.Distance + AGroundOffsetY, 0.0);
          if HasWorldTransform then
            FPoints[I].Position := WorldToLocal(HitWorld)
          else
            FPoints[I].Position := HitWorld;
          Inc(Result);
        end;
      finally
        FreeAndNil(RayHit);
      end;
    end;
  finally
    Pickable := SavedPickable;
  end;

  if Result > 0 then
  begin
    MarkSplineDirty;
    RebuildTransientMesh;
  end;
end;

procedure TCastleSplinePath.EnsureRenderScene;
var
  ShapeNode: TShapeNode;
begin
  if FRenderScene <> nil then
    Exit;

  FRenderScene := TCastleScene.Create(nil);
  FRenderScene.SetTransient;
  FRenderScene.Pickable := false;
  FRenderScene.Collides := false;

  FRootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;

  FAppearanceNode := TAppearanceNode.Create;
  FMaterialNode := TPhysicalMaterialNode.Create;
  FAppearanceNode.Material := FMaterialNode;
  ShapeNode.Appearance := FAppearanceNode;

  FTriSetNode := TTriangleSetNode.Create;
  FTriSetNode.Solid := false;

  FCoordNode := TCoordinateNode.Create;
  FTriSetNode.Coord := FCoordNode;

  FNormalNode := TNormalNode.Create;
  FTriSetNode.Normal := FNormalNode;

  FColorNode := TColorRGBANode.Create;
  FTriSetNode.Color := FColorNode;

  ShapeNode.Geometry := FTriSetNode;
  FRootNode.AddChildren(ShapeNode);

  SyncMaterialProperties;
  FRenderScene.Load(FRootNode, true);
  Add(FRenderScene);
end;

procedure TCastleSplinePath.SyncMaterialProperties;
begin
  if (FMaterialNode = nil) or (FAppearanceNode = nil) then
    Exit;
  FMaterialNode.BaseColor := Vector3(1.0, 1.0, 1.0);
  case FMeshMode of
    smRoadRibbon:
      begin
        FMaterialNode.Roughness := 0.85;
        FMaterialNode.Metallic := 0.04;
        FMaterialNode.Transparency := Clamped(1.0 - FRibbonColor.W, 0.0, 1.0);
        if FRibbonColor.W < 0.99 then
          FAppearanceNode.AlphaMode := amBlend
        else
          FAppearanceNode.AlphaMode := amOpaque;
      end;
    smRiverRibbon:
      begin
        FMaterialNode.Roughness := 0.14;
        FMaterialNode.Metallic := 0.08;
        FMaterialNode.Transparency := Clamped(1.0 - FRibbonColor.W, 0.0, 1.0);
        FAppearanceNode.AlphaMode := amBlend;
      end;
    smCableTube:
      begin
        FMaterialNode.Roughness := 0.36;
        FMaterialNode.Metallic := 0.65;
        FMaterialNode.Transparency := 0.0;
        FAppearanceNode.AlphaMode := amOpaque;
      end;
  else
    ;
  end;
end;

procedure TCastleSplinePath.RebuildTransientMesh;
var
  I, J, Sides, BaseV: Integer;
  S0, S1: TSplineSample;
  Off0, Off1, L0, R0, L1, R1: TVector3;
  Ang0, Ang1, Rad0, Rad1: Single;
  N0A, N0B, N1A, N1B, P0A, P0B, P1A, P1B: TVector3;
  EdgeCol, CenterCol: TCastleColor;

  procedure EmitTri(const A, B, C, NA, NB, NC: TVector3;
    const CA, CB, CC: TCastleColor);
  begin
    FVertexBuffer.L[BaseV + 0] := A;
    FVertexBuffer.L[BaseV + 1] := B;
    FVertexBuffer.L[BaseV + 2] := C;
    FNormalBuffer.L[BaseV + 0] := NA;
    FNormalBuffer.L[BaseV + 1] := NB;
    FNormalBuffer.L[BaseV + 2] := NC;
    FColorBuffer.L[BaseV + 0] := CA;
    FColorBuffer.L[BaseV + 1] := CB;
    FColorBuffer.L[BaseV + 2] := CC;
    Inc(BaseV, 3);
  end;

begin
  EnsureArcLengthLut;
  FGeneratedTriangleCount := 0;

  if (FMeshMode = smNone) or (Length(FLutSamples) < 2) then
  begin
    if FCoordNode <> nil then
    begin
      FVertexBuffer.Count := 0;
      FNormalBuffer.Count := 0;
      FColorBuffer.Count := 0;
      FCoordNode.SetPoint(FVertexBuffer);
      FNormalNode.SetVector(FNormalBuffer);
      FColorNode.SetColor(FColorBuffer);
    end;
    Exit;
  end;

  EnsureRenderScene;
  SyncMaterialProperties;

  BaseV := 0;
  if FMeshMode in [smRoadRibbon, smRiverRibbon] then
  begin
    { 2 triangles (6 vertices) per LUT span, with subtle shoulder/bank shading }
    FGeneratedTriangleCount := (Length(FLutSamples) - 1) * 2;
    FVertexBuffer.Count := FGeneratedTriangleCount * 3;
    FNormalBuffer.Count := FGeneratedTriangleCount * 3;
    FColorBuffer.Count := FGeneratedTriangleCount * 3;

    CenterCol := FRibbonColor;
    if FMeshMode = smRiverRibbon then
      EdgeCol := Vector4(FRibbonColor.X * 0.78, FRibbonColor.Y * 0.88,
        FRibbonColor.Z * 0.92, FRibbonColor.W * 0.65)
    else
      EdgeCol := Vector4(FRibbonColor.X * 0.85, FRibbonColor.Y * 0.85,
        FRibbonColor.Z * 0.85, FRibbonColor.W);

    for I := 0 to High(FLutSamples) - 1 do
    begin
      S0 := FLutSamples[I];
      S1 := FLutSamples[I + 1];
      Off0 := S0.Position + S0.Up * FRibbonOffsetY;
      Off1 := S1.Position + S1.Up * FRibbonOffsetY;
      L0 := Off0 - S0.Right * (S0.Width * 0.5);
      R0 := Off0 + S0.Right * (S0.Width * 0.5);
      L1 := Off1 - S1.Right * (S1.Width * 0.5);
      R1 := Off1 + S1.Right * (S1.Width * 0.5);
      EmitTri(L0, R0, R1, S0.Up, S0.Up, S1.Up, EdgeCol, CenterCol, CenterCol);
      EmitTri(L0, R1, L1, S0.Up, S1.Up, S1.Up, EdgeCol, CenterCol, EdgeCol);
    end;
  end else
  begin
    { smCableTube: cylindrical extrusion with FTubeSides radial facets }
    Sides := Max(3, FTubeSides);
    FGeneratedTriangleCount := (Length(FLutSamples) - 1) * Sides * 2;
    FVertexBuffer.Count := FGeneratedTriangleCount * 3;
    FNormalBuffer.Count := FGeneratedTriangleCount * 3;
    FColorBuffer.Count := FGeneratedTriangleCount * 3;

    for I := 0 to High(FLutSamples) - 1 do
    begin
      S0 := FLutSamples[I];
      S1 := FLutSamples[I + 1];
      Rad0 := Max(0.005, S0.Width * 0.5);
      Rad1 := Max(0.005, S1.Width * 0.5);
      for J := 0 to Sides - 1 do
      begin
        Ang0 := (2.0 * Pi * J) / Sides;
        Ang1 := (2.0 * Pi * (J + 1)) / Sides;
        N0A := (S0.Right * Cos(Ang0) + S0.Up * Sin(Ang0)).Normalize;
        N0B := (S0.Right * Cos(Ang1) + S0.Up * Sin(Ang1)).Normalize;
        N1A := (S1.Right * Cos(Ang0) + S1.Up * Sin(Ang0)).Normalize;
        N1B := (S1.Right * Cos(Ang1) + S1.Up * Sin(Ang1)).Normalize;

        P0A := S0.Position + N0A * Rad0;
        P0B := S0.Position + N0B * Rad0;
        P1A := S1.Position + N1A * Rad1;
        P1B := S1.Position + N1B * Rad1;

        EmitTri(P0A, P0B, P1B, N0A, N0B, N1B, FRibbonColor, FRibbonColor, FRibbonColor);
        EmitTri(P0A, P1B, P1A, N0A, N1B, N1A, FRibbonColor, FRibbonColor, FRibbonColor);
      end;
    end;
  end;

  FCoordNode.SetPoint(FVertexBuffer);
  FNormalNode.SetVector(FNormalBuffer);
  FColorNode.SetColor(FColorBuffer);
end;

function TCastleSplinePath.SplineSummaryBadge: String;
begin
  Result := Format('[Spline:%s %dpts %.1fm]', [
    SplineMeshModeToString(FMeshMode),
    Length(FPoints),
    TotalLength
  ]);
end;

{ TCastleSplineFollowerBehavior ---------------------------------------------- }

constructor TCastleSplineFollowerBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSplineName := '';
  FSpeedMetersPerSec := DefaultFollowerSpeed;
  FCurrentDistance := 0.0;
  FLoopMode := sflmLoop;
  FAlignToTangent := true;
  FVerticalOffset := 0.0;
  FPlaying := true;
  FPingPongDirection := 1;
end;

function TCastleSplineFollowerBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'SplineName', 'SpeedMetersPerSec', 'CurrentDistance',
       'LoopMode', 'AlignToTangent', 'VerticalOffset', 'Playing'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleSplineFollowerBehavior.SpeedStored: Boolean;
begin
  Result := not SameValue(FSpeedMetersPerSec, DefaultFollowerSpeed, 0.0001);
end;

function TCastleSplineFollowerBehavior.CurrentDistanceStored: Boolean;
begin
  Result := not SameValue(FCurrentDistance, 0.0, 0.0001);
end;

function TCastleSplineFollowerBehavior.VerticalOffsetStored: Boolean;
begin
  Result := not SameValue(FVerticalOffset, 0.0, 0.0001);
end;

function TCastleSplineFollowerBehavior.ResolveSpline(
  const ARoot: TComponent): TCastleSplinePath;

  function SearchTree(const C: TComponent): TCastleSplinePath;
  var
    I: Integer;
    T: TCastleTransform;
  begin
    Result := nil;
    if C = nil then
      Exit;
    if (C is TCastleSplinePath) and SameText(C.Name, FSplineName) then
      Exit(TCastleSplinePath(C));
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        if not (csTransient in T[I].ComponentStyle) then
        begin
          Result := SearchTree(T[I]);
          if Result <> nil then
            Exit;
        end;
    end;
    for I := 0 to C.ComponentCount - 1 do
      if not (csTransient in C.Components[I].ComponentStyle) then
      begin
        Result := SearchTree(C.Components[I]);
        if Result <> nil then
          Exit;
      end;
  end;

begin
  Result := nil;
  if Trim(FSplineName) = '' then
    Exit;
  if ARoot <> nil then
    Result := SearchTree(ARoot);
  if (Result = nil) and (Parent <> nil) and (Parent.World <> nil) then
    Result := SearchTree(Parent.World);
  if (Result = nil) and (Owner <> nil) then
    Result := SearchTree(Owner);
end;

procedure TCastleSplineFollowerBehavior.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FPlaying and (not CastleDesignMode) then
    StepFollow(SecondsPassed, nil);
end;

function TCastleSplineFollowerBehavior.StepFollow(const ASecondsPassed: Single;
  const ARoot: TComponent): Boolean;
var
  Spline: TCastleSplinePath;
  Len, NextD: Single;
  Sample: TSplineSample;
  TargetWorldPos: TVector3;
begin
  Result := false;
  if Parent = nil then
    Exit;
  Spline := ResolveSpline(ARoot);
  if Spline = nil then
    Exit;

  Len := Spline.TotalLength;
  if Len <= 1e-5 then
    Exit;

  if FPingPongDirection = 0 then
    FPingPongDirection := 1;

  NextD := FCurrentDistance + ASecondsPassed * FSpeedMetersPerSec * FPingPongDirection;
  case FLoopMode of
    sflmOnce:
      NextD := Clamped(NextD, 0.0, Len);
    sflmLoop:
      begin
        NextD := Frac(NextD / Len) * Len;
        if NextD < 0.0 then
          NextD := NextD + Len;
      end;
    sflmPingPong:
      begin
        while (NextD > Len) or (NextD < 0.0) do
        begin
          if NextD > Len then
          begin
            NextD := 2.0 * Len - NextD;
            FPingPongDirection := -1;
          end else
          if NextD < 0.0 then
          begin
            NextD := -NextD;
            FPingPongDirection := 1;
          end;
        end;
        NextD := Clamped(NextD, 0.0, Len);
      end;
  end;
  FCurrentDistance := NextD;

  Sample := Spline.EvaluateWorldAtDistance(FCurrentDistance);
  TargetWorldPos := Sample.Position + Sample.Up * FVerticalOffset;
  if (Parent.Parent <> nil) and Parent.Parent.HasWorldTransform then
    Parent.Translation := Parent.Parent.WorldToLocal(TargetWorldPos)
  else
    Parent.Translation := TargetWorldPos;

  if FAlignToTangent then
  begin
    if (Parent.Parent <> nil) and Parent.Parent.HasWorldTransform then
      Parent.SetView(
        Parent.Parent.WorldToLocalDirection(Sample.Tangent),
        Parent.Parent.WorldToLocalDirection(Sample.Up))
    else
      Parent.SetView(Sample.Tangent, Sample.Up);
  end;

  Result := true;
end;

function TCastleSplineFollowerBehavior.FollowerSummaryBadge: String;
begin
  Result := Format('[Follow:%s %.1fm/s]', [FSplineName, FSpeedMetersPerSec]);
end;

initialization
  RegisterSerializableComponent(TCastleSplinePath, 'Spline Path (Road / River / Cable)');
  RegisterSerializableComponent(TCastleSplineFollowerBehavior, ['Spline', 'Spline Follower']);
end.
