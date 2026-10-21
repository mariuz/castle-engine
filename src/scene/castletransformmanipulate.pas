{
  Copyright 2020-2025 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Select, manipulate (move, rotate, scale) and visualize hovering over
  TCastleTransform instances.
  Use this unit to implement 3D editing operations in your application. }
unit CastleTransformManipulate;

{$I castleconf.inc}

interface

uses Classes, SysUtils, Contnrs, Generics.Collections,
  CastleColors, CastleVectors, CastleVectorsInternalSingle, CastleTransform,
  CastleDebugTransform, CastleScene, CastleCameras, CastleTriangles, CastleUtils,
  CastleClassUtils;

type
  { Visualize the TCastleTransform we hover over
    (to visualize what would be selected by clicking). }
  TCastleTransformHover = class(TComponent)
  strict private
    FCurrent: TCastleTransform;
    FCurrentObserver: TFreeNotificationObserver;
    // This entire class is mostly a wrapper around this TDebugTransformBox
    Box: TDebugTransformBox;
    procedure CurrentFreeNotification(const Sender: TFreeNotificationObserver);
    procedure SetCurrent(const AValue: TCastleTransform);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Current TCastleTransform instance that "we are hovering over it,
      and clicking will select it". }
    property Current: TCastleTransform read FCurrent write SetCurrent;
  end;

  { Mode of operation for @link(TCastleTransformManipulate.Mode). }
  TManipulateMode = (mmSelect, mmTranslate, mmRotate, mmScale);

  { Coordinate space used by @link(TCastleTransformManipulate) when translating
    or rotating selected transformations. }
  TManipulateCoordSpace = (
    { Translate and rotate along the transformation's local axes. }
    csLocal,
    { Translate and rotate along the world (parent) axes, ignoring the
      selected transformation's own rotation. }
    csWorld
  );

  { Pivot mode used by @link(TCastleTransformManipulate) when rotating
    multiple selected transformations. }
  TManipulatePivotMode = (
    { Each selected transformation rotates around its own local origin
      (with the gizmo placed at the primary selected transformation). }
    pmPrimarySelected,
    { Selected transformations orbit and rotate around the combined center
      (@link(SelectionWorkingCenter)) of all selected transformations. }
    pmSelectionCenter
  );

  { Alignment reference target for @link(TCastleTransformManipulate.AlignSelected). }
  TAlignTarget = (
    { Align all selected transforms to the primary (first) selected transform's coordinate. }
    atPrimary,
    { Align all selected transforms to the minimum coordinate among the selection. }
    atMin,
    { Align all selected transforms to the midpoint between minimum and maximum coordinates. }
    atCenter,
    { Align all selected transforms to the maximum coordinate among the selection. }
    atMax
  );

  { Allow to select, move, rotate, scale a group of TCastleTransform instances.

    This component implements common 3D editing operations:

    @unorderedList(
      @item(Selection (when @link(Mode) = mmSelect).
        To use this, call @link(SetSelected) with any number of transforms.
        Multiple transform instances can be selected at once.

        This component does never itself change the selected objects.
        It relies on external code to call @link(SetSelected) whenever
        the selection changes.

        This component merely visualizes the selected objects.
      )

      @item(Move, rotate or scale selected transformations.
        To use this, call @link(SetSelected) with one or more transforms.
        And set @link(Mode) to the desired operation, like @link(mmTranslate).

        This component fully implements moving, rotating and scaling,
        including configurable snapping (@link(TranslateSnap), @link(RotateSnap),
        @link(ScaleSnap)), coordinate space selection (@link(CoordSpace)),
        pivot mode selection (@link(PivotMode)), multi-selection manipulation,
        alignment (@link(AlignSelected)), even distribution (@link(DistributeSelected)),
        absolute grid snapping (@link(SnapSelectedToGrid)), and downward surface
        snapping (@link(SnapToFloor)).
        It displays a proper "gizmo" to perform this for user,
        and it modifies the selected transformations when user drags the gizmo.
        Use events like @link(OnTransformModified) and @link(OnTransformModifyEnd)
        to get notified when the transformation is modified.
      )
    )
  }
  TCastleTransformManipulate = class(TComponent)
  strict private
    type
      TGizmoScene = class(TCastleScene)
      strict private
        {.$define DEBUG_GIZMO_PICK}
        {$ifdef DEBUG_GIZMO_PICK}
        VisualizePick: TCastleScene;
        {$endif DEBUG_GIZMO_PICK}
        GizmoDragging: Boolean;
        DraggingCoord: Integer;
        LastPick: TVector3;
        LastPickAngle: Single;
        GizmoScalingAssumeScale: Boolean;
        GizmoScalingAssumeScaleValue: TVector3;
        InsideUpdateSize: Boolean;
        LastIsProjectionOrthographic: Boolean;

        function ManipulateOwner: TCastleTransformManipulate;
        function UseWorldCoordSpace: Boolean;
        procedure GetEffectiveRay(const Pick: TRayCollisionNode;
          out RayOrigin, RayDirection: TVector3);

        { Point on axis closest to given pick.
          Axis may be -1 to indicate we drag on all axes with the same amount
          or -2 to indicate we drag X and Y axes for 2D. }
        function PointOnAxis(out Intersection: TVector3;
          const Pick: TRayCollisionNode; const Axis: Integer): Boolean;

        { Angle in radians on a plane lying at given Coord
          (e.g. plane "Z = 0" when Coord = 2).
          The angle is measured using ArcTan2 on the given plane.
          Angle is in radians, from -Pi to Pi.

          It is not defined here where's the Angle = 0 exactly, as users
          of this routine in practice always want to subtract 2 values of such
          angle, so it doesn't matter "where is Angle = 0". }
        function AngleOnPlane(out Angle: Single;
          const Pick: TRayCollisionNode; const Coord: T3DAxis): Boolean;

        procedure DoTransformModifyBegin;
        procedure DoTransformModified;
        procedure DoTransformModifyEnd;
      protected
        procedure ChangeWorld(const Value: TCastleAbstractRootTransform); override;
        function LocalRayCollision(const RayOrigin, RayDirection: TVector3;
          const TrianglesToIgnoreFunc: TTriangleIgnoreFunc): TRayCollision; override;
      public
        Mode: TManipulateMode;
        OnTransformModifyBegin: TNotifyEvent;
        OnTransformModified: TNotifyEvent;
        OnTransformModifyEnd: TNotifyEvent;
        constructor Create(AOwner: TComponent); override;
        procedure UpdateSize;
        procedure InternalCameraChanged; override;
        function PointingDevicePress(const Pick: TRayCollisionNode;
          const Distance: Single): Boolean; override;
        function PointingDeviceMove(const Pick: TRayCollisionNode;
          const Distance: Single): Boolean; override;
        function PointingDeviceRelease(const Pick: TRayCollisionNode;
          const Distance: Single; const CancelAction: Boolean): Boolean; override;
        procedure LocalRender(const Params: TRenderParams); override;
      end;

    var
      FMode: TManipulateMode;
      FCoordSpace: TManipulateCoordSpace;
      FPivotMode: TManipulatePivotMode;
      FTranslateSnap: Single;
      FRotateSnap: Single;
      FScaleSnap: Single;
      FMainSelected: TCastleTransform;
      FMainSelectedObserver: TFreeNotificationObserver;
      FPickable: Boolean;
      Boxes: TDebugTransformBoxList;
      Gizmo: array [TManipulateMode] of TGizmoScene;
      FOnTransformModifyBegin: TNotifyEvent;
      FOnTransformModified: TNotifyEvent;
      FOnTransformModifyEnd: TNotifyEvent;
      { Boxes from 0 to FMaxSelectedCount-1 *may* contain a selected
        TCastleTransform, if Boxes[I].Parent <> nil.
        The other Boxes always have Parent = nil. }
      FMaxSelectedCount: Cardinal;

    procedure SetMode(const AValue: TManipulateMode);
    procedure SetCoordSpace(const AValue: TManipulateCoordSpace);
    procedure SetPivotMode(const AValue: TManipulatePivotMode);
    procedure SetMainSelected(const AValue: TCastleTransform);
    procedure UpdateMainSelected;
    procedure SetPickable(const Value: Boolean);
    procedure GizmoHasTransformModifyBegin(Sender: TObject);
    procedure GizmoHasTransformModified(Sender: TObject);
    procedure GizmoHasTransformModifyEnd(Sender: TObject);
    procedure MainSelectedFreeNotification(const Sender: TFreeNotificationObserver);
    procedure CreateMoreBoxes;
    function GetSelected(Index: Integer): TCastleTransform;
    function IsDescendantOfAnySelected(const T: TCastleTransform): Boolean;
    function GetTransformWorkingPos(const T: TCastleTransform): TVector3;
    procedure SetTransformWorkingPos(const T: TCastleTransform; const NewWorkingPos: TVector3);
    procedure ApplyTranslateDelta(const DeltaInMainParent: TVector3);
    procedure ApplyRotateDelta(const AxisCoord: Integer; const DiffAngle: Single);
    procedure ApplyScaleMultiplier(const ScaleMultiplier: TVector3);

    { Primary TCastleTransform where the interactive gizmo is attached
      (depending on @link(Mode)).
      @nil when nothing is selected. }
    property MainSelected: TCastleTransform read FMainSelected write SetMainSelected;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Called right when the user begins dragging an interactive gizmo handle
      (to move/rotate/scale). Useful e.g. for Alt-drag in-place duplication. }
    property OnTransformModifyBegin: TNotifyEvent
      read FOnTransformModifyBegin write FOnTransformModifyBegin;

    { Called whenever we modify the transformation of selected transformations
      by moving/rotating/scaling.
      Useful e.g. to mark the design as "modified". }
    property OnTransformModified: TNotifyEvent
      read FOnTransformModified write FOnTransformModified;

    { Called when we stop dragging (to move/rotate/scale).
      Useful e.g. to mark new state as "next undo step". }
    property OnTransformModifyEnd: TNotifyEvent
      read FOnTransformModifyEnd write FOnTransformModifyEnd;

    { Modify this property temporarily to influnce ray collisions.
      If your code uses ray collisions (non-physical) using
      e.g. @code(MyViewport.Items.WorldRay) and you don't want to ever
      pick the internal "gizmo" scenes for manipulating, then set this
      temporarily to @false. }
    property Pickable: Boolean read FPickable write SetPickable default true;

    { Current mode of operation. }
    property Mode: TManipulateMode read FMode write SetMode
      default mmSelect;

    { Coordinate space for translation and rotation operations
      (@link(csLocal) or @link(csWorld)). }
    property CoordSpace: TManipulateCoordSpace
      read FCoordSpace write SetCoordSpace default csLocal;

    { Pivot point used when rotating multiple selected transformations
      (@link(pmPrimarySelected) or @link(pmSelectionCenter)). }
    property PivotMode: TManipulatePivotMode
      read FPivotMode write SetPivotMode default pmPrimarySelected;

    { Grid snap step for 3D translation operations.
      When > 0, translation movements are snapped to multiples of this value.
      Set to 0 (default) to disable translation snapping. }
    property TranslateSnap: Single
      read FTranslateSnap write FTranslateSnap {$ifdef FPC}default 0{$endif};

    { Angle snap step (in radians) for 3D rotation operations.
      When > 0, rotation angle increments are snapped to multiples of this value.
      Set to 0 (default) to disable rotation snapping. }
    property RotateSnap: Single
      read FRotateSnap write FRotateSnap {$ifdef FPC}default 0{$endif};

    { Scale increment snap step for 3D scaling operations.
      When > 0, scale changes are snapped to multiples of this value.
      Set to 0 (default) to disable scale snapping. }
    property ScaleSnap: Single
      read FScaleSnap write FScaleSnap {$ifdef FPC}default 0{$endif};

    { Pass a list of TCastleTransform instances to visualize them as selected
      and to manipulate them (move/rotate/scale).
      One or multiple transform instances can be selected and manipulated at once.

      The argument NewSelected may be @nil, which is treated just like passing an
      empty list.

      Instances of classes other than TCastleTransform on the NewSelected list
      are allowed, and they are just ignored.

      The list NewSelected does not become owned by this class.
      You can free it whenever you want, even immediately after calling this method,
      we don't keep any reference to it -- we copy the contents. }
    procedure SetSelected(const NewSelected: TComponentList); overload;
    procedure SetSelected(const NewSelected: array of TComponent); overload;

    { Currently selected items, use indexes from 0 to SelectedCount - 1.
      This is equivalent to the contents of last SetSelected call,
      but filtered to contain only TCastleTransform instances that
      can be manipulated, but with freed TCastleTransform instances
      removed. }
    property Selected[Index: Integer]: TCastleTransform read GetSelected;

    { Count of currently selected items.
      @seealso Selected }
    function SelectedCount: Integer;

    { Arithmetic center of all top-level selected transformations in working
      (world or root) coordinates. Returns @link(TVector3.Zero) when nothing is selected. }
    function SelectionWorkingCenter: TVector3;

    { Translate all currently selected transforms by RawDelta along the active
      @link(CoordSpace), applying @link(TranslateSnap) if > 0 and skipping
      selected transforms whose ancestor is also selected. }
    procedure TranslateSelected(const RawDelta: TVector3);

    { Rotate all currently selected transforms around Axis by RawAngleRad
      (in radians) in the active @link(CoordSpace) and @link(PivotMode),
      applying @link(RotateSnap) if > 0 and skipping selected transforms
      whose ancestor is also selected. }
    procedure RotateSelected(const Axis: T3DAxis; const RawAngleRad: Single);

    { Scale all currently selected transforms by adding RawScaleDelta to their
      scale, applying @link(ScaleSnap) if > 0 and skipping selected transforms
      whose ancestor is also selected. }
    procedure ScaleSelected(const RawScaleDelta: TVector3);

    { Align all top-level selected transforms along @code(Axis) (0=X, 1=Y, 2=Z)
      to the target coordinate specified by @code(Target) (@link(atPrimary),
      @link(atMin), @link(atCenter), or @link(atMax)).
      Requires at least 2 top-level selected transforms. }
    procedure AlignSelected(const Axis: T3DAxis; const Target: TAlignTarget = atPrimary);

    { Distribute all top-level selected transforms at equal intervals along
      @code(Axis) (0=X, 1=Y, 2=Z) between the minimum and maximum coordinates
      of the selection. Requires at least 3 top-level selected transforms. }
    procedure DistributeSelected(const Axis: T3DAxis);

    { Stack all top-level selected transforms flush edge-to-edge along
      @code(Axis) (0=X, 1=Y, 2=Z) using their @code(WorldBoundingBox) extents
      (plus optional @code(Spacing)), keeping the minimum-coordinate transform
      anchored at its current position. Requires at least 2 top-level selected transforms.
      Returns @true if at least one selected transform was modified. }
    function StackSelected(const Axis: T3DAxis; const Spacing: Single = 0): Boolean;

    { Snap the absolute @code(Translation) of all top-level selected transforms
      to the nearest multiple of @link(TranslateSnap) on all 3 axes.
      Returns @true if at least one selected transform was modified. }
    function SnapSelectedToGrid: Boolean;

    { Snap all currently selected transforms downward along the world gravity
      vector (@code(-World.GravityUp)) onto the nearest surface below each
      transform's bounding box bottom (or origin when its bounding box is empty).
      When @code(AlignToNormal) is @true, also rotates each transform's local
      +Y up axis to match the hit surface's world normal.
      Returns @true if at least one selected transform was modified. }
    function SnapToFloor(const AlignToNormal: Boolean = false): Boolean;

    { Mirror all top-level selected transforms across the plane perpendicular to
      @code(Axis) (0=X, 1=Y, 2=Z). When multiple transforms are selected (or
      @link(PivotMode) = @link(pmSelectionCenter)), positions are reflected across
      the active pivot coordinate; when a single transform is selected with
      @link(pmPrimarySelected), its position is reflected across 0 along @code(Axis).
      Orientation is reflected across the mirror plane while keeping @code(Scale)
      positive (physics-safe).
      Returns @true if at least one selected transform was modified. }
    function MirrorSelected(const Axis: T3DAxis): Boolean;

    { Rotate all currently selected transforms by an exact 90-degree step
      (@code(+Pi/2) when @code(Clockwise = false), @code(-Pi/2) when @code(Clockwise = true))
      around @code(Axis) in the active @link(CoordSpace) and @link(PivotMode),
      temporarily bypassing @link(RotateSnap).
      Returns @true if at least one selected transform was modified. }
    function RotateSelected90(const Axis: T3DAxis; const Clockwise: Boolean = true): Boolean;

    { Apply random variation to all top-level selected transforms for level
      set-dressing:
      - Random Yaw rotation in @code([-MaxYawRad, +MaxYawRad]) radians around +Y.
      - Uniform random scale multiplier in @code([ScaleMin, ScaleMax]).
      - Horizontal (X, Z) translation jitter in @code([-MaxPositionJitter, +MaxPositionJitter]).
      Returns @true if at least one selected transform was modified. }
    function RandomizeSelected(const MaxYawRad: Single;
      const ScaleMin, ScaleMax: Single;
      const MaxPositionJitter: Single = 0): Boolean;

    { Cast a world-space ray (@code(RayOrigin), @code(RayDirection)) against the
      scene (ignoring currently selected transforms and gizmos) and snap all
      top-level selected transforms to the hit location, preserving relative
      offsets between multiple selected transforms around the active pivot.
      - When @code(SnapToNearestVertex) is @false, snaps to the exact surface
        intersection point.
      - When @code(SnapToNearestVertex) is @true, snaps to the closest vertex
        of the hit mesh triangle in world space (falling back to the surface
        hit point if the hit object has no triangle geometry).
      - When @code(AlignToNormal) is @true, also aligns each selected transform's
        local +Y up axis to the hit surface normal.
      Returns @true if a surface was hit and at least one transform was modified. }
    function SnapSelectedToRay(const RayOrigin, RayDirection: TVector3;
      const SnapToNearestVertex: Boolean = false;
      const AlignToNormal: Boolean = false): Boolean;

    { Measure the world-space vector (@code(WorldDelta = Pos1 - Pos0)) and
      Euclidean distance between the first two selected transforms
      (@code(Selected[0]) and @code(Selected[1])).
      Returns @code(0) (and sets @code(WorldDelta := TVector3.Zero)) when fewer
      than 2 transforms are selected. }
    function MeasureSelectedDistance(out WorldDelta: TVector3): Single;

    { Cast a world-space ray (@code(RayOrigin), @code(RayDirection)) against the
      scene (ignoring gizmos and currently selected transforms) and measure the
      world-space distance and delta vector (@code(WorldDelta = HitWorldPoint - PivotWorldPos))
      from the active selection pivot to the hit surface point (@code(HitWorldPoint)).
      Returns @code(-1) when no surface is hit or nothing is selected. }
    function MeasureRayDistanceFromSelected(const RayOrigin, RayDirection: TVector3;
      out HitWorldPoint, WorldDelta: TVector3): Single;

    { Project each top-level selected transform individually from its current
      world bounding-box center (or origin) along @code(WorldDirection) onto the
      first unselected scene surface hit, placing each transform's leading
      bounding-box face flush against the hit surface.
      When @code(AlignToNormal) is @true, also rotates each transform's local +Y
      up axis to match the hit surface's world normal.
      Returns @true if at least one selected transform was modified. }
    function ProjectSelectedAlongDirection(const WorldDirection: TVector3;
      const AlignToNormal: Boolean = false): Boolean;

    { Distribute all top-level selected transforms along @code(Axis) (0=X, 1=Y, 2=Z)
      so that the world-space bounding-box gaps between consecutive transforms
      between the first and last transform are equal.
      Requires at least 3 top-level selected transforms.
      Returns @true if at least one selected transform was modified. }
    function DistributeSelectedGaps(const Axis: T3DAxis): Boolean;

    { Snap the absolute rotation angle (@code(Rotation.W)) of all top-level
      selected transforms to the nearest multiple of @link(RotateSnap) (when > 0)
      and the absolute @code(Scale) components to the nearest positive multiple of
      @link(ScaleSnap) (when > 0).
      Returns @true if at least one selected transform was modified. }
    function SnapSelectedRotationAndScaleToGrid: Boolean;

    { Swap the working (world or root) positions of two top-level selected
      transforms (or reverse the sequence of positions when 3 or more transforms
      are selected). Requires at least 2 top-level selected transforms.
      Returns @true if at least one selected transform was modified. }
    function SwapSelectedPositions: Boolean;

    { Scale all secondary top-level selected transforms (@code(Selected[1..N-1]))
      so that their bounding-box dimensions match the primary selected transform
      (@code(Selected[0])).
      - When @code(Axis) is @code(0), @code(1), or @code(2), matches only the X, Y,
        or Z dimension respectively.
      - When @code(Axis) is @code(-1) (default), matches all 3 dimensions (X, Y, Z).
      Requires at least 2 top-level selected transforms with non-empty bounding boxes.
      Returns @true if at least one selected transform was modified. }
    function MatchSelectedSize(const Axis: Integer = -1): Boolean;

    { Rotate all top-level selected transforms so their world forward direction
      (@code(Direction)) points directly toward @code(TargetWorldPos), keeping their
      up vector aligned with @code(World.GravityUp) (or +Y).
      Returns @true if at least one selected transform was modified. }
    function LookAtWorldPoint(const TargetWorldPos: TVector3): Boolean;

    { Rotate all secondary top-level selected transforms (@code(Selected[1..N-1]))
      so their world forward direction (@code(Direction)) aims directly at the
      primary selected transform (@code(Selected[0])).
      Requires at least 2 top-level selected transforms.
      Returns @true if at least one selected transform was modified. }
    function AimSelectedAtPrimary: Boolean;

    { Align the world-space bounding-box minimum faces (@code(UseMaxFace = false))
      or maximum faces (@code(UseMaxFace = true)) of all top-level selected
      transforms along @code(Axis) (0=X, 1=Y, 2=Z) to the outer minimum or maximum
      bounding-box face of the selection.
      Requires at least 2 top-level selected transforms with non-empty bounding boxes.
      Returns @true if at least one selected transform was modified. }
    function AlignSelectedBounds(const Axis: T3DAxis;
      const UseMaxFace: Boolean = false): Boolean;

    { Copy the world-space orientation (@code(Direction) and @code(Up)) of the
      primary selected transform (@code(Selected[0])) to all secondary top-level
      selected transforms (@code(Selected[1..N-1])), preserving each transform's
      existing world position and scale.
      Requires at least 2 top-level selected transforms.
      Returns @true if at least one selected transform was modified. }
    function MatchSelectedRotation: Boolean;

    { Copy the world-space position (@code(MatchPos)), world-space orientation
      (@code(MatchRot)), and/or scale (@code(MatchScale)) of the primary selected
      transform (@code(Selected[0])) to all secondary top-level selected transforms
      (@code(Selected[1..N-1])).
      Requires at least 2 top-level selected transforms.
      Returns @true if at least one selected transform was modified. }
    function MatchSelectedTransform(const MatchPos, MatchRot, MatchScale: Boolean): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) around
      a horizontal (XZ) circle or arc of radius @code(Radius) centered at the active
      selection pivot (@link(SelectionWorkingCenter) when @link(PivotMode) is
      @link(pmSelectionCenter), or @code(Selected[0]) when @link(pmPrimarySelected)).
      - When @code(Radius <= 0), automatically uses the average horizontal distance
        of the selected transforms from the center (or @code(5.0) if all coincide).
      - When @code(OrientToCenter) is @true, rotates each transform so its world
        forward direction (@code(-Z)) faces the circle center.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInCircle(const Radius: Single;
      const TotalAngleDeg: Single = 360.0;
      const OrientToCenter: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) into
      a 2D (XZ) or 3D (XYZ) grid without duplicating them.
      - When @code(ColumnsX <= 0), automatically uses @code(Ceil(Sqrt(Count))).
      - When @code(RowsZ <= 0), automatically uses @code(Ceil(Count / ColumnsX)).
      - When any component of @code(Spacing) is @code(<= 0), automatically computes
        that axis spacing as @code(1.25 * MaxBoundingBoxExtent) across the selection
        (or @code(2.0) when bounding boxes are empty).
      - When @code(CenterGrid) is @true, centers the grid around @link(SelectionWorkingCenter);
        otherwise starts the grid at @code(Selected[0])'s world origin.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInGrid(const ColumnsX, RowsZ: Integer;
      const Spacing: TVector3; const CenterGrid: Boolean = true): Boolean;

    { Push or pull the world-space positions of all top-level selected transforms
      (@code(SelectedCount >= 2)) away from or toward the active selection pivot
      (@link(SelectionWorkingCenter) when @link(PivotMode) is @link(pmSelectionCenter),
      or @code(Selected[0]) when @link(pmPrimarySelected)) by @code(Factor), without
      modifying any transform's @code(Scale) or @code(Rotation).
      Returns @true if at least one selected transform was modified. }
    function ScaleSelectedPositionsFromPivot(const Factor: TVector3): Boolean;

    { Reset local @code(Translation) to @code((0, 0, 0)), @code(Rotation) to
      @code((0, 1, 0, 0)), and/or @code(Scale) to @code((1, 1, 1)) on all selected
      transforms.
      Returns @true if at least one selected transform was modified. }
    function ResetSelectedTransform(
      const ResetTrans, ResetRot, ResetScale: Boolean): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      straight 3D line segment between @code(StartWorldPos) and @code(EndWorldPos)
      at evenly spaced intervals ($t = i / (N - 1)$).
      When @code(OrientAlongLine) is @true, rotates each transform so its world
      forward direction faces along the line segment direction.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedAlongLine(const StartWorldPos, EndWorldPos: TVector3;
      const OrientAlongLine: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      straight 3D line segment between the first selected transform
      (@code(Selected[0])) and the last selected transform (@code(Selected[N-1]))
      at evenly spaced intervals.
      When @code(OrientAlongLine) is @true, rotates each transform so its world
      forward direction faces from @code(Selected[0]) toward @code(Selected[N-1]).
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedBetweenEndpoints(
      const OrientAlongLine: Boolean = false): Boolean;

    { Iteratively separate overlapping top-level selected transforms
      (@code(SelectedCount >= 2)) by pushing apart any pair whose world-space
      axis-aligned bounding boxes intersect (including @code(MinPadding) clearance)
      along their minimum penetration axis.
      When @code(HorizontalOnly) is @true (default), resolves overlaps only on the
      horizontal XZ plane so objects remain at their current Y elevation.
      Returns @true if at least one selected transform was moved. }
    function SeparateOverlappingSelected(const MinPadding: Single = 0.0;
      const HorizontalOnly: Boolean = true;
      const MaxIterations: Integer = 16): Boolean;

    { Apply a linear gradient of @code(Scale) from @code(StartScale) (on the first
      top-level selected transform) to @code(EndScale) (on the last top-level
      selected transform), and/or a cumulative rotation step of @code(StepAngleRad)
      around @code(Axis) (@code(I * StepAngleRad) for item @code(I)).
      Requires at least 2 top-level selected transforms.
      Returns @true if at least one selected transform was modified. }
    function ApplyProgressiveTransformSelected(
      const StartScale, EndScale: TVector3; const ApplyScaleGradient: Boolean;
      const Axis: T3DAxis = 1; const StepAngleRad: Single = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      multi-point 3D polyline defined by @code(Waypoints) (@code(Length(Waypoints) >= 2))
      at equal arc-length intervals along the path.
      When @code(OrientAlongPath) is @true, rotates each transform so its world
      forward direction faces along the local segment tangent.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedAlongWaypoints(const Waypoints: array of TVector3;
      const OrientAlongPath: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      3D cylindrical or conical helix/spiral around the active selection pivot
      (@link(SelectionWorkingCenter) when @link(PivotMode) is @link(pmSelectionCenter),
      or @code(Selected[0]) when @link(pmPrimarySelected)).
      - @code(StartRadius) and @code(EndRadius) define the horizontal XZ radius at the
        first and last item (if @code(StartRadius <= 0), auto-detects the average XZ
        distance from the center; if @code(EndRadius < 0), uses @code(StartRadius)).
      - @code(HeightSpan) defines the total vertical Y change from the first item to
        the last item.
      - @code(Turns) defines the number of full 360-degree revolutions (default @code(1.0)).
      - When @code(OrientToCenter) is @true, rotates each transform horizontally so its
        world forward direction faces toward the central helix axis.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInHelix(const StartRadius, EndRadius, HeightSpan: Single;
      const Turns: Single = 1.0; const OrientToCenter: Boolean = false): Boolean;

    { Shift the origin (@code(Translation)) of each selected parent transform that has
      at least one direct @link(TCastleTransform) child to the combined world-space
      bounding box center of its direct children (or bottom-center when
      @code(UseBottomCenter) is @true), while inversely offsetting all direct
      children so their world-space positions remain completely unchanged.
      Returns @true if at least one parent transform was modified. }
    function CenterSelectedOriginOnChildren(
      const UseBottomCenter: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      smooth 3D quadratic Bezier curve or parabolic arch between @code(StartWorldPos)
      and @code(EndWorldPos) with middle control point @code(ControlWorldPos):
      $$B(t) = (1 - t)^2 P_0 + 2(1 - t)t P_1 + t^2 P_2, \quad t = i / (N - 1)$$
      When @code(OrientAlongCurve) is @true, rotates each transform so its world
      forward direction faces along the instantaneous curve tangent
      $B'(t) = 2(1 - t)(P_1 - P_0) + 2t(P_2 - P_1)$.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInBezierArch(
      const StartWorldPos, ControlWorldPos, EndWorldPos: TVector3;
      const OrientAlongCurve: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      smooth 3D parabolic arch between the first selected transform (@code(Selected[0]))
      and the last selected transform (@code(Selected[N-1])) whose apex at $t = 0.5$
      rises by @code(ApexHeightOffset) along the world Y axis above the midpoint.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInParabolicArchBetweenEndpoints(
      const ApexHeightOffset: Single;
      const OrientAlongCurve: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) over a
      3D sphere or dome of @code(Radius) around the active selection pivot
      (@link(SelectionWorkingCenter) when @link(PivotMode) is @link(pmSelectionCenter),
      or @code(Selected[0]) when @link(pmPrimarySelected)) using a Fibonacci golden-angle
      spiral lattice so points are nearly equidistant across the spherical cap.
      - When @code(Radius <= 0), auto-detects the average 3D distance from the pivot.
      - @code(MinElevationDeg) ($-90^\circ$ for a full sphere, $0^\circ$ for an upper
        hemisphere/dome) and @code(MaxElevationDeg) ($+90^\circ$ for the top pole)
        define the latitude band.
      - When @code(OrientOutward) is @true, rotates each transform so its world
        forward direction points radially outward from the sphere center.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnSphere(const Radius: Single;
      const MinElevationDeg: Single = 0.0; const MaxElevationDeg: Single = 90.0;
      const OrientOutward: Boolean = false): Boolean;

    { Scale all top-level selected transforms (@code(SelectedCount >= 1)) as a cohesive
      3D group around the active selection pivot (@link(SelectionWorkingCenter) when
      @link(PivotMode) is @link(pmSelectionCenter), or @code(Selected[0]) when
      @link(pmPrimarySelected)) by @code(Factor):
      - Multiplies each transform's world-space offset from the pivot by @code(Factor)
        (when @code(Count >= 2)).
      - Multiplies each transform's local @code(Scale) by @code(Factor) (when
        @code(ScaleSizes) is @true).
      Returns @true if at least one selected transform was modified. }
    function ScaleSelectedGroupAroundPivot(const Factor: TVector3;
      const ScaleSizes: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      3D sinusoidal wave between @code(StartWorldPos) and @code(EndWorldPos):
      $$P(t) = (1 - t) P_0 + t P_1 + A \sin(2\pi \cdot C \cdot t), \quad t = i / (N - 1)$$
      When @code(OrientAlongWave) is @true, rotates each transform so its world
      forward direction faces along the instantaneous wave tangent $P'(t)$.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInSineWave(const StartWorldPos, EndWorldPos: TVector3;
      const Amplitude: Single; const Cycles: Single = 1.0;
      const WaveAxis: T3DAxis = 1;
      const OrientAlongWave: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      3D sinusoidal wave between the first selected transform (@code(Selected[0]))
      and the last selected transform (@code(Selected[N-1])).
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInSineWaveBetweenEndpoints(
      const Amplitude: Single; const Cycles: Single = 1.0;
      const WaveAxis: T3DAxis = 1;
      const OrientAlongWave: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) evenly
      around a horizontal XZ ellipse centered at the active selection pivot
      (@link(SelectionWorkingCenter) when @link(PivotMode) is @link(pmSelectionCenter),
      or @code(Selected[0]) when @link(pmPrimarySelected)) with semi-axes @code(RadiusX)
      and @code(RadiusZ) (auto-detected from average XZ distance when @code(<= 0)).
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the ellipse center
      - @code(2): orient horizontally along the ellipse tangent direction
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInEllipse(const RadiusX, RadiusZ: Single;
      const OrientMode: Integer = 0): Boolean;

    { Reverse the order of world-space positions (and optionally rotations and scales)
      across all top-level selected transforms (@code(SelectedCount >= 2)), swapping
      item @code(0) with @code(N - 1), item @code(1) with @code(N - 2), etc.
      Returns @true if at least one selected transform was modified. }
    function ReverseSelectedPositions(const ReverseRotations: Boolean = false;
      const ReverseScales: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) across a
      horizontal XZ disk of @code(OuterRadius) around the active selection pivot
      (@link(SelectionWorkingCenter) when @link(PivotMode) is @link(pmSelectionCenter),
      or @code(Selected[0]) when @link(pmPrimarySelected)) using Vogel's golden-angle
      phyllotaxis spiral ($r_i = R \sqrt(i / (N - 1)), \; \theta_i = i \cdot \phi$)
      for uniform areal density without concentric ring artifacts.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the disk center
      - @code(2): orient horizontally outward away from the disk center
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInPhyllotaxisDisk(const OuterRadius: Single;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) as a
      3D staircase / stepped ramp between @code(StartWorldPos) and @code(EndWorldPos):
      - Horizontal XZ coordinates interpolate linearly ($t = i / (N - 1)$).
      - Vertical Y elevation follows $y(t) = y_0 + (y_1 - y_0) \cdot t^E$ where
        @code(CurveExponent) $E > 0$ (@code(1.0) = uniform steps, @code(< 1.0) = steep
        initial rise, @code(> 1.0) = gentle initial rise / grand concave stairs).
      - When @code(OrientHorizontallyAlongRun) is @true, rotates each step horizontally
        (yaw only, keeping steps level with @code(GravityUp)) to face along the XZ run.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInStaircase(const StartWorldPos, EndWorldPos: TVector3;
      const CurveExponent: Single = 1.0;
      const OrientHorizontallyAlongRun: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) as a
      3D staircase / stepped ramp between the first selected transform (@code(Selected[0]))
      and the last selected transform (@code(Selected[N-1])).
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInStaircaseBetweenEndpoints(
      const CurveExponent: Single = 1.0;
      const OrientHorizontallyAlongRun: Boolean = false): Boolean;

    { Scale only the horizontal XZ radial distance of all top-level selected transforms
      (@code(SelectedCount >= 2)) from the active selection pivot
      (@link(SelectionWorkingCenter) when @link(PivotMode) is @link(pmSelectionCenter),
      or @code(Selected[0]) when @link(pmPrimarySelected)) by @code(RadialFactor),
      preserving each transform's exact Y elevation and local @code(Scale).
      Returns @true if at least one selected transform was modified. }
    function ScaleSelectedRadialDistanceXZ(const RadialFactor: Single): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) around a
      3D torus or helical torus coil centered at the active selection pivot
      (@link(SelectionWorkingCenter) when @link(PivotMode) is @link(pmSelectionCenter),
      or @code(Selected[0]) when @link(pmPrimarySelected)) with major ring radius
      @code(MajorRadius), minor tube radius @code(MinorRadius), and @code(MinorTurns)
      revolutions around the tube cross-section per full major ring revolution:
      $$x(\theta, \phi) = (R + r \cos\phi) \cos\theta, \quad y(\theta, \phi) = r \sin\phi, \quad z(\theta, \phi) = (R + r \cos\phi) \sin\theta$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient outward along the torus tube surface normal
      - @code(2): orient forward along the helical torus tangent vector
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnTorus(const MajorRadius, MinorRadius: Single;
      const MinorTurns: Single = 1.0; const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) in an
      alternating 3D zigzag / staggered corridor pattern between @code(StartWorldPos)
      and @code(EndWorldPos), offsetting each item $i$ perpendicular to the line
      in the horizontal plane by $(-1)^i \cdot \text(LateralOffset)$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the main corridor line direction
      - @code(2): orient inward toward the central corridor line
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInZigzag(const StartWorldPos, EndWorldPos: TVector3;
      const LateralOffset: Single; const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) in an
      alternating 3D zigzag / staggered corridor pattern between the first selected
      transform (@code(Selected[0])) and the last selected transform (@code(Selected[N-1])).
      When @code(LateralOffset <= 0), auto-computes a lateral offset from the average
      bounding-box extent (or @code(2.0) when bounding boxes are empty).
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInZigzagBetweenEndpoints(
      const LateralOffset: Single = 0.0; const OrientMode: Integer = 0): Boolean;

    { Equalize / normalize the world-space bounding-box dimensions of all top-level
      selected transforms (@code(SelectedCount >= 2)) that have non-empty bounding
      boxes to their shared arithmetic mean:
      - When @code(PreserveAspectRatio) is @true (default), uniformly scales each
        selected transform's @code(Scale) so its world bounding-box diagonal length
        equals the average diagonal length across the selection.
      - When @code(PreserveAspectRatio) is @false, scales each transform's X, Y, and Z
        @code(Scale) components independently so every selected transform's world
        bounding-box size matches the average $(S_X, S_Y, S_Z)$ across the selection.
      Returns @true if at least one selected transform was modified. }
    function NormalizeSelectedSizes(
      const PreserveAspectRatio: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      3D Lissajous / figure-8 / lemniscate curve around the current selection pivot
      in the XZ horizontal plane with optional Y-axis harmonic wave oscillation:
      $x(\theta) = C_x + R_x \sin(\omega_x \theta)$,
      $y(\theta) = C_y + H_y \cos(\omega_x \theta)$,
      $z(\theta) = C_z + R_z \sin(\omega_z \theta)$
      for $\theta_i = \frac(2\pi i)(N)$.
      With default @code(FreqX = 1.0) and @code(FreqZ = 2.0), this forms a classic
      figure-8 / Gerono lemniscate loop; other frequency ratios produce general
      3D Lissajous knots and harmonic orbits.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the curve center
      - @code(2): orient forward along the 3D Lissajous curve tangent
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInLissajous(
      const RadiusX, RadiusZ: Single;
      const FreqX: Single = 1.0; const FreqZ: Single = 2.0;
      const VerticalAmplitude: Single = 0.0;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      3D catenary / hanging cable / suspension chain curve between @code(StartWorldPos)
      and @code(EndWorldPos), sagging along the world $-Y$ axis by @code(SagDepth) at
      the midpoint using a normalized hyperbolic cosine profile:
      $S(u) = \frac(\cosh(k) - \cosh(k u))(\cosh(k) - 1)$ for $u = 2t - 1 \in [-1, 1]$
      and $k = 1.5$, so the endpoints match @code(StartWorldPos) and @code(EndWorldPos)
      exactly while the midpoint ($t = 0.5, u = 0$) drops by @code(SagDepth).
      When @code(OrientAlongCurve) is @true, each transform is oriented along the
      instantaneous 3D catenary tangent vector.
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInCatenary(
      const StartWorldPos, EndWorldPos: TVector3;
      const SagDepth: Single;
      const OrientAlongCurve: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      3D catenary / hanging cable curve between the first selected transform
      (@code(Selected[0])) and the last selected transform (@code(Selected[N-1])).
      When @code(SagDepth = 0), auto-computes a natural sag equal to $25\%$ of the
      chord distance between endpoints (or @code(2.0) when endpoints coincide).
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInCatenaryBetweenEndpoints(
      const SagDepth: Single = 0.0;
      const OrientAlongCurve: Boolean = false): Boolean;

    { Project all top-level selected transforms (@code(SelectedCount >= 1))
      orthogonally onto the 3D line connecting @code(LineStartWorldPos) and
      @code(LineEndWorldPos):
      $P'_i = P_0 + t_i (P_1 - P_0)$ where
      $t_i = \frac((P_i - P_0) \cdot (P_1 - P_0))(\|P_1 - P_0\|^2)$.
      Unlike @link(ArrangeSelectedOnLine) which spaces items uniformly along the
      chord, orthogonal projection preserves each object's existing longitudinal
      spacing along the axis while eliminating lateral and vertical drift.
      When @code(ClampToSegment) is @true, $t_i$ is clamped to $[0, 1]$ so no
      transform is projected outside the segment endpoints.
      When @code(OrientAlongLine) is @true, each transform is also oriented to look
      along the line direction from @code(LineStartWorldPos) toward @code(LineEndWorldPos).
      Returns @true if at least one selected transform was modified. }
    function ProjectSelectedOntoLine(
      const LineStartWorldPos, LineEndWorldPos: TVector3;
      const ClampToSegment: Boolean = false;
      const OrientAlongLine: Boolean = false): Boolean;

    { Project all top-level selected transforms (@code(SelectedCount >= 3), or
      @code(SelectedCount >= 2) when @code(OrientAlongLine) is @true) orthogonally
      onto the 3D line connecting the first selected transform (@code(Selected[0]))
      and the last selected transform (@code(Selected[N-1])).
      Returns @true if at least one selected transform was modified. }
    function ProjectSelectedOntoLineBetweenEndpoints(
      const ClampToSegment: Boolean = false;
      const OrientAlongLine: Boolean = false): Boolean;
  end;

var
  { Hover and selection colors.
    They have reasonable defaults, but you can change them if you want. }
  ColorHover, ColorSelected: TCastleColor;

implementation

uses Math,
  CastleLog, CastleShapes, CastleViewport, CastleProjection, CastleBoxes,
  CastleQuaternions, X3DNodes, CastleGLUtils, CastleRenderContext,
  CastleKeysMouse, CastleRenderOptions,
  CastleInternalTransformData;

{ TCastleTransformHover ------------------------------------------------------ }

constructor TCastleTransformHover.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FCurrentObserver := TFreeNotificationObserver.Create(Self);
  FCurrentObserver.OnFreeNotification := {$ifdef FPC}@{$endif} CurrentFreeNotification;

  Box := TDebugTransformBox.Create(Self);
  Box.BoxColor := ColorOpacity(ColorHover, 0.25);
  Box.Exists := true;
end;

destructor TCastleTransformHover.Destroy;
begin
  inherited;
end;

procedure TCastleTransformHover.SetCurrent(const AValue: TCastleTransform);
begin
  if FCurrent = AValue then Exit;

  FCurrent := AValue;
  FCurrentObserver.Observed := AValue;
  Box.Parent := FCurrent;
end;

procedure TCastleTransformHover.CurrentFreeNotification(const Sender: TFreeNotificationObserver);
begin
  Current := nil;
end;

{ TCastleTransformManipulate.TGizmoScene -------------------------------------------- }

function TCastleTransformManipulate.TGizmoScene.ManipulateOwner: TCastleTransformManipulate;
begin
  if Owner is TCastleTransformManipulate then
    Result := TCastleTransformManipulate(Owner)
  else
    Result := nil;
end;

function TCastleTransformManipulate.TGizmoScene.UseWorldCoordSpace: Boolean;
var
  Manip: TCastleTransformManipulate;
begin
  Manip := ManipulateOwner;
  Result := (Manip <> nil) and (Manip.CoordSpace = csWorld) and
    (Mode in [mmTranslate, mmRotate]) and (Parent <> nil);
end;

procedure TCastleTransformManipulate.TGizmoScene.GetEffectiveRay(
  const Pick: TRayCollisionNode; out RayOrigin, RayDirection: TVector3);
begin
  if UseWorldCoordSpace then
  begin
    RayOrigin := RotatePointAroundAxis(Parent.Rotation, Pick.RayOrigin * Parent.Scale);
    RayDirection := RotatePointAroundAxis(Parent.Rotation, Pick.RayDirection * Parent.Scale);
  end else
  begin
    RayOrigin := Pick.RayOrigin;
    RayDirection := Pick.RayDirection;
  end;
end;

function TCastleTransformManipulate.TGizmoScene.PointOnAxis(
  out Intersection: TVector3; const Pick: TRayCollisionNode;
  const Axis: Integer): Boolean;
var
  IntersectionScalar: Single;
  IntersectionOneAxis, RayOrigin, RayDirection: TVector3;
begin
  GetEffectiveRay(Pick, RayOrigin, RayDirection);

  if Axis = -1 then
  begin
    Result := true;
    IntersectionScalar := Sqrt(PointToLineDistanceSqr(TVector3.Zero, RayOrigin, RayDirection));
    Intersection := Vector3(IntersectionScalar, IntersectionScalar, IntersectionScalar);
  end else
  if Axis = -2 then
  begin
    Intersection := Vector3(0, 0, 0);
    Result := false;
    if PointOnLineClosestToLine(IntersectionOneAxis,
       TVector3.Zero, TVector3.One[0],
       RayOrigin, RayDirection) then
    begin
      Intersection := IntersectionOneAxis;
      Result := true;
    end;

    if PointOnLineClosestToLine(IntersectionOneAxis,
       TVector3.Zero, TVector3.One[1],
       RayOrigin, RayDirection) then
    begin
      Intersection := Intersection + IntersectionOneAxis;
      Result := true;
    end;
  end else
  begin
    Result := PointOnLineClosestToLine(Intersection,
      TVector3.Zero, TVector3.One[Axis],
      RayOrigin, RayDirection);

    {$ifdef DEBUG_GIZMO_PICK}
    VisualizePick.Exists := Result;
    if Result then
    begin
      // Intersection is in MainSelected coordinate space, i.e. ignores our gizmo scale
      VisualizePick.Translation := OutsideToLocal(Intersection);
      WritelnLog('VisualizePick with %s', [Intersection.ToString]);
      WritelnLog('Line 1: %s %s, line 2 %s %s', [
        TVector3.Zero.ToString,
        TVector3.One[Axis].ToString,
        RayOrigin.ToString,
        RayDirection.ToString
      ]);
    end;
    {$endif DEBUG_GIZMO_PICK}
  end;
end;

function TCastleTransformManipulate.TGizmoScene.AngleOnPlane(out Angle: Single;
  const Pick: TRayCollisionNode; const Coord: T3DAxis): Boolean;
var
  C1, C2: T3DAxis;
  PointProjected: TVector2;
  Intersection, RayOrigin, RayDirection: TVector3;
begin
  GetEffectiveRay(Pick, RayOrigin, RayDirection);
  if not TrySimplePlaneRayIntersection(Intersection, Coord, 0, RayOrigin, RayDirection) then
    Exit(false);
  { Use RestOf3DCoordsCycle, in the lopping order X-Y-Z.
    This results in consistent ArcTan2 results, that makes rotating around
    any coord in TCastleTransformManipulate.TGizmoScene.PointingDeviceMove
    have the same behavior (no need to invert angle sign for Y coord,
    as with RestOf3DCoords). }
  RestOf3DCoordsCycle(Coord, C1, C2);
  PointProjected.X := Intersection[C1];
  PointProjected.Y := Intersection[C2];
  Angle := ArcTan2(PointProjected.Y, PointProjected.X);
  Result := true;
end;

procedure TCastleTransformManipulate.TGizmoScene.DoTransformModifyBegin;
begin
  if Assigned(OnTransformModifyBegin) then
    OnTransformModifyBegin(Self);
end;

procedure TCastleTransformManipulate.TGizmoScene.DoTransformModified;
begin
  if Assigned(OnTransformModified) then
    OnTransformModified(Self);
end;

procedure TCastleTransformManipulate.TGizmoScene.DoTransformModifyEnd;
begin
  if Assigned(OnTransformModifyEnd) then
    OnTransformModifyEnd(Self);
end;

procedure TCastleTransformManipulate.TGizmoScene.ChangeWorld(
  const Value: TCastleAbstractRootTransform);
begin
  if Value <> World then
  begin
    inherited;
    GizmoDragging := false;
  end;
end;

constructor TCastleTransformManipulate.TGizmoScene.Create(AOwner: TComponent);
{$ifdef DEBUG_GIZMO_PICK}
var
  SphereGeometry: TSphereNode;
  SphereShape: TShapeNode;
  SphereMat: TMaterialNode;
  SphereAppearance: TAppearanceNode;
  SphereRoot: TX3DRootNode;
{$endif DEBUG_GIZMO_PICK}
begin
  inherited Create(AOwner);
  InternalExistsOnlyInMeaningfulParents := true;
  RenderLayer := rlFront;

  {$ifdef DEBUG_GIZMO_PICK}
  VisualizePick := TCastleScene.Create(Self);

  SphereGeometry := TSphereNode.CreateWithShape(SphereShape);
  SphereGeometry.Radius := 0.1;

  SphereMat := TMaterialNode.Create;
  SphereMat.DiffuseColor := RedRGB;

  SphereAppearance := TAppearanceNode.Create;
  SphereAppearance.Material := SphereMat;

  SphereShape.Appearance := SphereAppearance;

  SphereRoot := TX3DRootNode.Create;
  SphereRoot.AddChildren(SphereShape);

  VisualizePick.Load(SphereRoot, true);
  VisualizePick.Exists := false;
  Add(VisualizePick);
  {$endif DEBUG_GIZMO_PICK}
end;

procedure TCastleTransformManipulate.TGizmoScene.InternalCameraChanged;
begin
  inherited;
  UpdateSize;
end;

procedure TCastleTransformManipulate.TGizmoScene.UpdateSize;

  function Projected(const V, X, Y: TVector3): TVector2;
  begin
    Result.X := TVector3.DotProduct(V, X);
    Result.Y := TVector3.DotProduct(V, Y);
  end;

var
  OldScale: TVector3;

  { Surround calls to WorldTransform in this, to account for
    GizmoScalingAssumeScale[Value]. }
  procedure BeginWorldTransform;
  begin
    if GizmoScalingAssumeScale then
    begin
      OldScale := Parent.Scale;
      Parent.Scale := GizmoScalingAssumeScaleValue;
    end;
  end;

  procedure EndWorldTransform;
  begin
    if GizmoScalingAssumeScale then
      Parent.Scale := OldScale;
  end;

  function GetPerspectiveGizmoScale(const Camera: TCastleCamera; const BaseGizmoScale: Single): Single;
  const
    AssumeNear = 1.0;
  var
    ZeroProjected, OneProjected: TVector2;
    OneDistance: Single;
    CameraPos, CameraDir, CameraUp: TVector3; //< camera vectors in world-coordinates
    ZeroWorld, OneWorld, OneProjected3, ZeroProjected3, CameraSide: TVector3;
    CameraNearPlane: TVector4;
    SceneSizeMultiplier: Single;
  begin
    { In theory, any value of SceneSizeMultiplier is OK,
      and it could be always 1.0.
      But on large scenes, this makes huge precision problems with calculation
      below, as OneWorld will be very close to ZeroWorld and then OneDistance is tiny.
      So we use to calculate in larger coordinates, and then scale it back to achieve the same.
      Testcase: gizmo_flickering_bug . }
    SceneSizeMultiplier := World.BoundingBox.AverageSize(false, 1.0);

    Camera.GetWorldView(CameraPos, CameraDir, CameraUp);

    BeginWorldTransform;

    { Map two points from gizmo local transformation,
      to determine correct gizmo scale.
      These points reflect the parent translation and scale.

      Note that we know that gizmo itself has never any translation,
      but it may have a scale.
    }
    Scale := Vector3(1, 1, 1); // assume gizmo scale = 1, will be changed later
    ZeroWorld := LocalToWorld(TVector3.Zero);
    { Note: We use CameraUp, not Camera.GravityUp, to work sensibly even
      when looking at world at a direction similar to +Y. }
    OneWorld := LocalToWorld(WorldToLocalDirection(CameraUp).AdjustToLength(SceneSizeMultiplier));

    EndWorldTransform;

    CameraNearPlane := Vector4(
      CameraDir,
      { plane equation should yield 0 when used with point in front of camera }
      - TVector3.DotProduct(
          CameraPos + CameraDir * AssumeNear * SceneSizeMultiplier,
          CameraDir
        )
    );
    if not TryPlaneLineIntersection(OneProjected3, CameraNearPlane, CameraPos, OneWorld - CameraPos) then
      Exit(1.0); // no valid value can be calculated
    if not TryPlaneLineIntersection(ZeroProjected3, CameraNearPlane, CameraPos, ZeroWorld - CameraPos) then
      Exit(1.0); // no valid value can be calculated

    CameraSide := TVector3.CrossProduct(CameraDir, CameraUp);
    ZeroProjected := Projected(ZeroProjected3, CameraSide, CameraUp);
    OneProjected := Projected(OneProjected3, CameraSide, CameraUp);

    // get the distance, on screen in pixels, of a 1 unit in 3D around gizmo
    OneDistance := PointsDistance(ZeroProjected, OneProjected);

    if IsZero(OneDistance) then
      Result := SceneSizeMultiplier
    else
      { Multiply by SceneSizeMultiplier 2x because
        1. it increases OneWorld
        2. it increases camera near (at AssumeNear) }
      Result := Sqr(SceneSizeMultiplier) * BaseGizmoScale / OneDistance;
  end;

const
  BaseGizmoScaleOrtho = 0.3 * 0.5;
  BaseGizmoScalePerspective = 0.25 * 0.5;
var
  Camera: TCastleCamera;
  GizmoScale, ScaleUniform: Single;
begin
  { UpdateSize changes our transformation, and ChangedTransform in turn
    calls InternalCameraChanged, which means we can get into infinite
    recursion. Use InsideUpdateSize to prevent it. }
  if InsideUpdateSize then Exit;
  InsideUpdateSize := true;
  try
    { Orient gizmo in World or Local coordinate space. }
    if UseWorldCoordSpace then
      Rotation := Vector4(Parent.Rotation.XYZ, -Parent.Rotation.W)
    else
      Rotation := Vector4(0, 1, 0, 0);

    { Adjust scale to take the same space on screen. }
    if HasWorldTransform and
       (World <> nil) and
       (World.MainCamera <> nil) then
    begin
      Camera := World.MainCamera;

      if Camera.ProjectionType = ptOrthographic then
      begin
        { We just want gizmo is about 15% of effective height }
        GizmoScale := BaseGizmoScaleOrtho * Camera.Orthographic.EffectiveRect.Height;
        ScaleUniform := Parent.WorldToLocalDistance(GizmoScale);
      end else
      begin
        GizmoScale := BaseGizmoScalePerspective {TODO:* Camera.Perspective.EffectiveFieldOfViewVertical};
        ScaleUniform := GetPerspectiveGizmoScale(Camera, GizmoScale);
      end;

      Scale := Vector3(ScaleUniform, ScaleUniform, ScaleUniform);
    end;
  finally
    InsideUpdateSize := false;
  end;
end;

function TCastleTransformManipulate.TGizmoScene.PointingDevicePress(
  const Pick: TRayCollisionNode; const Distance: Single): Boolean;
var
  AppearanceName: String;
  CanDrag: Boolean;

  function IsOrthographicTranslation: Boolean;
  begin
    Result := (
      (Mode = mmTranslate) and
      HasWorldTransform and
      (World <> nil) and
      (World.MainCamera <> nil) and
      (World.MainCamera.ProjectionType = ptOrthographic) and
      // TODO: should check world-space direction
      (TVector3.Equals(World.MainCamera.Direction, Vector3(0, 0, -1)))
    );
  end;

begin
  Result := inherited;
  if Result then Exit;

  { When importing glTF, Blender material name -> X3D Appearance name. }
  if (Pick.Triangle <> nil) and
     (Pick.Triangle^.ShapeNode <> nil) and
     (Pick.Triangle^.ShapeNode.Appearance <> nil) then
  begin
    AppearanceName := Pick.Triangle^.ShapeNode.Appearance.X3DName;
    if AppearanceName = 'MaterialX' then
    begin
      DraggingCoord := 0;
    end else
    if AppearanceName = 'MaterialY' then
    begin
      DraggingCoord := 1;
    end else
    if AppearanceName = 'MaterialZ' then
    begin
      { In 2D mode dragging Z axis means translate in X and Y. }
      if IsOrthographicTranslation then
        DraggingCoord := -2
      else
        DraggingCoord := 2;
    end else
    if AppearanceName = 'MaterialCenter' then
    begin
      { In 2D mode dragging center square means translate in X and Y. }
      if IsOrthographicTranslation then
        DraggingCoord := -2
      else
      if Mode = mmScale then
        DraggingCoord := -1;
    end else
      Exit; // ignore draging on other material names

    if Mode = mmRotate then
      CanDrag := AngleOnPlane(LastPickAngle, Pick, DraggingCoord)
    else
      CanDrag := PointOnAxis(LastPick, Pick, DraggingCoord);

    if CanDrag then
    begin
      DoTransformModifyBegin;
      if Mode = mmScale then
      begin
        { In CameraChanged, we adjust gizmo scale to make it fit within
          the screen nicely. This way, we actually "nullify" the effect
          of parent's scale on gizmo size.

          But this has to be disabled within the dragging when scaling,
          to enable scaling gizmo get smaller/larger as we drag.

          During a single drag, we behave like Scale is constant.
          Gizmo will be correctly scaled when you release. }
        GizmoScalingAssumeScale := true;
        GizmoScalingAssumeScaleValue := Parent.Scale;
      end;
      GizmoDragging := true;
      // keep tracking pointing device events, by TCastleViewport.CapturePointingDevice mechanism
      Result := true;
    end;
  end;
end;

function TCastleTransformManipulate.TGizmoScene.PointingDeviceMove(
  const Pick: TRayCollisionNode; const Distance: Single): Boolean;
var
  NewPick, Diff: TVector3;
  NewPickAngle, DiffAngle, TargetScale, SnappedScale: Single;
  I: Integer;
  DragSuccess, WorldCoord: Boolean;
  Manip: TCastleTransformManipulate;
begin
  Result := inherited;
  if Result then Exit;

  if GizmoDragging then
  begin
    if Mode = mmRotate then
      DragSuccess := AngleOnPlane(NewPickAngle, Pick, DraggingCoord)
    else
      DragSuccess := PointOnAxis(NewPick, Pick, DraggingCoord);
    if DragSuccess then
    begin
      Manip := ManipulateOwner;
      WorldCoord := UseWorldCoordSpace;

      {$ifdef DEBUG_GIZMO_PICK}
      if TCastleControl.MainControl.Pressed[keyShift] then
      {$endif DEBUG_GIZMO_PICK}
      case Mode of
        mmTranslate:
          begin
            Diff := NewPick - LastPick;
            if not WorldCoord then
            begin
              if DraggingCoord >= 0 then
                { We need to apply only scale in 1 axis,
                  https://forum.castle-engine.io/t/creating-a-non-linear-strategic-adventure/403/22 }
                Diff := Diff * Parent.Scale[DraggingCoord]
              else
                Diff := Diff * Parent.Scale;
            end;

            if (Manip <> nil) and (Manip.TranslateSnap > 0) then
            begin
              for I := 0 to 2 do
                Diff.Data[I] := Round(Diff.Data[I] / Manip.TranslateSnap) * Manip.TranslateSnap;
            end;

            if Diff.IsPerfectlyZero then
              Exit;

            if not WorldCoord then
            begin
              { Our gizmo display and interaction is affected by existing
                Parent.Rotation although the Parent.Translation
                is applied before rotation technically.
                So we need to manually multiply Diff by current rotation. }
              Diff := RotatePointAroundAxis(Parent.Rotation, Diff);
            end;

            if Manip <> nil then
              Manip.ApplyTranslateDelta(Diff)
            else
              Parent.Translation := Parent.Translation + Diff;
          end;
        mmRotate:
          begin
            DiffAngle := NewPickAngle - LastPickAngle;
            while DiffAngle > Pi do DiffAngle := DiffAngle - 2 * Pi;
            while DiffAngle < -Pi do DiffAngle := DiffAngle + 2 * Pi;

            if (Manip <> nil) and (Manip.RotateSnap > 0) then
              DiffAngle := Round(DiffAngle / Manip.RotateSnap) * Manip.RotateSnap;

            if IsZero(DiffAngle) then
              Exit;

            if WorldCoord then
              LastPickAngle := LastPickAngle + DiffAngle;

            if Manip <> nil then
              Manip.ApplyRotateDelta(DraggingCoord, DiffAngle)
            else
              Parent.Rotation := (
                QuatFromAxisAngle(Parent.Rotation) *
                QuatFromAxisAngle(TVector3.One[DraggingCoord], DiffAngle)).
                ToAxisAngle;
          end;
        mmScale:
          begin
            for I := 0 to 2 do
              if IsZero(LastPick[I]) then
                Diff.Data[I] := 1
              else
              begin
                if (Manip <> nil) and (Manip.ScaleSnap > 0) and (not IsZero(Parent.Scale[I])) then
                begin
                  TargetScale := Parent.Scale[I] * (NewPick[I] / LastPick[I]);
                  SnappedScale := GizmoScalingAssumeScaleValue[I] +
                    Round((TargetScale - GizmoScalingAssumeScaleValue[I]) / Manip.ScaleSnap) * Manip.ScaleSnap;
                  if Abs(SnappedScale) < 1e-4 then
                    Diff.Data[I] := 1
                  else
                    Diff.Data[I] := SnappedScale / Parent.Scale[I];
                end else
                  Diff.Data[I] := NewPick[I] / LastPick[I];
              end;

            if TVector3.Equals(Diff, Vector3(1, 1, 1)) then
              Exit;

            if Manip <> nil then
              Manip.ApplyScaleMultiplier(Diff)
            else
              Parent.Scale := Parent.Scale * Diff;
          end;
        mmSelect:
          raise EInternalError.Create('TGizmoScene shall never be created with mmSelect, ');
      end;

      // update our gizmo size and rotation, as we moved/rotated ourselves
      UpdateSize;
      DoTransformModified;
    end;
  end;
end;

function TCastleTransformManipulate.TGizmoScene.PointingDeviceRelease(
  const Pick: TRayCollisionNode; const Distance: Single;
  const CancelAction: Boolean): Boolean;
begin
  Result := inherited;
  if Result then Exit;

  GizmoDragging := false;

  if GizmoScalingAssumeScale then
  begin
    GizmoScalingAssumeScale := false;
    UpdateSize;
  end;
  DoTransformModifyEnd;
end;

procedure TCastleTransformManipulate.TGizmoScene.LocalRender(const Params: TRenderParams);
var
  GizmoRendered: Boolean;
begin
  { Similar to TInternalCastleEditorGizmo.LocalRender, do not render when gizmo
    is over the rendering camera (happens when moving/rotating/scaling
    the camera that is aligned to view). }
  LastIsProjectionOrthographic :=
    (Params.RenderingCamera.Camera <> nil) and
    (Params.RenderingCamera.Camera.ProjectionType = ptOrthographic);
  GizmoRendered := TInternalCastleEditorGizmo.ShouldGizmoBeRendered(
    LastIsProjectionOrthographic,
    Params.Transformation^.Transform.MultPoint(TVector3.Zero),
    Params.RenderingCamera.View.Translation
  );
  if not GizmoRendered then
    Exit; // do not show gizmo
  inherited;
end;

function TCastleTransformManipulate.TGizmoScene.LocalRayCollision(
  const RayOrigin, RayDirection: TVector3;
  const TrianglesToIgnoreFunc: TTriangleIgnoreFunc): TRayCollision;
var
  GizmoRendered: Boolean;
begin
  { Similar to TInternalCastleEditorGizmo.LocalRayCollision, do not collide
    when gizmo is also hidden. }
  GizmoRendered := TInternalCastleEditorGizmo.ShouldGizmoBeRendered(
    LastIsProjectionOrthographic,
    TVector3.Zero, RayOrigin);
  if not GizmoRendered then
    Exit(nil); // do not pick with gizmo with raycast

  Result := inherited;

  { Hack to make picking of the gizmo work even when gizmo is obscured
    by other TCastleTransform (including bbox of Parent, which is what
    we actually want to transform).
    Hacking Distance to be smallest possible means that it "wins"
    when TCastleTransform.LocalRayCollision desides which collision
    is first along the ray. }
  if Result <> nil then
    Result.Distance := 0;
end;

{ TCastleTransformManipulate ------------------------------------------------------ }

constructor TCastleTransformManipulate.Create(AOwner: TComponent);

  function CreateGizmoScene: TGizmoScene;
  begin
    Result := TGizmoScene.Create(Self);
    Result.Collides := false;
    Result.Pickable := FPickable;
    Result.CastShadows := false;
    Result.InternalExcludeFromParentBoundingVolume := true;
    Result.PreciseCollisions := true;
    Result.SetTransient;
    Result.OnTransformModifyBegin := {$ifdef FPC}@{$endif} GizmoHasTransformModifyBegin;
    Result.OnTransformModified := {$ifdef FPC}@{$endif} GizmoHasTransformModified;
    Result.OnTransformModifyEnd := {$ifdef FPC}@{$endif} GizmoHasTransformModifyEnd;
  end;

begin
  inherited;
  FPickable := true;
  FCoordSpace := csLocal;

  FMainSelectedObserver := TFreeNotificationObserver.Create(Self);
  FMainSelectedObserver.OnFreeNotification := {$ifdef FPC}@{$endif} MainSelectedFreeNotification;

  Boxes := TDebugTransformBoxList.Create(true);
  CreateMoreBoxes;

  RegisterTransformManipulateData;

  // Gizmo[mmSelect] remains nil
  Gizmo[mmTranslate] := CreateGizmoScene;
  Gizmo[mmTranslate].Load('castle-internal-embedded-data:/translate_final.x3dv');
  Gizmo[mmTranslate].Mode := mmTranslate;
  Gizmo[mmRotate] := CreateGizmoScene;
  Gizmo[mmRotate].Load('castle-internal-embedded-data:/rotate_final.x3dv');
  Gizmo[mmRotate].Mode := mmRotate;
  Gizmo[mmScale] := CreateGizmoScene;
  Gizmo[mmScale].Load('castle-internal-embedded-data:/scale_final.x3dv');
  Gizmo[mmScale].Mode := mmScale;
end;

destructor TCastleTransformManipulate.Destroy;
begin
  FreeAndNil(Boxes);
  inherited;
end;

procedure TCastleTransformManipulate.CreateMoreBoxes;
const
  IncreaseBoxes = 8;
var
  C, I: Integer;
begin
  C := Boxes.Count;
  Boxes.Count := Boxes.Count + IncreaseBoxes;
  for I := C to Boxes.Count - 1 do
  begin
    Boxes[I] := TDebugTransformBox.Create(Self);
    Boxes[I].BoxColor := ColorOpacity(ColorSelected, 0.5);
    Boxes[I].Exists := true;
  end;
end;

procedure TCastleTransformManipulate.SetSelected(const NewSelected: array of TComponent);
var
  List: TComponentList;
  C: TComponent;
begin
  List := TComponentList.Create(false);
  try
    for C in NewSelected do
      List.Add(C);
    SetSelected(List);
  finally FreeAndNil(List) end;
end;

procedure TCastleTransformManipulate.SetSelected(const NewSelected: TComponentList);
var
  I, NewSelectedCount: Integer;
begin
  NewSelectedCount := 0;
  if NewSelected <> nil then
    for I := 0 to NewSelected.Count - 1 do
      if (NewSelected[I] is TCastleTransform) and
         { Disallow editing TCastleAbstractRootTransform transformation.
           See InspectorFilter in CGE editor for explanation, in short:
           editing TCastleAbstractRootTransform transformation is very
           unintuitive, as you transform both objects and the camera...
           so actually nothing visible happens. }
         (not (NewSelected[I] is TCastleAbstractRootTransform)) then
      begin
        if NewSelectedCount >= Boxes.Count then
          CreateMoreBoxes;
        Assert(NewSelectedCount < Boxes.Count);
        Boxes[NewSelectedCount].Parent := TCastleTransform(NewSelected[I]);
        Inc(NewSelectedCount);
      end;

  { Note: each TDebugTransformBox already observes its Parent,
    and sets own Parent=nil if the parent is freed.
    So there's no need to worry about it here anymore. }

  { Detach remaining Boxes from any parent, to not show them }
  for I := NewSelectedCount to Boxes.Count - 1 do
    Boxes[I].Parent := nil;

  FMaxSelectedCount := NewSelectedCount;

  UpdateMainSelected;
end;

procedure TCastleTransformManipulate.UpdateMainSelected;
begin
  if SelectedCount >= 1 then
    MainSelected := Selected[0]
  else
    MainSelected := nil;
end;

procedure TCastleTransformManipulate.SetMainSelected(const AValue: TCastleTransform);
begin
  if FMainSelected = AValue then Exit;

  if FMainSelected <> nil then
  begin
    if Gizmo[Mode] <> nil then
      FMainSelected.Remove(Gizmo[Mode]);
  end;

  FMainSelected := AValue;
  FMainSelectedObserver.Observed := AValue;

  if FMainSelected <> nil then
  begin
    if Gizmo[Mode] <> nil then
    begin
      FMainSelected.Add(Gizmo[Mode]);
      Gizmo[Mode].UpdateSize;
    end;
  end;
end;

procedure TCastleTransformManipulate.MainSelectedFreeNotification(const Sender: TFreeNotificationObserver);
var
  I: Integer;
begin
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if Boxes[I].Parent = FMainSelected then
      Boxes[I].Parent := nil;
  UpdateMainSelected;
end;

procedure TCastleTransformManipulate.SetPickable(const Value: Boolean);
var
  M: TManipulateMode;
begin
  if FPickable <> Value then
  begin
    FPickable := Value;
    for M := Low(TManipulateMode) to High(TManipulateMode) do
      if Gizmo[M] <> nil then // Gizmo[mmSelect] is nil now, nothing to show
        Gizmo[M].Pickable := Value;
  end;
end;

procedure TCastleTransformManipulate.GizmoHasTransformModifyBegin(Sender: TObject);
begin
  if Assigned(OnTransformModifyBegin) then
    OnTransformModifyBegin(Self);
end;

procedure TCastleTransformManipulate.GizmoHasTransformModified(Sender: TObject);
begin
  if Assigned(OnTransformModified) then
    OnTransformModified(Self);
end;

procedure TCastleTransformManipulate.GizmoHasTransformModifyEnd(Sender: TObject);
begin
  if Assigned(OnTransformModifyEnd) then
    OnTransformModifyEnd(Self);
end;

procedure TCastleTransformManipulate.SetMode(const AValue: TManipulateMode);
begin
  if FMode = AValue then Exit;

  if (FMainSelected <> nil) and (Gizmo[Mode] <> nil) then
    FMainSelected.Remove(Gizmo[Mode]);

  FMode := AValue;

  if (FMainSelected <> nil) and (Gizmo[Mode] <> nil) then
  begin
    FMainSelected.Add(Gizmo[Mode]);
    Gizmo[Mode].UpdateSize;
  end;
end;

procedure TCastleTransformManipulate.SetCoordSpace(const AValue: TManipulateCoordSpace);
begin
  if FCoordSpace = AValue then Exit;
  FCoordSpace := AValue;
  if (FMainSelected <> nil) and (Gizmo[Mode] <> nil) then
    Gizmo[Mode].UpdateSize;
end;

procedure TCastleTransformManipulate.SetPivotMode(const AValue: TManipulatePivotMode);
begin
  if FPivotMode = AValue then Exit;
  FPivotMode := AValue;
  if (FMainSelected <> nil) and (Gizmo[Mode] <> nil) then
    Gizmo[Mode].UpdateSize;
end;

function TCastleTransformManipulate.IsDescendantOfAnySelected(const T: TCastleTransform): Boolean;
var
  P: TCastleTransform;
  I: Integer;
begin
  P := T.Parent;
  while P <> nil do
  begin
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
      if Boxes[I].Parent = P then
        Exit(true);
    P := P.Parent;
  end;
  Result := false;
end;

function TCastleTransformManipulate.GetTransformWorkingPos(const T: TCastleTransform): TVector3;
begin
  if (T <> nil) and T.HasWorldTransform then
    Result := T.LocalToWorld(TVector3.Zero)
  else
  if T <> nil then
    Result := T.Translation
  else
    Result := TVector3.Zero;
end;

procedure TCastleTransformManipulate.SetTransformWorkingPos(
  const T: TCastleTransform; const NewWorkingPos: TVector3);
var
  WorldDelta, LocalDelta: TVector3;
begin
  if T = nil then Exit;
  if T.HasWorldTransform then
  begin
    WorldDelta := NewWorkingPos - T.LocalToWorld(TVector3.Zero);
    if not WorldDelta.IsZero then
    begin
      if (T.Parent <> nil) and T.Parent.HasWorldTransform then
        LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta)
      else
        LocalDelta := WorldDelta;
      T.Translation := T.Translation + LocalDelta;
    end;
  end else
    T.Translation := NewWorkingPos;
end;

function TCastleTransformManipulate.SelectionWorkingCenter: TVector3;
var
  I, Count: Integer;
  T: TCastleTransform;
  Sum: TVector3;
begin
  Sum := TVector3.Zero;
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Sum := Sum + GetTransformWorkingPos(T);
      Inc(Count);
    end;
  end;
  if Count > 0 then
    Result := Sum / Single(Count)
  else
    Result := TVector3.Zero;
end;

procedure TCastleTransformManipulate.ApplyTranslateDelta(const DeltaInMainParent: TVector3);
var
  I: Integer;
  T: TCastleTransform;
  WorldDelta, ItemDelta: TVector3;
  HasWorldDelta: Boolean;
begin
  HasWorldDelta := (FMainSelected <> nil) and (FMainSelected.Parent <> nil) and
    FMainSelected.Parent.HasWorldTransform;
  if HasWorldDelta then
    WorldDelta := FMainSelected.Parent.LocalToWorldDirection(DeltaInMainParent)
  else
    WorldDelta := DeltaInMainParent;

  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      if (FMainSelected = nil) or (T.Parent = FMainSelected.Parent) then
        ItemDelta := DeltaInMainParent
      else
      if HasWorldDelta and (T.Parent <> nil) and T.Parent.HasWorldTransform then
        ItemDelta := T.Parent.WorldToLocalDirection(WorldDelta)
      else
        ItemDelta := DeltaInMainParent;

      T.Translation := T.Translation + ItemDelta;
    end;
  end;
end;

procedure TCastleTransformManipulate.ApplyRotateDelta(const AxisCoord: Integer; const DiffAngle: Single);
var
  I, TopLevelCount: Integer;
  T: TCastleTransform;
  AxisVec, OrbitAxisVec, PivotPos, RelPos: TVector3;
begin
  AxisVec := TVector3.One[AxisCoord];

  TopLevelCount := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
      Inc(TopLevelCount);
  end;

  if (FPivotMode = pmSelectionCenter) and (TopLevelCount > 1) then
  begin
    PivotPos := SelectionWorkingCenter;
    if (FCoordSpace = csLocal) and (FMainSelected <> nil) then
      OrbitAxisVec := RotatePointAroundAxis(FMainSelected.Rotation, AxisVec)
    else
      OrbitAxisVec := AxisVec;
  end else
  begin
    PivotPos := TVector3.Zero;
    OrbitAxisVec := AxisVec;
  end;

  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      if (FPivotMode = pmSelectionCenter) and (TopLevelCount > 1) then
      begin
        RelPos := GetTransformWorkingPos(T) - PivotPos;
        if not RelPos.IsZero then
          SetTransformWorkingPos(T, PivotPos + RotatePointAroundAxisRad(DiffAngle, RelPos, OrbitAxisVec));
      end;

      if FCoordSpace = csWorld then
        T.Rotation := (
          QuatFromAxisAngle(AxisVec, DiffAngle) *
          QuatFromAxisAngle(T.Rotation)).
          ToAxisAngle
      else
        T.Rotation := (
          QuatFromAxisAngle(T.Rotation) *
          QuatFromAxisAngle(AxisVec, DiffAngle)).
          ToAxisAngle;
    end;
  end;
end;

procedure TCastleTransformManipulate.ApplyScaleMultiplier(const ScaleMultiplier: TVector3);
var
  I: Integer;
  T: TCastleTransform;
begin
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
      T.Scale := T.Scale * ScaleMultiplier;
  end;
end;

procedure TCastleTransformManipulate.TranslateSelected(const RawDelta: TVector3);
var
  Delta: TVector3;
  I: Integer;
begin
  if FMainSelected = nil then Exit;

  Delta := RawDelta;
  if FTranslateSnap > 0 then
    for I := 0 to 2 do
      Delta.Data[I] := Round(Delta.Data[I] / FTranslateSnap) * FTranslateSnap;

  if Delta.IsPerfectlyZero then Exit;

  if FCoordSpace = csLocal then
    Delta := RotatePointAroundAxis(FMainSelected.Rotation, Delta);

  ApplyTranslateDelta(Delta);
  if Gizmo[Mode] <> nil then
    Gizmo[Mode].UpdateSize;
  GizmoHasTransformModified(Self);
end;

procedure TCastleTransformManipulate.RotateSelected(const Axis: T3DAxis; const RawAngleRad: Single);
var
  Angle: Single;
begin
  if FMainSelected = nil then Exit;

  Angle := RawAngleRad;
  if FRotateSnap > 0 then
    Angle := Round(Angle / FRotateSnap) * FRotateSnap;

  if IsZero(Angle) then Exit;

  ApplyRotateDelta(Axis, Angle);
  if Gizmo[Mode] <> nil then
    Gizmo[Mode].UpdateSize;
  GizmoHasTransformModified(Self);
end;

procedure TCastleTransformManipulate.ScaleSelected(const RawScaleDelta: TVector3);
var
  Delta, NewScale: TVector3;
  I: Integer;
  T: TCastleTransform;
  ModifiedAny: Boolean;
begin
  if FMainSelected = nil then Exit;

  Delta := RawScaleDelta;
  if FScaleSnap > 0 then
    for I := 0 to 2 do
      Delta.Data[I] := Round(Delta.Data[I] / FScaleSnap) * FScaleSnap;

  if Delta.IsPerfectlyZero then Exit;

  ModifiedAny := false;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      NewScale := T.Scale + Delta;
      if (Abs(NewScale.X) >= 1e-4) and
         (Abs(NewScale.Y) >= 1e-4) and
         (Abs(NewScale.Z) >= 1e-4) then
      begin
        T.Scale := NewScale;
        ModifiedAny := true;
      end;
    end;
  end;

  if ModifiedAny then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
  end;
end;

procedure TCastleTransformManipulate.AlignSelected(const Axis: T3DAxis; const Target: TAlignTarget);
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  Pos: TVector3;
  MinCoord, MaxCoord, TargetCoord: Single;
  ModifiedAny: Boolean;
begin
  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;
  if Count < 2 then Exit;

  MinCoord := GetTransformWorkingPos(Items[0])[Axis];
  MaxCoord := MinCoord;
  for I := 1 to Count - 1 do
  begin
    Pos := GetTransformWorkingPos(Items[I]);
    if Pos[Axis] < MinCoord then MinCoord := Pos[Axis];
    if Pos[Axis] > MaxCoord then MaxCoord := Pos[Axis];
  end;

  case Target of
    atPrimary:
      if FMainSelected <> nil then
        TargetCoord := GetTransformWorkingPos(FMainSelected)[Axis]
      else
        TargetCoord := GetTransformWorkingPos(Items[0])[Axis];
    atMin: TargetCoord := MinCoord;
    atCenter: TargetCoord := 0.5 * (MinCoord + MaxCoord);
    atMax: TargetCoord := MaxCoord;
  end;

  ModifiedAny := false;
  for I := 0 to Count - 1 do
  begin
    Pos := GetTransformWorkingPos(Items[I]);
    if not SameValue(Pos[Axis], TargetCoord) then
    begin
      Pos.Data[Axis] := TargetCoord;
      SetTransformWorkingPos(Items[I], Pos);
      ModifiedAny := true;
    end;
  end;

  if ModifiedAny then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

procedure TCastleTransformManipulate.DistributeSelected(const Axis: T3DAxis);
var
  Items: array of TCastleTransform;
  Coords: array of Single;
  I, J, Count: Integer;
  T, TempT: TCastleTransform;
  TempCoord, MinCoord, MaxCoord, Step, TargetCoord: Single;
  Pos: TVector3;
  ModifiedAny: Boolean;
begin
  SetLength(Items, FMaxSelectedCount);
  SetLength(Coords, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Coords[Count] := GetTransformWorkingPos(T)[Axis];
      Inc(Count);
    end;
  end;
  if Count < 3 then Exit;

  { Sort transforms by ascending coordinate along Axis. }
  for I := 0 to Count - 2 do
    for J := I + 1 to Count - 1 do
      if Coords[J] < Coords[I] then
      begin
        TempCoord := Coords[I];
        Coords[I] := Coords[J];
        Coords[J] := TempCoord;

        TempT := Items[I];
        Items[I] := Items[J];
        Items[J] := TempT;
      end;

  MinCoord := Coords[0];
  MaxCoord := Coords[Count - 1];
  Step := (MaxCoord - MinCoord) / Single(Count - 1);

  ModifiedAny := false;
  for I := 1 to Count - 2 do
  begin
    TargetCoord := MinCoord + Step * Single(I);
    Pos := GetTransformWorkingPos(Items[I]);
    if not SameValue(Pos[Axis], TargetCoord) then
    begin
      Pos.Data[Axis] := TargetCoord;
      SetTransformWorkingPos(Items[I], Pos);
      ModifiedAny := true;
    end;
  end;

  if ModifiedAny then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.StackSelected(
  const Axis: T3DAxis; const Spacing: Single): Boolean;
var
  Items: array of TCastleTransform;
  Coords: array of Single;
  Count, I, J: Integer;
  T, TempT: TCastleTransform;
  TempCoord, PrevMax, CurMin, CurMax, DeltaAxis: Single;
  BBox: TBox3D;
  Pos: TVector3;
begin
  Result := false;
  SetLength(Items, FMaxSelectedCount);
  SetLength(Coords, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Coords[Count] := GetTransformWorkingPos(T)[Axis];
      Inc(Count);
    end;
  end;
  if Count < 2 then Exit;

  { Sort transforms by ascending coordinate along Axis. }
  for I := 0 to Count - 2 do
    for J := I + 1 to Count - 1 do
      if Coords[J] < Coords[I] then
      begin
        TempCoord := Coords[I];
        Coords[I] := Coords[J];
        Coords[J] := TempCoord;

        TempT := Items[I];
        Items[I] := Items[J];
        Items[J] := TempT;
      end;

  if Items[0].HasWorldTransform then
    BBox := Items[0].WorldBoundingBox
  else
    BBox := Items[0].BoundingBox;

  if not BBox.IsEmpty then
    PrevMax := BBox.Max[Axis]
  else
    PrevMax := GetTransformWorkingPos(Items[0])[Axis];

  for I := 1 to Count - 1 do
  begin
    Pos := GetTransformWorkingPos(Items[I]);
    if Items[I].HasWorldTransform then
      BBox := Items[I].WorldBoundingBox
    else
      BBox := Items[I].BoundingBox;

    if not BBox.IsEmpty then
    begin
      CurMin := BBox.Min[Axis];
      CurMax := BBox.Max[Axis];
    end else
    begin
      CurMin := Pos[Axis];
      CurMax := Pos[Axis];
    end;

    DeltaAxis := (PrevMax + Spacing) - CurMin;
    if not SameValue(DeltaAxis, 0) then
    begin
      Pos.Data[Axis] := Pos[Axis] + DeltaAxis;
      SetTransformWorkingPos(Items[I], Pos);
      Result := true;
    end;

    PrevMax := (PrevMax + Spacing) + (CurMax - CurMin);
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.SnapSelectedToGrid: Boolean;
var
  I, C: Integer;
  T: TCastleTransform;
  Snapped: TVector3;
begin
  Result := false;
  if (SelectedCount = 0) or (FTranslateSnap <= 0) then Exit;

  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Snapped := T.Translation;
      for C := 0 to 2 do
        Snapped.Data[C] := Round(Snapped.Data[C] / FTranslateSnap) * FTranslateSnap;
      if not TVector3.Equals(Snapped, T.Translation) then
      begin
        T.Translation := Snapped;
        Result := true;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.SnapToFloor(const AlignToNormal: Boolean): Boolean;
var
  I: Integer;
  T: TCastleTransform;
  SavedPickable: array of Boolean;
  SavedGizmoPickable: Boolean;
  GravityUp, DownDir, RayOrigin, WorldDelta, LocalDelta: TVector3;
  WorldNormal, TargetUpInParent, CurrentUpInParent, RotAxis: TVector3;
  BBox: TBox3D;
  HalfHeight, HitDistance, RotAngle: Single;
  RayHit: TRayCollision;
begin
  Result := false;
  if SelectedCount = 0 then Exit;

  SavedGizmoPickable := Pickable;
  SetLength(SavedPickable, FMaxSelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if Boxes[I].Parent <> nil then
    begin
      SavedPickable[I] := Boxes[I].Parent.Pickable;
      Boxes[I].Parent.Pickable := false;
    end;
  Pickable := false;
  try
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
    begin
      T := Boxes[I].Parent;
      if (T <> nil) and (not IsDescendantOfAnySelected(T)) and
         (T.World <> nil) and T.HasWorldTransform then
      begin
        GravityUp := T.World.GravityUp;
        if GravityUp.IsZero then
          GravityUp := Vector3(0, 1, 0)
        else
          GravityUp := GravityUp.Normalize;
        DownDir := -GravityUp;

        BBox := T.WorldBoundingBox;
        if not BBox.IsEmpty then
        begin
          RayOrigin := BBox.Center;
          HalfHeight := 0.5 * (
            Abs(GravityUp.X) * BBox.SizeX +
            Abs(GravityUp.Y) * BBox.SizeY +
            Abs(GravityUp.Z) * BBox.SizeZ);
        end else
        begin
          RayOrigin := T.LocalToWorld(TVector3.Zero);
          HalfHeight := 0;
        end;

        RayHit := T.World.WorldRay(RayOrigin, DownDir);
        if RayHit <> nil then
        try
          if RayHit.Transform <> nil then
          begin
            HitDistance := RayHit.Distance;

            if AlignToNormal then
            begin
              if (RayHit.Count > 0) and (RayHit.First.Triangle <> nil) and
                 (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
                WorldNormal := RayHit.First.Item.LocalToWorldDirection(RayHit.First.Triangle^.SceneSpace.Normal)
              else
              if (RayHit.Count > 0) and (RayHit.First.Item <> nil) and
                 RayHit.First.Item.HasWorldTransform then
                WorldNormal := RayHit.First.Item.LocalToWorldDirection(Vector3(0, 1, 0))
              else
                WorldNormal := GravityUp;

              if not WorldNormal.IsZero then
              begin
                WorldNormal := WorldNormal.Normalize;
                if TVector3.DotProduct(WorldNormal, DownDir) > 0 then
                  WorldNormal := -WorldNormal;

                if (T.Parent <> nil) and T.Parent.HasWorldTransform then
                  TargetUpInParent := T.Parent.WorldToLocalDirection(WorldNormal).Normalize
                else
                  TargetUpInParent := WorldNormal;

                CurrentUpInParent := RotatePointAroundAxis(T.Rotation, Vector3(0, 1, 0)).Normalize;
                RotAngle := RotationAngleRadBetweenVectors(CurrentUpInParent, TargetUpInParent);
                if Abs(RotAngle) > 1e-4 then
                begin
                  RotAxis := TVector3.CrossProduct(CurrentUpInParent, TargetUpInParent);
                  if RotAxis.IsZero then
                    RotAxis := AnyOrthogonalVector(CurrentUpInParent);
                  T.Rotation := (QuatFromAxisAngle(RotAxis, RotAngle, true) *
                    QuatFromAxisAngle(T.Rotation, true)).ToAxisAngle;
                  Result := true;
                end;
              end;
            end;

            WorldDelta := DownDir * (HitDistance - HalfHeight);
            if not WorldDelta.IsZero then
            begin
              if (T.Parent <> nil) and T.Parent.HasWorldTransform then
                LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta)
              else
                LocalDelta := WorldDelta;

              T.Translation := T.Translation + LocalDelta;
              Result := true;
            end;
          end;
        finally
          FreeAndNil(RayHit);
        end;
      end;
    end;
  finally
    Pickable := SavedGizmoPickable;
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
      if Boxes[I].Parent <> nil then
        Boxes[I].Parent.Pickable := SavedPickable[I];
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.MirrorSelected(const Axis: T3DAxis): Boolean;
var
  Items: array of TCastleTransform;
  I, C, Count: Integer;
  T: TCastleTransform;
  PivotCoord, NewCoord: Single;
  Pos: TVector3;
  Rot: TVector4;
begin
  Result := false;
  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;
  if Count = 0 then Exit;

  if (Count > 1) and (FPivotMode = pmSelectionCenter) then
    PivotCoord := SelectionWorkingCenter[Axis]
  else
  if (Count > 1) and (FMainSelected <> nil) then
    PivotCoord := GetTransformWorkingPos(FMainSelected)[Axis]
  else
    PivotCoord := 0;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Pos := GetTransformWorkingPos(T);
    NewCoord := 2 * PivotCoord - Pos[Axis];
    if not SameValue(Pos[Axis], NewCoord) then
    begin
      Pos.Data[Axis] := NewCoord;
      SetTransformWorkingPos(T, Pos);
      Result := true;
    end;

    Rot := T.Rotation;
    if not SameValue(Rot.W, 0) then
    begin
      for C := 0 to 2 do
        if C <> Axis then
          Rot.Data[C] := -Rot.Data[C];
      if not TVector4.Equals(Rot, T.Rotation) then
      begin
        T.Rotation := Rot;
        Result := true;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.RotateSelected90(
  const Axis: T3DAxis; const Clockwise: Boolean): Boolean;
var
  SavedSnap, StepAngle: Single;
begin
  Result := false;
  if (SelectedCount = 0) or (FMainSelected = nil) then Exit;

  SavedSnap := FRotateSnap;
  FRotateSnap := 0;
  try
    if Clockwise then
      StepAngle := -0.5 * Pi
    else
      StepAngle := 0.5 * Pi;
    RotateSelected(Axis, StepAngle);
    GizmoHasTransformModifyEnd(Self);
    Result := true;
  finally
    FRotateSnap := SavedSnap;
  end;
end;

function TCastleTransformManipulate.RandomizeSelected(
  const MaxYawRad: Single; const ScaleMin, ScaleMax: Single;
  const MaxPositionJitter: Single): Boolean;
var
  I: Integer;
  T: TCastleTransform;
  YawAngle, ScaleFactor: Single;
  Jitter: TVector3;
begin
  Result := false;
  if SelectedCount = 0 then Exit;

  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      if MaxYawRad > 0 then
      begin
        YawAngle := (Random * 2.0 - 1.0) * MaxYawRad;
        if Abs(YawAngle) > 1e-6 then
        begin
          T.Rotation := (QuatFromAxisAngle(Vector3(0, 1, 0), YawAngle, true) *
            QuatFromAxisAngle(T.Rotation, true)).ToAxisAngle;
          Result := true;
        end;
      end;

      if (ScaleMin > 0) and (ScaleMax >= ScaleMin) and
         ((not SameValue(ScaleMin, 1.0)) or (not SameValue(ScaleMax, 1.0))) then
      begin
        ScaleFactor := ScaleMin + Random * (ScaleMax - ScaleMin);
        if Abs(ScaleFactor) >= 1e-4 then
        begin
          T.Scale := T.Scale * ScaleFactor;
          Result := true;
        end;
      end;

      if MaxPositionJitter > 0 then
      begin
        Jitter := Vector3(
          (Random * 2.0 - 1.0) * MaxPositionJitter,
          0,
          (Random * 2.0 - 1.0) * MaxPositionJitter);
        if not Jitter.IsZero then
        begin
          T.Translation := T.Translation + Jitter;
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.SnapSelectedToRay(
  const RayOrigin, RayDirection: TVector3;
  const SnapToNearestVertex: Boolean;
  const AlignToNormal: Boolean): Boolean;
var
  I, K: Integer;
  T: TCastleTransform;
  SavedPickable: array of Boolean;
  SavedGizmoPickable: Boolean;
  NormDir, HitWorldPoint, TargetWorldPoint, VWorld, BestVertexWorld: TVector3;
  PivotWorldPos, WorldDelta, LocalDelta: TVector3;
  WorldNormal, TargetUpInParent, CurrentUpInParent, RotAxis: TVector3;
  DistSqr, BestDistSqr, RotAngle: Single;
  Corners: TBoxCorners;
  RayHit: TRayCollision;
begin
  Result := false;
  if (SelectedCount = 0) or (FMainSelected = nil) or
     (FMainSelected.World = nil) or RayDirection.IsZero then
    Exit;

  NormDir := RayDirection.Normalize;
  SavedGizmoPickable := Pickable;
  SetLength(SavedPickable, FMaxSelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if Boxes[I].Parent <> nil then
    begin
      SavedPickable[I] := Boxes[I].Parent.Pickable;
      Boxes[I].Parent.Pickable := false;
    end;
  Pickable := false;
  try
    RayHit := FMainSelected.World.WorldRay(RayOrigin, NormDir);
    if RayHit <> nil then
    try
      if RayHit.Transform <> nil then
      begin
        HitWorldPoint := RayOrigin + NormDir * RayHit.Distance;
        TargetWorldPoint := HitWorldPoint;

        if SnapToNearestVertex and (RayHit.Count > 0) and
           (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
        begin
          if RayHit.First.Triangle <> nil then
          begin
            BestVertexWorld := RayHit.First.Item.LocalToWorld(
              RayHit.First.Triangle^.SceneSpace.Triangle.Data[0]);
            BestDistSqr := PointsDistanceSqr(BestVertexWorld, HitWorldPoint);
            for K := 1 to 2 do
            begin
              VWorld := RayHit.First.Item.LocalToWorld(
                RayHit.First.Triangle^.SceneSpace.Triangle.Data[K]);
              DistSqr := PointsDistanceSqr(VWorld, HitWorldPoint);
              if DistSqr < BestDistSqr then
              begin
                BestDistSqr := DistSqr;
                BestVertexWorld := VWorld;
              end;
            end;
            TargetWorldPoint := BestVertexWorld;
          end else
          if not RayHit.First.Item.BoundingBox.IsEmpty then
          begin
            RayHit.First.Item.BoundingBox.Corners(Corners);
            BestVertexWorld := RayHit.First.Item.LocalToWorld(Corners[0]);
            BestDistSqr := PointsDistanceSqr(BestVertexWorld, HitWorldPoint);
            for K := 1 to 7 do
            begin
              VWorld := RayHit.First.Item.LocalToWorld(Corners[K]);
              DistSqr := PointsDistanceSqr(VWorld, HitWorldPoint);
              if DistSqr < BestDistSqr then
              begin
                BestDistSqr := DistSqr;
                BestVertexWorld := VWorld;
              end;
            end;
            TargetWorldPoint := BestVertexWorld;
          end;
        end;

        if (SelectedCount > 1) and (FPivotMode = pmSelectionCenter) then
          PivotWorldPos := SelectionWorkingCenter
        else
        if FMainSelected.HasWorldTransform then
          PivotWorldPos := FMainSelected.LocalToWorld(TVector3.Zero)
        else
          PivotWorldPos := GetTransformWorkingPos(FMainSelected);

        WorldDelta := TargetWorldPoint - PivotWorldPos;

        WorldNormal := TVector3.Zero;
        if AlignToNormal then
        begin
          if (RayHit.Count > 0) and (RayHit.First.Triangle <> nil) and
             (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
            WorldNormal := RayHit.First.Item.LocalToWorldDirection(RayHit.First.Triangle^.SceneSpace.Normal)
          else
          if (RayHit.Count > 0) and (RayHit.First.Item <> nil) and
             RayHit.First.Item.HasWorldTransform then
            WorldNormal := RayHit.First.Item.LocalToWorldDirection(Vector3(0, 1, 0))
          else
            WorldNormal := FMainSelected.World.GravityUp;

          if not WorldNormal.IsZero then
          begin
            WorldNormal := WorldNormal.Normalize;
            if TVector3.DotProduct(WorldNormal, NormDir) > 0 then
              WorldNormal := -WorldNormal;
          end;
        end;

        for I := 0 to Integer(FMaxSelectedCount) - 1 do
        begin
          T := Boxes[I].Parent;
          if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
          begin
            if AlignToNormal and (not WorldNormal.IsZero) then
            begin
              if (T.Parent <> nil) and T.Parent.HasWorldTransform then
                TargetUpInParent := T.Parent.WorldToLocalDirection(WorldNormal).Normalize
              else
                TargetUpInParent := WorldNormal;

              CurrentUpInParent := RotatePointAroundAxis(T.Rotation, Vector3(0, 1, 0)).Normalize;
              RotAngle := RotationAngleRadBetweenVectors(CurrentUpInParent, TargetUpInParent);
              if Abs(RotAngle) > 1e-4 then
              begin
                RotAxis := TVector3.CrossProduct(CurrentUpInParent, TargetUpInParent);
                if RotAxis.IsZero then
                  RotAxis := AnyOrthogonalVector(CurrentUpInParent);
                T.Rotation := (QuatFromAxisAngle(RotAxis, RotAngle, true) *
                  QuatFromAxisAngle(T.Rotation, true)).ToAxisAngle;
                Result := true;
              end;
            end;

            if not WorldDelta.IsZero then
            begin
              if (T.Parent <> nil) and T.Parent.HasWorldTransform then
                LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta)
              else
                LocalDelta := WorldDelta;

              T.Translation := T.Translation + LocalDelta;
              Result := true;
            end;
          end;
        end;
      end;
    finally
      FreeAndNil(RayHit);
    end;
  finally
    Pickable := SavedGizmoPickable;
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
      if Boxes[I].Parent <> nil then
        Boxes[I].Parent.Pickable := SavedPickable[I];
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.MeasureSelectedDistance(
  out WorldDelta: TVector3): Single;
var
  T0, T1: TCastleTransform;
  Pos0, Pos1: TVector3;
begin
  WorldDelta := TVector3.Zero;
  Result := -1;
  if SelectedCount < 2 then
    Exit;

  T0 := Selected[0];
  T1 := Selected[1];
  if T0.HasWorldTransform then
    Pos0 := T0.LocalToWorld(TVector3.Zero)
  else
    Pos0 := GetTransformWorkingPos(T0);

  if T1.HasWorldTransform then
    Pos1 := T1.LocalToWorld(TVector3.Zero)
  else
    Pos1 := GetTransformWorkingPos(T1);

  WorldDelta := Pos1 - Pos0;
  Result := WorldDelta.Length;
end;

function TCastleTransformManipulate.MeasureRayDistanceFromSelected(
  const RayOrigin, RayDirection: TVector3;
  out HitWorldPoint, WorldDelta: TVector3): Single;
var
  I: Integer;
  SavedPickable: array of Boolean;
  SavedGizmoPickable: Boolean;
  NormDir, PivotWorldPos: TVector3;
  RayHit: TRayCollision;
begin
  HitWorldPoint := TVector3.Zero;
  WorldDelta := TVector3.Zero;
  Result := -1;
  if (SelectedCount = 0) or (FMainSelected = nil) or
     (FMainSelected.World = nil) or RayDirection.IsZero then
    Exit;

  NormDir := RayDirection.Normalize;
  SavedGizmoPickable := Pickable;
  SetLength(SavedPickable, FMaxSelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if Boxes[I].Parent <> nil then
    begin
      SavedPickable[I] := Boxes[I].Parent.Pickable;
      Boxes[I].Parent.Pickable := false;
    end;
  Pickable := false;
  try
    RayHit := FMainSelected.World.WorldRay(RayOrigin, NormDir);
    if RayHit <> nil then
    try
      if RayHit.Transform <> nil then
      begin
        HitWorldPoint := RayOrigin + NormDir * RayHit.Distance;
        if (SelectedCount > 1) and (FPivotMode = pmSelectionCenter) then
          PivotWorldPos := SelectionWorkingCenter
        else
        if FMainSelected.HasWorldTransform then
          PivotWorldPos := FMainSelected.LocalToWorld(TVector3.Zero)
        else
          PivotWorldPos := GetTransformWorkingPos(FMainSelected);

        WorldDelta := HitWorldPoint - PivotWorldPos;
        Result := WorldDelta.Length;
      end;
    finally
      FreeAndNil(RayHit);
    end;
  finally
    Pickable := SavedGizmoPickable;
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
      if Boxes[I].Parent <> nil then
        Boxes[I].Parent.Pickable := SavedPickable[I];
  end;
end;

function TCastleTransformManipulate.ProjectSelectedAlongDirection(
  const WorldDirection: TVector3; const AlignToNormal: Boolean): Boolean;
var
  I: Integer;
  T: TCastleTransform;
  SavedPickable: array of Boolean;
  SavedGizmoPickable: Boolean;
  NormDir, RayOrigin, WorldDelta, LocalDelta: TVector3;
  WorldNormal, TargetUpInParent, CurrentUpInParent, RotAxis: TVector3;
  BBox: TBox3D;
  HalfExtent, HitDistance, RotAngle: Single;
  RayHit: TRayCollision;
begin
  Result := false;
  if (SelectedCount = 0) or WorldDirection.IsZero then Exit;

  NormDir := WorldDirection.Normalize;
  SavedGizmoPickable := Pickable;
  SetLength(SavedPickable, FMaxSelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if Boxes[I].Parent <> nil then
    begin
      SavedPickable[I] := Boxes[I].Parent.Pickable;
      Boxes[I].Parent.Pickable := false;
    end;
  Pickable := false;
  try
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
    begin
      T := Boxes[I].Parent;
      if (T <> nil) and (not IsDescendantOfAnySelected(T)) and
         (T.World <> nil) and T.HasWorldTransform then
      begin
        BBox := T.WorldBoundingBox;
        if not BBox.IsEmpty then
        begin
          RayOrigin := BBox.Center;
          HalfExtent := 0.5 * (
            Abs(NormDir.X) * BBox.SizeX +
            Abs(NormDir.Y) * BBox.SizeY +
            Abs(NormDir.Z) * BBox.SizeZ);
        end else
        begin
          RayOrigin := T.LocalToWorld(TVector3.Zero);
          HalfExtent := 0;
        end;

        RayHit := T.World.WorldRay(RayOrigin, NormDir);
        if RayHit <> nil then
        try
          if RayHit.Transform <> nil then
          begin
            HitDistance := RayHit.Distance;

            if AlignToNormal then
            begin
              if (RayHit.Count > 0) and (RayHit.First.Triangle <> nil) and
                 (RayHit.First.Item <> nil) and RayHit.First.Item.HasWorldTransform then
                WorldNormal := RayHit.First.Item.LocalToWorldDirection(RayHit.First.Triangle^.SceneSpace.Normal)
              else
              if (RayHit.Count > 0) and (RayHit.First.Item <> nil) and
                 RayHit.First.Item.HasWorldTransform then
                WorldNormal := RayHit.First.Item.LocalToWorldDirection(Vector3(0, 1, 0))
              else
                WorldNormal := -NormDir;

              if not WorldNormal.IsZero then
              begin
                WorldNormal := WorldNormal.Normalize;
                if TVector3.DotProduct(WorldNormal, NormDir) > 0 then
                  WorldNormal := -WorldNormal;

                if (T.Parent <> nil) and T.Parent.HasWorldTransform then
                  TargetUpInParent := T.Parent.WorldToLocalDirection(WorldNormal).Normalize
                else
                  TargetUpInParent := WorldNormal;

                CurrentUpInParent := RotatePointAroundAxis(T.Rotation, Vector3(0, 1, 0)).Normalize;
                RotAngle := RotationAngleRadBetweenVectors(CurrentUpInParent, TargetUpInParent);
                if Abs(RotAngle) > 1e-4 then
                begin
                  RotAxis := TVector3.CrossProduct(CurrentUpInParent, TargetUpInParent);
                  if RotAxis.IsZero then
                    RotAxis := AnyOrthogonalVector(CurrentUpInParent);
                  T.Rotation := (QuatFromAxisAngle(RotAxis, RotAngle, true) *
                    QuatFromAxisAngle(T.Rotation, true)).ToAxisAngle;
                  Result := true;
                end;
              end;
            end;

            WorldDelta := NormDir * (HitDistance - HalfExtent);
            if not WorldDelta.IsZero then
            begin
              if (T.Parent <> nil) and T.Parent.HasWorldTransform then
                LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta)
              else
                LocalDelta := WorldDelta;

              T.Translation := T.Translation + LocalDelta;
              Result := true;
            end;
          end;
        finally
          FreeAndNil(RayHit);
        end;
      end;
    end;
  finally
    Pickable := SavedGizmoPickable;
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
      if Boxes[I].Parent <> nil then
        Boxes[I].Parent.Pickable := SavedPickable[I];
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.DistributeSelectedGaps(const Axis: T3DAxis): Boolean;
var
  Items: array of TCastleTransform;
  ItemMin, ItemMax: array of Single;
  Count, I, J: Integer;
  T, TempT: TCastleTransform;
  BBox: TBox3D;
  Pos: TVector3;
  TempVal, TotalExtent, OverallSpan, Gap, PrevMax, DeltaAxis: Single;
begin
  Result := false;
  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 3 then Exit;

  for I := 0 to Count - 2 do
    for J := I + 1 to Count - 1 do
      if GetTransformWorkingPos(Items[J])[Axis] < GetTransformWorkingPos(Items[I])[Axis] then
      begin
        TempT := Items[I];
        Items[I] := Items[J];
        Items[J] := TempT;
      end;

  SetLength(ItemMin, Count);
  SetLength(ItemMax, Count);
  TotalExtent := 0;
  for I := 0 to Count - 1 do
  begin
    Pos := GetTransformWorkingPos(Items[I]);
    if Items[I].HasWorldTransform then
      BBox := Items[I].WorldBoundingBox
    else
      BBox := Items[I].BoundingBox;

    if not BBox.IsEmpty then
    begin
      ItemMin[I] := BBox.Min[Axis];
      ItemMax[I] := BBox.Max[Axis];
    end else
    begin
      ItemMin[I] := Pos[Axis];
      ItemMax[I] := Pos[Axis];
    end;
    TotalExtent := TotalExtent + (ItemMax[I] - ItemMin[I]);
  end;

  OverallSpan := ItemMax[Count - 1] - ItemMin[0];
  Gap := (OverallSpan - TotalExtent) / (Count - 1);
  PrevMax := ItemMax[0];

  for I := 1 to Count - 2 do
  begin
    Pos := GetTransformWorkingPos(Items[I]);
    DeltaAxis := (PrevMax + Gap) - ItemMin[I];
    if not SameValue(DeltaAxis, 0, 1e-5) then
    begin
      Pos.Data[Axis] := Pos[Axis] + DeltaAxis;
      SetTransformWorkingPos(Items[I], Pos);
      Result := true;
    end;
    TempVal := ItemMax[I] - ItemMin[I];
    PrevMax := (PrevMax + Gap) + TempVal;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.SnapSelectedRotationAndScaleToGrid: Boolean;
var
  I, C: Integer;
  T: TCastleTransform;
  Rot: TVector4;
  Scl: TVector3;
  SnappedAngle, SnappedScale: Single;
begin
  Result := false;
  if (SelectedCount = 0) or ((FRotateSnap <= 0) and (FScaleSnap <= 0)) then
    Exit;

  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      if FRotateSnap > 0 then
      begin
        Rot := T.Rotation;
        SnappedAngle := Round(Rot.W / FRotateSnap) * FRotateSnap;
        if not SameValue(Rot.W, SnappedAngle, 1e-5) then
        begin
          Rot.W := SnappedAngle;
          T.Rotation := Rot;
          Result := true;
        end;
      end;

      if FScaleSnap > 0 then
      begin
        Scl := T.Scale;
        for C := 0 to 2 do
        begin
          SnappedScale := Round(Scl.Data[C] / FScaleSnap) * FScaleSnap;
          if SameValue(SnappedScale, 0, 1e-5) then
            SnappedScale := FScaleSnap;
          Scl.Data[C] := SnappedScale;
        end;
        if not TVector3.Equals(Scl, T.Scale) then
        begin
          T.Scale := Scl;
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.SwapSelectedPositions: Boolean;
var
  Items: array of TCastleTransform;
  OrigPos: array of TVector3;
  I, Count: Integer;
  T: TCastleTransform;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  SetLength(OrigPos, Count);
  for I := 0 to Count - 1 do
    OrigPos[I] := GetTransformWorkingPos(Items[I]);

  for I := 0 to Count - 1 do
    if not TVector3.Equals(OrigPos[I], OrigPos[(I + 1) mod Count]) then
    begin
      SetTransformWorkingPos(Items[I], OrigPos[(I + 1) mod Count]);
      Result := true;
    end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.MatchSelectedSize(const Axis: Integer): Boolean;
var
  Items: array of TCastleTransform;
  I, A, Count: Integer;
  T: TCastleTransform;
  RefBox, CurBox: TBox3D;
  RefSizes, CurSizes, NewScale: TVector3;
begin
  Result := false;
  if (Axis > 2) or (SelectedCount < 2) then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if Items[0].HasWorldTransform then
    RefBox := Items[0].WorldBoundingBox
  else
    RefBox := Items[0].BoundingBox;
  if RefBox.IsEmpty then Exit;
  RefSizes := RefBox.Size;

  for I := 1 to Count - 1 do
  begin
    if Items[I].HasWorldTransform then
      CurBox := Items[I].WorldBoundingBox
    else
      CurBox := Items[I].BoundingBox;
    if CurBox.IsEmpty then Continue;

    CurSizes := CurBox.Size;
    NewScale := Items[I].Scale;

    if Axis >= 0 then
    begin
      if (RefSizes[Axis] > 1e-5) and (CurSizes[Axis] > 1e-5) then
        NewScale.Data[Axis] := NewScale.Data[Axis] * (RefSizes[Axis] / CurSizes[Axis]);
    end else
    begin
      for A := 0 to 2 do
        if (RefSizes[A] > 1e-5) and (CurSizes[A] > 1e-5) then
          NewScale.Data[A] := NewScale.Data[A] * (RefSizes[A] / CurSizes[A]);
    end;

    if not TVector3.Equals(NewScale, Items[I].Scale) then
    begin
      Items[I].Scale := NewScale;
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.LookAtWorldPoint(
  const TargetWorldPos: TVector3): Boolean;

  function OrientTransformTowards(const T: TCastleTransform;
    const TargetPos: TVector3): Boolean;
  var
    CurPos, CurDir, CurUp, NewDir, NewUp, GravityUp, Side: TVector3;
  begin
    Result := false;
    if T.HasWorldTransform then
      T.GetWorldView(CurPos, CurDir, CurUp)
    else
    begin
      CurPos := T.Translation;
      CurDir := T.Direction;
      CurUp := T.Up;
    end;

    NewDir := TargetPos - CurPos;
    if NewDir.IsZero(1e-5) then Exit;
    NewDir := NewDir.Normalize;

    if T.World <> nil then
      GravityUp := T.World.GravityUp
    else
      GravityUp := Vector3(0, 1, 0);

    Side := TVector3.CrossProduct(NewDir, GravityUp);
    if Side.IsZero(1e-4) then
      Side := TVector3.CrossProduct(NewDir, CurUp);
    if Side.IsZero(1e-4) then
      Side := TVector3.CrossProduct(NewDir, Vector3(0, 0, 1));
    if Side.IsZero(1e-4) then
      Side := Vector3(1, 0, 0);
    NewUp := TVector3.CrossProduct(Side, NewDir).Normalize;

    if (not TVector3.Equals(NewDir, CurDir)) or
       (not TVector3.Equals(NewUp, CurUp)) then
    begin
      if T.HasWorldTransform then
        T.SetWorldView(CurPos, NewDir, NewUp)
      else
        T.SetView(CurPos, NewDir, NewUp);
      Result := true;
    end;
  end;

var
  I: Integer;
  T: TCastleTransform;
begin
  Result := false;
  if SelectedCount = 0 then Exit;

  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
      if OrientTransformTowards(T, TargetWorldPos) then
        Result := true;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.AimSelectedAtPrimary: Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  TargetPos, CurPos, CurDir, CurUp, NewDir, NewUp, GravityUp, Side: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  TargetPos := GetTransformWorkingPos(Items[0]);

  for I := 1 to Count - 1 do
  begin
    T := Items[I];
    if T.HasWorldTransform then
      T.GetWorldView(CurPos, CurDir, CurUp)
    else
    begin
      CurPos := T.Translation;
      CurDir := T.Direction;
      CurUp := T.Up;
    end;

    NewDir := TargetPos - CurPos;
    if NewDir.IsZero(1e-5) then Continue;
    NewDir := NewDir.Normalize;

    if T.World <> nil then
      GravityUp := T.World.GravityUp
    else
      GravityUp := Vector3(0, 1, 0);

    Side := TVector3.CrossProduct(NewDir, GravityUp);
    if Side.IsZero(1e-4) then
      Side := TVector3.CrossProduct(NewDir, CurUp);
    if Side.IsZero(1e-4) then
      Side := TVector3.CrossProduct(NewDir, Vector3(0, 0, 1));
    if Side.IsZero(1e-4) then
      Side := Vector3(1, 0, 0);
    NewUp := TVector3.CrossProduct(Side, NewDir).Normalize;

    if (not TVector3.Equals(NewDir, CurDir)) or
       (not TVector3.Equals(NewUp, CurUp)) then
    begin
      if T.HasWorldTransform then
        T.SetWorldView(CurPos, NewDir, NewUp)
      else
        T.SetView(CurPos, NewDir, NewUp);
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.AlignSelectedBounds(
  const Axis: T3DAxis; const UseMaxFace: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ItemBoxes: array of TBox3D;
  I, Count: Integer;
  T: TCastleTransform;
  BBox: TBox3D;
  TargetEdge, CurFace, Delta: Single;
  Pos: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  SetLength(ItemBoxes, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      if T.HasWorldTransform then
        BBox := T.WorldBoundingBox
      else
        BBox := T.BoundingBox;
      if not BBox.IsEmpty then
      begin
        Items[Count] := T;
        ItemBoxes[Count] := BBox;
        Inc(Count);
      end;
    end;
  end;

  if Count < 2 then Exit;

  if UseMaxFace then
  begin
    TargetEdge := ItemBoxes[0].Data[1][Axis];
    for I := 1 to Count - 1 do
      if ItemBoxes[I].Data[1][Axis] > TargetEdge then
        TargetEdge := ItemBoxes[I].Data[1][Axis];
  end else
  begin
    TargetEdge := ItemBoxes[0].Data[0][Axis];
    for I := 1 to Count - 1 do
      if ItemBoxes[I].Data[0][Axis] < TargetEdge then
        TargetEdge := ItemBoxes[I].Data[0][Axis];
  end;

  for I := 0 to Count - 1 do
  begin
    if UseMaxFace then
      CurFace := ItemBoxes[I].Data[1][Axis]
    else
      CurFace := ItemBoxes[I].Data[0][Axis];

    Delta := TargetEdge - CurFace;
    if not SameValue(Delta, 0.0, 1e-5) then
    begin
      Pos := GetTransformWorkingPos(Items[I]);
      Pos.Data[Axis] := Pos.Data[Axis] + Delta;
      SetTransformWorkingPos(Items[I], Pos);
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.MatchSelectedRotation: Boolean;
begin
  Result := MatchSelectedTransform(false, true, false);
end;

function TCastleTransformManipulate.MatchSelectedTransform(
  const MatchPos, MatchRot, MatchScale: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T, Primary: TCastleTransform;
  PrimaryPos, PrimaryDir, PrimaryUp, PrimaryScale: TVector3;
  CurPos, CurDir, CurUp, NewPos, NewDir, NewUp: TVector3;
begin
  Result := false;
  if (not MatchPos) and (not MatchRot) and (not MatchScale) then Exit;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  Primary := Items[0];
  if Primary.HasWorldTransform then
    Primary.GetWorldView(PrimaryPos, PrimaryDir, PrimaryUp)
  else
  begin
    PrimaryPos := Primary.Translation;
    PrimaryDir := Primary.Direction;
    PrimaryUp := Primary.Up;
  end;
  PrimaryScale := Primary.Scale;

  for I := 1 to Count - 1 do
  begin
    T := Items[I];
    if MatchPos or MatchRot then
    begin
      if T.HasWorldTransform then
        T.GetWorldView(CurPos, CurDir, CurUp)
      else
      begin
        CurPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;

      if MatchPos then
        NewPos := PrimaryPos
      else
        NewPos := CurPos;

      if MatchRot then
      begin
        NewDir := PrimaryDir;
        NewUp := PrimaryUp;
      end else
      begin
        NewDir := CurDir;
        NewUp := CurUp;
      end;

      if (not TVector3.Equals(NewPos, CurPos)) or
         (not TVector3.Equals(NewDir, CurDir)) or
         (not TVector3.Equals(NewUp, CurUp)) then
      begin
        if MatchRot then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(NewPos, NewDir, NewUp)
          else
            T.SetView(NewPos, NewDir, NewUp);
        end else
          SetTransformWorkingPos(T, NewPos);
        Result := true;
      end;
    end;

    if MatchScale and (not TVector3.Equals(T.Scale, PrimaryScale)) then
    begin
      T.Scale := PrimaryScale;
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInCircle(
  const Radius: Single; const TotalAngleDeg: Single;
  const OrientToCenter: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, NewPos, CurDir, CurUp, NewDir, NewUp, GravityUp, Side: TVector3;
  EffRadius, SumDist, AngleStepRad, Angle, SinA, CosA: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if FPivotMode = pmPrimarySelected then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  if Radius > 0 then
    EffRadius := Radius
  else
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      SumDist := SumDist + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    EffRadius := SumDist / Count;
    if EffRadius < 1e-4 then
      EffRadius := 5.0;
  end;

  if SameValue(Abs(TotalAngleDeg), 360.0, 1e-3) or (Abs(TotalAngleDeg) >= 360.0) then
    AngleStepRad := DegToRad(TotalAngleDeg) / Count
  else
    AngleStepRad := DegToRad(TotalAngleDeg) / (Count - 1);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Angle := I * AngleStepRad;
    SinCos(Angle, SinA, CosA);

    CurPos := GetTransformWorkingPos(T);
    NewPos := Vector3(
      CenterPos.X + SinA * EffRadius,
      CurPos.Y,
      CenterPos.Z + CosA * EffRadius);

    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientToCenter then
    begin
      if T.HasWorldTransform then
        T.GetWorldView(CurPos, CurDir, CurUp)
      else
      begin
        CurPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;

      NewDir := Vector3(CenterPos.X - CurPos.X, 0, CenterPos.Z - CurPos.Z);
      if not NewDir.IsZero(1e-5) then
      begin
        NewDir := NewDir.Normalize;
        if T.World <> nil then
          GravityUp := T.World.GravityUp
        else
          GravityUp := Vector3(0, 1, 0);

        Side := TVector3.CrossProduct(NewDir, GravityUp);
        if Side.IsZero(1e-4) then
          Side := TVector3.CrossProduct(NewDir, CurUp);
        if Side.IsZero(1e-4) then
          Side := Vector3(1, 0, 0);
        NewUp := TVector3.CrossProduct(Side, NewDir).Normalize;

        if (not TVector3.Equals(NewDir, CurDir)) or
           (not TVector3.Equals(NewUp, CurUp)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurPos, NewDir, NewUp)
          else
            T.SetView(CurPos, NewDir, NewUp);
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInGrid(
  const ColumnsX, RowsZ: Integer; const Spacing: TVector3;
  const CenterGrid: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, A, Count, ColsX, EffRowsZ, LayerSize, LayersY, UsedCols, UsedRows: Integer;
  LayerIdx, Rem, RowZ, ColX: Integer;
  T: TCastleTransform;
  BBox: TBox3D;
  MaxExtent, EffSpacing, GridSpan, OriginPos, CurPos, NewPos: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if ColumnsX > 0 then
    ColsX := ColumnsX
  else
    ColsX := Max(1, Ceil(Sqrt(Count)));

  if RowsZ > 0 then
    EffRowsZ := RowsZ
  else
    EffRowsZ := Max(1, Ceil(Count / ColsX));

  LayerSize := Max(1, ColsX * EffRowsZ);
  LayersY := Max(1, Ceil(Count / LayerSize));

  MaxExtent := TVector3.Zero;
  for I := 0 to Count - 1 do
  begin
    if Items[I].HasWorldTransform then
      BBox := Items[I].WorldBoundingBox
    else
      BBox := Items[I].BoundingBox;
    if not BBox.IsEmpty then
      for A := 0 to 2 do
        if BBox.Size[A] > MaxExtent[A] then
          MaxExtent.Data[A] := BBox.Size[A];
  end;

  for A := 0 to 2 do
  begin
    if Spacing[A] > 0 then
      EffSpacing.Data[A] := Spacing[A]
    else if MaxExtent[A] > 1e-4 then
      EffSpacing.Data[A] := MaxExtent[A] * 1.25
    else
      EffSpacing.Data[A] := 2.0;
  end;

  UsedCols := Min(Count, ColsX);
  UsedRows := Min(EffRowsZ, Max(1, Ceil(Count / ColsX)));
  GridSpan := Vector3(
    (UsedCols - 1) * EffSpacing.X,
    (LayersY - 1) * EffSpacing.Y,
    (UsedRows - 1) * EffSpacing.Z);

  if CenterGrid then
    OriginPos := SelectionWorkingCenter - GridSpan * 0.5
  else
    OriginPos := GetTransformWorkingPos(Items[0]);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    LayerIdx := I div LayerSize;
    Rem := I mod LayerSize;
    RowZ := Rem div ColsX;
    ColX := Rem mod ColsX;

    NewPos := OriginPos + Vector3(
      ColX * EffSpacing.X,
      LayerIdx * EffSpacing.Y,
      RowZ * EffSpacing.Z);
    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ScaleSelectedPositionsFromPivot(
  const Factor: TVector3): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  PivotPos, CurPos, NewPos: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if FPivotMode = pmPrimarySelected then
    PivotPos := GetTransformWorkingPos(Items[0])
  else
    PivotPos := SelectionWorkingCenter;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    NewPos := PivotPos + (CurPos - PivotPos) * Factor;
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ResetSelectedTransform(
  const ResetTrans, ResetRot, ResetScale: Boolean): Boolean;
var
  I: Integer;
  T: TCastleTransform;
begin
  Result := false;
  if (not ResetTrans) and (not ResetRot) and (not ResetScale) then Exit;
  if SelectedCount = 0 then Exit;

  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if T = nil then Continue;

    if ResetTrans and (not TVector3.Equals(T.Translation, TVector3.Zero)) then
    begin
      T.Translation := TVector3.Zero;
      Result := true;
    end;

    if ResetRot and (not SameValue(T.Rotation.W, 0.0, 1e-5)) then
    begin
      T.Rotation := Vector4(0, 1, 0, 0);
      Result := true;
    end;

    if ResetScale and (not TVector3.Equals(T.Scale, Vector3(1, 1, 1))) then
    begin
      T.Scale := Vector3(1, 1, 1);
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedAlongLine(
  const StartWorldPos, EndWorldPos: TVector3;
  const OrientAlongLine: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  Factor: Single;
  CurPos, NewPos, LineDir, CurWorldPos, CurDir, CurUp, GravityUp, Side, NewUp: TVector3;
  HasLineDir: Boolean;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  LineDir := EndWorldPos - StartWorldPos;
  HasLineDir := not LineDir.IsZero(1e-5);
  if HasLineDir then
    LineDir := LineDir.Normalize;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Factor := Single(I) / Single(Count - 1);
    NewPos := Lerp(Factor, StartWorldPos, EndWorldPos);
    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientAlongLine and HasLineDir then
    begin
      if T.HasWorldTransform then
        T.GetWorldView(CurWorldPos, CurDir, CurUp)
      else
      begin
        CurWorldPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;

      if T.World <> nil then
        GravityUp := T.World.GravityUp
      else
        GravityUp := Vector3(0, 1, 0);

      Side := TVector3.CrossProduct(LineDir, GravityUp);
      if Side.IsZero(1e-4) then
        Side := TVector3.CrossProduct(LineDir, CurUp);
      if Side.IsZero(1e-4) then
        Side := TVector3.CrossProduct(LineDir, Vector3(0, 0, 1));
      if Side.IsZero(1e-4) then
        Side := Vector3(1, 0, 0);
      NewUp := TVector3.CrossProduct(Side, LineDir).Normalize;

      if (not TVector3.Equals(LineDir, CurDir)) or
         (not TVector3.Equals(NewUp, CurUp)) then
      begin
        if T.HasWorldTransform then
          T.SetWorldView(CurWorldPos, LineDir, NewUp)
        else
          T.SetView(CurWorldPos, LineDir, NewUp);
        Result := true;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedBetweenEndpoints(
  const OrientAlongLine: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  StartPos, EndPos: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  StartPos := GetTransformWorkingPos(Items[0]);
  EndPos := GetTransformWorkingPos(Items[Count - 1]);
  Result := ArrangeSelectedAlongLine(StartPos, EndPos, OrientAlongLine);
end;

function TCastleTransformManipulate.SeparateOverlappingSelected(
  const MinPadding: Single; const HorizontalOnly: Boolean;
  const MaxIterations: Integer): Boolean;
var
  Items: array of TCastleTransform;
  I, J, Iter, Count, ActualMaxIter, BestAxis: Integer;
  T: TCastleTransform;
  BoxA, BoxB: TBox3D;
  CenterA, CenterB, PushVec, PosA, PosB: TVector3;
  OverlapX, OverlapY, OverlapZ, BestOverlap, SignDir, HalfPush, Pad: Single;
  AnyMovedInPass: Boolean;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  Pad := Max(0.0, MinPadding);
  ActualMaxIter := Max(1, MaxIterations);

  for Iter := 1 to ActualMaxIter do
  begin
    AnyMovedInPass := false;
    for I := 0 to Count - 2 do
      for J := I + 1 to Count - 1 do
      begin
        if Items[I].HasWorldTransform then
          BoxA := Items[I].WorldBoundingBox
        else
          BoxA := Items[I].BoundingBox;

        if Items[J].HasWorldTransform then
          BoxB := Items[J].WorldBoundingBox
        else
          BoxB := Items[J].BoundingBox;

        if BoxA.IsEmpty or BoxB.IsEmpty then Continue;

        OverlapX := Min(BoxA.Data[1].X, BoxB.Data[1].X) - Max(BoxA.Data[0].X, BoxB.Data[0].X) + Pad;
        if OverlapX <= 1e-4 then Continue;

        OverlapZ := Min(BoxA.Data[1].Z, BoxB.Data[1].Z) - Max(BoxA.Data[0].Z, BoxB.Data[0].Z) + Pad;
        if OverlapZ <= 1e-4 then Continue;

        OverlapY := Min(BoxA.Data[1].Y, BoxB.Data[1].Y) - Max(BoxA.Data[0].Y, BoxB.Data[0].Y) + Pad;
        if OverlapY <= 1e-4 then Continue;

        CenterA := BoxA.Center;
        CenterB := BoxB.Center;

        if HorizontalOnly then
        begin
          if OverlapX <= OverlapZ then
          begin
            BestAxis := 0;
            BestOverlap := OverlapX;
          end else
          begin
            BestAxis := 2;
            BestOverlap := OverlapZ;
          end;
        end else
        begin
          BestAxis := 0;
          BestOverlap := OverlapX;
          if OverlapY < BestOverlap then
          begin
            BestAxis := 1;
            BestOverlap := OverlapY;
          end;
          if OverlapZ < BestOverlap then
          begin
            BestAxis := 2;
            BestOverlap := OverlapZ;
          end;
        end;

        if CenterB[BestAxis] > CenterA[BestAxis] + 1e-4 then
          SignDir := 1.0
        else if CenterB[BestAxis] < CenterA[BestAxis] - 1e-4 then
          SignDir := -1.0
        else if J > I then
          SignDir := 1.0
        else
          SignDir := -1.0;

        HalfPush := 0.5 * BestOverlap * SignDir;
        PushVec := TVector3.Zero;
        PushVec.Data[BestAxis] := HalfPush;

        PosA := GetTransformWorkingPos(Items[I]);
        PosB := GetTransformWorkingPos(Items[J]);
        SetTransformWorkingPos(Items[I], PosA - PushVec);
        SetTransformWorkingPos(Items[J], PosB + PushVec);

        AnyMovedInPass := true;
        Result := true;
      end;

    if not AnyMovedInPass then
      Break;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ApplyProgressiveTransformSelected(
  const StartScale, EndScale: TVector3; const ApplyScaleGradient: Boolean;
  const Axis: T3DAxis; const StepAngleRad: Single): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  Factor, AngleRad: Single;
  NewScale, AxisVec: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;
  if (not ApplyScaleGradient) and SameValue(StepAngleRad, 0.0, 1e-6) then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  AxisVec := TVector3.One[Axis];

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Factor := Single(I) / Single(Count - 1);

    if ApplyScaleGradient then
    begin
      NewScale := Lerp(Factor, StartScale, EndScale);
      if (Abs(NewScale.X) >= 1e-4) and
         (Abs(NewScale.Y) >= 1e-4) and
         (Abs(NewScale.Z) >= 1e-4) and
         (not TVector3.Equals(NewScale, T.Scale)) then
      begin
        T.Scale := NewScale;
        Result := true;
      end;
    end;

    if (I > 0) and (not SameValue(StepAngleRad, 0.0, 1e-6)) then
    begin
      AngleRad := Single(I) * StepAngleRad;
      if FCoordSpace = csWorld then
        T.Rotation := (
          QuatFromAxisAngle(AxisVec, AngleRad, true) *
          QuatFromAxisAngle(T.Rotation, true)).ToAxisAngle
      else
        T.Rotation := (
          QuatFromAxisAngle(T.Rotation, true) *
          QuatFromAxisAngle(AxisVec, AngleRad, true)).ToAxisAngle;
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedAlongWaypoints(
  const Waypoints: array of TVector3; const OrientAlongPath: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  CumDist: array of Single;
  I, SegIdx, Count, WCount: Integer;
  T: TCastleTransform;
  TotalLen, TargetDist, SegLen, SegT: Single;
  CurPos, NewPos, SegDir, CurWorldPos, CurDir, CurUp, GravityUp, Side, NewUp: TVector3;
  HasSegDir: Boolean;
begin
  Result := false;
  WCount := Length(Waypoints);
  if (SelectedCount < 2) or (WCount < 2) then Exit;

  if WCount = 2 then
    Exit(ArrangeSelectedAlongLine(Waypoints[0], Waypoints[1], OrientAlongPath));

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  SetLength(CumDist, WCount);
  CumDist[0] := 0.0;
  for I := 1 to WCount - 1 do
    CumDist[I] := CumDist[I - 1] + PointsDistance(Waypoints[I - 1], Waypoints[I]);
  TotalLen := CumDist[WCount - 1];

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    if TotalLen <= 1e-6 then
    begin
      NewPos := Waypoints[0];
      HasSegDir := false;
      SegDir := Vector3(0, 0, -1);
    end else
    begin
      TargetDist := (Single(I) / Single(Count - 1)) * TotalLen;
      SegIdx := 0;
      while (SegIdx < WCount - 2) and (CumDist[SegIdx + 1] < TargetDist) do
        Inc(SegIdx);

      SegLen := CumDist[SegIdx + 1] - CumDist[SegIdx];
      if SegLen > 1e-6 then
        SegT := Clamped((TargetDist - CumDist[SegIdx]) / SegLen, 0.0, 1.0)
      else
        SegT := 0.0;

      NewPos := Lerp(SegT, Waypoints[SegIdx], Waypoints[SegIdx + 1]);
      SegDir := Waypoints[SegIdx + 1] - Waypoints[SegIdx];
      HasSegDir := not SegDir.IsZero(1e-5);
      if HasSegDir then
        SegDir := SegDir.Normalize;
    end;

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientAlongPath and HasSegDir then
    begin
      if T.HasWorldTransform then
        T.GetWorldView(CurWorldPos, CurDir, CurUp)
      else
      begin
        CurWorldPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;

      if T.World <> nil then
        GravityUp := T.World.GravityUp
      else
        GravityUp := Vector3(0, 1, 0);

      Side := TVector3.CrossProduct(SegDir, GravityUp);
      if Side.IsZero(1e-4) then
        Side := TVector3.CrossProduct(SegDir, CurUp);
      if Side.IsZero(1e-4) then
        Side := TVector3.CrossProduct(SegDir, Vector3(0, 0, 1));
      if Side.IsZero(1e-4) then
        Side := Vector3(1, 0, 0);
      NewUp := TVector3.CrossProduct(Side, SegDir).Normalize;

      if (not TVector3.Equals(SegDir, CurDir)) or
         (not TVector3.Equals(NewUp, CurUp)) then
      begin
        if T.HasWorldTransform then
          T.SetWorldView(CurWorldPos, SegDir, NewUp)
        else
          T.SetView(CurWorldPos, SegDir, NewUp);
        Result := true;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInHelix(
  const StartRadius, EndRadius, HeightSpan: Single; const Turns: Single;
  const OrientToCenter: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, NewPos, CurDir, CurUp, NewDir, NewUp, GravityUp, Side: TVector3;
  EffStartR, EffEndR, EffTurns, Factor, CurRadius, BaseY, Angle, SinA, CosA, SumDist: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if FPivotMode = pmPrimarySelected then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  if StartRadius > 0 then
    EffStartR := StartRadius
  else
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      SumDist := SumDist + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    EffStartR := SumDist / Count;
    if EffStartR < 1e-4 then
      EffStartR := 5.0;
  end;

  if EndRadius >= 0 then
    EffEndR := EndRadius
  else
    EffEndR := EffStartR;

  if SameValue(Turns, 0.0, 1e-5) then
    EffTurns := 1.0
  else
    EffTurns := Turns;

  if FPivotMode = pmPrimarySelected then
    BaseY := CenterPos.Y
  else
    BaseY := CenterPos.Y - 0.5 * HeightSpan;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Factor := Single(I) / Single(Count - 1);
    CurRadius := Lerp(Factor, EffStartR, EffEndR);
    Angle := Factor * EffTurns * 2.0 * Pi;
    SinCos(Angle, SinA, CosA);

    CurPos := GetTransformWorkingPos(T);
    NewPos := Vector3(
      CenterPos.X + SinA * CurRadius,
      BaseY + Factor * HeightSpan,
      CenterPos.Z + CosA * CurRadius);

    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientToCenter then
    begin
      if T.HasWorldTransform then
        T.GetWorldView(CurPos, CurDir, CurUp)
      else
      begin
        CurPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;

      NewDir := Vector3(CenterPos.X - CurPos.X, 0, CenterPos.Z - CurPos.Z);
      if not NewDir.IsZero(1e-5) then
      begin
        NewDir := NewDir.Normalize;
        if T.World <> nil then
          GravityUp := T.World.GravityUp
        else
          GravityUp := Vector3(0, 1, 0);

        Side := TVector3.CrossProduct(NewDir, GravityUp);
        if Side.IsZero(1e-4) then
          Side := TVector3.CrossProduct(NewDir, CurUp);
        if Side.IsZero(1e-4) then
          Side := Vector3(1, 0, 0);
        NewUp := TVector3.CrossProduct(Side, NewDir).Normalize;

        if (not TVector3.Equals(NewDir, CurDir)) or
           (not TVector3.Equals(NewUp, CurUp)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurPos, NewDir, NewUp)
          else
            T.SetView(CurPos, NewDir, NewUp);
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.CenterSelectedOriginOnChildren(
  const UseBottomCenter: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  DirectChildren: array of TCastleTransform;
  ChildOrigWorldPos: array of TVector3;
  I, J, Count, DirectChildCount: Integer;
  ParentT, ChildT: TCastleTransform;
  ChildrenWorldBox, ChildBox: TBox3D;
  TargetWorldOrigin, CurParentWorldPos: TVector3;
begin
  Result := false;
  if SelectedCount = 0 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    ParentT := Boxes[I].Parent;
    if (ParentT <> nil) and (not IsDescendantOfAnySelected(ParentT)) then
    begin
      Items[Count] := ParentT;
      Inc(Count);
    end;
  end;

  for I := 0 to Count - 1 do
  begin
    ParentT := Items[I];
    SetLength(DirectChildren, ParentT.Count);
    SetLength(ChildOrigWorldPos, ParentT.Count);
    DirectChildCount := 0;
    ChildrenWorldBox := TBox3D.Empty;
    for J := 0 to ParentT.Count - 1 do
    begin
      ChildT := ParentT[J];
      if (ChildT = nil) or (csTransient in ChildT.ComponentStyle) then Continue;
      DirectChildren[DirectChildCount] := ChildT;
      ChildOrigWorldPos[DirectChildCount] := GetTransformWorkingPos(ChildT);
      ChildBox := ChildT.WorldBoundingBox;
      if not ChildBox.IsEmpty then
        ChildrenWorldBox.Include(ChildBox)
      else
        ChildrenWorldBox.Include(ChildOrigWorldPos[DirectChildCount]);
      Inc(DirectChildCount);
    end;

    if (DirectChildCount = 0) or ChildrenWorldBox.IsEmpty then Continue;

    TargetWorldOrigin := ChildrenWorldBox.Center;
    if UseBottomCenter then
      TargetWorldOrigin.Y := ChildrenWorldBox.Data[0].Y;

    CurParentWorldPos := GetTransformWorkingPos(ParentT);
    if not TVector3.Equals(TargetWorldOrigin, CurParentWorldPos, 1e-5) then
    begin
      SetTransformWorkingPos(ParentT, TargetWorldOrigin);
      for J := 0 to DirectChildCount - 1 do
        SetTransformWorkingPos(DirectChildren[J], ChildOrigWorldPos[J]);
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInBezierArch(
  const StartWorldPos, ControlWorldPos, EndWorldPos: TVector3;
  const OrientAlongCurve: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  Factor, OneMinusT: Single;
  CurPos, NewPos, Tangent, CurWorldPos, CurDir, CurUp, GravityUp, Side, NewUp: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Factor := Single(I) / Single(Count - 1);
    OneMinusT := 1.0 - Factor;

    NewPos :=
      (StartWorldPos * (OneMinusT * OneMinusT)) +
      (ControlWorldPos * (2.0 * OneMinusT * Factor)) +
      (EndWorldPos * (Factor * Factor));

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientAlongCurve then
    begin
      Tangent :=
        ((ControlWorldPos - StartWorldPos) * (2.0 * OneMinusT)) +
        ((EndWorldPos - ControlWorldPos) * (2.0 * Factor));
      if Tangent.IsZero(1e-5) then
        Tangent := EndWorldPos - StartWorldPos;

      if not Tangent.IsZero(1e-5) then
      begin
        Tangent := Tangent.Normalize;
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;

        if T.World <> nil then
          GravityUp := T.World.GravityUp
        else
          GravityUp := Vector3(0, 1, 0);

        Side := TVector3.CrossProduct(Tangent, GravityUp);
        if Side.IsZero(1e-4) then
          Side := TVector3.CrossProduct(Tangent, CurUp);
        if Side.IsZero(1e-4) then
          Side := TVector3.CrossProduct(Tangent, Vector3(0, 0, 1));
        if Side.IsZero(1e-4) then
          Side := Vector3(1, 0, 0);
        NewUp := TVector3.CrossProduct(Side, Tangent).Normalize;

        if (not TVector3.Equals(Tangent, CurDir)) or
           (not TVector3.Equals(NewUp, CurUp)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurWorldPos, Tangent, NewUp)
          else
            T.SetView(CurWorldPos, Tangent, NewUp);
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInParabolicArchBetweenEndpoints(
  const ApexHeightOffset: Single; const OrientAlongCurve: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  StartPos, EndPos, MidPos, ControlPos: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  StartPos := GetTransformWorkingPos(Items[0]);
  EndPos := GetTransformWorkingPos(Items[Count - 1]);
  MidPos := Lerp(0.5, StartPos, EndPos);
  { For quadratic Bezier B(0.5) = 0.25*P0 + 0.5*P1 + 0.25*P2 = MidPos + 0.5*(P1 - MidPos),
    so setting P1 = MidPos + (0, 2 * ApexHeightOffset, 0) makes the curve pass through
    MidPos + (0, ApexHeightOffset, 0) at t = 0.5. }
  ControlPos := MidPos + Vector3(0, 2.0 * ApexHeightOffset, 0);
  Result := ArrangeSelectedInBezierArch(StartPos, ControlPos, EndPos, OrientAlongCurve);
end;

function TCastleTransformManipulate.ArrangeSelectedOnSphere(
  const Radius, MinElevationDeg, MaxElevationDeg: Single;
  const OrientOutward: Boolean): Boolean;
const
  GoldenAngleRad = 2.39996322972865332; // Pi * (3 - Sqrt(5))
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, NewPos, DirVec, CurWorldPos, CurDir, CurUp, GravityUp, Side, NewUp: TVector3;
  EffRadius, SumDist, MinSinY, MaxSinY, ActualMinSin, ActualMaxSin, Factor, SinY, CosY, Theta, SinT, CosT: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if FPivotMode = pmPrimarySelected then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  if Radius > 0 then
    EffRadius := Radius
  else
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Items[I]), CenterPos);
    EffRadius := SumDist / Count;
    if EffRadius < 1e-4 then
      EffRadius := 5.0;
  end;

  MinSinY := Sin(DegToRad(Clamped(MinElevationDeg, -90.0, 90.0)));
  MaxSinY := Sin(DegToRad(Clamped(MaxElevationDeg, -90.0, 90.0)));
  ActualMinSin := Min(MinSinY, MaxSinY);
  ActualMaxSin := Max(MinSinY, MaxSinY);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Factor := Single(I) / Single(Count - 1);
    SinY := Clamped(Lerp(Factor, ActualMinSin, ActualMaxSin), -1.0, 1.0);
    CosY := Sqrt(Max(0.0, 1.0 - Sqr(SinY)));
    Theta := Single(I) * GoldenAngleRad;
    SinCos(Theta, SinT, CosT);

    DirVec := Vector3(CosT * CosY, SinY, SinT * CosY);
    NewPos := CenterPos + DirVec * EffRadius;
    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientOutward and (not DirVec.IsZero(1e-5)) then
    begin
      DirVec := DirVec.Normalize;
      if T.HasWorldTransform then
        T.GetWorldView(CurWorldPos, CurDir, CurUp)
      else
      begin
        CurWorldPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;

      if T.World <> nil then
        GravityUp := T.World.GravityUp
      else
        GravityUp := Vector3(0, 1, 0);

      Side := TVector3.CrossProduct(DirVec, GravityUp);
      if Side.IsZero(1e-4) then
        Side := TVector3.CrossProduct(DirVec, CurUp);
      if Side.IsZero(1e-4) then
        Side := TVector3.CrossProduct(DirVec, Vector3(0, 0, 1));
      if Side.IsZero(1e-4) then
        Side := Vector3(1, 0, 0);
      NewUp := TVector3.CrossProduct(Side, DirVec).Normalize;

      if (not TVector3.Equals(DirVec, CurDir)) or
         (not TVector3.Equals(NewUp, CurUp)) then
      begin
        if T.HasWorldTransform then
          T.SetWorldView(CurWorldPos, DirVec, NewUp)
        else
          T.SetView(CurWorldPos, DirVec, NewUp);
        Result := true;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ScaleSelectedGroupAroundPivot(
  const Factor: TVector3; const ScaleSizes: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  PivotPos, CurPos, NewPos, NewScale: TVector3;
begin
  Result := false;
  if SelectedCount = 0 then Exit;
  if (Abs(Factor.X) < 1e-4) or (Abs(Factor.Y) < 1e-4) or (Abs(Factor.Z) < 1e-4) then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count = 0 then Exit;

  if (Count >= 2) and (FPivotMode = pmSelectionCenter) then
    PivotPos := SelectionWorkingCenter
  else
    PivotPos := GetTransformWorkingPos(Items[0]);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    if Count >= 2 then
    begin
      CurPos := GetTransformWorkingPos(T);
      NewPos := PivotPos + (CurPos - PivotPos) * Factor;
      if not TVector3.Equals(NewPos, CurPos) then
      begin
        SetTransformWorkingPos(T, NewPos);
        Result := true;
      end;
    end;

    if ScaleSizes then
    begin
      NewScale := T.Scale * Factor;
      if not TVector3.Equals(NewScale, T.Scale) then
      begin
        T.Scale := NewScale;
        Result := true;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInSineWave(
  const StartWorldPos, EndWorldPos: TVector3;
  const Amplitude: Single; const Cycles: Single;
  const WaveAxis: T3DAxis;
  const OrientAlongWave: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  Factor, Phase: Single;
  BasePos, WaveOffset, NewPos, CurPos: TVector3;
  Tangent, CurWorldPos, CurDir, CurUp, GravityUp, Side, NewUp: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Factor := Single(I) / Single(Count - 1);
    Phase := 2.0 * Pi * Cycles * Factor;
    BasePos := Lerp(Factor, StartWorldPos, EndWorldPos);
    WaveOffset := TVector3.Zero;
    WaveOffset.Data[WaveAxis] := Amplitude * Sin(Phase);
    NewPos := BasePos + WaveOffset;

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientAlongWave then
    begin
      Tangent := EndWorldPos - StartWorldPos;
      Tangent.Data[WaveAxis] := Tangent.Data[WaveAxis] +
        Amplitude * 2.0 * Pi * Cycles * Cos(Phase);
      if not Tangent.IsZero(1e-5) then
      begin
        Tangent := Tangent.Normalize;
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;
        GravityUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(Tangent, GravityUp)) > 0.99 then
          GravityUp := Vector3(0, 0, 1);
        Side := TVector3.CrossProduct(Tangent, GravityUp);
        if not Side.IsZero(1e-5) then
        begin
          Side := Side.Normalize;
          NewUp := TVector3.CrossProduct(Side, Tangent).Normalize;
          if (not TVector3.Equals(CurDir, Tangent, 1e-4)) or
             (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
          begin
            if T.HasWorldTransform then
              T.SetWorldView(CurWorldPos, Tangent, NewUp)
            else
              T.SetView(CurWorldPos, Tangent, NewUp);
            Result := true;
          end;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInSineWaveBetweenEndpoints(
  const Amplitude: Single; const Cycles: Single;
  const WaveAxis: T3DAxis;
  const OrientAlongWave: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  StartPos, EndPos: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  StartPos := GetTransformWorkingPos(Items[0]);
  EndPos := GetTransformWorkingPos(Items[Count - 1]);
  Result := ArrangeSelectedInSineWave(StartPos, EndPos, Amplitude, Cycles,
    WaveAxis, OrientAlongWave);
end;

function TCastleTransformManipulate.ArrangeSelectedInEllipse(
  const RadiusX, RadiusZ: Single; const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, NewPos, TargetDir, CurWorldPos, CurDir, CurUp, GravityUp, Side, NewUp: TVector3;
  EffRadiusX, EffRadiusZ, SumDist, Angle: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if FPivotMode = pmSelectionCenter then
    CenterPos := SelectionWorkingCenter
  else
    CenterPos := GetTransformWorkingPos(Items[0]);

  SumDist := 0;
  for I := 0 to Count - 1 do
  begin
    CurPos := GetTransformWorkingPos(Items[I]);
    SumDist := SumDist + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
  end;
  SumDist := SumDist / Count;
  if SumDist < 1e-4 then
    SumDist := 2.0;

  EffRadiusX := RadiusX;
  if EffRadiusX <= 0 then
    EffRadiusX := SumDist;
  EffRadiusZ := RadiusZ;
  if EffRadiusZ <= 0 then
    EffRadiusZ := SumDist;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    Angle := (2.0 * Pi * Single(I)) / Single(Count);
    NewPos := Vector3(
      CenterPos.X + Cos(Angle) * EffRadiusX,
      CurPos.Y,
      CenterPos.Z + Sin(Angle) * EffRadiusZ
    );

    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if (OrientMode = 1) or (OrientMode = 2) then
    begin
      if OrientMode = 1 then
        TargetDir := Vector3(CenterPos.X - NewPos.X, 0, CenterPos.Z - NewPos.Z)
      else
        TargetDir := Vector3(-Sin(Angle) * EffRadiusX, 0, Cos(Angle) * EffRadiusZ);

      if not TargetDir.IsZero(1e-5) then
      begin
        TargetDir := TargetDir.Normalize;
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;
        GravityUp := Vector3(0, 1, 0);
        Side := TVector3.CrossProduct(TargetDir, GravityUp);
        if not Side.IsZero(1e-5) then
        begin
          Side := Side.Normalize;
          NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;
          if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
             (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
          begin
            if T.HasWorldTransform then
              T.SetWorldView(CurWorldPos, TargetDir, NewUp)
            else
              T.SetView(CurWorldPos, TargetDir, NewUp);
            Result := true;
          end;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ReverseSelectedPositions(
  const ReverseRotations: Boolean; const ReverseScales: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  OrigWorldPos: array of TVector3;
  OrigRot: array of TVector4;
  OrigWorldDir, OrigWorldUp: array of TVector3;
  OrigScale: array of TVector3;
  I, MirrorIdx, Count: Integer;
  T: TCastleTransform;
  DummyPos, CurWorldPos, CurDir, CurUp: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  SetLength(OrigWorldPos, Count);
  SetLength(OrigRot, Count);
  SetLength(OrigWorldDir, Count);
  SetLength(OrigWorldUp, Count);
  SetLength(OrigScale, Count);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    OrigWorldPos[I] := GetTransformWorkingPos(T);
    OrigRot[I] := T.Rotation;
    if T.HasWorldTransform then
      T.GetWorldView(DummyPos, OrigWorldDir[I], OrigWorldUp[I])
    else
    begin
      OrigWorldDir[I] := T.Direction;
      OrigWorldUp[I] := T.Up;
    end;
    OrigScale[I] := T.Scale;
  end;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    MirrorIdx := Count - 1 - I;
    if I = MirrorIdx then Continue;

    if not TVector3.Equals(OrigWorldPos[MirrorIdx], OrigWorldPos[I]) then
    begin
      SetTransformWorkingPos(T, OrigWorldPos[MirrorIdx]);
      Result := true;
    end;

    if ReverseRotations then
    begin
      if T.Parent = Items[MirrorIdx].Parent then
      begin
        if not TVector4.Equals(OrigRot[MirrorIdx], T.Rotation) then
        begin
          T.Rotation := OrigRot[MirrorIdx];
          Result := true;
        end;
      end else
      begin
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;
        if (not TVector3.Equals(CurDir, OrigWorldDir[MirrorIdx], 1e-4)) or
           (not TVector3.Equals(CurUp, OrigWorldUp[MirrorIdx], 1e-4)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurWorldPos, OrigWorldDir[MirrorIdx], OrigWorldUp[MirrorIdx])
          else
            T.SetView(CurWorldPos, OrigWorldDir[MirrorIdx], OrigWorldUp[MirrorIdx]);
          Result := true;
        end;
      end;
    end;

    if ReverseScales then
    begin
      if not TVector3.Equals(OrigScale[MirrorIdx], T.Scale) then
      begin
        T.Scale := OrigScale[MirrorIdx];
        Result := true;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInPhyllotaxisDisk(
  const OuterRadius: Single; const OrientMode: Integer): Boolean;
const
  GoldenAngleRad = 2.39996322972865332; // Pi * (3 - Sqrt(5))
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, NewPos, TargetDir, CurWorldPos, CurDir, CurUp, GravityUp, Side, NewUp: TVector3;
  EffRadius, SumDist, Dist, Angle, SinA, CosA: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if FPivotMode = pmSelectionCenter then
    CenterPos := SelectionWorkingCenter
  else
    CenterPos := GetTransformWorkingPos(Items[0]);

  if OuterRadius > 0 then
    EffRadius := OuterRadius
  else
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      SumDist := Max(SumDist, Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z));
    end;
    EffRadius := SumDist;
    if EffRadius < 1e-4 then
      EffRadius := 6.0;
  end;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    Dist := EffRadius * Sqrt(Single(I) / Single(Count - 1));
    Angle := Single(I) * GoldenAngleRad;
    SinCos(Angle, SinA, CosA);
    NewPos := Vector3(
      CenterPos.X + CosA * Dist,
      CurPos.Y,
      CenterPos.Z + SinA * Dist
    );

    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if (OrientMode = 1) or (OrientMode = 2) then
    begin
      if I = 0 then
        TargetDir := Vector3(Cos(GoldenAngleRad), 0, Sin(GoldenAngleRad))
      else
        TargetDir := Vector3(NewPos.X - CenterPos.X, 0, NewPos.Z - CenterPos.Z);
      if OrientMode = 1 then
        TargetDir := -TargetDir;

      if not TargetDir.IsZero(1e-5) then
      begin
        TargetDir := TargetDir.Normalize;
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;
        GravityUp := Vector3(0, 1, 0);
        Side := TVector3.CrossProduct(TargetDir, GravityUp);
        if not Side.IsZero(1e-5) then
        begin
          Side := Side.Normalize;
          NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;
          if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
             (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
          begin
            if T.HasWorldTransform then
              T.SetWorldView(CurWorldPos, TargetDir, NewUp)
            else
              T.SetView(CurWorldPos, TargetDir, NewUp);
            Result := true;
          end;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInStaircase(
  const StartWorldPos, EndWorldPos: TVector3;
  const CurveExponent: Single;
  const OrientHorizontallyAlongRun: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  EffExp, Factor, HeightFactor: Single;
  CurPos, NewPos, HorizDir, CurWorldPos, CurDir, CurUp, GravityUp, Side, NewUp: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  EffExp := Max(0.05, CurveExponent);
  HorizDir := Vector3(EndWorldPos.X - StartWorldPos.X, 0, EndWorldPos.Z - StartWorldPos.Z);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Factor := Single(I) / Single(Count - 1);
    if Factor <= 0.0 then
      HeightFactor := 0.0
    else if Factor >= 1.0 then
      HeightFactor := 1.0
    else
      HeightFactor := Power(Factor, EffExp);

    NewPos := Vector3(
      Lerp(Factor, StartWorldPos.X, EndWorldPos.X),
      Lerp(HeightFactor, StartWorldPos.Y, EndWorldPos.Y),
      Lerp(Factor, StartWorldPos.Z, EndWorldPos.Z)
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientHorizontallyAlongRun and (not HorizDir.IsZero(1e-5)) then
    begin
      HorizDir := HorizDir.Normalize;
      if T.HasWorldTransform then
        T.GetWorldView(CurWorldPos, CurDir, CurUp)
      else
      begin
        CurWorldPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;
      GravityUp := Vector3(0, 1, 0);
      Side := TVector3.CrossProduct(HorizDir, GravityUp);
      if not Side.IsZero(1e-5) then
      begin
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, HorizDir).Normalize;
        if (not TVector3.Equals(CurDir, HorizDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurWorldPos, HorizDir, NewUp)
          else
            T.SetView(CurWorldPos, HorizDir, NewUp);
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInStaircaseBetweenEndpoints(
  const CurveExponent: Single;
  const OrientHorizontallyAlongRun: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  StartPos, EndPos: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  StartPos := GetTransformWorkingPos(Items[0]);
  EndPos := GetTransformWorkingPos(Items[Count - 1]);
  Result := ArrangeSelectedInStaircase(StartPos, EndPos, CurveExponent,
    OrientHorizontallyAlongRun);
end;

function TCastleTransformManipulate.ScaleSelectedRadialDistanceXZ(
  const RadialFactor: Single): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  PivotPos, CurPos, NewPos: TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if FPivotMode = pmSelectionCenter then
    PivotPos := SelectionWorkingCenter
  else
    PivotPos := GetTransformWorkingPos(Items[0]);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    NewPos := Vector3(
      PivotPos.X + (CurPos.X - PivotPos.X) * RadialFactor,
      CurPos.Y,
      PivotPos.Z + (CurPos.Z - PivotPos.Z) * RadialFactor
    );
    if not TVector3.Equals(NewPos, CurPos) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedOnTorus(
  const MajorRadius, MinorRadius: Single;
  const MinorTurns: Single; const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, TubeCenter, TargetDir, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  ActualMajor, ActualMinor, SumDist, Theta, Phi, RingR: Single;
  SinTheta, CosTheta, SinPhi, CosPhi, DTheta, DPhi: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if FPivotMode = pmSelectionCenter then
    CenterPos := SelectionWorkingCenter
  else
    CenterPos := GetTransformWorkingPos(Items[0]);

  ActualMajor := MajorRadius;
  if ActualMajor <= 0 then
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      SumDist := SumDist + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    ActualMajor := SumDist / Count;
    if ActualMajor < 1e-3 then
      ActualMajor := 10.0;
  end;

  ActualMinor := MinorRadius;
  if ActualMinor < 0 then
    ActualMinor := 0.25 * ActualMajor;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / Count;
    Phi := (2.0 * Pi * MinorTurns * I) / Count;
    SinCos(Theta, SinTheta, CosTheta);
    SinCos(Phi, SinPhi, CosPhi);

    RingR := ActualMajor + ActualMinor * CosPhi;
    TargetPos := Vector3(
      CenterPos.X + RingR * CosTheta,
      CenterPos.Y + ActualMinor * SinPhi,
      CenterPos.Z + RingR * SinTheta
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(TargetPos, CurPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientMode in [1, 2] then
    begin
      TargetDir := TVector3.Zero;
      if OrientMode = 1 then
      begin
        TubeCenter := Vector3(
          CenterPos.X + ActualMajor * CosTheta,
          CenterPos.Y,
          CenterPos.Z + ActualMajor * SinTheta
        );
        TargetDir := TargetPos - TubeCenter;
        if TargetDir.IsZero(1e-5) then
          TargetDir := Vector3(CosPhi * CosTheta, SinPhi, CosPhi * SinTheta);
      end else
      begin
        DTheta := 2.0 * Pi;
        DPhi := 2.0 * Pi * MinorTurns;
        TargetDir := Vector3(
          -ActualMinor * SinPhi * DPhi * CosTheta - RingR * SinTheta * DTheta,
          ActualMinor * CosPhi * DPhi,
          -ActualMinor * SinPhi * DPhi * SinTheta + RingR * CosTheta * DTheta
        );
      end;

      if not TargetDir.IsZero(1e-5) then
      begin
        TargetDir := TargetDir.Normalize;
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;

        if T.World <> nil then
          GravityUp := T.World.GravityUp
        else
          GravityUp := Vector3(0, 1, 0);

        Side := TVector3.CrossProduct(TargetDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := TVector3.CrossProduct(TargetDir, Vector3(0, 0, 1));
        if Side.IsZero(1e-5) then
          Side := TVector3.CrossProduct(TargetDir, Vector3(1, 0, 0));
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;

        if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurWorldPos, TargetDir, NewUp)
          else
            T.SetView(CurWorldPos, TargetDir, NewUp);
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInZigzag(
  const StartWorldPos, EndWorldPos: TVector3;
  const LateralOffset: Single; const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  I, Count: Integer;
  T: TCastleTransform;
  LineDelta, LineDir, GravityUp, SideVec, BasePos, TargetPos, CurPos: TVector3;
  TargetDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  Factor, SignVal: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  LineDelta := EndWorldPos - StartWorldPos;
  if Items[0].World <> nil then
    GravityUp := Items[0].World.GravityUp
  else
    GravityUp := Vector3(0, 1, 0);

  if not LineDelta.IsZero(1e-5) then
  begin
    LineDir := LineDelta.Normalize;
    SideVec := TVector3.CrossProduct(LineDir, GravityUp);
    if SideVec.IsZero(1e-5) then
      SideVec := TVector3.CrossProduct(LineDir, Vector3(0, 0, 1));
    if SideVec.IsZero(1e-5) then
      SideVec := Vector3(1, 0, 0)
    else
      SideVec := SideVec.Normalize;
  end else
  begin
    LineDir := Vector3(0, 0, -1);
    SideVec := Vector3(1, 0, 0);
  end;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Factor := Single(I) / Single(Count - 1);
    if Odd(I) then
      SignVal := -1.0
    else
      SignVal := 1.0;

    BasePos := Lerp(Factor, StartWorldPos, EndWorldPos);
    TargetPos := BasePos + (SideVec * (SignVal * LateralOffset));
    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(TargetPos, CurPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientMode in [1, 2] then
    begin
      if OrientMode = 1 then
        TargetDir := LineDir
      else
        TargetDir := -SideVec * SignVal;

      if not TargetDir.IsZero(1e-5) then
      begin
        TargetDir := TargetDir.Normalize;
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;

        Side := TVector3.CrossProduct(TargetDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := TVector3.CrossProduct(TargetDir, Vector3(0, 0, 1));
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;

        if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurWorldPos, TargetDir, NewUp)
          else
            T.SetView(CurWorldPos, TargetDir, NewUp);
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInZigzagBetweenEndpoints(
  const LateralOffset: Single; const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  I, Count, NonEmptyCount: Integer;
  T: TCastleTransform;
  StartPos, EndPos: TVector3;
  ActualOffset, SumDiag: Single;
  Box: TBox3D;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  Count := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  StartPos := GetTransformWorkingPos(Items[0]);
  EndPos := GetTransformWorkingPos(Items[Count - 1]);
  ActualOffset := LateralOffset;
  if ActualOffset <= 0 then
  begin
    SumDiag := 0;
    NonEmptyCount := 0;
    for I := 0 to Count - 1 do
    begin
      if Items[I].HasWorldTransform then
        Box := Items[I].WorldBoundingBox
      else
        Box := Items[I].BoundingBox;
      if not Box.IsEmpty then
      begin
        SumDiag := SumDiag + Box.AverageSize(false, 0);
        Inc(NonEmptyCount);
      end;
    end;
    if NonEmptyCount > 0 then
      ActualOffset := Max(0.5, SumDiag / NonEmptyCount)
    else
      ActualOffset := 2.0;
  end;

  Result := ArrangeSelectedInZigzag(StartPos, EndPos, ActualOffset, OrientMode);
end;

function TCastleTransformManipulate.NormalizeSelectedSizes(
  const PreserveAspectRatio: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Sizes: array of TVector3;
  Diags: array of Single;
  I, Count, ValidCount: Integer;
  T: TCastleTransform;
  Box: TBox3D;
  BoxSize, AvgSize, NewScale, RatioVec: TVector3;
  Diag, AvgDiag, Ratio: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  SetLength(Sizes, FMaxSelectedCount);
  SetLength(Diags, FMaxSelectedCount);
  Count := 0;
  ValidCount := 0;
  AvgSize := TVector3.Zero;
  AvgDiag := 0;

  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      if T.HasWorldTransform then
        Box := T.WorldBoundingBox
      else
        Box := T.BoundingBox;
      if not Box.IsEmpty then
      begin
        BoxSize := Box.Size;
        Diag := BoxSize.Length;
        if Diag > 1e-5 then
        begin
          Items[ValidCount] := T;
          Sizes[ValidCount] := BoxSize;
          Diags[ValidCount] := Diag;
          AvgSize := AvgSize + BoxSize;
          AvgDiag := AvgDiag + Diag;
          Inc(ValidCount);
        end;
      end;
      Inc(Count);
    end;
  end;

  if (Count < 2) or (ValidCount < 2) then Exit;

  AvgSize := AvgSize / Single(ValidCount);
  AvgDiag := AvgDiag / Single(ValidCount);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    if PreserveAspectRatio then
    begin
      Ratio := AvgDiag / Diags[I];
      NewScale := T.Scale * Ratio;
    end else
    begin
      RatioVec := Vector3(1.0, 1.0, 1.0);
      if Sizes[I].X > 1e-5 then RatioVec.X := AvgSize.X / Sizes[I].X;
      if Sizes[I].Y > 1e-5 then RatioVec.Y := AvgSize.Y / Sizes[I].Y;
      if Sizes[I].Z > 1e-5 then RatioVec.Z := AvgSize.Z / Sizes[I].Z;
      NewScale := T.Scale * RatioVec;
    end;

    if not TVector3.Equals(NewScale, T.Scale) then
    begin
      T.Scale := NewScale;
      Result := true;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInLissajous(
  const RadiusX, RadiusZ: Single;
  const FreqX: Single; const FreqZ: Single;
  const VerticalAmplitude: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, TargetDir, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  EffRx, EffRz, EffWx, EffWz, Theta, AvgExtent: Single;
  BBox: TBox3D;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  ValidCount := 0;
  AvgExtent := 0.0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[ValidCount] := T;
      Inc(ValidCount);
      BBox := T.WorldBoundingBox;
      if not BBox.IsEmpty then
        AvgExtent := AvgExtent + BBox.AverageSize(false, 1.0);
    end;
  end;

  if ValidCount < 2 then
    Exit;

  if AvgExtent > 1e-4 then
    AvgExtent := (AvgExtent / ValidCount) * 1.5
  else
    AvgExtent := 3.0;

  EffRx := RadiusX;
  if EffRx <= 1e-4 then
    EffRx := Max(2.0, AvgExtent * ValidCount / (2.0 * Pi));

  EffRz := RadiusZ;
  if EffRz <= 1e-4 then
    EffRz := EffRx * 0.5;

  EffWx := FreqX;
  if Abs(EffWx) <= 1e-4 then
    EffWx := 1.0;

  EffWz := FreqZ;
  if Abs(EffWz) <= 1e-4 then
    EffWz := 2.0;

  if FPivotMode = pmSelectionCenter then
    CenterPos := SelectionWorkingCenter
  else
    CenterPos := GetTransformWorkingPos(Items[0]);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / ValidCount;

    TargetPos := CenterPos + Vector3(
      EffRx * Sin(EffWx * Theta),
      VerticalAmplitude * Cos(EffWx * Theta),
      EffRz * Sin(EffWz * Theta)
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(TargetPos, CurPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientMode in [1, 2] then
    begin
      if OrientMode = 1 then
      begin
        TargetDir := CenterPos - TargetPos;
        TargetDir.Y := 0.0;
        if TargetDir.IsZero(1e-5) then
          TargetDir := Vector3(0.0, 0.0, -1.0);
      end else
      begin
        TargetDir := Vector3(
          EffRx * EffWx * Cos(EffWx * Theta),
          -VerticalAmplitude * EffWx * Sin(EffWx * Theta),
          EffRz * EffWz * Cos(EffWz * Theta)
        );
        if TargetDir.IsZero(1e-5) then
          TargetDir := Vector3(0.0, 0.0, -1.0);
      end;

      if not TargetDir.IsZero(1e-5) then
      begin
        TargetDir := TargetDir.Normalize;
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;

        if T.World <> nil then
          GravityUp := T.World.GravityUp
        else
          GravityUp := Vector3(0, 1, 0);

        Side := TVector3.CrossProduct(TargetDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := TVector3.CrossProduct(TargetDir, Vector3(0, 0, 1));
        if Side.IsZero(1e-5) then
          Side := TVector3.CrossProduct(TargetDir, Vector3(1, 0, 0));
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;

        if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurWorldPos, TargetDir, NewUp)
          else
            T.SetView(CurWorldPos, TargetDir, NewUp);
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInCatenary(
  const StartWorldPos, EndWorldPos: TVector3;
  const SagDepth: Single;
  const OrientAlongCurve: Boolean): Boolean;
const
  CatenaryK = 1.5;
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  ChordVec, TargetPos, CurPos, TargetDir, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  ParamT, ParamU, CoshK, Denom, SagFactor, dSdt: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, FMaxSelectedCount);
  ValidCount := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[ValidCount] := T;
      Inc(ValidCount);
    end;
  end;

  if ValidCount < 2 then
    Exit;

  ChordVec := EndWorldPos - StartWorldPos;
  CoshK := Cosh(CatenaryK);
  Denom := CoshK - 1.0;

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    ParamT := Single(I) / Single(ValidCount - 1);
    ParamU := 2.0 * ParamT - 1.0;
    if Denom > 1e-6 then
      SagFactor := (CoshK - Cosh(CatenaryK * ParamU)) / Denom
    else
      SagFactor := 1.0 - Sqr(ParamU);

    TargetPos := StartWorldPos + (ChordVec * ParamT) - Vector3(0.0, SagDepth * SagFactor, 0.0);
    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(TargetPos, CurPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientAlongCurve then
    begin
      if Denom > 1e-6 then
        dSdt := (-2.0 * CatenaryK * Sinh(CatenaryK * ParamU)) / Denom
      else
        dSdt := -4.0 * ParamU;

      TargetDir := ChordVec - Vector3(0.0, SagDepth * dSdt, 0.0);
      if not TargetDir.IsZero(1e-5) then
      begin
        TargetDir := TargetDir.Normalize;
        if T.HasWorldTransform then
          T.GetWorldView(CurWorldPos, CurDir, CurUp)
        else
        begin
          CurWorldPos := T.Translation;
          CurDir := T.Direction;
          CurUp := T.Up;
        end;

        if T.World <> nil then
          GravityUp := T.World.GravityUp
        else
          GravityUp := Vector3(0, 1, 0);

        Side := TVector3.CrossProduct(TargetDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := TVector3.CrossProduct(TargetDir, Vector3(0, 0, 1));
        if Side.IsZero(1e-5) then
          Side := TVector3.CrossProduct(TargetDir, Vector3(1, 0, 0));
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;

        if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          if T.HasWorldTransform then
            T.SetWorldView(CurWorldPos, TargetDir, NewUp)
          else
            T.SetView(CurWorldPos, TargetDir, NewUp);
          Result := true;
        end;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInCatenaryBetweenEndpoints(
  const SagDepth: Single;
  const OrientAlongCurve: Boolean): Boolean;
var
  FirstT, LastT, T: TCastleTransform;
  I, ValidCount: Integer;
  StartWorld, EndWorld: TVector3;
  EffSag, ChordLen: Single;
begin
  Result := false;
  FirstT := nil;
  LastT := nil;
  ValidCount := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      if FirstT = nil then
        FirstT := T;
      LastT := T;
      Inc(ValidCount);
    end;
  end;

  if (ValidCount < 2) or (FirstT = nil) or (LastT = nil) then
    Exit;

  StartWorld := GetTransformWorkingPos(FirstT);
  EndWorld := GetTransformWorkingPos(LastT);

  EffSag := SagDepth;
  if Abs(EffSag) <= 1e-5 then
  begin
    ChordLen := PointsDistance(StartWorld, EndWorld);
    if ChordLen > 1e-4 then
      EffSag := ChordLen * 0.25
    else
      EffSag := 2.0;
  end;

  Result := ArrangeSelectedInCatenary(StartWorld, EndWorld, EffSag, OrientAlongCurve);
end;

function TCastleTransformManipulate.ProjectSelectedOntoLine(
  const LineStartWorldPos, LineEndWorldPos: TVector3;
  const ClampToSegment: Boolean;
  const OrientAlongLine: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  LineVec, CurPos, TargetPos, TargetDir, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  LineLenSqr, ParamT: Single;
begin
  Result := false;
  if SelectedCount < 1 then Exit;

  SetLength(Items, FMaxSelectedCount);
  ValidCount := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[ValidCount] := T;
      Inc(ValidCount);
    end;
  end;

  if ValidCount < 1 then
    Exit;

  LineVec := LineEndWorldPos - LineStartWorldPos;
  LineLenSqr := LineVec.LengthSqr;
  if LineLenSqr <= 1e-10 then
    Exit;

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    ParamT := TVector3.DotProduct(CurPos - LineStartWorldPos, LineVec) / LineLenSqr;
    if ClampToSegment then
      ParamT := Clamped(ParamT, 0.0, 1.0);

    TargetPos := LineStartWorldPos + (LineVec * ParamT);
    if not TVector3.Equals(TargetPos, CurPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientAlongLine then
    begin
      TargetDir := LineVec.Normalize;
      if T.HasWorldTransform then
        T.GetWorldView(CurWorldPos, CurDir, CurUp)
      else
      begin
        CurWorldPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;

      if T.World <> nil then
        GravityUp := T.World.GravityUp
      else
        GravityUp := Vector3(0, 1, 0);

      Side := TVector3.CrossProduct(TargetDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := TVector3.CrossProduct(TargetDir, Vector3(0, 0, 1));
      if Side.IsZero(1e-5) then
        Side := TVector3.CrossProduct(TargetDir, Vector3(1, 0, 0));
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;

      if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        if T.HasWorldTransform then
          T.SetWorldView(CurWorldPos, TargetDir, NewUp)
        else
          T.SetView(CurWorldPos, TargetDir, NewUp);
        Result := true;
      end;
    end;
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ProjectSelectedOntoLineBetweenEndpoints(
  const ClampToSegment: Boolean;
  const OrientAlongLine: Boolean): Boolean;
var
  FirstT, LastT, T: TCastleTransform;
  I, ValidCount: Integer;
  StartWorld, EndWorld: TVector3;
begin
  Result := false;
  FirstT := nil;
  LastT := nil;
  ValidCount := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      if FirstT = nil then
        FirstT := T;
      LastT := T;
      Inc(ValidCount);
    end;
  end;

  if (ValidCount < 2) or (FirstT = nil) or (LastT = nil) then
    Exit;

  StartWorld := GetTransformWorkingPos(FirstT);
  EndWorld := GetTransformWorkingPos(LastT);
  Result := ProjectSelectedOntoLine(StartWorld, EndWorld, ClampToSegment, OrientAlongLine);
end;

function TCastleTransformManipulate.SelectedCount: Integer;
var
  I: Integer;
begin
  { Note that we cannot just return FMaxSelectedCount, because some of
    TCastleTransform instances could have been freed since the SetSelected call.
    They leave Boxes[..].Parent = nil in the middle. }

  Result := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if Boxes[I].Parent <> nil then
      Inc(Result);
end;

function TCastleTransformManipulate.GetSelected(Index: Integer): TCastleTransform;
var
  I: Integer;
begin
  if Index < 0 then
    raise EListError.CreateFmt('Index %d out of bounds (TCastleTransformManipulate.Selected)', [
      Index
    ]);

  { We have to iterate, not just access Boxes[Index].Parent,
    because some of TCastleTransform instances could have been
    freed since the SetSelected call. }

  for I := 0 to FMaxSelectedCount - 1 do
    if Boxes[I].Parent <> nil then
    begin
      if Index = 0 then
        Exit(Boxes[I].Parent);
      Dec(Index);
    end;

  raise EListError.CreateFmt('Index %d out of bounds (TCastleTransformManipulate.Selected)', [
    Index
  ]);
end;

initialization
  ColorHover := HexToColor('fffba0'); // desaturated yellow
  ColorSelected := White;
end.
