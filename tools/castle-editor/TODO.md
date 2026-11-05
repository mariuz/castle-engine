## TODO

------------------------------------------------------------------------------
Lower priority:
OK if after 7.0 release:

* TCastleButton:
  - Simplify property names, just Color and UseColor and BackgroundImage, less usage of "Custom" prefix
  - Test a way to upgrade names in design files while doing above?

* *All* images from theme should also be customizable at the control level,
  and naming should be consistent.

* Visual inspector. designer etc. less important
    * DONE: Dragging UI: "Snap" snaps to the final value (invisible grid `Round(Val / Snap) * Snap` in `TDesignerLayer.Motion`, or hold `Shift` for relative step increments)
    * ? open last design in the project,
      ? open the only scene in the project, if only one exists
      for now, list of views is good solution.
    * DONE: after adding, keep previously selected still selected (hold `Shift` when adding a component in `TDesignFrame.AddComponent` to keep `ParentComponent` selected)

* Add components tab at the bottom, with large icon for each component

* Make files browser with features as planned.
    * allow dropping scenes/images on UI design - done, but show preview when dropping
    * on audio files, you can open them with `examples/audio/audio_player/` (should this be moved to tools directory? probably!)

* build tool integration:
    * DONE: Shorter compile output:
        * DONE: also do not show FPC "logo", do not repeat information about FPC version, Os/CPU 2 times, debug mode (`IsRedundantCompilerBannerLine` in `TAsynchronousProcess.Update`)
        * DONE: remove the "separator" lines (`TAsynchronousProcess.Start`, `TAsynchronousProcessQueue.Update`, and `TOutputList.AddSeparator`)
    * rerun generate-program each time? (mark them as some *DO NOT MODIFY THIS, THIS IS ONLY FOR LAZARUS* comment)
        Not really OK, in case we open program with hand-crafted program file.
        Maybe only auto-generate in castle-engine-output,
          before opening Lazarus,
          if lpr not yet present?
        Best: change to use planned CastleEngineConfig.pas unit,
          that is always auto-generated without warning.
          Do not overwrite lpr each time.
    * DONE: checkbox in menu for verbose output from the build tool (`MenuItemVerboseBuildTool` in `MenuItemRun`)
    * use machine-readble format format for communication with build tool and CastleLog when CASTLE_ENGINE_EDITOR_INSIDE=true

        Causes build tool some lines (e.g. in verbose fpc command line) to use special format, and actual program uses CastleLog that has special output (and always goes to console even on Windows)
        - Avoid xml tags here (would require quoting rest).
        - Just tags like Cge-output, bytes=xxx:
        - Cge-output,multiline,...
        - Cge-output, warning,...
        - bytes are always required and allow reliably waiting reading up to message end, without the need to quote/unquote it

    * DONE: Detect multiline logs and show as one list item in output that can be expanded, only category initially visible (`TMultilineOutputInfo` & `TOutputList.ToggleExpandItem` in `editorutils.pas` + `TProjectForm.ListOutputDblClick` in `formproject.pas`). E.g. useful for
      - "OpenGL Information" or
      - command-line of FPC in build tool verbose mode

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

* When something is anchored to top-right,
  resizing by dragging left border makes unpleasant visual effect.
  Weird resizing by dragging bottom border is OK.
  On GTK2, with LCL 1.8.0.

------------------------------------------------------------------------------
"castle-engine editor" improvements:

- Do not rebuild "castle-engine editor" when not needed. It seems we should compare generated lpi/lpk, and *do not* overwrite (to not change timestamp) when equal. This way Lazarus xxx.compiled files will work.

    Hm, risky. Lazarus will then not recompile when only editor_units changed.
