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

{ Unreal Engine 5.5-style Behavior Tree & Blackboard Visual Editor dialog
  featuring a top-down hierarchical composite/task node canvas, blue Decorator
  & Observer-Abort banners, green periodic Service banners, ExecutionIndex
  priority badges, a live Blackboard key-value inspector, and interactive
  LoS/Tick testing (Phase 384 — 104 UE Studios / 27 MCP). }
unit FormBehaviorTree;

{$I castleconf.inc}

interface

uses
  SysUtils, Classes, Math,
  Controls, Forms, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleUtils, CastleVectors, CastleTransform,
  CastleBehaviorTree, ToolBehaviorTree;

type
  TBehaviorTreeModifiedCallback = procedure(const UndoComment: String) of object;
  TBehaviorTreeRefreshCallback = procedure of object;

  TBehaviorTreeForm = class(TForm)
  private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TBehaviorTreeModifiedCallback;
    FOnRefresh: TBehaviorTreeRefreshCallback;

    FActiveTree: TCastleBehaviorTree;
    FSelectedNodeId: String;
    FDraggingNode: Boolean;
    FDragOffsetX: Single;
    FDragOffsetY: Single;

    FLblStatus: TLabel;
    FPaintTree: TPaintBox;
    FListBlackboard: TListBox;
    FMemoLog: TMemo;

    procedure BuildUi;
    procedure RefreshFromScene;
    procedure NotifyChanged(const AComment: String);
    function NodeBoxHeight(const N: TBehaviorTreeNode): Integer;
    function HeaderColor(const AKind: TBehaviorTreeNodeKind): TColor;

    procedure PaintTreeCanvas(Sender: TObject);
    procedure TreeMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure TreeMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);

    procedure BtnSpawnGuardClick(Sender: TObject);
    procedure BtnSpawnParallelClick(Sender: TObject);
    procedure BtnSpotEnemyClick(Sender: TObject);
    procedure BtnLoseSightClick(Sender: TObject);
    procedure BtnTickTreeClick(Sender: TObject);
    procedure BtnResetTreeClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TBehaviorTreeModifiedCallback;
      const AOnRefresh: TBehaviorTreeRefreshCallback);
  end;

implementation

const
  BtNodeW = 188;

constructor TBehaviorTreeForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TBehaviorTreeModifiedCallback;
  const AOnRefresh: TBehaviorTreeRefreshCallback);
begin
  inherited CreateNew(AOwner);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefresh := AOnRefresh;

  Caption := 'Behavior Tree & Blackboard Visual Editor — Observer Aborts & Services (104 UE Studios / 27 MCP)';
  Position := poScreenCenter;
  Width := 1160;
  Height := 700;

  BuildUi;
  FActiveTree := TBehaviorTreeHelper.FindFirstBehaviorTree(FDesignRoot);
  RefreshFromScene;
end;

procedure TBehaviorTreeForm.BuildUi;
var
  PnlTop, PnlToolbar, PnlRight, PnlBottom: TPanel;
  LblBb: TLabel;
  BtnGuard, BtnPar, BtnSpot, BtnLose, BtnTick, BtnReset, BtnCopy, BtnClose: TButton;
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
  FLblStatus.Caption := 'Behavior Tree & Blackboard Editor Ready.';

  PnlToolbar := TPanel.Create(Self);
  PnlToolbar.Parent := Self;
  PnlToolbar.Align := alTop;
  PnlToolbar.Height := 42;
  PnlToolbar.BevelOuter := bvNone;

  BtnGuard := TButton.Create(Self);
  BtnGuard.Parent := PnlToolbar;
  BtnGuard.SetBounds(8, 6, 168, 30);
  BtnGuard.Caption := '+ Tactical Guard BT';
  BtnGuard.OnClick := @BtnSpawnGuardClick;

  BtnPar := TButton.Create(Self);
  BtnPar.Parent := PnlToolbar;
  BtnPar.SetBounds(180, 6, 148, 30);
  BtnPar.Caption := '+ SimpleParallel BT';
  BtnPar.OnClick := @BtnSpawnParallelClick;

  BtnSpot := TButton.Create(Self);
  BtnSpot.Parent := PnlToolbar;
  BtnSpot.SetBounds(332, 6, 146, 30);
  BtnSpot.Caption := 'Spot Enemy (LoS=T)';
  BtnSpot.OnClick := @BtnSpotEnemyClick;

  BtnLose := TButton.Create(Self);
  BtnLose.Parent := PnlToolbar;
  BtnLose.SetBounds(482, 6, 146, 30);
  BtnLose.Caption := 'Lose Sight (LoS=F)';
  BtnLose.OnClick := @BtnLoseSightClick;

  BtnTick := TButton.Create(Self);
  BtnTick.Parent := PnlToolbar;
  BtnTick.SetBounds(632, 6, 118, 30);
  BtnTick.Caption := 'Tick BT +0.25s';
  BtnTick.OnClick := @BtnTickTreeClick;

  BtnReset := TButton.Create(Self);
  BtnReset.Parent := PnlToolbar;
  BtnReset.SetBounds(754, 6, 94, 30);
  BtnReset.Caption := 'Reset BT';
  BtnReset.OnClick := @BtnResetTreeClick;

  BtnCopy := TButton.Create(Self);
  BtnCopy.Parent := PnlToolbar;
  BtnCopy.SetBounds(852, 6, 126, 30);
  BtnCopy.Caption := 'Copy Markdown';
  BtnCopy.OnClick := @BtnCopyMarkdownClick;

  PnlBottom := TPanel.Create(Self);
  PnlBottom.Parent := Self;
  PnlBottom.Align := alBottom;
  PnlBottom.Height := 160;
  PnlBottom.BevelOuter := bvNone;

  FMemoLog := TMemo.Create(Self);
  FMemoLog.Parent := PnlBottom;
  FMemoLog.Align := alClient;
  FMemoLog.ScrollBars := ssVertical;
  FMemoLog.ReadOnly := True;
  FMemoLog.Font.Name := 'Monospace';

  BtnClose := TButton.Create(Self);
  BtnClose.Parent := PnlBottom;
  BtnClose.Align := alRight;
  BtnClose.Width := 74;
  BtnClose.Caption := 'Close';
  BtnClose.ModalResult := mrOk;

  PnlRight := TPanel.Create(Self);
  PnlRight.Parent := Self;
  PnlRight.Align := alRight;
  PnlRight.Width := 255;
  PnlRight.BevelOuter := bvLowered;

  LblBb := TLabel.Create(Self);
  LblBb.Parent := PnlRight;
  LblBb.Align := alTop;
  LblBb.Caption := '  Blackboard Keys';

  FListBlackboard := TListBox.Create(Self);
  FListBlackboard.Parent := PnlRight;
  FListBlackboard.Align := alClient;

  FPaintTree := TPaintBox.Create(Self);
  FPaintTree.Parent := Self;
  FPaintTree.Align := alClient;
  FPaintTree.OnPaint := @PaintTreeCanvas;
  FPaintTree.OnMouseDown := @TreeMouseDown;
  FPaintTree.OnMouseMove := @TreeMouseMove;
  FPaintTree.OnMouseUp := @TreeMouseUp;
end;

procedure TBehaviorTreeForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefresh) then
    FOnRefresh();
  RefreshFromScene;
end;

procedure TBehaviorTreeForm.RefreshFromScene;
var
  I: Integer;
begin
  if (FActiveTree = nil) and (FDesignRoot <> nil) then
    FActiveTree := TBehaviorTreeHelper.FindFirstBehaviorTree(FDesignRoot);

  FListBlackboard.Items.BeginUpdate;
  try
    FListBlackboard.Items.Clear;
    if FActiveTree <> nil then
      for I := 0 to High(FActiveTree.Blackboard) do
        FListBlackboard.Items.Add(Format('%s = %s',
          [FActiveTree.Blackboard[I].KeyName, FActiveTree.Blackboard[I].ValueAsText]));
  finally
    FListBlackboard.Items.EndUpdate;
  end;

  if FActiveTree <> nil then
    FLblStatus.Caption := FActiveTree.Name + '  ' + FActiveTree.BehaviorTreeSummaryBadge
  else
    FLblStatus.Caption := 'No TCastleBehaviorTree in design yet — click "+ Tactical Guard BT".';

  FMemoLog.Text := TBehaviorTreeHelper.GenerateMarkdownReport(FDesignRoot, FActiveTree);
  FPaintTree.Invalidate;
end;

function TBehaviorTreeForm.NodeBoxHeight(const N: TBehaviorTreeNode): Integer;
begin
  Result := 54;
  if N.DecoratorOp <> bdopNone then Inc(Result, 20);
  if Trim(N.ServiceName) <> '' then Inc(Result, 20);
end;

function TBehaviorTreeForm.HeaderColor(const AKind: TBehaviorTreeNodeKind): TColor;
begin
  case AKind of
    btnRoot:           Result := RGBToColor(92, 96, 104);
    btnSelector,
    btnSequence:       Result := RGBToColor(68, 76, 88);
    btnSimpleParallel: Result := RGBToColor(96, 56, 148);
  else
    Result := RGBToColor(126, 52, 138);
  end;
end;

procedure TBehaviorTreeForm.PaintTreeCanvas(Sender: TObject);
var
  C: TCanvas;
  W, H, GX, GY, I, PIdx, TopCursor: Integer;
  N, ParentN: TBehaviorTreeNode;
  BoxR: TRect;
  BadgeTxt: String;
begin
  C := FPaintTree.Canvas;
  W := FPaintTree.Width;
  H := FPaintTree.Height;

  C.Brush.Color := RGBToColor(28, 30, 35);
  C.FillRect(0, 0, W, H);

  C.Pen.Width := 1;
  C.Pen.Color := RGBToColor(40, 44, 52);
  GX := 0;
  while GX < W do begin C.Line(GX, 0, GX, H); Inc(GX, 20); end;
  GY := 0;
  while GY < H do begin C.Line(0, GY, W, GY); Inc(GY, 20); end;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(88, 100, 116);
  C.TextOut(W - 210, H - 24, 'UE 5.5 BEHAVIOR TREE');

  if FActiveTree = nil then Exit;

  { Parent -> Child vertical links }
  for I := 0 to High(FActiveTree.Nodes) do
  begin
    N := FActiveTree.Nodes[I];
    if N.ParentNodeId <> '' then
    begin
      PIdx := FActiveTree.FindNodeIndex(N.ParentNodeId);
      if PIdx >= 0 then
      begin
        ParentN := FActiveTree.Nodes[PIdx];
        if N.LastStatus = btsRunning then
        begin
          C.Pen.Color := RGBToColor(255, 202, 48);
          C.Pen.Width := 4;
        end else
        begin
          C.Pen.Color := RGBToColor(186, 194, 206);
          C.Pen.Width := 2;
        end;
        C.Line(
          Round(ParentN.PosX) + BtNodeW div 2, Round(ParentN.PosY) + NodeBoxHeight(ParentN),
          Round(N.PosX) + BtNodeW div 2, Round(N.PosY));
      end;
    end;
  end;

  { Nodes }
  for I := 0 to High(FActiveTree.Nodes) do
  begin
    N := FActiveTree.Nodes[I];
    BoxR := Rect(Round(N.PosX), Round(N.PosY),
      Round(N.PosX) + BtNodeW, Round(N.PosY) + NodeBoxHeight(N));

    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(44, 48, 56);
    if N.LastStatus = btsRunning then
    begin
      C.Pen.Color := RGBToColor(255, 202, 48);
      C.Pen.Width := 3;
    end else if SameText(FSelectedNodeId, N.NodeId) then
    begin
      C.Pen.Color := RGBToColor(96, 224, 255);
      C.Pen.Width := 2;
    end else
    begin
      C.Pen.Color := RGBToColor(18, 20, 24);
      C.Pen.Width := 1;
    end;
    C.RoundRect(BoxR, 6, 6);

    TopCursor := BoxR.Top + 2;

    { Optional Blue Decorator Sub-Banner }
    if N.DecoratorOp <> bdopNone then
    begin
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(32, 92, 168);
      C.FillRect(BoxR.Left + 2, TopCursor, BoxR.Right - 2, TopCursor + 19);
      C.Brush.Style := bsClear;
      C.Font.Color := clWhite;
      C.TextOut(BoxR.Left + 6, TopCursor + 2,
        Copy(Format('BB:%s [%s]', [N.DecoratorKey, TCastleBehaviorTree.AbortModeName(N.ObserverAborts)]), 1, 26));
      Inc(TopCursor, 20);
    end;

    { Node Kind Header }
    C.Brush.Style := bsSolid;
    C.Brush.Color := HeaderColor(N.Kind);
    C.FillRect(BoxR.Left + 2, TopCursor, BoxR.Right - 2, TopCursor + 22);
    C.Brush.Style := bsClear;
    C.Font.Color := clWhite;
    C.TextOut(BoxR.Left + 6, TopCursor + 3, Copy(TCastleBehaviorTree.NodeKindTitle(N.Kind), 1, 22));
    Inc(TopCursor, 24);

    C.Font.Color := RGBToColor(216, 224, 234);
    C.TextOut(BoxR.Left + 6, TopCursor, Copy(N.Title, 1, 25));
    Inc(TopCursor, 20);

    { Optional Green Periodic Service Sub-Banner }
    if Trim(N.ServiceName) <> '' then
    begin
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(36, 122, 68);
      C.FillRect(BoxR.Left + 2, BoxR.Bottom - 21, BoxR.Right - 2, BoxR.Bottom - 2);
      C.Brush.Style := bsClear;
      C.Font.Color := clWhite;
      C.TextOut(BoxR.Left + 6, BoxR.Bottom - 19,
        Copy(Format('%s (%.2fs)', [N.ServiceName, N.ServiceIntervalSec]), 1, 26));
    end;

    { ExecutionIndex badge circle at upper-right }
    if N.ExecutionIndex >= 0 then
    begin
      BadgeTxt := IntToStr(N.ExecutionIndex);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(58, 64, 74);
      C.Pen.Color := clWhite;
      C.Pen.Width := 1;
      C.Ellipse(BoxR.Right - 20, BoxR.Top - 8, BoxR.Right + 2, BoxR.Top + 14);
      C.Brush.Style := bsClear;
      C.Font.Color := clWhite;
      C.TextOut(BoxR.Right - 14, BoxR.Top - 5, BadgeTxt);
    end;
  end;
end;

procedure TBehaviorTreeForm.TreeMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  N: TBehaviorTreeNode;
begin
  if (FActiveTree = nil) or (Button <> mbLeft) then Exit;
  for I := High(FActiveTree.Nodes) downto 0 do
  begin
    N := FActiveTree.Nodes[I];
    if (X >= Round(N.PosX)) and (X <= Round(N.PosX) + BtNodeW) and
       (Y >= Round(N.PosY)) and (Y <= Round(N.PosY) + NodeBoxHeight(N)) then
    begin
      FSelectedNodeId := N.NodeId;
      FDraggingNode := True;
      FDragOffsetX := X - N.PosX;
      FDragOffsetY := Y - N.PosY;
      FPaintTree.Invalidate;
      Exit;
    end;
  end;
  FSelectedNodeId := '';
  FPaintTree.Invalidate;
end;

procedure TBehaviorTreeForm.TreeMouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
begin
  if FDraggingNode and (FActiveTree <> nil) and (FSelectedNodeId <> '') then
  begin
    FActiveTree.SetNodePosition(FSelectedNodeId,
      Max(8.0, X - FDragOffsetX), Max(8.0, Y - FDragOffsetY));
    FPaintTree.Invalidate;
  end;
end;

procedure TBehaviorTreeForm.TreeMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if FDraggingNode then
  begin
    FDraggingNode := False;
    NotifyChanged('Move Behavior Tree Node');
  end;
end;

procedure TBehaviorTreeForm.BtnSpawnGuardClick(Sender: TObject);
begin
  FActiveTree := TBehaviorTreeHelper.SpawnBehaviorTreePresetInDesign(
    FDesignRoot, FDesignOwner, btpTacticalGuardObserverAborts, Vector3(0, 0, 0));
  NotifyChanged('Spawn Tactical Guard Behavior Tree');
end;

procedure TBehaviorTreeForm.BtnSpawnParallelClick(Sender: TObject);
begin
  FActiveTree := TBehaviorTreeHelper.SpawnBehaviorTreePresetInDesign(
    FDesignRoot, FDesignOwner, btpSimpleParallelSuppressAndMove, Vector3(4, 0, 0));
  NotifyChanged('Spawn SimpleParallel Behavior Tree');
end;

procedure TBehaviorTreeForm.BtnSpotEnemyClick(Sender: TObject);
begin
  if FActiveTree = nil then Exit;
  FActiveTree.SetBlackboardBool('HasLineOfSight', True);
  FActiveTree.TickBehaviorTree(0.10);
  NotifyChanged('Behavior Tree Spot Enemy');
end;

procedure TBehaviorTreeForm.BtnLoseSightClick(Sender: TObject);
begin
  if FActiveTree = nil then Exit;
  FActiveTree.SetBlackboardBool('HasLineOfSight', False);
  FActiveTree.TickBehaviorTree(0.10);
  NotifyChanged('Behavior Tree Lose Sight');
end;

procedure TBehaviorTreeForm.BtnTickTreeClick(Sender: TObject);
begin
  if FActiveTree = nil then Exit;
  FActiveTree.TickBehaviorTree(0.25);
  if Assigned(FOnRefresh) then FOnRefresh();
  RefreshFromScene;
end;

procedure TBehaviorTreeForm.BtnResetTreeClick(Sender: TObject);
begin
  if FActiveTree = nil then Exit;
  FActiveTree.ResetBehaviorTree;
  RefreshFromScene;
end;

procedure TBehaviorTreeForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := FMemoLog.Text;
end;

end.
