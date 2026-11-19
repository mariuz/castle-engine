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

{ Planar Portal & Seamless Mirror Oblique Frustum Teleport (Phase 377).
  Implements linked SE(3) portal pairs with 180-degree doorway turnaround,
  planar mirror reflection, Lengyel oblique near-plane clip equations,
  aperture-bounded segment crossing detection, anti-ping-pong cooldown
  hysteresis, and transient glowing arch previews. }
unit CastlePortalPair;

{$I castleconf.inc}

interface

uses SysUtils, Classes, Math,
  CastleVectors, CastleTransform, CastleScene, CastleRenderOptions, CastleColors,
  CastleClassUtils, CastleComponentSerialize;

type
  TPortalPreset = (
    ppLinkedBlueOrangePair,
    ppGrandHallPlanarMirror,
    ppInfiniteCorridorLoop,
    ppCustom
  );

  TPortalWarpSample = record
    ValidTarget: Boolean;
    VirtualEyePos: TVector3;
    VirtualViewDir: TVector3;
    ObliqueClipPlane: TVector4;
    EffectiveRecursionDepth: Integer;
  end;

  { Planar portal gateway or seamless mirror plane with SE(3) warp and crossing detection. }
  TCastlePortalGateway = class(TCastleTransform)
  private
    FPreset: TPortalPreset;
    FLinkedPortalName: String;
    FMirrorMode: Boolean;
    FPortalWidthMeters: Single;
    FPortalHeightMeters: Single;
    FPortalYawDeg: Single;
    FMaxRecursionDepth: Integer;
    FClipPlaneBiasMeters: Single;
    FTeleportCooldownSec: Single;
    FShowPreviewFrame: Boolean;
    FCooldownRemainingSec: Single;
    FTeleportCount: Integer;
    FPreviewRoot: TCastleTransform;
    FLeftPillar, FRightPillar, FTopLintel, FSurfacePane: TCastleBox;
    procedure SetPreset(const Value: TPortalPreset);
    procedure SetLinkedPortalName(const Value: String);
    procedure SetMirrorMode(const Value: Boolean);
    procedure SetPortalWidthMeters(const Value: Single);
    procedure SetPortalHeightMeters(const Value: Single);
    procedure SetPortalYawDeg(const Value: Single);
    procedure SetMaxRecursionDepth(const Value: Integer);
    procedure SetClipPlaneBiasMeters(const Value: Single);
    procedure SetTeleportCooldownSec(const Value: Single);
    procedure SetShowPreviewFrame(const Value: Boolean);
    function GetConfigJson: String;
    procedure SetConfigJson(const Value: String);
    procedure RebuildPreviewFrame;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { World-space basis vectors of this portal doorway (Right, Up=(0,1,0), OutwardNormal). }
    procedure GetPortalBasis(out RightAxis, UpAxis, OutwardNormal: TVector3);

    { Find linked destination portal in RootOwner / hierarchy if LinkedPortalName is set. }
    function ResolveLinkedPortal(const SearchRoot: TComponent): TCastlePortalGateway;

    { Evaluate virtual camera eye, view direction, and Lengyel oblique clip plane. }
    function EvaluateVirtualCameraView(const SearchRoot: TComponent;
      const ObserverEye, ObserverForward: TVector3): TPortalWarpSample;

    { Test segment PrevPos -> NextPos for front-to-back doorway crossing and warp position/velocity. }
    function TryCrossPortal(const SearchRoot: TComponent;
      const PrevPos, NextPos, InVelocity: TVector3;
      out WarpedPos, WarpedVelocity: TVector3): Boolean;

    procedure StepPortalCooldown(const DtSec: Single);
    procedure GrantCooldownLockout;
    function PortalSummaryBadge: String;

    property CooldownRemainingSec: Single read FCooldownRemainingSec;
    property TeleportCount: Integer read FTeleportCount;
  published
    property Preset: TPortalPreset read FPreset write SetPreset default ppLinkedBlueOrangePair;
    property LinkedPortalName: String read FLinkedPortalName write SetLinkedPortalName;
    property MirrorMode: Boolean read FMirrorMode write SetMirrorMode default False;
    property PortalWidthMeters: Single read FPortalWidthMeters write SetPortalWidthMeters {$ifdef FPC}default 2.4{$endif};
    property PortalHeightMeters: Single read FPortalHeightMeters write SetPortalHeightMeters {$ifdef FPC}default 3.2{$endif};
    property PortalYawDeg: Single read FPortalYawDeg write SetPortalYawDeg {$ifdef FPC}default 0.0{$endif};
    property MaxRecursionDepth: Integer read FMaxRecursionDepth write SetMaxRecursionDepth default 2;
    property ClipPlaneBiasMeters: Single read FClipPlaneBiasMeters write SetClipPlaneBiasMeters {$ifdef FPC}default 0.02{$endif};
    property TeleportCooldownSec: Single read FTeleportCooldownSec write SetTeleportCooldownSec {$ifdef FPC}default 0.25{$endif};
    property ShowPreviewFrame: Boolean read FShowPreviewFrame write SetShowPreviewFrame default True;
    property ConfigJson: String read GetConfigJson write SetConfigJson stored True;
  end;

implementation

uses fpjson, jsonparser;

constructor TCastlePortalGateway.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := ppLinkedBlueOrangePair;
  FLinkedPortalName := '';
  FMirrorMode := False;
  FPortalWidthMeters := 2.4;
  FPortalHeightMeters := 3.2;
  FPortalYawDeg := 0.0;
  FMaxRecursionDepth := 2;
  FClipPlaneBiasMeters := 0.02;
  FTeleportCooldownSec := 0.25;
  FShowPreviewFrame := True;
  FCooldownRemainingSec := 0.0;
  FTeleportCount := 0;
  RebuildPreviewFrame;
end;

destructor TCastlePortalGateway.Destroy;
begin
  inherited Destroy;
end;

function TCastlePortalGateway.PropertySections(const PropertyName: String): TPropertySections;
begin
  if (PropertyName = 'Preset') or
     (PropertyName = 'LinkedPortalName') or
     (PropertyName = 'MirrorMode') or
     (PropertyName = 'PortalWidthMeters') or
     (PropertyName = 'PortalHeightMeters') or
     (PropertyName = 'PortalYawDeg') or
     (PropertyName = 'MaxRecursionDepth') or
     (PropertyName = 'ClipPlaneBiasMeters') or
     (PropertyName = 'TeleportCooldownSec') or
     (PropertyName = 'ShowPreviewFrame') then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastlePortalGateway.GetPortalBasis(out RightAxis, UpAxis, OutwardNormal: TVector3);
var
  YawRad, S, C: Single;
begin
  YawRad := DegToRad(FPortalYawDeg);
  SinCos(YawRad, S, C);
  OutwardNormal := Vector3(S, 0.0, C);
  RightAxis := Vector3(C, 0.0, -S);
  UpAxis := Vector3(0.0, 1.0, 0.0);
end;

function TCastlePortalGateway.ResolveLinkedPortal(const SearchRoot: TComponent): TCastlePortalGateway;

  function WalkComp(const Comp: TComponent): TCastlePortalGateway;
  var
    I: Integer;
    T: TCastleTransform;
  begin
    Result := nil;
    if Comp = nil then Exit;
    if (Comp is TCastlePortalGateway) and (Comp <> Self) and
       SameText(Comp.Name, FLinkedPortalName) then
      Exit(TCastlePortalGateway(Comp));
    if Comp is TCastleTransform then
    begin
      T := TCastleTransform(Comp);
      for I := 0 to T.Count - 1 do
      begin
        Result := WalkComp(T[I]);
        if Result <> nil then Exit;
      end;
    end;
    for I := 0 to Comp.ComponentCount - 1 do
    begin
      Result := WalkComp(Comp.Components[I]);
      if Result <> nil then Exit;
    end;
  end;

begin
  Result := nil;
  if Trim(FLinkedPortalName) = '' then Exit;
  if SearchRoot <> nil then
    Result := WalkComp(SearchRoot);
  if (Result = nil) and (Owner <> nil) then
    Result := WalkComp(Owner);
end;

function TCastlePortalGateway.EvaluateVirtualCameraView(const SearchRoot: TComponent;
  const ObserverEye, ObserverForward: TVector3): TPortalWarpSample;
var
  InR, InU, InN, OutR, OutU, OutN, Rel, FwdNorm, PlanePoint: TVector3;
  LocalX, LocalY, LocalZ, FwdR, FwdU, FwdN: Single;
  Dest: TCastlePortalGateway;
begin
  FillChar(Result, SizeOf(Result), 0);
  GetPortalBasis(InR, InU, InN);
  FwdNorm := ObserverForward;
  if FwdNorm.LengthSqr < 1e-6 then
    FwdNorm := -InN
  else
    FwdNorm := FwdNorm.Normalize;

  if FMirrorMode then
  begin
    Result.ValidTarget := True;
    Rel := ObserverEye - Translation;
    Result.VirtualEyePos := ObserverEye - InN * (2.0 * TVector3.DotProduct(Rel, InN));
    Result.VirtualViewDir := (FwdNorm - InN * (2.0 * TVector3.DotProduct(FwdNorm, InN))).Normalize;
    PlanePoint := Translation + InN * FClipPlaneBiasMeters;
    Result.ObliqueClipPlane := Vector4(InN.X, InN.Y, InN.Z,
      -TVector3.DotProduct(InN, PlanePoint));
    Result.EffectiveRecursionDepth := FMaxRecursionDepth;
    Exit;
  end;

  Dest := ResolveLinkedPortal(SearchRoot);
  if Dest = nil then
    Exit;

  Dest.GetPortalBasis(OutR, OutU, OutN);
  Rel := ObserverEye - Translation;
  LocalX := TVector3.DotProduct(Rel, InR);
  LocalY := TVector3.DotProduct(Rel, InU);
  LocalZ := TVector3.DotProduct(Rel, InN);

  FwdR := TVector3.DotProduct(FwdNorm, InR);
  FwdU := TVector3.DotProduct(FwdNorm, InU);
  FwdN := TVector3.DotProduct(FwdNorm, InN);

  { 180-degree doorway turnaround: +InN maps to -OutN, +InR maps to -OutR }
  Result.ValidTarget := True;
  Result.VirtualEyePos := Dest.Translation - OutR * LocalX + OutU * LocalY - OutN * LocalZ;
  Result.VirtualViewDir := (-OutR * FwdR + OutU * FwdU - OutN * FwdN).Normalize;
  PlanePoint := Dest.Translation + OutN * Dest.ClipPlaneBiasMeters;
  Result.ObliqueClipPlane := Vector4(OutN.X, OutN.Y, OutN.Z,
    -TVector3.DotProduct(OutN, PlanePoint));
  Result.EffectiveRecursionDepth := Min(FMaxRecursionDepth, Dest.MaxRecursionDepth);
end;

function TCastlePortalGateway.TryCrossPortal(const SearchRoot: TComponent;
  const PrevPos, NextPos, InVelocity: TVector3;
  out WarpedPos, WarpedVelocity: TVector3): Boolean;
var
  InR, InU, InN, OutR, OutU, OutN, HitWorld, RelHit, RelAfter: TVector3;
  DistPrev, DistNext, TFrac, HitX, HitY, AfterX, AfterY, AfterZ, VelR, VelU, VelN: Single;
  Dest: TCastlePortalGateway;
begin
  Result := False;
  WarpedPos := NextPos;
  WarpedVelocity := InVelocity;

  if FMirrorMode or (FCooldownRemainingSec > 1e-5) then
    Exit;

  Dest := ResolveLinkedPortal(SearchRoot);
  if (Dest = nil) or (Dest.CooldownRemainingSec > 1e-5) then
    Exit;

  GetPortalBasis(InR, InU, InN);
  DistPrev := TVector3.DotProduct(PrevPos - Translation, InN);
  DistNext := TVector3.DotProduct(NextPos - Translation, InN);

  { Must cross from front side (DistPrev > 0) to back/plane side (DistNext <= 0) }
  if not ((DistPrev > 0.0) and (DistNext <= 0.0)) then
    Exit;

  TFrac := DistPrev / Max(1e-6, DistPrev - DistNext);
  HitWorld := PrevPos + (NextPos - PrevPos) * TFrac;
  RelHit := HitWorld - Translation;
  HitX := TVector3.DotProduct(RelHit, InR);
  HitY := TVector3.DotProduct(RelHit, InU);

  if (Abs(HitX) > FPortalWidthMeters * 0.5) or
     (HitY < -0.05) or (HitY > FPortalHeightMeters + 0.05) then
    Exit;

  Dest.GetPortalBasis(OutR, OutU, OutN);
  RelAfter := NextPos - Translation;
  AfterX := TVector3.DotProduct(RelAfter, InR);
  AfterY := TVector3.DotProduct(RelAfter, InU);
  AfterZ := TVector3.DotProduct(RelAfter, InN); // <= 0 -> -AfterZ >= 0 in front of Dest!

  WarpedPos := Dest.Translation - OutR * AfterX + OutU * AfterY - OutN * AfterZ;

  VelR := TVector3.DotProduct(InVelocity, InR);
  VelU := TVector3.DotProduct(InVelocity, InU);
  VelN := TVector3.DotProduct(InVelocity, InN);
  WarpedVelocity := -OutR * VelR + OutU * VelU - OutN * VelN;

  Inc(FTeleportCount);
  GrantCooldownLockout;
  Dest.GrantCooldownLockout;
  Result := True;
end;

procedure TCastlePortalGateway.StepPortalCooldown(const DtSec: Single);
begin
  if DtSec <= 0.0 then Exit;
  FCooldownRemainingSec := Max(0.0, FCooldownRemainingSec - DtSec);
end;

procedure TCastlePortalGateway.GrantCooldownLockout;
begin
  FCooldownRemainingSec := Max(FCooldownRemainingSec, FTeleportCooldownSec);
end;

function TCastlePortalGateway.PortalSummaryBadge: String;
var
  DestLabel: String;
begin
  if FMirrorMode then
    Result := Format('[Portal:MIRROR %.1fx%.1fm Depth=%d]', [
      FPortalWidthMeters, FPortalHeightMeters, FMaxRecursionDepth])
  else
  begin
    if FLinkedPortalName <> '' then
      DestLabel := FLinkedPortalName
    else
      DestLabel := 'unlinked';
    Result := Format('[Portal:->%s %.1fx%.1fm Warps=%d]', [
      DestLabel, FPortalWidthMeters, FPortalHeightMeters, FTeleportCount]);
  end;
end;

procedure TCastlePortalGateway.RebuildPreviewFrame;
var
  FrameColor, PaneColor: TCastleColor;
  HalfW, PillarThick: Single;
begin
  if FPreviewRoot = nil then
  begin
    FPreviewRoot := TCastleTransform.Create(Self);
    FPreviewRoot.SetTransient;
    FPreviewRoot.Name := 'PortalFrameTransient';
    Add(FPreviewRoot);

    FLeftPillar := TCastleBox.Create(FPreviewRoot);
    FLeftPillar.SetTransient;
    FLeftPillar.Material := pmUnlit;
    FPreviewRoot.Add(FLeftPillar);

    FRightPillar := TCastleBox.Create(FPreviewRoot);
    FRightPillar.SetTransient;
    FRightPillar.Material := pmUnlit;
    FPreviewRoot.Add(FRightPillar);

    FTopLintel := TCastleBox.Create(FPreviewRoot);
    FTopLintel.SetTransient;
    FTopLintel.Material := pmUnlit;
    FPreviewRoot.Add(FTopLintel);

    FSurfacePane := TCastleBox.Create(FPreviewRoot);
    FSurfacePane.SetTransient;
    FSurfacePane.Material := pmUnlit;
    FPreviewRoot.Add(FSurfacePane);
  end;

  FPreviewRoot.Exists := FShowPreviewFrame;
  FPreviewRoot.Rotation := Vector4(0.0, 1.0, 0.0, DegToRad(FPortalYawDeg));

  if FMirrorMode then
  begin
    FrameColor := Vector4(0.82, 0.88, 0.96, 1.0);
    PaneColor := Vector4(0.65, 0.78, 0.94, 0.55);
  end else if Pos('orange', LowerCase(Name)) > 0 then
  begin
    FrameColor := Vector4(1.0, 0.52, 0.12, 1.0);
    PaneColor := Vector4(0.95, 0.42, 0.08, 0.45);
  end else
  begin
    FrameColor := Vector4(0.14, 0.78, 1.0, 1.0);
    PaneColor := Vector4(0.10, 0.62, 0.95, 0.45);
  end;

  HalfW := FPortalWidthMeters * 0.5;
  PillarThick := 0.14;

  FLeftPillar.Size := Vector3(PillarThick, FPortalHeightMeters, PillarThick);
  FLeftPillar.Translation := Vector3(-HalfW - PillarThick * 0.5, FPortalHeightMeters * 0.5, 0.0);
  FLeftPillar.Color := FrameColor;

  FRightPillar.Size := Vector3(PillarThick, FPortalHeightMeters, PillarThick);
  FRightPillar.Translation := Vector3(HalfW + PillarThick * 0.5, FPortalHeightMeters * 0.5, 0.0);
  FRightPillar.Color := FrameColor;

  FTopLintel.Size := Vector3(FPortalWidthMeters + PillarThick * 2.0, PillarThick, PillarThick);
  FTopLintel.Translation := Vector3(0.0, FPortalHeightMeters + PillarThick * 0.5, 0.0);
  FTopLintel.Color := FrameColor;

  FSurfacePane.Size := Vector3(FPortalWidthMeters, FPortalHeightMeters, 0.03);
  FSurfacePane.Translation := Vector3(0.0, FPortalHeightMeters * 0.5, 0.0);
  FSurfacePane.Color := PaneColor;
end;

procedure TCastlePortalGateway.SetPreset(const Value: TPortalPreset);
begin
  if FPreset = Value then Exit;
  FPreset := Value;
  case Value of
    ppLinkedBlueOrangePair:
      begin
        FMirrorMode := False;
        FPortalWidthMeters := 2.4;
        FPortalHeightMeters := 3.2;
        FMaxRecursionDepth := 2;
        FClipPlaneBiasMeters := 0.02;
        FTeleportCooldownSec := 0.25;
      end;
    ppGrandHallPlanarMirror:
      begin
        FMirrorMode := True;
        FLinkedPortalName := '';
        FPortalWidthMeters := 4.8;
        FPortalHeightMeters := 3.6;
        FMaxRecursionDepth := 1;
        FClipPlaneBiasMeters := 0.01;
      end;
    ppInfiniteCorridorLoop:
      begin
        FMirrorMode := False;
        FPortalWidthMeters := 3.0;
        FPortalHeightMeters := 3.5;
        FMaxRecursionDepth := 4;
        FClipPlaneBiasMeters := 0.02;
        FTeleportCooldownSec := 0.15;
      end;
    ppCustom: ;
  end;
  RebuildPreviewFrame;
end;

procedure TCastlePortalGateway.SetLinkedPortalName(const Value: String);
var
  Trimmed: String;
begin
  Trimmed := Trim(Value);
  if FLinkedPortalName = Trimmed then Exit;
  FLinkedPortalName := Trimmed;
end;

procedure TCastlePortalGateway.SetMirrorMode(const Value: Boolean);
begin
  if FMirrorMode = Value then Exit;
  FMirrorMode := Value;
  FPreset := ppCustom;
  RebuildPreviewFrame;
end;

procedure TCastlePortalGateway.SetPortalWidthMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.5, 30.0);
  if SameValue(FPortalWidthMeters, Clamped, 1e-4) then Exit;
  FPortalWidthMeters := Clamped;
  FPreset := ppCustom;
  RebuildPreviewFrame;
end;

procedure TCastlePortalGateway.SetPortalHeightMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.5, 30.0);
  if SameValue(FPortalHeightMeters, Clamped, 1e-4) then Exit;
  FPortalHeightMeters := Clamped;
  FPreset := ppCustom;
  RebuildPreviewFrame;
end;

procedure TCastlePortalGateway.SetPortalYawDeg(const Value: Single);
begin
  if SameValue(FPortalYawDeg, Value, 1e-4) then Exit;
  FPortalYawDeg := Value;
  RebuildPreviewFrame;
end;

procedure TCastlePortalGateway.SetMaxRecursionDepth(const Value: Integer);
var
  Clamped: Integer;
begin
  Clamped := EnsureRange(Value, 1, 6);
  if FMaxRecursionDepth = Clamped then Exit;
  FMaxRecursionDepth := Clamped;
  FPreset := ppCustom;
end;

procedure TCastlePortalGateway.SetClipPlaneBiasMeters(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.0, 0.5);
  if SameValue(FClipPlaneBiasMeters, Clamped, 1e-5) then Exit;
  FClipPlaneBiasMeters := Clamped;
  FPreset := ppCustom;
end;

procedure TCastlePortalGateway.SetTeleportCooldownSec(const Value: Single);
var
  Clamped: Single;
begin
  Clamped := EnsureRange(Value, 0.0, 5.0);
  if SameValue(FTeleportCooldownSec, Clamped, 1e-4) then Exit;
  FTeleportCooldownSec := Clamped;
  FPreset := ppCustom;
end;

procedure TCastlePortalGateway.SetShowPreviewFrame(const Value: Boolean);
begin
  if FShowPreviewFrame = Value then Exit;
  FShowPreviewFrame := Value;
  RebuildPreviewFrame;
end;

function TCastlePortalGateway.GetConfigJson: String;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(FPreset));
    Obj.Add('linkedPortalName', FLinkedPortalName);
    Obj.Add('mirrorMode', FMirrorMode);
    Obj.Add('portalWidthMeters', FPortalWidthMeters);
    Obj.Add('portalHeightMeters', FPortalHeightMeters);
    Obj.Add('portalYawDeg', FPortalYawDeg);
    Obj.Add('maxRecursionDepth', FMaxRecursionDepth);
    Obj.Add('clipPlaneBiasMeters', FClipPlaneBiasMeters);
    Obj.Add('teleportCooldownSec', FTeleportCooldownSec);
    Result := Obj.AsJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

procedure TCastlePortalGateway.SetConfigJson(const Value: String);
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
    FLinkedPortalName := Obj.Get('linkedPortalName', FLinkedPortalName);
    FMirrorMode := Obj.Get('mirrorMode', FMirrorMode);
    FPortalWidthMeters := EnsureRange(Obj.Get('portalWidthMeters', FPortalWidthMeters), 0.5, 30.0);
    FPortalHeightMeters := EnsureRange(Obj.Get('portalHeightMeters', FPortalHeightMeters), 0.5, 30.0);
    FPortalYawDeg := Obj.Get('portalYawDeg', FPortalYawDeg);
    FMaxRecursionDepth := EnsureRange(Obj.Get('maxRecursionDepth', FMaxRecursionDepth), 1, 6);
    FClipPlaneBiasMeters := EnsureRange(Obj.Get('clipPlaneBiasMeters', FClipPlaneBiasMeters), 0.0, 0.5);
    FTeleportCooldownSec := EnsureRange(Obj.Get('teleportCooldownSec', FTeleportCooldownSec), 0.0, 5.0);
    SavedPreset := Obj.Get('preset', Ord(FPreset));
    if (SavedPreset >= Ord(Low(TPortalPreset))) and (SavedPreset <= Ord(High(TPortalPreset))) then
      FPreset := TPortalPreset(SavedPreset);
    RebuildPreviewFrame;
  finally
    FreeAndNil(Data);
  end;
end;

initialization
  RegisterSerializableComponent(TCastlePortalGateway, 'Planar Portal & Seamless Mirror');
end.
