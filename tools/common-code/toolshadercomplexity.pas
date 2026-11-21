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

{ 32x18 screen-tile viewport overdraw, stacked alpha-transparency hotspot,
  Early-Z vs. full-blend fragment shader ALU complexity auditor, and
  136-Studio Hub / 23rd MCP tool backing engine (Phase 416). }
unit ToolShaderComplexity;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson,
  CastleVectors, CastleBoxes, CastleTransform, CastleScene, CastleViewport;

const
  OverdrawGridCols = 32;
  OverdrawGridRows = 18;

type
  { Per-layer overdraw & shader ALU footprint summary. }
  TOverdrawContributor = record
    ComponentName: String;
    IsTranslucent: Boolean;
    EstimatedAluCost: Integer;
    CoveredTileCount: Integer;
    RemediationHint: String;
  end;

  { Holistic 32x18 screen-tile quad overdraw & shader ALU report. }
  TShaderComplexityReport = record
    AnalyzedLayerCount: Integer;
    OpaqueLayerCount: Integer;
    TranslucentLayerCount: Integer;
    MaxAllowedTranslucentOverdraw: Integer;
    PeakTranslucentOverdraw: Integer;
    PeakTileAluInstructions: Integer;
    AverageTileAluInstructions: Single;
    HotspotTileCount: Integer;
    TileTranslucentCounts: array[0..OverdrawGridRows - 1, 0..OverdrawGridCols - 1] of Integer;
    TileOpaqueCounts: array[0..OverdrawGridRows - 1, 0..OverdrawGridCols - 1] of Integer;
    TileAluCosts: array[0..OverdrawGridRows - 1, 0..OverdrawGridCols - 1] of Integer;
    Contributors: array of TOverdrawContributor;
  end;

  { Viewport Overdraw & Shader ALU Complexity Auditor (Phase 416). }
  TShaderComplexityAuditor = class
  private
    FLastReport: TShaderComplexityReport;
  public
    constructor Create;
    class function SharedAuditor: TShaderComplexityAuditor;

    { Project visible scene meshes onto a 32x18 screen-tile grid, accounting
      for Early-Z opaque occlusion vs. additive translucent alpha-blending
      fragment ALU stacking. }
    function AuditViewportOverdraw(const ADesignRoot: TComponent;
      const AMaxTranslucentLayers: Integer = 3;
      const AAluHotspotCap: Integer = 320): TShaderComplexityReport;

    { Populate a corridor scene with 2 flanking opaque walls and 6 stacked
      semi-transparent smoke/glass cards down the center sightline. }
    class function SpawnStackedSmokeOverdrawDemo(
      const ARoot, AOwner: TComponent): Boolean;

    class function GenerateMarkdownReport(
      const AReport: TShaderComplexityReport): String;

    property LastReport: TShaderComplexityReport read FLastReport;
  end;

implementation

uses
  CastleUtils, ToolStudioHub;

var
  GSharedShaderAuditor: TShaderComplexityAuditor = nil;

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

procedure ClassifyTransformShaderCost(const T: TCastleTransform;
  out AIsTranslucent: Boolean; out AAluCost: Integer;
  out AWorldCenter, AHalfExtents: TVector3);
var
  Box: TCastleBox;
  Sph: TCastleSphere;
  WT: TMatrix4;
begin
  if T.HasWorldTransform then WT := T.WorldTransform else WT := T.Transform;
  AWorldCenter := WT.MultPoint(TVector3.Zero);
  AHalfExtents := Vector3(1.0, 1.0, 0.5);
  AIsTranslucent := False;
  AAluCost := 48;

  if T is TCastleBox then
  begin
    Box := TCastleBox(T);
    AHalfExtents := Box.Size * 0.5;
    if Box.Color.W < 0.98 then
    begin
      AIsTranslucent := True;
      AAluCost := 96;
    end;
  end else
  if T is TCastleSphere then
  begin
    Sph := TCastleSphere(T);
    AHalfExtents := Vector3(Sph.Radius, Sph.Radius, Sph.Radius);
    if Sph.Color.W < 0.98 then
    begin
      AIsTranslucent := True;
      AAluCost := 96;
    end;
  end;

  if (Pos('Smoke', T.Name) > 0) or (Pos('Glass', T.Name) > 0) or
     (Pos('Particle', T.Name) > 0) or (Pos('Translucent', T.Name) > 0) then
  begin
    AIsTranslucent := True;
    AAluCost := Max(AAluCost, 96);
  end;

  if T.Tag > 0 then
    AAluCost := T.Tag;
end;

constructor TShaderComplexityAuditor.Create;
begin
  inherited Create;
  FLastReport := Default(TShaderComplexityReport);
end;

class function TShaderComplexityAuditor.SharedAuditor: TShaderComplexityAuditor;
begin
  if GSharedShaderAuditor = nil then
    GSharedShaderAuditor := TShaderComplexityAuditor.Create;
  Result := GSharedShaderAuditor;
end;

function TShaderComplexityAuditor.AuditViewportOverdraw(
  const ADesignRoot: TComponent; const AMaxTranslucentLayers,
  AAluHotspotCap: Integer): TShaderComplexityReport;
const
  CamPos: TVector3 = (X: 0.0; Y: 2.0; Z: 14.0);
  TanHalfV = 0.57735027; { tan(30 deg) for 60 deg vertical FOV }
  TanHalfH = 1.02640048; { 16:9 horizontal half-tan }

  procedure ProjectTransformToTiles(const T: TCastleTransform);
  var
    IsTrans: Boolean;
    Alu, K, R, C, CMin, CMax, RMin, RMax, Covered, Idx: Integer;
    CenterW, HalfExt, Rel: TVector3;
    DepthZ, HalfNdcX, HalfNdcY, CenterNdcX, CenterNdcY: Single;
    U0, U1, V0, V1: Single;
  begin
    if (T = nil) or (csTransient in T.ComponentStyle) or (not T.Exists) then
      Exit;

    if (T is TCastleAbstractRootTransform) or
       (T is TCastleCamera) or (T is TCastleAbstractLight) then
    begin
      for K := 0 to T.Count - 1 do
        ProjectTransformToTiles(T[K]);
      Exit;
    end;

    ClassifyTransformShaderCost(T, IsTrans, Alu, CenterW, HalfExt);
    Rel := CenterW - CamPos;
    DepthZ := -Rel.Z;

    if DepthZ > 0.5 then
    begin
      CenterNdcX := Rel.X / (DepthZ * TanHalfH);
      CenterNdcY := Rel.Y / (DepthZ * TanHalfV);
      HalfNdcX := Max(0.03, HalfExt.X / (DepthZ * TanHalfH));
      HalfNdcY := Max(0.03, HalfExt.Y / (DepthZ * TanHalfV));

      U0 := (CenterNdcX - HalfNdcX) * 0.5 + 0.5;
      U1 := (CenterNdcX + HalfNdcX) * 0.5 + 0.5;
      V0 := (CenterNdcY - HalfNdcY) * 0.5 + 0.5;
      V1 := (CenterNdcY + HalfNdcY) * 0.5 + 0.5;

      if (U1 > 0.0) and (U0 < 1.0) and (V1 > 0.0) and (V0 < 1.0) then
      begin
        CMin := Clamped(Floor(U0 * OverdrawGridCols), 0, OverdrawGridCols - 1);
        CMax := Clamped(Ceil(U1 * OverdrawGridCols) - 1, 0, OverdrawGridCols - 1);
        RMin := Clamped(Floor(V0 * OverdrawGridRows), 0, OverdrawGridRows - 1);
        RMax := Clamped(Ceil(V1 * OverdrawGridRows) - 1, 0, OverdrawGridRows - 1);

        Covered := 0;
        for R := RMin to RMax do
          for C := CMin to CMax do
          begin
            Inc(Covered);
            if IsTrans then
            begin
              { Translucent layers bypass Early-Z and stack full fragment ALU! }
              Inc(Result.TileTranslucentCounts[R, C]);
              Inc(Result.TileAluCosts[R, C], Alu);
            end else
            begin
              { First opaque hit pays full PBR ALU; occluded opaque hits pay 8 Early-Z cycles }
              if Result.TileOpaqueCounts[R, C] = 0 then
                Inc(Result.TileAluCosts[R, C], Alu)
              else
                Inc(Result.TileAluCosts[R, C], 8);
              Inc(Result.TileOpaqueCounts[R, C]);
            end;
          end;

        Inc(Result.AnalyzedLayerCount);
        if IsTrans then
          Inc(Result.TranslucentLayerCount)
        else
          Inc(Result.OpaqueLayerCount);

        Idx := Length(Result.Contributors);
        SetLength(Result.Contributors, Idx + 1);
        Result.Contributors[Idx].ComponentName := T.Name;
        Result.Contributors[Idx].IsTranslucent := IsTrans;
        Result.Contributors[Idx].EstimatedAluCost := Alu;
        Result.Contributors[Idx].CoveredTileCount := Covered;
        if IsTrans then
          Result.Contributors[Idx].RemediationHint :=
            'Convert soft-alpha card to Tight Polygon Cutout / Alpha-Clip Early-Z.'
        else
          Result.Contributors[Idx].RemediationHint :=
            'Opaque Early-Z friendly.';
      end;
    end;

    for K := 0 to T.Count - 1 do
      ProjectTransformToTiles(T[K]);
  end;

var
  VP: TCastleViewport;
  I, R, C, TransCap, AluCap: Integer;
  SumAlu: Int64;
begin
  Result := Default(TShaderComplexityReport);
  TransCap := Max(1, AMaxTranslucentLayers);
  AluCap := Max(64, AAluHotspotCap);
  Result.MaxAllowedTranslucentOverdraw := TransCap;
  if ADesignRoot = nil then Exit;

  VP := FindViewportInTree(ADesignRoot);
  if (VP <> nil) and (VP.Items <> nil) then
    for I := 0 to VP.Items.Count - 1 do
      ProjectTransformToTiles(VP.Items[I])
  else
    for I := 0 to ADesignRoot.ComponentCount - 1 do
      if ADesignRoot.Components[I] is TCastleTransform then
        ProjectTransformToTiles(TCastleTransform(ADesignRoot.Components[I]));

  SumAlu := 0;
  for R := 0 to OverdrawGridRows - 1 do
    for C := 0 to OverdrawGridCols - 1 do
    begin
      SumAlu := SumAlu + Result.TileAluCosts[R, C];
      if Result.TileTranslucentCounts[R, C] > Result.PeakTranslucentOverdraw then
        Result.PeakTranslucentOverdraw := Result.TileTranslucentCounts[R, C];
      if Result.TileAluCosts[R, C] > Result.PeakTileAluInstructions then
        Result.PeakTileAluInstructions := Result.TileAluCosts[R, C];
      if (Result.TileTranslucentCounts[R, C] > TransCap) or
         (Result.TileAluCosts[R, C] > AluCap) then
        Inc(Result.HotspotTileCount);
    end;

  Result.AverageTileAluInstructions :=
    SumAlu / (OverdrawGridCols * OverdrawGridRows);
  FLastReport := Result;
end;

class function TShaderComplexityAuditor.SpawnStackedSmokeOverdrawDemo(
  const ARoot, AOwner: TComponent): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  LeftWall, RightWall, SmokeCard: TCastleBox;
  I: Integer;
begin
  Result := False;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  LeftWall := TCastleBox.Create(Own);
  LeftWall.Name := 'CorridorOpaqueWall_West';
  LeftWall.Size := Vector3(3.0, 5.0, 2.0);
  LeftWall.Translation := Vector3(-6.5, 2.0, 0.0);
  LeftWall.Color := Vector4(0.35, 0.38, 0.42, 1.0);
  VP.Items.Add(LeftWall);

  RightWall := TCastleBox.Create(Own);
  RightWall.Name := 'CorridorOpaqueWall_East';
  RightWall.Size := Vector3(3.0, 5.0, 2.0);
  RightWall.Translation := Vector3(6.5, 2.0, 0.0);
  RightWall.Color := Vector4(0.35, 0.38, 0.42, 1.0);
  VP.Items.Add(RightWall);

  { 6 stacked semi-transparent smoke cards overlapping center sightline! }
  for I := 0 to 5 do
  begin
    SmokeCard := TCastleBox.Create(Own);
    SmokeCard.Name := Format('SmokePlumeCard_%d', [I + 1]);
    SmokeCard.Size := Vector3(5.0, 4.5, 0.08);
    SmokeCard.Translation := Vector3(0.0, 2.0, -2.5 + I * 1.0);
    SmokeCard.Color := Vector4(0.75, 0.78, 0.82, 0.35);
    VP.Items.Add(SmokeCard);
  end;

  Result := True;
end;

class function TShaderComplexityAuditor.GenerateMarkdownReport(
  const AReport: TShaderComplexityReport): String;
var
  SL: TStringList;
  I: Integer;
  C: TOverdrawContributor;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Viewport Overdraw, Transparency Stacking & Shader ALU Report');
    SL.Add('');
    SL.Add(Format('- **Unified Studio Hub Catalog**: `%d` Studios (`23` MCP Tools)',
      [TStudioHubManager.StudioCount]));
    SL.Add(Format('- **Analyzed Layers**: `%d` (`%d` opaque Early-Z, `%d` translucent blended)',
      [AReport.AnalyzedLayerCount, AReport.OpaqueLayerCount,
       AReport.TranslucentLayerCount]));
    SL.Add(FormatDot('- **Peak Translucent Overdraw**: **`%dx`** (Cap `<= %dx`) | **Hotspot Tiles**: `%d / %d`',
      [AReport.PeakTranslucentOverdraw, AReport.MaxAllowedTranslucentOverdraw,
       AReport.HotspotTileCount, OverdrawGridCols * OverdrawGridRows]));
    SL.Add(FormatDot('- **Fragment Shader ALU**: Peak `%d` instr/px, Mean `%.1f` instr/px',
      [AReport.PeakTileAluInstructions, AReport.AverageTileAluInstructions]));
    SL.Add('');
    SL.Add('## Layer Contributors');
    for I := 0 to High(AReport.Contributors) do
    begin
      C := AReport.Contributors[I];
      SL.Add(Format('- `%s`: `%d` ALU, `%d` tiles — %s',
        [C.ComponentName, C.EstimatedAluCost, C.CoveredTileCount,
         C.RemediationHint]));
    end;
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

finalization
  FreeAndNil(GSharedShaderAuditor);

end.
