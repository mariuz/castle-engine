{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless scene helper, preset spawner, UV2 lightmap & AO auditor, and
  Markdown report generator for Static Lightmap & Ambient Occlusion Atlas Baker
  (Phase 399). }
unit ToolLightmassBaker;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  CastleUtils, CastleClassUtils, CastleVectors, CastleTransform, CastleViewport,
  CastleUIControls, CastleLightmassBaker;

type
  TLightmassSceneAudit = record
    BakerCount: Integer;
    UnbuiltVolumeCount: Integer;
    TotalCharts: Integer;
    TotalInteriorTexels: Integer;
    TotalDilatedTexels: Integer;
    AvgSkyAo01: Single;
    AvgIndirectLum: Single;
  end;

  TLightmassBakerHelper = class
  public
    class procedure CollectLightmassBakers(const ARoot: TComponent;
      const AList: TList); static;
    class function FindFirstLightmassBaker(const ARoot: TComponent): TCastleLightmassBaker; static;
    class function FindLightmassBakerByName(const ARoot, AOwner: TComponent;
      const AName: String): TCastleLightmassBaker; static;

    class function SpawnLightmassPresetInDesign(const ARoot, AOwner: TComponent;
      const APreset: TLightmassBakePreset;
      const APosition: TVector3): TCastleLightmassBaker; static;

    class function AuditLightmassInDesign(const ARoot: TComponent): TLightmassSceneAudit; static;
    class function GenerateMarkdownReport(const ARoot: TComponent;
      const ActiveBaker: TCastleLightmassBaker): String; static;
  end;

implementation

class procedure TLightmassBakerHelper.CollectLightmassBakers(
  const ARoot: TComponent; const AList: TList);

  procedure Traverse(const C: TComponent);
  var
    I: Integer;
    T: TCastleTransform;
    UI: TCastleUserInterface;
    CC: TCastleComponent;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleLightmassBaker) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleComponent then
    begin
      CC := TCastleComponent(C);
      for I := 0 to CC.NonVisualComponentsCount - 1 do
        Traverse(CC.NonVisualComponents[I]);
    end;
    if C is TCastleViewport then
      Traverse(TCastleViewport(C).Items);
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Traverse(UI.Controls[I]);
    end;
    if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Traverse(T[I]);
    end;
  end;

begin
  if (ARoot = nil) or (AList = nil) then Exit;
  Traverse(ARoot);
end;

class function TLightmassBakerHelper.FindFirstLightmassBaker(
  const ARoot: TComponent): TCastleLightmassBaker;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectLightmassBakers(ARoot, L);
    if L.Count > 0 then
      Result := TCastleLightmassBaker(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TLightmassBakerHelper.FindLightmassBakerByName(
  const ARoot, AOwner: TComponent; const AName: String): TCastleLightmassBaker;
var
  L: TList;
  I: Integer;
  C: TComponent;
begin
  if Trim(AName) = '' then
    Exit(FindFirstLightmassBaker(ARoot));

  Result := nil;
  if AOwner <> nil then
  begin
    C := AOwner.FindComponent(AName);
    if C is TCastleLightmassBaker then
      Exit(TCastleLightmassBaker(C));
  end;

  L := TList.Create;
  try
    CollectLightmassBakers(ARoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleLightmassBaker(L[I]).Name, AName) then
        Exit(TCastleLightmassBaker(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TLightmassBakerHelper.SpawnLightmassPresetInDesign(
  const ARoot, AOwner: TComponent;
  const APreset: TLightmassBakePreset;
  const APosition: TVector3): TCastleLightmassBaker;
var
  ParentItems: TCastleTransform;
  VP: TCastleViewport;
  I: Integer;
  BaseName: String;
begin
  Result := nil;
  if ARoot = nil then Exit;

  ParentItems := nil;
  if ARoot is TCastleViewport then
    ParentItems := TCastleViewport(ARoot).Items
  else if ARoot is TCastleTransform then
    ParentItems := TCastleTransform(ARoot)
  else if ARoot is TCastleUserInterface then
  begin
    for I := 0 to TCastleUserInterface(ARoot).ControlsCount - 1 do
      if TCastleUserInterface(ARoot).Controls[I] is TCastleViewport then
      begin
        VP := TCastleViewport(TCastleUserInterface(ARoot).Controls[I]);
        ParentItems := VP.Items;
        Break;
      end;
  end;
  if ParentItems = nil then Exit;

  Result := TCastleLightmassBaker.Create(AOwner);
  case APreset of
    lbpCornellColorBleedRoom:  BaseName := 'Lightmass_CornellRoom';
    lbpArchwaySunbeamCloister: BaseName := 'Lightmass_SunbeamCloister';
    lbpSubterraneanTorchCrypt: BaseName := 'Lightmass_TorchCrypt';
  end;
  if AOwner <> nil then
    Result.Name := ProposeComponentName(TCastleLightmassBaker, AOwner, BaseName)
  else
    Result.Name := BaseName;
  Result.Preset := APreset;
  Result.Translation := APosition;
  ParentItems.Add(Result);
end;

class function TLightmassBakerHelper.AuditLightmassInDesign(
  const ARoot: TComponent): TLightmassSceneAudit;
var
  L: TList;
  I: Integer;
  B: TCastleLightmassBaker;
begin
  Result := Default(TLightmassSceneAudit);
  L := TList.Create;
  try
    CollectLightmassBakers(ARoot, L);
    Result.BakerCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      B := TCastleLightmassBaker(L[I]);
      if B.LightingNeedsRebuild then
        Inc(Result.UnbuiltVolumeCount);
      Inc(Result.TotalCharts, B.ChartCount);
      Inc(Result.TotalInteriorTexels, B.ValidInteriorTexelCount);
      Inc(Result.TotalDilatedTexels, B.DilatedBorderTexelCount);
      Result.AvgSkyAo01 := Result.AvgSkyAo01 + B.AverageSkyAo01;
      Result.AvgIndirectLum := Result.AvgIndirectLum + B.AverageIndirectLuminance;
    end;
    if L.Count > 0 then
    begin
      Result.AvgSkyAo01 := Result.AvgSkyAo01 / L.Count;
      Result.AvgIndirectLum := Result.AvgIndirectLum / L.Count;
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TLightmassBakerHelper.GenerateMarkdownReport(
  const ARoot: TComponent; const ActiveBaker: TCastleLightmassBaker): String;
var
  Audit: TLightmassSceneAudit;
  SB: TStringBuilder;
  I: Integer;
  Ch: TLightmassSurfaceChart;
  CenterTex: TLightmassTexel;
begin
  Audit := AuditLightmassInDesign(ARoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Static Lightmap & Ambient Occlusion Atlas Baker Report (Phase 399 — UE 5.5 GPU Lightmass Parity)');
    SB.AppendLine(Format('- **Scene Summary**: `%d` Lightmass Volumes (`%d` Unbuilt) | `%d` UV2 Charts | `%d` Interior Texels | `%d` Dilated Seam Texels',
      [Audit.BakerCount, Audit.UnbuiltVolumeCount, Audit.TotalCharts,
       Audit.TotalInteriorTexels, Audit.TotalDilatedTexels]));
    if ActiveBaker <> nil then
    begin
      SB.AppendLine(Format('- **Active Baker**: `%s` (`%s`, `%dx%d` Atlas, `%d` Bounces, Avg AO=`%.1f%%`, Avg GI=`%.3f`)',
        [ActiveBaker.Name,
         LightmassPresetDisplayName(ActiveBaker.Preset),
         ActiveBaker.AtlasResolution, ActiveBaker.AtlasResolution,
         ActiveBaker.IndirectBounces,
         ActiveBaker.AverageSkyAo01 * 100.0,
         ActiveBaker.AverageIndirectLuminance]));
      SB.AppendLine;
      SB.AppendLine('| UV2 Chart | Atlas Rect `(X,Y,W,H)` | Center Indirect GI `(R,G,B)` | Center Sky AO |');
      SB.AppendLine('| :--- | :--- | :--- | :--- |');
      for I := 0 to ActiveBaker.ChartCount - 1 do
      begin
        Ch := ActiveBaker.Charts[I];
        CenterTex := ActiveBaker.SampleChartTexelNearUV(I, 0.5, 0.5);
        SB.AppendLine(Format('| `%s` | `(%d, %d, %d, %d)` | `(%.3f, %.3f, %.3f)` | `%.2f` |',
          [Ch.ChartName, Ch.AtlasX, Ch.AtlasY, Ch.AtlasW, Ch.AtlasH,
           CenterTex.IndirectRGB.X, CenterTex.IndirectRGB.Y, CenterTex.IndirectRGB.Z,
           CenterTex.SkyAo01]));
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
