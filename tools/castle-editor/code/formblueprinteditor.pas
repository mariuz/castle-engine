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

{ Unreal Engine 5.5-style Blueprint Visual Scripting Editor dialog with
  interactive 2D EventGraph & Construction Script node canvas, Exec/Data Bezier
  wires, live execution trace highlighting, node breakpoints, My Blueprint
  variables list, and Blueprint-to-Pascal nativization preview (Phase 381). }
unit FormBlueprintEditor;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleBlueprint, ToolBlueprintEditor;

type
  TBlueprintEditorModifiedCallback = procedure(const UndoComment: String) of object;
  TBlueprintEditorRefreshCallback = procedure of object;

  TBlueprintEditorForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TBlueprintEditorModifiedCallback;
    FOnRefresh: TBlueprintEditorRefreshCallback;

    FActiveBp: TCastleBlueprint;
    FActiveGraph: TBlueprintGraphKind;
    FSelectedNodeId: String;
    FDraggingNode: Boolean;
    FDragOffsetX: Single;
    FDragOffsetY: Single;

    FLblStatus: TLabel;
    FListVariables: TListBox;
    FPaintCanvas: TPaintBox;
    FMemoOutput: TMemo;
    FBtnToggleGraph: TButton;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);
    function NodeBoxWidth(const N: TBlueprintNode): Integer;
    function NodeBoxHeight(const N: TBlueprintNode): Integer;
    function ExecInPinPos(const N: TBlueprintNode; const PinIdx: Integer): TPoint;
    function ExecOutPinPos(const N: TBlueprintNode; const PinIdx: Integer): TPoint;
    function DataInPinPos(const N: TBlueprintNode; const PinIdx: Integer): TPoint;
    function DataOutPinPos(const N: TBlueprintNode; const PinIdx: Integer): TPoint;
    function PinColor(const AType: TBlueprintPinType): TColor;
    function HeaderColor(const AKind: TBlueprintNodeKind): TColor;
    procedure DrawCubicWire(const C: TCanvas; const P0, P1: TPoint;
      const ACol: TColor; const AWidth: Integer);

    procedure PaintBlueprintCanvas(Sender: TObject);
    procedure CanvasMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure CanvasMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure CanvasMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnColonnadeClick(Sender: TObject);
    procedure BtnSpawnDoorClick(Sender: TObject);
    procedure BtnToggleGraphClick(Sender: TObject);
    procedure BtnCompileClick(Sender: TObject);
    procedure BtnRunConstructionClick(Sender: TObject);
    procedure BtnBeginPlayClick(Sender: TObject);
    procedure BtnStepTickClick(Sender: TObject);
    procedure BtnFireOverlapClick(Sender: TObject);
    procedure BtnToggleBreakpointClick(Sender: TObject);
    procedure BtnResumeBreakpointClick(Sender: TObject);
    procedure BtnShowPascalClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TBlueprintEditorModifiedCallback;
      const AOnRefresh: TBlueprintEditorRefreshCallback);
  end;

implementation

constructor TBlueprintEditorForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TBlueprintEditorModifiedCallback;
  const AOnRefresh: TBlueprintEditorRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;
  FActiveGraph := bgkEventGraph;

  Caption := 'Blueprint Visual Scripting Editor — EventGraph, Construction Script & Nativizer (101 UE Studios / 24 MCP)';
  Position := poScreenCenter;
  Width := 1080;
  Height := 700;

  BuildUi;
  FActiveBp := TBlueprintEditorHelper.FindFirstBlueprint(FDesignRoot);
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.BuildUi;
var
  PnlTop, PnlRow2, PnlLeft, PnlBottom: TPanel;
  LblVars: TLabel;
  BtnCol, BtnDoor, BtnComp, BtnCS, BtnBegin, BtnTick, BtnOverlap,
  BtnBp, BtnResume, BtnPas, BtnClose: TButton;
begin
  PnlTop := TPanel.Create(Self);
  PnlTop.Parent := Self;
  PnlTop.Align := alTop;
  PnlTop.Height := 34;
  PnlTop.BevelOuter := bvNone;

  FLblStatus := TLabel.Create(Self);
  FLblStatus.Parent := PnlTop;
  FLblStatus.Left := 10;
  FLblStatus.Top := 9;
  FLblStatus.Caption := 'Blueprint Visual Scripting Editor Ready.';

  PnlRow2 := TPanel.Create(Self);
  PnlRow2.Parent := Self;
  PnlRow2.Align := alTop;
  PnlRow2.Height := 42;
  PnlRow2.BevelOuter := bvNone;

  BtnCol := TButton.Create(Self);
  BtnCol.Parent := PnlRow2;
  BtnCol.SetBounds(8, 6, 128, 30);
  BtnCol.Caption := '+ Colonnade BP';
  BtnCol.OnClick := @BtnSpawnColonnadeClick;

  BtnDoor := TButton.Create(Self);
  BtnDoor.Parent := PnlRow2;
  BtnDoor.SetBounds(140, 6, 125, 30);
  BtnDoor.Caption := '+ Door Timeline';
  BtnDoor.OnClick := @BtnSpawnDoorClick;

  FBtnToggleGraph := TButton.Create(Self);
  FBtnToggleGraph.Parent := PnlRow2;
  FBtnToggleGraph.SetBounds(270, 6, 140, 30);
  FBtnToggleGraph.Caption := 'View: EventGraph';
  FBtnToggleGraph.OnClick := @BtnToggleGraphClick;

  BtnComp := TButton.Create(Self);
  BtnComp.Parent := PnlRow2;
  BtnComp.SetBounds(414, 6, 78, 30);
  BtnComp.Caption := 'Compile';
  BtnComp.OnClick := @BtnCompileClick;

  BtnCS := TButton.Create(Self);
  BtnCS.Parent := PnlRow2;
  BtnCS.SetBounds(496, 6, 98, 30);
  BtnCS.Caption := 'Run Constr.';
  BtnCS.OnClick := @BtnRunConstructionClick;

  BtnBegin := TButton.Create(Self);
  BtnBegin.Parent := PnlRow2;
  BtnBegin.SetBounds(598, 6, 86, 30);
  BtnBegin.Caption := 'BeginPlay';
  BtnBegin.OnClick := @BtnBeginPlayClick;

  BtnTick := TButton.Create(Self);
  BtnTick.Parent := PnlRow2;
  BtnTick.SetBounds(688, 6, 86, 30);
  BtnTick.Caption := 'Tick +0.25s';
  BtnTick.OnClick := @BtnStepTickClick;

  BtnOverlap := TButton.Create(Self);
  BtnOverlap.Parent := PnlRow2;
  BtnOverlap.SetBounds(778, 6, 78, 30);
  BtnOverlap.Caption := 'Overlap';
  BtnOverlap.OnClick := @BtnFireOverlapClick;

  BtnBp := TButton.Create(Self);
  BtnBp.Parent := PnlRow2;
  BtnBp.SetBounds(860, 6, 56, 30);
  BtnBp.Caption := 'BP F9';
  BtnBp.OnClick := @BtnToggleBreakpointClick;

  BtnResume := TButton.Create(Self);
  BtnResume.Parent := PnlRow2;
  BtnResume.SetBounds(920, 6, 66, 30);
  BtnResume.Caption := 'Resume';
  BtnResume.OnClick := @BtnResumeBreakpointClick;

  BtnPas := TButton.Create(Self);
  BtnPas.Parent := PnlRow2;
  BtnPas.SetBounds(990, 6, 82, 30);
  BtnPas.Caption := 'Copy .pas';
  BtnPas.OnClick := @BtnShowPascalClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 165;
  PnlBottom.BevelOuter := bvNone;

  FMemoOutput := TMemo.Create(Self);
  FMemoOutput.Parent := PnlBottom;
  FMemoOutput.Align := alClient;
  FMemoOutput.ScrollBars := ssVertical;
  FMemoOutput.ReadOnly := True;
  FMemoOutput.Font.Name := 'Monospace';

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.Align := alRight;
  BtnClose.Width := 74;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;

  PnlLeft := TPanel.Create(Self);
  PnlLeft.Parent := Self;
  PnlLeft.Align := alLeft;
  PnlLeft.Width := 242;
  PnlLeft.BevelOuter := bvLowered;

  LblVars := TLabel.Create(Self);
  LblVars.Parent := PnlLeft;
  LblVars.Align := alTop;
  LblVars.Caption := '  My Blueprint — Variables';

  FListVariables := TListBox.Create(Self);
  FListVariables.Parent := PnlLeft;
  FListVariables.Align := alClient;

  FPaintCanvas := TPaintBox.Create(Self);
  FPaintCanvas.Parent := Self;
  FPaintCanvas.Align := alClient;
  FPaintCanvas.OnPaint := @PaintBlueprintCanvas;
  FPaintCanvas.OnMouseDown := @CanvasMouseDown;
  FPaintCanvas.OnMouseMove := @CanvasMouseMove;
  FPaintCanvas.OnMouseUp := @CanvasMouseUp;
end;

procedure TBlueprintEditorForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.RefreshFromScene;
var
  I: Integer;
begin
  if (FActiveBp = nil) and (FDesignRoot <> nil) then
    FActiveBp := TBlueprintEditorHelper.FindFirstBlueprint(FDesignRoot);

  if FActiveGraph = bgkConstructionScript then
    FBtnToggleGraph.Caption := 'View: Construction'
  else
    FBtnToggleGraph.Caption := 'View: EventGraph';

  FListVariables.Items.BeginUpdate;
  try
    FListVariables.Items.Clear;
    if FActiveBp <> nil then
      for I := 0 to High(FActiveBp.Variables) do
        FListVariables.Items.Add(Format('%s : %s = %s', [
          FActiveBp.Variables[I].VarName,
          TCastleBlueprint.PinTypeName(FActiveBp.Variables[I].VarType),
          FActiveBp.Variables[I].CurrentValue.AsText]));
  finally
    FListVariables.Items.EndUpdate;
  end;

  if FActiveBp <> nil then
  begin
    FLblStatus.Caption := FActiveBp.Name + '  ' + FActiveBp.BlueprintSummaryBadge;
    FMemoOutput.Lines.BeginUpdate;
    try
      FMemoOutput.Lines.Clear;
      FMemoOutput.Lines.Add('=== Compiler & Execution Watch ===');
      if FActiveBp.CompileErrors.Count = 0 then
        FMemoOutput.Lines.Add('[OK] Blueprint Compiled Up-To-Date (0 Errors).')
      else
        FMemoOutput.Lines.AddStrings(FActiveBp.CompileErrors);
      if FActiveBp.PrintLog.Count > 0 then
      begin
        FMemoOutput.Lines.Add('--- Print Log ---');
        FMemoOutput.Lines.AddStrings(FActiveBp.PrintLog);
      end;
      if FActiveBp.WatchTrace.Count > 0 then
      begin
        FMemoOutput.Lines.Add('--- Wire Watch Trace ---');
        for I := Max(0, FActiveBp.WatchTrace.Count - 8) to FActiveBp.WatchTrace.Count - 1 do
          FMemoOutput.Lines.Add('  ' + FActiveBp.WatchTrace[I]);
      end;
    finally
      FMemoOutput.Lines.EndUpdate;
    end;
  end else
  begin
    FLblStatus.Caption := 'No TCastleBlueprint in design yet — click "+ Colonnade BP" or "+ Door Timeline".';
    FMemoOutput.Text := TBlueprintEditorHelper.GenerateMarkdownReport(FDesignRoot, nil);
  end;

  FPaintCanvas.Invalidate;
end;

function TBlueprintEditorForm.NodeBoxWidth(const N: TBlueprintNode): Integer;
begin
  if TCastleBlueprint.NodeIsPure(N.Kind) then
    Result := 188
  else
    Result := 208;
end;

function TBlueprintEditorForm.NodeBoxHeight(const N: TBlueprintNode): Integer;
var
  LeftRows, RightRows: Integer;
begin
  LeftRows := TCastleBlueprint.NodeExecInCount(N.Kind) + TCastleBlueprint.NodeDataInCount(N.Kind);
  RightRows := TCastleBlueprint.NodeExecOutCount(N.Kind) + TCastleBlueprint.NodeDataOutCount(N.Kind);
  Result := 32 + Max(1, Max(LeftRows, RightRows)) * 20 + 8;
end;

function TBlueprintEditorForm.ExecInPinPos(const N: TBlueprintNode; const PinIdx: Integer): TPoint;
begin
  Result := Point(Round(N.PosX), Round(N.PosY) + 38 + PinIdx * 20);
end;

function TBlueprintEditorForm.ExecOutPinPos(const N: TBlueprintNode; const PinIdx: Integer): TPoint;
begin
  Result := Point(Round(N.PosX) + NodeBoxWidth(N), Round(N.PosY) + 38 + PinIdx * 20);
end;

function TBlueprintEditorForm.DataInPinPos(const N: TBlueprintNode; const PinIdx: Integer): TPoint;
var
  ExecRows: Integer;
begin
  ExecRows := TCastleBlueprint.NodeExecInCount(N.Kind);
  Result := Point(Round(N.PosX), Round(N.PosY) + 38 + (ExecRows + PinIdx) * 20);
end;

function TBlueprintEditorForm.DataOutPinPos(const N: TBlueprintNode; const PinIdx: Integer): TPoint;
var
  ExecRows: Integer;
begin
  ExecRows := TCastleBlueprint.NodeExecOutCount(N.Kind);
  Result := Point(Round(N.PosX) + NodeBoxWidth(N), Round(N.PosY) + 38 + (ExecRows + PinIdx) * 20);
end;

function TBlueprintEditorForm.PinColor(const AType: TBlueprintPinType): TColor;
begin
  case AType of
    bptExec:   Result := RGBToColor(245, 245, 245);
    bptBool:   Result := RGBToColor(215, 48, 48);
    bptInt:    Result := RGBToColor(38, 210, 195);
    bptFloat:  Result := RGBToColor(110, 228, 78);
    bptString: Result := RGBToColor(232, 72, 205);
    bptVec3:   Result := RGBToColor(245, 196, 48);
    bptObject: Result := RGBToColor(64, 168, 245);
  end;
end;

function TBlueprintEditorForm.HeaderColor(const AKind: TBlueprintNodeKind): TColor;
begin
  if TCastleBlueprint.NodeIsEvent(AKind) then
    Result := RGBToColor(156, 32, 36)
  else if TCastleBlueprint.NodeIsLatent(AKind) then
    Result := RGBToColor(158, 112, 24)
  else if AKind in [bnkGetVariable, bnkSetVariable] then
    Result := RGBToColor(26, 112, 118)
  else if TCastleBlueprint.NodeIsPure(AKind) then
    Result := RGBToColor(42, 118, 56)
  else if AKind in [bnkBranch, bnkSequence, bnkForLoop, bnkDoOnce, bnkFlipFlop, bnkGate] then
    Result := RGBToColor(78, 84, 94)
  else
    Result := RGBToColor(36, 86, 152);
end;

procedure TBlueprintEditorForm.DrawCubicWire(const C: TCanvas;
  const P0, P1: TPoint; const ACol: TColor; const AWidth: Integer);
var
  Pts: array[0..16] of TPoint;
  TangentDX, T, OneMinusT: Single;
  C1X, C2X: Single;
  S: Integer;
begin
  TangentDX := Max(48.0, Abs(P1.X - P0.X) * 0.5);
  C1X := P0.X + TangentDX;
  C2X := P1.X - TangentDX;
  for S := 0 to 16 do
  begin
    T := S / 16.0;
    OneMinusT := 1.0 - T;
    Pts[S].X := Round(
      OneMinusT * OneMinusT * OneMinusT * P0.X +
      3 * OneMinusT * OneMinusT * T * C1X +
      3 * OneMinusT * T * T * C2X +
      T * T * T * P1.X);
    Pts[S].Y := Round(
      OneMinusT * OneMinusT * OneMinusT * P0.Y +
      3 * OneMinusT * OneMinusT * T * P0.Y +
      3 * OneMinusT * T * T * P1.Y +
      T * T * T * P1.Y);
  end;
  C.Pen.Color := ACol;
  C.Pen.Width := AWidth;
  C.Polyline(Pts);
end;

procedure TBlueprintEditorForm.PaintBlueprintCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, GX, GY, I, P, FromIdx, ToIdx, VarIdx: Integer;
  N: TBlueprintNode;
  BoxR: TRect;
  TitleText, TraceKey: String;
  PinPt: TPoint;
  VarT, PType: TBlueprintPinType;
  WireHot: Boolean;
begin
  C := FPaintCanvas.Canvas;
  W := FPaintCanvas.Width;
  H := FPaintCanvas.Height;

  { 1. Dark UE5 Blueprint background & dual-scale grid }
  C.Brush.Color := RGBToColor(28, 30, 34);
  C.FillRect(0, 0, W, H);

  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(38, 41, 47);
  GX := 0;
  while GX < W do begin C.Line(GX, 0, GX, H); Inc(GX, 16); end;
  GY := 0;
  while GY < H do begin C.Line(0, GY, W, GY); Inc(GY, 16); end;

  C.Pen.Color := RGBToColor(52, 56, 64);
  GX := 0;
  while GX < W do begin C.Line(GX, 0, GX, H); Inc(GX, 64); end;
  GY := 0;
  while GY < H do begin C.Line(0, GY, W, GY); Inc(GY, 64); end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(78, 86, 98);
  if FActiveGraph = bgkConstructionScript then
    C.TextOut(W - 230, H - 26, 'BLUEPRINT: CONSTRUCTION SCRIPT')
  else
    C.TextOut(W - 195, H - 26, 'BLUEPRINT: EVENT GRAPH');

  if FActiveBp = nil then Exit;

  { 2. Draw Data Wires }
  for I := 0 to High(FActiveBp.DataLinks) do
    if FActiveBp.DataLinks[I].Graph = FActiveGraph then
    begin
      FromIdx := FActiveBp.FindNodeIndex(FActiveBp.DataLinks[I].FromNodeId);
      ToIdx := FActiveBp.FindNodeIndex(FActiveBp.DataLinks[I].ToNodeId);
      if (FromIdx >= 0) and (ToIdx >= 0) then
      begin
        VarT := bptFloat;
        VarIdx := FActiveBp.FindVariableIndex(FActiveBp.Nodes[FromIdx].MemberName);
        if VarIdx >= 0 then VarT := FActiveBp.Variables[VarIdx].VarType;
        PType := TCastleBlueprint.NodeDataOutType(
          FActiveBp.Nodes[FromIdx].Kind, FActiveBp.DataLinks[I].FromDataPin, VarT);
        DrawCubicWire(C,
          DataOutPinPos(FActiveBp.Nodes[FromIdx], FActiveBp.DataLinks[I].FromDataPin),
          DataInPinPos(FActiveBp.Nodes[ToIdx], FActiveBp.DataLinks[I].ToDataPin),
          PinColor(PType), 2);
      end;
    end;

  { 3. Draw White / Glowing-Gold Exec Wires }
  for I := 0 to High(FActiveBp.ExecLinks) do
    if FActiveBp.ExecLinks[I].Graph = FActiveGraph then
    begin
      FromIdx := FActiveBp.FindNodeIndex(FActiveBp.ExecLinks[I].FromNodeId);
      ToIdx := FActiveBp.FindNodeIndex(FActiveBp.ExecLinks[I].ToNodeId);
      if (FromIdx >= 0) and (ToIdx >= 0) then
      begin
        TraceKey := Format('%s:%d->%s:%d',
          [FActiveBp.ExecLinks[I].FromNodeId, FActiveBp.ExecLinks[I].FromExecPin,
           FActiveBp.ExecLinks[I].ToNodeId, FActiveBp.ExecLinks[I].ToExecPin]);
        WireHot := FActiveBp.ActiveExecTrace.IndexOf(TraceKey) >= 0;
        if WireHot then
          DrawCubicWire(C,
            ExecOutPinPos(FActiveBp.Nodes[FromIdx], FActiveBp.ExecLinks[I].FromExecPin),
            ExecInPinPos(FActiveBp.Nodes[ToIdx], FActiveBp.ExecLinks[I].ToExecPin),
            RGBToColor(255, 178, 36), 4)
        else
          DrawCubicWire(C,
            ExecOutPinPos(FActiveBp.Nodes[FromIdx], FActiveBp.ExecLinks[I].FromExecPin),
            ExecInPinPos(FActiveBp.Nodes[ToIdx], FActiveBp.ExecLinks[I].ToExecPin),
            RGBToColor(242, 242, 242), 3);
      end;
    end;

  { 4. Draw Blueprint Nodes }
  for I := 0 to High(FActiveBp.Nodes) do
    if FActiveBp.Nodes[I].Graph = FActiveGraph then
    begin
      N := FActiveBp.Nodes[I];
      BoxR := Rect(Round(N.PosX), Round(N.PosY),
        Round(N.PosX) + NodeBoxWidth(N), Round(N.PosY) + NodeBoxHeight(N));

      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(42, 45, 52);
      if SameText(FActiveBp.PausedNodeId, N.NodeId) then
      begin
        C.Pen.Color := RGBToColor(255, 92, 36);
        C.Pen.Width := 3;
      end else if SameText(FSelectedNodeId, N.NodeId) then
      begin
        C.Pen.Color := RGBToColor(255, 198, 42);
        C.Pen.Width := 2;
      end else
      begin
        C.Pen.Color := RGBToColor(18, 20, 24);
        C.Pen.Width := 1;
      end;
      C.RoundRect(BoxR, 8, 8);

      { Colored UE5 header bar }
      C.Brush.Color := HeaderColor(N.Kind);
      C.FillRect(BoxR.Left + 2, BoxR.Top + 2, BoxR.Right - 2, BoxR.Top + 25);

      TitleText := TCastleBlueprint.NodeKindTitle(N.Kind);
      if N.MemberName <> '' then
        TitleText := TitleText + ': ' + N.MemberName;
      C.Brush.Style := bsClear;
      C.Font.Color := clWhite;
      C.TextOut(BoxR.Left + 8, BoxR.Top + 5, Copy(TitleText, 1, 29));

      { Red Breakpoint Badge }
      if N.HasBreakpoint then
      begin
        C.Brush.Style := bsSolid;
        C.Brush.Color := RGBToColor(225, 36, 36);
        C.Pen.Color := clWhite;
        C.Ellipse(BoxR.Right - 18, BoxR.Top - 6, BoxR.Right - 4, BoxR.Top + 8);
      end;

      VarT := bptFloat;
      VarIdx := FActiveBp.FindVariableIndex(N.MemberName);
      if VarIdx >= 0 then VarT := FActiveBp.Variables[VarIdx].VarType;

      { Exec Input Pins }
      for P := 0 to TCastleBlueprint.NodeExecInCount(N.Kind) - 1 do
      begin
        PinPt := ExecInPinPos(N, P);
        C.Brush.Style := bsSolid;
        C.Brush.Color := clWhite;
        C.Pen.Color := clWhite;
        C.Rectangle(PinPt.X - 4, PinPt.Y - 4, PinPt.X + 5, PinPt.Y + 5);
        C.Brush.Style := bsClear;
        C.Font.Color := RGBToColor(220, 224, 230);
        C.TextOut(PinPt.X + 8, PinPt.Y - 7, TCastleBlueprint.NodeExecInName(N.Kind, P));
      end;

      { Data Input Pins }
      for P := 0 to TCastleBlueprint.NodeDataInCount(N.Kind) - 1 do
      begin
        PinPt := DataInPinPos(N, P);
        PType := TCastleBlueprint.NodeDataInType(N.Kind, P, VarT);
        C.Brush.Style := bsSolid;
        C.Brush.Color := PinColor(PType);
        C.Pen.Color := PinColor(PType);
        C.Ellipse(PinPt.X - 4, PinPt.Y - 4, PinPt.X + 5, PinPt.Y + 5);
        C.Brush.Style := bsClear;
        C.Font.Color := RGBToColor(200, 206, 214);
        C.TextOut(PinPt.X + 8, PinPt.Y - 7, TCastleBlueprint.NodeDataInName(N.Kind, P));
      end;

      { Exec Output Pins }
      for P := 0 to TCastleBlueprint.NodeExecOutCount(N.Kind) - 1 do
      begin
        PinPt := ExecOutPinPos(N, P);
        C.Brush.Style := bsSolid;
        C.Brush.Color := clWhite;
        C.Pen.Color := clWhite;
        C.Rectangle(PinPt.X - 5, PinPt.Y - 4, PinPt.X + 4, PinPt.Y + 5);
        C.Brush.Style := bsClear;
        C.Font.Color := RGBToColor(220, 224, 230);
        TitleText := TCastleBlueprint.NodeExecOutName(N.Kind, P);
        C.TextOut(PinPt.X - 10 - C.TextWidth(TitleText), PinPt.Y - 7, TitleText);
      end;

      { Data Output Pins }
      for P := 0 to TCastleBlueprint.NodeDataOutCount(N.Kind) - 1 do
      begin
        PinPt := DataOutPinPos(N, P);
        PType := TCastleBlueprint.NodeDataOutType(N.Kind, P, VarT);
        C.Brush.Style := bsSolid;
        C.Brush.Color := PinColor(PType);
        C.Pen.Color := PinColor(PType);
        C.Ellipse(PinPt.X - 5, PinPt.Y - 4, PinPt.X + 4, PinPt.Y + 5);
        C.Brush.Style := bsClear;
        C.Font.Color := RGBToColor(200, 206, 214);
        TitleText := TCastleBlueprint.NodeDataOutName(N.Kind, P);
        C.TextOut(PinPt.X - 10 - C.TextWidth(TitleText), PinPt.Y - 7, TitleText);
      end;
    end;
end;

procedure TBlueprintEditorForm.CanvasMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  N: TBlueprintNode;
begin
  if (FActiveBp = nil) or (Button <> mbLeft) then Exit;
  for I := High(FActiveBp.Nodes) downto 0 do
    if FActiveBp.Nodes[I].Graph = FActiveGraph then
    begin
      N := FActiveBp.Nodes[I];
      if (X >= Round(N.PosX)) and (X <= Round(N.PosX) + NodeBoxWidth(N)) and
         (Y >= Round(N.PosY)) and (Y <= Round(N.PosY) + NodeBoxHeight(N)) then
      begin
        FSelectedNodeId := N.NodeId;
        FDraggingNode := True;
        FDragOffsetX := X - N.PosX;
        FDragOffsetY := Y - N.PosY;
        FPaintCanvas.Invalidate;
        Exit;
      end;
    end;
  FSelectedNodeId := '';
  FPaintCanvas.Invalidate;
end;

procedure TBlueprintEditorForm.CanvasMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingNode and (FActiveBp <> nil) and (FSelectedNodeId <> '') then
  begin
    FActiveBp.SetNodePosition(FSelectedNodeId,
      Max(8.0, X - FDragOffsetX), Max(8.0, Y - FDragOffsetY));
    FPaintCanvas.Invalidate;
  end;
end;

procedure TBlueprintEditorForm.CanvasMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingNode then
  begin
    FDraggingNode := False;
    NotifyChanged('Move Blueprint Node');
  end;
end;

procedure TBlueprintEditorForm.BtnSpawnColonnadeClick(Sender: TObject);
begin
  FActiveBp := TBlueprintEditorHelper.SpawnBlueprintPresetInDesign(
    FDesignRoot, FDesignOwner, bppPillarRowConstructionAndSpinPickup, Vector3(0, 0, 0));
  NotifyChanged('Spawn Colonnade & Pickup Blueprint');
end;

procedure TBlueprintEditorForm.BtnSpawnDoorClick(Sender: TObject);
begin
  FActiveBp := TBlueprintEditorHelper.SpawnBlueprintPresetInDesign(
    FDesignRoot, FDesignOwner, bppSlidingDoorTimelineAndGate, Vector3(0, 0, -4));
  FActiveGraph := bgkEventGraph;
  NotifyChanged('Spawn Sliding Door Timeline Blueprint');
end;

procedure TBlueprintEditorForm.BtnToggleGraphClick(Sender: TObject);
begin
  if FActiveGraph = bgkEventGraph then
    FActiveGraph := bgkConstructionScript
  else
    FActiveGraph := bgkEventGraph;
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.BtnCompileClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.CompileBlueprint;
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.BtnRunConstructionClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.RunConstructionScript;
  NotifyChanged('Run Blueprint Construction Script');
end;

procedure TBlueprintEditorForm.BtnBeginPlayClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.ExecuteBeginPlay;
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.BtnStepTickClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.StepBlueprintTick(0.25);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.BtnFireOverlapClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.ExecuteActorBeginOverlap('PlayerHero');
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.BtnToggleBreakpointClick(Sender: TObject);
begin
  if (FActiveBp = nil) or (FSelectedNodeId = '') then Exit;
  FActiveBp.ToggleNodeBreakpoint(FSelectedNodeId);
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.BtnResumeBreakpointClick(Sender: TObject);
begin
  if FActiveBp = nil then Exit;
  FActiveBp.ResumeFromBreakpoint;
  RefreshFromScene;
end;

procedure TBlueprintEditorForm.BtnShowPascalClick(Sender: TObject);
var
  PasCode: String;
begin
  if FActiveBp = nil then Exit;
  PasCode := FActiveBp.GeneratePascalUnit;
  Clipboard.AsText := PasCode;
  FMemoOutput.Text := PasCode;
end;

end.
