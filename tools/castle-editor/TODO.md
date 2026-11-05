## TODO

------------------------------------------------------------------------------
Lower priority:
OK if after 7.0 release:

* DONE: TCastleButton & control-level theme/background skinning:
  - Configured via `ShowNineSliceSetupDialog` / `ApplyNineSliceSetup` and `ShowUiThemePaletteDialog` in `framedesign.pas` (`CustomBackground`, `CustomBackgroundNormal/Pressed/Focused/Disabled`, `ProtectedSides`, `CustomColorNormal/Focused/Pressed/Disabled`, `CustomTextColor`, plus `TCastleEdit`, `TCastleCheckbox`, `TCastleImageControl`, and `TCastleRectangleControl` skin presets).

* DONE: Visual inspector. designer etc. less important
    * DONE: Dragging UI: "Snap" snaps to the final value (invisible grid `Round(Val / Snap) * Snap` in `TDesignerLayer.Motion`, or hold `Shift` for relative step increments)
    * DONE: open last design in the project (`ProjectForm_LastDesignUrl_<ProjectName>`), or open the only view design in the project if only one exists (`TProjectForm.OpenProject`)
    * DONE: after adding, keep previously selected still selected (hold `Shift` when adding a component in `TDesignFrame.AddComponent` to keep `ParentComponent` selected)

* DONE: Add components tab at the bottom, with large icon for each component (`TabComponents` / `CreateComponentsPaletteTab` in `formproject.pas`)

* DONE: Make files browser with features as planned.
    * DONE: allow dropping scenes/images on UI design - done, and show live preview overlay & target highlight when dropping (`CastleControlDragOver` / `TDesignerLayer.Render` in `framedesign.pas`)
    * DONE: on audio files, you can open them with `castle-audio-player` if present or toggle in-editor loop/playback with live `Playing: Offset / Duration` display (`TViewFileFrame.TogglePlaySound` & `TProjectForm.ShellListViewDoubleClick`)

* DONE: build tool integration:
    * DONE: Shorter compile output:
        * DONE: also do not show FPC "logo", do not repeat information about FPC version, Os/CPU 2 times, debug mode (`IsRedundantCompilerBannerLine` in `TAsynchronousProcess.Update`)
        * DONE: remove the "separator" lines (`TAsynchronousProcess.Start`, `TAsynchronousProcessQueue.Update`, and `TOutputList.AddSeparator`)
    * DONE: auto-generate missing `.lpi`/`.lpr` or `.dproj` before opening Lazarus/Delphi without overwriting existing `.lpr` files (`AutoGenerateProgramIfMissing` in `TProjectForm.ActionOpenProjectCodeExecute`)
    * DONE: checkbox in menu for verbose output from the build tool (`MenuItemVerboseBuildTool` in `MenuItemRun`)
    * DONE: use machine-readable `Cge-output,` format and `CASTLE_ENGINE_EDITOR_INSIDE=true` for communication with build tool and `CastleLog` (`InitializeLog` in `castlelog.pas`, `TAsynchronousProcess.Start` / `ParseStructuredLine` / `IsVerboseFpcCommandLine` in `editorutils.pas`)
    * DONE: Detect multiline logs and show as one list item in output that can be expanded, only category initially visible (`TMultilineOutputInfo` & `TOutputList.ToggleExpandItem` in `editorutils.pas` + `TProjectForm.ListOutputDblClick` in `formproject.pas`). E.g. useful for
      - "OpenGL Information" or
      - command-line of FPC in build tool verbose mode (`[+] FPC Command Line (N lines, double-click to expand)`)

* DONE: small GUI stuff:
    * DONE: on NewProject form AutoSize (`TNewProjectForm.FormShow.AdjustFormSize` dynamically sizes `ClientWidth` and `ClientHeight`)
    * DONE: allow configuring command output "word wrap" (`TOutputList.WordWrap` & `MenuItemOutputWordWrap` in `OutputPopup`)
    * DONE: Output ListBox has some width (and horiz scrollbar) on Windows (`ScrollWidth = 0` in `formproject.lfm` + dynamic `FMaxLineWidth` tracking in `TOutputList`)

* DONE: Project options:
    * DONE: Allow to configure project qualified name from "Project Options" in editor (`Project -> Project Options (CastleEngineManifest.xml)...`)
    * DONE: Icon, other stuff (`caption`, `author`, `version`, `screen_orientation`, `fullscreen_immersive`, `<icons><icon path="..."/></icons>`) from `CastleEngineManifest.xml` configurable in editor (`TProjectForm.ShowProjectOptionsDialog`)

* DONE: at scene loading show something "wait, loading..." (`TViewFileFrame.LoadScene` sets `LabelInformation.Caption := 'Wait, loading...'` and `Screen.Cursor := crHourGlass`)

* DONE: allow to import file with textures, audio, inline tracked
  as alternative at warning message when opening file outside of castle-data: (`WarningOrImportIfOutsideDataDirectory` & `TSceneDependencyCopyHelper` in `src/lcl/castledialogs.pas`)

* DONE: When something is anchored to top-right,
  resizing by dragging left border makes unpleasant visual effect — fixed in `TDesignerLayer.Motion.DragAllowed` (`framedesign.pas`) by scaling `Move * UI.UIScale`, adding 0.5 px sub-pixel parent tolerance, and checking only the actively dragged border edges during `dmResize`.

------------------------------------------------------------------------------
"castle-engine editor" improvements:

- DONE: Do not rebuild "castle-engine editor" when not needed (`TCastleProject.ExtractTemplateFile` in `toolproject.pas` avoids overwriting identical generated `.lpi`/`.lpk`/`.pas` files to preserve timestamps for `lazbuild` `.compiled` caches, while `TCastleProject.DoEditorRebuildIfNeeded` checks `Manifest.FindPascalFiles` timestamps and touches `castleeditorcustomcomponents.pas` whenever any project unit is newer).
