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

{ Unreal Engine 5.5-style Interchange Asset Import Pipeline & Reimport Studio
  featuring a 3-Stage Pipeline Stack DAG + DCC-to-CGE Axis/Unit/UCX_/SOCKET_
  Schematic Viewport and a Translated Asset & Override-Preserving Reimport
  Inspector (Phase 398 — 118 UE Studios / 41 MCP). }
unit FormInterchange;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleInterchange, ToolInterchange;

type
  TInterchangeModifiedCallback = procedure(const UndoComment: String) of object;
  TInterchangeRefreshCallback = procedure of object;

  TInterchangeForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TInterchangeModifiedCallback;
    FOnRefresh: TInterchangeRefreshCallback;

    FActivePipe: TCastleInterchangePipeline;

    FLblStatus: TLabel;
    FPaintPipelineDag: TPaintBox;
    FPaintAssetTable: TPaintBox;
    FMemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);

    procedure PaintPipelineStackAndSchematic(Sender: TObject);
    procedure PaintTranslatedAssetRegistry(Sender: TObject);

    procedure BtnSpawnArchClick(Sender: TObject);
    procedure BtnSpawnHeroClick(Sender: TObject);
    procedure BtnLockCustomMiClick(Sender: TObject);
    procedure BtnRunOneClickReimportClick(Sender: TObject);
    procedure BtnToggleUnitsClick(Sender: TObject);
    procedure BtnToggleAxisClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TInterchangeModifiedCallback;
      const AOnRefresh: TInterchangeRefreshCallback);
  end;

implementation

constructor TInterchangeForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TInterchangeModifiedCallback;
  const AOnRefresh: TInterchangeRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Interchange Asset Import Pipeline & Reimport Rules Studio (UInterchangeManager — 118 UE Studios / 41 MCP)';
  Position := poScreenCenter;
  Width := 1340;
  Height := 760;

  BuildUi;
  FActivePipe := TInterchangeHelper.FindFirstInterchangePipeline(FDesignRoot);
  RefreshFromScene;
end;

procedure TInterchangeForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlBottom, PnlRight: TPanel;
  BtnArch, BtnHero, BtnLock, BtnReimp, BtnUnit, BtnAxis, BtnCopy, BtnClose: TButton;
  XPos: Integer;

  function MakeToolbarBtn(const ACaption: String; const AWidth: Integer;
    const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := PnlToolbar;
    Result.Left := XPos;
    Result.Top := 6;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Caption := ACaption;
    Result.OnClick := AClick;
    Inc(XPos, AWidth + 6);
  end;

begin
  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;
  PnlToolbar.Color := RGBToColor(34, 37, 45);

  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Top := 0;
  PnlTop.Height := 32;
  PnlTop.BevelOuter := bvNone;
  PnlTop.Color := RGBToColor(26, 28, 34);
  PnlToolbar.Top := 32;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 12;
  FLblStatus.Top := 8;
  FLblStatus.Font.Color := RGBToColor(225, 232, 245);
  FLblStatus.Font.Style := [fsBold];
  FLblStatus.Caption := 'Interchange Asset Import Pipeline Ready.';

  XPos := 8;
  BtnArch := MakeToolbarBtn('+ Architecture FBX', 150, @BtnSpawnArchClick);
  BtnHero := MakeToolbarBtn('+ Hero Rig glTF', 132, @BtnSpawnHeroClick);
  BtnLock := MakeToolbarBtn('Lock Custom Steel MI', 162, @BtnLockCustomMiClick);
  BtnReimp := MakeToolbarBtn('1-Click Reimport (v2)', 166, @BtnRunOneClickReimportClick);
  BtnUnit := MakeToolbarBtn('Toggle cm / m', 124, @BtnToggleUnitsClick);
  BtnAxis := MakeToolbarBtn('Toggle Z-Up / Y-Up', 150, @BtnToggleAxisClick);
  BtnCopy := MakeToolbarBtn('Copy Report', 104, @BtnCopyReportClick);
  BtnClose := MakeToolbarBtn('Close', 70, nil);
  BtnClose.ModalResult := mrOk;
  if (BtnArch <> nil) and (BtnHero <> nil) and (BtnLock <> nil) and
     (BtnReimp <> nil) and (BtnUnit <> nil) and (BtnAxis <> nil) and
     (BtnCopy <> nil) then ;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 128;
  PnlBottom.BevelOuter := bvNone;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := PnlBottom;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;
  FMemoReport.Font.Name := 'Consolas';
  FMemoReport.Font.Size := 9;
  FMemoReport.Color := RGBToColor(18, 20, 26);
  FMemoReport.Font.Color := RGBToColor(208, 218, 232);

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 620;
  PnlRight.BevelOuter := bvNone;

  FPaintAssetTable := TPaintBox.Create(Self);
  FPaintAssetTable.Parent := PnlRight;
  FPaintAssetTable.Align := alClient;
  FPaintAssetTable.OnPaint := @PaintTranslatedAssetRegistry;

  FPaintPipelineDag := TPaintBox.Create(Self);
  FPaintPipelineDag.Parent := Self;
  FPaintPipelineDag.Align := alClient;
  FPaintPipelineDag.OnPaint := @PaintPipelineStackAndSchematic;
end;

procedure TInterchangeForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh;
  RefreshFromScene;
end;

procedure TInterchangeForm.RefreshFromScene;
var
  B: TVector3;
begin
  if FActivePipe = nil then
    FActivePipe := TInterchangeHelper.FindFirstInterchangePipeline(FDesignRoot);

  if FActivePipe <> nil then
  begin
    B := FActivePipe.PrimaryMeshBoundsMeters;
    FLblStatus.Caption := Format(
      'Source: %s (Rev v%d)  |  CGE Y-Up Bounds: %.2fx%.2fx%.2fm  |  VisTris: %d  |  Colliders: %d  |  Sockets: %d  |  Locked MI: %d',
      [FActivePipe.SourceFileUrl,
       FActivePipe.ReimportRevision,
       B.X, B.Y, B.Z,
       FActivePipe.TotalVisualTriangles,
       FActivePipe.ExtractedColliderCount,
       FActivePipe.ExtractedSocketCount,
       FActivePipe.LockedSlotOverrideCount]);
  end else
    FLblStatus.Caption := 'No TCastleInterchangePipeline in scene — click "+ Architecture FBX" to inspect UInterchangePipelineStack.';

  FMemoReport.Lines.Text := TInterchangeHelper.GenerateMarkdownReport(
    FDesignRoot, FActivePipe);

  FPaintPipelineDag.Invalidate;
  FPaintAssetTable.Invalidate;
end;

procedure TInterchangeForm.PaintPipelineStackAndSchematic(Sender: TObject);

  procedure DrawStageBox(const C: TCanvas; const X1, Y1, X2, Y2: Integer;
    const BorderCol: TColor; const TitleStr, Line1, Line2: String);
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(28, 33, 44);
    C.Pen.Color := BorderCol;
    C.Pen.Width := 2;
    C.RoundRect(X1, Y1, X2, Y2, 10, 10);
    C.Pen.Width := 1;
    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := BorderCol;
    C.TextOut(X1 + 10, Y1 + 8, TitleStr);
    C.Font.Style := [];
    C.Font.Color := RGBToColor(208, 220, 238);
    C.TextOut(X1 + 10, Y1 + 30, Line1);
    C.Font.Color := RGBToColor(156, 174, 202);
    C.TextOut(X1 + 10, Y1 + 48, Line2);
  end;

var
  C: TCanvas;
  W, H, StageW, GapX, SX, TopY, ArchCx, GroundY, GateW, GateH: Integer;
  B: TVector3;
begin
  C := FPaintPipelineDag.Canvas;
  W := Max(360, FPaintPipelineDag.Width);
  H := Max(320, FPaintPipelineDag.Height);

  C.Brush.Color := RGBToColor(18, 21, 28);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(28, 34, 46);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(126, 206, 255);
  C.TextOut(12, 7, 'UInterchangePipelineStack DAG & Extracted UCX_ / SOCKET_ Viewport');
  C.Font.Style := [];

  if FActivePipe = nil then Exit;

  { Top 3-Stage UE Interchange Pipeline Graph }
  GapX := 16;
  StageW := (W - 24 - GapX * 2) div 3;
  TopY := 44;

  SX := 12;
  DrawStageBox(C, SX, TopY, SX + StageW, TopY + 74,
    RGBToColor(102, 198, 255),
    '1. DCC Translator',
    Format('Rev v%d (%d Nodes)', [FActivePipe.ReimportRevision, Length(FActivePipe.DccNodes)]),
    InterchangeUnitDisplayName(FActivePipe.SourceUnit));

  C.Pen.Color := RGBToColor(120, 196, 255);
  C.Pen.Width := 2;
  C.MoveTo(SX + StageW, TopY + 37);
  C.LineTo(SX + StageW + GapX, TopY + 37);

  SX := SX + StageW + GapX;
  DrawStageBox(C, SX, TopY, SX + StageW, TopY + 74,
    RGBToColor(112, 242, 166),
    '2. GenericMeshPipeline',
    Format('%d VisTris | %d LODs',
      [FActivePipe.TotalVisualTriangles,
       TCastleInterchangePipeline.LodCountForGroup(FActivePipe.LodGroup)]),
    Format('Split: %d UCX/UBX + %d Sockets',
      [FActivePipe.ExtractedColliderCount, FActivePipe.ExtractedSocketCount]));

  C.Pen.Color := RGBToColor(112, 242, 166);
  C.Pen.Width := 2;
  C.MoveTo(SX + StageW, TopY + 37);
  C.LineTo(SX + StageW + GapX, TopY + 37);

  SX := SX + StageW + GapX;
  DrawStageBox(C, SX, TopY, SX + StageW, TopY + 74,
    RGBToColor(255, 206, 96),
    '3. Material & Texture',
    Format('%d MI Slots (%d Locked)',
      [Length(FActivePipe.SlotOverrides), FActivePipe.LockedSlotOverrideCount]),
    'BC=sRGB | ORM/N=Lin+DX');
  C.Pen.Width := 1;

  { Bottom Visual Schematic: Imported Gate Mesh + Green UCX_/UBX_ Hulls + Gold SOCKET_ Pins }
  ArchCx := W div 2;
  GroundY := H - 56;
  GateW := 230;
  GateH := 236;

  { Perspective floor grid }
  C.Pen.Color := RGBToColor(31, 36, 48);
  for SX := -5 to 5 do
  begin
    C.MoveTo(ArchCx + SX * 48, GroundY - 22);
    C.LineTo(ArchCx + SX * 58, GroundY + 18);
  end;
  C.MoveTo(36, GroundY);
  C.LineTo(W - 36, GroundY);

  { Visual Stone Gate Mesh (Blue-Slate Fill) }
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(52, 66, 92);
  C.Pen.Color := RGBToColor(118, 168, 232);
  C.Rectangle(ArchCx - GateW div 2, GroundY - GateH, ArchCx - GateW div 2 + 54, GroundY);
  C.Rectangle(ArchCx + GateW div 2 - 54, GroundY - GateH, ArchCx + GateW div 2, GroundY);
  C.Rectangle(ArchCx - GateW div 2, GroundY - GateH, ArchCx + GateW div 2, GroundY - GateH + 56);

  { Iron Portcullis Slot (highlights Amber-Gold when User MI Override is Locked!) }
  if FActivePipe.LockedSlotOverrideCount > 0 then
  begin
    C.Brush.Color := RGBToColor(116, 78, 42);
    C.Pen.Color := RGBToColor(255, 196, 84);
  end else
  begin
    C.Brush.Color := RGBToColor(42, 48, 58);
    C.Pen.Color := RGBToColor(136, 152, 178);
  end;
  C.Rectangle(ArchCx - 58, GroundY - GateH + 56, ArchCx + 58, GroundY - 18);

  { Extracted Green UCX_ / UBX_ / USP_ Collision Hull Wireframes }
  if FActivePipe.ExtractCollisionPrefixes then
  begin
    C.Brush.Style := bsClear;
    C.Pen.Color := RGBToColor(86, 246, 148);
    C.Pen.Width := 2;
    C.Rectangle(ArchCx - GateW div 2 - 4, GroundY - GateH - 4,
      ArchCx - GateW div 2 + 58, GroundY + 2);
    C.Rectangle(ArchCx + GateW div 2 - 58, GroundY - GateH - 4,
      ArchCx + GateW div 2 + 4, GroundY + 2);
    C.Rectangle(ArchCx - GateW div 2 - 4, GroundY - GateH - 4,
      ArchCx + GateW div 2 + 4, GroundY - GateH + 60);
    C.Ellipse(ArchCx - 98, GroundY - 166, ArchCx - 70, GroundY - 138);
    C.Pen.Width := 1;
    C.Font.Color := RGBToColor(106, 248, 162);
    C.TextOut(ArchCx + GateW div 2 + 12, GroundY - GateH + 12, 'UCX_ / UBX_ / USP_ Hulls');
  end;

  { Extracted Gold SOCKET_ Attachment Triads }
  if FActivePipe.ExtractSocketPrefixes then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(255, 214, 72);
    C.Pen.Color := RGBToColor(32, 28, 18);
    C.Ellipse(ArchCx - 86, GroundY - 156, ArchCx - 74, GroundY - 144);
    C.Ellipse(ArchCx - 6, GroundY - GateH + 10, ArchCx + 6, GroundY - GateH + 22);
    if FActivePipe.ExtractedSocketCount >= 3 then
      C.Ellipse(ArchCx + 74, GroundY - 196, ArchCx + 86, GroundY - 184);

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := RGBToColor(255, 224, 108);
    C.TextOut(ArchCx - GateW div 2 - 156, GroundY - 158, 'SOCKET_TorchMount_L');
    C.TextOut(ArchCx - 62, GroundY - GateH - 22, 'SOCKET_KeystoneCrest');
    if FActivePipe.ExtractedSocketCount >= 3 then
      C.TextOut(ArchCx + GateW div 2 + 12, GroundY - 198, 'SOCKET_BannerPole (v2)');
    C.Font.Style := [];
  end;

  { CGE Y-Up Converted Metric Dimension Callout }
  B := FActivePipe.PrimaryMeshBoundsMeters;
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(152, 216, 255);
  C.TextOut(16, GroundY - GateH - 46,
    Format('CGE Y-Up: %.2fm W x %.2fm H x %.2fm D', [B.X, B.Y, B.Z]));
  C.Font.Style := [];

  C.Font.Color := RGBToColor(184, 202, 228);
  C.TextOut(14, H - 24,
    '1-Click Reimport updates mesh tris & new SOCKET_ nodes while preserving [Locked] MI overrides.');
  C.Brush.Style := bsSolid;
end;

procedure TInterchangeForm.PaintTranslatedAssetRegistry(Sender: TObject);
var
  C: TCanvas;
  W, H, I, RowY: Integer;
  A: TInterchangeTranslatedAsset;
begin
  C := FPaintAssetTable.Canvas;
  W := Max(360, FPaintAssetTable.Width);
  H := Max(320, FPaintAssetTable.Height);

  C.Brush.Color := RGBToColor(24, 26, 33);
  C.FillRect(0, 0, W, H);

  C.Brush.Color := RGBToColor(34, 38, 48);
  C.FillRect(0, 0, W, 30);
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(255, 214, 112);
  C.TextOut(12, 7, 'Translated CGE Asset Registry & Non-Destructive Reimport Rules');
  C.Font.Style := [];

  if FActivePipe = nil then Exit;

  C.Brush.Color := RGBToColor(29, 33, 43);
  C.FillRect(10, 36, W - 10, 60);
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(172, 188, 214);
  C.TextOut(18, 41, 'Translated Asset');
  C.TextOut(218, 41, 'UE Class');
  C.TextOut(348, 41, 'Pipeline Rule / Override State');
  C.Font.Style := [];

  for I := 0 to FActivePipe.TranslatedAssetCount - 1 do
  begin
    A := FActivePipe.TranslatedAssets[I];
    RowY := 64 + I * 54;
    if RowY + 50 > H - 8 then Break;

    C.Brush.Style := bsSolid;
    if Pos('LOCKED OVERRIDE', A.Notes) > 0 then
      C.Brush.Color := RGBToColor(44, 42, 30)
    else if I mod 2 = 0 then
      C.Brush.Color := RGBToColor(28, 31, 41)
    else
      C.Brush.Color := RGBToColor(24, 27, 36);
    C.FillRect(10, RowY, W - 10, RowY + 50);

    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    if A.AssetClass = 'StaticMesh' then
      C.Font.Color := RGBToColor(118, 212, 255)
    else if A.AssetClass = 'SkeletalMesh' then
      C.Font.Color := RGBToColor(208, 152, 255)
    else if A.AssetClass = 'MaterialInstance' then
      C.Font.Color := RGBToColor(118, 242, 168)
    else
      C.Font.Color := RGBToColor(255, 206, 118);
    C.TextOut(18, RowY + 7, A.AssetName);
    C.Font.Style := [];

    C.Font.Color := RGBToColor(188, 204, 228);
    C.TextOut(218, RowY + 7, A.AssetClass);

    if Pos('LOCKED OVERRIDE', A.Notes) > 0 then
      C.Font.Color := RGBToColor(255, 214, 92)
    else
      C.Font.Color := RGBToColor(162, 184, 214);
    C.TextOut(18, RowY + 28, A.Notes);
  end;
  C.Brush.Style := bsSolid;
end;

procedure TInterchangeForm.BtnSpawnArchClick(Sender: TObject);
begin
  FActivePipe := TInterchangeHelper.SpawnInterchangePresetInDesign(
    FDesignRoot, FDesignOwner, ippModularArchitectureProps, Vector3(0, 0, 0));
  NotifyChanged('Spawn Modular Architecture Interchange Pipeline');
end;

procedure TInterchangeForm.BtnSpawnHeroClick(Sender: TObject);
begin
  FActivePipe := TInterchangeHelper.SpawnInterchangePresetInDesign(
    FDesignRoot, FDesignOwner, ippSkeletalHeroRigAndAnimations, Vector3(4, 0, 0));
  NotifyChanged('Spawn Skeletal Hero Interchange Pipeline');
end;

procedure TInterchangeForm.BtnLockCustomMiClick(Sender: TObject);
begin
  if FActivePipe = nil then Exit;
  FActivePipe.SetUserMaterialSlotOverride('Slot_PortcullisIron',
    'castle-data:/materials/MI_RustedDamascusSteel.castle-material');
  NotifyChanged('Lock Custom Material Instance Override on Slot_PortcullisIron');
end;

procedure TInterchangeForm.BtnRunOneClickReimportClick(Sender: TObject);
begin
  if FActivePipe = nil then Exit;
  FActivePipe.SimulateReimportUpdatedDccSource(420, 'SOCKET_BannerPole');
  NotifyChanged(Format('Run 1-Click Interchange Reimport (Rev v%d)',
    [FActivePipe.ReimportRevision]));
end;

procedure TInterchangeForm.BtnToggleUnitsClick(Sender: TObject);
begin
  if FActivePipe = nil then Exit;
  if FActivePipe.SourceUnit = isuCentimeters then
    FActivePipe.SourceUnit := isuMeters
  else
    FActivePipe.SourceUnit := isuCentimeters;
  NotifyChanged('Toggle Interchange Source Units (cm / m)');
end;

procedure TInterchangeForm.BtnToggleAxisClick(Sender: TObject);
begin
  if FActivePipe = nil then Exit;
  if FActivePipe.SourceAxisSystem = iasBlenderZUpRightHanded then
    FActivePipe.SourceAxisSystem := iasMayaYUpRightHanded
  else
    FActivePipe.SourceAxisSystem := iasBlenderZUpRightHanded;
  NotifyChanged('Toggle Interchange Source Axis (Z-Up / Y-Up)');
end;

procedure TInterchangeForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
  FLblStatus.Caption := 'Copied Interchange Asset Pipeline Report to Clipboard.';
end;

end.
