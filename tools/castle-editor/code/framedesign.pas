{
  Copyright 2018-2024 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Frame where you can design
  a xxx.castle-user-interface, xxx.castle-transform, xxx.castle-component file. }
unit FrameDesign;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, ExtCtrls, StdCtrls, ComCtrls,
  Spin, Buttons, Menus, ActnList, Contnrs, Generics.Collections,
  // for icons
  DataModuleIcons, ImgList,
  // for TOIPropertyGrid usage
  ObjectInspector, PropEdits, PropEditUtils, GraphPropEdits,
  CollectionPropEditForm, ComponentEditors,
  // CGE units
  CastleControl, CastleUIControls, CastlePropEdits, CastleDialogs,
  CastleSceneCore, CastleKeysMouse, CastleVectors, CastleRectangles,
  CastleViewport, CastleClassUtils, CastleControls, CastleTiledMap,
  CastleCameras, CastleBoxes, CastleTransform, CastleDebugTransform,
  CastleColors, CastleScene, CastleRenderOptions, CastleEditorPropEdits,
  CastleUtils,
  // editor units
  FrameAnchors, CastleShellCtrls, EditorUtils,
  CastleTransformManipulate, DesignUndoSystem, DesignCameraPreview,
  DesignObjectInspector;

type
  TProposeOpenDesignEvent = procedure (const DesignUrl: String) of object;

  TBooleanEvent = function: Boolean of object;

  TMode = (
    moInteract,
    moSelect,
    moTranslate,
    moRotate,
    moScale
  );

  { Frame to visually design component hierarchy. }
  TDesignFrame = class(TFrame)
    ActionApiReferenceOfCurrent: TAction;
    ActionPlayStop: TAction;
    ActionSimulationPauseUnpause: TAction;
    ActionSimulationPlayStop: TAction;
    ActionListDesign: TActionList;
    ButtonResetTransformation: TButton;
    ButtonClearTranslation: TButton;
    ButtonPlayStop: TSpeedButton;
    ButtonApiReferenceForCurrent: TSpeedButton;
    EditFindInHierarchy: TEdit;
    LabelPhysics: TLabel;
    LabelPlayStop: TLabel;
    LabelViewport: TLabel;
    LabelHeaderUi: TLabel;
    LabelEventsInfo: TLabel;
    LabelSimulation: TLabel;
    LabelSizeInfo: TLabel;
    MemoInfo: TMemo;
    MenuTreeViewItemDuplicateLinked: TMenuItem;
    PanelSpinEditAllowVerticalCentering: TPanel;
    ExportToModelDialog: TCastleSaveDialog;
    SeparatorBeforeChangeClass: TMenuItem;
    MenuItemChangeClassUserInterface: TMenuItem;
    MenuItemChangeClassNonVisual: TMenuItem;
    MenuItemChangeClassTransform: TMenuItem;
    MenuItemChangeClassBehavior: TMenuItem;
    MenuTreeViewItemSaveSelected: TMenuItem;
    MenuSeparator1: TMenuItem;
    MenuTreeViewItemCut: TMenuItem;
    MenuItemSeparator898989: TMenuItem;
    MenuTreeViewItemSeparator127u30130120983: TMenuItem;
    MenuTreeViewItemAddNonVisual: TMenuItem;
    MenuTreeViewItemAddBehavior: TMenuItem;
    MenuTreeViewItemRename: TMenuItem;
    MenuTreeViewItemAddTransform: TMenuItem;
    MenuTreeViewItemAddUserInterface: TMenuItem;
    MenuTreeViewItemDelete: TMenuItem;
    MenuTreeViewItemPaste: TMenuItem;
    MenuTreeViewItemCopy: TMenuItem;
    MenuTreeViewItemDuplicate: TMenuItem;
    MenuItemSeparator1: TMenuItem;
    PanelLayoutTop: TPanel;
    PanelLayoutTransform: TPanel;
    PanelEventsInfo: TPanel;
    PanelAnchors: TPanel;
    MenuTreeView: TPopupMenu;
    SaveDesignDialog: TCastleSaveDialog;
    SelfAnchorsFrame: TAnchorsFrame;
    ParentAnchorsFrame: TAnchorsFrame;
    CheckParentSelfAnchorsEqual: TCheckBox;
    ControlProperties: TPageControl;
    ControlsTree: TTreeView;
    LabelControlSelected: TLabel;
    LabelHierarchy: TLabel;
    PanelMiddleTop: TPanel;
    PanelMiddle: TPanel;
    PanelLeft: TPanel;
    PanelRight: TPanel;
    ButtonInteractMode: TSpeedButton;
    ButtonSimulationPlayStop: TSpeedButton;
    ButtonSimulationPause: TSpeedButton;
    ButtonSelectMode: TSpeedButton;
    ButtonTranslateMode: TSpeedButton;
    ButtonRotateMode: TSpeedButton;
    ButtonScaleMode: TSpeedButton;
    SpinEditSnap: TSpinEdit;
    Splitter1: TSplitter;
    TabLayoutScrollBox: TScrollBox;
    SplitterLeft: TSplitter;
    SplitterRight: TSplitter;
    TabAll: TTabSheet;
    TabEvents: TTabSheet;
    TabLayout: TTabSheet;
    TabBasic: TTabSheet;
    TabInfo: TTabSheet;
    UpdateObjectInspector: TTimer;
    procedure ActionApiReferenceOfCurrentExecute(Sender: TObject);
    procedure ActionPlayStopExecute(Sender: TObject);
    procedure ActionPlayStopUpdate(Sender: TObject);
    procedure ActionSimulationPauseUnpauseExecute(Sender: TObject);
    procedure ActionSimulationPauseUnpauseUpdate(Sender: TObject);
    procedure ActionSimulationPlayStopExecute(Sender: TObject);
    procedure ActionSimulationPlayStopUpdate(Sender: TObject);
    procedure ButtonClearTranslationClick(Sender: TObject);
    procedure ButtonResetTransformationClick(Sender: TObject);
    procedure ButtonRotateModeClick(Sender: TObject);
    procedure ButtonScaleModeClick(Sender: TObject);
    procedure ButtonSelectModeClick(Sender: TObject);
    procedure ButtonTranslateModeClick(Sender: TObject);
    procedure CheckParentSelfAnchorsEqualChange(Sender: TObject);
    procedure ControlsTreeAdvancedCustomDrawItem(Sender: TCustomTreeView;
      Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage;
      var PaintImages, DefaultDraw: Boolean);
    procedure ControlsTreeDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure ControlsTreeDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure ControlsTreeEditing(Sender: TObject; Node: TTreeNode;
      var AllowEdit: Boolean);
    procedure ControlsTreeEditingEnd(Sender: TObject; Node: TTreeNode;
      Cancel: Boolean);
    procedure ControlsTreeEndDrag(Sender, Target: TObject; X, Y: Integer);
    procedure ControlsTreeSelectionChanged(Sender: TObject);
    procedure ButtonInteractModeClick(Sender: TObject);
    procedure EditFindInHierarchyChange(Sender: TObject);
    procedure FrameResize(Sender: TObject);
    procedure MenuItemAddComponentClick(Sender: TObject);
    procedure MenuTreeViewItemCutClick(Sender: TObject);
    procedure MenuTreeViewItemDuplicateLinkedClick(Sender: TObject);
    procedure MenuTreeViewItemRenameClick(Sender: TObject);
    procedure MenuTreeViewItemDeleteClick(Sender: TObject);
    procedure MenuTreeViewItemCopyClick(Sender: TObject);
    procedure MenuTreeViewItemDuplicateClick(Sender: TObject);
    procedure MenuTreeViewItemPasteClick(Sender: TObject);
    procedure MenuTreeViewItemSaveSelectedClick(Sender: TObject);
    procedure MenuTreeViewPopup(Sender: TObject);
    procedure ClearDesign;
    procedure RenameSelectedItem;
    procedure PerformUndoRedo(const UHE: TUndoHistoryElement);
    procedure PerformRedo;
    procedure PerformUndo;
    procedure UpdateObjectInspectorTimer(Sender: TObject);
  protected
    procedure SetParent(AParent: TWinControl); override;
  private
    type
      { UI layer that can intercept mouse clicks and drags. }
      TDesignerLayer = class(TCastleUserInterface)
      strict private
        type
          TUiDraggingMode = (dmNone, dmTranslate, dmResize, dmMarquee);
        var
          UiPendingMove: TVector2;
          UiDraggingMode: TUiDraggingMode;
          ResizingHorizontal: THorizontalPosition; //< Defined only when UiDraggingMode=dmResize
          ResizingVertical: TVerticalPosition; //< Defined only when UiDraggingMode=dmResize
          MarqueeStartPos, MarqueeCurrentPos: TVector2;
          MarqueeActive: Boolean;
          LabelHover, LabelSelected, LabelStatistics: TCastleLabel;
          RectHover, RectSelected, RectStatistics: TCastleRectangleControl;
        { Should clicking inside UI rectangle start resizing (not only moving?). }
        function IsResizing(const UI: TCastleUserInterface; const Position: TVector2;
          out Horizontal: THorizontalPosition;
          out Vertical: TVerticalPosition; out Hint: String): Boolean;
        function IsResizing(const UI: TCastleUserInterface; const Position: TVector2;
          out Horizontal: THorizontalPosition;
          out Vertical: TVerticalPosition): Boolean;
        procedure SelectComponentsInMarquee(const MarqueeRect: TFloatRectangle;
          const Additive: Boolean);
      public
        Frame: TDesignFrame;
        LayerPhysicsSimulation: TCastleUserInterface;
        LabelPhysicsSimulationRunning: TCastleLabel;
        LabelPhysicsSimulationPaused: TCastleLabel;
        OnGLContextOpen: TNotifyEvent;
        constructor Create(AOwner: TComponent); override;
        procedure GLContextOpen; override;
        function Press(const Event: TInputPressRelease): Boolean; override;
        function Release(const Event: TInputPressRelease): Boolean; override;
        function Motion(const Event: TInputMotion): Boolean; override;
        procedure Render; override;

        { UI under given mouse position.
          AMousePosition is in coordinates local to TCastleControl and follows
          CGE conventions that Y goes from bottom to top.

          Note: In most cases, prefer to call HoverComponent.
          HoverUserInterface *does not* consider transforms within TCastleViewport,
          it will just return TCastleViewport if mouse is over it.

          @param(EnterNestedDesigns If @true, we enter children loaded by TCastleDesign,
            in TCastleDesign.Design. This should almost never be used: such children
            are not selectable, their names may collide with names in main design etc.) }
        function HoverUserInterface(const AMousePosition: TVector2;
          const EnterNestedDesigns: Boolean = false): TCastleUserInterface;

        { UI or transform under given mouse position.
          AMousePosition is like for HoverUserInterface. }
        function HoverComponent(const AMousePosition: TVector2): TCastleComponent;
      end;

      TTreeNodeMap = class(specialize TDictionary<TComponent, TTreeNode>)
      end;

      TTreeNodeSide = (tnsInside, tnsBottom, tnsTop);

      TInspectorType = (itBasic, itLayout, itEvents, itAll);

    var
      Inspector: array [TInspectorType] of TCastleObjectInspector;
      FUndoSystem: TUndoSystem;
      PropertyEditorHook: TCastlePropertyEditorHook;
      FDesignUrl: String;
      FDesignRoot: TComponent;
      { Viewport created for editing design with FDesignRoot being TCastleTransform. }
      FDesignViewportForTransforms: TCastleViewport;
      { Owner of all components saved/loaded to the design file.
        Also owner of a temporary viewport for .castle-transform,
        in general this owns everything specific to display currrent design. }
      DesignOwner: TComponent;
      { If design is visual (DesignRoot is TCastleUserInterface or
        TCastleTransform) then this is non-nil and allows to visualize
        alternative selected camera view. }
      CameraPreview: TCameraPreview;
      FDesignerLayer: TDesignerLayer;
      FDesignModified: Boolean;
      CastleControl: TCastleControl;
      TreeNodeMap: TTreeNodeMap;
      Mode: TMode;
      InsideToggleModeClick: Boolean;
      ControlsTreeNodeUnderMouse: TTreeNode;
      ControlsTreeNodeUnderMouseSide: TTreeNodeSide;
      PendingErrorBox: String;
      TransformHover: TCastleTransformHover;
      TransformManipulate: TCastleTransformManipulate;
      CollectionPropertyEditorForm: TCollectionPropertyEditorForm;
      DesignStateBeforePhysicsRun: String;
      DesignModifiedBeforePhysicsRun: Boolean;
      FCurrentViewport: TCastleViewport;
      FCurrentViewportObserver: TFreeNotificationObserver;
      FComponentEditorDesigner: TComponentEditorDesigner;
      (*
      // The TransformDesigning mechanism works, but it unused for now.
      FTransformDesigning: TCastleTransform;
      FTransformDesigningObserver: TFreeNotificationObserver;
      *)

      // Last selected components (with AutoSelectParents=true)
      LastSelected: TComponentList;
      FShowColliders: Boolean;
      FindActive: Boolean;
      FMaximizePreview: Boolean;
      ButtonCoordSpace: TSpeedButton;
      ButtonPivotMode: TSpeedButton;
      LabelHeader3DSnap: TLabel;
      PanelSpinEditSnap3D: TPanel;
      SpinEditSnap3D: TFloatSpinEdit;
      ButtonSnapToFloor: TButton;
      ButtonSnapToFloorNormal: TButton;
      ButtonSnapToGrid: TButton;
      ButtonMoveTransformToView: TButton;
      ButtonCopyTransform: TButton;
      ButtonPasteTransform: TButton;
      ButtonAlignX: TButton;
      ButtonAlignY: TButton;
      ButtonAlignZ: TButton;
      ButtonDistributeX: TButton;
      ButtonDistributeY: TButton;
      ButtonDistributeZ: TButton;
      ButtonStackX: TButton;
      ButtonStackY: TButton;
      ButtonStackZ: TButton;
      ButtonMirrorX: TButton;
      ButtonMirrorY: TButton;
      ButtonMirrorZ: TButton;
      ButtonRotate90Y: TButton;
      ButtonRandomizeTransform: TButton;
      ButtonArrayDuplicate: TButton;
      ButtonRadialDuplicate: TButton;
      ButtonGridDuplicate: TButton;
      ButtonProjectAlongView: TButton;
      ButtonViewTop: TButton;
      ButtonViewFront: TButton;
      ButtonViewRight: TButton;
      PanelPropertyFilter: TPanel;
      EditPropertyFilter: TEdit;
      ButtonResetProperty: TSpeedButton;
      MenuTreeViewItemToggleVisibility: TMenuItem;
      MenuTreeViewItemIsolateSelected: TMenuItem;
      MenuTreeViewItemShowAllHidden: TMenuItem;
      MenuTreeViewItemToggleLock: TMenuItem;
      MenuTreeViewItemUnlockAll: TMenuItem;
      MenuTreeViewItemGroupSelected: TMenuItem;
      MenuTreeViewItemUngroupSelected: TMenuItem;
      MenuTreeViewItemArrayDuplicate: TMenuItem;
      MenuTreeViewItemRadialDuplicate: TMenuItem;
      MenuTreeViewItemGridDuplicate: TMenuItem;
      MenuTreeViewItemReplaceSelected: TMenuItem;
      MenuTreeViewItemInvertSelection: TMenuItem;
      MenuTreeViewItemSelectChildren: TMenuItem;
      MenuTreeViewItemSelectDescendants: TMenuItem;
      MenuTreeViewItemSelectSameClass: TMenuItem;
      MenuTreeViewItemExpandAll: TMenuItem;
      MenuTreeViewItemCollapseAll: TMenuItem;
      FLockedComponents: TComponentList;
      FAltDragDuplicated: Boolean;
      FMeasureActive: Boolean;
      FMeasureStartWorld: TVector3;
      FMeasureEndWorld: TVector3;
      FMeasureDistance: Single;
      FMeasureDelta: TVector3;
      FQuickAddReplaceMode: Boolean;
      FCameraBookmarks: array [0..9] of record
        Valid: Boolean;
        Pos, Dir, Up: TVector3;
      end;
      FCopiedTransformValid: Boolean;
      FCopiedTranslation: TVector3;
      FCopiedRotation: TVector4;
      FCopiedScale: TVector3;
      FShowStatisticsToolbar: Boolean;
      ButtonViewMode: TSpeedButton;
      ButtonShowStats: TSpeedButton;
      ButtonShowColliders: TSpeedButton;
      ButtonQuickAdd: TSpeedButton;
      ButtonSimulationStep: TSpeedButton;
      ButtonKeepSimulation: TSpeedButton;
      FQuickAddEdit: TEdit;
      FQuickAddList: TListBox;

    procedure ButtonCoordSpaceClick(Sender: TObject);
    procedure ButtonPivotModeClick(Sender: TObject);
    procedure SpinEditSnap3DChange(Sender: TObject);
    procedure ButtonSnapToFloorClick(Sender: TObject);
    procedure ButtonSnapToFloorNormalClick(Sender: TObject);
    procedure ButtonSnapToGridClick(Sender: TObject);
    procedure ButtonMoveTransformToViewClick(Sender: TObject);
    procedure ButtonCopyTransformClick(Sender: TObject);
    procedure ButtonPasteTransformClick(Sender: TObject);
    procedure ButtonAlignAxisClick(Sender: TObject);
    procedure ButtonDistributeAxisClick(Sender: TObject);
    procedure ButtonStackAxisClick(Sender: TObject);
    procedure ButtonMirrorAxisClick(Sender: TObject);
    procedure ButtonRotate90YClick(Sender: TObject);
    procedure ButtonRandomizeTransformClick(Sender: TObject);
    procedure ButtonArrayDuplicateClick(Sender: TObject);
    procedure ButtonRadialDuplicateClick(Sender: TObject);
    procedure ButtonGridDuplicateClick(Sender: TObject);
    procedure ButtonProjectAlongViewClick(Sender: TObject);
    procedure ButtonAxisViewClick(Sender: TObject);
    procedure EditPropertyFilterChange(Sender: TObject);
    procedure ButtonResetPropertyClick(Sender: TObject);
    procedure ControlsTreeDblClick(Sender: TObject);
    procedure ControlsTreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MenuTreeViewItemToggleVisibilityClick(Sender: TObject);
    procedure MenuTreeViewItemIsolateSelectedClick(Sender: TObject);
    procedure MenuTreeViewItemShowAllHiddenClick(Sender: TObject);
    procedure MenuTreeViewItemToggleLockClick(Sender: TObject);
    procedure MenuTreeViewItemUnlockAllClick(Sender: TObject);
    procedure MenuTreeViewItemGroupSelectedClick(Sender: TObject);
    procedure MenuTreeViewItemUngroupSelectedClick(Sender: TObject);
    procedure MenuTreeViewItemArrayDuplicateClick(Sender: TObject);
    procedure MenuTreeViewItemRadialDuplicateClick(Sender: TObject);
    procedure MenuTreeViewItemGridDuplicateClick(Sender: TObject);
    procedure MenuTreeViewItemReplaceSelectedClick(Sender: TObject);
    procedure MenuTreeViewItemInvertSelectionClick(Sender: TObject);
    procedure MenuTreeViewItemSelectChildrenClick(Sender: TObject);
    procedure MenuTreeViewItemSelectDescendantsClick(Sender: TObject);
    procedure MenuTreeViewItemSelectSameClassClick(Sender: TObject);
    procedure MenuTreeViewItemExpandAllClick(Sender: TObject);
    procedure MenuTreeViewItemCollapseAllClick(Sender: TObject);
    function NodeMatchesHierarchyFilter(const C: TComponent): Boolean;
    function IsComponentDescendantOfSelection(const C: TComponent; const List: TComponentList): Boolean;
    procedure ButtonViewModeClick(Sender: TObject);
    procedure ButtonShowStatsClick(Sender: TObject);
    procedure ButtonShowCollidersClick(Sender: TObject);
    procedure ButtonQuickAddClick(Sender: TObject);
    procedure ButtonSimulationStepClick(Sender: TObject);
    procedure ButtonKeepSimulationClick(Sender: TObject);
    procedure QuickAddEditChange(Sender: TObject);
    procedure QuickAddEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure QuickAddListDblClick(Sender: TObject);
    procedure PopulateQuickAddList(const FilterText: String);

    { Create and add to the designed parent a new component,
      whose type best matches currently selected file in SourceShellList.
      May return @nil (and do nothing) if the SourceShellList does not
      have a suitable file selected for the given parent. }
    function ShellListAddComponent(
      const SourceShellList: TCastleShellListView;
      const ParentComponent: TComponent): TComponent;
    { Returns exactly the class that will be returned by
      ShellListAddComponent for the same arguments.
      May return @nil exactly if ShellListAddComponent also returns @nil. }
    function ShellListComponentClass(
      const SourceShellList: TCastleShellListView;
      const ParentComponent: TComponent): TComponentClass;

    (*
    // The TransformDesigning mechanism works, but it unused for now.

    procedure SetTransformDesigning(const Value: TCastleTransform);
    procedure TransformDesigningFreeNotification(const Value: TFreeNotificationObserver);
    { For this transform we display design-time helpers (e.g. to edit joints' anchors),
      using TCastleBehavior.DesigningBegin and TCastleBehavior.DesigningEnd. }
    property TransformDesigning: TCastleTransform
      read FTransformDesigning write SetTransformDesigning;
    *)

    function CameraToSynchronize(const V: TCastleViewport): TCastleCamera;
    procedure CameraSynchronize(const Source, Target: TCastleCamera; const MakeUndo: Boolean);
    procedure CastleControlGLContextOpen(Sender: TObject);
    //procedure CastleControlResize(Sender: TObject);
    procedure CastleControlUpdate(const Sender: TCastleUserInterface;
      const SecondsPassed: Single; var HandleInput: Boolean);
    procedure CastleControlDragOver(Sender, Source: TObject; X, Y: Integer;
      State: TDragState; var Accept: Boolean);
    procedure CastleControlDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure CollectionPropertyEditorFormUnassign;
    function ComponentCaption(const C: TComponent): String;
    function TreeNodeCaption(const C: TComponent): String;

    { Is is allowed to drag-and-drop from ControlsTree to ControlsTree.
      Src, Dst, SrcComponent can be @nil.
      (But SrcComponents cannot!) }
    function ControlsTreeAllowDrag(const Src, Dst: TTreeNode): Boolean;
    function ControlsTreeAllowDrag(const SrcComponent: TComponent; const Dst: TTreeNode): Boolean;
    function ControlsTreeAllowDrag(const SrcComponents: TComponentList; const Dst: TTreeNode): Boolean;

    procedure FrameAnchorsChange(Sender: TObject);
    procedure AdjustUserInterfaceAnchorsToKeepRect(const UI: TCastleUserInterface;
      const RenderRectBeforeChange: TFloatRectangle);
    // Save and restore selection.
    // Careful: you can use it only if the operation between will *never* free any of them.
    //procedure SelectionRestoreAndFree(var Selection: Classes.TList);
    //function SelectionSave: Classes.TList;

    { Get selected component from tree node.
      Should be used directly only by GetSelected and GetSelectedComponent,
      and everything else should look at GetSelected and GetSelectedComponent
      to know selection.

      @param(AutoSelectParents See GetSelected docs for explanation.) }
    function SelectedFromNode(Node: TTreeNode;
      const AutoSelectParents: Boolean = true): TComponent;

    { Calculate all selected components as a list, non-nil <=> non-empty.

      @param(AutoSelectParents If @true (default) then selecting a special
        grouping tree nodes like "Behaviors" and "Non-Visual Components"
        also implicitly selects their parent.

        This is generally useful for reading operations, but undesired for
        writing operations, see
        https://github.com/castle-engine/castle-engine/issues/522
        https://github.com/castle-engine/castle-engine/issues/521
        https://github.com/castle-engine/castle-engine/issues/520
      ).
    }
    procedure GetSelected(out Selected: TComponentList;
      out SelectedCount: Integer; const AutoSelectParents: Boolean = true);

    { Select given components in the hierarchy.
      Consistently with GetSelected, that may return @nil,
      this accepts @nil as input. }
    procedure SetSelected(const Selected: TComponentList);

    function GetSelectedUserInterface: TCastleUserInterface;
    procedure SetSelectedUserInterface(const Value: TCastleUserInterface);
    { If there is exactly one item selected, and it is TCastleUserInterface,
      return it. Otherwise return nil. }
    property SelectedUserInterface: TCastleUserInterface
      read GetSelectedUserInterface write SetSelectedUserInterface;

    function GetSelectedComponent(
      const AutoSelectParents: Boolean = true): TComponent;
    function GetSelectedComponentAutoSelectParents: TComponent;
    procedure SetSelectedComponent(const Value: TComponent);
    { If there is exactly one item selected, return it. Otherwise return nil. }
    property SelectedComponent: TComponent
      read GetSelectedComponentAutoSelectParents write SetSelectedComponent;

    { If the selected items all have the same TCastleViewport parent,
      return it. Otherwise return nil. }
    function SelectedViewport: TCastleViewport;

    { Look at current selection and hover and possibly change CurrentViewport,
      calling also OnCurrentViewportChanged. }
    procedure UpdateCurrentViewport;
    procedure SetCurrentViewport(const Value: TCastleViewport);

    { If there is exactly one item selected, and it is TCastleTransform,
      return it. Otherwise return nil. }
    function GetSelectedTransform: TCastleTransform;
    procedure SetSelectedTransform(const Value: TCastleTransform);
    property SelectedTransform: TCastleTransform
      read GetSelectedTransform write SetSelectedTransform;

    procedure InspectorBasicFilter(Sender: TObject; AEditor: TPropertyEditor;
      var aShow: Boolean);
    procedure InspectorLayoutFilter(Sender: TObject; AEditor: TPropertyEditor;
      var aShow: Boolean);
    procedure InspectorAllFilter(Sender: TObject; AEditor: TPropertyEditor;
      var aShow: Boolean);
    procedure MarkModified;
    function UndoMessageModified(const Sel: TPersistent;
      const ModifiedProperty, ModifiedValue: String; const SelectedCount: Integer): String;
    { PropertyGridModified and PropertyEditorModified are called when
      something changes in the design.
      PropertyGridModified and PropertyEditorModified are both called when
      something changes within Object Inspector basic features
      (such as editing string, boolean, enum or numeric values)
      In this case PropertyEditorModified usually comes first.
      In case something changed outside of Object inspector (e.g. drag-and-drops,
      rename components in treeview, add components, etc.)
      only PropertyGridModified is called
      In case a custom dialog is used to change a value
      (e.g. a Color picker, TStrings editor, Open File dialogue, etc.)
      then only PropertyEditorModified is called. }
    procedure PropertyGridModified(Sender: TObject);
    procedure PropertyEditorModified(Sender: TObject);
    procedure PropertyGridCollectionItemClick(Sender: TObject);
    procedure PropertyGridCollectionItemClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure PropertyGridCollectionItemAdd(Sender: TObject);
    procedure PropertyGridCollectionItemDelete(Sender: TObject);
    procedure PropertyGridCollectionItemMoveUp(Sender: TObject);
    procedure PropertyGridCollectionItemMoveDown(Sender: TObject);

    { Is Child selectable and visible in hierarchy. }
    class function Selectable(const Child: TComponent): Boolean; static;
    { Is Child deletable by user (this implies it is also selectable). }
    function Deletable(const Child: TComponent): Boolean;

    { Internal helper for UpdateDesign or ValidateHierarchy,
      should only be used by these 2 methods. }
    procedure ValidateOrUpdateHierarchy(const Validate: Boolean);

    { Make sure the hierarchy tree (ControlsTree) reflects current DesignRoot state.
      Add/remove tree nodes from ControlsTree as necessary.

      Also set TreeNodeMap (unconditionally, i.e. it is always cleared and filled
      from scratch by this method).

      This guarantees that editor UI shows the correct state of everything. }
    procedure UpdateDesign;

    { Returns a warning and false value when hierarchy tree (ControlsTree) differs from
      castle design hierarchy (DesignRoot). }
    function ValidateHierarchy: Boolean;

    procedure UpdateSelectedControl;
    { Update whether TabInfo is visible and if yes -- what it contains. }
    procedure UpdateSelectedInfo;
    { Update anchors shown, based on UI state.
      Updates which buttons are pressed inside 2 TAnchorFrame instances.
      If AllowToHideParentAnchorsFrame, updates also checkbox
      "parent and self equal" and may hide the parent anchor frame if yes. }
    procedure UpdateAnchors(const UI: TCastleUserInterface;
      const AllowToHideParentAnchorsFrame: Boolean);
    { Filter property in object inspector.
      When FilterBySection = true, then Section matters and only properties in this section
      are displayed. }
    procedure InspectorFilter(const Sender: TObject; const AEditor: TPropertyEditor;
      var AShow: Boolean;
      const FilterBySection: Boolean; const Section: TPropertySection);
    procedure GizmoTransformModifyBegin(Sender: TObject);
    procedure GizmoTransformModified(Sender: TObject);
    procedure GizmoTransformModifyEnd(Sender: TObject);
    { Fix camera position, to look at Pos.XY in case of 2D games.
      Use this before doing V.InternalCamera.AnimateTo/SetWorldView with given Pos,Dir,Up.

      In case of 2D this means we should:

      - Fix Pos.Z, to keep camera Z matching current run-time camera.
        (this seems most natural and simplest camera behavior at design-time,
        so that design-time camera uses the same Z).

      - Fix Pos.XY, to account that Camera.Orthographic.Origin may <> (0.5,0.5).

      Done when operating in 2D (*not* detected by navigation type, but by projection type and axis,
        to keep this also working in Fly mode for 2D games).
    }
    procedure FixCamera2D(const V: TCastleViewport; var Pos: TVector3; const Dir, Up: TVector3);
    procedure ViewportViewBox(const V: TCastleViewport; Box: TBox3D);
    procedure CurrentViewportFreeNotification(const Sender: TFreeNotificationObserver);

    { Single selected item.
      Only non-nil when we have selected exactly one component.
      IOW, this is always @nil if we selected zero or more than one component.

      Use this when you need to know only the single selected item,
      because the given operation cannot handle multiple selected items.
      E.g. for rename operation.

      Note:
      Never use built-in LCL ControlsTree.Selected, which is not reliable to use
      on a TTreeView with multi-selection possible.
      The LCL ControlsTree.Selected problems details:

      - it is not synchronized with ControlsTree.SelectionCount,
        ControlsTree.Selections after doing "ControlsTree.Selected := nil".
        The ControlsTree.SelectionCount may be left > 0.

      - it is not synchronized with ControlsTree.SelectionCount,
        ControlsTree.Selections after selecting multiple components with Shift and Ctrl.
        E.g.
        - select one tree node.
          click on it again with Ctrl.
          Effect: ControlsTree.Selected <> nil,
          but ControlsTree.SelectionCount = 0.
        - select one tree node.
          select 3 more with Shift.
          unselect 3 more with Ctrl.
          Effect: ControlsTree.Selected = nil,
          but ControlsTree.SelectionCount > 0.

      - adding / removing nodes also don't seem to always synchronize them...

      Note: Also never set ControlsTree.Selected.
      Do ControlsTree.ClearSelection that makes multi-selection properly cleared.
    }
    function ControlsTreeOneSelected: TTreeNode;
    function GetInspectorForActiveTab: TOIPropertyGrid;
    function GetSavedSelection: TSavedSelection;
    procedure RestoreSavedSelection(const S: TSavedSelection);
    procedure MenuItemChangeClassClick(Sender: TObject);
    procedure SetShowColliders(const AValue: Boolean);
    { Show / hide colliders following FShowColliders setting.
      If T = nil, updates everywhere (TODO: for now,
      only in CurrentViewport). Otherwise updates only in T. }
    procedure UpdateColliders(T: TCastleTransform = nil);

    { Get parent of non-visual component.

      Can be used on any TComponent. Parent can be TCastleComponent,
      but it can contain any TComponent, this is important ability to store
      in TCastleComponent.NonVisualComponents also non-CGE components.

      Since there's no TCastleComponent.NonVisualParent or such, so we find parent using
      ControlsTree knowledge.
      Returns nil if no parent. }
    function NonVisualComponentParent(const C: TComponent): TCastleComponent;

    { Currently selected transformation, chosen more aggressively than just
      SelectedTransform. Even selecting a behavior makes the parent current.
      This way e.g. TransformManipulate also shows
      the transformation of selected behavior. }
    function CurrentTransform: TCastleTransform;

    procedure SetMaximizePreview(const AValue: Boolean);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    OnUpdateFormCaption: TNotifyEvent;
    OnSelectionChanged: TNotifyEvent;
    { Called always when CurrentViewport value changed. }
    OnCurrentViewportChanged: TNotifyEvent;
    OnProposeOpenDesign: TProposeOpenDesignEvent;
    OnRunningToggle, OnApiReferenceOfCurrent: TNotifyEvent;
    OnIsRunning: TBooleanEvent;
    OnShowStatistics: TBooleanEvent;

    function RenameSelectedPossible: Boolean;
    function RenamePossible(const C: TComponent): Boolean;

    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;

    procedure SaveDesign(const Url: String);
    { Changes DesignRoot, DesignUrl and all the associated user-interface. }
    procedure OpenDesign(const NewDesignRoot, NewDesignOwner: TComponent;
      NewDesignUrl: String);
    procedure OpenDesign(const NewDesignUrl: String);
    procedure NewDesign(const ComponentClass: TComponentClass;
      const ComponentOnCreate: TNotifyEvent);

    function FormCaption: String;
    procedure BeforeProposeSaveDesign;
    procedure AddComponent(const ComponentClass: TComponentClass;
      const ComponentOnCreate: TNotifyEvent);
    { Create and add a new component to the design.

      @param(BaseNewComponentName Base of new name (without numeric suffix to
        make it unique. you can use StripNumericSuffix to calculate it),
        passed to @link(ProposeComponentName).

        Leave it empty to derive name from ComponentClass.ClassName.)

      @param(IndexInParent Index at which the new component should be inserted
        into parent. Leave -1 (default) to insert at the end ("front-most" for UI).)
    }
    function AddComponent(const ParentComponent: TComponent; const ComponentClass: TComponentClass;
      const ComponentOnCreate: TNotifyEvent;
      const BaseNewComponentName: String = '';
      const InsertIndex: Integer = -1): TComponent;
    procedure DeleteComponent(const AutoSelectParents: Boolean = false);
    { Free component C (which should be part of this designed, owned by DesignOwner)
      and all children.

      We have to delete things recursively, otherwise they would keep existing,
      taking resources and reserving names in DesignOwner,
      even though they would not be visible when disconnected from parent
      hierarchy.

      This does nothing if you try to free some internal component
      (like csTransient) or the design root (which can never be freed). }
    procedure FreeComponentRecursively(const C: TComponent);
    procedure CopyComponent;
    procedure PasteComponent;
    procedure CutComponent;
    procedure DuplicateComponent;
    procedure DuplicateLinkedComponent;

    function AddComponentFromUrl(const AddUrl: String;
      const ParentComponent: TComponent): TComponent;
    function AddImported(const AddUrl: String): TComponent;

    { Set UIScaling values. }
    procedure UIScaling(const UIScaling: TUIScaling;
      const UIReferenceWidth, UIReferenceHeight: Single);

    property UndoSystem: TUndoSystem read FUndoSystem;
    property DesignUrl: String read FDesignUrl;
    { Root saved/loaded to component file }
    property DesignRoot: TComponent read FDesignRoot;
    property DesignModified: Boolean read FDesignModified;
    procedure RecordUndo(const UndoComment: String;
      const UndoCommentPriority: TUndoCommentPriority);

    { Call after any change to the design (that changes what will be saved
      to JSON) happened, except when this was done by user changing value
      through Object Inspector.

      This:
      - Refreshes Object Inspector display,
      - marks design as "modified",
      - records undo.

      @param(UndoComment Describes the change. You can pass empty String
        to let auto-generating a sensible comment.)

      @param(UndoCommentPriority How much are you sure that UndoComment
        is the best message to describe last change.
        This is used only when UndoComment <> '' and only when an "undo record"
        was already stored for the current state. The given UndoComment
        overrides the last if it has higher UndoCommentPriority.

        Usually you want to pass here ucHigh, since usually you have
        a really good knowledge about the change when calling this method.)

      @param(UndoOnRelease If @true, then do not store "undo record" now,
        instead schedule storing undo record when user releases the mouse.

        This should be @true only for actions that do something on each mouse
        move (like dragging transform or UI position/size).
        In that case, storing "undo record" at each tiny mouse move would be
        bad -- performance would drop during mouse move, and generating too many
        "undo records" means that undoing them is not really comfortable.

        For most operations, this is @false.)
    }
    procedure ModifiedOutsideObjectInspector(const UndoComment: String;
      const UndoCommentPriority: TUndoCommentPriority; const UndoOnRelease: Boolean = false);

    procedure SaveSelected;

    procedure CurrentComponentApiUrl(var Url: String);

    { Viewport to act on using various commands.

      Chosen "aggressively" by looking at selected viewport
      (based on selected ui or transform within viewport)
      or viewport over which mouse hovers. We want to enable user to set current viewport
      as easily as possible, to avoid the "selection of viewport" being an extra step
      user needs to remember to do.

      Note that this viewport may not be Selectable.
      It may be an internal viewport (in case of .castle-transform files)
      or a viewport inside TCastleDesign.Design (testcase when it's needed:
      examples/physics/physics_joints_3d/ ).

      @nil if none. }
    property CurrentViewport: TCastleViewport read FCurrentViewport;

    procedure ViewportViewAxis(const Dir, Up: TVector3);
    procedure ViewportViewAll;
    procedure ViewportViewSelected;
    procedure ViewportSetup2D;
    procedure ViewportToggleProjection;
    procedure ViewportAlignViewToCamera;
    procedure ViewportAlignCameraToView;
    procedure ViewportAlignTransformToView;
    procedure ViewportSnapToFloor(const AlignToNormal: Boolean = false);
    procedure ViewportProjectAlongView(const AlignToNormal: Boolean = false);
    procedure ViewportSnapToGrid;
    procedure ViewportSnapToCursor(const SnapToVertex: Boolean = false;
      const AlignToNormal: Boolean = false);
    procedure ToggleCoordSpace;
    procedure TogglePivotMode;
    procedure AlignSelectionToAxis(const Axis: T3DAxis);
    procedure DistributeSelectionAlongAxis(const Axis: T3DAxis);
    procedure DistributeSelectionGapsAlongAxis(const Axis: T3DAxis);
    procedure StackSelectionAlongAxis(const Axis: T3DAxis);
    procedure MirrorSelectionAlongAxis(const Axis: T3DAxis);
    procedure RotateSelection90Y;
    procedure RandomizeSelectionTransform;
    procedure ArrayDuplicateSelected(const Count: Integer;
      const StepOffset: TVector3; const StepYawDeg: Single);
    procedure ShowArrayDuplicateDialog;
    procedure RadialDuplicateSelected(const Count: Integer;
      const Radius, TotalAngleDeg: Single; const OrientToCenter: Boolean);
    procedure ShowRadialDuplicateDialog;
    procedure GridDuplicateSelected(const CountX, CountY, CountZ: Integer;
      const Spacing: TVector3);
    procedure ShowGridDuplicateDialog;
    procedure ReplaceSelectedComponents(const NewClass: TComponentClass;
      const ComponentOnCreate: TNotifyEvent = nil);
    procedure ShowReplaceComponentPalette;
    procedure InvertSelection;
    procedure SelectChildren(const Recursive: Boolean = false);
    procedure ViewportMeasureToCursor;
    procedure ClearViewportMeasurement;
    function IsComponentLocked(const C: TComponent): Boolean;
    procedure ToggleSelectedLock;
    procedure UnlockAll;
    procedure SaveCameraBookmark(const Slot: Integer);
    procedure RecallCameraBookmark(const Slot: Integer);
    procedure AdjustCameraSpeed(const Factor: Single);
    procedure ToggleSelectedVisibility;
    procedure IsolateSelected;
    procedure ShowAllHidden;
    procedure GroupSelectedTransforms;
    procedure UngroupSelectedTransforms;
    procedure SelectAllOfSameClass;
    procedure ExpandSelectedSubtree;
    procedure CollapseSelectedSubtree;
    procedure ResetSelectedPropertyToDefault;
    procedure CopyTransform;
    procedure PasteTransform;
    procedure CycleViewportRenderMode;
    procedure UpdateViewModeButtonCaption;
    function EffectiveShowStatistics: Boolean;
    procedure ShowQuickAddPalette;

    { Physics stuff. } { }
    procedure SimulationPlayStop;
    procedure SimulationPauseUnpause;
    procedure SimulationSingleStep;
    procedure KeepSimulationChanges;
    property ShowColliders: Boolean read FShowColliders write SetShowColliders;

    procedure ReleaseAllKeysAndMouse;

    procedure FocusDesign;
    procedure ChangeMode(const NewMode: TMode);
    procedure ShowAllJointsTools;
    procedure HideAllJointsTools;

    { Saves some editor data in subcomponent of Application for property
      editors }
    procedure UpdateEditorDataForPropertyEditors;

    { Toggle whether the edit box to find component by name exists. }
    procedure FindToggle;
    { Find next, if find is active. }
    procedure FindNext;

    procedure ExportToModel;

    property MaximizePreview: Boolean
      read FMaximizePreview write SetMaximizePreview default false;
  end;

implementation

uses
  { Standard FPC/Lazarus units }
  // use Windows unit with FPC 3.0.x, to get TSplitRectType enums
  {$ifdef VER3_0} {$ifdef MSWINDOWS} Windows, {$endif} {$endif}
  TypInfo, StrUtils, Math, Graphics, Types, Dialogs, LCLType, ObjInspStrConsts,
  { CGE units }
  CastleComponentSerialize, CastleFileFilters, CastleGLUtils, CastleImages,
  CastleLog, CastleProjection, CastleQuaternions, CastleStringUtils, CastleTimeUtils,
  CastleUriUtils, X3DLoad, CastleFilesUtils, CastleInternalPhysicsVisualization,
  CastleInternalUrlUtils, CastleInternalFileMonitor, X3DNodes, CastleSoundEngine,
  CastleBehaviors,
  { Editor units }
  EditorRegisterAllComponents,
  FormProject, CastleComponentEditorDesigner;

{$R *.lfm}

{$ifdef VER3_0}
{$ifdef MSWINDOWS}
type
  TSplitRectType = Windows.TSplitRectType;
const
  srLeft = TSplitRectType.srLeft;
  srRight = TSplitRectType.srRight;
  srTop = TSplitRectType.srTop;
  srBottom = TSplitRectType.srBottom;
{$endif}
{$endif}

function ParentRenderRect(const UI: TCastleUserInterface): TFloatRectangle;
begin
  if UI.Parent = nil then
    Result := FloatRectangle(UI.Container.PixelsRect)
  else
    Result := UI.Parent.RenderRect;
end;

var
  { Used to display UI that is both selected and hovered over. }
  ColorHoverAndSelected: TCastleColor;

{ TDesignFrame.TDesignerLayer ------------------------------------------------ }

constructor TDesignFrame.TDesignerLayer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FullSize := true;

  LayerPhysicsSimulation := UserInterfaceLoad(InternalCastleDesignData + 'layer_physics_simulation.castle-user-interface', Self);
  LayerPhysicsSimulation.Exists := false;
  LabelPhysicsSimulationRunning := FindRequiredComponent('LabelRunning') as TCastleLabel;
  LabelPhysicsSimulationPaused := FindRequiredComponent('LabelPaused') as TCastleLabel;
  InsertFront(LayerPhysicsSimulation);

  RectHover := TCastleRectangleControl.Create(Self);
  RectHover.Color := Vector4(0, 0, 0, 0.25);
  RectHover.Exists := false;
  { LabelHover with scaling sometimes looks too tiny.
    Also, positioning RectHover is easier without UI scaling. }
  RectHover.EnableUIScaling := false;
  InsertFront(RectHover);

  LabelHover := TCastleLabel.Create(Self);
  LabelHover.Anchor(hpMiddle);
  LabelHover.Anchor(vpMiddle);
  LabelHover.FontSize := 15;
  LabelHover.EnableUIScaling := false;
  RectHover.InsertFront(LabelHover);

  RectSelected := TCastleRectangleControl.Create(Self);
  RectSelected.Color := Vector4(0, 0, 0, 0.25);
  RectSelected.Exists := false;
  RectSelected.EnableUIScaling := false;
  InsertFront(RectSelected);

  LabelSelected := TCastleLabel.Create(Self);
  LabelSelected.Anchor(hpMiddle);
  LabelSelected.Anchor(vpMiddle);
  LabelSelected.FontSize := 15;
  LabelSelected.EnableUIScaling := false;
  RectSelected.InsertFront(LabelSelected);

  RectStatistics := TCastleRectangleControl.Create(Self);
  RectStatistics.Color := Vector4(0, 0, 0, 0.25);
  RectStatistics.Exists := false;
  RectStatistics.EnableUIScaling := false;
  RectStatistics.Anchor(hpRight, -5);
  RectStatistics.Anchor(vpTop, -5);
  RectStatistics.AutoSizeToChildren := true;
  InsertFront(RectStatistics);

  LabelStatistics := TCastleLabel.Create(Self);
  LabelStatistics.Border.AllSides := 5;
  LabelStatistics.Anchor(hpMiddle);
  LabelStatistics.Anchor(vpMiddle);
  LabelStatistics.FontSize := 15;
  LabelStatistics.EnableUIScaling := false;
  LabelStatistics.Color := White;
  LabelStatistics.Alignment := hpRight;
  RectStatistics.InsertFront(LabelStatistics);

  ForceFallbackLook(RectStatistics);
end;

procedure TDesignFrame.TDesignerLayer.GLContextOpen;
begin
  inherited;
  if Assigned(OnGLContextOpen) then
    OnGLContextOpen(Self);
end;

function TDesignFrame.TDesignerLayer.HoverUserInterface(
  const AMousePosition: TVector2;
  const EnterNestedDesigns: Boolean): TCastleUserInterface;

  { Like TCastleUserInterface.CapturesEventsAtPosition, but
    - ignores CapturesEvents
    - uses RenderRectWithBorder (to be able to drag complete control)
    - doesn't need "if the control covers the whole Container" hack. }
  function SimpleCapturesEventsAtPosition(const UI: TCastleUserInterface;
    const Position: TVector2; const TestWithBorder: Boolean): Boolean;
  begin
    if TestWithBorder then
      Result := UI.RenderRectWithBorder.Contains(Position)
    else
      Result := UI.RenderRect.Contains(Position);
  end;

  { Is C selectable, or we should enter it anyway because of EnterNestedDesigns. }
  function Enter(const Parent, C: TCastleUserInterface): Boolean;
  begin
    Result := TDesignFrame.Selectable(C) or
      ( EnterNestedDesigns and
        (Parent is TCastleDesign) and
        (TCastleDesign(Parent).InternalDesign = C) );
  end;

  function ControlUnder(const C: TCastleUserInterface;
    const MousePos: TVector2; const TestWithBorder: Boolean): TCastleUserInterface;
  var
    I: Integer;
  begin
    Result := nil;

    { To allow selecting even controls that have bad rectangle (outside
      of parent, which can happen, e.g. if you enlarge caption of label
      with AutoSize), do not check C.CapturesEventsAtPosition(MousePos)
      too early here. So the condition

        and C.CapturesEventsAtPosition(MousePos)

      is not present in "if" below. }

    if C.Exists then
    begin
      { First try to find children, with TestWithBorder=false (so it doesn't detect
        control if we merely point at its border). This allows to find controls
        places on another control's border. }
      for I := C.ControlsCount - 1 downto 0 do
        if Enter(C, C.Controls[I]) then
        begin
          Result := ControlUnder(C.Controls[I], MousePos, false);
          if Result <> nil then Exit;
        end;

      { Next try to find children, with TestWithBorder=true, so it tries harder
        to find something. }
      for I := C.ControlsCount - 1 downto 0 do
        if Enter(C, C.Controls[I]) then
        begin
          Result := ControlUnder(C.Controls[I], MousePos, true);
          if Result <> nil then Exit;
        end;

      { Eventually return yourself, C. }
      //if C.CapturesEventsAtPosition(MousePos) then
      if SimpleCapturesEventsAtPosition(C, MousePos, TestWithBorder) and
         C.EditorSelectOnHover and
         ((C is TCastleViewport) or (not Frame.IsComponentLocked(C))) then
        Result := C;
    end;
  end;

  function MouseOverControl(const Control: TCastleControl): Boolean;
  var
    PosInClient: TPoint;
  begin
    PosInClient := Control.ScreenToClient(Mouse.CursorPos);
    Result := Control.ClientRect.Contains(PosInClient);
  end;

begin
  Result := nil;
  if MouseOverControl(Frame.CastleControl) then
  begin
    if Frame.DesignRoot is TCastleUserInterface then
      Result := ControlUnder(Frame.DesignRoot as TCastleUserInterface, AMousePosition, true)
    else
    if Frame.DesignRoot is TCastleTransform then
      Result := Frame.FDesignViewportForTransforms;
  end;
end;

function TDesignFrame.TDesignerLayer.HoverComponent(const AMousePosition: TVector2): TCastleComponent;

  function SelectionFromRayHit(const RayHit: TRayCollision): TCastleTransform;
  var
    I: Integer;
  begin
    // set outer-most TCastleTransformReference, if any, to show selection at TCastleTransformReference
    for I := RayHit.Count - 1 downto 0 do
      if (RayHit[I].Item is TCastleTransformReference) and Selectable(RayHit[I].Item) then
        Exit(RayHit[I].Item);

    { We want the inner-most TCastleTransform hit, but not anything non-selectable
      (which means csTransient) (to avoid hitting gizmo).
      Moreover, things that are children of csTransient should always be treated like csTransient
      too, e.g. GizmoSelect in TInternalCastleEditorGizmo should never be returned by this.

      So if there's anything non-selectable (which just means csTransient),
      searching from outer (world),
      then pick the selected transform right above it. }

    for I := RayHit.Count - 1 downto 0 do
      if not Selectable(RayHit[I].Item) then
      begin
        if I + 1 < RayHit.Count then
          Exit(RayHit[I + 1].Item)
        else
          Exit(nil);
      end;

    { Nothing non-selectable (csTransient) on the list, pick the inner-most transform }
    if RayHit.Count <> 0 then
      Result := RayHit[0].Item
    else
      Result := nil;
  end;

var
  Viewport: TCastleViewport;
  RayOrigin, RayDirection: TVector3;
  RayHit: TRayCollision;
begin
  { Note: We don't call here CurrentViewport.

    Unlike with CurrentViewport, here we don't try to forcefully select viewport
    (from hover or selection). If the mouse is over non-viewport, then this
    should return non-viewport.

    Also, unlike CurrentViewport,
    we don't want to remember last hovered/selected viewport here,
    it would be weird for user here.

    Also, unlike CurrentViewport, we don't pass EnterNestedDesigns as
    UpdateCurrentViewport does. We don't need to look for viewport that aggressive. }

  Result := HoverUserInterface(AMousePosition);
  if Result is TCastleViewport then // also checks Result <> nil
  begin
    Viewport := TCastleViewport(Result);
    Viewport.PositionToRay(AMousePosition, true, RayOrigin, RayDirection);
    RayHit := Viewport.Items.WorldRay(RayOrigin, RayDirection);
    try
      if RayHit <> nil then
        Result := SelectionFromRayHit(RayHit);
    finally FreeAndNil(RayHit) end;
  end;
  if (Result <> nil) and Frame.IsComponentLocked(Result) then
    Result := nil;
end;

procedure TDesignFrame.TDesignerLayer.SelectComponentsInMarquee(
  const MarqueeRect: TFloatRectangle; const Additive: Boolean);
var
  SelectedNodes: TList;
  TreeNode: TTreeNode;
  C: TComponent;
  T: TCastleTransform;
  UI: TCastleUserInterface;
  V: TCastleViewport;
  CamPos, CamDir, CamUp, WorldPos: TVector3;
  ScreenPos: TVector2;
  BBox: TBox3D;
  I: Integer;
  InViewportMarquee: Boolean;
begin
  SelectedNodes := TList.Create;
  try
    if Additive then
      for I := 0 to Frame.ControlsTree.SelectionCount - 1 do
        SelectedNodes.Add(Frame.ControlsTree.Selections[I]);

    V := Frame.CurrentViewport;
    InViewportMarquee := (V <> nil) and (V.InternalCamera <> nil) and
      MarqueeRect.Collides(V.RenderRectWithBorder);

    if InViewportMarquee then
      V.InternalCamera.GetWorldView(CamPos, CamDir, CamUp);

    TreeNode := Frame.ControlsTree.Items.GetFirstNode;
    while TreeNode <> nil do
    begin
      C := Frame.SelectedFromNode(TreeNode, false);
      if (C <> nil) and (C <> Frame.DesignRoot) and
         Selectable(C) and (not Frame.IsComponentLocked(C)) then
      begin
        if InViewportMarquee and (C is TCastleTransform) and
           (not (C is TCastleAbstractRootTransform)) then
        begin
          T := TCastleTransform(C);
          if T.Exists and (T.World = V.Items) and T.HasWorldTransform then
          begin
            BBox := T.WorldBoundingBox;
            if not BBox.IsEmpty then
              WorldPos := BBox.Center
            else
              WorldPos := T.LocalToWorld(TVector3.Zero);

            if (V.InternalCamera.ProjectionType = ptOrthographic) or
               (TVector3.DotProduct(WorldPos - CamPos, CamDir) > 0) then
            begin
              ScreenPos := V.LocalToContainerPosition(V.PositionFromWorld(WorldPos));
              if MarqueeRect.Contains(ScreenPos) and (SelectedNodes.IndexOf(TreeNode) = -1) then
                SelectedNodes.Add(TreeNode);
            end;
          end;
        end else
        if (not InViewportMarquee) and (C is TCastleUserInterface) then
        begin
          UI := TCastleUserInterface(C);
          if UI.Exists and MarqueeRect.Contains(UI.RenderRectWithBorder.Center) and
             (SelectedNodes.IndexOf(TreeNode) = -1) then
            SelectedNodes.Add(TreeNode);
        end;
      end;
      TreeNode := TreeNode.GetNext;
    end;

    Frame.ControlsTree.Select(SelectedNodes);
  finally
    FreeAndNil(SelectedNodes);
  end;
end;

function TDesignFrame.TDesignerLayer.IsResizing(const UI: TCastleUserInterface;
  const Position: TVector2; out Horizontal: THorizontalPosition;
  out Vertical: TVerticalPosition; out Hint: String): Boolean;
const
  BorderDragMargin = 10;
var
  R: TFloatRectangle;
  ResizeWidth, ResizeHeight, IsTop, IsBottom, IsRight, IsLeft: Boolean;
  ResizeDisabledReason: String;
begin
  R := UI.RenderRectWithBorder;

  UI.EditorAllowResize(ResizeWidth, ResizeHeight, ResizeDisabledReason);

  Hint := '';

  IsTop := R.TopPart(BorderDragMargin).Contains(Position);
  IsBottom := R.BottomPart(BorderDragMargin).Contains(Position);
  IsRight := R.RightPart(BorderDragMargin).Contains(Position);
  IsLeft := R.LeftPart(BorderDragMargin).Contains(Position);

  { the order of checking (top or bottom) matters in case of very
    small heights. }
  if ResizeHeight and IsTop then
    Vertical := vpTop
  else
  if ResizeHeight and IsBottom then
    Vertical := vpBottom
  else
  begin
    Vertical := vpMiddle;
    if IsTop or IsBottom then
      Hint := ResizeDisabledReason;
  end;

  if ResizeWidth and IsRight then
    Horizontal := hpRight
  else
  if ResizeWidth and IsLeft then
    Horizontal := hpLeft
  else
  begin
    Horizontal := hpMiddle;
    if IsLeft or IsRight then
      Hint := ResizeDisabledReason;
  end;

  if Hint <> '' then
    Hint := UI.Name + ':' + NL + Hint;

  Result := (Vertical <> vpMiddle) or (Horizontal <> hpMiddle);
end;

function TDesignFrame.TDesignerLayer.IsResizing(const UI: TCastleUserInterface;
  const Position: TVector2; out Horizontal: THorizontalPosition;
  out Vertical: TVerticalPosition): Boolean;
var
  Hint: String;
begin
  Result := IsResizing(UI, Position, Horizontal, Vertical, Hint);
end;

function TDesignFrame.TDesignerLayer.Press(
  const Event: TInputPressRelease): Boolean;

  procedure SetSelection(const NewComponent: TComponent; const ToggleSelection: Boolean);
  var
    NewComponentNode: TTreeNode;
    NewSelection: TList;
    I: Integer;
  begin
    if ToggleSelection then
    begin
      if Frame.TreeNodeMap.TryGetValue(NewComponent, NewComponentNode) then
      begin
        if NewComponentNode.Selected then
        begin
          { Unfortunately, unselecting by setting
              NewComponentNode.Selected := false
            doesn't work. }
          NewSelection := TList.Create;
          try
            for I := 0 to Frame.ControlsTree.SelectionCount - 1 do
              if NewComponentNode <> Frame.ControlsTree.Selections[I] then
                NewSelection.Add(Frame.ControlsTree.Selections[I]);
            Frame.ControlsTree.Select(NewSelection);
          finally FreeAndNil(NewSelection) end;
        end else
          NewComponentNode.Selected := not NewComponentNode.Selected;
      end else
        WritelnWarning('Cannot toggle selection of "%s" because it is not found in TreeNodeMap', [
          NewComponent.Name
        ]);
    end
    else
    begin
      { If NewComponent is already part of an active multi-selection (for example
        when clicking on the 3D gizmo attached to the primary selected transform),
        keep the multi-selection intact so the gizmo drags all selected objects. }
      if (NewComponent <> nil) and
         (Frame.ControlsTree.SelectionCount > 1) and
         Frame.TreeNodeMap.TryGetValue(NewComponent, NewComponentNode) and
         NewComponentNode.Selected then
        Exit;
      Frame.SelectedComponent := NewComponent;
    end;
  end;

var
  UI: TCastleUserInterface;
  BookmarkSlot: Integer;
begin
  Result := inherited Press(Event);
  if Result then Exit;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyEnd) then
  begin
    if (mkCtrl in Event.ModifiersDown) and (mkShift in Event.ModifiersDown) then
      Frame.ViewportProjectAlongView(mkAlt in Event.ModifiersDown)
    else
    if mkCtrl in Event.ModifiersDown then
      Frame.ViewportSnapToGrid
    else
    if (mkAlt in Event.ModifiersDown) or (mkShift in Event.ModifiersDown) then
      Frame.ViewportSnapToFloor(true)
    else
      Frame.ViewportSnapToFloor(false);
    Exit(true);
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyV) and
     (not (buttonRight in Frame.CastleControl.Container.MousePressed)) then
  begin
    if Event.ModifiersDown = [] then
    begin
      Frame.ViewportSnapToCursor(false, false);
      Exit(true);
    end else
    if Event.ModifiersDown = [mkShift] then
    begin
      Frame.ViewportSnapToCursor(true, false);
      Exit(true);
    end else
    if Event.ModifiersDown = [mkAlt] then
    begin
      Frame.ViewportSnapToCursor(false, true);
      Exit(true);
    end else
    if Event.ModifiersDown = [mkShift, mkAlt] then
    begin
      Frame.ViewportSnapToCursor(true, true);
      Exit(true);
    end;
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyL) and
     (not (buttonRight in Frame.CastleControl.Container.MousePressed)) then
  begin
    if Event.ModifiersDown = [] then
    begin
      Frame.ToggleSelectedLock;
      Exit(true);
    end else
    if Event.ModifiersDown = [mkAlt] then
    begin
      Frame.UnlockAll;
      Exit(true);
    end;
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyD) then
  begin
    if Event.ModifiersDown = [mkCtrl, mkShift] then
    begin
      Frame.ShowArrayDuplicateDialog;
      Exit(true);
    end else
    if Event.ModifiersDown = [mkCtrl, mkAlt] then
    begin
      Frame.ShowRadialDuplicateDialog;
      Exit(true);
    end;
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyG) and
     (Event.ModifiersDown = [mkCtrl, mkAlt]) then
  begin
    Frame.ShowGridDuplicateDialog;
    Exit(true);
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyI) and
     (Event.ModifiersDown = [mkCtrl]) then
  begin
    Frame.InvertSelection;
    Exit(true);
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyR) and
     (Event.ModifiersDown = [mkCtrl, mkShift]) then
  begin
    Frame.ShowReplaceComponentPalette;
    Exit(true);
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyM) and
     (not (buttonRight in Frame.CastleControl.Container.MousePressed)) then
  begin
    if Event.ModifiersDown = [] then
    begin
      Frame.ViewportMeasureToCursor;
      Exit(true);
    end else
    if Event.ModifiersDown = [mkAlt] then
    begin
      Frame.ClearViewportMeasurement;
      Exit(true);
    end;
  end;

  if (Frame.Mode <> moInteract) and (Event.EventType = itKey) and
     (not (buttonRight in Frame.CastleControl.Container.MousePressed)) then
  begin
    if (Event.Key = keyNumpad7) or ((Event.Key = key7) and (mkAlt in Event.ModifiersDown)) then
    begin
      if mkCtrl in Event.ModifiersDown then
        Frame.ViewportViewAxis(Vector3(0, 1, 0), Vector3(0, 0, 1))
      else
        Frame.ViewportViewAxis(Vector3(0, -1, 0), Vector3(0, 0, -1));
      Exit(true);
    end else
    if (Event.Key = keyNumpad1) or ((Event.Key = key1) and (mkAlt in Event.ModifiersDown)) then
    begin
      if mkCtrl in Event.ModifiersDown then
        Frame.ViewportViewAxis(Vector3(0, 0, 1), Vector3(0, 1, 0))
      else
        Frame.ViewportViewAxis(Vector3(0, 0, -1), Vector3(0, 1, 0));
      Exit(true);
    end else
    if (Event.Key = keyNumpad3) or ((Event.Key = key3) and (mkAlt in Event.ModifiersDown)) then
    begin
      if mkCtrl in Event.ModifiersDown then
        Frame.ViewportViewAxis(Vector3(1, 0, 0), Vector3(0, 1, 0))
      else
        Frame.ViewportViewAxis(Vector3(-1, 0, 0), Vector3(0, 1, 0));
      Exit(true);
    end else
    if (Event.Key = keyNumpad5) or ((Event.Key = key5) and (Event.ModifiersDown = [mkAlt])) then
    begin
      Frame.ViewportToggleProjection;
      Exit(true);
    end;
  end;

  if (Frame.Mode <> moInteract) and (Event.EventType = itKey) and
     (Event.Key in [key0..key9]) and
     (not (buttonRight in Frame.CastleControl.Container.MousePressed)) then
  begin
    BookmarkSlot := Ord(Event.Key) - Ord(key0);
    if Event.ModifiersDown = [mkCtrl] then
    begin
      Frame.SaveCameraBookmark(BookmarkSlot);
      Exit(true);
    end else
    if (Event.ModifiersDown = []) and Frame.FCameraBookmarks[BookmarkSlot].Valid then
    begin
      Frame.RecallCameraBookmark(BookmarkSlot);
      Exit(true);
    end;
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyH) and
     (not (buttonRight in Frame.CastleControl.Container.MousePressed)) then
  begin
    if Event.ModifiersDown = [] then
    begin
      Frame.ToggleSelectedVisibility;
      Exit(true);
    end else
    if Event.ModifiersDown = [mkShift] then
    begin
      Frame.IsolateSelected;
      Exit(true);
    end else
    if Event.ModifiersDown = [mkAlt] then
    begin
      Frame.ShowAllHidden;
      Exit(true);
    end;
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyG) then
  begin
    if Event.ModifiersDown = [mkCtrl] then
    begin
      Frame.GroupSelectedTransforms;
      Exit(true);
    end else
    if Event.ModifiersDown = [mkCtrl, mkShift] then
    begin
      Frame.UngroupSelectedTransforms;
      Exit(true);
    end;
  end;

  if (Frame.Mode <> moInteract) and Event.IsKey(keyBackQuote) and
     (Event.ModifiersDown = [mkCtrl]) then
  begin
    Frame.ToggleCoordSpace;
    Exit(true);
  end;

  if (Frame.Mode <> moInteract) and (Event.ModifiersDown = []) then
  begin
    if Event.IsKey(keyLeftBracket) then
    begin
      Frame.AdjustCameraSpeed(1.0 / 1.5);
      Exit(true);
    end else
    if Event.IsKey(keyRightBracket) then
    begin
      Frame.AdjustCameraSpeed(1.5);
      Exit(true);
    end;
  end;

  if Event.IsKey(keyP) and (Event.ModifiersDown = [mkCtrl]) then
  begin
    Frame.ShowQuickAddPalette;
    Exit(true);
  end;

  { Avoid handling mouse events over CameraPreview, to avoid messing with clicking
    on CameraPreview buttons, and using gizmos in CameraPreview viewport. }
  if Frame.CameraPreview.UiRoot.Exists and
     Frame.CameraPreview.UiRoot.RenderRectWithBorder.Contains(Event.Position) then
    Exit;

  if Event.IsMouseButton(buttonLeft) then
  begin
    { Below we will always calculate correct UiDraggingMode }
    UiDraggingMode := dmNone;
    MarqueeActive := false;

    if Frame.Mode <> moInteract then
    begin
      if [mkCtrl, mkAlt] <= Event.ModifiersDown then
      begin
        UiDraggingMode := dmMarquee;
        MarqueeStartPos := Event.Position;
        MarqueeCurrentPos := Event.Position;
        Exit(true);
      end;

      { Calculate Frame.SelectedComponent.
        Without shift pressed, we select before moving/resizing.
        With shift pressed we don't change selection.
        This allows to change the component without changing the selected component. }
      if (not (mkShift in Event.ModifiersDown)) then
      begin
        SetSelection(HoverComponent(Event.Position), mkCtrl in Event.ModifiersDown);
      end;

      if Frame.Mode = moSelect then
      begin
        UiDraggingMode := dmMarquee;
        MarqueeStartPos := Event.Position;
        MarqueeCurrentPos := Event.Position;
        Exit(true);
      end else
      begin
        UI := Frame.SelectedUserInterface;
        if (UI <> nil) and (not Frame.IsComponentLocked(UI)) then
        begin
          if IsResizing(UI, Event.Position, ResizingHorizontal, ResizingVertical) then
            UiDraggingMode := dmResize
          else
            UiDraggingMode := dmTranslate;

          { Note: No need for this Exit(true) when UI = nil.
            In particular if we selected TCastleTransform, we should not do Exit(true),
            to allow gizmos to start dragging. }
          Exit(true);
        end;
      end;

      UiPendingMove := TVector2.Zero;
    end;
  end;
end;

function TDesignFrame.TDesignerLayer.Release(const Event: TInputPressRelease): Boolean;
var
  Sel: TComponent;
  MarqueeRect: TFloatRectangle;
begin
  Result := inherited Press(Event);
  if Result then Exit;

  { Avoid handling mouse events over CameraPreview, to avoid messing with clicking
    on CameraPreview buttons, and using gizmos in CameraPreview viewport. }
  if Frame.CameraPreview.UiRoot.Exists and
     Frame.CameraPreview.UiRoot.RenderRectWithBorder.Contains(Event.Position) then
    Exit;

  if Event.IsMouseButton(buttonLeft) then
  begin
    if (UiDraggingMode = dmMarquee) and MarqueeActive then
    begin
      MarqueeRect := FloatRectangle(
        Min(MarqueeStartPos.X, MarqueeCurrentPos.X),
        Min(MarqueeStartPos.Y, MarqueeCurrentPos.Y),
        Abs(MarqueeCurrentPos.X - MarqueeStartPos.X),
        Abs(MarqueeCurrentPos.Y - MarqueeStartPos.Y));
      SelectComponentsInMarquee(MarqueeRect, mkShift in Event.ModifiersDown);
      UiDraggingMode := dmNone;
      MarqueeActive := false;
      Exit(true);
    end;

    UiDraggingMode := dmNone;
    MarqueeActive := false;

    { Note, that we may want to have better comment message here }
    if Frame.UndoSystem.ScheduleRecordUndoOnRelease then
    begin
      Sel := Frame.GetSelectedComponent;
      if Sel <> nil then
        Frame.RecordUndo('Drag''n''drop ' + Sel.Name, ucHigh)
      else
        Frame.RecordUndo('Drag''n''drop', ucHigh);
    end;
  end;
end;

function TDesignFrame.TDesignerLayer.Motion(const Event: TInputMotion): Boolean;

  { Grow the rectangle from the appropriate sides, following
    ResizingHorizontal/Vertical field values. }
  function ResizeRect(const R: TFloatRectangle; const Move: TVector2): TFloatRectangle;
  begin
    Result := R;
    case ResizingHorizontal of
      hpLeft : Result := Result.GrowLeft(-Move.X);
      hpRight: Result := Result.GrowRight(Move.X);
      else ;
    end;
    case ResizingVertical of
      vpBottom: Result := Result.GrowBottom(-Move.Y);
      vpTop   : Result := Result.GrowTop(Move.Y);
      else ;
    end;
  end;

  function DragAllowed(const UI: TCastleUserInterface; const Move: TVector2): Boolean;
  var
    CurrentRect, ResultingRect, ParentR: TFloatRectangle;
  begin
    CurrentRect := UI.RenderRectWithBorder;
    case UiDraggingMode of
      dmTranslate: ResultingRect := CurrentRect.Translate(Move);
      dmResize   : ResultingRect := ResizeRect(CurrentRect, Move);
    end;
    ParentR := ParentRenderRect(UI);
    { Only allow movement/resize if control will not go outside of parent,
      unless it was already outside.

      Note that we limit to the parent rect *without border*,
      that is: we don't allow to move control over a border of the parent.
      This makes sense, since FullSize and WidthFraction = 1 keep the control
      within the parent rect *without border* too.
    }
    Result := (not ParentR.Contains(CurrentRect)) or
      ParentR.Contains(ResultingRect);
  end;

  procedure ApplyDrag(const UI: TCastleUserInterface; X, Y: Single);
  const
    MinWidth  = 10;
    MinHeight = 10;
  begin
    if not DragAllowed(UI, Vector2(X, Y)) then Exit;
    case UiDraggingMode of
      dmTranslate:
        begin
          UI.Translation := UI.Translation + Vector2(X, Y);
        end;
      dmResize:
        begin
          case ResizingHorizontal of
            hpLeft:
              begin
                // do not allow to set UI.Width < MinWidth, by limiting X
                if UI.Width - X < MinWidth then
                  X := UI.Width - MinWidth;
                UI.Width := UI.Width - X;

                case UI.HorizontalAnchorSelf of
                  hpLeft  : UI.Translation := UI.Translation + Vector2(X, 0);
                  hpMiddle: UI.Translation := UI.Translation + Vector2(X / 2, 0);
                  //hpRight : UI.Translation := no need to change
                  else ;
                end;
              end;
            hpRight:
              begin
                // do not allow to set UI.Width < MinWidth, by limiting X
                if UI.Width + X < MinWidth then
                  X := MinWidth - UI.Width;
                UI.Width := UI.Width + X;

                case UI.HorizontalAnchorSelf of
                  // hpLeft  : UI.Translation := no need to change
                  hpMiddle: UI.Translation := UI.Translation + Vector2(X / 2, 0);
                  hpRight : UI.Translation := UI.Translation + Vector2(X, 0);
                  else ;
                end;
              end;
          end;
          case ResizingVertical of
            vpBottom:
              begin
                // do not allow to set UI.Height < MinHeight, by limiting Y
                if UI.Height - Y < MinHeight then
                  Y := UI.Height - MinHeight;
                UI.Height := UI.Height - Y;

                case UI.VerticalAnchorSelf of
                  vpBottom: UI.Translation := UI.Translation + Vector2(0, Y);
                  vpMiddle: UI.Translation := UI.Translation + Vector2(0, Y / 2);
                  //vpTop : UI.Translation := no need to change
                end;
              end;
            vpTop:
              begin
                // do not allow to set UI.Height < MinHeight, by limiting Y
                if UI.Height + Y < MinHeight then
                  Y := MinHeight - UI.Height;
                UI.Height := UI.Height + Y;

                case UI.VerticalAnchorSelf of
                  //vpBottom: UI.Translation := no need to change
                  vpMiddle: UI.Translation := UI.Translation + Vector2(0, Y / 2);
                  vpTop   : UI.Translation := UI.Translation + Vector2(0, Y);
                end;
              end;
          end;
        end;
      else ;
    end;

    { We pass UndoOnRelease = true to defer recording Undo until Release is called
      to avoid recording Undo on every user Motion event.
      In this case UndoComment and UndoPriority do not matter,
      they will be replaced by appropriate values on Release. }
    Frame.ModifiedOutsideObjectInspector('', ucLow, true); // UndoComment doesn't matter here
  end;

  function ResizingCursor(const H: THorizontalPosition;
    const V: TVerticalPosition): TMouseCursor;
  begin
    case H of
      hpLeft:
        case V of
          vpBottom: Result := mcResizeBottomLeft;
          vpMiddle: Result := mcResizeLeft;
          vpTop   : Result := mcResizeTopLeft;
        end;
      hpMiddle:
        case V of
          vpBottom: Result := mcResizeBottom;
          vpMiddle: raise EInternalError.Create('No resizing, cannot determine cursor');
          vpTop   : Result := mcResizeTop;
        end;
      hpRight:
        case V of
          vpBottom: Result := mcResizeBottomRight;
          vpMiddle: Result := mcResizeRight;
          vpTop   : Result := mcResizeTopRight;
        end;
    end;
  end;

  procedure UpdateCursor;
  var
    WouldResizeHorizontal: THorizontalPosition;
    WouldResizeVertical: TVerticalPosition;
    NewCursor: TMouseCursor;
    Hint: String;
    HoverC: TCastleComponent;
  begin
    Hint := '';
    if Frame.Mode = moInteract then
      NewCursor := mcDefault
    else
    case UiDraggingMode of
      dmNone:
        begin
          // calculate cursor based on what would happen if you Press
          HoverC := HoverComponent(Event.Position);
          if HoverC is TCastleUserInterface then
          begin
            if IsResizing(HoverC as TCastleUserInterface, Event.Position,
              WouldResizeHorizontal, WouldResizeVertical, Hint) then
            begin
              NewCursor := ResizingCursor(
                WouldResizeHorizontal, WouldResizeVertical);
            end else
              NewCursor := mcHand;
          end else
            NewCursor := mcDefault;
        end;
      dmTranslate:
        NewCursor := mcHand;
      dmResize:
        NewCursor := ResizingCursor(ResizingHorizontal, ResizingVertical);
      dmMarquee:
        NewCursor := mcDefault;
    end;
    Frame.CastleControl.Container.OverrideCursor := NewCursor;
    Frame.CastleControl.Hint := Hint;
    Frame.CastleControl.ShowHint := Hint <> '';
  end;

  procedure UpdateHoverComponent;
  var
    HoverC: TCastleComponent;
  begin
    if Frame.Mode <> moInteract then
    begin
      HoverC := HoverComponent(Event.Position); // may also return nil
      if HoverC is TCastleTransform then
        Frame.TransformHover.Current := TCastleTransform(HoverC)
      else
        Frame.TransformHover.Current := nil;
    end else
      Frame.TransformHover.Current := nil;
  end;

  { Sometimes, trying to drag (translate/resize) UI,
    should actually drag the UI's parent (or parent's parent...).
    This happens when UI has FullSize,
    or it is within a group that auto-aligns children.

    The DragAllowed is such case would block some actions on UI,
    and it is intuitive to perform them on parent.

    TODO: This has hardcoded logic for FullSize and group cases.
    There should be a virtual method instead like
      TCastleUserInterface.EditorDragParent(UiDraggingMode)
      TCastleUserInterface.EditorDragMeInsteadOfChild(UiDraggingMode)
  }
  procedure ChangeDraggedUI(var UI: TCastleUserInterface);
  begin
    if (UiDraggingMode in [dmResize, dmTranslate]) and
       UI.EffectiveFullSize and
       (UI.Parent <> nil) then
    begin
      UI := UI.Parent;
      ChangeDraggedUI(UI); // act recursively if necessary, to choose parent's parent...
    end;

    if (UiDraggingMode in [dmResize, dmTranslate]) and
       (UI.Parent <> nil) and
       { When the parent uses AutoSizeToChildren on a single child, then the effect is similar
         as it child had FullSize. }
       UI.Parent.AutoSizeToChildren and
       (UI.Parent.ControlsCount = 1) and
       {$warnings off} // looking at deprecated Left, Bottom to keep them working
       (UI.Left = 0) and
       (UI.Bottom = 0) and
       {$warnings on}
       TVector2.PerfectlyEquals(UI.Translation, TVector2.Zero) then
    begin
      UI := UI.Parent;
      ChangeDraggedUI(UI); // act recursively if necessary, to choose parent's parent...
    end;

    if (UiDraggingMode in [dmTranslate]) and
       (UI.Parent <> nil) and
       ( (UI.Parent is TCastleHorizontalGroup) or
         (UI.Parent is TCastleVerticalGroup) ) then
    begin
      UI := UI.Parent;
      ChangeDraggedUI(UI); // act recursively if necessary, to choose parent's parent...
    end;
  end;

var
  UI: TCastleUserInterface;
  Move: TVector2;
  Snap: Single;
begin
  Result := inherited Motion(Event);
  if Result then Exit;

  { Avoid handling mouse events over CameraPreview, to avoid messing with clicking
    on CameraPreview buttons, and using gizmos in CameraPreview viewport. }
  if Frame.CameraPreview.UiRoot.Exists and
     Frame.CameraPreview.UiRoot.RenderRectWithBorder.Contains(Event.Position) then
    Exit;

  { in case user released mouse button, but the event didn't reach us for some reason
    (maybe can happen e.g. if you Alt+Tab during dragging?),
    reset UiDraggingMode. }
  if (UiDraggingMode <> dmNone) and
     (not (buttonLeft in Event.Pressed)) then
  begin
    UiDraggingMode := dmNone;
    MarqueeActive := false;
  end;

  if (Frame.Mode <> moInteract) and
     (UiDraggingMode = dmMarquee) then
  begin
    MarqueeCurrentPos := Event.Position;
    if PointsDistance(MarqueeStartPos, MarqueeCurrentPos) >= 4 then
      MarqueeActive := true;
    Exit(true);
  end;

  if (Frame.Mode <> moInteract) and
     (UiDraggingMode <> dmNone) then
  begin
    UI := Frame.SelectedUserInterface;
    if (UI <> nil) and (not Frame.IsComponentLocked(UI)) then
    begin
      ChangeDraggedUI(UI);

      Move := (Event.Position - Event.OldPosition) / UI.UIScale;

      Snap := Frame.SpinEditSnap.Value;
      if Snap <> 0 then
      begin
        UiPendingMove += Move;
        while Abs(UiPendingMove.X) >= Snap do
        begin
          ApplyDrag(UI, Sign(UiPendingMove.X) * Snap, 0);
          UiPendingMove.X := UiPendingMove.X - Sign(UiPendingMove.X) * Snap;
        end;
        while Abs(UiPendingMove.Y) >= Snap do
        begin
          ApplyDrag(UI, 0, Sign(UiPendingMove.Y) * Snap);
          UiPendingMove.Y := UiPendingMove.Y - Sign(UiPendingMove.Y) * Snap;
        end;
      end else
      begin
        ApplyDrag(UI, Move.X, Move.Y);
      end;

      Exit(true);
    end;
  end;

  { Note: We do this regardless if some TCastleWalkNavigationDesign
    now uses mouse look (so user right-clicked on some viewport).
    When mouse look is used, it overrides cursor by Container.FInternalOverrideCursor,
    which takes precedence over Container.OverrideCursor so we don't need
    to worry about it. }
  UpdateCursor;

  UpdateHoverComponent;
end;

procedure TDesignFrame.TDesignerLayer.Render;

  procedure UpdateAttachedLabel(const UI: TCastleUserInterface;
    const UIRect: TFloatRectangle;
    const Lab: TCastleLabel; const Rect: TCastleRectangleControl;
    const LabelColor: TCastleColor);
  begin
    { Show additional UI to show selected UI.
      While these labels can be helpful, they often obscure important UI
      (even the one you're trying to edit) so it is also causing trouble.

      After some experimenting, we only show them on components with zero size.
      This allows to e.g. know where is new TCastleVertical/HorizontalGroup
      (as it is selected right after addition, and has zero size since has
      no children, and AutoSize=true).
    }
    if (UI <> nil) and
       (
         (UI.EffectiveWidth = 0) or
         (UI.EffectiveHeight = 0)
       ) then
    begin
      Lab.Caption := Frame.ComponentCaption(UI);
      Lab.Color := LabelColor;

      Rect.Exists := true;
      Rect.Width := Lab.EffectiveWidth + 6;
      Rect.Height := Lab.EffectiveHeight + 6;
      { Place in left-top corner. Because:
        - We want left-xxx corner, this way if the label is cut off,
          at least the beginning looks OK.
        - We don't want left-bottom corner, as that's where child controls
          are placed by default, so the text would be over them too often. }
      Rect.Anchor(hpLeft, Max(0, UIRect.Left));
      Rect.Anchor(vpBottom, UIRect.Top);

      if Rect.RenderRect.Top > Rect.Container.PixelsHeight then
        // put Rect inside UI, otherwise it would be offscreen
        Rect.Anchor(vpTop, vpBottom, Min(Rect.Container.PixelsHeight, UIRect.Top));
    end else
      Rect.Exists := false;
  end;

  function StatisticsToString: String;
  var
    ViewModeStr, SpaceStr, SpeedStr: String;
    T: TCastleTransform;
    BBox: TBox3D;
    SelDelta: TVector3;
    SelDist: Single;
  begin
    if InternalForceWireframe = weWireframeOnly then
      ViewModeStr := 'Wireframe'
    else if InternalForceWireframe = weSolidWireframe then
      ViewModeStr := 'Solid Wireframe'
    else if InternalForceUnlit then
      ViewModeStr := 'Unlit'
    else
      ViewModeStr := 'Lit';

    if (Frame.TransformManipulate <> nil) and (Frame.TransformManipulate.CoordSpace = csWorld) then
      SpaceStr := 'World'
    else
      SpaceStr := 'Local';

    if (Frame.CurrentViewport <> nil) and
       (Frame.CurrentViewport.InternalDesignNavigation is TCastleWalkNavigation) then
      SpeedStr := Format(' | Cam Speed: %.2f', [
        TCastleWalkNavigation(Frame.CurrentViewport.InternalDesignNavigation).MoveSpeed])
    else
      SpeedStr := '';

    Result := 'FPS: ' + Container.Fps.ToString + NL +
      Format('Render: %s | Space: %s | Selected: %d%s', [
        ViewModeStr, SpaceStr, Frame.ControlsTree.SelectionCount, SpeedStr]);

    if Frame.CurrentViewport <> nil then
      Result := Result + NL +
        'Viewport "' + Frame.CurrentViewport.Name + '":' + NL +
        Frame.CurrentViewport.Statistics.ToString;

    T := Frame.CurrentTransform;
    if T <> nil then
    begin
      BBox := T.WorldBoundingBox;
      Result := Result + NL +
        Format('Active Transform "%s":', [T.Name]) + NL +
        Format('  World Pos: %s', [T.WorldTranslation.ToString]);
      if not BBox.IsEmpty then
        Result := Result + NL +
          Format('  World BBox Size: %s', [BBox.Size.ToString]);
    end;

    if (Frame.TransformManipulate <> nil) and (Frame.TransformManipulate.SelectedCount >= 2) then
    begin
      SelDist := Frame.TransformManipulate.MeasureSelectedDistance(SelDelta);
      Result := Result + NL +
        Format('Ruler (Sel[0]->Sel[1]): %.3f (dX=%.2f, dY=%.2f, dZ=%.2f)', [
          SelDist, SelDelta.X, SelDelta.Y, SelDelta.Z]);
    end;

    if Frame.FMeasureActive then
      Result := Result + NL +
        Format('Measured Ray (M): %.3f (dX=%.2f, dY=%.2f, dZ=%.2f)', [
          Frame.FMeasureDistance,
          Frame.FMeasureDelta.X, Frame.FMeasureDelta.Y, Frame.FMeasureDelta.Z]);
  end;

var
  SelectedUI, HoverUI: TCastleUserInterface;
  SelectedUIRect, HoverUIRect, MarqueeRect: TFloatRectangle;
  V: TCastleViewport;
  CamPos, CamDir, CamUp: TVector3;
  ScreenStart, ScreenEnd: TVector2;
begin
  inherited;

  SelectedUI := Frame.SelectedUserInterface;
  if SelectedUI <> nil then
  begin
    SelectedUIRect := SelectedUI.RenderRectWithBorder;
    DrawRectangleOutline(SelectedUIRect, White);
    DrawRectangleOutline(SelectedUIRect.Grow(-1), Black);
  end;

  HoverUI := HoverUserInterface(Container.MousePosition);
  if HoverUI <> nil then
  begin
    HoverUIRect := HoverUI.RenderRectWithBorder;
    DrawRectangleOutline(HoverUIRect, Vector4(1, 1, 0, 0.75));
  end;

  if (HoverUI <> nil) and (HoverUI = SelectedUI) then
  begin
    UpdateAttachedLabel(SelectedUI, SelectedUIRect, LabelSelected, RectSelected,
      ColorHoverAndSelected);
    // make sure to hide RectHover in this case
    UpdateAttachedLabel(nil, TFloatRectangle.Empty, LabelHover, RectHover, Black);
  end else
  begin
    UpdateAttachedLabel(SelectedUI, SelectedUIRect, LabelSelected, RectSelected,
      ColorSelected);
    UpdateAttachedLabel(HoverUI, HoverUIRect, LabelHover, RectHover,
      ColorHover);

    { Improve special case, when both RectSelected and RectHover would
      be displayed on top of each other. In this case,
      shift the RectHover (as the more often changing one). }
    if RectSelected.Exists and
       RectHover.Exists and
       (RectSelected.RenderRect.Bottom = RectHover.RenderRect.Bottom) and
       (RectSelected.RenderRect.Left   = RectHover.RenderRect.Left  ) then
    begin
      RectHover.Translation := RectHover.Translation - Vector2(0, RectSelected.EffectiveHeight);
    end;
  end;

  if (UiDraggingMode = dmMarquee) and MarqueeActive then
  begin
    MarqueeRect := FloatRectangle(
      Min(MarqueeStartPos.X, MarqueeCurrentPos.X),
      Min(MarqueeStartPos.Y, MarqueeCurrentPos.Y),
      Abs(MarqueeCurrentPos.X - MarqueeStartPos.X),
      Abs(MarqueeCurrentPos.Y - MarqueeStartPos.Y));
    DrawRectangle(MarqueeRect, Vector4(0.2, 0.6, 1.0, 0.2));
    DrawRectangleOutline(MarqueeRect, Vector4(0.4, 0.8, 1.0, 0.9));
  end;

  if Frame.FMeasureActive and (Frame.CurrentViewport <> nil) and
     (Frame.CurrentViewport.InternalCamera <> nil) then
  begin
    V := Frame.CurrentViewport;
    V.InternalCamera.GetWorldView(CamPos, CamDir, CamUp);
    if (V.InternalCamera.ProjectionType = ptOrthographic) or
       (TVector3.DotProduct(Frame.FMeasureStartWorld - CamPos, CamDir) > 0) then
    begin
      ScreenStart := V.LocalToContainerPosition(V.PositionFromWorld(Frame.FMeasureStartWorld));
      DrawRectangle(FloatRectangle(ScreenStart.X - 4, ScreenStart.Y - 4, 8, 8),
        Vector4(0.1, 1.0, 0.9, 0.95));
    end;
    if (V.InternalCamera.ProjectionType = ptOrthographic) or
       (TVector3.DotProduct(Frame.FMeasureEndWorld - CamPos, CamDir) > 0) then
    begin
      ScreenEnd := V.LocalToContainerPosition(V.PositionFromWorld(Frame.FMeasureEndWorld));
      DrawRectangle(FloatRectangle(ScreenEnd.X - 4, ScreenEnd.Y - 4, 8, 8),
        Vector4(1.0, 0.85, 0.1, 0.95));
    end;
  end;

  RectStatistics.Exists := Frame.EffectiveShowStatistics;
  if RectStatistics.Exists then
  begin
    LabelStatistics.Caption := StatisticsToString;
  end;
end;

{ TDesignFrame --------------------------------------------------------------- }

constructor TDesignFrame.Create(TheOwner: TComponent);

  function CommonInspectorCreate: TCastleObjectInspector;
  begin
    Result := TCastleObjectInspector.Create(Self);
    Result.PropertyEditorHook := PropertyEditorHook;
    Result.Align := alClient;
    Result.OnModified := @PropertyGridModified;
    Result.CheckboxForBoolean := true;
    Result.PreferredSplitterX := 150;
    Result.ValueFont.Bold := true;
    Result.ShowGutter := false;
    Result.ReadOnlyColor := clWindowText;

    if UseIconsAndColorsForDarkTheme then
    begin
      Result.GutterColor := $9EFFFF;
      Result.ValueFont.Color := $9EFFFF;
      Result.SubPropertiesColor := clWindowText;
      Result.ReferencesColor := $9EFFFF;
    end;
  end;
begin
  inherited;

  LastSelected := TComponentList.Create(false);
  FLockedComponents := TComponentList.Create(false);

  PropertyEditorHook := TCastlePropertyEditorHook.Create(Self);

  FComponentEditorDesigner := TConcreteEditorDesigner.Create(Self, PropertyEditorHook);

  FUndoSystem := TUndoSystem.Create(Self);

  Inspector[itBasic] := CommonInspectorCreate;
  Inspector[itBasic].Parent := TabBasic;
  Inspector[itBasic].OnEditorFilter := @InspectorBasicFilter;
  Inspector[itBasic].Filter := tkProperties;

  Inspector[itLayout] := CommonInspectorCreate;
  Inspector[itLayout].Parent := TabLayout;
  Inspector[itLayout].OnEditorFilter := @InspectorLayoutFilter;
  Inspector[itLayout].Filter := tkProperties;
  Inspector[itLayout].Align := alBottom;
  Inspector[itLayout].AnchorToNeighbour(akTop, 0, PanelLayoutTop);

  Inspector[itAll] := CommonInspectorCreate;
  Inspector[itAll].OnEditorFilter := @InspectorAllFilter;
  Inspector[itAll].Parent := TabAll;
  Inspector[itAll].Filter := tkProperties;

  Inspector[itEvents] := CommonInspectorCreate;
  Inspector[itEvents].Parent := TabEvents;
  Inspector[itEvents].Filter := tkMethods;
  Inspector[itEvents].AnchorToNeighbour(akTop, 0, PanelEventsInfo);

  CastleControl := TCastleControl.Create(Self);
  CastleControl.AutoFocus := true; // needed on Windows to receive AWSD, Ctrl+Z...
  CastleControl.Align := alClient;
  CastleControl.OnDragOver := @CastleControlDragOver;
  CastleControl.OnDragDrop := @CastleControlDragDrop;
  CastleControl.Parent := PanelMiddle; // set Parent last, following https://wiki.freepascal.org/LCL_Tips#Set_the_Parent_as_last

  {$ifdef DEBUG_GIZMO_PICK}
  TCastleControl.MainControl := CastleControl;
  {$endif DEBUG_GIZMO_PICK}

  FDesignerLayer := TDesignerLayer.Create(Self);
  FDesignerLayer.Frame := Self;
  FDesignerLayer.OnUpdate := @CastleControlUpdate;
  FDesignerLayer.OnGLContextOpen := @CastleControlGLContextOpen;
  CastleControl.Controls.InsertFront(FDesignerLayer);

  // It's too easy to change it visually and forget, so we set it from code
  ControlProperties.ActivePage := TabBasic;

  TreeNodeMap := TTreeNodeMap.Create;

  SelfAnchorsFrame.OnAnchorChange := @FrameAnchorsChange;
  ParentAnchorsFrame.OnAnchorChange := @FrameAnchorsChange;

  TransformHover := TCastleTransformHover.Create(Self);
  TransformManipulate := TCastleTransformManipulate.Create(Self);
  TransformManipulate.OnTransformModifyBegin := @GizmoTransformModifyBegin;
  TransformManipulate.OnTransformModified := @GizmoTransformModified;
  TransformManipulate.OnTransformModifyEnd := @GizmoTransformModifyEnd;

  ButtonCoordSpace := TSpeedButton.Create(Self);
  ButtonCoordSpace.Caption := 'Local';
  ButtonCoordSpace.Hint := 'Toggle 3D gizmo coordinate space between Local and World (Shortcut: Ctrl+~)';
  ButtonCoordSpace.ShowHint := true;
  ButtonCoordSpace.AutoSize := true;
  ButtonCoordSpace.Constraints.MinHeight := 33;
  ButtonCoordSpace.Constraints.MinWidth := 54;
  ButtonCoordSpace.BorderSpacing.Left := 8;
  ButtonCoordSpace.OnClick := @ButtonCoordSpaceClick;
  ButtonCoordSpace.Parent := PanelMiddleTop;

  ButtonPivotMode := TSpeedButton.Create(Self);
  ButtonPivotMode.Caption := 'Pivot: Primary';
  ButtonPivotMode.Hint := 'Toggle multi-selection rotation pivot between Primary Selected object and Selection Center';
  ButtonPivotMode.ShowHint := true;
  ButtonPivotMode.AutoSize := true;
  ButtonPivotMode.Constraints.MinHeight := 33;
  ButtonPivotMode.Constraints.MinWidth := 82;
  ButtonPivotMode.BorderSpacing.Left := 4;
  ButtonPivotMode.OnClick := @ButtonPivotModeClick;
  ButtonPivotMode.Parent := PanelMiddleTop;

  LabelHeader3DSnap := TLabel.Create(Self);
  LabelHeader3DSnap.Caption := '3D snap:';
  LabelHeader3DSnap.Layout := tlCenter;
  LabelHeader3DSnap.BorderSpacing.Left := 8;
  LabelHeader3DSnap.BorderSpacing.Right := 4;
  LabelHeader3DSnap.Parent := PanelMiddleTop;

  PanelSpinEditSnap3D := TPanel.Create(Self);
  PanelSpinEditSnap3D.AutoSize := true;
  PanelSpinEditSnap3D.BevelOuter := bvNone;
  PanelSpinEditSnap3D.BorderSpacing.CellAlignHorizontal := ccaCenter;
  PanelSpinEditSnap3D.BorderSpacing.CellAlignVertical := ccaCenter;
  PanelSpinEditSnap3D.Parent := PanelMiddleTop;

  SpinEditSnap3D := TFloatSpinEdit.Create(Self);
  SpinEditSnap3D.DecimalPlaces := 2;
  SpinEditSnap3D.Increment := 0.5;
  SpinEditSnap3D.MinValue := 0;
  SpinEditSnap3D.MaxValue := 1000;
  SpinEditSnap3D.Value := 0;
  SpinEditSnap3D.Width := 68;
  SpinEditSnap3D.Hint := '3D Gizmo Snap step (0 = disabled). Snaps 3D translation units, rotation degrees (or 15 deg when <= 1), and scale increments.';
  SpinEditSnap3D.ShowHint := true;
  SpinEditSnap3D.OnChange := @SpinEditSnap3DChange;
  SpinEditSnap3D.Parent := PanelSpinEditSnap3D;

  ButtonViewMode := TSpeedButton.Create(Self);
  ButtonViewMode.Caption := 'View: Lit';
  ButtonViewMode.Hint := 'Cycle viewport rendering mode: Lit -> Unlit -> Wireframe -> Solid Wireframe (Ctrl+T)';
  ButtonViewMode.ShowHint := true;
  ButtonViewMode.AutoSize := true;
  ButtonViewMode.Constraints.MinHeight := 33;
  ButtonViewMode.Constraints.MinWidth := 68;
  ButtonViewMode.BorderSpacing.Left := 8;
  ButtonViewMode.OnClick := @ButtonViewModeClick;
  ButtonViewMode.Parent := PanelMiddleTop;
  UpdateViewModeButtonCaption;

  ButtonShowStats := TSpeedButton.Create(Self);
  ButtonShowStats.Caption := 'Stats';
  ButtonShowStats.Hint := 'Toggle real-time Viewport Statistics HUD overlay (FPS, Draw Calls, Shapes, Active Transform Info)';
  ButtonShowStats.ShowHint := true;
  ButtonShowStats.AllowAllUp := true;
  ButtonShowStats.GroupIndex := 901;
  ButtonShowStats.AutoSize := true;
  ButtonShowStats.Constraints.MinHeight := 33;
  ButtonShowStats.Constraints.MinWidth := 48;
  ButtonShowStats.BorderSpacing.Left := 4;
  ButtonShowStats.OnClick := @ButtonShowStatsClick;
  ButtonShowStats.Parent := PanelMiddleTop;

  ButtonShowColliders := TSpeedButton.Create(Self);
  ButtonShowColliders.Caption := 'Colliders';
  ButtonShowColliders.Hint := 'Toggle physics collider wireframe visualization in viewport';
  ButtonShowColliders.ShowHint := true;
  ButtonShowColliders.AllowAllUp := true;
  ButtonShowColliders.GroupIndex := 902;
  ButtonShowColliders.AutoSize := true;
  ButtonShowColliders.Constraints.MinHeight := 33;
  ButtonShowColliders.Constraints.MinWidth := 62;
  ButtonShowColliders.BorderSpacing.Left := 4;
  ButtonShowColliders.OnClick := @ButtonShowCollidersClick;
  ButtonShowColliders.Parent := PanelMiddleTop;

  ButtonQuickAdd := TSpeedButton.Create(Self);
  ButtonQuickAdd.Caption := '+ Add';
  ButtonQuickAdd.Hint := 'Open Quick-Add Component Palette (Shortcut: Ctrl+P in viewport)';
  ButtonQuickAdd.ShowHint := true;
  ButtonQuickAdd.AutoSize := true;
  ButtonQuickAdd.Constraints.MinHeight := 33;
  ButtonQuickAdd.Constraints.MinWidth := 52;
  ButtonQuickAdd.BorderSpacing.Left := 8;
  ButtonQuickAdd.OnClick := @ButtonQuickAddClick;
  ButtonQuickAdd.Parent := PanelMiddleTop;

  ButtonSimulationStep := TSpeedButton.Create(Self);
  ButtonSimulationStep.Caption := 'Step';
  ButtonSimulationStep.Hint := 'Advance physics simulation by a single frame (1/60s)';
  ButtonSimulationStep.ShowHint := true;
  ButtonSimulationStep.AutoSize := true;
  ButtonSimulationStep.Constraints.MinHeight := 33;
  ButtonSimulationStep.Constraints.MinWidth := 46;
  ButtonSimulationStep.BorderSpacing.Left := 4;
  ButtonSimulationStep.Visible := false;
  ButtonSimulationStep.OnClick := @ButtonSimulationStepClick;
  ButtonSimulationStep.Parent := PanelMiddleTop;

  ButtonKeepSimulation := TSpeedButton.Create(Self);
  ButtonKeepSimulation.Caption := 'Keep Sim';
  ButtonKeepSimulation.Hint := 'Stop physics simulation and keep the simulated Transform positions/rotations in the design';
  ButtonKeepSimulation.ShowHint := true;
  ButtonKeepSimulation.AutoSize := true;
  ButtonKeepSimulation.Constraints.MinHeight := 33;
  ButtonKeepSimulation.Constraints.MinWidth := 68;
  ButtonKeepSimulation.BorderSpacing.Left := 4;
  ButtonKeepSimulation.Visible := false;
  ButtonKeepSimulation.OnClick := @ButtonKeepSimulationClick;
  ButtonKeepSimulation.Parent := PanelMiddleTop;

  ButtonSnapToFloor := TButton.Create(Self);
  ButtonSnapToFloor.AutoSize := true;
  ButtonSnapToFloor.Caption := 'Snap to Floor (End)';
  ButtonSnapToFloor.Hint := 'Snap selected 3D transform(s) downward onto the nearest floor surface (Shortcut: End)';
  ButtonSnapToFloor.ShowHint := true;
  ButtonSnapToFloor.OnClick := @ButtonSnapToFloorClick;
  ButtonSnapToFloor.Parent := PanelLayoutTransform;

  ButtonSnapToFloorNormal := TButton.Create(Self);
  ButtonSnapToFloorNormal.AutoSize := true;
  ButtonSnapToFloorNormal.Caption := 'Snap + Normal (Alt+End)';
  ButtonSnapToFloorNormal.Hint := 'Snap selected 3D transform(s) onto the floor surface and align local +Y Up to the surface normal (Shortcut: Alt+End)';
  ButtonSnapToFloorNormal.ShowHint := true;
  ButtonSnapToFloorNormal.OnClick := @ButtonSnapToFloorNormalClick;
  ButtonSnapToFloorNormal.Parent := PanelLayoutTransform;

  ButtonSnapToGrid := TButton.Create(Self);
  ButtonSnapToGrid.AutoSize := true;
  ButtonSnapToGrid.Caption := 'Snap to Grid (Ctrl+End)';
  ButtonSnapToGrid.Hint := 'Snap absolute Translation of selected 3D transform(s) to nearest 3D Snap grid multiple (Shortcut: Ctrl+End)';
  ButtonSnapToGrid.ShowHint := true;
  ButtonSnapToGrid.OnClick := @ButtonSnapToGridClick;
  ButtonSnapToGrid.Parent := PanelLayoutTransform;

  ButtonMoveTransformToView := TButton.Create(Self);
  ButtonMoveTransformToView.AutoSize := true;
  ButtonMoveTransformToView.Caption := 'Move to View';
  ButtonMoveTransformToView.Hint := 'Snap selected 3D transform (light, scene, camera, spawn point) to the current viewport camera position and orientation';
  ButtonMoveTransformToView.ShowHint := true;
  ButtonMoveTransformToView.OnClick := @ButtonMoveTransformToViewClick;
  ButtonMoveTransformToView.Parent := PanelLayoutTransform;

  ButtonCopyTransform := TButton.Create(Self);
  ButtonCopyTransform.AutoSize := true;
  ButtonCopyTransform.Caption := 'Copy Transform';
  ButtonCopyTransform.Hint := 'Copy Translation, Rotation, and Scale of the selected 3D transform';
  ButtonCopyTransform.ShowHint := true;
  ButtonCopyTransform.OnClick := @ButtonCopyTransformClick;
  ButtonCopyTransform.Parent := PanelLayoutTransform;

  ButtonPasteTransform := TButton.Create(Self);
  ButtonPasteTransform.AutoSize := true;
  ButtonPasteTransform.Caption := 'Paste Transform';
  ButtonPasteTransform.Hint := 'Paste copied Translation, Rotation, and Scale onto all selected 3D transforms';
  ButtonPasteTransform.ShowHint := true;
  ButtonPasteTransform.Enabled := false;
  ButtonPasteTransform.OnClick := @ButtonPasteTransformClick;
  ButtonPasteTransform.Parent := PanelLayoutTransform;

  ButtonAlignX := TButton.Create(Self);
  ButtonAlignX.AutoSize := true;
  ButtonAlignX.Caption := 'Align X';
  ButtonAlignX.Hint := 'Align all selected 3D transforms along the X axis to the primary selected object';
  ButtonAlignX.ShowHint := true;
  ButtonAlignX.Tag := 0;
  ButtonAlignX.OnClick := @ButtonAlignAxisClick;
  ButtonAlignX.Parent := PanelLayoutTransform;

  ButtonAlignY := TButton.Create(Self);
  ButtonAlignY.AutoSize := true;
  ButtonAlignY.Caption := 'Align Y';
  ButtonAlignY.Hint := 'Align all selected 3D transforms along the Y axis to the primary selected object';
  ButtonAlignY.ShowHint := true;
  ButtonAlignY.Tag := 1;
  ButtonAlignY.OnClick := @ButtonAlignAxisClick;
  ButtonAlignY.Parent := PanelLayoutTransform;

  ButtonAlignZ := TButton.Create(Self);
  ButtonAlignZ.AutoSize := true;
  ButtonAlignZ.Caption := 'Align Z';
  ButtonAlignZ.Hint := 'Align all selected 3D transforms along the Z axis to the primary selected object';
  ButtonAlignZ.ShowHint := true;
  ButtonAlignZ.Tag := 2;
  ButtonAlignZ.OnClick := @ButtonAlignAxisClick;
  ButtonAlignZ.Parent := PanelLayoutTransform;

  ButtonDistributeX := TButton.Create(Self);
  ButtonDistributeX.AutoSize := true;
  ButtonDistributeX.Caption := 'Dist X';
  ButtonDistributeX.Hint := 'Evenly distribute 3 or more selected 3D transforms along the X axis';
  ButtonDistributeX.ShowHint := true;
  ButtonDistributeX.Tag := 0;
  ButtonDistributeX.OnClick := @ButtonDistributeAxisClick;
  ButtonDistributeX.Parent := PanelLayoutTransform;

  ButtonDistributeY := TButton.Create(Self);
  ButtonDistributeY.AutoSize := true;
  ButtonDistributeY.Caption := 'Dist Y';
  ButtonDistributeY.Hint := 'Evenly distribute 3 or more selected 3D transforms along the Y axis';
  ButtonDistributeY.ShowHint := true;
  ButtonDistributeY.Tag := 1;
  ButtonDistributeY.OnClick := @ButtonDistributeAxisClick;
  ButtonDistributeY.Parent := PanelLayoutTransform;

  ButtonDistributeZ := TButton.Create(Self);
  ButtonDistributeZ.AutoSize := true;
  ButtonDistributeZ.Caption := 'Dist Z';
  ButtonDistributeZ.Hint := 'Evenly distribute 3 or more selected 3D transforms along the Z axis';
  ButtonDistributeZ.ShowHint := true;
  ButtonDistributeZ.Tag := 2;
  ButtonDistributeZ.OnClick := @ButtonDistributeAxisClick;
  ButtonDistributeZ.Parent := PanelLayoutTransform;

  ButtonStackX := TButton.Create(Self);
  ButtonStackX.AutoSize := true;
  ButtonStackX.Caption := 'Stack X';
  ButtonStackX.Hint := 'Stack 2 or more selected 3D transforms flush edge-to-edge along the X axis using their bounding boxes';
  ButtonStackX.ShowHint := true;
  ButtonStackX.Tag := 0;
  ButtonStackX.OnClick := @ButtonStackAxisClick;
  ButtonStackX.Parent := PanelLayoutTransform;

  ButtonStackY := TButton.Create(Self);
  ButtonStackY.AutoSize := true;
  ButtonStackY.Caption := 'Stack Y';
  ButtonStackY.Hint := 'Stack 2 or more selected 3D transforms flush edge-to-edge along the Y axis using their bounding boxes';
  ButtonStackY.ShowHint := true;
  ButtonStackY.Tag := 1;
  ButtonStackY.OnClick := @ButtonStackAxisClick;
  ButtonStackY.Parent := PanelLayoutTransform;

  ButtonStackZ := TButton.Create(Self);
  ButtonStackZ.AutoSize := true;
  ButtonStackZ.Caption := 'Stack Z';
  ButtonStackZ.Hint := 'Stack 2 or more selected 3D transforms flush edge-to-edge along the Z axis using their bounding boxes';
  ButtonStackZ.ShowHint := true;
  ButtonStackZ.Tag := 2;
  ButtonStackZ.OnClick := @ButtonStackAxisClick;
  ButtonStackZ.Parent := PanelLayoutTransform;

  ButtonMirrorX := TButton.Create(Self);
  ButtonMirrorX.AutoSize := true;
  ButtonMirrorX.Caption := 'Mirror X';
  ButtonMirrorX.Hint := 'Mirror selected 3D transform(s) across the X axis (physics-safe orientation reflection)';
  ButtonMirrorX.ShowHint := true;
  ButtonMirrorX.Tag := 0;
  ButtonMirrorX.OnClick := @ButtonMirrorAxisClick;
  ButtonMirrorX.Parent := PanelLayoutTransform;

  ButtonMirrorY := TButton.Create(Self);
  ButtonMirrorY.AutoSize := true;
  ButtonMirrorY.Caption := 'Mirror Y';
  ButtonMirrorY.Hint := 'Mirror selected 3D transform(s) across the Y axis (physics-safe orientation reflection)';
  ButtonMirrorY.ShowHint := true;
  ButtonMirrorY.Tag := 1;
  ButtonMirrorY.OnClick := @ButtonMirrorAxisClick;
  ButtonMirrorY.Parent := PanelLayoutTransform;

  ButtonMirrorZ := TButton.Create(Self);
  ButtonMirrorZ.AutoSize := true;
  ButtonMirrorZ.Caption := 'Mirror Z';
  ButtonMirrorZ.Hint := 'Mirror selected 3D transform(s) across the Z axis (physics-safe orientation reflection)';
  ButtonMirrorZ.ShowHint := true;
  ButtonMirrorZ.Tag := 2;
  ButtonMirrorZ.OnClick := @ButtonMirrorAxisClick;
  ButtonMirrorZ.Parent := PanelLayoutTransform;

  ButtonRotate90Y := TButton.Create(Self);
  ButtonRotate90Y.AutoSize := true;
  ButtonRotate90Y.Caption := 'Rot 90° Y';
  ButtonRotate90Y.Hint := 'Rotate selected 3D transform(s) by an exact 90-degree step around the Y (Up) axis';
  ButtonRotate90Y.ShowHint := true;
  ButtonRotate90Y.OnClick := @ButtonRotate90YClick;
  ButtonRotate90Y.Parent := PanelLayoutTransform;

  ButtonRandomizeTransform := TButton.Create(Self);
  ButtonRandomizeTransform.AutoSize := true;
  ButtonRandomizeTransform.Caption := 'Randomize';
  ButtonRandomizeTransform.Hint := 'Randomize Yaw rotation (0..360 deg) and uniform Scale (0.85..1.15) of selected 3D transform(s) for level set-dressing';
  ButtonRandomizeTransform.ShowHint := true;
  ButtonRandomizeTransform.OnClick := @ButtonRandomizeTransformClick;
  ButtonRandomizeTransform.Parent := PanelLayoutTransform;

  ButtonArrayDuplicate := TButton.Create(Self);
  ButtonArrayDuplicate.AutoSize := true;
  ButtonArrayDuplicate.Caption := 'Array Dup...';
  ButtonArrayDuplicate.Hint := 'Duplicate selected 3D transform(s) N times with cumulative X/Y/Z offset and Yaw rotation step (Shortcut: Ctrl+Shift+D)';
  ButtonArrayDuplicate.ShowHint := true;
  ButtonArrayDuplicate.OnClick := @ButtonArrayDuplicateClick;
  ButtonArrayDuplicate.Parent := PanelLayoutTransform;

  ButtonRadialDuplicate := TButton.Create(Self);
  ButtonRadialDuplicate.Align := alTop;
  ButtonRadialDuplicate.AutoSize := true;
  ButtonRadialDuplicate.Caption := 'Radial Dup...';
  ButtonRadialDuplicate.Hint := 'Radial / circular array duplicate selected TCastleTransform component(s) around a circle or arc (Ctrl+Alt+D)';
  ButtonRadialDuplicate.ShowHint := true;
  ButtonRadialDuplicate.BorderSpacing.Around := 2;
  ButtonRadialDuplicate.OnClick := @ButtonRadialDuplicateClick;
  ButtonRadialDuplicate.Parent := PanelLayoutTransform;

  ButtonGridDuplicate := TButton.Create(Self);
  ButtonGridDuplicate.Align := alTop;
  ButtonGridDuplicate.AutoSize := true;
  ButtonGridDuplicate.Caption := 'Grid Dup...';
  ButtonGridDuplicate.Hint := '2D / 3D grid array duplicate selected TCastleTransform component(s) into Nx * Ny * Nz lattice (Ctrl+Alt+G)';
  ButtonGridDuplicate.ShowHint := true;
  ButtonGridDuplicate.BorderSpacing.Around := 2;
  ButtonGridDuplicate.OnClick := @ButtonGridDuplicateClick;
  ButtonGridDuplicate.Parent := PanelLayoutTransform;

  ButtonProjectAlongView := TButton.Create(Self);
  ButtonProjectAlongView.Align := alTop;
  ButtonProjectAlongView.AutoSize := true;
  ButtonProjectAlongView.Caption := 'Project Along View';
  ButtonProjectAlongView.Hint := 'Project selected TCastleTransform(s) along the viewport camera forward direction onto hit geometry (Ctrl+Shift+End; hold Shift/Alt to align +Y to surface normal)';
  ButtonProjectAlongView.ShowHint := true;
  ButtonProjectAlongView.BorderSpacing.Around := 2;
  ButtonProjectAlongView.OnClick := @ButtonProjectAlongViewClick;
  ButtonProjectAlongView.Parent := PanelLayoutTransform;

  ButtonViewTop := TButton.Create(Self);
  ButtonViewTop.Align := alTop;
  ButtonViewTop.AutoSize := true;
  ButtonViewTop.Caption := 'View: Top (-Y)';
  ButtonViewTop.Hint := 'Align viewport camera to Top view (-Y) centered on selection or scene (Numpad 7 / Alt+7, Ctrl for Bottom +Y)';
  ButtonViewTop.ShowHint := true;
  ButtonViewTop.BorderSpacing.Around := 2;
  ButtonViewTop.Tag := 0;
  ButtonViewTop.OnClick := @ButtonAxisViewClick;
  ButtonViewTop.Parent := PanelLayoutTransform;

  ButtonViewFront := TButton.Create(Self);
  ButtonViewFront.Align := alTop;
  ButtonViewFront.AutoSize := true;
  ButtonViewFront.Caption := 'View: Front (-Z)';
  ButtonViewFront.Hint := 'Align viewport camera to Front view (-Z) centered on selection or scene (Numpad 1 / Alt+1, Ctrl for Back +Z)';
  ButtonViewFront.ShowHint := true;
  ButtonViewFront.BorderSpacing.Around := 2;
  ButtonViewFront.Tag := 1;
  ButtonViewFront.OnClick := @ButtonAxisViewClick;
  ButtonViewFront.Parent := PanelLayoutTransform;

  ButtonViewRight := TButton.Create(Self);
  ButtonViewRight.Align := alTop;
  ButtonViewRight.AutoSize := true;
  ButtonViewRight.Caption := 'View: Right (-X)';
  ButtonViewRight.Hint := 'Align viewport camera to Right view (-X) centered on selection or scene (Numpad 3 / Alt+3, Ctrl for Left +X)';
  ButtonViewRight.ShowHint := true;
  ButtonViewRight.BorderSpacing.Around := 2;
  ButtonViewRight.Tag := 2;
  ButtonViewRight.OnClick := @ButtonAxisViewClick;
  ButtonViewRight.Parent := PanelLayoutTransform;

  PanelPropertyFilter := TPanel.Create(Self);
  PanelPropertyFilter.Align := alTop;
  PanelPropertyFilter.AutoSize := true;
  PanelPropertyFilter.BevelOuter := bvNone;
  PanelPropertyFilter.Parent := PanelRight;
  PanelPropertyFilter.Top := LabelControlSelected.Top + LabelControlSelected.Height + 1;

  ButtonResetProperty := TSpeedButton.Create(Self);
  ButtonResetProperty.Align := alRight;
  ButtonResetProperty.AutoSize := true;
  ButtonResetProperty.Caption := 'Reset Prop';
  ButtonResetProperty.Hint := 'Reset the currently selected Object Inspector property to its default value';
  ButtonResetProperty.ShowHint := true;
  ButtonResetProperty.BorderSpacing.Around := 4;
  ButtonResetProperty.OnClick := @ButtonResetPropertyClick;
  ButtonResetProperty.Parent := PanelPropertyFilter;

  EditPropertyFilter := TEdit.Create(Self);
  EditPropertyFilter.Align := alClient;
  EditPropertyFilter.BorderSpacing.Around := 4;
  EditPropertyFilter.TextHint := 'Search Properties...';
  EditPropertyFilter.Hint := 'Filter Object Inspector properties by name (case-insensitive substring match)';
  EditPropertyFilter.ShowHint := true;
  EditPropertyFilter.OnChange := @EditPropertyFilterChange;
  EditPropertyFilter.Parent := PanelPropertyFilter;

  MenuTreeViewItemToggleVisibility := TMenuItem.Create(Self);
  MenuTreeViewItemToggleVisibility.Caption := 'Toggle Visibility (Exists) (H)';
  MenuTreeViewItemToggleVisibility.OnClick := @MenuTreeViewItemToggleVisibilityClick;
  MenuTreeView.Items.Add(MenuTreeViewItemToggleVisibility);

  MenuTreeViewItemIsolateSelected := TMenuItem.Create(Self);
  MenuTreeViewItemIsolateSelected.Caption := 'Isolate Selected (Shift+H)';
  MenuTreeViewItemIsolateSelected.OnClick := @MenuTreeViewItemIsolateSelectedClick;
  MenuTreeView.Items.Add(MenuTreeViewItemIsolateSelected);

  MenuTreeViewItemShowAllHidden := TMenuItem.Create(Self);
  MenuTreeViewItemShowAllHidden.Caption := 'Show All Hidden (Alt+H)';
  MenuTreeViewItemShowAllHidden.OnClick := @MenuTreeViewItemShowAllHiddenClick;
  MenuTreeView.Items.Add(MenuTreeViewItemShowAllHidden);

  MenuTreeViewItemToggleLock := TMenuItem.Create(Self);
  MenuTreeViewItemToggleLock.Caption := 'Toggle Viewport Selection Lock (L)';
  MenuTreeViewItemToggleLock.OnClick := @MenuTreeViewItemToggleLockClick;
  MenuTreeView.Items.Add(MenuTreeViewItemToggleLock);

  MenuTreeViewItemUnlockAll := TMenuItem.Create(Self);
  MenuTreeViewItemUnlockAll.Caption := 'Unlock All Components (Alt+L)';
  MenuTreeViewItemUnlockAll.OnClick := @MenuTreeViewItemUnlockAllClick;
  MenuTreeView.Items.Add(MenuTreeViewItemUnlockAll);

  MenuTreeViewItemGroupSelected := TMenuItem.Create(Self);
  MenuTreeViewItemGroupSelected.Caption := 'Group Selected Under New Transform (Ctrl+G)';
  MenuTreeViewItemGroupSelected.OnClick := @MenuTreeViewItemGroupSelectedClick;
  MenuTreeView.Items.Add(MenuTreeViewItemGroupSelected);

  MenuTreeViewItemUngroupSelected := TMenuItem.Create(Self);
  MenuTreeViewItemUngroupSelected.Caption := 'Ungroup Selected Transform(s) (Ctrl+Shift+G)';
  MenuTreeViewItemUngroupSelected.OnClick := @MenuTreeViewItemUngroupSelectedClick;
  MenuTreeView.Items.Add(MenuTreeViewItemUngroupSelected);

  MenuTreeViewItemArrayDuplicate := TMenuItem.Create(Self);
  MenuTreeViewItemArrayDuplicate.Caption := 'Array Duplicate... (Ctrl+Shift+D)';
  MenuTreeViewItemArrayDuplicate.OnClick := @MenuTreeViewItemArrayDuplicateClick;
  MenuTreeView.Items.Add(MenuTreeViewItemArrayDuplicate);

  MenuTreeViewItemRadialDuplicate := TMenuItem.Create(Self);
  MenuTreeViewItemRadialDuplicate.Caption := 'Radial / Circular Duplicate... (Ctrl+Alt+D)';
  MenuTreeViewItemRadialDuplicate.OnClick := @MenuTreeViewItemRadialDuplicateClick;
  MenuTreeView.Items.Add(MenuTreeViewItemRadialDuplicate);

  MenuTreeViewItemGridDuplicate := TMenuItem.Create(Self);
  MenuTreeViewItemGridDuplicate.Caption := '2D / 3D Grid Duplicate... (Ctrl+Alt+G)';
  MenuTreeViewItemGridDuplicate.OnClick := @MenuTreeViewItemGridDuplicateClick;
  MenuTreeView.Items.Add(MenuTreeViewItemGridDuplicate);

  MenuTreeViewItemReplaceSelected := TMenuItem.Create(Self);
  MenuTreeViewItemReplaceSelected.Caption := 'Replace Selected With... (Ctrl+Shift+R)';
  MenuTreeViewItemReplaceSelected.OnClick := @MenuTreeViewItemReplaceSelectedClick;
  MenuTreeView.Items.Add(MenuTreeViewItemReplaceSelected);

  MenuTreeViewItemSelectSameClass := TMenuItem.Create(Self);
  MenuTreeViewItemSelectSameClass.Caption := 'Select All of Same Class';
  MenuTreeViewItemSelectSameClass.OnClick := @MenuTreeViewItemSelectSameClassClick;
  MenuTreeView.Items.Add(MenuTreeViewItemSelectSameClass);

  MenuTreeViewItemInvertSelection := TMenuItem.Create(Self);
  MenuTreeViewItemInvertSelection.Caption := 'Invert Selection (Ctrl+I)';
  MenuTreeViewItemInvertSelection.OnClick := @MenuTreeViewItemInvertSelectionClick;
  MenuTreeView.Items.Add(MenuTreeViewItemInvertSelection);

  MenuTreeViewItemSelectChildren := TMenuItem.Create(Self);
  MenuTreeViewItemSelectChildren.Caption := 'Select Direct Children (Ctrl+])';
  MenuTreeViewItemSelectChildren.OnClick := @MenuTreeViewItemSelectChildrenClick;
  MenuTreeView.Items.Add(MenuTreeViewItemSelectChildren);

  MenuTreeViewItemSelectDescendants := TMenuItem.Create(Self);
  MenuTreeViewItemSelectDescendants.Caption := 'Select All Descendants (Ctrl+Shift+])';
  MenuTreeViewItemSelectDescendants.OnClick := @MenuTreeViewItemSelectDescendantsClick;
  MenuTreeView.Items.Add(MenuTreeViewItemSelectDescendants);

  MenuTreeViewItemExpandAll := TMenuItem.Create(Self);
  MenuTreeViewItemExpandAll.Caption := 'Expand Subtree';
  MenuTreeViewItemExpandAll.OnClick := @MenuTreeViewItemExpandAllClick;
  MenuTreeView.Items.Add(MenuTreeViewItemExpandAll);

  MenuTreeViewItemCollapseAll := TMenuItem.Create(Self);
  MenuTreeViewItemCollapseAll.Caption := 'Collapse Subtree';
  MenuTreeViewItemCollapseAll.OnClick := @MenuTreeViewItemCollapseAllClick;
  MenuTreeView.Items.Add(MenuTreeViewItemCollapseAll);

  ControlsTree.OnDblClick := @ControlsTreeDblClick;
  ControlsTree.OnKeyDown := @ControlsTreeKeyDown;

  SaveDesignDialog.InitialDir := UriToFilenameSafe(ApplicationDataOverride);
  ExportToModelDialog.InitialDir := UriToFilenameSafe(ApplicationDataOverride);
  ExportToModelDialog.Filter := SaveNode_FileFilters;

  TabInfo.TabVisible := false;

  ChangeMode(moTranslate); // most expected default

  BuildComponentsMenu(
    MenuTreeViewItemAddUserInterface,
    MenuTreeViewItemAddTransform,
    MenuTreeViewItemAddBehavior,
    MenuTreeViewItemAddNonVisual,
    @MenuItemAddComponentClick);
  BuildComponentsMenu(
    MenuItemChangeClassUserInterface,
    MenuItemChangeClassTransform,
    MenuItemChangeClassBehavior,
    MenuItemChangeClassNonVisual,
    @MenuItemChangeClassClick);

  FCurrentViewportObserver := TFreeNotificationObserver.Create(Self);
  FCurrentViewportObserver.OnFreeNotification := {$ifdef FPC}@{$endif} CurrentViewportFreeNotification;

  // needed to set right action state maybe lazarus bug?
  ActionSimulationPauseUnpause.Update;

  (*
  // The TransformDesigning mechanism works, but it unused for now.
  FTransformDesigningObserver := TFreeNotificationObserver.Create(Self);
  FTransformDesigningObserver.OnFreeNotification := {$ifdef FPC}@{$endif} TransformDesigningFreeNotification;
  *)
  UpdateEditorDataForPropertyEditors;

  FindActive := true;
  EditFindInHierarchy.TextHint := 'Search Hierarchy (Name or +Class)...';
  EditFindInHierarchy.Hint := 'Filter Hierarchy by component name or class (use +ClassName to filter by class). Press F3 for next match.';
  EditFindInHierarchy.ShowHint := true;
  SetEnabledVisible(EditFindInHierarchy, FindActive);

  { TODO: This is unoptimal, we switch all actions buttons to "inactive".
    We don't really have a place to switch to "active" and "disabled",
    ActionListDesign has one property for images.

    We should instead pack all images into one long TImageList and set
    TSpeedButtons index properties accordingly.

    But to make this work, without going insane:), we need to manage TImageList
    contents by code (not by GUI in Lazarus IDE),
    and assign the indexes in TSpeedButtons by code.
    Otherwise (using GUI in Lazarus IDE to manage TImageList contents)
    this is unmaintainable, we'll constantly need to update
    indexes for other buttons (or we will have chaos in image list order)
    esp. with 3 versions for "dark" and possible future changes like
    variations for "light" as well.

    It also sucks we need all images prepared and loaded, instead of just
    tweaking the image color at display, like we can with TCastleButton
    in castle-editor-portable. }

  { TODO: This doesn't seem to work at all at runtime.
  if UseIconsAndColorsForDarkTheme then
    ActionListDesign.Images := Icons.ToolbarIconsDarkInactive;
  }
end;

destructor TDesignFrame.Destroy;
var
  F: TCollectionPropertyEditorForm;
begin
  FreeAndNil(TreeNodeMap);
  FreeAndNil(CameraPreview);
  FreeAndNil(FComponentEditorDesigner);
  FreeAndNil(LastSelected);
  FreeAndNil(FLockedComponents);

  if CollectionPropertyEditorForm <> nil then
  begin
    F := CollectionPropertyEditorForm;
    CollectionPropertyEditorFormUnassign;
    F.Close;
  end;

  inherited Destroy;
end;

procedure TDesignFrame.CollectionPropertyEditorFormUnassign;
begin
  if CollectionPropertyEditorForm <> nil then
  begin
    // unassign our callbacks from the form, as this TDesignFrame instance will no longer be valid
    CollectionPropertyEditorForm.OnClose := nil;
    CollectionPropertyEditorForm.CollectionListBox.OnClick := nil;
    CollectionPropertyEditorForm.AddButton.OnClick := nil;
    CollectionPropertyEditorForm.DeleteButton.OnClick := nil;
    CollectionPropertyEditorForm.MoveUpButton.OnClick := nil;
    CollectionPropertyEditorForm.MoveDownButton.OnClick := nil;
    CollectionPropertyEditorForm.RemoveFreeNotification(Self);
    CollectionPropertyEditorForm := nil;
  end;
end;

procedure TDesignFrame.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = CollectionPropertyEditorForm) then
    CollectionPropertyEditorFormUnassign;
end;

procedure TDesignFrame.SaveDesign(const Url: String);
begin
  if DesignRoot is TCastleUserInterface then
    UserInterfaceSave(TCastleUserInterface(DesignRoot), Url)
  else
  if DesignRoot is TCastleTransform then
    TransformSave(TCastleTransform(DesignRoot), Url)
  else
    ComponentSave(DesignRoot, Url);
  FDesignModified := false;
  FDesignUrl := Url; // after successfull save
  OnUpdateFormCaption(Self);
end;

procedure TDesignFrame.ClearDesign;
begin
  // ControlsTree.Items.Clear; // do not clear, we will always rebuild ControlsTree to just apply differences

  if FLockedComponents <> nil then
    FLockedComponents.Clear;

  ControlsTree.ClearSelection; // TODO: for now we reset selection, though maybe we could preserve it in some cases

  UpdateSelectedControl;
  //CastleControl.Controls.Clear; // don't clear it, leave DesignerLayer
  FDesignRoot := nil;
  FreeAndNil(CameraPreview);

  // this actually frees everything inside DesignRoot
  FreeAndNil(DesignOwner);
end;

procedure TDesignFrame.PerformUndoRedo(const UHE: TUndoHistoryElement);
var
  NewDesignOwner, NewDesignRoot: TComponent;
  InspectorType: TInspectorType;
  LoadInfo: TInternalComponentLoadInfo;
begin
  for InspectorType in TInspectorType do
    Inspector[InspectorType].SaveChanges;

  LoadInfo := TInternalComponentLoadInfo.Create;
  try
    LoadInfo.PreserveDataAcrossUndo := DesignOwner;

    NewDesignOwner := TComponent.Create(Self);
    NewDesignRoot := InternalStringToComponent(UHE.Data, NewDesignOwner, LoadInfo);
    OpenDesign(NewDesignRoot, NewDesignOwner, FDesignUrl);
  finally FreeAndNil(LoadInfo) end;

  RestoreSavedSelection(UHE.Selection);
end;

function TDesignFrame.GetInspectorForActiveTab: TOIPropertyGrid;
var
  InspectorType: TInspectorType;
begin
  for InspectorType in TInspectorType do
  begin
    if Inspector[InspectorType].Parent = ControlProperties.ActivePage then
      Exit(Inspector[InspectorType]);
  end;
  Result := nil;
end;

function TDesignFrame.GetSavedSelection: TSavedSelection;
var
  SelectedC: TComponent;
  ActiveInspector: TOIPropertyGrid;
begin
  SelectedC := GetSelectedComponent;
  { In case of modifying subcomponent, like TCastleViewport.Items,
    the currently selected component is not owned by whole design owner,
    so it will not be later found by name in RestoreSavedSelection. }
  if (SelectedC <> nil) and
     (SelectedC.Owner = DesignOwner) then
    Result.SelectedComponent := SelectedC.Name
  else
    Result.SelectedComponent := '';

  if (CurrentViewport <> nil) and
     (CurrentViewport.Owner = DesignOwner) then
    Result.CurrentViewport := CurrentViewport.Name
  else
    Result.CurrentViewport := '';

  Result.TabIndex := ControlProperties.TabIndex;

  ActiveInspector := GetInspectorForActiveTab;
  if ActiveInspector <> nil then
    Result.ItemIndex := ActiveInspector.ItemIndex
  else
    Result.ItemIndex := -1;
end;

procedure TDesignFrame.RestoreSavedSelection(const S: TSavedSelection);
var
  C: TComponent;
  V: TCastleViewport;
  ActiveInspector: TOIPropertyGrid;
begin
  if S.SelectedComponent <> '' then
  begin
    C := DesignOwner.FindComponent(S.SelectedComponent);
    if C = nil then
    begin
      WritelnLog('Cannot restore selection, as component "%s" no longer exists. This is normal if e.g. stopping physics removes an object added during physics simulation.', [
        S.SelectedComponent
      ]);
    end else
    begin
      SetSelectedComponent(C);

      { Restore object inspector state only if we could restore SelectedComponent,
        as object inspector should show the selected component. }
      if S.ItemIndex >= 0 then
      begin
        ControlProperties.TabIndex := S.TabIndex;

        ActiveInspector := GetInspectorForActiveTab;
        if ActiveInspector <> nil then
          ActiveInspector.SetItemIndexAndFocus(S.ItemIndex)
        else
          WritelnWarning('Cannot restore selection inspector ItemIndex, because inspector not found');
      end;
    end;
  end;

  if S.CurrentViewport <> '' then
  begin
    { We restore CurrentViewport, otherwise stopping physics would set CurrentViewport
      to nil if it was previously made non-nil because of hovering over a viewport
      (and not selecting viewport or something inside viewport). }
    C := DesignOwner.FindComponent(S.CurrentViewport);
    if (C = nil) or not (C is TCastleViewport) then
    begin
      WritelnLog('Cannot restore CurrentViewport, as viewport "%s" no longer exists or is no longer a TCastleViewport.', [
        S.CurrentViewport
      ]);
    end else
    begin
      V := C as TCastleViewport;
      SetCurrentViewport(V);
      { Note: This will also update FShowColliders on viewport,
        so e.g. Stop of physics will keep showing colliders. }
    end;
  end;

  { After restoring design, reliably focus the CastleControl,
    not the edit box of some property
    (which is optionally done by ActiveInspector.SetItemIndexAndFocus above).
    This allows using our general shortcuts, like Ctrl+Z, reliably after RestoreSavedSelection,
    in particular you can use Ctrl+Z after Ctrl+Z. }
  FocusDesign;
end;

procedure TDesignFrame.PerformRedo;
begin
  PerformUndoRedo(UndoSystem.Redo);
end;

procedure TDesignFrame.PerformUndo;
begin
  {//save current edited value and
  if not UndoSystem.IsRedoPossible then
  begin
    RecordUndo;
    UndoSystem.Undo;
  end;}
  PerformUndoRedo(UndoSystem.Undo);
end;

procedure TDesignFrame.UpdateObjectInspectorTimer(Sender: TObject);
//var
//  InspectorType: TInspectorType;
begin
  { In many cases, properties may change but property editor doesn't reflect it.
    E.g.
    - TCastleTransform changes by ExposeTransforms mechanism
    - Caption changes because you modified Name, and they used to match.
    The only universal solution to make OI up-to-date seems to be to just
    occasionally refresh it. }

  // TODO: This is not good, it breaks editing within object inspector, resets cursor
  //for InspectorType in TInspectorType do
  //  Inspector[InspectorType].RefreshPropertyValues;
end;

procedure TDesignFrame.OpenDesign(const NewDesignRoot, NewDesignOwner: TComponent;
  NewDesignUrl: String);

  { Note: NewDesignUrl parameter is *not* const.

    Because OpenDesign uses ClearDesign which destroys some components,
    and one of these components may be the owner of AnsiString with NewDesignUrl.
    So we have to keep refcount of NewDesignUrl,
    otherwise ClearDesign could free NewDesignUrl and then all its
    refences are invalid pointers, and OnUpdateFormCaption will crash.

    Testcase: Open any UI state design that uses TCastleDesign, click
    "Open Referenced Design".
    In this case, TCastleDesignComponentEditor.ExecuteVerb passes
    TCastleDesign.URL and NewDesignUrl, and ClearDesign removes this
    TCastleDesign instance.
  }

  { Initialize TCastleViewport that is internal, and used to edit
    .castle-transform. It requires some special considerations,
    as it needs a good camera/navigation, but also user cannot modify them,
    and they are not saved to .castle-transform. }
  procedure InitializeDesignViewportForTransforms(const V: TCastleViewport);
  var
    APos, ADir, AUp, AGravityUp: TVector3;
  begin
    { This Name is user-visible: if user selects anything in viewport,
      we show CurrentViewport.Name in header. }
    V.Name := 'InternalViewport';
    V.Transparent := true;
    V.FullSize := true;

    { Add headlight to design-time camera this way.
      Note that doing "V.Items.UseHeadLight := hlOn" would not have a desired
      effect, as this headlight would be done only from runtime camera,
      which we don't care about in this case. }
    V.InternalCamera.Add(TCastleDirectionalLight.Create(NewDesignOwner));

    CameraViewpointForWholeScene(V.Items.BoundingBox, 2, 1, false, true,
      APos, ADir, AUp, AGravityUp);
    V.InternalCamera.SetWorldView(APos, ADir, AUp);
    V.InternalCamera.GravityUp := AGravityUp;
  end;

var
  //LabelNonVisualHint: TCastleLabel;
  DesignRootVisual: Boolean;
begin
  ClearDesign;

  { We use CastleControl.Controls.InsertBack here, to keep DesignerLayer
    in the front. }

  DesignRootVisual :=
    (NewDesignRoot is TCastleUserInterface) or
    (NewDesignRoot is TCastleTransform);

  if DesignRootVisual then
  begin
    CameraPreview := TCameraPreview.Create(nil, NewDesignOwner);
    CastleControl.Controls.InsertBack(CameraPreview.UiRoot);
  end;

  if NewDesignRoot is TCastleUserInterface then
  begin
    CastleControl.Controls.InsertBack(NewDesignRoot as TCastleUserInterface);
    Assert(DesignRootVisual);
  end else
  if NewDesignRoot is TCastleTransform then
  begin
    FDesignViewportForTransforms := TCastleViewport.Create(NewDesignOwner);
    FDesignViewportForTransforms.Items.Add(NewDesignRoot as TCastleTransform);
    { Do this after adding NewDesignRoot, as it wants good Items.BoundingBox }
    InitializeDesignViewportForTransforms(FDesignViewportForTransforms);
    CastleControl.Controls.InsertBack(FDesignViewportForTransforms);
    Assert(DesignRootVisual);
  end else
  begin
    { This is normal situation for non-visual components. }
    (*
    LabelNonVisualHint := TCastleLabel.Create(NewDesignOwner);
    LabelNonVisualHint.Caption := 'This design does not contain any visual components.' + NL +
      'The root of this design has class:' + NL +
      NL +
      NewDesignRoot.ClassName;
    LabelNonVisualHint.Anchor(hpMiddle);
    LabelNonVisualHint.Anchor(vpMiddle);
    LabelNonVisualHint.FontSize := 40;
    CastleControl.Controls.InsertBack(LabelNonVisualHint);
    *)
    Assert(not DesignRootVisual);
  end;

  SetEnabledVisible(CastleControl, DesignRootVisual);
  SetEnabledVisible(PanelMiddleTop, DesignRootVisual);

  // set background to gray
  CastleControl.Container.BackgroundColor := Vector4(0.5, 0.5, 0.5, 1);

  // replace DesignXxx variables, once loading successfull
  FDesignRoot := NewDesignRoot;
  FDesignUrl := NewDesignUrl;
  DesignOwner := NewDesignOwner;
  FDesignModified := DesignUrl = ''; // when opening '', mark new hierarchy modified

  // Allows object inspectors to find matching components, e.g. when editing Viewport.Items.MainScene
  PropertyEditorHook.LookupRoot := DesignOwner;
  PropertyEditorHook.AddHandlerModified(@PropertyEditorModified);

  UpdateDesign;
  OnUpdateFormCaption(Self);
end;

procedure TDesignFrame.OpenDesign(const NewDesignUrl: String);
var
  NewDesignRoot, NewDesignOwner: TComponent;
  Mime: String;
begin
  NewDesignOwner := TComponent.Create(Self);

  try
    Mime := UriMimeType(NewDesignUrl);
    if Mime = 'text/x-castle-user-interface' then
      NewDesignRoot := UserInterfaceLoad(NewDesignUrl, NewDesignOwner)
    else
    if Mime = 'text/x-castle-transform' then
      NewDesignRoot := TransformLoad(NewDesignUrl, NewDesignOwner)
    else
    if (Mime = 'text/x-castle-component') or
       // open CastleLocalProjectSettings.json, and future CastleProject.json
       (Mime = 'application/json') then
      NewDesignRoot := ComponentLoad(NewDesignUrl, NewDesignOwner)
    else
      raise Exception.CreateFmt('Unrecognized file extension %s (MIME type %s)',
        [ExtractUriExt(NewDesignUrl), Mime]);
  except
    { Testcase: try to load using UserInterfaceLoad a file
      that has TCastleTransform inside. UserInterfaceLoad makes EInvalidCast. }
    on E: Exception do
    begin
      E.Message := 'Error when loading ' + UriDisplay(NewDesignUrl) + ': ' + E.Message;
      raise;
    end;
  end;

  UndoSystem.ClearUndoHistory;

  OpenDesign(NewDesignRoot, NewDesignOwner, NewDesignUrl);

  RecordUndo('Open design', High(TUndoCommentPriority)); // Technically this is impossible to see this Undo comment
end;

function TDesignFrame.FormCaption: String;
var
  DesignName: String;
begin
  // calculate DesignName
  if DesignUrl <> '' then
    DesignName := ExtractUriName(DesignUrl)
  else
  if DesignRoot is TCastleTransform then
    DesignName := 'New Transform'
  else
  if DesignRoot is TCastleUserInterface then
    DesignName := 'New User Interface'
  else
    // generic, should not happen now
    DesignName := 'New Component';
  Result := '[' + Iff(DesignModified, '*', '') + DesignName + '] ';
end;

procedure TDesignFrame.BeforeProposeSaveDesign;
var
  InspectorType: TInspectorType;
begin
  { call SaveChanges to be sure to have good DesignModified value.
    Otherwise when editing e.g. TCastleButton.Caption,
    you can press F9 and have DesignModified = false,
    because PropertyGridModified doesn't occur because we actually
    press "tab" to focus another control. }
  for InspectorType in TInspectorType do
    Inspector[InspectorType].SaveChanges;
end;

procedure TDesignFrame.AddComponent(const ComponentClass: TComponentClass;
  const ComponentOnCreate: TNotifyEvent);
var
  ParentComponent: TComponent;
begin
  // calculate ParentComponent
  ParentComponent := GetSelectedComponent;
  { User can use "Add Behavior" when another TCastleBehavior is selected,
    it means to insert into the parent TCastleTransform.
    E.g. usecase: add collider when rigid body is selected. }
  if ComponentClass.InheritsFrom(TCastleBehavior) and
     (ParentComponent is TCastleBehavior) then
  begin
    ParentComponent := TCastleBehavior(ParentComponent).Parent;
  end;
  { If nothing was selected, add to DesignRoot }
  if ParentComponent = nil then
    ParentComponent := DesignRoot;

  AddComponent(ParentComponent, ComponentClass, ComponentOnCreate);
end;

function TDesignFrame.AddComponent(const ParentComponent: TComponent;
  const ComponentClass: TComponentClass;
  const ComponentOnCreate: TNotifyEvent;
  const BaseNewComponentName: String;
  const InsertIndex: Integer): TComponent;

  function CreateComponent: TComponent;
  begin
    Result := ComponentClass.Create(DesignOwner) as TComponent;
    if Assigned(ComponentOnCreate) then // call ComponentOnCreate ASAP after constructor
      ComponentOnCreate(Result);
    Result.Name := ProposeComponentName(ComponentClass, DesignOwner, BaseNewComponentName);
  end;

  procedure FinishAddingComponent(const NewComponent: TComponent);
  begin
    UpdateDesign;
    SelectedComponent := NewComponent; // select after adding, makes it natural to edit
    ModifiedOutsideObjectInspector('Add ' + NewComponent.Name + ' to ' + ParentComponent.Name, ucHigh);
  end;

  procedure AutoCreateRigidBody(const Collider: TCastleCollider; const ParentComponent: TCastleTransform);
  var
    RBody: TCastleRigidBody;
  begin
    RBody := AddComponent(ParentComponent, TCastleRigidBody, nil) as TCastleRigidBody;
    if Collider.Mode2D then
      RBody.Setup2D;
  end;

  function AddToTransform(const ParentComponent: TCastleTransform): TComponent;
  begin
    if ComponentClass.InheritsFrom(TCastleTransform) then
    begin
      Result := CreateComponent;
      if InsertIndex >= 0 then
        ParentComponent.Insert(InsertIndex, Result as TCastleTransform)
      else
        ParentComponent.Add(Result as TCastleTransform);
      FinishAddingComponent(Result);
    end else
    if ComponentClass.InheritsFrom(TCastleUserInterface) then
    begin
      raise Exception.Create(Format('Cannot add TCastleUserInterface descendant (%s) when the parent is a TCastleTransform descendant (%s). Select a parent that descends from TCastleUserInterface.',
        [ComponentClass.ClassName, ParentComponent.ClassName]))
    end else
    if ComponentClass.InheritsFrom(TCastleBehavior) then
    begin
      Result := CreateComponent;
      if InsertIndex >= 0 then
        ParentComponent.InsertBehavior(InsertIndex, Result as TCastleBehavior)
      else
        ParentComponent.AddBehavior(Result as TCastleBehavior);
      try
        { Show colliders on newly added component }
        if (Result is TCastleCollider) and FShowColliders then
          UpdateColliders(ParentComponent);
        { If component is TCastleMeshCollider try to set Scene property to parent }
        if (Result is TCastleMeshCollider) and ParentComponent.HasColliderMesh then
          (Result as TCastleMeshCollider).Mesh := ParentComponent;
        (*
        // The TransformDesigning mechanism works, but it unused for now.
        { When creating new behavior under selected transform, call DesigningBegin.
          This way temporary anchors appear immediately on newly added physics joint. }
        if ParentComponent = TransformDesigning then
          (Result as TCastleBehavior).DesigningBegin;
        *)
        { auto-create TCastleRigidBody after adding collider }
        if (Result is TCastleCollider) and
           (ParentComponent.FindBehavior(TCastleRigidBody) = nil) then
          AutoCreateRigidBody(TCastleCollider(Result), ParentComponent);
      finally
        FinishAddingComponent(Result);
      end;
    end else
    begin
      Result := CreateComponent;
      if InsertIndex >= 0 then
        ParentComponent.InsertNonVisualComponent(InsertIndex, Result)
      else
        ParentComponent.AddNonVisualComponent(Result);
      FinishAddingComponent(Result);
    end;
  end;

  function AddToUserInterface(const ParentComponent: TCastleUserInterface): TComponent;
  begin
    if ComponentClass.InheritsFrom(TCastleUserInterface) then
    begin
      Result := CreateComponent;
      if InsertIndex >= 0 then
        ParentComponent.InsertControl(InsertIndex, Result as TCastleUserInterface)
      else
        ParentComponent.InsertFront(Result as TCastleUserInterface);
      FinishAddingComponent(Result);
    end else
    if ComponentClass.InheritsFrom(TCastleTransform) then
    begin
      raise Exception.Create(Format('Cannot add TCastleTransform descendant (%s) when the parent is a TCastleUserInterface descendant (%s). Select a parent that descends from TCastleTransform, for example select Viewport.Items.',
        [ComponentClass.ClassName, ParentComponent.ClassName]))
    end else
    if ComponentClass.InheritsFrom(TCastleBehavior) then
    begin
      raise Exception.Create(Format('Cannot add TCastleBehavior descendant (%s) when the parent is a TCastleUserInterface descendant (%s). Select a parent that descends from TCastleTransform, like TCastleTransform itself or TCastleScene.',
        [ComponentClass.ClassName, ParentComponent.ClassName]))
    end else
    begin
      Result := CreateComponent;
      if InsertIndex >= 0 then
        ParentComponent.InsertNonVisualComponent(InsertIndex, Result)
      else
        ParentComponent.AddNonVisualComponent(Result);
      FinishAddingComponent(Result);
    end;
  end;

  function AddToComponent(const ParentComponent: TCastleComponent): TComponent;
  begin
    { Note that, technically,
      we could add TCastleUserInterface/TCastleTransform/TCastleBehavior
      to non-visual components list.
      But this would be confusing, so we disallow it in editor. }
    if ComponentClass.InheritsFrom(TCastleUserInterface) then
    begin
      raise Exception.Create(Format('To add TCastleUserInterface descendant (%s), select a parent that descends from TCastleUserInterface.',
        [ComponentClass.ClassName, ParentComponent.ClassName]))
    end else
    if ComponentClass.InheritsFrom(TCastleTransform) then
    begin
      raise Exception.Create(Format('To add TCastleTransform descendant (%s), select a parent that descends from TCastleTransform, for example select Viewport.Items.',
        [ComponentClass.ClassName, ParentComponent.ClassName]))
    end else
    if ComponentClass.InheritsFrom(TCastleBehavior) then
    begin
      raise Exception.Create(Format('To add TCastleBehavior descendant (%s), select a parent that descends from TCastleTransform, like TCastleTransform itself or TCastleScene.',
        [ComponentClass.ClassName, ParentComponent.ClassName]))
    end else
    begin
      Result := CreateComponent;
      if InsertIndex >= 0 then
        ParentComponent.InsertNonVisualComponent(InsertIndex, Result)
      else
        ParentComponent.AddNonVisualComponent(Result);
      FinishAddingComponent(Result);
    end;
  end;

begin
  { Cancel editing the component name, when adding a component.
    See https://trello.com/c/IC6NQx0X/59-bug-adding-a-component-to-a-component-that-is-being-currently-renamed-triggers-and-exception . }
  if ControlsTreeOneSelected <> nil then
    ControlsTreeOneSelected.EndEdit(true);

  if ParentComponent is TCastleUserInterface then
  begin
    Exit(AddToUserInterface(TCastleUserInterface(ParentComponent)));
  end else
  if ParentComponent is TCastleTransform then
  begin
    Exit(AddToTransform(TCastleTransform(ParentComponent)));
  end else
  if ParentComponent is TCastleComponent then
  begin
    Exit(AddToComponent(ParentComponent as TCastleComponent));
  end else
    raise Exception.Create(Format('Cannot add to the parent of class %s, select other parent before adding.',
      [ParentComponent.ClassName]))
end;

procedure TDesignFrame.FreeComponentRecursively(const C: TComponent);

  procedure FreeNonVisualChildren(const C: TCastleComponent);
  var
    I: Integer;
  begin
    for I := C.NonVisualComponentsCount - 1 downto 0 do
      if Deletable(C.NonVisualComponents[I]) then
        FreeComponentRecursively(C.NonVisualComponents[I]);
  end;

  procedure FreeTransformChildren(const T: TCastleTransform);
  var
    I: Integer;
  begin
    for I := T.Count - 1 downto 0 do
      if Deletable(T[I]) then
        FreeComponentRecursively(T[I]);
  end;

  procedure FreeBehaviorChildren(const T: TCastleTransform);
  var
    I: Integer;
  begin
    for I := T.BehaviorsCount - 1 downto 0 do
      if Deletable(T.Behaviors[I]) then
        FreeComponentRecursively(T.Behaviors[I]);
  end;

  procedure FreeUiChildren(const C: TCastleUserInterface);
  var
    I: Integer;
  begin
    for I := C.ControlsCount - 1 downto 0 do
      if Deletable(C.Controls[I]) then
        FreeComponentRecursively(C.Controls[I]);
  end;

begin
  if not Deletable(C) then
    Exit;

  { Check this assertion after Deletable check, as it may be invalid
    e.g. for gizmos that are csTransient. }
  Assert(C.Owner = DesignOwner);

  if C is TCastleComponent then
  begin
    FreeNonVisualChildren(TCastleComponent(C));
    if C is TCastleTransform then
    begin
      FreeBehaviorChildren(TCastleTransform(C));
      FreeTransformChildren(TCastleTransform(C));
    end else
    if C is TCastleUserInterface then
    begin
      FreeUiChildren(TCastleUserInterface(C));
      if C is TCastleViewport then
      begin
        FreeBehaviorChildren(TCastleViewport(C).Items);
        FreeTransformChildren(TCastleViewport(C).Items);
      end;
    end;
  end;
  { Remove designing objects before delete behavior }
//  if C is TCastleBehavior then
//    TCastleBehavior(C).DesigningEnd;
  C.Free;

  UpdateDesign;
end;

procedure TDesignFrame.DeleteComponent(const AutoSelectParents: Boolean = false);

  { Explain to user why C cannot be deleted.
    We know that Deletable(C) = false at this point. }
  function ReasonWhyNotDeletable(const C: TComponent): String;
  var
    ReasonStart: String;
  begin
    ReasonStart := 'Cannot remove "' + C.Name + '":' + NL + NL;

    // This analyzes some conditions of Deletable and Selectable
    if C is TCastleToolTransform then
      Exit(ReasonStart + 'This is a temporary (tool) component, helpful to edit something, but it is not part of the final design. Use "Hide Joint Tools" to hide it.');
    if csTransient in C.ComponentStyle then
      Exit(ReasonStart + 'This is an internal component, you should not be able to even select it.');
    if csSubComponent in C.ComponentStyle then
      Exit(ReasonStart + 'This is a subcomponent, and subcomponents cannot be removed because owner depends that they always exist.');
    if C = DesignRoot then
      Exit(ReasonStart + 'This is the root component of the design. Design must always have a root component. You can only change it to something else using "Change Class".');

    // Shorter error message, if we don't know any specific reason
    Result := 'Cannot remove "' + C.Name + '".';
  end;

  function FirstDeletableComponent(const List: TComponentList): TComponent;
  var
    I: Integer;
  begin
    for I := 0 to List.Count - 1 do
      if Deletable(List[I]) then
        Exit(List[I]);
    Result := nil;
  end;

var
  Selected: TComponentList;
  SelectedCount: Integer;
  C: TComponent;
  UndoSummary: String;
begin
  GetSelected(Selected, SelectedCount, AutoSelectParents);
  try
    if SelectedCount <> 0 then // check this, otherwise Selected may be nil
    begin
      if SelectedCount = 1 then
        UndoSummary := Selected[0].Name
      else
        UndoSummary := SelectedCount.ToString + ' components';

      if (SelectedCount = 1) and not Deletable(Selected[0]) then
      begin
        { In this case we will not remove anything.
          Be vocal to user to explain "why", e.g. why root components cannot be removed. }
        ErrorBox(ReasonWhyNotDeletable(Selected[0]));
        Exit;
      end;

      { We depend on the fact TComponentList observes freed items,
        and removes them automatically.
        This way also freeing something that frees something else
        should work (although we don't really need it now,
        DesignOwner owns everything). }

      repeat
        C := FirstDeletableComponent(Selected);
        if C <> nil then
          FreeComponentRecursively(C)
        else
          Break;
      until false;

      { call this after UpdateDesign, otherwise tree is not ready,
        and events caused by ModifiedOutsideObjectInspector may expect it is. }
      ModifiedOutsideObjectInspector('Delete ' + UndoSummary, ucHigh);
    end;
  finally FreeAndNil(Selected) end;
end;

procedure TDesignFrame.CopyComponent;
const
  { For copying, copying auto-parent is not intuitive,
    see https://github.com/castle-engine/castle-engine/issues/522 . }
  AutoSelectParents = false;
var
  Sel: TComponent;
begin
  Sel := GetSelectedComponent(AutoSelectParents);
  if (Sel <> nil) and
     (not (csSubComponent in Sel.ComponentStyle)) then
  begin
    Clipboard.AsText := ComponentToString(Sel)
  end else
  begin
    ErrorBox('Select exactly one component, that is not a subcomponent, to copy');
  end;
end;

procedure TDesignFrame.PasteComponent;

  procedure FinishAddingComponent(const NewComponent: TComponent);
  begin
    UpdateDesign;
    SelectedComponent := NewComponent; // select after adding, makes it natural to edit
    ModifiedOutsideObjectInspector('Paste ' + NewComponent.Name, ucHigh);
  end;

var
  Selected: TComponentList;
  SelectedCount: Integer;
  ParentComponent, NewComponent: TComponent;
begin
  try
    NewComponent := StringToComponent(Clipboard.AsText, DesignOwner);
  except
    on E: Exception do
    begin
      ErrorBox('Cliboard doesn''t seem to contain a copied component.' + NL + NL +
        'Trying to deserialize it failed with the error:' + NL + NL +
        ExceptMessage(E));
      Exit;
    end;
  end;

  // calculate ParentComponent
  GetSelected(Selected, SelectedCount);
  try
    if SelectedCount = 1 then
      ParentComponent := Selected.First
    else
      ParentComponent := DesignRoot;
  finally FreeAndNil(Selected) end;

  if NewComponent is TCastleUserInterface then
  begin
    if not (ParentComponent is TCastleUserInterface) then
    begin
      ErrorBox('Clipboard contains a TCastleUserInterface instance, you need to select a TCastleUserInterface as a parent before doing "Paste Component"');
      FreeAndNil(NewComponent);
      Exit;
    end;
    (ParentComponent as TCastleUserInterface).InsertFront(NewComponent as TCastleUserInterface);
    FinishAddingComponent(NewComponent);
  end else
  if NewComponent is TCastleTransform then
  begin
    if not (ParentComponent is TCastleTransform) then
    begin
      ErrorBox('Clipboard contains a TCastleTransform instance, you need to select a TCastleTransform as a parent before doing "Paste Component"');
      FreeAndNil(NewComponent);
      Exit;
    end;
    (ParentComponent as TCastleTransform).Add(NewComponent as TCastleTransform);
    FinishAddingComponent(NewComponent);
  end else
  if NewComponent is TCastleBehavior then
  begin
    if not (ParentComponent is TCastleTransform) then
    begin
      ErrorBox('Clipboard contains a TCastleTransform instance, you need to select a TCastleTransform as a parent before doing "Paste Component"');
      FreeAndNil(NewComponent);
      Exit;
    end;
    (ParentComponent as TCastleTransform).AddBehavior(NewComponent as TCastleBehavior);
    FinishAddingComponent(NewComponent);
  end else
  begin
    ErrorBox(Format('Clipboard contains an instance of %s class, cannot insert it into the design',
      [NewComponent.ClassName]));
    FreeAndNil(NewComponent);
  end;
end;

procedure TDesignFrame.CutComponent;
const
  { For deletion, better to not select parent to avoid removing too much.
    See https://github.com/castle-engine/castle-engine/issues/521 . }
  AutoSelectParents = false;
var
  Sel: TComponent;
begin
  Sel := GetSelectedComponent(AutoSelectParents);
  if (Sel <> nil) and
     (not (csSubComponent in Sel.ComponentStyle)) then
  begin
    Clipboard.AsText := ComponentToString(Sel);
    DeleteComponent(AutoSelectParents);
  end else
  begin
    ErrorBox('Select exactly one component, that is not a subcomponent, to copy');
  end;
end;

function TDesignFrame.NonVisualComponentParent(const C: TComponent): TCastleComponent;
var
  CNode: TTreeNode;
  ParentComp: TComponent;
begin
  if not TreeNodeMap.TryGetValue(C, CNode) then
    raise EInternalError.Create('Cannot get parent of non-visual component: we cannot find the node in ControlsTree');

  // This can happen if C is root component in design
  if CNode.Parent = nil then
    Exit(nil);

  { Note: SelectedFromNode will automatically lookup higher parent,
    in case parent is special "Non-visual component" text node. }
  ParentComp := SelectedFromNode(CNode.Parent);
  if ParentComp = nil then
    raise EInternalError.Create('Cannot get parent of non-visual component: parent node not a regular component');

  if not (ParentComp is TCastleComponent) then
    raise EInternalError.Create('Cannot get parent of non-visual component: parent is TComponent but not TCastleComponent');

  Result := ParentComp as TCastleComponent;
end;

function TDesignFrame.IsComponentDescendantOfSelection(const C: TComponent;
  const List: TComponentList): Boolean;
var
  Node: TTreeNode;
begin
  Result := false;
  if (C = nil) or (List = nil) then Exit;
  if not TreeNodeMap.TryGetValue(C, Node) then Exit;

  Node := Node.Parent;
  while Node <> nil do
  begin
    if (Node.Data <> nil) and (List.IndexOf(TComponent(Node.Data)) <> -1) then
      Exit(true);
    Node := Node.Parent;
  end;
end;

procedure TDesignFrame.DuplicateComponent;

  function DuplicateSingleUserInterface(const Selected: TCastleUserInterface): TComponent;
  var
    ParentComp, NewComp: TCastleUserInterface;
    ComponentString: String;
    InsertIndex: Integer;
  begin
    Result := nil;
    ParentComp := Selected.Parent;
    if ParentComp = nil then Exit;
    ComponentString := ComponentToString(Selected);
    NewComp := StringToComponent(ComponentString, DesignOwner) as TCastleUserInterface;
    InsertIndex := ParentComp.IndexOfControl(Selected);
    ParentComp.InsertControl(InsertIndex + 1, NewComp);
    Result := NewComp;
  end;

  function DuplicateSingleTransform(const Selected: TCastleTransform): TComponent;
  var
    ParentComp, NewComp: TCastleTransform;
    ComponentString: String;
    InsertIndex: Integer;
  begin
    Result := nil;
    ParentComp := Selected.Parent;
    if ParentComp = nil then Exit;
    ComponentString := ComponentToString(Selected);
    NewComp := StringToComponent(ComponentString, DesignOwner) as TCastleTransform;
    InsertIndex := ParentComp.List.IndexOf(Selected);
    ParentComp.Insert(InsertIndex + 1, NewComp);
    Result := NewComp;
  end;

  function DuplicateSingleNonVisualComponent(const Selected: TCastleComponent): TComponent;
  var
    ParentComp, NewComp: TCastleComponent;
    ComponentString: String;
    InsertIndex: Integer;
  begin
    Result := nil;
    ParentComp := NonVisualComponentParent(Selected);
    if ParentComp = nil then Exit;
    ComponentString := ComponentToString(Selected);
    NewComp := StringToComponent(ComponentString, DesignOwner) as TCastleComponent;
    InsertIndex := ParentComp.NonVisualComponentsIndexOf(Selected);
    ParentComp.InsertNonVisualComponent(InsertIndex + 1, NewComp);
    Result := NewComp;
  end;

var
  SelectedList, NewComponents: TComponentList;
  SelectedCount, I: Integer;
  Sel, NewComp: TComponent;
  FirstOldName: String;
begin
  GetSelected(SelectedList, SelectedCount, false);
  try
    if SelectedCount = 0 then
    begin
      ErrorBox('Select at least one component (that is not the root or a subcomponent) to duplicate.');
      Exit;
    end;

    NewComponents := TComponentList.Create(false);
    try
      FirstOldName := '';
      for I := 0 to SelectedCount - 1 do
      begin
        Sel := SelectedList[I];
        if (Sel = nil) or
           (Sel = DesignRoot) or
           (csSubComponent in Sel.ComponentStyle) or
           IsComponentDescendantOfSelection(Sel, SelectedList) then
          Continue;

        NewComp := nil;
        if Sel is TCastleUserInterface then
          NewComp := DuplicateSingleUserInterface(Sel as TCastleUserInterface)
        else
        if Sel is TCastleTransform then
          NewComp := DuplicateSingleTransform(Sel as TCastleTransform)
        else
        if Sel is TCastleComponent then
          NewComp := DuplicateSingleNonVisualComponent(Sel as TCastleComponent);

        if NewComp <> nil then
        begin
          if FirstOldName = '' then
            FirstOldName := Sel.Name;
          NewComponents.Add(NewComp);
        end;
      end;

      if NewComponents.Count = 0 then
      begin
        ErrorBox('To duplicate, select one or more components with a parent (not the root or subcomponents).');
        Exit;
      end;

      UpdateDesign;
      SetSelected(NewComponents);
      if NewComponents.Count = 1 then
        ModifiedOutsideObjectInspector('Duplicate ' + FirstOldName + '->' + NewComponents[0].Name, ucHigh)
      else
        ModifiedOutsideObjectInspector(Format('Duplicate %d components', [NewComponents.Count]), ucHigh);
    finally
      FreeAndNil(NewComponents);
    end;
  finally
    FreeAndNil(SelectedList);
  end;
end;

procedure TDesignFrame.DuplicateLinkedComponent;

  procedure FinishAddingComponent(const NewComponent: TCastleTransformReference);
  begin
    // UpdateDesign; // no need to, AddComponent already does this
    // SelectedComponent := NewComponent; // no need to, AddComponent already does this
    Assert(NewComponent.Reference <> nil);
    ModifiedOutsideObjectInspector('Created reference ' + NewComponent.Name +
      ' to ' + NewComponent.Reference.Name, ucHigh);
  end;

  procedure DuplicateLinkedTransform(const Selected: TCastleTransform);
  var
    ParentComp, ReferenceTarget: TCastleTransform;
    NewReference: TCastleTransformReference;
    BaseNewComponentName: String;
    InsertIndex: Integer;
  begin
    ParentComp := Selected.Parent;
    if ParentComp = nil then
    begin
      ErrorBox('To duplicate, select component with exactly one parent');
      Exit;
    end;

    // When using "Duplicate Linked" over an existing TCastleTransformReference,
    // create another TCastleTransformReference to the same target,
    // not TCastleTransformReference to TCastleTransformReference.
    ReferenceTarget := Selected;
    if Selected is TCastleTransformReference then
    begin
      ReferenceTarget := TCastleTransformReference(Selected).Reference;
      if ReferenceTarget = nil then
      begin
        ErrorBox('To duplicate linked, select a target component (not TCastleTransformReference), or select another TCastleTransformReference with non-nil Target. Now you selected TCastleTransformReference with Target=nil.');
        Exit;
      end;
    end;
    Assert(ReferenceTarget <> nil);

    BaseNewComponentName := 'Reference' + StripNumericSuffix(ReferenceTarget.Name);

    InsertIndex := ParentComp.List.IndexOf(Selected) + 1;

    NewReference := AddComponent(ParentComp, TCastleTransformReference, nil,
      BaseNewComponentName, InsertIndex) as TCastleTransformReference;
    NewReference.Reference := ReferenceTarget;
    // copy transformation parameters Selected -> NewReference
    NewReference.Translation := Selected.Translation;
    NewReference.Rotation := Selected.Rotation;
    NewReference.Scale := Selected.Scale;
    NewReference.Center := Selected.Center;
    NewReference.ScaleOrientation := Selected.ScaleOrientation;

    FinishAddingComponent(NewReference);
  end;

var
  Sel: TComponent;
begin
  Sel := SelectedComponent;
  if (Sel <> nil) and
     (not (csSubComponent in Sel.ComponentStyle)) then
  begin
    if Sel is TCastleTransform then
      DuplicateLinkedTransform(Sel as TCastleTransform)
    else
      ErrorBox('To duplicate (linked, using TCastleTransformReference), select TCastleTransform component');
  end else
    ErrorBox('To duplicate (linked), select exactly one component that is not a subcomponent');
end;

function TDesignFrame.SelectedViewport: TCastleViewport;

  { Return viewport indicated by T, or @nil if none. }
  function ViewportOfTransform(const T: TCastleTransform): TCastleViewport;
  begin
    if T.World <> nil then
      Result := T.World.Owner as TCastleViewport
    else
      Result := nil;
  end;

  { Return viewport indicated by B, or @nil if none. }
  function ViewportOfBehavior(const B: TCastleBehavior): TCastleViewport;
  begin
    if B.Parent <> nil then
      Result := ViewportOfTransform(B.Parent)
    else
      Result := nil;
  end;

  { Return viewport indicated by C, or @nil if none. }
  function ViewportOfComponent(const C: TComponent): TCastleViewport;
  var
    ViewportChild: TCastleUserInterface;
  begin
    Result := nil;

    if C is TCastleViewport then
    begin
      Result := C as TCastleViewport;
    end else
    if C is TCastleUserInterface then
    begin
      { When hovering over TCastleNavigation, or TCastleTouchNavigation,
        or really any UI as viewport child -> select viewport. }
      ViewportChild := C as TCastleUserInterface;
      if {ViewportChild.FullSize and} (ViewportChild.Parent is TCastleViewport) then
      begin
        Result := ViewportChild.Parent as TCastleViewport;
      end;
    end else
    if C is TCastleTransform then
      Result := ViewportOfTransform(C as TCastleTransform)
    else
    if C is TCastleBehavior then
      Result := ViewportOfBehavior(C as TCastleBehavior);
  end;

var
  Selected: TComponentList;
  SelectedCount, I: Integer;
  NewResult: TCastleViewport;
begin
  Result := nil;

  GetSelected(Selected, SelectedCount);
  try
    for I := 0 to SelectedCount - 1 do
    begin
      NewResult := ViewportOfComponent(Selected[I]);

      if NewResult <> nil then
      begin
        if (Result <> nil) and (Result <> NewResult) then
          Exit(nil); // multiple viewports selected
        Result := NewResult;
      end;
    end;
  finally FreeAndNil(Selected) end;
end;

procedure TDesignFrame.UIScaling(const UIScaling: TUIScaling;
  const UIReferenceWidth, UIReferenceHeight: Single);
begin
  CastleControl.Container.UIScaling := UIScaling;
  CastleControl.Container.UIReferenceWidth := UIReferenceWidth;
  CastleControl.Container.UIReferenceHeight := UIReferenceHeight;
end;

procedure TDesignFrame.CurrentComponentApiUrl(var Url: String);

  function InspectorTypeFromActiveControl(const C: TWinControl;
    out InspectorType: TInspectorType): Boolean;
  begin
    for InspectorType in TInspectorType do
      if Inspector[InspectorType] = C then
        Exit(true);

    if C.Parent <> nil then
      Exit(InspectorTypeFromActiveControl(C.Parent, InspectorType));

    Result := false;
  end;

  { If a property of the SelectedComponent is now focused
    in one of our object inspectors, return property name. }
  function SelectedProperty(out PropertyInstance: TObject;
    out PropertyName, PropertyNameForLink: String): Boolean;
  var
    ParentForm: TCustomForm;
    InspectorType: TInspectorType;
    ActiveRow: TOIPropertyGridRow;
  begin
    ParentForm := GetParentForm(Self);
    if (ParentForm.ActiveControl <> nil) and
       InspectorTypeFromActiveControl(ParentForm.ActiveControl, InspectorType) and
       (Inspector[InspectorType].GetActiveRow <> nil) then
    begin
      ActiveRow := Inspector[InspectorType].GetActiveRow;
      PropertyInstance := ActiveRow.Editor.GetComponent(0);

      PropertyName := ActiveRow.Editor.GetPropInfo^.Name;

      { Why do we need PropertyNameForLink, sometimes different than PropertyName?

        Our TVectorXxxPersistent, TCastleColorPersistent property editors
        modify the GetName (returned by "ActiveRow.Name" here)
        to remove "Persistent" suffix.
        And in their case, we want to link to the version without "Persistent"
        suffix.

        But we need to use the version with "Persistent" for GetPropInfo
        as only "XxxPersistent" is published and actually available using RTTI,
        so we also return real PropertyName.

        For other properties (without "persistent" suffix)
        the PropertyNameForLink is equal to PropertyName.
        This way we avoid using weird names set by property editors, like "Angle W",
        for links. }
      if IsSuffix('persistent', PropertyName, true) then
        PropertyNameForLink := ActiveRow.Name
      else
        PropertyNameForLink := PropertyName;
      Result := true;
    end else
      Result := false;
  end;

  function GetFirstSelected: TComponent;
  var
    Selected: TComponentList;
    SelectedCount: Integer;
  begin
    Result := SelectedComponent;

    { In case multiple components are selected, try to return something non-nil:
      namely return the 1st component. This makes pressing F1 when a property is selected
      with multiple components sensible. They usually have equal class. }
    if Result = nil then
    begin
      GetSelected(Selected, SelectedCount);
      try
        if SelectedCount >= 1 then
          Result := Selected[0];
      finally FreeAndNil(Selected) end;
    end;
  end;

var
  C: TComponent;
  PropertyInstance: TObject;
  PropertyName, PropertyNameForLink: String;
begin
  C := GetFirstSelected;
  if C <> nil then
  begin
    { We do not use C for PropertyInstance, because in case of property
      in SubComponent, PropertyInstance needs to be <> nil.
      For example if you click F1 when being over "Blending" inside
      TCastleScene.RenderOptions. }
    if SelectedProperty(PropertyInstance, PropertyName, PropertyNameForLink) then
      Url := ApiReference(PropertyInstance, PropertyName, PropertyNameForLink)
    else
      Url := ApiReference(C, '', '');
  end;
end;

procedure TDesignFrame.UpdateCurrentViewport;
var
  NewCurrentViewport: TCastleViewport;
  HoverUi: TCastleUserInterface;
begin
  { try SelectedViewport }
  NewCurrentViewport := SelectedViewport;

  if NewCurrentViewport = nil then
  begin
    { try HoverUserInterface as TCastleViewport }
    HoverUi := FDesignerLayer.HoverUserInterface(
      CastleControl.Container.MousePosition, true);
    if HoverUi is TCastleViewport then // also checks HoverUi <> nil
      NewCurrentViewport := TCastleViewport(HoverUi)
    else
    { try HoverUserInterface as TCastleViewport child, like TCastleNavigation, TCastleTouchNavigation }
    if (HoverUi <> nil) and (HoverUi.Parent is TCastleViewport) then // also checks HoverUi.Parent <> nil
      NewCurrentViewport := TCastleViewport(HoverUi.Parent);
  end;

  if NewCurrentViewport <> nil then
    SetCurrentViewport(NewCurrentViewport);
  { otherwise keep using FCurrentViewport we had so far }
end;

procedure TDesignFrame.SetCurrentViewport(const Value: TCastleViewport);
begin
  if FCurrentViewport <> Value then
  begin
    FCurrentViewport := Value;
    FCurrentViewportObserver.Observed := Value;
    { After changing CurrentViewport, show colliders on new viewport.
      TODO: It would be better if toggling this checkbox
      set them already properly on all viewports. }
    if Value <> nil then
      UpdateColliders;
    if Assigned(OnCurrentViewportChanged) then
      OnCurrentViewportChanged(Self);
  end;
end;

procedure TDesignFrame.CurrentViewportFreeNotification(
  const Sender: TFreeNotificationObserver);
begin
  FCurrentViewport := nil;
  if Assigned(OnCurrentViewportChanged) then
    OnCurrentViewportChanged(Self);
end;

const
  CameraTransitionTime = 0.25;

procedure TDesignFrame.ViewportViewAxis(const Dir, Up: TVector3);
var
  V: TCastleViewport;
  Box: TBox3D;
  CenterPoint, NewPos: TVector3;
  Distance: Single;
begin
  V := CurrentViewport;
  if V = nil then Exit;
  if V.Items = nil then Exit;

  if (TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 0) then
  begin
    CenterPoint := TransformManipulate.SelectionWorkingCenter;
    Distance := Max(1.0, PointsDistance(V.InternalCamera.WorldTranslation, CenterPoint));
  end else
  begin
    Box := V.Items.BoundingBox;
    if not Box.IsEmpty then
    begin
      CenterPoint := Box.Center;
      Distance := Max(1.0, PointsDistance(V.InternalCamera.WorldTranslation, CenterPoint));
    end else
    begin
      CenterPoint := TVector3.Zero;
      Distance := 10.0;
    end;
  end;

  NewPos := CenterPoint - Dir * Distance;
  FixCamera2D(V, NewPos, Dir, Up);
  V.InternalCamera.AnimateTo(NewPos, Dir, Up, CameraTransitionTime);
end;

procedure TDesignFrame.FixCamera2D(const V: TCastleViewport; var Pos: TVector3; const Dir, Up: TVector3);
begin
  if (V.InternalCamera.ProjectionType = ptOrthographic) and
     TVector3.Equals(Dir, Vector3(0, 0, -1)) and
     TVector3.Equals(Up, Vector3(0, 1, 0)) then
  begin
    if V.Camera <> nil then
      Pos.Z := V.Camera.Translation.Z
    else
      Pos.Z := Default2DCameraZ;

    Pos.X := Pos.X - (0.5 - V.InternalCamera.Orthographic.Origin.X) * V.InternalCamera.Orthographic.EffectiveRect.Width;
    Pos.Y := Pos.Y - (0.5 - V.InternalCamera.Orthographic.Origin.Y) * V.InternalCamera.Orthographic.EffectiveRect.Height;
  end;
end;

procedure TDesignFrame.ViewportViewBox(const V: TCastleViewport; Box: TBox3D);
var
  APos, ADir, AUp: TVector3;
  IntersectionDistance: Single;
begin
  // in particular, condition below means we don't do anything if no TCastleTransform selected
  if not Box.IsEmpty then
  begin
    V.InternalCamera.GetWorldView(APos, ADir, AUp);

    { Convert Box to use maximum size in all 3 dimensions.
      This results in better camera view for boxes mostly flat in 1 dimension. }
    Box := Box3DAroundPoint(Box.Center, Box.Size.Max);
    if not Box.TryRayClosestIntersection(IntersectionDistance, Box.Center, -ADir) then
    begin
      { TryRayClosestIntersection may return false for box with size zero
        (though not observed in practice),
        only then ray from Box.Center may not hit one of box walls. }
      IntersectionDistance := 1;
      WritelnWarning('Ray from box center didn''t hit any of box walls');
    end;
    APos := Box.Center - ADir * IntersectionDistance * 2;

    { Older version of this routine was doing:

    CameraViewpointForWholeScene(Box, 2, 1, false, true,
      APos, ADir, AUp, AGravityUp);

    New version only modifies the camera position, preserving existing
    dir, up. This is more flexible for movement by key shortcuts,
    and consistent with
    - Blender home
    - Unity F
    - Godot O
    }

    FixCamera2D(V, APos, ADir, AUp);
    V.InternalCamera.AnimateTo(APos, ADir, AUp, CameraTransitionTime);
  end;
end;

procedure TDesignFrame.ViewportViewAll;
var
  V: TCastleViewport;
begin
  V := CurrentViewport;
  if V = nil then Exit;

  if V.Items <> nil then
    ViewportViewBox(V, V.Items.BoundingBox);
end;

procedure TDesignFrame.ViewportViewSelected;

  { Determine selected TCastleTransform based on selected component, or @nil.
    This routine treats selecting a behavior just like selecting a transform,
    so that pressing F on behavior works. }
  function TransformFromSelected(const C: TComponent): TCastleTransform;
  begin
    if C is TCastleTransform then
      Result := TCastleTransform(C)
    else
    if C is TCastleBehavior then
      Result := TCastleBehavior(C).Parent
    else
      Result := nil;
  end;

var
  Selected: TComponentList;
  SelectedCount, I: Integer;
  SelectedBox: TBox3D;
  V: TCastleViewport;
  T: TCastleTransform;
begin
  V := CurrentViewport;
  if V = nil then Exit;

  SelectedBox := TBox3D.Empty;

  GetSelected(Selected, SelectedCount);
  try
    for I := 0 to SelectedCount - 1 do
    begin
      T := TransformFromSelected(Selected[I]);
      if (T <> nil) and
         (T.World = V.Items) then
        SelectedBox := SelectedBox + T.WorldBoundingBox;
    end;
  finally FreeAndNil(Selected) end;

  ViewportViewBox(V, SelectedBox);
end;

function TDesignFrame.ComponentCaption(const C: TComponent): String;

  function ClassCaption(const C: TClass): String;
  begin
    Result := C.ClassName;

    // hide some internal classes by instead displaying ancestor name
    // No point in doing this now
    // if C = Txxx then
    //   Result := ClassCaption(C.ClassParent);
  end;

begin
  Result := C.Name + ' (' + ClassCaption(C.ClassType) + ')';
end;

function TDesignFrame.TreeNodeCaption(const C: TComponent): String;
begin
  Result := C.Name;
end;

(* TODO: Show UI scaling somewhere?

procedure TDesignFrame.CastleControlResize(Sender: TObject);
var
  CalculatedUIScale: Single;
  H, CalculatedUIScaleStr: String;
begin
  // trick to get private TCastleContainer.FCalculatedUIScale
  CalculatedUIScale :=  (1 / CastleControl.Container.UnscaledWidth) *
    CastleControl.Container.Width;
  CalculatedUIScaleStr := IntToStr(Round(CalculatedUIScale * 100)) + '%';

  LabelUIScaling.Caption := CalculatedUIScaleStr;
  case CastleControl.Container.UIScaling of
    usNone                : H := 'No user interface scaling';
    usEncloseReferenceSize: H := Format('User interface scaling in effect: window must enclose a reference size of %f x %f.' + NL,
      [CastleControl.Container.UIReferenceWidth,
       CastleControl.Container.UIReferenceHeight]);
    usEncloseReferenceSizeAutoOrientation:...
    usFitReferenceSize    : H := Format('User interface scaling in effect: window must fit inside a reference size of %f x %f.' + NL,
      [CastleControl.Container.UIReferenceWidth,
       CastleControl.Container.UIReferenceHeight]);
    usExplicitScale       : H := Format('User interface scaling in effect: explicit scale %f.' + NL,
      [CastleControl.Container.UIExplicitScale]);
    usDpiScale            : H := Format('User interface scaling in effect: scale to follow DPI (pixels per inch). DPI detected now is %f.' + NL,
      [CastleControl.Container.Dpi]);
    else raise EInternalError.Create('CastleControl.Container.UIScaling?');
  end;
  if CastleControl.Container.UIScaling <> usNone then
  begin
    H := Format(H +
      'Actual window size is %d x %d.' + NL +
      'Calculated scale is %s, which simulates surface of size %f x %f.',
      [CastleControl.Container.Width,
       CastleControl.Container.Height,
       CalculatedUIScaleStr,
       CastleControl.Container.UnscaledWidth,
       CastleControl.Container.UnscaledHeight]);
  end;
  LabelUIScaling.Hint := H;
end;
*)

procedure TDesignFrame.CastleControlGLContextOpen(Sender: TObject);

  procedure ReadSettings;
  var
    SettingsUrl: String;
  begin
    SettingsUrl := 'castle-data:/CastleSettings.xml';
    if UriFileExists(SettingsUrl) then
    try
      CastleControl.Container.LoadSettings(SettingsUrl);
    except
      on E: Exception do
      begin
        { Showing a message box (using ErrorBox, which calls LCL MessageDlg)
          from CastleControl.OnOpen (after OpenGL context is initialized)
          is not reliable.

          - WinAPI widgetset: works OK.
          - GTK widgetset: shows an empty message box (seems like the rendered text
            is invisible), and shows GTK error in the console
            (castle-editor:6999): Gtk-CRITICAL **: 21:23:50.518: IA__gtk_widget_realize: assertion 'GTK_WIDGET_ANCHORED (widget) || GTK_IS_INVISIBLE (widget)' failed

          To workaround this, we set PendingErrorBox field here,
          instead of showing ErrorBox immediately.
        }
        PendingErrorBox := SAppendPart(PendingErrorBox, NL,
          'An error occurred when reading the CastleSettings.xml file in your project:' +
          NL + NL + ExceptMessage(E));
        { and continue, this way you can still open a project with broken
          CastleSettings.xml }
      end;
    end;
  end;

begin
  ReadSettings;
end;

procedure TDesignFrame.CastleControlUpdate(const Sender: TCastleUserInterface;
  const SecondsPassed: Single; var HandleInput: Boolean);

  function ViewportDebugInfo(const V: TCastleViewport): String;

    function CameraDirectionStr: String;
    begin
      { This detection matches TProjectForm.ActionViewport*Execute methods in CGE editor. }
      if TVector3.Equals(V.InternalCamera.Direction, Vector3(0, -1, 0)) then
        Result := 'Top '
      else
      if TVector3.Equals(V.InternalCamera.Direction, Vector3(0, 1, 0)) then
        Result := 'Bottom '
      else
      if TVector3.Equals(V.InternalCamera.Direction, Vector3(0, 0, -1)) then
        Result := 'Front '
      else
      if TVector3.Equals(V.InternalCamera.Direction, Vector3(0, 0, 1)) then
        Result := 'Back '
      else
      if TVector3.Equals(V.InternalCamera.Direction, Vector3(1, 0, 0)) then
        Result := 'Left '
      else
      if TVector3.Equals(V.InternalCamera.Direction, Vector3(-1, 0, 0)) then
        Result := 'Right '
      else
        Result := '';
    end;

    function ProjectionStr: String;
    begin
      Result := ProjectionTypeToStr(V.InternalCamera.ProjectionType);
    end;

    function DesignNavigationStr: String;
    const
      Names: array [TInternalDesignNavigationType] of String = ('Fly', 'Examine', '2D');
    begin
      if not V.InternalDesignManipulation then
      begin
        WritelnWarning('Viewport not in design mode, but selected (submit a bug): %s', [V.Name]);
        Exit;
      end;
      Result := Names[V.InternalDesignNavigationType];
      { // speed is now shown using a label displayed by TCastleWalkNavigationDesign
      if V.InternalDesignNavigationType = dnFly then
        Result := Result + Format(' (speed %f)', [
          (V.InternalDesignNavigation as TCastleWalkNavigation).MoveSpeed
        ]);
      }
    end;

  begin
    Result := V.Name + ': ' + CameraDirectionStr + ProjectionStr + ' ' + NL +
      DesignNavigationStr;
  end;

  (*
  Unused debug routine to dump current selection of ControlsTree,
  derived from various properties.

  procedure DebugControlsTreeSelection;
  var
    S: String;
    I: Integer;
  begin
    S := '';

    if ControlsTree.Selected <> nil then
      S := S + 'Selected non-nil: ' + ControlsTree.Selected.Text + LineEnding
    else
      S := S + 'Selected nil' + LineEnding;

    if ControlsTreeOneSelected <> nil then
      S := S + 'OneSelected non-nil: ' + ControlsTreeOneSelected.Text + LineEnding
    else
      S := S + 'OneSelected nil' + LineEnding;

    S := S + 'SelectionCount: ' + IntToStr(ControlsTree.SelectionCount) + LineEnding;

    for I := 0 to ControlsTree.SelectionCount - 1 do
      S := S + IntToStr(I) + ': ' + ControlsTree.Selections[I].Text + LineEnding;

    LabelTreeDEbug.Caption := S;
  end;
  *)

var
  SavedErrorBox: String;
begin
  { process PendingErrorBox }
  if PendingErrorBox <> '' then
  begin
    SavedErrorBox := PendingErrorBox;
    { Clear PendingErrorBox *before* doing ErrorBox, as on WinAPI,
      the CastleControlUpdate will keep occurring underneath the box,
      and we would spawn ~infinite number of ErrorBox.
      This can happen e.g. in case of invalid CastleSettings.xml file,
      that sets PendingErrorBox. }
    PendingErrorBox := '';
    ErrorBox(SavedErrorBox);
  end;

  if InternalCastleDesignInvalidate then
  begin
    UpdateDesign;
    //WritelnWarning('CGE needed to explicitly tell editor to refresh hierarchy');
    ModifiedOutsideObjectInspector('', ucLow);
  end;

  { Hide some tabs if they don't contain anything. }
  TabLayout.TabVisible :=
    (Inspector[itLayout].RowCount <> 0) or
    PanelLayoutTransform.Visible or
    PanelAnchors.Visible;
  TabEvents.TabVisible :=
    (Inspector[itEvents].RowCount <> 0);

  UpdateCurrentViewport;

  LabelViewport.Visible := FCurrentViewport <> nil;
  if FCurrentViewport <> nil then
    LabelViewport.Caption := ViewportDebugInfo(FCurrentViewport);

  FDesignerLayer.LayerPhysicsSimulation.Exists := CastleApplicationMode in [appSimulation, appSimulationPaused];
  FDesignerLayer.LabelPhysicsSimulationRunning.Exists := CastleApplicationMode = appSimulation;
  FDesignerLayer.LabelPhysicsSimulationPaused.Exists := CastleApplicationMode = appSimulationPaused;
end;

procedure TDesignFrame.CastleControlDragOver(Sender, Source: TObject; X,
  Y: Integer; State: TDragState; var Accept: Boolean);
var
  SourceShellList: TCastleShellListView;
  UI: TCastleUserInterface;
  ParentComponent: TComponent;
begin
  Accept := false;
  if Source is TCastleShellListView then
  begin
    SourceShellList := TCastleShellListView(Source);
    UI := FDesignerLayer.HoverUserInterface(Vector2(X, CastleControl.Height - Y));
    if (UI is TCastleViewport) and not (ssShift in GetKeyShiftState) then
      ParentComponent := TCastleViewport(UI).Items
    else
      ParentComponent := UI;
    if ParentComponent = nil then // may happen because UI was nil
      Exit;

    Accept := ShellListComponentClass(SourceShellList, ParentComponent) <> nil;
  end;
end;

procedure TDesignFrame.CastleControlDragDrop(Sender, Source: TObject; X, Y: Integer);

  { Calculate 3D position of a TCastleTransform created by drag-and-drop on a vieport. }
  function DropPosition(const Viewport: TCastleViewport; out DropPos: TVector3): Boolean;
  var
    RayOrigin, RayDirection: TVector3;
    RayHit: TRayCollision;
    Distance: Single;
    OldPickable: Boolean;
    PlaneZ: Single;
    Cam: TCastleCamera;
  begin
    Result := true;

    Cam := Viewport.InternalCamera;
    if Cam = nil then
    begin
      WritelnWarning('Cannot drop on the viewport %s, as it has no camera (not even a design-time camera)', [
        Viewport.Name
      ]);
      Exit(false);
    end;

    { Make gizmos not pickable when looking for new scene position,
      because ray can hit on gizmo. }
    OldPickable := TransformManipulate.Pickable;
    try
      TransformManipulate.Pickable := false;
      Viewport.PositionToRay(Vector2(X, CastleControl.Height - Y), true, RayOrigin, RayDirection);
      RayHit := Viewport.Items.WorldRay(RayOrigin, RayDirection);
    finally
      TransformManipulate.Pickable := OldPickable;
    end;

    if (RayHit = nil) and (Cam.ProjectionType = ptOrthographic) then
    begin
      { In the past, we used to calculate this as
        "(Cam.EffectiveProjectionNear + Cam.EffectiveProjectionFar) / 2".

        But now that we auto-calculate projection, the above "smart" calculation is
        - unnecessary (projection will adjust to new item)
        - often results in weird values (as projection near/far are often "around zero"
          but usually their average is not exactly zero, as users expect zero).
      }
      PlaneZ := 0;
      if not TrySimplePlaneRayIntersection(DropPos, 2, PlaneZ, RayOrigin, RayDirection) then
        Exit(false); // camera direction parallel to 3D plane with Z = constant
    end else
    begin
      if RayHit <> nil then
      begin
        Distance := RayHit.Distance;
        FreeAndNil(RayHit);
      end else
      begin
        { If we don't hit any other scene set Distance to default value. }
        Distance := 10;
      end;
      DropPos := RayOrigin + (RayDirection * Distance);

      { In case of 2D game move scene a little closser to camera }
      if Cam.ProjectionType = ptOrthographic then
        DropPos := DropPos - Cam.Direction;
    end;
  end;

var
  SourceShellList: TCastleShellListView;
  ParentComponent, NewComponent: TComponent;
  NewComponentClass: TComponentClass;
  UI: TCastleUserInterface;
  Viewport: TCastleViewport;
  DropPosition2D: TVector2;
  DropPos: TVector3;
  Transform: TCastleTransform;
begin
  if Source is TCastleShellListView then
  begin
    SourceShellList := TCastleShellListView(Source);
    DropPosition2D := Vector2(X, CastleControl.Height - Y);

    { calculate ParentComponent and UI }
    if DesignRoot is TCastleTransform then
    begin
      { When we edit .castle-transform design, then the parent to drop must be DesignRoot.
        Not the Viewport, not even Viewport.Items -- only things inside DesignRoot
        are the hierarchy edited by user. }
      ParentComponent := DesignRoot;
      Assert(FDesignViewportForTransforms <> nil);
      UI := FDesignViewportForTransforms;
    end else
    begin
      UI := FDesignerLayer.HoverUserInterface(DropPosition2D);
      if (UI is TCastleViewport) and not (ssShift in GetKeyShiftState) then
        ParentComponent := TCastleViewport(UI).Items
      else
        ParentComponent := UI;
    end;

    if ParentComponent = nil then // may happen because UI was nil
      Exit;

    NewComponentClass := ShellListComponentClass(SourceShellList, ParentComponent);
    if NewComponentClass = nil then
      Exit;

    if NewComponentClass.InheritsFrom(TCastleTransform) then
    begin
      if not (UI is TCastleViewport) then
      begin
        WritelnWarning('Cannot drag-and-drop %s on UI %s', [
          NewComponentClass.ClassName,
          UI.ClassName
        ]);
        Exit;
      end;
      Viewport := TCastleViewport(UI);

      if not DropPosition(Viewport, DropPos) then
      begin
        WritelnWarning('Cannot drag-and-drop %s on viewport, cannot determine drop position', [
          NewComponentClass.ClassName
        ]);
        Exit;
      end;

      { We can assume that ShellListAddComponent creates non-nil,
        and TCastleTransform, because ShellListComponentClass
        returned non-nil TCastleTransform descendant. }
      Transform := ShellListAddComponent(SourceShellList, ParentComponent) as TCastleTransform;
      if (TransformManipulate <> nil) and (TransformManipulate.TranslateSnap > 0) then
      begin
        DropPos.X := Round(DropPos.X / TransformManipulate.TranslateSnap) * TransformManipulate.TranslateSnap;
        DropPos.Z := Round(DropPos.Z / TransformManipulate.TranslateSnap) * TransformManipulate.TranslateSnap;
      end;
      Transform.Translation := DropPos;
      WritelnLog('Dropped transform %s:%s into viewport %s at translation %s', [
        Transform.Name,
        Transform.ClassName,
        Viewport.Name,
        DropPos.ToString
      ]);
    end else
    if NewComponentClass.InheritsFrom(TCastleUserInterface) then
    begin
      NewComponent := ShellListAddComponent(SourceShellList, ParentComponent);
      if (NewComponent is TCastleUserInterface) and
         (ParentComponent is TCastleUserInterface) then
      begin
        TCastleUserInterface(NewComponent).Translation :=
          TCastleUserInterface(ParentComponent).ContainerToLocalPosition(DropPosition2D, true);
      end;
    end else
    begin
      WritelnWarning('Cannot drag-and-drop %s on UI %s', [
        NewComponentClass.ClassName,
        UI.ClassName
      ]);
    end;
  end;
end;

const
  LoadUiDesign_FileFilters = 'CGE User Interace Design (*.castle-user-interface)|*.castle-user-interface';
  LoadTransformDesign_FileFilters = 'CGE Transform Design (*.castle-transform)|*.castle-transform';

function TDesignFrame.ShellListComponentClass(const SourceShellList: TCastleShellListView;
  const ParentComponent: TComponent): TComponentClass;
var
  SelectedFileName: String;
  SelectedUrl: String;
  PreferTransform: Boolean;
begin
  Result := nil;
  PreferTransform := ParentComponent is TCastleTransform;

  { SourceShellList.Selected may be nil, testcase:
    - open any project (empty from template is OK)
    - create new design using menu item
      (looks like this step is necessary into tricking LCL that we're
      in the middle of drag-and-drop on GTK?)
    - double-click on some design file in data/ by double-clicking
    - mouse over the design -> without this check, would have access violation
      due to TDesignFrame.CastleControlDragOver being called with
      ShellList.Selected = nil. }

  if SourceShellList.Selected <> nil then
  begin
    SelectedFileName := SourceShellList.GetPathFromItem(SourceShellList.Selected);
    SelectedUrl := MaybeUseDataProtocol(FilenameToUriSafe(SelectedFileName));

    if LoadImage_FileFilters.Matches(SelectedUrl) then
    begin
      if PreferTransform then
        Result := TCastleImageTransform
      else
        Result := TCastleImageControl;
    end else
    // check LoadTiledMap_FileFilters before LoadScene_FileFilters, since *.tmx matches both
    if TFileFilterList.Matches(LoadTiledMap_FileFilters, SelectedUrl) then
      Result := TCastleTiledMap
    else
    if TFileFilterList.Matches(LoadScene_FileFilters, SelectedUrl) then
      Result := TCastleScene
    else
    if TFileFilterList.Matches(LoadSound_FileFilters, SelectedUrl) then
      Result := TCastleTransform // ShellListAddComponent creates TCastleTransform with TCastleSoundSource behavior
    else
    if TFileFilterList.Matches(LoadUiDesign_FileFilters, SelectedUrl) then
      Result := TCastleDesign
    else
    if TFileFilterList.Matches(LoadTransformDesign_FileFilters, SelectedUrl) then
      Result := TCastleTransformDesign;
  end;
end;

function TDesignFrame.ShellListAddComponent(const SourceShellList: TCastleShellListView;
  const ParentComponent: TComponent): TComponent;
var
  SelectedFileName, SelectedUrl: String;
begin
  Result := nil;
  if SourceShellList.Selected <> nil then
  begin
    SelectedFileName := SourceShellList.GetPathFromItem(SourceShellList.Selected);
    SelectedUrl := MaybeUseDataProtocol(FilenameToUriSafe(SelectedFileName));
    Result := AddComponentFromUrl(SelectedUrl, ParentComponent);
  end;
end;

procedure TDesignFrame.SetMaximizePreview(const AValue: Boolean);
begin
  if FMaximizePreview <> AValue then
  begin
    FMaximizePreview := AValue;
    SetEnabledVisible(PanelRight, not AValue);
    SetEnabledVisible(PanelLeft, not AValue);
  end;
end;

function TDesignFrame.AddComponentFromUrl(const AddUrl: String;
  const ParentComponent: TComponent): TComponent;
var
  BaseNameFromUrl: String;

  function AddImageTransform(const Url: String): TCastleImageTransform;
  begin
    Result := AddComponent(ParentComponent, TCastleImageTransform, nil,
      'Image' + BaseNameFromUrl) as TCastleImageTransform;
    Result.Url := Url;
  end;

  function AddImageControl(const Url: String): TCastleImageControl;
  begin
    Result := AddComponent(ParentComponent, TCastleImageControl, nil,
      'Image' + BaseNameFromUrl) as TCastleImageControl;
    Result.Url := Url;
  end;

  function AddScene(const Url: String): TCastleScene;
  begin
    Result := AddComponent(ParentComponent, TCastleScene, nil,
      'Scene' + BaseNameFromUrl) as TCastleScene;
    Result.Url := Url;
  end;

  function AddTiledMap(const Url: String): TCastleTiledMap;
  begin
    Result := AddComponent(ParentComponent, TCastleTiledMap, nil,
      'TiledMap' + BaseNameFromUrl) as TCastleTiledMap;
    Result.Url := Url;
  end;

  function AddSound(const Url: String): TCastleTransform;
  var
    SoundSource: TCastleSoundSource;
    Sound: TCastleSound;
  begin
    Result := AddComponent(ParentComponent, TCastleTransform, nil,
      'Transform' + BaseNameFromUrl) as TCastleTransform;
    SoundSource := AddComponent(Result, TCastleSoundSource, nil,
      'SoundSource' + BaseNameFromUrl) as TCastleSoundSource;
    Sound := AddComponent(SoundSource, TCastleSound, nil,
      'Sound' + BaseNameFromUrl) as TCastleSound;
    Sound.Url := Url;
    SoundSource.Sound := Sound;
  end;

  function AddUiDesign(const Url: String): TCastleDesign;
  begin
    Result := AddComponent(ParentComponent, TCastleDesign, nil,
      'Design' + BaseNameFromUrl) as TCastleDesign;
    Result.Url := Url;
  end;

  function AddTransformDesign(const Url: String): TCastleTransformDesign;
  begin
    Result := AddComponent(ParentComponent, TCastleTransformDesign, nil,
      'Design' + BaseNameFromUrl) as TCastleTransformDesign;
    Result.Url := Url;
  end;

var
  PreferTransform: Boolean;
begin
  Result := nil;
  PreferTransform := ParentComponent is TCastleTransform;
  BaseNameFromUrl := GetBaseNameFromUrl(AddUrl);
  if LoadImage_FileFilters.Matches(AddUrl) then
  begin
    if PreferTransform then
      Result := AddImageTransform(AddUrl)
    else
      Result := AddImageControl(AddUrl);
  end else
  if TFileFilterList.Matches(LoadTiledMap_FileFilters, AddUrl) then
    Result := AddTiledMap(AddUrl)
  else
  if TFileFilterList.Matches(LoadScene_FileFilters, AddUrl) then
    Result := AddScene(AddUrl)
  else
  if TFileFilterList.Matches(LoadSound_FileFilters, AddUrl) then
    Result := AddSound(AddUrl)
  else
  if TFileFilterList.Matches(LoadUiDesign_FileFilters, AddUrl) then
    Result := AddUiDesign(AddUrl)
  else
  if TFileFilterList.Matches(LoadTransformDesign_FileFilters, AddUrl) then
    Result := AddTransformDesign(AddUrl);

  { Warn if URL file, which can happen if you drag-and-drop from
    e.g. project top-level instead of "data".
    This is likely a mistake, and want to communicate to user why. }
  if (Result <> nil) and
     (UriProtocol(AddUrl) = 'file') then
    WarningBox(Format('Added component has URL pointing to a local filename: "%s".' + NL +
      NL +
      'This will likely not work when you open the project on another computer.' + NL +
      NL +
      'We advise to instead place all data files in "data" subdirectory and reference them using "castle-data:/" URLs.', [
      AddUrl
      ]
    ));
end;

function TDesignFrame.AddImported(const AddUrl: String): TComponent;
var
  ParentComponent: TComponent;
begin
  ParentComponent := SelectedComponent;

  { If AddUrl makes sense only with parent being TCastleTransform,
    try to use CurrentViewport.Items as parent.
    This way we "try harder" to find a parent that allows to drop
    given item. }
  if (not (ParentComponent is TCastleTransform)) and
     (CurrentViewport <> nil) and
     (
       // AddUrl can only be loaded to TCastleScene?
       ( TFileFilterList.Matches(LoadScene_FileFilters, AddUrl) and
         (not LoadImage_FileFilters.Matches(AddUrl)) ) or
       // AddUrl can only be loaded to TCastleTransformDesign?
       (TFileFilterList.Matches(LoadTransformDesign_FileFilters, AddUrl))
     ) then
    ParentComponent := CurrentViewport.Items;

  if ParentComponent = nil then
    raise Exception.CreateFmt('Cannot add imported component "%s".' + NL + NL + 'First select a valid parent in the design, usually a TCastleViewport or TCastleTransform.', [
      UriDisplay(AddUrl)
    ]);

  Result := AddComponentFromUrl(AddUrl, ParentComponent);
end;

procedure TDesignFrame.SetShowColliders(const AValue: Boolean);
begin
  if FShowColliders <> AValue then
  begin
    FShowColliders := AValue;
    if ButtonShowColliders <> nil then
      ButtonShowColliders.Down := FShowColliders;
    UpdateColliders;
  end;
end;

procedure TDesignFrame.MenuItemChangeClassClick(Sender: TObject);
var
  NewDesignOwner, NewDesignRoot, Sel: TComponent;
  LoadInfo: TInternalComponentLoadInfo;
  R: TRegisteredComponent;
  SavedSelection: TSavedSelection;
begin
  Sel := SelectedComponent;
  Assert(Sel <> nil); // menu item should be disabled otherwise

  R := TRegisteredComponent(Pointer((Sender as TComponent).Tag));

  if Sel.ClassType = R.ComponentClass then
  begin
    ErrorBox(Format('Component "%s" already has class "%s", no change is necessary.', [
        Sel.Name,
        Sel.ClassName
      ]));
    Exit;
  end;

  if YesNoBox('Change Component Class',
       Format('Changing component class is a potentially dangerous operation. All the properties you set in the current class that don''t exist in new class will be simply discarded.' + NL +
         NL +
         'Are you sure you want to change class of component "%s" from "%s" to "%s"?', [
         Sel.Name,
         Sel.ClassName,
         R.ComponentClass.ClassName
       ])) then
  begin
    SavedSelection := GetSavedSelection;

    LoadInfo := TInternalComponentLoadInfo.Create;
    try
      LoadInfo.ChangeClassName := Sel.Name;
      LoadInfo.ChangeClassClass := R.ComponentClass;

      { To change class, we reload whole design, this way
        all references to Sel.Name will remain correct. }

      NewDesignOwner := TComponent.Create(Self);
      NewDesignRoot := InternalStringToComponent(ComponentToString(DesignRoot), NewDesignOwner, LoadInfo);
      OpenDesign(NewDesignRoot, NewDesignOwner, FDesignUrl);
    finally FreeAndNil(LoadInfo) end;

    RestoreSavedSelection(SavedSelection);

    { We use ucHigh, otherwise when changing light source type
      we'd have older comment "Change OlderComponentName".
      Note: We still need this ModifiedOutsideObjectInspector call,
      otherwise change "Change OlderComponentName" doesn't happen and there's
      no undo / no modified flag after this operation. }
    ModifiedOutsideObjectInspector('Change Class To ' + R.ComponentClass.ClassName, ucHigh);
  end;
end;

procedure TDesignFrame.InspectorFilter(const Sender: TObject;
  const AEditor: TPropertyEditor; var AShow: Boolean;
  const FilterBySection: Boolean; const Section: TPropertySection);
var
  PropertyName, PropQuery: String;
  Instance: TPersistent;
  HasPropFilter: Boolean;
begin
  AShow := false;

  if AEditor.GetPropInfo = nil then
    Exit;

  PropertyName := AEditor.GetPropInfo^.Name;
  if EditPropertyFilter <> nil then
    PropQuery := LowerCase(Trim(EditPropertyFilter.Text))
  else
    PropQuery := '';
  HasPropFilter := PropQuery <> '';

  if HasPropFilter and (Pos(PropQuery, LowerCase(PropertyName)) = 0) then
    Exit;

  if (AEditor.GetInstProp <> nil) and
     (AEditor.GetInstProp^.Instance <> nil) then
  begin
    Instance := AEditor.GetInstProp^.Instance;
    if Instance is TComponent then
    begin
      { Early exit: never show Name on components not owned by DesignOwner.
        Such components are subcomponents of something,
        like Camera.Perspective, and their Name is
        - shown weird (with dot, like 'Camera1.Perspective')
        - not useful to edit (we don't really want to allow editing it,
          you cannot search for such component later with DesignedComponent
          anyway, and the name must be unique within the owner -- better
          to leave it unedited) }
      if (PropertyName = 'Name') and
         (not RenamePossible(TComponent(Instance))) then
        Exit;

      { Hide editing transformation of TCastleAbstractRootTransform,
        as it makes very unintuitive behavior because desing-time camera is also
        a child of it, so e.g. moving Viewport.Items seems to do nothing
        (TODO: but it breaks how mouse look works -- it should not;
        but still we'd hide these properties anyway, even once we fix mouse look
        in this case). }
      if (Instance is TCastleAbstractRootTransform) and
         ( (PropertyName = 'CenterPersistent') or
           (PropertyName = 'ScaleOrientationPersistent') or
           (PropertyName = 'RotationPersistent') or
           (PropertyName = 'ScalePersistent') or
           (PropertyName = 'TranslationPersistent') or
           (PropertyName = 'DirectionPersistent') or
           (PropertyName = 'UpPersistent')
         ) then
        Exit;

      if FilterBySection and (not HasPropFilter) and (Instance is TCastleComponent) then
      begin
        AShow := Section in TCastleComponent(Instance).PropertySections(PropertyName);
      end else
      begin
        AShow := true;
      end;
    end else
    begin
      { Show=true when Instance is some non-TComponent class used for subcomponents,
        like TBorder, TCastleImagePersistent... }
      AShow := true;
    end;
  end;
end;

procedure TDesignFrame.EditPropertyFilterChange(Sender: TObject);
var
  InspectorType: TInspectorType;
begin
  for InspectorType in TInspectorType do
    if Inspector[InspectorType] <> nil then
      Inspector[InspectorType].BuildPropertyList;
end;

procedure TDesignFrame.GizmoTransformModifyBegin(Sender: TObject);
var
  I, InsertIdx: Integer;
  T, ParentComp, StationaryClone: TCastleTransform;
  CompStr: String;
  SelectedList: TComponentList;
  SelectedCount: Integer;
begin
  FAltDragDuplicated := false;
  if (CastleControl = nil) or (CastleControl.Container = nil) then Exit;
  if not (mkAlt in CastleControl.Container.Pressed.Modifiers) then Exit;
  if CastleApplicationMode <> appDesign then Exit;
  if (TransformManipulate = nil) or (TransformManipulate.SelectedCount = 0) or
     (DesignOwner = nil) then Exit;

  GetSelected(SelectedList, SelectedCount, false);
  try
    for I := 0 to TransformManipulate.SelectedCount - 1 do
    begin
      T := TransformManipulate.Selected[I];
      if (T = nil) or (not Deletable(T)) or (T.Parent = nil) then
        Continue;
      if (SelectedList <> nil) and IsComponentDescendantOfSelection(T, SelectedList) then
        Continue;

      ParentComp := T.Parent;
      CompStr := ComponentToString(T);
      StationaryClone := StringToComponent(CompStr, DesignOwner) as TCastleTransform;
      InsertIdx := ParentComp.List.IndexOf(T);
      if InsertIdx >= 0 then
        ParentComp.Insert(InsertIdx, StationaryClone)
      else
        ParentComp.Add(StationaryClone);
      FAltDragDuplicated := true;
    end;
    if FAltDragDuplicated then
      UndoSystem.ScheduleRecordUndoOnRelease := true;
  finally
    FreeAndNil(SelectedList);
  end;
end;

procedure TDesignFrame.GizmoTransformModified(Sender: TObject);
begin
  { Same comment as in Apply Drag:
    UndoOnRelease = true here means that we don't record the actual undo
    but defer it to GizmoTransformModifyEnd event }
  ModifiedOutsideObjectInspector('', ucLow, true); // UndoComment doesn't matter here
end;

procedure TDesignFrame.GizmoTransformModifyEnd(Sender: TObject);

  { Short summary of current selection passed to @link(SetSelected).
    Useful to show user in UI. }
  function SelectionCaption(const M: TCastleTransformManipulate): String;
  begin
    case M.SelectedCount of
      0: Result := 'nothing';
      1: Result := M.Selected[0].Name;
      else Result := Format('%d objects', [M.SelectedCount])
    end;
  end;

begin
  if FAltDragDuplicated then
  begin
    FAltDragDuplicated := false;
    UpdateDesign;
    UndoSystem.ScheduleRecordUndoOnRelease := false;
    RecordUndo('Alt-Drag Duplicate ' +
      SelectionCaption(Sender as TCastleTransformManipulate), ucHigh);
  end else
  if UndoSystem.ScheduleRecordUndoOnRelease then
    RecordUndo('Transform ' +
      SelectionCaption(Sender as TCastleTransformManipulate) +
      ' with Gizmo', ucHigh);
end;

procedure TDesignFrame.InspectorBasicFilter(Sender: TObject;
  AEditor: TPropertyEditor; var aShow: Boolean);
begin
  InspectorFilter(Sender, AEditor, AShow, true, psBasic);
end;

procedure TDesignFrame.InspectorLayoutFilter(Sender: TObject;
  AEditor: TPropertyEditor; var aShow: Boolean);
begin
  InspectorFilter(Sender, AEditor, AShow, true, psLayout);
end;

procedure TDesignFrame.InspectorAllFilter(Sender: TObject;
  AEditor: TPropertyEditor; var aShow: Boolean);
begin
  InspectorFilter(Sender, AEditor, AShow, false, {Section doesn't matter here}psBasic);
end;

function TDesignFrame.UndoMessageModified(const Sel: TPersistent;
  const ModifiedProperty, ModifiedValue: String; const SelectedCount: Integer): String;
const
  { Unreadable chars are defined like in SReplaceChars.
    Note they include newlines, we don't want to include newlines in undo description,
    as it would make menu item look weird (actually multiline on GTK2). }
  UnreadableChars = [Low(AnsiChar) .. Pred(' '), #128 .. High(AnsiChar)];
var
  ToValue: String;
begin
  if (Length(ModifiedValue) < 24) and (CharsPos(UnreadableChars, ModifiedValue) = 0) then
    ToValue := ' to ' + ModifiedValue
  else
    ToValue := '';

  { Right now, when SelectedCount = 1 then we know that Sel <> nil
    (but it is better to not depend on it).
    But it may not be TComponent, in case when changing property like X
    of TCastleVector3Persistent. }
  if (SelectedCount = 1) and
     (Sel is TComponent) then
    Result := 'Change ' + TComponent(Sel).Name + '.' + ModifiedProperty + ToValue
  else
  if SelectedCount > 1 then
    Result := 'Change ' + ModifiedProperty + ToValue + ' in multiple components'
  else
    Result := 'Change ' + ModifiedProperty + ToValue;
end;

procedure TDesignFrame.PropertyGridModified(Sender: TObject);

  { Do a subset of work that UpdateSelectedControl also does:
    update UI to reflect the current state of selected object,
    when the properties of the selected object possibly changed
    (but the selected object stays the same -- otherwise
    UpdateSelectedControl would do the full job.)

    It also updates ControlsTree,
    in case you changed the TComponent.Name. }
  procedure UpdateSelectedControlModified;
  var
    Sel: TComponent;
    SelUI: TCastleUserInterface;
    SelNode: TTreeNode;
  begin
    // This checks we have selected *exactly one* component.
    Sel := SelectedComponent;

    if Sel <> nil then
    begin
      // update also LabelControlSelected
      LabelControlSelected.Caption := 'Selected:' + NL + ComponentCaption(Sel);

      if Sel is TCastleUserInterface then
      begin
        SelUI := Sel as TCastleUserInterface;
        UpdateAnchors(SelUI, true);
      end;

      { Note that we use TreeNodeMap to find SelNode,
        not just assume that SelNode := ControlsTree.Selected.
        That is because in case of special tree items "Behaviors" or "Non-Visual Components",
        the ControlsTree.Selected could be different. }
      if TreeNodeMap.TryGetValue(Sel, SelNode) then
        SelNode.Text := TreeNodeCaption(Sel);
    end;

    UpdateSelectedInfo;
  end;

  procedure DoRecordUndo;
  var
    Selected: TComponentList;
    Sel: TComponent;
    SelectedCount: Integer;
  begin
    GetSelected(Selected, SelectedCount);
    try
      if SelectedCount = 0 then
      begin
        // Something has changed, but we don't know what exactly. Let's rebuild everything to be safe.
        UpdateDesign;
        RecordUndo('', ucLow); // We're recording a generic Undo message
      end else
      begin
        if SelectedCount = 1 then
          Sel := Selected[0]
        else
          Sel := nil;

        if Sender is TOICustomPropertyGrid then
        begin
          RecordUndo(
            UndoMessageModified(Sel, TOICustomPropertyGrid(Sender).GetActiveRow.Name,
            TOICustomPropertyGrid(Sender).CurrentEditValue, SelectedCount),
            ucHigh);
        end else
        { Sender is nil when PropertyGridModified is called
          by ModifiedOutsideObjectInspector. }
        if Sel <> nil then // so SelectedCount = 1
          RecordUndo('Change ' + Sel.Name, ucLow)
        else
        begin
          // we handled SelectedCount = 0 or 1 above
          Assert(SelectedCount > 1);
          RecordUndo('Change multiple components', ucLow)
        end;
      end;
    finally FreeAndNil(Selected) end;
  end;

begin
  UpdateSelectedControlModified;

  { When UndoSystem.ScheduleRecordUndoOnRelease we ignore changes,
    otherwise we would record an undo for every OnMotion of dragging. }
  if not UndoSystem.ScheduleRecordUndoOnRelease then
    DoRecordUndo;

  MarkModified;
end;

procedure TDesignFrame.PropertyEditorModified(Sender: TObject);

  { Call Invalidate on all Object Inspectors.
    This way editing a single property (like X to 10 of TCastleTransform.Translation)
    and pressing Enter immediately updates the vector value of it too
    (so it shows e.g. "0 0 10"). }
  procedure InvalidateInspectors;
  var
    It: TInspectorType;
  begin
    for It in TInspectorType do
      Inspector[It].Invalidate;
  end;

var
  Sel: TPersistent;
begin
  InvalidateInspectors;

  if Sender is TPropertyEditor then
  begin
    if TPropertyEditor(Sender).PropCount = 1 then
      Sel := TPropertyEditor(Sender).GetComponent(0)
    else
      Sel := nil;
    RecordUndo(
      UndoMessageModified(Sel, TPropertyEditor(Sender).GetName,
        TPropertyEditor(Sender).GetValue, TPropertyEditor(Sender).PropCount),
      ucHigh);

    { Need to set modified flag.
      PropertyGridModified also does this, but not everything causes PropertyGridModified,
      e.g. setting URL property (done by TPropertyEditor.SetStrValue that calls
      TPropertyEditor.Modified) only results in PropertyEditorModified call. }
    MarkModified;
  end else
    raise EInternalError.Create('PropertyEditorModified can only be called with TPropertyEditor as a Sender.');
end;

procedure TDesignFrame.PropertyGridCollectionItemClick(Sender: TObject);
var
  SelectionForOI: TPersistentSelectionList;
  InspectorType: TInspectorType;
  Ed: TCollectionPropertyEditorForm;
  ListBox: TListBox;
begin
  SelectionForOI := TPersistentSelectionList.Create;
  try
    ListBox := Sender as TListBox;
    if ListBox.ItemIndex >= 0 then
    begin
      Ed := ListBox.Parent as TCollectionPropertyEditorForm;
      SelectionForOI.Add(Ed.Collection.Items[ListBox.ItemIndex]);
      for InspectorType in TInspectorType do
        Inspector[InspectorType].Selection := SelectionForOI;
    end;
  finally FreeAndNil(SelectionForOI) end;
end;

procedure TDesignFrame.PropertyGridCollectionItemClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  UpdateSelectedControl;
end;

procedure TDesignFrame.PropertyGridCollectionItemAdd(Sender: TObject);
begin
  ((Sender as TToolButton).Parent.Parent as TCollectionPropertyEditorForm).actAddExecute(Sender);
  RecordUndo('Add item', ucLow);
end;

procedure TDesignFrame.PropertyGridCollectionItemDelete(Sender: TObject);
begin
  ((Sender as TToolButton).Parent.Parent as TCollectionPropertyEditorForm).actDelExecute(Sender);
  RecordUndo('Delete item', ucLow);
end;

procedure TDesignFrame.PropertyGridCollectionItemMoveUp(Sender: TObject);
var
  FakeSender: TComponent;
begin
  FakeSender := TComponent.Create(nil);
  try
    { This is a weird decision. It depends on sender's name to determine if
      it should move item up or move item down }
    FakeSender.Name := 'actMoveUp';
    ((Sender as TToolButton).Parent.Parent as TCollectionPropertyEditorForm).actMoveUpDownExecute(FakeSender);
    RecordUndo('Move item up', ucLow);
  finally
    FreeAndNil(FakeSender);
  end;
end;

procedure TDesignFrame.PropertyGridCollectionItemMoveDown(Sender: TObject);
var
  FakeSender: TComponent;
begin
  FakeSender := TComponent.Create(nil);
  try
    { This is a weird decision. It depends on sender's name to determine if
      it should move item up or move item down }
    FakeSender.Name := 'actMoveDown';
    ((Sender as TToolButton).Parent.Parent as TCollectionPropertyEditorForm).actMoveUpDownExecute(FakeSender);
    RecordUndo('Move item down', ucLow);
  finally
    FreeAndNil(FakeSender);
  end;
end;

procedure TDesignFrame.UpdateEditorDataForPropertyEditors;
begin
  if PropertyEditorHook <> nil then
  begin
    PropertyEditorHook.InspectorAreaOnScreen.Left := ProjectForm.Left +
      Left + PanelRight.Left;
    PropertyEditorHook.InspectorAreaOnScreen.Top := ProjectForm.Top +
      Top + PanelRight.Top + ControlProperties.Top  + 10;
    PropertyEditorHook.InspectorAreaOnScreen.Width := ControlProperties.Width;
    PropertyEditorHook.InspectorAreaOnScreen.Height := ControlProperties.Height;
  end;
end;

procedure TDesignFrame.RecordUndo(const UndoComment: String;
  const UndoCommentPriority: TUndoCommentPriority);
var
  StartTimer: TTimerResult;
begin
  StartTimer := Timer;
  UndoSystem.RecordUndo(ComponentToString(FDesignRoot), GetSavedSelection, UndoComment, UndoCommentPriority);
  UndoSystem.DoLog('Undo "%s" recorded in %fs.', [UndoComment, StartTimer.ElapsedTime]);
end;

procedure TDesignFrame.SaveSelected;
var
  ComponentToSave: TComponent;
begin
  ComponentToSave := SelectedComponent;
  if ComponentToSave = nil then
  begin
    ErrorBox('Select exactly one component to save');
    Exit;
  end;

  PrepareSaveDesignDialog(SaveDesignDialog, ComponentToSave);
  SaveDesignDialog.Url := '';
  if SaveDesignDialog.Execute then
  begin
    if ComponentToSave is TCastleUserInterface then
      UserInterfaceSave(TCastleUserInterface(ComponentToSave), SaveDesignDialog.Url)
    else
    if ComponentToSave is TCastleTransform then
      TransformSave(TCastleTransform(ComponentToSave), SaveDesignDialog.Url)
    else
      ComponentSave(ComponentToSave, SaveDesignDialog.Url);
  end;
end;

procedure TDesignFrame.MarkModified;
begin
  // mark modified
  FDesignModified := true;
  OnUpdateFormCaption(Self);
end;

class function TDesignFrame.Selectable(const Child: TComponent): Boolean;
begin
  { Note: When changing conditions here, consider also updating ReasonWhyNotDeletable,
    that explains to user *why* something is not deletable (not being selectable
    also makes it not deletable). }

  { csTransient reason:

    Do not show in hierarchy the TCastleDesign loaded hierarchy,
    as it will not be saved.
    Same for TCastleCheckbox children.
    Consequently, do not allow to select stuff inside.

    However, show TCastleToolTransform, even though it is csTransient.
    We want to allow selecting joint tools.
  }
  // Define this to inspect all transformations, including internal (gizmos)
  {.$define EDITOR_DEBUG_TRANSFORMS}
  {$ifdef EDITOR_DEBUG_TRANSFORMS}
  Result := true;
  {$else}
  Result := (not (csTransient in Child.ComponentStyle)) or (Child is TCastleToolTransform);
  {$endif}
end;

function TDesignFrame.Deletable(const Child: TComponent): Boolean;
begin
  { Note: When changing conditions here, consider also updating ReasonWhyNotDeletable,
    that explains to user *why* something is not deletable. }

  Result := Selectable(Child) and
    (not (csSubComponent in Child.ComponentStyle)) and
    (Child <> DesignRoot) and (not (Child is TCastleToolTransform));
end;

type
  EHierarchyValidationFailed = class(Exception);
const
  ValidationError = 'Hierarchy view desynchronized with CGE internal hierarchy. 1. Please submit a bug, this should never happen. 2. To workaround it for now, save and reopen the design file.';

procedure TDesignFrame.ValidateOrUpdateHierarchy(const Validate: Boolean);
var
  NodesToExpand: TObjectList;

  { Make sure that given parent, at given index, has given child.
    Return this child (TTreeNode),
    and increase IndexInParent by 1.

    Parent may be nil, indicating the root of ControlsTree.
    (It's a bit uncomfortable, but there's no single "root" node for
    ControlsTree. At the top level there is TTreeNodes, which is already
    a list.)

    In case of Validate = false: if there is a mismatch,
    it fixes the mismatch by adding a new child.
    But it assumes that Parent has at least IndexInParent-1 children,
    i.e. all previous children (with smaller IndexInParent) are matching.

    In case of Validate = true: if there is a mismatch,
    raises EHierarchyValidationFailed. }
  function EnsureChildNodeIs(const Parent: TTreeNode; var IndexInParent: Integer;
    const ChildNodeCaption: String; const ChildNodeData: Pointer): TTreeNode;
  var
    Valid, NextIsValid: Boolean;
  begin
    if Parent = nil then
    begin
      Assert(ControlsTree.Items.TopLvlCount >= IndexInParent);
      Valid := (ControlsTree.Items.TopLvlCount > IndexInParent) and
        (ControlsTree.Items.TopLvlItems[IndexInParent].Text = ChildNodeCaption) and
        (ControlsTree.Items.TopLvlItems[IndexInParent].Data = ChildNodeData);
      NextIsValid := (ControlsTree.Items.TopLvlCount > IndexInParent + 1) and
        (ControlsTree.Items.TopLvlItems[IndexInParent + 1].Text = ChildNodeCaption) and
        (ControlsTree.Items.TopLvlItems[IndexInParent + 1].Data = ChildNodeData);
    end else
    begin
      Assert(Parent.Count >= IndexInParent);
      Valid := (Parent.Count > IndexInParent) and
        (Parent.Items[IndexInParent].Text = ChildNodeCaption) and
        (Parent.Items[IndexInParent].Data = ChildNodeData);
      NextIsValid := (Parent.Count > IndexInParent + 1) and
        (Parent.Items[IndexInParent + 1].Text = ChildNodeCaption) and
        (Parent.Items[IndexInParent + 1].Data = ChildNodeData);
    end;

    // observe this log after delete/add operation
    {
    WritelnLog('Child node %s valid? %s', [
      ChildNodeCaption,
      BoolToStr(Valid, true)
    ]);
    }

    if Valid then
    begin
      if Parent = nil then
        Result := ControlsTree.Items.TopLvlItems[IndexInParent]
      else
        Result := Parent.Items[IndexInParent];
    end else
    begin
      if Validate then
      begin
        raise EHierarchyValidationFailed.Create(ValidationError);
      end;

      // now we know Validate = false

      if NextIsValid then
      begin
        // delete the IndexInParent child of Parent and we will be OK
        if Parent = nil then
        begin
          ControlsTree.Items.Delete(ControlsTree.Items.TopLvlItems[IndexInParent]);
          Result := ControlsTree.Items.TopLvlItems[IndexInParent];
        end else
        begin
          ControlsTree.Items.Delete(Parent.Items[IndexInParent]);
          Result := Parent.Items[IndexInParent];
        end;
      end else
      begin
        { insert new child at position IndexInParent to Parent.

          Looks like TTreeNode doesn't give nice API to Insert at specified
          position into an indicated parent. But we can just remove
          all excessive nodes -- they are all likely invalid at this point. }

        if Parent = nil then
        begin
          while ControlsTree.Items.TopLvlCount > IndexInParent do
            ControlsTree.Items.Delete(ControlsTree.Items.TopLvlItems[IndexInParent]);
          Assert(IndexInParent = ControlsTree.Items.TopLvlCount); // this should be true if previous children were valid
        end else
        begin
          while Parent.Count > IndexInParent do
            ControlsTree.Items.Delete(Parent.Items[IndexInParent]);
          Assert(IndexInParent = Parent.Count); // this should be true if previous children were valid
        end;

        // this works for Parent = nil or non-nil
        Result := ControlsTree.Items.AddChildObject(Parent, ChildNodeCaption, ChildNodeData);

        { Expand newly added nodes.
          Note that we cannot call now Result.Expand(true),
          because Result has no children and calling Expand() on it does nothing. }
        if not Validate then
          NodesToExpand.Add(Result);
      end;
    end;

    Assert(Result.Text = ChildNodeCaption);
    Assert(Result.Data = ChildNodeData);
    Inc(IndexInParent);
  end;

  { Make sure given Parent node has *at most* ParentCount children.

    In case of Validate = false: if there is a mismatch,
    it removes excessive children.

    In case of Validate = true: if there is a mismatch,
    raises EHierarchyValidationFailed. }
  procedure EnsureChildrenNodesCount(const Parent: TTreeNode; const ParentCount: Integer);
  var
    Valid: Boolean;
  begin
    if Parent = nil then
    begin
      Valid := ControlsTree.Items.TopLvlCount <= ParentCount;
    end else
    begin
      Valid := Parent.Count <= ParentCount;
    end;

    if not Valid then
    begin
      if Validate then
      begin
        raise EHierarchyValidationFailed.Create(ValidationError);
      end;

      // now we know Validate = false

      if Parent = nil then
      begin
        while ControlsTree.Items.TopLvlCount > ParentCount do
          ControlsTree.Items.Delete(ControlsTree.Items.TopLvlItems[ParentCount]);
      end else
      begin
        while Parent.Count > ParentCount do
          ControlsTree.Items.Delete(Parent.Items[ParentCount]);
      end;
    end;
  end;

  { Update TreeNodeMap, mapping components -> to their corresponding tree node.
    Ignored when Validate = false. }
  procedure UpdateTreeNodeMap(const C: TComponent; const Node: TTreeNode);
  begin
    if not Validate then
      TreeNodeMap.AddOrSetValue(C, Node);
  end;

  { Add given component, and its children in C.NonVisualComponents }
  function AddNonVisualComponent(const Parent: TTreeNode; var IndexInParent: Integer; const C: TComponent): TTreeNode;
  var
    S: String;
    Child: TComponent;
    ChildrenNodesCount: Integer;
  begin
    S := TreeNodeCaption(C);
    Result := EnsureChildNodeIs(Parent, IndexInParent, S, C);
    UpdateTreeNodeMap(C, Result);

    if C is TCastleComponent then
    begin
      ChildrenNodesCount := 0;
      for Child in TCastleComponent(C).NonVisualComponentsEnumerate do
        if Selectable(Child) then
          AddNonVisualComponent(Result, ChildrenNodesCount, Child);
      EnsureChildrenNodesCount(Result, ChildrenNodesCount);
    end;
  end;

  { If C has some NonVisualComponents, then create a tree item
    'Non-Visual Components' and add them to it. }
  function AddNonVisualComponentsSection(const Parent: TTreeNode; var IndexInParent: Integer; const C: TCastleComponent): TTreeNode;
  var
    Child: TComponent;
    ChildrenNodesCount: Integer;
  begin
    if C.NonVisualComponentsCount <> 0 then
    begin
      Result := EnsureChildNodeIs(Parent, IndexInParent, 'Non-Visual Components', nil);

      ChildrenNodesCount := 0;
      for Child in C.NonVisualComponentsEnumerate do
        if Selectable(Child) then
          AddNonVisualComponent(Result, ChildrenNodesCount, Child);
      EnsureChildrenNodesCount(Result, ChildrenNodesCount);
    end;
  end;

  { If T has some Behaviors, then create a tree item
    'Behaviors' and add them to it. }
  function AddBehaviorsSection(const Parent: TTreeNode; var IndexInParent: Integer; const T: TCastleTransform): TTreeNode;
  var
    Child: TCastleBehavior;
    ChildrenNodesCount: Integer;
  begin
    if T.BehaviorsCount <> 0 then
    begin
      Result := EnsureChildNodeIs(Parent, IndexInParent, 'Behaviors', nil);

      ChildrenNodesCount := 0;
      for Child in T.BehaviorsEnumerate do
        if Selectable(Child) then
          AddNonVisualComponent(Result, ChildrenNodesCount, Child);
      EnsureChildrenNodesCount(Result, ChildrenNodesCount);
    end;
  end;

  { Add given transform, and its children
    (transform children, T.NonVisualComponents, T.Behaviors). }
  function AddTransform(const Parent: TTreeNode; var IndexInParent: Integer; const T: TCastleTransform): TTreeNode;
  var
    S: String;
    I, ChildrenNodesCount: Integer;
  begin
    S := TreeNodeCaption(T);
    Result := EnsureChildNodeIs(Parent, IndexInParent, S, T);
    UpdateTreeNodeMap(T, Result);

    ChildrenNodesCount := 0;
    AddNonVisualComponentsSection(Result, ChildrenNodesCount, T);
    AddBehaviorsSection(Result, ChildrenNodesCount, T);

    for I := 0 to T.Count - 1 do
      if Selectable(T[I]) then
        AddTransform(Result, ChildrenNodesCount, T[I]);

    EnsureChildrenNodesCount(Result, ChildrenNodesCount);
  end;

  { Add given UI control, and its children. }
  function AddControl(const Parent: TTreeNode; var IndexInParent: Integer; const C: TCastleUserInterface): TTreeNode;
  var
    S: String;
    I, ChildrenNodesCount: Integer;
    Viewport: TCastleViewport;
  begin
    S := TreeNodeCaption(C);
    Result := EnsureChildNodeIs(Parent, IndexInParent, S, C);
    UpdateTreeNodeMap(C, Result);

    ChildrenNodesCount := 0;
    AddNonVisualComponentsSection(Result, ChildrenNodesCount, C);

    for I := 0 to C.ControlsCount - 1 do
    begin
      if Selectable(C.Controls[I]) then
        AddControl(Result, ChildrenNodesCount, C.Controls[I]);
    end;

    if C is TCastleViewport then
    begin
      Viewport := TCastleViewport(C);
      if Selectable(Viewport.Items) then
        AddTransform(Result, ChildrenNodesCount, Viewport.Items);
    end;
    EnsureChildrenNodesCount(Result, ChildrenNodesCount);
  end;

var
  ChildrenNodesCount: Integer;
  O: Pointer;
begin
  if not Validate then
    NodesToExpand := TObjectList.Create(false)
  else
    NodesToExpand := nil;
  try
    ChildrenNodesCount := 0;
    if DesignRoot is TCastleUserInterface then
      AddControl(nil, ChildrenNodesCount, DesignRoot as TCastleUserInterface)
    else
    if DesignRoot is TCastleTransform then
      AddTransform(nil, ChildrenNodesCount, DesignRoot as TCastleTransform)
    else
    if DesignRoot <> nil then
      AddNonVisualComponent(nil, ChildrenNodesCount, DesignRoot);
    EnsureChildrenNodesCount(nil, ChildrenNodesCount);

    if not Validate then
    begin
      for O in NodesToExpand do
      begin
        { Expand also parent.
          Reason: we want the parent (which is a node that existed before) to expand,
          to show newly added child.

          Testcase:
          - add TCastleTransformDesign, with no children, with URL pointing to something,
          - and then use "Edit (Copy Here) Referenced Design".
          - the TCastleTransformDesign is initially added and without any children in the hierarchy.
            It gets a call to "Expand(false)", but it doesn't actually do anything it seems.
          - later, we add some children to TCastleTransformDesign.
            The children are on NodesToExpand list, but not the TCastleTransformDesign itself.
            So calling Expand(false) on children does not make them visible,
            as TCastleTransformDesign is collapsed.
          - So we need to access parent to expand that TCastleTransformDesign.
        }
        if TTreeNode(O).Parent <> nil then
          TTreeNode(O).Parent.Expand(false);

        TTreeNode(O).Expand(false); // no need for recurse=true, because we will call this on children too
      end;
    end;
  finally
    FreeAndNil(NodesToExpand);
  end;
end;

procedure TDesignFrame.UpdateDesign;

  { Set ControlsTree selection to given components.
    Selected may be @nil indicating "select nothing". }
  procedure ControlsTreeSetSelection(const Selected: TComponentList);
  var
    SelectedNodes: TList; // TTreeNode list
    SelectedNode: TTreeNode;
    I: Integer;
  begin
    if (Selected <> nil) and
       (Selected.Count <> 0) then
    begin
      SelectedNodes := TList.Create;
      try
        for I := 0 to Selected.Count - 1 do
          if TreeNodeMap.TryGetValue(Selected[I], SelectedNode) then
            SelectedNodes.Add(SelectedNode);
        ControlsTree.Select(SelectedNodes);
      finally FreeAndNil(SelectedNodes) end;
    end else
      ControlsTree.ClearSelection;
  end;

begin
  { Note that we cannot do GetSelected now to save current selection state.
    At this point, our tree may contain invalid pointers.
    Imagine that we just deleted a (selected) hinge component,
    that also freed related anchor (TCastleTransform).
    Neither hinge component, nor anchor (TCastleTransform), exist anymore.
    So we just use LastSelected to restore. }

  // temporarily disable events, as some pointers in ControlsTree data are invalid now
  ControlsTree.OnSelectionChanged := nil;

  TreeNodeMap.Clear; // ValidateOrUpdateHierarchy(false) will fill TreeNodeMap

  ValidateOrUpdateHierarchy(false);

  { Restore selection.
    Without this (if we would clear selection like ControlsTree.ClearSelection),
    selecting physics joint would not work,
    as selecting it would reset selection making it unselected again. }
  ControlsTreeSetSelection(LastSelected);

  // restore events
  ControlsTree.OnSelectionChanged := @ControlsTreeSelectionChanged;

  InternalCastleDesignInvalidate := false;

  { Note that this sets (maybe changes to nil if unselected) TransformDesigning,
    calling some DesigningBegin / DesigningEnd.
    They in turn may create / destroy something, and set
    InternalCastleDesignInvalidate :=  true and it shoud cause UpdateDesign again.
    It actually should not happen anymore (because we save/restore selection,
    so TransformDesigning should remain the same) but better be secure from it. }
  UpdateSelectedControl;
end;

function TDesignFrame.ValidateHierarchy: Boolean;
begin
  try
    ValidateOrUpdateHierarchy(true);
    Result := true;
  except
    on E: EHierarchyValidationFailed do
    begin
      Result := false;
      WritelnWarning(E.Message);
    end;
  end;
end;

function TDesignFrame.SelectedFromNode(Node: TTreeNode;
  const AutoSelectParents: Boolean): TComponent;
begin
  // This should never be called with Node = nil
  Assert(Node <> nil);

  { In case of special tree items "Behaviors" or "Non-Visual Components",
    treat parent as selected. }
  if AutoSelectParents then
  begin
    if Node.Data = nil then
    begin
      Node := Node.Parent;
      if Node = nil then
      begin
        WritelnWarning('No parent of special node (without the associated TComponent), this should not happen');
        Exit(nil);
      end;
      if Node.Data = nil then
      begin
        WritelnWarning('Parent of special node (without the associated TComponent) also has no associated TComponent, this should not happen');
        Exit(nil);
      end;
    end;
    Assert(Node.Data <> nil);
  end;

  if Node.Data = nil then
  begin
    Assert(not AutoSelectParents);  // possible only if AutoSelectParents=false
    Exit(nil);
  end;

  Assert(TObject(Node.Data) is TComponent); // we only store nil or TComponent instance in Node.Data
  Result := TComponent(Node.Data);
end;

procedure TDesignFrame.SetSelected(const Selected: TComponentList);
var
  NewSelectedNodes: TList;
  NewNode: TTreeNode;
  C: TComponent;
begin
  NewSelectedNodes := TList.Create;
  try
    if Selected <> nil then
      for C in Selected do
        if TreeNodeMap.TryGetValue(C, NewNode) then
          NewSelectedNodes.Add(NewNode);
    ControlsTree.Select(NewSelectedNodes);
  finally FreeAndNil(NewSelectedNodes) end;
end;

procedure TDesignFrame.GetSelected(out Selected: TComponentList;
  out SelectedCount: Integer; const AutoSelectParents: Boolean);

{ This implementation is synchronized with GetSelectedComponent closely,
  as GetSelectedComponent needs to do something similar. }

var
  I: Integer;
  C: TComponent;
begin
  Selected := nil;

  for I := 0 to ControlsTree.SelectionCount - 1 do
  begin
    C := SelectedFromNode(ControlsTree.Selections[I], AutoSelectParents);
    if C <> nil then
    begin
      if Selected = nil then
        Selected := TComponentList.Create(false);
      { Avoid duplicates that could occur if you select a component
        and special tree item "Behaviors" or "Non-Visual Components" within. }
      if Selected.IndexOf(C) = -1 then
        Selected.Add(C);
    end;
  end;

  if Selected <> nil then
  begin
    SelectedCount := Selected.Count;
    // LastSelected only reflects state with AutoSelectParents=true
    if AutoSelectParents then
      LastSelected.Assign(Selected);
  end else
  begin
    SelectedCount := 0;
    // LastSelected only reflects state with AutoSelectParents=true
    if AutoSelectParents then
      LastSelected.Clear;
  end;
end;

function TDesignFrame.GetSelectedUserInterface: TCastleUserInterface;
var
  C: TComponent;
begin
  C := GetSelectedComponent;
  if C is TCastleUserInterface then
    Result := TCastleUserInterface(C)
  else
    Result := nil;
end;

procedure TDesignFrame.SetSelectedUserInterface(const Value: TCastleUserInterface);
begin
  SelectedComponent := Value;
end;

function TDesignFrame.GetSelectedTransform: TCastleTransform;
var
  C: TComponent;
begin
  C := GetSelectedComponent;
  if C is TCastleTransform then
    Result := TCastleTransform(C)
  else
    Result := nil;
end;

procedure TDesignFrame.SetSelectedTransform(const Value: TCastleTransform);
begin
  SelectedComponent := Value;
end;

function TDesignFrame.GetSelectedComponentAutoSelectParents: TComponent;
begin
  Result := GetSelectedComponent(true);
end;

function TDesignFrame.GetSelectedComponent(const AutoSelectParents: Boolean): TComponent;

{ This implementation is synchronized with GetSelected closely.

  Naive version (using GetSelected to create TComponentList,
  that also registers notifications -- so it has some cost) is defined below,
  and you can use Assert to make sure it is equal to the optimized one.
  But it is commented out now, as the editor just uses debug mode now always,
  for simplicity -- as there are no practical points when it needs optimization.
  *This* optimization is also not practical, i.e. not proven by any test. }

{
  function GetSelectedComponentNaive: TComponent;
  var
    Selected: TComponentList;
    SelectedCount: Integer;
  begin
    GetSelected(Selected, SelectedCount, AutoSelectParents);
    try
      if SelectedCount = 1 then
        Result := Selected[0]
      else
        Result := nil;
    finally FreeAndNil(Selected) end;
  end;
}

var
  I: Integer;
  C: TComponent;
begin
  Result := nil;

  for I := 0 to ControlsTree.SelectionCount - 1 do
  begin
    C := SelectedFromNode(ControlsTree.Selections[I], AutoSelectParents);
    if C <> nil then
    begin
      if Result <> nil then
      begin
        if Result <> C then
        begin
          { more than one component selected -> exit nil, do not update LastSelected }
          // Assert(nil = GetSelectedComponentNaive);
          Exit(nil);
        end;
        { else C is the same thing as already selected
          (possible when you select both the component and its special child like "Behaviors"),
          so do nothing }
      end else
        { at least one component is selected }
        Result := C;
    end;
  end;

  // LastSelected only reflects state with AutoSelectParents=true
  if AutoSelectParents then
  begin
    { Update LastSelected to 0 or 1 components }
    LastSelected.Clear;
    if Result <> nil then
      LastSelected.Add(Result);
  end;

  // Assert(Result = GetSelectedComponentNaive);
end;

function TDesignFrame.ControlsTreeOneSelected: TTreeNode;
begin
  if ControlsTree.SelectionCount = 1 then
    Result := ControlsTree.Selections[0]
  else
    Result := nil;
end;

procedure TDesignFrame.SetSelectedComponent(const Value: TComponent);
var
  Node: TTreeNode;
begin
  { Disabling OnSelectionChanged is safest because ControlsTree.Select
    first calls ClearSelection which, in turn, calls OnSelectionChanged.

    If OnSelectionChanged would cause ControlsTreeSelectionChanged then
    - UpdateSelectedControl gets called
    - in turn TransformDesigning is set
    - which may cause some DesigningEnd calls on hinges
    - which may free some TTreeNode.Data pointers invalid

    There's nothing inherently bad in above (it would be bad only if TTreeNode
    instance would become invalid in the middle of ControlsTree.Select),
    but still it seems safer to avoid such cascade in the middle of ControlsTree.Select.
  }

  ControlsTree.OnSelectionChanged := nil;

  if Value = nil then
    ControlsTree.Select([])
  else
  if TreeNodeMap.TryGetValue(Value, Node) then
    ControlsTree.Select([Node]);

  ControlsTree.OnSelectionChanged := @ControlsTreeSelectionChanged;
  ControlsTreeSelectionChanged(nil);
end;

function TDesignFrame.CurrentTransform: TCastleTransform;
begin
  if SelectedComponent is TCastleBehavior then
    Result := TCastleBehavior(SelectedComponent).Parent
  else
    Result := SelectedTransform;
end;

procedure TDesignFrame.UpdateSelectedInfo;
var
  C: TComponent;
  SListInfo, SListWarnings: TStringList;
begin
  C := SelectedComponent;
  if C is TCastleComponent then
  begin
    SListInfo := nil;
    SListWarnings := nil;
    try
      SListInfo := TStringList.Create;
      SListWarnings := TStringList.Create;

      TCastleComponent(C).DesignerInfo(SListInfo);
      TCastleComponent(C).DesignerWarnings(SListWarnings);

      if (SListInfo.Count <> 0) or (SListWarnings.Count <> 0) then
      begin
        TabInfo.TabVisible := true;

        MemoInfo.Lines.Clear;

        if SListWarnings.Count <> 0 then
        begin
          MemoInfo.Lines.Add('Warnings (%d):', [SListWarnings.Count]);
          MemoInfo.Lines.AddStrings(SListWarnings, false);
          TabInfo.Caption := Format('Warnings (%d)', [SListWarnings.Count]);
        end else
          TabInfo.Caption := 'Info';

        if SListInfo.Count <> 0 then
        begin
          if MemoInfo.Lines.Count <> 0 then
            MemoInfo.Lines.Add('');
          MemoInfo.Lines.Add('Information:');
          MemoInfo.Lines.AddStrings(SListInfo, false);
        end;
      end else
      begin
        TabInfo.TabVisible := false;
      end;
    finally
      FreeAndNil(SListInfo);
      FreeAndNil(SListWarnings);
    end;
  end else
  begin
    TabInfo.TabVisible := false;
  end;
end;

procedure TDesignFrame.UpdateSelectedControl;

  procedure InitializeCollectionFormEvents(InspectorType: TInspectorType);
  var
    I: Integer;
    Row: TOIPropertyGridRow;
    Ed: TCollectionPropertyEditor = nil;
  begin
    if CollectionPropertyEditorForm = nil then
    begin
      { If there is any property that can have a TCollectionPropertyEditor,
        then (once for the whole lifetime of this TDesignFrame) we need to assign
        our callbacks to the associated TCollectionPropertyEditorForm .
        *Before* the form can be actually invoked by user pressing "..." button
        near the respective field.

        The TCollectionPropertyEditorForm form instance is internal in LCL,
        it is reused by all property editors and it stays constant
        for the rest of the application's lifetime.
        The code below detects if there's *any* field with TCollectionPropertyEditor,
        and if yes -- creates (and immediately closes) the associated
        TCollectionPropertyEditorForm, just to initialize our callbacks.

        Example field: TDbf.FieldDefs, test with
        https://github.com/castle-engine/castle-db-aware-controls }

      for I := 0 to Inspector[InspectorType].RowCount - 1 do
      begin
        Row := Inspector[InspectorType].Rows[I];
        if Row.Editor is TCollectionPropertyEditor then
        begin
          Ed := TCollectionPropertyEditor(Row.Editor);
          Break;
        end;
      end;
      if Ed <> nil then
      begin
        CollectionPropertyEditorForm := Ed.ShowCollectionEditor(nil, nil, '') as TCollectionPropertyEditorForm;
        CollectionPropertyEditorForm.FreeNotification(Self);
        CollectionPropertyEditorForm.Close; // Hide the form
        CollectionPropertyEditorForm.OnClose := @PropertyGridCollectionItemClose;
        CollectionPropertyEditorForm.FormStyle := fsStayOnTop;
        CollectionPropertyEditorForm.CollectionListBox.OnClick := @PropertyGridCollectionItemClick;
        { We remove TToolButton's actions and use our own's OnClick events
          instead so that we can hook our undo/redo system in }
        CollectionPropertyEditorForm.AddButton.Action := nil;
        CollectionPropertyEditorForm.AddButton.Enabled := True;
        CollectionPropertyEditorForm.DeleteButton.Action := nil;
        CollectionPropertyEditorForm.DeleteButton.Enabled := True;
        CollectionPropertyEditorForm.MoveUpButton.Action := nil;
        CollectionPropertyEditorForm.MoveUpButton.Enabled := True;
        CollectionPropertyEditorForm.MoveDownButton.Action := nil;
        CollectionPropertyEditorForm.MoveDownButton.Enabled := True;
        CollectionPropertyEditorForm.AddButton.OnClick := @PropertyGridCollectionItemAdd;
        CollectionPropertyEditorForm.DeleteButton.OnClick := @PropertyGridCollectionItemDelete;
        CollectionPropertyEditorForm.MoveUpButton.OnClick := @PropertyGridCollectionItemMoveUp;
        CollectionPropertyEditorForm.MoveDownButton.OnClick := @PropertyGridCollectionItemMoveDown;
      end;
    end;
  end;

var
  Selected, UnlockedSelected: TComponentList;
  I, SelectedCount: Integer;
  SelectionForOI: TPersistentSelectionList;
  UI: TCastleUserInterface;
  InspectorType: TInspectorType;
  V: TCastleViewport;
  T: TCastleTransform;
begin
  OnSelectionChanged(Self); // Calling it in ControlsTreeSelectionChanged doesn't seem to be enough as RenameSelectedPossible is true there even in case SelectedCount = 0 (does it use some obsolete value?)

  GetSelected(Selected, SelectedCount);
  try
    case SelectedCount of
      0: LabelControlSelected.Caption := 'Nothing Selected';
      1: LabelControlSelected.Caption := 'Selected:' + NL + ComponentCaption(Selected[0]);
      else LabelControlSelected.Caption := 'Selected:' + NL + IntToStr(SelectedCount) + ' components';
    end;

    SetEnabledVisible(ControlProperties, SelectedCount <> 0);
    if PanelPropertyFilter <> nil then
      SetEnabledVisible(PanelPropertyFilter, SelectedCount <> 0);

    SelectionForOI := TPersistentSelectionList.Create;
    try
      for I := 0 to SelectedCount - 1 do
        SelectionForOI.Add(Selected[I]);
      for InspectorType in TInspectorType do
        Inspector[InspectorType].Selection := SelectionForOI;

      { Inspector itAll includes all fields from all inspectors, always.
        So there's no reason to run InitializeCollectionFormEvents on other itXxx inspectors. }
      InitializeCollectionFormEvents(itAll);
    finally FreeAndNil(SelectionForOI) end;

    UI := SelectedUserInterface;
    SetEnabledVisible(PanelAnchors, UI <> nil);
    if UI <> nil then
      UpdateAnchors(UI, true);

    V := SelectedViewport;
    T := CurrentTransform;

    UnlockedSelected := TComponentList.Create(false);
    try
      if Selected <> nil then
        for I := 0 to Selected.Count - 1 do
          if not IsComponentLocked(Selected[I]) then
            UnlockedSelected.Add(Selected[I]);
      TransformManipulate.SetSelected(UnlockedSelected);
    finally
      FreeAndNil(UnlockedSelected);
    end;
    SetEnabledVisible(PanelLayoutTransform, (T <> nil) or (TransformManipulate.SelectedCount > 0));
    if ButtonAlignX <> nil then
      ButtonAlignX.Enabled := TransformManipulate.SelectedCount >= 2;
    if ButtonAlignY <> nil then
      ButtonAlignY.Enabled := TransformManipulate.SelectedCount >= 2;
    if ButtonAlignZ <> nil then
      ButtonAlignZ.Enabled := TransformManipulate.SelectedCount >= 2;
    if ButtonDistributeX <> nil then
      ButtonDistributeX.Enabled := TransformManipulate.SelectedCount >= 3;
    if ButtonDistributeY <> nil then
      ButtonDistributeY.Enabled := TransformManipulate.SelectedCount >= 3;
    if ButtonDistributeZ <> nil then
      ButtonDistributeZ.Enabled := TransformManipulate.SelectedCount >= 3;
    if ButtonStackX <> nil then
      ButtonStackX.Enabled := TransformManipulate.SelectedCount >= 2;
    if ButtonStackY <> nil then
      ButtonStackY.Enabled := TransformManipulate.SelectedCount >= 2;
    if ButtonStackZ <> nil then
      ButtonStackZ.Enabled := TransformManipulate.SelectedCount >= 2;
  finally FreeAndNil(Selected) end;

  if CameraPreview <> nil then
    CameraPreview.SelectedChanged(T, V);

  { if selection determines CurrentViewport, update CurrentViewport immediately
    (without waiting for OnUpdate) -- maybe this will be relevant at some point }
  UpdateCurrentViewport;

  UpdateSelectedInfo;
end;

(*
// The TransformDesigning mechanism works, but it unused for now.
procedure TDesignFrame.TransformDesigningFreeNotification(const Value: TFreeNotificationObserver);
begin
  TransformDesigning := nil;
end;

procedure TDesignFrame.SetTransformDesigning(const Value: TCastleTransform);
var
  B: TCastleBehavior;
begin
  if FTransformDesigning <> Value then
  begin
    if FTransformDesigning <> nil then
    begin
      for B in FTransformDesigning.BehaviorsEnumerate do
        B.DesigningEnd;
    end;

    FTransformDesigning := Value;
    FTransformDesigningObserver.Observed := Value;

    if FTransformDesigning <> nil then
    begin
      for B in FTransformDesigning.BehaviorsEnumerate do
        B.DesigningBegin;
    end;
  end;
end;
*)

procedure TDesignFrame.ControlsTreeSelectionChanged(Sender: TObject);
begin
  UpdateSelectedControl;
end;

procedure TDesignFrame.ControlsTreeDragOver(Sender, Source: TObject; X,
  Y: Integer; State: TDragState; var Accept: Boolean);

{ Drag and drop handling when destination is ControlsTree.
  Useful info about TTreeView drag and drop handling:
  on https://stackoverflow.com/questions/18856374/delphi-treeview-drag-and-drop-between-nodes
}

  function NodeSide(const Node: TTreeNode; const X, Y: Integer): TTreeNodeSide;
  var
    R: TRect;
  begin
    R := Node.DisplayRect(false);
    if Y < Lerp(0.75, R.Bottom, R.Top) then
      Result := tnsTop
    else
    if Y > Lerp(0.25, R.Bottom, R.Top) then
      Result := tnsBottom
    else
      Result := tnsInside;
  end;

var
  SrcComponents: TComponentList;
  IgnoredSrcComponentsCount: Integer;
  Dst: TTreeNode;
begin
  Accept := false;
  if Source = ControlsTree then
  begin
    // get destination of drag-and-drop
    Dst := ControlsTree.GetNodeAt(X, Y);
    ControlsTreeNodeUnderMouse := Dst;

    // get and check source of drag-and-drop
    GetSelected(SrcComponents, IgnoredSrcComponentsCount, false);
    if SrcComponents <> nil then
    try
      Accept := ControlsTreeAllowDrag(SrcComponents, Dst);
    finally FreeAndNil(SrcComponents) end;

    if not Accept then
      ControlsTreeNodeUnderMouse := nil;

    { We don't use TCustomTreeView.GetHitTestInfoAt,
      it never contains flags htAbove, htBelow, htOnRight that interest us.
      (Simply not implemented, marked by TODO in Lazarus sources.) }
    //ControlsTreeNodeUnderMouseHit := ControlsTree.GetHitTestInfoAt(X, Y);
    if ControlsTreeNodeUnderMouse <> nil then
      ControlsTreeNodeUnderMouseSide := NodeSide(ControlsTreeNodeUnderMouse, X, Y);
    ControlsTree.Invalidate; // force custom-drawn look redraw
  end else
  if Source is TCastleShellListView then
  begin
    if SelectedComponent <> nil then
      Accept := ShellListComponentClass(TCastleShellListView(Source),
        SelectedComponent) <> nil;
  end;
end;

procedure TDesignFrame.ControlsTreeEditing(Sender: TObject; Node: TTreeNode;
  var AllowEdit: Boolean);
var
  C: TComponent;
begin
  { This event is fired when calling TCustomListView.CanEdit
    which itself is called in TCustomListView.ShowEditor
    therefore this event preceeds initializing and showing of the editor. }
  C := TComponent(Node.Data);
  AllowEdit := C <> nil; // may be nil on special tree items "Behaviors" or "Non-Visual Components"

  { Old: when Note.Text was different from C.Name, we set it here.
    This is pointless now, but also harmless, since TreeNodeCaption
    now just returns C.Name. }
  if AllowEdit then
    Node.Text := C.Name;
end;

procedure TDesignFrame.ControlsTreeEditingEnd(Sender: TObject; Node: TTreeNode;
  Cancel: Boolean);
var
  UndoComment: String;
  Sel: TComponent;
begin
  try
    Sel := TComponent(Node.Data);
    if Sel = nil then
    begin
      // may be nil on special tree items "Behaviors" or "Non-Visual Components"
      WritelnWarning('Node data is nil at ControlsTreeEditingEnd, this should not happen');
      Exit;
    end;

    { Check whether the edit actually changed anything.
      Otherwise the code below would execute too often (and make e.g. warnings
      about name uneditable for subcomponents) even when clicking around on "Items"
      without changing anything. }
    if Sel.Name <> Node.Text then
    begin
      if not RenamePossible(Sel) then
      begin
        if Sel.Owner <> nil then
        begin
          WritelnWarning('Renaming subcomponent (%s.%s) is not allowed. Subcomponents cannot be accessed by their names using TCastleView.DesignedComponent.', [
            Sel.Owner.ClassName,
            Sel.Name
          ]);
        end else
        begin
          { This never happens now, as RenamePossible for now only blocks editing
            name of subcomponents. }
          WritelnWarning('Renaming %s is not allowed.', [
            Sel.Name
          ]);
        end;
        Exit;
      end;

      { Without this check, one could change Sel.Name to empty ('').
        Although TComponent.SetName checks that it's a valid Pascal identifier already,
        but it also explicitly allows to set Name = ''.
        Object inspector has special code to secure from empty Name
        (in TComponentNamePropertyEditor.SetValue), so we need a similar check here. }
      if not IsValidIdent(Node.Text) then
      begin
        ErrorBox(Format(oisComponentNameIsNotAValidIdentifier, [Node.Text]));
        Exit;
      end;

      UndoComment := 'Rename ' + Sel.Name + ' into ' + Node.Text;

      try
        Sel.Name := Node.Text;
      except
        { We capture exception and change into ErrorBox,
          otherwise tree view in LCL GTK2 may end up showing a weird content
          after doing "Node.Text := TreeNodeCaption(Sel)" below
          (blank, with size of component name) and sometimes hang.
          Explicitly catching and showing the error by ErrorBox workarounds it. }
        on E: EComponentError do
        begin
          ErrorBox(E.Message);
          Exit;
        end;
      end;

      ModifiedOutsideObjectInspector(UndoComment, ucHigh); // It'd be good if we set "ItemIndex" to index of "name" field, but there doesn't seem to be an easy way to
    end;
  finally
    { This method must set Node.Text, to cleanup after ControlsTreeEditing + user editing.
      - If the name was correct, then "Sel.Name := " goes without exception,
        and we want to show new name + class name.
      - If the name was not correct, then "Sel.Name := " raises exception,
        and we want to show old name + class name. }
    Node.Text := TreeNodeCaption(Sel);
  end;
end;

function TDesignFrame.ControlsTreeAllowDrag(const SrcComponent: TComponent; const Dst: TTreeNode): Boolean;
begin
  Result := not (
    { Do not allow to drag-and-drop from ControlsTree to ControlsTree when:

      - special tree items "Behaviors" or "Non-Visual Components"
        ( https://github.com/castle-engine/castle-engine/issues/520 )
      - root component
      - subcomponents (like TCastleScrollView.ScrollArea),
      - temporary transforms
    }
    (SrcComponent = nil) or
    (SrcComponent = DesignRoot) or
    (csSubComponent in SrcComponent.ComponentStyle) or
    (SrcComponent is TCastleToolTransform)
  );
end;

function TDesignFrame.ControlsTreeAllowDrag(const Src, Dst: TTreeNode): Boolean;
var
  SrcComponent: TComponent;
begin
  Result := (Src <> nil) and (Dst <> nil) and (Src <> Dst);
  if Result then
  begin
    SrcComponent := TObject(Src.Data) as TComponent;
    Result := ControlsTreeAllowDrag(SrcComponent, Dst);
  end;
end;

function TDesignFrame.ControlsTreeAllowDrag(const SrcComponents: TComponentList; const Dst: TTreeNode): Boolean;
var
  C: TComponent;
begin
  for C in SrcComponents do
    if not ControlsTreeAllowDrag(C, Dst) then
      Exit(false);
  Result := true;
end;

procedure TDesignFrame.FrameAnchorsChange(Sender: TObject);
var
  UI: TCastleUserInterface;
  OldRect: TFloatRectangle;
begin
  UI := SelectedUserInterface;
  if UI <> nil then
  begin
    OldRect := UI.RenderRectWithBorder;

    UI.HorizontalAnchorSelf := SelfAnchorsFrame.HorizontalAnchor;
    UI.VerticalAnchorSelf := SelfAnchorsFrame.VerticalAnchor;
    if CheckParentSelfAnchorsEqual.Checked then
    begin
      UI.HorizontalAnchorParent := UI.HorizontalAnchorSelf;
      UI.VerticalAnchorParent := UI.VerticalAnchorSelf;
      // keep invisible ParentAnchorsFrame synchronized
      ParentAnchorsFrame.HorizontalAnchor := UI.HorizontalAnchorParent;
      ParentAnchorsFrame.VerticalAnchor := UI.VerticalAnchorParent;
    end else
    begin
      UI.HorizontalAnchorParent := ParentAnchorsFrame.HorizontalAnchor;
      UI.VerticalAnchorParent := ParentAnchorsFrame.VerticalAnchor;
    end;

    AdjustUserInterfaceAnchorsToKeepRect(UI, OldRect);
  end;
end;

procedure TDesignFrame.AdjustUserInterfaceAnchorsToKeepRect(
  const UI: TCastleUserInterface; const RenderRectBeforeChange: TFloatRectangle);
var
  NewRect: TFloatRectangle;
begin
  // adjust anchors, to preserve previous position
  NewRect := UI.RenderRectWithBorder;
  if NewRect.IsEmpty or RenderRectBeforeChange.IsEmpty then
  begin
    { Empty rectangle(s) may happen e.g. if control is empty,
      e.g. TCastleLabel.Caption = ''.
      To implement AdjustUserInterfaceAnchorsToKeepRect perfectly for this case,
      we'd need TCastleUserInterface method like GlobalTranslationEvenIfEmpty,
      but it would be a burden to implement it just for this special case.

      It seems that not doing anythign is just valid in this case.
      At least, user can choose various anchors, and clicking back on original
      anchor will (intuitively) restore the control back to where it was.

      Note: Resetting "UI.Translation := TVector2.Zero"
      wasn't intuitive, see https://github.com/castle-engine/castle-engine/issues/422 .
      It would reset the control position when it's not expected.
    }
  end else
  begin
    UI.Translation := UI.Translation + Vector2(
      (RenderRectBeforeChange.Left   - NewRect.Left) / UI.UIScale,
      (RenderRectBeforeChange.Bottom - NewRect.Bottom) / UI.UIScale);
  end;

  ModifiedOutsideObjectInspector('', ucLow);
end;

procedure TDesignFrame.ControlsTreeEndDrag(Sender, Target: TObject; X,
  Y: Integer);
begin
  ControlsTreeNodeUnderMouse := nil;
  ControlsTree.Invalidate; // force custom-drawn look redraw
end;

function TDesignFrame.RenamePossible(const C: TComponent): Boolean;
begin
  { Do not allow renaming subcomponents.
    It is confusing, since their names live in different namespace
    (e.g. Items owned by TCastleViewport), and should not really be used
    to access them. }
  Result := C.Owner = DesignOwner;
end;

function TDesignFrame.RenameSelectedPossible: Boolean;
begin
  { Notes:

    - We do not check "GetSelectedComponent <> nil",
      as a component may also be selected indirectly by selecting
      special tree items "Behaviors" or "Non-Visual Components" underneath.
      For rename, it has to be selected directly.

    - We do not check "ControlsTree.SelectionCount > 0" or "ControlsTree.Selected <> nil".

    We rely on ControlsTreeOneSelected which is also used by rename operation.
    Currently it underneath checks "ControlsTree.SelectionCount = 1".
  }
  Result :=
    (ControlsTreeOneSelected <> nil) and
    (ControlsTreeOneSelected.Data <> nil) and
    RenamePossible(TComponent(ControlsTreeOneSelected.Data));
end;

procedure TDesignFrame.RenameSelectedItem;
begin
  if MaximizePreview then // cannot focus edit control when PanelLeft invisible
    Exit;

  if RenameSelectedPossible then
    ControlsTreeOneSelected.EditText;
end;

procedure TDesignFrame.ControlsTreeDragDrop(Sender, Source: TObject; X,
  Y: Integer);

  { Preserve UI or TCastleTransform transformation when changing parent. }
  function PreserveTransformation: Boolean;
  begin
    Result := not (ssCtrl in GetKeyShiftState);
  end;

  procedure MoveOnlyTreeNodes(
    const SrcComponent, DstComponent: TComponent); forward;

  { Does Parent contains PotentialChild, searching recursively.
    It checks is Parent equal PotentialChild,
    and searches Parent's children,
    and Parent's children's children etc.

    Uses ControlsTree hierarchy knowledge, so it accounts
    for all visible in the hierarchy relationships,
    e.g. non-visual components may be parents and children of each other,
    TCastleUserInterface may be parent of TCastleTransform through
    TCastleViewport.Items etc. }
  function ContainsRecursive(const Parent, PotentialChild: TComponent): Boolean;
  var
    ParentNode, PotentialChildNode: TTreeNode;
  begin
    ParentNode := TreeNodeMap[Parent];
    PotentialChildNode := TreeNodeMap[PotentialChild];

    while PotentialChildNode <> nil do
    begin
      if PotentialChildNode = ParentNode then
        Exit(true);
      PotentialChildNode := PotentialChildNode.Parent;
    end;

    Result := false;
  end;

  { Move Src (TCastleUserInterface)
    before/after/into Dst (another TCastleUserInterface). }
  procedure MoveUserInterface(const Src, Dst: TCastleUserInterface);
  var
    Index: Integer;
    OldRect: TFloatRectangle;
  begin
    OldRect := Src.RenderRectWithBorder;

    case ControlsTreeNodeUnderMouseSide of
      tnsInside:
        begin
          if not ContainsRecursive(Src, Dst) then
          begin
            if Src.Parent <> nil then
              Src.Parent.RemoveControl(Src);
            Dst.InsertFront(Src);
            if PreserveTransformation then
              AdjustUserInterfaceAnchorsToKeepRect(Src, OldRect);
            MoveOnlyTreeNodes(Src, Dst);
          end;
        end;
      tnsBottom, tnsTop:
        begin
          if (Dst.Parent <> nil) and
             not ContainsRecursive(Src, Dst.Parent) then
          begin
            if Src.Parent <> nil then
              Src.Parent.RemoveControl(Src);
            Index := Dst.Parent.IndexOfControl(Dst);
            Assert(Index <> -1);
            if ControlsTreeNodeUnderMouseSide = tnsBottom then
              Inc(Index);
            Dst.Parent.InsertControl(Index, Src);
            if PreserveTransformation then
              AdjustUserInterfaceAnchorsToKeepRect(Src, OldRect);
            MoveOnlyTreeNodes(Src, Dst);
          end;
        end;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('ControlsTreeDragDrop:ControlsTreeNodeUnderMouseSide?');
      {$endif}
    end;
    ValidateHierarchy;
  end;

  { Move Src (TCastleTransform)
    before/after/into Dst (another TCastleTransform). }
  procedure MoveTransform(const Src, Dst: TCastleTransform);
  var
    Index: Integer;
    FinalPreserveTransformation: Boolean;
    WorldPos, WorldDir, WorldUp: TVector3;
  begin
    FinalPreserveTransformation := PreserveTransformation and
      Src.HasWorldTransform and
      { Do it only when scale is identity, otherwise GetWorldView/SetWorldView would
        not preserve scale. }
      TVector3.Equals(ScaleFromMatrix(Src.WorldTransform), NoScale) and
      Dst.HasWorldTransform and
      TVector3.Equals(ScaleFromMatrix(Dst.WorldTransform), NoScale);
    if FinalPreserveTransformation then
      Src.GetWorldView(WorldPos, WorldDir, WorldUp);

    case ControlsTreeNodeUnderMouseSide of
      tnsInside:
        begin
          if not ContainsRecursive(Src, Dst) then
          begin
            if Src.Parent <> nil then
              Src.Parent.Remove(Src);
            Dst.Add(Src);
            if FinalPreserveTransformation then
              Src.SetWorldView(WorldPos, WorldDir, WorldUp);
            MoveOnlyTreeNodes(Src, Dst);
          end;
        end;
      tnsBottom, tnsTop:
        begin
          if (Dst.Parent <> nil) and
             not ContainsRecursive(Src, Dst.Parent) then
          begin
            if Src.Parent <> nil then
              Src.Parent.Remove(Src);
            Index := Dst.Parent.List.IndexOf(Dst);
            Assert(Index <> -1);
            if ControlsTreeNodeUnderMouseSide = tnsBottom then
              Inc(Index);
            Dst.Parent.Insert(Index, Src);
            if FinalPreserveTransformation then
              Src.SetWorldView(WorldPos, WorldDir, WorldUp);
            MoveOnlyTreeNodes(Src, Dst);
          end;
        end;
      {$ifndef COMPILER_CASE_ANALYSIS}
      else raise EInternalError.Create('ControlsTreeDragDrop:ControlsTreeNodeUnderMouseSide?');
      {$endif}
    end;
    ValidateHierarchy;
  end;

  { Move Src (TCastleBehavior) into a Dst (TCastleTransform). }
  procedure MoveBehaviorToTransform(const Src: TCastleBehavior; const Dst: TCastleTransform);
  begin
    case ControlsTreeNodeUnderMouseSide of
      tnsInside:
        begin
          Src.Parent.RemoveBehavior(Src);
          Dst.AddBehavior(Src);
          // TODO: update tree in a simple way for now
          UpdateDesign;
        end;
    end;
  end;

  { Move Src (TCastleBehavior)
    before/after Dst (another TCastleBehavior). }
  procedure MoveBehavior(const Src: TCastleBehavior; const Dst: TCastleBehavior);
  var
    Index: Integer;
    DstParent: TCastleTransform;
  begin
    case ControlsTreeNodeUnderMouseSide of
      tnsBottom, tnsTop:
        begin
          DstParent := Dst.Parent;
          if (DstParent <> nil) and (Src <> Dst) then
          begin
            Src.Parent.RemoveBehavior(Src);
            // Access the index of dst
            Index := DstParent.BehaviorIndex(Dst);
            Assert(Index <> -1);
            if ControlsTreeNodeUnderMouseSide = tnsBottom then
              Inc(Index);
            DstParent.InsertBehavior(Index, Src);
            // TODO: update tree in a simple way for now
            UpdateDesign;
          end;
        end;
    end;
  end;

  procedure MoveNonVisual(
    const Src: TComponent;
    const Dst: TCastleComponent);
  var
    SrcParentComponent: TCastleComponent;
  begin
    SrcParentComponent := NonVisualComponentParent(Src);
    case ControlsTreeNodeUnderMouseSide of
      tnsInside:
        begin
          SrcParentComponent.RemoveNonVisualComponent(Src);
          Dst.AddNonVisualComponent(Src);
          // TODO: update tree in a simple way for now
          UpdateDesign;
        end;
      else ;
    end;
  end;

  function ViewportItemsNode(const Viewport: TCastleViewport;
    const ViewportTreeNode: TTreeNode): TTreeNode;
  var
    I: Integer;
  begin
    Assert(TObject(ViewportTreeNode.Data) = Viewport);
    Assert(ViewportTreeNode.Data <> nil);
    Assert(TObject(ViewportTreeNode.Data) is TCastleViewport);

    for I := 0 to ViewportTreeNode.Count - 1 do
      if TObject(ViewportTreeNode[I].Data) = Viewport.Items then
        Exit(ViewportTreeNode[I]);
    raise EInternalError.CreateFmt('No tree node for viewport Items (TCastleTransform) found: %s %s', [
      Viewport.Name,
      Viewport.ClassName
    ]);
  end;

  { Move only the nodes in TTreeView, and update their captions.
    Assumes the move is possible. }
  procedure MoveOnlyTreeNodes(
    const SrcComponent, DstComponent: TComponent);
  var
    Src, Dst: TTreeNode;
  begin
    Src := TreeNodeMap[SrcComponent];
    Dst := TreeNodeMap[DstComponent];
    case ControlsTreeNodeUnderMouseSide of
      tnsInside:
        begin
          { Special treatment when inserting UI into TCastleViewport,
            testcase: try to drag some UI into TCastleViewport (with tnsInside),
            it should be added right before "Items" node. }
          if (DstComponent is TCastleViewport) and
             (SrcComponent is TCastleUserInterface) then
            Src.MoveTo(ViewportItemsNode(TCastleViewport(DstComponent), Dst), naInsert)
          else
            Src.MoveTo(Dst, naAddChild);
        end;
      tnsBottom:
        begin
          Src.MoveTo(Dst, naInsertBehind);
        end;
      tnsTop:
        begin
          Src.MoveTo(Dst, naInsert);
        end;
    end;
  end;

  { Returns @true if List contains some parent of C (but not exactly C). }
  function ListIncludesParent(const C: TComponent; const List: TComponentList): Boolean;
  var
    ListItem: TComponent;
  begin
    for ListItem in List do
      if C <> ListItem then
        if ContainsRecursive(ListItem, C) then
          Exit(true);
    Result := false;
  end;

  { Handle drag-and-drop from and to ControlsTree, i.e. dragging within
    the hierarchy tree. }
  procedure DragAndDropFromControlsTree;
  var
    Dst: TTreeNode;
    SrcComponent, DstComponent: TComponent;
    SrcComponents: TComponentList;
    IgnoredSrcComponentsCount: Integer;
  begin
    // get destination of drag-and-drop
    Dst := ControlsTreeNodeUnderMouse;
    DstComponent := TComponent(Dst.Data);

    // get and check source of drag-and-drop
    GetSelected(SrcComponents, IgnoredSrcComponentsCount, false);
    if SrcComponents <> nil then
    try
      for SrcComponent in SrcComponents do
      begin
        { Do not process components when their parent is also already on the list. }
        if not ListIncludesParent(SrcComponent, SrcComponents) then
          { Checking again ControlsTreeAllowDrag is somewhat paranoid:
            ControlsTreeDragOver should have checked it already. }
          if ControlsTreeAllowDrag(SrcComponent, Dst) then
          begin
            if (SrcComponent is TCastleUserInterface) and
               (DstComponent is TCastleUserInterface) then
            begin
              MoveUserInterface(
                TCastleUserInterface(SrcComponent),
                TCastleUserInterface(DstComponent));
            end else
            if (SrcComponent is TCastleTransform) and
               (DstComponent is TCastleTransform) then
            begin
              MoveTransform(
                TCastleTransform(SrcComponent),
                TCastleTransform(DstComponent));
            end else
            if (SrcComponent is TCastleBehavior) and
               (DstComponent is TCastleTransform) then
            begin
              MoveBehaviorToTransform(
                TCastleBehavior(SrcComponent),
                TCastleTransform(DstComponent));
            end else
            if (SrcComponent is TCastleBehavior) and
               (DstComponent is TCastleBehavior) then
            begin
              MoveBehavior(
                TCastleBehavior(SrcComponent),
                TCastleBehavior(DstComponent));
            end else
            if (not ( (SrcComponent is TCastleBehavior) or
                      (SrcComponent is TCastleTransform) or
                      (SrcComponent is TCastleUserInterface) ) ) and
               (DstComponent is TCastleComponent) then
            begin
              MoveNonVisual(
                SrcComponent,
                TCastleComponent(DstComponent));
            end;
          end;
      end;

      { Select the SrcComponents.

        This is necessary:

        - If our movement used TTreeNode.MoveTo and not UpdateDesign.
          I.e. it updated ControlsTree smartly, no need to build.

          In that case TTreeView.Selected property value
          is changed to nil but in TTreeNode.Selected stays true.
          This results in inconsistent state.

          Possibly this reason is outdated:
          our code doesn't use use TTreeView.Selected ever now.
          See ControlsTreeOneSelected.

        - If our movement used UpdateDesign.

          Then selection was lost, we recover it.
      }
      SetSelected(SrcComponents);

      ModifiedOutsideObjectInspector(Format('Drag and drop %d components', [
        SrcComponents.Count
      ]), ucHigh);
    finally FreeAndNil(SrcComponents) end;
  end;

  procedure DragAndDropFromShellListView(const Source: TCastleShellListView);
  begin
    if SelectedComponent <> nil then
      ShellListAddComponent(Source, SelectedComponent)
    else
      { TODO: This is never displayed, since Accept=false in this case.
        But it's a pity -- we should communicate to user better why drag-and-drop
        is not allowed now. }
      WritelnWarning('Select a component in hierarchy, to allow to drag-and-drop children into it');
  end;

begin
  if Source = ControlsTree then
    DragAndDropFromControlsTree
  else
  if Source is TCastleShellListView then
    DragAndDropFromShellListView(TCastleShellListView(Source));
end;

{$ifdef LCLCocoa}
type
  { Expose protected property of TCustomTreeView. }
  TTreeViewExposed = class(TCustomTreeView)
  public
    { Tree node that is being edited now, or @nil if none.
      This makes public a property protected in TCustomTreeView. }
    property EditingItem;
  end;
{$endif LCLCocoa}

procedure TDesignFrame.ControlsTreeAdvancedCustomDrawItem(
  Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
  Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
var
  C: TCanvas;

  procedure DrawTreeNodeUnderMouse;
  const
    ColorOutline = clBlack;
    ColorDecoration = clGray;
  var
    NodeRect, R: TRect;
  begin
    NodeRect := Node.DisplayRect(false);

    { We can't draw it in cdPrePaint, as after csPrePaint
      the node rectangle is cleared anyway.
      And we can't draw it in any cdXxxErase, which are not implemented
      in LCL (2.1.0). }
    C.Pen.Color := ColorOutline;
    C.Pen.Style := psDot;
    C.Brush.Style := bsClear;
    C.Rectangle(NodeRect);

    if ControlsTreeNodeUnderMouseSide = tnsInside then
    begin
      R := NodeRect.SplitRect(srRight, NodeRect.Height);
      R.Inflate(-5, -5);
      C.Brush.Color := ColorDecoration;
      C.Brush.Style := bsSolid;
      C.Pen.Color := ColorOutline;
      C.Pen.Style := psSolid;
      //C.FillRect(R);
      C.Polygon([
        Point(R.Left , R.Top),
        Point(R.Right, R.CenterPoint.Y),
        Point(R.Left , R.Bottom)
      ]);
    end else
    begin
      if ControlsTreeNodeUnderMouseSide = tnsTop then
        R := NodeRect.SplitRect(srTop, 0.1)
      else
        R := NodeRect.SplitRect(srBottom, 0.1);
      R.Left := R.Left + ((Node.Level + 1)* ControlsTree.Indent);

      C.Brush.Color := ColorDecoration;
      C.Brush.Style := bsSolid;
      C.FillRect(R);
    end;
  end;

  procedure DrawTreeNodeClassName(const NodeObj: TObject);
  var
    TextRect: TRect;
    Suffix: String;
    IsHidden, IsLocked, IsFilterMatch: Boolean;
  begin
    {$ifdef LCLCocoa}
    { On Cocoa, this is fired even when editing given Node, but we should not
      draw the class name of the edited node (as it visually collides
      with the edit box, being underneath the typed text). }
    if Node = TTreeViewExposed(ControlsTree).EditingItem then
      Exit;
    {$endif LCLCocoa}

    IsHidden := ((NodeObj is TCastleTransform) and (not TCastleTransform(NodeObj).Exists)) or
                ((NodeObj is TCastleUserInterface) and (not TCastleUserInterface(NodeObj).Exists));
    IsLocked := (NodeObj is TComponent) and (FLockedComponents <> nil) and
                (FLockedComponents.IndexOf(TComponent(NodeObj)) <> -1);
    IsFilterMatch := FindActive and (Trim(EditFindInHierarchy.Text) <> '') and
                     (NodeObj is TComponent) and NodeMatchesHierarchyFilter(TComponent(NodeObj));

    Suffix := ' (' + NodeObj.ClassName + ')';
    if IsHidden then
      Suffix := Suffix + ' [Hidden]';
    if IsLocked then
      Suffix := Suffix + ' [Locked]';

    TextRect := Node.DisplayRect(true);
    C.Brush.Style := bsClear;
    if IsFilterMatch then
      C.Font.Color := clYellow
    else if IsHidden then
      C.Font.Color := clGray
    else
      C.Font.Color := clLtGray;
    C.TextOut(TextRect.Right, TextRect.Top, Suffix);
  end;

begin
  C := ControlsTree.Canvas;
  DefaultDraw := true;

  case Stage of
    cdPostPaint:
      begin
        if Node = ControlsTreeNodeUnderMouse then
          DrawTreeNodeUnderMouse;

        { When InternalCastleDesignInvalidate, don't trust that pointers
          on Node.Data are valid. This may happen if you freed joint,
          which also freed associated anchor.

          TODO: understand better why this is possible.
          After FreeComponentRecursively, we immediately do UpdateDesign
          and at that point the InternalCastleDesignInvalidate should be already
          resolved? }

        if (not InternalCastleDesignInvalidate) and
           (Node.Data <> nil) then
          DrawTreeNodeClassName(TObject(Node.Data));
      end;
    else ; // nothing to do otherwise
  end;
end;

procedure TDesignFrame.CheckParentSelfAnchorsEqualChange(Sender: TObject);
var
  UI: TCastleUserInterface;
  OldRect: TFloatRectangle;
begin
  ParentAnchorsFrame.Visible := not CheckParentSelfAnchorsEqual.Checked;
  ParentAnchorsFrame.Enabled := not CheckParentSelfAnchorsEqual.Checked;
  if CheckParentSelfAnchorsEqual.Checked then
  begin
    UI := SelectedUserInterface;
    if UI <> nil then
    begin
      OldRect := UI.RenderRectWithBorder;

      UI.HorizontalAnchorParent := UI.HorizontalAnchorSelf;
      UI.VerticalAnchorParent := UI.VerticalAnchorSelf;

      AdjustUserInterfaceAnchorsToKeepRect(UI, OldRect);

      // update also (invisible now) ParentAnchorsFrame UI state
      UpdateAnchors(UI, false);
    end;
  end;
end;

procedure TDesignFrame.ButtonClearTranslationClick(Sender: TObject);
var
  UI: TCastleUserInterface;
begin
  UI := SelectedUserInterface;
  if UI <> nil then
  begin
    UI.Translation := TVector2.Zero;
    ModifiedOutsideObjectInspector('Clear anchor deltas for ' + UI.Name, ucHigh);
  end;
end;

procedure TDesignFrame.SimulationPlayStop;
var
  NewDesignOwner, NewDesignRoot: TComponent;
  SavedSelection: TSavedSelection;
  LoadInfo: TInternalComponentLoadInfo;
begin
  if InternalCastleApplicationMode in [appSimulation, appSimulationPaused] then
    InternalCastleApplicationMode := appDesign
  else
    InternalCastleApplicationMode := appSimulation;

  if CastleApplicationMode = appSimulation then
  begin
    DesignStateBeforePhysicsRun := ComponentToString(DesignRoot);
    DesignModifiedBeforePhysicsRun := FDesignModified;
  end else
  begin
    SavedSelection := GetSavedSelection;

    LoadInfo := TInternalComponentLoadInfo.Create;
    try
      LoadInfo.PreserveDataAcrossUndo := DesignOwner;

      NewDesignOwner := TComponent.Create(Self);
      NewDesignRoot := InternalStringToComponent(DesignStateBeforePhysicsRun, NewDesignOwner, LoadInfo);
      OpenDesign(NewDesignRoot, NewDesignOwner, FDesignUrl);
    finally FreeAndNil(LoadInfo) end;

    FDesignModified := DesignModifiedBeforePhysicsRun;
    OnUpdateFormCaption(Self);

    RestoreSavedSelection(SavedSelection);
  end;

  // TODO: why is this not called automatically?
  ActionSimulationPlayStopUpdate(ActionSimulationPlayStop);
  ActionSimulationPauseUnpauseUpdate(ActionSimulationPauseUnpause);
end;

procedure TDesignFrame.ShowAllJointsTools;
var
  V: TCastleViewport;
  BehList: TCastleBehaviorList;
  B: TCastleBehavior;
begin
  V := CurrentViewport;
  if V = nil then Exit;

  BehList := V.Items.FindAllBehaviors(TCastleAbstractJoint);
  try
    for B in BehList do
      TCastleAbstractJoint(B).InternalCreateGizmos;
  finally FreeAndNil(BehList) end;
end;

procedure TDesignFrame.SimulationPauseUnpause;
begin
  if InternalCastleApplicationMode = appSimulationPaused then
    InternalCastleApplicationMode := appSimulation
  else
  if InternalCastleApplicationMode = appSimulation then
    InternalCastleApplicationMode := appSimulationPaused;

  // TODO: why is this not called automatically?
  ActionSimulationPlayStopUpdate(ActionSimulationPlayStop);
  ActionSimulationPauseUnpauseUpdate(ActionSimulationPauseUnpause);
end;

procedure TDesignFrame.ActionSimulationPlayStopExecute(Sender: TObject);
begin
  SimulationPlayStop;
end;

procedure TDesignFrame.ActionSimulationPlayStopUpdate(Sender: TObject);
begin
  if CastleApplicationMode = appDesign then
    ActionSimulationPlayStop.ImageIndex := TImageIndex(iiSimulationPlay)
  else
    ActionSimulationPlayStop.ImageIndex := TImageIndex(iiSimulationStop);
  ActionSimulationPlayStop.Checked := CastleApplicationMode in [appSimulation, appSimulationPaused];
end;

procedure TDesignFrame.ActionSimulationPauseUnpauseUpdate(Sender: TObject);
var
  InSim: Boolean;
begin
  InSim := CastleApplicationMode in [appSimulation, appSimulationPaused];
  ActionSimulationPauseUnpause.Checked := CastleApplicationMode = appSimulationPaused;
  ActionSimulationPauseUnpause.Visible := InSim;
  if ButtonSimulationStep <> nil then
    ButtonSimulationStep.Visible := InSim;
  if ButtonKeepSimulation <> nil then
    ButtonKeepSimulation.Visible := InSim;
end;

procedure TDesignFrame.ActionSimulationPauseUnpauseExecute(Sender: TObject);
begin
  SimulationPauseUnpause;
end;

procedure TDesignFrame.HideAllJointsTools;
var
  V: TCastleViewport;
  BehList: TCastleBehaviorList;
  B: TCastleBehavior;
begin
  V := CurrentViewport;
  if V = nil then Exit;

  BehList := V.Items.FindAllBehaviors(TCastleAbstractJoint);
  try
    for B in BehList do
      TCastleAbstractJoint(B).InternalDestroyGizmos;
  finally FreeAndNil(BehList) end;
end;

procedure TDesignFrame.ActionPlayStopExecute(Sender: TObject);
begin
  OnRunningToggle(Self);
end;

procedure TDesignFrame.ActionApiReferenceOfCurrentExecute(Sender: TObject);
begin
  OnApiReferenceOfCurrent(Self);
end;

procedure TDesignFrame.ActionPlayStopUpdate(Sender: TObject);
var
  IsRunning: Boolean;
begin
  IsRunning := OnIsRunning();
  if IsRunning then
    ActionPlayStop.ImageIndex := TImageIndex(iiStop)
  else
    ActionPlayStop.ImageIndex := TImageIndex(iiPlay);
  ActionPlayStop.Checked := IsRunning;
end;

procedure TDesignFrame.ButtonResetTransformationClick(Sender: TObject);
var
  T: TCastleTransform;
  I: Integer;
begin
  if TransformManipulate.SelectedCount > 1 then
  begin
    for I := 0 to TransformManipulate.SelectedCount - 1 do
      TransformManipulate.Selected[I].Identity;
    ModifiedOutsideObjectInspector(
      Format('Reset transformations for %d objects', [TransformManipulate.SelectedCount]), ucHigh);
  end else
  begin
    T := CurrentTransform;
    if T <> nil then
    begin
      T.Identity;
      ModifiedOutsideObjectInspector('Reset transformations for ' + T.Name, ucHigh);
    end;
  end;
end;

procedure TDesignFrame.ToggleCoordSpace;
begin
  if TransformManipulate.CoordSpace = csLocal then
  begin
    TransformManipulate.CoordSpace := csWorld;
    if ButtonCoordSpace <> nil then
      ButtonCoordSpace.Caption := 'World';
  end else
  begin
    TransformManipulate.CoordSpace := csLocal;
    if ButtonCoordSpace <> nil then
      ButtonCoordSpace.Caption := 'Local';
  end;
end;

procedure TDesignFrame.ButtonCoordSpaceClick(Sender: TObject);
begin
  ToggleCoordSpace;
end;

procedure TDesignFrame.SpinEditSnap3DChange(Sender: TObject);
var
  SnapVal: Single;
begin
  if (SpinEditSnap3D = nil) or (TransformManipulate = nil) then Exit;
  SnapVal := SpinEditSnap3D.Value;
  if SnapVal > 0 then
  begin
    TransformManipulate.TranslateSnap := SnapVal;
    if SnapVal <= 1.0 then
      TransformManipulate.RotateSnap := DegToRad(15.0)
    else
      TransformManipulate.RotateSnap := DegToRad(SnapVal);
    TransformManipulate.ScaleSnap := SnapVal;
  end else
  begin
    TransformManipulate.TranslateSnap := 0;
    TransformManipulate.RotateSnap := 0;
    TransformManipulate.ScaleSnap := 0;
  end;
end;

procedure TDesignFrame.ViewportSnapToFloor(const AlignToNormal: Boolean);
begin
  if TransformManipulate <> nil then
    TransformManipulate.SnapToFloor(AlignToNormal);
end;

procedure TDesignFrame.ButtonSnapToFloorClick(Sender: TObject);
begin
  ViewportSnapToFloor(false);
end;

procedure TDesignFrame.ButtonSnapToFloorNormalClick(Sender: TObject);
begin
  ViewportSnapToFloor(true);
end;

procedure TDesignFrame.CopyTransform;
var
  T: TCastleTransform;
begin
  T := CurrentTransform;
  if (T = nil) and (TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 0) then
    T := TransformManipulate.Selected[0];
  if T <> nil then
  begin
    FCopiedTranslation := T.Translation;
    FCopiedRotation := T.Rotation;
    FCopiedScale := T.Scale;
    FCopiedTransformValid := true;
    if ButtonPasteTransform <> nil then
      ButtonPasteTransform.Enabled := true;
  end;
end;

procedure TDesignFrame.PasteTransform;
var
  T: TCastleTransform;
  I: Integer;
begin
  if not FCopiedTransformValid then Exit;

  if (TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 1) then
  begin
    for I := 0 to TransformManipulate.SelectedCount - 1 do
    begin
      T := TransformManipulate.Selected[I];
      T.Translation := FCopiedTranslation;
      T.Rotation := FCopiedRotation;
      T.Scale := FCopiedScale;
    end;
    ModifiedOutsideObjectInspector(
      Format('Paste transform to %d objects', [TransformManipulate.SelectedCount]), ucHigh);
  end else
  begin
    T := CurrentTransform;
    if T <> nil then
    begin
      T.Translation := FCopiedTranslation;
      T.Rotation := FCopiedRotation;
      T.Scale := FCopiedScale;
      ModifiedOutsideObjectInspector('Paste transform to ' + T.Name, ucHigh);
    end;
  end;
end;

procedure TDesignFrame.ButtonCopyTransformClick(Sender: TObject);
begin
  CopyTransform;
end;

procedure TDesignFrame.ButtonPasteTransformClick(Sender: TObject);
begin
  PasteTransform;
end;

procedure TDesignFrame.ToggleSelectedVisibility;
var
  I: Integer;
  C: TComponent;
  ToggledCount: Integer;
  NewExists: Boolean;
  FirstFound: Boolean;
begin
  if ControlsTree.SelectionCount = 0 then Exit;

  FirstFound := false;
  NewExists := false;
  ToggledCount := 0;

  for I := 0 to ControlsTree.SelectionCount - 1 do
  begin
    C := SelectedFromNode(ControlsTree.Selections[I]);
    if C is TCastleTransform then
    begin
      if not FirstFound then
      begin
        NewExists := not TCastleTransform(C).Exists;
        FirstFound := true;
      end;
      TCastleTransform(C).Exists := NewExists;
      Inc(ToggledCount);
    end else
    if C is TCastleUserInterface then
    begin
      if not FirstFound then
      begin
        NewExists := not TCastleUserInterface(C).Exists;
        FirstFound := true;
      end;
      TCastleUserInterface(C).Exists := NewExists;
      Inc(ToggledCount);
    end;
  end;

  if ToggledCount > 0 then
  begin
    ControlsTree.Invalidate;
    ModifiedOutsideObjectInspector(
      Format('Toggle visibility (Exists=%s) for %d component(s)',
        [BoolToStr(NewExists, true), ToggledCount]), ucHigh);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemToggleVisibilityClick(Sender: TObject);
begin
  ToggleSelectedVisibility;
end;

procedure TDesignFrame.ControlsTreeDblClick(Sender: TObject);
begin
  if CurrentTransform <> nil then
    ViewportViewSelected;
end;

procedure TDesignFrame.ControlsTreeKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if not ControlsTree.IsEditing then
  begin
    if Key = Ord('H') then
    begin
      if Shift = [] then
      begin
        ToggleSelectedVisibility;
        Key := 0;
      end else
      if Shift = [ssShift] then
      begin
        IsolateSelected;
        Key := 0;
      end else
      if Shift = [ssAlt] then
      begin
        ShowAllHidden;
        Key := 0;
      end;
    end else
    if Key = Ord('G') then
    begin
      if Shift = [ssCtrl] then
      begin
        GroupSelectedTransforms;
        Key := 0;
      end else
      if Shift = [ssCtrl, ssShift] then
      begin
        UngroupSelectedTransforms;
        Key := 0;
      end else
      if Shift = [ssCtrl, ssAlt] then
      begin
        ShowGridDuplicateDialog;
        Key := 0;
      end;
    end else
    if Key = Ord('L') then
    begin
      if Shift = [] then
      begin
        ToggleSelectedLock;
        Key := 0;
      end else
      if Shift = [ssAlt] then
      begin
        UnlockAll;
        Key := 0;
      end;
    end else
    if (Key = Ord('D')) and (Shift = [ssCtrl, ssShift]) then
    begin
      ShowArrayDuplicateDialog;
      Key := 0;
    end else
    if (Key = Ord('D')) and (Shift = [ssCtrl, ssAlt]) then
    begin
      ShowRadialDuplicateDialog;
      Key := 0;
    end else
    if (Key = Ord('I')) and (Shift = [ssCtrl]) then
    begin
      InvertSelection;
      Key := 0;
    end else
    if Key = VK_OEM_6 then
    begin
      if Shift = [ssCtrl] then
      begin
        SelectChildren(false);
        Key := 0;
      end else
      if Shift = [ssCtrl, ssShift] then
      begin
        SelectChildren(true);
        Key := 0;
      end;
    end else
    if (Key = Ord('R')) and (Shift = [ssCtrl, ssShift]) then
    begin
      ShowReplaceComponentPalette;
      Key := 0;
    end;
  end;
end;

function TDesignFrame.NodeMatchesHierarchyFilter(const C: TComponent): Boolean;
var
  Query, LowerName, LowerClass: String;
begin
  if C = nil then Exit(false);
  Query := Trim(LowerCase(EditFindInHierarchy.Text));
  if Query = '' then Exit(true);

  LowerName := LowerCase(C.Name);
  LowerClass := LowerCase(C.ClassName);

  if (Length(Query) > 1) and (Query[1] = '+') then
  begin
    Delete(Query, 1, 1);
    Result := Pos(Query, LowerClass) <> 0;
  end else
    Result := (Pos(Query, LowerName) <> 0) or (Pos(Query, LowerClass) <> 0);
end;

procedure TDesignFrame.UpdateViewModeButtonCaption;
begin
  if ButtonViewMode = nil then Exit;
  if InternalForceWireframe = weWireframeOnly then
    ButtonViewMode.Caption := 'View: Wire'
  else if InternalForceWireframe = weSolidWireframe then
    ButtonViewMode.Caption := 'View: SolidWire'
  else if InternalForceUnlit then
    ButtonViewMode.Caption := 'View: Unlit'
  else
    ButtonViewMode.Caption := 'View: Lit';
end;

procedure TDesignFrame.CycleViewportRenderMode;
begin
  if (InternalForceWireframe = weNormal) and (not InternalForceUnlit) then
  begin
    InternalForceUnlit := true;
    InternalForceWireframe := weNormal;
  end else
  if (InternalForceWireframe = weNormal) and InternalForceUnlit then
  begin
    InternalForceUnlit := false;
    InternalForceWireframe := weWireframeOnly;
  end else
  if InternalForceWireframe = weWireframeOnly then
  begin
    InternalForceUnlit := false;
    InternalForceWireframe := weSolidWireframe;
  end else
  begin
    InternalForceUnlit := false;
    InternalForceWireframe := weNormal;
  end;
  UpdateViewModeButtonCaption;
end;

procedure TDesignFrame.ButtonViewModeClick(Sender: TObject);
begin
  CycleViewportRenderMode;
end;

function TDesignFrame.EffectiveShowStatistics: Boolean;
begin
  Result := FShowStatisticsToolbar or
    (Assigned(OnShowStatistics) and OnShowStatistics());
end;

procedure TDesignFrame.ButtonShowStatsClick(Sender: TObject);
begin
  if ButtonShowStats <> nil then
    FShowStatisticsToolbar := ButtonShowStats.Down
  else
    FShowStatisticsToolbar := not FShowStatisticsToolbar;
end;

procedure TDesignFrame.ButtonShowCollidersClick(Sender: TObject);
begin
  if ButtonShowColliders <> nil then
    ShowColliders := ButtonShowColliders.Down
  else
    ShowColliders := not ShowColliders;
end;

procedure TDesignFrame.PopulateQuickAddList(const FilterText: String);
var
  R: TRegisteredComponent;
  Category, CaptionStr, Part, ItemText, LowerFilter: String;
  Sel: TComponent;
  CanAddUI, CanAddTransform, CanAddBehavior, CanAddNonVisual: Boolean;
begin
  if FQuickAddList = nil then Exit;
  FQuickAddList.Items.BeginUpdate;
  try
    FQuickAddList.Items.Clear;
    LowerFilter := Trim(LowerCase(FilterText));

    Sel := SelectedComponent;
    if FQuickAddReplaceMode then
    begin
      CanAddTransform := (Sel is TCastleTransform) or
                         ((TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 0));
      CanAddUI := (not CanAddTransform) and (Sel is TCastleUserInterface);
      CanAddBehavior := (not CanAddTransform) and (not CanAddUI) and (Sel is TCastleBehavior);
      CanAddNonVisual := (not CanAddTransform) and (not CanAddUI) and (not CanAddBehavior) and (Sel <> nil);
    end else
    begin
      CanAddUI := (Sel is TCastleUserInterface) or ((Sel = nil) and (DesignRoot is TCastleUserInterface));
      CanAddTransform := (Sel is TCastleTransform) or ((Sel = nil) and (DesignRoot is TCastleTransform)) or
                         (CurrentViewport <> nil);
      CanAddBehavior := (Sel is TCastleTransform) or (Sel is TCastleBehavior) or
                        ((Sel = nil) and (DesignRoot is TCastleTransform));
      CanAddNonVisual := true;
    end;

    for R in RegisteredComponents do
      if not R.IsDeprecated then
      begin
        if R.ComponentClass.InheritsFrom(TCastleUserInterface) then
        begin
          if not CanAddUI then Continue;
          Category := 'UI';
        end else
        if R.ComponentClass.InheritsFrom(TCastleTransform) then
        begin
          if not CanAddTransform then Continue;
          Category := 'Transform';
        end else
        if R.ComponentClass.InheritsFrom(TCastleBehavior) then
        begin
          if not CanAddBehavior then Continue;
          Category := 'Behavior';
        end else
        begin
          if not CanAddNonVisual then Continue;
          Category := 'NonVisual';
        end;

        CaptionStr := '';
        for Part in R.Caption do
        begin
          if CaptionStr <> '' then
            CaptionStr := CaptionStr + ' -> ';
          CaptionStr := CaptionStr + Part;
        end;

        ItemText := Format('[%s] %s (%s)', [
          Category, CaptionStr, R.ComponentClass.ClassName]);

        if (LowerFilter = '') or (Pos(LowerFilter, LowerCase(ItemText)) <> 0) then
          FQuickAddList.Items.AddObject(ItemText, R);
      end;

    if FQuickAddList.Items.Count > 0 then
      FQuickAddList.ItemIndex := 0;
  finally
    FQuickAddList.Items.EndUpdate;
  end;
end;

procedure TDesignFrame.QuickAddEditChange(Sender: TObject);
begin
  if FQuickAddEdit <> nil then
    PopulateQuickAddList(FQuickAddEdit.Text);
end;

procedure TDesignFrame.QuickAddEditKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if FQuickAddList = nil then Exit;
  if Key = VK_DOWN then
  begin
    if FQuickAddList.ItemIndex < FQuickAddList.Items.Count - 1 then
      FQuickAddList.ItemIndex := FQuickAddList.ItemIndex + 1;
    Key := 0;
  end else
  if Key = VK_UP then
  begin
    if FQuickAddList.ItemIndex > 0 then
      FQuickAddList.ItemIndex := FQuickAddList.ItemIndex - 1;
    Key := 0;
  end;
end;

procedure TDesignFrame.QuickAddListDblClick(Sender: TObject);
var
  ParentForm: TCustomForm;
begin
  if (FQuickAddList <> nil) and (FQuickAddList.ItemIndex >= 0) then
  begin
    ParentForm := GetParentForm(FQuickAddList);
    if ParentForm <> nil then
      ParentForm.ModalResult := mrOk;
  end;
end;

procedure TDesignFrame.ShowQuickAddPalette;
var
  Dialog: TForm;
  BottomPanel: TPanel;
  BtnOk, BtnCancel: TButton;
  R: TRegisteredComponent;
  Sel: TComponent;
begin
  Dialog := TForm.CreateNew(Self);
  try
    Dialog.Caption := 'Quick-Add Component Palette (Ctrl+P)';
    Dialog.Position := poMainFormCenter;
    Dialog.Width := 520;
    Dialog.Height := 420;
    Dialog.BorderStyle := bsSizeToolWin;

    FQuickAddEdit := TEdit.Create(Dialog);
    FQuickAddEdit.Align := alTop;
    FQuickAddEdit.BorderSpacing.Around := 8;
    FQuickAddEdit.TextHint := 'Search component by name, category, or class (e.g. Scene, Light, Button, RigidBody)...';
    FQuickAddEdit.OnChange := @QuickAddEditChange;
    FQuickAddEdit.OnKeyDown := @QuickAddEditKeyDown;
    FQuickAddEdit.Parent := Dialog;

    BottomPanel := TPanel.Create(Dialog);
    BottomPanel.Align := alBottom;
    BottomPanel.AutoSize := true;
    BottomPanel.BevelOuter := bvNone;
    BottomPanel.Parent := Dialog;

    BtnCancel := TButton.Create(Dialog);
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := true;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Align := alRight;
    BtnCancel.BorderSpacing.Around := 6;
    BtnCancel.Parent := BottomPanel;

    BtnOk := TButton.Create(Dialog);
    BtnOk.Caption := 'Add Component';
    BtnOk.Default := true;
    BtnOk.ModalResult := mrOk;
    BtnOk.AutoSize := true;
    BtnOk.Align := alRight;
    BtnOk.BorderSpacing.Around := 6;
    BtnOk.Parent := BottomPanel;

    FQuickAddList := TListBox.Create(Dialog);
    FQuickAddList.Align := alClient;
    FQuickAddList.BorderSpacing.Left := 8;
    FQuickAddList.BorderSpacing.Right := 8;
    FQuickAddList.OnDblClick := @QuickAddListDblClick;
    FQuickAddList.Parent := Dialog;

    PopulateQuickAddList('');

    if (Dialog.ShowModal = mrOk) and
       (FQuickAddList.ItemIndex >= 0) and
       (FQuickAddList.Items.Objects[FQuickAddList.ItemIndex] is TRegisteredComponent) then
    begin
      R := TRegisteredComponent(FQuickAddList.Items.Objects[FQuickAddList.ItemIndex]);
      Sel := SelectedComponent;
      if R.ComponentClass.InheritsFrom(TCastleTransform) and
         (not (Sel is TCastleTransform)) and
         (not ((Sel = nil) and (DesignRoot is TCastleTransform))) and
         (CurrentViewport <> nil) then
        SelectedComponent := CurrentViewport;
      AddComponent(R.ComponentClass, R.OnCreate);
    end;
  finally
    FQuickAddEdit := nil;
    FQuickAddList := nil;
    FreeAndNil(Dialog);
  end;
end;

procedure TDesignFrame.ButtonQuickAddClick(Sender: TObject);
begin
  ShowQuickAddPalette;
end;

procedure TDesignFrame.SimulationSingleStep;
var
  HandleInput: Boolean;
begin
  if CastleApplicationMode = appDesign then Exit;

  if CastleApplicationMode = appSimulation then
  begin
    SimulationPauseUnpause;
    Exit;
  end;

  InternalCastleApplicationMode := appSimulation;
  try
    HandleInput := true;
    if CurrentViewport <> nil then
      CurrentViewport.Update(1.0 / 60.0, HandleInput);
  finally
    InternalCastleApplicationMode := appSimulationPaused;
  end;
  ActionSimulationPlayStopUpdate(ActionSimulationPlayStop);
  ActionSimulationPauseUnpauseUpdate(ActionSimulationPauseUnpause);
end;

procedure TDesignFrame.ButtonSimulationStepClick(Sender: TObject);
begin
  SimulationSingleStep;
end;

procedure TDesignFrame.KeepSimulationChanges;
type
  TSimTransformState = record
    Name: String;
    Translation: TVector3;
    Rotation: TVector4;
    Scale: TVector3;
  end;
var
  States: array of TSimTransformState;
  StateCount, I, AppliedCount: Integer;
  C: TComponent;
  T: TCastleTransform;
begin
  if not (CastleApplicationMode in [appSimulation, appSimulationPaused]) then
    Exit;
  if DesignOwner = nil then
    Exit;

  SetLength(States, DesignOwner.ComponentCount);
  StateCount := 0;
  for I := 0 to DesignOwner.ComponentCount - 1 do
  begin
    C := DesignOwner.Components[I];
    if (C is TCastleTransform) and (C.Name <> '') and Selectable(C) then
    begin
      T := TCastleTransform(C);
      States[StateCount].Name := T.Name;
      States[StateCount].Translation := T.Translation;
      States[StateCount].Rotation := T.Rotation;
      States[StateCount].Scale := T.Scale;
      Inc(StateCount);
    end;
  end;

  // Stop simulation (restores DesignStateBeforePhysicsRun)
  SimulationPlayStop;

  AppliedCount := 0;
  if DesignOwner <> nil then
  begin
    for I := 0 to StateCount - 1 do
    begin
      C := DesignOwner.FindComponent(States[I].Name);
      if C is TCastleTransform then
      begin
        T := TCastleTransform(C);
        if (not TVector3.PerfectlyEquals(T.Translation, States[I].Translation)) or
           (not TVector4.PerfectlyEquals(T.Rotation, States[I].Rotation)) or
           (not TVector3.PerfectlyEquals(T.Scale, States[I].Scale)) then
        begin
          T.Translation := States[I].Translation;
          T.Rotation := States[I].Rotation;
          T.Scale := States[I].Scale;
          Inc(AppliedCount);
        end;
      end;
    end;
  end;

  if AppliedCount > 0 then
    ModifiedOutsideObjectInspector(
      Format('Keep physics simulation changes (%d transforms)', [AppliedCount]), ucHigh);
end;

procedure TDesignFrame.ButtonKeepSimulationClick(Sender: TObject);
begin
  KeepSimulationChanges;
end;

procedure TDesignFrame.TogglePivotMode;
begin
  if TransformManipulate.PivotMode = pmPrimarySelected then
  begin
    TransformManipulate.PivotMode := pmSelectionCenter;
    if ButtonPivotMode <> nil then
      ButtonPivotMode.Caption := 'Pivot: Center';
  end else
  begin
    TransformManipulate.PivotMode := pmPrimarySelected;
    if ButtonPivotMode <> nil then
      ButtonPivotMode.Caption := 'Pivot: Primary';
  end;
end;

procedure TDesignFrame.ButtonPivotModeClick(Sender: TObject);
begin
  TogglePivotMode;
end;

procedure TDesignFrame.ViewportSnapToGrid;
var
  SavedSnap: Single;
begin
  if TransformManipulate = nil then Exit;
  SavedSnap := TransformManipulate.TranslateSnap;
  if SavedSnap <= 0 then
    TransformManipulate.TranslateSnap := 1.0;
  try
    TransformManipulate.SnapSelectedToGrid;
    TransformManipulate.SnapSelectedRotationAndScaleToGrid;
  finally
    TransformManipulate.TranslateSnap := SavedSnap;
  end;
end;

procedure TDesignFrame.ButtonSnapToGridClick(Sender: TObject);
begin
  ViewportSnapToGrid;
end;

procedure TDesignFrame.ViewportProjectAlongView(const AlignToNormal: Boolean);
var
  V: TCastleViewport;
  CamPos, CamDir, CamUp: TVector3;
begin
  V := CurrentViewport;
  if (V = nil) or (V.InternalCamera = nil) or (TransformManipulate = nil) then Exit;
  V.InternalCamera.GetWorldView(CamPos, CamDir, CamUp);
  TransformManipulate.ProjectSelectedAlongDirection(CamDir, AlignToNormal);
end;

procedure TDesignFrame.ButtonProjectAlongViewClick(Sender: TObject);
begin
  ViewportProjectAlongView(
    (ssShift in GetKeyShiftState) or (ssAlt in GetKeyShiftState));
end;

procedure TDesignFrame.ViewportAlignTransformToView;
var
  V: TCastleViewport;
  T: TCastleTransform;
  CamPos, CamDir, CamUp: TVector3;
begin
  V := CurrentViewport;
  T := CurrentTransform;
  if (V = nil) or (V.InternalCamera = nil) or (T = nil) then Exit;

  V.InternalCamera.GetWorldView(CamPos, CamDir, CamUp);
  T.SetWorldView(CamPos, CamDir, CamUp);
  ModifiedOutsideObjectInspector('Move Transform To View: ' + T.Name, ucHigh);
end;

procedure TDesignFrame.ButtonMoveTransformToViewClick(Sender: TObject);
begin
  ViewportAlignTransformToView;
end;

procedure TDesignFrame.AlignSelectionToAxis(const Axis: T3DAxis);
begin
  if TransformManipulate <> nil then
    TransformManipulate.AlignSelected(Axis, atPrimary);
end;

procedure TDesignFrame.DistributeSelectionAlongAxis(const Axis: T3DAxis);
begin
  if TransformManipulate <> nil then
    TransformManipulate.DistributeSelected(Axis);
end;

procedure TDesignFrame.DistributeSelectionGapsAlongAxis(const Axis: T3DAxis);
begin
  if TransformManipulate <> nil then
    TransformManipulate.DistributeSelectedGaps(Axis);
end;

procedure TDesignFrame.ButtonAlignAxisClick(Sender: TObject);
begin
  if Sender is TComponent then
    AlignSelectionToAxis(TComponent(Sender).Tag);
end;

procedure TDesignFrame.ButtonDistributeAxisClick(Sender: TObject);
begin
  if Sender is TComponent then
  begin
    if ssShift in GetKeyShiftState then
      DistributeSelectionGapsAlongAxis(TComponent(Sender).Tag)
    else
      DistributeSelectionAlongAxis(TComponent(Sender).Tag);
  end;
end;

procedure TDesignFrame.StackSelectionAlongAxis(const Axis: T3DAxis);
begin
  if TransformManipulate <> nil then
    TransformManipulate.StackSelected(Axis, 0);
end;

procedure TDesignFrame.ButtonStackAxisClick(Sender: TObject);
begin
  if Sender is TComponent then
    StackSelectionAlongAxis(TComponent(Sender).Tag);
end;

procedure TDesignFrame.MirrorSelectionAlongAxis(const Axis: T3DAxis);
begin
  if TransformManipulate <> nil then
    TransformManipulate.MirrorSelected(Axis);
end;

procedure TDesignFrame.ButtonMirrorAxisClick(Sender: TObject);
begin
  if Sender is TComponent then
    MirrorSelectionAlongAxis(TComponent(Sender).Tag);
end;

procedure TDesignFrame.RotateSelection90Y;
begin
  if TransformManipulate <> nil then
    TransformManipulate.RotateSelected90(1, true);
end;

procedure TDesignFrame.ButtonRotate90YClick(Sender: TObject);
begin
  RotateSelection90Y;
end;

procedure TDesignFrame.RandomizeSelectionTransform;
begin
  if TransformManipulate <> nil then
    TransformManipulate.RandomizeSelected(Pi, 0.85, 1.15, 0);
end;

procedure TDesignFrame.ButtonRandomizeTransformClick(Sender: TObject);
begin
  RandomizeSelectionTransform;
end;

procedure TDesignFrame.AdjustCameraSpeed(const Factor: Single);
var
  V: TCastleViewport;
  WalkNav: TCastleWalkNavigation;
begin
  V := CurrentViewport;
  if (V <> nil) and (V.InternalDesignNavigation is TCastleWalkNavigation) then
  begin
    WalkNav := TCastleWalkNavigation(V.InternalDesignNavigation);
    WalkNav.MoveSpeed := Clamped(WalkNav.MoveSpeed * Factor, 0.05, 5000.0);
  end;
end;

procedure TDesignFrame.IsolateSelected;

  function IsAncestorOfAnySelectedNode(const CandidateNode: TTreeNode): Boolean;
  var
    I: Integer;
    P: TTreeNode;
  begin
    Result := false;
    if CandidateNode = nil then Exit;
    for I := 0 to ControlsTree.SelectionCount - 1 do
    begin
      P := ControlsTree.Selections[I].Parent;
      while P <> nil do
      begin
        if P = CandidateNode then
          Exit(true);
        P := P.Parent;
      end;
    end;
  end;

var
  Selected: TComponentList;
  SelectedCount, ChangedCount: Integer;
  TreeNode: TTreeNode;
  C: TComponent;
  ShouldBeVisible: Boolean;
begin
  GetSelected(Selected, SelectedCount, false);
  try
    if (Selected = nil) or (SelectedCount = 0) then Exit;

    ChangedCount := 0;
    TreeNode := ControlsTree.Items.GetFirstNode;
    while TreeNode <> nil do
    begin
      C := SelectedFromNode(TreeNode, false);
      if (C <> nil) and (C <> DesignRoot) and
         (not (C is TCastleAbstractRootTransform)) and
         (not (C is TCastleViewport)) then
      begin
        ShouldBeVisible :=
          (Selected.IndexOf(C) <> -1) or
          IsAncestorOfAnySelectedNode(TreeNode) or
          IsComponentDescendantOfSelection(C, Selected);

        if C is TCastleTransform then
        begin
          if TCastleTransform(C).Exists <> ShouldBeVisible then
          begin
            TCastleTransform(C).Exists := ShouldBeVisible;
            Inc(ChangedCount);
          end;
        end else
        if C is TCastleUserInterface then
        begin
          if TCastleUserInterface(C).Exists <> ShouldBeVisible then
          begin
            TCastleUserInterface(C).Exists := ShouldBeVisible;
            Inc(ChangedCount);
          end;
        end;
      end;
      TreeNode := TreeNode.GetNext;
    end;

    if ChangedCount > 0 then
    begin
      ControlsTree.Invalidate;
      ModifiedOutsideObjectInspector(
        Format('Isolate %d selected component(s)', [SelectedCount]), ucHigh);
    end;
  finally
    FreeAndNil(Selected);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemIsolateSelectedClick(Sender: TObject);
begin
  IsolateSelected;
end;

procedure TDesignFrame.ShowAllHidden;
var
  TreeNode: TTreeNode;
  C: TComponent;
  RestoredCount: Integer;
begin
  RestoredCount := 0;
  TreeNode := ControlsTree.Items.GetFirstNode;
  while TreeNode <> nil do
  begin
    C := SelectedFromNode(TreeNode, false);
    if (C is TCastleTransform) and (not TCastleTransform(C).Exists) then
    begin
      TCastleTransform(C).Exists := true;
      Inc(RestoredCount);
    end else
    if (C is TCastleUserInterface) and (not TCastleUserInterface(C).Exists) then
    begin
      TCastleUserInterface(C).Exists := true;
      Inc(RestoredCount);
    end;
    TreeNode := TreeNode.GetNext;
  end;

  if RestoredCount > 0 then
  begin
    ControlsTree.Invalidate;
    ModifiedOutsideObjectInspector(
      Format('Show all hidden (%d component(s))', [RestoredCount]), ucHigh);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemShowAllHiddenClick(Sender: TObject);
begin
  ShowAllHidden;
end;

procedure TDesignFrame.GroupSelectedTransforms;
var
  Selected: TComponentList;
  SelectedCount, I, Count: Integer;
  Items: array of TCastleTransform;
  WorldPositions: array of TVector3;
  C: TComponent;
  T, TargetParent, NewGroup: TCastleTransform;
  GroupWorldCenter: TVector3;
begin
  if DesignOwner = nil then Exit;

  GetSelected(Selected, SelectedCount, false);
  try
    if (Selected = nil) or (SelectedCount = 0) then Exit;

    SetLength(Items, SelectedCount);
    SetLength(WorldPositions, SelectedCount);
    Count := 0;
    for I := 0 to SelectedCount - 1 do
    begin
      C := Selected[I];
      if (C is TCastleTransform) and Deletable(C) and
         (TCastleTransform(C).Parent <> nil) and
         (not IsComponentDescendantOfSelection(C, Selected)) then
      begin
        T := TCastleTransform(C);
        Items[Count] := T;
        if T.HasWorldTransform then
          WorldPositions[Count] := T.LocalToWorld(TVector3.Zero)
        else
          WorldPositions[Count] := T.Translation;
        Inc(Count);
      end;
    end;

    if Count = 0 then Exit;

    TargetParent := Items[0].Parent;
    GroupWorldCenter := TransformManipulate.SelectionWorkingCenter;

    NewGroup := TCastleTransform.Create(DesignOwner);
    NewGroup.Name := ProposeComponentName(TCastleTransform, DesignOwner, 'Group');
    TargetParent.Add(NewGroup);

    if TargetParent.HasWorldTransform then
      NewGroup.Translation := TargetParent.WorldToLocal(GroupWorldCenter)
    else
      NewGroup.Translation := GroupWorldCenter;

    for I := 0 to Count - 1 do
    begin
      T := Items[I];
      if T.Parent <> nil then
        T.Parent.Remove(T);
      NewGroup.Add(T);
      if NewGroup.HasWorldTransform then
        T.Translation := NewGroup.WorldToLocal(WorldPositions[I])
      else
        T.Translation := WorldPositions[I] - NewGroup.Translation;
    end;

    UpdateDesign;
    SelectedComponent := NewGroup;
    ModifiedOutsideObjectInspector(
      Format('Group %d transform(s) into %s', [Count, NewGroup.Name]), ucHigh);
  finally
    FreeAndNil(Selected);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemGroupSelectedClick(Sender: TObject);
begin
  GroupSelectedTransforms;
end;

procedure TDesignFrame.UngroupSelectedTransforms;
var
  Selected, UnpackedChildren: TComponentList;
  SelectedCount, I, J, UnpackedGroupCount: Integer;
  C: TComponent;
  GroupT, ParentT, ChildT: TCastleTransform;
  ChildrenToMove: array of TCastleTransform;
  ChildWorldPos, ChildWorldDir, ChildWorldUp: array of TVector3;
  ChildHasWorld: array of Boolean;
  ChildCount, InsertIdx: Integer;
begin
  if DesignOwner = nil then Exit;

  GetSelected(Selected, SelectedCount, false);
  if (Selected = nil) or (SelectedCount = 0) then
  begin
    FreeAndNil(Selected);
    Exit;
  end;

  UnpackedChildren := TComponentList.Create(false);
  try
    UnpackedGroupCount := 0;
    for I := 0 to SelectedCount - 1 do
    begin
      C := Selected[I];
      if (C is TCastleTransform) and Deletable(C) and
         (TCastleTransform(C).Parent <> nil) then
      begin
        GroupT := TCastleTransform(C);
        ParentT := GroupT.Parent;

        ChildCount := 0;
        SetLength(ChildrenToMove, GroupT.Count);
        SetLength(ChildWorldPos, GroupT.Count);
        SetLength(ChildWorldDir, GroupT.Count);
        SetLength(ChildWorldUp, GroupT.Count);
        SetLength(ChildHasWorld, GroupT.Count);

        for J := 0 to GroupT.Count - 1 do
          if Selectable(GroupT[J]) and (not (csSubComponent in GroupT[J].ComponentStyle)) and
             (not (GroupT[J] is TCastleToolTransform)) then
          begin
            ChildT := GroupT[J];
            ChildrenToMove[ChildCount] := ChildT;
            ChildHasWorld[ChildCount] := ChildT.HasWorldTransform;
            if ChildHasWorld[ChildCount] then
              ChildT.GetWorldView(ChildWorldPos[ChildCount], ChildWorldDir[ChildCount], ChildWorldUp[ChildCount])
            else
              ChildWorldPos[ChildCount] := GroupT.Translation + ChildT.Translation;
            Inc(ChildCount);
          end;

        if ChildCount = 0 then
          Continue;

        InsertIdx := ParentT.List.IndexOf(GroupT);
        for J := 0 to ChildCount - 1 do
        begin
          ChildT := ChildrenToMove[J];
          GroupT.Remove(ChildT);
          if InsertIdx >= 0 then
          begin
            ParentT.Insert(InsertIdx, ChildT);
            Inc(InsertIdx);
          end else
            ParentT.Add(ChildT);

          if ChildHasWorld[J] and ChildT.HasWorldTransform then
            ChildT.SetWorldView(ChildWorldPos[J], ChildWorldDir[J], ChildWorldUp[J])
          else
            ChildT.Translation := ChildWorldPos[J];

          UnpackedChildren.Add(ChildT);
        end;

        // If GroupT is a plain TCastleTransform container with no remaining children/behaviors, remove it
        if (GroupT.ClassType = TCastleTransform) and
           (GroupT.Count = 0) and
           (GroupT.BehaviorsCount = 0) and
           (GroupT.NonVisualComponentsCount = 0) then
          GroupT.Free;

        Inc(UnpackedGroupCount);
      end;
    end;

    if UnpackedGroupCount > 0 then
    begin
      UpdateDesign;
      SetSelected(UnpackedChildren);
      ModifiedOutsideObjectInspector(
        Format('Ungroup %d transform group(s)', [UnpackedGroupCount]), ucHigh);
    end;
  finally
    FreeAndNil(UnpackedChildren);
    FreeAndNil(Selected);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemUngroupSelectedClick(Sender: TObject);
begin
  UngroupSelectedTransforms;
end;

procedure TDesignFrame.SaveCameraBookmark(const Slot: Integer);
var
  V: TCastleViewport;
begin
  if (Slot < 0) or (Slot > 9) then Exit;
  V := CurrentViewport;
  if (V = nil) or (V.InternalCamera = nil) then Exit;

  V.InternalCamera.GetWorldView(
    FCameraBookmarks[Slot].Pos,
    FCameraBookmarks[Slot].Dir,
    FCameraBookmarks[Slot].Up);
  FCameraBookmarks[Slot].Valid := true;
end;

procedure TDesignFrame.RecallCameraBookmark(const Slot: Integer);
var
  V: TCastleViewport;
begin
  if (Slot < 0) or (Slot > 9) then Exit;
  if not FCameraBookmarks[Slot].Valid then Exit;
  V := CurrentViewport;
  if (V = nil) or (V.InternalCamera = nil) then Exit;

  V.InternalCamera.AnimateTo(
    FCameraBookmarks[Slot].Pos,
    FCameraBookmarks[Slot].Dir,
    FCameraBookmarks[Slot].Up,
    CameraTransitionTime);
end;

procedure TDesignFrame.SelectAllOfSameClass;
var
  Sel, C: TComponent;
  TargetClass: TClass;
  TreeNode: TTreeNode;
  MatchingNodes: TList;
begin
  Sel := SelectedComponent;
  if Sel = nil then Exit;
  TargetClass := Sel.ClassType;

  MatchingNodes := TList.Create;
  try
    TreeNode := ControlsTree.Items.GetFirstNode;
    while TreeNode <> nil do
    begin
      C := SelectedFromNode(TreeNode, false);
      if (C <> nil) and (C.ClassType = TargetClass) then
        MatchingNodes.Add(TreeNode);
      TreeNode := TreeNode.GetNext;
    end;
    if MatchingNodes.Count > 0 then
      ControlsTree.Select(MatchingNodes);
  finally
    FreeAndNil(MatchingNodes);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemSelectSameClassClick(Sender: TObject);
begin
  SelectAllOfSameClass;
end;

procedure TDesignFrame.ExpandSelectedSubtree;
var
  I: Integer;
begin
  ControlsTree.Items.BeginUpdate;
  try
    if ControlsTree.SelectionCount > 0 then
    begin
      for I := 0 to ControlsTree.SelectionCount - 1 do
        ControlsTree.Selections[I].Expand(true);
    end else
      ControlsTree.FullExpand;
  finally
    ControlsTree.Items.EndUpdate;
  end;
end;

procedure TDesignFrame.CollapseSelectedSubtree;
var
  I: Integer;
begin
  ControlsTree.Items.BeginUpdate;
  try
    if ControlsTree.SelectionCount > 0 then
    begin
      for I := 0 to ControlsTree.SelectionCount - 1 do
        ControlsTree.Selections[I].Collapse(true);
    end else
      ControlsTree.FullCollapse;
  finally
    ControlsTree.Items.EndUpdate;
  end;
end;

procedure TDesignFrame.MenuTreeViewItemExpandAllClick(Sender: TObject);
begin
  ExpandSelectedSubtree;
end;

procedure TDesignFrame.MenuTreeViewItemCollapseAllClick(Sender: TObject);
begin
  CollapseSelectedSubtree;
end;

procedure TDesignFrame.ResetSelectedPropertyToDefault;
var
  ActiveInspector: TOIPropertyGrid;
  Row: TOIPropertyGridRow;
  DefaultVal: String;
begin
  ActiveInspector := GetInspectorForActiveTab;
  if ActiveInspector = nil then Exit;
  Row := ActiveInspector.GetActiveRow;
  if (Row = nil) or (Row.Editor = nil) then Exit;

  DefaultVal := Row.Editor.GetDefaultValue;
  if (DefaultVal <> '') and (DefaultVal <> Row.Editor.GetVisualValue) then
    Row.Editor.SetValue(DefaultVal)
  else
    Row.Editor.Revert;

  ModifiedOutsideObjectInspector('Reset property ' + Row.Name + ' to default', ucHigh);
end;

procedure TDesignFrame.ButtonResetPropertyClick(Sender: TObject);
begin
  ResetSelectedPropertyToDefault;
end;

procedure TDesignFrame.ViewportSnapToCursor(const SnapToVertex: Boolean;
  const AlignToNormal: Boolean);
var
  V: TCastleViewport;
  RayOrigin, RayDirection: TVector3;
begin
  if (TransformManipulate = nil) or (TransformManipulate.SelectedCount = 0) then
    Exit;
  V := CurrentViewport;
  if (V = nil) or (CastleControl = nil) or (CastleControl.Container = nil) then
    Exit;

  V.PositionToRay(CastleControl.Container.MousePosition, true, RayOrigin, RayDirection);
  TransformManipulate.SnapSelectedToRay(RayOrigin, RayDirection, SnapToVertex, AlignToNormal);
end;

function TDesignFrame.IsComponentLocked(const C: TComponent): Boolean;
var
  Node: TTreeNode;
begin
  Result := false;
  if (C = nil) or (FLockedComponents = nil) or (FLockedComponents.Count = 0) then
    Exit;
  if FLockedComponents.IndexOf(C) <> -1 then
    Exit(true);
  if (TreeNodeMap <> nil) and TreeNodeMap.TryGetValue(C, Node) then
  begin
    Node := Node.Parent;
    while Node <> nil do
    begin
      if (Node.Data <> nil) and (FLockedComponents.IndexOf(TComponent(Node.Data)) <> -1) then
        Exit(true);
      Node := Node.Parent;
    end;
  end;
end;

procedure TDesignFrame.ToggleSelectedLock;
var
  I: Integer;
  C: TComponent;
  FirstFound, LockTarget: Boolean;
  ToggledCount: Integer;
begin
  if (ControlsTree.SelectionCount = 0) or (FLockedComponents = nil) then
    Exit;

  FirstFound := false;
  LockTarget := true;
  ToggledCount := 0;

  for I := 0 to ControlsTree.SelectionCount - 1 do
  begin
    C := SelectedFromNode(ControlsTree.Selections[I]);
    if (C <> nil) and (C <> DesignRoot) then
    begin
      if not FirstFound then
      begin
        LockTarget := FLockedComponents.IndexOf(C) = -1;
        FirstFound := true;
      end;
      if LockTarget then
      begin
        if FLockedComponents.IndexOf(C) = -1 then
          FLockedComponents.Add(C);
      end else
        FLockedComponents.Remove(C);
      Inc(ToggledCount);
    end;
  end;

  if ToggledCount > 0 then
  begin
    ControlsTree.Invalidate;
    UpdateSelectedControl;
  end;
end;

procedure TDesignFrame.UnlockAll;
begin
  if (FLockedComponents <> nil) and (FLockedComponents.Count > 0) then
  begin
    FLockedComponents.Clear;
    ControlsTree.Invalidate;
    UpdateSelectedControl;
  end;
end;

procedure TDesignFrame.MenuTreeViewItemToggleLockClick(Sender: TObject);
begin
  ToggleSelectedLock;
end;

procedure TDesignFrame.MenuTreeViewItemUnlockAllClick(Sender: TObject);
begin
  UnlockAll;
end;

procedure TDesignFrame.ArrayDuplicateSelected(const Count: Integer;
  const StepOffset: TVector3; const StepYawDeg: Single);
var
  SelectedList, CreatedTransforms: TComponentList;
  SelectedCount, I, StepIdx, SourceCount, InsertIdx: Integer;
  SourceItems: array of TCastleTransform;
  Sel: TComponent;
  T, ParentComp, NewT: TCastleTransform;
  CompStr: String;
  YawRad: Single;
begin
  if (Count <= 0) or (DesignOwner = nil) then Exit;

  GetSelected(SelectedList, SelectedCount, false);
  try
    if (SelectedList = nil) or (SelectedCount = 0) then Exit;

    SetLength(SourceItems, SelectedCount);
    SourceCount := 0;
    for I := 0 to SelectedCount - 1 do
    begin
      Sel := SelectedList[I];
      if (Sel is TCastleTransform) and Deletable(Sel) and
         (TCastleTransform(Sel).Parent <> nil) and
         (not IsComponentDescendantOfSelection(Sel, SelectedList)) then
      begin
        SourceItems[SourceCount] := TCastleTransform(Sel);
        Inc(SourceCount);
      end;
    end;

    if SourceCount = 0 then Exit;

    CreatedTransforms := TComponentList.Create(false);
    try
      for StepIdx := 1 to Count do
      begin
        YawRad := DegToRad(StepYawDeg * StepIdx);
        for I := 0 to SourceCount - 1 do
        begin
          T := SourceItems[I];
          ParentComp := T.Parent;
          CompStr := ComponentToString(T);
          NewT := StringToComponent(CompStr, DesignOwner) as TCastleTransform;
          InsertIdx := ParentComp.List.IndexOf(T);
          if InsertIdx >= 0 then
            ParentComp.Insert(InsertIdx + 1, NewT)
          else
            ParentComp.Add(NewT);

          NewT.Translation := T.Translation + StepOffset * StepIdx;
          if Abs(YawRad) > 1e-6 then
            NewT.Rotation := (QuatFromAxisAngle(Vector3(0, 1, 0), YawRad, true) *
              QuatFromAxisAngle(T.Rotation, true)).ToAxisAngle;

          CreatedTransforms.Add(NewT);
        end;
      end;

      if CreatedTransforms.Count > 0 then
      begin
        UpdateDesign;
        SetSelected(CreatedTransforms);
        ModifiedOutsideObjectInspector(
          Format('Array duplicate (%d copies)', [Count]), ucHigh);
      end;
    finally
      FreeAndNil(CreatedTransforms);
    end;
  finally
    FreeAndNil(SelectedList);
  end;
end;

procedure TDesignFrame.ShowArrayDuplicateDialog;
var
  Dialog: TForm;
  LblCount, LblOffsetX, LblOffsetY, LblOffsetZ, LblYaw: TLabel;
  SpinCount: TSpinEdit;
  SpinOffsetX, SpinOffsetY, SpinOffsetZ, SpinYaw: TFloatSpinEdit;
  BottomPanel: TPanel;
  BtnOk, BtnCancel: TButton;
  T: TCastleTransform;
  BBox: TBox3D;
  DefaultStepX: Single;
begin
  T := CurrentTransform;
  if (T = nil) and ((TransformManipulate = nil) or (TransformManipulate.SelectedCount = 0)) then
    Exit;

  DefaultStepX := 2.0;
  if T <> nil then
  begin
    BBox := T.WorldBoundingBox;
    if (not BBox.IsEmpty) and (BBox.SizeX > 0.01) then
      DefaultStepX := BBox.SizeX;
  end;

  Dialog := TForm.CreateNew(Self);
  try
    Dialog.Caption := 'Array Duplicate (Ctrl+Shift+D)';
    Dialog.Position := poMainFormCenter;
    Dialog.Width := 340;
    Dialog.Height := 260;
    Dialog.BorderStyle := bsDialog;

    LblCount := TLabel.Create(Dialog);
    LblCount.Caption := 'Number of Copies:';
    LblCount.Left := 16;
    LblCount.Top := 18;
    LblCount.Parent := Dialog;

    SpinCount := TSpinEdit.Create(Dialog);
    SpinCount.MinValue := 1;
    SpinCount.MaxValue := 500;
    SpinCount.Value := 5;
    SpinCount.Left := 180;
    SpinCount.Top := 14;
    SpinCount.Width := 130;
    SpinCount.Parent := Dialog;

    LblOffsetX := TLabel.Create(Dialog);
    LblOffsetX.Caption := 'Step Offset X:';
    LblOffsetX.Left := 16;
    LblOffsetX.Top := 54;
    LblOffsetX.Parent := Dialog;

    SpinOffsetX := TFloatSpinEdit.Create(Dialog);
    SpinOffsetX.DecimalPlaces := 2;
    SpinOffsetX.Increment := 0.5;
    SpinOffsetX.MinValue := -10000;
    SpinOffsetX.MaxValue := 10000;
    SpinOffsetX.Value := DefaultStepX;
    SpinOffsetX.Left := 180;
    SpinOffsetX.Top := 50;
    SpinOffsetX.Width := 130;
    SpinOffsetX.Parent := Dialog;

    LblOffsetY := TLabel.Create(Dialog);
    LblOffsetY.Caption := 'Step Offset Y:';
    LblOffsetY.Left := 16;
    LblOffsetY.Top := 90;
    LblOffsetY.Parent := Dialog;

    SpinOffsetY := TFloatSpinEdit.Create(Dialog);
    SpinOffsetY.DecimalPlaces := 2;
    SpinOffsetY.Increment := 0.5;
    SpinOffsetY.MinValue := -10000;
    SpinOffsetY.MaxValue := 10000;
    SpinOffsetY.Value := 0;
    SpinOffsetY.Left := 180;
    SpinOffsetY.Top := 86;
    SpinOffsetY.Width := 130;
    SpinOffsetY.Parent := Dialog;

    LblOffsetZ := TLabel.Create(Dialog);
    LblOffsetZ.Caption := 'Step Offset Z:';
    LblOffsetZ.Left := 16;
    LblOffsetZ.Top := 126;
    LblOffsetZ.Parent := Dialog;

    SpinOffsetZ := TFloatSpinEdit.Create(Dialog);
    SpinOffsetZ.DecimalPlaces := 2;
    SpinOffsetZ.Increment := 0.5;
    SpinOffsetZ.MinValue := -10000;
    SpinOffsetZ.MaxValue := 10000;
    SpinOffsetZ.Value := 0;
    SpinOffsetZ.Left := 180;
    SpinOffsetZ.Top := 122;
    SpinOffsetZ.Width := 130;
    SpinOffsetZ.Parent := Dialog;

    LblYaw := TLabel.Create(Dialog);
    LblYaw.Caption := 'Step Yaw Rotation (deg):';
    LblYaw.Left := 16;
    LblYaw.Top := 162;
    LblYaw.Parent := Dialog;

    SpinYaw := TFloatSpinEdit.Create(Dialog);
    SpinYaw.DecimalPlaces := 1;
    SpinYaw.Increment := 15.0;
    SpinYaw.MinValue := -360;
    SpinYaw.MaxValue := 360;
    SpinYaw.Value := 0;
    SpinYaw.Left := 180;
    SpinYaw.Top := 158;
    SpinYaw.Width := 130;
    SpinYaw.Parent := Dialog;

    BottomPanel := TPanel.Create(Dialog);
    BottomPanel.Align := alBottom;
    BottomPanel.AutoSize := true;
    BottomPanel.BevelOuter := bvNone;
    BottomPanel.Parent := Dialog;

    BtnCancel := TButton.Create(Dialog);
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := true;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Align := alRight;
    BtnCancel.BorderSpacing.Around := 6;
    BtnCancel.Parent := BottomPanel;

    BtnOk := TButton.Create(Dialog);
    BtnOk.Caption := 'Duplicate Array';
    BtnOk.Default := true;
    BtnOk.ModalResult := mrOk;
    BtnOk.AutoSize := true;
    BtnOk.Align := alRight;
    BtnOk.BorderSpacing.Around := 6;
    BtnOk.Parent := BottomPanel;

    if Dialog.ShowModal = mrOk then
      ArrayDuplicateSelected(
        SpinCount.Value,
        Vector3(SpinOffsetX.Value, SpinOffsetY.Value, SpinOffsetZ.Value),
        SpinYaw.Value);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TDesignFrame.ButtonArrayDuplicateClick(Sender: TObject);
begin
  ShowArrayDuplicateDialog;
end;

procedure TDesignFrame.MenuTreeViewItemArrayDuplicateClick(Sender: TObject);
begin
  ShowArrayDuplicateDialog;
end;

procedure TDesignFrame.RadialDuplicateSelected(const Count: Integer;
  const Radius, TotalAngleDeg: Single; const OrientToCenter: Boolean);
var
  SelectedList, SourceTransforms, NewSelection: TComponentList;
  SelectedCount, I, CopyIdx, InsertIdx: Integer;
  Src, ParentT, NewComp: TCastleTransform;
  CompStr: String;
  AngleStepDeg, AngleRad: Single;
  CircleCenter: TVector3;
begin
  if (Count <= 0) or (DesignOwner = nil) then Exit;

  SourceTransforms := TComponentList.Create(false);
  NewSelection := TComponentList.Create(false);
  try
    GetSelected(SelectedList, SelectedCount, false);
    try
      if SelectedList <> nil then
        for I := 0 to SelectedList.Count - 1 do
          if (SelectedList[I] is TCastleTransform) and
             Deletable(SelectedList[I]) and
             (TCastleTransform(SelectedList[I]).Parent <> nil) and
             (not IsComponentDescendantOfSelection(SelectedList[I], SelectedList)) then
            SourceTransforms.Add(SelectedList[I]);
    finally
      FreeAndNil(SelectedList);
    end;

    if (SourceTransforms.Count = 0) and (CurrentTransform <> nil) and
       Deletable(CurrentTransform) and (CurrentTransform.Parent <> nil) then
      SourceTransforms.Add(CurrentTransform);

    if SourceTransforms.Count = 0 then
    begin
      ErrorBox('Select at least one TCastleTransform (that is not the root or a subcomponent) to radial-duplicate.');
      Exit;
    end;

    if SameValue(Abs(TotalAngleDeg), 360.0, 0.01) then
      AngleStepDeg := TotalAngleDeg / (Count + 1)
    else
      AngleStepDeg := TotalAngleDeg / Count;

    for I := 0 to SourceTransforms.Count - 1 do
    begin
      Src := TCastleTransform(SourceTransforms[I]);
      ParentT := Src.Parent;
      CompStr := ComponentToString(Src);
      InsertIdx := ParentT.List.IndexOf(Src);
      CircleCenter := Src.Translation - Vector3(0, 0, Radius);

      for CopyIdx := 1 to Count do
      begin
        AngleRad := DegToRad(AngleStepDeg * CopyIdx);
        NewComp := StringToComponent(CompStr, DesignOwner) as TCastleTransform;
        if not SameValue(Radius, 0.0, SingleEpsilon) then
          NewComp.Translation := CircleCenter + Vector3(Sin(AngleRad) * Radius, 0, Cos(AngleRad) * Radius)
        else
          NewComp.Translation := RotatePointAroundAxisRad(AngleRad, Src.Translation, Vector3(0, 1, 0));

        if OrientToCenter then
          NewComp.Rotation := (QuatFromAxisAngle(Src.Rotation) *
            QuatFromAxisAngle(Vector4(0, 1, 0, AngleRad))).ToAxisAngle;

        if InsertIdx >= 0 then
        begin
          Inc(InsertIdx);
          ParentT.Insert(InsertIdx, NewComp);
        end else
          ParentT.Add(NewComp);

        NewSelection.Add(NewComp);
      end;
    end;

    if NewSelection.Count > 0 then
    begin
      UpdateDesign;
      SetSelected(NewSelection);
      ModifiedOutsideObjectInspector(
        Format('Radial duplicate (%d copies, R=%.2f, %.1f deg)',
          [Count, Radius, TotalAngleDeg]), ucHigh);
    end;
  finally
    FreeAndNil(NewSelection);
    FreeAndNil(SourceTransforms);
  end;
end;

procedure TDesignFrame.ShowRadialDuplicateDialog;
var
  Dialog: TForm;
  LblCount, LblRadius, LblAngle: TLabel;
  SpinCount: TSpinEdit;
  SpinRadius, SpinAngle: TFloatSpinEdit;
  CheckOrient: TCheckBox;
  BottomPanel: TPanel;
  BtnOk, BtnCancel: TButton;
begin
  if (CurrentTransform = nil) and
     ((TransformManipulate = nil) or (TransformManipulate.SelectedCount = 0)) then
  begin
    ErrorBox('Select at least one TCastleTransform component before opening Radial Duplicate.');
    Exit;
  end;

  Dialog := TForm.CreateNew(Self);
  try
    Dialog.Caption := 'Radial / Circular Duplicate (Ctrl+Alt+D)';
    Dialog.Position := poMainFormCenter;
    Dialog.Width := 360;
    Dialog.Height := 215;
    Dialog.BorderStyle := bsDialog;

    LblCount := TLabel.Create(Dialog);
    LblCount.Caption := 'Number of Copies:';
    LblCount.Left := 16;
    LblCount.Top := 18;
    LblCount.Parent := Dialog;

    SpinCount := TSpinEdit.Create(Dialog);
    SpinCount.MinValue := 1;
    SpinCount.MaxValue := 360;
    SpinCount.Value := 7;
    SpinCount.Left := 190;
    SpinCount.Top := 14;
    SpinCount.Width := 140;
    SpinCount.Parent := Dialog;

    LblRadius := TLabel.Create(Dialog);
    LblRadius.Caption := 'Circle Radius (XZ):';
    LblRadius.Left := 16;
    LblRadius.Top := 54;
    LblRadius.Parent := Dialog;

    SpinRadius := TFloatSpinEdit.Create(Dialog);
    SpinRadius.DecimalPlaces := 2;
    SpinRadius.Increment := 1.0;
    SpinRadius.MinValue := -10000;
    SpinRadius.MaxValue := 10000;
    SpinRadius.Value := 5.0;
    SpinRadius.Left := 190;
    SpinRadius.Top := 50;
    SpinRadius.Width := 140;
    SpinRadius.Parent := Dialog;

    LblAngle := TLabel.Create(Dialog);
    LblAngle.Caption := 'Total Arc Angle (deg):';
    LblAngle.Left := 16;
    LblAngle.Top := 90;
    LblAngle.Parent := Dialog;

    SpinAngle := TFloatSpinEdit.Create(Dialog);
    SpinAngle.DecimalPlaces := 1;
    SpinAngle.Increment := 15.0;
    SpinAngle.MinValue := -360;
    SpinAngle.MaxValue := 360;
    SpinAngle.Value := 360.0;
    SpinAngle.Left := 190;
    SpinAngle.Top := 86;
    SpinAngle.Width := 140;
    SpinAngle.Parent := Dialog;

    CheckOrient := TCheckBox.Create(Dialog);
    CheckOrient.Caption := 'Rotate copies along circle arc (+Y yaw)';
    CheckOrient.Checked := true;
    CheckOrient.Left := 16;
    CheckOrient.Top := 126;
    CheckOrient.Parent := Dialog;

    BottomPanel := TPanel.Create(Dialog);
    BottomPanel.Align := alBottom;
    BottomPanel.AutoSize := true;
    BottomPanel.BevelOuter := bvNone;
    BottomPanel.Parent := Dialog;

    BtnCancel := TButton.Create(Dialog);
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := true;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Align := alRight;
    BtnCancel.BorderSpacing.Around := 6;
    BtnCancel.Parent := BottomPanel;

    BtnOk := TButton.Create(Dialog);
    BtnOk.Caption := 'Radial Duplicate';
    BtnOk.Default := true;
    BtnOk.ModalResult := mrOk;
    BtnOk.AutoSize := true;
    BtnOk.Align := alRight;
    BtnOk.BorderSpacing.Around := 6;
    BtnOk.Parent := BottomPanel;

    if Dialog.ShowModal = mrOk then
      RadialDuplicateSelected(
        SpinCount.Value,
        SpinRadius.Value,
        SpinAngle.Value,
        CheckOrient.Checked);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TDesignFrame.ButtonRadialDuplicateClick(Sender: TObject);
begin
  ShowRadialDuplicateDialog;
end;

procedure TDesignFrame.MenuTreeViewItemRadialDuplicateClick(Sender: TObject);
begin
  ShowRadialDuplicateDialog;
end;

procedure TDesignFrame.ReplaceSelectedComponents(const NewClass: TComponentClass;
  const ComponentOnCreate: TNotifyEvent);
var
  SelectedList, RestoredSelection: TComponentList;
  SelectedCount, I: Integer;
  C, NewDesignOwner, NewDesignRoot, TempOwner, TempRoot, ReplacedComp: TComponent;
  NamesToReplace: TStringList;
  Serialized: String;
  LoadInfo: TInternalComponentLoadInfo;
begin
  if (NewClass = nil) or (DesignRoot = nil) or (DesignOwner = nil) then Exit;

  NamesToReplace := TStringList.Create;
  try
    GetSelected(SelectedList, SelectedCount, false);
    try
      if SelectedList <> nil then
        for I := 0 to SelectedList.Count - 1 do
        begin
          C := SelectedList[I];
          if (C = nil) or (csSubComponent in C.ComponentStyle) or (C.Name = '') or
             (C.ClassType = NewClass) then
            Continue;
          if (NewClass.InheritsFrom(TCastleTransform) and (C is TCastleTransform)) or
             (NewClass.InheritsFrom(TCastleUserInterface) and (C is TCastleUserInterface)) or
             (NewClass.InheritsFrom(TCastleBehavior) and (C is TCastleBehavior)) or
             ((not NewClass.InheritsFrom(TCastleTransform)) and
              (not NewClass.InheritsFrom(TCastleUserInterface)) and
              (not NewClass.InheritsFrom(TCastleBehavior)) and
              (not (C is TCastleTransform)) and
              (not (C is TCastleUserInterface)) and
              (not (C is TCastleBehavior))) then
            NamesToReplace.Add(C.Name);
        end;
    finally
      FreeAndNil(SelectedList);
    end;

    if NamesToReplace.Count = 0 then
    begin
      ErrorBox(Format('No selected components can be replaced with %s (either none selected, or already of class %s).',
        [NewClass.ClassName, NewClass.ClassName]));
      Exit;
    end;

    Serialized := ComponentToString(DesignRoot);
    for I := 0 to NamesToReplace.Count - 1 do
    begin
      LoadInfo := TInternalComponentLoadInfo.Create;
      try
        LoadInfo.ChangeClassName := NamesToReplace[I];
        LoadInfo.ChangeClassClass := NewClass;
        if I < NamesToReplace.Count - 1 then
        begin
          TempOwner := TComponent.Create(nil);
          try
            TempRoot := InternalStringToComponent(Serialized, TempOwner, LoadInfo);
            if Assigned(ComponentOnCreate) then
            begin
              ReplacedComp := TempOwner.FindComponent(NamesToReplace[I]);
              if ReplacedComp <> nil then
                ComponentOnCreate(ReplacedComp);
            end;
            Serialized := ComponentToString(TempRoot);
          finally
            FreeAndNil(TempOwner);
          end;
        end else
        begin
          LoadInfo.PreserveDataAcrossUndo := DesignOwner;
          NewDesignOwner := TComponent.Create(Self);
          NewDesignRoot := InternalStringToComponent(Serialized, NewDesignOwner, LoadInfo);
          if Assigned(ComponentOnCreate) then
          begin
            ReplacedComp := NewDesignOwner.FindComponent(NamesToReplace[I]);
            if ReplacedComp <> nil then
              ComponentOnCreate(ReplacedComp);
          end;
          OpenDesign(NewDesignRoot, NewDesignOwner, FDesignUrl);
        end;
      finally
        FreeAndNil(LoadInfo);
      end;
    end;

    RestoredSelection := TComponentList.Create(false);
    try
      for I := 0 to NamesToReplace.Count - 1 do
      begin
        ReplacedComp := DesignOwner.FindComponent(NamesToReplace[I]);
        if ReplacedComp <> nil then
          RestoredSelection.Add(ReplacedComp);
      end;
      if RestoredSelection.Count > 0 then
        SetSelected(RestoredSelection);
    finally
      FreeAndNil(RestoredSelection);
    end;

    ModifiedOutsideObjectInspector(
      Format('Replace %d component(s) with %s', [NamesToReplace.Count, NewClass.ClassName]), ucHigh);
  finally
    FreeAndNil(NamesToReplace);
  end;
end;

procedure TDesignFrame.ShowReplaceComponentPalette;
var
  Dialog: TForm;
  BottomPanel: TPanel;
  BtnOk, BtnCancel: TButton;
  R: TRegisteredComponent;
begin
  if ControlsTree.SelectionCount = 0 then
  begin
    ErrorBox('Select one or more components first before using Replace Selected With (Ctrl+Shift+R).');
    Exit;
  end;

  FQuickAddReplaceMode := true;
  Dialog := TForm.CreateNew(Self);
  try
    Dialog.Caption := 'Replace Selected Component(s) With... (Ctrl+Shift+R)';
    Dialog.Position := poMainFormCenter;
    Dialog.Width := 520;
    Dialog.Height := 420;
    Dialog.BorderStyle := bsSizeToolWin;

    FQuickAddEdit := TEdit.Create(Dialog);
    FQuickAddEdit.Align := alTop;
    FQuickAddEdit.BorderSpacing.Around := 8;
    FQuickAddEdit.TextHint := 'Search replacement component class (preserves transform, children & common properties)...';
    FQuickAddEdit.OnChange := @QuickAddEditChange;
    FQuickAddEdit.OnKeyDown := @QuickAddEditKeyDown;
    FQuickAddEdit.Parent := Dialog;

    BottomPanel := TPanel.Create(Dialog);
    BottomPanel.Align := alBottom;
    BottomPanel.AutoSize := true;
    BottomPanel.BevelOuter := bvNone;
    BottomPanel.Parent := Dialog;

    BtnCancel := TButton.Create(Dialog);
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := true;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Align := alRight;
    BtnCancel.BorderSpacing.Around := 6;
    BtnCancel.Parent := BottomPanel;

    BtnOk := TButton.Create(Dialog);
    BtnOk.Caption := 'Replace Selected';
    BtnOk.Default := true;
    BtnOk.ModalResult := mrOk;
    BtnOk.AutoSize := true;
    BtnOk.Align := alRight;
    BtnOk.BorderSpacing.Around := 6;
    BtnOk.Parent := BottomPanel;

    FQuickAddList := TListBox.Create(Dialog);
    FQuickAddList.Align := alClient;
    FQuickAddList.BorderSpacing.Left := 8;
    FQuickAddList.BorderSpacing.Right := 8;
    FQuickAddList.OnDblClick := @QuickAddListDblClick;
    FQuickAddList.Parent := Dialog;

    PopulateQuickAddList('');

    if (Dialog.ShowModal = mrOk) and
       (FQuickAddList.ItemIndex >= 0) and
       (FQuickAddList.Items.Objects[FQuickAddList.ItemIndex] is TRegisteredComponent) then
    begin
      R := TRegisteredComponent(FQuickAddList.Items.Objects[FQuickAddList.ItemIndex]);
      ReplaceSelectedComponents(R.ComponentClass, R.OnCreate);
    end;
  finally
    FQuickAddReplaceMode := false;
    FQuickAddEdit := nil;
    FQuickAddList := nil;
    FreeAndNil(Dialog);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemReplaceSelectedClick(Sender: TObject);
begin
  ShowReplaceComponentPalette;
end;

procedure TDesignFrame.ButtonAxisViewClick(Sender: TObject);
var
  Opposite: Boolean;
begin
  if not (Sender is TComponent) then Exit;
  Opposite := ssCtrl in GetKeyShiftState;
  case TComponent(Sender).Tag of
    0: if Opposite then
         ViewportViewAxis(Vector3(0, 1, 0), Vector3(0, 0, 1))
       else
         ViewportViewAxis(Vector3(0, -1, 0), Vector3(0, 0, -1));
    1: if Opposite then
         ViewportViewAxis(Vector3(0, 0, 1), Vector3(0, 1, 0))
       else
         ViewportViewAxis(Vector3(0, 0, -1), Vector3(0, 1, 0));
    2: if Opposite then
         ViewportViewAxis(Vector3(1, 0, 0), Vector3(0, 1, 0))
       else
         ViewportViewAxis(Vector3(-1, 0, 0), Vector3(0, 1, 0));
  end;
end;

procedure TDesignFrame.ViewportMeasureToCursor;
var
  V: TCastleViewport;
  RayOrigin, RayDirection, HitPoint, WorldDelta: TVector3;
  Dist: Single;
begin
  V := CurrentViewport;
  if (V = nil) or (CastleControl = nil) or (CastleControl.Container = nil) or
     (TransformManipulate = nil) or (TransformManipulate.SelectedCount = 0) then
    Exit;

  V.PositionToRay(CastleControl.Container.MousePosition, true, RayOrigin, RayDirection);
  Dist := TransformManipulate.MeasureRayDistanceFromSelected(
    RayOrigin, RayDirection, HitPoint, WorldDelta);
  if Dist >= 0 then
  begin
    FMeasureActive := true;
    FMeasureStartWorld := TransformManipulate.SelectionWorkingCenter;
    FMeasureEndWorld := HitPoint;
    FMeasureDistance := Dist;
    FMeasureDelta := WorldDelta;
    FShowStatisticsToolbar := true;
    if ButtonShowStats <> nil then
      ButtonShowStats.Down := true;
  end;
end;

procedure TDesignFrame.ClearViewportMeasurement;
begin
  FMeasureActive := false;
end;

procedure TDesignFrame.GridDuplicateSelected(const CountX, CountY, CountZ: Integer;
  const Spacing: TVector3);
var
  SelectedList, SourceTransforms, NewSelection: TComponentList;
  SelectedCount, I, IX, IY, IZ, InsertIdx, TotalCopies: Integer;
  Src, ParentT, NewComp: TCastleTransform;
  CompStr: String;
  CellOffset: TVector3;
begin
  if (CountX < 1) or (CountY < 1) or (CountZ < 1) or (DesignOwner = nil) then Exit;
  if (CountX = 1) and (CountY = 1) and (CountZ = 1) then Exit;

  SourceTransforms := TComponentList.Create(false);
  NewSelection := TComponentList.Create(false);
  try
    GetSelected(SelectedList, SelectedCount, false);
    try
      if SelectedList <> nil then
        for I := 0 to SelectedList.Count - 1 do
          if (SelectedList[I] is TCastleTransform) and
             Deletable(SelectedList[I]) and
             (TCastleTransform(SelectedList[I]).Parent <> nil) and
             (not IsComponentDescendantOfSelection(SelectedList[I], SelectedList)) then
            SourceTransforms.Add(SelectedList[I]);
    finally
      FreeAndNil(SelectedList);
    end;

    if (SourceTransforms.Count = 0) and (CurrentTransform <> nil) and
       Deletable(CurrentTransform) and (CurrentTransform.Parent <> nil) then
      SourceTransforms.Add(CurrentTransform);

    if SourceTransforms.Count = 0 then
    begin
      ErrorBox('Select at least one TCastleTransform (that is not the root or a subcomponent) to grid-duplicate.');
      Exit;
    end;

    TotalCopies := 0;
    for I := 0 to SourceTransforms.Count - 1 do
    begin
      Src := TCastleTransform(SourceTransforms[I]);
      ParentT := Src.Parent;
      CompStr := ComponentToString(Src);
      InsertIdx := ParentT.List.IndexOf(Src);

      for IX := 0 to CountX - 1 do
        for IY := 0 to CountY - 1 do
          for IZ := 0 to CountZ - 1 do
          begin
            if (IX = 0) and (IY = 0) and (IZ = 0) then
              Continue; // original already occupies (0,0,0)

            CellOffset := Vector3(
              IX * Spacing.X,
              IY * Spacing.Y,
              IZ * Spacing.Z);

            NewComp := StringToComponent(CompStr, DesignOwner) as TCastleTransform;
            NewComp.Translation := Src.Translation + CellOffset;

            if InsertIdx >= 0 then
            begin
              Inc(InsertIdx);
              ParentT.Insert(InsertIdx, NewComp);
            end else
              ParentT.Add(NewComp);

            NewSelection.Add(NewComp);
            Inc(TotalCopies);
          end;
    end;

    if NewSelection.Count > 0 then
    begin
      UpdateDesign;
      SetSelected(NewSelection);
      ModifiedOutsideObjectInspector(
        Format('Grid duplicate (%dx%dx%d, %d new copies)',
          [CountX, CountY, CountZ, TotalCopies]), ucHigh);
    end;
  finally
    FreeAndNil(NewSelection);
    FreeAndNil(SourceTransforms);
  end;
end;

procedure TDesignFrame.ShowGridDuplicateDialog;
var
  Dialog: TForm;
  LblCountX, LblCountY, LblCountZ, LblSpacingX, LblSpacingY, LblSpacingZ: TLabel;
  SpinCountX, SpinCountY, SpinCountZ: TSpinEdit;
  SpinSpacingX, SpinSpacingY, SpinSpacingZ: TFloatSpinEdit;
  BottomPanel: TPanel;
  BtnOk, BtnCancel: TButton;
  T: TCastleTransform;
  BBox: TBox3D;
  DefStepX, DefStepY, DefStepZ: Single;
begin
  T := CurrentTransform;
  if (T = nil) and ((TransformManipulate = nil) or (TransformManipulate.SelectedCount = 0)) then
  begin
    ErrorBox('Select at least one TCastleTransform component before opening Grid Duplicate.');
    Exit;
  end;

  DefStepX := 2.0;
  DefStepY := 2.0;
  DefStepZ := 2.0;
  if T <> nil then
  begin
    BBox := T.WorldBoundingBox;
    if not BBox.IsEmpty then
    begin
      if BBox.SizeX > 0.01 then DefStepX := BBox.SizeX;
      if BBox.SizeY > 0.01 then DefStepY := BBox.SizeY;
      if BBox.SizeZ > 0.01 then DefStepZ := BBox.SizeZ;
    end;
  end;

  Dialog := TForm.CreateNew(Self);
  try
    Dialog.Caption := '2D / 3D Grid Duplicate (Ctrl+Alt+G)';
    Dialog.Position := poMainFormCenter;
    Dialog.Width := 360;
    Dialog.Height := 300;
    Dialog.BorderStyle := bsDialog;

    LblCountX := TLabel.Create(Dialog);
    LblCountX.Caption := 'Columns X (Count X):';
    LblCountX.Left := 16;
    LblCountX.Top := 18;
    LblCountX.Parent := Dialog;

    SpinCountX := TSpinEdit.Create(Dialog);
    SpinCountX.MinValue := 1;
    SpinCountX.MaxValue := 50;
    SpinCountX.Value := 3;
    SpinCountX.Left := 190;
    SpinCountX.Top := 14;
    SpinCountX.Width := 140;
    SpinCountX.Parent := Dialog;

    LblCountY := TLabel.Create(Dialog);
    LblCountY.Caption := 'Layers Y (Count Y):';
    LblCountY.Left := 16;
    LblCountY.Top := 54;
    LblCountY.Parent := Dialog;

    SpinCountY := TSpinEdit.Create(Dialog);
    SpinCountY.MinValue := 1;
    SpinCountY.MaxValue := 50;
    SpinCountY.Value := 1;
    SpinCountY.Left := 190;
    SpinCountY.Top := 50;
    SpinCountY.Width := 140;
    SpinCountY.Parent := Dialog;

    LblCountZ := TLabel.Create(Dialog);
    LblCountZ.Caption := 'Rows Z (Count Z):';
    LblCountZ.Left := 16;
    LblCountZ.Top := 90;
    LblCountZ.Parent := Dialog;

    SpinCountZ := TSpinEdit.Create(Dialog);
    SpinCountZ.MinValue := 1;
    SpinCountZ.MaxValue := 50;
    SpinCountZ.Value := 3;
    SpinCountZ.Left := 190;
    SpinCountZ.Top := 86;
    SpinCountZ.Width := 140;
    SpinCountZ.Parent := Dialog;

    LblSpacingX := TLabel.Create(Dialog);
    LblSpacingX.Caption := 'Cell Spacing X:';
    LblSpacingX.Left := 16;
    LblSpacingX.Top := 126;
    LblSpacingX.Parent := Dialog;

    SpinSpacingX := TFloatSpinEdit.Create(Dialog);
    SpinSpacingX.DecimalPlaces := 2;
    SpinSpacingX.Increment := 0.5;
    SpinSpacingX.MinValue := -10000;
    SpinSpacingX.MaxValue := 10000;
    SpinSpacingX.Value := DefStepX;
    SpinSpacingX.Left := 190;
    SpinSpacingX.Top := 122;
    SpinSpacingX.Width := 140;
    SpinSpacingX.Parent := Dialog;

    LblSpacingY := TLabel.Create(Dialog);
    LblSpacingY.Caption := 'Cell Spacing Y:';
    LblSpacingY.Left := 16;
    LblSpacingY.Top := 162;
    LblSpacingY.Parent := Dialog;

    SpinSpacingY := TFloatSpinEdit.Create(Dialog);
    SpinSpacingY.DecimalPlaces := 2;
    SpinSpacingY.Increment := 0.5;
    SpinSpacingY.MinValue := -10000;
    SpinSpacingY.MaxValue := 10000;
    SpinSpacingY.Value := DefStepY;
    SpinSpacingY.Left := 190;
    SpinSpacingY.Top := 158;
    SpinSpacingY.Width := 140;
    SpinSpacingY.Parent := Dialog;

    LblSpacingZ := TLabel.Create(Dialog);
    LblSpacingZ.Caption := 'Cell Spacing Z:';
    LblSpacingZ.Left := 16;
    LblSpacingZ.Top := 198;
    LblSpacingZ.Parent := Dialog;

    SpinSpacingZ := TFloatSpinEdit.Create(Dialog);
    SpinSpacingZ.DecimalPlaces := 2;
    SpinSpacingZ.Increment := 0.5;
    SpinSpacingZ.MinValue := -10000;
    SpinSpacingZ.MaxValue := 10000;
    SpinSpacingZ.Value := DefStepZ;
    SpinSpacingZ.Left := 190;
    SpinSpacingZ.Top := 194;
    SpinSpacingZ.Width := 140;
    SpinSpacingZ.Parent := Dialog;

    BottomPanel := TPanel.Create(Dialog);
    BottomPanel.Align := alBottom;
    BottomPanel.AutoSize := true;
    BottomPanel.BevelOuter := bvNone;
    BottomPanel.Parent := Dialog;

    BtnCancel := TButton.Create(Dialog);
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := true;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Align := alRight;
    BtnCancel.BorderSpacing.Around := 6;
    BtnCancel.Parent := BottomPanel;

    BtnOk := TButton.Create(Dialog);
    BtnOk.Caption := 'Grid Duplicate';
    BtnOk.Default := true;
    BtnOk.ModalResult := mrOk;
    BtnOk.AutoSize := true;
    BtnOk.Align := alRight;
    BtnOk.BorderSpacing.Around := 6;
    BtnOk.Parent := BottomPanel;

    if Dialog.ShowModal = mrOk then
      GridDuplicateSelected(
        SpinCountX.Value, SpinCountY.Value, SpinCountZ.Value,
        Vector3(SpinSpacingX.Value, SpinSpacingY.Value, SpinSpacingZ.Value));
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TDesignFrame.ButtonGridDuplicateClick(Sender: TObject);
begin
  ShowGridDuplicateDialog;
end;

procedure TDesignFrame.MenuTreeViewItemGridDuplicateClick(Sender: TObject);
begin
  ShowGridDuplicateDialog;
end;

procedure TDesignFrame.InvertSelection;
var
  SelectedList, NewSelection: TComponentList;
  SelectedCount: Integer;
  TreeNode, ScopeParent: TTreeNode;
  C: TComponent;
begin
  GetSelected(SelectedList, SelectedCount, false);
  NewSelection := TComponentList.Create(false);
  try
    ScopeParent := nil;
    if ControlsTree.SelectionCount > 0 then
      ScopeParent := ControlsTree.Selections[0].Parent;

    if ScopeParent <> nil then
    begin
      TreeNode := ScopeParent.GetFirstChild;
      while TreeNode <> nil do
      begin
        C := SelectedFromNode(TreeNode, false);
        if (C <> nil) and (C <> DesignRoot) and
           ((SelectedList = nil) or (SelectedList.IndexOf(C) = -1)) then
          NewSelection.Add(C);
        TreeNode := TreeNode.GetNextSibling;
      end;
    end else
    begin
      TreeNode := ControlsTree.Items.GetFirstNode;
      while TreeNode <> nil do
      begin
        C := SelectedFromNode(TreeNode, false);
        if (C <> nil) and (C <> DesignRoot) and
           ((SelectedList = nil) or (SelectedList.IndexOf(C) = -1)) then
          NewSelection.Add(C);
        TreeNode := TreeNode.GetNext;
      end;
    end;

    if NewSelection.Count > 0 then
      SetSelected(NewSelection);
  finally
    FreeAndNil(NewSelection);
    FreeAndNil(SelectedList);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemInvertSelectionClick(Sender: TObject);
begin
  InvertSelection;
end;

procedure TDesignFrame.SelectChildren(const Recursive: Boolean);

  procedure CollectChildNodes(const ParentNode: TTreeNode; const List: TComponentList);
  var
    ChildNode: TTreeNode;
    C: TComponent;
  begin
    if ParentNode = nil then Exit;
    ChildNode := ParentNode.GetFirstChild;
    while ChildNode <> nil do
    begin
      C := SelectedFromNode(ChildNode, false);
      if (C <> nil) and (List.IndexOf(C) = -1) then
        List.Add(C);
      if Recursive then
        CollectChildNodes(ChildNode, List);
      ChildNode := ChildNode.GetNextSibling;
    end;
  end;

var
  NewSelection: TComponentList;
  I: Integer;
begin
  if ControlsTree.SelectionCount = 0 then Exit;

  NewSelection := TComponentList.Create(false);
  try
    for I := 0 to ControlsTree.SelectionCount - 1 do
      CollectChildNodes(ControlsTree.Selections[I], NewSelection);

    if NewSelection.Count > 0 then
      SetSelected(NewSelection);
  finally
    FreeAndNil(NewSelection);
  end;
end;

procedure TDesignFrame.MenuTreeViewItemSelectChildrenClick(Sender: TObject);
begin
  SelectChildren(false);
end;

procedure TDesignFrame.MenuTreeViewItemSelectDescendantsClick(Sender: TObject);
begin
  SelectChildren(true);
end;

procedure TDesignFrame.ButtonRotateModeClick(Sender: TObject);
begin
  if InsideToggleModeClick then Exit;
  InsideToggleModeClick := true;
  ChangeMode(moRotate);
  InsideToggleModeClick := false;
end;

procedure TDesignFrame.ButtonScaleModeClick(Sender: TObject);
begin
  if InsideToggleModeClick then Exit;
  InsideToggleModeClick := true;
  ChangeMode(moScale);
  InsideToggleModeClick := false;
end;

procedure TDesignFrame.ButtonSelectModeClick(Sender: TObject);
begin
  if InsideToggleModeClick then Exit;
  InsideToggleModeClick := true;
  ChangeMode(moSelect);
  InsideToggleModeClick := false;
end;

procedure TDesignFrame.ButtonTranslateModeClick(Sender: TObject);
begin
  if InsideToggleModeClick then Exit;
  InsideToggleModeClick := true;
  ChangeMode(moTranslate);
  InsideToggleModeClick := false;
end;

procedure TDesignFrame.ButtonInteractModeClick(Sender: TObject);
begin
  if InsideToggleModeClick then Exit;
  InsideToggleModeClick := true;
  ChangeMode(moInteract);
  InsideToggleModeClick := false;
end;

procedure TDesignFrame.FrameResize(Sender: TObject);

  { Buttons on top panel are resized by LCL to have height equal panel height,
    but this makes them non-square. Fix them to be square.
    Fixes problem observed on Windows. }
  procedure FixButtonSquare(const B: TSpeedButton);
  begin
    if B.Width < B.Height then
      B.Constraints.MinWidth := B.Height;
  end;

begin
  UpdateEditorDataForPropertyEditors;

  FixButtonSquare(ButtonInteractMode);
  FixButtonSquare(ButtonSelectMode);
  FixButtonSquare(ButtonTranslateMode);
  FixButtonSquare(ButtonRotateMode);
  FixButtonSquare(ButtonScaleMode);
  FixButtonSquare(ButtonPlayStop);
  FixButtonSquare(ButtonSimulationPlayStop);
  FixButtonSquare(ButtonSimulationPause);

  { Make ButtonApiReferenceForCurrent square, with size following
    LabelControlSelected.Height.
    Fixes the button being larger than LabelControlSelected,
    which looks bad. }
  ButtonApiReferenceForCurrent.Width := LabelControlSelected.Height;
  ButtonApiReferenceForCurrent.Height := LabelControlSelected.Height;
end;

procedure TDesignFrame.MenuItemAddComponentClick(Sender: TObject);
var
  R: TRegisteredComponent;
begin
  R := TRegisteredComponent(Pointer((Sender as TComponent).Tag));
  AddComponent(R.ComponentClass, R.OnCreate);
end;

procedure TDesignFrame.MenuTreeViewItemCutClick(Sender: TObject);
begin
  CutComponent;
end;

procedure TDesignFrame.MenuTreeViewItemDuplicateLinkedClick(Sender: TObject);
begin
  DuplicateLinkedComponent;
end;

procedure TDesignFrame.MenuTreeViewItemRenameClick(Sender: TObject);
begin
  RenameSelectedItem;
end;

procedure TDesignFrame.MenuTreeViewItemDeleteClick(Sender: TObject);
begin
  DeleteComponent;
end;

procedure TDesignFrame.MenuTreeViewItemCopyClick(Sender: TObject);
begin
  CopyComponent;
end;

procedure TDesignFrame.MenuTreeViewItemPasteClick(Sender: TObject);
begin
  PasteComponent;
end;

procedure TDesignFrame.MenuTreeViewItemSaveSelectedClick(Sender: TObject);
begin
  SaveSelected;
end;

procedure TDesignFrame.MenuTreeViewPopup(Sender: TObject);

  procedure ClearComponentEditorVerbs;
  begin
    { remove all TMenuItemToExecuteVerb }
    while (MenuTreeView.Items.Count > 0) and
          (MenuTreeView.Items[0] is TMenuItemToExecuteVerb) do
      MenuTreeView.Items[0].Free;

    { remove separator }
    if (MenuTreeView.Items.Count > 0) and
       (MenuTreeView.Items[0].Caption = '-') then
      MenuTreeView.Items[0].Free;
  end;

  procedure AddComponentEditorVerbs(const C: TComponent);
  var
    E: TBaseComponentEditor;
    I: Integer;
    MenuItem: TMenuItemToExecuteVerb;
    MenuItemSeparator: TMenuItem;
    InsertedVerbs: Cardinal;
  begin
    E := GetComponentEditor(C, FComponentEditorDesigner);
    if E <> nil then
    begin
      InsertedVerbs := 0;
      for I := 0 to E.GetVerbCount - 1 do
      begin
        { Ignore "Create default event" that we couldn't handle now,
          as our designer cannot initialize Code Tools to insert the event in code. }
        if E.GetVerb(I) = oisCreateDefaultEvent then
          Continue;
        MenuItem := TMenuItemToExecuteVerb.Create(Self);
        MenuItem.Caption := E.GetVerb(I);
        MenuItem.VerbIndex := I;
        MenuItem.ComponentEditor := E;
        MenuItem.ComponentToExecute := C;
        MenuTreeView.Items.Insert(InsertedVerbs, MenuItem);
        Inc(InsertedVerbs);
      end;

      { add separator if needed }
      if InsertedVerbs <> 0 then
      begin
        MenuItemSeparator := TMenuItem.Create(Self);
        MenuItemSeparator.Caption := '-';
        MenuTreeView.Items.Insert(InsertedVerbs, MenuItemSeparator);
      end;
    end;
  end;

var
  Sel: TComponent;
  CanAddUserInterface, CanAddTransform, CanAddBehavior: Boolean;
begin
  Sel := SelectedComponent;

  ClearComponentEditorVerbs;
  if Sel <> nil then
    AddComponentEditorVerbs(Sel);

  MenuTreeViewItemRename.Enabled := RenameSelectedPossible;
  MenuTreeViewItemDuplicate.Enabled := ControlsTree.SelectionCount > 0;
  MenuTreeViewItemDuplicateLinked.Enabled := Sel <> nil;
  if MenuTreeViewItemToggleVisibility <> nil then
    MenuTreeViewItemToggleVisibility.Enabled := ControlsTree.SelectionCount > 0;
  if MenuTreeViewItemIsolateSelected <> nil then
    MenuTreeViewItemIsolateSelected.Enabled := ControlsTree.SelectionCount > 0;
  if MenuTreeViewItemShowAllHidden <> nil then
    MenuTreeViewItemShowAllHidden.Enabled := ControlsTree.Items.Count > 0;
  if MenuTreeViewItemToggleLock <> nil then
    MenuTreeViewItemToggleLock.Enabled := ControlsTree.SelectionCount > 0;
  if MenuTreeViewItemUnlockAll <> nil then
    MenuTreeViewItemUnlockAll.Enabled := (FLockedComponents <> nil) and (FLockedComponents.Count > 0);
  if MenuTreeViewItemGroupSelected <> nil then
    MenuTreeViewItemGroupSelected.Enabled := (TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 0);
  if MenuTreeViewItemUngroupSelected <> nil then
    MenuTreeViewItemUngroupSelected.Enabled := (TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 0);
  if MenuTreeViewItemArrayDuplicate <> nil then
    MenuTreeViewItemArrayDuplicate.Enabled := (CurrentTransform <> nil) or ((TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 0));
  if MenuTreeViewItemRadialDuplicate <> nil then
    MenuTreeViewItemRadialDuplicate.Enabled := (CurrentTransform <> nil) or ((TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 0));
  if MenuTreeViewItemGridDuplicate <> nil then
    MenuTreeViewItemGridDuplicate.Enabled := (CurrentTransform <> nil) or ((TransformManipulate <> nil) and (TransformManipulate.SelectedCount > 0));
  if MenuTreeViewItemReplaceSelected <> nil then
    MenuTreeViewItemReplaceSelected.Enabled := ControlsTree.SelectionCount > 0;
  if MenuTreeViewItemSelectSameClass <> nil then
    MenuTreeViewItemSelectSameClass.Enabled := Sel <> nil;
  if MenuTreeViewItemInvertSelection <> nil then
    MenuTreeViewItemInvertSelection.Enabled := ControlsTree.Items.Count > 1;
  if MenuTreeViewItemSelectChildren <> nil then
    MenuTreeViewItemSelectChildren.Enabled := ControlsTree.SelectionCount > 0;
  if MenuTreeViewItemSelectDescendants <> nil then
    MenuTreeViewItemSelectDescendants.Enabled := ControlsTree.SelectionCount > 0;
  if MenuTreeViewItemExpandAll <> nil then
    MenuTreeViewItemExpandAll.Enabled := ControlsTree.Items.Count > 0;
  if MenuTreeViewItemCollapseAll <> nil then
    MenuTreeViewItemCollapseAll.Enabled := ControlsTree.Items.Count > 0;
  MenuTreeViewItemCut.Enabled := Sel <> nil;
  MenuTreeViewItemCopy.Enabled := Sel <> nil;
  MenuTreeViewItemSaveSelected.Enabled := Sel <> nil;
  MenuTreeViewItemDelete.Enabled := ControlsTree.SelectionCount > 0; // delete can handle multiple objects

  CanAddUserInterface := false;
  CanAddTransform := false;
  CanAddBehavior := false;

  if (Sel is TCastleUserInterface) or ((Sel = nil) and (DesignRoot is TCastleUserInterface)) then
  begin
    CanAddUserInterface := true;
  end else
  if (Sel is TCastleTransform) or ((Sel = nil) and (DesignRoot is TCastleTransform)) then
  begin
    CanAddTransform := true;
    CanAddBehavior := true;
  end else
  if Sel is TCastleBehavior then
  begin
    CanAddBehavior := true;
  end;
  // on other components, you can add only NonVisualComponent

  MenuTreeViewItemAddUserInterface.SetEnabledVisible(CanAddUserInterface);
  MenuTreeViewItemAddTransform.SetEnabledVisible(CanAddTransform);
  MenuTreeViewItemAddBehavior.SetEnabledVisible(CanAddBehavior);

  // at most one of MenuItemChangeClassXxx is enabled
  MenuItemChangeClassUserInterface.SetEnabledVisible(false);
  MenuItemChangeClassTransform.SetEnabledVisible(false);
  MenuItemChangeClassBehavior.SetEnabledVisible(false);
  MenuItemChangeClassNonVisual.SetEnabledVisible(false);
  if Sel is TCastleUserInterface then
    MenuItemChangeClassUserInterface.SetEnabledVisible(true)
  else
  if Sel is TCastleTransform then
    MenuItemChangeClassTransform.SetEnabledVisible(true)
  else
  if Sel is TCastleBehavior then
    MenuItemChangeClassBehavior.SetEnabledVisible(true)
  else
  if Sel <> nil then
    MenuItemChangeClassNonVisual.SetEnabledVisible(true);

  MenuTreeView.PopupComponent := ControlsTree; // I'm not sure what it means, something like menu owner?
end;

procedure TDesignFrame.MenuTreeViewItemDuplicateClick(Sender: TObject);
begin
  DuplicateComponent;
end;

procedure TDesignFrame.ViewportSetup2D;
var
  V: TCastleViewport;
begin
  V := CurrentViewport;
  if V = nil then Exit;

  V.Setup2D;
  ModifiedOutsideObjectInspector('2D Camera And Projection At Runtime: ' + V.Name, ucHigh);
end;

procedure TDesignFrame.ViewportToggleProjection;
var
  V: TCastleViewport;
begin
  V := CurrentViewport;
  if V = nil then Exit;

  if V.InternalCamera.ProjectionType = ptPerspective then
    V.InternalCamera.ProjectionType := ptOrthographic
  else
    V.InternalCamera.ProjectionType := ptPerspective;
end;

function TDesignFrame.CameraToSynchronize(const V: TCastleViewport): TCastleCamera;
begin
  { Prefer to use camera from CameraPreview, as this is most natural in UI,
    because user sees CameraPreview.
    Do this even when SelectedTransform is also (maybe different) camera. }
  if (CameraPreview <> nil) and
     (CameraPreview.SelectedCamera <> nil) and
     (CameraPreview.SelectedCamera.World = V.Items) then
    Result := CameraPreview.SelectedCamera
  else
  if (SelectedTransform is TCastleCamera) and
     (TCastleCamera(SelectedTransform).World = V.Items) then
    Result := TCastleCamera(SelectedTransform)
  else
    Result := V.Camera;
end;

procedure TDesignFrame.CameraSynchronize(const Source, Target: TCastleCamera; const MakeUndo: Boolean);
var
  BeginPos, BeginDir, BeginUp, EndPos, EndDir, EndUp: TVector3;
begin
  Target.ProjectionType := Source.ProjectionType;
  Target.Perspective.FieldOfView     := Source.Perspective.FieldOfView;
  Target.Perspective.FieldOfViewAxis := Source.Perspective.FieldOfViewAxis;
  Target.Orthographic.Origin  := Source.Orthographic.Origin;
  Target.Orthographic.Width   := Source.Orthographic.Width;
  Target.Orthographic.Height  := Source.Orthographic.Height;

  Target.GetWorldView(BeginPos, BeginDir, BeginUp);
  Source.GetWorldView(EndPos, EndDir, EndUp);

  { Instead of using FixCamera2D, just explicitly force Z values to be unchanged. }
  if (Source.ProjectionType = ptOrthographic) and
     TVector3.Equals(EndDir, Vector3(0, 0, -1)) and
     TVector3.Equals(EndUp, Vector3(0, 1, 0)) then
  begin
    EndPos.Z := BeginPos.Z;
  end;

  if MakeUndo then
  begin
    { To record undo for Target camera pos/dir/up, we do a little trick.
      As we want to animate using AnimateTo, but we want to record undo state
      with already final pos/dir/up, so we *temporarily* adjust Target instantly
      to Source pos/dir/up. }
    Target.SetWorldView(EndPos, EndDir, EndUp);
    ModifiedOutsideObjectInspector('Align Camera To View: ' + Target.Name, ucHigh);
    // restore Target to begin positions, to animate to it
    Target.SetWorldView(BeginPos, BeginDir, BeginUp);
  end;

  Target.AnimateTo(EndPos, EndDir, EndUp, CameraTransitionTime);
end;

procedure TDesignFrame.ViewportAlignViewToCamera;
var
  V: TCastleViewport;
  C: TCastleCamera;
begin
  V := CurrentViewport;
  if V = nil then Exit;

  C := CameraToSynchronize(V);
  if C <> nil then
    CameraSynchronize(C, V.InternalCamera, false);
end;

procedure TDesignFrame.ViewportAlignCameraToView;
var
  V: TCastleViewport;
  C: TCastleCamera;
begin
  V := CurrentViewport;
  if V = nil then Exit;

  C := CameraToSynchronize(V);
  if C <> nil then
    CameraSynchronize(V.InternalCamera, C, true);
end;

procedure TDesignFrame.UpdateColliders(T: TCastleTransform);
var
  BehList: TCastleBehaviorList;
  V: TCastleViewport;
  B: TCastleBehavior;
begin
  if T = nil then
  begin
    V := CurrentViewport;
    if V = nil then Exit;
    T := V.Items;
  end;

  BehList := T.FindAllBehaviors(TCastleCollider);
  try
    for B in BehList do
      if FShowColliders then
        TCastleCollider(B).InternalDesigningBegin
      else
        TCastleCollider(B).InternalDesigningEnd;
  finally FreeAndNil(BehList) end;
end;

{
function TDesignFrame.SelectionSave: Classes.TList;
var
  I: Integer;
begin
  Result := Classes.TList.Create;
  Result.Count := ControlsTree.SelectionCount;
  for I := 0 to Result.Count - 1 do
    Result[I] := ControlsTree.Selections[I];
end;

procedure TDesignFrame.SelectionRestoreAndFree(var Selection: Classes.TList);
begin
  ControlsTree.Select(Selection);
  FreeAndNil(Selection);
end;
}

procedure TDesignFrame.SetParent(AParent: TWinControl);
{$ifdef LCLwin32}
var
  H: Integer;
  InspectorType: TInspectorType;
{$endif}
begin
  inherited SetParent(AParent);
  {$ifdef LCLwin32}
  // fix height of rows of object inspector
  if AParent <> nil then
  begin
    H := Canvas.TextHeight('Wg') + 4;
    for InspectorType in TInspectorType do
      Inspector[InspectorType].DefaultItemHeight := H;
  end;
  {$endif}
end;

procedure TDesignFrame.UpdateAnchors(const UI: TCastleUserInterface;
  const AllowToHideParentAnchorsFrame: Boolean);
begin
  SelfAnchorsFrame.HorizontalAnchor := UI.HorizontalAnchorSelf;
  SelfAnchorsFrame.VerticalAnchor := UI.VerticalAnchorSelf;
  ParentAnchorsFrame.HorizontalAnchor := UI.HorizontalAnchorParent;
  ParentAnchorsFrame.VerticalAnchor := UI.VerticalAnchorParent;

  if AllowToHideParentAnchorsFrame then
  begin
    CheckParentSelfAnchorsEqual.Checked :=
      (UI.HorizontalAnchorSelf = UI.HorizontalAnchorParent) and
      (UI.VerticalAnchorSelf = UI.VerticalAnchorParent);
    { The above will automatically call CheckParentSelfAnchorsEqualChanged,
      if Checked just changed. }
  end;
end;

procedure TDesignFrame.ChangeMode(const NewMode: TMode);

  { For dark theme: change button colors, and also make them depending on
    active/inactive/disabled states.
    Note: the disabled state is never used now in practice,
    as these buttons are never disabled (for now). }
  procedure AdjustToolbarButtonsTheme;

    { Change Button.Images to use an image suitable for dark theme. }
    procedure UpdateButtonForDarkTheme(const Button: TSpeedButton);
    begin
      if not Button.Enabled then
        Button.Images := Icons.ToolbarIconsDarkDisabled
      else
      if Button.Down then
        Button.Images := Icons.ToolbarIconsDarkActive
      else
        Button.Images := Icons.ToolbarIconsDarkInactive;
    end;

  begin
    if UseIconsAndColorsForDarkTheme then
    begin
      UpdateButtonForDarkTheme(ButtonInteractMode);
      UpdateButtonForDarkTheme(ButtonSelectMode);
      UpdateButtonForDarkTheme(ButtonTranslateMode);
      UpdateButtonForDarkTheme(ButtonRotateMode);
      UpdateButtonForDarkTheme(ButtonScaleMode);
    end;
  end;

begin
  Mode := NewMode;

  ButtonInteractMode.Down := Mode = moInteract;
  ButtonSelectMode.Down := Mode = moSelect;
  ButtonTranslateMode.Down := Mode = moTranslate;
  ButtonRotateMode.Down := Mode = moRotate;
  ButtonScaleMode.Down := Mode = moScale;

  AdjustToolbarButtonsTheme;

  case Mode of
    moTranslate: TransformManipulate.Mode := mmTranslate;
    moRotate: TransformManipulate.Mode := mmRotate;
    moScale: TransformManipulate.Mode := mmScale;
    else TransformManipulate.Mode := mmSelect;
  end;
end;

procedure TDesignFrame.ModifiedOutsideObjectInspector(const UndoComment: String;
  const UndoCommentPriority: TUndoCommentPriority; const UndoOnRelease: Boolean = false);
var
  InspectorType: TInspectorType;
begin
  // TODO: this moves UI scrollbar up,
  // TODO: this is not optimized
  // (PropertyGridModified does some unnecessary things if we only changed size)

  for InspectorType in TInspectorType do
    Inspector[InspectorType].RefreshPropertyValues;
  // do not call PropertyGridModified if nothing selected, e.g. after delete operation
  if ControlsTree.SelectionCount <> 0 then
    PropertyGridModified(nil);

  MarkModified;

  if UndoOnRelease then
    UndoSystem.ScheduleRecordUndoOnRelease := true
  else
    RecordUndo(UndoComment, UndoCommentPriority); //it will overwrite Undo recorded in PropertyGridModified with a better comment
end;

procedure TDesignFrame.NewDesign(const ComponentClass: TComponentClass;
  const ComponentOnCreate: TNotifyEvent);
var
  NewRoot: TComponent;
  NewDesignOwner: TComponent;
begin
  NewDesignOwner := TComponent.Create(Self);

  NewRoot := ComponentClass.Create(NewDesignOwner);
  if Assigned(ComponentOnCreate) then
    ComponentOnCreate(NewRoot);
  NewRoot.Name := ProposeComponentName(ComponentClass, NewDesignOwner);

  { In these special cases, set FullSize to true,
    since this is almost certainly what user wants when creating a new UI
    that has this component class as root. }
  if (ComponentClass = TCastleUserInterface) or
     (ComponentClass = TCastleRectangleControl) then
    (NewRoot as TCastleUserInterface).FullSize := true;

  UndoSystem.ClearUndoHistory;

  OpenDesign(NewRoot, NewDesignOwner, '');

  RecordUndo('Start new design', High(TUndoCommentPriority)); // This Undo comment is never seen
end;

procedure TDesignFrame.ReleaseAllKeysAndMouse;
begin
  CastleControl.ReleaseAllKeysAndMouse;
end;

procedure TDesignFrame.FocusDesign;
begin
  { Note that we ignore this call when CastleControl is disabled or invisible.
    Otherwise SetFocus would raise an error: understandably, we cannot focus
    disabled or invisible control.
    Ignoring it here prevents errors at "Escape" key or Undo when the design
    is non-visual (like sounds.castle-component). }
  if CastleControl.Enabled and CastleControl.Visible then
    CastleControl.SetFocus;
end;

procedure TDesignFrame.FindToggle;
begin
  if FindActive and (not EditFindInHierarchy.Focused) then
  begin
    EditFindInHierarchy.SetFocus;
    EditFindInHierarchy.SelectAll;
    Exit;
  end;
  FindActive := not FindActive;
  SetEnabledVisible(EditFindInHierarchy, FindActive);
  if FindActive then
  begin
    EditFindInHierarchy.Text := ''; // clear edit when showing it
    // Note: SetFocus must be done after making it enabled, otherwise exception is raised
    EditFindInHierarchy.SetFocus;
  end;
  ControlsTree.Invalidate;
end;

procedure TDesignFrame.EditFindInHierarchyChange(Sender: TObject);
var
  TreeNode: TTreeNode;
  C: TComponent;
begin
  ControlsTree.Invalidate;
  if FindActive and (Trim(EditFindInHierarchy.Text) <> '') then
  begin
    TreeNode := ControlsTree.Items.GetFirstNode;
    while TreeNode <> nil do
    begin
      C := SelectedFromNode(TreeNode, false);
      if (C <> nil) and NodeMatchesHierarchyFilter(C) then
      begin
        SelectedComponent := C;
        Exit;
      end;
      TreeNode := TreeNode.GetNext;
    end;

    Beep; // nothing found
  end;
end;

procedure TDesignFrame.FindNext;
var
  TreeNode: TTreeNode;
  Sel, C: TComponent;
  SeenSelection: Boolean;
begin
  if FindActive and (Trim(EditFindInHierarchy.Text) <> '') then
  begin
    if SelectedComponent = nil then
    begin
      { try to find first match }
      EditFindInHierarchyChange(nil)
    end else
    begin
      Sel := GetSelectedComponent(false);

      // first pass: go to selected component, find first match after it
      SeenSelection := false;

      TreeNode := ControlsTree.Items.GetFirstNode;
      while TreeNode <> nil do
      begin
        C := SelectedFromNode(TreeNode, false);

        if SeenSelection and
           (C <> nil) and
           NodeMatchesHierarchyFilter(C) then
        begin
          SelectedComponent := C;
          Exit;
        end;
        if C = Sel then
          SeenSelection := true;

        TreeNode := TreeNode.GetNext;
      end;

      // no match found after selected component, search from the beginning

      if not SeenSelection then
      begin
        WritelnWarning('Not found SelectedComponent %s among tree nodes, something is wrong', [Sel.Name]);
        Exit;
      end;

      TreeNode := ControlsTree.Items.GetFirstNode;
      while TreeNode <> nil do
      begin
        C := SelectedFromNode(TreeNode, false);

        if C = Sel then
        begin
          // we reached selection again, so no next match found
          Exit;
        end;

        if (C <> nil) and NodeMatchesHierarchyFilter(C) then
        begin
          SelectedComponent := C;
          Exit;
        end;

        TreeNode := TreeNode.GetNext;
      end;
    end;
  end;
end;

procedure TDesignFrame.ExportToModel;
var
  RootNode: TX3DRootNode;
  SaveUrl: String;
  UrlProcessing: TUrlProcessing;
begin
  if CurrentViewport = nil then
  begin
    ErrorBox('Select a viewport to export first.' + NL + NL +
      'Do it by selecting any TCastleViewport or a child of it in the hierarchy. Or just hover your mouse over it.');
    Exit;
  end;

  if ExportToModelDialog.Execute then
  begin
    SaveUrl := ExportToModelDialog.Url;
    UrlProcessing := suChangeCastleDataToRelative;
    { TODO: get UrlProcessing as parameter;

      TODO: FormProject should allow user to choose UrlProcessing --
      e.g. by selecting a menu item (radio), like

        Data ->
          Export to Model URL Behavior ->
            None
            Change castle-data:/ To Relative // default
            Embed Resources using data URI (make self-contained X3D file)
            Copy All Resources to exported-output Subdirectory
    }
    RootNode := CurrentViewport.InternalBuildNode(SaveUrl, UrlProcessing);
    try
      SaveNode(RootNode, SaveUrl);
    finally FreeAndNil(RootNode) end;
  end;
end;

initialization
  ColorHoverAndSelected := Yellow;

  { Enable using our property edits e.g. for TCastleScene.URL }
  CastlePropEdits.Register;
  CastleEditorPropEdits.Register;

  { Inside CGE editor,
    - CastleApplicationMode is never appRunning,
    - so CastleDesignMode is always true. }
  InternalCastleApplicationMode := appDesign;

  { Inside CGE editor, file monitor is always enabled. }
  FileMonitor.MakePossiblyEnabled;
  FileMonitor.Enabled := true;
end.
