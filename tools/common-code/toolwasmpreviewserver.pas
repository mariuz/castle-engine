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

{ Built-in localhost WebAssembly (@code(targetWeb)) HTTP preview server with
  COOP/COEP Cross-Origin Isolation headers, live build-stamp auto-reload, and
  WASM + @code(data/) payload size profiler (Phase 284 — UE 5.9 Web Parity). }
unit ToolWasmPreviewServer;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, SyncObjs
  {$if defined(FPC) and (not defined(WASI))}
  , FpHttpServer
  {$endif};

type
  { Asset payload category for WebAssembly download budget profiling. }
  TWasmPayloadCategory = (
    wpcWasmBinary,
    wpcJsHtmlShell,
    wpcPackedDataArchive,
    wpcTextures,
    wpcModels3D,
    wpcAudio,
    wpcDesignsFontsShaders,
    wpcOther
  );

  { Single file entry in a WebAssembly bundle or project data scan. }
  TWasmBundleFileEntry = record
    RelativePath: String;
    Extension: String;
    Category: TWasmPayloadCategory;
    SizeBytes: Int64;
    IsFromDist: Boolean;
  end;

  { Complete WebAssembly dist/ + data/ size breakdown & optimization report. }
  TWasmBundleReport = class
  public
    DistDirectory: String;
    DataDirectory: String;
    DistExists: Boolean;
    HasIndexHtml: Boolean;
    HasWasmBinary: Boolean;
    TotalDistBytes: Int64;
    TotalRawDataBytes: Int64;
    DistCategoryBytes: array [TWasmPayloadCategory] of Int64;
    DataCategoryBytes: array [TWasmPayloadCategory] of Int64;
    DistFiles: array of TWasmBundleFileEntry;
    LargestDataFiles: array of TWasmBundleFileEntry;
    EstSecondsSlow3G: Double;   // 1.5 Mbps
    EstSecondsFast4G: Double;   // 10 Mbps
    EstSecondsBroadband: Double;// 50 Mbps
    OptimizationHints: TStringList;

    constructor Create;
    destructor Destroy; override;
    function FormatMarkdownReport: String;
  end;

  TWasmServerLogEvent = procedure (const Msg: String) of object;

  { Embedded localhost HTTP server tailored for Castle Game Engine @code(targetWeb)
    builds (@code(castle-engine-output/web/dist)).
    Serves @code(application/wasm), @code(COOP/COEP) Cross-Origin Isolation headers,
    @code(Cache-Control: no-store), and @code(/__cge_live_reload) build-stamp polling. }
  TWasmPreviewHttpServer = class(TComponent)
  strict private
    {$if defined(FPC) and (not defined(WASI))}
    type
      THttpWorkerThread = class(TThread)
      strict private
        FOwnerServer: TWasmPreviewHttpServer;
        FHttpServer: TFPHttpServer;
        procedure HandleHttpRequest(Sender: TObject;
          var ARequest: TFPHTTPConnectionRequest;
          var AResponse: TFPHTTPConnectionResponse);
      protected
        procedure Execute; override;
      public
        constructor Create(const AOwnerServer: TWasmPreviewHttpServer; const APort: Word);
        destructor Destroy; override;
        procedure StopWorker;
      end;
    {$endif}
  strict private
    FLock: TCriticalSection;
    FDocumentRoot: String;
    FPort: Word;
    FListening: Boolean;
    FEnableCrossOriginIsolation: Boolean;
    FEnableAutoReload: Boolean;
    FRequestsServed: Int64;
    FBytesServed: Int64;
    FLastRequestedUri: String;
    FOnLog: TWasmServerLogEvent;
    {$if defined(FPC) and (not defined(WASI))}
    FWorkerThread: THttpWorkerThread;
    {$endif}
    procedure SetDocumentRoot(const AValue: String);
    procedure SetPort(const AValue: Word);
    function GetRequestsServed: Int64;
    function GetBytesServed: Int64;
    function GetLastRequestedUri: String;
    procedure RecordServed(const Uri: String; const NumBytes: Int64);
    procedure SnapshotConfig(out ARoot: String; out ACoopCoep, AAutoReload: Boolean);
  public
    const
      DefaultWasmPreviewPort = 8090;
      LiveReloadEndpoint = '/__cge_live_reload';

    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function StartServer: Boolean;
    procedure StopServer;
    function PreviewUrl(const CacheBust: Boolean = false): String;

    { Compute a deterministic modification/size stamp across build artifacts in @code(ADir). }
    class function ComputeDirectoryBuildStamp(const ADir: String): String;
    { Map file extension (including leading dot, e.g. @code('.wasm')) to HTTP Content-Type. }
    class function MimeTypeForExtension(const ExtLower: String): String;
    { Safely resolve an HTTP URI path inside @code(ARootDir); returns @false on traversal attempts. }
    class function ResolveSafeFilePath(const ARootDir, RequestUri: String;
      out FullFilePath: String): Boolean;
    { Inject the @code(/__cge_live_reload) polling snippet into an HTML document string. }
    class function InjectAutoReloadScript(const HtmlContent: String): String;

    property Listening: Boolean read FListening;
    property DocumentRoot: String read FDocumentRoot write SetDocumentRoot;
    property Port: Word read FPort write SetPort default DefaultWasmPreviewPort;
    property EnableCrossOriginIsolation: Boolean
      read FEnableCrossOriginIsolation write FEnableCrossOriginIsolation default true;
    property EnableAutoReload: Boolean
      read FEnableAutoReload write FEnableAutoReload default true;
    property RequestsServed: Int64 read GetRequestsServed;
    property BytesServed: Int64 read GetBytesServed;
    property LastRequestedUri: String read GetLastRequestedUri;
    property OnLog: TWasmServerLogEvent read FOnLog write FOnLog;
  end;

  { Stateless analyzer for CGE @code(castle-engine-output/web/dist) and @code(data/) directories. }
  TWasmBundleProfiler = class
  public
    class function CategorizeExtension(const ExtLower: String): TWasmPayloadCategory;
    class function CategoryDisplayName(const Cat: TWasmPayloadCategory): String;
    class function FormatBytesHuman(const Bytes: Int64): String;
    class function DefaultDistDirectoryForProject(const ProjectPath: String): String;
    class function DefaultDataDirectoryForProject(const ProjectPath: String): String;
    class function ProfileWebBundle(const DistDir: String;
      const ProjectDataDir: String = ''): TWasmBundleReport;
  end;

implementation

uses
  Math, StrUtils
  {$if defined(FPC) and (not defined(WASI))}
  , ssockets
  {$endif}
  , CastleUtils, CastleLog;

{ Helpers -------------------------------------------------------------------- }

type
  TWasmBundleFileEntryList = array of TWasmBundleFileEntry;

procedure AppendFileEntry(var Arr: TWasmBundleFileEntryList; var Count: Integer;
  const Entry: TWasmBundleFileEntry);
begin
  if Count >= Length(Arr) then
    SetLength(Arr, Max(16, Length(Arr) * 2));
  Arr[Count] := Entry;
  Inc(Count);
end;

procedure ScanFilesRecursive(const RootDir, SubDir: String;
  const IsDist: Boolean; var List: TWasmBundleFileEntryList; var Count: Integer);
var
  SR: TSearchRec;
  DirWithSep, FullItem, RelItem, Ext: String;
  Entry: TWasmBundleFileEntry;
begin
  if (RootDir = '') or (not DirectoryExists(SubDir)) then
    Exit;
  DirWithSep := IncludeTrailingPathDelimiter(SubDir);
  if FindFirst(DirWithSep + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then
          Continue;
        FullItem := DirWithSep + SR.Name;
        if (SR.Attr and faDirectory) <> 0 then
          ScanFilesRecursive(RootDir, FullItem, IsDist, List, Count)
        else
        begin
          RelItem := Copy(FullItem, Length(IncludeTrailingPathDelimiter(RootDir)) + 1, MaxInt);
          RelItem := StringReplace(RelItem, '\', '/', [rfReplaceAll]);
          Ext := LowerCase(ExtractFileExt(SR.Name));
          Entry := Default(TWasmBundleFileEntry);
          Entry.RelativePath := RelItem;
          Entry.Extension := Ext;
          Entry.Category := TWasmBundleProfiler.CategorizeExtension(Ext);
          Entry.SizeBytes := SR.Size;
          Entry.IsFromDist := IsDist;
          AppendFileEntry(List, Count, Entry);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

procedure SortEntriesBySizeDesc(var Arr: TWasmBundleFileEntryList);
var
  I, J: Integer;
  Tmp: TWasmBundleFileEntry;
begin
  for I := 0 to High(Arr) - 1 do
    for J := I + 1 to High(Arr) do
      if Arr[J].SizeBytes > Arr[I].SizeBytes then
      begin
        Tmp := Arr[I];
        Arr[I] := Arr[J];
        Arr[J] := Tmp;
      end;
end;

{ TWasmBundleReport ---------------------------------------------------------- }

constructor TWasmBundleReport.Create;
begin
  inherited;
  OptimizationHints := TStringList.Create;
end;

destructor TWasmBundleReport.Destroy;
begin
  FreeAndNil(OptimizationHints);
  inherited;
end;

function TWasmBundleReport.FormatMarkdownReport: String;
var
  SB: TStringBuilder;
  Cat: TWasmPayloadCategory;
  Pct: Double;
  I, MaxRows: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Game Engine — WebAssembly (`targetWeb`) Bundle Diagnostics');
    SB.AppendLine('');
    SB.AppendLine('- **Dist Directory:** `' + DistDirectory + '`');
    if DataDirectory <> '' then
      SB.AppendLine('- **Source Data Directory:** `' + DataDirectory + '`');
    SB.AppendLine(Format('- **Total Web Payload (`dist/`):** %s (%d bytes)',
      [TWasmBundleProfiler.FormatBytesHuman(TotalDistBytes), TotalDistBytes]));
    if TotalRawDataBytes > 0 then
      SB.AppendLine(Format('- **Uncompressed `data/` Source Assets:** %s (%d bytes)',
        [TWasmBundleProfiler.FormatBytesHuman(TotalRawDataBytes), TotalRawDataBytes]));
    SB.AppendLine(Format(
      '- **Estimated Cold Download:** Slow 3G (1.5 Mbps): `%.1fs` | Fast 4G (10 Mbps): `%.2fs` | Broadband (50 Mbps): `%.2fs`',
      [EstSecondsSlow3G, EstSecondsFast4G, EstSecondsBroadband]));
    SB.AppendLine('');

    SB.AppendLine('## `dist/` Payload Breakdown by Category');
    for Cat := Low(TWasmPayloadCategory) to High(TWasmPayloadCategory) do
      if (DistCategoryBytes[Cat] > 0) or (DataCategoryBytes[Cat] > 0) then
      begin
        if TotalDistBytes > 0 then
          Pct := (DistCategoryBytes[Cat] * 100.0) / TotalDistBytes
        else
          Pct := 0.0;
        SB.AppendLine(Format('- **%s:** Dist `%s` (%.1f%%) | Source Data `%s`',
          [TWasmBundleProfiler.CategoryDisplayName(Cat),
           TWasmBundleProfiler.FormatBytesHuman(DistCategoryBytes[Cat]),
           Pct,
           TWasmBundleProfiler.FormatBytesHuman(DataCategoryBytes[Cat])]));
      end;

    if Length(DistFiles) > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('## Largest `dist/` Artifacts');
      MaxRows := Min(10, Length(DistFiles));
      for I := 0 to MaxRows - 1 do
        SB.AppendLine(Format('- `%s` — **%s** (%s)',
          [DistFiles[I].RelativePath,
           TWasmBundleProfiler.FormatBytesHuman(DistFiles[I].SizeBytes),
           TWasmBundleProfiler.CategoryDisplayName(DistFiles[I].Category)]));
    end;

    if OptimizationHints.Count > 0 then
    begin
      SB.AppendLine('');
      SB.AppendLine('## Optimization Recommendations');
      for I := 0 to OptimizationHints.Count - 1 do
        SB.AppendLine('- ' + OptimizationHints[I]);
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

{ TWasmBundleProfiler -------------------------------------------------------- }

class function TWasmBundleProfiler.CategorizeExtension(
  const ExtLower: String): TWasmPayloadCategory;
begin
  if ExtLower = '.wasm' then
    Result := wpcWasmBinary
  else if MatchStr(ExtLower, ['.js', '.mjs', '.html', '.htm', '.css', '.map', '.ico']) then
    Result := wpcJsHtmlShell
  else if MatchStr(ExtLower, ['.zip', '.data', '.pak']) then
    Result := wpcPackedDataArchive
  else if MatchStr(ExtLower, ['.png', '.jpg', '.jpeg', '.webp', '.dds', '.ktx', '.ktx2', '.tga', '.bmp', '.rgbe', '.exr']) then
    Result := wpcTextures
  else if MatchStr(ExtLower, ['.gltf', '.glb', '.x3d', '.x3dv', '.wrl', '.obj', '.mtl', '.ifc', '.stl', '.dae', '.md3', '.plist', '.castle-sprite-sheet', '.castle-anim-frames', '.starling-xml']) then
    Result := wpcModels3D
  else if MatchStr(ExtLower, ['.ogg', '.wav', '.mp3', '.flac']) then
    Result := wpcAudio
  else if MatchStr(ExtLower, ['.castle-user-interface', '.castle-transform', '.castle-component', '.ttf', '.otf', '.woff', '.woff2', '.glsl', '.fs', '.vs', '.xml', '.json']) then
    Result := wpcDesignsFontsShaders
  else
    Result := wpcOther;
end;

class function TWasmBundleProfiler.CategoryDisplayName(
  const Cat: TWasmPayloadCategory): String;
begin
  case Cat of
    wpcWasmBinary:          Result := 'WebAssembly Code (.wasm)';
    wpcJsHtmlShell:         Result := 'JS / HTML / CSS Loader Shell';
    wpcPackedDataArchive:   Result := 'Packed Data Archive (.zip / .data)';
    wpcTextures:            Result := 'Textures & Images';
    wpcModels3D:            Result := '3D Models & Sprite Sheets';
    wpcAudio:               Result := 'Audio Clips (.ogg / .wav)';
    wpcDesignsFontsShaders: Result := 'CGE Designs, Fonts & Shaders';
    wpcOther:               Result := 'Other Files';
  end;
end;

class function TWasmBundleProfiler.FormatBytesHuman(const Bytes: Int64): String;
begin
  if Bytes >= 1024 * 1024 then
    Result := Format('%.2f MB', [Bytes / (1024.0 * 1024.0)])
  else if Bytes >= 1024 then
    Result := Format('%.1f KB', [Bytes / 1024.0])
  else
    Result := Format('%d B', [Bytes]);
end;

class function TWasmBundleProfiler.DefaultDistDirectoryForProject(
  const ProjectPath: String): String;
begin
  if Trim(ProjectPath) = '' then
    Result := ''
  else
    Result := IncludeTrailingPathDelimiter(ProjectPath) +
      'castle-engine-output' + PathDelim + 'web' + PathDelim + 'dist';
end;

class function TWasmBundleProfiler.DefaultDataDirectoryForProject(
  const ProjectPath: String): String;
begin
  if Trim(ProjectPath) = '' then
    Result := ''
  else
    Result := IncludeTrailingPathDelimiter(ProjectPath) + 'data';
end;

class function TWasmBundleProfiler.ProfileWebBundle(const DistDir: String;
  const ProjectDataDir: String): TWasmBundleReport;
var
  DistList, DataList: TWasmBundleFileEntryList;
  DistCount, DataCount, I, KeepCount: Integer;
  WasmBytes, UncompressedWavBytes: Int64;
begin
  Result := TWasmBundleReport.Create;
  Result.DistDirectory := DistDir;
  Result.DataDirectory := ProjectDataDir;
  Result.DistExists := (DistDir <> '') and DirectoryExists(DistDir);

  DistList := nil;
  DataList := nil;
  DistCount := 0;
  DataCount := 0;

  if Result.DistExists then
  begin
    ScanFilesRecursive(DistDir, DistDir, true, DistList, DistCount);
    SetLength(DistList, DistCount);
    SortEntriesBySizeDesc(DistList);
    Result.DistFiles := DistList;

    for I := 0 to High(DistList) do
    begin
      Result.TotalDistBytes := Result.TotalDistBytes + DistList[I].SizeBytes;
      Result.DistCategoryBytes[DistList[I].Category] :=
        Result.DistCategoryBytes[DistList[I].Category] + DistList[I].SizeBytes;
      if SameText(ExtractFileName(DistList[I].RelativePath), 'index.html') then
        Result.HasIndexHtml := true;
      if DistList[I].Extension = '.wasm' then
        Result.HasWasmBinary := true;
    end;
  end;

  UncompressedWavBytes := 0;
  if (ProjectDataDir <> '') and DirectoryExists(ProjectDataDir) then
  begin
    ScanFilesRecursive(ProjectDataDir, ProjectDataDir, false, DataList, DataCount);
    SetLength(DataList, DataCount);
    SortEntriesBySizeDesc(DataList);

    for I := 0 to High(DataList) do
    begin
      Result.TotalRawDataBytes := Result.TotalRawDataBytes + DataList[I].SizeBytes;
      Result.DataCategoryBytes[DataList[I].Category] :=
        Result.DataCategoryBytes[DataList[I].Category] + DataList[I].SizeBytes;
      if DataList[I].Extension = '.wav' then
        UncompressedWavBytes := UncompressedWavBytes + DataList[I].SizeBytes;
    end;

    KeepCount := Min(25, Length(DataList));
    SetLength(Result.LargestDataFiles, KeepCount);
    for I := 0 to KeepCount - 1 do
      Result.LargestDataFiles[I] := DataList[I];
  end;

  { Network transfer estimates: bits = Bytes * 8 }
  Result.EstSecondsSlow3G := (Result.TotalDistBytes * 8.0) / 1500000.0;
  Result.EstSecondsFast4G := (Result.TotalDistBytes * 8.0) / 10000000.0;
  Result.EstSecondsBroadband := (Result.TotalDistBytes * 8.0) / 50000000.0;

  { Actionable optimization diagnostics }
  if not Result.DistExists then
    Result.OptimizationHints.Add(
      'Web output directory does not exist yet. Run `castle-engine compile --target=web` to generate `castle-engine-output/web/dist`.')
  else
  begin
    if not Result.HasIndexHtml then
      Result.OptimizationHints.Add(
        'Missing `index.html` in `dist/` — verify `castle-engine compile --target=web` completed cleanly.');
    if not Result.HasWasmBinary then
      Result.OptimizationHints.Add(
        'No `.wasm` module found in `dist/` — verify FPC `wasm32-wasip1` cross-compiler is installed.');
  end;

  WasmBytes := Result.DistCategoryBytes[wpcWasmBinary];
  if WasmBytes > 15 * 1024 * 1024 then
    Result.OptimizationHints.Add(Format(
      '`.wasm` binary is %s (> 15 MB). Compile in `--mode=release` so `wasm-opt` strips DWARF/debug sections and shrinks code size.',
      [FormatBytesHuman(WasmBytes)]));

  if UncompressedWavBytes > 1024 * 1024 then
    Result.OptimizationHints.Add(Format(
      'Uncompressed `.wav` audio in `data/` totals %s. Convert music/ambient tracks to `.ogg` Vorbis to cut web download payload by 70-85%%.',
      [FormatBytesHuman(UncompressedWavBytes)]));

  if Result.DataCategoryBytes[wpcTextures] > 20 * 1024 * 1024 then
    Result.OptimizationHints.Add(Format(
      'Source textures in `data/` total %s. Consider WebP/JPEG/KTX2 compression or `material_properties.xml` GPU texture downscaling for web targets.',
      [FormatBytesHuman(Result.DataCategoryBytes[wpcTextures])]));

  if (Result.DistExists) and (Result.HasIndexHtml) and (Result.HasWasmBinary) and
     (Result.OptimizationHints.Count = 0) then
    Result.OptimizationHints.Add(
      'Web bundle looks healthy and compact! Keep COOP/COEP headers enabled when deploying to production CDN/hosts.');
end;

{ TWasmPreviewHttpServer.THttpWorkerThread ----------------------------------- }

{$if defined(FPC) and (not defined(WASI))}
constructor TWasmPreviewHttpServer.THttpWorkerThread.Create(
  const AOwnerServer: TWasmPreviewHttpServer; const APort: Word);
begin
  inherited Create(true);
  FreeOnTerminate := false;
  FOwnerServer := AOwnerServer;
  FHttpServer := TFPHttpServer.Create(nil);
  FHttpServer.Port := APort;
  FHttpServer.Threaded := false;
  FHttpServer.OnRequest := @HandleHttpRequest;
end;

destructor TWasmPreviewHttpServer.THttpWorkerThread.Destroy;
begin
  FreeAndNil(FHttpServer);
  inherited;
end;

procedure TWasmPreviewHttpServer.THttpWorkerThread.StopWorker;
begin
  Terminate;
  if FHttpServer <> nil then
    FHttpServer.Active := false;
end;

procedure TWasmPreviewHttpServer.THttpWorkerThread.Execute;
begin
  try
    FHttpServer.Active := true;
  except
    on E: Exception do
      WritelnWarning('WasmPreview', 'HTTP preview listener stopped: ' + E.Message);
  end;
end;

procedure TWasmPreviewHttpServer.THttpWorkerThread.HandleHttpRequest(
  Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  RemoteAddr, RootDir, FullPath, ExtLower, HtmlStr, StampStr: String;
  CoopCoep, AutoReload: Boolean;
  FS: TFileStream;
  RawBytes: TBytes;
begin
  RemoteAddr := Trim(ARequest.RemoteAddress);
  if (RemoteAddr <> '') and
     (RemoteAddr <> '127.0.0.1') and
     (RemoteAddr <> '::1') and
     (Pos('127.', RemoteAddr) <> 1) and
     (Pos('::ffff:127.', LowerCase(RemoteAddr)) <> 1) then
  begin
    AResponse.Code := 403;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'Forbidden: CGE WebAssembly preview server accepts loopback connections only.';
    Exit;
  end;

  FOwnerServer.SnapshotConfig(RootDir, CoopCoep, AutoReload);

  AResponse.SetCustomHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
  if CoopCoep then
  begin
    AResponse.SetCustomHeader('Cross-Origin-Opener-Policy', 'same-origin');
    AResponse.SetCustomHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    AResponse.SetCustomHeader('Cross-Origin-Resource-Policy', 'same-origin');
  end;

  if SameText(ARequest.Method, 'OPTIONS') then
  begin
    AResponse.Code := 204;
    AResponse.Content := '';
    Exit;
  end;

  if (Pos(TWasmPreviewHttpServer.LiveReloadEndpoint, ARequest.URI) = 1) then
  begin
    StampStr := TWasmPreviewHttpServer.ComputeDirectoryBuildStamp(RootDir);
    AResponse.Code := 200;
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.Content := Format('{"status":"ok","stamp":"%s","coopCoep":%s}',
      [StampStr, LowerCase(BoolToStr(CoopCoep, true))]);
    FOwnerServer.RecordServed(ARequest.URI, Length(AResponse.Content));
    Exit;
  end;

  if (not SameText(ARequest.Method, 'GET')) and (not SameText(ARequest.Method, 'HEAD')) then
  begin
    AResponse.Code := 405;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'Method Not Allowed';
    Exit;
  end;

  if not TWasmPreviewHttpServer.ResolveSafeFilePath(RootDir, ARequest.URI, FullPath) then
  begin
    AResponse.Code := 403;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'Forbidden path';
    Exit;
  end;

  if not FileExists(FullPath) then
  begin
    AResponse.Code := 404;
    AResponse.ContentType := 'text/plain; charset=utf-8';
    AResponse.Content := 'Not Found: ' + ARequest.URI;
    Exit;
  end;

  ExtLower := LowerCase(ExtractFileExt(FullPath));
  AResponse.Code := 200;
  AResponse.ContentType := TWasmPreviewHttpServer.MimeTypeForExtension(ExtLower);

  FS := TFileStream.Create(FullPath, fmOpenRead or fmShareDenyNone);
  try
    if AutoReload and ((ExtLower = '.html') or (ExtLower = '.htm')) then
    begin
      SetLength(RawBytes, FS.Size);
      if FS.Size > 0 then
        FS.ReadBuffer(RawBytes[0], FS.Size);
      SetString(HtmlStr, PAnsiChar(@RawBytes[0]), Length(RawBytes));
      HtmlStr := TWasmPreviewHttpServer.InjectAutoReloadScript(HtmlStr);
      AResponse.Content := HtmlStr;
      FOwnerServer.RecordServed(ARequest.URI, Length(HtmlStr));
    end else
    begin
      AResponse.ContentStream := FS;
      AResponse.FreeContentStream := true;
      FOwnerServer.RecordServed(ARequest.URI, FS.Size);
      FS := nil; // Owned and freed by AResponse
    end;
  finally
    FreeAndNil(FS);
  end;
end;
{$endif}

{ TWasmPreviewHttpServer ----------------------------------------------------- }

constructor TWasmPreviewHttpServer.Create(AOwner: TComponent);
begin
  inherited;
  FLock := TCriticalSection.Create;
  FPort := DefaultWasmPreviewPort;
  FEnableCrossOriginIsolation := true;
  FEnableAutoReload := true;
  FListening := false;
end;

destructor TWasmPreviewHttpServer.Destroy;
begin
  StopServer;
  FreeAndNil(FLock);
  inherited;
end;

procedure TWasmPreviewHttpServer.SetDocumentRoot(const AValue: String);
begin
  FLock.Acquire;
  try
    FDocumentRoot := ExcludeTrailingPathDelimiter(Trim(AValue));
  finally
    FLock.Release;
  end;
end;

procedure TWasmPreviewHttpServer.SetPort(const AValue: Word);
var
  WasListening: Boolean;
begin
  if (AValue = 0) or (FPort = AValue) then
    Exit;
  WasListening := FListening;
  if WasListening then
    StopServer;
  FPort := AValue;
  if WasListening then
    StartServer;
end;

function TWasmPreviewHttpServer.GetRequestsServed: Int64;
begin
  FLock.Acquire;
  try
    Result := FRequestsServed;
  finally
    FLock.Release;
  end;
end;

function TWasmPreviewHttpServer.GetBytesServed: Int64;
begin
  FLock.Acquire;
  try
    Result := FBytesServed;
  finally
    FLock.Release;
  end;
end;

function TWasmPreviewHttpServer.GetLastRequestedUri: String;
begin
  FLock.Acquire;
  try
    Result := FLastRequestedUri;
  finally
    FLock.Release;
  end;
end;

procedure TWasmPreviewHttpServer.RecordServed(const Uri: String; const NumBytes: Int64);
begin
  FLock.Acquire;
  try
    Inc(FRequestsServed);
    FBytesServed := FBytesServed + Max(0, NumBytes);
    FLastRequestedUri := Uri;
  finally
    FLock.Release;
  end;
end;

procedure TWasmPreviewHttpServer.SnapshotConfig(out ARoot: String;
  out ACoopCoep, AAutoReload: Boolean);
begin
  FLock.Acquire;
  try
    ARoot := FDocumentRoot;
    ACoopCoep := FEnableCrossOriginIsolation;
    AAutoReload := FEnableAutoReload;
  finally
    FLock.Release;
  end;
end;

function TWasmPreviewHttpServer.StartServer: Boolean;
begin
  if FListening then
    Exit(true);
  {$if defined(FPC) and (not defined(WASI))}
  try
    FWorkerThread := THttpWorkerThread.Create(Self, FPort);
    FWorkerThread.Start;
    FListening := true;
    if Assigned(FOnLog) then
      FOnLog(Format('[WASM Preview] Serving "%s" at %s (COOP/COEP=%s)',
        [FDocumentRoot, PreviewUrl(false), BoolToStr(FEnableCrossOriginIsolation, true)]));
    Result := true;
  except
    on E: Exception do
    begin
      FreeAndNil(FWorkerThread);
      FListening := false;
      if Assigned(FOnLog) then
        FOnLog('[WASM Preview] Failed to start server: ' + E.Message);
      Result := false;
    end;
  end;
  {$else}
  Result := false;
  {$endif}
end;

procedure TWasmPreviewHttpServer.StopServer;
{$if defined(FPC) and (not defined(WASI))}
var
  WakeSock: TInetSocket;
{$endif}
begin
  {$if defined(FPC) and (not defined(WASI))}
  if FWorkerThread <> nil then
  begin
    FWorkerThread.StopWorker;
    if not FWorkerThread.Finished then
    begin
      try
        WakeSock := TInetSocket.Create('127.0.0.1', FPort, 100);
        FreeAndNil(WakeSock);
      except
      end;
    end;
    FWorkerThread.WaitFor;
    FreeAndNil(FWorkerThread);
  end;
  {$endif}
  if FListening then
  begin
    FListening := false;
    if Assigned(FOnLog) then
      FOnLog('[WASM Preview] Stopped localhost HTTP preview server.');
  end;
end;

function TWasmPreviewHttpServer.PreviewUrl(const CacheBust: Boolean): String;
begin
  Result := Format('http://127.0.0.1:%d/index.html', [FPort]);
  if CacheBust then
    Result := Result + '?t=' + IntToStr(GetTickCount64);
end;

class function TWasmPreviewHttpServer.ComputeDirectoryBuildStamp(
  const ADir: String): String;
var
  SR: TSearchRec;
  FileCount: Integer;
  TotalSize, MaxAge: Int64;
begin
  FileCount := 0;
  TotalSize := 0;
  MaxAge := 0;
  if (ADir <> '') and DirectoryExists(ADir) then
  begin
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, SR) = 0 then
    begin
      try
        repeat
          if (SR.Name = '.') or (SR.Name = '..') or ((SR.Attr and faDirectory) <> 0) then
            Continue;
          Inc(FileCount);
          TotalSize := TotalSize + SR.Size;
          if SR.Time > MaxAge then
            MaxAge := SR.Time;
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    end;
  end;
  Result := Format('%d-%d-%d', [FileCount, TotalSize, MaxAge]);
end;

class function TWasmPreviewHttpServer.MimeTypeForExtension(
  const ExtLower: String): String;
begin
  if ExtLower = '.wasm' then
    Result := 'application/wasm'
  else if (ExtLower = '.js') or (ExtLower = '.mjs') then
    Result := 'text/javascript; charset=utf-8'
  else if (ExtLower = '.html') or (ExtLower = '.htm') then
    Result := 'text/html; charset=utf-8'
  else if ExtLower = '.css' then
    Result := 'text/css; charset=utf-8'
  else if (ExtLower = '.json') or (ExtLower = '.gltf') or
          (ExtLower = '.castle-user-interface') or (ExtLower = '.castle-transform') then
    Result := 'application/json; charset=utf-8'
  else if ExtLower = '.zip' then
    Result := 'application/zip'
  else if ExtLower = '.png' then
    Result := 'image/png'
  else if (ExtLower = '.jpg') or (ExtLower = '.jpeg') then
    Result := 'image/jpeg'
  else if ExtLower = '.webp' then
    Result := 'image/webp'
  else if ExtLower = '.svg' then
    Result := 'image/svg+xml'
  else if ExtLower = '.ico' then
    Result := 'image/x-icon'
  else if ExtLower = '.ogg' then
    Result := 'audio/ogg'
  else if ExtLower = '.wav' then
    Result := 'audio/wav'
  else if ExtLower = '.mp3' then
    Result := 'audio/mpeg'
  else if ExtLower = '.woff2' then
    Result := 'font/woff2'
  else if ExtLower = '.ttf' then
    Result := 'font/ttf'
  else
    Result := 'application/octet-stream';
end;

class function TWasmPreviewHttpServer.ResolveSafeFilePath(
  const ARootDir, RequestUri: String; out FullFilePath: String): Boolean;
var
  CleanUri, RelPath, ExpandedRoot, ExpandedTarget: String;
  QPos: Integer;
begin
  FullFilePath := '';
  Result := false;
  if Trim(ARootDir) = '' then
    Exit;

  CleanUri := RequestUri;
  QPos := Pos('?', CleanUri);
  if QPos > 0 then
    CleanUri := Copy(CleanUri, 1, QPos - 1);
  QPos := Pos('#', CleanUri);
  if QPos > 0 then
    CleanUri := Copy(CleanUri, 1, QPos - 1);

  if (Pos(#0, CleanUri) > 0) or (Pos('..', CleanUri) > 0) or (Pos(':', CleanUri) > 0) then
    Exit;

  while (CleanUri <> '') and (CleanUri[1] = '/') do
    Delete(CleanUri, 1, 1);

  if CleanUri = '' then
    CleanUri := 'index.html';

  RelPath := StringReplace(CleanUri, '/', PathDelim, [rfReplaceAll]);
  ExpandedRoot := IncludeTrailingPathDelimiter(ExpandFileName(ARootDir));
  ExpandedTarget := ExpandFileName(ExpandedRoot + RelPath);

  if DirectoryExists(ExpandedTarget) then
    ExpandedTarget := IncludeTrailingPathDelimiter(ExpandedTarget) + 'index.html';

  {$ifdef MSWINDOWS}
  Result := SameText(Copy(ExpandedTarget, 1, Length(ExpandedRoot)), ExpandedRoot);
  {$else}
  Result := Copy(ExpandedTarget, 1, Length(ExpandedRoot)) = ExpandedRoot;
  {$endif}
  if Result then
    FullFilePath := ExpandedTarget;
end;

class function TWasmPreviewHttpServer.InjectAutoReloadScript(
  const HtmlContent: String): String;
const
  ReloadSnippet =
    '<script>(function(){var s="";setInterval(function(){fetch("/__cge_live_reload",{cache:"no-store"})' +
    '.then(function(r){return r.json();}).then(function(d){if(!s)s=d.stamp;else if(d.stamp&&d.stamp!==s)location.reload();})' +
    '.catch(function(){});},1500);})();</script>';
var
  BodyClosePos: Integer;
begin
  if Pos('/__cge_live_reload', HtmlContent) > 0 then
    Exit(HtmlContent);
  BodyClosePos := Pos('</body>', LowerCase(HtmlContent));
  if BodyClosePos > 0 then
    Result := Copy(HtmlContent, 1, BodyClosePos - 1) + ReloadSnippet +
      Copy(HtmlContent, BodyClosePos, MaxInt)
  else
    Result := HtmlContent + ReloadSnippet;
end;

end.
