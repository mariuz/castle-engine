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

{ Design-time helper for Dynamic Foliage/Grass Trample, Radial Shockwave Blast
  Flatten & Damped Spring-Back Bend Field Studio (Phase 393). }
unit ToolFoliageTrample;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleFoliageTrample;

type
  TFoliageTrampleHelper = class
  public
    class function FindFirstField(const ARoot: TComponent): TCastleFoliageTrampleField;
    class function SpawnWheatFieldDemo(const ARoot, AOwner: TComponent;
      out AField: TCastleFoliageTrampleField): Boolean;
    class function ExportFieldJson(const AField: TCastleFoliageTrampleField): String;
    class function ImportFieldJson(const AField: TCastleFoliageTrampleField;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AField: TCastleFoliageTrampleField): String;
  end;

implementation

uses
  CastleUtils;

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

class function TFoliageTrampleHelper.FindFirstField(
  const ARoot: TComponent): TCastleFoliageTrampleField;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleFoliageTrampleField;
  var
    J: Integer;
  begin
    if T is TCastleFoliageTrampleField then
      Exit(TCastleFoliageTrampleField(T));
    for J := 0 to T.Count - 1 do
    begin
      Result := SearchTransform(T[J]);
      if Result <> nil then Exit;
    end;
    Result := nil;
  end;

begin
  Result := nil;
  if ARoot = nil then Exit;
  if ARoot is TCastleFoliageTrampleField then
    Exit(TCastleFoliageTrampleField(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleFoliageTrampleField then
      Exit(TCastleFoliageTrampleField(ARoot.Components[I]));
end;

class function TFoliageTrampleHelper.SpawnWheatFieldDemo(
  const ARoot, AOwner: TComponent; out AField: TCastleFoliageTrampleField): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  SoilBed: TCastleBox;
begin
  Result := False;
  AField := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  SoilBed := TCastleBox.Create(Own);
  SoilBed.Name := 'MeadowLoamBed';
  SoilBed.Size := Vector3(18.0, 0.2, 18.0);
  SoilBed.Translation := Vector3(0.0, -0.1, 0.0);
  SoilBed.Color := Vector4(0.28, 0.22, 0.14, 1.0);
  VP.Items.Add(SoilBed);

  AField := TCastleFoliageTrampleField.Create(Own);
  AField.Name := 'GoldenWheatMeadow';
  AField.ApplyPreset(ftpGoldenWheatField);
  VP.Items.Add(AField);

  AField.StampCharacterWalkCrush(Vector3(-3.0, 0.0, 0.0), 2.2, 0.90);
  AField.StampCharacterWalkCrush(Vector3(-1.0, 0.0, 0.4), 2.2, 0.90);
  Result := True;
end;

class function TFoliageTrampleHelper.ExportFieldJson(
  const AField: TCastleFoliageTrampleField): String;
var
  Obj: TJSONObject;
begin
  if AField = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('preset', Ord(AField.Preset));
    Obj.Add('fieldExtentMeters', AField.FieldExtentMeters);
    Obj.Add('gridResolution', AField.GridResolution);
    Obj.Add('stalkHeightMeters', AField.StalkHeightMeters);
    Obj.Add('maxTiltDeg', AField.MaxTiltDeg);
    Obj.Add('springStiffness', AField.SpringStiffness);
    Obj.Add('springDamping', AField.SpringDamping);
    Result := Obj.FormatJSON;
  finally
    FreeAndNil(Obj);
  end;
end;

class function TFoliageTrampleHelper.ImportFieldJson(
  const AField: TCastleFoliageTrampleField; const AJson: String): Boolean;
var
  D: TJSONData;
  Obj: TJSONObject;
  POrd: Integer;
begin
  Result := False;
  if (AField = nil) or (Trim(AJson) = '') then Exit;
  D := nil;
  try
    D := GetJSON(AJson);
    if not (D is TJSONObject) then Exit;
    Obj := TJSONObject(D);
    POrd := Obj.Get('preset', Ord(AField.Preset));
    if (POrd >= Ord(Low(TFoliageTramplePreset))) and
       (POrd <= Ord(High(TFoliageTramplePreset))) then
      AField.Preset := TFoliageTramplePreset(POrd);
    AField.FieldExtentMeters := Obj.Get('fieldExtentMeters', AField.FieldExtentMeters);
    AField.GridResolution := Obj.Get('gridResolution', AField.GridResolution);
    AField.StalkHeightMeters := Obj.Get('stalkHeightMeters', AField.StalkHeightMeters);
    AField.MaxTiltDeg := Obj.Get('maxTiltDeg', AField.MaxTiltDeg);
    AField.SpringStiffness := Obj.Get('springStiffness', AField.SpringStiffness);
    AField.SpringDamping := Obj.Get('springDamping', AField.SpringDamping);
    Result := True;
  finally
    FreeAndNil(D);
  end;
end;

class function TFoliageTrampleHelper.GenerateMarkdownReport(
  const AField: TCastleFoliageTrampleField): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Dynamic Foliage Trample, Blast Flatten & Elastic Recovery Report');
    SL.Add('');
    if AField = nil then
    begin
      SL.Add('_No `TCastleFoliageTrampleField` found in the active design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Field Name**: `' + AField.Name + '` (`' +
      FoliageTramplePresetToString(AField.Preset) + '`)');
    SL.Add(FormatDot('- **Grid / Extent**: `%d x %d` cells over `%.1f m x %.1f m` (Stalk Height `%.2f m`)',
      [AField.GridResolution, AField.GridResolution, AField.FieldExtentMeters,
       AField.FieldExtentMeters, AField.StalkHeightMeters]));
    SL.Add(FormatDot('- **Elastic Dynamics**: Stiffness `%.1f`, Damping `%.1f` (`%d` bent cells, Peak Tilt `%.1f deg`)',
      [AField.SpringStiffness, AField.SpringDamping, AField.TrampledCellCount,
       AField.MaxActiveTiltDeg]));
    Result := SL.Text;
  finally
    FreeAndNil(SL);
  end;
end;

end.
