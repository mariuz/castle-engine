# Castle Game Engine — Editor Modernization Roadmap & Unreal Engine 5.5 Comparison

This document compares the **Castle Game Engine (CGE 7.0-alpha.3)** editor (`tools/castle-editor`) and runtime scene/UI manipulation architecture against **Unreal Engine 5.5 (Current Release)**, identifies the highest-impact workflow gaps, and tracks the phased engineering roadmap across all 27 phases.

For complete user workflows, mathematical foundations, Pascal API reference, architecture diagrams, and keyboard shortcuts, see the companion reference guide:
- **[`docs/EDITOR_MODERNIZATION_GUIDE.md`](docs/EDITOR_MODERNIZATION_GUIDE.md)**

---

## 1. Architectural Comparison: Castle Game Engine vs. Unreal Engine 5.5

| Domain | Unreal Engine 5.5 (Current Release) | Castle Game Engine (Baseline State) | Modernization Status & Implementation |
| :--- | :--- | :--- | :--- |
| **1. 3D Viewport Gizmos, Marquee Selection & Snapping** | • Translate / Rotate / Scale / Universal gizmos (`W`/`E`/`R`)<br>• **Viewport Marquee / Box Selection** (Left-Drag rectangle to batch-select 3D/2D objects)<br>• **Interactive Surface & Vertex Snapping (`V` Key)** to snap selection onto hovered mesh surfaces or triangle vertices<br>• **Configurable 3D Snapping**: Grid snap (1, 5, 10, 50, 100), Rotation snap (5°, 15°, 45°, 90°), Scale snap (0.1, 0.25, 0.5)<br>• **World vs. Local Coordinate Space** toggle (`Ctrl+~`)<br>• **Alt-Drag Gizmo Duplication**, **Linear Array (`Ctrl+Shift+D`)**, **Radial Array (`Ctrl+Alt+D`)**, & **2D/3D Grid Array (`Ctrl+Alt+G`)**<br>• **Multi-Actor Transform Manipulation** around primary pivot or selection center<br>• **Snap to Floor (`End` key)**, **Snap + Align to Surface Normal (`Alt+End`)**, **Project Along Camera View (`Ctrl+Shift+End`)**, & **Snap Pos/Rot/Scale to Grid (`Ctrl+End`)**<br>• **Multi-Actor Align, Center/Equal-Gap Distribution, Flush Bounding-Box Stack, Mirror, 90° Step Rotate, Set-Dressing Randomize & 3D Ruler (`M`)** | • Select / Translate / Rotate / Scale gizmos (`TCastleTransformManipulate`)<br>• `SpinEditSnap` **only snapped 2D UI controls** — zero 3D translation, rotation, or scale snapping<br>• **Local space only** (gizmo was parented directly to `FMainSelected` with no rotation compensation)<br>• **Single-transform limit**: selecting >1 `TCastleTransform` hid the gizmo (`TODO` in `castletransformmanipulate.pas`)<br>• No Viewport Marquee selection, Surface/Vertex snapping (`V`), Array/Radial/Grid Duplication, Alt-drag duplication, Snap-to-Floor (`End`), Surface Normal Alignment (`Alt+End`), Project Along View (`Ctrl+Shift+End`), Snap-to-Grid (`Ctrl+End`), Pivot Mode toggle, Align/Distribute/Stack, Mirror, Transform Randomizer, or 3D Ruler (`M`) | **Completed (Phases 1, 8, 11, 14, 16, 17, 18, 20, 23, 24, 25 & 27)**:<br>• Added `TranslateSnap`, `RotateSnap`, `ScaleSnap` with remainder preservation on `TCastleTransformManipulate`<br>• Added `TManipulateCoordSpace = (csLocal, csWorld)` and `CoordSpace` property + toolbar button + `Ctrl+~` shortcut<br>• Added **Viewport Marquee / Box Selection** (`dmMarquee` in `Select Mode` or `Ctrl+Alt` + Left-Drag in any mode, with `Shift` additive selection)<br>• Added `SnapSelectedToRay` on `TCastleTransformManipulate` and **`V` / `Shift+V` / `Alt+V` / `Shift+Alt+V`** viewport shortcuts for instant cursor raycast Surface & Vertex Snapping<br>• Added **Linear Array (`Ctrl+Shift+D`)**, **Radial Array (`Ctrl+Alt+D`)**, and **2D/3D Grid Array (`Ctrl+Alt+G`)** duplication tools<br>• Added `OnTransformModifyBegin` & `GizmoTransformModifyBegin` for seamless **Alt-drag 3D gizmo duplication**<br>• Added `TManipulatePivotMode = (pmPrimarySelected, pmSelectionCenter)` + `Pivot: Primary / Center` toolbar button<br>• Enabled multi-selection 3D manipulation (`SelectedCount >= 1`) with ancestor deduplication<br>• Added `SnapToFloor(AlignToNormal)` (`End` / `Alt+End`), `ProjectSelectedAlongDirection` (`Ctrl+Shift+End` / `Project Along View`), `SnapSelectedToGrid` + `SnapSelectedRotationAndScaleToGrid` (`Ctrl+End`), `AlignSelected` (`Align X/Y/Z`), `DistributeSelected` & `DistributeSelectedGaps` (`Dist X/Y/Z` & `Shift+Dist X/Y/Z`), `StackSelected` (`Stack X/Y/Z`), `MirrorSelected` (`Mirror X/Y/Z`), `RotateSelected90` (`Rot 90° Y`), `RandomizeSelected` (`Randomize`), and 3D Ruler (`M` / `MeasureSelectedDistance` / `MeasureRayDistanceFromSelected`) |
| **2. Scene Outliner (Hierarchy Tree)** | • Live instant filter search bar at top of Outliner (`Name`, `+Type`)<br>• **Actor Selection Locking (`L` Key / Lock icon)** preventing accidental viewport picking while keeping actors visible<br>• Quick eye-icon visibility toggle (`H` key), **Isolate Selection (`Shift+H`)**, **Show All Hidden (`Alt+H`)**, & hidden indicators<br>• **Group Selection (`Ctrl+G`)** & **Ungroup Selection (`Ctrl+Shift+G`)**<br>• **Replace Selected Actors With... (`Ctrl+Shift+R`)**<br>• **Invert Selection (`Ctrl+I`)**, **Select Direct Children (`Ctrl+]`)**, **Select All Descendants (`Ctrl+Shift+]`)**, & **Select All of Same Class**<br>• Double-click actor node to frame camera (`F`) | • `ControlsTree` with hidden `Ctrl+F` (`EditFindInHierarchy`) sequential name-only search<br>• No class filter or visual match highlighting<br>• Duplicate (`Ctrl+D`) restricted to single selection<br>• Visibility toggled only via Object Inspector (`Exists` checkbox); no Selection Lock (`L`), Isolate (`Shift+H`), Show All (`Alt+H`), Group (`Ctrl+G`), Ungroup (`Ctrl+Shift+G`), Multi-Replace (`Ctrl+Shift+R`), Invert Selection (`Ctrl+I`), or Select Children (`Ctrl+]`) | **Completed (Phases 2, 10, 12, 15, 19, 21 & 26)**:<br>• Always-visible live Hierarchy filter box supporting `Name`, `ClassName`, and `+ClassName` queries with live yellow match highlighting<br>• Added **Hierarchy Selection Locking (`L` toggle, `Alt+L` Unlock All)** with `[Locked]` tree badge and full viewport click/marquee/gizmo protection<br>• `H` shortcut to toggle `Exists`, `Shift+H` (`IsolateSelected`) to solo selected hierarchy branches, and `Alt+H` (`ShowAllHidden`) to unhide all nodes, plus `[Hidden]` tree badge<br>• `Ctrl+G` (`GroupSelectedTransforms`) and `Ctrl+Shift+G` (`UngroupSelectedTransforms`) preserving world transforms<br>• `Ctrl+Shift+R` (`ReplaceSelectedComponents` / `ShowReplaceComponentPalette`) replacing multiple selected components while preserving transforms & children<br>• `Ctrl+I` (`InvertSelection`), `Ctrl+]` (`SelectChildren(false)`), `Ctrl+Shift+]` (`SelectChildren(true)`), `Select All of Same Class`, `Expand Subtree`, and `Collapse Subtree`<br>• Double-click hierarchy node to frame 3D camera |
| **3. Details Panel (Object Inspector)** | • Live property search bar filtering properties across categories<br>• One-click Reset Property to Default arrow (`Revert`)<br>• Copy / Paste / Reset Transform (`Translation`, `Rotation`, `Scale`)<br>• Multi-object editing & transform clipboard | • 4 tabs (`Basic`, `Layout`, `Events`, `All`) wrapping Lazarus `TOIPropertyGrid`<br>• Modified properties shown in bold (`IsPropertyModified`), but no live text search filter or one-click Reset Property button<br>• Only single-object `Reset` transform button; no Copy/Paste Transform | **Completed (Phases 3 & 10)**:<br>• Live `Search Properties...` filter box (`EditPropertyFilter`) and `Reset Prop` (`ButtonResetProperty`) button above Object Inspector tabs<br>• `Copy Transform`, `Paste Transform`, and multi-selection `Reset` Transform buttons in `PanelLayoutTransform` |
| **4. Viewport View Modes, Camera Bookmarks, Speed Controls & Visualizers** | • Lit, Unlit (`Alt+3`), Wireframe (`Alt+2`), Lit Wireframe<br>• **Selection-Aware Standard Axis Views (`Numpad 1/3/7/5` / `Alt+1/3/7/5`)**<br>• **Camera Bookmarks** (`Ctrl+0..9` save, `0..9` recall)<br>• **Dynamic Camera Speed** (`[` / `]` keys + HUD readout)<br>• **Snap Actor to View** (place lights/actors at camera)<br>• Collision / Physics Mesh & Bounding Volume overlays<br>• FPS / Frame Time / Draw Call / Actor Bounds / 3D Ruler stats overlay | • 3 modes in menu only: `Normal` (`rmFull`), `Wireframe`, `SolidWireframe`<br>• `ViewportViewAxis` always centered on `TVector3.Zero` instead of selection<br>• No Camera Bookmarks (`Ctrl+0..9` / `0..9`) or `[` / `]` camera fly speed hotkeys<br>• Align to View only worked for `TCastleCamera`<br>• Physics collider visualization & Statistics overlay buried in menus | **Completed (Phases 4, 9, 13, 22 & 23)**:<br>• Added `InternalForceUnlit` in CGE renderer & `View: Lit / Unlit / Wire / SolidWire` cycling toolbar button (`Ctrl+T`)<br>• Upgraded `ViewportViewAxis` to orbit around `SelectionWorkingCenter` + added `Numpad 1/3/7/5` & `Alt+1/3/7/5` shortcuts and `View: Top / Front / Right` buttons<br>• Added 10 Viewport Camera Bookmarks (`Ctrl+0..9` save, `0..9` smooth animated recall)<br>• Added `[` / `]` dynamic camera fly speed scaling (`AdjustCameraSpeed`) and `Cam Speed` readout in the Stats HUD<br>• Added `Move to View` (`ViewportAlignTransformToView`) snapping any selected `TCastleTransform` to the viewport camera<br>• Added one-click `Stats` and `Colliders` toolbar toggles + enriched HUD with 3D Ruler |
| **5. Content Browser / Drawer** | • Instant search bar filtering assets by name or extension<br>• Asset type filter pills (All, 3D/Meshes, Blueprints/Designs, Textures, Audio, Code)<br>• Drag-and-drop from Content Browser directly onto 3D viewport surface with grid snapping | • `TCastleShellTreeView` + `TCastleShellListView` + `TViewFileFrame` preview<br>• No search bar or asset type filter pills in the Files panel<br>• Drag-and-drop into 3D viewport did not snap to 3D grid | **Completed (Phase 5)**:<br>• Added `PanelFilesTop` filter bar in `TProjectForm` with `EditFileFilter` and 6 asset category pills (`All`, `3D/Scenes`, `Designs`, `Images`, `Audio`, `Code`) combining category masks with substring queries<br>• Upgraded `CastleControlDragDrop` to snap dropped 3D transforms to `TranslateSnap` when 3D snapping is active |
| **6. Quick-Add & Command Palette** | • "Quickly Add to the Project" button & searchable palette<br>• Instant keyboard-driven actor/component instantiation | • Deep nested menus (`Add Transform -> ...`, `Add User Interface -> ...`) | **Completed (Phase 6)**:<br>• Added `+ Add` toolbar button (`ButtonQuickAdd`) and `Ctrl+P` viewport shortcut opening `ShowQuickAddPalette`, a searchable modal palette filtering all registered `TCastleTransform`, `TCastleUserInterface`, `TCastleBehavior`, and `TCastleComponent` classes |
| **7. Play-In-Editor (PIE) & Simulation** | • Simulate-In-Editor (Physics running while camera is free)<br>• Pause & Single-Step physics frame<br>• "Keep Simulation Changes" (`K`) saving simulated transforms back to level design | • Internal Physics Simulation (`ActionSimulationPlayStop`, `ActionSimulationPauseUnpause`), but stopping simulation always discarded simulated positions and no Single-Step existed | **Completed (Phase 7)**:<br>• Added `Step` (`ButtonSimulationStep` / `SimulationSingleStep`) to advance paused physics by exactly 1 frame ($1/60\text{ s}$)<br>• Added `Keep Sim` (`ButtonKeepSimulation` / `KeepSimulationChanges`) to stop simulation and persist simulated `Translation`, `Rotation`, and `Scale` onto the design as a single Undo-able step |

---

## 2. Prioritized Modernization TODO List (All 27 Phases Completed)

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

### Phase 24: 2D / 3D Grid Array Duplication (`GridDuplicateSelected` / `Ctrl+Alt+G`)
- [x] **24.1. Multi-Dimensional Lattice Duplication ($N_X \times N_Y \times N_Z$)**
  - Implemented `TDesignFrame.GridDuplicateSelected(CountX, CountY, CountZ, Spacing)` and `ShowGridDuplicateDialog`.
  - Auto-initializes default cell spacing $(S_X, S_Y, S_Z)$ from the active transform's world bounding-box dimensions (`WorldBoundingBox.SizeX/Y/Z`) and clones all top-level selected `TCastleTransform` objects across $(i_X, i_Y, i_Z) \in [0\dots N_X-1] \times [0\dots N_Y-1] \times [0\dots N_Z-1] \setminus \{(0,0,0)\}$ in a single Undo step.
  - Bound to **`Ctrl+Alt+G`** in both the Viewport and Hierarchy Tree, **`Grid Dup...`** (`ButtonGridDuplicate`) in `PanelLayoutTransform`, and **`2D / 3D Grid Duplicate... (Ctrl+Alt+G)`** in `MenuTreeView`.

### Phase 25: Project Selected Transforms Along Any Direction / Camera View Ray (`ProjectSelectedAlongDirection` / `Ctrl+Shift+End`)
- [x] **25.1. Directional Raycast Surface Projection (`TCastleTransformManipulate.ProjectSelectedAlongDirection`)**
  - Implemented `TCastleTransformManipulate.ProjectSelectedAlongDirection(WorldDirection, AlignToNormal): Boolean`: casts a ray from each top-level selected transform along any arbitrary world direction (accounting for the transform's half-extent along `WorldDirection` so its leading bounding-box face lands flush against the target wall, ceiling, or angled surface) and optionally aligns local `+Y` to the hit surface normal.
  - Implemented `TDesignFrame.ViewportProjectAlongView(AlignToNormal)` projecting selected transforms along the viewport camera's forward look vector (`CamDir`), bound to **`Ctrl+Shift+End`** (`Alt` for normal alignment) and **`Project Along View`** (`ButtonProjectAlongView`, `Shift`/`Alt`-click for normal alignment) in `PanelLayoutTransform`.

### Phase 26: Hierarchy & Viewport Selection Power Tools (`InvertSelection` / `Ctrl+I`, `SelectChildren` / `Ctrl+]`)
- [x] **26.1. Sibling-Scoped Selection Inversion & Direct/Recursive Child Selection**
  - Implemented `TDesignFrame.InvertSelection` (**`Ctrl+I`** in Viewport and Hierarchy Tree, plus `Invert Selection (Ctrl+I)` in `MenuTreeView`), inverting the selection among siblings of the active parent node (or across all design nodes when at root level).
  - Implemented `TDesignFrame.SelectChildren(Recursive: Boolean)` bound to **`Ctrl+]`** (direct children) and **`Ctrl+Shift+]`** (all recursive descendants) in the Hierarchy Tree, plus `Select Direct Children (Ctrl+])` and `Select All Descendants (Ctrl+Shift+])` in `MenuTreeView`.

### Phase 27: Bounding-Box Equal-Gap Distribution (`DistributeSelectedGaps`) & Absolute Rotation/Scale Grid Quantization (`SnapSelectedRotationAndScaleToGrid`)
- [x] **27.1. Bounding-Box Equal-Gap Distribution (`DistributeSelectedGaps` / `Shift+Dist X/Y/Z`)**
  - Implemented `TCastleTransformManipulate.DistributeSelectedGaps(Axis)`: sorts 3+ selected transforms along `Axis`, computes the total outer bounding span minus the sum of all individual world AABB widths, and spaces intermediate objects so the empty gap between adjacent bounding boxes is identical (even when objects have different sizes).
  - Integrated into `ButtonDistributeAxisClick` when holding **`Shift`** (`Shift`-click on `Dist X`, `Dist Y`, or `Dist Z`).
- [x] **27.2. Absolute Rotation & Scale Grid Quantization (`SnapSelectedRotationAndScaleToGrid` / `Ctrl+End`)**
  - Implemented `TCastleTransformManipulate.SnapSelectedRotationAndScaleToGrid: Boolean` to round existing `Rotation.W` angles to the nearest `RotateSnap` multiple and `Scale.X/Y/Z` components to the nearest `ScaleSnap` multiple, and integrated it into `ViewportSnapToGrid` (`Ctrl+End`).
  - Added automated unit test `TestProjectAlongDirectionDistributeGapsAndSnapRotScale` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 28: Match Size / Scale to Primary Selection (`MatchSelectedSize`) & Swap / Cycle Positions (`SwapSelectedPositions` / `Ctrl+Shift+S`)
- [x] **28.1. World-Space Position Swap & Cycle (`TCastleTransformManipulate.SwapSelectedPositions` / `Ctrl+Shift+S`)**
  - Implemented `TCastleTransformManipulate.SwapSelectedPositions: Boolean`: swaps the world-space positions of 2 selected transforms ($T_0 \leftrightarrow T_1$), or cyclically rotates the world-space positions of $N \ge 3$ selected transforms ($T_0 \to T_1 \to \dots \to T_{N-1} \to T_0$), converting each target world position back into each transform's parent local space via `Parent.WorldToLocal`.
  - Bound to **`Ctrl+Shift+S`** in both the 3D Viewport and Hierarchy Tree, plus **`Swap Pos`** (`ButtonSwapPositions`) in `PanelLayoutTransform`.
- [x] **28.2. Match World Bounding-Box Size to Primary Selection (`TCastleTransformManipulate.MatchSelectedSize` / `Match Size`)**
  - Implemented `TCastleTransformManipulate.MatchSelectedSize(const Axis: Integer = -1): Boolean`: adjusts `Scale` on all secondary selected transforms so their world bounding-box dimensions (`WorldBoundingBox.Size`) match `Selected[0]` along all axes (`Axis = -1`, normal click on **`Match Size`**) or along a single axis (`Axis = 1` for Y height when `Shift`-clicking **`Match Size`**).
  - Added automated unit test `TestSwapPositionsAndMatchSelectedSize` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 29: Camera Pilot / "Lock Actor to Viewport Camera" Mode (`TogglePilotTransform` / `Ctrl+Shift+P`)
- [x] **29.1. Interactive Viewport Camera Pilot Mode (`TogglePilotTransform` / `StopPilotTransform`)**
  - Implemented Unreal Engine 5.5-style **Pilot Actor** mode (`FPilotTransform`, `TogglePilotTransform`, `StopPilotTransform`) in `TDesignFrame`.
  - Pressing **`Ctrl+Shift+P`** (or clicking **`Pilot Transform`** in `PanelLayoutTransform`) snaps the viewport camera to the active `TCastleTransform`'s world view (`GetWorldView` / `SetWorldView`) and continuously synchronizes the transform's world position and orientation with `CurrentViewport.InternalCamera` every frame in `CastleControlUpdate` as you fly/orbit in the viewport.
  - Displays a live `[PILOT ACTIVE: "<Name>" - Ctrl+Shift+P to exit]` indicator in the Viewport Statistics HUD and records a single clean `'Pilot Transform: <Name>'` Undo entry upon exiting Pilot Mode or changing selection.

### Phase 30: Select By Spatial Proximity (`SelectWithinRadius`) & Select All With Same Asset URL (`SelectAllWithSameUrl`)
- [x] **30.1. Select All Components Sharing the Same Asset URL (`SelectAllWithSameUrl`)**
  - Implemented `TDesignFrame.GetComponentAssetUrl(C)` (using `TypInfo` RTTI inspection of published `Url` string properties across `TCastleScene`, `TCastleDesign`, `TCastleTransformDesign`, `TCastleImageControl`, `TCastleImageTransform`, `TCastleTiledMap`, `TCastleSound`, etc.) and `SelectAllWithSameUrl` (`MenuTreeViewItemSelectSameUrl` in `MenuTreeView`).
- [x] **30.2. Select Transforms Within Spatial Radius (`SelectWithinRadius` / `ShowSelectWithinRadiusDialog`)**
  - Implemented `TDesignFrame.SelectWithinRadius(Radius)` and `ShowSelectWithinRadiusDialog` (`MenuTreeViewItemSelectWithinRadius` in `MenuTreeView`), selecting all visible, unlocked `TCastleTransform` instances in the same world whose world bounding-box center (or origin) lies within `Radius` world units of the active selection center.

### Phase 31: Ground-Aware Scatter / Drop-to-Floor Duplication (`ScatterDuplicateSelected` / `Ctrl+Alt+S`)
- [x] **31.1. Uniform-Disk Scatter Duplication with Automatic Floor Snapping (`ScatterDuplicateSelected`)**
  - Implemented `TDesignFrame.ScatterDuplicateSelected(Count, Radius, MaxYawDeg, ScaleMin, ScaleMax, SnapToGround, AlignToNormal)` and `ShowScatterDuplicateDialog`.
  - Scatters `Count` clones per selected `TCastleTransform` across a uniform-area disk of radius `Radius` in the XZ plane ($r = \sqrt{u} \cdot R$, $\theta = 2\pi v$), applies random Yaw rotation in $[-\text{MaxYawDeg}, +\text{MaxYawDeg}]$ and uniform scale in $[\text{ScaleMin}, \text{ScaleMax}]$, automatically drops all scattered clones onto the underlying floor geometry via `TransformManipulate.SnapToFloor(AlignToNormal)`, and records a single Undo step.
  - Bound to **`Ctrl+Alt+S`** in both the Viewport and Hierarchy Tree, **`Scatter Dup...`** (`ButtonScatterDuplicate`) in `PanelLayoutTransform`, and **`Scatter Duplicate on Ground... (Ctrl+Alt+S)`** in `MenuTreeView`.

### Phase 32: Look-At / Aim Selected Transforms at Primary or Cursor Target (`LookAtWorldPoint` / `AimSelectedAtPrimary` / `Ctrl+Shift+L`)
- [x] **32.1. World-Space Look-At & Multi-Transform Aiming (`LookAtWorldPoint`, `AimSelectedAtPrimary`)**
  - Implemented `TCastleTransformManipulate.LookAtWorldPoint(TargetWorldPos): Boolean` and `TCastleTransformManipulate.AimSelectedAtPrimary: Boolean`: rotates each selected transform (or all secondary selected transforms `Selected[1..N-1]` when aiming at `Selected[0]`) so its world forward direction (`SetWorldView`) points directly at `TargetWorldPos` while keeping its world Up vector orthogonalized around `World.GravityUp` and preserving existing `Scale`.
  - Implemented `TDesignFrame.AimSelectionAtPrimaryOrCursor`: when 2+ transforms are selected, aims `Selected[1..N-1]` at `Selected[0]`; when 1 transform is selected, raycasts from the mouse cursor into the 3D viewport (`MeasureRayDistanceFromSelected`) and aims the selected transform at the 3D surface point under the cursor.
  - Bound to **`Ctrl+Shift+L`** in both the 3D Viewport and Hierarchy Tree, plus **`Aim at Target`** (`ButtonAimAtTarget`) in `PanelLayoutTransform`.

### Phase 33: Bounding-Box Min / Max Face Alignment (`AlignSelectedBounds` / `Ctrl`/`Alt` + `Align X/Y/Z`)
- [x] **33.1. World AABB Min-Face & Max-Face Alignment (`TCastleTransformManipulate.AlignSelectedBounds`)**
  - Implemented `TCastleTransformManipulate.AlignSelectedBounds(Axis, UseMaxFace): Boolean`: translates secondary selected transforms (`Selected[1..N-1]`) along `Axis` so their minimum (`UseMaxFace = false`) or maximum (`UseMaxFace = true`) world bounding-box face (`WorldBoundingBox.Data[0]` or `Data[1]`) aligns flush with the corresponding face of `Selected[0]`.
  - Upgraded `ButtonAlignAxisClick` (`Align X`, `Align Y`, `Align Z` in `PanelLayoutTransform`): normal click aligns origins to Primary (`atPrimary`), **`Shift`-click** aligns to selection Center (`atCenter`), **`Ctrl`-click** aligns minimum bounding-box faces (`AlignSelectedBounds(Axis, false)`), and **`Alt`-click** aligns maximum bounding-box faces (`AlignSelectedBounds(Axis, true)`).
  - Added automated unit test `TestLookAtAimAndAlignSelectedBounds` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 34: Interactive 2D UI Layout Alignment, Equal-Gap Distribution & Size Matching (`PanelLayoutUI`)
- [x] **34.1. Multi-Selection 2D `TCastleUserInterface` Alignment, Distribution & Size Matching**
  - Added `PanelLayoutUI` inside `PanelLayoutTop` (automatically shown in the `Layout` tab whenever 2 or more unlocked `TCastleUserInterface` controls are selected) with 9 quick-action buttons:
    - **`UI Align Left`**, **`UI Center H`**, **`UI Align Right`**, **`UI Align Bottom`**, **`UI Middle V`**, **`UI Align Top`** (`AlignSelectedUserInterfaces`): aligns the rendered screen-space edges or centers (`RenderRectWithBorder`) of all secondary selected UI controls to the primary selected UI control, converting screen pixel deltas cleanly via `UI.UIScale` regardless of anchor settings.
    - **`UI Dist H`**, **`UI Dist V`** (`DistributeSelectedUserInterfaces`): sorts 3+ selected UI controls by horizontal or vertical center and spaces them with equal screen-space gaps between adjacent `RenderRectWithBorder` bounds.
    - **`UI Match Size`** (`MatchSelectedUserInterfaceSize`): matches `Width` and `Height` of secondary selected UI controls to `PrimaryUI.EffectiveWidth` and `EffectiveHeight` (`Shift`-click for Width only, `Ctrl`-click for Height only).

### Phase 35: Hierarchy Selection Sets (`Ctrl+Shift+0..9` / `Shift+0..9`) & Select By Name / Wildcard Pattern (`SelectByNamePattern`)
- [x] **35.1. 10 Named Hierarchy Selection Set Slots (`SaveSelectionSet` / `RecallSelectionSet`)**
  - Added `FSelectionSets: array [0..9] of TStringList` in `TDesignFrame`.
  - Pressing **`Ctrl+Shift+0..9`** in the Viewport or Hierarchy Tree saves the names of all currently selected components into slot `0..9`; pressing **`Shift+0..9`** recalls that selection set (or **`Alt+Shift+0..9`** to additively union the saved set with the current selection).
- [x] **35.2. Select Components By Substring or Wildcard Pattern (`SelectByNamePattern` / `ShowSelectByNamePatternDialog`)**
  - Implemented `TDesignFrame.SelectByNamePattern(Pattern)` and `ShowSelectByNamePatternDialog` (`Select By Name Pattern...` in `MenuTreeView`), supporting case-insensitive wildcard patterns (`*`, `?` via `StrUtils.IsWild`, pre-populated from `StripNumericSuffix(SelectedComponent.Name) + '*'`) as well as plain substring matching across all selectable, unlocked components.

### Phase 36: Match Rotation (`MatchSelectedRotation`) & Match Transform (`MatchSelectedTransform`) to Primary Selection (`Ctrl+Shift+M`)
- [x] **36.1. Copy World Orientation & Full Transform from Primary Selection (`MatchSelectedRotation`, `MatchSelectedTransform`)**
  - Implemented `TCastleTransformManipulate.MatchSelectedRotation: Boolean` and `TCastleTransformManipulate.MatchSelectedTransform(MatchPos, MatchRot, MatchScale): Boolean`: copies the primary selected transform's (`Selected[0]`) world-space orientation (`GetWorldView` / `SetWorldView`), world position, and/or scale to all secondary top-level selected transforms (`Selected[1..N-1]`).
  - Added **`Match Rot`** (`ButtonMatchRotation`) in `PanelLayoutTransform` and bound **`Ctrl+Shift+M`** in both the 3D Viewport and Hierarchy Tree: normal click (or `Ctrl+Shift+M`) matches world rotation only, **`Shift`-click** matches world position + rotation, and **`Ctrl`-click** matches full transform (position + rotation + scale).

### Phase 37: Circular / Radial Arrange Existing Selection (`ArrangeSelectedInCircle` / `Alt+Shift+C`)
- [x] **37.1. Horizontal Circle & Arc Arrangement for Existing Transforms (`TCastleTransformManipulate.ArrangeSelectedInCircle`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInCircle(Radius, TotalAngleDeg, OrientToCenter): Boolean`: arranges 2+ existing top-level selected transforms around a horizontal (XZ) circle or arc centered at `SelectionWorkingCenter` (or `Selected[0]` when `PivotMode = pmPrimarySelected`), automatically computing the average horizontal radius when `Radius <= 0` and optionally orienting each transform to face the circle center (`OrientToCenter = true`).
  - Added **`Circle Arrange`** (`ButtonArrangeCircle` in `PanelLayoutTransform`: normal click arranges immediately with auto-radius; `Shift`-click opens the customization dialog) and `ShowArrangeInCircleDialog` bound to **`Alt+Shift+C`** in both the Viewport and Hierarchy Tree.
  - Added automated unit test `TestMatchRotationTransformAndArrangeInCircle` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 38: Select Overlapping / Intersecting Transforms (`SelectOverlappingTransforms` / `Ctrl+Shift+O`) & Select By Bounding-Box Diagonal Size Range (`SelectBySizeRange`)
- [x] **38.1. Overlap / Duplicate Placement Detection (`SelectOverlappingTransforms` / `Ctrl+Shift+O`)**
  - Implemented `TDesignFrame.SelectOverlappingTransforms`: checks `WorldBoundingBox` intersections (with a $10^{-3}$ interior margin so flush-stacked objects are not false-flagged, while excluding ancestor/descendant pairs) against the active selection, or scans all pairs across the entire scene when nothing (or a non-overlapping transform) is selected.
  - Bound to **`Ctrl+Shift+O`** in both the 3D Viewport and Hierarchy Tree, plus **`Select Overlapping Transforms (Ctrl+Shift+O)`** in `MenuTreeView`.
- [x] **38.2. Select Transforms By World Bounding-Box Diagonal Size (`SelectBySizeRange` / `ShowSelectBySizeRangeDialog`)**
  - Implemented `TDesignFrame.SelectBySizeRange(MinDiagonal, MaxDiagonal)` and `ShowSelectBySizeRangeDialog` (**`Select By Bounding-Box Size...`** in `MenuTreeView`), pre-populated with $[0.8 \times D, 1.2 \times D]$ of the active transform's world bounding-box diagonal length $D$ to quickly find similarly sized props across the level.

### Phase 39: World/Local-Aware 3D Transform & 2D UI Layout Attribute Copy/Paste (`CopyTransform` / `PasteTransform` / `Ctrl+Alt+C` / `Ctrl+Alt+V`)
- [x] **39.1. Coordinate-Space-Aware Transform & 2D UI Layout Attribute Copy/Paste**
  - Upgraded `TDesignFrame.CopyTransform` and `TDesignFrame.PasteTransform(RotationAndScaleOnly)` to support both 3D `TCastleTransform` (recording both local `Translation`/`Rotation`/`Scale` and world `GetWorldView` state, pasting in World space when `CoordSpace = csWorld` or Local space when `csLocal`) and 2D `TCastleUserInterface` (`Translation`, `Width`, `Height`, `FullSize`, horizontal/vertical anchors, and `Border.AllSides`).
  - Holding **`Shift`** when pasting (**`Ctrl+Alt+Shift+V`** or `Shift`-clicking **`Paste Transform`**) pastes **Rotation & Scale only** (for 3D transforms) or **Size & Border only** (for 2D UI controls), preserving each target object's existing position.
  - Bound to **`Ctrl+Alt+C`**, **`Ctrl+Alt+V`**, and **`Ctrl+Alt+Shift+V`** in both the 3D Viewport and Hierarchy Tree, plus **`Copy Transform / UI Layout (Ctrl+Alt+C)`** and **`Paste Transform / UI Layout (Ctrl+Alt+V)`** in `MenuTreeView`.

### Phase 40: Arrange Existing Selection in 2D / 3D Grid (`ArrangeSelectedInGrid` / `Alt+Shift+G`)
- [x] **40.1. Non-Duplicating 2D / 3D Grid Arrangement for Existing Transforms (`TCastleTransformManipulate.ArrangeSelectedInGrid`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInGrid(ColumnsX, RowsZ, Spacing, CenterGrid): Boolean`: arranges 2+ existing top-level selected transforms into a 2D (XZ) or 3D (XYZ) grid without duplicating them, automatically computing `ColumnsX = Ceil(Sqrt(Count))`, `RowsZ = Ceil(Count / ColumnsX)`, and `Spacing = 1.25 * MaxBoundingBoxExtent` when any parameter is `<= 0`.
  - Added **`Grid Arrange`** (`ButtonArrangeGrid` in `PanelLayoutTransform`: normal click arranges immediately with auto columns/spacing centered on selection; `Shift`-click opens the customization dialog) and `ShowArrangeInGridDialog` bound to **`Alt+Shift+G`** in both the Viewport and Hierarchy Tree.

### Phase 41: Push / Pull Selected Positions From Pivot (`ScaleSelectedPositionsFromPivot` / `Alt+Shift+=` / `Alt+Shift+-`)
- [x] **41.1. Expand & Contract Multi-Selection Spacing Without Scaling Objects (`TCastleTransformManipulate.ScaleSelectedPositionsFromPivot`)**
  - Implemented `TCastleTransformManipulate.ScaleSelectedPositionsFromPivot(Factor): Boolean`: scales the world-space offsets of 2+ top-level selected transforms away from or toward the active selection pivot (`SelectionWorkingCenter` or `Selected[0]`) by `Factor` without altering any transform's `Scale` or `Rotation`.
  - Added **`Expand +25%`** (`ButtonExpandPositions`) and **`Contract -20%`** (`ButtonContractPositions`) in `PanelLayoutTransform` (`Shift`-click restricts push/pull to the horizontal XZ plane) and bound **`Alt+Shift+=`** / **`Alt+Shift+-`** in both the Viewport and Hierarchy Tree.

### Phase 42: Granular Transform Attribute Reset (`ResetSelectedTransform` / `Alt+G`, `Alt+R`, `Alt+S`)
- [x] **42.1. Blender-Style Clear Location (`Alt+G`), Clear Rotation (`Alt+R`), Clear Scale (`Alt+S`) & `Reset Xform`**
  - Implemented `TCastleTransformManipulate.ResetSelectedTransform(ResetTrans, ResetRot, ResetScale): Boolean` and `TDesignFrame.ResetSelectionTransformAttributes` (which also resets `Translation` on selected 2D `TCastleUserInterface` controls when `Alt+G` is pressed).
  - Bound **`Alt+G`** (Reset Translation), **`Alt+R`** (Reset Rotation), and **`Alt+S`** (Reset Scale) in both the 3D Viewport and Hierarchy Tree, and added **`Reset Xform`** (`ButtonResetTransform`) in `PanelLayoutTransform` (normal click: All; `Shift`-click: Rot+Scale only; `Ctrl`-click: Rot only).
  - Added automated unit test `TestArrangeInGridScalePositionsAndResetTransform` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 43: Select Transforms At Same Elevation (`SelectAtSameElevation` / `Ctrl+Shift+E`) & 2D UI Swap / Grid Arrange (`PanelLayoutUI`)
- [x] **43.1. Select Same Floor / World-Y Elevation (`SelectAtSameElevation` / `Ctrl+Shift+E`)**
  - Implemented `TDesignFrame.SelectAtSameElevation(Tolerance)` and `ShowSelectAtSameElevationDialog`: selects all visible, unlocked `TCastleTransform` instances in the same world whose world origin Y or world bounding-box bottom Y matches any currently selected transform within `Tolerance` (default `0.25` units).
  - Bound to **`Ctrl+Shift+E`** in both the Viewport and Hierarchy Tree, plus **`Select At Same Elevation (Y)... (Ctrl+Shift+E)`** (`MenuTreeViewItemSelectSameElevation`) in `MenuTreeView`.
- [x] **43.2. 2D UI Position Swap & 2D UI Grid Arrange (`SwapSelectedUserInterfacePositions`, `ArrangeSelectedUserInterfacesInGrid`)**
  - Added **`UI Swap Pos`** (`ButtonUISwapPos`) and **`UI Grid`** (`ButtonUIGridArrange`) to `PanelLayoutUI` to swap/cycle screen-space centers of 2+ selected `TCastleUserInterface` controls or arrange them into an even $\lceil\sqrt{N}\rceil$-column 2D screen grid (`16 px` gap, or `8 px` when `Shift`-clicked).

### Phase 44: Arrange Existing Selection Along 3D Line Segment (`ArrangeSelectedAlongLine` / `ArrangeSelectedBetweenEndpoints` / `Alt+Shift+L`)
- [x] **44.1. Even 3D Line-Segment Placement & Forward Orientation (`TCastleTransformManipulate.ArrangeSelectedAlongLine`, `ArrangeSelectedBetweenEndpoints`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedAlongLine(StartWorldPos, EndWorldPos, OrientAlongLine): Boolean` and `TCastleTransformManipulate.ArrangeSelectedBetweenEndpoints(OrientAlongLine): Boolean`: places 2+ top-level selected transforms at evenly spaced intervals ($t = i / (N - 1)$) along the 3D line segment between `StartWorldPos` and `EndWorldPos` (or between `Selected[0]` and `Selected[N-1]`), optionally orienting each transform's world forward vector along the line direction while keeping its up vector aligned with `World.GravityUp`.
  - Added **`Line Arrange`** (`ButtonArrangeLine` in `PanelLayoutTransform`: normal click arranges between first and last selected endpoints; `Ctrl`-click also orients forward along the line; `Shift`-click opens the custom 3D endpoints dialog) and `ShowArrangeAlongLineDialog` bound to **`Alt+Shift+L`** in both the Viewport and Hierarchy Tree.

### Phase 45: Automatic Bounding-Box Overlap Separation / Depenetrate (`SeparateOverlappingSelected` / `Alt+Shift+X`)
- [x] **45.1. Iterative Minimum-Penetration-Vector Overlap Resolution (`TCastleTransformManipulate.SeparateOverlappingSelected`)**
  - Implemented `TCastleTransformManipulate.SeparateOverlappingSelected(MinPadding, HorizontalOnly, MaxIterations): Boolean`: iteratively resolves intersecting `WorldBoundingBox` pairs among 2+ selected transforms (plus optional `MinPadding` clearance) along the minimum penetration axis (horizontal XZ plane when `HorizontalOnly = true` so Y elevation is preserved, or full 3D XYZ when `HorizontalOnly = false`).
  - Added **`Depenetrate`** (`ButtonSeparateOverlaps` in `PanelLayoutTransform`: normal click separates horizontally with `0` padding; `Shift`-click opens `ShowSeparateOverlappingDialog`) and bound **`Alt+Shift+X`** in both the Viewport and Hierarchy Tree.

### Phase 46: Progressive Scale Taper & Cumulative Rotation Step (`ApplyProgressiveTransformSelected` / `Alt+Shift+T`)
- [x] **46.1. Selection-Ordered Scale Gradient & Spiral Yaw Step (`TCastleTransformManipulate.ApplyProgressiveTransformSelected`)**
  - Implemented `TCastleTransformManipulate.ApplyProgressiveTransformSelected(StartScale, EndScale, ApplyScaleGradient, Axis, StepAngleRad): Boolean`: interpolates `Scale` linearly from `StartScale` (`Selected[0]`) to `EndScale` (`Selected[N-1]`) and/or applies a cumulative rotation increment $i \cdot \text{StepAngleRad}$ around `Axis` across 2+ top-level selected transforms.
  - Added **`Taper / Spiral...`** (`ButtonProgressiveXform`) in `PanelLayoutTransform` and `ShowProgressiveTransformDialog` bound to **`Alt+Shift+T`** in both the Viewport and Hierarchy Tree.
  - Added automated unit test `TestArrangeLineSeparateOverlappingAndProgressiveTransform` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 47: Select Transforms Visible In Camera Frustum (`SelectTransformsInCameraFrustum` / `Ctrl+Shift+F`) & 2D UI Horizontal / Vertical Edge-to-Edge Stack (`StackSelectedUserInterfaces`)
- [x] **47.1. Camera Frustum Visibility Query (`SelectTransformsInCameraFrustum` / `Ctrl+Shift+F`)**
  - Implemented `TDesignFrame.SelectTransformsInCameraFrustum`: tests all visible, unlocked `TCastleTransform` instances in the active viewport against `CurrentViewport.Camera.Frustum` (`Box3DCollisionPossibleSimple` / `SphereCollisionPossibleSimple`) and selects all transforms currently inside the camera's view frustum.
  - Bound to **`Ctrl+Shift+F`** in both the Viewport and Hierarchy Tree, plus **`Select Visible In Camera View (Ctrl+Shift+F)`** (`MenuTreeViewItemSelectInCameraFrustum`) in `MenuTreeView`.
- [x] **47.2. 2D UI Edge-to-Edge Horizontal & Vertical Stacking (`StackSelectedUserInterfaces` / `ButtonUIStackH` & `ButtonUIStackV`)**
  - Implemented `TDesignFrame.StackSelectedUserInterfaces(Vertical, GapPx)` and added **`UI Stack H`** (`ButtonUIStackH`) and **`UI Stack V`** (`ButtonUIStackV`) to `PanelLayoutUI`, sorting 2+ selected `TCastleUserInterface` controls left-to-right or top-to-bottom and stacking them flush (`0 px` gap on normal click, or `8 px` gap on `Shift`-click).

### Phase 48: 3D Polyline / Multi-Waypoint Path Arrangement (`ArrangeSelectedAlongWaypoints` / `Alt+Shift+P`)
- [x] **48.1. Equal Arc-Length 3D Polyline Arrangement & Tangent Orientation (`TCastleTransformManipulate.ArrangeSelectedAlongWaypoints`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedAlongWaypoints(Waypoints: array of TVector3; OrientAlongPath: Boolean): Boolean`: computes cumulative arc lengths along a multi-point 3D polyline (`Length(Waypoints) >= 2`), places 2+ top-level selected transforms at equal arc-length intervals ($d_i = \frac{i}{N - 1} L_{\text{total}}$), and optionally rotates each transform so its world forward direction faces along the active segment tangent while keeping its up vector aligned with `World.GravityUp`.
  - Added **`Path Arrange`** (`ButtonArrangePath` in `PanelLayoutTransform`: normal click arranges along the 3-waypoint polyline formed by the first, middle, and last selected transforms; `Ctrl`-click also orients forward along the path; `Shift`-click opens the 3-waypoint dialog) and `ShowArrangeAlongPathDialog` bound to **`Alt+Shift+P`** in both the Viewport and Hierarchy Tree.

### Phase 49: 3D Spiral / Helix Arrangement for Existing Selection (`ArrangeSelectedInHelix` / `Alt+Shift+H`)
- [x] **49.1. Cylindrical & Conical 3D Spiral Staircase / Helix Arrangement (`TCastleTransformManipulate.ArrangeSelectedInHelix`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInHelix(StartRadius, EndRadius, HeightSpan, Turns, OrientToCenter): Boolean`: arranges 2+ top-level selected transforms along a 3D cylindrical (`StartRadius = EndRadius`) or conical (`StartRadius <> EndRadius`) helix around the active selection pivot across `Turns` full revolutions and `HeightSpan` vertical rise, optionally orienting each transform toward the central helix axis.
  - Added **`Helix Arrange...`** (`ButtonArrangeHelix`) in `PanelLayoutTransform` and `ShowArrangeInHelixDialog` bound to **`Alt+Shift+H`** in both the Viewport and Hierarchy Tree.

### Phase 50: Center / Snap Parent Transform Origin to Children Bounds (`CenterSelectedOriginOnChildren` / `Alt+Shift+O`)
- [x] **50.1. Non-Destructive Parent Pivot Centering on Direct Children (`TCastleTransformManipulate.CenterSelectedOriginOnChildren`)**
  - Implemented `TCastleTransformManipulate.CenterSelectedOriginOnChildren(UseBottomCenter: Boolean = false): Boolean`: shifts each selected parent `TCastleTransform` that has direct `TCastleTransform` children to the combined `WorldBoundingBox.Center` (or bottom-center `MinY` when `UseBottomCenter = true`) of its direct children while restoring all children's world-space positions so the visual scene does not move.
  - Added **`Center Parent Origin`** (`ButtonCenterPivotOnChildren` in `PanelLayoutTransform`: normal click snaps to children center; `Shift`-click snaps to children bottom-center) and bound **`Alt+Shift+O`** in both the Viewport and Hierarchy Tree.
  - Added automated unit test `TestArrangeWaypointsHelixAndCenterOriginOnChildren` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 51: Select Transforms By World-Space Axis Coordinate Slice (`SelectByAxisRange` / `Ctrl+Shift+B`) & 2D UI Center In Parent (`CenterSelectedUserInterfacesInParent` / `ButtonUICenterInParent`)
- [x] **51.1. World-Space Axis Coordinate Slice Selection (`SelectByAxisRange` / `Ctrl+Shift+B`)**
  - Implemented `TDesignFrame.SelectByAxisRange(Axis, MinCoord, MaxCoord)` and `ShowSelectByAxisRangeDialog`: selects all visible, unlocked `TCastleTransform` instances whose world coordinate along `Axis` (`X`, `Y`, or `Z`) falls within `[MinCoord, MaxCoord]`.
  - Bound to **`Ctrl+Shift+B`** in both the Viewport and Hierarchy Tree, plus **`Select By Axis Coordinate Slice... (Ctrl+Shift+B)`** (`MenuTreeViewItemSelectByAxisRange`) in `MenuTreeView`.
- [x] **51.2. 2D UI Center In Parent Container (`CenterSelectedUserInterfacesInParent` / `ButtonUICenterInParent`)**
  - Implemented `TDesignFrame.CenterSelectedUserInterfacesInParent(Horizontally, Vertically)` and added **`UI Center Parent`** (`ButtonUICenterInParent`) to `PanelLayoutUI` (enabled whenever 1 or more unlocked `TCastleUserInterface` controls are selected: normal click centers both horizontally and vertically in `ParentRenderRect`; `Shift`-click centers horizontally only; `Ctrl`-click centers vertically only).

### Phase 52: 3D Parabolic / Quadratic Bezier Arch Arrangement (`ArrangeSelectedInBezierArch` / `ArrangeSelectedInParabolicArchBetweenEndpoints` / `Alt+Shift+A`)
- [x] **52.1. Smooth 3D Quadratic Bezier & Parabolic Bridge / Gateway Arch Arrangement (`TCastleTransformManipulate.ArrangeSelectedInBezierArch`, `ArrangeSelectedInParabolicArchBetweenEndpoints`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInBezierArch(StartWorldPos, ControlWorldPos, EndWorldPos, OrientAlongCurve): Boolean` and `TCastleTransformManipulate.ArrangeSelectedInParabolicArchBetweenEndpoints(ApexHeightOffset, OrientAlongCurve): Boolean`: arranges 2+ top-level selected transforms along a quadratic Bezier arch $B(t) = (1 - t)^2 P_0 + 2(1 - t)t P_1 + t^2 P_2$ ($t = i / (N - 1)$) whose apex at $t = 0.5$ rises by `ApexHeightOffset` along Y above the midpoint, with optional forward orientation along the instantaneous curve tangent $B'(t) = 2(1 - t)(P_1 - P_0) + 2t(P_2 - P_1)$.
  - Added **`Arch Arrange`** (`ButtonArrangeArch` in `PanelLayoutTransform`: normal click arranges in a parabolic arch between first & last selected transforms; `Ctrl`-click also orients forward along the curve tangent; `Shift`-click opens the custom arch dialog) and `ShowArrangeInArchDialog` bound to **`Alt+Shift+A`** in both the Viewport and Hierarchy Tree.

### Phase 53: 3D Spherical / Dome Fibonacci Lattice Arrangement (`ArrangeSelectedOnSphere` / `Alt+Shift+S`)
- [x] **53.1. Equidistant Fibonacci Golden-Angle Sphere, Dome & Latitude Band Distribution (`TCastleTransformManipulate.ArrangeSelectedOnSphere`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedOnSphere(Radius, MinElevationDeg, MaxElevationDeg, OrientOutward): Boolean`: distributes 2+ top-level selected transforms evenly across a 3D sphere ($[-90^\circ, +90^\circ]$), upper hemisphere dome ($[0^\circ, +90^\circ]$), or custom latitude band around the active selection pivot using the Fibonacci golden-angle spiral lattice ($\Delta\theta = \pi(3 - \sqrt{5})$), optionally rotating each transform to point radially outward from the sphere center.
  - Added **`Sphere / Dome...`** (`ButtonArrangeSphere`) in `PanelLayoutTransform` and `ShowArrangeOnSphereDialog` bound to **`Alt+Shift+S`** in both the Viewport and Hierarchy Tree.

### Phase 54: Cohesive Group Scaling Around Pivot (`ScaleSelectedGroupAroundPivot` / `Alt+Shift+]` & `Alt+Shift+[`)
- [x] **54.1. Simultaneous World-Offset & Local-Scale Group Scaling Around Selection Pivot (`TCastleTransformManipulate.ScaleSelectedGroupAroundPivot`)**
  - Implemented `TCastleTransformManipulate.ScaleSelectedGroupAroundPivot(Factor, ScaleSizes): Boolean`: scales both the world-space position offsets from the active selection pivot (`SelectionWorkingCenter` or `Selected[0]`) and the local `Scale` of all top-level selected transforms simultaneously by `Factor`, allowing an entire multi-object assembly to be scaled up or down proportionally without creating a parent group node.
  - Added **`Group Scale +25%`** (`ButtonScaleGroupUp` / **`Alt+Shift+]`**) and **`Group Scale -20%`** (`ButtonScaleGroupDown` / **`Alt+Shift+[`**) in `PanelLayoutTransform` (`Shift`-clicking either button restricts group scaling to the horizontal XZ plane).
  - Added automated unit test `TestArrangeBezierArchSphereAndScaleGroupAroundPivot` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 55: Select Empty / Unreferenced Transforms (`SelectEmptyTransforms` / `Ctrl+Shift+U`) & 2D UI Fit Parent Container (`FitSelectedUserInterfacesToParent` / `ButtonUIFitParent`)
- [x] **55.1. Scene Cleanup Audit: Select Empty Groups & Unreferenced Scene Transforms (`SelectEmptyTransforms` / `Ctrl+Shift+U`)**
  - Implemented `TDesignFrame.SelectEmptyTransforms`: selects all visible, unlocked `TCastleTransform` instances that have no non-transient child transforms, no behaviors, and no non-visual components, and are either plain `TCastleTransform` containers or `TCastleScene` / `TCastleTransformDesign` instances with an empty `Url`.
  - Bound to **`Ctrl+Shift+U`** in both the Viewport and Hierarchy Tree, plus **`Select Empty / Unreferenced Transforms (Ctrl+Shift+U)`** (`MenuTreeViewItemSelectEmptyTransforms`) in `MenuTreeView`.
- [x] **55.2. 2D UI Fit To Parent Container (`FitSelectedUserInterfacesToParent` / `ButtonUIFitParent`)**
  - Implemented `TDesignFrame.FitSelectedUserInterfacesToParent(FitWidth, FitHeight)` and added **`UI Fit Parent`** (`ButtonUIFitParent`) to `PanelLayoutUI` (normal click matches both `Width` and `Height` to `ParentRenderRect` and centers in parent; `Shift`-click fits Width and horizontal position only; `Ctrl`-click fits Height and vertical position only).

### Phase 56: 3D Sine-Wave / Undulating Ribbon Arrangement (`ArrangeSelectedInSineWave` / `ArrangeSelectedInSineWaveBetweenEndpoints` / `Alt+Shift+W`)
- [x] **56.1. 3D Sinusoidal Wave & Tangent-Oriented Ribbon Arrangement (`TCastleTransformManipulate.ArrangeSelectedInSineWave`, `ArrangeSelectedInSineWaveBetweenEndpoints`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInSineWave(StartWorldPos, EndWorldPos, Amplitude, Cycles, WaveAxis, OrientAlongWave): Boolean` and `TCastleTransformManipulate.ArrangeSelectedInSineWaveBetweenEndpoints(Amplitude, Cycles, WaveAxis, OrientAlongWave): Boolean`: arranges 2+ top-level selected transforms along a 3D line between `StartWorldPos` and `EndWorldPos` with sinusoidal displacement $A \sin(2\pi \cdot \text{Cycles} \cdot t)$ along `WaveAxis` (`X`, `Y`, or `Z`) and optional forward orientation along the instantaneous wave tangent $P'(t)$.
  - Added **`Wave Arrange`** (`ButtonArrangeWave` in `PanelLayoutTransform`: normal click arranges in a vertical sine wave between first & last selected transforms; `Ctrl`-click also orients forward along the wave tangent; `Shift`-click opens the custom wave dialog) and `ShowArrangeInWaveDialog` bound to **`Alt+Shift+W`** in both the Viewport and Hierarchy Tree.

### Phase 57: 3D Elliptical / Stadium Ring Arrangement (`ArrangeSelectedInEllipse` / `Alt+Shift+E`)
- [x] **57.1. Horizontal XZ Ellipse & Tangent / Inward Orientation (`TCastleTransformManipulate.ArrangeSelectedInEllipse`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInEllipse(RadiusX, RadiusZ, OrientMode): Boolean`: distributes 2+ top-level selected transforms evenly around a horizontal XZ ellipse centered at the active selection pivot with independent `RadiusX` and `RadiusZ` semi-axes and `OrientMode` (`0` = keep rotation, `1` = orient inward toward center, `2` = orient along ellipse tangent).
  - Added **`Ellipse Arrange...`** (`ButtonArrangeEllipse`) in `PanelLayoutTransform` and `ShowArrangeInEllipseDialog` bound to **`Alt+Shift+E`** in both the Viewport and Hierarchy Tree.

### Phase 58: Reverse / Flip Selection Order (`ReverseSelectedPositions` / `Alt+Shift+R`)
- [x] **58.1. World-Space Position, Rotation & Scale Order Reversal (`TCastleTransformManipulate.ReverseSelectedPositions`)**
  - Implemented `TCastleTransformManipulate.ReverseSelectedPositions(ReverseRotations, ReverseScales): Boolean`: reverses the order of world-space positions ($T_0 \leftrightarrow T_{N-1}, \; T_1 \leftrightarrow T_{N-2}, \dots$), and optionally world rotations and local scales, across 2+ top-level selected transforms.
  - Added **`Reverse Order`** (`ButtonReversePositions` in `PanelLayoutTransform`: normal click reverses positions; `Shift`-click reverses positions + rotations; `Ctrl`-click reverses positions + rotations + scales) and bound **`Alt+Shift+R`** in both the Viewport and Hierarchy Tree.
  - Added automated unit test `TestArrangeSineWaveEllipseAndReversePositions` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 59: Select Non-Uniformly Scaled Transforms (`SelectNonUniformlyScaledTransforms` / `Ctrl+Shift+N`) & 2D UI Equal-Span Split In Parent (`StretchSelectedUserInterfacesAcrossParent`)
- [x] **59.1. Physics Collider Scale Audit: Select Non-Uniformly or Non-Positively Scaled Transforms (`SelectNonUniformlyScaledTransforms` / `Ctrl+Shift+N`)**
  - Implemented `TDesignFrame.SelectNonUniformlyScaledTransforms`: selects all visible, unlocked `TCastleTransform` instances whose `Scale` has non-uniform components (`not SameValue(S.X, S.Y, 1e-3)` or `not SameValue(S.Y, S.Z, 1e-3)`) or non-positive components (`<= 0`).
  - Bound to **`Ctrl+Shift+N`** in both the Viewport and Hierarchy Tree, plus **`Select Non-Uniformly Scaled Transforms (Ctrl+Shift+N)`** (`MenuTreeViewItemSelectNonUniformScale`) in `MenuTreeView`.
- [x] **59.2. 2D UI Equal-Span Row & Column Split In Parent (`StretchSelectedUserInterfacesAcrossParent` / `ButtonUIStretchRow` & `ButtonUIStretchCol`)**
  - Implemented `TDesignFrame.StretchSelectedUserInterfacesAcrossParent(Vertical, GapPx)` and added **`UI Split Row`** (`ButtonUIStretchRow`) and **`UI Split Col`** (`ButtonUIStretchCol`) to `PanelLayoutUI`, dividing `ParentRenderRect` width (`Vertical = false`) or height (`Vertical = true`) equally across 2+ selected `TCastleUserInterface` controls with `8 px` spacing on normal click or `0 px` flush spacing on `Shift`-click.

### Phase 60: 3D Phyllotaxis / Golden-Angle Sunflower Disk Arrangement (`ArrangeSelectedInPhyllotaxisDisk` / `Alt+Shift+D`)
- [x] **60.1. Uniform-Density Golden-Angle Spiral Disk Arrangement (`TCastleTransformManipulate.ArrangeSelectedInPhyllotaxisDisk`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInPhyllotaxisDisk(OuterRadius, OrientMode): Boolean`: distributes 2+ top-level selected transforms across a horizontal XZ disk of radius `OuterRadius` centered at the active selection pivot using Vogel's golden-angle phyllotaxis model ($r_i = R \sqrt{i / (N - 1)}, \; \theta_i = i \cdot \pi(3 - \sqrt{5})$) with `OrientMode` (`0` = keep rotation, `1` = orient inward toward center, `2` = orient outward from center).
  - Added **`Disk Arrange...`** (`ButtonArrangeDisk`) in `PanelLayoutTransform` and `ShowArrangeInDiskDialog` bound to **`Alt+Shift+D`** in both the Viewport and Hierarchy Tree.

### Phase 61: 3D Staircase / Stepped Ramp Arrangement (`ArrangeSelectedInStaircase` / `ArrangeSelectedInStaircaseBetweenEndpoints` / `Alt+Shift+Y`)
- [x] **61.1. Linear-XZ & Power-Curve-Y Staircase Arrangement (`TCastleTransformManipulate.ArrangeSelectedInStaircase`, `ArrangeSelectedInStaircaseBetweenEndpoints`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInStaircase(StartWorldPos, EndWorldPos, CurveExponent, OrientHorizontallyAlongRun): Boolean` and `TCastleTransformManipulate.ArrangeSelectedInStaircaseBetweenEndpoints(CurveExponent, OrientHorizontallyAlongRun): Boolean`: arranges 2+ top-level selected transforms between `StartWorldPos` and `EndWorldPos` with uniform horizontal XZ step progression and power-curve vertical Y elevation ($y(t) = y_0 + (y_1 - y_0)t^E$), optionally orienting each step's horizontal yaw along the XZ staircase run while keeping steps level (`World.GravityUp`).
  - Added **`Stair Arrange`** (`ButtonArrangeStairs` in `PanelLayoutTransform`: normal click arranges in a linear staircase between first & last selected transforms; `Ctrl`-click also orients yaw along the horizontal run; `Shift`-click opens the custom staircase dialog) and `ShowArrangeInStairsDialog` bound to **`Alt+Shift+Y`** in both the Viewport and Hierarchy Tree.

### Phase 62: Radial / Cylindrical XZ Push-Pull From Pivot (`ScaleSelectedRadialDistanceXZ` / `Alt+Shift+.` & `Alt+Shift+,`)
- [x] **62.1. Horizontal Radial Distance Scaling Around Selection Pivot (`TCastleTransformManipulate.ScaleSelectedRadialDistanceXZ`)**
  - Implemented `TCastleTransformManipulate.ScaleSelectedRadialDistanceXZ(RadialFactor): Boolean`: scales only the horizontal XZ radial distance of 2+ top-level selected transforms away from or toward the active selection pivot (`SelectionWorkingCenter` or `Selected[0]`) by `RadialFactor` while strictly preserving each transform's world Y elevation, `Rotation`, and `Scale`.
  - Added **`Radial +25%`** (`ButtonRadialExpand` / **`Alt+Shift+.`**) and **`Radial -20%`** (`ButtonRadialContract` / **`Alt+Shift+,`**) in `PanelLayoutTransform`.
  - Added automated unit test `TestArrangePhyllotaxisDiskStaircaseAndRadialScale` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 63: Select Rotated / Tilted Transforms (`SelectRotatedTransforms` / `Ctrl+Shift+T`) & 2D UI Equal Margin Inset In Parent (`InsetSelectedUserInterfacesInParent` / `ButtonUIInsetParent`)
- [x] **63.1. Orientation Audit: Select Rotated or Tilted Transforms (`SelectRotatedTransforms` / `Ctrl+Shift+T`)**
  - Implemented `TDesignFrame.SelectRotatedTransforms`: selects all visible, unlocked `TCastleTransform` instances that have non-zero local rotation (`Abs(T.Rotation.W) > 1e-3`) or tilted world orientation (`WorldUp` $\neq (0,1,0)$ or `WorldDir` $\neq (0,0,-1)$).
  - Bound to **`Ctrl+Shift+T`** in both the Viewport and Hierarchy Tree, plus **`Select Rotated / Tilted Transforms (Ctrl+Shift+T)`** (`MenuTreeViewItemSelectRotatedTransforms`) in `MenuTreeView`.
- [x] **63.2. 2D UI Uniform Margin Inset In Parent (`InsetSelectedUserInterfacesInParent` / `ButtonUIInsetParent`)**
  - Implemented `TDesignFrame.InsetSelectedUserInterfacesInParent(MarginPx)` and added **`UI Inset Parent`** (`ButtonUIInsetParent`) to `PanelLayoutUI`, resizing and centering 1+ selected `TCastleUserInterface` controls inside their parent container with a uniform screen-space margin (`16 px` on normal click, `8 px` on `Shift`-click, `32 px` on `Ctrl`-click).

### Phase 64: 3D Torus / Helical Torus Coil Arrangement (`ArrangeSelectedOnTorus` / `Alt+Shift+U`)
- [x] **64.1. 3D Torus Ring & Helical Tube Coil Arrangement (`TCastleTransformManipulate.ArrangeSelectedOnTorus`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedOnTorus(MajorRadius, MinorRadius, MinorTurns, OrientMode): Boolean`: distributes 2+ top-level selected transforms around a 3D torus or helical torus coil centered at the active selection pivot ($x = (R + r\cos\phi)\cos\theta, \; y = r\sin\phi, \; z = (R + r\cos\phi)\sin\theta$ where $\theta_i = 2\pi i / N$ and $\phi_i = 2\pi \cdot \text{MinorTurns} \cdot i / N$) with `OrientMode` (`0` = keep rotation, `1` = orient outward along torus tube normal, `2` = orient along helical torus tangent).
  - Added **`Torus / Coil...`** (`ButtonArrangeTorus`) in `PanelLayoutTransform` and `ShowArrangeOnTorusDialog` bound to **`Alt+Shift+U`** in both the Viewport and Hierarchy Tree.

### Phase 65: 3D Zigzag / Alternating Staggered Corridor Arrangement (`ArrangeSelectedInZigzag` / `ArrangeSelectedInZigzagBetweenEndpoints` / `Alt+Shift+Z`)
- [x] **65.1. Alternating Lateral Corridor Offset & Inward/Forward Orientation (`TCastleTransformManipulate.ArrangeSelectedInZigzag`, `ArrangeSelectedInZigzagBetweenEndpoints`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInZigzag(StartWorldPos, EndWorldPos, LateralOffset, OrientMode): Boolean` and `TCastleTransformManipulate.ArrangeSelectedInZigzagBetweenEndpoints(LateralOffset, OrientMode): Boolean`: arranges 2+ top-level selected transforms evenly between `StartWorldPos` and `EndWorldPos` with alternating lateral horizontal offset $(-1)^i \cdot \text{LateralOffset}$ perpendicular to the corridor line and `OrientMode` (`0` = keep rotation, `1` = orient forward along corridor line, `2` = orient inward toward central corridor walkway).
  - Added **`Zigzag Arrange`** (`ButtonArrangeZigzag` in `PanelLayoutTransform`: normal click arranges in an alternating zigzag between first & last selected transforms; `Ctrl`-click also orients inward toward the central corridor; `Shift`-click opens the custom zigzag dialog) and `ShowArrangeInZigzagDialog` bound to **`Alt+Shift+Z`** in both the Viewport and Hierarchy Tree.

### Phase 66: Equalize / Normalize World Bounding-Box Sizes (`NormalizeSelectedSizes` / `Alt+Shift+N`)
- [x] **66.1. Uniform Diagonal & Per-Axis Bounding-Box Size Equalization (`TCastleTransformManipulate.NormalizeSelectedSizes`)**
  - Implemented `TCastleTransformManipulate.NormalizeSelectedSizes(PreserveAspectRatio): Boolean`: computes the shared arithmetic mean of the world bounding-box diagonals (when `PreserveAspectRatio = true`) or per-axis bounding-box dimensions $(S_X, S_Y, S_Z)$ (when `PreserveAspectRatio = false`) across 2+ top-level selected transforms and scales each transform's `Scale` so all selected transforms match the average size.
  - Added **`Equalize Size`** (`ButtonNormalizeSize` in `PanelLayoutTransform`: normal click or **`Alt+Shift+N`** equalizes diagonals uniformly; `Shift`-click equalizes X, Y, Z dimensions independently).
  - Added automated unit test `TestArrangeTorusZigzagAndNormalizeSizes` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 67: Select Transforms With Behaviors / Physics (`SelectTransformsWithBehaviors` / `Ctrl+Shift+K`) & 2D UI Make Square (`MakeSelectedUserInterfacesSquare` / `ButtonUISquareSize`)
- [x] **67.1. Behavior & Physics Audit: Select Transforms With Behaviors (`SelectTransformsWithBehaviors` / `Ctrl+Shift+K`)**
  - Implemented `TDesignFrame.SelectTransformsWithBehaviors(PhysicsOnly)`: selects all visible, unlocked `TCastleTransform` instances that have attached `TCastleBehavior` components (`BehaviorsCount > 0`), or—when `Shift`-clicking the menu item (`PhysicsOnly = true`)—only transforms with `TCastleRigidBody` or `TCastleCollider` behaviors.
  - Bound to **`Ctrl+Shift+K`** in both the Viewport and Hierarchy Tree, plus **`Select Transforms With Behaviors / Physics (Ctrl+Shift+K)`** (`MenuTreeViewItemSelectWithBehaviors`) in `MenuTreeView`.
- [x] **67.2. 2D UI Equal-Aspect Square Sizing (`MakeSelectedUserInterfacesSquare` / `ButtonUISquareSize`)**
  - Implemented `TDesignFrame.MakeSelectedUserInterfacesSquare(SizeMode)` and added **`UI Make Square`** (`ButtonUISquareSize`) to `PanelLayoutUI`, resizing 1+ selected `TCastleUserInterface` controls to a 1:1 square around their current screen center (`Max(W, H)` on normal click, `Min(W, H)` on `Shift`-click, `0.5 * (W + H)` on `Ctrl`-click).

### Phase 68: 3D Figure-8 / Lemniscate & Lissajous Curve Arrangement (`ArrangeSelectedInLissajous` / `Alt+Shift+F`)
- [x] **68.1. Parametric 3D Lissajous & Figure-8 Loop Arrangement (`TCastleTransformManipulate.ArrangeSelectedInLissajous`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInLissajous(RadiusX, RadiusZ, FreqX, FreqZ, VerticalAmplitude, OrientMode): Boolean`: distributes 2+ top-level selected transforms along a 3D Lissajous / figure-8 / lemniscate curve around the active selection pivot ($x(\theta) = C_x + R_x \sin(\omega_x \theta), \; y(\theta) = C_y + H_y \cos(\omega_x \theta), \; z(\theta) = C_z + R_z \sin(\omega_z \theta)$ for $\theta_i = 2\pi i / N$) with `OrientMode` (`0` = keep rotation, `1` = orient horizontally inward toward center, `2` = orient forward along 3D curve tangent).
  - Added **`Figure-8 / Lissajous`** (`ButtonArrangeLissajous` in `PanelLayoutTransform`: normal click arranges in a figure-8 loop; `Ctrl`-click also orients along the curve tangent; `Shift`-click opens the custom Lissajous dialog) and `ShowArrangeInLissajousDialog` bound to **`Alt+Shift+F`** in both the Viewport and Hierarchy Tree.

### Phase 69: 3D Catenary / Hanging Cable / Suspension Chain Arrangement (`ArrangeSelectedInCatenary` / `ArrangeSelectedInCatenaryBetweenEndpoints` / `Alt+Shift+B`)
- [x] **69.1. Hyperbolic Cosine Catenary Sag Curve & Tangent Orientation (`TCastleTransformManipulate.ArrangeSelectedInCatenary`, `ArrangeSelectedInCatenaryBetweenEndpoints`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInCatenary(StartWorldPos, EndWorldPos, SagDepth, OrientAlongCurve): Boolean` and `TCastleTransformManipulate.ArrangeSelectedInCatenaryBetweenEndpoints(SagDepth, OrientAlongCurve): Boolean`: arranges 2+ top-level selected transforms along a hanging catenary cable / suspension bridge chain between `StartWorldPos` and `EndWorldPos` with normalized hyperbolic cosine sag $S(u) = \frac{\cosh(k) - \cosh(k u)}{\cosh(k) - 1}$ ($k = 1.5, u = 2t - 1$) so endpoints match $P_0, P_1$ exactly while the midpoint sags by `SagDepth` (or arches upward when `SagDepth < 0`), with optional 3D catenary tangent orientation (`OrientAlongCurve = true`).
  - Added **`Catenary Cable`** (`ButtonArrangeCatenary` in `PanelLayoutTransform`: normal click arranges with auto $25\%$ span sag; `Ctrl`-click also orients along the cable tangent; `Shift`-click opens the custom catenary dialog) and `ShowArrangeInCatenaryDialog` bound to **`Alt+Shift+B`** in both the Viewport and Hierarchy Tree.

### Phase 70: Orthogonal Projection / Snap Selected Transforms Onto Connecting Line (`ProjectSelectedOntoLine` / `ProjectSelectedOntoLineBetweenEndpoints` / `Alt+Shift+I`)
- [x] **70.1. Longitudinal-Spacing-Preserving Orthogonal Line Projection (`TCastleTransformManipulate.ProjectSelectedOntoLine`, `ProjectSelectedOntoLineBetweenEndpoints`)**
  - Implemented `TCastleTransformManipulate.ProjectSelectedOntoLine(LineStartWorldPos, LineEndWorldPos, ClampToSegment, OrientAlongLine): Boolean` and `TCastleTransformManipulate.ProjectSelectedOntoLineBetweenEndpoints(ClampToSegment, OrientAlongLine): Boolean`: projects each selected transform orthogonally onto the 3D line connecting `LineStartWorldPos` and `LineEndWorldPos` ($P'_i = P_0 + t_i(P_1 - P_0)$ where $t_i = \frac{(P_i - P_0)\cdot(P_1 - P_0)}{\|P_1 - P_0\|^2}$), straightening hand-placed rows of props without altering their relative longitudinal spacing, with optional segment clamping (`ClampToSegment`) and line-direction orientation (`OrientAlongLine`).
  - Added **`Snap to Line`** (`ButtonProjectOntoLine` in `PanelLayoutTransform`: normal click or **`Alt+Shift+I`** projects onto the line between first & last selected transforms; `Shift`-click clamps to segment $[0, 1]$; `Ctrl`-click orients along the line).
  - Added automated unit test `TestArrangeLissajousCatenaryAndProjectOntoLine` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 71: Select All Lights & Cameras (`SelectLightsAndCameras` / `Ctrl+Shift+J`) & 2D UI Golden-Ratio Sizing (`ApplyGoldenRatioToSelectedUserInterfaces` / `ButtonUIGoldenRatio`)
- [x] **71.1. Scene Lighting & Camera Audit: Select All Lights & Cameras (`SelectLightsAndCameras` / `Ctrl+Shift+J`)**
  - Implemented `TDesignFrame.SelectLightsAndCameras(Mode)`: selects all visible, unlocked `TCastleAbstractLight` and `TCastleCamera` instances in the hierarchy (`Mode = 0` on normal click or **`Ctrl+Shift+J`**), only lights on `Shift`-click (`Mode = 1`), or only cameras on `Ctrl`-click (`Mode = 2`).
  - Added **`Select All Lights & Cameras (Ctrl+Shift+J)`** (`MenuTreeViewItemSelectLightsAndCameras`) to `MenuTreeView`.
- [x] **71.2. 2D UI Golden-Ratio Aspect Sizing (`ApplyGoldenRatioToSelectedUserInterfaces` / `ButtonUIGoldenRatio`)**
  - Implemented `TDesignFrame.ApplyGoldenRatioToSelectedUserInterfaces(Landscape, KeepWidth)` and added **`UI Golden Ratio`** (`ButtonUIGoldenRatio`) to `PanelLayoutUI`, resizing 1+ selected `TCastleUserInterface` controls around their current screen center to the golden ratio $\varphi = \frac{1 + \sqrt{5}}{2} \approx 1.618034$ (`Width := Height * Phi` on normal click, portrait `Height := Width * Phi` on `Shift`-click, landscape keeping width `Height := Width / Phi` on `Ctrl`-click).

### Phase 72: 3D Regular Polygon & Star Polygon Perimeter Arrangement (`ArrangeSelectedInPolygon` / `Alt+Shift+K`)
- [x] **72.1. Regular N-gon & Star Polygon Perimeter Interpolation (`TCastleTransformManipulate.ArrangeSelectedInPolygon`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInPolygon(Sides, OuterRadius, InnerRadius, OrientMode): Boolean`: distributes 2+ top-level selected transforms evenly by perimeter progress $u = i / N$ along the closed $N$-sided regular polygon (`InnerRadius <= 0`) or $2N$-vertex star polygon (`InnerRadius > 0`, alternating between `OuterRadius` and `InnerRadius` vertices) around the active selection pivot on the horizontal XZ plane, with `OrientMode` (`0` = keep rotation, `1` = orient outward along polygon edge normal, `2` = orient forward along polygon edge tangent).
  - Added **`Polygon / Star`** (`ButtonArrangePolygon` in `PanelLayoutTransform`: normal click arranges in a regular pentagon; `Ctrl`-click also orients along edge tangent; `Shift`-click opens the custom polygon/star dialog) and `ShowArrangeInPolygonDialog` bound to **`Alt+Shift+K`** in both the Viewport and Hierarchy Tree.

### Phase 73: 3D Archimedean & Logarithmic Spiral Vortex Arrangement (`ArrangeSelectedInSpiralVortex` / `Alt+Shift+J`)
- [x] **73.1. Parametric 3D Archimedean & Logarithmic Spiral Vortex (`TCastleTransformManipulate.ArrangeSelectedInSpiralVortex`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInSpiralVortex(StartRadius, EndRadius, Turns, HeightSpan, Logarithmic, OrientMode): Boolean`: arranges 2+ top-level selected transforms along a 3D spiral vortex around the active selection pivot with linear Archimedean radial growth $r(t) = R_0 + (R_1 - R_0)t$ (`Logarithmic = false`) or exponential Logarithmic radial growth $r(t) = R_0 (R_1 / R_0)^t$ (`Logarithmic = true`), angular sweep $\theta(t) = 2\pi \cdot \text{Turns} \cdot t$, vertical span $y(t) = C_y + (t - \tfrac{1}{2}) H$, and `OrientMode` (`0` = keep rotation, `1` = orient horizontally outward from vortex axis, `2` = orient forward along 3D spiral tangent).
  - Added **`Spiral Vortex`** (`ButtonArrangeSpiralVortex` in `PanelLayoutTransform`: normal click arranges in a 2-turn spiral; `Ctrl`-click also orients along the spiral tangent; `Shift`-click opens the custom spiral vortex dialog) and `ShowArrangeInSpiralVortexDialog` bound to **`Alt+Shift+J`** in both the Viewport and Hierarchy Tree.

### Phase 74: Orthogonal Projection / Flatten Selected Transforms Onto 3D Plane (`ProjectSelectedOntoPlane` / `ProjectSelectedOntoPlaneThreePoints` / `Alt+Shift+M`)
- [x] **74.1. Arbitrary & 3-Point 3D Plane Orthogonal Projection (`TCastleTransformManipulate.ProjectSelectedOntoPlane`, `ProjectSelectedOntoPlaneThreePoints`)**
  - Implemented `TCastleTransformManipulate.ProjectSelectedOntoPlane(PlanePoint, PlaneNormal, AlignUpToNormal): Boolean` and `TCastleTransformManipulate.ProjectSelectedOntoPlaneThreePoints(AlignUpToNormal): Boolean`: orthogonally projects 2+ top-level selected transforms onto any 3D plane defined by `(PlanePoint, PlaneNormal)` ($P'_i = P_i - ((P_i - P_{\text{plane}}) \cdot \hat{N}) \hat{N}$) or the plane passing through the first 3 selected transforms (`Selected[0..2]`), with optional local $+Y$ Up alignment to $\hat{N}$ (`AlignUpToNormal = true`).
  - Added **`Flatten to Plane`** (`ButtonProjectOntoPlane` in `PanelLayoutTransform`: normal click or **`Alt+Shift+M`** flattens onto the horizontal XZ plane at the selection pivot; `Shift`-click flattens 4+ selected transforms onto the inclined plane defined by the first 3 selected transforms; `Ctrl`-click aligns local $+Y$ Up to the plane normal).
  - Added automated unit test `TestArrangePolygonSpiralVortexAndProjectOntoPlane` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 75: Select Transforms With Sound Sources / Trigger Volumes (`SelectSoundAndTriggerTransforms` / `Ctrl+Shift+W`) & 2D UI Standard 16:9 / 4:3 Aspect Sizing (`ApplyStandardAspectToSelectedUserInterfaces` / `ButtonUIAspect16x9`)
- [x] **75.1. Audio & Trigger Volume Audit: Select Transforms With Sound Sources or Physics Triggers (`SelectSoundAndTriggerTransforms` / `Ctrl+Shift+W`)**
  - Implemented `TDesignFrame.SelectSoundAndTriggerTransforms(TriggersOnly)`: selects all visible, unlocked `TCastleTransform` instances that have an attached `TCastleSoundSource` behavior or a trigger `TCastleRigidBody` (`RBody.Trigger = true`), or—when `Shift`-clicking the menu item (`TriggersOnly = true`)—only physics trigger volumes.
  - Bound to **`Ctrl+Shift+W`** in both the Viewport and Hierarchy Tree, plus **`Select Transforms With Sound Sources (Ctrl+Shift+W)`** (`MenuTreeViewItemSelectSoundSources`) in `MenuTreeView`.
- [x] **75.2. 2D UI Widescreen 16:9, Vertical 9:16 & Classic 4:3 Aspect Sizing (`ApplyStandardAspectToSelectedUserInterfaces` / `ButtonUIAspect16x9`)**
  - Implemented `TDesignFrame.ApplyStandardAspectToSelectedUserInterfaces(AspectMode)` and added **`UI 16:9 / 4:3`** (`ButtonUIAspect16x9`) to `PanelLayoutUI`, resizing 1+ selected `TCastleUserInterface` controls around their current screen center to standard display aspect ratios (`16:9` widescreen on normal click, `9:16` vertical on `Shift`-click, `4:3` classic on `Ctrl`-click).

### Phase 76: 3D $(p, q)$ Torus Knot / Trefoil Knot Arrangement (`ArrangeSelectedInTorusKnot` / `Alt+Shift+Q`)
- [x] **76.1. Parametric 3D $(p, q)$ Torus Knot Curve Arrangement (`TCastleTransformManipulate.ArrangeSelectedInTorusKnot`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInTorusKnot(MajorRadius, TubeRadius, KnotP, KnotQ, OrientMode): Boolean`: distributes 2+ top-level selected transforms evenly around a 3D $(p, q)$ torus knot (such as the $(2, 3)$ trefoil knot or $(3, 5)$ cinquefoil knot) centered at the active selection pivot:
    $$r(t) = R + r_t \cos(q t), \quad X(t) = C_x + r(t) \cos(p t), \quad Y(t) = C_y + r_t \sin(q t), \quad Z(t) = C_z + r(t) \sin(p t)$$
    with `OrientMode` (`0` = keep rotation, `1` = orient outward along tube normal, `2` = orient forward along analytical 3D knot tangent).
  - Added **`Torus Knot`** (`ButtonArrangeTorusKnot` in `PanelLayoutTransform`: normal click arranges in a $(2, 3)$ trefoil knot; `Ctrl`-click also orients along the 3D knot tangent; `Shift`-click opens the custom $(p, q)$ torus knot dialog) and `ShowArrangeInTorusKnotDialog` bound to **`Alt+Shift+Q`** in both the Viewport and Hierarchy Tree.

### Phase 77: 3D Concentric Amphitheater / Stadium Rings Arrangement (`ArrangeSelectedInConcentricRings` / `Alt+Shift+V`)
- [x] **77.1. Multi-Tier Concentric Amphitheater & Stadium Ring Distribution (`TCastleTransformManipulate.ArrangeSelectedInConcentricRings`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInConcentricRings(FirstRingRadius, RingSpacing, RingRiseY, BaseRingCount, OrientMode): Boolean`: distributes 2+ top-level selected transforms across concentric horizontal XZ rings with stepped vertical elevation (`RingRiseY` per tier) around the active selection pivot, where ring $k$ has radius $R_k = R_0 + k \cdot \Delta R$, elevation $Y_k = C_y + k \cdot \Delta Y$, and capacity proportional to circumference ($\text{Cap}_k = \operatorname{Round}(\text{BaseRingCount} \cdot R_k / R_0)$), with `OrientMode` (`0` = keep rotation, `1` = orient inward toward arena center, `2` = orient outward from center).
  - Added **`Amphitheater Rings`** (`ButtonArrangeConcentricRings` in `PanelLayoutTransform`: normal click arranges in tiered amphitheater rings; `Ctrl`-click also orients inward toward the arena center; `Shift`-click opens the custom concentric rings dialog) and `ShowArrangeInConcentricRingsDialog` bound to **`Alt+Shift+V`** in both the Viewport and Hierarchy Tree.

### Phase 78: Radial Projection / Snap Selected Transforms Onto Sphere or Cylinder (`ProjectSelectedOntoSphere` / `ProjectSelectedOntoCylinder` / `Alt+Shift+/`)
- [x] **78.1. Radial Spherical & Cylindrical Shell Projection (`TCastleTransformManipulate.ProjectSelectedOntoSphere`, `ProjectSelectedOntoCylinder`)**
  - Implemented `TCastleTransformManipulate.ProjectSelectedOntoSphere(Radius, OrientOutward): Boolean` and `TCastleTransformManipulate.ProjectSelectedOntoCylinder(Radius, OrientOutward): Boolean`: radially projects 2+ top-level selected transforms from the active selection pivot onto a sphere of radius $R$ ($P'_i = C + R \frac{P_i - C}{\|P_i - C\|}$) or a vertical XZ cylinder of radius $R$ while preserving each transform's individual Y elevation ($P'_i = (C_x + R u_x, P_{i,y}, C_z + R u_z)$), automatically using the mean distance from the pivot when `Radius <= 0` and optionally orienting each transform radially outward (`OrientOutward = true`).
  - Added **`Snap to Sphere/Cyl`** (`ButtonProjectOntoSphere` in `PanelLayoutTransform`: normal click or **`Alt+Shift+/`** snaps onto a sphere at the selection's average radius; `Shift`-click snaps onto a vertical XZ cylinder; `Ctrl`-click also orients radially outward).
  - Added automated unit test `TestArrangeTorusKnotConcentricRingsAndProjectSphereCylinder` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 79: Select All Hidden (`Exists = false`) Components (`SelectHiddenComponents` / `Ctrl+Shift+H`) & 2D UI Reverse Visual Order (`ReverseSelectedUserInterfacePositions` / `ButtonUIReverseOrder`)
- [x] **79.1. Scene Visibility Audit: Select All Hidden Components (`SelectHiddenComponents` / `Ctrl+Shift+H`)**
  - Implemented `TDesignFrame.SelectHiddenComponents(TransformsOnly)`: selects all unlocked `TCastleTransform` and `TCastleUserInterface` instances in the hierarchy that currently have `Exists = false` (or `Shift`-clicking the menu item for hidden `TCastleTransform` instances only) so hidden objects can be inspected, batch-unhidden, or deleted.
  - Bound to **`Ctrl+Shift+H`** in both the Viewport and Hierarchy Tree, plus **`Select All Hidden Components (Ctrl+Shift+H)`** (`MenuTreeViewItemSelectHidden`) in `MenuTreeView`.
- [x] **79.2. 2D UI Reverse Visual Order (`ReverseSelectedUserInterfacePositions` / `ButtonUIReverseOrder`)**
  - Implemented `TDesignFrame.ReverseSelectedUserInterfacePositions(SwapSizes)` and added **`UI Reverse Order`** (`ButtonUIReverseOrder`) to `PanelLayoutUI`, reversing the screen-space center positions of 2+ selected `TCastleUserInterface` controls from first to last (`Shift`-click also swaps their `Width` and `Height` dimensions).

### Phase 80: 3D Geodesic / Fibonacci Cylinder & Pillar Shell Arrangement (`ArrangeSelectedOnCylinder` / `Alt+Shift+\`)
- [x] **80.1. Uniform Cylindrical Golden-Angle Lattice Distribution (`TCastleTransformManipulate.ArrangeSelectedOnCylinder`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedOnCylinder(Radius, HeightSpan, OrientMode): Boolean`: distributes 2+ top-level selected transforms uniformly across the lateral surface of a vertical 3D cylinder of radius $R$ and vertical span $H$ centered at the active selection pivot using the cylindrical golden-angle spiral lattice ($\theta_i = i \cdot \pi(3 - \sqrt{5}), \; y_i = C_y + (\frac{i}{N - 1} - \frac{1}{2}) H, \; X_i = C_x + R\cos\theta_i, \; Z_i = C_z + R\sin\theta_i$) with `OrientMode` (`0` = keep rotation, `1` = orient horizontally inward toward cylinder axis, `2` = orient horizontally outward along cylinder surface normal).
  - Added **`Cylinder Wall...`** (`ButtonArrangeCylinder` in `PanelLayoutTransform`: normal click arranges on a Fibonacci cylinder wall; `Ctrl`-click also orients radially outward; `Shift`-click opens the custom cylinder dialog) and `ShowArrangeOnCylinderDialog` bound to **`Alt+Shift+\`** in both the Viewport and Hierarchy Tree.

### Phase 81: 3D Stepped Pyramid / Ziggurat Tier Arrangement (`ArrangeSelectedInPyramid` / `Alt+Shift+;`)
- [x] **81.1. Stacked $(L+1)\times(L+1)$ Square Tier Pyramid Distribution (`TCastleTransformManipulate.ArrangeSelectedInPyramid`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInPyramid(BaseSpacingXZ, LayerRiseY, OrientMode): Boolean`: arranges 2+ top-level selected transforms into a 3D stepped pyramid / ziggurat of stacked horizontal square tiers around the active selection pivot, where tier $L \in \{0, \dots, K-1\}$ (from top apex $1 \times 1$ down to base $K \times K$) forms a centered $(L+1)\times(L+1)$ grid at elevation $Y_L = C_y + (K - 1 - L)\cdot \Delta Y$, with `OrientMode` (`0` = keep rotation, `1` = orient horizontally outward from pyramid center, `2` = orient horizontally inward toward pyramid center).
  - Added **`Pyramid / Ziggurat`** (`ButtonArrangePyramid` in `PanelLayoutTransform`: normal click arranges in a stepped pyramid; `Ctrl`-click also orients outward; `Shift`-click opens the custom pyramid dialog) and `ShowArrangeInPyramidDialog` bound to **`Alt+Shift+;`** in both the Viewport and Hierarchy Tree.

### Phase 82: Clamp Selected Transforms Inside 3D Box / Primary Selection Bounds (`ClampSelectedToBox` / `ClampSelectedToPrimaryBounds` / `Alt+Shift+'`)
- [x] **82.1. Bounding-Box-Aware 3D Volume Containment Clamping (`TCastleTransformManipulate.ClampSelectedToBox`, `ClampSelectedToPrimaryBounds`)**
  - Implemented `TCastleTransformManipulate.ClampSelectedToBox(BoxMin, BoxMax, UseObjectBounds): Boolean` and `TCastleTransformManipulate.ClampSelectedToPrimaryBounds(UseObjectBounds): Boolean`: clamps top-level selected transforms so their entire `WorldBoundingBox` (`UseObjectBounds = true`) or world origin (`UseObjectBounds = false`) stays strictly inside `[BoxMin, BoxMax]` or inside the primary selected transform's `WorldBoundingBox` (`Selected[0]`), shifting any protruding object inward by the exact minimum axis delta (or centering it along any axis where the object is wider than the container).
  - Added **`Clamp Inside Primary`** (`ButtonClampToPrimaryBounds` in `PanelLayoutTransform`: normal click or **`Alt+Shift+'`** clamps secondary selected transforms' bounding boxes inside the primary selection's world bounding box; `Shift`-click clamps origins only).
  - Added automated unit test `TestArrangeCylinderPyramidAndClampToBox` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 83: Select Far Outlier Transforms (`SelectOutlierTransforms` / `Ctrl+Shift+Y`) & 2D UI Circular / Radial Menu Arrangement (`ArrangeSelectedUserInterfacesInCircle` / `ButtonUICircleArrange`)
- [x] **83.1. Scene Bounds Audit: Select Far Outlier Transforms (`SelectOutlierTransforms` / `Ctrl+Shift+Y`)**
  - Implemented `TDesignFrame.SelectOutlierTransforms(MinDistance)`: selects all visible, unlocked `TCastleTransform` instances whose world distance from the active selection pivot (or world origin `(0, 0, 0)` when nothing is selected) exceeds `MinDistance` (`100.0` units on normal click or **`Ctrl+Shift+Y`**, `500.0` units on `Shift`-click) to immediately find stray or accidentally dragged transforms far outside the level.
  - Bound to **`Ctrl+Shift+Y`** in both the Viewport and Hierarchy Tree, plus **`Select Far Outlier Transforms (Ctrl+Shift+Y)`** (`MenuTreeViewItemSelectOutliers`) in `MenuTreeView`.
- [x] **83.2. 2D UI Circular / Radial Menu Dial Arrangement (`ArrangeSelectedUserInterfacesInCircle` / `ButtonUICircleArrange`)**
  - Implemented `TDesignFrame.ArrangeSelectedUserInterfacesInCircle(RadiusScale, HalfArc)` and added **`UI Circle / Dial`** (`ButtonUICircleArrange`) to `PanelLayoutUI`, arranging 2+ selected `TCastleUserInterface` controls evenly around a 2D circle (or $180^\circ$ upper semicircle arc when `Ctrl`-clicked, or $1.5\times$ radius when `Shift`-clicked) around their shared screen-space center.

### Phase 84: 3D Conical / Funnel Shell Arrangement (`ArrangeSelectedOnCone` / `Alt+Shift+\``)
- [x] **84.1. Fibonacci Conical & Frustum Shell Distribution (`TCastleTransformManipulate.ArrangeSelectedOnCone`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedOnCone(BaseRadius, TopRadius, HeightSpan, OrientMode): Boolean`: distributes 2+ top-level selected transforms across the lateral surface of a 3D cone (`TopRadius = 0`) or truncated frustum / funnel (`TopRadius > 0`) centered at the active selection pivot using the golden-angle spiral lattice ($\theta_i = i \cdot \pi(3 - \sqrt{5}), \; r(t_i) = \operatorname{Lerp}(t_i, R_{\text{base}}, R_{\text{top}}), \; y_i = C_y + (t_i - 0.5) H$) with `OrientMode` (`0` = keep rotation, `1` = orient horizontally outward from cone axis, `2` = orient horizontally inward toward cone axis).
  - Added **`Cone / Funnel...`** (`ButtonArrangeCone` in `PanelLayoutTransform`: normal click arranges on a pointed cone shell; `Ctrl`-click also orients outward; `Shift`-click opens the custom cone/frustum dialog) and `ShowArrangeOnConeDialog` bound to **`Alt+Shift+\``** in both the Viewport and Hierarchy Tree.

### Phase 85: 3D Hexagonal / Honeycomb Lattice Grid Arrangement (`ArrangeSelectedInHexGrid` / `Ctrl+Alt+H`)
- [x] **85.1. Staggered Honeycomb XZ Lattice Distribution (`TCastleTransformManipulate.ArrangeSelectedInHexGrid`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInHexGrid(Columns, CellRadius, OrientMode): Boolean`: arranges 2+ top-level selected transforms into a staggered hexagonal / honeycomb grid on the horizontal XZ plane centered around the active selection pivot, where pointy-top hex cells of circumradius $R$ have horizontal column step $\Delta X = \sqrt{3} R$, vertical row step $\Delta Z = 1.5 R$, and odd-row horizontal stagger $+0.5 \Delta X$, with `OrientMode` (`0` = keep rotation, `1` = orient horizontally outward from grid center, `2` = orient horizontally inward toward grid center).
  - Added **`Hex Grid Arrange`** (`ButtonArrangeHexGrid` in `PanelLayoutTransform`: normal click arranges in a hex grid; `Ctrl`-click also orients outward; `Shift`-click opens the custom hex grid dialog) and `ShowArrangeInHexGridDialog` bound to **`Ctrl+Alt+H`** in both the Viewport and Hierarchy Tree.

### Phase 86: Push Apart / Repel Selected Transforms Outside 3D Box or Primary Selection Bounds (`PushSelectedOutsideBox` / `PushSelectedOutsidePrimaryBounds` / `Ctrl+Alt+B`)
- [x] **86.1. Shortest-Axis Exclusion Zone Repulsion (`TCastleTransformManipulate.PushSelectedOutsideBox`, `PushSelectedOutsidePrimaryBounds`)**
  - Implemented `TCastleTransformManipulate.PushSelectedOutsideBox(BoxMin, BoxMax, UseObjectBounds): Boolean` and `TCastleTransformManipulate.PushSelectedOutsidePrimaryBounds(UseObjectBounds): Boolean`: pushes top-level selected transforms whose `WorldBoundingBox` (`UseObjectBounds = true`) or world origin (`UseObjectBounds = false`) intersects an exclusion box `[BoxMin, BoxMax]` or the primary selected transform's `WorldBoundingBox` (`Selected[0]`) out to the nearest face (`-X`, `+X`, `-Y`, `+Y`, `-Z`, or `+Z`) along the axis of minimum translation distance.
  - Added **`Push Outside Primary`** (`ButtonPushOutsidePrimaryBounds` in `PanelLayoutTransform`: normal click or **`Ctrl+Alt+B`** pushes secondary selected transforms' bounding boxes outside the primary selection's world bounding box; `Shift`-click pushes origins only).
  - Added automated unit test `TestArrangeConeHexGridAndPushOutsideBox` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 87: Select Components With Missing / Broken Asset URL (`SelectTransformsWithMissingUrl` / `Ctrl+Shift+Q`) & 2D UI Aspect-Preserving Fit Inside Parent (`FitSelectedUserInterfacesMaintainAspect` / `ButtonUIFitAspect`)
- [x] **87.1. Asset Integrity Audit: Select Components With Missing / Broken Asset URL (`SelectTransformsWithMissingUrl` / `Ctrl+Shift+Q`)**
  - Implemented `TDesignFrame.SelectTransformsWithMissingUrl(BrokenOnly)`: inspects all unlocked components in the hierarchy that publish a `Url` property (such as `TCastleScene`, `TCastleTransformDesign`, `TCastleImageControl`, `TCastleDesign`, `TCastleSound`) and selects those whose `Url` is empty (`not BrokenOnly`) or points to a non-existent file (`not URIFileExists(AssetUrl)`).
  - Bound to **`Ctrl+Shift+Q`** in both the Viewport and Hierarchy Tree, plus **`Select Components With Missing / Broken Asset URL (Ctrl+Shift+Q)`** (`MenuTreeViewItemSelectMissingUrl`) in `MenuTreeView` (`Shift`-click selects broken non-empty URLs only).
- [x] **87.2. 2D UI Letterboxed / Aspect-Preserving Fit Inside Parent (`FitSelectedUserInterfacesMaintainAspect` / `ButtonUIFitAspect`)**
  - Implemented `TDesignFrame.FitSelectedUserInterfacesMaintainAspect(CoverParent)` and added **`UI Fit Aspect`** (`ButtonUIFitAspect`) to `PanelLayoutUI`, scaling and centering 1+ selected `TCastleUserInterface` controls inside their parent container while preserving their current `Width:Height` aspect ratio (**Click**: letterbox / contain using `Min(ParW/CurW, ParH/CurH)`; **`Shift`-click**: cover parent using `Max(ParW/CurW, ParH/CurH)`).

### Phase 88: 3D Cubic / Hollow Frame Lattice & Shell Arrangement (`ArrangeSelectedOnCubeFrame` / `Ctrl+Alt+F`)
- [x] **88.1. 12-Edge Wireframe Box & 6-Face Hollow Shell Distribution (`TCastleTransformManipulate.ArrangeSelectedOnCubeFrame`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedOnCubeFrame(HalfExtents, ShellMode, OrientMode): Boolean`: distributes 2+ top-level selected transforms along the 12 wireframe edges and 8 corner vertices of a 3D box with half-extents `HalfExtents` around the active selection pivot (`ShellMode = false`), or across the 6 outer boundary faces of a $K \times K \times K$ hollow cubic lattice (`ShellMode = true`), with `OrientMode` (`0` = keep rotation, `1` = orient outward from cube center, `2` = orient inward toward cube center).
  - Added **`Cube Frame...`** (`ButtonArrangeCubeFrame` in `PanelLayoutTransform`: normal click arranges along the 12 wireframe edges; `Ctrl`-click arranges across the 6 hollow shell faces; `Shift`-click opens the custom dialog) and `ShowArrangeOnCubeFrameDialog` bound to **`Ctrl+Alt+F`** in both the Viewport and Hierarchy Tree.

### Phase 89: 3D Phyllotaxis Paraboloid Dish / Bowl Arrangement (`ArrangeSelectedInParaboloidBowl` / `Ctrl+Alt+P`)
- [x] **89.1. Golden-Angle Paraboloid Dish / Crater Distribution (`TCastleTransformManipulate.ArrangeSelectedInParaboloidBowl`)**
  - Implemented `TCastleTransformManipulate.ArrangeSelectedInParaboloidBowl(RimRadius, DepthY, OrientMode): Boolean`: distributes 2+ top-level selected transforms in a 3D paraboloid dish / bowl / crater (or inverted dome when `DepthY < 0`) centered at the active selection pivot using a sunflower golden-angle Phyllotaxis spiral ($u_i = (i + 0.5)/N, \; r_i = R\sqrt{u_i}, \; \theta_i = i\phi_{\text{golden}}, \; y_i = C_y + D_y(u_i - 0.5)$) with analytical paraboloid surface-normal orientation (`OrientMode = 1`) or horizontal inward orientation (`OrientMode = 2`).
  - Added **`Bowl / Dish...`** (`ButtonArrangeBowl` in `PanelLayoutTransform`: normal click arranges in a paraboloid bowl; `Ctrl`-click also orients along the concave dish surface normal; `Shift`-click opens the custom dialog) and `ShowArrangeInParaboloidBowlDialog` bound to **`Ctrl+Alt+P`** in both the Viewport and Hierarchy Tree.

### Phase 90: Snap / Project Selected Transforms Onto Nearest Face of 3D Box or Primary Selection Bounds (`SnapSelectedToBoxSurface` / `SnapSelectedToPrimaryBoundsSurface` / `Ctrl+Alt+M`)
- [x] **90.1. 6-Face Box Surface Projection & Outward Normal Alignment (`TCastleTransformManipulate.SnapSelectedToBoxSurface`, `SnapSelectedToPrimaryBoundsSurface`)**
  - Implemented `TCastleTransformManipulate.SnapSelectedToBoxSurface(BoxMin, BoxMax, FlushOutside, OrientOutward): Boolean` and `TCastleTransformManipulate.SnapSelectedToPrimaryBoundsSurface(FlushOutside, OrientOutward): Boolean`: snaps each top-level selected transform (or secondary selected transforms `Selected[1..N-1]` relative to `Selected[0].WorldBoundingBox`) onto the nearest of the 6 outer box faces ($\pm X, \pm Y, \pm Z$), clamping its two tangential coordinates to the face bounds, offsetting its normal coordinate outward by its own bounding-box half-extent when `FlushOutside = true`, and optionally rotating it to face along the outward face normal when `OrientOutward = true`.
  - Added **`Snap Primary Face`** (`ButtonSnapToPrimarySurface` in `PanelLayoutTransform`: normal click or **`Ctrl+Alt+M`** snaps secondary selected transforms flush onto the nearest outer face of the primary selection; `Shift`-click snaps origins onto the face; `Ctrl`-click also orients outward along the face normal).
  - Added automated unit test `TestArrangeCubeFrameParaboloidBowlAndSnapToBoxSurface` in `tests/code/testcases/testcastletransformmanipulate.pas`.

### Phase 91: Select Co-Located / Duplicate-Position Transforms (`SelectDuplicatePositionTransforms` / `Ctrl+Shift+I`) & 2D UI Snap To Nearest Parent Edge / Corner (`SnapSelectedUserInterfacesToParentEdge` / `ButtonUISnapParentEdge`)
- [x] **91.1. Co-Located Duplicate Audit: Select Duplicate-Position Transforms (`SelectDuplicatePositionTransforms` / `Ctrl+Shift+I`)**
  - Implemented `TDesignFrame.SelectDuplicatePositionTransforms(SameClassOnly, Tolerance)`: scans all visible, unlocked `TCastleTransform` instances and selects any later transform(s) that occupy the exact same world position (within `Tolerance = 0.01` units) as an earlier sibling/scene transform while leaving the first original unselected so pressing `Delete` immediately cleans up accidental double-pasted or double-duplicated objects.
  - Bound to **`Ctrl+Shift+I`** in both the Viewport and Hierarchy Tree, plus **`Select Co-Located / Duplicate-Position Transforms (Ctrl+Shift+I)`** (`MenuTreeViewItemSelectDuplicatePos`) in `MenuTreeView` (`Shift`-click restricts to identical component classes only).
- [x] **91.2. 2D UI Snap To Nearest Parent Edge / Corner (`SnapSelectedUserInterfacesToParentEdge` / `ButtonUISnapParentEdge`)**
  - Implemented `TDesignFrame.SnapSelectedUserInterfacesToParentEdge(SnapCorner, MarginPx)` and added **`UI Snap Edge`** (`ButtonUISnapParentEdge`) to `PanelLayoutUI`, snapping 1+ selected `TCastleUserInterface` controls flush against the nearest of the 4 parent container edges (**Click**), nearest of the 4 parent corners (**`Shift`-click**), or nearest parent edge with a $16\text{ px}$ inset margin (**`Ctrl`-click**).
