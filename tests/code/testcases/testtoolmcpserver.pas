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

{ Test ToolMcpServer unit (TCastleMcpServer JSON-RPC 2.0 MCP server). }
unit TestToolMcpServer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester, CastleImages, ToolMcpServer;

type
  TTestToolMcpServer = class(TCastleTestCase)
  strict private
    FLastUndoComment: String;
    FAfterModifyCalls: Integer;
    FSavedCalled: Boolean;
    FLastBuildCommand: String;
    procedure HandleAfterModify(const UndoComment: String);
    function HandleUndoRedo(const IsRedo: Boolean;
      out ExecutedComment: String): Boolean;
    function HandleCaptureScreenshot: TRGBImage;
    procedure HandleGetBuildOutput(const MaxLines: Integer;
      const OutLines: TStrings; out WarningsCount, ErrorsCount: Integer);
    function HandleSaveDesign(out ErrorReason: String): Boolean;
    function HandleRunBuildCommand(const CommandName: String;
      out StatusMessage: String): Boolean;
  published
    procedure TestProtocolInitializeToolsListAndAuth;
    procedure TestAutonomyModesAndSceneManipulation;
    procedure TestLiveLocalhostHttpRoundtrip;
  end;

implementation

uses
  FpJson, JsonParser, Base64, FpHttpClient,
  CastleVectors, CastleColors, CastleUIControls, CastleControls,
  CastleTransform, CastleScene, CastleViewport;

type
  THttpPostWorkerThread = class(TThread)
  public
    Url: String;
    RequestBody: String;
    ResponseBody: String;
    ErrorMessage: String;
    protected procedure Execute; override;
  end;

procedure THttpPostWorkerThread.Execute;
var
  Client: TFPHTTPClient;
  ReqStream: TStringStream;
begin
  Client := TFPHTTPClient.Create(nil);
  ReqStream := TStringStream.Create(RequestBody);
  try
    try
      Client.AddHeader('Content-Type', 'application/json');
      Client.RequestBody := ReqStream;
      ResponseBody := Client.Post(Url);
    except
      on E: Exception do
        ErrorMessage := E.Message;
    end;
  finally
    Client.RequestBody := nil;
    FreeAndNil(ReqStream);
    FreeAndNil(Client);
  end;
end;

procedure TTestToolMcpServer.HandleAfterModify(const UndoComment: String);
begin
  Inc(FAfterModifyCalls);
  FLastUndoComment := UndoComment;
end;

function TTestToolMcpServer.HandleUndoRedo(const IsRedo: Boolean;
  out ExecutedComment: String): Boolean;
begin
  if IsRedo then
    ExecutedComment := 'Redo last MCP edit'
  else
    ExecutedComment := 'Undo ' + FLastUndoComment;
  Result := true;
end;

function TTestToolMcpServer.HandleCaptureScreenshot: TRGBImage;
begin
  Result := TRGBImage.Create(16, 12);
  Result.Clear(Vector4Byte(32, 64, 128, 255));
end;

procedure TTestToolMcpServer.HandleGetBuildOutput(const MaxLines: Integer;
  const OutLines: TStrings; out WarningsCount, ErrorsCount: Integer);
begin
  WarningsCount := 2;
  ErrorsCount := 0;
  OutLines.Add('Compiling project...');
  OutLines.Add('Linking castle-game...');
end;

function TTestToolMcpServer.HandleSaveDesign(out ErrorReason: String): Boolean;
begin
  ErrorReason := '';
  FSavedCalled := true;
  Result := true;
end;

function TTestToolMcpServer.HandleRunBuildCommand(const CommandName: String;
  out StatusMessage: String): Boolean;
begin
  FLastBuildCommand := CommandName;
  StatusMessage := 'Started ' + CommandName;
  Result := true;
end;

procedure TTestToolMcpServer.TestProtocolInitializeToolsListAndAuth;
var
  Server: TCastleMcpServer;
  RespStr, ConfigStr: String;
  JsonData: TJSONData;
  RespObj, ResObj: TJSONObject;
  ToolsArr: TJSONArray;
begin
  Server := TCastleMcpServer.Create(nil);
  try
    AssertTrue(Server.AutonomyMode = mamDisabled);
    Server.Port := 18765;

    { Disabled server rejects JSON-RPC with -32001 }
    RespStr := Server.HandleJsonRpcString('{"jsonrpc":"2.0","id":1,"method":"ping"}');
    JsonData := GetJSON(RespStr);
    try
      RespObj := TJSONObject(JsonData);
      AssertEquals(-32001, RespObj.Objects['error'].Integers['code']);
    finally
      FreeAndNil(JsonData);
    end;

    { Enable ReadOnly + AuthToken }
    Server.AutonomyMode := mamReadOnly;
    Server.AuthToken := 'secret-mcp-token';

    ConfigStr := Server.ClientConfigJson;
    AssertTrue(Pos('http://127.0.0.1:18765/mcp', ConfigStr) > 0);
    AssertTrue(Pos('Bearer secret-mcp-token', ConfigStr) > 0);

    { Missing token -> -32002 }
    RespStr := Server.HandleJsonRpcString('{"jsonrpc":"2.0","id":2,"method":"ping"}', '');
    JsonData := GetJSON(RespStr);
    try
      RespObj := TJSONObject(JsonData);
      AssertEquals(-32002, RespObj.Objects['error'].Integers['code']);
    finally
      FreeAndNil(JsonData);
    end;

    { Valid Bearer token -> initialize }
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":3,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}',
      'Bearer secret-mcp-token');
    JsonData := GetJSON(RespStr);
    try
      RespObj := TJSONObject(JsonData);
      ResObj := RespObj.Objects['result'];
      AssertEquals(TCastleMcpServer.McpProtocolVersion, ResObj.Strings['protocolVersion']);
      AssertEquals('castle-editor-mcp', ResObj.Objects['serverInfo'].Strings['name']);
    finally
      FreeAndNil(JsonData);
    end;

    { Notification without id returns empty string }
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","method":"notifications/initialized"}',
      'Bearer secret-mcp-token');
    AssertEquals('', RespStr);

    { tools/list returns all 12 MCP tools }
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":4,"method":"tools/list"}',
      'Bearer secret-mcp-token');
    JsonData := GetJSON(RespStr);
    try
      RespObj := TJSONObject(JsonData);
      ToolsArr := RespObj.Objects['result'].Arrays['tools'];
      AssertEquals(12, ToolsArr.Count);
    finally
      FreeAndNil(JsonData);
    end;

    { cge_list_component_classes filtered by Box }
    Server.AuthToken := '';
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"cge_list_component_classes","arguments":{"filter":"CastleBox"}}}');
    AssertTrue(Pos('TCastleBox', RespStr) > 0);
  finally
    FreeAndNil(Server);
  end;
end;

procedure TTestToolMcpServer.TestAutonomyModesAndSceneManipulation;
var
  DesignOwner: TComponent;
  RootUI: TCastleUserInterface;
  Viewport: TCastleViewport;
  Server: TCastleMcpServer;
  RespStr, InnerText, DecodedPng, DeletedCrateName: String;
  JsonData, InnerData: TJSONData;
  ResObj: TJSONObject;
  ContentArr: TJSONArray;
  CrateA, CrateB: TCastleBox;
begin
  FAfterModifyCalls := 0;
  FLastUndoComment := '';
  FSavedCalled := false;
  FLastBuildCommand := '';

  DesignOwner := TComponent.Create(nil);
  Server := TCastleMcpServer.Create(nil);
  try
    RootUI := TCastleUserInterface.Create(DesignOwner);
    RootUI.Name := 'GroupRoot';
    Viewport := TCastleViewport.Create(DesignOwner);
    Viewport.Name := 'ViewportMain';
    RootUI.InsertFront(Viewport);

    Server.StandaloneDesignRoot := RootUI;
    Server.StandaloneDesignOwner := DesignOwner;
    Server.StandaloneDesignUrl := 'castle-data:/gameviewmain.castle-user-interface';
    Server.OnAfterModify := {$ifdef FPC}@{$endif} HandleAfterModify;
    Server.OnUndoRedo := {$ifdef FPC}@{$endif} HandleUndoRedo;
    Server.OnCaptureScreenshot := {$ifdef FPC}@{$endif} HandleCaptureScreenshot;
    Server.OnGetBuildOutput := {$ifdef FPC}@{$endif} HandleGetBuildOutput;
    Server.OnSaveDesign := {$ifdef FPC}@{$endif} HandleSaveDesign;
    Server.OnRunBuildCommand := {$ifdef FPC}@{$endif} HandleRunBuildCommand;

    { 1. ReadOnly allows hierarchy inspection, denies adding components }
    Server.AutonomyMode := mamReadOnly;
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"cge_get_hierarchy","arguments":{}}}');
    AssertTrue(Pos('ViewportMain', RespStr) > 0);

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"cge_add_component","arguments":{"className":"TCastleBox","parentName":"ViewportMain"}}}');
    JsonData := GetJSON(RespStr);
    try
      ResObj := TJSONObject(JsonData).Objects['result'];
      AssertTrue(ResObj.Get('isError', false));
    finally
      FreeAndNil(JsonData);
    end;

    { 2. EditWithUndo allows adding, modifying, layout actions, and undo, but denies saving }
    Server.AutonomyMode := mamEditWithUndo;

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"cge_add_component","arguments":{"className":"TCastleBox","parentName":"ViewportMain","baseName":"CrateA","properties":{"Translation":[1.0,4.0,2.0],"Size":[2.0,3.0,4.0]}}}}');
    CrateA := DesignOwner.FindComponent('CrateA1') as TCastleBox;
    if CrateA = nil then
      CrateA := DesignOwner.FindComponent('CrateA') as TCastleBox;
    AssertTrue(CrateA <> nil);
    AssertVectorEquals(Vector3(1.0, 4.0, 2.0), CrateA.Translation, 0.001);
    AssertVectorEquals(Vector3(2.0, 3.0, 4.0), CrateA.Size, 0.001);

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"cge_add_component","arguments":{"className":"TCastleBox","parentName":"ViewportMain","baseName":"CrateB","properties":{"Translation":[5.3,9.0,-2.4]}}}}');
    CrateB := DesignOwner.FindComponent('CrateB1') as TCastleBox;
    if CrateB = nil then
      CrateB := DesignOwner.FindComponent('CrateB') as TCastleBox;
    AssertTrue(CrateB <> nil);

    { Modify properties on CrateB }
    RespStr := Server.HandleJsonRpcString(Format(
      '{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"cge_set_component_properties","arguments":{"name":"%s","properties":{"Pickable":false,"Translation":[5.4,9.0,-2.6]}}}}',
      [CrateB.Name]));
    AssertFalse(CrateB.Pickable);
    AssertVectorEquals(Vector3(5.4, 9.0, -2.6), CrateB.Translation, 0.001);
    AssertTrue(FAfterModifyCalls >= 3);

    { Inspect non-default properties on CrateA }
    RespStr := Server.HandleJsonRpcString(Format(
      '{"jsonrpc":"2.0","id":15,"method":"tools/call","params":{"name":"cge_get_component_properties","arguments":{"name":"%s","onlyNonDefault":true}}}',
      [CrateA.Name]));
    JsonData := GetJSON(RespStr);
    try
      InnerText := TJSONObject(JsonData).Objects['result'].Arrays['content'].Objects[0].Strings['text'];
      InnerData := GetJSON(InnerText);
      try
        AssertEquals('TCastleBox', TJSONObject(InnerData).Strings['className']);
        AssertTrue(TJSONObject(InnerData).Objects['properties'].Find('Size') <> nil);
      finally
        FreeAndNil(InnerData);
      end;
    finally
      FreeAndNil(JsonData);
    end;

    { Layout actions: align_y then snap_to_grid }
    RespStr := Server.HandleJsonRpcString(Format(
      '{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"cge_execute_layout_action","arguments":{"action":"align_y","targets":["%s","%s"]}}}',
      [CrateA.Name, CrateB.Name]));
    AssertSameValue(4.0, CrateB.Translation.Y, 0.001);

    RespStr := Server.HandleJsonRpcString(Format(
      '{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"cge_execute_layout_action","arguments":{"action":"snap_to_grid","gridStep":1.0,"targets":["%s"]}}}',
      [CrateB.Name]));
    AssertVectorEquals(Vector3(5.0, 4.0, -3.0), CrateB.Translation, 0.001);

    { Save is denied in mamEditWithUndo }
    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":18,"method":"tools/call","params":{"name":"cge_save_design","arguments":{}}}');
    JsonData := GetJSON(RespStr);
    try
      AssertTrue(TJSONObject(JsonData).Objects['result'].Get('isError', false));
    finally
      FreeAndNil(JsonData);
    end;
    AssertFalse(FSavedCalled);

    { 3. FullControl allows save, compile, screenshot, build output, undo, and delete }
    Server.AutonomyMode := mamFullControl;

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"cge_save_design","arguments":{}}}');
    AssertTrue(FSavedCalled);

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"cge_run_build_command","arguments":{"command":"compile"}}}');
    AssertEquals('compile', FLastBuildCommand);

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":21,"method":"tools/call","params":{"name":"cge_get_build_output","arguments":{"maxLines":10}}}');
    AssertTrue(Pos('Linking castle-game', RespStr) > 0);

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"cge_undo_redo","arguments":{"direction":"undo"}}}');
    AssertTrue(Pos('Undo ', RespStr) > 0);

    RespStr := Server.HandleJsonRpcString(
      '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"cge_capture_viewport_screenshot","arguments":{}}}');
    JsonData := GetJSON(RespStr);
    try
      ContentArr := TJSONObject(JsonData).Objects['result'].Arrays['content'];
      AssertEquals(2, ContentArr.Count);
      AssertEquals('image/png', ContentArr.Objects[1].Strings['mimeType']);
      DecodedPng := DecodeStringBase64(ContentArr.Objects[1].Strings['data']);
      AssertTrue(Length(DecodedPng) > 16);
      AssertEquals(#$89'PNG', Copy(DecodedPng, 1, 4));
    finally
      FreeAndNil(JsonData);
    end;

    { Delete CrateB (Viewport.Items still keeps its built-in Camera + CrateA = 2) }
    DeletedCrateName := CrateB.Name;
    RespStr := Server.HandleJsonRpcString(Format(
      '{"jsonrpc":"2.0","id":24,"method":"tools/call","params":{"name":"cge_delete_component","arguments":{"name":"%s"}}}',
      [DeletedCrateName]));
    AssertTrue(DesignOwner.FindComponent(DeletedCrateName) = nil);
    AssertTrue(CrateA.Parent = Viewport.Items);
    AssertEquals(2, Viewport.Items.Count);
  finally
    FreeAndNil(Server);
    FreeAndNil(DesignOwner);
  end;
end;

procedure TTestToolMcpServer.TestLiveLocalhostHttpRoundtrip;
var
  Server: TCastleMcpServer;
  Worker: THttpPostWorkerThread;
  HealthResp: String;
  Client: TFPHTTPClient;
begin
  Server := TCastleMcpServer.Create(nil);
  try
    Server.Port := 18793;
    Server.AutonomyMode := mamReadOnly;
    if not Server.StartListening then
      Exit; { Skip gracefully if sandbox forbids binding localhost port }

    Sleep(30);

    { 1. GET /health responds directly from listener thread }
    Client := TFPHTTPClient.Create(nil);
    try
      HealthResp := Client.Get('http://127.0.0.1:18793/health');
      AssertTrue(Pos('"status":"ok"', HealthResp) > 0);
      AssertTrue(Pos('"autonomyMode":"read_only"', HealthResp) > 0);
    finally
      FreeAndNil(Client);
    end;

    { 2. POST /mcp marshals onto main thread via TThread.Synchronize }
    Worker := THttpPostWorkerThread.Create(true);
    try
      Worker.FreeOnTerminate := false;
      Worker.Url := Server.EndpointUrl;
      Worker.RequestBody := '{"jsonrpc":"2.0","id":99,"method":"initialize","params":{}}';
      Worker.Start;
      while not Worker.Finished do
        CheckSynchronize(10);
      Worker.WaitFor;
      AssertEquals('', Worker.ErrorMessage);
      AssertTrue(Pos('"castle-editor-mcp"', Worker.ResponseBody) > 0);
    finally
      FreeAndNil(Worker);
    end;

    Server.StopListening;
    AssertFalse(Server.Listening);
  finally
    FreeAndNil(Server);
  end;
end;

initialization
  RegisterTest(TTestToolMcpServer);
end.
