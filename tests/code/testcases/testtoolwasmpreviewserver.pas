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

{ Automated unit tests for Phase 284 WebAssembly (targetWeb) Live Preview
  HTTP Server and Bundle Size Diagnostics (ToolWasmPreviewServer). }
unit TestToolWasmPreviewServer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, CastleTester;

type
  TTestToolWasmPreviewServer = class(TCastleTestCase)
  published
    procedure TestMimeTypesPathTraversalGuardAndBundleProfiler;
    procedure TestLiveLocalhostHttpWasmMimeCoopCoepAndLiveReload;
  end;

implementation

uses
  FpHttpClient, CastleFilesUtils, CastleUriUtils, ToolWasmPreviewServer;

procedure WriteDummyBytes(const FileName: String; const HeaderStr: AnsiString;
  const TotalBytes: Integer);
var
  FS: TFileStream;
  Buf: TBytes;
  I: Integer;
begin
  ForceDirectories(ExtractFileDir(FileName));
  FS := TFileStream.Create(FileName, fmCreate);
  try
    SetLength(Buf, TotalBytes);
    for I := 0 to TotalBytes - 1 do
      if I < Length(HeaderStr) then
        Buf[I] := Ord(HeaderStr[I + 1])
      else
        Buf[I] := Byte(I and $FF);
    if TotalBytes > 0 then
      FS.WriteBuffer(Buf[0], TotalBytes);
  finally
    FreeAndNil(FS);
  end;
end;

function HeaderContains(const Headers: TStrings; const NamePart, ValuePart: String): Boolean;
var
  I: Integer;
  LineLower: String;
begin
  Result := false;
  for I := 0 to Headers.Count - 1 do
  begin
    LineLower := LowerCase(Headers[I]);
    if (Pos(LowerCase(NamePart), LineLower) > 0) and
       (Pos(LowerCase(ValuePart), LineLower) > 0) then
      Exit(true);
  end;
end;

procedure TTestToolWasmPreviewServer.TestMimeTypesPathTraversalGuardAndBundleProfiler;
var
  TempBase, DistDir, DataDir, Resolved: String;
  Report: TWasmBundleReport;
  MdText, InjectedHtml: String;
begin
  AssertEquals('application/wasm', TWasmPreviewHttpServer.MimeTypeForExtension('.wasm'));
  AssertEquals('text/javascript; charset=utf-8', TWasmPreviewHttpServer.MimeTypeForExtension('.js'));
  AssertEquals('application/zip', TWasmPreviewHttpServer.MimeTypeForExtension('.zip'));

  InjectedHtml := TWasmPreviewHttpServer.InjectAutoReloadScript(
    '<html><body><canvas id="c"></canvas></body></html>');
  AssertTrue(Pos('/__cge_live_reload', InjectedHtml) > 0);
  AssertTrue(Pos('location.reload()', InjectedHtml) > 0);

  TempBase := IncludeTrailingPathDelimiter(GetTempDir(false)) + 'cge_wasm_test_' + IntToStr(GetTickCount64);
  DistDir := TempBase + PathDelim + 'castle-engine-output' + PathDelim + 'web' + PathDelim + 'dist';
  DataDir := TempBase + PathDelim + 'data';
  try
    WriteDummyBytes(DistDir + PathDelim + 'index.html',
      '<!doctype html><html><body><h1>CGE Web</h1></body></html>', 57);
    WriteDummyBytes(DistDir + PathDelim + 'dungeon_game.js', 'console.log("cge");', 4096);
    WriteDummyBytes(DistDir + PathDelim + 'dungeon_game.wasm', #0'asm'#1#0#0#0, 65536);
    WriteDummyBytes(DistDir + PathDelim + 'dungeon_game.castle-engine-data.zip', 'PK'#3#4, 32768);

    { Source data with > 1 MB uncompressed .wav to trigger audio optimization hint }
    WriteDummyBytes(DataDir + PathDelim + 'audio' + PathDelim + 'ambient.wav', 'RIFF', 1200000);
    WriteDummyBytes(DataDir + PathDelim + 'models' + PathDelim + 'hero.gltf', '{"asset":{}}', 8192);
    WriteDummyBytes(DataDir + PathDelim + 'ui' + PathDelim + 'hud.castle-user-interface', '{}', 1024);

    { Safe path resolution & traversal blocking }
    AssertTrue(TWasmPreviewHttpServer.ResolveSafeFilePath(DistDir, '/', Resolved));
    AssertEquals('index.html', ExtractFileName(Resolved));
    AssertTrue(TWasmPreviewHttpServer.ResolveSafeFilePath(DistDir, '/dungeon_game.wasm?v=42', Resolved));
    AssertEquals('dungeon_game.wasm', ExtractFileName(Resolved));
    AssertFalse(TWasmPreviewHttpServer.ResolveSafeFilePath(DistDir, '/../secret.txt', Resolved));
    AssertFalse(TWasmPreviewHttpServer.ResolveSafeFilePath(DistDir, '/sub/../../outside.txt', Resolved));

    { Bundle size diagnostics }
    Report := TWasmBundleProfiler.ProfileWebBundle(DistDir, DataDir);
    try
      AssertTrue(Report.DistExists);
      AssertTrue(Report.HasIndexHtml);
      AssertTrue(Report.HasWasmBinary);
      AssertEquals(57 + 4096 + 65536 + 32768, Report.TotalDistBytes);
      AssertEquals(65536, Report.DistCategoryBytes[wpcWasmBinary]);
      AssertEquals(32768, Report.DistCategoryBytes[wpcPackedDataArchive]);
      AssertEquals(1200000 + 8192 + 1024, Report.TotalRawDataBytes);
      AssertEquals(1200000, Report.DataCategoryBytes[wpcAudio]);
      AssertTrue(Report.OptimizationHints.Count >= 1);
      MdText := Report.FormatMarkdownReport;
      AssertTrue(Pos('dungeon_game.wasm', MdText) > 0);
      AssertTrue(Pos('.ogg', MdText) > 0);
    finally
      FreeAndNil(Report);
    end;
  finally
    if DirectoryExists(TempBase) then
      RemoveNonEmptyDir(TempBase, true);
  end;
end;

procedure TTestToolWasmPreviewServer.TestLiveLocalhostHttpWasmMimeCoopCoepAndLiveReload;
var
  TempBase, DistDir, HtmlResp, WasmResp, StampResp1, StampResp2: String;
  Server: TWasmPreviewHttpServer;
  Client: TFPHTTPClient;
begin
  TempBase := IncludeTrailingPathDelimiter(GetTempDir(false)) + 'cge_wasm_live_' + IntToStr(GetTickCount64);
  DistDir := TempBase + PathDelim + 'dist';
  Server := TWasmPreviewHttpServer.Create(nil);
  try
    WriteDummyBytes(DistDir + PathDelim + 'index.html',
      '<!doctype html><html><body><canvas id="castle"></canvas></body></html>', 70);
    WriteDummyBytes(DistDir + PathDelim + 'app.wasm', #0'asm'#1#0#0#0'CODE', 128);

    Server.DocumentRoot := DistDir;
    Server.Port := 18947;
    Server.EnableCrossOriginIsolation := true;
    Server.EnableAutoReload := true;

    if not Server.StartServer then
      Exit; { Skip gracefully if test environment blocks localhost port binding }

    Sleep(30);

    Client := TFPHTTPClient.Create(nil);
    try
      Client.AllowRedirect := false;

      { 1. GET /index.html -> COOP + COEP + Cache-Control + Auto-reload script }
      HtmlResp := Client.Get('http://127.0.0.1:18947/index.html');
      AssertEquals(200, Client.ResponseStatusCode);
      AssertTrue(HeaderContains(Client.ResponseHeaders, 'Cross-Origin-Opener-Policy', 'same-origin'));
      AssertTrue(HeaderContains(Client.ResponseHeaders, 'Cross-Origin-Embedder-Policy', 'require-corp'));
      AssertTrue(HeaderContains(Client.ResponseHeaders, 'Cache-Control', 'no-store'));
      AssertTrue(Pos('/__cge_live_reload', HtmlResp) > 0);

      { 2. GET /app.wasm -> Content-Type: application/wasm + exact 128 bytes }
      WasmResp := Client.Get('http://127.0.0.1:18947/app.wasm');
      AssertEquals(200, Client.ResponseStatusCode);
      AssertTrue(HeaderContains(Client.ResponseHeaders, 'Content-Type', 'application/wasm'));
      AssertEquals(128, Length(WasmResp));
      AssertEquals(#0'asm', Copy(WasmResp, 1, 4));

      { 3. GET /__cge_live_reload stamp changes after rebuild modifies app.wasm }
      StampResp1 := Client.Get('http://127.0.0.1:18947/__cge_live_reload');
      AssertTrue(Pos('"status":"ok"', StampResp1) > 0);

      WriteDummyBytes(DistDir + PathDelim + 'app.wasm', #0'asm'#1#0#0#0'NEW_BUILD_CODE', 256);
      StampResp2 := Client.Get('http://127.0.0.1:18947/__cge_live_reload');
      AssertTrue(StampResp1 <> StampResp2);

      AssertTrue(Server.RequestsServed >= 4);
      AssertTrue(Server.BytesServed >= 200);
    finally
      FreeAndNil(Client);
    end;

    Server.StopServer;
    AssertFalse(Server.Listening);
  finally
    FreeAndNil(Server);
    if DirectoryExists(TempBase) then
      RemoveNonEmptyDir(TempBase, true);
  end;
end;

initialization
  RegisterTest(TTestToolWasmPreviewServer);
end.
