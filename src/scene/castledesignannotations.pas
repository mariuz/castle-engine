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

{ Spatial 3D & 2D viewport design review annotations ("Canvas Pins") and
  camera viewpoint bookmarks (Phase 283 — UE 5.9 Spatial Review Parity). }
unit CastleDesignAnnotations;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleBoxes, CastleClassUtils,
  CastleTransform, CastleCameras, CastleUIControls;

type
  { Review pin semantic category. }
  TDesignAnnotationCategory = (
    { General design note, lore/layout context, or art commentary. }
    dacNote,
    { Actionable task or set-dressing / polish follow-up. }
    dacTodo,
    { Visual, collision, lighting, or gameplay defect to resolve before ship. }
    dacBug,
    { Spatial instruction prompt anchored in 3D/2D space for an AI/MCP agent. }
    dacAiPrompt
  );

  { Review pin lifecycle workflow state. }
  TDesignAnnotationStatus = (
    dasOpen,
    dasInProgress,
    dasResolved
  );

  { 3D spatial design review pin ("Canvas Pin") with optional saved camera
    viewpoint bookmark.
    Renders a pickable callout marker in @code(CastleDesignMode) and has zero
    visual, raycast, or bounding-box footprint at game runtime. }
  TCastleDesignAnnotation = class(TCastleTransform)
  private
    FCategory: TDesignAnnotationCategory;
    FStatus: TDesignAnnotationStatus;
    FTitle: String;
    FAuthor: String;
    FComment: String;
    FPriority: Integer;
    FShowPinInViewport: Boolean;
    FHasCameraBookmark: Boolean;
    FCameraPosition: TVector3;
    FCameraDirection: TVector3;
    FCameraUp: TVector3;
    FCameraPositionPersistent: TCastleVector3Persistent;
    FCameraDirectionPersistent: TCastleVector3Persistent;
    FCameraUpPersistent: TCastleVector3Persistent;
    procedure SetPriority(const AValue: Integer);
    function GetCameraPositionForPersistent: TVector3;
    procedure SetCameraPositionForPersistent(const AValue: TVector3);
    function GetCameraDirectionForPersistent: TVector3;
    procedure SetCameraDirectionForPersistent(const AValue: TVector3);
    function GetCameraUpForPersistent: TVector3;
    procedure SetCameraUpForPersistent(const AValue: TVector3);
  public
    const
      DefaultPriority = 3;
      DesignPickHalfSize = 0.35;

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    function LocalBoundingBox: TBox3D; override;
    procedure LocalRender(const Params: TRenderParams); override;

    { Store an explicit world-space camera pose on this annotation pin. }
    procedure SetCameraBookmark(const APos, ADir, AUp: TVector3);
    { Capture the current world-space pose from @code(ACamera). }
    function CaptureCameraFrom(const ACamera: TCastleTransform): Boolean;
    { Restore the saved camera pose onto @code(ACamera) when @link(HasCameraBookmark) is true. }
    function ApplyCameraTo(const ACamera: TCastleTransform): Boolean;
    { Clear any saved camera bookmark. }
    procedure ClearCameraBookmark;

    { True when this pin is an unresolved (@code(dasOpen) or @code(dasInProgress))
      @code(dacBug) or @code(dacTodo) item that should be flagged in pre-release audits. }
    function IsUnresolvedActionable: Boolean;
    { Compact single-line badge label (e.g. @code('[BUG] Floating rock') or @code('[OK] Lighting check')). }
    function PinSummaryBadge: String;
    { RGBA accent color matching @link(Category) and @link(Status). }
    function PinColor: TCastleColor;

    property CameraPosition: TVector3 read FCameraPosition write FCameraPosition;
    property CameraDirection: TVector3 read FCameraDirection write FCameraDirection;
    property CameraUp: TVector3 read FCameraUp write FCameraUp;
  published
    property Category: TDesignAnnotationCategory read FCategory write FCategory default dacNote;
    property Status: TDesignAnnotationStatus read FStatus write FStatus default dasOpen;
    property Title: String read FTitle write FTitle;
    property Author: String read FAuthor write FAuthor;
    property Comment: String read FComment write FComment;
    property Priority: Integer read FPriority write SetPriority default DefaultPriority;
    property ShowPinInViewport: Boolean read FShowPinInViewport write FShowPinInViewport default true;
    property HasCameraBookmark: Boolean read FHasCameraBookmark write FHasCameraBookmark default false;
    property CameraPositionPersistent: TCastleVector3Persistent read FCameraPositionPersistent;
    property CameraDirectionPersistent: TCastleVector3Persistent read FCameraDirectionPersistent;
    property CameraUpPersistent: TCastleVector3Persistent read FCameraUpPersistent;
  end;

  { 2D UI spatial design review pin ("Canvas Pin") for @code(.castle-user-interface) layouts.
    Renders a crisp callout pill in @code(CastleDesignMode) and does nothing at game runtime. }
  TCastleDesignAnnotationUi = class(TCastleUserInterface)
  private
    FCategory: TDesignAnnotationCategory;
    FStatus: TDesignAnnotationStatus;
    FTitle: String;
    FAuthor: String;
    FComment: String;
    FPriority: Integer;
    FShowPinInViewport: Boolean;
    procedure SetPriority(const AValue: Integer);
  public
    const
      DefaultPriority = 3;
      DefaultPinWidth = 168.0;
      DefaultPinHeight = 30.0;

    constructor Create(AOwner: TComponent); override;
    function PropertySections(const PropertyName: String): TPropertySections; override;
    procedure Render; override;

    function IsUnresolvedActionable: Boolean;
    function PinSummaryBadge: String;
    function PinColor: TCastleColor;
  published
    property Category: TDesignAnnotationCategory read FCategory write FCategory default dacNote;
    property Status: TDesignAnnotationStatus read FStatus write FStatus default dasOpen;
    property Title: String read FTitle write FTitle;
    property Author: String read FAuthor write FAuthor;
    property Comment: String read FComment write FComment;
    property Priority: Integer read FPriority write SetPriority default DefaultPriority;
    property ShowPinInViewport: Boolean read FShowPinInViewport write FShowPinInViewport default true;
    property Width default DefaultPinWidth;
    property Height default DefaultPinHeight;
  end;

{ Human-readable tag and color helpers for annotation categories & statuses. }
function DesignAnnotationCategoryTag(const ACategory: TDesignAnnotationCategory): String;
function DesignAnnotationCategoryDisplayName(const ACategory: TDesignAnnotationCategory): String;
function DesignAnnotationStatusDisplayName(const AStatus: TDesignAnnotationStatus): String;
function DesignAnnotationPinColor(const ACategory: TDesignAnnotationCategory;
  const AStatus: TDesignAnnotationStatus): TCastleColor;

implementation

uses
  Math, CastleUtils, CastleStringUtils, CastleRectangles,
  CastleGLUtils, CastleControls, CastleComponentSerialize;

function DesignAnnotationCategoryTag(const ACategory: TDesignAnnotationCategory): String;
begin
  case ACategory of
    dacNote:     Result := 'NOTE';
    dacTodo:     Result := 'TODO';
    dacBug:      Result := 'BUG';
    dacAiPrompt: Result := 'AI';
  end;
end;

function DesignAnnotationCategoryDisplayName(const ACategory: TDesignAnnotationCategory): String;
begin
  case ACategory of
    dacNote:     Result := 'Note';
    dacTodo:     Result := 'TODO';
    dacBug:      Result := 'Bug';
    dacAiPrompt: Result := 'AI Prompt';
  end;
end;

function DesignAnnotationStatusDisplayName(const AStatus: TDesignAnnotationStatus): String;
begin
  case AStatus of
    dasOpen:       Result := 'Open';
    dasInProgress: Result := 'In Progress';
    dasResolved:   Result := 'Resolved';
  end;
end;

function DesignAnnotationPinColor(const ACategory: TDesignAnnotationCategory;
  const AStatus: TDesignAnnotationStatus): TCastleColor;
begin
  if AStatus = dasResolved then
    Exit(Vector4(0.35, 0.85, 0.52, 0.88));
  case ACategory of
    dacNote:     Result := Vector4(0.30, 0.80, 1.00, 0.95);
    dacTodo:     Result := Vector4(1.00, 0.78, 0.22, 0.95);
    dacBug:      Result := Vector4(1.00, 0.30, 0.32, 0.98);
    dacAiPrompt: Result := Vector4(0.80, 0.45, 1.00, 0.95);
  end;
end;

function BuildPinSummaryBadge(const ACategory: TDesignAnnotationCategory;
  const AStatus: TDesignAnnotationStatus; const ATitle, AName: String): String;
var
  CleanTitle: String;
begin
  CleanTitle := Trim(ATitle);
  if CleanTitle = '' then
    CleanTitle := AName;
  if CleanTitle = '' then
    CleanTitle := 'Pin';
  if AStatus = dasResolved then
    Result := Format('[DONE:%s] %s', [DesignAnnotationCategoryTag(ACategory), CleanTitle])
  else if AStatus = dasInProgress then
    Result := Format('[WIP:%s] %s', [DesignAnnotationCategoryTag(ACategory), CleanTitle])
  else
    Result := Format('[%s] %s', [DesignAnnotationCategoryTag(ACategory), CleanTitle]);
end;

{ TCastleDesignAnnotation ---------------------------------------------------- }

constructor TCastleDesignAnnotation.Create(AOwner: TComponent);
begin
  inherited;
  FCategory := dacNote;
  FStatus := dasOpen;
  FTitle := 'Review Pin';
  FAuthor := '';
  FComment := '';
  FPriority := DefaultPriority;
  FShowPinInViewport := true;
  FHasCameraBookmark := false;
  FCameraPosition := Vector3(0, 2, 5);
  FCameraDirection := Vector3(0, 0, -1);
  FCameraUp := Vector3(0, 1, 0);

  FCameraPositionPersistent := TCastleVector3Persistent.Create(nil);
  FCameraPositionPersistent.SetSubComponent(true);
  FCameraPositionPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetCameraPositionForPersistent;
  FCameraPositionPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetCameraPositionForPersistent;
  FCameraPositionPersistent.InternalDefaultValue := FCameraPosition;

  FCameraDirectionPersistent := TCastleVector3Persistent.Create(nil);
  FCameraDirectionPersistent.SetSubComponent(true);
  FCameraDirectionPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetCameraDirectionForPersistent;
  FCameraDirectionPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetCameraDirectionForPersistent;
  FCameraDirectionPersistent.InternalDefaultValue := FCameraDirection;

  FCameraUpPersistent := TCastleVector3Persistent.Create(nil);
  FCameraUpPersistent.SetSubComponent(true);
  FCameraUpPersistent.InternalGetValue := {$ifdef FPC}@{$endif}GetCameraUpForPersistent;
  FCameraUpPersistent.InternalSetValue := {$ifdef FPC}@{$endif}SetCameraUpForPersistent;
  FCameraUpPersistent.InternalDefaultValue := FCameraUp;
end;

destructor TCastleDesignAnnotation.Destroy;
begin
  FreeAndNil(FCameraPositionPersistent);
  FreeAndNil(FCameraDirectionPersistent);
  FreeAndNil(FCameraUpPersistent);
  inherited;
end;

procedure TCastleDesignAnnotation.SetPriority(const AValue: Integer);
begin
  FPriority := Clamped(AValue, 1, 5);
end;

function TCastleDesignAnnotation.GetCameraPositionForPersistent: TVector3;
begin
  Result := FCameraPosition;
end;

procedure TCastleDesignAnnotation.SetCameraPositionForPersistent(const AValue: TVector3);
begin
  FCameraPosition := AValue;
end;

function TCastleDesignAnnotation.GetCameraDirectionForPersistent: TVector3;
begin
  Result := FCameraDirection;
end;

procedure TCastleDesignAnnotation.SetCameraDirectionForPersistent(const AValue: TVector3);
begin
  FCameraDirection := AValue;
end;

function TCastleDesignAnnotation.GetCameraUpForPersistent: TVector3;
begin
  Result := FCameraUp;
end;

procedure TCastleDesignAnnotation.SetCameraUpForPersistent(const AValue: TVector3);
begin
  FCameraUp := AValue;
end;

function TCastleDesignAnnotation.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Category', 'Status', 'Title', 'Author', 'Comment', 'Priority',
       'ShowPinInViewport', 'HasCameraBookmark',
       'CameraPositionPersistent', 'CameraDirectionPersistent', 'CameraUpPersistent'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

function TCastleDesignAnnotation.LocalBoundingBox: TBox3D;
begin
  if CastleDesignMode and FShowPinInViewport then
    Result := Box3D(
      Vector3(-DesignPickHalfSize, -DesignPickHalfSize, -DesignPickHalfSize),
      Vector3( DesignPickHalfSize,  DesignPickHalfSize,  DesignPickHalfSize))
  else
    Result := TBox3D.Empty;
end;

procedure TCastleDesignAnnotation.LocalRender(const Params: TRenderParams);
begin
  { Intentionally renders no 3D mesh geometry at runtime; in CastleDesignMode
    the editor viewport overlay renders crisp 2D screen-space callout badges,
    while child transforms (if any) still render only in design mode. }
  if not CastleDesignMode then
    Exit;
  inherited;
end;

procedure TCastleDesignAnnotation.SetCameraBookmark(const APos, ADir, AUp: TVector3);
begin
  FCameraPosition := APos;
  if ADir.IsZero then
    FCameraDirection := Vector3(0, 0, -1)
  else
    FCameraDirection := ADir.Normalize;
  if AUp.IsZero then
    FCameraUp := Vector3(0, 1, 0)
  else
    FCameraUp := AUp.Normalize;
  FHasCameraBookmark := true;
end;

function TCastleDesignAnnotation.CaptureCameraFrom(const ACamera: TCastleTransform): Boolean;
var
  P, D, U: TVector3;
begin
  Result := ACamera <> nil;
  if not Result then
    Exit;
  ACamera.GetWorldView(P, D, U);
  SetCameraBookmark(P, D, U);
end;

function TCastleDesignAnnotation.ApplyCameraTo(const ACamera: TCastleTransform): Boolean;
var
  SafeDir, SafeUp: TVector3;
begin
  Result := FHasCameraBookmark and (ACamera <> nil);
  if not Result then
    Exit;
  if FCameraDirection.IsZero then
    SafeDir := Vector3(0, 0, -1)
  else
    SafeDir := FCameraDirection.Normalize;
  if FCameraUp.IsZero then
    SafeUp := Vector3(0, 1, 0)
  else
    SafeUp := FCameraUp.Normalize;
  ACamera.SetWorldView(FCameraPosition, SafeDir, SafeUp);
end;

procedure TCastleDesignAnnotation.ClearCameraBookmark;
begin
  FHasCameraBookmark := false;
end;

function TCastleDesignAnnotation.IsUnresolvedActionable: Boolean;
begin
  Result := (FStatus <> dasResolved) and (FCategory in [dacBug, dacTodo]);
end;

function TCastleDesignAnnotation.PinSummaryBadge: String;
begin
  Result := BuildPinSummaryBadge(FCategory, FStatus, FTitle, Name);
  if FHasCameraBookmark then
    Result := Result + ' [Cam]';
end;

function TCastleDesignAnnotation.PinColor: TCastleColor;
begin
  Result := DesignAnnotationPinColor(FCategory, FStatus);
end;

{ TCastleDesignAnnotationUi -------------------------------------------------- }

constructor TCastleDesignAnnotationUi.Create(AOwner: TComponent);
begin
  inherited;
  FCategory := dacNote;
  FStatus := dasOpen;
  FTitle := 'UI Review Pin';
  FAuthor := '';
  FComment := '';
  FPriority := DefaultPriority;
  FShowPinInViewport := true;
  Width := DefaultPinWidth;
  Height := DefaultPinHeight;
end;

procedure TCastleDesignAnnotationUi.SetPriority(const AValue: Integer);
begin
  FPriority := Clamped(AValue, 1, 5);
end;

function TCastleDesignAnnotationUi.PropertySections(
  const PropertyName: String): TPropertySections;
begin
  if ArrayContainsString(PropertyName, [
       'Category', 'Status', 'Title', 'Author', 'Comment', 'Priority',
       'ShowPinInViewport'
     ]) then
    Result := [psBasic]
  else
    Result := inherited PropertySections(PropertyName);
end;

procedure TCastleDesignAnnotationUi.Render;
var
  RR: TFloatRectangle;
  Col: TCastleColor;
begin
  if not CastleDesignMode then
    Exit;
  inherited;
  if not FShowPinInViewport then
    Exit;

  RR := RenderRect;
  if RR.IsEmpty then
    Exit;

  Col := PinColor;
  DrawRectangle(RR, Vector4(0.06, 0.08, 0.13, 0.88));
  DrawRectangle(FloatRectangle(RR.Left, RR.Bottom, Min(6.0, RR.Width), RR.Height), Col);
  DrawRectangleOutline(RR, Col);
  if UIFont <> nil then
    UIFont.PrintRect(RR.Grow(-8, -4), Col, PinSummaryBadge, hpLeft, vpMiddle);
end;

function TCastleDesignAnnotationUi.IsUnresolvedActionable: Boolean;
begin
  Result := (FStatus <> dasResolved) and (FCategory in [dacBug, dacTodo]);
end;

function TCastleDesignAnnotationUi.PinSummaryBadge: String;
begin
  Result := BuildPinSummaryBadge(FCategory, FStatus, FTitle, Name);
end;

function TCastleDesignAnnotationUi.PinColor: TCastleColor;
begin
  Result := DesignAnnotationPinColor(FCategory, FStatus);
end;

initialization
  RegisterSerializableComponent(TCastleDesignAnnotation,
    ['Transform', 'Design Annotation Pin (3D Review)']);
  RegisterSerializableComponent(TCastleDesignAnnotationUi,
    ['Controls', 'Design Annotation Pin (2D UI Review)']);
end.
