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

{ Verlet Cloth / Cape / Banner Grids & Catenary Rope Soft-Body Wind Simulation
  with Pinned Anchors, Iterative Distance/Bending Constraints, Sphere Collider
  Repulsion & Dynamic Weather Wind Coupling (@link(TCastleClothSurface),
  @link(TCastleVerletRope)) (Phase 313 — UE 6.0+ Chaos Cloth & Cable Parity). }
unit CastleClothRope;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils, CastleTransform, CastleScene,
  X3DNodes, CastleTimeOfDayWeather;

type
  { Vertex pinning layout for @link(TCastleClothSurface). }
  TClothPinMode = (
    cpmTopEdge,
    cpmTopTwoCorners,
    cpmLeftPoleEdge,
    cpmFourCorners
  );

  { One-click cloth preset for @link(TCastleClothSurface). }
  TClothPreset = (
    cpCustom,
    cpRoyalBanner,
    cpHeroShoulderCape,
    cpWindFlagOnPole,
    cpCanopyAwning
  );

  { Endpoint pinning mode for @link(TCastleVerletRope). }
  TRopePinMode = (
    rpmBothEndsCatenary,
    rpmStartOnlyPendulum
  );

  { 2D Verlet soft-body cloth surface (@link(TCastleTransform)) generating a
    double-sided PBR @link(TTriangleSetNode) mesh with structural, shear &
    2-hop bending distance constraints, aerodynamic face-normal wind pressure,
    world-space sphere collider repulsion, and optional
    @link(TCastleTimeOfDayWeather) wind synchronization. }
  TCastleClothSurface = class(TCastleTransform)
  public
    const
      DefaultCols = 11;
      DefaultRows = 13;
      DefaultWidth = 1.6;
      DefaultHeight = 2.2;
      DefaultSolverIterations = 8;
      DefaultStructuralStiffness = 1.0;
      DefaultBendStiffness = 0.35;
      DefaultDamping = 0.985;
      DefaultGravityY = -9.81;
      DefaultGustTurbulence = 0.30;
      DefaultColliderRadius = 0.55;
      DefaultRoughness = 0.72;
  strict private
    type
      TClothConstraint = record
        IdxA, IdxB: Integer;
        RestLen: Single;
        Stiffness: Single;
      end;
  strict private
    FPreset: TClothPreset;
    FPinMode: TClothPinMode;
    FCols: Integer;
    FRows: Integer;
    FWidth: Single;
    FHeight: Single;
    FSolverIterations: Integer;
    FStructuralStiffness: Single;
    FBendStiffness: Single;
    FDamping: Single;
    FGravityY: Single;
    FWindVelocity: TVector3;
    FWindVelocityPersistent: TCastleVector3Persistent;
    FGustTurbulence: Single;
    FSyncWithWeather: Boolean;
    FWeatherController: TCastleTimeOfDayWeather;
    FColliderTransform: TCastleTransform;
    FColliderRadius: Single;
    FBaseColor: TCastleColorRGB;
    FBaseColorPersistent: TCastleColorRGBPersistent;
    FRoughness: Single;
    FSimulateInEditor: Boolean;

    FPos: array of TVector3;
    FPrevPos: array of TVector3;
    FPinnedPos: array of TVector3;
    FPinned: array of Boolean;
    FConstraints: array of TClothConstraint;
    FSimTimeSec: Single;
    FOutputTriangleCount: Integer;

    FRenderScene: TCastleScene;
    FRootNode: TX3DRootNode;
    FAppearanceNode: TAppearanceNode;
    FMaterialNode: TPhysicalMaterialNode;
    FTriSetNode: TTriangleSetNode;
    FCoordNode: TCoordinateNode;
    FNormalNode: TNormalNode;

    procedure SetPreset(const Value: TClothPreset);
    procedure SetPinMode(const Value: TClothPinMode);
    procedure SetCols(const Value: Integer);
    procedure SetRows(const Value: Integer);
    procedure SetWidth(const Value: Single);
    procedure SetHeight(const Value: Single);
    procedure SetSolverIterations(const Value: Integer);
    procedure SetWeatherController(const Value: TCastleTimeOfDayWeather);
    procedure SetColliderTransform(const Value: TCastleTransform);
    procedure SetColliderRadius(const Value: Single);
    procedure SetRoughness(const Value: Single);

    function GetWindVelocityForPersistent: TVector3;
    procedure SetWindVelocityForPersistent(const AValue: TVector3);
    function GetBaseColorForPersistent: TCastleColorRGB;
    procedure SetBaseColorForPersistent(const AValue: TCastleColorRGB);

    procedure EnsureRenderScene;
    procedure SyncMaterialProperties;
    procedure BuildConstraints;
    procedure RebuildClothMesh;
    procedure StepSubInterval(const SubDt: Single; const AWindWorld: TVector3);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ApplyPreset(const APreset: TClothPreset);
    procedure ResetClothGrid;
    procedure StepSimulation(const Dt: Single);

    function ParticleCount: Integer;
    function IsParticlePinned(const ACol, ARow: Integer): Boolean;
    function GetParticleLocalPos(const ACol, ARow: Integer): TVector3;
    function GetParticleWorldPos(const ACol, ARow: Integer): TVector3;
    function MaxStretchRatio: Single;
    function EffectiveWindWorld: TVector3;
    function ClothSummaryBadge: String;

    property WindVelocity: TVector3 read FWindVelocity write FWindVelocity;
    property BaseColor: TCastleColorRGB read FBaseColor write FBaseColor;
    property OutputTriangleCount: Integer read FOutputTriangleCount;
  published
    property Preset: TClothPreset read FPreset write SetPreset default cpRoyalBanner;
    property PinMode: TClothPinMode read FPinMode write SetPinMode default cpmTopEdge;
    property Cols: Integer read FCols write SetCols default DefaultCols;
    property Rows: Integer read FRows write SetRows default DefaultRows;
    property Width: Single read FWidth write SetWidth {$ifdef FPC}default DefaultWidth{$endif};
    property Height: Single read FHeight write SetHeight {$ifdef FPC}default DefaultHeight{$endif};
    property SolverIterations: Integer
      read FSolverIterations write SetSolverIterations default DefaultSolverIterations;
    property StructuralStiffness: Single
      read FStructuralStiffness write FStructuralStiffness {$ifdef FPC}default DefaultStructuralStiffness{$endif};
    property BendStiffness: Single
      read FBendStiffness write FBendStiffness {$ifdef FPC}default DefaultBendStiffness{$endif};
    property Damping: Single
      read FDamping write FDamping {$ifdef FPC}default DefaultDamping{$endif};
    property GravityY: Single
      read FGravityY write FGravityY {$ifdef FPC}default DefaultGravityY{$endif};
    property WindVelocityPersistent: TCastleVector3Persistent read FWindVelocityPersistent;
    property GustTurbulence: Single
      read FGustTurbulence write FGustTurbulence {$ifdef FPC}default DefaultGustTurbulence{$endif};
    property SyncWithWeather: Boolean
      read FSyncWithWeather write FSyncWithWeather default False;
    property WeatherController: TCastleTimeOfDayWeather
      read FWeatherController write SetWeatherController;
    property ColliderTransform: TCastleTransform
      read FColliderTransform write SetColliderTransform;
    property ColliderRadius: Single
      read FColliderRadius write SetColliderRadius {$ifdef FPC}default DefaultColliderRadius{$endif};
    property BaseColorPersistent: TCastleColorRGBPersistent read FBaseColorPersistent;
    property Roughness: Single
      read FRoughness write SetRoughness {$ifdef FPC}default DefaultRoughness{$endif};
    property SimulateInEditor: Boolean
      read FSimulateInEditor write FSimulateInEditor default False;
  end;

  { 1D Verlet catenary / pendulum rope (@link(TCastleTransform)) generating a
    cylindrical PBR @link(TTriangleSetNode) cable mesh with segment distance
    constraints, wind drag, and world-space sphere collider repulsion. }
  TCastleVerletRope = class(TCastleTransform)
  public
    const
      DefaultSegmentCount = 18;
      DefaultTotalLength = 6.0;
      DefaultTubeRadius = 0.035;
      DefaultSolverIterations = 12;
      DefaultDamping = 0.988;
      DefaultGravityY = -9.81;
      DefaultColliderRadius = 0.50;
  strict private
    FPinMode: TRopePinMode;
    FSegmentCount: Integer;
    FTotalLength: Single;
    FTubeRadius: Single;
    FSolverIterations: Integer;
    FDamping: Single;
    FGravityY: Single;
    FWindVelocity: TVector3;
    FWindVelocityPersistent: TCastleVector3Persistent;
    FEndOffset: TVector3;
    FEndOffsetPersistent: TCastleVector3Persistent;
    FEndAnchorTransform: TCastleTransform;
    FColliderTransform: TCastleTransform;
    FColliderRadius: Single;
    FRopeColor: TCastleColorRGB;
    FRopeColorPersistent: TCastleColorRGBPersistent;
    FSimulateInEditor: Boolean;

    FNodes: array of TVector3;
    FPrevNodes: array of TVector3;
    FSimTimeSec: Single;
    FOutputTriangleCount: Integer;

    FRenderScene: TCastleScene;
    FRootNode: TX3DRootNode;
    FAppearanceNode: TAppearanceNode;
    FMaterialNode: TPhysicalMaterialNode;
    FTriSetNode: TTriangleSetNode;
    FCoordNode: TCoordinateNode;
    FNormalNode: TNormalNode;

    procedure SetPinMode(const Value: TRopePinMode);
    procedure SetSegmentCount(const Value: Integer);
    procedure SetTotalLength(const Value: Single);
    procedure SetTubeRadius(const Value: Single);
    procedure SetSolverIterations(const Value: Integer);
    procedure SetEndAnchorTransform(const Value: TCastleTransform);
    procedure SetColliderTransform(const Value: TCastleTransform);
    procedure SetColliderRadius(const Value: Single);

    function GetWindVelocityForPersistent: TVector3;
    procedure SetWindVelocityForPersistent(const AValue: TVector3);
    function GetEndOffsetForPersistent: TVector3;
    procedure SetEndOffsetForPersistent(const AValue: TVector3);
    function GetRopeColorForPersistent: TCastleColorRGB;
    procedure SetRopeColorForPersistent(const AValue: TCastleColorRGB);

    function ResolveEndAnchorLocal: TVector3;
    procedure EnsureRenderScene;
    procedure SyncMaterialProperties;
    procedure RebuildRopeMesh;
    procedure StepSubInterval(const SubDt: Single);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;

    procedure ResetRope;
    procedure StepSimulation(const Dt: Single);

    function NodeCount: Integer;
    function GetNodeLocalPos(const AIndex: Integer): TVector3;
    function GetNodeWorldPos(const AIndex: Integer): TVector3;
    function LowestSagLocalY: Single;
    function MaxStretchRatio: Single;
    function RopeSummaryBadge: String;

    property WindVelocity: TVector3 read FWindVelocity write FWindVelocity;
    property EndOffset: TVector3 read FEndOffset write FEndOffset;
    property RopeColor: TCastleColorRGB read FRopeColor write FRopeColor;
    property OutputTriangleCount: Integer read FOutputTriangleCount;
  published
    property PinMode: TRopePinMode read FPinMode write SetPinMode default rpmBothEndsCatenary;
    property SegmentCount: Integer
      read FSegmentCount write SetSegmentCount default DefaultSegmentCount;
    property TotalLength: Single
      read FTotalLength write SetTotalLength {$ifdef FPC}default DefaultTotalLength{$endif};
    property TubeRadius: Single
      read FTubeRadius write SetTubeRadius {$ifdef FPC}default DefaultTubeRadius{$endif};
    property SolverIterations: Integer
      read FSolverIterations write SetSolverIterations default DefaultSolverIterations;
    property Damping: Single
      read FDamping write FDamping {$ifdef FPC}default DefaultDamping{$endif};
    property GravityY: Single
      read FGravityY write FGravityY {$ifdef FPC}default DefaultGravityY{$endif};
    property WindVelocityPersistent: TCastleVector3Persistent read FWindVelocityPersistent;
    property EndOffsetPersistent: TCastleVector3Persistent read FEndOffsetPersistent;
    property EndAnchorTransform: TCastleTransform
      read FEndAnchorTransform write SetEndAnchorTransform;
    property ColliderTransform: TCastleTransform
      read FColliderTransform write SetColliderTransform;
    property ColliderRadius: Single
      read FColliderRadius write SetColliderRadius {$ifdef FPC}default DefaultColliderRadius{$endif};
    property RopeColorPersistent: TCastleColorRGBPersistent read FRopeColorPersistent;
    property SimulateInEditor: Boolean
      read FSimulateInEditor write FSimulateInEditor default False;
  end;

implementation

uses
  Math,
  CastleComponentSerialize, CastleApplicationProperties, CastleUtils;

function GetClothHierarchyMatrix(const T: TCastleTransform): TMatrix4;
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

function ClothLocalToWorld(const T: TCastleTransform; const LocalPt: TVector3): TVector3;
begin
  Result := GetClothHierarchyMatrix(T).MultPoint(LocalPt);
end;

function ClothWorldToLocal(const T: TCastleTransform; const WorldPt: TVector3): TVector3;
var
  M, InvM: TMatrix4;
begin
  M := GetClothHierarchyMatrix(T);
  if M.TryInverse(InvM) then
    Result := InvM.MultPoint(WorldPt)
  else
    Result := WorldPt;
end;

function ClothWorldDirToLocal(const T: TCastleTransform; const WorldDir: TVector3): TVector3;
var
  M, InvM: TMatrix4;
begin
  M := GetClothHierarchyMatrix(T);
  if M.TryInverse(InvM) then
    Result := InvM.MultDirection(WorldDir)
  else
    Result := WorldDir;
end;

{ TCastleClothSurface -------------------------------------------------------- }

constructor TCastleClothSurface.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPreset := cpRoyalBanner;
  FPinMode := cpmTopEdge;
  FCols := DefaultCols;
  FRows := DefaultRows;
  FWidth := DefaultWidth;
  FHeight := DefaultHeight;
  FSolverIterations := DefaultSolverIterations;
  FStructuralStiffness := DefaultStructuralStiffness;
  FBendStiffness := DefaultBendStiffness;
  FDamping := DefaultDamping;
  FGravityY := DefaultGravityY;
  FWindVelocity := Vector3(0.0, 0.0, 3.5);
  FGustTurbulence := DefaultGustTurbulence;
  FSyncWithWeather := False;
  FColliderRadius := DefaultColliderRadius;
  FBaseColor := Vector3(0.76, 0.14, 0.18);
  FRoughness := DefaultRoughness;
  FSimulateInEditor := False;
  FSimTimeSec := 0.0;

  FWindVelocityPersistent := TCastleVector3Persistent.Create(nil);
  FWindVelocityPersistent.SetSubComponent(True);
  FWindVelocityPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetWindVelocityForPersistent;
  FWindVelocityPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetWindVelocityForPersistent;
  FWindVelocityPersistent.InternalDefaultValue := FWindVelocity;

  FBaseColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FBaseColorPersistent.SetSubComponent(True);
  FBaseColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetBaseColorForPersistent;
  FBaseColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetBaseColorForPersistent;
  FBaseColorPersistent.InternalDefaultValue := FBaseColor;

  ApplyPreset(cpRoyalBanner);
end;

destructor TCastleClothSurface.Destroy;
begin
  SetWeatherController(nil);
  SetColliderTransform(nil);
  if FRenderScene <> nil then
  begin
    Remove(FRenderScene);
    FreeAndNil(FRenderScene);
  end;
  FreeAndNil(FBaseColorPersistent);
  FreeAndNil(FWindVelocityPersistent);
  inherited;
end;

procedure TCastleClothSurface.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FWeatherController then
      FWeatherController := nil;
    if AComponent = FColliderTransform then
      FColliderTransform := nil;
  end;
end;

procedure TCastleClothSurface.Loaded;
begin
  inherited;
  SyncMaterialProperties;
  ResetClothGrid;
end;

function TCastleClothSurface.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Preset', 'PinMode', 'Cols', 'Rows', 'Width', 'Height',
       'SolverIterations', 'StructuralStiffness', 'BendStiffness',
       'Damping', 'GravityY', 'WindVelocityPersistent', 'GustTurbulence',
       'SyncWithWeather', 'WeatherController', 'ColliderTransform',
       'ColliderRadius', 'BaseColorPersistent', 'Roughness', 'SimulateInEditor'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleClothSurface.GetWindVelocityForPersistent: TVector3;
begin
  Result := FWindVelocity;
end;

procedure TCastleClothSurface.SetWindVelocityForPersistent(const AValue: TVector3);
begin
  FWindVelocity := AValue;
end;

function TCastleClothSurface.GetBaseColorForPersistent: TCastleColorRGB;
begin
  Result := FBaseColor;
end;

procedure TCastleClothSurface.SetBaseColorForPersistent(const AValue: TCastleColorRGB);
begin
  FBaseColor := AValue;
  SyncMaterialProperties;
end;

procedure TCastleClothSurface.SetPreset(const Value: TClothPreset);
begin
  if FPreset <> Value then
  begin
    if Value = cpCustom then
      FPreset := cpCustom
    else
      ApplyPreset(Value);
  end;
end;

procedure TCastleClothSurface.ApplyPreset(const APreset: TClothPreset);
begin
  FPreset := APreset;
  case APreset of
    cpRoyalBanner, cpCustom:
      begin
        FPinMode := cpmTopEdge;
        FCols := 11;
        FRows := 14;
        FWidth := 1.4;
        FHeight := 2.4;
        FWindVelocity := Vector3(0.4, 0.0, 3.2);
        FBaseColor := Vector3(0.76, 0.14, 0.18);
        FRoughness := 0.72;
      end;

    cpHeroShoulderCape:
      begin
        FPinMode := cpmTopEdge;
        FCols := 12;
        FRows := 14;
        FWidth := 1.2;
        FHeight := 1.65;
        FWindVelocity := Vector3(0.0, 0.1, 4.5);
        FBaseColor := Vector3(0.16, 0.24, 0.56);
        FRoughness := 0.68;
      end;

    cpWindFlagOnPole:
      begin
        FPinMode := cpmLeftPoleEdge;
        FCols := 14;
        FRows := 9;
        FWidth := 2.2;
        FHeight := 1.2;
        FWindVelocity := Vector3(8.5, 0.4, 1.8);
        FBaseColor := Vector3(0.88, 0.66, 0.14);
        FRoughness := 0.62;
      end;

    cpCanopyAwning:
      begin
        FPinMode := cpmFourCorners;
        FCols := 12;
        FRows := 12;
        FWidth := 3.2;
        FHeight := 3.2;
        FWindVelocity := Vector3(1.2, 0.5, 1.0);
        FBaseColor := Vector3(0.85, 0.80, 0.70);
        FRoughness := 0.80;
      end;
  end;
  if not (csLoading in ComponentState) then
  begin
    SyncMaterialProperties;
    ResetClothGrid;
  end;
end;

procedure TCastleClothSurface.SetPinMode(const Value: TClothPinMode);
begin
  if FPinMode <> Value then
  begin
    FPinMode := Value;
    if not (csLoading in ComponentState) then
      ResetClothGrid;
  end;
end;

procedure TCastleClothSurface.SetCols(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 3, 40);
  if FCols <> V then
  begin
    FCols := V;
    if not (csLoading in ComponentState) then
      ResetClothGrid;
  end;
end;

procedure TCastleClothSurface.SetRows(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 3, 40);
  if FRows <> V then
  begin
    FRows := V;
    if not (csLoading in ComponentState) then
      ResetClothGrid;
  end;
end;

procedure TCastleClothSurface.SetWidth(const Value: Single);
var
  V: Single;
begin
  V := Max(0.2, Value);
  if not SameValue(FWidth, V) then
  begin
    FWidth := V;
    if not (csLoading in ComponentState) then
      ResetClothGrid;
  end;
end;

procedure TCastleClothSurface.SetHeight(const Value: Single);
var
  V: Single;
begin
  V := Max(0.2, Value);
  if not SameValue(FHeight, V) then
  begin
    FHeight := V;
    if not (csLoading in ComponentState) then
      ResetClothGrid;
  end;
end;

procedure TCastleClothSurface.SetSolverIterations(const Value: Integer);
begin
  FSolverIterations := Clamped(Value, 1, 32);
end;

procedure TCastleClothSurface.SetWeatherController(const Value: TCastleTimeOfDayWeather);
begin
  if FWeatherController <> Value then
  begin
    if FWeatherController <> nil then
      FWeatherController.RemoveFreeNotification(Self);
    FWeatherController := Value;
    if FWeatherController <> nil then
      FWeatherController.FreeNotification(Self);
  end;
end;

procedure TCastleClothSurface.SetColliderTransform(const Value: TCastleTransform);
begin
  if FColliderTransform <> Value then
  begin
    if FColliderTransform <> nil then
      FColliderTransform.RemoveFreeNotification(Self);
    FColliderTransform := Value;
    if FColliderTransform <> nil then
      FColliderTransform.FreeNotification(Self);
  end;
end;

procedure TCastleClothSurface.SetColliderRadius(const Value: Single);
begin
  FColliderRadius := Clamped(Value, 0.05, 20.0);
end;

procedure TCastleClothSurface.SetRoughness(const Value: Single);
begin
  FRoughness := Clamped(Value, 0.05, 1.0);
  SyncMaterialProperties;
end;

procedure TCastleClothSurface.EnsureRenderScene;
var
  ShapeNode: TShapeNode;
begin
  if FRenderScene <> nil then
    Exit;

  FRenderScene := TCastleScene.Create(nil);
  FRenderScene.SetTransient;
  FRenderScene.Pickable := False;
  FRenderScene.Collides := False;

  FRootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;

  FAppearanceNode := TAppearanceNode.Create;
  FMaterialNode := TPhysicalMaterialNode.Create;
  FAppearanceNode.Material := FMaterialNode;
  ShapeNode.Appearance := FAppearanceNode;

  FTriSetNode := TTriangleSetNode.Create;
  FTriSetNode.Solid := False; // Double-sided cloth rendering!

  FCoordNode := TCoordinateNode.Create;
  FTriSetNode.Coord := FCoordNode;

  FNormalNode := TNormalNode.Create;
  FTriSetNode.Normal := FNormalNode;

  ShapeNode.Geometry := FTriSetNode;
  FRootNode.AddChildren(ShapeNode);

  SyncMaterialProperties;
  FRenderScene.Load(FRootNode, True);
  Add(FRenderScene);
end;

procedure TCastleClothSurface.SyncMaterialProperties;
begin
  if FMaterialNode = nil then
    Exit;
  FMaterialNode.BaseColor := FBaseColor;
  FMaterialNode.Roughness := FRoughness;
  FMaterialNode.Metallic := 0.04;
end;

procedure TCastleClothSurface.BuildConstraints;
var
  LinkCount: Integer;

  procedure AddLink(const C0, R0, C1, R1: Integer; const AStiff: Single);
  var
    IA, IB: Integer;
    Dist: Single;
  begin
    if (C1 < 0) or (C1 >= FCols) or (R1 < 0) or (R1 >= FRows) then
      Exit;
    IA := R0 * FCols + C0;
    IB := R1 * FCols + C1;
    Dist := PointsDistance(FPos[IA], FPos[IB]);
    if Dist <= 1.0e-5 then
      Exit;
    if LinkCount >= Length(FConstraints) then
      SetLength(FConstraints, Max(64, Length(FConstraints) * 2));
    FConstraints[LinkCount].IdxA := IA;
    FConstraints[LinkCount].IdxB := IB;
    FConstraints[LinkCount].RestLen := Dist;
    FConstraints[LinkCount].Stiffness := AStiff;
    Inc(LinkCount);
  end;

var
  R, C: Integer;
begin
  LinkCount := 0;
  SetLength(FConstraints, FCols * FRows * 6);
  for R := 0 to FRows - 1 do
    for C := 0 to FCols - 1 do
    begin
      { Structural horizontal & vertical }
      AddLink(C, R, C + 1, R, FStructuralStiffness);
      AddLink(C, R, C, R + 1, FStructuralStiffness);
      { Diagonal shear }
      AddLink(C, R, C + 1, R + 1, FStructuralStiffness * 0.85);
      AddLink(C, R, C - 1, R + 1, FStructuralStiffness * 0.85);
      { 2-hop bending }
      if FBendStiffness > 0.001 then
      begin
        AddLink(C, R, C + 2, R, FBendStiffness);
        AddLink(C, R, C, R + 2, FBendStiffness);
      end;
    end;
  SetLength(FConstraints, LinkCount);
end;

procedure TCastleClothSurface.ResetClothGrid;
var
  N, R, C, Idx: Integer;
  U, V: Single;
  P: TVector3;
  IsPin: Boolean;
begin
  FCols := Clamped(FCols, 3, 40);
  FRows := Clamped(FRows, 3, 40);
  N := FCols * FRows;
  SetLength(FPos, N);
  SetLength(FPrevPos, N);
  SetLength(FPinnedPos, N);
  SetLength(FPinned, N);
  FSimTimeSec := 0.0;

  for R := 0 to FRows - 1 do
  begin
    V := R / Max(1, FRows - 1);
    for C := 0 to FCols - 1 do
    begin
      U := C / Max(1, FCols - 1);
      Idx := R * FCols + C;

      case FPinMode of
        cpmLeftPoleEdge:
          P := Vector3(U * FWidth, -V * FHeight, 0.0);
        cpmFourCorners:
          P := Vector3((U - 0.5) * FWidth, 0.0, (V - 0.5) * FHeight);
        else
          P := Vector3((U - 0.5) * FWidth, -V * FHeight, 0.0);
      end;

      IsPin := False;
      case FPinMode of
        cpmTopEdge:
          IsPin := (R = 0);
        cpmTopTwoCorners:
          IsPin := (R = 0) and ((C = 0) or (C = FCols - 1));
        cpmLeftPoleEdge:
          IsPin := (C = 0);
        cpmFourCorners:
          IsPin := ((R = 0) or (R = FRows - 1)) and ((C = 0) or (C = FCols - 1));
      end;

      FPos[Idx] := P;
      FPrevPos[Idx] := P;
      FPinnedPos[Idx] := P;
      FPinned[Idx] := IsPin;
    end;
  end;

  BuildConstraints;
  RebuildClothMesh;
end;

function TCastleClothSurface.EffectiveWindWorld: TVector3;
begin
  if FSyncWithWeather and (FWeatherController <> nil) then
    Result := FWeatherController.CurrentAtmosphere.WindVelocityWorld
  else
    Result := FWindVelocity;
end;

procedure TCastleClothSurface.StepSubInterval(
  const SubDt: Single; const AWindWorld: TVector3);
var
  N, I, Iter, R, C, I00, I10, I01, IA, IB: Integer;
  Acc: array of TVector3;
  GravLocal, WindLocal, GustVec, FaceN, AeroForce, Vel, Delta, Corr: TVector3;
  SphereCenterLocal, ToPart: TVector3;
  HasSphere: Boolean;
  DtSqr, Dist, Diff, Stiff, WSum: Single;
begin
  N := Length(FPos);
  if N = 0 then
    Exit;

  SetLength(Acc, N);
  GravLocal := ClothWorldDirToLocal(Self, Vector3(0.0, FGravityY, 0.0));
  WindLocal := ClothWorldDirToLocal(Self, AWindWorld);

  for I := 0 to N - 1 do
    Acc[I] := GravLocal;

  { Aerodynamic pressure across cloth quads }
  if (WindLocal.LengthSqr > 1.0e-6) or (FGustTurbulence > 1.0e-4) then
  begin
    for R := 0 to FRows - 2 do
      for C := 0 to FCols - 2 do
      begin
        I00 := R * FCols + C;
        I10 := I00 + 1;
        I01 := I00 + FCols;
        FaceN := TVector3.CrossProduct(FPos[I10] - FPos[I00], FPos[I01] - FPos[I00]);
        if FaceN.LengthSqr > 1.0e-10 then
        begin
          FaceN := FaceN.Normalize;
          GustVec := WindLocal + Vector3(
            Sin(FSimTimeSec * 4.3 + R * 0.5) * FGustTurbulence,
            Cos(FSimTimeSec * 3.1 + C * 0.6) * FGustTurbulence * 0.4,
            Cos(FSimTimeSec * 5.2 + (R + C) * 0.35) * FGustTurbulence * 1.5);
          AeroForce := FaceN * (TVector3.DotProduct(GustVec, FaceN) * 2.2);
          Acc[I00] := Acc[I00] + AeroForce;
          Acc[I10] := Acc[I10] + AeroForce;
          Acc[I01] := Acc[I01] + AeroForce;
          Acc[I01 + 1] := Acc[I01 + 1] + AeroForce;
        end;
      end;
  end;

  { Verlet integration }
  DtSqr := SubDt * SubDt;
  for I := 0 to N - 1 do
  begin
    if FPinned[I] then
    begin
      FPos[I] := FPinnedPos[I];
      FPrevPos[I] := FPinnedPos[I];
    end else
    begin
      Vel := (FPos[I] - FPrevPos[I]) * Clamped(FDamping, 0.5, 0.9999);
      FPrevPos[I] := FPos[I];
      FPos[I] := FPos[I] + Vel + Acc[I] * DtSqr;
    end;
  end;

  HasSphere := (FColliderTransform <> nil) and (FColliderRadius > 0.01);
  if HasSphere then
    SphereCenterLocal := ClothWorldToLocal(
      Self, ClothLocalToWorld(FColliderTransform, TVector3.Zero))
  else
    SphereCenterLocal := TVector3.Zero;

  { Iterative Gauss-Seidel distance & sphere-repulsion solver }
  for Iter := 1 to FSolverIterations do
  begin
    for I := 0 to High(FConstraints) do
    begin
      IA := FConstraints[I].IdxA;
      IB := FConstraints[I].IdxB;
      if FPinned[IA] and FPinned[IB] then
        Continue;
      Delta := FPos[IB] - FPos[IA];
      Dist := Delta.Length;
      if Dist < 1.0e-6 then
        Continue;
      Stiff := Clamped(FConstraints[I].Stiffness, 0.01, 1.0);
      Diff := (Dist - FConstraints[I].RestLen) / Dist;
      Corr := Delta * (Diff * Stiff);

      if FPinned[IA] then
        FPos[IB] := FPos[IB] - Corr
      else if FPinned[IB] then
        FPos[IA] := FPos[IA] + Corr
      else
      begin
        WSum := 0.5;
        FPos[IA] := FPos[IA] + Corr * WSum;
        FPos[IB] := FPos[IB] - Corr * WSum;
      end;
    end;

    if HasSphere then
      for I := 0 to N - 1 do
      begin
        if FPinned[I] then
          Continue;
        ToPart := FPos[I] - SphereCenterLocal;
        Dist := ToPart.Length;
        if Dist < FColliderRadius then
        begin
          if Dist < 1.0e-5 then
            FPos[I] := SphereCenterLocal + Vector3(0.0, 0.0, FColliderRadius)
          else
            FPos[I] := SphereCenterLocal + ToPart * (FColliderRadius / Dist);
        end;
      end;
  end;
end;

procedure TCastleClothSurface.StepSimulation(const Dt: Single);
const
  MaxSubStep = 1.0 / 60.0;
var
  Rem, StepDt: Single;
  WindW: TVector3;
begin
  if Dt <= 0.0 then
    Exit;
  if Length(FPos) = 0 then
    ResetClothGrid;

  WindW := EffectiveWindWorld;
  Rem := Min(Dt, 2.0);
  while Rem > 1.0e-5 do
  begin
    StepDt := Min(Rem, MaxSubStep);
    FSimTimeSec := FSimTimeSec + StepDt;
    StepSubInterval(StepDt, WindW);
    Rem := Rem - StepDt;
  end;

  RebuildClothMesh;
end;

procedure TCastleClothSurface.RebuildClothMesh;
var
  N, QuadCount, R, C, OutIdx, I00, I10, I01, I11: Integer;
  GridNorm: array of TVector3;
  Verts, Norms: array of TVector3;
  FN1, FN2: TVector3;
begin
  EnsureRenderScene;
  N := Length(FPos);
  if (N = 0) or (FCols < 2) or (FRows < 2) then
    Exit;

  SetLength(GridNorm, N);
  for OutIdx := 0 to N - 1 do
    GridNorm[OutIdx] := TVector3.Zero;

  for R := 0 to FRows - 2 do
    for C := 0 to FCols - 2 do
    begin
      I00 := R * FCols + C;
      I10 := I00 + 1;
      I01 := I00 + FCols;
      I11 := I01 + 1;

      FN1 := TVector3.CrossProduct(FPos[I01] - FPos[I00], FPos[I10] - FPos[I00]);
      FN2 := TVector3.CrossProduct(FPos[I01] - FPos[I10], FPos[I11] - FPos[I10]);
      GridNorm[I00] := GridNorm[I00] + FN1;
      GridNorm[I01] := GridNorm[I01] + FN1 + FN2;
      GridNorm[I10] := GridNorm[I10] + FN1 + FN2;
      GridNorm[I11] := GridNorm[I11] + FN2;
    end;

  for OutIdx := 0 to N - 1 do
    if GridNorm[OutIdx].LengthSqr > 1.0e-10 then
      GridNorm[OutIdx] := GridNorm[OutIdx].Normalize
    else
      GridNorm[OutIdx] := Vector3(0.0, 0.0, 1.0);

  QuadCount := (FCols - 1) * (FRows - 1);
  FOutputTriangleCount := QuadCount * 2;
  SetLength(Verts, FOutputTriangleCount * 3);
  SetLength(Norms, FOutputTriangleCount * 3);
  OutIdx := 0;

  for R := 0 to FRows - 2 do
    for C := 0 to FCols - 2 do
    begin
      I00 := R * FCols + C;
      I10 := I00 + 1;
      I01 := I00 + FCols;
      I11 := I01 + 1;

      Verts[OutIdx] := FPos[I00]; Norms[OutIdx] := GridNorm[I00]; Inc(OutIdx);
      Verts[OutIdx] := FPos[I01]; Norms[OutIdx] := GridNorm[I01]; Inc(OutIdx);
      Verts[OutIdx] := FPos[I10]; Norms[OutIdx] := GridNorm[I10]; Inc(OutIdx);

      Verts[OutIdx] := FPos[I10]; Norms[OutIdx] := GridNorm[I10]; Inc(OutIdx);
      Verts[OutIdx] := FPos[I01]; Norms[OutIdx] := GridNorm[I01]; Inc(OutIdx);
      Verts[OutIdx] := FPos[I11]; Norms[OutIdx] := GridNorm[I11]; Inc(OutIdx);
    end;

  FCoordNode.SetPoint(Verts);
  FNormalNode.SetVector(Norms);
end;

procedure TCastleClothSurface.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepSimulation(SecondsPassed);
end;

function TCastleClothSurface.ParticleCount: Integer;
begin
  Result := Length(FPos);
end;

function TCastleClothSurface.IsParticlePinned(const ACol, ARow: Integer): Boolean;
var
  Idx: Integer;
begin
  Idx := ARow * FCols + ACol;
  if (ACol < 0) or (ACol >= FCols) or (ARow < 0) or (ARow >= FRows) or
     (Idx < 0) or (Idx >= Length(FPinned)) then
    Exit(False);
  Result := FPinned[Idx];
end;

function TCastleClothSurface.GetParticleLocalPos(const ACol, ARow: Integer): TVector3;
var
  Idx: Integer;
begin
  Idx := ARow * FCols + ACol;
  if (ACol < 0) or (ACol >= FCols) or (ARow < 0) or (ARow >= FRows) or
     (Idx < 0) or (Idx >= Length(FPos)) then
    Exit(TVector3.Zero);
  Result := FPos[Idx];
end;

function TCastleClothSurface.GetParticleWorldPos(const ACol, ARow: Integer): TVector3;
begin
  Result := ClothLocalToWorld(Self, GetParticleLocalPos(ACol, ARow));
end;

function TCastleClothSurface.MaxStretchRatio: Single;
var
  I: Integer;
  D, Ratio: Single;
begin
  Result := 1.0;
  for I := 0 to High(FConstraints) do
    if FConstraints[I].Stiffness >= 0.8 then
    begin
      D := PointsDistance(FPos[FConstraints[I].IdxA], FPos[FConstraints[I].IdxB]);
      Ratio := D / Max(1.0e-4, FConstraints[I].RestLen);
      if Ratio > Result then
        Result := Ratio;
    end;
end;

function TCastleClothSurface.ClothSummaryBadge: String;
var
  PresetName: String;
begin
  case FPreset of
    cpCustom:           PresetName := 'Custom';
    cpRoyalBanner:      PresetName := 'Banner';
    cpHeroShoulderCape: PresetName := 'Cape';
    cpWindFlagOnPole:   PresetName := 'Flag';
    cpCanopyAwning:     PresetName := 'Canopy';
  end;
  Result := Format('[Cloth:%s %dx%d %d tris]',
    [PresetName, FCols, FRows, FOutputTriangleCount]);
end;

{ TCastleVerletRope ---------------------------------------------------------- }

constructor TCastleVerletRope.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPinMode := rpmBothEndsCatenary;
  FSegmentCount := DefaultSegmentCount;
  FTotalLength := DefaultTotalLength;
  FTubeRadius := DefaultTubeRadius;
  FSolverIterations := DefaultSolverIterations;
  FDamping := DefaultDamping;
  FGravityY := DefaultGravityY;
  FWindVelocity := Vector3(0.0, 0.0, 1.2);
  FEndOffset := Vector3(4.0, 0.0, 0.0);
  FColliderRadius := DefaultColliderRadius;
  FRopeColor := Vector3(0.62, 0.48, 0.28);
  FSimulateInEditor := False;
  FSimTimeSec := 0.0;

  FWindVelocityPersistent := TCastleVector3Persistent.Create(nil);
  FWindVelocityPersistent.SetSubComponent(True);
  FWindVelocityPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetWindVelocityForPersistent;
  FWindVelocityPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetWindVelocityForPersistent;
  FWindVelocityPersistent.InternalDefaultValue := FWindVelocity;

  FEndOffsetPersistent := TCastleVector3Persistent.Create(nil);
  FEndOffsetPersistent.SetSubComponent(True);
  FEndOffsetPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetEndOffsetForPersistent;
  FEndOffsetPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetEndOffsetForPersistent;
  FEndOffsetPersistent.InternalDefaultValue := FEndOffset;

  FRopeColorPersistent := TCastleColorRGBPersistent.Create(nil);
  FRopeColorPersistent.SetSubComponent(True);
  FRopeColorPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetRopeColorForPersistent;
  FRopeColorPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetRopeColorForPersistent;
  FRopeColorPersistent.InternalDefaultValue := FRopeColor;

  ResetRope;
end;

destructor TCastleVerletRope.Destroy;
begin
  SetEndAnchorTransform(nil);
  SetColliderTransform(nil);
  if FRenderScene <> nil then
  begin
    Remove(FRenderScene);
    FreeAndNil(FRenderScene);
  end;
  FreeAndNil(FRopeColorPersistent);
  FreeAndNil(FEndOffsetPersistent);
  FreeAndNil(FWindVelocityPersistent);
  inherited;
end;

procedure TCastleVerletRope.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation = opRemove then
  begin
    if AComponent = FEndAnchorTransform then
      FEndAnchorTransform := nil;
    if AComponent = FColliderTransform then
      FColliderTransform := nil;
  end;
end;

procedure TCastleVerletRope.Loaded;
begin
  inherited;
  SyncMaterialProperties;
  ResetRope;
end;

function TCastleVerletRope.PropertySections(const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'PinMode', 'SegmentCount', 'TotalLength', 'TubeRadius',
       'SolverIterations', 'Damping', 'GravityY', 'WindVelocityPersistent',
       'EndOffsetPersistent', 'EndAnchorTransform', 'ColliderTransform',
       'ColliderRadius', 'RopeColorPersistent', 'SimulateInEditor'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleVerletRope.GetWindVelocityForPersistent: TVector3;
begin
  Result := FWindVelocity;
end;

procedure TCastleVerletRope.SetWindVelocityForPersistent(const AValue: TVector3);
begin
  FWindVelocity := AValue;
end;

function TCastleVerletRope.GetEndOffsetForPersistent: TVector3;
begin
  Result := FEndOffset;
end;

procedure TCastleVerletRope.SetEndOffsetForPersistent(const AValue: TVector3);
begin
  FEndOffset := AValue;
  if not (csLoading in ComponentState) then
    ResetRope;
end;

function TCastleVerletRope.GetRopeColorForPersistent: TCastleColorRGB;
begin
  Result := FRopeColor;
end;

procedure TCastleVerletRope.SetRopeColorForPersistent(const AValue: TCastleColorRGB);
begin
  FRopeColor := AValue;
  SyncMaterialProperties;
end;

procedure TCastleVerletRope.SetPinMode(const Value: TRopePinMode);
begin
  if FPinMode <> Value then
  begin
    FPinMode := Value;
    if not (csLoading in ComponentState) then
      ResetRope;
  end;
end;

procedure TCastleVerletRope.SetSegmentCount(const Value: Integer);
var
  V: Integer;
begin
  V := Clamped(Value, 2, 80);
  if FSegmentCount <> V then
  begin
    FSegmentCount := V;
    if not (csLoading in ComponentState) then
      ResetRope;
  end;
end;

procedure TCastleVerletRope.SetTotalLength(const Value: Single);
var
  V: Single;
begin
  V := Max(0.2, Value);
  if not SameValue(FTotalLength, V) then
  begin
    FTotalLength := V;
    if not (csLoading in ComponentState) then
      ResetRope;
  end;
end;

procedure TCastleVerletRope.SetTubeRadius(const Value: Single);
begin
  FTubeRadius := Clamped(Value, 0.005, 1.0);
  if not (csLoading in ComponentState) then
    RebuildRopeMesh;
end;

procedure TCastleVerletRope.SetSolverIterations(const Value: Integer);
begin
  FSolverIterations := Clamped(Value, 1, 48);
end;

procedure TCastleVerletRope.SetEndAnchorTransform(const Value: TCastleTransform);
begin
  if FEndAnchorTransform <> Value then
  begin
    if FEndAnchorTransform <> nil then
      FEndAnchorTransform.RemoveFreeNotification(Self);
    FEndAnchorTransform := Value;
    if FEndAnchorTransform <> nil then
      FEndAnchorTransform.FreeNotification(Self);
  end;
end;

procedure TCastleVerletRope.SetColliderTransform(const Value: TCastleTransform);
begin
  if FColliderTransform <> Value then
  begin
    if FColliderTransform <> nil then
      FColliderTransform.RemoveFreeNotification(Self);
    FColliderTransform := Value;
    if FColliderTransform <> nil then
      FColliderTransform.FreeNotification(Self);
  end;
end;

procedure TCastleVerletRope.SetColliderRadius(const Value: Single);
begin
  FColliderRadius := Clamped(Value, 0.05, 20.0);
end;

function TCastleVerletRope.ResolveEndAnchorLocal: TVector3;
begin
  if FEndAnchorTransform <> nil then
    Result := ClothWorldToLocal(Self, ClothLocalToWorld(FEndAnchorTransform, TVector3.Zero))
  else
    Result := FEndOffset;
end;

procedure TCastleVerletRope.EnsureRenderScene;
var
  ShapeNode: TShapeNode;
begin
  if FRenderScene <> nil then
    Exit;

  FRenderScene := TCastleScene.Create(nil);
  FRenderScene.SetTransient;
  FRenderScene.Pickable := False;
  FRenderScene.Collides := False;

  FRootNode := TX3DRootNode.Create;
  ShapeNode := TShapeNode.Create;

  FAppearanceNode := TAppearanceNode.Create;
  FMaterialNode := TPhysicalMaterialNode.Create;
  FAppearanceNode.Material := FMaterialNode;
  ShapeNode.Appearance := FAppearanceNode;

  FTriSetNode := TTriangleSetNode.Create;
  FTriSetNode.Solid := False;

  FCoordNode := TCoordinateNode.Create;
  FTriSetNode.Coord := FCoordNode;

  FNormalNode := TNormalNode.Create;
  FTriSetNode.Normal := FNormalNode;

  ShapeNode.Geometry := FTriSetNode;
  FRootNode.AddChildren(ShapeNode);

  SyncMaterialProperties;
  FRenderScene.Load(FRootNode, True);
  Add(FRenderScene);
end;

procedure TCastleVerletRope.SyncMaterialProperties;
begin
  if FMaterialNode = nil then
    Exit;
  FMaterialNode.BaseColor := FRopeColor;
  FMaterialNode.Roughness := 0.85;
  FMaterialNode.Metallic := 0.02;
end;

procedure TCastleVerletRope.ResetRope;
var
  N, I: Integer;
  EndPt: TVector3;
  T: Single;
begin
  FSegmentCount := Clamped(FSegmentCount, 2, 80);
  N := FSegmentCount + 1;
  SetLength(FNodes, N);
  SetLength(FPrevNodes, N);
  FSimTimeSec := 0.0;
  EndPt := ResolveEndAnchorLocal;

  for I := 0 to N - 1 do
  begin
    T := I / FSegmentCount;
    if FPinMode = rpmBothEndsCatenary then
      FNodes[I] := Lerp(T, TVector3.Zero, EndPt)
    else
      FNodes[I] := Vector3(0.0, -T * FTotalLength, 0.0);
    FPrevNodes[I] := FNodes[I];
  end;

  RebuildRopeMesh;
end;

procedure TCastleVerletRope.StepSubInterval(const SubDt: Single);
var
  N, I, Iter: Integer;
  EndPt, Acc, Vel, Delta, Corr, SphereCenterLocal, ToNode: TVector3;
  SegRestLen, DtSqr, Dist, Diff: Single;
  HasSphere: Boolean;
begin
  N := Length(FNodes);
  if N < 2 then
    Exit;

  EndPt := ResolveEndAnchorLocal;
  SegRestLen := Max(0.001, FTotalLength / FSegmentCount);
  Acc := ClothWorldDirToLocal(Self, Vector3(0.0, FGravityY, 0.0) + FWindVelocity * 0.9);
  DtSqr := SubDt * SubDt;

  for I := 0 to N - 1 do
  begin
    if (I = 0) or ((FPinMode = rpmBothEndsCatenary) and (I = N - 1)) then
      Continue;
    Vel := (FNodes[I] - FPrevNodes[I]) * Clamped(FDamping, 0.5, 0.9999);
    FPrevNodes[I] := FNodes[I];
    FNodes[I] := FNodes[I] + Vel + Acc * DtSqr;
  end;

  FNodes[0] := TVector3.Zero;
  FPrevNodes[0] := TVector3.Zero;
  if FPinMode = rpmBothEndsCatenary then
  begin
    FNodes[N - 1] := EndPt;
    FPrevNodes[N - 1] := EndPt;
  end;

  HasSphere := (FColliderTransform <> nil) and (FColliderRadius > 0.01);
  if HasSphere then
    SphereCenterLocal := ClothWorldToLocal(
      Self, ClothLocalToWorld(FColliderTransform, TVector3.Zero))
  else
    SphereCenterLocal := TVector3.Zero;

  for Iter := 1 to FSolverIterations do
  begin
    for I := 0 to N - 2 do
    begin
      Delta := FNodes[I + 1] - FNodes[I];
      Dist := Delta.Length;
      if Dist < 1.0e-6 then
        Continue;
      Diff := (Dist - SegRestLen) / Dist;
      Corr := Delta * Diff;

      if I = 0 then
        FNodes[I + 1] := FNodes[I + 1] - Corr
      else if (FPinMode = rpmBothEndsCatenary) and (I + 1 = N - 1) then
        FNodes[I] := FNodes[I] + Corr
      else
      begin
        FNodes[I] := FNodes[I] + Corr * 0.5;
        FNodes[I + 1] := FNodes[I + 1] - Corr * 0.5;
      end;
    end;

    if HasSphere then
      for I := 1 to N - 1 do
      begin
        if (FPinMode = rpmBothEndsCatenary) and (I = N - 1) then
          Continue;
        ToNode := FNodes[I] - SphereCenterLocal;
        Dist := ToNode.Length;
        if Dist < FColliderRadius then
        begin
          if Dist < 1.0e-5 then
            FNodes[I] := SphereCenterLocal + Vector3(0.0, FColliderRadius, 0.0)
          else
            FNodes[I] := SphereCenterLocal + ToNode * (FColliderRadius / Dist);
        end;
      end;
  end;
end;

procedure TCastleVerletRope.StepSimulation(const Dt: Single);
const
  MaxSubStep = 1.0 / 60.0;
var
  Rem, StepDt: Single;
begin
  if Dt <= 0.0 then
    Exit;
  if Length(FNodes) < 2 then
    ResetRope;

  Rem := Min(Dt, 2.0);
  while Rem > 1.0e-5 do
  begin
    StepDt := Min(Rem, MaxSubStep);
    FSimTimeSec := FSimTimeSec + StepDt;
    StepSubInterval(StepDt);
    Rem := Rem - StepDt;
  end;

  RebuildRopeMesh;
end;

procedure TCastleVerletRope.RebuildRopeMesh;
const
  Sides = 6;
var
  N, SegIdx, S, NextS, OutIdx: Integer;
  Verts, Norms: array of TVector3;
  P0, P1, Tang, SideA, SideB, N00, N01, V00, V01, V10, V11: TVector3;
  Ang0, Ang1: Single;
begin
  EnsureRenderScene;
  N := Length(FNodes);
  if N < 2 then
    Exit;

  FOutputTriangleCount := (N - 1) * Sides * 2;
  SetLength(Verts, FOutputTriangleCount * 3);
  SetLength(Norms, FOutputTriangleCount * 3);
  OutIdx := 0;

  for SegIdx := 0 to N - 2 do
  begin
    P0 := FNodes[SegIdx];
    P1 := FNodes[SegIdx + 1];
    Tang := P1 - P0;
    if Tang.LengthSqr < 1.0e-8 then
      Tang := Vector3(0.0, -1.0, 0.0)
    else
      Tang := Tang.Normalize;

    if Abs(Tang.Y) < 0.92 then
      SideA := TVector3.CrossProduct(Tang, Vector3(0.0, 1.0, 0.0)).Normalize
    else
      SideA := TVector3.CrossProduct(Tang, Vector3(1.0, 0.0, 0.0)).Normalize;
    SideB := TVector3.CrossProduct(SideA, Tang).Normalize;

    for S := 0 to Sides - 1 do
    begin
      NextS := (S + 1) mod Sides;
      Ang0 := (2.0 * Pi * S) / Sides;
      Ang1 := (2.0 * Pi * NextS) / Sides;

      N00 := (SideA * Cos(Ang0) + SideB * Sin(Ang0)).Normalize;
      N01 := (SideA * Cos(Ang1) + SideB * Sin(Ang1)).Normalize;

      V00 := P0 + N00 * FTubeRadius;
      V01 := P0 + N01 * FTubeRadius;
      V10 := P1 + N00 * FTubeRadius;
      V11 := P1 + N01 * FTubeRadius;

      Verts[OutIdx] := V00; Norms[OutIdx] := N00; Inc(OutIdx);
      Verts[OutIdx] := V10; Norms[OutIdx] := N00; Inc(OutIdx);
      Verts[OutIdx] := V01; Norms[OutIdx] := N01; Inc(OutIdx);

      Verts[OutIdx] := V01; Norms[OutIdx] := N01; Inc(OutIdx);
      Verts[OutIdx] := V10; Norms[OutIdx] := N00; Inc(OutIdx);
      Verts[OutIdx] := V11; Norms[OutIdx] := N01; Inc(OutIdx);
    end;
  end;

  FCoordNode.SetPoint(Verts);
  FNormalNode.SetVector(Norms);
end;

procedure TCastleVerletRope.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
begin
  inherited;
  if CastleDesignMode and (not FSimulateInEditor) then
    Exit;
  StepSimulation(SecondsPassed);
end;

function TCastleVerletRope.NodeCount: Integer;
begin
  Result := Length(FNodes);
end;

function TCastleVerletRope.GetNodeLocalPos(const AIndex: Integer): TVector3;
begin
  if (AIndex < 0) or (AIndex >= Length(FNodes)) then
    Exit(TVector3.Zero);
  Result := FNodes[AIndex];
end;

function TCastleVerletRope.GetNodeWorldPos(const AIndex: Integer): TVector3;
begin
  Result := ClothLocalToWorld(Self, GetNodeLocalPos(AIndex));
end;

function TCastleVerletRope.LowestSagLocalY: Single;
var
  I: Integer;
begin
  if Length(FNodes) = 0 then
    Exit(0.0);
  Result := FNodes[0].Y;
  for I := 1 to High(FNodes) do
    if FNodes[I].Y < Result then
      Result := FNodes[I].Y;
end;

function TCastleVerletRope.MaxStretchRatio: Single;
var
  I: Integer;
  SegRest, D, Ratio: Single;
begin
  Result := 1.0;
  if Length(FNodes) < 2 then
    Exit;
  SegRest := Max(1.0e-4, FTotalLength / FSegmentCount);
  for I := 0 to High(FNodes) - 1 do
  begin
    D := PointsDistance(FNodes[I], FNodes[I + 1]);
    Ratio := D / SegRest;
    if Ratio > Result then
      Result := Ratio;
  end;
end;

function TCastleVerletRope.RopeSummaryBadge: String;
var
  ModeStr: String;
begin
  if FPinMode = rpmBothEndsCatenary then
    ModeStr := 'Catenary'
  else
    ModeStr := 'Pendulum';
  Result := Format('[Rope:%s %d segs %.1fm]', [ModeStr, FSegmentCount, FTotalLength]);
end;

initialization
  RegisterSerializableComponent(TCastleClothSurface, ['Verlet Cloth / Banner / Cape']);
  RegisterSerializableComponent(TCastleVerletRope, ['Verlet Catenary / Pendulum Rope']);
end.
