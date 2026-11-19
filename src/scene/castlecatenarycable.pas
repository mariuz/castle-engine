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

{ Exact hyperbolic cosine catenary cable, powerline sag solver, wind pendulum
  sway, and arc-length hanging lantern/insulator attachments (Phase 385). }
unit CastleCatenaryCable;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, X3DNodes,
  CastleClassUtils, CastleComponentSerialize, CastleColors;

type
  { Ready-made catenary utility and decorative garland presets. }
  TCatenaryPreset = (
    ccpFestivalLanternGarland,
    ccpHighVoltagePowerline,
    ccpHarborMooringHawser
  );

  { Computed world-space pose of an arc-length-spaced hanging lantern or weight. }
  TCatenaryLanternAttachment = record
    WorldPos: TVector3;
    CableTangent: TVector3;
    ArcFraction01: Single;
    PendulumTiltRad: Single;
  end;

  { Procedural hyperbolic cosine catenary cable between two local/world anchors
    with wind sway and arc-length-distributed hanging attachments. }
  TCastleCatenaryCable = class(TCastleTransform)
  private
    FPreset: TCatenaryPreset;
    FStartX, FStartY, FStartZ: Single;
    FEndX, FEndY, FEndZ: Single;
    FSlackRatio: Single;
    FCableRadiusMeters: Single;
    FSubdivisionSegments: Integer;
    FHangingAttachmentCount: Integer;
    FWindSpeedMps: Single;
    FWindDirectionDeg: Single;
    FSwayFrequencyHz: Single;
    FShowPreviewMesh: Boolean;
    FPhaseTimeSec: Single;
    FCatenaryParamA: Single;
    FTotalArcLengthMeters: Single;
    FMidpointSagMeters: Single;
    FKnotsWorld: array of TVector3;
    FCumArcLen: array of Single;
    FAttachments: array of TCatenaryLanternAttachment;
    FPreviewRoot: TCastleTransform;
    FCableScene: TCastleScene;
    FCoordNode: TCoordinateNode;
    FColorNode: TColorNode;
    procedure SetPreset(const AValue: TCatenaryPreset);
    procedure SetStartX(const AValue: Single);
    procedure SetStartY(const AValue: Single);
    procedure SetStartZ(const AValue: Single);
    procedure SetEndX(const AValue: Single);
    procedure SetEndY(const AValue: Single);
    procedure SetEndZ(const AValue: Single);
    procedure SetSlackRatio(const AValue: Single);
    procedure SetCableRadiusMeters(const AValue: Single);
    procedure SetSubdivisionSegments(const AValue: Integer);
    procedure SetHangingAttachmentCount(const AValue: Integer);
    procedure SetWindSpeedMps(const AValue: Single);
    procedure SetSwayFrequencyHz(const AValue: Single);
    procedure SetShowPreviewMesh(const AValue: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const AValue: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TCatenaryPreset);

    { Solve exact cosh catenary, wind sway, arc-length LUT, and attachment poses. }
    procedure RebuildCatenary;

    { Advance harmonic wind pendulum sway by ADtSec and rebuild. }
    procedure StepWindSway(const ADtSec: Single);

    { Evaluate world-space point along the solved cable for T01 in [0..1]. }
    function EvaluatePointAtNormalizedSpan(const AT01: Single): TVector3;

    function KnotCount: Integer;
    function GetKnotWorld(const AIndex: Integer): TVector3;
    function AttachmentCount: Integer;
    function GetAttachment(const AIndex: Integer): TCatenaryLanternAttachment;
    function CableSummaryBadge: String;

    property CatenaryParamA: Single read FCatenaryParamA;
    property TotalArcLengthMeters: Single read FTotalArcLengthMeters;
    property MidpointSagMeters: Single read FMidpointSagMeters;
  published
    property Preset: TCatenaryPreset read FPreset write SetPreset default ccpFestivalLanternGarland;
    property StartX: Single read FStartX write SetStartX;
    property StartY: Single read FStartY write SetStartY;
    property StartZ: Single read FStartZ write SetStartZ;
    property EndX: Single read FEndX write SetEndX;
    property EndY: Single read FEndY write SetEndY;
    property EndZ: Single read FEndZ write SetEndZ;
    property SlackRatio: Single read FSlackRatio write SetSlackRatio;
    property CableRadiusMeters: Single read FCableRadiusMeters write SetCableRadiusMeters;
    property SubdivisionSegments: Integer read FSubdivisionSegments write SetSubdivisionSegments default 24;
    property HangingAttachmentCount: Integer read FHangingAttachmentCount write SetHangingAttachmentCount default 5;
    property WindSpeedMps: Single read FWindSpeedMps write SetWindSpeedMps;
    property WindDirectionDeg: Single read FWindDirectionDeg write FWindDirectionDeg;
    property SwayFrequencyHz: Single read FSwayFrequencyHz write SetSwayFrequencyHz;
    property ShowPreviewMesh: Boolean read FShowPreviewMesh write SetShowPreviewMesh default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored False;
  end;

implementation

uses FpJson, JsonParser, CastleUtils;

function SafeArsinh(const X: Double): Double;
begin
  Result := Ln(X + Sqrt(X * X + 1.0));
end;

{ TCastleCatenaryCable ------------------------------------------------------- }

constructor TCastleCatenaryCable.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStartX := -8.0; FStartY := 6.0; FStartZ := 0.0;
  FEndX := 8.0;    FEndY := 6.0;   FEndZ := 0.0;
  FSlackRatio := 1.14;
  FCableRadiusMeters := 0.045;
  FSubdivisionSegments := 24;
  FHangingAttachmentCount := 5;
  FWindSpeedMps := 4.5;
  FWindDirectionDeg := 90.0;
  FSwayFrequencyHz := 0.65;
  FShowPreviewMesh := True;
  ApplyPreset(ccpFestivalLanternGarland);
end;

destructor TCastleCatenaryCable.Destroy;
begin
  FreeAndNil(FPreviewRoot);
  SetLength(FKnotsWorld, 0);
  SetLength(FCumArcLen, 0);
  SetLength(FAttachments, 0);
  inherited Destroy;
end;

function TCastleCatenaryCable.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'StartX', 'StartY', 'StartZ', 'EndX', 'EndY', 'EndZ',
       'SlackRatio', 'CableRadiusMeters', 'SubdivisionSegments',
       'HangingAttachmentCount', 'WindSpeedMps', 'WindDirectionDeg',
       'SwayFrequencyHz', 'ShowPreviewMesh'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleCatenaryCable.ApplyPreset(const APreset: TCatenaryPreset);
begin
  FPreset := APreset;
  case APreset of
    ccpFestivalLanternGarland:
      begin
        FSlackRatio := 1.14;
        FCableRadiusMeters := 0.04;
        FSubdivisionSegments := 28;
        FHangingAttachmentCount := 5;
        FWindSpeedMps := 4.5;
        FSwayFrequencyHz := 0.65;
      end;
    ccpHighVoltagePowerline:
      begin
        FSlackRatio := 1.03;
        FCableRadiusMeters := 0.03;
        FSubdivisionSegments := 32;
        FHangingAttachmentCount := 0;
        FWindSpeedMps := 6.0;
        FSwayFrequencyHz := 0.45;
      end;
    ccpHarborMooringHawser:
      begin
        FSlackRatio := 1.28;
        FCableRadiusMeters := 0.09;
        FSubdivisionSegments := 24;
        FHangingAttachmentCount := 3;
        FWindSpeedMps := 2.0;
        FSwayFrequencyHz := 0.35;
      end;
  end;
  RebuildCatenary;
end;

procedure TCastleCatenaryCable.SetPreset(const AValue: TCatenaryPreset);
begin
  if FPreset <> AValue then
    ApplyPreset(AValue);
end;

procedure TCastleCatenaryCable.SetStartX(const AValue: Single);
begin FStartX := AValue; RebuildCatenary; end;

procedure TCastleCatenaryCable.SetStartY(const AValue: Single);
begin FStartY := AValue; RebuildCatenary; end;

procedure TCastleCatenaryCable.SetStartZ(const AValue: Single);
begin FStartZ := AValue; RebuildCatenary; end;

procedure TCastleCatenaryCable.SetEndX(const AValue: Single);
begin FEndX := AValue; RebuildCatenary; end;

procedure TCastleCatenaryCable.SetEndY(const AValue: Single);
begin FEndY := AValue; RebuildCatenary; end;

procedure TCastleCatenaryCable.SetEndZ(const AValue: Single);
begin FEndZ := AValue; RebuildCatenary; end;

procedure TCastleCatenaryCable.SetSlackRatio(const AValue: Single);
begin
  FSlackRatio := EnsureRange(AValue, 1.0005, 3.0);
  RebuildCatenary;
end;

procedure TCastleCatenaryCable.SetCableRadiusMeters(const AValue: Single);
begin
  FCableRadiusMeters := Max(0.005, AValue);
  RebuildCatenary;
end;

procedure TCastleCatenaryCable.SetSubdivisionSegments(const AValue: Integer);
begin
  FSubdivisionSegments := EnsureRange(AValue, 6, 64);
  RebuildCatenary;
end;

procedure TCastleCatenaryCable.SetHangingAttachmentCount(const AValue: Integer);
begin
  FHangingAttachmentCount := EnsureRange(AValue, 0, 16);
  RebuildCatenary;
end;

procedure TCastleCatenaryCable.SetWindSpeedMps(const AValue: Single);
begin
  FWindSpeedMps := Max(0.0, AValue);
  RebuildCatenary;
end;

procedure TCastleCatenaryCable.SetSwayFrequencyHz(const AValue: Single);
begin
  FSwayFrequencyHz := Max(0.05, AValue);
end;

procedure TCastleCatenaryCable.SetShowPreviewMesh(const AValue: Boolean);
begin
  if FShowPreviewMesh <> AValue then
  begin
    FShowPreviewMesh := AValue;
    RebuildCatenary;
  end;
end;

procedure TCastleCatenaryCable.RebuildCatenary;
var
  WT, InvWorld: TMatrix4;
  PStartW, PEndW, SpanHorizVec, LateralDir, WindHorizDir, PtW, SegDir, SideA, SideB: TVector3;
  H, V, Chord, TargetL, TargetRatio, LoU, HiU, MidU, AParam, X0, Y0: Double;
  Iter, Segs, I, K, SegIdx: Integer;
  T, XVal, BaseY, SwayEnv, WindRad, SwayAmp, SwayDisp, SegFrac, TargetArc, HalfR: Single;
  ChordMidY, CableMidY: Single;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  TriSet: TTriangleSetNode;
  Verts, Colors: TVector3List;
  CableCol: TVector3;
  LanternBox: TCastleBox;

  procedure AddQuadW(const A, B, Offs, Col: TVector3);
  begin
    Verts.Add(InvWorld.MultPoint(A - Offs));
    Verts.Add(InvWorld.MultPoint(A + Offs));
    Verts.Add(InvWorld.MultPoint(B + Offs));
    Colors.Add(Col); Colors.Add(Col); Colors.Add(Col);

    Verts.Add(InvWorld.MultPoint(A - Offs));
    Verts.Add(InvWorld.MultPoint(B + Offs));
    Verts.Add(InvWorld.MultPoint(B - Offs));
    Colors.Add(Col); Colors.Add(Col); Colors.Add(Col);
  end;

begin
  if HasWorldTransform then
    WT := WorldTransform
  else
    WT := Transform;
  if not WT.TryInverse(InvWorld) then
    InvWorld := TMatrix4.Identity;

  PStartW := WT.MultPoint(Vector3(FStartX, FStartY, FStartZ));
  PEndW := WT.MultPoint(Vector3(FEndX, FEndY, FEndZ));

  SpanHorizVec := Vector3(PEndW.X - PStartW.X, 0.0, PEndW.Z - PStartW.Z);
  H := SpanHorizVec.Length;
  V := PEndW.Y - PStartW.Y;
  Chord := Sqrt(H * H + V * V);
  TargetL := Max(Chord * 1.0005, Chord * FSlackRatio);

  Segs := Max(6, FSubdivisionSegments);
  SetLength(FKnotsWorld, Segs + 1);
  SetLength(FCumArcLen, Segs + 1);

  { Solve sinh(u)/u = sqrt(L^2 - V^2) / H for u = H / (2*a) }
  if H < 1e-3 then
  begin
    FCatenaryParamA := 0.01;
    AParam := 0.01;
    X0 := 0.0;
    Y0 := Min(PStartW.Y, PEndW.Y);
  end else
  begin
    TargetRatio := Max(1.00001, Sqrt(Max(0.0, TargetL * TargetL - V * V)) / H);
    LoU := 1e-4;
    HiU := 18.0;
    for Iter := 1 to 60 do
    begin
      MidU := 0.5 * (LoU + HiU);
      if (Sinh(MidU) / MidU) < TargetRatio then
        LoU := MidU
      else
        HiU := MidU;
    end;
    MidU := 0.5 * (LoU + HiU);
    AParam := H / (2.0 * MidU);
    FCatenaryParamA := AParam;
    X0 := 0.5 * H - AParam * SafeArsinh(V / Max(1e-9, 2.0 * AParam * Sinh(MidU)));
    Y0 := PStartW.Y - AParam * Cosh(-X0 / AParam);
  end;

  WindRad := DegToRad(FWindDirectionDeg);
  WindHorizDir := Vector3(Cos(WindRad), 0.0, Sin(WindRad));
  if H > 1e-3 then
  begin
    LateralDir := TVector3.CrossProduct(SpanHorizVec.Normalize, Vector3(0, 1, 0)).Normalize;
    SwayAmp := (FWindSpeedMps * 0.065) * (0.25 + 0.75 * Abs(TVector3.DotProduct(WindHorizDir, LateralDir)))
      * (0.65 + 0.35 * Sin(2.0 * Pi * FSwayFrequencyHz * FPhaseTimeSec));
  end else
  begin
    LateralDir := Vector3(0, 0, 1);
    SwayAmp := 0.0;
  end;

  for I := 0 to Segs do
  begin
    if I = 0 then
      PtW := PStartW
    else if I = Segs then
      PtW := PEndW
    else
    begin
      T := I / Single(Segs);
      if H < 1e-3 then
        BaseY := Lerp(T, PStartW.Y, PEndW.Y) - (TargetL - Chord) * 0.5 * Sin(Pi * T)
      else
      begin
        XVal := T * H;
        BaseY := Y0 + AParam * Cosh((XVal - X0) / AParam);
      end;
      SwayEnv := Sin(Pi * T);
      SwayDisp := SwayAmp * SwayEnv * Max(0.25, Min(3.5, (TargetL - Chord) + 0.35));
      PtW := Vector3(
        Lerp(T, PStartW.X, PEndW.X),
        BaseY,
        Lerp(T, PStartW.Z, PEndW.Z)) + LateralDir * SwayDisp;
    end;
    FKnotsWorld[I] := PtW;
    if I = 0 then
      FCumArcLen[0] := 0.0
    else
      FCumArcLen[I] := FCumArcLen[I - 1] + PointsDistance(FKnotsWorld[I - 1], FKnotsWorld[I]);
  end;

  FTotalArcLengthMeters := FCumArcLen[Segs];
  ChordMidY := 0.5 * (PStartW.Y + PEndW.Y);
  CableMidY := EvaluatePointAtNormalizedSpan(0.5).Y;
  FMidpointSagMeters := Max(0.0, ChordMidY - CableMidY);

  { Compute arc-length-spaced hanging lantern attachments at (K+1)/(Count+1) }
  SetLength(FAttachments, FHangingAttachmentCount);
  for K := 0 to FHangingAttachmentCount - 1 do
  begin
    FAttachments[K] := Default(TCatenaryLanternAttachment);
    FAttachments[K].ArcFraction01 := (K + 1) / Single(FHangingAttachmentCount + 1);
    TargetArc := FAttachments[K].ArcFraction01 * FTotalArcLengthMeters;
    SegIdx := 0;
    while (SegIdx < Segs - 1) and (FCumArcLen[SegIdx + 1] < TargetArc) do
      Inc(SegIdx);
    SegFrac := EnsureRange(
      (TargetArc - FCumArcLen[SegIdx]) / Max(1e-5, FCumArcLen[SegIdx + 1] - FCumArcLen[SegIdx]),
      0.0, 1.0);
    FAttachments[K].WorldPos := Lerp(SegFrac, FKnotsWorld[SegIdx], FKnotsWorld[SegIdx + 1]);
    SegDir := FKnotsWorld[SegIdx + 1] - FKnotsWorld[SegIdx];
    if SegDir.LengthSqr > 1e-8 then
      FAttachments[K].CableTangent := SegDir.Normalize
    else
      FAttachments[K].CableTangent := Vector3(1, 0, 0);
    FAttachments[K].PendulumTiltRad := ArcTan2(SwayAmp, 1.0);
  end;

  { Rebuild csTransient preview cable + lantern housings }
  FreeAndNil(FPreviewRoot);
  FCableScene := nil;
  if not FShowPreviewMesh then Exit;

  FPreviewRoot := TCastleTransform.Create(nil);
  FPreviewRoot.SetTransient;
  FPreviewRoot.Pickable := False;
  FPreviewRoot.Collides := False;
  FPreviewRoot.Name := 'TransientCatenaryPreview';

  FCableScene := TCastleScene.Create(FPreviewRoot);
  FCableScene.SetTransient;
  FCableScene.Pickable := False;
  FCableScene.Collides := False;
  FCableScene.PreciseCollisions := False;

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
  FCableScene.Load(Root, True);
  FPreviewRoot.Add(FCableScene);

  Verts := TVector3List.Create;
  Colors := TVector3List.Create;
  try
    case FPreset of
      ccpFestivalLanternGarland: CableCol := Vector3(0.24, 0.22, 0.20);
      ccpHighVoltagePowerline:   CableCol := Vector3(0.32, 0.35, 0.38);
      ccpHarborMooringHawser:    CableCol := Vector3(0.62, 0.48, 0.30);
    end;
    HalfR := FCableRadiusMeters;
    for I := 0 to Segs - 1 do
    begin
      SegDir := FKnotsWorld[I + 1] - FKnotsWorld[I];
      if SegDir.LengthSqr < 1e-7 then Continue;
      SegDir := SegDir.Normalize;
      SideA := TVector3.CrossProduct(SegDir, Vector3(0, 1, 0));
      if SideA.LengthSqr < 1e-5 then
        SideA := TVector3.CrossProduct(SegDir, Vector3(1, 0, 0));
      SideA := SideA.Normalize;
      SideB := TVector3.CrossProduct(SegDir, SideA).Normalize;
      AddQuadW(FKnotsWorld[I], FKnotsWorld[I + 1], SideA * HalfR, CableCol);
      AddQuadW(FKnotsWorld[I], FKnotsWorld[I + 1], SideB * HalfR, CableCol);
    end;
    FCoordNode.SetPoint(Verts);
    FCoordNode.FdPoint.Changed;
    FColorNode.SetColor(Colors);
    FColorNode.FdColor.Changed;
  finally
    FreeAndNil(Colors);
    FreeAndNil(Verts);
  end;

  for K := 0 to High(FAttachments) do
  begin
    LanternBox := TCastleBox.Create(FPreviewRoot);
    LanternBox.SetTransient;
    LanternBox.Pickable := False;
    LanternBox.Collides := False;
    LanternBox.Size := Vector3(0.28, 0.38, 0.28);
    LanternBox.Translation := InvWorld.MultPoint(FAttachments[K].WorldPos - Vector3(0, 0.22, 0));
    LanternBox.Color := Vector4(1.0, 0.78, 0.32, 1.0);
    FPreviewRoot.Add(LanternBox);
  end;

  Add(FPreviewRoot);
end;

procedure TCastleCatenaryCable.StepWindSway(const ADtSec: Single);
begin
  if ADtSec <= 0.0 then Exit;
  FPhaseTimeSec := FPhaseTimeSec + ADtSec;
  RebuildCatenary;
end;

procedure TCastleCatenaryCable.Update(const SecondsPassed: Single;
  var RemoveMe: TRemoveType);
begin
  inherited Update(SecondsPassed, RemoveMe);
  if FWindSpeedMps > 0.01 then
    StepWindSway(Min(SecondsPassed, 0.1));
end;

function TCastleCatenaryCable.EvaluatePointAtNormalizedSpan(
  const AT01: Single): TVector3;
var
  ClampedT, ScaledIdx, FracPart: Single;
  Idx0, Idx1: Integer;
begin
  if Length(FKnotsWorld) = 0 then
    Exit(WorldTranslation);
  ClampedT := EnsureRange(AT01, 0.0, 1.0);
  ScaledIdx := ClampedT * High(FKnotsWorld);
  Idx0 := Floor(ScaledIdx);
  Idx1 := Min(High(FKnotsWorld), Idx0 + 1);
  FracPart := ScaledIdx - Idx0;
  Result := Lerp(FracPart, FKnotsWorld[Idx0], FKnotsWorld[Idx1]);
end;

function TCastleCatenaryCable.KnotCount: Integer;
begin
  Result := Length(FKnotsWorld);
end;

function TCastleCatenaryCable.GetKnotWorld(const AIndex: Integer): TVector3;
begin
  if (AIndex >= 0) and (AIndex <= High(FKnotsWorld)) then
    Result := FKnotsWorld[AIndex]
  else
    Result := TVector3.Zero;
end;

function TCastleCatenaryCable.AttachmentCount: Integer;
begin
  Result := Length(FAttachments);
end;

function TCastleCatenaryCable.GetAttachment(
  const AIndex: Integer): TCatenaryLanternAttachment;
begin
  if (AIndex >= 0) and (AIndex <= High(FAttachments)) then
    Result := FAttachments[AIndex]
  else
    Result := Default(TCatenaryLanternAttachment);
end;

function TCastleCatenaryCable.CableSummaryBadge: String;
begin
  Result := FormatDot('[Cable:L=%.1fm Sag=%.2fm Lanterns=%d]', [
    FTotalArcLengthMeters, FMidpointSagMeters, Length(FAttachments)]);
end;

function TCastleCatenaryCable.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('startX', FStartX);
    Obj.Add('startY', FStartY);
    Obj.Add('startZ', FStartZ);
    Obj.Add('endX', FEndX);
    Obj.Add('endY', FEndY);
    Obj.Add('endZ', FEndZ);
    Obj.Add('slackRatio', FSlackRatio);
    Obj.Add('cableRadiusMeters', FCableRadiusMeters);
    Obj.Add('subdivisionSegments', FSubdivisionSegments);
    Obj.Add('hangingAttachmentCount', FHangingAttachmentCount);
    Obj.Add('windSpeedMps', FWindSpeedMps);
    Obj.Add('windDirectionDeg', FWindDirectionDeg);
    Obj.Add('swayFrequencyHz', FSwayFrequencyHz);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastleCatenaryCable.SetConfigJson(const AValue: String);
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
      FPreset := TCatenaryPreset(EnsureRange(Obj.Get('preset', Ord(FPreset)), 0, Ord(High(TCatenaryPreset))));
      FStartX := Obj.Get('startX', FStartX);
      FStartY := Obj.Get('startY', FStartY);
      FStartZ := Obj.Get('startZ', FStartZ);
      FEndX := Obj.Get('endX', FEndX);
      FEndY := Obj.Get('endY', FEndY);
      FEndZ := Obj.Get('endZ', FEndZ);
      FSlackRatio := EnsureRange(Obj.Get('slackRatio', FSlackRatio), 1.0005, 3.0);
      FCableRadiusMeters := Max(0.005, Obj.Get('cableRadiusMeters', FCableRadiusMeters));
      FSubdivisionSegments := EnsureRange(Obj.Get('subdivisionSegments', FSubdivisionSegments), 6, 64);
      FHangingAttachmentCount := EnsureRange(Obj.Get('hangingAttachmentCount', FHangingAttachmentCount), 0, 16);
      FWindSpeedMps := Max(0.0, Obj.Get('windSpeedMps', FWindSpeedMps));
      FWindDirectionDeg := Obj.Get('windDirectionDeg', FWindDirectionDeg);
      FSwayFrequencyHz := Max(0.05, Obj.Get('swayFrequencyHz', FSwayFrequencyHz));
      RebuildCatenary;
    end;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastleCatenaryCable,
    ['Architecture & Splines', 'Catenary Cable & Lantern Garland (TCastleCatenaryCable)']);

end.
