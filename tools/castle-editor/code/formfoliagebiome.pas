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

{ Interactive Procedural Foliage Ecosystems, Biome Masks & Multi-LOD Proxy
  Studio (@link(TFoliageBiomeForm)) featuring 1-click Alpine/Meadow/Canyon
  biome presets, road exclusion volumes, top-down XZ scatter + exclusion
  preview canvas, and hysteresis LOD tester (Phase 303). }
unit FormFoliageBiome;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Grids, Spin, ComCtrls, Graphics, Clipbrd,
  CastleVectors, CastleUtils, CastleTransform,
  CastleFoliageBiome, ToolFoliageBiome;

type
  TFoliageBiomeModifiedCallback = procedure(const AComment: String) of object;
  TFoliageBiomeRefreshViewportCallback = procedure of object;

  TFoliageBiomeForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FSpawnPos: TVector3;
    FOnModified: TFoliageBiomeModifiedCallback;
    FOnRefreshViewport: TFoliageBiomeRefreshViewportCallback;

    FSummary: TFoliageBiomeSummary;
    FCurrentBiome: TCastleFoliageBiomeVolume;

    LblHeader: TLabel;
    CmbBiomes: TComboBox;
    SpinSeed: TSpinEdit;
    SpinTargetCount: TSpinEdit;
    SpinMaxSlope: TFloatSpinEdit;
    GridSpecies: TStringGrid;
    TrackLodDist: TTrackBar;
    LblLodStatus: TLabel;
    PaintMap: TPaintBox;
    MemoLog: TMemo;

    procedure BuildUi;
    procedure RefreshEcosystem(const APreferred: TCastleFoliageBiomeVolume = nil);
    procedure PopulateBiomeControls;
    procedure NotifyModified(const AComment: String);

    procedure CmbBiomesChange(Sender: TObject);
    procedure BtnAddAlpineClick(Sender: TObject);
    procedure BtnAddMeadowClick(Sender: TObject);
    procedure BtnAddCanyonClick(Sender: TObject);
    procedure BtnAddExclusionClick(Sender: TObject);
    procedure BtnPopulateClick(Sender: TObject);
    procedure BtnClearInstancesClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure TrackLodDistChange(Sender: TObject);
    procedure PaintMapPaint(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner, AInitialComponent: TComponent;
      const ASpawnWorldPos: TVector3;
      const AOnModified: TFoliageBiomeModifiedCallback;
      const AOnRefreshViewport: TFoliageBiomeRefreshViewportCallback);
  end;

implementation

constructor TFoliageBiomeForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner, AInitialComponent: TComponent;
  const ASpawnWorldPos: TVector3;
  const AOnModified: TFoliageBiomeModifiedCallback;
  const AOnRefreshViewport: TFoliageBiomeRefreshViewportCallback);
var
  InitB: TCastleFoliageBiomeVolume;
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FSpawnPos := ASpawnWorldPos;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Procedural Foliage Ecosystems, Biome Masks & Multi-LOD Proxy Studio';
  Width := 1080;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;

  InitB := nil;
  if AInitialComponent is TCastleFoliageBiomeVolume then
    InitB := TCastleFoliageBiomeVolume(AInitialComponent);
  RefreshEcosystem(InitB);
end;

procedure TFoliageBiomeForm.BuildUi;
var
  TopBar, LeftPanel, RightPanel, BottomBar, LodBox: TPanel;
  BtnAlpine, BtnMeadow, BtnCanyon, BtnExcl, BtnPop, BtnClear, BtnRep, BtnClose: TButton;
  LblB, LblSeed, LblCnt, LblSlope, LblSpec, LblMap: TLabel;
begin
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 46;
  TopBar.BevelOuter := bvNone;

  BtnAlpine := TButton.Create(Self);
  BtnAlpine.Parent := TopBar;
  BtnAlpine.SetBounds(8, 8, 125, 30);
  BtnAlpine.Caption := '+ Alpine Forest';
  BtnAlpine.OnClick := @BtnAddAlpineClick;

  BtnMeadow := TButton.Create(Self);
  BtnMeadow.Parent := TopBar;
  BtnMeadow.SetBounds(138, 8, 125, 30);
  BtnMeadow.Caption := '+ Oak Meadow';
  BtnMeadow.OnClick := @BtnAddMeadowClick;

  BtnCanyon := TButton.Create(Self);
  BtnCanyon.Parent := TopBar;
  BtnCanyon.SetBounds(268, 8, 125, 30);
  BtnCanyon.Caption := '+ Canyon Scrub';
  BtnCanyon.OnClick := @BtnAddCanyonClick;

  BtnExcl := TButton.Create(Self);
  BtnExcl.Parent := TopBar;
  BtnExcl.SetBounds(398, 8, 138, 30);
  BtnExcl.Caption := '+ Exclusion Zone';
  BtnExcl.OnClick := @BtnAddExclusionClick;

  BtnPop := TButton.Create(Self);
  BtnPop.Parent := TopBar;
  BtnPop.SetBounds(542, 8, 138, 30);
  BtnPop.Caption := 'Populate Biome';
  BtnPop.OnClick := @BtnPopulateClick;

  BtnClear := TButton.Create(Self);
  BtnClear.Parent := TopBar;
  BtnClear.SetBounds(686, 8, 118, 30);
  BtnClear.Caption := 'Clear Foliage';
  BtnClear.OnClick := @BtnClearInstancesClick;

  BtnRep := TButton.Create(Self);
  BtnRep.Parent := TopBar;
  BtnRep.SetBounds(810, 8, 120, 30);
  BtnRep.Caption := 'Copy Report';
  BtnRep.OnClick := @BtnCopyReportClick;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := TopBar;
  LblHeader.SetBounds(938, 15, 135, 20);
  LblHeader.Caption := '0 Biomes';

  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 40;
  BottomBar.BevelOuter := bvNone;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := BottomBar;
  BtnClose.SetBounds(960, 5, 104, 28);
  BtnClose.Anchors := [akTop, akRight];
  BtnClose.Caption := 'Close';
  BtnClose.OnClick := @BtnCloseClick;

  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := Self;
  LeftPanel.Align := alLeft;
  LeftPanel.Width := 380;
  LeftPanel.BevelOuter := bvNone;

  LblB := TLabel.Create(Self);
  LblB.Parent := LeftPanel;
  LblB.SetBounds(10, 8, 250, 18);
  LblB.Caption := 'Active Foliage Biome Volume:';

  CmbBiomes := TComboBox.Create(Self);
  CmbBiomes.Parent := LeftPanel;
  CmbBiomes.SetBounds(10, 28, 356, 26);
  CmbBiomes.Style := csDropDownList;
  CmbBiomes.OnChange := @CmbBiomesChange;

  LblSeed := TLabel.Create(Self);
  LblSeed.Parent := LeftPanel;
  LblSeed.SetBounds(10, 64, 80, 18);
  LblSeed.Caption := 'Seed:';

  SpinSeed := TSpinEdit.Create(Self);
  SpinSeed.Parent := LeftPanel;
  SpinSeed.SetBounds(10, 84, 105, 26);
  SpinSeed.MinValue := 1;
  SpinSeed.MaxValue := 999999;
  SpinSeed.Value := 2026;

  LblCnt := TLabel.Create(Self);
  LblCnt.Parent := LeftPanel;
  LblCnt.SetBounds(125, 64, 110, 18);
  LblCnt.Caption := 'Target Count:';

  SpinTargetCount := TSpinEdit.Create(Self);
  SpinTargetCount.Parent := LeftPanel;
  SpinTargetCount.SetBounds(125, 84, 110, 26);
  SpinTargetCount.MinValue := 1;
  SpinTargetCount.MaxValue := 2000;
  SpinTargetCount.Value := 48;

  LblSlope := TLabel.Create(Self);
  LblSlope.Parent := LeftPanel;
  LblSlope.SetBounds(245, 64, 120, 18);
  LblSlope.Caption := 'Max Slope (deg):';

  SpinMaxSlope := TFloatSpinEdit.Create(Self);
  SpinMaxSlope.Parent := LeftPanel;
  SpinMaxSlope.SetBounds(245, 84, 120, 26);
  SpinMaxSlope.MinValue := 1.0;
  SpinMaxSlope.MaxValue := 90.0;
  SpinMaxSlope.Value := 40.0;

  LblSpec := TLabel.Create(Self);
  LblSpec.Parent := LeftPanel;
  LblSpec.SetBounds(10, 118, 320, 18);
  LblSpec.Caption := 'Weighted Species Palette & Ecological Filters:';

  GridSpecies := TStringGrid.Create(Self);
  GridSpecies.Parent := LeftPanel;
  GridSpecies.SetBounds(10, 138, 356, 175);
  GridSpecies.ColCount := 4;
  GridSpecies.RowCount := 2;
  GridSpecies.FixedCols := 0;
  GridSpecies.FixedRows := 1;
  GridSpecies.ColWidths[0] := 105;
  GridSpecies.ColWidths[1] := 80;
  GridSpecies.ColWidths[2] := 75;
  GridSpecies.ColWidths[3] := 80;
  GridSpecies.Cells[0, 0] := 'Species';
  GridSpecies.Cells[1, 0] := 'Archetype';
  GridSpecies.Cells[2, 0] := 'Spacing';
  GridSpecies.Cells[3, 0] := 'Max Slope';

  LodBox := TPanel.Create(Self);
  LodBox.Parent := LeftPanel;
  LodBox.SetBounds(10, 322, 356, 90);
  LodBox.BevelOuter := bvLowered;

  LblLodStatus := TLabel.Create(Self);
  LblLodStatus.Parent := LodBox;
  LblLodStatus.SetBounds(8, 8, 338, 20);
  LblLodStatus.Caption := 'Hysteresis LOD Simulator: Distance = 10 m -> [High]';

  TrackLodDist := TTrackBar.Create(Self);
  TrackLodDist.Parent := LodBox;
  TrackLodDist.SetBounds(6, 34, 342, 42);
  TrackLodDist.Min := 0;
  TrackLodDist.Max := 180;
  TrackLodDist.Position := 10;
  TrackLodDist.OnChange := @TrackLodDistChange;

  MemoLog := TMemo.Create(Self);
  MemoLog.Parent := LeftPanel;
  MemoLog.SetBounds(10, 420, 356, 185);
  MemoLog.ReadOnly := true;
  MemoLog.ScrollBars := ssVertical;

  RightPanel := TPanel.Create(Self);
  RightPanel.Parent := Self;
  RightPanel.Align := alClient;
  RightPanel.BevelOuter := bvNone;

  LblMap := TLabel.Create(Self);
  LblMap.Parent := RightPanel;
  LblMap.Align := alTop;
  LblMap.Caption := '  Top-Down XZ Ecosystem Scatter & Exclusion Mask Preview (emerald = trees/foliage, red = exclusion zones):';

  PaintMap := TPaintBox.Create(Self);
  PaintMap.Parent := RightPanel;
  PaintMap.Align := alClient;
  PaintMap.OnPaint := @PaintMapPaint;
end;

procedure TFoliageBiomeForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TFoliageBiomeForm.RefreshEcosystem(
  const APreferred: TCastleFoliageBiomeVolume);
var
  I, PrefIdx: Integer;
begin
  FSummary := TFoliageBiomeHelper.ScanFoliageEcosystem(FDesignRoot);
  LblHeader.Caption := Format('%d Biomes | %d Inst',
    [Length(FSummary.Biomes), FSummary.TotalGeneratedInstances]);

  CmbBiomes.Items.BeginUpdate;
  try
    CmbBiomes.Items.Clear;
    PrefIdx := -1;
    for I := 0 to High(FSummary.Biomes) do
    begin
      CmbBiomes.Items.AddObject(
        Format('%s — %s (%d inst)',
          [FSummary.Biomes[I].Name, FSummary.Biomes[I].BiomeTitle,
           FSummary.Biomes[I].GeneratedInstanceCount]),
        FSummary.Biomes[I]);
      if FSummary.Biomes[I] = APreferred then
        PrefIdx := I;
    end;
    if (PrefIdx < 0) and (CmbBiomes.Items.Count > 0) then
      PrefIdx := 0;
    CmbBiomes.ItemIndex := PrefIdx;
  finally
    CmbBiomes.Items.EndUpdate;
  end;

  if CmbBiomes.ItemIndex >= 0 then
    FCurrentBiome := TCastleFoliageBiomeVolume(CmbBiomes.Items.Objects[CmbBiomes.ItemIndex])
  else
    FCurrentBiome := nil;

  PopulateBiomeControls;
end;

procedure TFoliageBiomeForm.PopulateBiomeControls;
var
  I: Integer;
  S: TFoliageSpeciesEntry;
begin
  if FCurrentBiome = nil then
  begin
    GridSpecies.RowCount := 2;
    GridSpecies.Cells[0, 1] := '(no biome)';
    GridSpecies.Cells[1, 1] := '-';
    GridSpecies.Cells[2, 1] := '-';
    GridSpecies.Cells[3, 1] := '-';
    PaintMap.Invalidate;
    Exit;
  end;

  SpinSeed.Value := FCurrentBiome.Seed;
  SpinTargetCount.Value := FCurrentBiome.TargetInstanceCount;
  SpinMaxSlope.Value := FCurrentBiome.GlobalMaxSlopeDeg;

  GridSpecies.RowCount := Max(2, FCurrentBiome.SpeciesCount + 1);
  for I := 0 to FCurrentBiome.SpeciesCount - 1 do
  begin
    S := FCurrentBiome.GetSpecies(I);
    GridSpecies.Cells[0, I + 1] := S.SpeciesId;
    GridSpecies.Cells[1, I + 1] := TCastleFoliageBiomeVolume.ArchetypeToName(S.Archetype);
    GridSpecies.Cells[2, I + 1] := Format('%.1f m', [S.MinRadiusSpacing]);
    GridSpecies.Cells[3, I + 1] := Format('%.0f deg', [S.MaxSlopeDeg]);
  end;
  PaintMap.Invalidate;
end;

procedure TFoliageBiomeForm.CmbBiomesChange(Sender: TObject);
begin
  if CmbBiomes.ItemIndex >= 0 then
    FCurrentBiome := TCastleFoliageBiomeVolume(CmbBiomes.Items.Objects[CmbBiomes.ItemIndex])
  else
    FCurrentBiome := nil;
  PopulateBiomeControls;
end;

procedure TFoliageBiomeForm.BtnAddAlpineClick(Sender: TObject);
var
  B: TCastleFoliageBiomeVolume;
begin
  B := TFoliageBiomeHelper.CreateBiomeVolumeInDesign(FDesignRoot, FDesignOwner, 0, FSpawnPos);
  if B <> nil then
  begin
    NotifyModified('Create Alpine Pine Biome Volume');
    RefreshEcosystem(B);
  end;
end;

procedure TFoliageBiomeForm.BtnAddMeadowClick(Sender: TObject);
var
  B: TCastleFoliageBiomeVolume;
begin
  B := TFoliageBiomeHelper.CreateBiomeVolumeInDesign(FDesignRoot, FDesignOwner, 1, FSpawnPos);
  if B <> nil then
  begin
    NotifyModified('Create Oak Meadow Biome Volume');
    RefreshEcosystem(B);
  end;
end;

procedure TFoliageBiomeForm.BtnAddCanyonClick(Sender: TObject);
var
  B: TCastleFoliageBiomeVolume;
begin
  B := TFoliageBiomeHelper.CreateBiomeVolumeInDesign(FDesignRoot, FDesignOwner, 2, FSpawnPos);
  if B <> nil then
  begin
    NotifyModified('Create Canyon Scrub Biome Volume');
    RefreshEcosystem(B);
  end;
end;

procedure TFoliageBiomeForm.BtnAddExclusionClick(Sender: TObject);
var
  Ex: TCastleFoliageExclusionVolume;
begin
  Ex := TFoliageBiomeHelper.CreateExclusionVolumeInDesign(
    FDesignRoot, FDesignOwner, FSpawnPos, Vector3(10.0, 12.0, 10.0));
  if Ex <> nil then
  begin
    MemoLog.Lines.Add('Added Exclusion Volume: ' + Ex.Name);
    NotifyModified('Create Foliage Exclusion Volume');
    RefreshEcosystem(FCurrentBiome);
  end;
end;

procedure TFoliageBiomeForm.BtnPopulateClick(Sender: TObject);
var
  Spawned: Integer;
begin
  if FCurrentBiome = nil then
    Exit;
  FCurrentBiome.Seed := SpinSeed.Value;
  FCurrentBiome.TargetInstanceCount := SpinTargetCount.Value;
  FCurrentBiome.GlobalMaxSlopeDeg := SpinMaxSlope.Value;

  Spawned := TFoliageBiomeHelper.PopulateBiomeWithSceneExclusions(
    FDesignRoot, FDesignOwner, FCurrentBiome);
  MemoLog.Lines.Add(Format('Populated "%s": %d instances spawned.',
    [FCurrentBiome.Name, Spawned]));
  NotifyModified('Populate Foliage Biome ' + FCurrentBiome.Name);
  RefreshEcosystem(FCurrentBiome);
end;

procedure TFoliageBiomeForm.BtnClearInstancesClick(Sender: TObject);
var
  Removed: Integer;
begin
  if FCurrentBiome = nil then
    Exit;
  Removed := FCurrentBiome.ClearGeneratedInstances;
  MemoLog.Lines.Add(Format('Cleared %d generated instances from "%s".',
    [Removed, FCurrentBiome.Name]));
  NotifyModified('Clear Foliage Biome ' + FCurrentBiome.Name);
  RefreshEcosystem(FCurrentBiome);
end;

procedure TFoliageBiomeForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := TFoliageBiomeHelper.BuildMarkdownReport(FDesignRoot);
  MemoLog.Lines.Add('Copied Ecosystem Markdown Report to clipboard.');
end;

procedure TFoliageBiomeForm.TrackLodDistChange(Sender: TObject);
var
  I: Integer;
  Lvl: TFoliageLodLevel;
begin
  Lvl := fllHigh;
  if Length(FSummary.LodProxies) > 0 then
  begin
    for I := 0 to High(FSummary.LodProxies) do
      Lvl := FSummary.LodProxies[I].EvaluateForDistance(TrackLodDist.Position);
  end else
  begin
    if TrackLodDist.Position > 140 then Lvl := fllCulled
    else if TrackLodDist.Position > 60 then Lvl := fllLow
    else if TrackLodDist.Position > 25 then Lvl := fllMedium
    else Lvl := fllHigh;
  end;
  LblLodStatus.Caption := Format('Hysteresis LOD Simulator: Distance = %d m -> [%s]',
    [TrackLodDist.Position, TCastleLodProxyBehavior.LodLevelToName(Lvl)]);
end;

procedure TFoliageBiomeForm.PaintMapPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, CX, CY, I, PX, PY, RX, RZ: Integer;
  HalfSpan, ScalePx: Single;
  Child: TCastleTransform;
  Ex: TCastleFoliageExclusionVolume;
  RelPos: TVector3;
begin
  C := PaintMap.Canvas;
  W := PaintMap.Width;
  H := PaintMap.Height;
  C.Brush.Color := RGBToColor(22, 30, 26);
  C.FillRect(0, 0, W, H);

  if FCurrentBiome = nil then
    Exit;

  CX := W div 2;
  CY := H div 2;
  HalfSpan := Max(10.0, Max(FCurrentBiome.VolumeSize.X, FCurrentBiome.VolumeSize.Z) * 0.6);
  ScalePx := (Min(W, H) * 0.45) / HalfSpan;

  { Biome bounds }
  RX := Round(FCurrentBiome.VolumeSize.X * 0.5 * ScalePx);
  RZ := Round(FCurrentBiome.VolumeSize.Z * 0.5 * ScalePx);
  C.Pen.Color := RGBToColor(70, 195, 110);
  C.Pen.Width := 2;
  C.Brush.Style := bsClear;
  C.Rectangle(CX - RX, CY - RZ, CX + RX, CY + RZ);

  { Exclusion zones }
  for I := 0 to High(FSummary.Exclusions) do
  begin
    Ex := FSummary.Exclusions[I];
    RelPos := Ex.Translation - FCurrentBiome.Translation;
    PX := CX + Round(RelPos.X * ScalePx);
    PY := CY + Round(RelPos.Z * ScalePx);
    RX := Round(Ex.ExclusionSize.X * 0.5 * ScalePx);
    RZ := Round(Ex.ExclusionSize.Z * 0.5 * ScalePx);
    C.Pen.Color := RGBToColor(235, 85, 80);
    C.Brush.Color := RGBToColor(75, 30, 32);
    C.Brush.Style := bsSolid;
    C.Rectangle(PX - RX, PY - RZ, PX + RX, PY + RZ);
  end;

  { Spawned foliage dots }
  C.Pen.Color := RGBToColor(30, 80, 45);
  C.Pen.Width := 1;
  C.Brush.Color := RGBToColor(95, 235, 130);
  for I := 0 to FCurrentBiome.Count - 1 do
  begin
    Child := FCurrentBiome.Items[I];
    if (Child <> nil) and (Child.Tag = FoliageGeneratedInstanceTag) then
    begin
      PX := CX + Round(Child.Translation.X * ScalePx);
      PY := CY + Round(Child.Translation.Z * ScalePx);
      C.Ellipse(PX - 4, PY - 4, PX + 4, PY + 4);
    end;
  end;
end;

procedure TFoliageBiomeForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

end.
