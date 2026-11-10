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

{ Discovery, filtering, camera bookmark navigation, Pre-Release Readiness
  Auditor reporting, and Markdown checklist export for spatial 3D & 2D
  design annotations (Phase 283 — UE 5.9 Spatial Review Parity). }
unit ToolDesignAnnotations;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleVectors, CastleColors, CastleClassUtils,
  CastleTransform, CastleUIControls, CastleViewport,
  CastleDesignAnnotations;

type
  { Flattened snapshot of a single 3D or 2D spatial review pin in a design. }
  TDesignAnnotationItemInfo = record
    Component: TComponent;
    ComponentName: String;
    Is3D: Boolean;
    Category: TDesignAnnotationCategory;
    Status: TDesignAnnotationStatus;
    Title: String;
    Author: String;
    Comment: String;
    Priority: Integer;
    ShowPinInViewport: Boolean;
    HasCameraBookmark: Boolean;
    WorldOrUiPos: TVector3;
    SummaryBadge: String;
  end;

  { Aggregated scan & audit report across all 3D and 2D review pins in a design. }
  TDesignAnnotationAuditReport = class
  public
    TotalPins: Integer;
    Pins3DCount: Integer;
    Pins2DCount: Integer;
    OpenCount: Integer;
    InProgressCount: Integer;
    ResolvedCount: Integer;
    UnresolvedBugCount: Integer;
    UnresolvedTodoCount: Integer;
    AiPromptCount: Integer;
    Bookmarked3DPins: Integer;
    Items: array of TDesignAnnotationItemInfo;
    AuditWarnings: TStringList;

    constructor Create;
    destructor Destroy; override;
    function FormatMarkdownChecklist(const DesignName: String = ''): String;
  end;

  { Stateless scanner, factory, and batch-action helper for spatial review pins. }
  TDesignAnnotationManager = class
  public
    { Recursively scan @code(RootComp) for all @link(TCastleDesignAnnotation)
      and @link(TCastleDesignAnnotationUi) instances, sorted by unresolved status
      first and then descending @code(Priority). }
    class function ScanDesign(const RootComp: TComponent): TDesignAnnotationAuditReport;

    { Test whether @code(Item) matches UI filter criteria.
      @param(CategoryFilter -1 for All, or @code(Ord(TDesignAnnotationCategory)).)
      @param(StatusFilter -1 for All, -2 for Unresolved Only (@code(Open + InProgress)),
        or @code(Ord(TDesignAnnotationStatus)).) }
    class function MatchesFilter(const Item: TDesignAnnotationItemInfo;
      const CategoryFilter, StatusFilter: Integer;
      const SearchText: String): Boolean;

    { Spawn a new 3D @link(TCastleDesignAnnotation) inside @code(AVp.Items)
      positioned @code(ForwardDistance) units ahead of @code(AVp.InternalCamera)
      (or at origin if no camera is active), optionally capturing the camera bookmark. }
    class function Create3DPinInViewport(const AVp: TCastleViewport;
      const AOwner: TComponent;
      const ACategory: TDesignAnnotationCategory;
      const ATitle: String;
      const CaptureCamera: Boolean = true;
      const ForwardDistance: Single = 5.0): TCastleDesignAnnotation;

    { Spawn a new 2D @link(TCastleDesignAnnotationUi) inside @code(ParentUi). }
    class function Create2DPinInUi(const ParentUi: TCastleUserInterface;
      const AOwner: TComponent;
      const ACategory: TDesignAnnotationCategory;
      const ATitle: String): TCastleDesignAnnotationUi;

    { Jump @code(AVp.InternalCamera) to @code(Pin3D)'s saved camera bookmark, or
      frame @code(Pin3D)'s world position from a comfortable offset when no
      explicit camera bookmark was stored. }
    class function JumpViewportTo3DPin(const AVp: TCastleViewport;
      const Pin3D: TCastleDesignAnnotation): Boolean;

    { Mark all matching unresolved pins under @code(RootComp) as @code(dasResolved).
      Pass @code(OnlyCategory = -1) for all categories. Returns number of updated pins. }
    class function MarkAllResolved(const RootComp: TComponent;
      const OnlyCategory: Integer = -1): Integer;

    { Delete all @code(dasResolved) pins under @code(RootComp). Returns number deleted. }
    class function DeleteResolvedPins(const RootComp: TComponent): Integer;
  end;

implementation

uses
  Math, CastleUtils, CastleStringUtils;

function MakeUniqueComponentName(const AOwner: TComponent; const BasePrefix: String): String;
var
  Idx: Integer;
begin
  Idx := 1;
  repeat
    Result := BasePrefix + IntToStr(Idx);
    Inc(Idx);
  until (AOwner = nil) or (AOwner.FindComponent(Result) = nil);
end;

{ TDesignAnnotationAuditReport ----------------------------------------------- }

constructor TDesignAnnotationAuditReport.Create;
begin
  inherited;
  AuditWarnings := TStringList.Create;
end;

destructor TDesignAnnotationAuditReport.Destroy;
begin
  FreeAndNil(AuditWarnings);
  inherited;
end;

function TDesignAnnotationAuditReport.FormatMarkdownChecklist(
  const DesignName: String): String;
var
  SB: TStringBuilder;
  I: Integer;
  CheckMark, HeaderTitle, PosStr: String;
begin
  SB := TStringBuilder.Create;
  try
    if Trim(DesignName) <> '' then
      HeaderTitle := Trim(DesignName)
    else
      HeaderTitle := 'Active Design';
    SB.AppendLine('# Spatial Design Review Checklist — ' + HeaderTitle);
    SB.AppendLine('');
    SB.AppendLine(Format(
      '- **Total Pins:** %d (%d 3D, %d 2D) | **Open:** %d | **In Progress:** %d | **Resolved:** %d',
      [TotalPins, Pins3DCount, Pins2DCount, OpenCount, InProgressCount, ResolvedCount]));
    SB.AppendLine(Format(
      '- **Actionable Blockers:** %d Unresolved Bug(s), %d Unresolved TODO(s), %d AI Prompt(s)',
      [UnresolvedBugCount, UnresolvedTodoCount, AiPromptCount]));
    SB.AppendLine('');

    if Length(Items) = 0 then
      SB.AppendLine('_No spatial review pins in this design._')
    else
    begin
      SB.AppendLine('## Review Pins');
      for I := 0 to High(Items) do
      begin
        if Items[I].Status = dasResolved then
          CheckMark := 'x'
        else
          CheckMark := ' ';
        if Items[I].Is3D then
          PosStr := Format('3D (%.2f, %.2f, %.2f)',
            [Items[I].WorldOrUiPos.X, Items[I].WorldOrUiPos.Y, Items[I].WorldOrUiPos.Z])
        else
          PosStr := Format('2D UI (%.0f, %.0f)',
            [Items[I].WorldOrUiPos.X, Items[I].WorldOrUiPos.Y]);

        SB.AppendLine(Format('- [%s] **[%s | P%d | %s]** `%s` — **%s** _(%s)_',
          [CheckMark,
           DesignAnnotationCategoryTag(Items[I].Category),
           Items[I].Priority,
           DesignAnnotationStatusDisplayName(Items[I].Status),
           Items[I].ComponentName,
           Items[I].Title,
           PosStr]));
        if Trim(Items[I].Author) <> '' then
          SB.AppendLine('  - Author: `' + Trim(Items[I].Author) + '`');
        if Trim(Items[I].Comment) <> '' then
          SB.AppendLine('  - Note: ' + Trim(Items[I].Comment));
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

{ TDesignAnnotationManager --------------------------------------------------- }

class function TDesignAnnotationManager.ScanDesign(
  const RootComp: TComponent): TDesignAnnotationAuditReport;
var
  FoundList: TList;

  procedure Walk(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    CC: TCastleComponent;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then
      Exit;

    if (C is TCastleDesignAnnotation) or (C is TCastleDesignAnnotationUi) then
      if FoundList.IndexOf(C) = -1 then
        FoundList.Add(C);

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Walk(CC.NonVisualComponents[I]);
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Walk(T[I]);
    end else
    if C is TCastleViewport then
    begin
      for I := 0 to TCastleViewport(C).ControlsCount - 1 do
        Walk(TCastleViewport(C).Controls[I]);
      Walk(TCastleViewport(C).Items);
    end else
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Walk(UI.Controls[I]);
    end;
  end;

  function SortRank(const Info: TDesignAnnotationItemInfo): Integer;
  begin
    { Unresolved Bugs & TODOs sort highest, Resolved sort lowest }
    if Info.Status = dasResolved then
      Result := 0
    else
      Result := 100 + Info.Priority * 10 + Ord(Info.Category = dacBug) * 5;
  end;

var
  I, J: Integer;
  Comp: TComponent;
  Pin3D: TCastleDesignAnnotation;
  Pin2D: TCastleDesignAnnotationUi;
  Info, TempInfo: TDesignAnnotationItemInfo;
begin
  Result := TDesignAnnotationAuditReport.Create;
  if RootComp = nil then
    Exit;

  FoundList := TList.Create;
  try
    Walk(RootComp);
    Result.TotalPins := FoundList.Count;
    SetLength(Result.Items, FoundList.Count);

    for I := 0 to FoundList.Count - 1 do
    begin
      Comp := TComponent(FoundList[I]);
      Info := Default(TDesignAnnotationItemInfo);
      Info.Component := Comp;
      if Comp.Name <> '' then
        Info.ComponentName := Comp.Name
      else
        Info.ComponentName := Comp.ClassName;

      if Comp is TCastleDesignAnnotation then
      begin
        Pin3D := TCastleDesignAnnotation(Comp);
        Inc(Result.Pins3DCount);
        Info.Is3D := true;
        Info.Category := Pin3D.Category;
        Info.Status := Pin3D.Status;
        Info.Title := Pin3D.Title;
        Info.Author := Pin3D.Author;
        Info.Comment := Pin3D.Comment;
        Info.Priority := Pin3D.Priority;
        Info.ShowPinInViewport := Pin3D.ShowPinInViewport;
        Info.HasCameraBookmark := Pin3D.HasCameraBookmark;
        if Pin3D.HasWorldTransform then
          Info.WorldOrUiPos := Pin3D.WorldTranslation
        else
          Info.WorldOrUiPos := Pin3D.Translation;
        Info.SummaryBadge := Pin3D.PinSummaryBadge;
        if Pin3D.HasCameraBookmark then
          Inc(Result.Bookmarked3DPins);
      end else
      begin
        Pin2D := TCastleDesignAnnotationUi(Comp);
        Inc(Result.Pins2DCount);
        Info.Is3D := false;
        Info.Category := Pin2D.Category;
        Info.Status := Pin2D.Status;
        Info.Title := Pin2D.Title;
        Info.Author := Pin2D.Author;
        Info.Comment := Pin2D.Comment;
        Info.Priority := Pin2D.Priority;
        Info.ShowPinInViewport := Pin2D.ShowPinInViewport;
        Info.HasCameraBookmark := false;
        Info.WorldOrUiPos := Vector3(Pin2D.Translation.X, Pin2D.Translation.Y, 0);
        Info.SummaryBadge := Pin2D.PinSummaryBadge;
      end;

      case Info.Status of
        dasOpen:       Inc(Result.OpenCount);
        dasInProgress: Inc(Result.InProgressCount);
        dasResolved:   Inc(Result.ResolvedCount);
      end;

      if Info.Category = dacAiPrompt then
        Inc(Result.AiPromptCount);

      if Info.Status <> dasResolved then
      begin
        if Info.Category = dacBug then
        begin
          Inc(Result.UnresolvedBugCount);
          Result.AuditWarnings.Add(Format(
            'Unresolved [BUG] Review Pin "%s" (%s, P%d): %s',
            [Info.ComponentName, DesignAnnotationStatusDisplayName(Info.Status),
             Info.Priority, Info.Title]));
        end else
        if Info.Category = dacTodo then
        begin
          Inc(Result.UnresolvedTodoCount);
          Result.AuditWarnings.Add(Format(
            'Unresolved [TODO] Review Pin "%s" (%s, P%d): %s',
            [Info.ComponentName, DesignAnnotationStatusDisplayName(Info.Status),
             Info.Priority, Info.Title]));
        end;
      end;

      Result.Items[I] := Info;
    end;

    for I := 0 to High(Result.Items) - 1 do
      for J := I + 1 to High(Result.Items) do
        if SortRank(Result.Items[J]) > SortRank(Result.Items[I]) then
        begin
          TempInfo := Result.Items[I];
          Result.Items[I] := Result.Items[J];
          Result.Items[J] := TempInfo;
        end;
  finally
    FreeAndNil(FoundList);
  end;
end;

class function TDesignAnnotationManager.MatchesFilter(
  const Item: TDesignAnnotationItemInfo;
  const CategoryFilter, StatusFilter: Integer;
  const SearchText: String): Boolean;
var
  Needle, Haystack: String;
begin
  if (CategoryFilter >= 0) and (Ord(Item.Category) <> CategoryFilter) then
    Exit(false);

  if StatusFilter = -2 then
  begin
    if Item.Status = dasResolved then
      Exit(false);
  end else
  if (StatusFilter >= 0) and (Ord(Item.Status) <> StatusFilter) then
    Exit(false);

  Needle := LowerCase(Trim(SearchText));
  if Needle <> '' then
  begin
    Haystack := LowerCase(Item.ComponentName + ' ' + Item.Title + ' ' +
      Item.Author + ' ' + Item.Comment + ' ' +
      DesignAnnotationCategoryDisplayName(Item.Category));
    if Pos(Needle, Haystack) = 0 then
      Exit(false);
  end;

  Result := true;
end;

class function TDesignAnnotationManager.Create3DPinInViewport(
  const AVp: TCastleViewport; const AOwner: TComponent;
  const ACategory: TDesignAnnotationCategory; const ATitle: String;
  const CaptureCamera: Boolean; const ForwardDistance: Single): TCastleDesignAnnotation;
var
  Cam: TCastleTransform;
  CamPos, CamDir, CamUp: TVector3;
begin
  Result := nil;
  if (AVp = nil) or (AVp.Items = nil) then
    Exit;

  Result := TCastleDesignAnnotation.Create(AOwner);
  Result.Name := MakeUniqueComponentName(AOwner, 'ReviewPin');
  Result.Category := ACategory;
  if Trim(ATitle) <> '' then
    Result.Title := Trim(ATitle)
  else
    Result.Title := DesignAnnotationCategoryDisplayName(ACategory) + ' Pin';

  Cam := AVp.InternalCamera;
  if Cam = nil then
    Cam := AVp.Camera;

  if Cam <> nil then
  begin
    Cam.GetWorldView(CamPos, CamDir, CamUp);
    if CamDir.IsZero then
      CamDir := Vector3(0, 0, -1)
    else
      CamDir := CamDir.Normalize;
    Result.Translation := CamPos + CamDir * Max(0.5, ForwardDistance);
    if CaptureCamera then
      Result.SetCameraBookmark(CamPos, CamDir, CamUp);
  end;

  AVp.Items.Add(Result);
end;

class function TDesignAnnotationManager.Create2DPinInUi(
  const ParentUi: TCastleUserInterface; const AOwner: TComponent;
  const ACategory: TDesignAnnotationCategory;
  const ATitle: String): TCastleDesignAnnotationUi;
begin
  Result := nil;
  if ParentUi = nil then
    Exit;

  Result := TCastleDesignAnnotationUi.Create(AOwner);
  Result.Name := MakeUniqueComponentName(AOwner, 'UiReviewPin');
  Result.Category := ACategory;
  if Trim(ATitle) <> '' then
    Result.Title := Trim(ATitle)
  else
    Result.Title := DesignAnnotationCategoryDisplayName(ACategory) + ' Pin';
  Result.Anchor(hpMiddle, 0);
  Result.Anchor(vpMiddle, 0);
  ParentUi.InsertFront(Result);
end;

class function TDesignAnnotationManager.JumpViewportTo3DPin(
  const AVp: TCastleViewport; const Pin3D: TCastleDesignAnnotation): Boolean;
var
  Cam: TCastleTransform;
  PinWorld, CamPos, CamDir, CamUp, NewDir: TVector3;
begin
  Result := false;
  if (AVp = nil) or (Pin3D = nil) then
    Exit;

  Cam := AVp.InternalCamera;
  if Cam = nil then
    Cam := AVp.Camera;
  if Cam = nil then
    Exit;

  if Pin3D.HasCameraBookmark then
    Exit(Pin3D.ApplyCameraTo(Cam));

  { Fallback when no explicit camera bookmark was stored: frame the pin from 5m back }
  if Pin3D.HasWorldTransform then
    PinWorld := Pin3D.WorldTranslation
  else
    PinWorld := Pin3D.Translation;

  Cam.GetWorldView(CamPos, CamDir, CamUp);
  if CamDir.IsZero then
    NewDir := Vector3(0, -0.25, -1).Normalize
  else
    NewDir := CamDir.Normalize;
  if CamUp.IsZero then
    CamUp := Vector3(0, 1, 0);
  Cam.SetWorldView(PinWorld - NewDir * 5.0, NewDir, CamUp);
  Result := true;
end;

class function TDesignAnnotationManager.MarkAllResolved(
  const RootComp: TComponent; const OnlyCategory: Integer): Integer;
var
  Report: TDesignAnnotationAuditReport;
  I: Integer;
begin
  Result := 0;
  Report := ScanDesign(RootComp);
  try
    for I := 0 to High(Report.Items) do
    begin
      if (Report.Items[I].Status <> dasResolved) and
         ((OnlyCategory < 0) or (Ord(Report.Items[I].Category) = OnlyCategory)) then
      begin
        if Report.Items[I].Component is TCastleDesignAnnotation then
          TCastleDesignAnnotation(Report.Items[I].Component).Status := dasResolved
        else if Report.Items[I].Component is TCastleDesignAnnotationUi then
          TCastleDesignAnnotationUi(Report.Items[I].Component).Status := dasResolved;
        Inc(Result);
      end;
    end;
  finally
    FreeAndNil(Report);
  end;
end;

class function TDesignAnnotationManager.DeleteResolvedPins(
  const RootComp: TComponent): Integer;
var
  Report: TDesignAnnotationAuditReport;
  I: Integer;
  C: TComponent;
begin
  Result := 0;
  Report := ScanDesign(RootComp);
  try
    for I := 0 to High(Report.Items) do
      if Report.Items[I].Status = dasResolved then
      begin
        C := Report.Items[I].Component;
        if C <> nil then
        begin
          FreeAndNil(C);
          Inc(Result);
        end;
      end;
  finally
    FreeAndNil(Report);
  end;
end;

end.
