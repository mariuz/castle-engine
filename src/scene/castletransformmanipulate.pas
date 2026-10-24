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

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along the
      perimeter edges of a regular $M$-sided polygon (@code(InnerRadius <= 0)) or an
      alternating $2M$-vertex star polygon (@code(InnerRadius > 0)) in the horizontal
      XZ plane around the active selection pivot.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the polygon center
      - @code(2): orient forward along the active polygon edge direction
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInPolygon(
      const Sides: Integer;
      const OuterRadius: Single;
      const InnerRadius: Single = 0.0;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      multi-turn 3D logarithmic / equiangular spiral vortex (@code(Logarithmic = true):
      $r(t) = R_(\text(start)) \cdot (R_(\text(end)) / R_(\text(start)))^t$) or
      Archimedean spiral (@code(Logarithmic = false):
      $r(t) = R_(\text(start)) + (R_(\text(end)) - R_(\text(start))) \cdot t$) around
      the active selection pivot over @code(Turns) revolutions and @code(HeightSpan)
      vertical rise.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the vortex center
      - @code(2): orient forward along the 3D spiral tangent vector
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInSpiralVortex(
      const StartRadius, EndRadius: Single;
      const Turns: Single = 2.0;
      const HeightSpan: Single = 0.0;
      const Logarithmic: Boolean = true;
      const OrientMode: Integer = 0): Boolean;

    { Project all top-level selected transforms (@code(SelectedCount >= 1))
      orthogonally onto the 3D plane passing through @code(PlanePoint) with unit
      normal @code(PlaneNormal):
      $P'_i = P_i - ((P_i - P_0) \cdot \hat(n)) \hat(n)$.
      When @code(AlignUpToNormal) is @true, each transform's world $+Y$ Up axis is
      also aligned to @code(PlaneNormal) while preserving its forward direction
      projected onto the plane.
      Returns @true if at least one selected transform was modified. }
    function ProjectSelectedOntoPlane(
      const PlanePoint, PlaneNormal: TVector3;
      const AlignUpToNormal: Boolean = false): Boolean;

    { Project all top-level selected transforms (@code(SelectedCount >= 3))
      orthogonally onto the 3D plane defined by the first (@code(Selected[0])),
      middle (@code(Selected[N div 2])), and last (@code(Selected[N-1])) selected
      transforms (falling back to the horizontal XZ plane at @code(Selected[0]) when
      the three reference points are collinear or @code(SelectedCount = 2)).
      Returns @true if at least one selected transform was modified. }
    function ProjectSelectedOntoPlaneThreePoints(
      const AlignUpToNormal: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      parametric 3D (p, q) torus knot (such as the (2, 3) trefoil knot or (3, 2)
      cinquefoil knot) around the active selection pivot:
      $r(\theta) = R + r_(tube) \cos(q \theta)$,
      $x(\theta) = C_x + r(\theta) \cos(p \theta)$,
      $y(\theta) = C_y + r_(tube) \sin(q \theta)$,
      $z(\theta) = C_z + r(\theta) \sin(p \theta)$
      for $\theta_i = 2\pi i / N$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient outward along the torus tube normal from the core ring
      - @code(2): orient forward along the 3D torus knot tangent vector
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInTorusKnot(
      const MajorRadius, TubeRadius: Single;
      const KnotP: Integer = 2; const KnotQ: Integer = 3;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) into
      concentric circular amphitheater / stadium rings around the active selection
      pivot, where ring $k \ge 0$ has radius $R_k = R_0 + k \cdot \Delta R$,
      elevation $Y_k = C_y + k \cdot \Delta Y$, and capacity
      $M_k = \max(1, \text(BaseRingCount) \cdot (k + 1))$ (distributing the final
      partial ring evenly around the full $2\pi$ circumference).
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the amphitheater center
      - @code(2): orient horizontally outward from the amphitheater center
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInConcentricRings(
      const FirstRingRadius, RingSpacing, RingRiseY: Single;
      const BaseRingCount: Integer = 6;
      const OrientMode: Integer = 0): Boolean;

    { Project all top-level selected transforms (@code(SelectedCount >= 2))
      radially from the active selection pivot onto a 3D sphere of @code(Radius)
      (auto-computing the average 3D distance from the pivot when @code(Radius <= 0))
      while preserving each transform's existing angular direction from the pivot.
      When @code(OrientOutward) is @true, each transform is also oriented radially
      outward from the sphere center.
      Returns @true if at least one selected transform was modified. }
    function ProjectSelectedOntoSphere(
      const Radius: Single = 0.0;
      const OrientOutward: Boolean = false): Boolean;

    { Project all top-level selected transforms (@code(SelectedCount >= 2))
      horizontally from the active selection pivot onto a vertical cylinder of
      @code(Radius) (auto-computing the average horizontal XZ distance from the
      pivot when @code(Radius <= 0)) while preserving each transform's existing
      horizontal azimuth angle and world Y elevation.
      When @code(OrientOutward) is @true, each transform is also oriented
      horizontally outward from the cylinder axis.
      Returns @true if at least one selected transform was modified. }
    function ProjectSelectedOntoCylinder(
      const Radius: Single = 0.0;
      const OrientOutward: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) evenly
      over a 3D vertical cylindrical shell / tower wall around the active selection
      pivot using a 2D cylindrical Fibonacci golden-angle lattice:
      $\theta_i = i \cdot \phi_(golden)$,
      $y_i = C_y + (i / (N - 1) - 0.5) \cdot \text(HeightSpan)$,
      $x_i = C_x + R \cos(\theta_i), \quad z_i = C_z + R \sin(\theta_i)$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the central cylinder axis
      - @code(2): orient horizontally outward away from the cylinder wall
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnCylinder(
      const Radius: Single;
      const HeightSpan: Single = 10.0;
      const OrientMode: Integer = 2): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) into a
      stepped 3D square pyramid / ziggurat centered horizontally at the active
      selection pivot, where tier $L \ge 0$ (from top apex $L = 0$ down to base
      $L = K - 1$) forms an $(L + 1) \times (L + 1)$ horizontal grid with cell
      spacing @code(BaseSpacingXZ) and vertical elevation
      $Y_L = C_y + (K - 1 - L) \cdot \text(LayerRiseY)$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally outward from the pyramid center
      - @code(2): orient horizontally inward toward the pyramid center
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInPyramid(
      const BaseSpacingXZ, LayerRiseY: Single;
      const OrientMode: Integer = 0): Boolean;

    { Clamp all top-level selected transforms (@code(SelectedCount >= 1)) so their
      world positions (@code(UseObjectBounds = false)) or their entire world-space
      axis-aligned bounding boxes (@code(UseObjectBounds = true)) lie within
      the 3D axis-aligned box defined by @code(BoxMin) and @code(BoxMax).
      Returns @true if at least one selected transform was modified. }
    function ClampSelectedToBox(const BoxMin, BoxMax: TVector3;
      const UseObjectBounds: Boolean = true): Boolean;

    { Clamp all secondary top-level selected transforms (@code(Selected[1..N-1]))
      so their world positions (@code(UseObjectBounds = false)) or their entire
      world-space bounding boxes (@code(UseObjectBounds = true)) lie within the
      world bounding box of the primary selected transform (@code(Selected[0])).
      Returns @true if at least one selected transform was modified. }
    function ClampSelectedToPrimaryBounds(
      const UseObjectBounds: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) evenly
      over a 3D conical or frustum/funnel shell around the active selection pivot
      using a conical Fibonacci golden-angle spiral lattice:
      $t_i = i / (N - 1)$,
      $r_i = R_(\text(base)) + (R_(\text(top)) - R_(\text(base))) \cdot t_i$,
      $\theta_i = i \cdot \phi_(golden)$,
      $x_i = C_x + r_i \cos(\theta_i), \quad y_i = C_y + (t_i - 0.5) \cdot \text(HeightSpan), \quad z_i = C_z + r_i \sin(\theta_i)$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the cone axis
      - @code(2): orient outward along the 3D conical surface normal
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnCone(
      const BaseRadius: Single;
      const TopRadius: Single = 0.0;
      const HeightSpan: Single = 10.0;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) in a
      2D pointy-top hexagonal / honeycomb lattice on the horizontal XZ plane
      centered at the active selection pivot, where every adjacent cell neighbor
      in all 6 hexagonal directions is equidistant at $\sqrt(3) \cdot \text(CellRadius)$
      ($\Delta X = \sqrt(3) R$, $\Delta Z = 1.5 R$, odd rows staggered by $+0.5 \Delta X$).
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): cycle 6-fold hexagonal symmetry yaw ($60^\circ \cdot (i \bmod 6)$)
      - @code(2): orient horizontally outward from the honeycomb center
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInHexGrid(
      const Columns: Integer = 0;
      const CellRadius: Single = 0.0;
      const OrientMode: Integer = 0): Boolean;

    { Push all top-level selected transforms (@code(SelectedCount >= 1)) whose
      world positions (@code(UseObjectBounds = false)) or world-space bounding
      boxes (@code(UseObjectBounds = true)) penetrate the 3D axis-aligned box
      @code([BoxMin, BoxMax]) outward to the nearest face of the exclusion box
      along the minimum-penetration axis.
      Returns @true if at least one selected transform was modified. }
    function PushSelectedOutsideBox(const BoxMin, BoxMax: TVector3;
      const UseObjectBounds: Boolean = true): Boolean;

    { Push all secondary top-level selected transforms (@code(Selected[1..N-1]))
      whose world positions (@code(UseObjectBounds = false)) or world-space
      bounding boxes (@code(UseObjectBounds = true)) penetrate the world bounding
      box of the primary selected transform (@code(Selected[0])) outward to the
      nearest face of the primary bounding box.
      Returns @true if at least one selected transform was modified. }
    function PushSelectedOutsidePrimaryBounds(
      const UseObjectBounds: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along the
      12 outer wireframe edges and 8 corner vertices of a 3D box with half-extents
      @code(HalfExtents) around the active selection pivot (@code(ShellMode = false)),
      or over the outer 6 boundary faces of a hollow cubic lattice (@code(ShellMode = true)).
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient outward from the cube center
      - @code(2): orient inward toward the cube center
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnCubeFrame(
      const HalfExtents: TVector3;
      const ShellMode: Boolean = false;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) in a
      3D paraboloid dish / bowl / crater using a sunflower golden-angle Phyllotaxis
      spiral centered at the active selection pivot:
      $u_i = (i + 0.5) / N$,
      $r_i = R \sqrt(u_i)$,
      $\theta_i = i \cdot \phi_(golden)$,
      $x_i = C_x + r_i \cos(\theta_i), \quad y_i = C_y + D_y (u_i - 0.5), \quad z_i = C_z + r_i \sin(\theta_i)$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient along the 3D paraboloid surface normal (concave inward when $D_y > 0$)
      - @code(2): orient horizontally inward toward the central vertical axis
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInParaboloidBowl(
      const RimRadius: Single = 0.0;
      const DepthY: Single = 5.0;
      const OrientMode: Integer = 0): Boolean;

    { Snap / project all top-level selected transforms (@code(SelectedCount >= 1))
      onto the nearest of the 6 outer faces ($\pm X, \pm Y, \pm Z$) of the 3D
      axis-aligned box @code([BoxMin, BoxMax]).
      Each transform's two tangential coordinates are clamped to the box face bounds,
      while its normal coordinate is snapped to the nearest face (offset outward by
      the transform's own half-extent along that face normal when @code(FlushOutside = true)).
      When @code(OrientOutward = true), each transform is also rotated to face along
      the snapped box face's outward normal.
      Returns @true if at least one selected transform was modified. }
    function SnapSelectedToBoxSurface(const BoxMin, BoxMax: TVector3;
      const FlushOutside: Boolean = true;
      const OrientOutward: Boolean = false): Boolean;

    { Snap / project all secondary top-level selected transforms (@code(Selected[1..N-1]))
      onto the nearest of the 6 outer faces of the primary selected transform's
      (@code(Selected[0])) world bounding box.
      Returns @true if at least one selected transform was modified. }
    function SnapSelectedToPrimaryBoundsSurface(
      const FlushOutside: Boolean = true;
      const OrientOutward: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) along a
      3D polar Rose / Rhodonea petal curve centered at the active selection pivot:
      $\theta_i = \frac(2\pi i)(N), \quad r(\theta_i) = R \cos(k \theta_i)$,
      $x_i = C_x + r(\theta_i)\cos(\theta_i), \quad y_i = C_y + H_y \sin(k \theta_i), \quad z_i = C_z + r(\theta_i)\sin(\theta_i)$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the rose center
      - @code(2): orient forward along the 3D rose petal tangent vector
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInRoseCurve(
      const OuterRadius: Single = 0.0;
      const PetalsK: Single = 2.0;
      const VerticalWaveY: Single = 0.0;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2)) over a
      triaxial 3D ellipsoid or dome with semi-axes @code(Radii) $(R_x, R_y, R_z)$
      centered at the active selection pivot using a Fibonacci golden-angle
      spherical lattice scaled to $(R_x, R_y, R_z)$.
      When @code(UpperHemisphereOnly = true), places items over the upper dome ($y \ge C_y$).
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient outward along the analytic 3D ellipsoid surface normal
        $\mathbf(N)_i \propto (s_(ix)/R_x, s_(iy)/R_y, s_(iz)/R_z)$
      - @code(2): orient inward toward the ellipsoid center
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnEllipsoid(
      const Radii: TVector3;
      const UpperHemisphereOnly: Boolean = false;
      const OrientMode: Integer = 0): Boolean;

    { Apply a linear 3D spatial shear / skew transformation across all top-level
      selected transforms (@code(SelectedCount >= 2)) relative to the active
      selection pivot $\mathbf(C)$:
      $P'_(\text(ShearAxis)) = P_(\text(ShearAxis)) + \text(ShearFactor) \cdot (P_(\text(ReferenceAxis)) - C_(\text(ReferenceAxis)))$.
      When @code(TiltOrientation = true), also tilts each selected transform's
      orientation by $\arctan(\text(ShearFactor))$ from @code(ReferenceAxis)
      toward @code(ShearAxis).
      Returns @true if at least one selected transform was modified. }
    function ShearSelected(
      const ShearAxis, ReferenceAxis: T3DAxis;
      const ShearFactor: Single;
      const TiltOrientation: Boolean = false): Boolean;

    { Apply a 3D helical twist deformation around @code(TwistAxis) passing
      through the active selection pivot $\mathbf(C)$ across all top-level
      selected transforms (@code(SelectedCount >= 2)).
      Each transform is rotated around @code(TwistAxis) by an angle linearly
      interpolated from $-\text(TotalAngleRad)/2$ at the minimum coordinate
      along @code(TwistAxis) to $+\text(TotalAngleRad)/2$ at the maximum
      coordinate along @code(TwistAxis) (or by selection index if all items
      share the same coordinate along @code(TwistAxis)).
      When @code(RotateOrientations = true), also twists each transform's
      orientation around @code(TwistAxis) by the same angle.
      Returns @true if at least one selected transform was modified. }
    function TwistSelected(
      const TwistAxis: T3DAxis;
      const TotalAngleRad: Single;
      const RotateOrientations: Boolean = true): Boolean;

    { Apply a linear 3D spatial taper (pinch / flare) deformation along
      @code(TaperAxis) across all top-level selected transforms
      (@code(SelectedCount >= 2)) relative to the active selection pivot $\mathbf(C)$.
      For each transform with normalized position $t_i \in [0, 1]$ from the
      minimum to maximum coordinate along @code(TaperAxis), scales its two
      perpendicular world offsets from $\mathbf(C)$ by
      $s_i = \operatorname(Lerp)(t_i, 1.0, \text(TopScaleFactor))$.
      When @code(ScaleObjects = true), also scales each transform's local
      @code(Scale) along the two perpendicular axes by $s_i$.
      Returns @true if at least one selected transform was modified. }
    function TaperSelected(
      const TaperAxis: T3DAxis;
      const TopScaleFactor: Single;
      const ScaleObjects: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a continuous 3D pole-to-pole spherical spiral curve on a sphere
      of radius @code(Radius) centered at the active selection pivot $\mathbf(C)$
      with @code(Turns) full revolutions from bottom pole ($y = -R$) to top
      pole ($y = +R$).
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient radially outward from the sphere center
      - @code(2): orient along the analytical 3D spherical spiral tangent
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInSphericalSpiral(
      const Radius, Turns: Single;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      around a 3D Superellipse (Lamé curve / Squircle / Astroid star) on the
      horizontal XZ plane centered at the active selection pivot $\mathbf(C)$:
      $x(\theta) = C_x + R_x \operatorname(sgn)(\cos\theta)|\cos\theta|^(2/n)$,
      $z(\theta) = C_z + R_z \operatorname(sgn)(\sin\theta)|\sin\theta|^(2/n)$.
      - @code(ExponentN = 0.6667) ($p = 3$): 4-cusped Astroid star
      - @code(ExponentN = 1.0) ($p = 2$): diamond / rhombus
      - @code(ExponentN = 2.0) ($p = 1$): standard ellipse
      - @code(ExponentN = 4.0) ($p = 0.5$): rounded squircle stadium
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the center
      - @code(2): orient horizontally outward from the center
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInSuperellipse(
      const RadiusX, RadiusZ, ExponentN: Single;
      const OrientMode: Integer = 0): Boolean;

    { Apply a 3D circular arc bend deformation across all top-level selected
      transforms (@code(SelectedCount >= 2)) along @code(SpineAxis) toward
      @code(BendDirAxis) by a total arc angle of @code(TotalAngleRad) radians
      centered at the active selection pivot $\mathbf(C)$:
      - Radius of curvature $R = \text(Span) / \text(TotalAngleRad)$
      - Bend angle $\theta_i = ((P_(i,\text(Spine)) - C_(\text(Spine))) / \text(Span)) \cdot \text(TotalAngleRad)$
      - Effective radial distance $r_i = R - (P_(i,\text(BendDir)) - C_(\text(BendDir)))$
      - $P'_(i,\text(Spine)) = C_(\text(Spine)) + r_i \sin(\theta_i)$
      - $P'_(i,\text(BendDir)) = C_(\text(BendDir)) + R - r_i \cos(\theta_i)$
      When @code(RotateOrientations = true), also rotates each transform's
      orientation by $\theta_i$ from @code(SpineAxis) toward @code(BendDirAxis).
      Returns @true if at least one selected transform was modified. }
    function BendSelected(
      const SpineAxis, BendDirAxis: T3DAxis;
      const TotalAngleRad: Single;
      const RotateOrientations: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Viviani's curve (spherical figure-8 window formed by the
      intersection of a sphere of radius @code(Radius) and a tangent cylinder)
      centered at the active selection pivot $\mathbf(C)$:
      $\theta_i = \frac(2\pi i)(N)$,
      $x(\theta_i) = C_x + R \cos^2(\theta_i)$,
      $y(\theta_i) = C_y + R \sin(\theta_i)$,
      $z(\theta_i) = C_z + R \sin(\theta_i)\cos(\theta_i)$.
      Every placed point lies on the sphere of radius $R$ centered at $\mathbf(C)$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient radially outward along the sphere surface normal
      - @code(2): orient forward along the analytical 3D Viviani curve tangent
        $\mathbf(T)(\theta_i) \propto (-\sin(2\theta_i), \cos(\theta_i), \cos(2\theta_i))$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInVivianiCurve(
      const Radius: Single = 0.0;
      const OrientMode: Integer = 0): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Hypotrochoid (@code(Epitrochoid = false)) or Epitrochoid
      (@code(Epitrochoid = true)) Spirograph gear curve on the horizontal XZ
      plane centered at the active selection pivot $\mathbf(C)$:
      - Hypotrochoid:
        $x(\theta) = C_x + (R - r)\cos\theta + d\cos\left(\frac(R - r)(r)\theta\right)$,
        $z(\theta) = C_z + (R - r)\sin\theta - d\sin\left(\frac(R - r)(r)\theta\right)$
      - Epitrochoid:
        $x(\theta) = C_x + (R + r)\cos\theta - d\cos\left(\frac(R + r)(r)\theta\right)$,
        $z(\theta) = C_z + (R + r)\sin\theta - d\sin\left(\frac(R + r)(r)\theta\right)$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward the spirograph center
      - @code(2): orient forward along the analytical spirograph tangent vector
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInSpirograph(
      const FixedRadiusR, RollingRadiusSmallR, PenOffsetD: Single;
      const Epitrochoid: Boolean = false;
      const OrientMode: Integer = 0): Boolean;

    { Morph / deform all top-level selected transforms (@code(SelectedCount >= 2))
      toward or away from a 3D sphere of radius @code(TargetRadius) centered at the
      active selection pivot $\mathbf(C)$ by blending factor @code(StrengthFactor):
      - When @code(TargetRadius <= 0), auto-computes the average 3D distance $R$
        from $\mathbf(C)$ across the selected transforms.
      - Each transform at distance $d_i = \|\mathbf(P)_i - \mathbf(C)\|$ is moved to
        radial distance $d'_i = \operatorname(Lerp)(\text(StrengthFactor), d_i, R)$
        along its radial direction from $\mathbf(C)$:
        - @code(StrengthFactor = 0.0): no change
        - @code(StrengthFactor = 0.5): 50% spherical bulge / roundness
        - @code(StrengthFactor = 1.0): 100% spherical projection onto radius $R$
        - @code(StrengthFactor < 0.0): pinch / exaggerate non-spherical corners
      - When @code(OrientRadially = true), also rotates each transform to face
        radially outward from $\mathbf(C)$.
      Returns @true if at least one selected transform was modified. }
    function SpherifySelected(
      const TargetRadius: Single;
      const StrengthFactor: Single = 0.5;
      const OrientRadially: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Möbius Strip / Twisted Ribbon of major radius @code(MajorRadius)
      and half-width @code(StripHalfWidth) with @code(HalfTwists) half-twists
      (default @code(1) for a classic single-sided Möbius strip, @code(2) for a
      full-twist ribbon) centered at the active selection pivot $\mathbf(C)$:
      $u_i = \frac(2\pi i)(N), \quad \alpha_i = \text(HalfTwists) \cdot \frac(u_i)(2), \quad v_i = (-1)^i W$,
      $x_i = C_x + (R + v_i \cos\alpha_i)\cos u_i$,
      $y_i = C_y + v_i \sin\alpha_i$,
      $z_i = C_z + (R + v_i \cos\alpha_i)\sin u_i$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient Up along the local twisted Möbius strip normal and
        forward along the ribbon centerline tangent
      - @code(2): orient horizontally inward toward the central axis
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInMobiusStrip(
      const MajorRadius, StripHalfWidth: Single;
      const HalfTwists: Integer = 1;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Parametric Heart Curve (@code(HeartShape = true)) or Cardioid
      Curve (@code(HeartShape = false)) on the horizontal XZ plane centered at
      the active selection pivot $\mathbf(C)$ with optional vertical wave
      elevation @code(VerticalWave):
      - Heart (@code(HeartShape = true)):
        $x(t) = C_x + S \sin^3 t$,
        $z(t) = C_z - S \cdot \frac(13\cos t - 5\cos 2t - 2\cos 3t - \cos 4t)(16)$
      - Cardioid (@code(HeartShape = false)):
        $r(t) = 0.5 S (1 - \sin t), \quad x(t) = C_x + r(t)\cos t, \quad z(t) = C_z + r(t)\sin t$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward $\mathbf(C)$
      - @code(2): orient horizontally outward away from $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInCardioidOrHeart(
      const SizeScale: Single;
      const HeartShape: Boolean = true;
      const VerticalWave: Single = 0.0;
      const OrientMode: Integer = 1): Boolean;

    { Apply a concentric 3D radial ripple / water-drop wave deformation across all
      top-level selected transforms (@code(SelectedCount >= 2)) around the active
      selection pivot $\mathbf(C)$:
      - Horizontal radial distance $r_i = \sqrt((P_(i,x) - C_x)^2 + (P_(i,z) - C_z)^2)$
      - Wave number $k = 2\pi / \max(0.01, \text(Wavelength))$
      - Vertical wave displacement:
        $\Delta y_i = \text(Amplitude) \cdot e^(-\max(0, \text(DecayRate)) \cdot r_i) \cdot \cos(k r_i + \text(PhaseRad))$
      - When @code(TiltNormals = true), tilts each transform's world $+Y$ Up axis
        to match the analytical ripple surface normal
        $\mathbf(N)_i = \operatorname(Normalize)(-\frac(\partial y)(\partial r)\frac(\Delta x_i)(r_i), 1, -\frac(\partial y)(\partial r)\frac(\Delta z_i)(r_i))$.
      Returns @true if at least one selected transform was modified. }
    function RippleSelected(
      const Amplitude, Wavelength: Single;
      const PhaseRad: Single = 0.0;
      const DecayRate: Single = 0.0;
      const TiltNormals: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Lemniscate of Bernoulli (classic $\infty$ infinity loop /
      figure-8 overpass track) centered at the active selection pivot $\mathbf(C)$:
      $t_i = \frac(2\pi i)(N)$,
      $x(t_i) = C_x + \frac(a \cos t_i)(1 + \sin^2 t_i)$,
      $z(t_i) = C_z + \frac(a \sin t_i \cos t_i)(1 + \sin^2 t_i)$,
      $y(t_i) = C_y + H \sin t_i$,
      where $a = \text(HalfWidthA)$ (auto-computed when $\le 0$) is the half-width
      of the infinity lobes and $H = \text(VerticalBridgeLift)$ optionally lifts
      one crossing pass over the other at the central origin.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical 3D lemniscate curve tangent
      - @code(2): orient horizontally inward toward $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInLemniscate(
      const HalfWidthA: Single = 0.0;
      const VerticalBridgeLift: Single = 0.0;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a continuous 3D Toroidal Solenoid / Helical Coil winding
      @code(CoilWindings) times around a torus of major radius @code(MajorRadius)
      and minor tube radius @code(MinorRadius) centered at the active selection
      pivot $\mathbf(C)$:
      $u_i = \frac(2\pi i)(N), \quad v_i = \text(CoilWindings) \cdot u_i$,
      $x_i = C_x + (R + r\cos v_i)\cos u_i$,
      $y_i = C_y + r\sin v_i$,
      $z_i = C_z + (R + r\cos v_i)\sin u_i$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical 3D solenoid coil tangent
        with outward tube normal as Up
      - @code(2): orient radially outward from the torus tube centerline
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInTorusHelix(
      const MajorRadius: Single = 0.0;
      const MinorRadius: Single = 0.0;
      const CoilWindings: Single = 6.0;
      const OrientMode: Integer = 1): Boolean;

    { Apply a volume-preserving 3D squash & stretch deformation along @code(Axis)
      across all top-level selected transforms (@code(SelectedCount >= 1))
      by @code(StretchFactor) ($> 0$, clamped to $\ge 0.05$):
      - Longitudinal scale factor along @code(Axis): $s_\parallel = \text(StretchFactor)$
      - Cross-sectional scale factor along the two perpendicular axes:
        $s_\perp = \frac(1)(\sqrt(\text(StretchFactor)))$ so $s_\parallel \cdot s_\perp^2 = 1$.
      - When @code(AnchorAtBase = true) and 2+ transforms are selected, anchors
        the longitudinal stretch/squash at the minimum coordinate along @code(Axis)
        so grounded props remain planted at their base; otherwise anchors at the
        active selection pivot $\mathbf(C)$.
      - When @code(ScaleObjects = true), also multiplies each transform's local
        @code(Scale) by the volume-preserving factors $(s_\parallel, s_\perp, s_\perp)$.
      Returns @true if at least one selected transform was modified. }
    function VolumeSquashStretchSelected(
      const Axis: T3DAxis;
      const StretchFactor: Single;
      const AnchorAtBase: Boolean = true;
      const ScaleObjects: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along Temple H. Fay's 3D Parametric Butterfly Curve centered at the active
      selection pivot $\mathbf(C)$:
      $t_i = \frac(2\pi i)(N)$,
      $r(t_i) = e^(\sin t_i) - 2\cos(4 t_i) + \sin^5\!\left(\frac(2 t_i - \pi)(24)\right)$,
      $x(t_i) = C_x + S \cdot r(t_i)\cos t_i$,
      $z(t_i) = C_z + S \cdot r(t_i)\sin t_i$,
      $y(t_i) = C_y + \text(WingFlapHeight) \cdot |\cos t_i|$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient horizontally inward toward $\mathbf(C)$
      - @code(2): orient horizontally outward away from $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInButterflyCurve(
      const SizeScale: Single = 0.0;
      const WingFlapHeight: Single = 0.0;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Clélie Curve (spherical rosette / polar satellite orbit on a
      sphere of radius @code(Radius) where latitude $\phi = m \theta$) centered
      at the active selection pivot $\mathbf(C)$:
      $\theta_i = \frac(2\pi i)(N), \quad \phi_i = m \theta_i$,
      $x_i = C_x + R \cos\phi_i \cos\theta_i$,
      $y_i = C_y + R \sin\phi_i$,
      $z_i = C_z + R \cos\phi_i \sin\theta_i$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward radially outward along the sphere surface normal
        with analytical Clélie tangent as Up
      - @code(2): orient forward along the analytical 3D Clélie curve tangent
        with outward sphere surface normal as Up
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInClelieCurve(
      const Radius: Single = 0.0;
      const PetalRatioM: Single = 2.0;
      const OrientMode: Integer = 1): Boolean;

    { Apply a 3D radial vortex / swirl deformation around @code(Axis) passing
      through the active selection pivot $\mathbf(C)$ across all top-level
      selected transforms (@code(SelectedCount >= 2)).
      Each transform at radial distance $r_i$ from the swirl axis is rotated
      around @code(Axis) by a radially decaying angle:
      $$\theta_i = \text(MaxCenterAngleRad) \cdot \max\left(0, 1 - \frac(r_i)(R_(\text(falloff)))\right)$$
      so objects near the center ($r_i \to 0$) twist by the full @code(MaxCenterAngleRad)
      while objects at or beyond $R_(\text(falloff))$ remain stationary.
      When @code(FalloffRadius <= 0), automatically sets $R_(\text(falloff)) = 1.25 \max_i(r_i)$.
      When @code(RotateOrientations = true), also rotates each transform's world
      orientation around @code(Axis) by $\theta_i$.
      Returns @true if at least one selected transform was modified. }
    function SwirlSelected(
      const Axis: T3DAxis = 1;
      const MaxCenterAngleRad: Single = Pi;
      const FalloffRadius: Single = 0.0;
      const RotateOrientations: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Trefoil Knot ($3_1$, @code(FigureEightKnot = false)) or
      Figure-Eight / Listing's Knot ($4_1$, @code(FigureEightKnot = true))
      of outer horizontal radius @code(Radius) centered at the active selection
      pivot $\mathbf(C)$:
      - Trefoil Knot (@code(FigureEightKnot = false)):
        $x(t) = C_x + \frac(R)(3)(\sin t + 2\sin 2t)$,
        $y(t) = C_y - \frac(R)(3)\sin 3t$,
        $z(t) = C_z + \frac(R)(3)(\cos t - 2\cos 2t)$
      - Figure-Eight Knot (@code(FigureEightKnot = true)):
        $x(t) = C_x + \frac(R)(3)(2 + \cos 2t)\cos 3t$,
        $y(t) = C_y + \frac(R)(3)\sin 4t$,
        $z(t) = C_z + \frac(R)(3)(2 + \cos 2t)\sin 3t$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical 3D knot curve tangent
      - @code(2): orient horizontally outward from $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInKnotCurve(
      const Radius: Single = 0.0;
      const FigureEightKnot: Boolean = false;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      across concentric horizontal latitude rings of a 3D Geodesic / Upper-Hemisphere
      Dome of radius @code(Radius) ($y \in [C_y, C_y + R]$) centered at the active
      selection pivot $\mathbf(C)$:
      - Places @code(Selected[0]) at the dome apex $(C_x, C_y + R, C_z)$ and
        distributes the remaining items across @code(RingsCount) latitude tiers
        (auto-computed when @code(RingsCount <= 0)) with ring capacity proportional
        to $\sin\phi_r$ and half-step azimuth stagger on alternating rings.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): align each transform's $+Y$ Up axis with the outward dome normal
      - @code(2): orient forward radially inward toward the dome center $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInGeodesicDome(
      const Radius: Single = 0.0;
      const RingsCount: Integer = 0;
      const OrientMode: Integer = 1): Boolean;

    { Apply a 3D radial implode / explode / gravity-well displacement with
      Gaussian distance falloff around the active selection pivot $\mathbf(C)$
      across all top-level selected transforms (@code(SelectedCount >= 2)).
      Each transform at radial distance $d_i = \|\mathbf(P)_i - \mathbf(C)\|$ is
      radially displaced along $\hat(\mathbf(u))_i = (\mathbf(P)_i - \mathbf(C)) / d_i$
      to a new radial distance:
      $$d'_i = \max\left(0, d_i + \text(Strength) \cdot \exp\left(-\left(\frac(d_i)(R_(\text(falloff)))\right)^2\right)\right)$$
      where positive @code(Strength > 0) pushes objects outward (explode / shockwave)
      and negative @code(Strength < 0) pulls objects inward toward $\mathbf(C)$
      (gravity well / implode, clamped at $d'_i \ge 0$).
      When @code(FalloffRadius <= 0), automatically sets $R_(\text(falloff))$ to the
      average distance from $\mathbf(C)$ (fallback $5.0$).
      When @code(ScaleWithDisplacement = true), also uniformly scales each transform
      proportionally to the local radial falloff intensity.
      Returns @true if at least one selected transform was modified. }
    function RadialFalloffSelected(
      const Strength: Single = 3.0;
      const FalloffRadius: Single = 0.0;
      const ScaleWithDisplacement: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D $k$-cusped Hypocycloid (@code(Epicycloid = false), e.g. Deltoid
      $k=3$, Astroid $k=4$) or Epicycloid (@code(Epicycloid = true), e.g. Nephroid
      $k=2$, Ranunculoid $k=5$) of outer radius @code(Radius) in the horizontal
      XZ plane centered at the active selection pivot $\mathbf(C)$:
      - Hypocycloid (@code(Epicycloid = false)):
        $x(t) = C_x + \frac(R)(k)((k - 1)\cos t + \cos((k - 1)t))$,
        $z(t) = C_z + \frac(R)(k)((k - 1)\sin t - \sin((k - 1)t))$
      - Epicycloid (@code(Epicycloid = true)):
        $x(t) = C_x + \frac(R)(k + 2)((k + 1)\cos t - \cos((k + 1)t))$,
        $z(t) = C_z + \frac(R)(k + 2)((k + 1)\sin t - \sin((k + 1)t))$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical cycloid curve tangent
      - @code(2): orient horizontally outward from $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInCycloid(
      const Radius: Single = 0.0;
      const Cusps: Integer = 4;
      const Epicycloid: Boolean = false;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      across a 3D Hyperboloid of One Sheet (doubly-ruled cooling-tower / hourglass
      shell) centered at the active selection pivot $\mathbf(C)$ with waist radius
      @code(WaistRadius), vertical span @code(HeightSpan), and rim flare factor
      @code(FlareFactor):
      $$u_i = -1 + \frac(2i)(N - 1), \quad y_i = C_y + \frac(H)(2) u_i, \quad
        r_i = R_(\text(waist))\sqrt(1 + (\text(FlareFactor) \cdot u_i)^2)$$
      $$x_i = C_x + r_i \cos(i \cdot \phi_(\text(golden))), \quad
        z_i = C_z + r_i \sin(i \cdot \phi_(\text(golden)))$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the outward hyperboloid surface normal
      - @code(2): orient forward along the straight-line hyperboloid ruling generator
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnHyperboloid(
      const WaistRadius: Single = 0.0;
      const HeightSpan: Single = 10.0;
      const FlareFactor: Single = 1.0;
      const OrientMode: Integer = 1): Boolean;

    { Deform all top-level selected transforms (@code(SelectedCount >= 2))
      toward a vertical 3D Cylinder (`CapsuleHemispheres = false`) or 3D Capsule /
      Pill shell with hemispherical end-caps (`CapsuleHemispheres = true`) of radius
      @code(TargetRadius) centered at the active selection pivot $\mathbf(C)$,
      blending each transform's world position from its original position toward
      the cylinder/capsule shell by @code(StrengthFactor) ($\in [0, 1]$).
      When @code(OrientRadially) is @true, each transform is also rotated to face
      outward along the cylinder or capsule surface normal.
      Returns @true if at least one selected transform was modified. }
    function CylindrifySelected(
      const TargetRadius: Single = 0.0;
      const StrengthFactor: Single = 1.0;
      const CapsuleHemispheres: Boolean = false;
      const OrientRadially: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Cassini Oval (pinched peanut / biconcave red-blood-cell / stadium loop)
      in the horizontal XZ plane around the active selection pivot $\mathbf(C)$:
      $$r(\theta) = a\sqrt(\max(0, \cos(2\theta) + \sqrt(\max(0, c^4 - \sin^2(2\theta))))), \quad
        c = \max(1.0001, \text(ShapeRatioBOverA))$$
      $$x(\theta) = C_x + r(\theta)\cos\theta, \quad
        z(\theta) = C_z + r(\theta)\sin\theta, \quad
        y(\theta) = C_y + \text(VerticalRimWave)\cos(2\theta)$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical 3D Cassini oval tangent
      - @code(2): orient forward inward toward the oval center $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInCassiniOval(
      const FocusHalfDistA: Single = 0.0;
      const ShapeRatioBOverA: Single = 1.11803399;
      const VerticalRimWave: Single = 0.0;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      across a 3D Catenoid Minimal Surface (soap-film waist / hyperbolic-cosine shell)
      centered at the active selection pivot $\mathbf(C)$ with waist radius
      @code(WaistRadius), vertical span @code(HeightSpan), and neck curvature
      @code(NeckCurvature):
      $$u_i = -1 + \frac(2i)(N - 1), \quad y_i = C_y + \frac(H)(2)u_i, \quad
        r_i = R_(\text(waist))\cosh(\kappa u_i), \quad
        \theta_i = i \cdot \phi_(\text(golden))$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the outward catenoid minimal-surface normal
      - @code(2): orient forward along the catenary meridian profile tangent
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnCatenoid(
      const WaistRadius: Single = 0.0;
      const HeightSpan: Single = 8.0;
      const NeckCurvature: Single = 1.0;
      const OrientMode: Integer = 1): Boolean;

    { Deform all top-level selected transforms (@code(SelectedCount >= 2))
      radially perpendicular to @code(Axis) ($0 = X, 1 = Y, 2 = Z$) around the
      active selection pivot $\mathbf(C)$ using a quadratic Barrel bulge
      (@code(BulgeFactor > 0)) or Pincushion / Corset waist pinch
      (@code(BulgeFactor < 0)):
      $$u_i = \text(Clamped)\left(\frac(P_(\text(axis),i) - C_(\text(axis)))(H_(\text(half))), -1, 1\right), \quad
        s(u_i) = \max\left(0.05, \; 1.0 + \text(BulgeFactor) \cdot (1.0 - u_i^2)\right)$$
      When @code(ScaleObjects) is @true, each transform's local @code(Scale)
      perpendicular to @code(Axis) is also multiplied by $s(u_i)$.
      Returns @true if at least one selected transform was modified. }
    function BarrelPincushionSelected(
      const Axis: Integer = 1;
      const BulgeFactor: Single = 0.5;
      const ScaleObjects: Boolean = false): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Spherical Hippopede (Eudoxus Kampyle / Horse-Fetter curve on a
      sphere of radius @code(Radius) centered at the active selection pivot $\mathbf(C)$):
      $$r_(xz)(t) = R\sqrt(\max(0, 1 - \lambda\sin^2 t)), \quad \lambda = \text(Clamped)(\text(PinchLambda), 0, 1)$$
      $$x(t) = C_x + r_(xz)(t)\cos t, \quad y(t) = C_y + R\sqrt(\lambda)\sin t, \quad z(t) = C_z + r_(xz)(t)\sin t$$
      Every point lies identically on the sphere $(x - C_x)^2 + (y - C_y)^2 + (z - C_z)^2 = R^2$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the outward sphere normal
      - @code(2): orient forward along the 3D Hippopede curve tangent
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInHippopede(
      const Radius: Single = 0.0;
      const PinchLambda: Single = 0.64;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      across a 3D Ruled Helicoid Minimal Surface (Archimedes screw / spiral ramp shell)
      centered at the active selection pivot $\mathbf(C)$ with outer blade radius
      @code(OuterRadius), vertical span @code(HeightSpan), and @code(Turns) revolutions:
      $$u_i = -1 + \frac(2i)(N - 1), \quad y_i = C_y + \frac(H)(2)u_i, \quad
        \theta_i = \pi \cdot \text(Turns) \cdot u_i, \quad s_i = (-1)^i R_(\text(outer))$$
      $$x_i = C_x + s_i \cos\theta_i, \quad z_i = C_z + s_i \sin\theta_i$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical Helicoid minimal-surface normal $(c\sin\theta_i, R, -c\cos\theta_i)$
      - @code(2): orient forward along the straight horizontal Helicoid ruling $(\cos\theta_i, 0, \sin\theta_i)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnHelicoid(
      const OuterRadius: Single = 0.0;
      const HeightSpan: Single = 10.0;
      const Turns: Single = 1.0;
      const OrientMode: Integer = 1): Boolean;

    { Deform all top-level selected transforms (@code(SelectedCount >= 2))
      along @code(DisplaceAxis) ($0 = X, 1 = Y, 2 = Z$) as a sinusoidal wave
      function of their signed coordinate along @code(WaveAxis) ($0 = X, 1 = Y, 2 = Z$)
      relative to the active selection pivot $\mathbf(C)$:
      $$\phi_i = \frac(2\pi)(\lambda)(P_(\text(WaveAxis),i) - C_(\text(WaveAxis))) + \text(PhaseRad), \quad
        \Delta d_i = \text(Amplitude) \cdot \sin(\phi_i)$$
      When @code(OrientNormals) is @true, each transform's orientation is tilted
      to match the analytical wave tangent and normal vectors.
      Returns @true if at least one selected transform was modified. }
    function WaveDeformSelected(
      const WaveAxis: Integer = 0;
      const DisplaceAxis: Integer = 1;
      const Amplitude: Single = 2.0;
      const Wavelength: Single = 10.0;
      const PhaseRad: Single = 0.0;
      const OrientNormals: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      across a 3D Enneper Minimal Surface saddle shell of order @code(OrderK) ($\ge 1$)
      centered at the active selection pivot $\mathbf(C)$:
      $$u_i = \frac(i)(N - 1), \quad r_i = R_(\max)\sqrt(u_i), \quad \theta_i = 2\pi u_i$$
      $$x_i = C_x + S\left(r_i\cos\theta_i - \frac(r_i^(2k+1))(2k+1)\cos((2k+1)\theta_i)\right)$$
      $$y_i = C_y + S\left(\frac(2)(k+1)r_i^(k+1)\cos((k+1)\theta_i)\right)$$
      $$z_i = C_z + S\left(-r_i\sin\theta_i - \frac(r_i^(2k+1))(2k+1)\sin((2k+1)\theta_i)\right)$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the exact Gauss-map Enneper minimal-surface normal
      - @code(2): orient forward along the Enneper azimuthal surface tangent
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnEnneperSurface(
      const ScaleRadius: Single = 0.0;
      const MaxR: Single = 1.15;
      const OrderK: Integer = 1;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      around a horizontal 3D Gear-Tooth / Castle Battlement Crenellation / Sawtooth
      Starburst ring centered at the active selection pivot $\mathbf(C)$ with
      pitch radius @code(PitchRadius), radial tooth modulation @code(ToothDepth),
      and @code(TeethCount) teeth:
      - When @code(SharpSawtooth) is @false (harmonic gear / crenellation profile):
        $r(\theta_i) = \max(0.05, R_(\text(pitch)) + D\cos(M\theta_i))$
      - When @code(SharpSawtooth) is @true (ratchet sawtooth starburst profile):
        $r(\theta_i) = \max(0.05, R_(\text(pitch)) + D(2\tau_i - 1))$ where $\tau_i = \text(Frac)(M i / N)$.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the outward gear profile normal
      - @code(2): orient forward along the analytical gear rim tangent
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInGearWheel(
      const PitchRadius: Single = 0.0;
      const ToothDepth: Single = 2.0;
      const TeethCount: Integer = 6;
      const SharpSawtooth: Boolean = false;
      const OrientMode: Integer = 1): Boolean;

    { Deform all top-level selected transforms (@code(SelectedCount >= 2))
      using a 3D Hyperbolic Paraboloid / Pringle Saddle / Parabolic Dome
      curvature deformer along @code(DisplaceAxis) (@code(0)=X, @code(1)=Y, @code(2)=Z)
      across the two orthogonal span axes $(U, V)$ relative to the active selection pivot $\mathbf(C)$:
      $$\Delta d_i = K_u u_i^2 + K_v v_i^2, \quad u_i = \text(Clamped)\left(\frac(P_i[U] - C[U])(R_u), -1, 1\right), \quad v_i = \text(Clamped)\left(\frac(P_i[V] - C[V])(R_v), -1, 1\right)$$
      When $K_u \cdot K_v < 0$, produces a hyperbolic paraboloid (Pringle saddle roof);
      when $K_u, K_v < 0$, produces a parabolic dome; when $K_u, K_v > 0$, produces a parabolic dish/bowl;
      when $K_v = 0$, produces a parabolic barrel vault.
      When @code(OrientNormals) is @true, orients each transform using the analytical
      paraboloid surface tangent and normal vectors.
      Returns @true if at least one selected transform was modified. }
    function SaddleDomeDeformSelected(
      const DisplaceAxis: Integer = 1;
      const CurvatureU: Single = 3.0;
      const CurvatureV: Single = -3.0;
      const OrientNormals: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Figure-8 Klein Bottle Immersion Shell centered at the active
      selection pivot $\mathbf(C)$ with major radius @code(MajorRadius) ($R$),
      figure-8 lobe amplitude @code(LobeRadius) ($A$), and @code(Turns) ($W$)
      twist revolutions:
      $$u_i = \frac(2\pi i)(N), \quad v_i = \frac(2\pi W i)(N), \quad \rho_i = R + A\left(\cos\frac(u_i)(2)\sin v_i - \sin\frac(u_i)(2)\sin(2v_i)\right)$$
      $$x_i = C_x + \rho_i \cos u_i, \quad y_i = C_y + A\left(\sin\frac(u_i)(2)\sin v_i + \cos\frac(u_i)(2)\sin(2v_i)\right), \quad z_i = C_z + \rho_i \sin u_i$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical immersion curve tangent
      - @code(2): orient forward radially outward from the central $Y$ axis
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnKleinBottle(
      const MajorRadius: Single = 0.0;
      const LobeRadius: Single = 2.5;
      const Turns: Single = 2.0;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Parabolic Fermat Spiral / Dual-Arm Barred Galaxy Pinwheel
      centered at the active selection pivot $\mathbf(C)$ with outer radius
      @code(OuterRadius) ($R_(\max)$), @code(Turns) ($W$) revolutions, and
      vertical rise @code(VerticalRise) ($H$):
      $$r_i = R_(\max)\sqrt(u_i), \quad \theta_i = 2\pi W u_i + \phi_i$$
      When @code(DualArmPinwheel) is @true, odd-indexed items receive phase
      offset $\phi_i = \pi$ to form a symmetric two-arm barred spiral galaxy.
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical Fermat spiral tangent
      - @code(2): orient forward radially outward from the spiral center
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInFermatSpiral(
      const OuterRadius: Single = 0.0;
      const Turns: Single = 2.0;
      const VerticalRise: Single = 0.0;
      const DualArmPinwheel: Boolean = false;
      const OrientMode: Integer = 1): Boolean;

    { Project / blend all top-level selected transforms (@code(SelectedCount >= 2))
      onto a 3D Generalized $\ell_p$-Norm Octahedral Diamond / Superquadric Shell
      centered at the active selection pivot $\mathbf(C)$ with shell radius
      @code(Radius) ($R$) and norm exponent @code(ExponentP) ($p > 0$):
      $$\|\mathbf(d)_i\|_p = \left(|d_x|^p + |d_y|^p + |d_z|^p\right)^(1/p), \quad
        \mathbf(P)^(\text(target))_i = \mathbf(C) + \frac(R)(\|\mathbf(d)_i\|_p)\mathbf(d)_i$$
      - $p = 1.0$: 3D Octahedron / Diamond shell ($|x| + |y| + |z| = R$)
      - $p = 0.5$: 3D Astroidal Star-Octahedron shell
      - $p = 4.0$: 3D Rounded Cube Superquadric shell
      Blends each transform's world position by @code(Strength) $\in [0, 1]$.
      When @code(OrientNormals) is @true, orients each transform's forward axis
      along the analytical outward $\ell_p$ surface normal
      $\nabla \|\mathbf(d)\|_p^p \propto (\text(sgn)(d_x)|d_x|^(p-1), \text(sgn)(d_y)|d_y|^(p-1), \text(sgn)(d_z)|d_z|^(p-1))$.
      Returns @true if at least one selected transform was modified. }
    function OctahedralDeformSelected(
      const Radius: Single = 0.0;
      const ExponentP: Single = 1.0;
      const Strength: Single = 1.0;
      const OrientNormals: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      across a 3D Ulisse Dini Pseudospherical Twisted Horn Surface centered at
      the active selection pivot $\mathbf(C)$ with radial scale @code(RadiusA) ($a$),
      helical pitch @code(PitchB) ($b$), and @code(Turns) ($W$) revolutions:
      $$t_i = \frac(i)(N - 1), \quad u_i = 2\pi W t_i, \quad v_i = \frac(\pi)(6) + \frac(\pi)(3)t_i$$
      $$x_i = C_x + a\cos u_i \sin v_i, \quad z_i = C_z + a\sin u_i \sin v_i, \quad
        y_i = C_y + a\left(\cos v_i + \ln\tan\frac(v_i)(2)\right) + b u_i$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical 3D Dini spiral curve tangent
      - @code(2): orient forward horizontally outward from the central $Y$ axis
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnDiniSurface(
      const RadiusA: Single = 0.0;
      const PitchB: Single = 1.2;
      const Turns: Single = 2.0;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Euler / Cornu Clothoid S-Curve Spiral centered at the active
      selection pivot $\mathbf(C)$ with scale length @code(ScaleLength) ($L$),
      maximum Fresnel parameter @code(MaxParamT) ($T_(\max)$), and vertical span
      @code(HeightSpan) ($H$):
      $$s_i = T_(\max)\left(\frac(2i)(N - 1) - 1\right), \quad
        C(s_i) = \int_0^(s_i)\cos\left(\frac(\pi)(2)\tau^2\right)d\tau, \quad
        S(s_i) = \int_0^(s_i)\sin\left(\frac(\pi)(2)\tau^2\right)d\tau$$
      $$x_i = C_x + L \cdot C(s_i), \quad y_i = C_y + H\left(\frac(i)(N - 1) - 0.5\right), \quad z_i = C_z + L \cdot S(s_i)$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the exact analytical Cornu tangent $(L\cos(\frac(\pi)(2)s_i^2), \frac(H)(2T_(\max)), L\sin(\frac(\pi)(2)s_i^2))$
      - @code(2): orient forward along the horizontal principal normal $(-\sin(\frac(\pi)(2)s_i^2), 0, \cos(\frac(\pi)(2)s_i^2))$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInCornuSpiral(
      const ScaleLength: Single = 0.0;
      const MaxParamT: Single = 1.6;
      const HeightSpan: Single = 0.0;
      const OrientMode: Integer = 1): Boolean;

    { Deform all top-level selected transforms (@code(SelectedCount >= 2))
      along the analytical gradient of a 3D Triply Periodic Minimal Surface
      (Schoen Gyroid when @code(SchwarzPMode = false), or Schwarz P Primitive
      Cubic Minimal Surface when @code(SchwarzPMode = true)) centered at the
      active selection pivot $\mathbf(C)$ with spatial period @code(Wavelength) ($\lambda$)
      and displacement @code(Amplitude) ($A$):
      - Schoen Gyroid (@code(SchwarzPMode = false)):
        $F(\mathbf(d)) = \sin(kx)\cos(ky) + \sin(ky)\cos(kz) + \sin(kz)\cos(kx)$
      - Schwarz P (@code(SchwarzPMode = true)):
        $F(\mathbf(d)) = \cos(kx) + \cos(ky) + \cos(kz)$
      where $k = 2\pi / \lambda$, displacing each transform by $A \cdot F(\mathbf(d)) \cdot \hat(\mathbf(g))$
      along the normalized spatial gradient $\hat(\mathbf(g)) = \nabla F / \|\nabla F\|$
      and optionally orienting its forward axis along $\hat(\mathbf(g))$ (@code(OrientNormals = true)).
      Returns @true if at least one selected transform was modified. }
    function GyroidDeformSelected(
      const Wavelength: Single = 0.0;
      const Amplitude: Single = 2.0;
      const SchwarzPMode: Boolean = false;
      const OrientNormals: Boolean = true): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      across Jakob Steiner's 3D Roman Projective Surface centered at the active
      selection pivot $\mathbf(C)$ with outer radius @code(Radius) ($R$) and
      azimuthal winding @code(Turns) ($W$):
      $$t_i = \frac(i)(N - 1), \quad u_i = \pi W t_i, \quad v_i = -\frac(\pi)(4) + \frac(\pi)(2)t_i$$
      $$x_i = C_x + \frac(R)(2)\sin(2u_i)\cos^2 v_i, \quad
        y_i = C_y + \frac(R)(2)\sin u_i \sin(2v_i), \quad
        z_i = C_z + \frac(R)(2)\cos u_i \sin(2v_i)$$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical Roman surface curve tangent
      - @code(2): orient forward radially outward from $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedOnRomanSurface(
      const Radius: Single = 0.0;
      const Turns: Single = 2.0;
      const OrientMode: Integer = 1): Boolean;

    { Arrange all top-level selected transforms (@code(SelectedCount >= 2))
      along a 3D Cochleoid Snail-Shell Spiral ($r(\theta) = A\frac(\sin\theta)(\theta)$)
      centered at the active selection pivot $\mathbf(C)$ with scale radius
      @code(ScaleRadius) ($A$), angular span @code(MaxAngleTurns) ($\Theta_(\max) = \pi W$),
      and vertical rise @code(HeightSpan) ($H$):
      - When @code(SymmetricDualLobe) is @false: $\theta_i = \Theta_(\max) t_i \in [0, \Theta_(\max)]$
      - When @code(SymmetricDualLobe) is @true: $\theta_i = \Theta_(\max)(2t_i - 1) \in [-\Theta_(\max), +\Theta_(\max)]$
      @code(OrientMode):
      - @code(0): keep current rotation
      - @code(1): orient forward along the analytical 3D Cochleoid tangent
      - @code(2): orient forward radially outward from $\mathbf(C)$
      Returns @true if at least one selected transform was modified. }
    function ArrangeSelectedInCochleoid(
      const ScaleRadius: Single = 0.0;
      const MaxAngleTurns: Single = 2.0;
      const HeightSpan: Single = 0.0;
      const SymmetricDualLobe: Boolean = false;
      const OrientMode: Integer = 1): Boolean;
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

function TCastleTransformManipulate.ArrangeSelectedInPolygon(
  const Sides: Integer;
  const OuterRadius: Single;
  const InnerRadius: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Vertices: array of TVector3;
  ValidCount, I, NumSides, NumVertices, EdgeIdx, NextEdgeIdx: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, TargetDir, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  EffOuter, EffInner, AvgExtent, Angle, R, EdgePos, EdgeFrac: Single;
  BBox: TBox3D;
  StarMode: Boolean;
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

  NumSides := Max(3, Sides);
  if AvgExtent > 1e-4 then
    AvgExtent := (AvgExtent / ValidCount) * 1.5
  else
    AvgExtent := 3.0;

  EffOuter := OuterRadius;
  if EffOuter <= 1e-4 then
    EffOuter := Max(2.0, AvgExtent * ValidCount / (2.0 * Pi));

  StarMode := InnerRadius > 1e-4;
  EffInner := InnerRadius;
  if StarMode then
    NumVertices := NumSides * 2
  else
    NumVertices := NumSides;

  if FPivotMode = pmSelectionCenter then
    CenterPos := SelectionWorkingCenter
  else
    CenterPos := GetTransformWorkingPos(Items[0]);

  SetLength(Vertices, NumVertices);
  for I := 0 to NumVertices - 1 do
  begin
    Angle := (2.0 * Pi * I) / NumVertices;
    if StarMode and Odd(I) then
      R := EffInner
    else
      R := EffOuter;
    Vertices[I] := CenterPos + Vector3(R * Cos(Angle), 0.0, R * Sin(Angle));
  end;

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    EdgePos := (Single(I) * NumVertices) / Single(ValidCount);
    EdgeIdx := Floor(EdgePos) mod NumVertices;
    if EdgeIdx < 0 then
      Inc(EdgeIdx, NumVertices);
    EdgeFrac := EdgePos - Floor(EdgePos);
    NextEdgeIdx := (EdgeIdx + 1) mod NumVertices;

    TargetPos := Lerp(EdgeFrac, Vertices[EdgeIdx], Vertices[NextEdgeIdx]);
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
        TargetDir := Vertices[NextEdgeIdx] - Vertices[EdgeIdx];
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

function TCastleTransformManipulate.ArrangeSelectedInSpiralVortex(
  const StartRadius, EndRadius: Single;
  const Turns: Single;
  const HeightSpan: Single;
  const Logarithmic: Boolean;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, TargetDir, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  EffStartR, EffEndR, EffTurns, ParamT, Theta, CurR, dRdt, dThetadt, SinTheta, CosTheta: Single;
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

  EffStartR := StartRadius;
  if EffStartR <= 1e-4 then
    EffStartR := 2.0;

  EffEndR := EndRadius;
  if EffEndR <= 1e-4 then
    EffEndR := EffStartR * 4.0;

  EffTurns := Turns;
  if Abs(EffTurns) <= 1e-4 then
    EffTurns := 2.0;

  if FPivotMode = pmSelectionCenter then
    CenterPos := SelectionWorkingCenter
  else
    CenterPos := GetTransformWorkingPos(Items[0]);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    ParamT := Single(I) / Single(ValidCount - 1);
    Theta := 2.0 * Pi * EffTurns * ParamT;
    SinCos(Theta, SinTheta, CosTheta);

    if Logarithmic and (EffStartR > 1e-4) and (EffEndR > 1e-4) then
    begin
      CurR := EffStartR * Power(EffEndR / EffStartR, ParamT);
      dRdt := CurR * Ln(EffEndR / EffStartR);
    end else
    begin
      CurR := Lerp(ParamT, EffStartR, EffEndR);
      dRdt := EffEndR - EffStartR;
    end;

    TargetPos := CenterPos + Vector3(
      CurR * CosTheta,
      HeightSpan * ParamT,
      CurR * SinTheta
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
        TargetDir := Vector3(CenterPos.X - TargetPos.X, 0.0, CenterPos.Z - TargetPos.Z);
        if TargetDir.IsZero(1e-5) then
          TargetDir := Vector3(-CosTheta, 0.0, -SinTheta);
      end else
      begin
        dThetadt := 2.0 * Pi * EffTurns;
        TargetDir := Vector3(
          dRdt * CosTheta - CurR * dThetadt * SinTheta,
          HeightSpan,
          dRdt * SinTheta + CurR * dThetadt * CosTheta
        );
        if TargetDir.IsZero(1e-5) then
          TargetDir := Vector3(-SinTheta, 0.0, CosTheta);
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

function TCastleTransformManipulate.ProjectSelectedOntoPlane(
  const PlanePoint, PlaneNormal: TVector3;
  const AlignUpToNormal: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  UnitNormal, CurPos, TargetPos, CurWorldPos, CurDir, CurUp, Side, NewDir: TVector3;
  SignedDist: Single;
begin
  Result := false;
  if SelectedCount < 1 then Exit;
  if PlaneNormal.IsZero(1e-6) then Exit;

  UnitNormal := PlaneNormal.Normalize;

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

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    SignedDist := TVector3.DotProduct(CurPos - PlanePoint, UnitNormal);
    TargetPos := CurPos - (UnitNormal * SignedDist);

    if not TVector3.Equals(TargetPos, CurPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if AlignUpToNormal then
    begin
      if T.HasWorldTransform then
        T.GetWorldView(CurWorldPos, CurDir, CurUp)
      else
      begin
        CurWorldPos := T.Translation;
        CurDir := T.Direction;
        CurUp := T.Up;
      end;

      Side := TVector3.CrossProduct(CurDir, UnitNormal);
      if Side.IsZero(1e-5) then
        Side := TVector3.CrossProduct(Vector3(0, 0, -1), UnitNormal);
      if Side.IsZero(1e-5) then
        Side := TVector3.CrossProduct(Vector3(1, 0, 0), UnitNormal);
      Side := Side.Normalize;
      NewDir := TVector3.CrossProduct(UnitNormal, Side).Normalize;

      if (not TVector3.Equals(CurDir, NewDir, 1e-4)) or
         (not TVector3.Equals(CurUp, UnitNormal, 1e-4)) then
      begin
        if T.HasWorldTransform then
          T.SetWorldView(CurWorldPos, NewDir, UnitNormal)
        else
          T.SetView(CurWorldPos, NewDir, UnitNormal);
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

function TCastleTransformManipulate.ProjectSelectedOntoPlaneThreePoints(
  const AlignUpToNormal: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  P0, PMid, PLast, PlaneNormal: TVector3;
begin
  Result := false;
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

  P0 := GetTransformWorkingPos(Items[0]);
  if ValidCount >= 3 then
  begin
    PMid := GetTransformWorkingPos(Items[ValidCount div 2]);
    PLast := GetTransformWorkingPos(Items[ValidCount - 1]);
    PlaneNormal := TVector3.CrossProduct(PMid - P0, PLast - P0);
    if PlaneNormal.IsZero(1e-5) then
      PlaneNormal := Vector3(0, 1, 0)
    else
      PlaneNormal := PlaneNormal.Normalize;
  end else
    PlaneNormal := Vector3(0, 1, 0);

  Result := ProjectSelectedOntoPlane(P0, PlaneNormal, AlignUpToNormal);
end;

function TCastleTransformManipulate.ArrangeSelectedInTorusKnot(
  const MajorRadius, TubeRadius: Single;
  const KnotP: Integer; const KnotQ: Integer;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I, EffP, EffQ: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, CorePos, TargetDir, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  EffMajorR, EffTubeR, Theta, RTheta, DRTheta, AvgDistXZ, DistXZ: Single;
  SinP, CosP, SinQ, CosQ: Single;
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
  if ValidCount < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  EffMajorR := MajorRadius;
  if EffMajorR <= 0 then
  begin
    AvgDistXZ := 0.0;
    for I := 0 to ValidCount - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      DistXZ := Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
      AvgDistXZ := AvgDistXZ + DistXZ;
    end;
    EffMajorR := AvgDistXZ / Single(ValidCount);
    if EffMajorR < 1e-4 then
      EffMajorR := 6.0;
  end;

  EffTubeR := TubeRadius;
  if EffTubeR <= 0 then
    EffTubeR := EffMajorR * 0.35;

  EffP := Max(1, Abs(KnotP));
  EffQ := Max(1, Abs(KnotQ));

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * Single(I)) / Single(ValidCount);
    SinCos(Single(EffP) * Theta, SinP, CosP);
    SinCos(Single(EffQ) * Theta, SinQ, CosQ);

    RTheta := EffMajorR + EffTubeR * CosQ;
    TargetPos := Vector3(
      CenterPos.X + RTheta * CosP,
      CenterPos.Y + EffTubeR * SinQ,
      CenterPos.Z + RTheta * SinP);

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        CorePos := Vector3(
          CenterPos.X + EffMajorR * CosP,
          CenterPos.Y,
          CenterPos.Z + EffMajorR * SinP);
        TargetDir := TargetPos - CorePos;
      end else
      begin
        DRTheta := -Single(EffQ) * EffTubeR * SinQ;
        TargetDir := Vector3(
          DRTheta * CosP - Single(EffP) * RTheta * SinP,
          Single(EffQ) * EffTubeR * CosQ,
          DRTheta * SinP + Single(EffP) * RTheta * CosP);
      end;

      if not TargetDir.IsZero(1e-5) then
      begin
        TargetDir := TargetDir.Normalize;
        Side := TVector3.CrossProduct(TargetDir, GravityUp);
        if Side.IsZero(1e-5) then
        begin
          Side := TVector3.CrossProduct(TargetDir, Vector3(0, 0, 1));
          if Side.IsZero(1e-5) then
            Side := TVector3.CrossProduct(TargetDir, Vector3(1, 0, 0));
        end;
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), TargetDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInConcentricRings(
  const FirstRingRadius, RingSpacing, RingRiseY: Single;
  const BaseRingCount: Integer;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I, RingIdx, InRingIdx, RingCap, RemainingAfterPrev, ItemsInThisRing: Integer;
  EffBaseCount: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, TargetDir, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  EffR0, EffStepR, RingR, RingY, Theta, AvgDistXZ: Single;
  SinT, CosT: Single;
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
  if ValidCount < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  EffR0 := FirstRingRadius;
  if EffR0 <= 0 then
  begin
    AvgDistXZ := 0.0;
    for I := 0 to ValidCount - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      AvgDistXZ := AvgDistXZ + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    EffR0 := (AvgDistXZ / Single(ValidCount)) * 0.6;
    if EffR0 < 1e-4 then
      EffR0 := 4.0;
  end;

  EffStepR := RingSpacing;
  if EffStepR <= 0 then
    EffStepR := Max(2.0, EffR0 * 0.75);

  EffBaseCount := Max(1, BaseRingCount);

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  RingIdx := 0;
  InRingIdx := 0;
  RemainingAfterPrev := ValidCount;
  RingCap := EffBaseCount;
  ItemsInThisRing := Min(RemainingAfterPrev, RingCap);

  for I := 0 to ValidCount - 1 do
  begin
    if InRingIdx >= ItemsInThisRing then
    begin
      Dec(RemainingAfterPrev, ItemsInThisRing);
      Inc(RingIdx);
      InRingIdx := 0;
      RingCap := EffBaseCount * (RingIdx + 1);
      ItemsInThisRing := Min(RemainingAfterPrev, RingCap);
    end;

    T := Items[I];
    RingR := EffR0 + Single(RingIdx) * EffStepR;
    RingY := CenterPos.Y + Single(RingIdx) * RingRiseY;
    Theta := (2.0 * Pi * Single(InRingIdx)) / Single(Max(1, ItemsInThisRing));
    SinCos(Theta, SinT, CosT);

    TargetPos := Vector3(
      CenterPos.X + RingR * CosT,
      RingY,
      CenterPos.Z + RingR * SinT);

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
        TargetDir := Vector3(-CosT, 0.0, -SinT)
      else
        TargetDir := Vector3(CosT, 0.0, SinT);

      if not TargetDir.IsZero(1e-5) then
      begin
        TargetDir := TargetDir.Normalize;
        Side := TVector3.CrossProduct(TargetDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := Vector3(0, 0, 1);
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, TargetDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, TargetDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), TargetDir, NewUp);
          Result := true;
        end;
      end;
    end;

    Inc(InRingIdx);
  end;

  if Result then
  begin
    if Gizmo[Mode] <> nil then
      Gizmo[Mode].UpdateSize;
    GizmoHasTransformModified(Self);
    GizmoHasTransformModifyEnd(Self);
  end;
end;

function TCastleTransformManipulate.ProjectSelectedOntoSphere(
  const Radius: Single;
  const OrientOutward: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, Offset, UnitDir, TargetPos, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  EffRadius, AvgDist: Single;
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
  if ValidCount < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  EffRadius := Radius;
  if EffRadius <= 0 then
  begin
    AvgDist := 0.0;
    for I := 0 to ValidCount - 1 do
      AvgDist := AvgDist + (GetTransformWorkingPos(Items[I]) - CenterPos).Length;
    EffRadius := AvgDist / Single(ValidCount);
    if EffRadius < 1e-4 then
      EffRadius := 5.0;
  end;

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    Offset := CurPos - CenterPos;
    if Offset.IsZero(1e-5) then
      UnitDir := Vector3(0, 1, 0)
    else
      UnitDir := Offset.Normalize;

    TargetPos := CenterPos + UnitDir * EffRadius;
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientOutward and T.HasWorldTransform then
    begin
      Side := TVector3.CrossProduct(UnitDir, GravityUp);
      if Side.IsZero(1e-5) then
      begin
        Side := TVector3.CrossProduct(UnitDir, Vector3(0, 0, 1));
        if Side.IsZero(1e-5) then
          Side := TVector3.CrossProduct(UnitDir, Vector3(1, 0, 0));
      end;
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, UnitDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, UnitDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), UnitDir, NewUp);
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

function TCastleTransformManipulate.ProjectSelectedOntoCylinder(
  const Radius: Single;
  const OrientOutward: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, UnitDirXZ, TargetPos, GravityUp, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  EffRadius, AvgDistXZ, DistXZ, DX, DZ: Single;
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
  if ValidCount < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  EffRadius := Radius;
  if EffRadius <= 0 then
  begin
    AvgDistXZ := 0.0;
    for I := 0 to ValidCount - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      AvgDistXZ := AvgDistXZ + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    EffRadius := AvgDistXZ / Single(ValidCount);
    if EffRadius < 1e-4 then
      EffRadius := 5.0;
  end;

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    DX := CurPos.X - CenterPos.X;
    DZ := CurPos.Z - CenterPos.Z;
    DistXZ := Hypot(DX, DZ);
    if DistXZ < 1e-5 then
      UnitDirXZ := Vector3(1, 0, 0)
    else
      UnitDirXZ := Vector3(DX / DistXZ, 0.0, DZ / DistXZ);

    TargetPos := Vector3(
      CenterPos.X + UnitDirXZ.X * EffRadius,
      CurPos.Y,
      CenterPos.Z + UnitDirXZ.Z * EffRadius);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientOutward and T.HasWorldTransform then
    begin
      Side := TVector3.CrossProduct(UnitDirXZ, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(0, 0, 1);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, UnitDirXZ).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, UnitDirXZ, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), UnitDirXZ, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedOnCylinder(
  const Radius: Single;
  const HeightSpan: Single;
  const OrientMode: Integer): Boolean;
const
  GoldenAngle = 2.39996322972865332; // Pi * (3 - Sqrt(5))
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp,
    CurWorldPos, CurDir, CurUp: TVector3;
  EffRadius, AvgDistXZ, Theta, FracY, SinT, CosT: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 2 then Exit;

  if (PivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  EffRadius := Abs(Radius);
  if EffRadius < 1e-4 then
  begin
    AvgDistXZ := 0.0;
    for I := 0 to ValidCount - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      AvgDistXZ := AvgDistXZ + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    EffRadius := AvgDistXZ / Single(ValidCount);
    if EffRadius < 1e-4 then
      EffRadius := 5.0;
  end;

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    Theta := Single(I) * GoldenAngle;
    SinCos(Theta, SinT, CosT);
    FracY := (Single(I) / Single(ValidCount - 1)) - 0.5;

    TargetPos := Vector3(
      CenterPos.X + EffRadius * CosT,
      CenterPos.Y + FracY * HeightSpan,
      CenterPos.Z + EffRadius * SinT);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
        LookDir := Vector3(-CosT, 0.0, -SinT)
      else
        LookDir := Vector3(CosT, 0.0, SinT);

      if not LookDir.IsZero(1e-5) then
      begin
        LookDir := LookDir.Normalize;
        Side := TVector3.CrossProduct(LookDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := Vector3(0, 0, 1);
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInPyramid(
  const BaseSpacingXZ, LayerRiseY: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I, TotalLayers, CapacitySum, LayerIdx, SlotInLayer,
    GridDim, Row, Col: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp,
    CurWorldPos, CurDir, CurUp: TVector3;
  EffSpacing, AvgSizeXZ, EffRiseY, OffsetX, OffsetZ, DistXZ: Single;
  BBox: TBox3D;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 2 then Exit;

  if (PivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  EffSpacing := Abs(BaseSpacingXZ);
  if EffSpacing < 1e-4 then
  begin
    AvgSizeXZ := 0.0;
    for I := 0 to ValidCount - 1 do
    begin
      BBox := Items[I].WorldBoundingBox;
      if not BBox.IsEmpty then
        AvgSizeXZ := AvgSizeXZ + Max(BBox.SizeX, BBox.SizeZ);
    end;
    EffSpacing := AvgSizeXZ / Single(ValidCount);
    if EffSpacing < 1e-4 then
      EffSpacing := 2.0;
  end;

  EffRiseY := LayerRiseY;
  if Abs(EffRiseY) < 1e-4 then
    EffRiseY := EffSpacing;

  // Determine number of pyramid tiers TotalLayers so sum_{L=0..TotalLayers-1} (L+1)^2 >= ValidCount
  TotalLayers := 1;
  CapacitySum := 1;
  while CapacitySum < ValidCount do
  begin
    Inc(TotalLayers);
    CapacitySum := CapacitySum + Sqr(TotalLayers);
  end;

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  LayerIdx := 0;
  SlotInLayer := 0;
  for I := 0 to ValidCount - 1 do
  begin
    GridDim := LayerIdx + 1;
    if SlotInLayer >= Sqr(GridDim) then
    begin
      Inc(LayerIdx);
      SlotInLayer := 0;
      GridDim := LayerIdx + 1;
    end;

    Row := SlotInLayer div GridDim;
    Col := SlotInLayer mod GridDim;
    Inc(SlotInLayer);

    OffsetX := (Single(Col) - 0.5 * Single(GridDim - 1)) * EffSpacing;
    OffsetZ := (Single(Row) - 0.5 * Single(GridDim - 1)) * EffSpacing;

    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    TargetPos := Vector3(
      CenterPos.X + OffsetX,
      CenterPos.Y + Single(TotalLayers - 1 - LayerIdx) * EffRiseY,
      CenterPos.Z + OffsetZ);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      DistXZ := Hypot(OffsetX, OffsetZ);
      if DistXZ < 1e-5 then
        LookDir := Vector3(0, 0, -1)
      else if OrientMode = 1 then
        LookDir := Vector3(OffsetX / DistXZ, 0.0, OffsetZ / DistXZ)
      else
        LookDir := Vector3(-OffsetX / DistXZ, 0.0, -OffsetZ / DistXZ);

      LookDir := LookDir.Normalize;
      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(0, 0, 1);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ClampSelectedToBox(
  const BoxMin, BoxMax: TVector3;
  const UseObjectBounds: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I, Axis: Integer;
  T: TCastleTransform;
  ActualMin, ActualMax, CurPos, TargetPos, DeltaWorld: TVector3;
  ObjBox: TBox3D;
  ObjMin, ObjMax, AllowedSpan, ObjSpan: Single;
begin
  Result := false;
  if SelectedCount < 1 then Exit;

  for Axis := 0 to 2 do
  begin
    ActualMin.Data[Axis] := Min(BoxMin.Data[Axis], BoxMax.Data[Axis]);
    ActualMax.Data[Axis] := Max(BoxMin.Data[Axis], BoxMax.Data[Axis]);
  end;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 1 then Exit;

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    TargetPos := CurPos;

    if UseObjectBounds then
    begin
      ObjBox := T.WorldBoundingBox;
      if not ObjBox.IsEmpty then
      begin
        DeltaWorld := TVector3.Zero;
        for Axis := 0 to 2 do
        begin
          ObjMin := ObjBox.Data[0].Data[Axis];
          ObjMax := ObjBox.Data[1].Data[Axis];
          ObjSpan := ObjMax - ObjMin;
          AllowedSpan := ActualMax.Data[Axis] - ActualMin.Data[Axis];
          if ObjSpan >= AllowedSpan then
            DeltaWorld.Data[Axis] :=
              0.5 * (ActualMin.Data[Axis] + ActualMax.Data[Axis]) -
              0.5 * (ObjMin + ObjMax)
          else if ObjMin < ActualMin.Data[Axis] then
            DeltaWorld.Data[Axis] := ActualMin.Data[Axis] - ObjMin
          else if ObjMax > ActualMax.Data[Axis] then
            DeltaWorld.Data[Axis] := ActualMax.Data[Axis] - ObjMax;
        end;
        TargetPos := CurPos + DeltaWorld;
      end else
      begin
        for Axis := 0 to 2 do
          TargetPos.Data[Axis] := EnsureRange(
            CurPos.Data[Axis], ActualMin.Data[Axis], ActualMax.Data[Axis]);
      end;
    end else
    begin
      for Axis := 0 to 2 do
        TargetPos.Data[Axis] := EnsureRange(
          CurPos.Data[Axis], ActualMin.Data[Axis], ActualMax.Data[Axis]);
    end;

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
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

function TCastleTransformManipulate.ClampSelectedToPrimaryBounds(
  const UseObjectBounds: Boolean): Boolean;
var
  PrimaryT, T: TCastleTransform;
  PrimaryBox, ObjBox: TBox3D;
  ActualMin, ActualMax, CurPos, TargetPos, DeltaWorld: TVector3;
  I, Axis: Integer;
  ObjMin, ObjMax, ObjSpan, AllowedSpan: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  PrimaryT := FMainSelected;
  if PrimaryT = nil then
    PrimaryT := Selected[0];
  if PrimaryT = nil then Exit;

  PrimaryBox := PrimaryT.WorldBoundingBox;
  if PrimaryBox.IsEmpty then Exit;

  ActualMin := PrimaryBox.Data[0];
  ActualMax := PrimaryBox.Data[1];

  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or (T = PrimaryT) or IsDescendantOfAnySelected(T) then Continue;

    CurPos := GetTransformWorkingPos(T);
    TargetPos := CurPos;

    if UseObjectBounds then
    begin
      ObjBox := T.WorldBoundingBox;
      if not ObjBox.IsEmpty then
      begin
        DeltaWorld := TVector3.Zero;
        for Axis := 0 to 2 do
        begin
          ObjMin := ObjBox.Data[0].Data[Axis];
          ObjMax := ObjBox.Data[1].Data[Axis];
          ObjSpan := ObjMax - ObjMin;
          AllowedSpan := ActualMax.Data[Axis] - ActualMin.Data[Axis];
          if ObjSpan >= AllowedSpan then
            DeltaWorld.Data[Axis] :=
              0.5 * (ActualMin.Data[Axis] + ActualMax.Data[Axis]) -
              0.5 * (ObjMin + ObjMax)
          else if ObjMin < ActualMin.Data[Axis] then
            DeltaWorld.Data[Axis] := ActualMin.Data[Axis] - ObjMin
          else if ObjMax > ActualMax.Data[Axis] then
            DeltaWorld.Data[Axis] := ActualMax.Data[Axis] - ObjMax;
        end;
        TargetPos := CurPos + DeltaWorld;
      end else
      begin
        for Axis := 0 to 2 do
          TargetPos.Data[Axis] := EnsureRange(
            CurPos.Data[Axis], ActualMin.Data[Axis], ActualMax.Data[Axis]);
      end;
    end else
    begin
      for Axis := 0 to 2 do
        TargetPos.Data[Axis] := EnsureRange(
          CurPos.Data[Axis], ActualMin.Data[Axis], ActualMax.Data[Axis]);
    end;

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
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

function TCastleTransformManipulate.ArrangeSelectedOnCone(
  const BaseRadius: Single;
  const TopRadius: Single;
  const HeightSpan: Single;
  const OrientMode: Integer): Boolean;
const
  GoldenAngle = 2.39996322972865332; // Pi * (3 - Sqrt(5))
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp,
    CurWorldPos, CurDir, CurUp: TVector3;
  EffBaseR, EffTopR, EffHeight, AvgDistXZ, Theta, SinT, CosT,
    FracT, CurR: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 2 then Exit;

  if (PivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  EffBaseR := BaseRadius;
  if EffBaseR <= 1e-4 then
  begin
    AvgDistXZ := 0.0;
    for I := 0 to ValidCount - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      AvgDistXZ := AvgDistXZ + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    EffBaseR := (AvgDistXZ / Single(ValidCount)) * 1.25;
    if EffBaseR < 1e-4 then
      EffBaseR := 5.0;
  end;

  EffTopR := Max(0.0, TopRadius);
  EffHeight := HeightSpan;
  if Abs(EffHeight) < 1e-4 then
    EffHeight := Max(4.0, EffBaseR * 1.5);

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    FracT := Single(I) / Single(ValidCount - 1);
    CurR := EffBaseR + (EffTopR - EffBaseR) * FracT;
    Theta := Single(I) * GoldenAngle;
    SinCos(Theta, SinT, CosT);

    TargetPos := Vector3(
      CenterPos.X + CurR * CosT,
      CenterPos.Y + (FracT - 0.5) * EffHeight,
      CenterPos.Z + CurR * SinT);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
        LookDir := Vector3(-CosT, 0.0, -SinT)
      else
        LookDir := Vector3(
          Abs(EffHeight) * CosT,
          EffBaseR - EffTopR,
          Abs(EffHeight) * SinT);

      if not LookDir.IsZero(1e-5) then
      begin
        LookDir := LookDir.Normalize;
        Side := TVector3.CrossProduct(LookDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := Vector3(0, 0, 1);
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInHexGrid(
  const Columns: Integer;
  const CellRadius: Single;
  const OrientMode: Integer): Boolean;
const
  Sqrt3 = 1.7320508075688772;
var
  Items: array of TCastleTransform;
  RawX, RawZ: array of Single;
  ValidCount, I, EffCols, Row, Col: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp,
    CurWorldPos, CurDir, CurUp: TVector3;
  EffRadius, AvgSizeXZ, StepX, StepZ, MinX, MaxX, MinZ, MaxZ,
    MidX, MidZ, OffsetX, OffsetZ, DistXZ, AngleRad, SinA, CosA: Single;
  BBox: TBox3D;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 2 then Exit;

  if (PivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  if Columns > 0 then
    EffCols := Columns
  else
    EffCols := Max(1, Ceil(Sqrt(Single(ValidCount))));

  EffRadius := Abs(CellRadius);
  if EffRadius < 1e-4 then
  begin
    AvgSizeXZ := 0.0;
    for I := 0 to ValidCount - 1 do
    begin
      BBox := Items[I].WorldBoundingBox;
      if not BBox.IsEmpty then
        AvgSizeXZ := AvgSizeXZ + Max(BBox.SizeX, BBox.SizeZ);
    end;
    EffRadius := (AvgSizeXZ / Single(ValidCount)) / Sqrt3;
    if EffRadius < 1e-4 then
      EffRadius := 2.0;
  end;

  StepX := Sqrt3 * EffRadius;
  StepZ := 1.5 * EffRadius;

  SetLength(RawX, ValidCount);
  SetLength(RawZ, ValidCount);
  MinX := 0.0;
  MaxX := 0.0;
  MinZ := 0.0;
  MaxZ := 0.0;

  for I := 0 to ValidCount - 1 do
  begin
    Row := I div EffCols;
    Col := I mod EffCols;
    RawX[I] := (Single(Col) + 0.5 * Single(Row mod 2)) * StepX;
    RawZ[I] := Single(Row) * StepZ;
    if I = 0 then
    begin
      MinX := RawX[I];
      MaxX := RawX[I];
      MinZ := RawZ[I];
      MaxZ := RawZ[I];
    end else
    begin
      MinX := Min(MinX, RawX[I]);
      MaxX := Max(MaxX, RawX[I]);
      MinZ := Min(MinZ, RawZ[I]);
      MaxZ := Max(MaxZ, RawZ[I]);
    end;
  end;

  MidX := 0.5 * (MinX + MaxX);
  MidZ := 0.5 * (MinZ + MaxZ);

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    OffsetX := RawX[I] - MidX;
    OffsetZ := RawZ[I] - MidZ;
    TargetPos := Vector3(
      CenterPos.X + OffsetX,
      CenterPos.Y,
      CenterPos.Z + OffsetZ);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        AngleRad := Single(I mod 6) * (Pi / 3.0);
        SinCos(AngleRad, SinA, CosA);
        LookDir := Vector3(SinA, 0.0, -CosA);
      end else
      begin
        DistXZ := Hypot(OffsetX, OffsetZ);
        if DistXZ < 1e-5 then
          LookDir := Vector3(0, 0, -1)
        else
          LookDir := Vector3(OffsetX / DistXZ, 0.0, OffsetZ / DistXZ);
      end;

      LookDir := LookDir.Normalize;
      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(0, 0, 1);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.PushSelectedOutsideBox(
  const BoxMin, BoxMax: TVector3;
  const UseObjectBounds: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I, Axis, BestAxis: Integer;
  T: TCastleTransform;
  ActualMin, ActualMax, CurPos, TargetPos: TVector3;
  ObjBox: TBox3D;
  Overlaps: Boolean;
  DeltaNeg, DeltaPos, BestDelta: Single;
begin
  Result := false;
  if SelectedCount < 1 then Exit;

  for Axis := 0 to 2 do
  begin
    ActualMin.Data[Axis] := Min(BoxMin.Data[Axis], BoxMax.Data[Axis]);
    ActualMax.Data[Axis] := Max(BoxMin.Data[Axis], BoxMax.Data[Axis]);
  end;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 1 then Exit;

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    TargetPos := CurPos;

    if UseObjectBounds then
    begin
      ObjBox := T.WorldBoundingBox;
      if not ObjBox.IsEmpty then
      begin
        Overlaps :=
          (ObjBox.Data[1].X > ActualMin.X + 1e-5) and (ObjBox.Data[0].X < ActualMax.X - 1e-5) and
          (ObjBox.Data[1].Y > ActualMin.Y + 1e-5) and (ObjBox.Data[0].Y < ActualMax.Y - 1e-5) and
          (ObjBox.Data[1].Z > ActualMin.Z + 1e-5) and (ObjBox.Data[0].Z < ActualMax.Z - 1e-5);
        if Overlaps then
        begin
          BestAxis := 0;
          BestDelta := 1e30;
          for Axis := 0 to 2 do
          begin
            DeltaNeg := ActualMin.Data[Axis] - ObjBox.Data[1].Data[Axis];
            DeltaPos := ActualMax.Data[Axis] - ObjBox.Data[0].Data[Axis];
            if Abs(DeltaNeg) < Abs(BestDelta) then
            begin
              BestDelta := DeltaNeg;
              BestAxis := Axis;
            end;
            if Abs(DeltaPos) < Abs(BestDelta) then
            begin
              BestDelta := DeltaPos;
              BestAxis := Axis;
            end;
          end;
          TargetPos.Data[BestAxis] := CurPos.Data[BestAxis] + BestDelta;
        end;
      end else
      begin
        Overlaps :=
          (CurPos.X > ActualMin.X + 1e-5) and (CurPos.X < ActualMax.X - 1e-5) and
          (CurPos.Y > ActualMin.Y + 1e-5) and (CurPos.Y < ActualMax.Y - 1e-5) and
          (CurPos.Z > ActualMin.Z + 1e-5) and (CurPos.Z < ActualMax.Z - 1e-5);
        if Overlaps then
        begin
          BestAxis := 0;
          BestDelta := 1e30;
          for Axis := 0 to 2 do
          begin
            DeltaNeg := ActualMin.Data[Axis] - CurPos.Data[Axis];
            DeltaPos := ActualMax.Data[Axis] - CurPos.Data[Axis];
            if Abs(DeltaNeg) < Abs(BestDelta) then
            begin
              BestDelta := DeltaNeg;
              BestAxis := Axis;
            end;
            if Abs(DeltaPos) < Abs(BestDelta) then
            begin
              BestDelta := DeltaPos;
              BestAxis := Axis;
            end;
          end;
          TargetPos.Data[BestAxis] := CurPos.Data[BestAxis] + BestDelta;
        end;
      end;
    end else
    begin
      Overlaps :=
        (CurPos.X > ActualMin.X + 1e-5) and (CurPos.X < ActualMax.X - 1e-5) and
        (CurPos.Y > ActualMin.Y + 1e-5) and (CurPos.Y < ActualMax.Y - 1e-5) and
        (CurPos.Z > ActualMin.Z + 1e-5) and (CurPos.Z < ActualMax.Z - 1e-5);
      if Overlaps then
      begin
        BestAxis := 0;
        BestDelta := 1e30;
        for Axis := 0 to 2 do
        begin
          DeltaNeg := ActualMin.Data[Axis] - CurPos.Data[Axis];
          DeltaPos := ActualMax.Data[Axis] - CurPos.Data[Axis];
          if Abs(DeltaNeg) < Abs(BestDelta) then
          begin
            BestDelta := DeltaNeg;
            BestAxis := Axis;
          end;
          if Abs(DeltaPos) < Abs(BestDelta) then
          begin
            BestDelta := DeltaPos;
            BestAxis := Axis;
          end;
        end;
        TargetPos.Data[BestAxis] := CurPos.Data[BestAxis] + BestDelta;
      end;
    end;

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
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

function TCastleTransformManipulate.PushSelectedOutsidePrimaryBounds(
  const UseObjectBounds: Boolean): Boolean;
var
  PrimaryT, T: TCastleTransform;
  PrimaryBox, ObjBox: TBox3D;
  ActualMin, ActualMax, CurPos, TargetPos: TVector3;
  I, Axis, BestAxis: Integer;
  Overlaps: Boolean;
  DeltaNeg, DeltaPos, BestDelta: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  PrimaryT := FMainSelected;
  if PrimaryT = nil then
    PrimaryT := Selected[0];
  if PrimaryT = nil then Exit;

  PrimaryBox := PrimaryT.WorldBoundingBox;
  if PrimaryBox.IsEmpty then Exit;

  ActualMin := PrimaryBox.Data[0];
  ActualMax := PrimaryBox.Data[1];

  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or (T = PrimaryT) or IsDescendantOfAnySelected(T) then Continue;

    CurPos := GetTransformWorkingPos(T);
    TargetPos := CurPos;

    if UseObjectBounds then
    begin
      ObjBox := T.WorldBoundingBox;
      if not ObjBox.IsEmpty then
      begin
        Overlaps :=
          (ObjBox.Data[1].X > ActualMin.X + 1e-5) and (ObjBox.Data[0].X < ActualMax.X - 1e-5) and
          (ObjBox.Data[1].Y > ActualMin.Y + 1e-5) and (ObjBox.Data[0].Y < ActualMax.Y - 1e-5) and
          (ObjBox.Data[1].Z > ActualMin.Z + 1e-5) and (ObjBox.Data[0].Z < ActualMax.Z - 1e-5);
        if Overlaps then
        begin
          BestAxis := 0;
          BestDelta := 1e30;
          for Axis := 0 to 2 do
          begin
            DeltaNeg := ActualMin.Data[Axis] - ObjBox.Data[1].Data[Axis];
            DeltaPos := ActualMax.Data[Axis] - ObjBox.Data[0].Data[Axis];
            if Abs(DeltaNeg) < Abs(BestDelta) then
            begin
              BestDelta := DeltaNeg;
              BestAxis := Axis;
            end;
            if Abs(DeltaPos) < Abs(BestDelta) then
            begin
              BestDelta := DeltaPos;
              BestAxis := Axis;
            end;
          end;
          TargetPos.Data[BestAxis] := CurPos.Data[BestAxis] + BestDelta;
        end;
      end else
      begin
        Overlaps :=
          (CurPos.X > ActualMin.X + 1e-5) and (CurPos.X < ActualMax.X - 1e-5) and
          (CurPos.Y > ActualMin.Y + 1e-5) and (CurPos.Y < ActualMax.Y - 1e-5) and
          (CurPos.Z > ActualMin.Z + 1e-5) and (CurPos.Z < ActualMax.Z - 1e-5);
        if Overlaps then
        begin
          BestAxis := 0;
          BestDelta := 1e30;
          for Axis := 0 to 2 do
          begin
            DeltaNeg := ActualMin.Data[Axis] - CurPos.Data[Axis];
            DeltaPos := ActualMax.Data[Axis] - CurPos.Data[Axis];
            if Abs(DeltaNeg) < Abs(BestDelta) then
            begin
              BestDelta := DeltaNeg;
              BestAxis := Axis;
            end;
            if Abs(DeltaPos) < Abs(BestDelta) then
            begin
              BestDelta := DeltaPos;
              BestAxis := Axis;
            end;
          end;
          TargetPos.Data[BestAxis] := CurPos.Data[BestAxis] + BestDelta;
        end;
      end;
    end else
    begin
      Overlaps :=
        (CurPos.X > ActualMin.X + 1e-5) and (CurPos.X < ActualMax.X - 1e-5) and
        (CurPos.Y > ActualMin.Y + 1e-5) and (CurPos.Y < ActualMax.Y - 1e-5) and
        (CurPos.Z > ActualMin.Z + 1e-5) and (CurPos.Z < ActualMax.Z - 1e-5);
      if Overlaps then
      begin
        BestAxis := 0;
        BestDelta := 1e30;
        for Axis := 0 to 2 do
        begin
          DeltaNeg := ActualMin.Data[Axis] - CurPos.Data[Axis];
          DeltaPos := ActualMax.Data[Axis] - CurPos.Data[Axis];
          if Abs(DeltaNeg) < Abs(BestDelta) then
          begin
            BestDelta := DeltaNeg;
            BestAxis := Axis;
          end;
          if Abs(DeltaPos) < Abs(BestDelta) then
          begin
            BestDelta := DeltaPos;
            BestAxis := Axis;
          end;
        end;
        TargetPos.Data[BestAxis] := CurPos.Data[BestAxis] + BestDelta;
      end;
    end;

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
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

function TCastleTransformManipulate.ArrangeSelectedOnCubeFrame(
  const HalfExtents: TVector3;
  const ShellMode: Boolean;
  const OrientMode: Integer): Boolean;
const
  EdgeStarts: array [0..11] of TVector3 = (
    (X: -1; Y: -1; Z: -1), (X:  1; Y: -1; Z: -1), (X:  1; Y: -1; Z:  1), (X: -1; Y: -1; Z:  1),
    (X: -1; Y:  1; Z: -1), (X:  1; Y:  1; Z: -1), (X:  1; Y:  1; Z:  1), (X: -1; Y:  1; Z:  1),
    (X: -1; Y: -1; Z: -1), (X:  1; Y: -1; Z: -1), (X:  1; Y: -1; Z:  1), (X: -1; Y: -1; Z:  1)
  );
  EdgeEnds: array [0..11] of TVector3 = (
    (X:  1; Y: -1; Z: -1), (X:  1; Y: -1; Z:  1), (X: -1; Y: -1; Z:  1), (X: -1; Y: -1; Z: -1),
    (X:  1; Y:  1; Z: -1), (X:  1; Y:  1; Z:  1), (X: -1; Y:  1; Z:  1), (X: -1; Y:  1; Z: -1),
    (X: -1; Y:  1; Z: -1), (X:  1; Y:  1; Z: -1), (X:  1; Y:  1; Z:  1), (X: -1; Y:  1; Z:  1)
  );
var
  Items: array of TCastleTransform;
  ValidCount, I, EdgeIdx, K, IX, IY, IZ, CapCount: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, Ext, P0, P1, EdgeVec, NormPos,
    GravityUp, LookDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  EdgeLens: array [0..11] of Single;
  TotalPerim, DistAlong, SegLen, Frac: Single;
  ShellPts: array of TVector3;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 2 then Exit;

  if (PivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  Ext := Vector3(Abs(HalfExtents.X), Abs(HalfExtents.Y), Abs(HalfExtents.Z));
  if (Ext.X <= 1e-4) and (Ext.Y <= 1e-4) and (Ext.Z <= 1e-4) then
  begin
    for I := 0 to ValidCount - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]) - CenterPos;
      Ext.X := Max(Ext.X, Abs(CurPos.X));
      Ext.Y := Max(Ext.Y, Abs(CurPos.Y));
      Ext.Z := Max(Ext.Z, Abs(CurPos.Z));
    end;
    if Ext.X <= 1e-4 then Ext.X := 5.0;
    if Ext.Y <= 1e-4 then Ext.Y := 5.0;
    if Ext.Z <= 1e-4 then Ext.Z := 5.0;
  end else
  begin
    if Ext.X <= 1e-4 then Ext.X := Max(Ext.Y, Ext.Z);
    if Ext.Y <= 1e-4 then Ext.Y := Max(Ext.X, Ext.Z);
    if Ext.Z <= 1e-4 then Ext.Z := Max(Ext.X, Ext.Y);
  end;

  if ShellMode then
  begin
    K := 2;
    while (6 * K * K - 12 * K + 8) < ValidCount do
      Inc(K);
    CapCount := 6 * K * K - 12 * K + 8;
    SetLength(ShellPts, CapCount);
    EdgeIdx := 0;
    for IY := 0 to K - 1 do
      for IZ := 0 to K - 1 do
        for IX := 0 to K - 1 do
          if (IX = 0) or (IX = K - 1) or
             (IY = 0) or (IY = K - 1) or
             (IZ = 0) or (IZ = K - 1) then
          begin
            ShellPts[EdgeIdx] := Vector3(
              -1.0 + 2.0 * Single(IX) / Single(K - 1),
              -1.0 + 2.0 * Single(IY) / Single(K - 1),
              -1.0 + 2.0 * Single(IZ) / Single(K - 1));
            Inc(EdgeIdx);
          end;
  end else
  begin
    TotalPerim := 0.0;
    for EdgeIdx := 0 to 11 do
    begin
      P0 := Vector3(EdgeStarts[EdgeIdx].X * Ext.X, EdgeStarts[EdgeIdx].Y * Ext.Y, EdgeStarts[EdgeIdx].Z * Ext.Z);
      P1 := Vector3(EdgeEnds[EdgeIdx].X * Ext.X, EdgeEnds[EdgeIdx].Y * Ext.Y, EdgeEnds[EdgeIdx].Z * Ext.Z);
      EdgeLens[EdgeIdx] := PointsDistance(P0, P1);
      TotalPerim := TotalPerim + EdgeLens[EdgeIdx];
    end;
  end;

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);

    if ShellMode then
    begin
      NormPos := ShellPts[I];
      TargetPos := CenterPos + Vector3(NormPos.X * Ext.X, NormPos.Y * Ext.Y, NormPos.Z * Ext.Z);
    end else
    begin
      DistAlong := (Single(I) / Single(ValidCount)) * TotalPerim;
      NormPos := EdgeStarts[0];
      for EdgeIdx := 0 to 11 do
      begin
        SegLen := EdgeLens[EdgeIdx];
        if (DistAlong < SegLen - 1e-5) or (EdgeIdx = 11) then
        begin
          if SegLen > 1e-5 then
            Frac := Clamped(DistAlong / SegLen, 0.0, 1.0)
          else
            Frac := 0.0;
          NormPos := Lerp(Frac, EdgeStarts[EdgeIdx], EdgeEnds[EdgeIdx]);
          Break;
        end;
        DistAlong := Max(0.0, DistAlong - SegLen);
      end;
      TargetPos := CenterPos + Vector3(NormPos.X * Ext.X, NormPos.Y * Ext.Y, NormPos.Z * Ext.Z);
    end;

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      EdgeVec := TargetPos - CenterPos;
      if not EdgeVec.IsZero(1e-5) then
      begin
        if OrientMode = 1 then
          LookDir := EdgeVec.Normalize
        else
          LookDir := (-EdgeVec).Normalize;

        Side := TVector3.CrossProduct(LookDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := Vector3(0, 0, 1);
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInParaboloidBowl(
  const RimRadius: Single;
  const DepthY: Single;
  const OrientMode: Integer): Boolean;
const
  GoldenAngle = 2.39996322972865332; // Pi * (3 - Sqrt(5))
var
  Items: array of TCastleTransform;
  ValidCount, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, NormalVec,
    GravityUp, LookDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  ActualRadius, U, R, Theta, CosT, SinT, SlopeFactor: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 2 then Exit;

  if (PivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  ActualRadius := Abs(RimRadius);
  if ActualRadius <= 1e-4 then
  begin
    for I := 0 to ValidCount - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]) - CenterPos;
      ActualRadius := Max(ActualRadius, Hypot(CurPos.X, CurPos.Z));
    end;
    if ActualRadius <= 1e-4 then
      ActualRadius := 6.0;
  end;

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);

    U := (Single(I) + 0.5) / Single(ValidCount);
    R := ActualRadius * Sqrt(U);
    Theta := Single(I) * GoldenAngle;
    SinCos(Theta, SinT, CosT);

    TargetPos := Vector3(
      CenterPos.X + R * CosT,
      CenterPos.Y + DepthY * (U - 0.5),
      CenterPos.Z + R * SinT);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        SlopeFactor := 2.0 * DepthY * R;
        NormalVec := Vector3(
          -SlopeFactor * CosT,
          ActualRadius * ActualRadius,
          -SlopeFactor * SinT);
        if NormalVec.IsZero(1e-5) then
          LookDir := Vector3(0, 1, 0)
        else
          LookDir := NormalVec.Normalize;
      end else
      begin
        NormalVec := Vector3(-CosT, 0.0, -SinT);
        if NormalVec.IsZero(1e-5) then
          LookDir := Vector3(0, 0, -1)
        else
          LookDir := NormalVec.Normalize;
      end;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(0, 0, 1);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.SnapSelectedToBoxSurface(
  const BoxMin, BoxMax: TVector3;
  const FlushOutside: Boolean;
  const OrientOutward: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  ValidCount, I, Axis, BestAxis, BestSign: Integer;
  T: TCastleTransform;
  ActualMin, ActualMax, CurPos, TargetPos, HalfExt,
    GravityUp, LookDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  ObjBox: TBox3D;
  DistNeg, DistPos, BestDist: Single;
begin
  Result := false;
  if SelectedCount < 1 then Exit;

  for Axis := 0 to 2 do
  begin
    ActualMin.Data[Axis] := Min(BoxMin.Data[Axis], BoxMax.Data[Axis]);
    ActualMax.Data[Axis] := Max(BoxMin.Data[Axis], BoxMax.Data[Axis]);
  end;

  SetLength(Items, SelectedCount);
  ValidCount := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or IsDescendantOfAnySelected(T) then Continue;
    Items[ValidCount] := T;
    Inc(ValidCount);
  end;

  if ValidCount < 1 then Exit;

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to ValidCount - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    HalfExt := TVector3.Zero;
    if FlushOutside then
    begin
      ObjBox := T.WorldBoundingBox;
      if not ObjBox.IsEmpty then
        HalfExt := ObjBox.Size * 0.5;
    end;

    BestAxis := 0;
    BestSign := 1;
    BestDist := 1e30;
    for Axis := 0 to 2 do
    begin
      DistNeg := Abs(CurPos.Data[Axis] - ActualMin.Data[Axis]);
      if DistNeg < BestDist then
      begin
        BestDist := DistNeg;
        BestAxis := Axis;
        BestSign := -1;
      end;
      DistPos := Abs(CurPos.Data[Axis] - ActualMax.Data[Axis]);
      if DistPos < BestDist then
      begin
        BestDist := DistPos;
        BestAxis := Axis;
        BestSign := 1;
      end;
    end;

    for Axis := 0 to 2 do
      if Axis = BestAxis then
      begin
        if BestSign < 0 then
          TargetPos.Data[Axis] := ActualMin.Data[Axis] - HalfExt.Data[Axis]
        else
          TargetPos.Data[Axis] := ActualMax.Data[Axis] + HalfExt.Data[Axis];
      end else
        TargetPos.Data[Axis] := Clamped(CurPos.Data[Axis], ActualMin.Data[Axis], ActualMax.Data[Axis]);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientOutward and T.HasWorldTransform then
    begin
      LookDir := TVector3.Zero;
      LookDir.Data[BestAxis] := Single(BestSign);
      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(0, 0, 1);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.SnapSelectedToPrimaryBoundsSurface(
  const FlushOutside: Boolean;
  const OrientOutward: Boolean): Boolean;
var
  PrimaryT, T: TCastleTransform;
  PrimaryBox, ObjBox: TBox3D;
  ActualMin, ActualMax, CurPos, TargetPos, HalfExt,
    GravityUp, LookDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  I, Axis, BestAxis, BestSign: Integer;
  DistNeg, DistPos, BestDist: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  PrimaryT := FMainSelected;
  if PrimaryT = nil then
    PrimaryT := Selected[0];
  if PrimaryT = nil then Exit;

  PrimaryBox := PrimaryT.WorldBoundingBox;
  if PrimaryBox.IsEmpty then Exit;

  ActualMin := PrimaryBox.Data[0];
  ActualMax := PrimaryBox.Data[1];

  if (PrimaryT.World <> nil) and (not PrimaryT.World.GravityUp.IsZero) then
    GravityUp := PrimaryT.World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T = nil) or (T = PrimaryT) or IsDescendantOfAnySelected(T) then Continue;

    CurPos := GetTransformWorkingPos(T);
    HalfExt := TVector3.Zero;
    if FlushOutside then
    begin
      ObjBox := T.WorldBoundingBox;
      if not ObjBox.IsEmpty then
        HalfExt := ObjBox.Size * 0.5;
    end;

    BestAxis := 0;
    BestSign := 1;
    BestDist := 1e30;
    for Axis := 0 to 2 do
    begin
      DistNeg := Abs(CurPos.Data[Axis] - ActualMin.Data[Axis]);
      if DistNeg < BestDist then
      begin
        BestDist := DistNeg;
        BestAxis := Axis;
        BestSign := -1;
      end;
      DistPos := Abs(CurPos.Data[Axis] - ActualMax.Data[Axis]);
      if DistPos < BestDist then
      begin
        BestDist := DistPos;
        BestAxis := Axis;
        BestSign := 1;
      end;
    end;

    for Axis := 0 to 2 do
      if Axis = BestAxis then
      begin
        if BestSign < 0 then
          TargetPos.Data[Axis] := ActualMin.Data[Axis] - HalfExt.Data[Axis]
        else
          TargetPos.Data[Axis] := ActualMax.Data[Axis] + HalfExt.Data[Axis];
      end else
        TargetPos.Data[Axis] := Clamped(CurPos.Data[Axis], ActualMin.Data[Axis], ActualMax.Data[Axis]);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientOutward and T.HasWorldTransform then
    begin
      LookDir := TVector3.Zero;
      LookDir.Data[BestAxis] := Single(BestSign);
      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(0, 0, 1);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInRoseCurve(
  const OuterRadius: Single;
  const PetalsK: Single;
  const VerticalWaveY: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  ActualR, ActualK, SumDist, Theta, CosT, SinT, CosKT, SinKT, RVal: Single;
  DX, DY, DZ: Single;
begin
  Result := false;
  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  ActualR := OuterRadius;
  if ActualR <= 0 then
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      SumDist := SumDist + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    ActualR := SumDist / Count;
    if ActualR < 1e-3 then
      ActualR := 6.0;
  end;

  ActualK := PetalsK;
  if Abs(ActualK) < 1e-4 then
    ActualK := 2.0;

  if (FMainSelected <> nil) and (FMainSelected.World <> nil) then
  begin
    GravityUp := FMainSelected.World.GravityUp;
    if GravityUp.IsZero then
      GravityUp := Vector3(0, 1, 0)
    else
      GravityUp := GravityUp.Normalize;
  end else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / Count;
    SinCos(Theta, SinT, CosT);
    SinCos(ActualK * Theta, SinKT, CosKT);
    RVal := ActualR * CosKT;

    TargetPos := Vector3(
      CenterPos.X + RVal * CosT,
      CenterPos.Y + VerticalWaveY * SinKT,
      CenterPos.Z + RVal * SinT
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        LookDir := Vector3(CenterPos.X - TargetPos.X, 0, CenterPos.Z - TargetPos.Z);
        if LookDir.IsZero(1e-5) then
          LookDir := Vector3(-CosT, 0, -SinT);
        LookDir := LookDir.Normalize;
      end else
      begin
        // Tangent dP/dTheta of Rose curve:
        // r(theta) = R cos(k theta), r'(theta) = -R k sin(k theta)
        // x' = r' cos(theta) - r sin(theta)
        // y' = H_y k cos(k theta)
        // z' = r' sin(theta) + r cos(theta)
        DX := (-ActualR * ActualK * SinKT) * CosT - RVal * SinT;
        DY := VerticalWaveY * ActualK * CosKT;
        DZ := (-ActualR * ActualK * SinKT) * SinT + RVal * CosT;
        LookDir := Vector3(DX, DY, DZ);
        if LookDir.IsZero(1e-5) then
          LookDir := Vector3(-SinT, 0, CosT);
        LookDir := LookDir.Normalize;
      end;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedOnEllipsoid(
  const Radii: TVector3;
  const UpperHemisphereOnly: Boolean;
  const OrientMode: Integer): Boolean;
const
  GoldenAngle = 2.39996322972865332; // Pi * (3 - Sqrt(5))
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, ActualRadii, UnitSpherePt, GravityUp, LookDir, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  SumDist, AvgR, U, Rho, Theta, SinT, CosT: Single;
begin
  Result := false;
  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  SumDist := 0;
  for I := 0 to Count - 1 do
    SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Items[I]), CenterPos);
  AvgR := SumDist / Count;
  if AvgR < 1e-3 then
    AvgR := 6.0;

  ActualRadii := Radii;
  if ActualRadii.X <= 0 then ActualRadii.X := AvgR * 1.25;
  if ActualRadii.Y <= 0 then ActualRadii.Y := AvgR * 0.75;
  if ActualRadii.Z <= 0 then ActualRadii.Z := AvgR;

  if (FMainSelected <> nil) and (FMainSelected.World <> nil) then
  begin
    GravityUp := FMainSelected.World.GravityUp;
    if GravityUp.IsZero then
      GravityUp := Vector3(0, 1, 0)
    else
      GravityUp := GravityUp.Normalize;
  end else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    if UpperHemisphereOnly then
      U := 1.0 - ((I + 0.5) / Count) // U in (0, 1)
    else
      U := 1.0 - (2.0 * (I + 0.5) / Count); // U in (-1, 1)

    Rho := Sqrt(Max(0.0, 1.0 - Sqr(U)));
    Theta := I * GoldenAngle;
    SinCos(Theta, SinT, CosT);

    UnitSpherePt := Vector3(Rho * CosT, U, Rho * SinT);
    TargetPos := Vector3(
      CenterPos.X + ActualRadii.X * UnitSpherePt.X,
      CenterPos.Y + ActualRadii.Y * UnitSpherePt.Y,
      CenterPos.Z + ActualRadii.Z * UnitSpherePt.Z
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        // Analytic outward normal of ellipsoid (x/Rx)^2 + (y/Ry)^2 + (z/Rz)^2 = 1:
        // grad F proportional to (s_x / Rx, s_y / Ry, s_z / Rz)
        LookDir := Vector3(
          UnitSpherePt.X / ActualRadii.X,
          UnitSpherePt.Y / ActualRadii.Y,
          UnitSpherePt.Z / ActualRadii.Z
        );
      end else
        LookDir := CenterPos - TargetPos;

      if LookDir.IsZero(1e-5) then
        LookDir := Vector3(0, 1, 0);
      LookDir := LookDir.Normalize;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ShearSelected(
  const ShearAxis, ReferenceAxis: T3DAxis;
  const ShearFactor: Single;
  const TiltOrientation: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, RefUnit, ShearUnit, RotAxis: TVector3;
  DeltaRef, TiltAngle: Single;
  TiltQuat: TQuaternion;
begin
  Result := false;
  if (ShearAxis = ReferenceAxis) or (Abs(ShearFactor) < 1e-6) then Exit;

  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  RefUnit := TVector3.Zero;
  RefUnit.Data[ReferenceAxis] := 1.0;
  ShearUnit := TVector3.Zero;
  ShearUnit.Data[ShearAxis] := 1.0;
  RotAxis := TVector3.CrossProduct(RefUnit, ShearUnit).Normalize;
  TiltAngle := ArcTan(ShearFactor);
  TiltQuat := QuatFromAxisAngle(Vector4(RotAxis, TiltAngle));

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    DeltaRef := CurPos.Data[ReferenceAxis] - CenterPos.Data[ReferenceAxis];
    TargetPos := CurPos;
    TargetPos.Data[ShearAxis] := CurPos.Data[ShearAxis] + ShearFactor * DeltaRef;

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if TiltOrientation and (Abs(TiltAngle) > 1e-5) then
    begin
      T.Rotation := (TiltQuat * QuatFromAxisAngle(T.Rotation)).ToAxisAngle;
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

function TCastleTransformManipulate.TwistSelected(
  const TwistAxis: T3DAxis;
  const TotalAngleRad: Single;
  const RotateOrientations: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, AxisUnit, Offset: TVector3;
  MinCoord, MaxCoord, Span, CoordVal, NormT, Angle: Single;
  TwistQuat: TQuaternion;
begin
  Result := false;
  if Abs(TotalAngleRad) < 1e-6 then Exit;

  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  MinCoord := GetTransformWorkingPos(Items[0]).Data[TwistAxis];
  MaxCoord := MinCoord;
  for I := 1 to Count - 1 do
  begin
    CoordVal := GetTransformWorkingPos(Items[I]).Data[TwistAxis];
    if CoordVal < MinCoord then MinCoord := CoordVal;
    if CoordVal > MaxCoord then MaxCoord := CoordVal;
  end;
  Span := MaxCoord - MinCoord;

  AxisUnit := TVector3.Zero;
  AxisUnit.Data[TwistAxis] := 1.0;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    if Span > 1e-5 then
      NormT := ((CurPos.Data[TwistAxis] - MinCoord) / Span) - 0.5
    else
      NormT := (Single(I) / Single(Count - 1)) - 0.5;

    Angle := NormT * TotalAngleRad;
    Offset := CurPos - CenterPos;
    TargetPos := CenterPos + RotatePointAroundAxisRad(Angle, Offset, AxisUnit);

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if RotateOrientations and (Abs(Angle) > 1e-5) then
    begin
      TwistQuat := QuatFromAxisAngle(Vector4(AxisUnit, Angle));
      T.Rotation := (TwistQuat * QuatFromAxisAngle(T.Rotation)).ToAxisAngle;
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

function TCastleTransformManipulate.TaperSelected(
  const TaperAxis: T3DAxis;
  const TopScaleFactor: Single;
  const ScaleObjects: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, NewScale: TVector3;
  MinCoord, MaxCoord, Span, CoordVal, NormT, ScaleF: Single;
  Axis1, Axis2: T3DAxis;
begin
  Result := false;
  if Abs(TopScaleFactor - 1.0) < 1e-6 then Exit;

  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  MinCoord := GetTransformWorkingPos(Items[0]).Data[TaperAxis];
  MaxCoord := MinCoord;
  for I := 1 to Count - 1 do
  begin
    CoordVal := GetTransformWorkingPos(Items[I]).Data[TaperAxis];
    if CoordVal < MinCoord then MinCoord := CoordVal;
    if CoordVal > MaxCoord then MaxCoord := CoordVal;
  end;
  Span := MaxCoord - MinCoord;

  Axis1 := T3DAxis((Ord(TaperAxis) + 1) mod 3);
  Axis2 := T3DAxis((Ord(TaperAxis) + 2) mod 3);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    if Span > 1e-5 then
      NormT := (CurPos.Data[TaperAxis] - MinCoord) / Span
    else
      NormT := Single(I) / Single(Count - 1);

    ScaleF := Lerp(NormT, 1.0, TopScaleFactor);
    TargetPos := CurPos;
    TargetPos.Data[Axis1] := CenterPos.Data[Axis1] + (CurPos.Data[Axis1] - CenterPos.Data[Axis1]) * ScaleF;
    TargetPos.Data[Axis2] := CenterPos.Data[Axis2] + (CurPos.Data[Axis2] - CenterPos.Data[Axis2]) * ScaleF;

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if ScaleObjects and (Abs(ScaleF - 1.0) > 1e-5) then
    begin
      NewScale := T.Scale;
      NewScale.Data[Axis1] := Max(1e-4, NewScale.Data[Axis1] * Abs(ScaleF));
      NewScale.Data[Axis2] := Max(1e-4, NewScale.Data[Axis2] * Abs(ScaleF));
      if not TVector3.Equals(T.Scale, NewScale) then
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

function TCastleTransformManipulate.ArrangeSelectedInSphericalSpiral(
  const Radius, Turns: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  ActualR, ActualTurns, SumDist, FracT, U, Rho, RhoSafe, DRhoDT, DThetaDT, Theta, SinT, CosT, DX, DY, DZ: Single;
begin
  Result := false;
  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  if Radius > 0 then
    ActualR := Radius
  else
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Items[I]), CenterPos);
    ActualR := SumDist / Count;
    if ActualR < 1e-3 then
      ActualR := 6.0;
  end;

  ActualTurns := Turns;
  if Abs(ActualTurns) < 1e-4 then
    ActualTurns := 2.0;

  if (FMainSelected <> nil) and (FMainSelected.World <> nil) then
  begin
    GravityUp := FMainSelected.World.GravityUp;
    if GravityUp.IsZero then
      GravityUp := Vector3(0, 1, 0)
    else
      GravityUp := GravityUp.Normalize;
  end else
    GravityUp := Vector3(0, 1, 0);

  DThetaDT := 2.0 * Pi * ActualTurns;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    FracT := Single(I) / Single(Count - 1);
    U := 2.0 * FracT - 1.0; // U in [-1, 1] from bottom pole to top pole
    Rho := Sqrt(Max(0.0, 1.0 - Sqr(U)));
    Theta := DThetaDT * FracT;
    SinCos(Theta, SinT, CosT);

    TargetPos := Vector3(
      CenterPos.X + ActualR * Rho * CosT,
      CenterPos.Y + ActualR * U,
      CenterPos.Z + ActualR * Rho * SinT
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        LookDir := Vector3(Rho * CosT, U, Rho * SinT);
      end else
      begin
        RhoSafe := Max(0.05, Rho);
        DRhoDT := (-2.0 * U) / RhoSafe;
        DX := DRhoDT * CosT - Rho * DThetaDT * SinT;
        DY := 2.0;
        DZ := DRhoDT * SinT + Rho * DThetaDT * CosT;
        LookDir := Vector3(DX, DY, DZ);
      end;

      if LookDir.IsZero(1e-5) then
        LookDir := Vector3(0, 1, 0);
      LookDir := LookDir.Normalize;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInSuperellipse(
  const RadiusX, RadiusZ, ExponentN: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  ActualRX, ActualRZ, PowerP, SumDist, AvgR, Theta, SinT, CosT, SignedCosP, SignedSinP: Single;
begin
  Result := false;
  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  SumDist := 0;
  for I := 0 to Count - 1 do
    SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Items[I]), CenterPos);
  AvgR := SumDist / Count;
  if AvgR < 1e-3 then
    AvgR := 6.0;

  if RadiusX > 0 then ActualRX := RadiusX else ActualRX := AvgR;
  if RadiusZ > 0 then ActualRZ := RadiusZ else ActualRZ := AvgR;
  PowerP := 2.0 / Max(0.1, ExponentN);

  if (FMainSelected <> nil) and (FMainSelected.World <> nil) then
  begin
    GravityUp := FMainSelected.World.GravityUp;
    if GravityUp.IsZero then
      GravityUp := Vector3(0, 1, 0)
    else
      GravityUp := GravityUp.Normalize;
  end else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / Count;
    SinCos(Theta, SinT, CosT);

    if Abs(CosT) < 1e-6 then
      SignedCosP := 0.0
    else
      SignedCosP := Sign(CosT) * Power(Abs(CosT), PowerP);

    if Abs(SinT) < 1e-6 then
      SignedSinP := 0.0
    else
      SignedSinP := Sign(SinT) * Power(Abs(SinT), PowerP);

    TargetPos := Vector3(
      CenterPos.X + ActualRX * SignedCosP,
      CenterPos.Y,
      CenterPos.Z + ActualRZ * SignedSinP
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
        LookDir := Vector3(CenterPos.X - TargetPos.X, 0, CenterPos.Z - TargetPos.Z)
      else
        LookDir := Vector3(TargetPos.X - CenterPos.X, 0, TargetPos.Z - CenterPos.Z);

      if LookDir.IsZero(1e-5) then
        LookDir := Vector3(CosT, 0, SinT);
      LookDir := LookDir.Normalize;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.BendSelected(
  const SpineAxis, BendDirAxis: T3DAxis;
  const TotalAngleRad: Single;
  const RotateOrientations: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  OrigPos: array of TVector3;
  Count, I: Integer;
  T: TCastleTransform;
  ActualSpine, ActualBendDir: T3DAxis;
  CenterPos, CurPos, TargetPos, SpineUnit, BendUnit, RotAxis: TVector3;
  CurWorldPos, CurDir, CurUp, NewDir, NewUp: TVector3;
  MinS, MaxS, Span, RadiusR, RelS, RelD, Theta, SinT, CosT, EffR: Single;
  UseIndexSpan: Boolean;
begin
  Result := false;
  if Abs(TotalAngleRad) < 1e-5 then Exit;

  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  ActualSpine := SpineAxis;
  if BendDirAxis = ActualSpine then
    ActualBendDir := (ActualSpine + 1) mod 3
  else
    ActualBendDir := BendDirAxis;

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  SetLength(OrigPos, Count);
  for I := 0 to Count - 1 do
    OrigPos[I] := GetTransformWorkingPos(Items[I]);

  MinS := OrigPos[0].Data[ActualSpine];
  MaxS := MinS;
  for I := 1 to Count - 1 do
  begin
    if OrigPos[I].Data[ActualSpine] < MinS then
      MinS := OrigPos[I].Data[ActualSpine];
    if OrigPos[I].Data[ActualSpine] > MaxS then
      MaxS := OrigPos[I].Data[ActualSpine];
  end;

  Span := MaxS - MinS;
  UseIndexSpan := Span < 1e-4;
  if UseIndexSpan then
    Span := 10.0;

  RadiusR := Span / TotalAngleRad;

  SpineUnit := TVector3.Zero;
  SpineUnit.Data[ActualSpine] := 1.0;
  BendUnit := TVector3.Zero;
  BendUnit.Data[ActualBendDir] := 1.0;
  RotAxis := TVector3.CrossProduct(SpineUnit, BendUnit).Normalize;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := OrigPos[I];

    if UseIndexSpan then
      RelS := ((Single(I) / Single(Count - 1)) - 0.5) * Span
    else
      RelS := CurPos.Data[ActualSpine] - CenterPos.Data[ActualSpine];

    RelD := CurPos.Data[ActualBendDir] - CenterPos.Data[ActualBendDir];
    Theta := (RelS / Span) * TotalAngleRad;
    SinCos(Theta, SinT, CosT);

    EffR := RadiusR - RelD;
    TargetPos := CurPos;
    TargetPos.Data[ActualSpine] := CenterPos.Data[ActualSpine] + EffR * SinT;
    TargetPos.Data[ActualBendDir] := CenterPos.Data[ActualBendDir] + RadiusR - EffR * CosT;

    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if RotateOrientations and (Abs(Theta) > 1e-5) and T.HasWorldTransform then
    begin
      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      NewDir := RotatePointAroundAxisRad(Theta, CurDir, RotAxis);
      NewUp := RotatePointAroundAxisRad(Theta, CurUp, RotAxis);
      if (not TVector3.Equals(CurDir, NewDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), NewDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInVivianiCurve(
  const Radius: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  ActualR, SumDist, Theta, SinT, CosT, Sin2T, Cos2T: Single;
begin
  Result := false;
  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  if Radius > 0 then
    ActualR := Radius
  else
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Items[I]), CenterPos);
    ActualR := SumDist / Count;
    if ActualR < 1e-3 then
      ActualR := 6.0;
  end;

  if (FMainSelected <> nil) and (FMainSelected.World <> nil) then
  begin
    GravityUp := FMainSelected.World.GravityUp;
    if GravityUp.IsZero then
      GravityUp := Vector3(0, 1, 0)
    else
      GravityUp := GravityUp.Normalize;
  end else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / Count;
    SinCos(Theta, SinT, CosT);

    TargetPos := Vector3(
      CenterPos.X + ActualR * Sqr(CosT),
      CenterPos.Y + ActualR * SinT,
      CenterPos.Z + ActualR * SinT * CosT
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        LookDir := Vector3(Sqr(CosT), SinT, SinT * CosT);
      end else
      begin
        SinCos(2.0 * Theta, Sin2T, Cos2T);
        LookDir := Vector3(-Sin2T, CosT, Cos2T);
      end;

      if LookDir.IsZero(1e-5) then
        LookDir := Vector3(0, 1, 0);
      LookDir := LookDir.Normalize;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInSpirograph(
  const FixedRadiusR, RollingRadiusSmallR, PenOffsetD: Single;
  const Epitrochoid: Boolean;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  BigR, SmallR, PenD, SumDist, AvgR, BaseR, FreqK, Theta: Single;
  SinT, CosT, SinKT, CosKT, DX, DZ: Single;
begin
  Result := false;
  Count := 0;
  SetLength(Items, FMaxSelectedCount);
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

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := SelectionWorkingCenter;

  SumDist := 0;
  for I := 0 to Count - 1 do
    SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Items[I]), CenterPos);
  AvgR := SumDist / Count;
  if AvgR < 1e-3 then
    AvgR := 8.0;

  if FixedRadiusR > 0 then BigR := FixedRadiusR else BigR := AvgR;
  if RollingRadiusSmallR > 0 then SmallR := RollingRadiusSmallR else SmallR := BigR * 0.25;
  SmallR := Max(1e-3, SmallR);
  if PenOffsetD > 0 then PenD := PenOffsetD else PenD := SmallR * 0.8;

  if Epitrochoid then
    BaseR := BigR + SmallR
  else
    BaseR := BigR - SmallR;
  FreqK := BaseR / SmallR;

  if (FMainSelected <> nil) and (FMainSelected.World <> nil) then
  begin
    GravityUp := FMainSelected.World.GravityUp;
    if GravityUp.IsZero then
      GravityUp := Vector3(0, 1, 0)
    else
      GravityUp := GravityUp.Normalize;
  end else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / Count;
    SinCos(Theta, SinT, CosT);
    SinCos(FreqK * Theta, SinKT, CosKT);

    if Epitrochoid then
    begin
      TargetPos := Vector3(
        CenterPos.X + BaseR * CosT - PenD * CosKT,
        CenterPos.Y,
        CenterPos.Z + BaseR * SinT - PenD * SinKT
      );
    end else
    begin
      TargetPos := Vector3(
        CenterPos.X + BaseR * CosT + PenD * CosKT,
        CenterPos.Y,
        CenterPos.Z + BaseR * SinT - PenD * SinKT
      );
    end;

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        LookDir := Vector3(CenterPos.X - TargetPos.X, 0, CenterPos.Z - TargetPos.Z);
      end else
      begin
        if Epitrochoid then
        begin
          DX := -BaseR * SinT + PenD * FreqK * SinKT;
          DZ := BaseR * CosT - PenD * FreqK * CosKT;
        end else
        begin
          DX := -BaseR * SinT - PenD * FreqK * SinKT;
          DZ := BaseR * CosT - PenD * FreqK * CosKT;
        end;
        LookDir := Vector3(DX, 0, DZ);
      end;

      if LookDir.IsZero(1e-5) then
        LookDir := Vector3(-SinT, 0, CosT);
      LookDir := LookDir.Normalize;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.SpherifySelected(
  const TargetRadius: Single;
  const StrengthFactor: Single;
  const OrientRadially: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  I, Count, NonZeroCount: Integer;
  T: TCastleTransform;
  CenterPos, Offset, RadialDir, TargetPos, CurPos: TVector3;
  GravityUp, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  R, Dist, NewDist, SumDist: Single;
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
  if Count < 2 then Exit;

  SetLength(Positions, Count);
  CenterPos := TVector3.Zero;
  for I := 0 to Count - 1 do
  begin
    Positions[I] := GetTransformWorkingPos(Items[I]);
    CenterPos := CenterPos + Positions[I];
  end;

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := CenterPos / Single(Count);

  R := TargetRadius;
  if R <= 0 then
  begin
    SumDist := 0.0;
    NonZeroCount := 0;
    for I := 0 to Count - 1 do
    begin
      Dist := (Positions[I] - CenterPos).Length;
      if Dist > 1e-4 then
      begin
        SumDist := SumDist + Dist;
        Inc(NonZeroCount);
      end;
    end;
    if NonZeroCount > 0 then
      R := SumDist / Single(NonZeroCount)
    else
      R := 5.0;
  end;

  GravityUp := Vector3(0, 1, 0);
  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Offset := Positions[I] - CenterPos;
    Dist := Offset.Length;
    if Dist > 1e-5 then
      RadialDir := Offset / Dist
    else
      RadialDir := Vector3(Cos(2.0 * Pi * Single(I) / Single(Count)), 0,
                           Sin(2.0 * Pi * Single(I) / Single(Count)));

    NewDist := Max(0.0, Lerp(StrengthFactor, Dist, R));
    TargetPos := CenterPos + RadialDir * NewDist;

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if OrientRadially and T.HasWorldTransform then
    begin
      Side := TVector3.CrossProduct(RadialDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := AnyOrthogonalVector(RadialDir);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, RadialDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, RadialDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), RadialDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInMobiusStrip(
  const MajorRadius, StripHalfWidth: Single;
  const HalfTwists: Integer;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  I, Count: Integer;
  T: TCastleTransform;
  CenterPos, TargetPos, CurPos: TVector3;
  GravityUp, LookDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  RadialXZ, BinormalV: TVector3;
  R, W, U, Alpha, VCoord, RadialFactor: Single;
  SinU, CosU, SinAlpha, CosAlpha: Single;
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
  if Count < 2 then Exit;

  SetLength(Positions, Count);
  CenterPos := TVector3.Zero;
  for I := 0 to Count - 1 do
  begin
    Positions[I] := GetTransformWorkingPos(Items[I]);
    CenterPos := CenterPos + Positions[I];
  end;

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := CenterPos / Single(Count);

  R := MajorRadius;
  if R <= 0 then
  begin
    R := 0.0;
    for I := 0 to Count - 1 do
      R := R + Hypot(Positions[I].X - CenterPos.X, Positions[I].Z - CenterPos.Z);
    R := R / Single(Count);
    if R < 1e-3 then
      R := 8.0;
  end;

  W := StripHalfWidth;
  if W <= 0 then
    W := R * 0.25;

  GravityUp := Vector3(0, 1, 0);
  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    U := (2.0 * Pi * Single(I)) / Single(Count);
    Alpha := Single(HalfTwists) * 0.5 * U;
    if Odd(I) then
      VCoord := -W
    else
      VCoord := W;

    SinCos(U, SinU, CosU);
    SinCos(Alpha, SinAlpha, CosAlpha);

    RadialFactor := R + VCoord * CosAlpha;
    TargetPos := Vector3(
      CenterPos.X + RadialFactor * CosU,
      CenterPos.Y + VCoord * SinAlpha,
      CenterPos.Z + RadialFactor * SinU
    );

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        // Forward along centerline tangent (-SinU, 0, CosU), Up along twisted strip normal
        LookDir := Vector3(-SinU, 0, CosU);
        RadialXZ := Vector3(CosU, 0, SinU);
        NewUp := (RadialXZ * (-SinAlpha) + Vector3(0, CosAlpha, 0)).Normalize;
      end else
      begin
        LookDir := Vector3(CenterPos.X - TargetPos.X, 0, CenterPos.Z - TargetPos.Z);
        if LookDir.IsZero(1e-5) then
          LookDir := Vector3(-CosU, 0, -SinU);
        LookDir := LookDir.Normalize;
        Side := TVector3.CrossProduct(LookDir, GravityUp);
        if Side.IsZero(1e-5) then
          Side := Vector3(1, 0, 0);
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;
      end;

      BinormalV := TVector3.CrossProduct(LookDir, NewUp);
      if BinormalV.IsZero(1e-5) then
        NewUp := GravityUp;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInCardioidOrHeart(
  const SizeScale: Single;
  const HeartShape: Boolean;
  const VerticalWave: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  I, Count: Integer;
  T: TCastleTransform;
  CenterPos, TargetPos, CurPos: TVector3;
  GravityUp, LookDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  S, Theta, SinT, CosT, RCardioid, XOff, YOff, ZOff: Single;
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
  if Count < 2 then Exit;

  SetLength(Positions, Count);
  CenterPos := TVector3.Zero;
  for I := 0 to Count - 1 do
  begin
    Positions[I] := GetTransformWorkingPos(Items[I]);
    CenterPos := CenterPos + Positions[I];
  end;

  if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
    CenterPos := GetTransformWorkingPos(FMainSelected)
  else
    CenterPos := CenterPos / Single(Count);

  S := SizeScale;
  if S <= 0 then
  begin
    S := 0.0;
    for I := 0 to Count - 1 do
      S := S + Hypot(Positions[I].X - CenterPos.X, Positions[I].Z - CenterPos.Z);
    S := S / Single(Count);
    if S < 1e-3 then
      S := 8.0;
  end;

  GravityUp := Vector3(0, 1, 0);
  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * Single(I)) / Single(Count);
    SinCos(Theta, SinT, CosT);

    if HeartShape then
    begin
      // Normalized 16-sin^3 heart curve scaled by S
      XOff := S * (SinT * SinT * SinT);
      ZOff := -S * ((13.0 * CosT - 5.0 * Cos(2.0 * Theta) -
                     2.0 * Cos(3.0 * Theta) - Cos(4.0 * Theta)) / 16.0);
    end else
    begin
      // Cardioid curve r(t) = S * (1 - sin(t))
      RCardioid := S * (1.0 - SinT);
      XOff := RCardioid * CosT;
      ZOff := RCardioid * SinT;
    end;

    YOff := VerticalWave * Sin(2.0 * Theta);
    TargetPos := Vector3(CenterPos.X + XOff, CenterPos.Y + YOff, CenterPos.Z + ZOff);

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
        LookDir := Vector3(CenterPos.X - TargetPos.X, 0, CenterPos.Z - TargetPos.Z)
      else
        LookDir := Vector3(TargetPos.X - CenterPos.X, 0, TargetPos.Z - CenterPos.Z);

      if LookDir.IsZero(1e-5) then
        LookDir := Vector3(0, 0, -1);
      LookDir := LookDir.Normalize;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.RippleSelected(
  const Amplitude, Wavelength: Single;
  const PhaseRad: Single;
  const DecayRate: Single;
  const TiltNormals: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, CurWorldPos, CurDir, CurUp, SurfNormal, NewDir, NewUp: TVector3;
  DX, DZ, R, K, Alpha, Damping, Arg, SinArg, CosArg, DeltaY, Dydr: Single;
begin
  Result := false;
  Count := SelectedCount;
  if Count < 2 then
    Exit;

  SetLength(Items, Count);
  SetLength(Positions, Count);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if not IsDescendantOfAnySelected(T) then
    begin
      Items[Count] := T;
      Positions[Count] := GetTransformWorkingPos(T);
      Inc(Count);
    end;
  end;

  if Count < 2 then
    Exit;

  CenterPos := SelectionWorkingCenter;
  K := (2.0 * Pi) / Max(0.01, Abs(Wavelength));
  Alpha := Max(0.0, DecayRate);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := Positions[I];
    DX := CurPos.X - CenterPos.X;
    DZ := CurPos.Z - CenterPos.Z;
    R := Sqrt(Sqr(DX) + Sqr(DZ));

    Damping := Exp(-Alpha * R);
    Arg := K * R + PhaseRad;
    SinCos(Arg, SinArg, CosArg);
    DeltaY := Amplitude * Damping * CosArg;

    TargetPos := Vector3(CurPos.X, CurPos.Y + DeltaY, CurPos.Z);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if TiltNormals and T.HasWorldTransform and (R > 1e-4) then
    begin
      // dy/dr = -Amplitude * e^(-Alpha*r) * (Alpha*cos(k*r + phi) + k*sin(k*r + phi))
      Dydr := -Amplitude * Damping * (Alpha * CosArg + K * SinArg);
      SurfNormal := Vector3(-Dydr * (DX / R), 1.0, -Dydr * (DZ / R)).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      NewUp := SurfNormal;
      NewDir := CurDir - NewUp * TVector3.DotProduct(CurDir, NewUp);
      if NewDir.IsZero(1e-5) then
      begin
        NewDir := TVector3.CrossProduct(NewUp, Vector3(1, 0, 0));
        if NewDir.IsZero(1e-5) then
          NewDir := TVector3.CrossProduct(NewUp, Vector3(0, 0, 1));
      end;
      NewDir := NewDir.Normalize;

      if (not TVector3.Equals(CurDir, NewDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), NewDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInLemniscate(
  const HalfWidthA: Single;
  const VerticalBridgeLift: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, CurWorldPos, CurDir, CurUp, LookDir, Side, NewUp, GravityUp: TVector3;
  A, SumDist, Theta, SinT, CosT, Denom, DenomSq, XOff, YOff, ZOff, DXdt, DYdt, DZdt: Single;
begin
  Result := false;
  Count := SelectedCount;
  if Count < 2 then
    Exit;

  SetLength(Items, Count);
  SetLength(Positions, Count);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if not IsDescendantOfAnySelected(T) then
    begin
      Items[Count] := T;
      Positions[Count] := GetTransformWorkingPos(T);
      Inc(Count);
    end;
  end;

  if Count < 2 then
    Exit;

  CenterPos := SelectionWorkingCenter;
  A := HalfWidthA;
  if A <= 0 then
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + Sqrt(Sqr(Positions[I].X - CenterPos.X) + Sqr(Positions[I].Z - CenterPos.Z));
    A := SumDist / Count;
    if A < 1e-4 then
      A := 6.0;
  end;

  GravityUp := Vector3(0, 1, 0);
  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / Count;
    SinCos(Theta, SinT, CosT);
    Denom := 1.0 + Sqr(SinT);

    XOff := (A * CosT) / Denom;
    ZOff := (A * SinT * CosT) / Denom;
    YOff := VerticalBridgeLift * SinT;

    TargetPos := Vector3(CenterPos.X + XOff, CenterPos.Y + YOff, CenterPos.Z + ZOff);
    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        // Analytical derivative of Lemniscate of Bernoulli:
        // x(t) = a*cos(t)/(1 + sin^2(t)) => dx/dt = -a*sin(t)*(3 - sin^2(t)) / (1 + sin^2(t))^2
        // z(t) = a*sin(t)*cos(t)/(1 + sin^2(t)) => dz/dt = a*(1 - 3*sin^2(t)) / (1 + sin^2(t))^2
        // y(t) = H*sin(t) => dy/dt = H*cos(t)
        DenomSq := Sqr(Denom);
        DXdt := (-A * SinT * (3.0 - Sqr(SinT))) / DenomSq;
        DZdt := (A * (1.0 - 3.0 * Sqr(SinT))) / DenomSq;
        DYdt := VerticalBridgeLift * CosT;
        LookDir := Vector3(DXdt, DYdt, DZdt);
      end else
        LookDir := Vector3(CenterPos.X - TargetPos.X, 0, CenterPos.Z - TargetPos.Z);

      if LookDir.IsZero(1e-5) then
        LookDir := Vector3(0, 0, -1);
      LookDir := LookDir.Normalize;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInTorusHelix(
  const MajorRadius: Single;
  const MinorRadius: Single;
  const CoilWindings: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, TubeCenter, TubeNormal, CoilTangent, LookDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  MajR, MinR, Windings, SumDist, U, V, SinU, CosU, SinV, CosV, RadialR, DXdu, DYdu, DZdu: Single;
begin
  Result := false;
  Count := SelectedCount;
  if Count < 2 then
    Exit;

  SetLength(Items, Count);
  SetLength(Positions, Count);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if not IsDescendantOfAnySelected(T) then
    begin
      Items[Count] := T;
      Positions[Count] := GetTransformWorkingPos(T);
      Inc(Count);
    end;
  end;

  if Count < 2 then
    Exit;

  CenterPos := SelectionWorkingCenter;
  MajR := MajorRadius;
  if MajR <= 0 then
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + Sqrt(Sqr(Positions[I].X - CenterPos.X) + Sqr(Positions[I].Z - CenterPos.Z));
    MajR := SumDist / Count;
    if MajR < 1e-4 then
      MajR := 6.0;
  end;

  MinR := MinorRadius;
  if MinR <= 0 then
    MinR := MajR * 0.3;

  Windings := CoilWindings;
  if Abs(Windings) < 1e-4 then
    Windings := 6.0;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    U := (2.0 * Pi * I) / Count;
    V := Windings * U;
    SinCos(U, SinU, CosU);
    SinCos(V, SinV, CosV);

    RadialR := MajR + MinR * CosV;
    TargetPos := Vector3(
      CenterPos.X + RadialR * CosU,
      CenterPos.Y + MinR * SinV,
      CenterPos.Z + RadialR * SinU);

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      TubeCenter := Vector3(CenterPos.X + MajR * CosU, CenterPos.Y, CenterPos.Z + MajR * SinU);
      TubeNormal := TargetPos - TubeCenter;
      if TubeNormal.IsZero(1e-5) then
        TubeNormal := Vector3(CosU * CosV, SinV, SinU * CosV);
      TubeNormal := TubeNormal.Normalize;

      // Analytical tangent dP/du of the toroidal helix:
      // dx/du = -MinR*Windings*sin(v)*cos(u) - (MajR + MinR*cos(v))*sin(u)
      // dy/du = MinR*Windings*cos(v)
      // dz/du = -MinR*Windings*sin(v)*sin(u) + (MajR + MinR*cos(v))*cos(u)
      DXdu := -MinR * Windings * SinV * CosU - RadialR * SinU;
      DYdu := MinR * Windings * CosV;
      DZdu := -MinR * Windings * SinV * SinU + RadialR * CosU;
      CoilTangent := Vector3(DXdu, DYdu, DZdu);
      if CoilTangent.IsZero(1e-5) then
        CoilTangent := Vector3(-SinU, 0, CosU);
      CoilTangent := CoilTangent.Normalize;

      if OrientMode = 1 then
      begin
        LookDir := CoilTangent;
        NewUp := TubeNormal - LookDir * TVector3.DotProduct(TubeNormal, LookDir);
        if NewUp.IsZero(1e-5) then
          NewUp := Vector3(0, 1, 0);
        NewUp := NewUp.Normalize;
      end else
      begin
        LookDir := TubeNormal;
        Side := TVector3.CrossProduct(LookDir, CoilTangent);
        if Side.IsZero(1e-5) then
          Side := Vector3(0, 1, 0);
        Side := Side.Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;
      end;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.VolumeSquashStretchSelected(
  const Axis: T3DAxis;
  const StretchFactor: Single;
  const AnchorAtBase: Boolean;
  const ScaleObjects: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  Count, I: Integer;
  T: TCastleTransform;
  C1, C2: T3DAxis;
  SafeStretch, InvSqrtStretch, MinCoord: Single;
  AnchorPos, CurPos, TargetPos, ScaleMult, NewScale: TVector3;
begin
  Result := false;
  Count := SelectedCount;
  if Count < 1 then
    Exit;

  SetLength(Items, Count);
  SetLength(Positions, Count);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if not IsDescendantOfAnySelected(T) then
    begin
      Items[Count] := T;
      Positions[Count] := GetTransformWorkingPos(T);
      Inc(Count);
    end;
  end;

  if (Count < 1) or ((Count = 1) and (not ScaleObjects)) then
    Exit;

  SafeStretch := Max(0.05, StretchFactor);
  InvSqrtStretch := 1.0 / Sqrt(SafeStretch);
  RestOf3DCoords(Axis, C1, C2);

  AnchorPos := SelectionWorkingCenter;
  if AnchorAtBase and (Count >= 2) then
  begin
    MinCoord := Positions[0][Axis];
    for I := 1 to Count - 1 do
      if Positions[I][Axis] < MinCoord then
        MinCoord := Positions[I][Axis];
    AnchorPos.Data[Axis] := MinCoord;
  end;

  ScaleMult := Vector3(1.0, 1.0, 1.0);
  ScaleMult.Data[Axis] := SafeStretch;
  ScaleMult.Data[C1] := InvSqrtStretch;
  ScaleMult.Data[C2] := InvSqrtStretch;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    if Count >= 2 then
    begin
      CurPos := Positions[I];
      TargetPos := CurPos;
      TargetPos.Data[Axis] := AnchorPos[Axis] + (CurPos[Axis] - AnchorPos[Axis]) * SafeStretch;
      TargetPos.Data[C1] := AnchorPos[C1] + (CurPos[C1] - AnchorPos[C1]) * InvSqrtStretch;
      TargetPos.Data[C2] := AnchorPos[C2] + (CurPos[C2] - AnchorPos[C2]) * InvSqrtStretch;
      if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, TargetPos);
        Result := true;
      end;
    end;

    if ScaleObjects then
    begin
      NewScale := T.Scale * ScaleMult;
      if not TVector3.Equals(T.Scale, NewScale, 1e-5) then
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

function TCastleTransformManipulate.ArrangeSelectedInButterflyCurve(
  const SizeScale: Single;
  const WingFlapHeight: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, GravityUp, LookDir, Side, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  S, SumDist, Theta, SinT, CosT, SinTerm, SinTerm5, R, XOff, YOff, ZOff: Single;
begin
  Result := false;
  Count := SelectedCount;
  if Count < 2 then
    Exit;

  SetLength(Items, Count);
  SetLength(Positions, Count);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if not IsDescendantOfAnySelected(T) then
    begin
      Items[Count] := T;
      Positions[Count] := GetTransformWorkingPos(T);
      Inc(Count);
    end;
  end;

  if Count < 2 then
    Exit;

  CenterPos := SelectionWorkingCenter;
  S := SizeScale;
  if S <= 0 then
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + Hypot(Positions[I].X - CenterPos.X, Positions[I].Z - CenterPos.Z);
    S := (SumDist / Count) / 2.5;
    if S < 1e-3 then
      S := 3.0;
  end;

  GravityUp := Vector3(0, 1, 0);
  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / Count;
    SinCos(Theta, SinT, CosT);
    SinTerm := Sin((2.0 * Theta - Pi) / 24.0);
    SinTerm5 := Sqr(SinTerm) * Sqr(SinTerm) * SinTerm;
    R := Exp(SinT) - 2.0 * Cos(4.0 * Theta) + SinTerm5;

    XOff := S * R * CosT;
    ZOff := S * R * SinT;
    YOff := WingFlapHeight * Abs(CosT);

    TargetPos := Vector3(CenterPos.X + XOff, CenterPos.Y + YOff, CenterPos.Z + ZOff);
    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
        LookDir := Vector3(CenterPos.X - TargetPos.X, 0, CenterPos.Z - TargetPos.Z)
      else
        LookDir := Vector3(TargetPos.X - CenterPos.X, 0, TargetPos.Z - CenterPos.Z);

      if LookDir.IsZero(1e-5) then
        LookDir := Vector3(0, 0, -1);
      LookDir := LookDir.Normalize;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(1, 0, 0);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInClelieCurve(
  const Radius: Single;
  const PetalRatioM: Single;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Positions: array of TVector3;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, SphereNormal, CurveTangent, LookDir, NewUp, CurWorldPos, CurDir, CurUp: TVector3;
  R, M, SumDist, Theta, Phi, SinT, CosT, SinP, CosP, DX, DY, DZ: Single;
begin
  Result := false;
  Count := SelectedCount;
  if Count < 2 then
    Exit;

  SetLength(Items, Count);
  SetLength(Positions, Count);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if not IsDescendantOfAnySelected(T) then
    begin
      Items[Count] := T;
      Positions[Count] := GetTransformWorkingPos(T);
      Inc(Count);
    end;
  end;

  if Count < 2 then
    Exit;

  CenterPos := SelectionWorkingCenter;
  R := Radius;
  if R <= 0 then
  begin
    SumDist := 0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + PointsDistance(Positions[I], CenterPos);
    R := SumDist / Count;
    if R < 1e-4 then
      R := 8.0;
  end;

  M := PetalRatioM;
  if Abs(M) < 1e-4 then
    M := 2.0;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    Theta := (2.0 * Pi * I) / Count;
    Phi := M * Theta;
    SinCos(Theta, SinT, CosT);
    SinCos(Phi, SinP, CosP);

    SphereNormal := Vector3(CosP * CosT, SinP, CosP * SinT);
    if SphereNormal.IsZero(1e-5) then
      SphereNormal := Vector3(0, 1, 0)
    else
      SphereNormal := SphereNormal.Normalize;

    TargetPos := CenterPos + SphereNormal * R;
    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      // Analytical tangent d(SphereNormal)/d(theta):
      // dx/dtheta = -m*sin(phi)*cos(theta) - cos(phi)*sin(theta)
      // dy/dtheta = m*cos(phi)
      // dz/dtheta = -m*sin(phi)*sin(theta) + cos(phi)*cos(theta)
      DX := -M * SinP * CosT - CosP * SinT;
      DY := M * CosP;
      DZ := -M * SinP * SinT + CosP * CosT;
      CurveTangent := Vector3(DX, DY, DZ);
      if CurveTangent.IsZero(1e-5) then
        CurveTangent := Vector3(-SinT, 0, CosT);
      CurveTangent := CurveTangent.Normalize;

      if OrientMode = 1 then
      begin
        LookDir := SphereNormal;
        NewUp := CurveTangent - LookDir * TVector3.DotProduct(CurveTangent, LookDir);
        if NewUp.IsZero(1e-5) then
          NewUp := Vector3(0, 1, 0);
        NewUp := NewUp.Normalize;
      end else
      begin
        LookDir := CurveTangent;
        NewUp := SphereNormal - LookDir * TVector3.DotProduct(SphereNormal, LookDir);
        if NewUp.IsZero(1e-5) then
          NewUp := Vector3(0, 1, 0);
        NewUp := NewUp.Normalize;
      end;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.SwirlSelected(
  const Axis: T3DAxis;
  const MaxCenterAngleRad: Single;
  const FalloffRadius: Single;
  const RotateOrientations: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Count, I, Perp1, Perp2: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, Offset, AxisVec, TargetPos: TVector3;
  CurWorldPos, CurDir, CurUp, NewDir, NewUp: TVector3;
  RadDist, MaxRad, EffRadius, Factor, Theta: Single;
  RadialDistances: array of Single;
begin
  Result := false;
  if Abs(MaxCenterAngleRad) < 1e-6 then Exit;

  SetLength(Items, SelectedCount);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Items[0] <> nil) then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  Perp1 := (Axis + 1) mod 3;
  Perp2 := (Axis + 2) mod 3;
  AxisVec := TVector3.Zero;
  AxisVec.Data[Axis] := 1.0;

  SetLength(RadialDistances, Count);
  MaxRad := 0.0;
  for I := 0 to Count - 1 do
  begin
    Offset := GetTransformWorkingPos(Items[I]) - CenterPos;
    RadDist := Hypot(Offset.Data[Perp1], Offset.Data[Perp2]);
    RadialDistances[I] := RadDist;
    if RadDist > MaxRad then
      MaxRad := RadDist;
  end;

  if FalloffRadius > 1e-4 then
    EffRadius := FalloffRadius
  else
  begin
    EffRadius := MaxRad * 1.25;
    if EffRadius < 1e-4 then
      EffRadius := 10.0;
  end;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    Offset := CurPos - CenterPos;
    Factor := Max(0.0, 1.0 - (RadialDistances[I] / EffRadius));
    Theta := MaxCenterAngleRad * Factor;
    if Abs(Theta) < 1e-6 then
      Continue;

    TargetPos := CenterPos + RotatePointAroundAxisRad(Theta, Offset, AxisVec);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if RotateOrientations and T.HasWorldTransform then
    begin
      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      NewDir := RotatePointAroundAxisRad(Theta, CurDir, AxisVec);
      NewUp := RotatePointAroundAxisRad(Theta, CurUp, AxisVec);
      if (not TVector3.Equals(CurDir, NewDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), NewDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInKnotCurve(
  const Radius: Single;
  const FigureEightKnot: Boolean;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, CurveTangent, LookDir, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  SumDist, R, S, ParamT, SinT, CosT, Sin2T, Cos2T, Sin3T, Cos3T, Sin4T, Cos4T: Single;
  DX, DY, DZ: Single;
begin
  Result := false;
  SetLength(Items, SelectedCount);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Items[0] <> nil) then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  if Radius > 0 then
    R := Radius
  else
  begin
    SumDist := 0.0;
    for I := 0 to Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]);
      SumDist := SumDist + Hypot(CurPos.X - CenterPos.X, CurPos.Z - CenterPos.Z);
    end;
    R := (SumDist / Count) * 1.25;
    if R < 0.05 then
      R := 5.0;
  end;

  S := R / 3.0;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    ParamT := (2.0 * Pi * I) / Count;
    SinCos(ParamT, SinT, CosT);
    SinCos(2.0 * ParamT, Sin2T, Cos2T);
    SinCos(3.0 * ParamT, Sin3T, Cos3T);

    if FigureEightKnot then
    begin
      SinCos(4.0 * ParamT, Sin4T, Cos4T);
      TargetPos := Vector3(
        CenterPos.X + S * (2.0 + Cos2T) * Cos3T,
        CenterPos.Y + S * Sin4T,
        CenterPos.Z + S * (2.0 + Cos2T) * Sin3T);
      DX := -2.0 * Sin2T * Cos3T - 3.0 * (2.0 + Cos2T) * Sin3T;
      DY := 4.0 * Cos4T;
      DZ := -2.0 * Sin2T * Sin3T + 3.0 * (2.0 + Cos2T) * Cos3T;
    end else
    begin
      TargetPos := Vector3(
        CenterPos.X + S * (SinT + 2.0 * Sin2T),
        CenterPos.Y - S * Sin3T,
        CenterPos.Z + S * (CosT - 2.0 * Cos2T));
      DX := CosT + 4.0 * Cos2T;
      DY := -3.0 * Cos3T;
      DZ := -SinT + 4.0 * Sin2T;
    end;

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        CurveTangent := Vector3(DX, DY, DZ);
        if CurveTangent.IsZero(1e-5) then
          CurveTangent := Vector3(1, 0, 0)
        else
          CurveTangent := CurveTangent.Normalize;
        LookDir := CurveTangent;
      end else
      begin
        LookDir := Vector3(TargetPos.X - CenterPos.X, 0, TargetPos.Z - CenterPos.Z);
        if LookDir.IsZero(1e-5) then
          LookDir := Vector3(CosT, 0, SinT)
        else
          LookDir := LookDir.Normalize;
      end;

      NewUp := Vector3(0, 1, 0) - LookDir * LookDir.Y;
      if NewUp.IsZero(1e-5) then
        NewUp := Vector3(1, 0, 0) - LookDir * LookDir.X;
      NewUp := NewUp.Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInGeodesicDome(
  const Radius: Single;
  const RingsCount: Integer;
  const OrientMode: Integer): Boolean;
var
  Items: array of TCastleTransform;
  Count, I, RIdx, J, NumRings, RemItems, Allocated, RingCap, ItemIdx: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, DomeNormal, LookDir, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  SumDist, R, Phi, Theta, SinP, CosP, SinT, CosT, WeightSum: Single;
  RingWeights: array of Single;
  RingSizes: array of Integer;
begin
  Result := false;
  SetLength(Items, SelectedCount);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Items[0] <> nil) then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  if Radius > 0 then
    R := Radius
  else
  begin
    SumDist := 0.0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Items[I]), CenterPos);
    R := SumDist / Count;
    if R < 0.05 then
      R := 5.0;
  end;

  if RingsCount >= 2 then
    NumRings := Min(Count, RingsCount)
  else
    NumRings := Max(2, Min(Count, Ceil(Sqrt(Count / 1.5)) + 1));

  SetLength(RingWeights, NumRings);
  SetLength(RingSizes, NumRings);
  RingSizes[0] := 1; // Item 0 at dome apex
  RemItems := Count - 1;

  WeightSum := 0.0;
  for RIdx := 1 to NumRings - 1 do
  begin
    Phi := (0.5 * Pi * RIdx) / (NumRings - 1);
    RingWeights[RIdx] := Sin(Phi);
    WeightSum := WeightSum + RingWeights[RIdx];
  end;

  Allocated := 0;
  for RIdx := 1 to NumRings - 1 do
  begin
    if RIdx = NumRings - 1 then
      RingCap := Max(0, RemItems - Allocated)
    else
    begin
      RingCap := Max(1, Round((RingWeights[RIdx] / Max(1e-5, WeightSum)) * RemItems));
      if Allocated + RingCap > RemItems - (NumRings - 1 - RIdx) then
        RingCap := Max(1, RemItems - Allocated - (NumRings - 1 - RIdx));
    end;
    RingSizes[RIdx] := RingCap;
    Allocated := Allocated + RingCap;
  end;

  ItemIdx := 0;
  for RIdx := 0 to NumRings - 1 do
  begin
    RingCap := RingSizes[RIdx];
    if RingCap <= 0 then Continue;

    if RIdx = 0 then
      Phi := 0.0
    else
      Phi := (0.5 * Pi * RIdx) / (NumRings - 1);
    SinCos(Phi, SinP, CosP);

    for J := 0 to RingCap - 1 do
    begin
      if ItemIdx >= Count then Break;
      T := Items[ItemIdx];
      Inc(ItemIdx);

      if RIdx = 0 then
      begin
        Theta := 0.0;
        DomeNormal := Vector3(0, 1, 0);
      end else
      begin
        Theta := (2.0 * Pi * (J + 0.5 * (RIdx mod 2))) / RingCap;
        SinCos(Theta, SinT, CosT);
        DomeNormal := Vector3(SinP * CosT, CosP, SinP * SinT).Normalize;
      end;

      TargetPos := CenterPos + DomeNormal * R;
      CurPos := GetTransformWorkingPos(T);
      if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, TargetPos);
        Result := true;
      end;

      if (OrientMode in [1, 2]) and T.HasWorldTransform then
      begin
        if OrientMode = 1 then
        begin
          NewUp := DomeNormal;
          if RIdx = 0 then
            LookDir := Vector3(0, 0, -1)
          else
          begin
            SinCos(Theta, SinT, CosT);
            LookDir := Vector3(-SinT, 0, CosT);
          end;
          LookDir := LookDir - NewUp * TVector3.DotProduct(LookDir, NewUp);
          if LookDir.IsZero(1e-5) then
            LookDir := Vector3(1, 0, 0) - NewUp * NewUp.X;
          LookDir := LookDir.Normalize;
        end else
        begin
          LookDir := -DomeNormal;
          NewUp := Vector3(0, 1, 0) - LookDir * LookDir.Y;
          if NewUp.IsZero(1e-5) then
            NewUp := Vector3(0, 0, -1) - LookDir * LookDir.Z;
          NewUp := NewUp.Normalize;
        end;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.RadialFalloffSelected(
  const Strength: Single;
  const FalloffRadius: Single;
  const ScaleWithDisplacement: Boolean): Boolean;
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, Offset, RadialDir, TargetPos, TargetScale: TVector3;
  SumDist, RFalloff, Dist, Weight, NewDist, ScaleFactor: Single;
begin
  Result := false;
  if SameValue(Strength, 0.0, 1e-6) then Exit;

  SetLength(Items, SelectedCount);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Items[0] <> nil) then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  if FalloffRadius > 0 then
    RFalloff := FalloffRadius
  else
  begin
    SumDist := 0.0;
    for I := 0 to Count - 1 do
      SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Items[I]), CenterPos);
    RFalloff := SumDist / Count;
    if RFalloff < 0.05 then
      RFalloff := 5.0;
  end;

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    CurPos := GetTransformWorkingPos(T);
    Offset := CurPos - CenterPos;
    Dist := Offset.Length;
    Weight := Exp(-Sqr(Dist / RFalloff));

    if Dist > 1e-5 then
    begin
      RadialDir := Offset / Dist;
      NewDist := Max(0.0, Dist + Strength * Weight);
      TargetPos := CenterPos + RadialDir * NewDist;
      if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, TargetPos);
        Result := true;
      end;
    end;

    if ScaleWithDisplacement then
    begin
      ScaleFactor := Clamped(1.0 + 0.5 * (Strength / RFalloff) * Weight, 0.1, 10.0);
      TargetScale := T.Scale * ScaleFactor;
      if not TVector3.Equals(T.Scale, TargetScale, 1e-5) then
      begin
        T.Scale := TargetScale;
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

function TCastleTransformManipulate.ArrangeSelectedInCycloid(
  const Radius: Single;
  const Cusps: Integer;
  const Epicycloid: Boolean;
  const OrientMode: Integer): Boolean;

  procedure EvalCycloidPointAndTangent(const TParam, R: Single;
    const K: Integer; const IsEpicycloid: Boolean;
    out LocalXZ, TangentDir: TVector3);
  var
    SinT, CosT, SinSub, CosSub, ScaleF, DX, DZ, SinT2, CosT2, SinSub2, CosSub2: Single;
    T2: Single;
  begin
    SinCos(TParam, SinT, CosT);
    if IsEpicycloid then
    begin
      SinCos((K + 1) * TParam, SinSub, CosSub);
      ScaleF := R / (K + 2);
      LocalXZ := Vector3(
        ScaleF * ((K + 1) * CosT - CosSub),
        0.0,
        ScaleF * ((K + 1) * SinT - SinSub));
      DX := ScaleF * (K + 1) * (-SinT + SinSub);
      DZ := ScaleF * (K + 1) * (CosT - CosSub);
      if Hypot(DX, DZ) < 1e-5 then
      begin
        T2 := TParam + 0.01;
        SinCos(T2, SinT2, CosT2);
        SinCos((K + 1) * T2, SinSub2, CosSub2);
        DX := -SinT2 + SinSub2;
        DZ := CosT2 - CosSub2;
      end;
    end else
    begin
      SinCos((K - 1) * TParam, SinSub, CosSub);
      ScaleF := R / K;
      LocalXZ := Vector3(
        ScaleF * ((K - 1) * CosT + CosSub),
        0.0,
        ScaleF * ((K - 1) * SinT - SinSub));
      DX := ScaleF * (K - 1) * (-SinT - SinSub);
      DZ := ScaleF * (K - 1) * (CosT - CosSub);
      if Hypot(DX, DZ) < 1e-5 then
      begin
        T2 := TParam + 0.01;
        SinCos(T2, SinT2, CosT2);
        SinCos((K - 1) * T2, SinSub2, CosSub2);
        DX := -SinT2 - SinSub2;
        DZ := CosT2 - CosSub2;
      end;
    end;
    TangentDir := Vector3(DX, 0.0, DZ);
    if TangentDir.IsZero(1e-6) then
      TangentDir := Vector3(0.0, 0.0, -1.0)
    else
      TangentDir := TangentDir.Normalize;
  end;

var
  Items: array of TCastleTransform;
  Count, I, KVal: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, LocalXZ, TargetPos, TangentDir, LookDir, NewUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  SumDist, R, TParam: Single;
begin
  Result := false;
  SetLength(Items, SelectedCount);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Items[0] <> nil) then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  if Radius > 0 then
    R := Radius
  else
  begin
    SumDist := 0.0;
    for I := 0 to Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]) - CenterPos;
      SumDist := SumDist + Hypot(CurPos.X, CurPos.Z);
    end;
    R := SumDist / Count;
    if R < 0.05 then
      R := 5.0;
  end;

  KVal := Max(2, Cusps);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    TParam := (2.0 * Pi * I) / Count;
    EvalCycloidPointAndTangent(TParam, R, KVal, Epicycloid, LocalXZ, TangentDir);
    TargetPos := CenterPos + LocalXZ;

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
        LookDir := TangentDir
      else
      begin
        LookDir := Vector3(LocalXZ.X, 0.0, LocalXZ.Z);
        if LookDir.IsZero(1e-5) then
          LookDir := Vector3(Cos(TParam), 0.0, Sin(TParam))
        else
          LookDir := LookDir.Normalize;
      end;

      NewUp := Vector3(0.0, 1.0, 0.0);
      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedOnHyperboloid(
  const WaistRadius: Single;
  const HeightSpan: Single;
  const FlareFactor: Single;
  const OrientMode: Integer): Boolean;
const
  GoldenAngle = 2.39996322972865332; // Pi * (3 - Sqrt(5))
var
  Items: array of TCastleTransform;
  Count, I: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, LookDir, Side, NewUp, GravityUp: TVector3;
  CurWorldPos, CurDir, CurUp: TVector3;
  SumDist, RWaist, HSpan, HalfH, Alpha, U, RadScale, R, Theta, SinT, CosT: Single;
begin
  Result := false;
  SetLength(Items, SelectedCount);
  Count := 0;
  for I := 0 to SelectedCount - 1 do
  begin
    T := Selected[I];
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Items[Count] := T;
      Inc(Count);
    end;
  end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Items[0] <> nil) then
    CenterPos := GetTransformWorkingPos(Items[0])
  else
    CenterPos := SelectionWorkingCenter;

  if WaistRadius > 0 then
    RWaist := WaistRadius
  else
  begin
    SumDist := 0.0;
    for I := 0 to Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(Items[I]) - CenterPos;
      SumDist := SumDist + Hypot(CurPos.X, CurPos.Z);
    end;
    RWaist := SumDist / Count;
    if RWaist < 0.05 then
      RWaist := 4.0;
  end;

  if HeightSpan > 0 then
    HSpan := HeightSpan
  else
    HSpan := 2.0 * RWaist;
  HalfH := 0.5 * HSpan;
  Alpha := Max(0.0, FlareFactor);

  if (Items[0].World <> nil) and (not Items[0].World.GravityUp.IsZero) then
    GravityUp := Items[0].World.GravityUp.Normalize
  else
    GravityUp := Vector3(0, 1, 0);

  for I := 0 to Count - 1 do
  begin
    T := Items[I];
    U := -1.0 + (2.0 * I) / (Count - 1);
    RadScale := Sqrt(1.0 + Sqr(Alpha * U));
    R := RWaist * RadScale;
    Theta := I * GoldenAngle;
    SinCos(Theta, SinT, CosT);

    TargetPos := Vector3(
      CenterPos.X + R * CosT,
      CenterPos.Y + HalfH * U,
      CenterPos.Z + R * SinT);

    CurPos := GetTransformWorkingPos(T);
    if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, TargetPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        // Outward surface normal of Hyperboloid of One Sheet
        LookDir := Vector3(
          RadScale * CosT,
          -(RWaist * Sqr(Alpha) / Max(1e-4, HalfH)) * U,
          RadScale * SinT).Normalize;
      end else
      begin
        // Straight-line generator ruling of Hyperboloid of One Sheet
        LookDir := Vector3(
          -RWaist * Alpha * SinT,
          HalfH,
          RWaist * Alpha * CosT).Normalize;
      end;

      Side := TVector3.CrossProduct(LookDir, GravityUp);
      if Side.IsZero(1e-5) then
        Side := Vector3(-SinT, 0.0, CosT);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.CylindrifySelected(
  const TargetRadius: Single;
  const StrengthFactor: Single;
  const CapsuleHemispheres: Boolean;
  const OrientRadially: Boolean): Boolean;
var
  I, Count, ValidHorizCount: Integer;
  T: TCastleTransform;
  Targets: array of TCastleTransform;
  Center, OldWorldPos, SpinePt, OffsetVec, OutwardDir, TargetPos, NewWorldPos, WorldDelta, LocalDelta: TVector3;
  CurWorldPos, CurDir, CurUp, Side, NewUp: TVector3;
  HorizDist, SumHoriz, ActualRadius, MaxAbsDY, HalfSpineY, SpineY, Blend, Len: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  Count := 0;
  SetLength(Targets, SelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
    begin
      Targets[Count] := Boxes[I].Parent;
      Inc(Count);
    end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;
  SumHoriz := 0.0;
  ValidHorizCount := 0;
  MaxAbsDY := 0.0;

  for I := 0 to Count - 1 do
  begin
    OldWorldPos := GetTransformWorkingPos(Targets[I]);
    HorizDist := Hypot(OldWorldPos.X - Center.X, OldWorldPos.Z - Center.Z);
    if HorizDist > 1e-4 then
    begin
      SumHoriz := SumHoriz + HorizDist;
      Inc(ValidHorizCount);
    end;
    MaxAbsDY := Max(MaxAbsDY, Abs(OldWorldPos.Y - Center.Y));
  end;

  if TargetRadius <= 1e-4 then
  begin
    if ValidHorizCount > 0 then
      ActualRadius := SumHoriz / Single(ValidHorizCount)
    else
      ActualRadius := 5.0;
  end else
    ActualRadius := TargetRadius;

  HalfSpineY := MaxAbsDY * 0.5;
  Blend := Clamped(StrengthFactor, 0.0, 1.0);

  for I := 0 to Count - 1 do
  begin
    T := Targets[I];
    if T.Parent = nil then Continue;

    OldWorldPos := GetTransformWorkingPos(T);
    if CapsuleHemispheres then
      SpineY := Clamped(OldWorldPos.Y, Center.Y - HalfSpineY, Center.Y + HalfSpineY)
    else
      SpineY := OldWorldPos.Y;

    SpinePt := Vector3(Center.X, SpineY, Center.Z);
    OffsetVec := OldWorldPos - SpinePt;
    if not CapsuleHemispheres then
      OffsetVec.Y := 0.0;

    Len := OffsetVec.Length;
    if Len > 1e-5 then
      OutwardDir := OffsetVec / Len
    else if CapsuleHemispheres and (Abs(OldWorldPos.Y - SpineY) > 1e-5) then
      OutwardDir := Vector3(0.0, Sign(OldWorldPos.Y - SpineY), 0.0)
    else
      OutwardDir := Vector3(1.0, 0.0, 0.0);

    TargetPos := SpinePt + OutwardDir * ActualRadius;
    NewWorldPos := Lerp(Blend, OldWorldPos, TargetPos);
    WorldDelta := NewWorldPos - OldWorldPos;
    if WorldDelta.LengthSqr > Sqr(1e-5) then
    begin
      LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta);
      T.Translation := T.Translation + LocalDelta;
      Result := true;
    end;

    if OrientRadially then
    begin
      if Abs(OutwardDir.Y) > 0.99 then
        Side := TVector3.CrossProduct(OutwardDir, Vector3(0, 0, 1))
      else
        Side := TVector3.CrossProduct(OutwardDir, Vector3(0, 1, 0));
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, OutwardDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, OutwardDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), OutwardDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInCassiniOval(
  const FocusHalfDistA: Single;
  const ShapeRatioBOverA: Single;
  const VerticalRimWave: Single;
  const OrientMode: Integer): Boolean;
const
  DeltaTheta = 1e-3;
var
  I, Count: Integer;
  T: TCastleTransform;
  Targets: array of TCastleTransform;
  Center, OldWorldPos, NewWorldPos, WorldDelta, LocalDelta: TVector3;
  PosMinus, PosPlus, LookDir, CurWorldPos, CurDir, CurUp, Side, NewUp: TVector3;
  ActualA, CVal, C4, AvgDist, Theta: Single;

  function EvalCassiniPoint(const Angle: Single): TVector3;
  var
    SinT, CosT, Sin2T, Cos2T, InnerRad, Rad: Single;
  begin
    SinCos(Angle, SinT, CosT);
    SinCos(2.0 * Angle, Sin2T, Cos2T);
    InnerRad := Cos2T + Sqrt(Max(0.0, C4 - Sqr(Sin2T)));
    Rad := ActualA * Sqrt(Max(0.0, InnerRad));
    Result := Vector3(
      Center.X + Rad * CosT,
      Center.Y + VerticalRimWave * Cos2T,
      Center.Z + Rad * SinT);
  end;

begin
  Result := false;
  if SelectedCount < 2 then Exit;

  Count := 0;
  SetLength(Targets, SelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
    begin
      Targets[Count] := Boxes[I].Parent;
      Inc(Count);
    end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;
  CVal := Max(1.0001, Abs(ShapeRatioBOverA));
  C4 := Sqr(Sqr(CVal));

  ActualA := FocusHalfDistA;
  if ActualA <= 1e-4 then
  begin
    AvgDist := 0.0;
    for I := 0 to Count - 1 do
    begin
      OldWorldPos := GetTransformWorkingPos(Targets[I]);
      AvgDist := AvgDist + Hypot(OldWorldPos.X - Center.X, OldWorldPos.Z - Center.Z);
    end;
    AvgDist := AvgDist / Single(Count);
    if AvgDist > 1e-4 then
      ActualA := AvgDist / Sqrt(1.0 + Sqr(CVal))
    else
      ActualA := 5.0;
  end;

  for I := 0 to Count - 1 do
  begin
    T := Targets[I];
    if T.Parent = nil then Continue;

    Theta := (2.0 * Pi * Single(I)) / Single(Count);
    OldWorldPos := GetTransformWorkingPos(T);
    NewWorldPos := EvalCassiniPoint(Theta);

    WorldDelta := NewWorldPos - OldWorldPos;
    if WorldDelta.LengthSqr > Sqr(1e-5) then
    begin
      LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta);
      T.Translation := T.Translation + LocalDelta;
      Result := true;
    end;

    if (OrientMode = 1) or (OrientMode = 2) then
    begin
      if OrientMode = 1 then
      begin
        PosMinus := EvalCassiniPoint(Theta - DeltaTheta);
        PosPlus := EvalCassiniPoint(Theta + DeltaTheta);
        LookDir := PosPlus - PosMinus;
        if LookDir.LengthSqr <= Sqr(1e-5) then
          LookDir := Vector3(-Sin(Theta), 0.0, Cos(Theta));
      end else
      begin
        LookDir := Center - NewWorldPos;
        LookDir.Y := 0.0;
        if LookDir.LengthSqr <= Sqr(1e-5) then
          LookDir := Vector3(-Cos(Theta), 0.0, -Sin(Theta));
      end;
      LookDir := LookDir.Normalize;

      if Abs(LookDir.Y) > 0.99 then
        Side := TVector3.CrossProduct(LookDir, Vector3(0, 0, 1))
      else
        Side := TVector3.CrossProduct(LookDir, Vector3(0, 1, 0));
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedOnCatenoid(
  const WaistRadius: Single;
  const HeightSpan: Single;
  const NeckCurvature: Single;
  const OrientMode: Integer): Boolean;
const
  GoldenAngle = 2.39996322972865332; // Pi * (3 - Sqrt(5))
var
  I, Count: Integer;
  T: TCastleTransform;
  Targets: array of TCastleTransform;
  Center, OldWorldPos, NewWorldPos, WorldDelta, LocalDelta: TVector3;
  LookDir, CurWorldPos, CurDir, CurUp, Side, NewUp: TVector3;
  ActualWaist, ActualHeight, Kappa, AvgDist, U, Theta, SinT, CosT, RadAtU, DrDy: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  Count := 0;
  SetLength(Targets, SelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
    begin
      Targets[Count] := Boxes[I].Parent;
      Inc(Count);
    end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;
  ActualWaist := WaistRadius;
  if ActualWaist <= 1e-4 then
  begin
    AvgDist := 0.0;
    for I := 0 to Count - 1 do
    begin
      OldWorldPos := GetTransformWorkingPos(Targets[I]);
      AvgDist := AvgDist + Hypot(OldWorldPos.X - Center.X, OldWorldPos.Z - Center.Z);
    end;
    AvgDist := AvgDist / Single(Count);
    if AvgDist > 1e-4 then
      ActualWaist := AvgDist
    else
      ActualWaist := 4.0;
  end;

  ActualHeight := HeightSpan;
  if ActualHeight <= 1e-4 then
    ActualHeight := ActualWaist * 2.0;
  Kappa := Max(0.01, Abs(NeckCurvature));

  for I := 0 to Count - 1 do
  begin
    T := Targets[I];
    if T.Parent = nil then Continue;

    U := -1.0 + (2.0 * Single(I)) / Single(Count - 1);
    RadAtU := ActualWaist * Cosh(Kappa * U);
    Theta := Single(I) * GoldenAngle;
    SinCos(Theta, SinT, CosT);

    OldWorldPos := GetTransformWorkingPos(T);
    NewWorldPos := Vector3(
      Center.X + RadAtU * CosT,
      Center.Y + 0.5 * ActualHeight * U,
      Center.Z + RadAtU * SinT);

    WorldDelta := NewWorldPos - OldWorldPos;
    if WorldDelta.LengthSqr > Sqr(1e-5) then
    begin
      LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta);
      T.Translation := T.Translation + LocalDelta;
      Result := true;
    end;

    if (OrientMode = 1) or (OrientMode = 2) then
    begin
      DrDy := (2.0 * Kappa * ActualWaist / ActualHeight) * Sinh(Kappa * U);
      if OrientMode = 1 then
      begin
        { Outward catenoid minimal-surface normal: (cos Theta, -dr/dy, sin Theta) }
        LookDir := Vector3(CosT, -DrDy, SinT);
      end else
      begin
        { Catenary meridian tangent pointing upward along the profile }
        LookDir := Vector3(DrDy * CosT, 1.0, DrDy * SinT);
      end;
      LookDir := LookDir.Normalize;

      if Abs(LookDir.Y) > 0.99 then
        Side := TVector3.CrossProduct(LookDir, Vector3(0, 0, 1))
      else
        Side := TVector3.CrossProduct(LookDir, Vector3(0, 1, 0));
      if Side.LengthSqr <= Sqr(1e-5) then
        Side := Vector3(-SinT, 0.0, CosT);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.BarrelPincushionSelected(
  const Axis: Integer;
  const BulgeFactor: Single;
  const ScaleObjects: Boolean): Boolean;
var
  I, Count, SpineAxis, Perp1, Perp2: Integer;
  T: TCastleTransform;
  Targets: array of TCastleTransform;
  Center, OldWorldPos, NewWorldPos, WorldDelta, LocalDelta, NewScale: TVector3;
  MaxAbsAlong, HalfSpan, U, ScalePerp: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  Count := 0;
  SetLength(Targets, SelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
    begin
      Targets[Count] := Boxes[I].Parent;
      Inc(Count);
    end;

  if Count < 2 then Exit;

  SpineAxis := Clamped(Axis, 0, 2);
  Perp1 := (SpineAxis + 1) mod 3;
  Perp2 := (SpineAxis + 2) mod 3;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;

  MaxAbsAlong := 0.0;
  for I := 0 to Count - 1 do
  begin
    OldWorldPos := GetTransformWorkingPos(Targets[I]);
    MaxAbsAlong := Max(MaxAbsAlong, Abs(OldWorldPos.Data[SpineAxis] - Center.Data[SpineAxis]));
  end;
  HalfSpan := Max(1e-4, MaxAbsAlong);

  for I := 0 to Count - 1 do
  begin
    T := Targets[I];
    if T.Parent = nil then Continue;

    OldWorldPos := GetTransformWorkingPos(T);
    if MaxAbsAlong > 1e-4 then
      U := Clamped((OldWorldPos.Data[SpineAxis] - Center.Data[SpineAxis]) / HalfSpan, -1.0, 1.0)
    else
      U := 0.0;

    ScalePerp := Max(0.05, 1.0 + BulgeFactor * (1.0 - Sqr(U)));

    NewWorldPos := OldWorldPos;
    NewWorldPos.Data[Perp1] := Center.Data[Perp1] + (OldWorldPos.Data[Perp1] - Center.Data[Perp1]) * ScalePerp;
    NewWorldPos.Data[Perp2] := Center.Data[Perp2] + (OldWorldPos.Data[Perp2] - Center.Data[Perp2]) * ScalePerp;

    WorldDelta := NewWorldPos - OldWorldPos;
    if WorldDelta.LengthSqr > Sqr(1e-5) then
    begin
      LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta);
      T.Translation := T.Translation + LocalDelta;
      Result := true;
    end;

    if ScaleObjects and (Abs(ScalePerp - 1.0) > 1e-4) then
    begin
      NewScale := T.Scale;
      NewScale.Data[Perp1] := NewScale.Data[Perp1] * ScalePerp;
      NewScale.Data[Perp2] := NewScale.Data[Perp2] * ScalePerp;
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

function TCastleTransformManipulate.ArrangeSelectedInHippopede(
  const Radius: Single;
  const PinchLambda: Single;
  const OrientMode: Integer): Boolean;
const
  DeltaTheta = 1e-3;
var
  I, Count: Integer;
  T: TCastleTransform;
  Targets: array of TCastleTransform;
  Center, OldWorldPos, NewWorldPos, WorldDelta, LocalDelta: TVector3;
  PosMinus, PosPlus, LookDir, CurWorldPos, CurDir, CurUp, Side, NewUp: TVector3;
  ActualRadius, Lambda, SqrtLambda, AvgDist, Theta: Single;

  function EvalHippopedePoint(const Angle: Single): TVector3;
  var
    SinT, CosT, RXZ: Single;
  begin
    SinCos(Angle, SinT, CosT);
    RXZ := ActualRadius * Sqrt(Max(0.0, 1.0 - Lambda * Sqr(SinT)));
    Result := Vector3(
      Center.X + RXZ * CosT,
      Center.Y + ActualRadius * SqrtLambda * SinT,
      Center.Z + RXZ * SinT);
  end;

begin
  Result := false;
  if SelectedCount < 2 then Exit;

  Count := 0;
  SetLength(Targets, SelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
    begin
      Targets[Count] := Boxes[I].Parent;
      Inc(Count);
    end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;

  Lambda := Clamped(PinchLambda, 0.0, 1.0);
  SqrtLambda := Sqrt(Lambda);

  ActualRadius := Radius;
  if ActualRadius <= 1e-4 then
  begin
    AvgDist := 0.0;
    for I := 0 to Count - 1 do
      AvgDist := AvgDist + PointsDistance(GetTransformWorkingPos(Targets[I]), Center);
    AvgDist := AvgDist / Single(Count);
    if AvgDist > 1e-4 then
      ActualRadius := AvgDist
    else
      ActualRadius := 6.0;
  end;

  for I := 0 to Count - 1 do
  begin
    T := Targets[I];
    if T.Parent = nil then Continue;

    Theta := (2.0 * Pi * Single(I)) / Single(Count);
    OldWorldPos := GetTransformWorkingPos(T);
    NewWorldPos := EvalHippopedePoint(Theta);

    WorldDelta := NewWorldPos - OldWorldPos;
    if WorldDelta.LengthSqr > Sqr(1e-5) then
    begin
      LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta);
      T.Translation := T.Translation + LocalDelta;
      Result := true;
    end;

    if (OrientMode = 1) or (OrientMode = 2) then
    begin
      if OrientMode = 1 then
      begin
        LookDir := NewWorldPos - Center;
        if LookDir.LengthSqr <= Sqr(1e-5) then
          LookDir := Vector3(Cos(Theta), 0.0, Sin(Theta));
      end else
      begin
        PosMinus := EvalHippopedePoint(Theta - DeltaTheta);
        PosPlus := EvalHippopedePoint(Theta + DeltaTheta);
        LookDir := PosPlus - PosMinus;
        if LookDir.LengthSqr <= Sqr(1e-5) then
          LookDir := Vector3(-Sin(Theta), 0.0, Cos(Theta));
      end;
      LookDir := LookDir.Normalize;

      if Abs(LookDir.Y) > 0.99 then
        Side := TVector3.CrossProduct(LookDir, Vector3(0, 0, 1))
      else
        Side := TVector3.CrossProduct(LookDir, Vector3(0, 1, 0));
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedOnHelicoid(
  const OuterRadius: Single;
  const HeightSpan: Single;
  const Turns: Single;
  const OrientMode: Integer): Boolean;
var
  I, Count: Integer;
  T: TCastleTransform;
  Targets: array of TCastleTransform;
  Center, OldWorldPos, NewWorldPos, WorldDelta, LocalDelta: TVector3;
  LookDir, CurWorldPos, CurDir, CurUp, Side, NewUp: TVector3;
  ActualRadius, ActualHeight, ActualTurns, PitchPerRad, AvgDist, U, Theta, SinT, CosT, SignedS: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  Count := 0;
  SetLength(Targets, SelectedCount);
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
    if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
    begin
      Targets[Count] := Boxes[I].Parent;
      Inc(Count);
    end;

  if Count < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;

  ActualRadius := OuterRadius;
  if ActualRadius <= 1e-4 then
  begin
    AvgDist := 0.0;
    for I := 0 to Count - 1 do
    begin
      OldWorldPos := GetTransformWorkingPos(Targets[I]);
      AvgDist := AvgDist + Hypot(OldWorldPos.X - Center.X, OldWorldPos.Z - Center.Z);
    end;
    AvgDist := AvgDist / Single(Count);
    if AvgDist > 1e-4 then
      ActualRadius := AvgDist
    else
      ActualRadius := 5.0;
  end;

  ActualHeight := HeightSpan;
  if ActualHeight <= 1e-4 then
    ActualHeight := ActualRadius * 2.0;

  ActualTurns := Turns;
  if Abs(ActualTurns) <= 1e-4 then
    ActualTurns := 1.0;

  PitchPerRad := ActualHeight / (2.0 * Pi * ActualTurns);

  for I := 0 to Count - 1 do
  begin
    T := Targets[I];
    if T.Parent = nil then Continue;

    U := -1.0 + (2.0 * Single(I)) / Single(Count - 1);
    Theta := Pi * ActualTurns * U;
    SinCos(Theta, SinT, CosT);
    if (I and 1) = 0 then
      SignedS := ActualRadius
    else
      SignedS := -ActualRadius;

    OldWorldPos := GetTransformWorkingPos(T);
    NewWorldPos := Vector3(
      Center.X + SignedS * CosT,
      Center.Y + 0.5 * ActualHeight * U,
      Center.Z + SignedS * SinT);

    WorldDelta := NewWorldPos - OldWorldPos;
    if WorldDelta.LengthSqr > Sqr(1e-5) then
    begin
      LocalDelta := T.Parent.WorldToLocalDirection(WorldDelta);
      T.Translation := T.Translation + LocalDelta;
      Result := true;
    end;

    if (OrientMode = 1) or (OrientMode = 2) then
    begin
      if OrientMode = 1 then
      begin
        { Analytical Helicoid minimal-surface normal: (c*sin Theta, R, -c*cos Theta) }
        LookDir := Vector3(PitchPerRad * SinT, ActualRadius, -PitchPerRad * CosT);
      end else
      begin
        { Straight horizontal Helicoid ruling direction }
        LookDir := Vector3(CosT, 0.0, SinT);
      end;
      LookDir := LookDir.Normalize;

      if Abs(LookDir.Y) > 0.99 then
        Side := TVector3.CrossProduct(LookDir, Vector3(0, 0, 1))
      else
        Side := TVector3.CrossProduct(LookDir, Vector3(0, 1, 0));
      if Side.LengthSqr <= Sqr(1e-5) then
        Side := Vector3(-SinT, 0.0, CosT);
      Side := Side.Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.WaveDeformSelected(
  const WaveAxis: Integer;
  const DisplaceAxis: Integer;
  const Amplitude: Single;
  const Wavelength: Single;
  const PhaseRad: Single;
  const OrientNormals: Boolean): Boolean;
var
  Targets: array of TCastleTransform;
  Positions: array of TVector3;
  N, I, WAxis, DAxis: Integer;
  T: TCastleTransform;
  Center, P, NewPos, TangentVec, NormalVec, CurWorldPos, CurDir, CurUp: TVector3;
  MinW, MaxW, ActualWavelength, KWave, U, Phi, Slope: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Targets, FMaxSelectedCount);
  N := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Targets[N] := T;
      Inc(N);
    end;
  end;
  if N < 2 then Exit;

  WAxis := Clamped(WaveAxis, 0, 2);
  DAxis := Clamped(DisplaceAxis, 0, 2);
  if DAxis = WAxis then
    DAxis := (WAxis + 1) mod 3;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;

  SetLength(Positions, N);
  MinW := MaxSingle;
  MaxW := -MaxSingle;
  for I := 0 to N - 1 do
  begin
    Positions[I] := GetTransformWorkingPos(Targets[I]);
    MinW := Min(MinW, Positions[I].Data[WAxis]);
    MaxW := Max(MaxW, Positions[I].Data[WAxis]);
  end;

  ActualWavelength := Wavelength;
  if ActualWavelength <= 1e-4 then
  begin
    ActualWavelength := MaxW - MinW;
    if ActualWavelength < 1e-3 then
      ActualWavelength := 10.0;
  end;
  KWave := (2.0 * Pi) / ActualWavelength;

  for I := 0 to N - 1 do
  begin
    T := Targets[I];
    P := Positions[I];
    U := P.Data[WAxis] - Center.Data[WAxis];
    Phi := KWave * U + PhaseRad;

    NewPos := P;
    NewPos.Data[DAxis] := P.Data[DAxis] + Amplitude * Sin(Phi);

    if not TVector3.Equals(P, NewPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if OrientNormals and T.HasWorldTransform then
    begin
      Slope := Amplitude * KWave * Cos(Phi);

      TangentVec := TVector3.Zero;
      TangentVec.Data[WAxis] := 1.0;
      TangentVec.Data[DAxis] := Slope;
      TangentVec := TangentVec.Normalize;

      NormalVec := TVector3.Zero;
      NormalVec.Data[DAxis] := 1.0;
      NormalVec.Data[WAxis] := -Slope;
      NormalVec := NormalVec.Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, TangentVec, 1e-4)) or
         (not TVector3.Equals(CurUp, NormalVec, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), TangentVec, NormalVec);
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

function TCastleTransformManipulate.ArrangeSelectedOnEnneperSurface(
  const ScaleRadius: Single;
  const MaxR: Single;
  const OrderK: Integer;
  const OrientMode: Integer): Boolean;
var
  Targets: array of TCastleTransform;
  N, I, K, M, P: Integer;
  T: TCastleTransform;
  Center, CurPos, NewPos, LookDir, NewUp, Side, CurWorldPos, CurDir, CurUp: TVector3;
  ActualScale, ActualMaxR, SumDist, U, RParam, Theta, SinT, CosT: Single;
  RK, R2K, RP, RM, InvDenom, DX, DY, DZ: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Targets, FMaxSelectedCount);
  N := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Targets[N] := T;
      Inc(N);
    end;
  end;
  if N < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;

  K := Max(1, OrderK);
  M := 2 * K + 1;
  P := K + 1;
  ActualMaxR := Clamped(MaxR, 0.2, 1.8);

  ActualScale := ScaleRadius;
  if ActualScale <= 1e-4 then
  begin
    SumDist := 0.0;
    for I := 0 to N - 1 do
      SumDist := SumDist + PointsDistance(GetTransformWorkingPos(Targets[I]), Center);
    ActualScale := (SumDist / N) / Max(0.5, ActualMaxR);
    if ActualScale < 1e-3 then
      ActualScale := 4.0;
  end;

  for I := 0 to N - 1 do
  begin
    T := Targets[I];
    CurPos := GetTransformWorkingPos(T);
    U := I / (N - 1);
    RParam := ActualMaxR * Sqrt(U);
    Theta := 2.0 * Pi * U;
    SinCos(Theta, SinT, CosT);

    RM := Power(RParam, M);
    RP := Power(RParam, P);
    RK := Power(RParam, K);
    R2K := Sqr(RK);

    NewPos.X := Center.X + ActualScale * (RParam * CosT - (RM / M) * Cos(M * Theta));
    NewPos.Y := Center.Y + ActualScale * ((2.0 / P) * RP * Cos(P * Theta));
    NewPos.Z := Center.Z + ActualScale * (-RParam * SinT - (RM / M) * Sin(M * Theta));

    if not TVector3.Equals(CurPos, NewPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      if OrientMode = 1 then
      begin
        // Exact Gauss-map unit normal of Enneper's minimal surface:
        InvDenom := 1.0 / (1.0 + R2K);
        LookDir := Vector3(
          2.0 * RK * Cos(K * Theta) * InvDenom,
          (1.0 - R2K) * InvDenom,
          2.0 * RK * Sin(K * Theta) * InvDenom);
      end else
      begin
        // Azimuthal derivative dPos/dTheta on Enneper surface:
        if RParam > 1e-4 then
        begin
          DX := -RParam * SinT + RM * Sin(M * Theta);
          DY := -2.0 * RP * Sin(P * Theta);
          DZ := -RParam * CosT - RM * Cos(M * Theta);
          LookDir := Vector3(DX, DY, DZ);
        end else
          LookDir := Vector3(0.0, 0.0, -1.0);
      end;

      if LookDir.LengthSqr > 1e-8 then
      begin
        LookDir := LookDir.Normalize;
        NewUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(LookDir, NewUp)) > 0.98 then
          NewUp := Vector3(0, 0, 1);
        Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.ArrangeSelectedInGearWheel(
  const PitchRadius: Single;
  const ToothDepth: Single;
  const TeethCount: Integer;
  const SharpSawtooth: Boolean;
  const OrientMode: Integer): Boolean;
var
  Targets: array of TCastleTransform;
  N, I, M: Integer;
  T: TCastleTransform;
  Center, CurPos, NewPos, LookDir, NewUp, Side, CurWorldPos, CurDir, CurUp: TVector3;
  ActualPitchR, SumDist, Theta, SinT, CosT, Tau, RVal, DRDTheta, DX, DZ: Single;
begin
  Result := false;
  if SelectedCount < 2 then Exit;

  SetLength(Targets, FMaxSelectedCount);
  N := 0;
  for I := 0 to Integer(FMaxSelectedCount) - 1 do
  begin
    T := Boxes[I].Parent;
    if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
    begin
      Targets[N] := T;
      Inc(N);
    end;
  end;
  if N < 2 then Exit;

  if (FPivotMode = pmPrimarySelected) and (Targets[0] <> nil) then
    Center := GetTransformWorkingPos(Targets[0])
  else
    Center := SelectionWorkingCenter;

  M := Max(1, TeethCount);
  ActualPitchR := PitchRadius;
  if ActualPitchR <= 1e-4 then
  begin
    SumDist := 0.0;
    for I := 0 to N - 1 do
    begin
      CurPos := GetTransformWorkingPos(Targets[I]);
      SumDist := SumDist + Hypot(CurPos.X - Center.X, CurPos.Z - Center.Z);
    end;
    ActualPitchR := SumDist / N;
    if ActualPitchR < 1e-3 then
      ActualPitchR := 8.0;
  end;

  for I := 0 to N - 1 do
  begin
    T := Targets[I];
    CurPos := GetTransformWorkingPos(T);
    Theta := (2.0 * Pi * I) / N;
    SinCos(Theta, SinT, CosT);

    if SharpSawtooth then
    begin
      Tau := Frac((M * I) / N);
      if Tau < 0.0 then
        Tau := Tau + 1.0;
      RVal := Max(0.05, ActualPitchR + ToothDepth * (2.0 * Tau - 1.0));
      DRDTheta := (ToothDepth * M) / Pi;
    end else
    begin
      RVal := Max(0.05, ActualPitchR + ToothDepth * Cos(M * Theta));
      DRDTheta := -ToothDepth * M * Sin(M * Theta);
    end;

    NewPos.X := Center.X + RVal * CosT;
    NewPos.Y := Center.Y;
    NewPos.Z := Center.Z + RVal * SinT;

    if not TVector3.Equals(CurPos, NewPos, 1e-5) then
    begin
      SetTransformWorkingPos(T, NewPos);
      Result := true;
    end;

    if (OrientMode in [1, 2]) and T.HasWorldTransform then
    begin
      DX := DRDTheta * CosT - RVal * SinT;
      DZ := DRDTheta * SinT + RVal * CosT;
      if OrientMode = 1 then
        LookDir := Vector3(DZ, 0.0, -DX)
      else
        LookDir := Vector3(DX, 0.0, DZ);

      if LookDir.LengthSqr < 1e-8 then
        LookDir := Vector3(CosT, 0.0, SinT);

      LookDir := LookDir.Normalize;
      NewUp := Vector3(0, 1, 0);
      Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
      NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

      T.GetWorldView(CurWorldPos, CurDir, CurUp);
      if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
         (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
      begin
        T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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

function TCastleTransformManipulate.SaddleDomeDeformSelected(
  const DisplaceAxis: Integer;
  const CurvatureU: Single;
  const CurvatureV: Single;
  const OrientNormals: Boolean): Boolean;
var
  TopLevel: TCastleTransformList;
  I, DAxis, UAxis, VAxis: Integer;
  T: TCastleTransform;
  Center, CurPos, NewPos, CurWorldPos, CurDir, CurUp, TanU, TanV, SurfNormal, LookDir, NewUp, Side: TVector3;
  HalfSpanU, HalfSpanV, UVal, VVal, DeltaD, SlopeU, SlopeV: Single;
begin
  Result := false;
  if SelectedCount < 2 then
    Exit;
  if (Abs(CurvatureU) < 1e-6) and (Abs(CurvatureV) < 1e-6) then
    Exit;

  DAxis := Clamped(DisplaceAxis, 0, 2);
  case DAxis of
    0: begin UAxis := 1; VAxis := 2; end;
    1: begin UAxis := 0; VAxis := 2; end;
  else
    begin UAxis := 0; VAxis := 1; end;
  end;

  TopLevel := TCastleTransformList.Create(false);
  try
    for I := 0 to SelectedCount - 1 do
    begin
      T := Selected[I];
      if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
        TopLevel.Add(T);
    end;

    if TopLevel.Count < 2 then
      Exit;

    if (FPivotMode = pmPrimarySelected) and (TopLevel[0] <> nil) then
      Center := GetTransformWorkingPos(TopLevel[0])
    else
      Center := SelectionWorkingCenter;
    HalfSpanU := 0.0;
    HalfSpanV := 0.0;
    for I := 0 to TopLevel.Count - 1 do
    begin
      CurPos := GetTransformWorkingPos(TopLevel[I]);
      HalfSpanU := Max(HalfSpanU, Abs(CurPos.Data[UAxis] - Center.Data[UAxis]));
      HalfSpanV := Max(HalfSpanV, Abs(CurPos.Data[VAxis] - Center.Data[VAxis]));
    end;
    if HalfSpanU < 1e-4 then
      HalfSpanU := 5.0;
    if HalfSpanV < 1e-4 then
      HalfSpanV := 5.0;

    for I := 0 to TopLevel.Count - 1 do
    begin
      T := TopLevel[I];
      CurPos := GetTransformWorkingPos(T);
      UVal := Clamped((CurPos.Data[UAxis] - Center.Data[UAxis]) / HalfSpanU, -1.0, 1.0);
      VVal := Clamped((CurPos.Data[VAxis] - Center.Data[VAxis]) / HalfSpanV, -1.0, 1.0);
      DeltaD := CurvatureU * Sqr(UVal) + CurvatureV * Sqr(VVal);

      NewPos := CurPos;
      NewPos.Data[DAxis] := CurPos.Data[DAxis] + DeltaD;

      if not TVector3.Equals(CurPos, NewPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, NewPos);
        Result := true;
      end;

      if OrientNormals and T.HasWorldTransform then
      begin
        SlopeU := (2.0 * CurvatureU * UVal) / HalfSpanU;
        SlopeV := (2.0 * CurvatureV * VVal) / HalfSpanV;

        TanU := TVector3.Zero;
        TanU.Data[UAxis] := 1.0;
        TanU.Data[DAxis] := SlopeU;
        TanU := TanU.Normalize;

        TanV := TVector3.Zero;
        TanV.Data[VAxis] := 1.0;
        TanV.Data[DAxis] := SlopeV;
        TanV := TanV.Normalize;

        SurfNormal := TVector3.CrossProduct(TanV, TanU);
        if SurfNormal.Data[DAxis] < 0.0 then
          SurfNormal := -SurfNormal;
        if SurfNormal.LengthSqr < 1e-8 then
        begin
          SurfNormal := TVector3.Zero;
          SurfNormal.Data[DAxis] := 1.0;
        end else
          SurfNormal := SurfNormal.Normalize;

        LookDir := TanU;
        NewUp := SurfNormal;
        Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedOnKleinBottle(
  const MajorRadius: Single;
  const LobeRadius: Single;
  const Turns: Single;
  const OrientMode: Integer): Boolean;
var
  TopLevel: TCastleTransformList;
  I, N: Integer;
  T: TCastleTransform;
  Center, CurPos, NewPos, CurWorldPos, CurDir, CurUp, LookDir, NewUp, Side: TVector3;
  AutoR, ActualR, ActualA, ActualW: Single;
  UParam, VParam, HalfU, SinHalfU, CosHalfU, SinV, CosV, Sin2V, Cos2V, Rho, DRhoDU, DX, DY, DZ: Single;
begin
  Result := false;
  if SelectedCount < 2 then
    Exit;

  TopLevel := TCastleTransformList.Create(false);
  try
    for I := 0 to SelectedCount - 1 do
    begin
      T := Selected[I];
      if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
        TopLevel.Add(T);
    end;

    N := TopLevel.Count;
    if N < 2 then
      Exit;

    if (FPivotMode = pmPrimarySelected) and (TopLevel[0] <> nil) then
      Center := GetTransformWorkingPos(TopLevel[0])
    else
      Center := SelectionWorkingCenter;
    if MajorRadius > 1e-4 then
      ActualR := MajorRadius
    else
    begin
      AutoR := 0.0;
      for I := 0 to N - 1 do
      begin
        CurPos := GetTransformWorkingPos(TopLevel[I]);
        AutoR := AutoR + Hypot(CurPos.X - Center.X, CurPos.Z - Center.Z);
      end;
      AutoR := AutoR / N;
      if AutoR < 1e-4 then
        AutoR := 8.0;
      ActualR := AutoR;
    end;

    ActualA := Max(0.05, Abs(LobeRadius));
    if Abs(Turns) < 1e-4 then
      ActualW := 1.0
    else
      ActualW := Turns;

    for I := 0 to N - 1 do
    begin
      T := TopLevel[I];
      CurPos := GetTransformWorkingPos(T);
      UParam := (2.0 * Pi * I) / N;
      VParam := (2.0 * Pi * ActualW * I) / N;
      HalfU := 0.5 * UParam;
      SinCos(HalfU, SinHalfU, CosHalfU);
      SinCos(VParam, SinV, CosV);
      SinCos(2.0 * VParam, Sin2V, Cos2V);

      Rho := ActualR + ActualA * (CosHalfU * SinV - SinHalfU * Sin2V);
      NewPos.X := Center.X + Rho * Cos(UParam);
      NewPos.Y := Center.Y + ActualA * (SinHalfU * SinV + CosHalfU * Sin2V);
      NewPos.Z := Center.Z + Rho * Sin(UParam);

      if not TVector3.Equals(CurPos, NewPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, NewPos);
        Result := true;
      end;

      if (OrientMode in [1, 2]) and T.HasWorldTransform then
      begin
        if OrientMode = 1 then
        begin
          DRhoDU := ActualA * (
            (-0.5 * SinHalfU * SinV + CosHalfU * ActualW * CosV) -
            (0.5 * CosHalfU * Sin2V + SinHalfU * 2.0 * ActualW * Cos2V));
          DX := DRhoDU * Cos(UParam) - Rho * Sin(UParam);
          DY := ActualA * (
            (0.5 * CosHalfU * SinV + SinHalfU * ActualW * CosV) +
            (-0.5 * SinHalfU * Sin2V + CosHalfU * 2.0 * ActualW * Cos2V));
          DZ := DRhoDU * Sin(UParam) + Rho * Cos(UParam);
          LookDir := Vector3(DX, DY, DZ);
        end else
        begin
          LookDir := Vector3(NewPos.X - Center.X, 0.0, NewPos.Z - Center.Z);
        end;

        if LookDir.LengthSqr < 1e-8 then
          LookDir := Vector3(Cos(UParam), 0.0, Sin(UParam));
        LookDir := LookDir.Normalize;

        NewUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(LookDir, NewUp)) > 0.99 then
          NewUp := Vector3(1, 0, 0);
        Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInFermatSpiral(
  const OuterRadius: Single;
  const Turns: Single;
  const VerticalRise: Single;
  const DualArmPinwheel: Boolean;
  const OrientMode: Integer): Boolean;
var
  TopLevel: TCastleTransformList;
  I, N, ArmIdx, ArmCount: Integer;
  T: TCastleTransform;
  Center, CurPos, NewPos, CurWorldPos, CurDir, CurUp, LookDir, NewUp, Side: TVector3;
  AutoR, ActualR, ActualW, UParam, RVal, Theta, PhiOffset, SinT, CosT, DRDU, DThetaDU, DX, DY, DZ: Single;
begin
  Result := false;
  if SelectedCount < 2 then
    Exit;

  TopLevel := TCastleTransformList.Create(false);
  try
    for I := 0 to SelectedCount - 1 do
    begin
      T := Selected[I];
      if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
        TopLevel.Add(T);
    end;

    N := TopLevel.Count;
    if N < 2 then
      Exit;

    if (FPivotMode = pmPrimarySelected) and (TopLevel[0] <> nil) then
      Center := GetTransformWorkingPos(TopLevel[0])
    else
      Center := SelectionWorkingCenter;
    if OuterRadius > 1e-4 then
      ActualR := OuterRadius
    else
    begin
      AutoR := 0.0;
      for I := 0 to N - 1 do
      begin
        CurPos := GetTransformWorkingPos(TopLevel[I]);
        AutoR := Max(AutoR, Hypot(CurPos.X - Center.X, CurPos.Z - Center.Z));
      end;
      if AutoR < 1e-4 then
        AutoR := 10.0;
      ActualR := AutoR;
    end;

    if Abs(Turns) < 1e-4 then
      ActualW := 1.0
    else
      ActualW := Turns;

    for I := 0 to N - 1 do
    begin
      T := TopLevel[I];
      CurPos := GetTransformWorkingPos(T);

      if DualArmPinwheel then
      begin
        ArmIdx := I div 2;
        ArmCount := (N + 1 - (I mod 2)) div 2;
        if ArmCount <= 1 then
          UParam := 1.0
        else
          UParam := (ArmIdx + 1) / ArmCount;
        if (I mod 2) = 1 then
          PhiOffset := Pi
        else
          PhiOffset := 0.0;
      end else
      begin
        UParam := I / (N - 1);
        PhiOffset := 0.0;
      end;

      RVal := ActualR * Sqrt(Max(0.0, UParam));
      Theta := 2.0 * Pi * ActualW * UParam + PhiOffset;
      SinCos(Theta, SinT, CosT);

      NewPos.X := Center.X + RVal * CosT;
      NewPos.Y := Center.Y + VerticalRise * (UParam - 0.5);
      NewPos.Z := Center.Z + RVal * SinT;

      if not TVector3.Equals(CurPos, NewPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, NewPos);
        Result := true;
      end;

      if (OrientMode in [1, 2]) and T.HasWorldTransform then
      begin
        if OrientMode = 1 then
        begin
          if UParam < 1e-4 then
          begin
            DX := Cos(PhiOffset);
            DY := 0.0;
            DZ := Sin(PhiOffset);
          end else
          begin
            DRDU := ActualR / (2.0 * Sqrt(UParam));
            DThetaDU := 2.0 * Pi * ActualW;
            DX := DRDU * CosT - RVal * SinT * DThetaDU;
            DY := VerticalRise;
            DZ := DRDU * SinT + RVal * CosT * DThetaDU;
          end;
          LookDir := Vector3(DX, DY, DZ);
        end else
        begin
          LookDir := Vector3(CosT, 0.0, SinT);
        end;

        if LookDir.LengthSqr < 1e-8 then
          LookDir := Vector3(CosT, 0.0, SinT);
        LookDir := LookDir.Normalize;

        NewUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(LookDir, NewUp)) > 0.99 then
          NewUp := Vector3(1, 0, 0);
        Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
end;

function TCastleTransformManipulate.OctahedralDeformSelected(
  const Radius: Single;
  const ExponentP: Single;
  const Strength: Single;
  const OrientNormals: Boolean): Boolean;
var
  TopLevel: TCastleTransformList;
  I, N, ValidCount: Integer;
  T: TCastleTransform;
  Center, CurPos, Rel, TargetPos, NewPos, Grad, LookDir, NewUp, Side, CurWorldPos, CurDir, CurUp: TVector3;
  PExp, ActualStrength, ActualR, SumNorm, LpNorm: Single;

  function SignedPowPMinus1(const V: Single): Single;
  begin
    if Abs(V) < 1e-5 then
      Result := 0.0
    else if V > 0.0 then
      Result := Power(V, PExp - 1.0)
    else
      Result := -Power(-V, PExp - 1.0);
  end;

begin
  Result := false;
  if SelectedCount < 2 then
    Exit;

  PExp := Clamped(ExponentP, 0.25, 16.0);
  ActualStrength := Clamped(Strength, 0.0, 1.0);
  if (ActualStrength < 1e-6) and (not OrientNormals) then
    Exit;

  TopLevel := TCastleTransformList.Create(false);
  try
    for I := 0 to SelectedCount - 1 do
    begin
      T := Selected[I];
      if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
        TopLevel.Add(T);
    end;

    N := TopLevel.Count;
    if N < 2 then
      Exit;

    if (FPivotMode = pmPrimarySelected) and (TopLevel[0] <> nil) then
      Center := GetTransformWorkingPos(TopLevel[0])
    else
      Center := SelectionWorkingCenter;

    if Radius > 1e-4 then
      ActualR := Radius
    else
    begin
      SumNorm := 0.0;
      ValidCount := 0;
      for I := 0 to N - 1 do
      begin
        Rel := GetTransformWorkingPos(TopLevel[I]) - Center;
        LpNorm := Power(
          Power(Abs(Rel.X), PExp) +
          Power(Abs(Rel.Y), PExp) +
          Power(Abs(Rel.Z), PExp), 1.0 / PExp);
        if LpNorm > 1e-4 then
        begin
          SumNorm := SumNorm + LpNorm;
          Inc(ValidCount);
        end;
      end;
      if ValidCount > 0 then
        ActualR := SumNorm / ValidCount
      else
        ActualR := 10.0;
    end;

    for I := 0 to N - 1 do
    begin
      T := TopLevel[I];
      CurPos := GetTransformWorkingPos(T);
      Rel := CurPos - Center;
      LpNorm := Power(
        Power(Abs(Rel.X), PExp) +
        Power(Abs(Rel.Y), PExp) +
        Power(Abs(Rel.Z), PExp), 1.0 / PExp);

      if LpNorm > 1e-5 then
      begin
        TargetPos := Center + Rel * (ActualR / LpNorm);
        NewPos := Lerp(ActualStrength, CurPos, TargetPos);
        if not TVector3.Equals(CurPos, NewPos, 1e-5) then
        begin
          SetTransformWorkingPos(T, NewPos);
          Result := true;
        end;

        if OrientNormals and T.HasWorldTransform then
        begin
          Grad := Vector3(
            SignedPowPMinus1(Rel.X),
            SignedPowPMinus1(Rel.Y),
            SignedPowPMinus1(Rel.Z));
          if Grad.LengthSqr < 1e-8 then
            LookDir := Rel.Normalize
          else
            LookDir := Grad.Normalize;

          NewUp := Vector3(0, 1, 0);
          if Abs(TVector3.DotProduct(LookDir, NewUp)) > 0.99 then
            NewUp := Vector3(1, 0, 0);
          Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
          NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

          T.GetWorldView(CurWorldPos, CurDir, CurUp);
          if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
             (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
          begin
            T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedOnDiniSurface(
  const RadiusA: Single;
  const PitchB: Single;
  const Turns: Single;
  const OrientMode: Integer): Boolean;
var
  TopLevel: TCastleTransformList;
  I, N: Integer;
  T: TCastleTransform;
  Center, CurPos, NewPos, LookDir, NewUp, Side, CurWorldPos, CurDir, CurUp: TVector3;
  AutoA, ActualA, ActualW, TParam, UParam, VParam, SinU, CosU, SinV, CosV, TanHalfV: Single;
  DUDT, DVDT, DX, DY, DZ: Single;
begin
  Result := false;
  if SelectedCount < 2 then
    Exit;

  TopLevel := TCastleTransformList.Create(false);
  try
    for I := 0 to SelectedCount - 1 do
    begin
      T := Selected[I];
      if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
        TopLevel.Add(T);
    end;

    N := TopLevel.Count;
    if N < 2 then
      Exit;

    if (FPivotMode = pmPrimarySelected) and (TopLevel[0] <> nil) then
      Center := GetTransformWorkingPos(TopLevel[0])
    else
      Center := SelectionWorkingCenter;

    if RadiusA > 1e-4 then
      ActualA := RadiusA
    else
    begin
      AutoA := 0.0;
      for I := 0 to N - 1 do
      begin
        CurPos := GetTransformWorkingPos(TopLevel[I]);
        AutoA := Max(AutoA, Hypot(CurPos.X - Center.X, CurPos.Z - Center.Z));
      end;
      if AutoA < 1e-4 then
        AutoA := 8.0;
      ActualA := AutoA;
    end;

    if Abs(Turns) < 1e-4 then
      ActualW := 1.0
    else
      ActualW := Turns;

    DUDT := 2.0 * Pi * ActualW;
    DVDT := Pi / 3.0;

    for I := 0 to N - 1 do
    begin
      T := TopLevel[I];
      CurPos := GetTransformWorkingPos(T);
      TParam := I / (N - 1);
      UParam := DUDT * TParam;
      VParam := (Pi / 6.0) + DVDT * TParam;
      SinCos(UParam, SinU, CosU);
      SinCos(VParam, SinV, CosV);
      TanHalfV := Max(1e-5, Tan(0.5 * VParam));

      NewPos.X := Center.X + ActualA * CosU * SinV;
      NewPos.Z := Center.Z + ActualA * SinU * SinV;
      NewPos.Y := Center.Y + ActualA * (CosV + Ln(TanHalfV)) + PitchB * UParam;

      if not TVector3.Equals(CurPos, NewPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, NewPos);
        Result := true;
      end;

      if (OrientMode in [1, 2]) and T.HasWorldTransform then
      begin
        if OrientMode = 1 then
        begin
          DX := ActualA * (-SinU * DUDT * SinV + CosU * CosV * DVDT);
          DZ := ActualA * (CosU * DUDT * SinV + SinU * CosV * DVDT);
          DY := ActualA * (-SinV + (1.0 / Max(1e-4, SinV))) * DVDT + PitchB * DUDT;
          LookDir := Vector3(DX, DY, DZ);
        end else
        begin
          LookDir := Vector3(CosU, 0.0, SinU);
        end;

        if LookDir.LengthSqr < 1e-8 then
          LookDir := Vector3(CosU, 0.0, SinU);
        LookDir := LookDir.Normalize;

        NewUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(LookDir, NewUp)) > 0.99 then
          NewUp := Vector3(1, 0, 0);
        Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInCornuSpiral(
  const ScaleLength: Single;
  const MaxParamT: Single;
  const HeightSpan: Single;
  const OrientMode: Integer): Boolean;

  procedure EvalFresnel(const SVal: Single; out FresnelC, FresnelS: Single);
  const
    Steps = 64;
  var
    K: Integer;
    HStep, Tau, Angle, Weight, SumC, SumS: Double;
  begin
    if Abs(SVal) < 1e-7 then
    begin
      FresnelC := 0.0;
      FresnelS := 0.0;
      Exit;
    end;
    HStep := SVal / Steps;
    SumC := 0.0;
    SumS := 0.0;
    for K := 0 to Steps do
    begin
      Tau := K * HStep;
      Angle := 0.5 * Pi * Sqr(Tau);
      if (K = 0) or (K = Steps) then
        Weight := 1.0
      else if (K mod 2) = 1 then
        Weight := 4.0
      else
        Weight := 2.0;
      SumC := SumC + Weight * Cos(Angle);
      SumS := SumS + Weight * Sin(Angle);
    end;
    FresnelC := (HStep / 3.0) * SumC;
    FresnelS := (HStep / 3.0) * SumS;
  end;

var
  TopLevel: TCastleTransformList;
  I, N: Integer;
  T: TCastleTransform;
  Center, CurPos, NewPos, LookDir, NewUp, Side, CurWorldPos, CurDir, CurUp: TVector3;
  AutoL, ActualL, ActualTMax, UParam, SVal, FC, FS, Phase, SinP, CosP: Single;
begin
  Result := false;
  if SelectedCount < 2 then
    Exit;

  TopLevel := TCastleTransformList.Create(false);
  try
    for I := 0 to SelectedCount - 1 do
    begin
      T := Selected[I];
      if (T <> nil) and (not IsDescendantOfAnySelected(T)) then
        TopLevel.Add(T);
    end;

    N := TopLevel.Count;
    if N < 2 then
      Exit;

    if (FPivotMode = pmPrimarySelected) and (TopLevel[0] <> nil) then
      Center := GetTransformWorkingPos(TopLevel[0])
    else
      Center := SelectionWorkingCenter;

    ActualTMax := Clamped(Abs(MaxParamT), 0.2, 3.5);
    if ScaleLength > 1e-4 then
      ActualL := ScaleLength
    else
    begin
      AutoL := 0.0;
      for I := 0 to N - 1 do
      begin
        CurPos := GetTransformWorkingPos(TopLevel[I]);
        AutoL := Max(AutoL, Hypot(CurPos.X - Center.X, CurPos.Z - Center.Z));
      end;
      if AutoL < 1e-4 then
        AutoL := 10.0;
      ActualL := AutoL;
    end;

    for I := 0 to N - 1 do
    begin
      T := TopLevel[I];
      CurPos := GetTransformWorkingPos(T);
      UParam := I / (N - 1);
      SVal := ActualTMax * (2.0 * UParam - 1.0);
      EvalFresnel(SVal, FC, FS);

      NewPos.X := Center.X + ActualL * FC;
      NewPos.Y := Center.Y + HeightSpan * (UParam - 0.5);
      NewPos.Z := Center.Z + ActualL * FS;

      if not TVector3.Equals(CurPos, NewPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, NewPos);
        Result := true;
      end;

      if (OrientMode in [1, 2]) and T.HasWorldTransform then
      begin
        Phase := 0.5 * Pi * Sqr(SVal);
        SinCos(Phase, SinP, CosP);
        if OrientMode = 1 then
          LookDir := Vector3(ActualL * CosP, HeightSpan / (2.0 * ActualTMax), ActualL * SinP)
        else
          LookDir := Vector3(-SinP, 0.0, CosP);

        if LookDir.LengthSqr < 1e-8 then
          LookDir := Vector3(1.0, 0.0, 0.0);
        LookDir := LookDir.Normalize;

        NewUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(LookDir, NewUp)) > 0.99 then
          NewUp := Vector3(1, 0, 0);
        Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
end;

function TCastleTransformManipulate.GyroidDeformSelected(
  const Wavelength, Amplitude: Single;
  const SchwarzPMode, OrientNormals: Boolean): Boolean;
var
  TopLevel: TComponentList;
  I, N: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, RelVec, TargetPos, GradVec, UnitGrad, CurWorldPos, CurDir, CurUp, NewUp, Side: TVector3;
  ActualLambda, WaveK, KX, KY, KZ, SinX, CosX, SinY, CosY, SinZ, CosZ, FieldVal, TotalSpan, Dist: Single;
begin
  Result := false;
  TopLevel := TComponentList.Create(false);
  try
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
      if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
        TopLevel.Add(Boxes[I].Parent);

    N := TopLevel.Count;
    if N < 2 then Exit;

    if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
      CenterPos := GetTransformWorkingPos(FMainSelected)
    else
      CenterPos := SelectionWorkingCenter;

    ActualLambda := Wavelength;
    if ActualLambda <= 0.0 then
    begin
      TotalSpan := 0.0;
      for I := 0 to N - 1 do
      begin
        Dist := (GetTransformWorkingPos(TCastleTransform(TopLevel[I])) - CenterPos).Length;
        TotalSpan := Max(TotalSpan, Dist * 2.0);
      end;
      ActualLambda := Max(4.0, TotalSpan);
    end;
    ActualLambda := Max(0.25, ActualLambda);
    WaveK := (2.0 * Pi) / ActualLambda;

    for I := 0 to N - 1 do
    begin
      T := TCastleTransform(TopLevel[I]);
      CurPos := GetTransformWorkingPos(T);
      RelVec := CurPos - CenterPos;

      KX := WaveK * RelVec.X;
      KY := WaveK * RelVec.Y;
      KZ := WaveK * RelVec.Z;
      SinCos(KX, SinX, CosX);
      SinCos(KY, SinY, CosY);
      SinCos(KZ, SinZ, CosZ);

      if SchwarzPMode then
      begin
        FieldVal := CosX + CosY + CosZ;
        GradVec := Vector3(-WaveK * SinX, -WaveK * SinY, -WaveK * SinZ);
      end else
      begin
        FieldVal := SinX * CosY + SinY * CosZ + SinZ * CosX;
        GradVec := Vector3(
          WaveK * (CosX * CosY - SinZ * SinX),
          WaveK * (-SinX * SinY + CosY * CosZ),
          WaveK * (-SinY * SinZ + CosZ * CosX));
      end;

      if GradVec.LengthSqr > 1e-8 then
        UnitGrad := GradVec.Normalize
      else
        UnitGrad := Vector3(0.0, 1.0, 0.0);

      TargetPos := CurPos + UnitGrad * (Amplitude * FieldVal);
      if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, TargetPos);
        Result := true;
      end;

      if OrientNormals then
      begin
        NewUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(UnitGrad, NewUp)) > 0.99 then
          NewUp := Vector3(1, 0, 0);
        Side := TVector3.CrossProduct(UnitGrad, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, UnitGrad).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, UnitGrad, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), UnitGrad, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedOnRomanSurface(
  const Radius: Single;
  const Turns: Single;
  const OrientMode: Integer): Boolean;
var
  TopLevel: TComponentList;
  I, N: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, LookDir, CurWorldPos, CurDir, CurUp, NewUp, Side: TVector3;
  ActualR, ActualTurns, TParam, UVal, VVal, SinU, CosU, Sin2U, Cos2U, SinV, CosV, Sin2V, Cos2V: Single;
  DuDt, DvDt, DxDt, DyDt, DzDt, TotalDist, Dist: Single;
begin
  Result := false;
  TopLevel := TComponentList.Create(false);
  try
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
      if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
        TopLevel.Add(Boxes[I].Parent);

    N := TopLevel.Count;
    if N < 2 then Exit;

    if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
      CenterPos := GetTransformWorkingPos(FMainSelected)
    else
      CenterPos := SelectionWorkingCenter;

    ActualR := Radius;
    if ActualR <= 0.0 then
    begin
      TotalDist := 0.0;
      for I := 0 to N - 1 do
      begin
        Dist := (GetTransformWorkingPos(TCastleTransform(TopLevel[I])) - CenterPos).Length;
        TotalDist := TotalDist + Dist;
      end;
      ActualR := Max(4.0, (TotalDist / N) * 2.0);
    end;
    ActualR := Max(0.1, ActualR);

    ActualTurns := Turns;
    if Abs(ActualTurns) < 0.05 then
      ActualTurns := 2.0;

    DuDt := Pi * ActualTurns;
    DvDt := Pi * 0.5;

    for I := 0 to N - 1 do
    begin
      T := TCastleTransform(TopLevel[I]);
      CurPos := GetTransformWorkingPos(T);
      TParam := I / (N - 1);
      UVal := DuDt * TParam;
      VVal := (-Pi * 0.25) + DvDt * TParam;

      SinCos(UVal, SinU, CosU);
      SinCos(2.0 * UVal, Sin2U, Cos2U);
      SinCos(VVal, SinV, CosV);
      SinCos(2.0 * VVal, Sin2V, Cos2V);

      TargetPos := Vector3(
        CenterPos.X + 0.5 * ActualR * Sin2U * Sqr(CosV),
        CenterPos.Y + 0.5 * ActualR * SinU * Sin2V,
        CenterPos.Z + 0.5 * ActualR * CosU * Sin2V);

      if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, TargetPos);
        Result := true;
      end;

      if OrientMode in [1, 2] then
      begin
        if OrientMode = 1 then
        begin
          DxDt := 0.5 * ActualR * (2.0 * DuDt * Cos2U * Sqr(CosV) - DvDt * Sin2U * Sin2V);
          DyDt := 0.5 * ActualR * (DuDt * CosU * Sin2V + 2.0 * DvDt * SinU * Cos2V);
          DzDt := 0.5 * ActualR * (-DuDt * SinU * Sin2V + 2.0 * DvDt * CosU * Cos2V);
          LookDir := Vector3(DxDt, DyDt, DzDt);
        end else
          LookDir := TargetPos - CenterPos;

        if LookDir.LengthSqr < 1e-8 then
          LookDir := Vector3(0.0, 0.0, 1.0);
        LookDir := LookDir.Normalize;

        NewUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(LookDir, NewUp)) > 0.99 then
          NewUp := Vector3(1, 0, 0);
        Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
end;

function TCastleTransformManipulate.ArrangeSelectedInCochleoid(
  const ScaleRadius, MaxAngleTurns, HeightSpan: Single;
  const SymmetricDualLobe: Boolean;
  const OrientMode: Integer): Boolean;
var
  TopLevel: TComponentList;
  I, N: Integer;
  T: TCastleTransform;
  CenterPos, CurPos, TargetPos, LookDir, CurWorldPos, CurDir, CurUp, NewUp, Side: TVector3;
  ActualA, ActualTurns, ThetaMax, TParam, Theta, SinT, CosT, RVal, DrDTheta, DThetaDt, DxDt, DyDt, DzDt, TotalDist, Dist: Single;
begin
  Result := false;
  TopLevel := TComponentList.Create(false);
  try
    for I := 0 to Integer(FMaxSelectedCount) - 1 do
      if (Boxes[I].Parent <> nil) and (not IsDescendantOfAnySelected(Boxes[I].Parent)) then
        TopLevel.Add(Boxes[I].Parent);

    N := TopLevel.Count;
    if N < 2 then Exit;

    if (FPivotMode = pmPrimarySelected) and (FMainSelected <> nil) then
      CenterPos := GetTransformWorkingPos(FMainSelected)
    else
      CenterPos := SelectionWorkingCenter;

    ActualA := ScaleRadius;
    if ActualA <= 0.0 then
    begin
      TotalDist := 0.0;
      for I := 0 to N - 1 do
      begin
        Dist := Hypot(
          GetTransformWorkingPos(TCastleTransform(TopLevel[I])).X - CenterPos.X,
          GetTransformWorkingPos(TCastleTransform(TopLevel[I])).Z - CenterPos.Z);
        TotalDist := TotalDist + Dist;
      end;
      ActualA := Max(5.0, (TotalDist / N) * 1.5);
    end;
    ActualA := Max(0.1, ActualA);

    ActualTurns := MaxAngleTurns;
    if Abs(ActualTurns) < 0.05 then
      ActualTurns := 2.0;
    ThetaMax := Pi * ActualTurns;

    if SymmetricDualLobe then
      DThetaDt := 2.0 * ThetaMax
    else
      DThetaDt := ThetaMax;

    for I := 0 to N - 1 do
    begin
      T := TCastleTransform(TopLevel[I]);
      CurPos := GetTransformWorkingPos(T);
      TParam := I / (N - 1);
      if SymmetricDualLobe then
        Theta := ThetaMax * (2.0 * TParam - 1.0)
      else
        Theta := ThetaMax * TParam;

      SinCos(Theta, SinT, CosT);
      if Abs(Theta) < 1e-5 then
      begin
        RVal := ActualA;
        DrDTheta := 0.0;
      end else
      begin
        RVal := ActualA * (SinT / Theta);
        DrDTheta := ActualA * ((Theta * CosT - SinT) / Sqr(Theta));
      end;

      TargetPos := Vector3(
        CenterPos.X + RVal * CosT,
        CenterPos.Y + HeightSpan * (TParam - 0.5),
        CenterPos.Z + RVal * SinT);

      if not TVector3.Equals(CurPos, TargetPos, 1e-5) then
      begin
        SetTransformWorkingPos(T, TargetPos);
        Result := true;
      end;

      if OrientMode in [1, 2] then
      begin
        if OrientMode = 1 then
        begin
          DxDt := (DrDTheta * CosT - RVal * SinT) * DThetaDt;
          DyDt := HeightSpan;
          DzDt := (DrDTheta * SinT + RVal * CosT) * DThetaDt;
          LookDir := Vector3(DxDt, DyDt, DzDt);
        end else
        begin
          LookDir := Vector3(TargetPos.X - CenterPos.X, 0.0, TargetPos.Z - CenterPos.Z);
          if LookDir.LengthSqr < 1e-8 then
            LookDir := Vector3(CosT, 0.0, SinT);
        end;

        if LookDir.LengthSqr < 1e-8 then
          LookDir := Vector3(0.0, 0.0, 1.0);
        LookDir := LookDir.Normalize;

        NewUp := Vector3(0, 1, 0);
        if Abs(TVector3.DotProduct(LookDir, NewUp)) > 0.99 then
          NewUp := Vector3(1, 0, 0);
        Side := TVector3.CrossProduct(LookDir, NewUp).Normalize;
        NewUp := TVector3.CrossProduct(Side, LookDir).Normalize;

        T.GetWorldView(CurWorldPos, CurDir, CurUp);
        if (not TVector3.Equals(CurDir, LookDir, 1e-4)) or
           (not TVector3.Equals(CurUp, NewUp, 1e-4)) then
        begin
          T.SetWorldView(GetTransformWorkingPos(T), LookDir, NewUp);
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
  finally
    FreeAndNil(TopLevel);
  end;
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
