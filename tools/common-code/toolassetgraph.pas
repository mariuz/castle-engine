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

{ Project-wide bidirectional asset reference graph, unreferenced orphan asset
  sweeper, and broken @code(castle-data:/) URL auto-repair engine
  (@link(TAssetDependencyAnalyzer))
  (Phase 292 — UE 5.9 / 6.0 Reference Viewer & Redirector Repair Parity). }
unit ToolAssetGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils;

type
  TAssetCategory = (
    acDesign,
    acModel3D,
    acSpriteSheet,
    acTextureImage,
    acAudio,
    acFont,
    acShaderOrConfig,
    acOther
  );

  { Metadata and bidirectional edges for a single file inside @code(data/). }
  TAssetNodeInfo = record
    DataRelPath: String;
    CastleDataUrl: String;
    FullDiskPath: String;
    FileNameLower: String;
    StemLower: String;
    Category: TAssetCategory;
    SizeBytes: Int64;
    FastContentSig: QWord;
    Dependencies: array of String;
    Referencers: array of String;
    BrokenUrls: array of String;
    IsRootEntry: Boolean;
    IsOrphan: Boolean;
  end;

  TAssetNodeInfoArray = array of TAssetNodeInfo;

  { Proposed repair mapping for a broken @code(castle-data:/) or relative URL. }
  TBrokenUrlRepairAction = record
    OwnerAssetRelPath: String;
    BrokenUrl: String;
    SuggestedUrl: String;
    MatchReason: String;
  end;

  TBrokenUrlRepairArray = array of TBrokenUrlRepairAction;

  { Project-wide @code(data/) reference graph & health audit. }
  TAssetGraphReport = record
    DataDirPath: String;
    Nodes: TAssetNodeInfoArray;
    Repairs: TBrokenUrlRepairArray;
    TotalAssets: Integer;
    TotalBytes: Int64;
    OrphanCount: Integer;
    OrphanBytes: Int64;
    BrokenUrlCount: Integer;
  end;

  TAssetDependencyAnalyzer = class
  public
    { Classify a filename by extension into @link(TAssetCategory). }
    class function ClassifyAssetExtension(const AFileName: String): TAssetCategory;

    { Scan @code(ADataDirPath) recursively, build bidirectional
      @code(Referencers <-> Dependencies), detect orphan assets, and propose
      auto-repairs for broken URLs. }
    class function AnalyzeDataDirectory(const ADataDirPath: String): TAssetGraphReport;

    { Locate node index by @code(DataRelPath) (case-insensitive), or @code(-1). }
    class function FindNodeIndex(const AReport: TAssetGraphReport;
      const ADataRelPath: String): Integer;

    { Rewrite owner files on disk to repair broken URLs using @code(ARepairs).
      Returns total number of repaired URL occurrences. }
    class function RepairBrokenUrls(const ADataDirPath: String;
      const ARepairs: array of TBrokenUrlRepairAction): Integer;

    { Non-destructively quarantine orphan assets from @code(data/) into
      @code(<ParentOfData>/.castle-orphan-trash/), preserving relative paths.
      Returns number of moved files. }
    class function SweepOrphanAssetsToTrash(const ADataDirPath: String;
      const AOrphanRelPaths: array of String;
      out OutTrashDir: String): Integer;

    { Export Markdown summary + Mermaid @code(flowchart LR) graph. }
    class function FormatAssetGraphMarkdown(const AReport: TAssetGraphReport): String;
  end;

function AssetCategoryToDisplayName(const ACat: TAssetCategory): String;
function FormatByteSizeShort(const ABytes: Int64): String;

implementation

uses
  Math, StrUtils;

function AssetCategoryToDisplayName(const ACat: TAssetCategory): String;
begin
  case ACat of
    acDesign:         Result := 'Design';
    acModel3D:        Result := '3D Model';
    acSpriteSheet:    Result := 'SpriteSheet';
    acTextureImage:   Result := 'Texture';
    acAudio:          Result := 'Audio';
    acFont:           Result := 'Font';
    acShaderOrConfig: Result := 'Config/Shader';
    acOther:          Result := 'Other';
  end;
end;

function FormatByteSizeShort(const ABytes: Int64): String;
begin
  if ABytes < 1024 then
    Result := Format('%d B', [ABytes])
  else if ABytes < 1024 * 1024 then
    Result := Format('%.1f KB', [ABytes / 1024.0])
  else
    Result := Format('%.2f MB', [ABytes / (1024.0 * 1024.0)]);
end;

function NormalizeSlashPath(const S: String): String;
var
  Parts: array of String;
  Count, I, StartIdx: Integer;
  Seg, Clean: String;
begin
  Clean := StringReplace(Trim(S), '\', '/', [rfReplaceAll]);
  while (Length(Clean) > 0) and (Clean[1] = '/') do
    Delete(Clean, 1, 1);

  SetLength(Parts, 0);
  Count := 0;
  StartIdx := 1;
  for I := 1 to Length(Clean) + 1 do
    if (I > Length(Clean)) or (Clean[I] = '/') then
    begin
      Seg := Copy(Clean, StartIdx, I - StartIdx);
      StartIdx := I + 1;
      if (Seg = '') or (Seg = '.') then
        Continue
      else if Seg = '..' then
      begin
        if Count > 0 then
          Dec(Count);
      end else
      begin
        if Count >= Length(Parts) then
          SetLength(Parts, Count + 8);
        Parts[Count] := Seg;
        Inc(Count);
      end;
    end;

  Result := '';
  for I := 0 to Count - 1 do
  begin
    if I > 0 then
      Result := Result + '/';
    Result := Result + Parts[I];
  end;
end;

function RelDirOf(const ARelFile: String): String;
var
  LastSlash: Integer;
begin
  LastSlash := LastDelimiter('/', ARelFile);
  if LastSlash > 1 then
    Result := Copy(ARelFile, 1, LastSlash - 1)
  else
    Result := '';
end;

function ComputeFastFileSignature(const AFullPath: String;
  const ASizeBytes: Int64): QWord;
const
  FnvOffset: QWord = QWord($CBF29CE484222325);
  FnvPrime: QWord = QWord($00000100000001B3);
var
  FS: TFileStream;
  Buf: array [0..4095] of Byte;
  NRead, I: Integer;
begin
  {$PUSH}{$Q-}{$R-}
  Result := FnvOffset xor QWord(ASizeBytes);
  if (ASizeBytes <= 0) or (not FileExists(AFullPath)) then
    Exit;
  try
    FS := TFileStream.Create(AFullPath, fmOpenRead or fmShareDenyNone);
    try
      NRead := FS.Read(Buf[0], Min(Int64(SizeOf(Buf)), ASizeBytes));
      for I := 0 to NRead - 1 do
        Result := (Result xor Buf[I]) * FnvPrime;
    finally
      FreeAndNil(FS);
    end;
  except
    { Keep size-seeded hash if locked }
  end;
  {$POP}
end;

procedure AppendUniqueDynStr(var Arr: TStringArray; const Val: String);
var
  I, N: Integer;
begin
  for I := 0 to High(Arr) do
    if SameText(Arr[I], Val) then
      Exit;
  N := Length(Arr);
  SetLength(Arr, N + 1);
  Arr[N] := Val;
end;

function ReadFileAsStringSafe(const AFullPath: String): String;
var
  FS: TFileStream;
  Bytes: RawByteString;
begin
  Result := '';
  if not FileExists(AFullPath) then
    Exit;
  FS := TFileStream.Create(AFullPath, fmOpenRead or fmShareDenyNone);
  try
    if FS.Size <= 0 then
      Exit('');
    SetLength(Bytes, FS.Size);
    FS.ReadBuffer(Bytes[1], FS.Size);
    Result := String(Bytes);
  finally
    FreeAndNil(FS);
  end;
end;

procedure WriteStringToFileSafe(const AFullPath, AContent: String);
var
  FS: TFileStream;
begin
  ForceDirectories(ExtractFileDir(AFullPath));
  FS := TFileStream.Create(AFullPath, fmCreate);
  try
    if Length(AContent) > 0 then
      FS.WriteBuffer(AContent[1], Length(AContent));
  finally
    FreeAndNil(FS);
  end;
end;

function IsScannableReferencerAsset(const AExtLower: String): Boolean;
begin
  Result :=
    (AExtLower = '.castle-user-interface') or
    (AExtLower = '.castle-transform') or
    (AExtLower = '.castle-component') or
    (AExtLower = '.castle-sprite-sheet') or
    (AExtLower = '.gltf') or
    (AExtLower = '.x3dv') or
    (AExtLower = '.x3d') or
    (AExtLower = '.mtl') or
    (AExtLower = '.atlas') or
    (AExtLower = '.xml') or
    (AExtLower = '.json');
end;

function StripAnchorAndQuery(const RawRef: String): String;
var
  P: Integer;
begin
  Result := Trim(RawRef);
  P := Pos('#', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
  P := Pos('?', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
end;

procedure ExtractAssetReferencesFromText(const AContent, AOwnerExtLower: String;
  var OutRefs: TStringArray);
const
  CastlePrefix = 'castle-data:/';
var
  Len, I, StartPos, EndPos, KeyPos: Integer;
  Candidate, Sub: String;
begin
  SetLength(OutRefs, 0);
  Len := Length(AContent);
  if Len = 0 then
    Exit;

  { 1. Extract all castle-data:/... occurrences inside quotes or XML attributes }
  I := 1;
  while I <= Len - Length(CastlePrefix) + 1 do
  begin
    if (AContent[I] in ['c', 'C']) and
       SameText(Copy(AContent, I, Length(CastlePrefix)), CastlePrefix) then
    begin
      EndPos := I + Length(CastlePrefix);
      while (EndPos <= Len) and
            not (AContent[EndPos] in ['"', '''', '<', '>', #13, #10, #9]) do
        Inc(EndPos);
      Candidate := StripAnchorAndQuery(Copy(AContent, I, EndPos - I));
      if Length(Candidate) > Length(CastlePrefix) then
        AppendUniqueDynStr(OutRefs, Candidate);
      I := EndPos + 1;
    end else
      Inc(I);
  end;

  { 2. For .gltf / .castle-sprite-sheet / .xml / .x3d, extract relative "uri" / file attributes }
  if (AOwnerExtLower = '.gltf') or (AOwnerExtLower = '.castle-sprite-sheet') or
     (AOwnerExtLower = '.xml') or (AOwnerExtLower = '.x3d') then
  begin
    I := 1;
    while I <= Len do
    begin
      if AContent[I] = '"' then
      begin
        StartPos := I + 1;
        EndPos := StartPos;
        while (EndPos <= Len) and (AContent[EndPos] <> '"') and
              not (AContent[EndPos] in [#13, #10]) do
          Inc(EndPos);
        if (EndPos <= Len) and (AContent[EndPos] = '"') then
        begin
          Sub := StripAnchorAndQuery(Copy(AContent, StartPos, EndPos - StartPos));
          if (Sub <> '') and
             (not StartsText('data:', Sub)) and
             (not StartsText('http://', Sub)) and
             (not StartsText('https://', Sub)) and
             (not StartsText('castle-data:/', Sub)) and
             (Pos(' ', Sub) = 0) and
             (ExtractFileExt(Sub) <> '') then
          begin
            { In glTF specifically, verify preceding token mentions uri or image/buffer/file }
            KeyPos := Max(1, I - 24);
            if (AOwnerExtLower <> '.gltf') or
               (Pos('"uri"', LowerCase(Copy(AContent, KeyPos, I - KeyPos))) > 0) then
              AppendUniqueDynStr(OutRefs, Sub);
          end;
          I := EndPos + 1;
          Continue;
        end;
      end;
      Inc(I);
    end;
  end;
end;

{ TAssetDependencyAnalyzer --------------------------------------------------- }

class function TAssetDependencyAnalyzer.ClassifyAssetExtension(
  const AFileName: String): TAssetCategory;
var
  Ext: String;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  if (Ext = '.castle-user-interface') or (Ext = '.castle-transform') or
     (Ext = '.castle-component') then
    Result := acDesign
  else if (Ext = '.gltf') or (Ext = '.glb') or (Ext = '.x3d') or
          (Ext = '.x3dv') or (Ext = '.obj') or (Ext = '.dae') or
          (Ext = '.stl') or (Ext = '.ifc') or (Ext = '.md3') then
    Result := acModel3D
  else if (Ext = '.castle-sprite-sheet') or (Ext = '.starling-xml') or
          (Ext = '.cocos2d-plist') or (Ext = '.atlas') then
    Result := acSpriteSheet
  else if (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') or
          (Ext = '.webp') or (Ext = '.ktx') or (Ext = '.dds') or
          (Ext = '.tga') or (Ext = '.bmp') or (Ext = '.rgbe') then
    Result := acTextureImage
  else if (Ext = '.ogg') or (Ext = '.wav') or (Ext = '.mp3') or
          (Ext = '.flac') then
    Result := acAudio
  else if (Ext = '.ttf') or (Ext = '.otf') or (Ext = '.woff') then
    Result := acFont
  else if (Ext = '.glsl') or (Ext = '.vs') or (Ext = '.fs') or
          (Ext = '.xml') or (Ext = '.json') or (Ext = '.ini') or
          (Ext = '.cfg') then
    Result := acShaderOrConfig
  else
    Result := acOther;
end;

class function TAssetDependencyAnalyzer.FindNodeIndex(
  const AReport: TAssetGraphReport; const ADataRelPath: String): Integer;
var
  Norm: String;
  I: Integer;
begin
  Norm := NormalizeSlashPath(ADataRelPath);
  for I := 0 to High(AReport.Nodes) do
    if SameText(AReport.Nodes[I].DataRelPath, Norm) then
      Exit(I);
  Result := -1;
end;

class function TAssetDependencyAnalyzer.AnalyzeDataDirectory(
  const ADataDirPath: String): TAssetGraphReport;
var
  CleanRoot: String;

  procedure WalkDir(const ACurrentDiskDir, ARelPrefix: String);
  var
    SR: TSearchRec;
    ChildDisk, ChildRel, ExtLow, NameLow: String;
    Idx: Integer;
  begin
    if FindFirst(IncludeTrailingPathDelimiter(ACurrentDiskDir) + '*',
         faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') or (SR.Name = '') then
          Continue;
        if SR.Name[1] = '.' then
          Continue;

        ChildDisk := IncludeTrailingPathDelimiter(ACurrentDiskDir) + SR.Name;
        if ARelPrefix = '' then
          ChildRel := SR.Name
        else
          ChildRel := ARelPrefix + '/' + SR.Name;

        if (SR.Attr and faDirectory) <> 0 then
          WalkDir(ChildDisk, ChildRel)
        else
        begin
          Idx := Length(Result.Nodes);
          SetLength(Result.Nodes, Idx + 1);
          Result.Nodes[Idx] := Default(TAssetNodeInfo);
          Result.Nodes[Idx].DataRelPath := NormalizeSlashPath(ChildRel);
          Result.Nodes[Idx].CastleDataUrl := 'castle-data:/' + Result.Nodes[Idx].DataRelPath;
          Result.Nodes[Idx].FullDiskPath := ChildDisk;
          NameLow := LowerCase(SR.Name);
          ExtLow := LowerCase(ExtractFileExt(SR.Name));
          Result.Nodes[Idx].FileNameLower := NameLow;
          Result.Nodes[Idx].StemLower := LowerCase(ChangeFileExt(SR.Name, ''));
          Result.Nodes[Idx].Category := ClassifyAssetExtension(SR.Name);
          Result.Nodes[Idx].SizeBytes := SR.Size;
          Result.Nodes[Idx].FastContentSig := ComputeFastFileSignature(ChildDisk, SR.Size);

          { Top-level UI views, CastleSettings.xml, and sound repo XMLs act as entry roots }
          Result.Nodes[Idx].IsRootEntry :=
            (ExtLow = '.castle-user-interface') or
            SameText(SR.Name, 'CastleSettings.xml') or
            SameText(SR.Name, 'sounds.xml');

          Inc(Result.TotalAssets);
          Inc(Result.TotalBytes, SR.Size);
        end;
      until FindNext(SR) <> 0;
    finally
      SysUtils.FindClose(SR);
    end;
  end;

  procedure AddDepEdge(const SrcIdx, DstIdx: Integer);
  var
    I, N: Integer;
    SrcRel, DstRel: String;
  begin
    if (SrcIdx < 0) or (DstIdx < 0) or (SrcIdx = DstIdx) then
      Exit;
    SrcRel := Result.Nodes[SrcIdx].DataRelPath;
    DstRel := Result.Nodes[DstIdx].DataRelPath;

    for I := 0 to High(Result.Nodes[SrcIdx].Dependencies) do
      if SameText(Result.Nodes[SrcIdx].Dependencies[I], DstRel) then
        Exit;
    N := Length(Result.Nodes[SrcIdx].Dependencies);
    SetLength(Result.Nodes[SrcIdx].Dependencies, N + 1);
    Result.Nodes[SrcIdx].Dependencies[N] := DstRel;

    N := Length(Result.Nodes[DstIdx].Referencers);
    SetLength(Result.Nodes[DstIdx].Referencers, N + 1);
    Result.Nodes[DstIdx].Referencers[N] := SrcRel;
  end;

  procedure SuggestBrokenRepair(const AOwnerIdx: Integer;
    const ABrokenRawUrl: String; const AWasCastleDataUrl: Boolean);
  var
    WantedNameLow, WantedStemLow, OwnerDirRel: String;
    WantedCat: TAssetCategory;
    BestIdx, BestScore, Score, J, RIdx: Integer;
  begin
    WantedNameLow := LowerCase(ExtractFileName(StringReplace(ABrokenRawUrl, '\', '/', [rfReplaceAll])));
    WantedStemLow := LowerCase(ChangeFileExt(WantedNameLow, ''));
    WantedCat := ClassifyAssetExtension(WantedNameLow);
    if WantedNameLow = '' then
      Exit;

    BestIdx := -1;
    BestScore := 0;
    for J := 0 to High(Result.Nodes) do
      if J <> AOwnerIdx then
      begin
        Score := 0;
        if Result.Nodes[J].FileNameLower = WantedNameLow then
          Score := 100
        else if (Result.Nodes[J].Category = WantedCat) and
                (WantedStemLow <> '') and
                ((Pos(WantedStemLow, Result.Nodes[J].StemLower) > 0) or
                 (Pos(Result.Nodes[J].StemLower, WantedStemLow) > 0)) then
          Score := 60;

        if Score > BestScore then
        begin
          BestScore := Score;
          BestIdx := J;
        end;
      end;

    if BestIdx >= 0 then
    begin
      RIdx := Length(Result.Repairs);
      SetLength(Result.Repairs, RIdx + 1);
      Result.Repairs[RIdx] := Default(TBrokenUrlRepairAction);
      Result.Repairs[RIdx].OwnerAssetRelPath := Result.Nodes[AOwnerIdx].DataRelPath;
      Result.Repairs[RIdx].BrokenUrl := ABrokenRawUrl;
      if AWasCastleDataUrl then
        Result.Repairs[RIdx].SuggestedUrl := Result.Nodes[BestIdx].CastleDataUrl
      else
      begin
        OwnerDirRel := RelDirOf(Result.Nodes[AOwnerIdx].DataRelPath);
        if OwnerDirRel = '' then
          Result.Repairs[RIdx].SuggestedUrl := Result.Nodes[BestIdx].DataRelPath
        else
          Result.Repairs[RIdx].SuggestedUrl := Result.Nodes[BestIdx].CastleDataUrl;
      end;
      if BestScore >= 100 then
        Result.Repairs[RIdx].MatchReason := 'Exact filename match in moved subfolder'
      else
        Result.Repairs[RIdx].MatchReason := 'Fuzzy stem + asset category match';
    end;
  end;

var
  I, R, TargetIdx, BIdx: Integer;
  ExtLow, Content, RawRef, ResolvedRel, OwnerDir: String;
  Refs: TStringArray;
  IsCastleUrl: Boolean;
begin
  Result := Default(TAssetGraphReport);
  CleanRoot := ExcludeTrailingPathDelimiter(ADataDirPath);
  Result.DataDirPath := CleanRoot;
  if (CleanRoot = '') or (not DirectoryExists(CleanRoot)) then
    Exit;

  WalkDir(CleanRoot, '');

  { Parse outgoing references }
  for I := 0 to High(Result.Nodes) do
  begin
    ExtLow := LowerCase(ExtractFileExt(Result.Nodes[I].DataRelPath));
    if not IsScannableReferencerAsset(ExtLow) then
      Continue;
    if Result.Nodes[I].SizeBytes > 16 * 1024 * 1024 then
      Continue;

    Content := ReadFileAsStringSafe(Result.Nodes[I].FullDiskPath);
    ExtractAssetReferencesFromText(Content, ExtLow, Refs);
    OwnerDir := RelDirOf(Result.Nodes[I].DataRelPath);

    for R := 0 to High(Refs) do
    begin
      RawRef := Refs[R];
      IsCastleUrl := StartsText('castle-data:/', RawRef);
      if IsCastleUrl then
        ResolvedRel := NormalizeSlashPath(Copy(RawRef, Length('castle-data:/') + 1, MaxInt))
      else if OwnerDir <> '' then
        ResolvedRel := NormalizeSlashPath(OwnerDir + '/' + RawRef)
      else
        ResolvedRel := NormalizeSlashPath(RawRef);

      TargetIdx := FindNodeIndex(Result, ResolvedRel);
      if TargetIdx >= 0 then
        AddDepEdge(I, TargetIdx)
      else if IsCastleUrl or (ExtLow = '.gltf') or (ExtLow = '.castle-sprite-sheet') then
      begin
        BIdx := Length(Result.Nodes[I].BrokenUrls);
        SetLength(Result.Nodes[I].BrokenUrls, BIdx + 1);
        Result.Nodes[I].BrokenUrls[BIdx] := RawRef;
        Inc(Result.BrokenUrlCount);
        SuggestBrokenRepair(I, RawRef, IsCastleUrl);
      end;
    end;
  end;

  { Compute orphan flags }
  for I := 0 to High(Result.Nodes) do
  begin
    Result.Nodes[I].IsOrphan :=
      (not Result.Nodes[I].IsRootEntry) and
      (Length(Result.Nodes[I].Referencers) = 0);
    if Result.Nodes[I].IsOrphan then
    begin
      Inc(Result.OrphanCount);
      Inc(Result.OrphanBytes, Result.Nodes[I].SizeBytes);
    end;
  end;
end;

class function TAssetDependencyAnalyzer.RepairBrokenUrls(
  const ADataDirPath: String;
  const ARepairs: array of TBrokenUrlRepairAction): Integer;
var
  CleanRoot, DiskPath, Content, Updated: String;
  I: Integer;
begin
  Result := 0;
  CleanRoot := ExcludeTrailingPathDelimiter(ADataDirPath);
  if (CleanRoot = '') or (not DirectoryExists(CleanRoot)) then
    Exit;

  for I := 0 to High(ARepairs) do
  begin
    if (ARepairs[I].BrokenUrl = '') or (ARepairs[I].SuggestedUrl = '') or
       (ARepairs[I].BrokenUrl = ARepairs[I].SuggestedUrl) then
      Continue;
    DiskPath := IncludeTrailingPathDelimiter(CleanRoot) +
      StringReplace(ARepairs[I].OwnerAssetRelPath, '/', PathDelim, [rfReplaceAll]);
    if not FileExists(DiskPath) then
      Continue;
    Content := ReadFileAsStringSafe(DiskPath);
    if Pos(ARepairs[I].BrokenUrl, Content) > 0 then
    begin
      Updated := StringReplace(Content, ARepairs[I].BrokenUrl,
        ARepairs[I].SuggestedUrl, [rfReplaceAll]);
      if Updated <> Content then
      begin
        WriteStringToFileSafe(DiskPath, Updated);
        Inc(Result);
      end;
    end;
  end;
end;

class function TAssetDependencyAnalyzer.SweepOrphanAssetsToTrash(
  const ADataDirPath: String; const AOrphanRelPaths: array of String;
  out OutTrashDir: String): Integer;
var
  CleanData, ParentDir, SrcFile, DstFile, RelNative: String;
  I: Integer;
begin
  Result := 0;
  CleanData := ExcludeTrailingPathDelimiter(ADataDirPath);
  ParentDir := ExtractFileDir(CleanData);
  if ParentDir = '' then
    ParentDir := CleanData;
  OutTrashDir := IncludeTrailingPathDelimiter(ParentDir) + '.castle-orphan-trash';

  for I := 0 to High(AOrphanRelPaths) do
  begin
    RelNative := StringReplace(NormalizeSlashPath(AOrphanRelPaths[I]),
      '/', PathDelim, [rfReplaceAll]);
    if RelNative = '' then
      Continue;
    SrcFile := IncludeTrailingPathDelimiter(CleanData) + RelNative;
    if not FileExists(SrcFile) then
      Continue;
    DstFile := IncludeTrailingPathDelimiter(OutTrashDir) + RelNative;
    ForceDirectories(ExtractFileDir(DstFile));
    if FileExists(DstFile) then
      SysUtils.DeleteFile(DstFile);
    if RenameFile(SrcFile, DstFile) then
      Inc(Result);
  end;
end;

class function TAssetDependencyAnalyzer.FormatAssetGraphMarkdown(
  const AReport: TAssetGraphReport): String;
var
  SB: TStringBuilder;
  I, D: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Castle Asset Reference Graph & Health Audit');
    SB.AppendLine;
    SB.AppendLine(Format('- **Indexed Assets**: `%d` (`%s`)',
      [AReport.TotalAssets, FormatByteSizeShort(AReport.TotalBytes)]));
    SB.AppendLine(Format('- **Unreferenced Orphan Assets**: `%d` (`%s` reclaimable)',
      [AReport.OrphanCount, FormatByteSizeShort(AReport.OrphanBytes)]));
    SB.AppendLine(Format('- **Broken Asset URLs**: `%d` (`%d` auto-repairable)',
      [AReport.BrokenUrlCount, Length(AReport.Repairs)]));
    SB.AppendLine;

    SB.AppendLine('## Mermaid Dependency Graph');
    SB.AppendLine;
    SB.AppendLine('```mermaid');
    SB.AppendLine('flowchart LR');
    for I := 0 to High(AReport.Nodes) do
      for D := 0 to High(AReport.Nodes[I].Dependencies) do
        SB.AppendLine(Format('  N%d["%s"] --> "%s"',
          [I, AReport.Nodes[I].DataRelPath, AReport.Nodes[I].Dependencies[D]]));
    SB.AppendLine('```');
    SB.AppendLine;

    if AReport.OrphanCount > 0 then
    begin
      SB.AppendLine('## Unreferenced Orphan Assets');
      SB.AppendLine;
      for I := 0 to High(AReport.Nodes) do
        if AReport.Nodes[I].IsOrphan then
          SB.AppendLine(Format('- `%s` (%s, `%s`)',
            [AReport.Nodes[I].DataRelPath,
             AssetCategoryToDisplayName(AReport.Nodes[I].Category),
             FormatByteSizeShort(AReport.Nodes[I].SizeBytes)]));
      SB.AppendLine;
    end;

    if Length(AReport.Repairs) > 0 then
    begin
      SB.AppendLine('## Proposed Broken-URL Auto-Repairs');
      SB.AppendLine;
      for I := 0 to High(AReport.Repairs) do
        SB.AppendLine(Format('- **`%s`**: `%s` -> `%s` (%s)',
          [AReport.Repairs[I].OwnerAssetRelPath,
           AReport.Repairs[I].BrokenUrl,
           AReport.Repairs[I].SuggestedUrl,
           AReport.Repairs[I].MatchReason]));
    end;

    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
