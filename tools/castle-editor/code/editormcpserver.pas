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

{ Bridge connecting @link(TCastleMcpServer) to Castle Game Engine Editor's
  @link(TProjectForm), @link(TDesignFrame), Undo system, viewport screenshot
  capture, and asynchronous build output log. }
unit EditorMcpServer;

{$I castleconf.inc}

interface

uses Classes, SysUtils,
  CastleImages, ToolMcpServer;

type
  { LCL editor host bridge for @link(TCastleMcpServer). }
  TEditorMcpBridge = class(TComponent)
  strict private
    FServer: TCastleMcpServer;
    FProjectForm: TComponent;
    procedure HandleGetDesignInfo(out ADesignRoot, ADesignOwner: TComponent;
      out ADesignUrl: String; out ADesignModified: Boolean);
    function HandleAddComponent(const ParentComponent: TComponent;
      const ComponentClass: TComponentClass; const ComponentOnCreate: TNotifyEvent;
      const BaseName: String): TComponent;
    function HandleDeleteComponent(const TargetComponent: TComponent;
      out ErrorReason: String): Boolean;
    procedure HandleAfterModify(const UndoComment: String);
    function HandleUndoRedo(const IsRedo: Boolean;
      out ExecutedComment: String): Boolean;
    function HandleCaptureScreenshot: TRGBImage;
    procedure HandleGetBuildOutput(const MaxLines: Integer;
      const OutLines: TStrings; out WarningsCount, ErrorsCount: Integer);
    function HandleSaveDesign(out ErrorReason: String): Boolean;
    function HandleRunBuildCommand(const CommandName: String;
      out StatusMessage: String): Boolean;
    procedure HandleLogMessage(const MessageText: String);
  public
    constructor CreateForProjectForm(const AProjectForm: TComponent);
    destructor Destroy; override;

    procedure LoadFromConfig;
    procedure ApplyAutonomyMode(const AMode: TMcpAutonomyMode;
      const PersistConfig: Boolean = true);
    procedure ApplyPort(const APort: Word;
      const PersistConfig: Boolean = true);
    procedure ApplyAuthToken(const AToken: String;
      const PersistConfig: Boolean = true);
    function StatusSummary: String;

    property Server: TCastleMcpServer read FServer;
  end;

implementation

uses Math,
  CastleConfig, CastleUtils, CastleTransform, CastleViewport,
  EditorUtils, FrameDesign, FormProject;

constructor TEditorMcpBridge.CreateForProjectForm(const AProjectForm: TComponent);
begin
  inherited Create(AProjectForm);
  FProjectForm := AProjectForm;
  FServer := TCastleMcpServer.Create(Self);
  FServer.OnGetDesignInfo := {$ifdef FPC}@{$endif} HandleGetDesignInfo;
  FServer.OnAddComponent := {$ifdef FPC}@{$endif} HandleAddComponent;
  FServer.OnDeleteComponent := {$ifdef FPC}@{$endif} HandleDeleteComponent;
  FServer.OnAfterModify := {$ifdef FPC}@{$endif} HandleAfterModify;
  FServer.OnUndoRedo := {$ifdef FPC}@{$endif} HandleUndoRedo;
  FServer.OnCaptureScreenshot := {$ifdef FPC}@{$endif} HandleCaptureScreenshot;
  FServer.OnGetBuildOutput := {$ifdef FPC}@{$endif} HandleGetBuildOutput;
  FServer.OnSaveDesign := {$ifdef FPC}@{$endif} HandleSaveDesign;
  FServer.OnRunBuildCommand := {$ifdef FPC}@{$endif} HandleRunBuildCommand;
  FServer.OnLogMessage := {$ifdef FPC}@{$endif} HandleLogMessage;
end;

destructor TEditorMcpBridge.Destroy;
begin
  if FServer <> nil then
    FServer.StopListening;
  inherited;
end;

procedure TEditorMcpBridge.LoadFromConfig;
var
  SavedPort: Integer;
  SavedToken: String;
  SavedMode: TMcpAutonomyMode;
begin
  SavedPort := Clamped(
    UserConfig.GetValue('Mcp_Port', Integer(TCastleMcpServer.DefaultMcpPort)),
    1024, 65535);
  SavedToken := UserConfig.GetValue('Mcp_AuthToken', '');
  SavedMode := StringToMcpAutonomyMode(
    UserConfig.GetValue('Mcp_AutonomyMode', 'disabled'), mamDisabled);

  FServer.AuthToken := SavedToken;
  ApplyPort(Word(SavedPort), false);
  ApplyAutonomyMode(SavedMode, false);
end;

procedure TEditorMcpBridge.ApplyAutonomyMode(const AMode: TMcpAutonomyMode;
  const PersistConfig: Boolean);
begin
  FServer.AutonomyMode := AMode;
  if AMode = mamDisabled then
    FServer.StopListening
  else
    FServer.StartListening;

  if PersistConfig then
  begin
    UserConfig.SetValue('Mcp_AutonomyMode', McpAutonomyModeToString(AMode));
    UserConfig.Save;
  end;
end;

procedure TEditorMcpBridge.ApplyPort(const APort: Word;
  const PersistConfig: Boolean);
begin
  if APort < 1024 then
    Exit;
  FServer.Port := APort;
  if PersistConfig then
  begin
    UserConfig.SetValue('Mcp_Port', Integer(APort));
    UserConfig.Save;
  end;
end;

procedure TEditorMcpBridge.ApplyAuthToken(const AToken: String;
  const PersistConfig: Boolean);
begin
  FServer.AuthToken := Trim(AToken);
  if PersistConfig then
  begin
    UserConfig.SetValue('Mcp_AuthToken', FServer.AuthToken);
    UserConfig.Save;
  end;
end;

function TEditorMcpBridge.StatusSummary: String;
begin
  if FServer.Listening then
    Result := Format('Listening on %s (%s, %d reqs)',
      [FServer.EndpointUrl, McpAutonomyModeToString(FServer.AutonomyMode),
       FServer.RequestsHandledCount])
  else
    Result := Format('Stopped (%s, port %d)',
      [McpAutonomyModeToString(FServer.AutonomyMode), FServer.Port]);
end;

procedure TEditorMcpBridge.HandleGetDesignInfo(
  out ADesignRoot, ADesignOwner: TComponent;
  out ADesignUrl: String; out ADesignModified: Boolean);
var
  D: TDesignFrame;
begin
  ADesignRoot := nil;
  ADesignOwner := nil;
  ADesignUrl := '';
  ADesignModified := false;
  if not (FProjectForm is TProjectForm) then Exit;
  D := TProjectForm(FProjectForm).McpGetDesignFrame;
  if D <> nil then
  begin
    ADesignRoot := D.DesignRoot;
    ADesignOwner := D.CurrentDesignOwner;
    ADesignUrl := D.DesignUrl;
    ADesignModified := D.DesignModified;
  end;
end;

function TEditorMcpBridge.HandleAddComponent(const ParentComponent: TComponent;
  const ComponentClass: TComponentClass; const ComponentOnCreate: TNotifyEvent;
  const BaseName: String): TComponent;
var
  D: TDesignFrame;
  EffectiveParent: TComponent;
begin
  Result := nil;
  if not (FProjectForm is TProjectForm) then Exit;
  D := TProjectForm(FProjectForm).McpGetDesignFrame;
  if D = nil then Exit;

  EffectiveParent := ParentComponent;
  if (EffectiveParent is TCastleViewport) and
     ComponentClass.InheritsFrom(TCastleTransform) then
    EffectiveParent := TCastleViewport(EffectiveParent).Items;

  try
    Result := D.AddComponent(EffectiveParent, ComponentClass,
      ComponentOnCreate, BaseName);
  except
    on E: Exception do
    begin
      HandleLogMessage('[MCP] AddComponent error: ' + E.Message);
      Result := nil;
    end;
  end;
end;

function TEditorMcpBridge.HandleDeleteComponent(
  const TargetComponent: TComponent; out ErrorReason: String): Boolean;
var
  D: TDesignFrame;
begin
  ErrorReason := 'No active design.';
  if not (FProjectForm is TProjectForm) then Exit(false);
  D := TProjectForm(FProjectForm).McpGetDesignFrame;
  if D = nil then Exit(false);
  Result := D.McpDeleteComponent(TargetComponent, ErrorReason);
end;

procedure TEditorMcpBridge.HandleAfterModify(const UndoComment: String);
var
  D: TDesignFrame;
begin
  if not (FProjectForm is TProjectForm) then Exit;
  D := TProjectForm(FProjectForm).McpGetDesignFrame;
  if D <> nil then
    D.RefreshAfterMcpModify(UndoComment);
end;

function TEditorMcpBridge.HandleUndoRedo(const IsRedo: Boolean;
  out ExecutedComment: String): Boolean;
var
  D: TDesignFrame;
begin
  ExecutedComment := '';
  if not (FProjectForm is TProjectForm) then Exit(false);
  D := TProjectForm(FProjectForm).McpGetDesignFrame;
  if D = nil then Exit(false);
  Result := D.McpUndoRedo(IsRedo, ExecutedComment);
end;

function TEditorMcpBridge.HandleCaptureScreenshot: TRGBImage;
var
  D: TDesignFrame;
begin
  Result := nil;
  if not (FProjectForm is TProjectForm) then Exit;
  D := TProjectForm(FProjectForm).McpGetDesignFrame;
  if D <> nil then
    Result := D.McpCaptureViewportImage;
end;

procedure TEditorMcpBridge.HandleGetBuildOutput(const MaxLines: Integer;
  const OutLines: TStrings; out WarningsCount, ErrorsCount: Integer);
var
  OutList: TOutputList;
  StartIdx, I: Integer;
begin
  WarningsCount := 0;
  ErrorsCount := 0;
  if not (FProjectForm is TProjectForm) then Exit;
  OutList := TProjectForm(FProjectForm).McpGetOutputList;
  if OutList = nil then Exit;
  WarningsCount := OutList.WarningsCount;
  ErrorsCount := OutList.ErrorsCount;
  if OutList.List <> nil then
  begin
    StartIdx := Max(0, OutList.List.Items.Count - MaxLines);
    for I := StartIdx to OutList.List.Items.Count - 1 do
      OutLines.Add(OutList.List.Items[I]);
  end;
end;

function TEditorMcpBridge.HandleSaveDesign(out ErrorReason: String): Boolean;
begin
  ErrorReason := 'Project form unavailable.';
  if not (FProjectForm is TProjectForm) then Exit(false);
  Result := TProjectForm(FProjectForm).McpSaveCurrentDesign(ErrorReason);
end;

function TEditorMcpBridge.HandleRunBuildCommand(const CommandName: String;
  out StatusMessage: String): Boolean;
begin
  StatusMessage := 'Project form unavailable.';
  if not (FProjectForm is TProjectForm) then Exit(false);
  Result := TProjectForm(FProjectForm).McpRunBuildCommand(CommandName, StatusMessage);
end;

procedure TEditorMcpBridge.HandleLogMessage(const MessageText: String);
var
  OutList: TOutputList;
begin
  if not (FProjectForm is TProjectForm) then Exit;
  OutList := TProjectForm(FProjectForm).McpGetOutputList;
  if OutList <> nil then
    OutList.AddLine(MessageText, okInfo);
end;

end.
