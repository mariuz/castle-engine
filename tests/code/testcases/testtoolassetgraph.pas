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

{ Automated tests for @link(TAssetDependencyAnalyzer) bidirectional reference
  indexing, @code(.gltf) relative URI chaining, orphan asset sweeping, and
  broken @code(castle-data:/) URL auto-repair
  (Phase 292 — UE 5.9 / 6.0 Reference Viewer Parity). }
unit TestToolAssetGraph;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils,
  CastleTester;

type
  TTestToolAssetGraph = class(TCastleTestCase)
  published
    procedure TestBidirectionalGraphGltfChainAndOrphanDetection;
    procedure TestBrokenUrlFuzzyRepairAndSafeOrphanTrashSweep;
  end;

implementation

uses
  ToolAssetGraph;

procedure WriteMockAssetFile(const AFullPath, AContent: String);
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

procedure DeleteDirectoryRecursiveSafe(const ADir: String);
var
  SR: TSearchRec;
  Child: String;
begin
  if (ADir = '') or (not DirectoryExists(ADir)) then
    Exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      Child := IncludeTrailingPathDelimiter(ADir) + SR.Name;
      if (SR.Attr and faDirectory) <> 0 then
        DeleteDirectoryRecursiveSafe(Child)
      else
        SysUtils.DeleteFile(Child);
    until FindNext(SR) <> 0;
  finally
    SysUtils.FindClose(SR);
  end;
  RemoveDir(ADir);
end;

procedure TTestToolAssetGraph.TestBidirectionalGraphGltfChainAndOrphanDetection;
var
  BaseDir, DataDir, Md: String;
  Rep: TAssetGraphReport;
  LevelIdx, PrefabIdx, GltfIdx, FlameTexIdx, OrphanTexIdx: Integer;
begin
  BaseDir := IncludeTrailingPathDelimiter(GetTempDir(false)) +
    'cge_test_asset_graph_1_' + IntToStr(GetProcessID);
  DataDir := IncludeTrailingPathDelimiter(BaseDir) + 'data';
  DeleteDirectoryRecursiveSafe(BaseDir);
  try
    WriteMockAssetFile(DataDir + PathDelim + 'CastleSettings.xml',
      '<?xml version="1.0"?><castle_settings/>');

    WriteMockAssetFile(
      DataDir + PathDelim + 'designs' + PathDelim + 'level1.castle-user-interface',
      '{"$ClassName":"TCastleUserInterface","Url":"castle-data:/designs/torch_prefab.castle-transform","Bgm":"castle-data:/audio/theme.ogg"}');

    WriteMockAssetFile(
      DataDir + PathDelim + 'designs' + PathDelim + 'torch_prefab.castle-transform',
      '{"$ClassName":"TCastleScene","Url":"castle-data:/models/torch.gltf"}');

    WriteMockAssetFile(
      DataDir + PathDelim + 'models' + PathDelim + 'torch.gltf',
      '{"asset":{"version":"2.0"},"images":[{"uri":"../textures/flame_albedo.png"}]}');

    WriteMockAssetFile(
      DataDir + PathDelim + 'textures' + PathDelim + 'flame_albedo.png',
      'PNG_FLAME_DATA_1234567890');

    WriteMockAssetFile(
      DataDir + PathDelim + 'audio' + PathDelim + 'theme.ogg',
      'OGG_AUDIO_STREAM_DATA');

    WriteMockAssetFile(
      DataDir + PathDelim + 'textures' + PathDelim + 'unused_old_wall.png',
      'ORPHAN_TEXTURE_PAYLOAD_BYTES_0123456789');

    Rep := TAssetDependencyAnalyzer.AnalyzeDataDirectory(DataDir);
    AssertEquals(7, Rep.TotalAssets);
    AssertEquals(0, Rep.BrokenUrlCount);
    AssertEquals(1, Rep.OrphanCount);

    LevelIdx := TAssetDependencyAnalyzer.FindNodeIndex(Rep, 'designs/level1.castle-user-interface');
    PrefabIdx := TAssetDependencyAnalyzer.FindNodeIndex(Rep, 'designs/torch_prefab.castle-transform');
    GltfIdx := TAssetDependencyAnalyzer.FindNodeIndex(Rep, 'models/torch.gltf');
    FlameTexIdx := TAssetDependencyAnalyzer.FindNodeIndex(Rep, 'textures/flame_albedo.png');
    OrphanTexIdx := TAssetDependencyAnalyzer.FindNodeIndex(Rep, 'textures/unused_old_wall.png');

    AssertTrue(LevelIdx >= 0);
    AssertTrue(PrefabIdx >= 0);
    AssertTrue(GltfIdx >= 0);
    AssertTrue(FlameTexIdx >= 0);
    AssertTrue(OrphanTexIdx >= 0);

    { Bidirectional edges verified across UI -> Prefab -> glTF -> Texture }
    AssertTrue(Rep.Nodes[LevelIdx].IsRootEntry);
    AssertFalse(Rep.Nodes[LevelIdx].IsOrphan);
    AssertEquals(2, Length(Rep.Nodes[LevelIdx].Dependencies));

    AssertEquals(1, Length(Rep.Nodes[PrefabIdx].Referencers));
    AssertEquals('designs/level1.castle-user-interface', Rep.Nodes[PrefabIdx].Referencers[0]);
    AssertEquals(1, Length(Rep.Nodes[PrefabIdx].Dependencies));
    AssertEquals('models/torch.gltf', Rep.Nodes[PrefabIdx].Dependencies[0]);

    AssertEquals(1, Length(Rep.Nodes[GltfIdx].Referencers));
    AssertEquals('designs/torch_prefab.castle-transform', Rep.Nodes[GltfIdx].Referencers[0]);
    AssertEquals(1, Length(Rep.Nodes[GltfIdx].Dependencies));
    AssertEquals('textures/flame_albedo.png', Rep.Nodes[GltfIdx].Dependencies[0]);

    AssertEquals(1, Length(Rep.Nodes[FlameTexIdx].Referencers));
    AssertFalse(Rep.Nodes[FlameTexIdx].IsOrphan);

    AssertTrue(Rep.Nodes[OrphanTexIdx].IsOrphan);
    AssertEquals(Rep.Nodes[OrphanTexIdx].SizeBytes, Rep.OrphanBytes);

    Md := TAssetDependencyAnalyzer.FormatAssetGraphMarkdown(Rep);
    AssertTrue(Pos('flowchart LR', Md) > 0);
    AssertTrue(Pos('unused_old_wall.png', Md) > 0);
  finally
    DeleteDirectoryRecursiveSafe(BaseDir);
  end;
end;

procedure TTestToolAssetGraph.TestBrokenUrlFuzzyRepairAndSafeOrphanTrashSweep;
var
  BaseDir, DataDir, TrashDir: String;
  Rep: TAssetGraphReport;
  FixedCount, SweptCount, HeroTexIdx: Integer;
begin
  BaseDir := IncludeTrailingPathDelimiter(GetTempDir(false)) +
    'cge_test_asset_graph_2_' + IntToStr(GetProcessID);
  DataDir := IncludeTrailingPathDelimiter(BaseDir) + 'data';
  DeleteDirectoryRecursiveSafe(BaseDir);
  try
    { Design points to old texture folder; actual texture moved to textures/characters/ }
    WriteMockAssetFile(
      DataDir + PathDelim + 'designs' + PathDelim + 'hud.castle-user-interface',
      '{"$ClassName":"TCastleImageControl","Url":"castle-data:/legacy_ui/hero_portrait.png"}');

    WriteMockAssetFile(
      DataDir + PathDelim + 'textures' + PathDelim + 'characters' + PathDelim + 'hero_portrait.png',
      'HERO_PORTRAIT_PNG_BYTES');

    WriteMockAssetFile(
      DataDir + PathDelim + 'audio' + PathDelim + 'scratch_unused.wav',
      'UNUSED_WAV_ORPHAN_BYTES');

    Rep := TAssetDependencyAnalyzer.AnalyzeDataDirectory(DataDir);
    AssertEquals(1, Rep.BrokenUrlCount);
    AssertEquals(1, Length(Rep.Repairs));
    AssertEquals('castle-data:/textures/characters/hero_portrait.png',
      Rep.Repairs[0].SuggestedUrl);

    { 1. Auto-repair broken URL on disk and verify broken count drops to 0 }
    FixedCount := TAssetDependencyAnalyzer.RepairBrokenUrls(DataDir, Rep.Repairs);
    AssertEquals(1, FixedCount);

    Rep := TAssetDependencyAnalyzer.AnalyzeDataDirectory(DataDir);
    AssertEquals(0, Rep.BrokenUrlCount);
    HeroTexIdx := TAssetDependencyAnalyzer.FindNodeIndex(
      Rep, 'textures/characters/hero_portrait.png');
    AssertTrue(HeroTexIdx >= 0);
    AssertFalse(Rep.Nodes[HeroTexIdx].IsOrphan);
    AssertEquals(1, Rep.OrphanCount); // only audio/scratch_unused.wav remains orphan!

    { 2. Quarantine remaining orphan into .castle-orphan-trash }
    SweptCount := TAssetDependencyAnalyzer.SweepOrphanAssetsToTrash(
      DataDir, ['audio/scratch_unused.wav'], TrashDir);
    AssertEquals(1, SweptCount);
    AssertTrue(FileExists(IncludeTrailingPathDelimiter(TrashDir) +
      'audio' + PathDelim + 'scratch_unused.wav'));

    Rep := TAssetDependencyAnalyzer.AnalyzeDataDirectory(DataDir);
    AssertEquals(0, Rep.OrphanCount);
  finally
    DeleteDirectoryRecursiveSafe(BaseDir);
  end;
end;

initialization
  RegisterTest(TTestToolAssetGraph);
end.
