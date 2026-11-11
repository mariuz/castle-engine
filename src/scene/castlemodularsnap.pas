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

{ Typed modular connector sockets (@link(TCastleSnapSocket)), architectural
  kitbash piece behaviors (@link(TCastleModularPieceBehavior)), closed-form 180°
  opposing-socket world alignment, and world AABB overlap validation
  (Phase 301 — UE 6.0 Modular Socket Snapping & PCG Dungeon Grammar Parity). }
unit CastleModularSnap;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math,
  CastleVectors, CastleColors, CastleBoxes, CastleClassUtils, CastleUtils,
  CastleTransform, CastleScene, X3DNodes;

type
  { Built-in modular architectural kitbash archetypes. }
  TModularPieceKind = (
    mpkCustom,
    mpkEntryHall,
    mpkCorridorStraight,
    mpkCornerTurnL,
    mpkCrossJunction,
    mpkTreasureChamber
  );

  { Named typed 3D connector socket whose local @code(+Z) points outward from
    the piece doorway/flange (matching @code(TCastleTransform.DefaultOrientation))
    and local @code(+Y) points upward. }
  TCastleSnapSocket = class(TCastleTransform)
  strict private
    FSocketCategory: String;
    FOccupied: Boolean;
    FConnectedSocketName: String;
    FShowSocketInViewport: Boolean;
    procedure SetSocketCategory(const Value: String);
  public
    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    { Check category compatibility (@code(SameText) or wildcard @code('*')). }
    function IsCompatibleWith(const AOther: TCastleSnapSocket): Boolean;

    { Compute world/hierarchy position, outward @code(+Z) unit direction, and
      @code(+Y) unit up vector (works both inside @code(TCastleViewport) and in
      headless @code(TCastleTransform) hierarchies). }
    procedure GetHierarchyWorldFrame(out OutPos, OutOutwardDir, OutUp: TVector3);

    function SocketSummaryBadge: String;
  published
    property SocketCategory: String read FSocketCategory write SetSocketCategory;
    property Occupied: Boolean read FOccupied write FOccupied default false;
    property ConnectedSocketName: String read FConnectedSocketName write FConnectedSocketName;
    property ShowSocketInViewport: Boolean
      read FShowSocketInViewport write FShowSocketInViewport default true;
  end;

  { Behavior marking a @link(TCastleTransform) as a modular room/corridor/kitbash
    piece with explicit footprint bounds and optional @code(csTransient) PBR
    greybox floor/trim visualization. }
  TCastleModularPieceBehavior = class(TCastleBehavior)
  strict private
    FPieceKind: TModularPieceKind;
    FPieceBoundsExtents: TVector3;
    FPieceBoundsExtentsPersistent: TCastleVector3Persistent;
    FGenerateGreyboxPreview: Boolean;
    FGreyboxScene: TCastleScene;
    FRootNode: TX3DRootNode;

    function GetPieceBoundsExtentsForPersistent: TVector3;
    procedure SetPieceBoundsExtentsForPersistent(const AValue: TVector3);
    procedure SetPieceKind(const Value: TModularPieceKind);
    procedure SetPieceBoundsExtents(const Value: TVector3);
    procedure SetGenerateGreyboxPreview(const Value: Boolean);
    procedure RebuildGreyboxPreview;
    procedure FreeGreyboxPreview;
  protected
    procedure ParentAfterAttach; override;
    procedure ParentBeforeDetach; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;

    class function PieceKindDisplayName(const AKind: TModularPieceKind): String; static;

    { Compute world-space AABB of this modular piece's @link(PieceBoundsExtents). }
    function ComputeHierarchyWorldBox: TBox3D;

    function PieceSummaryBadge: String;

    property PieceBoundsExtents: TVector3
      read FPieceBoundsExtents write SetPieceBoundsExtents;
  published
    property PieceKind: TModularPieceKind
      read FPieceKind write SetPieceKind default mpkCustom;
    property PieceBoundsExtentsPersistent: TCastleVector3Persistent
      read FPieceBoundsExtentsPersistent;
    property GenerateGreyboxPreview: Boolean
      read FGenerateGreyboxPreview write SetGenerateGreyboxPreview default true;
  end;

{ Compute accumulated 4x4 matrix of @code(T) up to the root @link(TCastleTransform). }
function GetHierarchyTransformMatrix(const T: TCastleTransform): TMatrix4;

{ Align @code(AMovingPiece) in world/parent space so its descendant socket
  @code(AMovingSocket) meets @code(ATargetSocket) flush at @code(TargetPos)
  with exact 180-degree opposing outward @code(-Z) normals and matched @code(+Y) Up. }
function SnapModularPieceToTargetSocket(const AMovingPiece: TCastleTransform;
  const AMovingSocket, ATargetSocket: TCastleSnapSocket;
  const AMarkOccupied: Boolean = true): Boolean;

{ Return @true if @code(ACandidatePiece)'s shrunk world footprint intersects any
  piece in @code(AExistingPieces) (ignoring @code(AIgnoreNeighborPiece)). }
function CheckModularPieceWorldOverlap(
  const ACandidatePiece, AIgnoreNeighborPiece: TCastleTransform;
  const AExistingPieces: array of TCastleTransform;
  const AShrinkMargin: Single = 0.08): Boolean;

implementation

uses
  CastleComponentSerialize;

function GetHierarchyTransformMatrix(const T: TCastleTransform): TMatrix4;
var
  Cur: TCastleTransform;
begin
  Result := TMatrix4.Identity;
  Cur := T;
  while (Cur <> nil) and (not (Cur is TCastleAbstractRootTransform)) do
  begin
    { Stop before an unparented design root container whose Parent is nil so
      sibling pieces inside DesignRoot share DesignRoot's coordinate frame. }
    if Cur.Parent = nil then
      Break;
    Result := Cur.Transform * Result;
    Cur := Cur.Parent;
  end;
end;

function GetRelativeTransformMatrix(const ADescendant, AAncestor: TCastleTransform): TMatrix4;
var
  Cur: TCastleTransform;
begin
  Result := TMatrix4.Identity;
  Cur := ADescendant;
  while (Cur <> nil) and (Cur <> AAncestor) do
  begin
    Result := Cur.Transform * Result;
    Cur := Cur.Parent;
  end;
end;

function SnapModularPieceToTargetSocket(const AMovingPiece: TCastleTransform;
  const AMovingSocket, ATargetSocket: TCastleSnapSocket;
  const AMarkOccupied: Boolean): Boolean;
var
  RelMat, ParentMat, ParentInv: TMatrix4;
  SockPosLocal, SockOutLocal, SockUpLocal, SockRightLocal, ScaledPos: TVector3;
  TargetPosW, TargetOutW, TargetUpW: TVector3;
  DesOutW, DesUpW, DesRightW: TVector3;
  PieceDirW, PieceUpW, RotatedOffsetW, PiecePosW: TVector3;
  PiecePosLocal, PieceDirLocal, PieceUpLocal: TVector3;
  Col1W, Col2W: TVector3;
begin
  Result := false;
  if (AMovingPiece = nil) or (AMovingSocket = nil) or (ATargetSocket = nil) then
    Exit;
  if not AMovingSocket.IsCompatibleWith(ATargetSocket) then
    Exit;

  { 1. MovingSocket frame inside AMovingPiece local space (+Z is outward) }
  RelMat := GetRelativeTransformMatrix(AMovingSocket, AMovingPiece);
  SockPosLocal := RelMat.MultPoint(TVector3.Zero);
  SockOutLocal := RelMat.MultDirection(Vector3(0.0, 0.0, 1.0));
  SockUpLocal := RelMat.MultDirection(Vector3(0.0, 1.0, 0.0));
  if SockOutLocal.LengthSqr < 1e-8 then
    SockOutLocal := Vector3(0.0, 0.0, 1.0)
  else
    SockOutLocal := SockOutLocal.Normalize;
  if SockUpLocal.LengthSqr < 1e-8 then
    SockUpLocal := Vector3(0.0, 1.0, 0.0)
  else
    SockUpLocal := SockUpLocal.Normalize;
  MakeVectorsOrthoOnTheirPlane(SockUpLocal, SockOutLocal);
  SockUpLocal := SockUpLocal.Normalize;
  SockRightLocal := TVector3.CrossProduct(SockUpLocal, SockOutLocal).Normalize;

  { 2. TargetSocket frame in hierarchy world space }
  ATargetSocket.GetHierarchyWorldFrame(TargetPosW, TargetOutW, TargetUpW);

  { 3. Desired 180-degree opposing frame for MovingSocket }
  DesOutW := -TargetOutW;
  DesUpW := TargetUpW;
  MakeVectorsOrthoOnTheirPlane(DesUpW, DesOutW);
  if DesUpW.LengthSqr < 1e-8 then
    DesUpW := Vector3(0.0, 1.0, 0.0)
  else
    DesUpW := DesUpW.Normalize;
  DesRightW := TVector3.CrossProduct(DesUpW, DesOutW).Normalize;

  { 4. Closed-form right-handed 3x3 rotation R = B_desired * (B_local)^T:
       For any piece-local vector V, R * V =
         DesRightW * Dot(SockRightLocal, V) +
         DesUpW    * Dot(SockUpLocal, V) +
         DesOutW   * Dot(SockOutLocal, V). }
  Col1W :=
    DesRightW * SockRightLocal.Y +
    DesUpW    * SockUpLocal.Y +
    DesOutW   * SockOutLocal.Y;
  Col2W :=
    DesRightW * SockRightLocal.Z +
    DesUpW    * SockUpLocal.Z +
    DesOutW   * SockOutLocal.Z;

  PieceUpW := Col1W.Normalize;
  PieceDirW := Col2W.Normalize; // TCastleTransform.DefaultOrientation is otUpYDirectionZ (+Z)

  ScaledPos := SockPosLocal * AMovingPiece.Scale;
  RotatedOffsetW :=
    DesRightW * TVector3.DotProduct(SockRightLocal, ScaledPos) +
    DesUpW    * TVector3.DotProduct(SockUpLocal, ScaledPos) +
    DesOutW   * TVector3.DotProduct(SockOutLocal, ScaledPos);

  PiecePosW := TargetPosW - RotatedOffsetW;

  { 5. Convert world view into AMovingPiece.Parent local space }
  if (AMovingPiece.Parent <> nil) and
     (not (AMovingPiece.Parent is TCastleAbstractRootTransform)) and
     (AMovingPiece.Parent.Parent <> nil) then
  begin
    ParentMat := GetHierarchyTransformMatrix(AMovingPiece.Parent);
    if ParentMat.TryInverse(ParentInv) then
    begin
      PiecePosLocal := ParentInv.MultPoint(PiecePosW);
      PieceDirLocal := ParentInv.MultDirection(PieceDirW).Normalize;
      PieceUpLocal := ParentInv.MultDirection(PieceUpW).Normalize;
    end else
    begin
      PiecePosLocal := PiecePosW;
      PieceDirLocal := PieceDirW;
      PieceUpLocal := PieceUpW;
    end;
  end else
  begin
    PiecePosLocal := PiecePosW;
    PieceDirLocal := PieceDirW;
    PieceUpLocal := PieceUpW;
  end;

  AMovingPiece.SetView(PiecePosLocal, PieceDirLocal, PieceUpLocal);

  if AMarkOccupied then
  begin
    AMovingSocket.Occupied := true;
    ATargetSocket.Occupied := true;
    AMovingSocket.ConnectedSocketName := ATargetSocket.Name;
    ATargetSocket.ConnectedSocketName := AMovingSocket.Name;
  end;
  Result := true;
end;

function GetPieceWorldBox(const APiece: TCastleTransform): TBox3D;
var
  Beh: TCastleModularPieceBehavior;
  M: TMatrix4;
  HalfE: TVector3;
begin
  Beh := APiece.FindBehavior(TCastleModularPieceBehavior) as TCastleModularPieceBehavior;
  if Beh <> nil then
    Exit(Beh.ComputeHierarchyWorldBox);

  HalfE := Vector3(2.0, 2.0, 2.0);
  M := GetHierarchyTransformMatrix(APiece);
  Result := Box3D(-HalfE, HalfE).Transform(M);
end;

function ShrinkBox3D(const B: TBox3D; const AMargin: Single): TBox3D;
var
  MinP, MaxP: TVector3;
begin
  if B.IsEmpty then
    Exit(TBox3D.Empty);
  MinP := B.Data[0] + Vector3(AMargin, AMargin, AMargin);
  MaxP := B.Data[1] - Vector3(AMargin, AMargin, AMargin);
  if (MinP.X >= MaxP.X) or (MinP.Y >= MaxP.Y) or (MinP.Z >= MaxP.Z) then
    Exit(TBox3D.Empty);
  Result := Box3D(MinP, MaxP);
end;

function CheckModularPieceWorldOverlap(
  const ACandidatePiece, AIgnoreNeighborPiece: TCastleTransform;
  const AExistingPieces: array of TCastleTransform;
  const AShrinkMargin: Single): Boolean;
var
  CandBox, OtherBox: TBox3D;
  I: Integer;
begin
  Result := false;
  if ACandidatePiece = nil then
    Exit;
  CandBox := ShrinkBox3D(GetPieceWorldBox(ACandidatePiece), AShrinkMargin);
  if CandBox.IsEmpty then
    Exit;

  for I := Low(AExistingPieces) to High(AExistingPieces) do
  begin
    if (AExistingPieces[I] = nil) or
       (AExistingPieces[I] = ACandidatePiece) or
       (AExistingPieces[I] = AIgnoreNeighborPiece) then
      Continue;
    OtherBox := ShrinkBox3D(GetPieceWorldBox(AExistingPieces[I]), AShrinkMargin);
    if (not OtherBox.IsEmpty) and CandBox.Collision(OtherBox) then
      Exit(true);
  end;
end;

{ TCastleSnapSocket ---------------------------------------------------------- }

constructor TCastleSnapSocket.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSocketCategory := 'Doorway_3m';
  FOccupied := false;
  FConnectedSocketName := '';
  FShowSocketInViewport := true;
end;

function TCastleSnapSocket.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'SocketCategory', 'Occupied', 'ConnectedSocketName', 'ShowSocketInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleSnapSocket.SetSocketCategory(const Value: String);
begin
  FSocketCategory := Trim(Value);
  if FSocketCategory = '' then
    FSocketCategory := 'Doorway_3m';
end;

function TCastleSnapSocket.IsCompatibleWith(const AOther: TCastleSnapSocket): Boolean;
begin
  Result := (AOther <> nil) and
    ((FSocketCategory = '*') or (AOther.SocketCategory = '*') or
     SameText(FSocketCategory, AOther.SocketCategory));
end;

procedure TCastleSnapSocket.GetHierarchyWorldFrame(
  out OutPos, OutOutwardDir, OutUp: TVector3);
var
  M: TMatrix4;
begin
  M := GetHierarchyTransformMatrix(Self);
  OutPos := M.MultPoint(TVector3.Zero);
  OutOutwardDir := M.MultDirection(Vector3(0.0, 0.0, 1.0));
  OutUp := M.MultDirection(Vector3(0.0, 1.0, 0.0));
  if OutOutwardDir.LengthSqr < 1e-8 then
    OutOutwardDir := Vector3(0.0, 0.0, 1.0)
  else
    OutOutwardDir := OutOutwardDir.Normalize;
  if OutUp.LengthSqr < 1e-8 then
    OutUp := Vector3(0.0, 1.0, 0.0)
  else
    OutUp := OutUp.Normalize;
end;

function TCastleSnapSocket.SocketSummaryBadge: String;
begin
  if FOccupied then
  begin
    if FConnectedSocketName <> '' then
      Result := Format('[Socket:%s -> %s]', [FSocketCategory, FConnectedSocketName])
    else
      Result := Format('[Socket:%s USED]', [FSocketCategory]);
  end else
    Result := Format('[Socket:%s OPEN]', [FSocketCategory]);
end;

{ TCastleModularPieceBehavior ------------------------------------------------ }

constructor TCastleModularPieceBehavior.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPieceKind := mpkCustom;
  FPieceBoundsExtents := Vector3(6.0, 4.0, 6.0);
  FGenerateGreyboxPreview := true;

  FPieceBoundsExtentsPersistent := TCastleVector3Persistent.Create(nil);
  FPieceBoundsExtentsPersistent.InternalGetValue := @GetPieceBoundsExtentsForPersistent;
  FPieceBoundsExtentsPersistent.InternalSetValue := @SetPieceBoundsExtentsForPersistent;
  FPieceBoundsExtentsPersistent.InternalDefaultValue := FPieceBoundsExtents;
end;

destructor TCastleModularPieceBehavior.Destroy;
begin
  FreeGreyboxPreview;
  FreeAndNil(FPieceBoundsExtentsPersistent);
  inherited;
end;

function TCastleModularPieceBehavior.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'PieceKind', 'PieceBoundsExtentsPersistent', 'GenerateGreyboxPreview'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

class function TCastleModularPieceBehavior.PieceKindDisplayName(
  const AKind: TModularPieceKind): String;
begin
  case AKind of
    mpkCustom: Result := 'Custom Piece';
    mpkEntryHall: Result := 'Entry Hall';
    mpkCorridorStraight: Result := 'Straight Corridor';
    mpkCornerTurnL: Result := 'Corner Turn L';
    mpkCrossJunction: Result := '4-Way Cross Junction';
    mpkTreasureChamber: Result := 'Treasure Chamber';
  end;
end;

function TCastleModularPieceBehavior.GetPieceBoundsExtentsForPersistent: TVector3;
begin
  Result := FPieceBoundsExtents;
end;

procedure TCastleModularPieceBehavior.SetPieceBoundsExtentsForPersistent(
  const AValue: TVector3);
begin
  SetPieceBoundsExtents(AValue);
end;

procedure TCastleModularPieceBehavior.SetPieceKind(const Value: TModularPieceKind);
begin
  if FPieceKind = Value then
    Exit;
  FPieceKind := Value;
  RebuildGreyboxPreview;
end;

procedure TCastleModularPieceBehavior.SetPieceBoundsExtents(const Value: TVector3);
begin
  FPieceBoundsExtents := Vector3(
    Max(0.5, Value.X),
    Max(0.5, Value.Y),
    Max(0.5, Value.Z));
  RebuildGreyboxPreview;
end;

procedure TCastleModularPieceBehavior.SetGenerateGreyboxPreview(const Value: Boolean);
begin
  if FGenerateGreyboxPreview = Value then
    Exit;
  FGenerateGreyboxPreview := Value;
  RebuildGreyboxPreview;
end;

procedure TCastleModularPieceBehavior.ParentAfterAttach;
begin
  inherited;
  RebuildGreyboxPreview;
end;

procedure TCastleModularPieceBehavior.ParentBeforeDetach;
begin
  FreeGreyboxPreview;
  inherited;
end;

procedure TCastleModularPieceBehavior.FreeGreyboxPreview;
begin
  if FGreyboxScene <> nil then
  begin
    if FGreyboxScene.Parent <> nil then
      FGreyboxScene.Parent.Remove(FGreyboxScene);
    FreeAndNil(FGreyboxScene);
  end;
  FRootNode := nil;
end;

procedure TCastleModularPieceBehavior.RebuildGreyboxPreview;
var
  ShapeFloor: TShapeNode;
  FloorBox: TBoxNode;
  FloorMat: TPhysicalMaterialNode;
  TransNode: TTransformNode;
begin
  FreeGreyboxPreview;
  if (not FGenerateGreyboxPreview) or (Parent = nil) or (Parent is TCastleScene) then
    Exit;

  FGreyboxScene := TCastleScene.Create(nil);
  FGreyboxScene.SetTransient;
  FGreyboxScene.Pickable := false;
  FGreyboxScene.Collides := true;

  FRootNode := TX3DRootNode.Create;
  FloorBox := TBoxNode.CreateWithTransform(ShapeFloor, TransNode);
  TransNode.Translation := Vector3(0.0, 0.10, 0.0);
  FloorBox.Size := Vector3(
    Max(0.4, FPieceBoundsExtents.X - 0.12),
    0.20,
    Max(0.4, FPieceBoundsExtents.Z - 0.12));

  FloorMat := TPhysicalMaterialNode.Create;
  case FPieceKind of
    mpkEntryHall: FloorMat.BaseColor := Vector3(0.26, 0.36, 0.48);
    mpkCorridorStraight: FloorMat.BaseColor := Vector3(0.32, 0.34, 0.38);
    mpkCornerTurnL: FloorMat.BaseColor := Vector3(0.38, 0.34, 0.28);
    mpkCrossJunction: FloorMat.BaseColor := Vector3(0.34, 0.42, 0.34);
    mpkTreasureChamber: FloorMat.BaseColor := Vector3(0.52, 0.40, 0.18);
  else
    FloorMat.BaseColor := Vector3(0.35, 0.35, 0.38);
  end;
  FloorMat.Roughness := 0.78;
  ShapeFloor.Material := FloorMat;

  FRootNode.AddChildren(TransNode);
  FGreyboxScene.Load(FRootNode, true);
  Parent.Add(FGreyboxScene);
end;

function TCastleModularPieceBehavior.ComputeHierarchyWorldBox: TBox3D;
var
  HalfX, HalfZ: Single;
  LocalB: TBox3D;
  M: TMatrix4;
begin
  if Parent = nil then
    Exit(TBox3D.Empty);
  HalfX := FPieceBoundsExtents.X * 0.5;
  HalfZ := FPieceBoundsExtents.Z * 0.5;
  LocalB := Box3D(
    Vector3(-HalfX, 0.0, -HalfZ),
    Vector3(HalfX, FPieceBoundsExtents.Y, HalfZ));
  M := GetHierarchyTransformMatrix(Parent);
  Result := LocalB.Transform(M);
end;

function TCastleModularPieceBehavior.PieceSummaryBadge: String;
begin
  Result := Format('[Modular:%s %.0fx%.0fm]',
    [PieceKindDisplayName(FPieceKind), FPieceBoundsExtents.X, FPieceBoundsExtents.Z]);
end;

initialization
  RegisterSerializableComponent(TCastleSnapSocket,
    ['Level Design', 'Modular Snap Socket']);
  RegisterSerializableComponent(TCastleModularPieceBehavior,
    ['Level Design', 'Modular Piece Behavior']);
end.
