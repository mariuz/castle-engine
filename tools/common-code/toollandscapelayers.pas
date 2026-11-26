{
  Copyright 2026-2026 Michalis Kamburelis and Castle Game Engine developers.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Stateless scene authoring, non-destructive Landscape Edit Layer auditor, and
  terrain-carving spline earthwork report helper (@link(TLandscapeLayersHelper),
  @link(TLandscapeSceneAudit))
  (Phase 394 — UE 5.5 Landscape Edit Layers & ULandscapeSplinesComponent Parity + 37th MCP Tool). }
unit ToolLandscapeLayers;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes,
  CastleVectors, CastleTransform, CastleViewport,
  CastleLandscapeLayers;

type
  { Scene-wide Landscape Edit Layers & Splines audit summary. }
  TLandscapeSceneAudit = record
    LandscapeCount: Integer;
    TotalEditLayers: Integer;
    TotalSplines: Integer;
    TotalCutVolumeM3: Single;
    TotalFillVolumeM3: Single;
    TotalRoadAreaM2: Single;
    TotalRiverAreaM2: Single;
  end;

  { Scene spawner, layer visibility controller, and Markdown report builder. }
  TLandscapeLayersHelper = class
  public
    class function FindParentViewportItems(const ADesignRoot: TComponent): TCastleTransform; static;
    class procedure CollectLandscapes(const ADesignRoot: TComponent;
      const AList: TList); static;
    class function FindFirstLandscape(
      const ADesignRoot: TComponent): TCastleLandscapeLayerTerrain; static;
    class function FindLandscapeByName(
      const ADesignRoot, ADesignOwner: TComponent;
      const AName: String): TCastleLandscapeLayerTerrain; static;

    class function SpawnLandscapePresetInDesign(
      const ADesignRoot, ADesignOwner: TComponent;
      const APreset: TLandscapeLayerPreset;
      const AWorldPos: TVector3): TCastleLandscapeLayerTerrain; static;

    class function AuditLandscapesInDesign(
      const ADesignRoot: TComponent): TLandscapeSceneAudit; static;

    class function GenerateMarkdownReport(
      const ADesignRoot: TComponent;
      const AActiveLandscape: TCastleLandscapeLayerTerrain): String; static;
  end;

implementation

uses
  CastleUtils, CastleClassUtils, CastleUIControls;

class function TLandscapeLayersHelper.FindParentViewportItems(
  const ADesignRoot: TComponent): TCastleTransform;

  function SearchVp(const C: TComponent): TCastleViewport;
  var
    UI: TCastleUserInterface;
    I: Integer;
  begin
    Result := nil;
    if C = nil then Exit;
    if C is TCastleViewport then Exit(TCastleViewport(C));
    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
      begin
        Result := SearchVp(UI.Controls[I]);
        if Result <> nil then Exit;
      end;
    end;
  end;

var
  VP: TCastleViewport;
begin
  Result := nil;
  if ADesignRoot = nil then Exit;
  if ADesignRoot is TCastleTransform then
    Exit(TCastleTransform(ADesignRoot));
  VP := SearchVp(ADesignRoot);
  if VP <> nil then
    Result := VP.Items;
end;

class procedure TLandscapeLayersHelper.CollectLandscapes(
  const ADesignRoot: TComponent; const AList: TList);

  procedure Scan(const C: TComponent);
  var
    UI: TCastleUserInterface;
    T: TCastleTransform;
    I: Integer;
  begin
    if (C = nil) or (csTransient in C.ComponentStyle) then Exit;
    if (C is TCastleLandscapeLayerTerrain) and (AList.IndexOf(C) < 0) then
      AList.Add(C);

    if C is TCastleUserInterface then
    begin
      UI := TCastleUserInterface(C);
      for I := 0 to UI.ControlsCount - 1 do
        Scan(UI.Controls[I]);
    end;
    if C is TCastleViewport then
      Scan(TCastleViewport(C).Items)
    else if C is TCastleTransform then
    begin
      T := TCastleTransform(C);
      for I := 0 to T.Count - 1 do
        Scan(T[I]);
    end;
  end;

begin
  if AList = nil then Exit;
  Scan(ADesignRoot);
end;

class function TLandscapeLayersHelper.FindFirstLandscape(
  const ADesignRoot: TComponent): TCastleLandscapeLayerTerrain;
var
  L: TList;
begin
  Result := nil;
  L := TList.Create;
  try
    CollectLandscapes(ADesignRoot, L);
    if L.Count > 0 then
      Result := TCastleLandscapeLayerTerrain(L[0]);
  finally
    FreeAndNil(L);
  end;
end;

class function TLandscapeLayersHelper.FindLandscapeByName(
  const ADesignRoot, ADesignOwner: TComponent;
  const AName: String): TCastleLandscapeLayerTerrain;
var
  Found: TComponent;
  L: TList;
  I: Integer;
begin
  Result := nil;
  if Trim(AName) = '' then
    Exit(FindFirstLandscape(ADesignRoot));

  if ADesignOwner <> nil then
  begin
    Found := ADesignOwner.FindComponent(AName);
    if Found is TCastleLandscapeLayerTerrain then
      Exit(TCastleLandscapeLayerTerrain(Found));
  end;

  L := TList.Create;
  try
    CollectLandscapes(ADesignRoot, L);
    for I := 0 to L.Count - 1 do
      if SameText(TCastleLandscapeLayerTerrain(L[I]).Name, AName) then
        Exit(TCastleLandscapeLayerTerrain(L[I]));
  finally
    FreeAndNil(L);
  end;
end;

class function TLandscapeLayersHelper.SpawnLandscapePresetInDesign(
  const ADesignRoot, ADesignOwner: TComponent;
  const APreset: TLandscapeLayerPreset;
  const AWorldPos: TVector3): TCastleLandscapeLayerTerrain;
var
  ParentT: TCastleTransform;
  BaseName: String;
  OwnerToUse: TComponent;
begin
  Result := nil;
  ParentT := FindParentViewportItems(ADesignRoot);
  if ParentT = nil then Exit;

  OwnerToUse := ADesignOwner;
  if OwnerToUse = nil then
    OwnerToUse := ADesignRoot;

  Result := TCastleLandscapeLayerTerrain.Create(OwnerToUse);
  case APreset of
    llpDesertCanyonHighwayCauseway:   BaseName := 'LS_DesertCauseway';
    llpMedievalMoatAndCastleApproach: BaseName := 'LS_CitadelMoat';
  else
    BaseName := 'LS_AlpineSwitchback';
  end;

  if ADesignOwner <> nil then
    Result.Name := ProposeComponentName(TCastleLandscapeLayerTerrain, ADesignOwner, BaseName)
  else
    Result.Name := BaseName;

  Result.Translation := AWorldPos;
  ParentT.Add(Result);
  Result.ApplyPreset(APreset);
end;

class function TLandscapeLayersHelper.AuditLandscapesInDesign(
  const ADesignRoot: TComponent): TLandscapeSceneAudit;
var
  L: TList;
  Terr: TCastleLandscapeLayerTerrain;
  I: Integer;
begin
  Result := Default(TLandscapeSceneAudit);
  L := TList.Create;
  try
    CollectLandscapes(ADesignRoot, L);
    Result.LandscapeCount := L.Count;
    for I := 0 to L.Count - 1 do
    begin
      Terr := TCastleLandscapeLayerTerrain(L[I]);
      Inc(Result.TotalEditLayers, Length(Terr.Layers));
      Inc(Result.TotalSplines, Length(Terr.Splines));
      Result.TotalCutVolumeM3 := Result.TotalCutVolumeM3 + Terr.Metrics.CutExcavatedVolumeM3;
      Result.TotalFillVolumeM3 := Result.TotalFillVolumeM3 + Terr.Metrics.FillEmbankmentVolumeM3;
      Result.TotalRoadAreaM2 := Result.TotalRoadAreaM2 + Terr.Metrics.RoadPaintedAreaM2;
      Result.TotalRiverAreaM2 := Result.TotalRiverAreaM2 + Terr.Metrics.RiverPaintedAreaM2;
    end;
  finally
    FreeAndNil(L);
  end;
end;

class function TLandscapeLayersHelper.GenerateMarkdownReport(
  const ADesignRoot: TComponent;
  const AActiveLandscape: TCastleLandscapeLayerTerrain): String;
var
  Audit: TLandscapeSceneAudit;
  M: TLandscapeEarthworkMetrics;
  SB: TStringBuilder;
  ModeStr: String;
  I: Integer;
begin
  Audit := AuditLandscapesInDesign(ADesignRoot);
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('# Landscape Edit Layers & Terrain-Carving Splines Report (Phase 394 — UE 5.5 Parity)');
    SB.AppendLine(Format('- **Scene Summary**: `%d` Landscapes | `%d` Edit Layers | `%d` Splines | `Cut=%.0f m^3` | `Fill=%.0f m^3`',
      [Audit.LandscapeCount, Audit.TotalEditLayers, Audit.TotalSplines,
       Audit.TotalCutVolumeM3, Audit.TotalFillVolumeM3]));

    if AActiveLandscape <> nil then
    begin
      M := AActiveLandscape.Metrics;
      SB.AppendLine(Format('- **Active Terrain (`%s`, `%dx%d`)**: `Elev=[%.2fm .. %.2fm]` | `Road=%.0f m^2` | `River=%.0f m^2`',
        [AActiveLandscape.LandscapeKey, AActiveLandscape.GridRes, AActiveLandscape.GridRes,
         M.MinElevationM, M.MaxElevationM, M.RoadPaintedAreaM2, M.RiverPaintedAreaM2]));
      SB.AppendLine;
      SB.AppendLine('| Layer Order | Layer Name | Blend Mode | Opacity | Visible | Splines |');
      SB.AppendLine('| :---: | :--- | :--- | :---: | :---: | :---: |');
      for I := High(AActiveLandscape.Layers) downto 0 do
      begin
        case AActiveLandscape.Layers[I].BlendMode of
          llbmAdditive:      ModeStr := 'Additive';
          llbmAlphaBlend:    ModeStr := 'AlphaBlend';
          llbmMinCarveOnly:  ModeStr := 'MinCarve';
          llbmMaxRaiseOnly:  ModeStr := 'MaxRaise';
        end;
        SB.AppendLine(Format('| `%d` | `%s` | %s | `%.2f` | %s | %s |',
          [I, AActiveLandscape.Layers[I].LayerName, ModeStr,
           AActiveLandscape.Layers[I].Opacity,
           BoolToStr(AActiveLandscape.Layers[I].Visible, 'Yes', 'Muted'),
           BoolToStr(AActiveLandscape.Layers[I].ReservedForSplines, 'Reserved', '-')]));
      end;
    end;
    Result := SB.ToString;
  finally
    FreeAndNil(SB);
  end;
end;

end.
