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

{ Visual Studio dialog for Procedural Spiderweb, Radial WorldRay Wall Mooring,
  Logarithmic Capture Spiral & Dewdrop Silk Studio (Phase 392). }
unit FormSpiderweb;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleViewport,
  CastleSpiderweb, ToolSpiderweb;

type
  TSpiderwebModifiedCallback = procedure(const UndoComment: String) of object;
  TSpiderwebRefreshCallback = procedure of object;

  TSpiderwebForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TSpiderwebModifiedCallback;
    FOnRefresh: TSpiderwebRefreshCallback;
    FLblSummary: TLabel;
    FPaintWeb: TPaintBox;
    FMemoReport: TMemo;
    function FindViewport: TCastleViewport;
    procedure BuildUi;
    procedure RefreshView;
    procedure NotifyChanged(const AReason: String);
    procedure BtnSpawnArchClick(Sender: TObject);
    procedure BtnTornCryptClick(Sender: TObject);
    procedure BtnDewCanopyClick(Sender: TObject);
    procedure BtnCopyReportClick(Sender: TObject);
    procedure PaintWebDiagram(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TSpiderwebModifiedCallback;
      const AOnRefresh: TSpiderwebRefreshCallback);
  end;

implementation

constructor TSpiderwebForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TSpiderwebModifiedCallback;
  const AOnRefresh: TSpiderwebRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  Caption := 'Procedural Spiderweb, Wall-Anchor Raycast & Dewdrop Silk Studio';
  Position := poScreenCenter;
  Width := 760;
  Height := 560;
  BuildUi;
  RefreshView;
end;

function TSpiderwebForm.FindViewport: TCastleViewport;
var
  I: Integer;
begin
  Result := nil;
  if FDesignRoot = nil then Exit;
  if FDesignRoot is TCastleViewport then Exit(TCastleViewport(FDesignRoot));
  for I := 0 to FDesignRoot.ComponentCount - 1 do
    if FDesignRoot.Components[I] is TCastleViewport then
      Exit(TCastleViewport(FDesignRoot.Components[I]));
end;

procedure TSpiderwebForm.BuildUi;
var
  PnlTop, PnlButtons: TPanel;
  BtnSpawn, BtnTorn, BtnDew, BtnCopy, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 42;
  PnlTop.BevelOuter := bvNone;

  FLblSummary := TLabel.Create(Self);
  FLblSummary.Parent := PnlTop;
  FLblSummary.Left := 12;
  FLblSummary.Top := 12;
  FLblSummary.Caption := 'Ready.';

  PnlButtons := TPanel.Create(Self);
  PnlButtons.Parent := Self;
  PnlButtons.Align := alTop;
  PnlButtons.Height := 46;
  PnlButtons.BevelOuter := bvNone;

  BtnSpawn := TButton.Create(Self);
  BtnSpawn.Parent := PnlButtons;
  BtnSpawn.SetBounds(10, 8, 195, 30);
  BtnSpawn.Caption := '+ Spawn Archway & Weave Web';
  BtnSpawn.OnClick := @BtnSpawnArchClick;

  BtnTorn := TButton.Create(Self);
  BtnTorn.Parent := PnlButtons;
  BtnTorn.SetBounds(211, 8, 185, 30);
  BtnTorn.Caption := 'Preset: Torn Crypt Cobweb';
  BtnTorn.OnClick := @BtnTornCryptClick;

  BtnDew := TButton.Create(Self);
  BtnDew.Parent := PnlButtons;
  BtnDew.SetBounds(402, 8, 195, 30);
  BtnDew.Caption := 'Preset: Morning Dew Silk';
  BtnDew.OnClick := @BtnDewCanopyClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlButtons;
  BtnCopy.SetBounds(603, 8, 135, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyReportClick;

  FPaintWeb := TPaintBox.Create(Self);
  FPaintWeb.Parent := Self;
  FPaintWeb.Align := alTop;
  FPaintWeb.Height := 210;
  FPaintWeb.OnPaint := @PaintWebDiagram;

  FMemoReport := TMemo.Create(Self);
  FMemoReport.Parent := Self;
  FMemoReport.Align := alClient;
  FMemoReport.ReadOnly := True;
  FMemoReport.ScrollBars := ssVertical;

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := Self;
  BtnClose.Align := alBottom;
  BtnClose.Height := 34;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;
end;

procedure TSpiderwebForm.NotifyChanged(const AReason: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AReason);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshView;
end;

procedure TSpiderwebForm.RefreshView;
var
  W: TCastleSpiderwebGenerator;
begin
  W := TSpiderwebHelper.FindFirstWeb(FDesignRoot);
  if W = nil then
    FLblSummary.Caption := 'No TCastleSpiderwebGenerator in scene. Click "+ Spawn Archway & Weave Web".'
  else
    FLblSummary.Caption := W.SpiderwebSummaryBadge;
  FMemoReport.Lines.Text := TSpiderwebHelper.GenerateMarkdownReport(W);
  FPaintWeb.Invalidate;
end;

procedure TSpiderwebForm.BtnSpawnArchClick(Sender: TObject);
var
  W: TCastleSpiderwebGenerator;
begin
  if TSpiderwebHelper.SpawnDungeonArchwayWebDemo(FDesignRoot, FDesignOwner, W) then
    NotifyChanged('Spawn Dungeon Archway Spiderweb');
end;

procedure TSpiderwebForm.BtnTornCryptClick(Sender: TObject);
var
  W: TCastleSpiderwebGenerator;
  VP: TCastleViewport;
begin
  W := TSpiderwebHelper.FindFirstWeb(FDesignRoot);
  VP := FindViewport;
  if (W = nil) or (VP = nil) then Exit;
  W.ApplyPreset(swpTornDungeonCornerCobweb);
  W.WeaveSpiderwebOnWorld(VP.Items);
  NotifyChanged('Weave Torn Crypt Cobweb');
end;

procedure TSpiderwebForm.BtnDewCanopyClick(Sender: TObject);
var
  W: TCastleSpiderwebGenerator;
  VP: TCastleViewport;
begin
  W := TSpiderwebHelper.FindFirstWeb(FDesignRoot);
  VP := FindViewport;
  if (W = nil) or (VP = nil) then Exit;
  W.ApplyPreset(swpDewdropForestCanopySilk);
  W.WeaveSpiderwebOnWorld(VP.Items);
  NotifyChanged('Weave Morning Dew Canopy Silk');
end;

procedure TSpiderwebForm.BtnCopyReportClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoReport.Lines.Text;
end;

procedure TSpiderwebForm.PaintWebDiagram(Sender: TObject);
var
  C: TCanvas;
  Gen: TCastleSpiderwebGenerator;
  Seg: TSilkSegment;
  W, H, CX, CY, I: Integer;
  S: Single;
begin
  C := FPaintWeb.Canvas;
  W := Max(20, FPaintWeb.Width);
  H := Max(20, FPaintWeb.Height);
  C.Brush.Color := RGBToColor(15, 18, 25);
  C.FillRect(0, 0, W, H);

  Gen := TSpiderwebHelper.FindFirstWeb(FDesignRoot);
  if (Gen = nil) or (Gen.SilkSegmentCount = 0) then Exit;

  CX := W div 2;
  CY := H div 2;
  S := Min(W, H) / 5.2;
  for I := 0 to Gen.SilkSegmentCount - 1 do
  begin
    Seg := Gen.GetSilkSegment(I);
    if Seg.IsRadialSpoke then
      C.Pen.Color := RGBToColor(180, 200, 230)
    else
      C.Pen.Color := RGBToColor(125, 165, 205);
    C.MoveTo(CX + Round((Seg.StartWorld.X - Gen.HubWorldPos.X) * S),
             CY - Round((Seg.StartWorld.Y - Gen.HubWorldPos.Y) * S));
    C.LineTo(CX + Round((Seg.EndWorld.X - Gen.HubWorldPos.X) * S),
             CY - Round((Seg.EndWorld.Y - Gen.HubWorldPos.Y) * S));
  end;
end;

end.
