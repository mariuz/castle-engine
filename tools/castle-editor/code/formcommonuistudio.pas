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

{ CommonUI Gamepad Spatial 2D Focus Router, Modal Activatable Widget Stack,
  Input-Device Glyph Switcher & MVVM ViewModel Binding Studio Dialog
  (@link(TCommonUiStudioForm))
  (Phase 332 — UE 6.0+ CommonUI & UMG MVVM ViewModel Parity). }
unit FormCommonUiStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleUIControls,
  CastleCommonUiMvvm, ToolCommonUiStudio;

type
  TCommonUiModifyCallback = procedure(const AUndoComment: String) of object;
  TCommonUiRefreshCallback = procedure of object;

  TCommonUiStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModify: TCommonUiModifyCallback;
    FOnRefresh: TCommonUiRefreshCallback;

    FRouters: TCommonRouterArray;
    FBinders: TMvvmBinderArray;

    LblHeader: TLabel;
    ListRouters: TListBox;
    LblDetails: TLabel;
    PaintFocusGraph: TPaintBox;
    MemoReport: TMemo;

    procedure BuildUi;
    procedure RefreshFromDesign;
    function SelectedRouter: TCastleCommonUiRouter;
    function SelectedBinder: TCastleMvvmBinder;
    procedure NotifyModified(const AComment: String);

    procedure ListRoutersClick(Sender: TObject);
    procedure BtnSpawnDemoClick(Sender: TObject);
    procedure BtnNavUpClick(Sender: TObject);
    procedure BtnNavDownClick(Sender: TObject);
    procedure BtnNavLeftClick(Sender: TObject);
    procedure BtnNavRightClick(Sender: TObject);
    procedure BtnCycleDeviceClick(Sender: TObject);
    procedure BtnToggleModalClick(Sender: TObject);
    procedure BtnDamageMvvmClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintFocusGraphPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModify: TCommonUiModifyCallback;
      const AOnRefresh: TCommonUiRefreshCallback);
  end;

implementation

constructor TCommonUiStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModify: TCommonUiModifyCallback;
  const AOnRefresh: TCommonUiRefreshCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModify := AOnModify;
  FOnRefresh := AOnRefresh;

  Caption := 'Castle Game Engine — CommonUI Gamepad Focus, Device Glyphs & MVVM Studio';
  Width := 1180;
  Height := 730;
  Position := poMainFormCenter;

  BuildUi;
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModify) then
    FOnModify(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
end;

procedure TCommonUiStudioForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
  Lbl: TLabel;
  BtnClose: TButton;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.SetBounds(ALeft, ATop, AWidth, 28);
    Result.Caption := ACaption;
    Result.OnClick := AClick;
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 74;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'CommonUI & MVVM Studio — D-Pad Spatial Cone Focus, Modal Activatable Layers, KB/Xbox/PS5 Glyphs & Two-Way RTTI Bindings';

  MakeBtn(PanelTop, '+ Spawn Menu + MVVM HUD', 12, 34, 196, @BtnSpawnDemoClick);
  MakeBtn(PanelTop, 'Up', 214, 34, 58, @BtnNavUpClick);
  MakeBtn(PanelTop, 'Down', 276, 34, 66, @BtnNavDownClick);
  MakeBtn(PanelTop, 'Left', 346, 34, 62, @BtnNavLeftClick);
  MakeBtn(PanelTop, 'Right', 412, 34, 66, @BtnNavRightClick);
  MakeBtn(PanelTop, 'Cycle KB / Xbox / PS5 / Deck', 484, 34, 214, @BtnCycleDeviceClick);
  MakeBtn(PanelTop, 'Push / Pop Modal', 704, 34, 146, @BtnToggleModalClick);
  MakeBtn(PanelTop, 'MVVM Hit (-20% HP)', 856, 34, 166, @BtnDamageMvvmClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy CommonUI Report Markdown', 12, 6, 232, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 1050, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 420;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(12, 6, 380, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'CommonUI Routers & MVVM Binders:';

  ListRouters := TListBox.Create(Self);
  ListRouters.Parent := PanelLeft;
  ListRouters.SetBounds(12, 26, 396, 240);
  ListRouters.OnClick := @ListRoutersClick;

  LblDetails := TLabel.Create(Self);
  LblDetails.Parent := PanelLeft;
  LblDetails.SetBounds(12, 276, 396, 130);
  LblDetails.WordWrap := True;
  LblDetails.Caption := '';

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintFocusGraph := TPaintBox.Create(Self);
  PaintFocusGraph.Parent := PanelCenter;
  PaintFocusGraph.Align := alTop;
  PaintFocusGraph.Height := 300;
  PaintFocusGraph.OnPaint := @PaintFocusGraphPaint;

  MemoReport := TMemo.Create(Self);
  MemoReport.Parent := PanelCenter;
  MemoReport.Align := alClient;
  MemoReport.ReadOnly := True;
  MemoReport.ScrollBars := ssAutoBoth;
  MemoReport.Font.Name := 'Monospace';
end;

function TCommonUiStudioForm.SelectedRouter: TCastleCommonUiRouter;
var
  Idx: Integer;
begin
  Idx := ListRouters.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FRouters)) then
    Result := FRouters[Idx]
  else if Length(FRouters) > 0 then
    Result := FRouters[0]
  else
    Result := nil;
end;

function TCommonUiStudioForm.SelectedBinder: TCastleMvvmBinder;
begin
  if Length(FBinders) > 0 then
    Result := FBinders[0]
  else
    Result := nil;
end;

procedure TCommonUiStudioForm.RefreshFromDesign;
var
  I, PrevIdx: Integer;
  R: TCastleCommonUiRouter;
  B: TCastleMvvmBinder;
  FocName: String;
begin
  PrevIdx := ListRouters.ItemIndex;
  TCommonUiStudioHelper.ScanCommonUi(FDesignRoot, FDesignOwner, FRouters, FBinders);

  ListRouters.Items.BeginUpdate;
  try
    ListRouters.Items.Clear;
    for I := 0 to High(FRouters) do
      ListRouters.Items.Add(Format('%s  %s',
        [FRouters[I].Name, FRouters[I].RouterSummaryBadge]));
    for I := 0 to High(FBinders) do
      ListRouters.Items.Add(Format('%s  %s',
        [FBinders[I].Name, FBinders[I].MvvmSummaryBadge]));
    if ListRouters.Items.Count > 0 then
      ListRouters.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListRouters.Items.Count - 1);
  finally
    ListRouters.Items.EndUpdate;
  end;

  R := SelectedRouter;
  B := SelectedBinder;
  if R <> nil then
  begin
    if R.FocusedControl <> nil then FocName := R.FocusedControl.Name else FocName := '(none)';
    LblDetails.Caption := Format(
      'Active Input Device: %s' + LineEnding +
      'Focused Control: %s  |  Modal Stack Depth: %d' + LineEnding +
      'Confirm Glyph: %s   Back Glyph: %s   Tabs: %s / %s',
      [TCastleCommonUiRouter.DeviceDisplayName(R.ActiveDevice),
       FocName, R.ModalStackDepth,
       ResolveInputPromptGlyph(R.ActiveDevice, 'Confirm'),
       ResolveInputPromptGlyph(R.ActiveDevice, 'Back'),
       ResolveInputPromptGlyph(R.ActiveDevice, 'TabPrev'),
       ResolveInputPromptGlyph(R.ActiveDevice, 'TabNext')]);
    if B <> nil then
      LblDetails.Caption := LblDetails.Caption + LineEnding + Format(
        'MVVM HealthRatio = %.0f%%  |  Bindings = %d  |  Syncs = %d',
        [B.GetFloat('HealthRatio', 1.0) * 100.0, B.BindingCount, B.SyncCounter]);
  end else
    LblDetails.Caption := 'Click "+ Spawn Menu + MVVM HUD" to create a Gamepad Menu & MVVM HUD.';

  MemoReport.Lines.Text := TCommonUiStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintFocusGraph.Invalidate;
end;

procedure TCommonUiStudioForm.ListRoutersClick(Sender: TObject);
begin
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnSpawnDemoClick(Sender: TObject);
var
  MenuRoot, PopupLayer: TCastleUserInterface;
  R: TCastleCommonUiRouter;
  B: TCastleMvvmBinder;
begin
  TCommonUiStudioHelper.SpawnCommonUiMenuAndMvvmHudDemo(
    FDesignRoot, FDesignOwner, MenuRoot, PopupLayer, R, B);
  NotifyModified('Spawn CommonUI Gamepad Menu & MVVM HUD');
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnNavUpClick(Sender: TObject);
var
  R: TCastleCommonUiRouter;
begin
  R := SelectedRouter;
  if R <> nil then R.NavigateDirection(cndUp);
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnNavDownClick(Sender: TObject);
var
  R: TCastleCommonUiRouter;
begin
  R := SelectedRouter;
  if R <> nil then R.NavigateDirection(cndDown);
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnNavLeftClick(Sender: TObject);
var
  R: TCastleCommonUiRouter;
begin
  R := SelectedRouter;
  if R <> nil then R.NavigateDirection(cndLeft);
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnNavRightClick(Sender: TObject);
var
  R: TCastleCommonUiRouter;
begin
  R := SelectedRouter;
  if R <> nil then R.NavigateDirection(cndRight);
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnCycleDeviceClick(Sender: TObject);
var
  R: TCastleCommonUiRouter;
begin
  R := SelectedRouter;
  if R = nil then Exit;
  if R.ActiveDevice = High(TCommonInputDeviceFamily) then
    R.ActiveDevice := Low(TCommonInputDeviceFamily)
  else
    R.ActiveDevice := Succ(R.ActiveDevice);
  R.RefreshPromptLabels(FDesignOwner);
  NotifyModified('Switch CommonUI Input Device Family');
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnToggleModalClick(Sender: TObject);
var
  R: TCastleCommonUiRouter;
  PopComp: TComponent;
begin
  R := SelectedRouter;
  if R = nil then Exit;
  if R.ModalStackDepth > 0 then
    R.PopActivatableLayer
  else if FDesignOwner <> nil then
  begin
    PopComp := FDesignOwner.FindComponent('PopupConfirmQuitModal');
    if PopComp is TCastleUserInterface then
      R.PushActivatableLayer(TCastleUserInterface(PopComp));
  end;
  NotifyModified('Toggle CommonUI Activatable Modal Layer');
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnDamageMvvmClick(Sender: TObject);
var
  B: TCastleMvvmBinder;
  Hp: Single;
begin
  B := SelectedBinder;
  if B = nil then Exit;
  Hp := B.GetFloat('HealthRatio', 1.0) - 0.20;
  if Hp < 0.05 then Hp := 1.0;
  B.SetFloat('HealthRatio', Hp);
  B.PushViewModelToUi(FDesignRoot, FDesignOwner);
  NotifyModified('Push MVVM HealthRatio Update');
  RefreshFromDesign;
end;

procedure TCommonUiStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := MemoReport.Lines.Text;
end;

procedure TCommonUiStudioForm.BtnCloseClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TCommonUiStudioForm.PaintFocusGraphPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, Count, I, PX, PY: Integer;
  R: TCastleCommonUiRouter;
  ControlsList: array [0..63] of TCastleUserInterface;
  Pt: TVector2;
begin
  C := PaintFocusGraph.Canvas;
  W := PaintFocusGraph.Width;
  H := PaintFocusGraph.Height;

  C.Brush.Color := RGBToColor(16, 20, 28);
  C.FillRect(0, 0, W, H);

  R := SelectedRouter;
  if R = nil then Exit;

  R.CollectFocusableControls(ControlsList, Count);
  for I := 0 to Count - 1 do
  begin
    Pt := TCastleCommonUiRouter.ComputeControlCenter2D(ControlsList[I]);
    PX := Clamped(Round(40 + Pt.X * 0.95), 50, W - 90);
    PY := Clamped(Round(H - 30 - Pt.Y * 0.62), 36, H - 30);

    if ControlsList[I] = R.FocusedControl then
    begin
      C.Brush.Color := RGBToColor(42, 138, 92);
      C.Pen.Color := RGBToColor(118, 255, 172);
      C.Pen.Width := 3;
    end else
    begin
      C.Brush.Color := RGBToColor(32, 40, 56);
      C.Pen.Color := RGBToColor(86, 108, 142);
      C.Pen.Width := 1;
    end;
    C.RoundRect(PX - 68, PY - 18, PX + 68, PY + 18, 8, 8);
    C.Pen.Width := 1;

    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.TextOut(PX - 60, PY - 7, Copy(ControlsList[I].Name, 1, 18));
  end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(200, 218, 242);
  C.Font.Style := [fsBold];
  C.TextOut(16, 8, Format(
    'Active Layer Spatial Focus Map (Green = Focused)   |   %s Confirm   %s Back',
    [ResolveInputPromptGlyph(R.ActiveDevice, 'Confirm'),
     ResolveInputPromptGlyph(R.ActiveDevice, 'Back')]));
  C.Font.Style := [];
end;

end.
