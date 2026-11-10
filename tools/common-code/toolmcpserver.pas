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
  CastleViewport, CastleTransformManipulate, CastleLog;

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
  ImgBlock, MetaBlock: TJSONObject;
  OutLines: TStringList;
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
