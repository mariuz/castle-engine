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

{ Embedded Model Context Protocol (MCP) JSON-RPC 2.0 server and scene/UI
  automation engine (@link(TCastleMcpServer)), allowing AI coding assistants
  (Claude Code, Cursor, VS Code, Antigravity) and external tools to inspect
  and edit live Castle Game Engine designs with configurable autonomy levels
  and Undo integration. }
unit ToolMcpServer;

{$I castleconf.inc}

interface

uses Classes, SysUtils, FpJson, FpHttpServer,
  CastleImages, CastleVectors;

type
  { Autonomy mode controlling which MCP tools external clients may execute. }
  TMcpAutonomyMode = (
    { Reject all MCP requests. }
    mamDisabled,
    { Allow read-only hierarchy, RTTI property, screenshot, and build-log queries. }
    mamReadOnly,
    { Allow read-only queries plus Undo-recorded scene/UI editing and layout tools. }
    mamEditWithUndo,
    { Allow all tools including saving designs to disk and triggering project builds. }
    mamFullControl
  );

  TMcpGetDesignInfoEvent = procedure (out ADesignRoot, ADesignOwner: TComponent;
    out ADesignUrl: String; out ADesignModified: Boolean) of object;
  TMcpAddComponentEvent = function (const ParentComponent: TComponent;
    const ComponentClass: TComponentClass; const ComponentOnCreate: TNotifyEvent;
    const BaseName: String): TComponent of object;
  TMcpDeleteComponentEvent = function (const TargetComponent: TComponent;
    out ErrorReason: String): Boolean of object;
  TMcpAfterModifyEvent = procedure (const UndoComment: String) of object;
  TMcpUndoRedoEvent = function (const IsRedo: Boolean;
    out ExecutedComment: String): Boolean of object;
  TMcpCaptureScreenshotEvent = function: TRGBImage of object;
  TMcpGetBuildOutputEvent = procedure (const MaxLines: Integer;
    const OutLines: TStrings; out WarningsCount, ErrorsCount: Integer) of object;
  TMcpSaveDesignEvent = function (out ErrorReason: String): Boolean of object;
  TMcpRunBuildCommandEvent = function (const CommandName: String;
    out StatusMessage: String): Boolean of object;
  TMcpLogMessageEvent = procedure (const MessageText: String) of object;

  { Model Context Protocol (MCP) JSON-RPC 2.0 dispatcher and localhost HTTP server.
    Can operate standalone on @link(StandaloneDesignRoot) / @link(StandaloneDesignOwner)
    (e.g. in automated unit tests or CLI tools) or delegate to host editor callbacks
    while marshaling HTTP requests onto the main UI/OpenGL thread via TThread.Synchronize. }
  TCastleMcpServer = class(TComponent)
  strict private
    type
      THttpListenerThread = class(TThread)
      strict private
        FOwnerServer: TCastleMcpServer;
        FHttpServer: TFPHttpServer;
        FPendingRequestBody: String;
        FPendingAuthHeader: String;
        FPendingResponseBody: String;
        FPendingStatusCode: Integer;
        procedure HandleHttpRequest(Sender: TObject;
          var ARequest: TFPHTTPConnectionRequest;
          var AResponse: TFPHTTPConnectionResponse);
        procedure SyncProcessRequest;
      protected
        procedure Execute; override;
      public
        constructor Create(const AOwnerServer: TCastleMcpServer; const APort: Word);
        destructor Destroy; override;
        procedure StopServer;
      end;

    var
      FAutonomyMode: TMcpAutonomyMode;
      FPort: Word;
      FAuthToken: String;
      FListening: Boolean;
      FListenerThread: THttpListenerThread;
      FRequestsHandledCount: Int64;
      FStandaloneDesignRoot: TComponent;
      FStandaloneDesignOwner: TComponent;
      FStandaloneDesignUrl: String;
      FStandaloneDesignModified: Boolean;

      FOnGetDesignInfo: TMcpGetDesignInfoEvent;
      FOnAddComponent: TMcpAddComponentEvent;
      FOnDeleteComponent: TMcpDeleteComponentEvent;
      FOnAfterModify: TMcpAfterModifyEvent;
      FOnUndoRedo: TMcpUndoRedoEvent;
      FOnCaptureScreenshot: TMcpCaptureScreenshotEvent;
      FOnGetBuildOutput: TMcpGetBuildOutputEvent;
      FOnSaveDesign: TMcpSaveDesignEvent;
      FOnRunBuildCommand: TMcpRunBuildCommandEvent;
      FOnLogMessage: TMcpLogMessageEvent;

    procedure SetAutonomyMode(const AValue: TMcpAutonomyMode);
    procedure SetPort(const AValue: Word);
    procedure DoLog(const Msg: String);

    procedure ResolveDesignContext(out ADesignRoot, ADesignOwner: TComponent;
      out ADesignUrl: String; out ADesignModified: Boolean);
    function FindComponentInDesign(const ADesignRoot, ADesignOwner: TComponent;
      const CompName: String): TComponent;
    function BuildHierarchyJson(const Comp: TComponent): TJSONObject;
    function BuildPropertiesJson(const TargetObj: TObject;
      const OnlyNonDefault: Boolean): TJSONObject;
    function SetSinglePropertyFromJson(const TargetObj: TObject;
      const PropPath: String; const JsonVal: TJSONData;
      out ErrorMsg: String): Boolean;
    function BuildToolsListJson: TJSONArray;
    function ExecuteMcpTool(const ToolName: String; const ArgsObj: TJSONObject;
      out IsToolError: Boolean): TJSONObject;
    function MakeToolTextResult(const TextContent: String;
      const IsError: Boolean = false): TJSONObject;
    function MakeJsonRpcResult(const IdData: TJSONData;
      const ResultObj: TJSONData): TJSONObject;
    function MakeJsonRpcError(const IdData: TJSONData;
      const Code: Integer; const MessageText: String): TJSONObject;
  public
    const
      DefaultMcpPort = 8765;
      McpProtocolVersion = '2025-03-26';

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Start or stop the background localhost (127.0.0.1) HTTP listener thread. }
    function StartListening: Boolean;
    procedure StopListening;

    { Process a raw JSON-RPC 2.0 request body synchronously on the caller thread
      and return a serialized JSON-RPC 2.0 response string (empty string for
      JSON-RPC notifications without an @code(id)). }
    function HandleJsonRpcString(const RequestBody: String;
      const AuthorizationHeader: String = ''): String;

    { Ready-to-paste @code(mcpServers) client configuration JSON for Claude Code,
      Cursor, VS Code, Windsurf, or Antigravity. }
    function ClientConfigJson: String;
    function EndpointUrl: String;

    property AutonomyMode: TMcpAutonomyMode read FAutonomyMode write SetAutonomyMode
      default mamDisabled;
    property Port: Word read FPort write SetPort default DefaultMcpPort;
    property AuthToken: String read FAuthToken write FAuthToken;
    property Listening: Boolean read FListening;
    property RequestsHandledCount: Int64 read FRequestsHandledCount;

    { Optional standalone design context when host callbacks are not assigned. }
    property StandaloneDesignRoot: TComponent
      read FStandaloneDesignRoot write FStandaloneDesignRoot;
    property StandaloneDesignOwner: TComponent
      read FStandaloneDesignOwner write FStandaloneDesignOwner;
    property StandaloneDesignUrl: String
      read FStandaloneDesignUrl write FStandaloneDesignUrl;
    property StandaloneDesignModified: Boolean
      read FStandaloneDesignModified write FStandaloneDesignModified;

    { Host integration callbacks (invoked on main thread when running HTTP server). }
    property OnGetDesignInfo: TMcpGetDesignInfoEvent
      read FOnGetDesignInfo write FOnGetDesignInfo;
    property OnAddComponent: TMcpAddComponentEvent
      read FOnAddComponent write FOnAddComponent;
    property OnDeleteComponent: TMcpDeleteComponentEvent
      read FOnDeleteComponent write FOnDeleteComponent;
    property OnAfterModify: TMcpAfterModifyEvent
      read FOnAfterModify write FOnAfterModify;
    property OnUndoRedo: TMcpUndoRedoEvent
      read FOnUndoRedo write FOnUndoRedo;
    property OnCaptureScreenshot: TMcpCaptureScreenshotEvent
      read FOnCaptureScreenshot write FOnCaptureScreenshot;
    property OnGetBuildOutput: TMcpGetBuildOutputEvent
      read FOnGetBuildOutput write FOnGetBuildOutput;
    property OnSaveDesign: TMcpSaveDesignEvent
      read FOnSaveDesign write FOnSaveDesign;
    property OnRunBuildCommand: TMcpRunBuildCommandEvent
      read FOnRunBuildCommand write FOnRunBuildCommand;
    property OnLogMessage: TMcpLogMessageEvent
      read FOnLogMessage write FOnLogMessage;
  end;

function McpAutonomyModeToString(const Mode: TMcpAutonomyMode): String;
function StringToMcpAutonomyMode(const S: String;
  const DefaultMode: TMcpAutonomyMode = mamDisabled): TMcpAutonomyMode;

implementation

uses Math, TypInfo, Contnrs, JsonParser, Base64, ssockets,
  CastleUtils, CastleStringUtils, CastleClassUtils, CastleInternalRttiUtils,
  CastleComponentSerialize, CastleUIControls, CastleControls, CastleTransform,
  CastleViewport, CastleTransformManipulate, CastleLog, ToolStudioHub, ToolTelemetryInsights, ToolRegressionHarness, ToolLiveCookAuditor, ToolCollabPresence, ToolMacroRecorder, ToolPrefabDiffMerge, ToolBudgetTreemap, ToolLodInstancing, ToolShaderComplexity, CastleBlueprint, ToolBlueprintEditor, CastlePcgGraph, ToolPcgGraph, CastleAnimBlueprint, ToolAnimBlueprint, CastleBehaviorTree, ToolBehaviorTree, CastleNiagaraStack, ToolNiagaraStack, CastleWidgetAnim, ToolWidgetAnim, CastleIkRetargeter, ToolIkRetargeter, CastlePhysicsAsset, ToolPhysicsAsset, CastleUvEditor, ToolUvEditor, CastleLevelInstance, ToolLevelInstance, CastleMaterialInstance, ToolMaterialInstance, CastleMeshEditor, ToolMeshEditor, CastleRecastNavMesh, ToolRecastNavMesh;

function McpAutonomyModeToString(const Mode: TMcpAutonomyMode): String;
begin
  case Mode of
    mamDisabled: Result := 'disabled';
    mamReadOnly: Result := 'read_only';
    mamEditWithUndo: Result := 'edit_with_undo';
    mamFullControl: Result := 'full_control';
  end;
end;

function StringToMcpAutonomyMode(const S: String;
  const DefaultMode: TMcpAutonomyMode): TMcpAutonomyMode;
begin
  if SameText(S, 'disabled') then
    Result := mamDisabled
  else
  if SameText(S, 'read_only') or SameText(S, 'readonly') then
    Result := mamReadOnly
  else
  if SameText(S, 'edit_with_undo') or SameText(S, 'edit') then
    Result := mamEditWithUndo
  else
  if SameText(S, 'full_control') or SameText(S, 'full') then
    Result := mamFullControl
  else
    Result := DefaultMode;
end;

{ TCastleMcpServer.THttpListenerThread --------------------------------------- }

constructor TCastleMcpServer.THttpListenerThread.Create(
  const AOwnerServer: TCastleMcpServer; const APort: Word);
begin
  inherited Create(true);
  FreeOnTerminate := false;
  FOwnerServer := AOwnerServer;
  FHttpServer := TFPHttpServer.Create(nil);
  FHttpServer.Port := APort;
  FHttpServer.Threaded := false;
  FHttpServer.OnRequest := {$ifdef FPC}@{$endif} HandleHttpRequest;
end;

destructor TCastleMcpServer.THttpListenerThread.Destroy;
begin
  FreeAndNil(FHttpServer);
  inherited;
end;

procedure TCastleMcpServer.THttpListenerThread.StopServer;
begin
  Terminate;
  if FHttpServer <> nil then
    FHttpServer.Active := false;
end;

procedure TCastleMcpServer.THttpListenerThread.SyncProcessRequest;
begin
  if FOwnerServer <> nil then
    FPendingResponseBody := FOwnerServer.HandleJsonRpcString(
      FPendingRequestBody, FPendingAuthHeader)
  else
    FPendingResponseBody := '';
end;

procedure TCastleMcpServer.THttpListenerThread.HandleHttpRequest(
  Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  RemoteAddr: String;
begin
  RemoteAddr := Trim(ARequest.RemoteAddress);
  if (RemoteAddr <> '') and
     (RemoteAddr <> '127.0.0.1') and
     (RemoteAddr <> '::1') and
     (Pos('127.', RemoteAddr) <> 1) and
     (Pos('::ffff:127.', LowerCase(RemoteAddr)) <> 1) then
  begin
    AResponse.Code := 403;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := '{"jsonrpc":"2.0","id":null,"error":{"code":-32003,"message":"Forbidden: MCP server only accepts loopback connections."}}';
    Exit;
  end;

  AResponse.SetCustomHeader('Access-Control-Allow-Origin', 'http://127.0.0.1');
  AResponse.SetCustomHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  AResponse.SetCustomHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, Mcp-Session-Id');

  if SameText(ARequest.Method, 'OPTIONS') then
  begin
    AResponse.Code := 204;
    AResponse.Content := '';
    Exit;
  end;

  if SameText(ARequest.Method, 'GET') and
     ((ARequest.URI = '/health') or (ARequest.URI = '/mcp/health')) then
  begin
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := Format(
      '{"status":"ok","server":"castle-editor-mcp","protocolVersion":"%s","autonomyMode":"%s"}',
      [TCastleMcpServer.McpProtocolVersion, McpAutonomyModeToString(FOwnerServer.AutonomyMode)]);
    Exit;
  end;

  if not SameText(ARequest.Method, 'POST') then
  begin
    AResponse.Code := 405;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := '{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"Use HTTP POST with JSON-RPC 2.0 payload"}}';
    Exit;
  end;

  FPendingRequestBody := ARequest.Content;
  FPendingAuthHeader := ARequest.Authorization;
  FPendingResponseBody := '';
  FPendingStatusCode := 200;

  Synchronize({$ifdef FPC}@{$endif} SyncProcessRequest);

  if FPendingResponseBody = '' then
  begin
    AResponse.Code := 202;
    AResponse.Content := '';
  end else
  begin
    AResponse.Code := FPendingStatusCode;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := FPendingResponseBody;
  end;
end;

procedure TCastleMcpServer.THttpListenerThread.Execute;
begin
  try
    FHttpServer.Active := true;
  except
    on E: Exception do
      WritelnWarning('MCP', 'HTTP listener stopped with exception: ' + E.Message);
  end;
end;

{ TCastleMcpServer ----------------------------------------------------------- }

constructor TCastleMcpServer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAutonomyMode := mamDisabled;
  FPort := DefaultMcpPort;
end;

destructor TCastleMcpServer.Destroy;
begin
  StopListening;
  inherited;
end;

procedure TCastleMcpServer.DoLog(const Msg: String);
begin
  if Assigned(FOnLogMessage) then
    FOnLogMessage(Msg);
end;

procedure TCastleMcpServer.SetAutonomyMode(const AValue: TMcpAutonomyMode);
begin
  if FAutonomyMode = AValue then Exit;
  FAutonomyMode := AValue;
  DoLog(Format('[MCP] Autonomy mode set to %s', [McpAutonomyModeToString(FAutonomyMode)]));
end;

procedure TCastleMcpServer.SetPort(const AValue: Word);
var
  WasListening: Boolean;
begin
  if (AValue = 0) or (FPort = AValue) then Exit;
  WasListening := FListening;
  if WasListening then
    StopListening;
  FPort := AValue;
  if WasListening then
    StartListening;
end;

function TCastleMcpServer.StartListening: Boolean;
begin
  if FListening then
    Exit(true);
  if FAutonomyMode = mamDisabled then
    Exit(false);
  try
    FListenerThread := THttpListenerThread.Create(Self, FPort);
    FListenerThread.Start;
    FListening := true;
    DoLog(Format('[MCP] Listening on %s (mode=%s)',
      [EndpointUrl, McpAutonomyModeToString(FAutonomyMode)]));
    Result := true;
  except
    on E: Exception do
    begin
      FreeAndNil(FListenerThread);
      FListening := false;
      DoLog('[MCP] Failed to start listener: ' + E.Message);
      Result := false;
    end;
  end;
end;

procedure TCastleMcpServer.StopListening;
var
  WakeSock: TInetSocket;
begin
  if FListenerThread <> nil then
  begin
    FListenerThread.StopServer;
    if not FListenerThread.Finished then
    begin
      try
        WakeSock := TInetSocket.Create('127.0.0.1', FPort, 100);
        FreeAndNil(WakeSock);
      except
        { Ignore connection refused if listener already closed socket }
      end;
    end;
    FListenerThread.WaitFor;
    FreeAndNil(FListenerThread);
  end;
  if FListening then
  begin
    FListening := false;
    DoLog('[MCP] Stopped localhost HTTP listener.');
  end;
end;

function TCastleMcpServer.EndpointUrl: String;
begin
  Result := Format('http://127.0.0.1:%d/mcp', [FPort]);
end;

function TCastleMcpServer.ClientConfigJson: String;
var
  RootObj, ServersObj, CgeObj, HeadersObj: TJSONObject;
begin
  RootObj := TJSONObject.Create;
  try
    ServersObj := TJSONObject.Create;
    CgeObj := TJSONObject.Create;
    CgeObj.Add('type', 'http');
    CgeObj.Add('url', EndpointUrl);
    if FAuthToken <> '' then
    begin
      HeadersObj := TJSONObject.Create;
      HeadersObj.Add('Authorization', 'Bearer ' + FAuthToken);
      CgeObj.Add('headers', HeadersObj);
    end;
    ServersObj.Add('castle-editor', CgeObj);
    RootObj.Add('mcpServers', ServersObj);
    Result := RootObj.FormatJSON;
  finally
    FreeAndNil(RootObj);
  end;
end;

procedure TCastleMcpServer.ResolveDesignContext(
  out ADesignRoot, ADesignOwner: TComponent;
  out ADesignUrl: String; out ADesignModified: Boolean);
begin
  if Assigned(FOnGetDesignInfo) then
    FOnGetDesignInfo(ADesignRoot, ADesignOwner, ADesignUrl, ADesignModified)
  else
  begin
    ADesignRoot := FStandaloneDesignRoot;
    ADesignOwner := FStandaloneDesignOwner;
    if (ADesignOwner = nil) and (ADesignRoot <> nil) then
      ADesignOwner := ADesignRoot.Owner;
    ADesignUrl := FStandaloneDesignUrl;
    ADesignModified := FStandaloneDesignModified;
  end;
end;

function TCastleMcpServer.FindComponentInDesign(
  const ADesignRoot, ADesignOwner: TComponent; const CompName: String): TComponent;

  function SearchRecursive(const C: TComponent): TComponent;
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    CC: TCastleComponent;
    I: Integer;
  begin
    Result := nil;
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if SameText(C.Name, CompName) then
      Exit(C);

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
      begin
        Result := SearchRecursive(UI.Controls[I]);
        if Result <> nil then Exit;
      end;
    end;

    if C is TCastleViewport then
    begin
      Result := SearchRecursive(TCastleViewport(C).Items);
      if Result <> nil then Exit;
    end;

    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
      begin
        Result := SearchRecursive(T[I]);
        if Result <> nil then Exit;
      end;
      for I := 0 to T.BehaviorsCount - 1 do
      begin
        Result := SearchRecursive(T.Behaviors[I]);
        if Result <> nil then Exit;
      end;
    end;

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
      begin
        Result := SearchRecursive(CC.NonVisualComponents[I]);
        if Result <> nil then Exit;
      end;
    end;
  end;

begin
  Result := nil;
  if ADesignRoot = nil then Exit;
  if (CompName = '') or SameText(ADesignRoot.Name, CompName) then
    Exit(ADesignRoot);
  if ADesignOwner <> nil then
  begin
    Result := ADesignOwner.FindComponent(CompName);
    if (Result <> nil) and (not (csTransient in Result.ComponentStyle)) then
      Exit;
  end;
  Result := SearchRecursive(ADesignRoot);
end;

function TCastleMcpServer.BuildHierarchyJson(const Comp: TComponent): TJSONObject;
var
  ChildrenArr, BehaviorsArr, NonVisualArr, VecArr: TJSONArray;
  ChildJson: TJSONObject;
  UI: TCastleUserInterface;
  T: TCastleTransform;
  CC: TCastleComponent;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.Add('name', Comp.Name);
  Result.Add('className', Comp.ClassName);

  if Comp is TCastleTransform then
  begin
    T := TCastleTransform(Comp);
    Result.Add('exists', T.Exists);
    VecArr := TJSONArray.Create;
    VecArr.Add(T.Translation.X);
    VecArr.Add(T.Translation.Y);
    VecArr.Add(T.Translation.Z);
    Result.Add('translation', VecArr);

    VecArr := TJSONArray.Create;
    VecArr.Add(T.Scale.X);
    VecArr.Add(T.Scale.Y);
    VecArr.Add(T.Scale.Z);
    Result.Add('scale', VecArr);
  end else
  if Comp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(Comp);
    Result.Add('exists', UI.Exists);
    Result.Add('width', UI.Width);
    Result.Add('height', UI.Height);
  end;

  ChildrenArr := TJSONArray.Create;
  if Comp is TCastleUserInterface then
  begin
    UI := TCastleUserInterface(Comp);
    for I := 0 to UI.ControlsCount - 1 do
      if not (csTransient in UI.Controls[I].ComponentStyle) then
      begin
        ChildJson := BuildHierarchyJson(UI.Controls[I]);
        ChildrenArr.Add(ChildJson);
      end;
  end;

  if Comp is TCastleViewport then
  begin
    T := TCastleViewport(Comp).Items;
    for I := 0 to T.Count - 1 do
      if not (csTransient in T[I].ComponentStyle) then
        ChildrenArr.Add(BuildHierarchyJson(T[I]));
  end else
  if Comp is TCastleTransform then
  begin
    T := TCastleTransform(Comp);
    for I := 0 to T.Count - 1 do
      if not (csTransient in T[I].ComponentStyle) then
        ChildrenArr.Add(BuildHierarchyJson(T[I]));
  end;
  Result.Add('children', ChildrenArr);

  if Comp is TCastleTransform then
  begin
    T := TCastleTransform(Comp);
    if T.BehaviorsCount > 0 then
    begin
      BehaviorsArr := TJSONArray.Create;
      for I := 0 to T.BehaviorsCount - 1 do
        if not (csTransient in T.Behaviors[I].ComponentStyle) then
          BehaviorsArr.Add(BuildHierarchyJson(T.Behaviors[I]));
      Result.Add('behaviors', BehaviorsArr);
    end;
  end;

  if Comp is TCastleComponent then
  begin
    CC := TCastleComponent(Comp);
    if CC.NonVisualComponentsCount > 0 then
    begin
      NonVisualArr := TJSONArray.Create;
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        if not (csTransient in CC.NonVisualComponents[I].ComponentStyle) then
          NonVisualArr.Add(BuildHierarchyJson(CC.NonVisualComponents[I]));
      Result.Add('nonVisualComponents', NonVisualArr);
    end;
  end;
end;

function TCastleMcpServer.BuildPropertiesJson(const TargetObj: TObject;
  const OnlyNonDefault: Boolean): TJSONObject;
var
  PropList: TPropInfoList;
  PropInfo: PPropInfo;
  PType: TPropertyType;
  PropName, CleanVecName: String;
  SubObj: TObject;
  VecArr: TJSONArray;
  SubProps: TJSONObject;
  I: Integer;
begin
  Result := TJSONObject.Create;
  if TargetObj = nil then Exit;

  PropList := TPropInfoList.Create(TargetObj, tkProperties);
  try
    for I := 0 to PropList.Count - 1 do
    begin
      PropInfo := PropList[I];
      PropName := PropInfo^.Name;
      if OnlyNonDefault and PropertyHasDefaultValue(TargetObj, PropInfo) then
        Continue;

      PType := PropertyType(PropInfo);
      case PType of
        ptInteger:
          Result.Add(PropName, PropertyGetInteger(TargetObj, PropInfo));
        ptFloat:
          Result.Add(PropName, PropertyGetFloat(TargetObj, PropInfo));
        ptString:
          Result.Add(PropName, PropertyGetString(TargetObj, PropInfo));
        ptBoolean:
          Result.Add(PropName, PropertyGetBoolean(TargetObj, PropInfo));
        ptEnumeration:
          Result.Add(PropName, PropertyGetEnumStr(TargetObj, PropInfo));
        ptInstance:
          begin
            SubObj := PropertyGetInstance(TargetObj, PropInfo);
            if SubObj = nil then
            begin
              if not OnlyNonDefault then
                Result.Add(PropName, TJSONNull.Create);
            end else
            if SubObj is TCastleVector2Persistent then
            begin
              CleanVecName := SuffixRemove('Persistent', PropName, true);
              VecArr := TJSONArray.Create;
              VecArr.Add(TCastleVector2Persistent(SubObj).Value.X);
              VecArr.Add(TCastleVector2Persistent(SubObj).Value.Y);
              Result.Add(CleanVecName, VecArr);
            end else
            if SubObj is TCastleVector3Persistent then
            begin
              CleanVecName := SuffixRemove('Persistent', PropName, true);
              VecArr := TJSONArray.Create;
              VecArr.Add(TCastleVector3Persistent(SubObj).Value.X);
              VecArr.Add(TCastleVector3Persistent(SubObj).Value.Y);
              VecArr.Add(TCastleVector3Persistent(SubObj).Value.Z);
              Result.Add(CleanVecName, VecArr);
            end else
            if SubObj is TCastleVector4Persistent then
            begin
              CleanVecName := SuffixRemove('Persistent', PropName, true);
              VecArr := TJSONArray.Create;
              VecArr.Add(TCastleVector4Persistent(SubObj).Value.X);
              VecArr.Add(TCastleVector4Persistent(SubObj).Value.Y);
              VecArr.Add(TCastleVector4Persistent(SubObj).Value.Z);
              VecArr.Add(TCastleVector4Persistent(SubObj).Value.W);
              Result.Add(CleanVecName, VecArr);
            end else
            if (SubObj is TComponent) and (csSubComponent in TComponent(SubObj).ComponentStyle) then
            begin
              SubProps := BuildPropertiesJson(SubObj, OnlyNonDefault);
              if (not OnlyNonDefault) or (SubProps.Count > 0) then
                Result.Add(PropName, SubProps)
              else
                FreeAndNil(SubProps);
            end else
            if SubObj is TComponent then
              Result.Add(PropName, TComponent(SubObj).Name);
          end;
        else ;
      end;
    end;
  finally
    FreeAndNil(PropList);
  end;
end;

function TCastleMcpServer.SetSinglePropertyFromJson(const TargetObj: TObject;
  const PropPath: String; const JsonVal: TJSONData;
  out ErrorMsg: String): Boolean;
var
  DotPos: Integer;
  HeadName, TailName: String;
  PropInfo: PPropInfo;
  SubObj: TObject;
  PType: TPropertyType;
  Arr: TJSONArray;
  V2: TVector2;
  V3: TVector3;
  V4: TVector4;
begin
  ErrorMsg := '';
  if TargetObj = nil then
  begin
    ErrorMsg := 'Target object is nil';
    Exit(false);
  end;

  DotPos := Pos('.', PropPath);
  if DotPos > 0 then
  begin
    HeadName := Copy(PropPath, 1, DotPos - 1);
    TailName := Copy(PropPath, DotPos + 1, MaxInt);
    PropInfo := GetPropInfo(TargetObj, HeadName);
    if (PropInfo = nil) or (PropertyType(PropInfo) <> ptInstance) then
      PropInfo := GetPropInfo(TargetObj, HeadName + 'Persistent');
    if (PropInfo = nil) or (PropertyType(PropInfo) <> ptInstance) then
    begin
      ErrorMsg := Format('Sub-object property "%s" not found on %s', [HeadName, TargetObj.ClassName]);
      Exit(false);
    end;
    SubObj := PropertyGetInstance(TargetObj, PropInfo);
    Exit(SetSinglePropertyFromJson(SubObj, TailName, JsonVal, ErrorMsg));
  end;

  PropInfo := GetPropInfo(TargetObj, PropPath);
  if (PropInfo = nil) or (PropertyType(PropInfo) = ptOther) then
  begin
    { Check for auto-generated *Persistent vector/color wrapper }
    PropInfo := GetPropInfo(TargetObj, PropPath + 'Persistent');
  end;

  if PropInfo = nil then
  begin
    ErrorMsg := Format('Property "%s" not found on %s', [PropPath, TargetObj.ClassName]);
    Exit(false);
  end;

  PType := PropertyType(PropInfo);
  try
    case PType of
      ptInteger:
        PropertySetInteger(TargetObj, PropInfo, JsonVal.AsInt64);
      ptFloat:
        PropertySetFloat(TargetObj, PropInfo, JsonVal.AsFloat);
      ptString:
        PropertySetString(TargetObj, PropInfo, JsonVal.AsString);
      ptBoolean:
        PropertySetBoolean(TargetObj, PropInfo, JsonVal.AsBoolean);
      ptEnumeration:
        begin
          if JsonVal.JSONType = jtNumber then
            PropertySetEnum(TargetObj, PropInfo, JsonVal.AsInteger)
          else
            PropertySetEnumStr(TargetObj, PropInfo, JsonVal.AsString);
        end;
      ptInstance:
        begin
          SubObj := PropertyGetInstance(TargetObj, PropInfo);
          if (SubObj is TCastleVector2Persistent) and (JsonVal is TJSONArray) then
          begin
            Arr := TJSONArray(JsonVal);
            if Arr.Count < 2 then
            begin
              ErrorMsg := Format('Vector2 property "%s" requires 2 array elements', [PropPath]);
              Exit(false);
            end;
            V2 := Vector2(Arr.Floats[0], Arr.Floats[1]);
            TCastleVector2Persistent(SubObj).Value := V2;
          end else
          if (SubObj is TCastleVector3Persistent) and (JsonVal is TJSONArray) then
          begin
            Arr := TJSONArray(JsonVal);
            if Arr.Count < 3 then
            begin
              ErrorMsg := Format('Vector3 property "%s" requires 3 array elements', [PropPath]);
              Exit(false);
            end;
            V3 := Vector3(Arr.Floats[0], Arr.Floats[1], Arr.Floats[2]);
            TCastleVector3Persistent(SubObj).Value := V3;
          end else
          if (SubObj is TCastleVector4Persistent) and (JsonVal is TJSONArray) then
          begin
            Arr := TJSONArray(JsonVal);
            if Arr.Count < 4 then
            begin
              ErrorMsg := Format('Vector4 property "%s" requires 4 array elements', [PropPath]);
              Exit(false);
            end;
            V4 := Vector4(Arr.Floats[0], Arr.Floats[1], Arr.Floats[2], Arr.Floats[3]);
            TCastleVector4Persistent(SubObj).Value := V4;
          end else
          begin
            ErrorMsg := Format('Instance property "%s" requires dot-path or numeric vector array', [PropPath]);
            Exit(false);
          end;
        end;
      else
      begin
        ErrorMsg := Format('Unsupported RTTI type for property "%s"', [PropPath]);
        Exit(false);
      end;
    end;
    Result := true;
  except
    on E: Exception do
    begin
      ErrorMsg := Format('Failed to set "%s": %s', [PropPath, E.Message]);
      Result := false;
    end;
  end;
end;

function TCastleMcpServer.BuildToolsListJson: TJSONArray;

  procedure AddToolDef(const Name, Desc: String; const PropsObj: TJSONObject;
    const RequiredNames: array of String);
  var
    ToolObj, SchemaObj: TJSONObject;
    ReqArr: TJSONArray;
    S: String;
  begin
    ToolObj := TJSONObject.Create;
    ToolObj.Add('name', Name);
    ToolObj.Add('description', Desc);
    SchemaObj := TJSONObject.Create;
    SchemaObj.Add('type', 'object');
    if PropsObj <> nil then
      SchemaObj.Add('properties', PropsObj)
    else
      SchemaObj.Add('properties', TJSONObject.Create);
    if Length(RequiredNames) > 0 then
    begin
      ReqArr := TJSONArray.Create;
      for S in RequiredNames do
        ReqArr.Add(S);
      SchemaObj.Add('required', ReqArr);
    end;
    ToolObj.Add('inputSchema', SchemaObj);
    Result.Add(ToolObj);
  end;

  function MakePropSchema(const TypeName, Desc: String): TJSONObject;
  begin
    Result := TJSONObject.Create;
    Result.Add('type', TypeName);
    Result.Add('description', Desc);
  end;

var
  P: TJSONObject;
begin
  Result := TJSONArray.Create;

  AddToolDef('cge_get_hierarchy',
    'Return the currently open Castle Game Engine design hierarchy tree (components, transforms, UI controls, behaviors, and design metadata).',
    nil, []);

  P := TJSONObject.Create;
  P.Add('name', MakePropSchema('string', 'Component name to inspect (omit or empty for DesignRoot).'));
  P.Add('onlyNonDefault', MakePropSchema('boolean', 'When true, return only properties modified from their default value.'));
  AddToolDef('cge_get_component_properties',
    'Inspect published RTTI properties (including vector/color arrays and subcomponents) of a component in the open design.',
    P, []);

  P := TJSONObject.Create;
  P.Add('filter', MakePropSchema('string', 'Optional case-insensitive substring filter (e.g. "Light", "Button", "Box").'));
  AddToolDef('cge_list_component_classes',
    'List registered serializable Castle Game Engine component classes available for cge_add_component.',
    P, []);

  P := TJSONObject.Create;
  P.Add('name', MakePropSchema('string', 'Target component name in the active design.'));
  P.Add('properties', MakePropSchema('object', 'Key-value map of RTTI properties to set (supports scalars, enums, dot-paths like "Translation.X", and vector arrays like "Translation": [1, 2, 3]).'));
  AddToolDef('cge_set_component_properties',
    'Modify one or more RTTI properties on a component and record an Undo step (requires EditWithUndo or FullControl).',
    P, ['name', 'properties']);

  P := TJSONObject.Create;
  P.Add('className', MakePropSchema('string', 'Registered CGE component class name (e.g. "TCastleBox", "TCastleScene", "TCastleButton", "TCastlePointLight").'));
  P.Add('parentName', MakePropSchema('string', 'Optional parent component name (defaults to DesignRoot).'));
  P.Add('baseName', MakePropSchema('string', 'Optional base name for the newly created component.'));
  P.Add('properties', MakePropSchema('object', 'Optional initial RTTI property map to apply to the created component.'));
  AddToolDef('cge_add_component',
    'Instantiate and attach a new Castle Game Engine component into the open design with Undo support.',
    P, ['className']);

  P := TJSONObject.Create;
  P.Add('name', MakePropSchema('string', 'Name of the component to remove from the design (cannot be DesignRoot).'));
  AddToolDef('cge_delete_component',
    'Delete a component and its children from the active design with Undo support.',
    P, ['name']);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Layout action: snap_to_grid | reset_transform | align_x | align_y | align_z | distribute_x | distribute_y | distribute_z | arrange_circle | arrange_grid | center_in_parent'));
  P.Add('targets', MakePropSchema('array', 'Array of target component names.'));
  P.Add('gridStep', MakePropSchema('number', 'Optional grid/spacing parameter (default 1.0).'));
  P.Add('radius', MakePropSchema('number', 'Optional circle radius parameter (default 5.0).'));
  P.Add('columns', MakePropSchema('integer', 'Optional grid column count (default 3).'));
  AddToolDef('cge_execute_layout_action',
    'Execute a multi-component 3D transform or 2D UI layout/alignment operation with Undo support.',
    P, ['action', 'targets']);

  P := TJSONObject.Create;
  P.Add('direction', MakePropSchema('string', '"undo" (default) or "redo".'));
  AddToolDef('cge_undo_redo',
    'Undo or Redo the most recent design modification in TUndoSystem.',
    P, []);

  AddToolDef('cge_capture_viewport_screenshot',
    'Capture the live Castle Game Engine editor viewport as a Base64-encoded PNG image content block.',
    nil, []);

  P := TJSONObject.Create;
  P.Add('maxLines', MakePropSchema('integer', 'Maximum number of recent log lines to return (default 50).'));
  AddToolDef('cge_get_build_output',
    'Read recent Castle Game Engine Editor output/compiler log lines and warning/error counts.',
    P, []);

  AddToolDef('cge_save_design',
    'Save the currently open design file to disk (requires FullControl autonomy mode).',
    nil, []);

  P := TJSONObject.Create;
  P.Add('command', MakePropSchema('string', 'Build command to run: "compile" or "clean" (requires FullControl autonomy mode).'));
  AddToolDef('cge_run_build_command',
    'Trigger project compilation or clean inside Castle Game Engine Editor (requires FullControl autonomy mode).',
    P, ['command']);

  P := TJSONObject.Create;
  P.Add('query', MakePropSchema('string', 'Optional multi-token case-insensitive keyword filter (e.g. "ackermann", "gauntlet", "phase 325").'));
  P.Add('category', MakePropSchema('integer', 'Optional studio domain index (-1 = all 6 domains, 0..5 = specific TStudioHubCategory).'));
  AddToolDef('cge_list_studios',
    'Search and list all 96 specialized Castle Game Engine Horizon 2-11 editor studios across 6 domains.',
    P, []);

  AddToolDef('cge_audit_world_readiness',
    'Run a holistic cross-studio World Readiness QA audit across the currently open design, returning the 0..100 score, grade, subsystem counts, and actionable integration warnings.',
    nil, []);

  P := TJSONObject.Create;
  P.Add('frames', MakePropSchema('integer', 'Number of frames to capture in the telemetry ring buffer (default 30, range 1..120).'));
  P.Add('includeChromeTrace', MakePropSchema('boolean', 'When true, embeds Chrome about://tracing / Perfetto traceEvents JSON spans in the response.'));
  AddToolDef('cge_capture_telemetry_trace',
    'Capture a multi-frame Unreal Insights-style subsystem flame-graph profile of the open design, returning P50/P95/P99 frame times, hitch spikes, top hotspot subsystem, and optional Chrome/Perfetto traceEvents.',
    P, []);

  P := TJSONObject.Create;
  P.Add('steps', MakePropSchema('integer', 'Number of deterministic fixed-timestep frames to simulate in each dual-run pass (default 20, range 1..240).'));
  P.Add('seed', MakePropSchema('integer', 'Deterministic PRNG seed applied across simulation subsystems before each pass (default 20260346).'));
  AddToolDef('cge_verify_determinism_hash',
    'Compute the canonical 64-bit FNV-1a world-state hash and run a non-destructive dual-pass seeded determinism verification across all actors & simulation subsystems.',
    P, []);

  P := TJSONObject.Create;
  P.Add('checkDiskUrls', MakePropSchema('boolean', 'When true, also checks URIFileExists on disk for every non-empty asset URL property (default false).'));
  AddToolDef('cge_audit_package_cook',
    'Run the Release Package Cook Readiness Auditor across the open design (broken/traversal URLs, ChooserTable validation, Tetrahedral Soft-Body inversions, MassTraffic safety, and 96-Studio World Readiness).',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Collaborative lock command: "list", "acquire", "release", "heartbeat", or "expire" (default "list").'));
  P.Add('userId', MakePropSchema('string', 'Collaborator or AI agent identifier (e.g. "agent-alpha" or "alice").'));
  P.Add('subtree', MakePropSchema('string', 'Target component subtree root name in the open design (e.g. "CastleGate").'));
  P.Add('leaseSec', MakePropSchema('number', 'Lease reservation duration in seconds before stale auto-expiration (default 30).'));
  AddToolDef('cge_manage_collab_locks',
    'Coordinate multi-user / multi-agent subtree edit reservation locks with ancestor/descendant conflict rejection and lease heartbeats.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Macro command: "status", "record_step", "replay", "clear", or "import_json" (default "status").'));
  P.Add('stepKind', MakePropSchema('string', 'Step operation for record_step: "add_translate", "multiply_scale", "set_tag", "rename_prefix", or "set_color_rgb".'));
  P.Add('targetFilter', MakePropSchema('string', 'Case-insensitive transform name substring filter ("*" or empty matches all transforms).'));
  P.Add('vecX', MakePropSchema('number', 'X vector parameter for translation/scale/RGB tint.'));
  P.Add('vecY', MakePropSchema('number', 'Y vector parameter for translation/scale/RGB tint.'));
  P.Add('vecZ', MakePropSchema('number', 'Z vector parameter for translation/scale/RGB tint.'));
  P.Add('scalarParam', MakePropSchema('number', 'Scalar parameter (e.g. integer Tag value for set_tag).'));
  P.Add('strParam', MakePropSchema('string', 'String parameter (e.g. prefix for rename_prefix).'));
  P.Add('multiplier', MakePropSchema('number', 'Parameterized delta multiplier applied during replay (default 1.0).'));
  P.Add('macroJson', MakePropSchema('string', 'Serialized macro JSON payload for import_json.'));
  AddToolDef('cge_run_editor_macro',
    'Record, import, inspect, or replay parameterized multi-step scene transform macros across the open design.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Merge operation: diff_three_way, capture_base, or status.'));
  P.Add('baseJson', MakePropSchema('string', 'Common ancestor CGE component JSON string.'));
  P.Add('oursJson', MakePropSchema('string', 'Local (Ours) CGE component JSON string.'));
  P.Add('theirsJson', MakePropSchema('string', 'Incoming branch (Theirs) CGE component JSON string.'));
  P.Add('conflictPolicy', MakePropSchema('string', 'True-conflict resolution policy: prefer_ours or prefer_theirs.'));
  AddToolDef('cge_diff_merge_scene',
    'Perform structural 3-way Ancestor/Ours/Theirs CGE scene & prefab diff/merge with automatic non-conflicting property/node merging.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Budget treemap operation: audit_viewport or status.'));
  P.Add('budgetLimitKB', MakePropSchema('number', 'Total scene memory budget in KB (default 8192).'));
  P.Add('perNodeCapKB', MakePropSchema('number', 'Per-component memory outlier threshold in KB (default 2048).'));
  P.Add('canvasWidth', MakePropSchema('number', 'Squarified treemap width in pixels (default 640).'));
  P.Add('canvasHeight', MakePropSchema('number', 'Squarified treemap height in pixels (default 360).'));
  AddToolDef('cge_audit_scene_budget',
    'Partition open scene memory & triangle footprint via a Bruls-Huizing-van Wijk squarified treemap and report over-budget outliers.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'LOD & instancing operation: analyze_scene or status.'));
  P.Add('minBatchInstances', MakePropSchema('integer', 'Minimum repeated instances required to form a GPU instancing batch (default 2).'));
  P.Add('verticalFovDeg', MakePropSchema('number', 'Camera vertical FOV in degrees for screen-coverage LOD distances (default 60).'));
  P.Add('lodMinTriangles', MakePropSchema('integer', 'Minimum base mesh triangle count to synthesize a 4-tier LOD chain (default 500).'));
  AddToolDef('cge_optimize_lod_instancing',
    'Cluster repeated meshes into GPU-instanced draw-call batches and synthesize 4-tier screen-size hysteresis LOD chains.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Overdraw & shader complexity operation: audit_viewport or status.'));
  P.Add('maxTranslucentLayers', MakePropSchema('integer', 'Maximum allowed stacked translucent alpha layers per screen tile before flagging hotspot (default 3).'));
  P.Add('aluHotspotCap', MakePropSchema('integer', 'Per-tile fragment ALU instruction hotspot threshold (default 320).'));
  AddToolDef('cge_audit_overdraw_shaders',
    'Audit 32x18 screen-tile viewport translucent overdraw, Early-Z vs. alpha-blend fragment ALU cost, and cutout remediation.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Blueprint operation: status, compile, run_construction, fire_event, generate_pascal, or spawn_preset (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleBlueprint name (defaults to first Blueprint in design).'));
  P.Add('eventName', MakePropSchema('string', 'Event to fire for fire_event: begin_play, tick, overlap, or a CustomEvent name (default begin_play).'));
  P.Add('deltaSec', MakePropSchema('number', 'Delta seconds for tick event (default 0.25).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: colonnade, door_timeline, or warmup_branch (default colonnade).'));
  AddToolDef('cge_compile_blueprint',
    'Compile, inspect, run Construction Script, dispatch EventGraph events, or generate nativized Pascal code for TCastleBlueprint visual scripts.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'PCG operation: status, execute, inspect_node, reseed, or spawn_preset (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastlePcgGraph name (defaults to first PCG graph in design).'));
  P.Add('nodeId', MakePropSchema('string', 'NodeId to inspect for inspect_node (e.g. "Diff_ClearRoad" or "Prune_NoOverlap").'));
  P.Add('seed', MakePropSchema('integer', 'New deterministic seed for reseed (default 4242).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: forest_road, rock_union, or spline_posts (default forest_road).'));
  AddToolDef('cge_execute_pcg_graph',
    'Execute, re-seed, spawn, or inspect intermediate per-node point clouds of TCastlePcgGraph visual PCG pipelines.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'AnimBlueprint operation: status, step_pose, set_params, or spawn_preset (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleAnimBlueprint name (defaults to first AnimBlueprint in design).'));
  P.Add('deltaSec', MakePropSchema('number', 'Delta seconds for step_pose (default 0.25).'));
  P.Add('speedMps', MakePropSchema('number', 'Character speed in m/s for set_params (default 5.5).'));
  P.Add('upperAimWeight', MakePropSchema('number', 'Upper-body LayeredBlendPerBone weight 0..1 for set_params (default 1.0).'));
  P.Add('isInAir', MakePropSchema('boolean', 'Airborne jump state flag for set_params (default false).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: loco_aim_ik, combat_slot, or jump_air (default loco_aim_ik).'));
  AddToolDef('cge_evaluate_anim_blueprint',
    'Spawn, configure, step AnimGraph pose evaluation, or inspect AnimNotify tracks on TCastleAnimBlueprint components.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Behavior Tree operation: status, tick, set_blackboard, or spawn_preset (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleBehaviorTree name (defaults to first Behavior Tree in design).'));
  P.Add('deltaSec', MakePropSchema('number', 'Delta seconds for tick (default 0.25).'));
  P.Add('bbKey', MakePropSchema('string', 'Blackboard boolean key name for set_blackboard (e.g. "HasLineOfSight").'));
  P.Add('bbBool', MakePropSchema('boolean', 'Blackboard boolean value for set_blackboard (default true).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: tactical_guard, simple_parallel, or ammo_reload (default tactical_guard).'));
  AddToolDef('cge_tick_behavior_tree',
    'Spawn, update Blackboard keys, tick Behavior Tree execution (including Observer Aborts & Services), or audit TCastleBehaviorTree components.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Niagara operation: status, step_sim, toggle_module, or spawn_preset (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleNiagaraSystem name (defaults to first Niagara system in design).'));
  P.Add('deltaSec', MakePropSchema('number', 'Delta seconds for step_sim (default 0.25).'));
  P.Add('moduleId', MakePropSchema('string', 'ModuleId to enable/disable for toggle_module (e.g. "PU_Attractor").'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: vortex_portal, collision_sparks, or campfire_embers (default vortex_portal).'));
  AddToolDef('cge_simulate_niagara_stack',
    'Spawn, toggle stack modules, step simulation, or audit TCastleNiagaraSystem 4-stage modular VFX emitters.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'UMG Widget Animation operation: status, spawn_preset, play_clip, scrub, or fire_event (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleWidgetAnimator name (defaults to first WidgetAnimator in design).'));
  P.Add('clipName', MakePropSchema('string', 'Clip name for play_clip (e.g. "Anim_ModalOpen" or "Anim_ButtonHover").'));
  P.Add('timeSec', MakePropSchema('number', 'Timeline time in seconds for scrub (default 0.30).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: modal_bounce, hud_damage, or boss_banner (default modal_bounce).'));
  AddToolDef('cge_animate_umg_widget',
    'Spawn, scrub timeline, play forward/reverse clips, trigger UI events, or audit TCastleWidgetAnimator UMG 2D UI animations.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'IK Retargeter operation: status, spawn_preset, step_walk, or toggle_ref_delta (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleIkRetargeter name (defaults to first IK Retargeter in design).'));
  P.Add('deltaSec', MakePropSchema('number', 'Delta seconds for step_walk (default 0.25).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: compact_apose, brute_ogre, or two_hand_ik (default compact_apose).'));
  AddToolDef('cge_retarget_ik_skeleton',
    'Spawn, step cross-skeleton stride retargeting, toggle T/A-pose reference delta compensation, or audit TCastleIkRetargeter rigs.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'PhAT operation: status, spawn_preset, step_sim, or poke_body (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastlePhysicsAsset name (defaults to first PhysicsAsset in design).'));
  P.Add('bodyName', MakePropSchema('string', 'Target bone body name for poke_body (default "LowerArm_L").'));
  P.Add('deltaSec', MakePropSchema('number', 'Delta seconds for step_sim (default 0.04).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: humanoid_ragdoll, pinned_test, or heavy_brute (default humanoid_ragdoll).'));
  AddToolDef('cge_simulate_physics_asset',
    'Spawn, step ragdoll simulation, poke skeletal bodies, or audit TCastlePhysicsAsset (PhAT) bodies & Swing1/Swing2 joint cones.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'UV Editor operation: status, spawn_preset, or unwrap_pack (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleUvEditorMesh name (defaults to first UV mesh in design).'));
  P.Add('projection', MakePropSchema('string', 'Projection mode for unwrap_pack: box6, cylindrical, planar, or conformal (default box6).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: crate_6islands, cylindrical_column, or overlap_demo (default crate_6islands).'));
  AddToolDef('cge_unwrap_pack_uvs',
    'Spawn, project/unwrap, rectilinearly shelf-pack UV islands, or audit overlapping UV triangles & world-space Texel Density.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Level Instance / OFPA operation: status, spawn_preset, edit_in_place, commit_sync, or export_ofpa (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleLevelInstance name (defaults to first Level Instance in design).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: watchtower, cyber_street, or dungeon_room (default watchtower).'));
  AddToolDef('cge_manage_ofpa_actors',
    'Spawn, edit/commit/sync Level Instances & Packed ISM batches, or export One-File-Per-Actor (OFPA / __ExternalActors__) manifests.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Material Instance / MPC operation: status, spawn_showcase, override_scalar, reset_overrides, or broadcast_mpc (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleMaterialInstance name (defaults to first instance in design).'));
  P.Add('paramName', MakePropSchema('string', 'Scalar parameter name for override_scalar (e.g. Roughness, Metallic, ClearCoat, UVTiling).'));
  P.Add('scalarValue', MakePropSchema('number', 'Scalar value for override_scalar (default 0.25).'));
  P.Add('mpcPreset', MakePropSchema('string', 'MPC environment preset for broadcast_mpc: dry_noon, monsoon_rain, blizzard_snow, or neon_night (default monsoon_rain).'));
  AddToolDef('cge_override_material_instance',
    'Spawn Parent->Child Material Instances & MPCs, override parameters with zero shader recompiles, reset to parent, or broadcast global MPC weather uniforms.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Mesh Editor operation: status, spawn_preset, decompose_convex, attach_socket_prop, or recompute_tangents (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleMeshEditorAsset name (defaults to first mesh asset in design).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: archway, halberd, or turret (default archway).'));
  P.Add('maxHulls', MakePropSchema('integer', 'Max convex hulls for decompose_convex (default 3).'));
  P.Add('socketName', MakePropSchema('string', 'Socket name for attach_socket_prop (e.g. Socket_TorchBracket_L).'));
  AddToolDef('cge_edit_mesh_sockets_collision',
    'Spawn Static/Skeletal Mesh Editor assets, run V-HACD / K-DOP Auto-Convex Collision decomposition, attach Socket props, or recompute MikkTSpace tangents.',
    P, []);

  P := TJSONObject.Create;
  P.Add('action', MakePropSchema('string', 'Recast NavMesh operation: status, spawn_preset, build_navmesh, or find_path (default status).'));
  P.Add('name', MakePropSchema('string', 'Optional target TCastleRecastNavMesh name (defaults to first Recast volume in design).'));
  P.Add('preset', MakePropSchema('string', 'Preset for spawn_preset: bridge_2story, dungeon_keep, or canyon_parkour (default bridge_2story).'));
  P.Add('agentHeight', MakePropSchema('number', 'Optional AgentHeight in meters for build_navmesh (default 1.80).'));
  AddToolDef('cge_build_recast_navmesh',
    'Spawn 3D Polygonal Recast NavMesh volumes, rebuild multi-floor headroom-aware NavPolys & ANavLinkProxy off-mesh links, or solve 3D funnel A* paths.',
    P, []);
end;

function TCastleMcpServer.MakeToolTextResult(const TextContent: String;
  const IsError: Boolean): TJSONObject;
var
  ContentArr: TJSONArray;
  ItemObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  ContentArr := TJSONArray.Create;
  ItemObj := TJSONObject.Create;
  ItemObj.Add('type', 'text');
  ItemObj.Add('text', TextContent);
  ContentArr.Add(ItemObj);
  Result.Add('content', ContentArr);
  if IsError then
    Result.Add('isError', true);
end;

function TCastleMcpServer.ExecuteMcpTool(const ToolName: String;
  const ArgsObj: TJSONObject; out IsToolError: Boolean): TJSONObject;

  function FindRegisteredComp(const CName: String): TRegisteredComponent;
  var
    R: TRegisteredComponent;
  begin
    Result := nil;
    for R in RegisteredComponents do
      if SameText(R.ComponentClass.ClassName, CName) then
        Exit(R);
  end;

  function RequireAutonomy(const MinMode: TMcpAutonomyMode;
    out DeniedResult: TJSONObject): Boolean;
  begin
    Result := Ord(FAutonomyMode) >= Ord(MinMode);
    if not Result then
    begin
      IsToolError := true;
      DeniedResult := MakeToolTextResult(Format(
        'Tool "%s" requires autonomy mode "%s", but current mode is "%s".',
        [ToolName, McpAutonomyModeToString(MinMode), McpAutonomyModeToString(FAutonomyMode)]),
        true);
    end;
  end;

  function DefaultAddChildComponent(const ParentComp: TComponent;
    const Reg: TRegisteredComponent; const DesignOwner: TComponent;
    const BaseName: String; out ErrMsg: String): TComponent;
  var
    CleanBase: String;
  begin
    ErrMsg := '';
    Result := Reg.ComponentClass.Create(DesignOwner);
    if Assigned(Reg.OnCreate) then
      Reg.OnCreate(Result);
    if BaseName <> '' then
      CleanBase := BaseName
    else
      CleanBase := PrefixRemove('TCastle', Reg.ComponentClass.ClassName, true);
    if DesignOwner <> nil then
      Result.Name := ProposeComponentName(Reg.ComponentClass, DesignOwner, CleanBase)
    else
      Result.Name := CleanBase;

    if (Result is TCastleUserInterface) and (ParentComp is TCastleUserInterface) then
      TCastleUserInterface(ParentComp).InsertFront(TCastleUserInterface(Result))
    else
    if (Result is TCastleTransform) and (ParentComp is TCastleViewport) then
      TCastleViewport(ParentComp).Items.Add(TCastleTransform(Result))
    else
    if (Result is TCastleTransform) and (ParentComp is TCastleTransform) then
      TCastleTransform(ParentComp).Add(TCastleTransform(Result))
    else
    if (Result is TCastleBehavior) and (ParentComp is TCastleTransform) then
      TCastleTransform(ParentComp).AddBehavior(TCastleBehavior(Result))
    else
    if (ParentComp is TCastleComponent) then
      TCastleComponent(ParentComp).AddNonVisualComponent(Result)
    else
    begin
      FreeAndNil(Result);
      ErrMsg := Format('Cannot attach %s as a child of %s (%s)',
        [Reg.ComponentClass.ClassName, ParentComp.Name, ParentComp.ClassName]);
    end;
  end;

var
  DesignRoot, DesignOwner, TargetComp, ParentComp, NewComp: TComponent;
  DesignUrl, CompName, ClassNameStr, ParentName, BaseName, FilterStr,
    ErrMsg, ActionName, DirectionStr, CmdStr, UndoDesc, EncodedPng: String;
  DesignModified, OnlyNonDefault, IsRedo: Boolean;
  OutPayload, PropsMap: TJSONObject;
  ClassesArr, TargetsArr, LinesArr, ContentArr: TJSONArray;
  Reg: TRegisteredComponent;
  I, MaxLines, WarnCount, ErrCount, ColumnsCount: Integer;
  Manip: TCastleTransformManipulate;
  CompList: TComponentList;
  GridStep, RadiusVal: Single;
  UI: TCastleUserInterface;
  ScreenshotImg: TRGBImage;
  PngStream: TMemoryStream;
  ImgBlock, MetaBlock, StudioItemObj: TJSONObject;
  OutLines: TStringList;
  StudioMatches: TStudioCatalogEntryArray;
  HealthReport: TStudioWorldHealthReport;
  CatFilter: Integer;
  TelemetryProf: TTelemetryInsightsProfiler;
  TelemetryStats: TTelemetryAggregateStats;
  IncludeChromeTrace: Boolean;
  DetAudit: TDeterminismAuditResult;
  DetSnap: TGoldenWorldSnapshot;
  DetSeed: Integer;
  CookRep: TCookAuditReport;
  CheckDiskUrls: Boolean;
  CollabLeaseSec: Double;
  CollabOk: Boolean;
  CollabLock: TCollabSubtreeLock;
  MacroStepKind: TMacroStepKind;
  MacroAffected: Integer;
  MacroMult: Single;
  MacroStepItem: TEditorMacroStep;
  DiffMergeRep: TThreeWayMergeReport;
  DiffPolicy: TMergeConflictPolicy;
  DiffBaseStr, DiffOursStr, DiffTheirsStr: String;
  BudgetRep: TSceneBudgetTreemapReport;
  BudgetLimitVal, NodeCapVal, TreemapW, TreemapH: Single;
  LodInstRep: TLodInstancingReport;
  MinBatchInstVal, LodMinTrisVal: Integer;
  LodFovVal: Single;
  OverdrawRep: TShaderComplexityReport;
  MaxTransLayersVal, AluCapVal: Integer;
  BpAudit: TBlueprintSceneAuditReport;
  BpComp: TCastleBlueprint;
  BpPresetVal: TBlueprintPreset;
  BpErrStr, BpEventStr, ActionStr: String;
  PcgAudit: TPcgSceneAuditReport;
  PcgComp: TCastlePcgGraph;
  PcgPresetVal: TPcgGraphPreset;
  PcgPts: TPcgPointArray;
  PcgNodeIdStr: String;
  AnimBpAudit: TAnimBlueprintAuditReport;
  AnimBpComp: TCastleAnimBlueprint;
  AnimBpPresetVal: TAnimBlueprintPreset;
  BtAudit: TBehaviorTreeAuditReport;
  BtComp: TCastleBehaviorTree;
  BtPresetVal: TBehaviorTreePreset;
  BtKeyStr: String;
  NiagAudit: TNiagaraSceneAuditReport;
  NiagComp: TCastleNiagaraSystem;
  NiagPresetVal: TNiagaraSystemPreset;
  NiagModId: String;
  UmgAudit: TUmgWidgetSceneAuditReport;
  UmgComp: TCastleWidgetAnimator;
  UmgPresetVal: TUmgWidgetAnimPreset;
  UmgClipStr: String;
  UmgTimeVal: Single;
  IkRtgAudit: TIkRetargetSceneAuditReport;
  IkRtgComp: TCastleIkRetargeter;
  IkRtgPresetVal: TIkRetargetPreset;
  PhAtAudit: TPhysicsAssetAuditReport;
  PhAtComp: TCastlePhysicsAsset;
  PhAtPresetVal: TPhAtAssetPreset;
  PhAtBodyStr: String;
  UvAudit: TUvSceneAuditReport;
  UvComp: TCastleUvEditorMesh;
  UvPresetVal: TUvMeshPreset;
  UvProjVal: TUvProjectionMode;
  LiAudit: TLevelInstanceAuditReport;
  LiComp: TCastleLevelInstance;
  LiPresetVal: TLevelInstancePreset;
  OfpaRepo: TOfpaActorFileEntryArray;
  OfpaArr: TJSONArray;
  OfpaObj: TJSONObject;
  MiAudit: TMaterialInstanceAuditReport;
  MiComp, MiParentOut, MiChildOut: TCastleMaterialInstance;
  MpcComp: TCastleMaterialParameterCollection;
  MpcPresetVal: TMpcEnvironmentPreset;
  MiSurf: TResolvedPbrSurface;
  MiParamStr: String;
  MiScalarVal: Single;
  MeshAudit: TMeshEditorSceneAudit;
  MeshComp: TCastleMeshEditorAsset;
  MeshPresetVal: TMeshEditorPreset;
  MeshMaxHulls: Integer;
  MeshSockStr: String;
  TanAuditRes: TMeshTangentAudit;
  RecastAudit: TRecastSceneAudit;
  RecastComp: TCastleRecastNavMesh;
  RecastPresetVal: TRecastNavPreset;
  RecastAgentH: Single;
  RecastPathRes: TRecastPathResult;
begin
  IsToolError := false;
  DoLog('[MCP] Tool call: ' + ToolName);

  if ToolName = 'cge_get_hierarchy' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('designUrl', DesignUrl);
      OutPayload.Add('designModified', DesignModified);
      if DesignRoot <> nil then
        OutPayload.Add('root', BuildHierarchyJson(DesignRoot))
      else
        OutPayload.Add('root', TJSONNull.Create);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_get_component_properties' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    CompName := '';
    OnlyNonDefault := false;
    if ArgsObj <> nil then
    begin
      CompName := ArgsObj.Get('name', '');
      OnlyNonDefault := ArgsObj.Get('onlyNonDefault', false);
    end;
    TargetComp := FindComponentInDesign(DesignRoot, DesignOwner, CompName);
    if TargetComp = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(Format('Component "%s" not found in design.', [CompName]), true));
    end;
    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('name', TargetComp.Name);
      OutPayload.Add('className', TargetComp.ClassName);
      OutPayload.Add('properties', BuildPropertiesJson(TargetComp, OnlyNonDefault));
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_list_component_classes' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    FilterStr := '';
    if ArgsObj <> nil then
      FilterStr := LowerCase(Trim(ArgsObj.Get('filter', '')));
    ClassesArr := TJSONArray.Create;
    try
      for Reg in RegisteredComponents do
        if (not Reg.IsDeprecated) and
           ((FilterStr = '') or (Pos(FilterStr, LowerCase(Reg.ComponentClass.ClassName)) > 0)) then
        begin
          OutPayload := TJSONObject.Create;
          OutPayload.Add('className', Reg.ComponentClass.ClassName);
          if Reg.ComponentClass.InheritsFrom(TCastleUserInterface) then
            OutPayload.Add('category', 'UserInterface')
          else
          if Reg.ComponentClass.InheritsFrom(TCastleTransform) then
            OutPayload.Add('category', 'Transform')
          else
          if Reg.ComponentClass.InheritsFrom(TCastleBehavior) then
            OutPayload.Add('category', 'Behavior')
          else
            OutPayload.Add('category', 'NonVisual');
          ClassesArr.Add(OutPayload);
        end;
      Result := MakeToolTextResult(ClassesArr.FormatJSON);
    finally
      FreeAndNil(ClassesArr);
    end;
    Exit;
  end;

  if ToolName = 'cge_set_component_properties' then
  begin
    if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    if (ArgsObj = nil) or (ArgsObj.Find('properties') = nil) or
       (not (ArgsObj.Find('properties') is TJSONObject)) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Missing "properties" object argument.', true));
    end;
    CompName := ArgsObj.Get('name', '');
    TargetComp := FindComponentInDesign(DesignRoot, DesignOwner, CompName);
    if TargetComp = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(Format('Component "%s" not found.', [CompName]), true));
    end;
    PropsMap := TJSONObject(ArgsObj.Find('properties'));
    for I := 0 to PropsMap.Count - 1 do
      if not SetSinglePropertyFromJson(TargetComp, PropsMap.Names[I], PropsMap.Items[I], ErrMsg) then
      begin
        IsToolError := true;
        Exit(MakeToolTextResult(ErrMsg, true));
      end;

    FStandaloneDesignModified := true;
    if Assigned(FOnAfterModify) then
      FOnAfterModify(Format('MCP set properties on %s', [TargetComp.Name]));

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('updatedComponent', TargetComp.Name);
      OutPayload.Add('updatedPropertiesCount', PropsMap.Count);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_add_component' then
  begin
    if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    ClassNameStr := '';
    ParentName := '';
    BaseName := '';
    if ArgsObj <> nil then
    begin
      ClassNameStr := ArgsObj.Get('className', '');
      ParentName := ArgsObj.Get('parentName', '');
      BaseName := ArgsObj.Get('baseName', '');
    end;
    Reg := FindRegisteredComp(ClassNameStr);
    if Reg = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(Format('Component class "%s" is not registered.', [ClassNameStr]), true));
    end;
    ParentComp := FindComponentInDesign(DesignRoot, DesignOwner, ParentName);
    if ParentComp = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(Format('Parent component "%s" not found.', [ParentName]), true));
    end;

    if Assigned(FOnAddComponent) then
    begin
      NewComp := FOnAddComponent(ParentComp, Reg.ComponentClass, Reg.OnCreate, BaseName);
      if NewComp = nil then
      begin
        IsToolError := true;
        Exit(MakeToolTextResult(Format('Editor refused adding %s under %s.', [ClassNameStr, ParentComp.Name]), true));
      end;
    end else
    begin
      NewComp := DefaultAddChildComponent(ParentComp, Reg, DesignOwner, BaseName, ErrMsg);
      if NewComp = nil then
      begin
        IsToolError := true;
        Exit(MakeToolTextResult(ErrMsg, true));
      end;
    end;

    if (ArgsObj <> nil) and (ArgsObj.Find('properties') is TJSONObject) then
    begin
      PropsMap := TJSONObject(ArgsObj.Find('properties'));
      for I := 0 to PropsMap.Count - 1 do
        if not SetSinglePropertyFromJson(NewComp, PropsMap.Names[I], PropsMap.Items[I], ErrMsg) then
        begin
          IsToolError := true;
          Exit(MakeToolTextResult(ErrMsg, true));
        end;
    end;

    FStandaloneDesignModified := true;
    if Assigned(FOnAfterModify) then
      FOnAfterModify(Format('MCP add %s (%s)', [NewComp.Name, NewComp.ClassName]));

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('name', NewComp.Name);
      OutPayload.Add('className', NewComp.ClassName);
      OutPayload.Add('parent', ParentComp.Name);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_delete_component' then
  begin
    if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    CompName := '';
    if ArgsObj <> nil then
      CompName := ArgsObj.Get('name', '');
    if CompName = '' then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Component "name" is required.', true));
    end;
    TargetComp := FindComponentInDesign(DesignRoot, DesignOwner, CompName);
    if TargetComp = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(Format('Component "%s" not found.', [CompName]), true));
    end;
    if TargetComp = DesignRoot then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Cannot delete DesignRoot.', true));
    end;
    if (csTransient in TargetComp.ComponentStyle) or
       (csSubComponent in TargetComp.ComponentStyle) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(Format('Component "%s" is an internal/subcomponent and cannot be deleted.', [CompName]), true));
    end;

    if Assigned(FOnDeleteComponent) then
    begin
      if not FOnDeleteComponent(TargetComp, ErrMsg) then
      begin
        IsToolError := true;
        Exit(MakeToolTextResult(ErrMsg, true));
      end;
    end else
      FreeAndNil(TargetComp);

    FStandaloneDesignModified := true;
    if Assigned(FOnAfterModify) then
      FOnAfterModify(Format('MCP delete %s', [CompName]));

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('deleted', CompName);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_execute_layout_action' then
  begin
    if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    if (ArgsObj = nil) or (not (ArgsObj.Find('targets') is TJSONArray)) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Missing "targets" component name array.', true));
    end;
    ActionName := LowerCase(Trim(ArgsObj.Get('action', '')));
    GridStep := ArgsObj.Get('gridStep', 1.0);
    RadiusVal := ArgsObj.Get('radius', 5.0);
    ColumnsCount := Max(1, ArgsObj.Get('columns', 3));
    TargetsArr := TJSONArray(ArgsObj.Find('targets'));

    CompList := TComponentList.Create(false);
    Manip := TCastleTransformManipulate.Create(nil);
    try
      for I := 0 to TargetsArr.Count - 1 do
      begin
        TargetComp := FindComponentInDesign(DesignRoot, DesignOwner, TargetsArr.Strings[I]);
        if TargetComp <> nil then
          CompList.Add(TargetComp);
      end;
      if CompList.Count = 0 then
      begin
        IsToolError := true;
        Exit(MakeToolTextResult('None of the target components were found.', true));
      end;

      if ActionName = 'center_in_parent' then
      begin
        for I := 0 to CompList.Count - 1 do
          if CompList[I] is TCastleUserInterface then
          begin
            UI := TCastleUserInterface(CompList[I]);
            UI.Anchor(hpMiddle, 0);
            UI.Anchor(vpMiddle, 0);
          end;
      end else
      begin
        Manip.SetSelected(CompList);
        if ActionName = 'snap_to_grid' then
        begin
          Manip.TranslateSnap := Max(0.01, GridStep);
          Manip.SnapSelectedToGrid;
        end
        else
        if ActionName = 'reset_transform' then
          Manip.ResetSelectedTransform(true, true, true)
        else
        if ActionName = 'align_x' then
          Manip.AlignSelected(0)
        else
        if ActionName = 'align_y' then
          Manip.AlignSelected(1)
        else
        if ActionName = 'align_z' then
          Manip.AlignSelected(2)
        else
        if ActionName = 'distribute_x' then
          Manip.DistributeSelected(0)
        else
        if ActionName = 'distribute_y' then
          Manip.DistributeSelected(1)
        else
        if ActionName = 'distribute_z' then
          Manip.DistributeSelected(2)
        else
        if ActionName = 'arrange_circle' then
          Manip.ArrangeSelectedInCircle(RadiusVal, 360.0, true)
        else
        if ActionName = 'arrange_grid' then
          Manip.ArrangeSelectedInGrid(ColumnsCount, 0, Vector3(GridStep, 0, GridStep), true)
        else
        begin
          IsToolError := true;
          Exit(MakeToolTextResult('Unknown layout action: ' + ActionName, true));
        end;
      end;

      FStandaloneDesignModified := true;
      if Assigned(FOnAfterModify) then
        FOnAfterModify(Format('MCP layout %s (%d items)', [ActionName, CompList.Count]));

      OutPayload := TJSONObject.Create;
      try
        OutPayload.Add('action', ActionName);
        OutPayload.Add('affectedCount', CompList.Count);
        Result := MakeToolTextResult(OutPayload.FormatJSON);
      finally
        FreeAndNil(OutPayload);
      end;
    finally
      FreeAndNil(Manip);
      FreeAndNil(CompList);
    end;
    Exit;
  end;

  if ToolName = 'cge_undo_redo' then
  begin
    if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    DirectionStr := 'undo';
    if ArgsObj <> nil then
      DirectionStr := LowerCase(Trim(ArgsObj.Get('direction', 'undo')));
    IsRedo := DirectionStr = 'redo';
    if not Assigned(FOnUndoRedo) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Undo/Redo host callback is not attached.', true));
    end;
    if not FOnUndoRedo(IsRedo, UndoDesc) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(Format('Nothing available to %s.', [DirectionStr]), true));
    end;
    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('direction', DirectionStr);
      OutPayload.Add('comment', UndoDesc);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_capture_viewport_screenshot' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    if not Assigned(FOnCaptureScreenshot) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Viewport screenshot callback is not available.', true));
    end;
    ScreenshotImg := FOnCaptureScreenshot();
    if ScreenshotImg = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Viewport OpenGL context is not active or no design is open.', true));
    end;
    PngStream := TMemoryStream.Create;
    try
      SaveImage(ScreenshotImg, 'image/png', PngStream);
      SetLength(EncodedPng, 0);
      if PngStream.Size > 0 then
      begin
        SetString(EncodedPng, PChar(PngStream.Memory), PngStream.Size);
        EncodedPng := EncodeStringBase64(EncodedPng);
      end;
      Result := TJSONObject.Create;
      ContentArr := TJSONArray.Create;
      MetaBlock := TJSONObject.Create;
      MetaBlock.Add('type', 'text');
      MetaBlock.Add('text', Format('Captured viewport screenshot (%dx%d PNG)',
        [ScreenshotImg.Width, ScreenshotImg.Height]));
      ContentArr.Add(MetaBlock);
      ImgBlock := TJSONObject.Create;
      ImgBlock.Add('type', 'image');
      ImgBlock.Add('data', EncodedPng);
      ImgBlock.Add('mimeType', 'image/png');
      ContentArr.Add(ImgBlock);
      Result.Add('content', ContentArr);
    finally
      FreeAndNil(PngStream);
      FreeAndNil(ScreenshotImg);
    end;
    Exit;
  end;

  if ToolName = 'cge_get_build_output' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    MaxLines := 50;
    if ArgsObj <> nil then
      MaxLines := Clamped(ArgsObj.Get('maxLines', 50), 1, 500);
    OutLines := TStringList.Create;
    OutPayload := TJSONObject.Create;
    try
      WarnCount := 0;
      ErrCount := 0;
      if Assigned(FOnGetBuildOutput) then
        FOnGetBuildOutput(MaxLines, OutLines, WarnCount, ErrCount);
      OutPayload.Add('warningsCount', WarnCount);
      OutPayload.Add('errorsCount', ErrCount);
      LinesArr := TJSONArray.Create;
      for I := 0 to OutLines.Count - 1 do
        LinesArr.Add(OutLines[I]);
      OutPayload.Add('lines', LinesArr);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
      FreeAndNil(OutLines);
    end;
    Exit;
  end;

  if ToolName = 'cge_save_design' then
  begin
    if not RequireAutonomy(mamFullControl, Result) then Exit;
    if not Assigned(FOnSaveDesign) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Save design callback is not attached.', true));
    end;
    if not FOnSaveDesign(ErrMsg) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(ErrMsg, true));
    end;
    Exit(MakeToolTextResult('{"saved":true}'));
  end;

  if ToolName = 'cge_run_build_command' then
  begin
    if not RequireAutonomy(mamFullControl, Result) then Exit;
    CmdStr := '';
    if ArgsObj <> nil then
      CmdStr := LowerCase(Trim(ArgsObj.Get('command', '')));
    if not Assigned(FOnRunBuildCommand) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('Build command callback is not attached.', true));
    end;
    if not FOnRunBuildCommand(CmdStr, ErrMsg) then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult(ErrMsg, true));
    end;
    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('command', CmdStr);
      OutPayload.Add('status', ErrMsg);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_list_studios' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    FilterStr := '';
    CatFilter := -1;
    if ArgsObj <> nil then
    begin
      FilterStr := ArgsObj.Get('query', '');
      CatFilter := ArgsObj.Get('category', -1);
    end;
    TStudioHubManager.FilterStudios(CatFilter, FilterStr, StudioMatches);
    OutPayload := TJSONObject.Create;
    ClassesArr := TJSONArray.Create;
    try
      OutPayload.Add('totalCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('matchedCount', Length(StudioMatches));
      for I := 0 to High(StudioMatches) do
      begin
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('studioId', StudioMatches[I].StudioId);
        StudioItemObj.Add('title', StudioMatches[I].Title);
        StudioItemObj.Add('shortBadge', StudioMatches[I].ShortBadge);
        StudioItemObj.Add('category', TStudioHubManager.CategoryDisplayName(StudioMatches[I].Category));
        StudioItemObj.Add('phaseNumber', StudioMatches[I].PhaseNumber);
        StudioItemObj.Add('summary', StudioMatches[I].Summary);
        ClassesArr.Add(StudioItemObj);
      end;
      OutPayload.Add('studios', ClassesArr);
      ClassesArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(ClassesArr);
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_audit_world_readiness' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    HealthReport := TStudioHubManager.AuditEntireDesign(DesignRoot, DesignOwner);
    OutPayload := TJSONObject.Create;
    LinesArr := TJSONArray.Create;
    try
      OutPayload.Add('readinessScore', HealthReport.ReadinessScore);
      OutPayload.Add('readinessGrade', HealthReport.ReadinessGrade);
      OutPayload.Add('totalTransforms', HealthReport.TotalTransforms);
      OutPayload.Add('totalUserInterfaces', HealthReport.TotalUserInterfaces);
      OutPayload.Add('totalModernSubsystems', HealthReport.TotalModernSubsystems);
      OutPayload.Add('issuesCount', Length(HealthReport.Issues));
      for I := 0 to High(HealthReport.Issues) do
      begin
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('severityPoints', HealthReport.Issues[I].SeverityPoints);
        StudioItemObj.Add('recommendedStudioId', HealthReport.Issues[I].RecommendedStudioId);
        StudioItemObj.Add('message', HealthReport.Issues[I].MessageText);
        LinesArr.Add(StudioItemObj);
      end;
      OutPayload.Add('issues', LinesArr);
      LinesArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(LinesArr);
      FreeAndNil(OutPayload);
      FreeAndNil(HealthReport);
    end;
    Exit;
  end;

  if ToolName = 'cge_capture_telemetry_trace' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    MaxLines := 30;
    IncludeChromeTrace := False;
    if ArgsObj <> nil then
    begin
      MaxLines := EnsureRange(ArgsObj.Get('frames', 30), 1, 120);
      IncludeChromeTrace := ArgsObj.Get('includeChromeTrace', False);
    end;
    TelemetryProf := TTelemetryInsightsProfiler.Create(120);
    OutPayload := TJSONObject.Create;
    try
      TelemetryProf.CaptureLiveHierarchyProfileRun(DesignRoot, DesignOwner, MaxLines);
      TelemetryStats := TelemetryProf.ComputeAggregateStats(16.67);
      OutPayload.Add('capturedFrames', TelemetryStats.CapturedFrames);
      OutPayload.Add('totalSpansRecorded', TelemetryStats.TotalSpansRecorded);
      OutPayload.Add('meanFrameMs', TelemetryStats.MeanFrameMs);
      OutPayload.Add('minFrameMs', TelemetryStats.MinFrameMs);
      OutPayload.Add('maxFrameMs', TelemetryStats.MaxFrameMs);
      OutPayload.Add('p50FrameMs', TelemetryStats.P50FrameMs);
      OutPayload.Add('p95FrameMs', TelemetryStats.P95FrameMs);
      OutPayload.Add('p99FrameMs', TelemetryStats.P99FrameMs);
      OutPayload.Add('hitchSpikeCount', TelemetryStats.HitchSpikeCount);
      OutPayload.Add('topHotspotCategory', TelemetryStats.TopHotspotCategory);
      if IncludeChromeTrace then
        OutPayload.Add('traceEvents', TelemetryProf.ExportChromeTraceEventsArray);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
      FreeAndNil(TelemetryProf);
    end;
    Exit;
  end;

  if ToolName = 'cge_verify_determinism_hash' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    MaxLines := 20;
    DetSeed := 20260346;
    if ArgsObj <> nil then
    begin
      MaxLines := EnsureRange(ArgsObj.Get('steps', 20), 1, 240);
      DetSeed := ArgsObj.Get('seed', 20260346);
    end;
    DetSnap := TDeterminismRegressionHarness.CaptureWorldSnapshot(
      DesignRoot, DesignOwner, 'McpBaseline', 0, DetSeed);
    OutPayload := TJSONObject.Create;
    try
      DetAudit := TDeterminismRegressionHarness.VerifyDualRunDeterminism(
        DesignRoot, DesignOwner, MaxLines, 1.0 / 60.0, DetSeed);
      OutPayload.Add('worldHashHex', DetSnap.WorldHashHex);
      OutPayload.Add('bitExactMatch', DetAudit.BitExactMatch);
      OutPayload.Add('runAHashHex', DetAudit.RunAHashHex);
      OutPayload.Add('runBHashHex', DetAudit.RunBHashHex);
      OutPayload.Add('actorsCompared', DetAudit.ActorsCompared);
      OutPayload.Add('driftedActorCount', DetAudit.DriftedActorCount);
      OutPayload.Add('maxPositionDriftMeters', DetAudit.MaxPositionDriftMeters);
      OutPayload.Add('stateRestoredCleanly', DetAudit.StateRestoredCleanly);
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
      FreeAndNil(DetSnap);
    end;
    Exit;
  end;

  if ToolName = 'cge_audit_package_cook' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;
    CheckDiskUrls := False;
    if ArgsObj <> nil then
      CheckDiskUrls := ArgsObj.Get('checkDiskUrls', False);
    CookRep := TLiveCodingCookBroker.AuditPackageCookReadiness(DesignRoot, DesignOwner, CheckDiskUrls);
    OutPayload := TJSONObject.Create;
    LinesArr := TJSONArray.Create;
    try
      for I := 0 to CookRep.Findings.Count - 1 do
        LinesArr.Add(CookRep.Findings[I]);
      OutPayload.Add('cookReadinessScore', CookRep.CookReadinessScore);
      OutPayload.Add('cookReadyToShip', CookRep.CookReadyToShip);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('totalCookableComponents', CookRep.TotalCookableComponents);
      OutPayload.Add('brokenAssetUrlCount', CookRep.BrokenAssetUrlCount);
      OutPayload.Add('chooserIssueCount', CookRep.ChooserIssueCount);
      OutPayload.Add('invertedSoftBodyCount', CookRep.InvertedSoftBodyCount);
      OutPayload.Add('trafficHazardCount', CookRep.TrafficHazardCount);
      OutPayload.Add('estimatedCookedPayloadKB', CookRep.EstimatedCookedPayloadKB);
      OutPayload.Add('findings', LinesArr);
      LinesArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(LinesArr);
      FreeAndNil(OutPayload);
      FreeAndNil(CookRep);
    end;
    Exit;
  end;

  if ToolName = 'cge_manage_collab_locks' then
  begin
    ActionName := 'list';
    BaseName := '';
    CompName := '';
    CollabLeaseSec := 30.0;
    if ArgsObj <> nil then
    begin
      ActionName := LowerCase(Trim(ArgsObj.Get('action', 'list')));
      BaseName := Trim(ArgsObj.Get('userId', ''));
      CompName := Trim(ArgsObj.Get('subtree', ''));
      CollabLeaseSec := ArgsObj.Get('leaseSec', 30.0);
    end;
    if SameText(ActionName, 'list') then
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    ErrMsg := '';
    CollabOk := True;
    if SameText(ActionName, 'acquire') then
      CollabOk := TCollabPresenceBroker.SharedBroker.AcquireSubtreeLock(
        DesignRoot, BaseName, BaseName, CompName, CollabLeaseSec, ErrMsg)
    else if SameText(ActionName, 'release') then
      CollabOk := TCollabPresenceBroker.SharedBroker.ReleaseSubtreeLock(BaseName, CompName)
    else if SameText(ActionName, 'heartbeat') then
      CollabOk := TCollabPresenceBroker.SharedBroker.RenewHeartbeat(BaseName, CompName, CollabLeaseSec)
    else if SameText(ActionName, 'expire') then
      TCollabPresenceBroker.SharedBroker.ExpireStaleLocks;

    OutPayload := TJSONObject.Create;
    TargetsArr := TJSONArray.Create;
    try
      for I := 0 to TCollabPresenceBroker.SharedBroker.ActiveLockCount - 1 do
      begin
        CollabLock := TCollabPresenceBroker.SharedBroker.GetLock(I);
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('lockId', CollabLock.LockId);
        StudioItemObj.Add('userId', CollabLock.UserId);
        StudioItemObj.Add('subtree', CollabLock.SubtreeRootName);
        StudioItemObj.Add('leaseExpiresAtSec', CollabLock.LeaseExpiresAtSec);
        StudioItemObj.Add('heartbeats', CollabLock.HeartbeatCount);
        TargetsArr.Add(StudioItemObj);
      end;
      OutPayload.Add('ok', CollabOk);
      OutPayload.Add('action', ActionName);
      OutPayload.Add('conflictReason', ErrMsg);
      OutPayload.Add('activeLockCount', TCollabPresenceBroker.SharedBroker.ActiveLockCount);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('locks', TargetsArr);
      TargetsArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(TargetsArr);
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_run_editor_macro' then
  begin
    ActionName := 'status';
    FilterStr := '';
    MacroMult := 1.0;
    if ArgsObj <> nil then
    begin
      ActionName := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      FilterStr := Trim(ArgsObj.Get('targetFilter', ''));
      MacroMult := ArgsObj.Get('multiplier', 1.0);
    end;

    if SameText(ActionName, 'status') then
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    CollabOk := True;
    MacroAffected := 0;
    ErrMsg := '';

    if SameText(ActionName, 'clear') then
      TEditorMacroRecorder.SharedRecorder.ClearSteps
    else if SameText(ActionName, 'record_step') then
    begin
      if (ArgsObj = nil) or (not TEditorMacroRecorder.StringToStepKind(
         ArgsObj.Get('stepKind', 'add_translate'), MacroStepKind)) then
      begin
        CollabOk := False;
        ErrMsg := 'INVALID_STEP_KIND';
      end else
        TEditorMacroRecorder.SharedRecorder.RecordStep(
          MacroStepKind,
          FilterStr,
          Vector3(
            ArgsObj.Get('vecX', 0.0),
            ArgsObj.Get('vecY', 0.0),
            ArgsObj.Get('vecZ', 0.0)),
          ArgsObj.Get('scalarParam', 0.0),
          ArgsObj.Get('strParam', ''));
    end else if SameText(ActionName, 'import_json') then
    begin
      CollabOk := (ArgsObj <> nil) and
        TEditorMacroRecorder.SharedRecorder.ImportMacroJson(ArgsObj.Get('macroJson', ''));
      if not CollabOk then
        ErrMsg := 'INVALID_MACRO_JSON';
    end else if SameText(ActionName, 'replay') then
    begin
      if DesignRoot = nil then
      begin
        CollabOk := False;
        ErrMsg := 'NO_OPEN_DESIGN';
      end else
      begin
        MacroAffected := TEditorMacroRecorder.SharedRecorder.ReplayMacro(DesignRoot, MacroMult);
        if (MacroAffected > 0) and Assigned(FOnAfterModify) then
          FOnAfterModify(Format('MCP replay macro %s (%d transforms)',
            [TEditorMacroRecorder.SharedRecorder.MacroName, MacroAffected]));
      end;
    end;

    OutPayload := TJSONObject.Create;
    TargetsArr := TJSONArray.Create;
    try
      for I := 0 to TEditorMacroRecorder.SharedRecorder.StepCount - 1 do
      begin
        MacroStepItem := TEditorMacroRecorder.SharedRecorder.GetStep(I);
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('kind', TEditorMacroRecorder.StepKindToString(MacroStepItem.Kind));
        StudioItemObj.Add('targetFilter', MacroStepItem.TargetFilter);
        StudioItemObj.Add('vecX', MacroStepItem.VecParam.X);
        StudioItemObj.Add('vecY', MacroStepItem.VecParam.Y);
        StudioItemObj.Add('vecZ', MacroStepItem.VecParam.Z);
        StudioItemObj.Add('scalarParam', MacroStepItem.ScalarParam);
        StudioItemObj.Add('strParam', MacroStepItem.StrParam);
        TargetsArr.Add(StudioItemObj);
      end;
      OutPayload.Add('ok', CollabOk);
      OutPayload.Add('action', ActionName);
      OutPayload.Add('errorReason', ErrMsg);
      OutPayload.Add('macroName', TEditorMacroRecorder.SharedRecorder.MacroName);
      OutPayload.Add('stepCount', TEditorMacroRecorder.SharedRecorder.StepCount);
      OutPayload.Add('affectedTransforms', MacroAffected);
      OutPayload.Add('replayCount', TEditorMacroRecorder.SharedRecorder.ReplayCount);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('macroJson', TEditorMacroRecorder.SharedRecorder.ExportMacroJson);
      OutPayload.Add('steps', TargetsArr);
      TargetsArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(TargetsArr);
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_diff_merge_scene' then
  begin
    ActionName := 'status';
    DiffBaseStr := '';
    DiffOursStr := '';
    DiffTheirsStr := '';
    DiffPolicy := mcpPreferOurs;
    if ArgsObj <> nil then
    begin
      ActionName := LowerCase(Trim(ArgsObj.Get('action', 'diff_three_way')));
      DiffBaseStr := ArgsObj.Get('baseJson', '');
      DiffOursStr := ArgsObj.Get('oursJson', '');
      DiffTheirsStr := ArgsObj.Get('theirsJson', '');
      DiffPolicy := TPrefabDiffMergeEngine.StringToPolicy(
        ArgsObj.Get('conflictPolicy', 'prefer_ours'));
    end;

    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);

    if SameText(ActionName, 'capture_base') then
    begin
      TPrefabDiffMergeEngine.SharedEngine.CaptureBaseSnapshotFromComponent(DesignRoot);
      DiffMergeRep := TPrefabDiffMergeEngine.SharedEngine.LastReport;
    end else
    if SameText(ActionName, 'diff_three_way') then
    begin
      if (DiffBaseStr = '') and (TPrefabDiffMergeEngine.SharedEngine.CapturedBaseJson <> '') then
        DiffBaseStr := TPrefabDiffMergeEngine.SharedEngine.CapturedBaseJson;
      if (DiffOursStr = '') and (DesignRoot <> nil) then
        DiffOursStr := ComponentToString(DesignRoot);
      DiffMergeRep := TPrefabDiffMergeEngine.SharedEngine.RunMergeAndStore(
        DiffBaseStr, DiffOursStr, DiffTheirsStr, DiffPolicy);
    end else
      DiffMergeRep := TPrefabDiffMergeEngine.SharedEngine.LastReport;

    OutPayload := TJSONObject.Create;
    TargetsArr := TJSONArray.Create;
    try
      for I := 0 to High(DiffMergeRep.Changes) do
      begin
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('component', DiffMergeRep.Changes[I].ComponentName);
        StudioItemObj.Add('property', DiffMergeRep.Changes[I].PropertyPath);
        StudioItemObj.Add('kind', TPrefabDiffMergeEngine.ChangeKindToString(DiffMergeRep.Changes[I].Kind));
        StudioItemObj.Add('resolved', DiffMergeRep.Changes[I].ResolvedValueJson);
        TargetsArr.Add(StudioItemObj);
      end;
      OutPayload.Add('ok', True);
      OutPayload.Add('action', ActionName);
      OutPayload.Add('policy', TPrefabDiffMergeEngine.PolicyToString(DiffMergeRep.PolicyUsed));
      OutPayload.Add('autoMergedCount', DiffMergeRep.AutoMergedCount);
      OutPayload.Add('conflictCount', DiffMergeRep.ConflictCount);
      OutPayload.Add('addedNodesCount', DiffMergeRep.AddedNodesCount);
      OutPayload.Add('deletedNodesCount', DiffMergeRep.DeletedNodesCount);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('mergedJson', DiffMergeRep.MergedSceneJson);
      OutPayload.Add('changes', TargetsArr);
      TargetsArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(TargetsArr);
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_audit_scene_budget' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ActionName := 'audit_viewport';
    BudgetLimitVal := 8192.0;
    NodeCapVal := 2048.0;
    TreemapW := 640.0;
    TreemapH := 360.0;
    if ArgsObj <> nil then
    begin
      ActionName := ArgsObj.Get('action', 'audit_viewport');
      BudgetLimitVal := ArgsObj.Get('budgetLimitKB', 8192.0);
      NodeCapVal := ArgsObj.Get('perNodeCapKB', 2048.0);
      TreemapW := ArgsObj.Get('canvasWidth', 640.0);
      TreemapH := ArgsObj.Get('canvasHeight', 360.0);
    end;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if SameText(ActionName, 'status') then
      BudgetRep := TSceneBudgetTreemapAnalyzer.SharedAnalyzer.LastReport
    else
      BudgetRep := TSceneBudgetTreemapAnalyzer.SharedAnalyzer.AnalyzeSceneTreemap(
        DesignRoot, BudgetLimitVal, NodeCapVal, TreemapW, TreemapH);

    OutPayload := TJSONObject.Create;
    TargetsArr := TJSONArray.Create;
    try
      for I := 0 to High(BudgetRep.Cells) do
      begin
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('name', BudgetRep.Cells[I].ComponentName);
        StudioItemObj.Add('className', BudgetRep.Cells[I].ComponentClassName);
        StudioItemObj.Add('memoryKB', BudgetRep.Cells[I].EstimatedMemoryKB);
        StudioItemObj.Add('triangles', BudgetRep.Cells[I].EstimatedTriangles);
        StudioItemObj.Add('rectX', BudgetRep.Cells[I].RectX);
        StudioItemObj.Add('rectY', BudgetRep.Cells[I].RectY);
        StudioItemObj.Add('rectW', BudgetRep.Cells[I].RectW);
        StudioItemObj.Add('rectH', BudgetRep.Cells[I].RectH);
        StudioItemObj.Add('overCap', BudgetRep.Cells[I].IsOverNodeCap);
        TargetsArr.Add(StudioItemObj);
      end;
      OutPayload.Add('ok', True);
      OutPayload.Add('action', ActionName);
      OutPayload.Add('totalComponents', BudgetRep.TotalComponents);
      OutPayload.Add('totalEstimatedMemoryKB', BudgetRep.TotalEstimatedMemoryKB);
      OutPayload.Add('totalEstimatedTriangles', BudgetRep.TotalEstimatedTriangles);
      OutPayload.Add('overBudgetNodeCount', BudgetRep.OverBudgetNodeCount);
      OutPayload.Add('worstCellAspectRatio', BudgetRep.WorstCellAspectRatio);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('cells', TargetsArr);
      TargetsArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(TargetsArr);
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_optimize_lod_instancing' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ActionName := 'analyze_scene';
    MinBatchInstVal := 2;
    LodFovVal := 60.0;
    LodMinTrisVal := 500;
    if ArgsObj <> nil then
    begin
      ActionName := ArgsObj.Get('action', 'analyze_scene');
      MinBatchInstVal := ArgsObj.Get('minBatchInstances', 2);
      LodFovVal := ArgsObj.Get('verticalFovDeg', 60.0);
      LodMinTrisVal := ArgsObj.Get('lodMinTriangles', 500);
    end;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if SameText(ActionName, 'status') then
      LodInstRep := TLodInstancingOptimizer.SharedOptimizer.LastReport
    else
      LodInstRep := TLodInstancingOptimizer.SharedOptimizer.AnalyzeSceneInstancingAndLod(
        DesignRoot, MinBatchInstVal, LodFovVal, LodMinTrisVal);

    OutPayload := TJSONObject.Create;
    TargetsArr := TJSONArray.Create;
    ClassesArr := TJSONArray.Create;
    try
      for I := 0 to High(LodInstRep.Batches) do
      begin
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('signature', LodInstRep.Batches[I].SignatureKey);
        StudioItemObj.Add('representative', LodInstRep.Batches[I].RepresentativeName);
        StudioItemObj.Add('instances', LodInstRep.Batches[I].InstanceCount);
        StudioItemObj.Add('savedDrawCalls', LodInstRep.Batches[I].SavedDrawCalls);
        TargetsArr.Add(StudioItemObj);
      end;
      for I := 0 to High(LodInstRep.LodPlans) do
      begin
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('archetype', LodInstRep.LodPlans[I].ArchetypeName);
        StudioItemObj.Add('baseTriangles', LodInstRep.LodPlans[I].BaseLod0Triangles);
        StudioItemObj.Add('lod1DistMeters', LodInstRep.LodPlans[I].Tiers[1].EnterDistanceMeters);
        StudioItemObj.Add('lod2DistMeters', LodInstRep.LodPlans[I].Tiers[2].EnterDistanceMeters);
        StudioItemObj.Add('lod3DistMeters', LodInstRep.LodPlans[I].Tiers[3].EnterDistanceMeters);
        ClassesArr.Add(StudioItemObj);
      end;
      OutPayload.Add('ok', True);
      OutPayload.Add('action', ActionName);
      OutPayload.Add('totalTransforms', LodInstRep.TotalAnalyzedTransforms);
      OutPayload.Add('baselineDrawCalls', LodInstRep.BaselineDrawCalls);
      OutPayload.Add('optimizedDrawCalls', LodInstRep.OptimizedDrawCalls);
      OutPayload.Add('savedDrawCalls', LodInstRep.PotentialDrawCallReduction);
      OutPayload.Add('reductionPercent', LodInstRep.ReductionPercent);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('batches', TargetsArr);
      TargetsArr := nil;
      OutPayload.Add('lodPlans', ClassesArr);
      ClassesArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(ClassesArr);
      FreeAndNil(TargetsArr);
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_audit_overdraw_shaders' then
  begin
    if not RequireAutonomy(mamReadOnly, Result) then Exit;
    ActionName := 'audit_viewport';
    MaxTransLayersVal := 3;
    AluCapVal := 320;
    if ArgsObj <> nil then
    begin
      ActionName := ArgsObj.Get('action', 'audit_viewport');
      MaxTransLayersVal := ArgsObj.Get('maxTranslucentLayers', 3);
      AluCapVal := ArgsObj.Get('aluHotspotCap', 320);
    end;
    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if SameText(ActionName, 'status') then
      OverdrawRep := TShaderComplexityAuditor.SharedAuditor.LastReport
    else
      OverdrawRep := TShaderComplexityAuditor.SharedAuditor.AuditViewportOverdraw(
        DesignRoot, MaxTransLayersVal, AluCapVal);

    OutPayload := TJSONObject.Create;
    TargetsArr := TJSONArray.Create;
    try
      for I := 0 to High(OverdrawRep.Contributors) do
      begin
        StudioItemObj := TJSONObject.Create;
        StudioItemObj.Add('name', OverdrawRep.Contributors[I].ComponentName);
        StudioItemObj.Add('translucent', OverdrawRep.Contributors[I].IsTranslucent);
        StudioItemObj.Add('estimatedAlu', OverdrawRep.Contributors[I].EstimatedAluCost);
        StudioItemObj.Add('coveredTiles', OverdrawRep.Contributors[I].CoveredTileCount);
        StudioItemObj.Add('remediation', OverdrawRep.Contributors[I].RemediationHint);
        TargetsArr.Add(StudioItemObj);
      end;
      OutPayload.Add('ok', True);
      OutPayload.Add('action', ActionName);
      OutPayload.Add('analyzedLayerCount', OverdrawRep.AnalyzedLayerCount);
      OutPayload.Add('opaqueLayerCount', OverdrawRep.OpaqueLayerCount);
      OutPayload.Add('translucentLayerCount', OverdrawRep.TranslucentLayerCount);
      OutPayload.Add('peakTranslucentOverdraw', OverdrawRep.PeakTranslucentOverdraw);
      OutPayload.Add('peakTileAluInstructions', OverdrawRep.PeakTileAluInstructions);
      OutPayload.Add('averageTileAluInstructions', OverdrawRep.AverageTileAluInstructions);
      OutPayload.Add('hotspotTileCount', OverdrawRep.HotspotTileCount);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('contributors', TargetsArr);
      TargetsArr := nil;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(TargetsArr);
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_compile_blueprint' then
  begin
    ActionStr := 'status';
    CompName := '';
    BpEventStr := 'begin_play';
    MacroMult := 0.25;
    BpPresetVal := bppPillarRowConstructionAndSpinPickup;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      BpEventStr := Trim(ArgsObj.Get('eventName', 'begin_play'));
      MacroMult := ArgsObj.Get('deltaSec', 0.25);
      if SameText(ArgsObj.Get('preset', ''), 'door_timeline') then
        BpPresetVal := bppSlidingDoorTimelineAndGate
      else if SameText(ArgsObj.Get('preset', ''), 'warmup_branch') then
        BpPresetVal := bppPatrolBranchAndLatentDelay;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'run_construction') or
       SameText(ActionStr, 'fire_event') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      BpComp := TBlueprintEditorHelper.SpawnBlueprintPresetInDesign(
        DesignRoot, DesignOwner, BpPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn Blueprint');
    end else
      BpComp := TBlueprintEditorHelper.FindBlueprintByName(DesignRoot, DesignOwner, CompName);

    BpErrStr := '';
    if SameText(ActionStr, 'compile') then
      BpAudit := TBlueprintEditorHelper.CompileAllBlueprintsInDesign(DesignRoot, BpErrStr)
    else
    begin
      if (BpComp <> nil) and SameText(ActionStr, 'run_construction') then
        BpComp.RunConstructionScript
      else if (BpComp <> nil) and SameText(ActionStr, 'fire_event') then
      begin
        if SameText(BpEventStr, 'begin_play') then
          BpComp.ExecuteBeginPlay
        else if SameText(BpEventStr, 'tick') then
          BpComp.StepBlueprintTick(MacroMult)
        else if SameText(BpEventStr, 'overlap') then
          BpComp.ExecuteActorBeginOverlap('McpAgent')
        else
          BpComp.ExecuteCustomEvent(BpEventStr);
      end;
      BpAudit := TBlueprintEditorHelper.AuditBlueprintsInDesign(DesignRoot);
    end;

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('blueprintCount', BpAudit.BlueprintCount);
      OutPayload.Add('compiledOkCount', BpAudit.CompiledOkCount);
      OutPayload.Add('errorBlueprintCount', BpAudit.ErrorBlueprintCount);
      OutPayload.Add('totalNodeCount', BpAudit.TotalNodeCount);
      OutPayload.Add('totalVariableCount', BpAudit.TotalVariableCount);
      OutPayload.Add('totalConstructionMeshes', BpAudit.TotalConstructionMeshes);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('compileErrors', BpErrStr);
      if BpComp <> nil then
      begin
        OutPayload.Add('activeBlueprint', BpComp.Name);
        OutPayload.Add('summaryBadge', BpComp.BlueprintSummaryBadge);
        if SameText(ActionStr, 'generate_pascal') then
          OutPayload.Add('pascalUnit', BpComp.GeneratePascalUnit);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_execute_pcg_graph' then
  begin
    ActionStr := 'status';
    CompName := '';
    PcgNodeIdStr := '';
    DetSeed := 4242;
    PcgPresetVal := pgpForestWithRoadClearing;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      PcgNodeIdStr := Trim(ArgsObj.Get('nodeId', ''));
      DetSeed := ArgsObj.Get('seed', 4242);
      if SameText(ArgsObj.Get('preset', ''), 'rock_union') then
        PcgPresetVal := pgpRockOutcropAndShrubUnion
      else if SameText(ArgsObj.Get('preset', ''), 'spline_posts') then
        PcgPresetVal := pgpSplineFenceColonnade;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'execute') or
       SameText(ActionStr, 'reseed') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      PcgComp := TPcgGraphHelper.SpawnPcgPresetInDesign(
        DesignRoot, DesignOwner, PcgPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn PCG Graph');
    end else
      PcgComp := TPcgGraphHelper.FindPcgGraphByName(DesignRoot, DesignOwner, CompName);

    BpErrStr := '';
    if SameText(ActionStr, 'execute') then
      PcgAudit := TPcgGraphHelper.ExecuteAllPcgGraphsInDesign(DesignRoot, BpErrStr)
    else
    begin
      if (PcgComp <> nil) and SameText(ActionStr, 'reseed') then
        PcgComp.GraphSeed := DetSeed;
      PcgAudit := TPcgGraphHelper.AuditPcgGraphsInDesign(DesignRoot);
    end;

    PcgPts := nil;
    if (PcgComp <> nil) and SameText(ActionStr, 'inspect_node') and (PcgNodeIdStr <> '') then
      PcgComp.EvaluateNodeOutput(PcgNodeIdStr, PcgPts);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('graphCount', PcgAudit.GraphCount);
      OutPayload.Add('validGraphCount', PcgAudit.ValidGraphCount);
      OutPayload.Add('errorGraphCount', PcgAudit.ErrorGraphCount);
      OutPayload.Add('totalNodeCount', PcgAudit.TotalNodeCount);
      OutPayload.Add('totalSpawnedInstances', PcgAudit.TotalSpawnedInstances);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      OutPayload.Add('validationErrors', BpErrStr);
      if PcgComp <> nil then
      begin
        OutPayload.Add('activeGraph', PcgComp.Name);
        OutPayload.Add('summaryBadge', PcgComp.PcgSummaryBadge);
        if SameText(ActionStr, 'inspect_node') then
        begin
          OutPayload.Add('inspectedNodeId', PcgNodeIdStr);
          OutPayload.Add('inspectedPointCount', Length(PcgPts));
        end;
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_evaluate_anim_blueprint' then
  begin
    ActionStr := 'status';
    CompName := '';
    MacroMult := 0.25;
    AnimBpPresetVal := abpLocomotionUpperBodyAimAndFootIk;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      MacroMult := ArgsObj.Get('deltaSec', 0.25);
      if SameText(ArgsObj.Get('preset', ''), 'combat_slot') then
        AnimBpPresetVal := abpCombatSlotMontageOverride
      else if SameText(ArgsObj.Get('preset', ''), 'jump_air') then
        AnimBpPresetVal := abpAirborneJumpStateCrossfade;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'step_pose') or
       SameText(ActionStr, 'set_params') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      AnimBpComp := TAnimBlueprintHelper.SpawnAnimBlueprintPresetInDesign(
        DesignRoot, DesignOwner, AnimBpPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn AnimBlueprint');
    end else
      AnimBpComp := TAnimBlueprintHelper.FindAnimBlueprintByName(DesignRoot, DesignOwner, CompName);

    if (AnimBpComp <> nil) and SameText(ActionStr, 'set_params') and (ArgsObj <> nil) then
    begin
      AnimBpComp.SpeedMps := ArgsObj.Get('speedMps', AnimBpComp.SpeedMps);
      AnimBpComp.UpperBodyAimWeight := ArgsObj.Get('upperAimWeight', AnimBpComp.UpperBodyAimWeight);
      AnimBpComp.IsInAir := ArgsObj.Get('isInAir', AnimBpComp.IsInAir);
      AnimBpComp.StepAnimBlueprint(0.0);
    end else if (AnimBpComp <> nil) and SameText(ActionStr, 'step_pose') then
      AnimBpComp.StepAnimBlueprint(MacroMult);

    AnimBpAudit := TAnimBlueprintHelper.AuditAnimBlueprintsInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('animBpCount', AnimBpAudit.AnimBpCount);
      OutPayload.Add('validCount', AnimBpAudit.ValidCount);
      OutPayload.Add('errorCount', AnimBpAudit.ErrorCount);
      OutPayload.Add('totalPoseNodeCount', AnimBpAudit.TotalPoseNodeCount);
      OutPayload.Add('totalNotifyTrackCount', AnimBpAudit.TotalNotifyTrackCount);
      OutPayload.Add('totalTriggeredNotifies', AnimBpAudit.TotalTriggeredNotifies);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if AnimBpComp <> nil then
      begin
        OutPayload.Add('activeAnimBlueprint', AnimBpComp.Name);
        OutPayload.Add('activeState', AnimBpComp.ActiveLocomotionState);
        OutPayload.Add('playheadSec', AnimBpComp.PlayheadTimeSec);
        OutPayload.Add('summaryBadge', AnimBpComp.AnimBlueprintSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_tick_behavior_tree' then
  begin
    ActionStr := 'status';
    CompName := '';
    BtKeyStr := 'HasLineOfSight';
    MacroMult := 0.25;
    BtPresetVal := btpTacticalGuardObserverAborts;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      BtKeyStr := Trim(ArgsObj.Get('bbKey', 'HasLineOfSight'));
      MacroMult := ArgsObj.Get('deltaSec', 0.25);
      if SameText(ArgsObj.Get('preset', ''), 'simple_parallel') then
        BtPresetVal := btpSimpleParallelSuppressAndMove
      else if SameText(ArgsObj.Get('preset', ''), 'ammo_reload') then
        BtPresetVal := btpAmmoReloadFallbackSequence;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'tick') or
       SameText(ActionStr, 'set_blackboard') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      BtComp := TBehaviorTreeHelper.SpawnBehaviorTreePresetInDesign(
        DesignRoot, DesignOwner, BtPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn Behavior Tree');
    end else
      BtComp := TBehaviorTreeHelper.FindBehaviorTreeByName(DesignRoot, DesignOwner, CompName);

    if (BtComp <> nil) and SameText(ActionStr, 'set_blackboard') and (ArgsObj <> nil) then
      BtComp.SetBlackboardBool(BtKeyStr, ArgsObj.Get('bbBool', True))
    else if (BtComp <> nil) and SameText(ActionStr, 'tick') then
      BtComp.TickBehaviorTree(MacroMult);

    BtAudit := TBehaviorTreeHelper.AuditBehaviorTreesInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('treeCount', BtAudit.TreeCount);
      OutPayload.Add('validTreeCount', BtAudit.ValidTreeCount);
      OutPayload.Add('errorTreeCount', BtAudit.ErrorTreeCount);
      OutPayload.Add('totalNodeCount', BtAudit.TotalNodeCount);
      OutPayload.Add('totalBlackboardKeys', BtAudit.TotalBlackboardKeys);
      OutPayload.Add('totalObserverAborts', BtAudit.TotalObserverAborts);
      OutPayload.Add('totalServiceTicks', BtAudit.TotalServiceTicks);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if BtComp <> nil then
      begin
        OutPayload.Add('activeTree', BtComp.Name);
        OutPayload.Add('runningLeafNodeId', BtComp.RunningLeafNodeId);
        OutPayload.Add('summaryBadge', BtComp.BehaviorTreeSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_simulate_niagara_stack' then
  begin
    ActionStr := 'status';
    CompName := '';
    NiagModId := '';
    MacroMult := 0.25;
    NiagPresetVal := nspArcaneVortexPortal;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      NiagModId := Trim(ArgsObj.Get('moduleId', ''));
      MacroMult := ArgsObj.Get('deltaSec', 0.25);
      if SameText(ArgsObj.Get('preset', ''), 'collision_sparks') then
        NiagPresetVal := nspAnvilSparksCollisionBurst
      else if SameText(ArgsObj.Get('preset', ''), 'campfire_embers') then
        NiagPresetVal := nspCampfireEmberColumn;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'step_sim') or
       SameText(ActionStr, 'toggle_module') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      NiagComp := TNiagaraStackHelper.SpawnNiagaraPresetInDesign(
        DesignRoot, DesignOwner, NiagPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn Niagara System');
    end else
      NiagComp := TNiagaraStackHelper.FindNiagaraSystemByName(DesignRoot, DesignOwner, CompName);

    if (NiagComp <> nil) and SameText(ActionStr, 'toggle_module') and (NiagModId <> '') then
      NiagComp.ToggleModuleEnabled(NiagModId)
    else if (NiagComp <> nil) and SameText(ActionStr, 'step_sim') then
      NiagComp.StepSystem(MacroMult);

    NiagAudit := TNiagaraStackHelper.AuditNiagaraSystemsInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('systemCount', NiagAudit.SystemCount);
      OutPayload.Add('totalModuleCount', NiagAudit.TotalModuleCount);
      OutPayload.Add('enabledModuleCount', NiagAudit.EnabledModuleCount);
      OutPayload.Add('totalActiveParticles', NiagAudit.TotalActiveParticles);
      OutPayload.Add('totalCollisionEvents', NiagAudit.TotalCollisionEvents);
      OutPayload.Add('totalSubSparksSpawned', NiagAudit.TotalSubSparksSpawned);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if NiagComp <> nil then
      begin
        OutPayload.Add('activeSystem', NiagComp.Name);
        OutPayload.Add('summaryBadge', NiagComp.NiagaraSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_animate_umg_widget' then
  begin
    ActionStr := 'status';
    CompName := '';
    UmgClipStr := 'Anim_ModalOpen';
    UmgTimeVal := 0.30;
    UmgPresetVal := uwapModalPopupSlideBounceAndFade;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      UmgClipStr := Trim(ArgsObj.Get('clipName', 'Anim_ModalOpen'));
      UmgTimeVal := ArgsObj.Get('timeSec', 0.30);
      if SameText(ArgsObj.Get('preset', ''), 'hud_damage') then
        UmgPresetVal := uwapHudDamageToastAndHealthFlash
      else if SameText(ArgsObj.Get('preset', ''), 'boss_banner') then
        UmgPresetVal := uwapBossHealthBannerStretchReveal;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'play_clip') or
       SameText(ActionStr, 'scrub') or SameText(ActionStr, 'fire_event') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      UmgComp := TWidgetAnimHelper.SpawnWidgetAnimPresetInDesign(
        DesignRoot, DesignOwner, UmgPresetVal);
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn UMG Widget Animator');
    end else
      UmgComp := TWidgetAnimHelper.FindWidgetAnimatorByName(DesignRoot, DesignOwner, CompName);

    if (UmgComp <> nil) and SameText(ActionStr, 'play_clip') then
      UmgComp.PlayAnimation(UmgClipStr, upmForward, 1, 1.0)
    else if (UmgComp <> nil) and SameText(ActionStr, 'scrub') then
      UmgComp.ScrubTimeline(UmgTimeVal)
    else if (UmgComp <> nil) and SameText(ActionStr, 'fire_event') then
      UmgComp.FireUiEvent('', uetOnShow);

    UmgAudit := TWidgetAnimHelper.AuditWidgetAnimatorsInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('animatorCount', UmgAudit.AnimatorCount);
      OutPayload.Add('slotCount', UmgAudit.SlotCount);
      OutPayload.Add('clipCount', UmgAudit.ClipCount);
      OutPayload.Add('trackCount', UmgAudit.TrackCount);
      OutPayload.Add('keyframeCount', UmgAudit.KeyframeCount);
      OutPayload.Add('bindingCount', UmgAudit.BindingCount);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if UmgComp <> nil then
      begin
        OutPayload.Add('activeAnimator', UmgComp.Name);
        OutPayload.Add('currentTimeSec', UmgComp.CurrentTimeSec);
        OutPayload.Add('summaryBadge', UmgComp.WidgetAnimSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_retarget_ik_skeleton' then
  begin
    ActionStr := 'status';
    CompName := '';
    MacroMult := 0.25;
    IkRtgPresetVal := irpMannequinToCompactAPose;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      MacroMult := ArgsObj.Get('deltaSec', 0.25);
      if SameText(ArgsObj.Get('preset', ''), 'brute_ogre') then
        IkRtgPresetVal := irpMannequinToBruteOgre
      else if SameText(ArgsObj.Get('preset', ''), 'two_hand_ik') then
        IkRtgPresetVal := irpTwoHandedGripIkRetarget;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'step_walk') or
       SameText(ActionStr, 'toggle_ref_delta') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      IkRtgComp := TIkRetargeterHelper.SpawnIkRetargetPresetInDesign(
        DesignRoot, DesignOwner, IkRtgPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn Skeletal IK Retargeter');
    end else
      IkRtgComp := TIkRetargeterHelper.FindIkRetargeterByName(DesignRoot, DesignOwner, CompName);

    if (IkRtgComp <> nil) and SameText(ActionStr, 'step_walk') then
      IkRtgComp.StepRetargeter(MacroMult)
    else if (IkRtgComp <> nil) and SameText(ActionStr, 'toggle_ref_delta') then
      IkRtgComp.CompensateRefPoseDelta := not IkRtgComp.CompensateRefPoseDelta;

    IkRtgAudit := TIkRetargeterHelper.AuditIkRetargetersInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('retargeterCount', IkRtgAudit.RetargeterCount);
      OutPayload.Add('totalMappedChains', IkRtgAudit.TotalMappedChains);
      OutPayload.Add('ikEnabledChainCount', IkRtgAudit.IkEnabledChainCount);
      OutPayload.Add('refDeltaCompensatedCount', IkRtgAudit.RefDeltaCompensatedCount);
      OutPayload.Add('maxLimbLengthErrorMeters', IkRtgAudit.MaxLimbLengthErrorMeters);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if IkRtgComp <> nil then
      begin
        OutPayload.Add('activeRetargeter', IkRtgComp.Name);
        OutPayload.Add('scaleRatio', IkRtgComp.PelvisHeightScaleRatio);
        OutPayload.Add('summaryBadge', IkRtgComp.IkRetargetSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_simulate_physics_asset' then
  begin
    ActionStr := 'status';
    CompName := '';
    PhAtBodyStr := 'LowerArm_L';
    MacroMult := 0.04;
    PhAtPresetVal := papHumanoidRagdoll11Bodies;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      PhAtBodyStr := Trim(ArgsObj.Get('bodyName', 'LowerArm_L'));
      MacroMult := ArgsObj.Get('deltaSec', 0.04);
      if SameText(ArgsObj.Get('preset', ''), 'pinned_test') then
        PhAtPresetVal := papKinematicPinnedUpperBodyTest
      else if SameText(ArgsObj.Get('preset', ''), 'heavy_brute') then
        PhAtPresetVal := papHeavyArmoredBruteRagdoll;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'step_sim') or
       SameText(ActionStr, 'poke_body') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      PhAtComp := TPhysicsAssetHelper.SpawnPhysicsAssetPresetInDesign(
        DesignRoot, DesignOwner, PhAtPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn Physics Asset (PhAT)');
    end else
      PhAtComp := TPhysicsAssetHelper.FindPhysicsAssetByName(DesignRoot, DesignOwner, CompName);

    if (PhAtComp <> nil) and SameText(ActionStr, 'poke_body') then
    begin
      PhAtComp.ApplyPokeImpulse(PhAtBodyStr, Vector3(28.0, 12.0, 8.0));
      PhAtComp.StepSimulation(MacroMult);
    end else if (PhAtComp <> nil) and SameText(ActionStr, 'step_sim') then
      PhAtComp.StepSimulation(MacroMult);

    PhAtAudit := TPhysicsAssetHelper.AuditPhysicsAssetsInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('assetCount', PhAtAudit.AssetCount);
      OutPayload.Add('totalBodies', PhAtAudit.TotalBodies);
      OutPayload.Add('totalConstraints', PhAtAudit.TotalConstraints);
      OutPayload.Add('totalDisabledPairs', PhAtAudit.TotalDisabledPairs);
      OutPayload.Add('totalMassKg', PhAtAudit.TotalMassKg);
      OutPayload.Add('maxConeViolationDeg', PhAtAudit.MaxConeViolationDeg);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if PhAtComp <> nil then
      begin
        OutPayload.Add('activeAsset', PhAtComp.Name);
        OutPayload.Add('pokeImpulseCount', PhAtComp.PokeImpulseCount);
        OutPayload.Add('summaryBadge', PhAtComp.PhAtSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_unwrap_pack_uvs' then
  begin
    ActionStr := 'status';
    CompName := '';
    UvPresetVal := umpArchitecturalCrate6Islands;
    UvProjVal := upmBox6FaceTriplanar;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      if SameText(ArgsObj.Get('preset', ''), 'cylindrical_column') then
        UvPresetVal := umpCylindricalColumnSeamUnwrap
      else if SameText(ArgsObj.Get('preset', ''), 'overlap_demo') then
        UvPresetVal := umpOverlappingStackedUvRepairDemo;

      if SameText(ArgsObj.Get('projection', ''), 'cylindrical') then
        UvProjVal := upmCylindricalSeam
      else if SameText(ArgsObj.Get('projection', ''), 'planar') then
        UvProjVal := upmPlanarTopXZ
      else if SameText(ArgsObj.Get('projection', ''), 'conformal') then
        UvProjVal := upmConformalSeamRelax;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'unwrap_pack') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      UvComp := TUvEditorHelper.SpawnUvMeshPresetInDesign(
        DesignRoot, DesignOwner, UvPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn UV Editor Mesh');
    end else
      UvComp := TUvEditorHelper.FindUvMeshByName(DesignRoot, DesignOwner, CompName);

    if (UvComp <> nil) and SameText(ActionStr, 'unwrap_pack') then
      UvComp.AutoUnwrapAndPack(UvProjVal);

    UvAudit := TUvEditorHelper.AuditUvMeshesInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('meshCount', UvAudit.MeshCount);
      OutPayload.Add('totalTriangles', UvAudit.TotalTriangles);
      OutPayload.Add('totalIslands', UvAudit.TotalIslands);
      OutPayload.Add('totalOverlappingPairs', UvAudit.TotalOverlappingPairs);
      OutPayload.Add('totalInvertedTriangles', UvAudit.TotalInvertedTriangles);
      OutPayload.Add('avgCoveragePercent', UvAudit.AvgCoveragePercent);
      OutPayload.Add('avgTexelsPerMeter', UvAudit.AvgTexelsPerMeter);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if UvComp <> nil then
      begin
        OutPayload.Add('activeMesh', UvComp.Name);
        OutPayload.Add('summaryBadge', UvComp.UvSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_manage_ofpa_actors' then
  begin
    ActionStr := 'status';
    CompName := '';
    LiPresetVal := lipMedievalWatchtower10Actors;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      if SameText(ArgsObj.Get('preset', ''), 'cyber_street') then
        LiPresetVal := lipCyberpunkStreetBlock12Actors
      else if SameText(ArgsObj.Get('preset', ''), 'dungeon_room') then
        LiPresetVal := lipDungeonRoomModular8Actors;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'edit_in_place') or
       SameText(ActionStr, 'commit_sync') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      LiComp := TLevelInstanceHelper.SpawnLevelInstancePresetInDesign(
        DesignRoot, DesignOwner, LiPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn Level Instance');
    end else
      LiComp := TLevelInstanceHelper.FindLevelInstanceByName(DesignRoot, DesignOwner, CompName);

    if (LiComp <> nil) and SameText(ActionStr, 'edit_in_place') then
      LiComp.BeginEditInPlace
    else if (LiComp <> nil) and SameText(ActionStr, 'commit_sync') then
    begin
      if LiComp.CommitInPlaceEdits then
        TLevelInstanceHelper.SyncSiblingInstancesInDesign(DesignRoot, LiComp);
    end;

    LiAudit := TLevelInstanceHelper.AuditLevelInstancesInDesign(DesignRoot);
    OfpaRepo := TLevelInstanceHelper.ExportDesignToOfpaRepo(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('levelInstanceCount', LiAudit.LevelInstanceCount);
      OutPayload.Add('totalSubActors', LiAudit.TotalSubActors);
      OutPayload.Add('totalPackedBatches', LiAudit.TotalPackedBatches);
      OutPayload.Add('ofpaActorFileCount', Length(OfpaRepo));
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if LiComp <> nil then
      begin
        OutPayload.Add('activeLevelInstance', LiComp.Name);
        OutPayload.Add('drawCallReductionPercent', LiComp.DrawCallReductionPercent);
        OutPayload.Add('summaryBadge', LiComp.LevelInstanceSummaryBadge);
      end;
      if SameText(ActionStr, 'export_ofpa') then
      begin
        OfpaArr := TJSONArray.Create;
        for I := 0 to High(OfpaRepo) do
        begin
          OfpaObj := TJSONObject.Create;
          OfpaObj.Add('actorName', OfpaRepo[I].ActorName);
          OfpaObj.Add('relativePath', OfpaRepo[I].RelativeOfpaPath);
          OfpaObj.Add('contentHash', OfpaRepo[I].ContentHashHex);
          OfpaArr.Add(OfpaObj);
        end;
        OutPayload.Add('ofpaManifest', OfpaArr);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_override_material_instance' then
  begin
    ActionStr := 'status';
    CompName := '';
    MiParamStr := 'Roughness';
    MiScalarVal := 0.25;
    MpcPresetVal := mpcpMonsoonRainStorm;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      MiParamStr := Trim(ArgsObj.Get('paramName', 'Roughness'));
      MiScalarVal := ArgsObj.Get('scalarValue', 0.25);
      if SameText(ArgsObj.Get('mpcPreset', ''), 'dry_noon') then
        MpcPresetVal := mpcpClearNoonDry
      else if SameText(ArgsObj.Get('mpcPreset', ''), 'blizzard_snow') then
        MpcPresetVal := mpcpBlizzardSnowline
      else if SameText(ArgsObj.Get('mpcPreset', ''), 'neon_night') then
        MpcPresetVal := mpcpCyberpunkNeonNight;
    end;

    if SameText(ActionStr, 'spawn_showcase') or SameText(ActionStr, 'override_scalar') or
       SameText(ActionStr, 'reset_overrides') or SameText(ActionStr, 'broadcast_mpc') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    MpcComp := TMaterialInstanceHelper.FindFirstMpc(DesignRoot);
    if SameText(ActionStr, 'spawn_showcase') then
    begin
      TMaterialInstanceHelper.SpawnParentChildMpcShowcaseInDesign(
        DesignRoot, DesignOwner, MpcComp, MiParentOut, MiChildOut);
      MiComp := MiChildOut;
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn Material Instance + MPC Showcase');
    end else
      MiComp := TMaterialInstanceHelper.FindMaterialInstanceByName(DesignRoot, DesignOwner, CompName);

    if (MiComp <> nil) and SameText(ActionStr, 'override_scalar') then
    begin
      MiComp.SetScalarParameterValue(MiParamStr, MiScalarVal);
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Override Material Instance Scalar ' + MiParamStr);
    end else
    if (MiComp <> nil) and SameText(ActionStr, 'reset_overrides') then
    begin
      MiComp.ResetAllOverrides;
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Reset Material Instance Overrides');
    end else
    if SameText(ActionStr, 'broadcast_mpc') then
    begin
      TMaterialInstanceHelper.BroadcastMpcPresetInDesign(DesignRoot, MpcPresetVal);
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Broadcast MPC Preset');
    end;

    MiAudit := TMaterialInstanceHelper.AuditMaterialInstancesInDesign(DesignRoot);
    MpcComp := TMaterialInstanceHelper.FindFirstMpc(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('materialInstanceCount', MiAudit.MaterialInstanceCount);
      OutPayload.Add('parentLinkedInstanceCount', MiAudit.ParentLinkedInstanceCount);
      OutPayload.Add('mpcCount', MiAudit.MpcCount);
      OutPayload.Add('totalOverriddenSlots', MiAudit.TotalOverriddenSlots);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if MiComp <> nil then
      begin
        MiSurf := MiComp.EvaluateEffectiveSurface(MpcComp);
        OutPayload.Add('activeMaterialInstance', MiComp.Name);
        OutPayload.Add('hierarchyChain', MiComp.HierarchyChainString);
        OutPayload.Add('finalRoughness', MiSurf.FinalRoughness);
        OutPayload.Add('finalMetallic', MiSurf.FinalMetallic);
        OutPayload.Add('shaderPermutationsCompiled', MiSurf.ShaderPermutationsCompiled);
        OutPayload.Add('summaryBadge', MiComp.MaterialInstanceSummaryBadge);
      end;
      if MpcComp <> nil then
      begin
        OutPayload.Add('mpcCollectionKey', MpcComp.CollectionKey);
        OutPayload.Add('globalWetness', MpcComp.GlobalWetness);
        OutPayload.Add('snowCoverage', MpcComp.SnowCoverage);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_edit_mesh_sockets_collision' then
  begin
    ActionStr := 'status';
    CompName := '';
    MeshPresetVal := mepGothicArchwayConcave3Hulls;
    MeshMaxHulls := 3;
    MeshSockStr := '';
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      MeshMaxHulls := ArgsObj.Get('maxHulls', 3);
      MeshSockStr := Trim(ArgsObj.Get('socketName', ''));
      if SameText(ArgsObj.Get('preset', ''), 'halberd') then
        MeshPresetVal := mepSkeletalHalberdWeapon4Sockets
      else if SameText(ArgsObj.Get('preset', ''), 'turret') then
        MeshPresetVal := mepSciFiDefenseTurretMultiPart;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'decompose_convex') or
       SameText(ActionStr, 'attach_socket_prop') or SameText(ActionStr, 'recompute_tangents') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      MeshComp := TMeshEditorHelper.SpawnMeshEditorPresetInDesign(
        DesignRoot, DesignOwner, MeshPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn Mesh Editor Asset');
    end else
      MeshComp := TMeshEditorHelper.FindMeshEditorAssetByName(DesignRoot, DesignOwner, CompName);

    if (MeshComp <> nil) and SameText(ActionStr, 'decompose_convex') then
    begin
      MeshComp.GenerateAutoConvexCollision(MeshMaxHulls, kdm18DopBeveled, 20);
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Decompose Auto-Convex Hulls');
    end else
    if (MeshComp <> nil) and SameText(ActionStr, 'attach_socket_prop') then
    begin
      if (MeshSockStr = '') and (Length(MeshComp.Sockets) > 0) then
        MeshSockStr := MeshComp.Sockets[0].SocketName;
      TMeshEditorHelper.SpawnPreviewPropOnSocket(MeshComp, DesignOwner, MeshSockStr);
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Attach Prop to Socket ' + MeshSockStr);
    end else
    if (MeshComp <> nil) and SameText(ActionStr, 'recompute_tangents') then
    begin
      MeshComp.RecomputeNormalsAndMikkTangents(60.0);
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Recompute MikkTSpace Tangents');
    end;

    MeshAudit := TMeshEditorHelper.AuditMeshAssetsInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('meshAssetCount', MeshAudit.MeshAssetCount);
      OutPayload.Add('skeletalMeshCount', MeshAudit.SkeletalMeshCount);
      OutPayload.Add('totalSocketCount', MeshAudit.TotalSocketCount);
      OutPayload.Add('totalConvexHullCount', MeshAudit.TotalConvexHullCount);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if MeshComp <> nil then
      begin
        TanAuditRes := MeshComp.LastTangentAudit;
        OutPayload.Add('activeMeshAsset', MeshComp.Name);
        OutPayload.Add('convexHullCount', Length(MeshComp.ConvexHulls));
        OutPayload.Add('socketCount', Length(MeshComp.Sockets));
        OutPayload.Add('centerOpeningClear',
          not MeshComp.PointHitsAnyConvexHull(Vector3(0.0, 1.2, 0.0)));
        OutPayload.Add('nonOrthogonalTangents', TanAuditRes.NonOrthogonalTangentCount);
        OutPayload.Add('summaryBadge', MeshComp.MeshEditorSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  if ToolName = 'cge_build_recast_navmesh' then
  begin
    ActionStr := 'status';
    CompName := '';
    RecastPresetVal := rnpTwoStoryBridgeAndStairs;
    RecastAgentH := 1.80;
    if ArgsObj <> nil then
    begin
      ActionStr := LowerCase(Trim(ArgsObj.Get('action', 'status')));
      CompName := Trim(ArgsObj.Get('name', ''));
      RecastAgentH := ArgsObj.Get('agentHeight', 1.80);
      if SameText(ArgsObj.Get('preset', ''), 'dungeon_keep') then
        RecastPresetVal := rnpMultiFloorDungeonKeep
      else if SameText(ArgsObj.Get('preset', ''), 'canyon_parkour') then
        RecastPresetVal := rnpSteepCanyonParkourLinks;
    end;

    if SameText(ActionStr, 'spawn_preset') or SameText(ActionStr, 'build_navmesh') then
    begin
      if not RequireAutonomy(mamEditWithUndo, Result) then Exit;
    end else
    begin
      if not RequireAutonomy(mamReadOnly, Result) then Exit;
    end;

    ResolveDesignContext(DesignRoot, DesignOwner, DesignUrl, DesignModified);
    if DesignRoot = nil then
    begin
      IsToolError := true;
      Exit(MakeToolTextResult('No design is currently open.', true));
    end;

    if SameText(ActionStr, 'spawn_preset') then
    begin
      RecastComp := TRecastNavMeshHelper.SpawnRecastPresetInDesign(
        DesignRoot, DesignOwner, RecastPresetVal, Vector3(0, 0, 0));
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Spawn 3D Recast NavMesh Volume');
    end else
      RecastComp := TRecastNavMeshHelper.FindRecastNavMeshByName(DesignRoot, DesignOwner, CompName);

    if (RecastComp <> nil) and SameText(ActionStr, 'build_navmesh') then
    begin
      RecastComp.AgentHeight := RecastAgentH;
      RecastComp.BuildPolygonalNavMesh;
      if Assigned(FOnAfterModify) then
        FOnAfterModify('MCP Rebuild 3D Recast NavMesh');
    end else
    if (RecastComp <> nil) and SameText(ActionStr, 'find_path') then
    begin
      RecastPathRes := RecastComp.FindPath3D(
        Vector3(6.5, 0.0, -2.5), Vector3(8.2, 3.0, 2.6));
      if not RecastPathRes.Found then ;
    end;

    RecastAudit := TRecastNavMeshHelper.AuditRecastNavMeshesInDesign(DesignRoot);

    OutPayload := TJSONObject.Create;
    try
      OutPayload.Add('action', ActionStr);
      OutPayload.Add('navVolumeCount', RecastAudit.NavVolumeCount);
      OutPayload.Add('totalPolys', RecastAudit.TotalPolys);
      OutPayload.Add('totalNavTriangles', RecastAudit.TotalNavTriangles);
      OutPayload.Add('totalNavLinks', RecastAudit.TotalNavLinks);
      OutPayload.Add('totalStackedFloorPairs', RecastAudit.TotalStackedFloorPairs);
      OutPayload.Add('studioCatalogCount', TStudioHubManager.StudioCount);
      if RecastComp <> nil then
      begin
        OutPayload.Add('activeNavVolume', RecastComp.Name);
        OutPayload.Add('polyCount', Length(RecastComp.Polys));
        OutPayload.Add('stackedFloorPairs', RecastComp.CountStackedMultiFloorPairs);
        OutPayload.Add('pathFound', RecastComp.LastPath.Found);
        OutPayload.Add('pathDistanceM', RecastComp.LastPath.TotalDistanceM);
        OutPayload.Add('pathUsedLinks', RecastComp.LastPath.UsedLinkCount);
        OutPayload.Add('summaryBadge', RecastComp.RecastSummaryBadge);
      end;
      Result := MakeToolTextResult(OutPayload.FormatJSON);
    finally
      FreeAndNil(OutPayload);
    end;
    Exit;
  end;

  IsToolError := true;
  Result := MakeToolTextResult('Unknown MCP tool: ' + ToolName, true);
end;

function TCastleMcpServer.MakeJsonRpcResult(const IdData: TJSONData;
  const ResultObj: TJSONData): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('jsonrpc', '2.0');
  if IdData <> nil then
    Result.Add('id', IdData.Clone)
  else
    Result.Add('id', TJSONNull.Create);
  Result.Add('result', ResultObj);
end;

function TCastleMcpServer.MakeJsonRpcError(const IdData: TJSONData;
  const Code: Integer; const MessageText: String): TJSONObject;
var
  ErrObj: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('jsonrpc', '2.0');
  if IdData <> nil then
    Result.Add('id', IdData.Clone)
  else
    Result.Add('id', TJSONNull.Create);
  ErrObj := TJSONObject.Create;
  ErrObj.Add('code', Code);
  ErrObj.Add('message', MessageText);
  Result.Add('error', ErrObj);
end;

function TCastleMcpServer.HandleJsonRpcString(const RequestBody: String;
  const AuthorizationHeader: String): String;
var
  ParsedData, IdNode, ParamsNode, ArgsNode: TJSONData;
  ReqObj, RespObj, InitRes, CapsObj, ToolsCapObj, ServerInfoObj,
    ToolsListRes, ToolCallRes: TJSONObject;
  RpcMethod, ToolName, ExpectedAuth: String;
  IsToolErr: Boolean;
begin
  Inc(FRequestsHandledCount);

  if FAutonomyMode = mamDisabled then
  begin
    RespObj := MakeJsonRpcError(nil, -32001, 'Castle Game Engine MCP Server is disabled.');
    try
      Result := RespObj.AsJSON;
    finally
      FreeAndNil(RespObj);
    end;
    Exit;
  end;

  if FAuthToken <> '' then
  begin
    ExpectedAuth := 'Bearer ' + FAuthToken;
    if Trim(AuthorizationHeader) <> ExpectedAuth then
    begin
      RespObj := MakeJsonRpcError(nil, -32002, 'Invalid or missing Authorization Bearer token.');
      try
        Result := RespObj.AsJSON;
      finally
        FreeAndNil(RespObj);
      end;
      Exit;
    end;
  end;

  ParsedData := nil;
  try
    try
      ParsedData := GetJSON(RequestBody);
    except
      on E: Exception do
      begin
        RespObj := MakeJsonRpcError(nil, -32700, 'Parse error: ' + E.Message);
        try
          Result := RespObj.AsJSON;
        finally
          FreeAndNil(RespObj);
        end;
        Exit;
      end;
    end;

    if not (ParsedData is TJSONObject) then
    begin
      RespObj := MakeJsonRpcError(nil, -32600, 'Invalid Request: expected JSON object.');
      try
        Result := RespObj.AsJSON;
      finally
        FreeAndNil(RespObj);
      end;
      Exit;
    end;

    ReqObj := TJSONObject(ParsedData);
    IdNode := ReqObj.Find('id');
    RpcMethod := ReqObj.Get('method', '');

    { JSON-RPC notifications (no id, e.g. notifications/initialized) return empty body }
    if (IdNode = nil) and (Pos('notifications/', RpcMethod) = 1) then
      Exit('');

    if RpcMethod = 'initialize' then
    begin
      InitRes := TJSONObject.Create;
      InitRes.Add('protocolVersion', McpProtocolVersion);
      CapsObj := TJSONObject.Create;
      ToolsCapObj := TJSONObject.Create;
      ToolsCapObj.Add('listChanged', false);
      CapsObj.Add('tools', ToolsCapObj);
      InitRes.Add('capabilities', CapsObj);
      ServerInfoObj := TJSONObject.Create;
      ServerInfoObj.Add('name', 'castle-editor-mcp');
      ServerInfoObj.Add('version', CastleEngineVersion);
      InitRes.Add('serverInfo', ServerInfoObj);
      RespObj := MakeJsonRpcResult(IdNode, InitRes);
    end else
    if RpcMethod = 'ping' then
    begin
      RespObj := MakeJsonRpcResult(IdNode, TJSONObject.Create);
    end else
    if RpcMethod = 'tools/list' then
    begin
      ToolsListRes := TJSONObject.Create;
      ToolsListRes.Add('tools', BuildToolsListJson);
      RespObj := MakeJsonRpcResult(IdNode, ToolsListRes);
    end else
    if RpcMethod = 'tools/call' then
    begin
      ParamsNode := ReqObj.Find('params');
      if not (ParamsNode is TJSONObject) then
        RespObj := MakeJsonRpcError(IdNode, -32602, 'Invalid params: expected object.')
      else
      begin
        ToolName := TJSONObject(ParamsNode).Get('name', '');
        ArgsNode := TJSONObject(ParamsNode).Find('arguments');
        if (ArgsNode <> nil) and (not (ArgsNode is TJSONObject)) then
          RespObj := MakeJsonRpcError(IdNode, -32602, 'Invalid tool arguments: expected object.')
        else
        begin
          ToolCallRes := ExecuteMcpTool(ToolName, TJSONObject(ArgsNode), IsToolErr);
          RespObj := MakeJsonRpcResult(IdNode, ToolCallRes);
        end;
      end;
    end else
      RespObj := MakeJsonRpcError(IdNode, -32601, 'Method not found: ' + RpcMethod);

    try
      Result := RespObj.AsJSON;
    finally
      FreeAndNil(RespObj);
    end;
  finally
    FreeAndNil(ParsedData);
  end;
end;

end.
