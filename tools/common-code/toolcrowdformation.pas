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

{ Design-time helper for Tactical Squad & Crowd Formation Controller
  (Wedge, Phalanx, Shield-Circle, Column & WorldRay Obstacle Split) Studio (Phase 405). }
unit ToolCrowdFormation;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, jsonparser,
  CastleVectors, CastleTransform, CastleScene, CastleViewport, CastleColors,
  CastleCrowdFormation;

type
  TCrowdFormationHelper = class
  public
    class function FindFirstFormation(const ARoot: TComponent): TCastleCrowdFormation;
    class function SpawnSquadPassWithBoulderDemo(const ARoot, AOwner: TComponent;
      out AForm: TCastleCrowdFormation): Boolean;
    class function ExportFormationJson(const AForm: TCastleCrowdFormation): String;
    class function ImportFormationJson(const AForm: TCastleCrowdFormation;
      const AJson: String): Boolean;
    class function GenerateMarkdownReport(const AForm: TCastleCrowdFormation): String;
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

class function TCrowdFormationHelper.FindFirstFormation(
  const ARoot: TComponent): TCastleCrowdFormation;
var
  VP: TCastleViewport;
  I: Integer;

  function SearchTransform(const T: TCastleTransform): TCastleCrowdFormation;
  var
    J: Integer;
  begin
    if T is TCastleCrowdFormation then
      Exit(TCastleCrowdFormation(T));
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
  if ARoot is TCastleCrowdFormation then
    Exit(TCastleCrowdFormation(ARoot));
  VP := FindViewportInTree(ARoot);
  if (VP <> nil) and (VP.Items <> nil) then
  begin
    Result := SearchTransform(VP.Items);
    if Result <> nil then Exit;
  end;
  for I := 0 to ARoot.ComponentCount - 1 do
    if ARoot.Components[I] is TCastleCrowdFormation then
      Exit(TCastleCrowdFormation(ARoot.Components[I]));
end;

class function TCrowdFormationHelper.SpawnSquadPassWithBoulderDemo(
  const ARoot, AOwner: TComponent; out AForm: TCastleCrowdFormation): Boolean;
var
  VP: TCastleViewport;
  Own: TComponent;
  GroundSlab, CenterBoulder: TCastleBox;
begin
  Result := False;
  AForm := nil;
  VP := FindViewportInTree(ARoot);
  if (VP = nil) or (VP.Items = nil) then Exit;
  if AOwner <> nil then Own := AOwner else Own := ARoot;

  GroundSlab := TCastleBox.Create(Own);
  GroundSlab.Name := 'PassWalkableTerrain';
  GroundSlab.Size := Vector3(28.0, 0.4, 28.0);
  GroundSlab.Translation := Vector3(0.0, -0.2, 0.0);
  GroundSlab.Color := Vector4(0.32, 0.36, 0.28, 1.0);
  VP.Items.Add(GroundSlab);

  { Tall 3.0m impassable granite boulder right across the middle ranks (Z = +3.4) }
  CenterBoulder := TCastleBox.Create(Own);
  CenterBoulder.Name := 'PassGraniteBoulderObstacle';
  CenterBoulder.Size := Vector3(2.8, 3.0, 2.6);
  CenterBoulder.Translation := Vector3(0.0, 1.5, 3.4);
  CenterBoulder.Color := Vector4(0.46, 0.45, 0.48, 1.0);
  VP.Items.Add(CenterBoulder);

  AForm := TCastleCrowdFormation.Create(Own);
  AForm.Name := 'VanguardSquadFormation';
  AForm.UnitCount := 16;
  AForm.SlotSpacingMeters := 1.80;
  AForm.PhalanxColumns := 4;
  AForm.FormationShape := sfsHoplitesPhalanxGrid;
  VP.Items.Add(AForm);

  AForm.SolveFormationSlots(VP.Items);
  Result := True;
end;

class function TCrowdFormationHelper.ExportFormationJson(
  const AForm: TCastleCrowdFormation): String;
var
  Obj: TJSONObject;
begin
  if AForm = nil then Exit('{}');
  Obj := TJSONObject.Create;
  try
    Obj.Add('shape', Ord(AForm.FormationShape));
    Obj.Add('unit_count', AForm.UnitCount);
    Obj.Add('spacing_m', AForm.SlotSpacingMeters);
    Obj.Add('phalanx_cols', AForm.PhalanxColumns);
    Obj.Add('max_step_m', AForm.MaxStepHeightMeters);
    Result := Obj.FormatJSON;
  finally
    Obj.Free;
  end;
end;

class function TCrowdFormationHelper.ImportFormationJson(
  const AForm: TCastleCrowdFormation; const AJson: String): Boolean;
var
  Data: TJSONData;
  Obj: TJSONObject;
  SOrd: Integer;
begin
  Result := False;
  if (AForm = nil) or (Trim(AJson) = '') then Exit;
  Data := GetJSON(AJson);
  try
    if not (Data is TJSONObject) then Exit;
    Obj := TJSONObject(Data);
    AForm.UnitCount := Obj.Get('unit_count', AForm.UnitCount);
    AForm.SlotSpacingMeters := Obj.Get('spacing_m', AForm.SlotSpacingMeters);
    AForm.PhalanxColumns := Obj.Get('phalanx_cols', AForm.PhalanxColumns);
    AForm.MaxStepHeightMeters := Obj.Get('max_step_m', AForm.MaxStepHeightMeters);
    SOrd := Obj.Get('shape', Ord(AForm.FormationShape));
    if (SOrd >= Ord(Low(TSquadFormationShape))) and
       (SOrd <= Ord(High(TSquadFormationShape))) then
      AForm.FormationShape := TSquadFormationShape(SOrd);
    Result := True;
  finally
    Data.Free;
  end;
end;

class function TCrowdFormationHelper.GenerateMarkdownReport(
  const AForm: TCastleCrowdFormation): String;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# Tactical Squad & Crowd Formation Report');
    SL.Add('');
    if AForm = nil then
    begin
      SL.Add('_No `TCastleCrowdFormation` found in the current design._');
      Exit(SL.Text);
    end;
    SL.Add('- **Formation**: `' + AForm.Name + '` (`' +
      SquadFormationShapeToString(AForm.FormationShape) + '`)');
    SL.Add(FormatDot('- **Squad Size**: `%d` units (Spacing `%.2f m`, Phalanx Cols `%d`)',
      [AForm.SlotCount, AForm.SlotSpacingMeters, AForm.PhalanxColumns]));
    SL.Add(Format('- **WorldRay Terrain-Snapped Slots**: `%d / %d`',
      [AForm.GroundSnappedSlotCount, AForm.SlotCount]));
    SL.Add(Format('- **Boulder/Obstacle Split-Around Slots**: `%d`',
      [AForm.ObstacleAvoidedSlotCount]));
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

end.
