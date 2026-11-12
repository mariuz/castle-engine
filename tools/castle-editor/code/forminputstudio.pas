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

{ Interactive Enhanced Input Action Mapping, Chord/Combo Triggers & Rebinding
  Studio (@link(TInputStudioForm)) featuring 1-click genre presets, priority
  context toggling, runtime key rebinding with conflict detection, a live 2D
  radial gamepad deadzone & response-curve visualizer, and Markdown/JSON export
  (Phase 311). }
unit FormInputStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleUtils,
  CastleEnhancedInput, ToolInputStudio;

type
  TInputStudioModifiedCallback = procedure(const AComment: String) of object;
  TInputStudioRefreshViewportCallback = procedure of object;

  TInputStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TInputStudioModifiedCallback;
    FOnRefreshViewport: TInputStudioRefreshViewportCallback;

    FReport: TInputStudioAuditReport;
    FPreviewRawStick: TVector2;

    LblHeader: TLabel;
    ListManagers: TListBox;
    ListContexts: TListBox;
    ListBindings: TListBox;
    EditRebindKey: TEdit;
    PaintStick: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function CurrentManager: TCastleInputMapManager;
    procedure RefreshAll;
    procedure RefreshSubLists;
    procedure NotifyChanged(const AComment: String);

    procedure ListManagersClick(Sender: TObject);
    procedure ListBindingsClick(Sender: TObject);
    procedure BtnSpawnActionRpgClick(Sender: TObject);
    procedure BtnSpawnTwinStickClick(Sender: TObject);
    procedure BtnSpawnVehicleClick(Sender: TObject);
    procedure BtnToggleContextClick(Sender: TObject);
    procedure BtnApplyRebindClick(Sender: TObject);
    procedure BtnResetRebindsClick(Sender: TObject);
    procedure BtnCopyRebindsJsonClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintStickPaint(Sender: TObject);
    procedure PaintStickMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TInputStudioModifiedCallback;
      const AOnRefreshViewport: TInputStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TInputStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TInputStudioModifiedCallback;
  const AOnRefreshViewport: TInputStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;
  FPreviewRawStick := Vector2(0.58, 0.42);

  Caption := 'Enhanced Input Action Mapping, Chord/Combo Triggers & Rebinding Studio';
  Width := 1100;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TInputStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TInputStudioForm.BuildUi;
var
  PanelTop, RowTop, PanelBottom, PanelBody, PanelLeft, PanelCenter: TPanel;
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
  PanelTop.Height := 72;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Enhanced Input Studio — Layered Contexts, Tap/Hold/Chord Triggers & Rebinding';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 30, 1080, 38);
  RowTop.BevelOuter := bvNone;

  MakeBtn(RowTop, '+ Action RPG Input Map', 4, 4, 180, @BtnSpawnActionRpgClick);
  MakeBtn(RowTop, '+ Twin-Stick Shooter', 190, 4, 170, @BtnSpawnTwinStickClick);
  MakeBtn(RowTop, '+ Vehicle Racing', 366, 4, 160, @BtnSpawnVehicleClick);
  MakeBtn(RowTop, 'Toggle Selected Context', 532, 4, 180, @BtnToggleContextClick);
  MakeBtn(RowTop, 'Reset Default Keys', 718, 4, 160, @BtnResetRebindsClick);
  MakeBtn(RowTop, 'Copy Rebinds JSON', 884, 4, 164, @BtnCopyRebindsJsonClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Markdown Report', 12, 6, 190, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 970, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 360;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 300, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Input Map Managers:';

  ListManagers := TListBox.Create(Self);
  ListManagers.Parent := PanelLeft;
  ListManagers.SetBounds(10, 26, 340, 96);
  ListManagers.OnClick := @ListManagersClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 128, 300, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Priority Input Mapping Contexts:';

  ListContexts := TListBox.Create(Self);
  ListContexts.Parent := PanelLeft;
  ListContexts.SetBounds(10, 148, 340, 96);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 250, 300, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Action Bindings (Select to Rebind):';

  ListBindings := TListBox.Create(Self);
  ListBindings.Parent := PanelLeft;
  ListBindings.SetBounds(10, 270, 340, 240);
  ListBindings.OnClick := @ListBindingsClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 520, 90, 18);
  Lbl.Caption := 'New Key Name:';

  EditRebindKey := TEdit.Create(Self);
  EditRebindKey.Parent := PanelLeft;
  EditRebindKey.SetBounds(106, 516, 134, 26);
  EditRebindKey.Text := 'KeyF';

  MakeBtn(PanelLeft, 'Rebind Key', 246, 515, 104, @BtnApplyRebindClick);

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintStick := TPaintBox.Create(Self);
  PaintStick.Parent := PanelCenter;
  PaintStick.Align := alTop;
  PaintStick.Height := 340;
  PaintStick.OnPaint := @PaintStickPaint;
  PaintStick.OnMouseDown := @PaintStickMouseDown;

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelCenter;
  MemoDiag.Align := alClient;
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;
  MemoDiag.Font.Name := 'Monospace';
end;

function TInputStudioForm.CurrentManager: TCastleInputMapManager;
var
  Idx: Integer;
begin
  Result := nil;
  if (FReport = nil) or (Length(FReport.Managers) = 0) then
    Exit;
  Idx := ListManagers.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.Managers)) then
    Result := FReport.Managers[Idx];
end;

procedure TInputStudioForm.RefreshAll;
var
  PrevMgr: TCastleInputMapManager;
  I, TargetIdx: Integer;
begin
  PrevMgr := CurrentManager;
  FreeAndNil(FReport);
  FReport := TInputStudioHelper.ScanDesign(FDesignRoot, FDesignOwner);

  ListManagers.Items.BeginUpdate;
  try
    ListManagers.Items.Clear;
    TargetIdx := 0;
    for I := 0 to High(FReport.Managers) do
    begin
      ListManagers.Items.Add(Format('%s %s',
        [FReport.Managers[I].Name, FReport.Managers[I].InputSummaryBadge]));
      if FReport.Managers[I] = PrevMgr then
        TargetIdx := I;
    end;
    if ListManagers.Items.Count > 0 then
      ListManagers.ItemIndex := TargetIdx;
  finally
    ListManagers.Items.EndUpdate;
  end;

  LblHeader.Caption := Format(
    'Enhanced Input Studio — %d Manager(s) | %d Contexts | %d Bindings | %d Conflict(s)',
    [Length(FReport.Managers), FReport.TotalContexts,
     FReport.TotalBindings, FReport.ConflictCount]);

  RefreshSubLists;
  MemoDiag.Lines.Text := TInputStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintStick.Invalidate;
end;

procedure TInputStudioForm.RefreshSubLists;
var
  M: TCastleInputMapManager;
  I, PrevC, PrevB: Integer;
  C: TInputMappingContextDef;
  B: TInputBindingDef;
  ChordTxt: String;
begin
  PrevC := ListContexts.ItemIndex;
  PrevB := ListBindings.ItemIndex;
  ListContexts.Items.BeginUpdate;
  ListBindings.Items.BeginUpdate;
  try
    ListContexts.Items.Clear;
    ListBindings.Items.Clear;
    M := CurrentManager;
    if M <> nil then
    begin
      for I := 0 to M.Contexts.Count - 1 do
      begin
        C := M.Contexts[I];
        ListContexts.Items.Add(Format('[Prio %d] %s — %s',
          [C.Priority, C.ContextId,
           specialize IfThen<String>(C.Active, 'ACTIVE', 'Inactive')]));
      end;
      if ListContexts.Items.Count > 0 then
        ListContexts.ItemIndex := Clamped(Max(0, PrevC), 0, ListContexts.Items.Count - 1);

      for I := 0 to M.Bindings.Count - 1 do
      begin
        B := M.Bindings[I];
        if B.ChordKeyName <> '' then
          ChordTxt := B.ChordKeyName + '+'
        else
          ChordTxt := '';
        ListBindings.Items.Add(Format('[%s] %s <- %s%s (%s)',
          [B.ContextId, B.ActionId, ChordTxt, B.KeyName,
           InputTriggerToString(B.TriggerKind)]));
      end;
      if ListBindings.Items.Count > 0 then
        ListBindings.ItemIndex := Clamped(Max(0, PrevB), 0, ListBindings.Items.Count - 1);
    end;
  finally
    ListBindings.Items.EndUpdate;
    ListContexts.Items.EndUpdate;
  end;
  ListBindingsClick(nil);
end;

procedure TInputStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TInputStudioForm.ListManagersClick(Sender: TObject);
begin
  RefreshSubLists;
  PaintStick.Invalidate;
end;

procedure TInputStudioForm.ListBindingsClick(Sender: TObject);
var
  M: TCastleInputMapManager;
  Idx: Integer;
begin
  M := CurrentManager;
  Idx := ListBindings.ItemIndex;
  if (M <> nil) and (Idx >= 0) and (Idx < M.Bindings.Count) then
    EditRebindKey.Text := M.Bindings[Idx].KeyName;
  PaintStick.Invalidate;
end;

procedure TInputStudioForm.BtnSpawnActionRpgClick(Sender: TObject);
begin
  TInputStudioHelper.CreateInputManagerInDesign(
    FDesignRoot, FDesignOwner, ipkActionRpgThirdPerson, 'ActionRpgInput');
  NotifyChanged('Spawn Action RPG Enhanced Input Manager');
end;

procedure TInputStudioForm.BtnSpawnTwinStickClick(Sender: TObject);
begin
  TInputStudioHelper.CreateInputManagerInDesign(
    FDesignRoot, FDesignOwner, ipkTwinStickShooter, 'TwinStickInput');
  NotifyChanged('Spawn Twin-Stick Enhanced Input Manager');
end;

procedure TInputStudioForm.BtnSpawnVehicleClick(Sender: TObject);
begin
  TInputStudioHelper.CreateInputManagerInDesign(
    FDesignRoot, FDesignOwner, ipkVehicleRacing, 'VehicleInput');
  NotifyChanged('Spawn Vehicle Racing Enhanced Input Manager');
end;

procedure TInputStudioForm.BtnToggleContextClick(Sender: TObject);
var
  M: TCastleInputMapManager;
  Idx: Integer;
  C: TInputMappingContextDef;
begin
  M := CurrentManager;
  Idx := ListContexts.ItemIndex;
  if (M = nil) or (Idx < 0) or (Idx >= M.Contexts.Count) then
    Exit;
  C := M.Contexts[Idx];
  M.SetContextActive(C.ContextId, not C.Active);
  NotifyChanged('Toggle Input Mapping Context ' + C.ContextId);
end;

procedure TInputStudioForm.BtnApplyRebindClick(Sender: TObject);
var
  M: TCastleInputMapManager;
  Idx: Integer;
begin
  M := CurrentManager;
  Idx := ListBindings.ItemIndex;
  if (M = nil) or (Idx < 0) then
    Exit;
  if M.RebindAtIndex(Idx, EditRebindKey.Text) then
    NotifyChanged('Rebind Input Action Key');
end;

procedure TInputStudioForm.BtnResetRebindsClick(Sender: TObject);
var
  M: TCastleInputMapManager;
begin
  M := CurrentManager;
  if M = nil then
    Exit;
  M.ResetAllRebindsToDefault;
  NotifyChanged('Reset Input Bindings to Defaults');
end;

procedure TInputStudioForm.BtnCopyRebindsJsonClick(Sender: TObject);
var
  M: TCastleInputMapManager;
begin
  M := CurrentManager;
  if M <> nil then
    Clipboard.AsText := M.ExportUserRebindsJson;
end;

procedure TInputStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TInputStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TInputStudioForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TInputStudioForm.PaintStickMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  CX, CY, Rad: Single;
begin
  Rad := Min(PaintStick.Height * 0.36, 110.0);
  CX := 160.0;
  CY := PaintStick.Height * 0.54;
  if Abs(X - CX) <= Rad * 1.3 then
  begin
    FPreviewRawStick := Vector2(
      Clamped((X - CX) / Rad, -1.0, 1.0),
      Clamped((CY - Y) / Rad, -1.0, 1.0));
    if FPreviewRawStick.Length > 1.0 then
      FPreviewRawStick := FPreviewRawStick.Normalize;
    PaintStick.Invalidate;
  end;
end;

procedure TInputStudioForm.PaintStickPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, I, CurveLeft, CurveW, CurveBottom, CurveH, PX, PY, PrevX, PrevY: Integer;
  CX, CY, Rad, InnerDz, OuterSat, ExpVal, T, OutMag: Single;
  M: TCastleInputMapManager;
  B: TInputBindingDef;
  Filtered: TVector2;
begin
  C := PaintStick.Canvas;
  W := PaintStick.Width;
  H := PaintStick.Height;

  C.Brush.Color := RGBToColor(22, 26, 34);
  C.FillRect(0, 0, W, H);

  InnerDz := 0.20;
  OuterSat := 0.95;
  ExpVal := 1.50;
  M := CurrentManager;
  if (M <> nil) and (ListBindings.ItemIndex >= 0) and
     (ListBindings.ItemIndex < M.Bindings.Count) then
  begin
    B := M.Bindings[ListBindings.ItemIndex];
    InnerDz := B.InnerDeadzone;
    OuterSat := B.OuterSaturation;
    ExpVal := B.ResponseExponent;
  end;

  Filtered := EvaluateRadialDeadzone2D(FPreviewRawStick, InnerDz, OuterSat, ExpVal);

  CX := 160.0;
  CY := H * 0.54;
  Rad := Min(H * 0.36, 110.0);

  C.Font.Color := RGBToColor(220, 232, 246);
  C.Brush.Style := bsClear;
  C.TextOut(14, 10, '2D Radial Stick Deadzone (Click Circle to Test Stick Vector)');

  { Outer saturation & unit circles }
  C.Pen.Color := RGBToColor(78, 92, 114);
  C.Ellipse(Round(CX - Rad), Round(CY - Rad), Round(CX + Rad), Round(CY + Rad));
  C.Pen.Color := RGBToColor(226, 88, 84);
  C.Ellipse(Round(CX - Rad * InnerDz), Round(CY - Rad * InnerDz),
            Round(CX + Rad * InnerDz), Round(CY + Rad * InnerDz));

  { Raw stick vector (amber) vs Filtered output vector (emerald) }
  C.Pen.Color := RGBToColor(240, 186, 68);
  C.Pen.Width := 2;
  C.Line(Round(CX), Round(CY),
         Round(CX + FPreviewRawStick.X * Rad), Round(CY - FPreviewRawStick.Y * Rad));

  C.Pen.Color := RGBToColor(68, 224, 148);
  C.Pen.Width := 3;
  C.Line(Round(CX), Round(CY),
         Round(CX + Filtered.X * Rad), Round(CY - Filtered.Y * Rad));
  C.Pen.Width := 1;

  C.TextOut(14, H - 26, Format('Raw=(%.2f, %.2f) -> Filtered=(%.2f, %.2f) | DZ=%.2f Exp=%.2f',
    [FPreviewRawStick.X, FPreviewRawStick.Y, Filtered.X, Filtered.Y, InnerDz, ExpVal]));

  { Response curve plot on the right }
  CurveLeft := 340;
  CurveW := Max(140, W - CurveLeft - 28);
  CurveBottom := H - 44;
  CurveH := Max(100, H - 96);

  C.TextOut(CurveLeft, 10, 'Sensitivity Response Curve (Input Deflection -> Output Magnitude)');
  C.Pen.Color := RGBToColor(64, 74, 90);
  C.Rectangle(CurveLeft, CurveBottom - CurveH, CurveLeft + CurveW, CurveBottom);

  C.Pen.Color := RGBToColor(78, 186, 250);
  C.Pen.Width := 2;
  PrevX := CurveLeft;
  PrevY := CurveBottom;
  for I := 0 to 40 do
  begin
    T := I / 40.0;
    OutMag := EvaluateRadialDeadzone2D(Vector2(T, 0.0), InnerDz, OuterSat, ExpVal).X;
    PX := CurveLeft + Round(T * CurveW);
    PY := CurveBottom - Round(OutMag * CurveH);
    if I > 0 then
      C.Line(PrevX, PrevY, PX, PY);
    PrevX := PX;
    PrevY := PY;
  end;
  C.Pen.Width := 1;
end;

end.
