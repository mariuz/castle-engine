# Castle Game Engine — Editor Modernization Roadmap & Unreal Engine 5.5 Comparison

This document compares the **Castle Game Engine (CGE 7.0-alpha.3)** editor (`tools/castle-editor`) and runtime scene/UI manipulation architecture against **Unreal Engine 5.5 (Current Release)**, identifies the highest-impact workflow gaps, and tracks the phased engineering roadmap across all 19 phases.

For complete user workflows, mathematical foundations, Pascal API reference, architecture diagrams, and keyboard shortcuts, see the companion reference guide:
- **[`docs/EDITOR_MODERNIZATION_GUIDE.md`](docs/EDITOR_MODERNIZATION_GUIDE.md)**

---

## 1. Architectural Comparison: Castle Game Engine vs. Unreal Engine 5.5

| Domain | Unreal Engine 5.5 (Current Release) | Castle Game Engine (Baseline State) | Modernization Status & Implementation |
| :--- | :--- | :--- | :--- |
| **1. 3D Viewport Gizmos, Marquee Selection & Snapping** | • Translate / Rotate / Scale / Universal gizmos (`W`/`E`/`R`)<br>• **Viewport Marquee / Box Selection** (Left-Drag rectangle to batch-select 3D/2D objects)<br>• **Interactive Surface & Vertex Snapping (`V` Key)** to snap selection onto hovered mesh surfaces or triangle vertices<br>• **Configurable 3D Snapping**: Grid snap (1, 5, 10, 50, 100), Rotation snap (5°, 15°, 45°, 90°), Scale snap (0.1, 0.25, 0.5)<br>• **World vs. Local Coordinate Space** toggle (`Ctrl+~`)<br>• **Alt-Drag Gizmo Duplication** & **Linear / Step Array Duplication (`Ctrl+Shift+D`)**<br>• **Multi-Actor Transform Manipulation** around primary pivot or selection center<br>• **Snap to Floor (`End` key)**, **Snap + Align to Surface Normal (`Alt+End`)**, & **Snap Origin to Grid (`Ctrl+End`)**<br>• **Multi-Actor Align, Even Distribution, Flush Bounding-Box Stack, Mirror, 90° Step Rotate & Set-Dressing Randomize** | • Select / Translate / Rotate / Scale gizmos (`TCastleTransformManipulate`)<br>• `SpinEditSnap` **only snapped 2D UI controls** — zero 3D translation, rotation, or scale snapping<br>• **Local space only** (gizmo was parented directly to `FMainSelected` with no rotation compensation)<br>• **Single-transform limit**: selecting >1 `TCastleTransform` hid the gizmo (`TODO` in `castletransformmanipulate.pas`)<br>• No Viewport Marquee selection, Surface/Vertex snapping (`V`), Array Duplication (`Ctrl+Shift+D`), Alt-drag duplication, Snap-to-Floor (`End`), Surface Normal Alignment (`Alt+End`), Snap-to-Grid (`Ctrl+End`), Pivot Mode toggle, Align/Distribute/Stack, Mirror, or Transform Randomizer | **Completed (Phases 1, 8, 11, 14, 16, 17 & 18)**:<br>• Added `TranslateSnap`, `RotateSnap`, `ScaleSnap` with remainder preservation on `TCastleTransformManipulate`<br>• Added `TManipulateCoordSpace = (csLocal, csWorld)` and `CoordSpace` property + toolbar button + `Ctrl+~` shortcut<br>• Added **Viewport Marquee / Box Selection** (`dmMarquee` in `Select Mode` or `Ctrl+Alt` + Left-Drag in any mode, with `Shift` additive selection)<br>• Added `SnapSelectedToRay` on `TCastleTransformManipulate` and **`V` / `Shift+V` / `Alt+V` / `Shift+Alt+V`** viewport shortcuts for instant cursor raycast Surface & Vertex Snapping<br>• Added **Linear / Step Array Duplication (`Ctrl+Shift+D` / `Array Dup...`)** creating `N` copies with cumulative translation & yaw offsets<br>• Added `OnTransformModifyBegin` & `GizmoTransformModifyBegin` for seamless **Alt-drag 3D gizmo duplication**<br>• Added `TManipulatePivotMode = (pmPrimarySelected, pmSelectionCenter)` + `Pivot: Primary / Center` toolbar button<br>• Enabled multi-selection 3D manipulation (`SelectedCount >= 1`) with ancestor deduplication<br>• Added `SnapToFloor(AlignToNormal)` (`End` / `Alt+End`), `SnapSelectedToGrid` (`Ctrl+End`), `AlignSelected` (`Align X/Y/Z`), `DistributeSelected` (`Dist X/Y/Z`), `StackSelected` (`Stack X/Y/Z`), `MirrorSelected` (`Mirror X/Y/Z`), `RotateSelected90` (`Rot 90° Y`), and `RandomizeSelected` (`Randomize`) |
| **2. Scene Outliner (Hierarchy Tree)** | • Live instant filter search bar at top of Outliner (`Name`, `+Type`)<br>• **Actor Selection Locking (`L` Key / Lock icon)** preventing accidental viewport picking while keeping actors visible<br>• Quick eye-icon visibility toggle (`H` key), **Isolate Selection (`Shift+H`)**, **Show All Hidden (`Alt+H`)**, & hidden indicators<br>• **Group Selection (`Ctrl+G`)** & **Ungroup Selection (`Ctrl+Shift+G`)**<br>• Multi-selection delete, duplicate (`Ctrl+D`), reparenting<br>• Select All of Same Class, Expand/Collapse Subtree<br>• Double-click actor node to frame camera (`F`) | • `ControlsTree` with hidden `Ctrl+F` (`EditFindInHierarchy`) sequential name-only search<br>• No class filter or visual match highlighting<br>• Duplicate (`Ctrl+D`) restricted to single selection<br>• Visibility toggled only via Object Inspector (`Exists` checkbox); no Selection Lock (`L`), Isolate (`Shift+H`), Show All (`Alt+H`), Group (`Ctrl+G`), or Ungroup (`Ctrl+Shift+G`) | **Completed (Phases 2, 10, 12, 15 & 19)**:<br>• Always-visible live Hierarchy filter box supporting `Name`, `ClassName`, and `+ClassName` queries with live yellow match highlighting<br>• Added **Hierarchy Selection Locking (`L` toggle, `Alt+L` Unlock All)** with `[Locked]` tree badge and full viewport click/marquee/gizmo protection<br>• `H` shortcut to toggle `Exists`, `Shift+H` (`IsolateSelected`) to solo selected hierarchy branches, and `Alt+H` (`ShowAllHidden`) to unhide all nodes, plus `[Hidden]` tree badge<br>• `Ctrl+G` (`GroupSelectedTransforms`) and `Ctrl+Shift+G` (`UngroupSelectedTransforms`) preserving world transforms<br>• Multi-selection `Ctrl+D` duplication with ancestor deduplication<br>• `Select All of Same Class`, `Expand Subtree`, and `Collapse Subtree` context menu actions<br>• Double-click hierarchy node to frame 3D camera |
| **3. Details Panel (Object Inspector)** | • Live property search bar filtering properties across categories<br>• One-click Reset Property to Default arrow (`Revert`)<br>• Copy / Paste / Reset Transform (`Translation`, `Rotation`, `Scale`)<br>• Multi-object editing & transform clipboard | • 4 tabs (`Basic`, `Layout`, `Events`, `All`) wrapping Lazarus `TOIPropertyGrid`<br>• Modified properties shown in bold (`IsPropertyModified`), but no live text search filter or one-click Reset Property button<br>• Only single-object `Reset` transform button; no Copy/Paste Transform | **Completed (Phases 3 & 10)**:<br>• Live `Search Properties...` filter box (`EditPropertyFilter`) and `Reset Prop` (`ButtonResetProperty`) button above Object Inspector tabs<br>• `Copy Transform`, `Paste Transform`, and multi-selection `Reset` Transform buttons in `PanelLayoutTransform` |
| **4. Viewport View Modes, Camera Bookmarks, Speed Controls & Visualizers** | • Lit, Unlit (`Alt+3`), Wireframe (`Alt+2`), Lit Wireframe<br>• **Camera Bookmarks** (`Ctrl+0..9` save, `0..9` recall)<br>• **Dynamic Camera Speed** (`[` / `]` keys + HUD readout)<br>• **Snap Actor to View** (place lights/actors at camera)<br>• Collision / Physics Mesh & Bounding Volume overlays<br>• FPS / Frame Time / Draw Call / Actor Bounds stats overlay | • 3 modes in menu only: `Normal` (`rmFull`), `Wireframe`, `SolidWireframe`<br>• No Camera Bookmarks (`Ctrl+0..9` / `0..9`) or `[` / `]` camera fly speed hotkeys<br>• Align to View only worked for `TCastleCamera`<br>• Physics collider visualization & Statistics overlay buried in menus | **Completed (Phases 4, 9 & 13)**:<br>• Added `InternalForceUnlit` in CGE renderer & `View: Lit / Unlit / Wire / SolidWire` cycling toolbar button (`Ctrl+T`)<br>• Added 10 Viewport Camera Bookmarks (`Ctrl+0..9` save, `0..9` smooth animated recall)<br>• Added `[` / `]` dynamic camera fly speed scaling (`AdjustCameraSpeed`) and `Cam Speed` readout in the Stats HUD<br>• Added `Move to View` (`ViewportAlignTransformToView`) snapping any selected `TCastleTransform` to the viewport camera<br>• Added one-click `Stats` and `Colliders` toolbar toggles + enriched HUD |
| **5. Content Browser / Drawer** | • Instant search bar filtering assets by name or extension<br>• Asset type filter pills (All, 3D/Meshes, Blueprints/Designs, Textures, Audio, Code)<br>• Drag-and-drop from Content Browser directly onto 3D viewport surface with grid snapping | • `TCastleShellTreeView` + `TCastleShellListView` + `TViewFileFrame` preview<br>• No search bar or asset type filter pills in the Files panel<br>• Drag-and-drop into 3D viewport did not snap to 3D grid | **Completed (Phase 5)**:<br>• Added `PanelFilesTop` filter bar in `TProjectForm` with `EditFileFilter` and 6 asset category pills (`All`, `3D/Scenes`, `Designs`, `Images`, `Audio`, `Code`) combining category masks with substring queries<br>• Upgraded `CastleControlDragDrop` to snap dropped 3D transforms to `TranslateSnap` when 3D snapping is active |
| **6. Quick-Add & Command Palette** | • "Quickly Add to the Project" button & searchable palette<br>• Instant keyboard-driven actor/component instantiation | • Deep nested menus (`Add Transform -> ...`, `Add User Interface -> ...`) | **Completed (Phase 6)**:<br>• Added `+ Add` toolbar button (`ButtonQuickAdd`) and `Ctrl+P` viewport shortcut opening `ShowQuickAddPalette`, a searchable modal palette filtering all registered `TCastleTransform`, `TCastleUserInterface`, `TCastleBehavior`, and `TCastleComponent` classes |
| **7. Play-In-Editor (PIE) & Simulation** | • Simulate-In-Editor (Physics running while camera is free)<br>• Pause & Single-Step physics frame<br>• "Keep Simulation Changes" (`K`) saving simulated transforms back to level design | • Internal Physics Simulation (`ActionSimulationPlayStop`, `ActionSimulationPauseUnpause`), but stopping simulation always discarded simulated positions and no Single-Step existed | **Completed (Phase 7)**:<br>• Added `Step` (`ButtonSimulationStep` / `SimulationSingleStep`) to advance paused physics by exactly 1 frame ($1/60\text{ s}$)<br>• Added `Keep Sim` (`ButtonKeepSimulation` / `KeepSimulationChanges`) to stop simulation and persist simulated `Translation`, `Rotation`, and `Scale` onto the design as a single Undo-able step |

---

## 2. Prioritized Modernization TODO List (All 19 Phases Completed)

### Phase 1: Unreal-Grade 3D Gizmo Manipulation, Snapping, Coordinate Spaces & Multi-Selection
- [x] **1.1. 3D Translation, Rotation & Scale Snapping (`TCastleTransformManipulate`)**
  - Added `TranslateSnap: Single` (grid unit snap, `0` = disabled) with remainder tracking (`LastPick`) so dragging across grid increments feels responsive and exact.
  - Added `RotateSnap: Single` (angle snap in radians, `0` = disabled) with remainder tracking (`LastPickAngle`) during circular gizmo drags.
  - Added `ScaleSnap: Single` (scale increment snap, `0` = disabled) with remainder tracking.
  - Added programmatic helpers `TranslateSelected`, `RotateSelected`, and `ScaleSelected` that honor snapping and coordinate space settings.
- [x] **1.2. World vs. Local Coordinate Space Toggle (`TManipulateCoordSpace`)**
  - Introduced `TManipulateCoordSpace = (csLocal, csWorld)` and `CoordSpace` property on `TCastleTransformManipulate`.
  - In `csWorld` mode, `TGizmoScene.LocalRender` and `GetEffectiveRay` compensate for the target transform's world rotation so gizmo handles align with World $(X, Y, Z)$ axes and drag rays project onto World axes.
- [x] **1.3. Multi-Selection Transform Manipulation**
  - Lifted the single-selection restriction in `TCastleTransformManipulate` (`SelectedCount >= 1`).
  - Displays the gizmo at the primary selected transform (`Selected[0]`) whenever one or more transforms are selected, and applies translation, rotation, and scale deltas across all selected transforms while skipping any selected transform whose ancestor is also selected (`IsDescendantOfAnySelected`).
  - Preserves multi-selection in `TDesignFrame.DesignerLayer.Press` when clicking a gizmo or an already-selected transform.
- [x] **1.4. Snap to Floor (`SnapToFloor` / `End` Key)**
  - Implemented `TCastleTransformManipulate.SnapToFloor`: raycasts downward along the world gravity vector (`-World.GravityUp`) from each selected transform's bounding box bottom (or translation origin if empty) against the rest of the scene, snapping the transform cleanly onto the supporting surface.
- [x] **1.5. Editor UI, Shortcuts & Unit Tests (`TDesignFrame`, `TTestCastleTransformManipulate`)**
  - Added `ButtonCoordSpace` (`Local` / `World`), `SpinEditSnap3D`, and `ButtonSnapToFloor` (`Snap to Floor (End)`) to `castle-editor`.
  - Added unit tests in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 2: Scene Outliner (Hierarchy) Modernization
- [x] **2.1. Live Incremental Search & Class Filter (`EditFindInHierarchy`)**
  - Made `EditFindInHierarchy` permanently accessible at the top of the Hierarchy panel with support for matching component `Name`, `ClassName`, or explicit `+ClassName` prefix (e.g., `+Scene`, `+Light`, `+Button`).
  - Added live visual highlighting (`clYellow`) in `ControlsTreeAdvancedCustomDrawItem` for all hierarchy nodes matching the active filter query.
- [x] **2.2. Quick Visibility (`Exists`) Toggle (`H` Key) & Multi-Selection Duplicate (`Ctrl+D`)**
  - Added `ToggleSelectedVisibility` bound to the `H` key (both in the 3D/2D Viewport and in the Hierarchy tree) and `Toggle Visibility (Exists) (H)` in the Hierarchy context menu.
  - Added `' [Hidden]'` indicator badge and dimmed text (`clGray`) in `ControlsTreeAdvancedCustomDrawItem` when a `TCastleTransform` or `TCastleUserInterface` has `Exists = false`.
  - Upgraded `DuplicateComponent` (`Ctrl+D`) to duplicate all selected components in a multi-selection while skipping descendants of already-selected ancestors.
- [x] **2.3. Double-Click Hierarchy Node to Focus Camera**
  - Bound `ControlsTree.OnDblClick` (`ControlsTreeDblClick`) to frame the active 3D viewport camera on the double-clicked `TCastleTransform` (`ViewportViewSelected`).

### Phase 3: Details Panel (Object Inspector) Enhancements
- [x] **3.1. Live Property Filter Search Box (`EditPropertyFilter`)**
  - Added `EditPropertyFilter` (`Search Properties...`) at the top of the Object Inspector panel in `TDesignFrame`, filtering `PropertyGrid` rows live across `Basic`, `Layout`, `Events`, and `All` tabs via `InspectorFilter`.
- [x] **3.2. Copy / Paste / Multi-Reset Transform Quick Actions**
  - Added `Copy Transform` (`ButtonCopyTransform`) and `Paste Transform` (`ButtonPasteTransform`) buttons alongside `Reset` (`ButtonResetTransformation`) in `PanelLayoutTransform`.
  - Upgraded `Reset` and `Paste` Transform actions to apply across all selected transforms when multiple `TCastleTransform` objects are selected.

### Phase 4: Viewport Rendering Modes & Real-Time Stats Overlay
- [x] **4.1. Unlit Rendering Mode (`InternalForceUnlit`) & Toolbar Cycling (`ButtonViewMode`)**
  - Added `InternalForceUnlit: Boolean` in `src/base/castlerenderoptions_globals.inc` and wired it into `castleinternalrenderer_materials.inc` and `castleinternalrenderer_meshrenderer.inc`.
  - Added `ButtonViewMode` (`View: Lit` / `View: Unlit` / `View: Wire` / `View: SolidWire`) on the top viewport toolbar and integrated `Unlit` into `ActionViewportRenderNextExecute` (`Ctrl+T`).
- [x] **4.2. Real-Time Viewport Statistics HUD (`ButtonShowStats` & Enhanced HUD)**
  - Added `Stats` toggle button (`ButtonShowStats`) on the top toolbar.
  - Enhanced `TDesignerLayer.Render.StatisticsToString` to display FPS, active Render Mode, Coordinate Space, selection count, Viewport rendering statistics, and the active transform's World Position and World Bounding Box dimensions.
- [x] **4.3. Physics Collider Visualization Toggle (`ButtonShowColliders`)**
  - Added `Colliders` toggle button (`ButtonShowColliders`) on the top toolbar synchronized with `ShowColliders`.

### Phase 5: Content Browser Search, Asset Filter Pills & Viewport Drag-and-Drop
- [x] **5.1. Content Browser Search & Asset Type Filter Pills (`PanelFilesTop`)**
  - Added `EditFileFilter` and 6 category filter pills (`All`, `3D/Scenes`, `Designs`, `Images`, `Audio`, `Code`) to the Files panel (`TProjectForm.CreateShellViews`), dynamically combining extension masks and substring queries in `UpdateShellListMask`.
- [x] **5.2. 3D Grid-Snapped Viewport Drag-and-Drop**
  - Updated `TDesignFrame.CastleControlDragDrop` to snap dropped `TCastleTransform` horizontal coordinates (`DropPos.X`, `DropPos.Z`) to `TransformManipulate.TranslateSnap` when 3D snapping is enabled.

### Phase 6: Quick-Add Component Palette (`Ctrl+P` / `+ Add`)
- [x] **6.1. Fuzzy/Substring-Searchable Component Palette (`ShowQuickAddPalette`)**
  - Added `+ Add` toolbar button (`ButtonQuickAdd`) and `Ctrl+P` viewport shortcut launching a keyboard-driven modal palette that filters all context-valid `RegisteredComponents` (`[Transform]`, `[UI]`, `[Behavior]`, `[NonVisual]`) and instantiates the chosen component on `Enter` or double-click.

### Phase 7: Enhanced In-Editor Physics Simulation Controls
- [x] **7.1. Single-Step Physics (`Step`) & Keep Simulation Transform Changes (`Keep Sim`)**
  - Added `ButtonSimulationStep` (`SimulationSingleStep`) to advance paused physics simulations by a single $1/60\text{ s}$ frame.
  - Added `ButtonKeepSimulation` (`KeepSimulationChanges`) to capture simulated `Translation`, `Rotation`, and `Scale` across all selectable `TCastleTransform` instances, stop the simulation cleanly, apply the settled transforms to the design, and record an Undo step.

### Phase 8: Multi-Object Alignment, Even Distribution, Snap-to-Grid (`Ctrl+End`), and Selection Center Pivot (`TCastleTransformManipulate`)
- [x] **8.1. Selection Center Orbital Pivot Mode (`TManipulatePivotMode`)**
  - Added `TManipulatePivotMode = (pmPrimarySelected, pmSelectionCenter)`, `PivotMode` property, and `SelectionWorkingCenter: TVector3` on `TCastleTransformManipulate`.
  - When `PivotMode = pmSelectionCenter`, rotating multiple selected transforms orbits their world positions around `SelectionWorkingCenter` in addition to rotating their orientations.
  - Added `ButtonPivotMode` (`Pivot: Primary` / `Pivot: Center`) on the top viewport toolbar.
- [x] **8.2. Multi-Object Alignment & Even Distribution (`AlignSelected`, `DistributeSelected`)**
  - Added `TAlignTarget = (atPrimary, atMin, atCenter, atMax)` and `AlignSelected(Axis, Target)` on `TCastleTransformManipulate`, plus `Align X`, `Align Y`, and `Align Z` buttons in `PanelLayoutTransform`.
  - Added `DistributeSelected(Axis)` on `TCastleTransformManipulate` to space 3+ selected transforms evenly between the minimum and maximum coordinates along `Axis`, plus `Dist X`, `Dist Y`, and `Dist Z` buttons in `PanelLayoutTransform`.
- [x] **8.3. Absolute Snap-to-Grid (`SnapSelectedToGrid` / `Ctrl+End`)**
  - Added `SnapSelectedToGrid: Boolean` on `TCastleTransformManipulate` and wired `Ctrl+End` and `ButtonSnapToGrid` (`Snap to Grid (Ctrl+End)`) in `TDesignFrame`.
  - Added automated unit tests `TestAlignAndDistributeSelected` and `TestSnapSelectedToGridAndPivotCenter` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 9: Viewport Camera Bookmarks (`Ctrl+0..9` / `0..9`) & Move Selected Transform to View
- [x] **9.1. 10 Instant Camera Bookmark Slots (`SaveCameraBookmark`, `RecallCameraBookmark`)**
  - Added `FCameraBookmarks[0..9]` in `TDesignFrame`: pressing `Ctrl+0..9` in the viewport saves the current `InternalCamera` world view `(Pos, Dir, Up)` into slot `0..9`; pressing `0..9` smoothly animates the viewport camera back to that saved viewpoint (`AnimateTo`).
- [x] **9.2. Move Any Selected Transform to Camera View (`ViewportAlignTransformToView`)**
  - Added `Move to View` (`ButtonMoveTransformToView` / `ViewportAlignTransformToView`) in `PanelLayoutTransform` to snap any selected `TCastleTransform` (such as a spot/directional light, prop, camera, or spawn point) to the current viewport camera's position and orientation via `SetWorldView`.

### Phase 10: Hierarchy & Object Inspector Productivity Tools
- [x] **10.1. Select All of Same Class & Expand/Collapse Subtree**
  - Added `Select All of Same Class` (`SelectAllOfSameClass`), `Expand Subtree` (`ExpandSelectedSubtree`), and `Collapse Subtree` (`CollapseSelectedSubtree`) to the Hierarchy context menu (`MenuTreeView`).
- [x] **10.2. One-Click Reset Property to Default (`ResetSelectedPropertyToDefault`)**
  - Added `Reset Prop` (`ButtonResetProperty`) next to `EditPropertyFilter` at the top of the Object Inspector to revert the active property row to its default value (`GetDefaultValue` / `Revert`) and record an Undo step.

### Phase 11: Surface Normal Alignment (`Alt+End`), Mirroring (`MirrorSelected`), 90° Step Rotation (`RotateSelected90`), and Set-Dressing Randomization (`RandomizeSelected`)
- [x] **11.1. Surface Normal Alignment on Snap-to-Floor (`SnapToFloor(AlignToNormal: Boolean)` / `Alt+End`)**
  - Upgraded `TCastleTransformManipulate.SnapToFloor` to accept `AlignToNormal: Boolean = false` using `T.World.WorldRay`. When `AlignToNormal = true`, extracts the hit triangle's world normal (or hit transform's local `+Y` axis in world space) and rotates each selected transform's local `+Y` up vector to align with the surface normal before snapping onto the surface.
  - Bound to `Alt+End` (and `Shift+End`) in the viewport and `ButtonSnapToFloorNormal` (`Snap + Normal (Alt+End)`) in `PanelLayoutTransform`.
- [x] **11.2. Physics-Safe Multi-Object Mirroring (`MirrorSelected`) & 90° Step Rotation (`RotateSelected90`)**
  - Implemented `TCastleTransformManipulate.MirrorSelected(Axis)`: reflects positions across the active pivot (or `0` for single selection) and reflects axis-angle orientations across the mirror plane while keeping `Scale` positive so physics colliders remain valid.
  - Implemented `TCastleTransformManipulate.RotateSelected90(Axis, Clockwise)`: rotates selected transforms by an exact $\pm 90^\circ$ ($\pm \pi/2\text{ rad}$) step around `Axis`, bypassing `RotateSnap`.
  - Wired `Mirror X`, `Mirror Y`, `Mirror Z`, and `Rot 90° Y` buttons in `PanelLayoutTransform`.
- [x] **11.3. Set-Dressing Transform Randomizer (`RandomizeSelected`)**
  - Implemented `TCastleTransformManipulate.RandomizeSelected(MaxYawRad, ScaleMin, ScaleMax, MaxPositionJitter)` and wired `ButtonRandomizeTransform` (`Randomize`) in `PanelLayoutTransform` for rapid foliage/prop variation.
  - Added automated unit tests `TestSnapToFloorAlignToNormal` and `TestMirrorRotate90AndRandomizeSelected` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 12: Scene Outliner Selection Isolation (`Shift+H` / `Alt+H`) & Group Selection Under New Transform (`Ctrl+G`)
- [x] **12.1. Isolate Selected (`Shift+H`) & Show All Hidden (`Alt+H`)**
  - Implemented `TDesignFrame.IsolateSelected`: hides (`Exists := false`) all unselected sibling/unrelated components while keeping selected components, their ancestor chain, and their descendants visible.
  - Implemented `TDesignFrame.ShowAllHidden`: restores `Exists := true` across all hidden `TCastleTransform` and `TCastleUserInterface` instances in the design.
  - Bound to `Shift+H` and `Alt+H` in both the Viewport and Hierarchy Tree, plus `Isolate Selected (Shift+H)` and `Show All Hidden (Alt+H)` in `MenuTreeView`.
- [x] **12.2. Group Selected Transforms (`Ctrl+G` / `GroupSelectedTransforms`)**
  - Implemented `TDesignFrame.GroupSelectedTransforms`: creates a new parent `TCastleTransform` (`Group1`, etc.) centered at `TransformManipulate.SelectionWorkingCenter` and reparents all top-level selected `TCastleTransform` nodes into the group while preserving their world positions.
  - Bound to `Ctrl+G` in both the Viewport and Hierarchy Tree, plus `Group Selected Under New Transform (Ctrl+G)` in `MenuTreeView`.

### Phase 13: Dynamic Viewport Camera Speed Controls (`[` / `]` Keys) & Camera Speed HUD Readout
- [x] **13.1. Dynamic Camera Fly Speed Scaling (`AdjustCameraSpeed` / `[` & `]` Keys)**
  - Bound `[` (`keyLeftBracket`) and `]` (`keyRightBracket`) in `TDesignerLayer.Press` to scale `CurrentViewport.InternalDesignNavigation`'s `MoveSpeed` down/up by $1.5\times$ (clamped to $[0.05, 5000]$).
  - Added live `Cam Speed: X.XX` readout to the Viewport Statistics HUD (`TDesignerLayer.Render.StatisticsToString`).

### Phase 14: Alt-Drag 3D Gizmo Duplication (`OnTransformModifyBegin`) & Bounding-Box Flush Stacking (`StackSelected`)
- [x] **14.1. Alt-Drag 3D Gizmo Duplication (`OnTransformModifyBegin` / `GizmoTransformModifyBegin`)**
  - Added `OnTransformModifyBegin: TNotifyEvent` on `TGizmoScene` and `TCastleTransformManipulate`, fired at the start of any 3D gizmo drag operation (`PointingDevicePress`).
  - Implemented `TDesignFrame.GizmoTransformModifyBegin`: when `Alt` (`mkAlt`) is held at the start of a gizmo drag in design mode, clones all top-level selected `TCastleTransform` objects in-place (leaving the stationary duplicates at the drag start position while the gizmo smoothly drags the selected objects) and records an `'Alt-Drag Duplicate ...'` Undo step on release.
  - Added `Ctrl+~` (`keyBackQuote` with `mkCtrl`) viewport shortcut for `ToggleCoordSpace` (Unreal Engine 5.5 standard Local/World toggle shortcut).
- [x] **14.2. Bounding-Box Flush Edge-to-Edge Stacking (`StackSelected` / `Stack X/Y/Z`)**
  - Implemented `TCastleTransformManipulate.StackSelected(Axis, Spacing)`: sorts 2+ selected transforms along `Axis` and places each subsequent transform's minimum world AABB face flush against the previous transform's maximum world AABB face (plus `Spacing`), enabling zero-gap modular wall/floor/tile assembly.
  - Added `Stack X`, `Stack Y`, and `Stack Z` buttons (`ButtonStackX`, `ButtonStackY`, `ButtonStackZ`) in `PanelLayoutTransform`.
  - Added automated unit test `TestStackSelected` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 15: Ungroup Selected Transforms (`Ctrl+Shift+G` / `UngroupSelectedTransforms`)
- [x] **15.1. Ungroup Selected Transform Groups Preserving World Transforms (`UngroupSelectedTransforms`)**
  - Implemented `TDesignFrame.UngroupSelectedTransforms`: unpacks all selectable child `TCastleTransform` objects of each selected group into the group's parent while preserving each child's world position and orientation (`GetWorldView` / `SetWorldView`), automatically removes empty plain `TCastleTransform` group containers, selects the unpacked children, and records a single Undo step.
  - Bound to `Ctrl+Shift+G` in both the 3D Viewport and Hierarchy Tree, plus `Ungroup Selected Transform(s) (Ctrl+Shift+G)` in `MenuTreeView`.

### Phase 16: Viewport Marquee / Box Selection (`dmMarquee` / `SelectComponentsInMarquee`)
- [x] **16.1. 2D & 3D Viewport Marquee Rectangle Selection**
  - Added `dmMarquee` to `TUiDraggingMode` and implemented `TDesignFrame.SelectComponentsInMarquee(MarqueeRect, Additive)`.
  - Activated by Left-Dragging in `Select` mode (`moSelect`, once drag distance $\ge 4\text{ px}$) or by holding `Ctrl+Alt` + Left-Drag in any manipulation mode.
  - Renders a translucent blue selection rectangle with a crisp border in `TDesignerLayer.Render`.
  - In 3D viewports, projects every selectable, visible, unlocked `TCastleTransform` origin (and world bounding-box center) in front of the camera (`CamDir.DotProduct(WorldPos - CamPos) > 0`) into container screen coordinates via `V.LocalToContainerPosition(V.PositionFromWorld(WorldPos))` and selects all transforms inside the marquee rectangle.
  - In 2D UI designs, selects all selectable, visible, unlocked `TCastleUserInterface` controls whose `RenderRect` intersects the marquee rectangle.
  - Holding `Shift` during release performs additive multi-selection.

### Phase 17: Interactive Surface & Vertex Snapping (`SnapSelectedToRay` / `V` Key)
- [x] **17.1. Raycast Surface & Nearest-Vertex Snapping (`TCastleTransformManipulate.SnapSelectedToRay`)**
  - Implemented `TCastleTransformManipulate.SnapSelectedToRay(RayOrigin, RayDirection, SnapToNearestVertex, AlignToNormal): Boolean`.
  - Temporarily sets `Pickable := false` on gizmo scenes and all selected transforms, casts `FMainSelected.World.WorldRay(RayOrigin, NormDir)`, and snaps either to the exact ray-surface intersection point (`RayHit.First.Point`) or—when `SnapToNearestVertex = true` and `RayHit.First.Triangle <> nil`—to the closest world-space vertex of the hit triangle (`RayHit.First.Item.LocalToWorld(Tri.Data[0..2])`).
  - Preserves multi-selection relative offsets around the active pivot (`pmPrimarySelected` or `pmSelectionCenter`) and optionally aligns local `+Y` to the surface normal (`AlignToNormal = true`).
  - Bound in `TDesignerLayer.Press` (`ViewportSnapToCursor`) to **`V`** (surface snap to cursor), **`Shift+V`** (nearest vertex snap to cursor), **`Alt+V`** (surface + normal alignment), and **`Shift+Alt+V`** (nearest vertex + normal alignment).
  - Added automated unit test `TestSnapSelectedToRaySurfaceAndVertex` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 18: Linear / Step Array Duplication Tool (`ArrayDuplicateSelected` / `Ctrl+Shift+D`)
- [x] **18.1. Modal & Programmatic Step-and-Repeat Array Duplication**
  - Implemented `TDesignFrame.ArrayDuplicateSelected(Count, StepOffset, StepYawDeg)` and `ShowArrayDuplicateDialog`.
  - Clones all top-level selected `TCastleTransform` or `TCastleUserInterface` components `Count` times ($1\dots 100$), applying cumulative offset $i \times \text{StepOffset}$ and cumulative Y-axis rotation $i \times \text{StepYawDeg}$ in a single Undo step (`'Array Duplicate (N copies)'`).
  - Bound to **`Ctrl+Shift+D`** in both the Viewport and Hierarchy Tree, **`Array Dup...`** (`ButtonArrayDuplicate`) in `PanelLayoutTransform`, and **`Array Duplicate... (Ctrl+Shift+D)`** in `MenuTreeView`.

### Phase 19: Hierarchy Selection Locking (`L` Key / `Alt+L` / `[Locked]` Badge)
- [x] **19.1. Viewport Selection Lock & Ancestor Lock Propagation**
  - Added `FLockedComponents: TComponentList` (`FreeObjects = false`), `IsComponentLocked(C)` (with automatic ancestor lock propagation), `ToggleSelectedLock` (**`L`** key), and `UnlockAll` (**`Alt+L`**).
  - Locked components remain visible in the viewport but are skipped by viewport hover/click picking (`HoverUserInterface`, `HoverComponent`), marquee box selection (`SelectComponentsInMarquee`), and gizmo drags (`UpdateSelectedControl` detaches gizmos when a locked component is selected in the Hierarchy tree).
  - Added `' [Locked]'` indicator badge in `ControlsTreeAdvancedCustomDrawItem` and `Toggle Selection Lock (L)` / `Unlock All (Alt+L)` in `MenuTreeView`.

### Phase 20: Radial / Circular Array Duplication (`RadialDuplicateSelected` / `Ctrl+Alt+D`)
- [x] **20.1. Circular & Arc Array Duplication with Optional Inward/Outward Orientation**
  - Implemented `TDesignFrame.RadialDuplicateSelected(Count, Radius, TotalAngleDeg, OrientToCenter)` and `ShowRadialDuplicateDialog`.
  - Places `Count` copies ($1\dots 360$) of all selected `TCastleTransform` objects around a circle of radius `Radius` in the XZ plane across `TotalAngleDeg` (using $\Delta\theta = 360^\circ / (\text{Count} + 1)$ for full $360^\circ$ circles so the last copy does not overlap the original, or $\Delta\theta = \text{TotalAngleDeg} / \text{Count}$ for partial arcs), optionally rotating each copy's yaw around $+Y$ by $\theta_i$ (`OrientToCenter = true`).
  - Bound to **`Ctrl+Alt+D`** in both the Viewport and Hierarchy Tree, **`Radial Dup...`** (`ButtonRadialDuplicate`) in `PanelLayoutTransform`, and **`Radial / Circular Duplicate... (Ctrl+Alt+D)`** in `MenuTreeView`.

### Phase 21: Multi-Component Replace With Another Class (`ReplaceSelectedComponents` / `Ctrl+Shift+R`)
- [x] **21.1. Searchable Multi-Selection Component Class Replacement**
  - Implemented `TDesignFrame.ReplaceSelectedComponents(NewClass, ComponentOnCreate)` and `ShowReplaceComponentPalette` (reusing the searchable Quick-Add filter UI with `FQuickAddReplaceMode = true`).
  - Replaces one or multiple selected components (`TCastleTransform`, `TCastleUserInterface`, `TCastleBehavior`, or non-visual) with `NewClass` via `TInternalComponentLoadInfo` (`ChangeClassName` / `ChangeClassClass`), preserving component names, child hierarchies, behaviors, `Translation`/`Rotation`/`Scale`/anchors, and cross-component references in a single Undo step.
  - Bound to **`Ctrl+Shift+R`** in both the Viewport and Hierarchy Tree and **`Replace Selected With... (Ctrl+Shift+R)`** in `MenuTreeView`.

### Phase 22: Selection-Aware Standard Axis Viewport Camera Views (`Numpad 1/3/7/5` & `Alt+1/3/7/5`)
- [x] **22.1. Selection-Aware `ViewportViewAxis` & Blender/Unreal Axis View Shortcuts**
  - Upgraded `TDesignFrame.ViewportViewAxis(Dir, Up)` to orbit around `TransformManipulate.SelectionWorkingCenter` when objects are selected (falling back to `V.Items.BoundingBox.Center` or `TVector3.Zero` when the scene is empty).
  - Bound **`Numpad 7`** / **`Alt+7`** (Top `-Y`, `Ctrl` for Bottom `+Y`), **`Numpad 1`** / **`Alt+1`** (Front `-Z`, `Ctrl` for Back `+Z`), **`Numpad 3`** / **`Alt+3`** (Right `-X`, `Ctrl` for Left `+X`), and **`Numpad 5`** / **`Alt+5`** (`ViewportToggleProjection` Perspective / Orthographic toggle) in `TDesignerLayer.Press`.
  - Added **`View: Top (-Y)`**, **`View: Front (-Z)`**, and **`View: Right (-X)`** buttons (`Ctrl`-click for opposite axis) in `PanelLayoutTransform`.

### Phase 23: 3D Viewport Ruler & Distance Measurement Tool (`M` Key / Multi-Select Ruler HUD)
- [x] **23.1. Selection-to-Selection & Selection-to-Cursor Ray Distance Measurement**
  - Implemented `TCastleTransformManipulate.MeasureSelectedDistance(out WorldDelta): Single` (world distance and $\Delta X, \Delta Y, \Delta Z$ between `Selected[0]` and `Selected[1]`) and `MeasureRayDistanceFromSelected(RayOrigin, RayDirection, out HitWorldPoint, WorldDelta): Single` (raycast distance from `SelectionWorkingCenter` to the surface point under the cursor, ignoring gizmos and selected objects).
  - Bound **`M`** (`ViewportMeasureToCursor`) and **`Alt+M`** (`ClearViewportMeasurement`) in the 3D Viewport, rendering 2D screen-space start/end crosshairs and displaying live `Ruler (Sel[0]->Sel[1])` and `Measured Ray (M)` readouts in the Viewport Statistics HUD.
  - Added automated unit test `TestMeasureSelectedAndRayDistance` in `tests/code/testcases/testcastletransformmanipulate.pas`.
