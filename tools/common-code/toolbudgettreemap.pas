{
  Copyright 2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Bruls-Huizing-van Wijk squarified scene memory/triangle budget treemap
  analyzer, outlier remediation auditor, and 116-Studio Hub / 21st MCP tool
  backing engine (Phase 396). }
unit ToolBudgetTreemap;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleUIControls;

type
  { Single squarified treemap rectangle cell representing a scene component's
    memory & geometry footprint. }
  TBudgetTreemapCell = record
    ComponentName: String;
    ComponentClassName: String;
    EstimatedMemoryKB: Single;
    EstimatedTriangles: Integer;
    BudgetShare01: Single;
    RectX: Single;
    RectY: Single;
    RectW: Single;
    RectH: Single;
    AspectRatio: Single;
    IsOverNodeCap: Boolean;
    RemediationHint: String;
  end;

  { Holistic scene memory/triangle budget & squarified treemap report. }
  TSceneBudgetTreemapReport = record
    TotalComponents: Integer;
    TotalEstimatedMemoryKB: Single;
    TotalEstimatedTriangles: Integer;
    SceneBudgetLimitKB: Single;
    PerNodeCapKB: Single;
    CanvasWidth: Single;
    CanvasHeight: Single;
    UtilizationRatio01: Single;
    OverBudgetNodeCount: Integer;
    WorstCellAspectRatio: Single;
    Cells: array of TBudgetTreemapCell;
  end;

  { Squarified Treemap & Scene Asset Budget Analyzer (Phase 396). }
  TSceneBudgetTreemapAnalyzer = class
  private
    FLastReport: TSceneBudgetTreemapReport;
    FSceneBudgetLimitKB: Single;
    FPerNodeCapKB: Single;
  public
    constructor Create;
    class function SharedAnalyzer: TSceneBudgetTreemapAnalyzer;

    { Audit ADesignRoot, estimate per-node VRAM/geometry weight, flag outliers
      above APerNodeCapKB, and partition [0..ACanvasW] x [0..ACanvasH] via the
      Bruls-Huizing-van Wijk squarified treemap algorithm. }
    function AnalyzeSceneTreemap(const ADesignRoot: TComponent;
      const ASceneBudgetLimitKB: Single = 8192.0;
      const APerNodeCapKB: Single = 2048.0;
      const ACanvasW: Single = 640.0;
      const ACanvasH: Single = 360.0): TSceneBudgetTreemapReport;

    { Populate a synthetic multi-scale scene hierarchy with an over-budget
      4200 KB Boss statue + balanced environment props for live testing. }
    class function SpawnSyntheticHeavySceneDemo(
      const ARoot, AOwner: TComponent): Boolean;

    class function GenerateMarkdownReport(
      const AReport: TSceneBudgetTreemapReport): String;

    property LastReport: TSceneBudgetTreemapReport read FLastReport;
    property SceneBudgetLimitKB: Single
      read FSceneBudgetLimitKB write FSceneBudgetLimitKB;
    property PerNodeCapKB: Single read FPerNodeCapKB write FPerNodeCapKB;
  end;

implementation

uses
  CastleUtils, CastleTerrain, ToolStudioHub;

var
  GSharedBudgetAnalyzer: TSceneBudgetTreemapAnalyzer = nil;

function FindViewportInTree(const ARoot: TComponent): TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleViewport then Exit(TCastleViewport(ARoot));
  for I := 0 to ARoot.ComponentCount - 1 do
  begin
    Result := FindViewportInTree(ARoot.Components[I]);
    if Result <> nil then Exit;
  end;
end;

procedure EstimateComponentFootprint(const C: TComponent;
  out AMemKB: Single; out ATris: Integer; out AHint: String);
var
  Scn: TCastleScene;
  Box: TCastleBox;
  VolEst: Single;
begin
  AMemKB := 16.0;
  ATris := 0;
  AHint := 'Within node budget.';

  { Tag > 0 on synthetic/annotated components provides explicit KB weight }
  if C.Tag > 0 then
  begin
    AMemKB := C.Tag;
    ATris := C.Tag * 18;
  end else
  if C is TCastleBox then
  begin
    Box := TCastleBox(C);
    VolEst := Max(0.1, Box.Size.X * Box.Size.Y * Box.Size.Z);
    AMemKB := 24.0 + Sqrt(VolEst) * 8.0;
    ATris := 12;
  end else
  if C is TCastleScene then
  begin
    Scn := TCastleScene(C);
    ATris := Max(24, Scn.TrianglesCount);
    AMemKB := Max(64.0, (Scn.VerticesCount * 48.0 + ATris * 12.0) / 1024.0);
    if Scn.Url <> '' then
      AMemKB := AMemKB + 256.0;
  end else
  if C is TCastleTerrain then
  begin
    AMemKB := 1536.0;
    ATris := 32768;
  end else
  if C is TCastleTransform then
  begin
    AMemKB := 32.0;
    ATris := 16;
  end else
  if C is TCastleUserInterface then
  begin
    AMemKB := 20.0;
    ATris := 2;
  end;
end;

{ Bruls-Huizing-van Wijk Squarified Treemap Layout --------------------------- }

procedure SquarifyCells(var ACells: array of TBudgetTreemapCell;
  const ACanvasW, ACanvasH: Single);
var
  Areas: array of Single;
  N, StartIdx, EndIdx, NextIdx, I: Integer;
  RX, RY, RW, RH, TotalWeight, TotalCanvasArea: Single;

  function WorstAspect(const FirstIdx, LastIdx: Integer;
    const ShorterSide: Single): Single;
  var
    K: Integer;
    SumA, MinA, MaxA, S2, Sum2, R1, R2: Single;
  begin
    if (ShorterSide <= 1e-5) or (FirstIdx > LastIdx) then
      Exit(1e9);
    SumA := 0.0;
    MinA := Areas[FirstIdx];
    MaxA := Areas[FirstIdx];
    for K := FirstIdx to LastIdx do
    begin
      SumA := SumA + Areas[K];
      if Areas[K] < MinA then MinA := Areas[K];
      if Areas[K] > MaxA then MaxA := Areas[K];
    end;
    if (SumA <= 1e-6) or (MinA <= 1e-6) then
      Exit(1e9);
    S2 := ShorterSide * ShorterSide;
    Sum2 := SumA * SumA;
    R1 := (S2 * MaxA) / Sum2;
    R2 := Sum2 / (S2 * MinA);
    Result := Max(R1, R2);
  end;

  procedure CommitStrip(const FirstIdx, LastIdx: Integer);
  var
    K: Integer;
    SumA, StripThickness, Cursor, ItemSpan: Single;
    HorizontalStrip: Boolean;
  begin
    SumA := 0.0;
    for K := FirstIdx to LastIdx do
      SumA := SumA + Areas[K];

    { Lay strip along the shorter dimension of remaining (RW, RH) }
    HorizontalStrip := RW < RH;
    if HorizontalStrip then
    begin
      { Strip spans full width RW, thickness = SumA / RW along Y }
      StripThickness := SumA / Max(1e-4, RW);
      Cursor := RX;
      for K := FirstIdx to LastIdx do
      begin
        if K = LastIdx then
          ItemSpan := Max(0.0, (RX + RW) - Cursor)
        else
          ItemSpan := Areas[K] / Max(1e-4, StripThickness);
        ACells[K].RectX := Cursor;
        ACells[K].RectY := RY;
        ACells[K].RectW := ItemSpan;
        ACells[K].RectH := StripThickness;
        Cursor := Cursor + ItemSpan;
      end;
      RY := RY + StripThickness;
      RH := Max(0.0, RH - StripThickness);
    end else
    begin
      { Strip spans full height RH, thickness = SumA / RH along X }
      StripThickness := SumA / Max(1e-4, RH);
      Cursor := RY;
      for K := FirstIdx to LastIdx do
      begin
        if K = LastIdx then
          ItemSpan := Max(0.0, (RY + RH) - Cursor)
        else
          ItemSpan := Areas[K] / Max(1e-4, StripThickness);
        ACells[K].RectX := RX;
        ACells[K].RectY := Cursor;
        ACells[K].RectW := StripThickness;
        ACells[K].RectH := ItemSpan;
        Cursor := Cursor + ItemSpan;
      end;
      RX := RX + StripThickness;
      RW := Max(0.0, RW - StripThickness);
    end;
  end;

var
  ShortSide, CurWorst, NextWorst: Single;
begin
  N := Length(ACells);
  if N = 0 then Exit;

  TotalCanvasArea := Max(1.0, ACanvasW) * Max(1.0, ACanvasH);
  TotalWeight := 0.0;
  for I := 0 to N - 1 do
    TotalWeight := TotalWeight + Max(0.01, ACells[I].EstimatedMemoryKB);

  SetLength(Areas, N);
  for I := 0 to N - 1 do
    Areas[I] := (Max(0.01, ACells[I].EstimatedMemoryKB) / TotalWeight) * TotalCanvasArea;

  RX := 0.0;
  RY := 0.0;
  RW := Max(1.0, ACanvasW);
  RH := Max(1.0, ACanvasH);

  StartIdx := 0;
  while StartIdx < N do
  begin
    EndIdx := StartIdx;
    ShortSide := Min(Max(1e-3, RW), Max(1e-3, RH));
    CurWorst := WorstAspect(StartIdx, EndIdx, ShortSide);
    while EndIdx + 1 < N do
    begin
      NextIdx := EndIdx + 1;
      NextWorst := WorstAspect(StartIdx, NextIdx, ShortSide);
      if NextWorst <= CurWorst then
      begin
        EndIdx := NextIdx;
        CurWorst := NextWorst;
      end else
        Break;
    end;
    CommitStrip(StartIdx, EndIdx);
    StartIdx := EndIdx + 1;
  end;

  for I := 0 to N - 1 do
  begin
    if (ACells[I].RectW > 1e-4) and (ACells[I].RectH > 1e-4) then
      ACells[I].AspectRatio := Max(
        ACells[I].RectW / ACells[I].RectH,
        ACells[I].RectH / ACells[I].RectW)
    else
      ACells[I].AspectRatio := 1.0;
  end;
end;

{ TSceneBudgetTreemapAnalyzer ------------------------------------------------ }

constructor TSceneBudgetTreemapAnalyzer.Create;
begin
  inherited Create;
  FSceneBudgetLimitKB := 8192.0;
  FPerNodeCapKB := 2048.0;
  FLastReport := Default(TSceneBudgetTreemapReport);
end;

class function TSceneBudgetTreemapAnalyzer.SharedAnalyzer: TSceneBudgetTreemapAnalyzer;
begin
  if GSharedBudgetAnalyzer = nil then
    GSharedBudgetAnalyzer := TSceneBudgetTreemapAnalyzer.Create;
  Result := GSharedBudgetAnalyzer;
end;

function TSceneBudgetTreemapAnalyzer.AnalyzeSceneTreemap(
  const ADesignRoot: TComponent;
  const ASceneBudgetLimitKB, APerNodeCapKB, ACanvasW, ACanvasH: Single): TSceneBudgetTreemapReport;
var
  Visited: Classes.TList;
  CellCount, I, J: Integer;
  SwapTmp: TBudgetTreemapCell;

  procedure AddNodeCell(const C: TComponent);
  var
    MemKB: Single;
    Tris, Idx: Integer;
    Hint: String;
  begin
    if (C = nil) or (Visited.IndexOf(C) >= 0) then Exit;
    if csTransient in C.ComponentStyle then Exit;
    Visited.Add(C);

    if (C = ADesignRoot) or (C is TCastleViewport) or
       (C is TCastleAbstractRootTransform) or (C is TCastleCamera) then
      Exit;

    if not ((C is TCastleTransform) or (C is TCastleUserInterface)) then
      Exit;

    EstimateComponentFootprint(C, MemKB, Tris, Hint);
    Idx := CellCount;
    Inc(CellCount);
    if Idx >= Length(Result.Cells) then
      SetLength(Result.Cells, Max(16, Length(Result.Cells) * 2));

    Result.Cells[Idx] := Default(TBudgetTreemapCell);
    if C.Name <> '' then
      Result.Cells[Idx].ComponentName := C.Name
    else
      Result.Cells[Idx].ComponentName := C.ClassName + '_' + IntToStr(Idx);
    Result.Cells[Idx].ComponentClassName := C.ClassName;
    Result.Cells[Idx].EstimatedMemoryKB := MemKB;
    Result.Cells[Idx].EstimatedTriangles := Tris;
    Result.Cells[Idx].IsOverNodeCap := MemKB > Result.PerNodeCapKB;
    if Result.Cells[Idx].IsOverNodeCap then
      Result.Cells[Idx].RemediationHint :=
        'Exceeds PerNodeCapKB: bake HLOD / Octahedral Impostor LOD or compress KTX2 textures.'
    else
      Result.Cells[Idx].RemediationHint := Hint;
  end;

  procedure WalkComponent(const C: TComponent);
  var
    K: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    AddNodeCell(C);
    if C is TCastleViewport then
      WalkComponent(TCastleViewport(C).Items);
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for K := 0 to T.Count - 1 do
        WalkComponent(T[K]);
    end;
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for K := 0 to UI.ControlsCount - 1 do
        WalkComponent(UI.Controls[K]);
    end;
    for K := 0 to C.ComponentCount - 1 do
      WalkComponent(C.Components[K]);
  end;

begin
  Result := Default(TSceneBudgetTreemapReport);
  FSceneBudgetLimitKB := Max(64.0, ASceneBudgetLimitKB);
  FPerNodeCapKB := Max(16.0, APerNodeCapKB);
  Result.SceneBudgetLimitKB := FSceneBudgetLimitKB;
  Result.PerNodeCapKB := FPerNodeCapKB;
  Result.CanvasWidth := Max(32.0, ACanvasW);
  Result.CanvasHeight := Max(32.0, ACanvasH);

  CellCount := 0;
  SetLength(Result.Cells, 16);
  Visited := Classes.TList.Create;
  try
    WalkComponent(ADesignRoot);
  finally
    FreeAndNil(Visited);
  end;
  SetLength(Result.Cells, CellCount);

  { Sort descending by EstimatedMemoryKB for optimal squarification }
  for I := 0 to CellCount - 2 do
    for J := I + 1 to CellCount - 1 do
      if Result.Cells[J].EstimatedMemoryKB > Result.Cells[I].EstimatedMemoryKB then
      begin
        SwapTmp := Result.Cells[I];
        Result.Cells[I] := Result.Cells[J];
        Result.Cells[J] := SwapTmp;
      end;

  Result.TotalComponents := CellCount;
  for I := 0 to CellCount - 1 do
  begin
    Result.TotalEstimatedMemoryKB := Result.TotalEstimatedMemoryKB +
      Result.Cells[I].EstimatedMemoryKB;
    Result.TotalEstimatedTriangles := Result.TotalEstimatedTriangles +
      Result.Cells[I].EstimatedTriangles;
    if Result.Cells[I].IsOverNodeCap then
      Inc(Result.OverBudgetNodeCount);
  end;

  if Result.TotalEstimatedMemoryKB > 1e-4 then
    for I := 0 to CellCount - 1 do
      Result.Cells[I].BudgetShare01 :=
        Result.Cells[I].EstimatedMemoryKB / Result.TotalEstimatedMemoryKB;

  Result.UtilizationRatio01 :=
    Result.TotalEstimatedMemoryKB / Result.SceneBudgetLimitKB;

  SquarifyCells(Result.Cells, Result.CanvasWidth, Result.CanvasHeight);

  Result.WorstCellAspectRatio := 1.0;
  for I := 0 to CellCount - 1 do
    if Result.Cells[I].AspectRatio > Result.WorstCellAspectRatio then
      Result.WorstCellAspectRatio := Result.Cells[I].AspectRatio;

  FLastReport := Result;
end;

class function TSceneBudgetTreemapAnalyzer.SpawnSyntheticHeavySceneDemo(
  const ARoot, AOwner: TComponent): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;

  procedure AddWeightedBox(const AName: String; const AKB: Integer;
    const ASize, APos: TVector3; const ACol: TVector4);
  var
    B: TCastleBox;
  begin
    B := TCastleBox.Create(Own);
    B.Name := AName;
    B.Tag := AKB;
    B.Size := ASize;
    B.Translation := APos;
    B.Color := ACol;
    VP.Items.Add(B);
  end;

begin
  Result := False;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  AddWeightedBox('BossTitanStatueUncompressed', 4200,
    Vector3(2.8, 5.2, 2.8), Vector3(0.0, 2.6, -6.0), Vector4(0.92, 0.34, 0.28, 1.0));
  AddWeightedBox('ValleyCliffMeshChunk', 1800,
    Vector3(8.0, 3.0, 4.0), Vector3(-6.0, 1.5, -10.0), Vector4(0.42, 0.68, 0.46, 1.0));
  AddWeightedBox('CathedralFacadeArch', 960,
    Vector3(5.0, 4.2, 1.5), Vector3(6.0, 2.1, -9.0), Vector4(0.48, 0.58, 0.82, 1.0));
  AddWeightedBox('MarketCrateCluster', 480,
    Vector3(2.0, 1.4, 2.0), Vector3(-3.0, 0.7, -4.0), Vector4(0.76, 0.60, 0.32, 1.0));
  AddWeightedBox('StreetLanternPost', 220,
    Vector3(0.5, 2.8, 0.5), Vector3(3.2, 1.4, -3.5), Vector4(0.88, 0.82, 0.38, 1.0));

  SharedAnalyzer.AnalyzeSceneTreemap(ARoot, 8192.0, 2048.0, 640.0, 360.0);
  Result := True;
end;

class function TSceneBudgetTreemapAnalyzer.GenerateMarkdownReport(
  const AReport: TSceneBudgetTreemapReport): String;
var
  SL: TStringList;
  I: Integer;
  C: TBudgetTreemapCell;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Squarified Scene Budget Treemap & 116-Studio Hub Report');
    SL.Add('');
    SL.Add(Format('- **Unified Studio Hub Catalog**: `%d` Studios (`21` MCP Tools)',
      [TStudioHubManager.StudioCount]));
    SL.Add(FormatDot('- **Scene Memory Utilization**: `%.1f KB / %.1f KB` (`%.1f%%`, `%d` over-cap outliers)',
      [AReport.TotalEstimatedMemoryKB, AReport.SceneBudgetLimitKB,
       AReport.UtilizationRatio01 * 100.0, AReport.OverBudgetNodeCount]));
    SL.Add(FormatDot('- **Estimated Triangles / Worst Treemap Aspect**: `%d` tris / `%.2f:1`',
      [AReport.TotalEstimatedTriangles, AReport.WorstCellAspectRatio]));
    SL.Add('');
    SL.Add('## Squarified Treemap Cells');
    for I := 0 to High(AReport.Cells) do
    begin
      C := AReport.Cells[I];
      SL.Add(FormatDot('- `%s` (`%s`): `%.1f KB` (`%.1f%%`), Rect `(%.1f, %.1f, %.1fx%.1f)` — %s',
        [C.ComponentName, C.ComponentClassName, C.EstimatedMemoryKB,
         C.BudgetShare01 * 100.0, C.RectX, C.RectY, C.RectW, C.RectH,
         C.RemediationHint]));
    end;
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

finalization
  FreeAndNil(GSharedBudgetAnalyzer);

end.
