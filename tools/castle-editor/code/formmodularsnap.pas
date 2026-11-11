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

{ Interactive Modular Socket Snapping, Room/Dungeon Grammar & Kitbash
  Assembler Studio (@link(TModularSnapForm)) with 1-click room spawning,
  180-degree opposing socket snapping, seeded zero-overlap PCG dungeon
  generation, and 2D XZ floorplan blueprint preview (Phase 301). }
unit FormModularSnap;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleBoxes, CastleUtils, CastleTransform,
  CastleModularSnap, ToolModularSnap;

type
  TModularSnapModifiedCallback = procedure(const AComment: String) of object;
  TModularSnapRefreshViewportCallback = procedure of object;

  TModularSnapForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FSelectedComponent: TComponent;
    FSpawnOrigin: TVector3;
    FOnModified: TModularSnapModifiedCallback;
    FOnRefreshViewport: TModularSnapRefreshViewportCallback;

    FSummary: TModularSnapSummary;

    ButtonSpawnHall: TButton;
    ButtonSpawnCorridor: TButton;
    ButtonSpawnCorner: TButton;
    ButtonSpawnCross: TButton;
    ButtonSpawnChamber: TButton;
    ButtonSnapSelected: TButton;
    ButtonCopyMarkdown: TButton;

    ListBoxPieces: TListBox;
    EditTargetCount: TEdit;
    EditSeed: TEdit;
    ButtonGenerateDungeon: TButton;
    ButtonClearGenerated: TButton;
    MemoDiagnostics: TMemo;

    PaintBoxFloorplan: TPaintBox;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    function ActivePiece: TCastleTransform;
    procedure RefreshSceneScan(const ASelectPiece: TCastleTransform = nil);
    procedure NotifyModified(const AComment: String);
    procedure SpawnAndAutoSnapPiece(const AKind: TModularPieceKind; const ALabel: String);

    procedure ButtonSpawnHallClick(Sender: TObject);
    procedure ButtonSpawnCorridorClick(Sender: TObject);
    procedure ButtonSpawnCornerClick(Sender: TObject);
    procedure ButtonSpawnCrossClick(Sender: TObject);
    procedure ButtonSpawnChamberClick(Sender: TObject);
    procedure ButtonSnapSelectedClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);

    procedure ListBoxPiecesClick(Sender: TObject);
    procedure ButtonGenerateDungeonClick(Sender: TObject);
    procedure ButtonClearGeneratedClick(Sender: TObject);
    procedure PaintBoxFloorplanPaint(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
      const ASpawnOrigin: TVector3;
      const AOnModified: TModularSnapModifiedCallback;
      const AOnRefreshViewport: TModularSnapRefreshViewportCallback);
  end;

implementation

{ TModularSnapForm ----------------------------------------------------------- }

constructor TModularSnapForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
  const ASpawnOrigin: TVector3;
  const AOnModified: TModularSnapModifiedCallback;
  const AOnRefreshViewport: TModularSnapRefreshViewportCallback);
var
  InitPiece: TCastleTransform;
begin
  inherited CreateNew(AOwner, 1);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FSelectedComponent := ASelectedComponent;
  FSpawnOrigin := ASpawnOrigin;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Modular Socket Snapping, Room/Dungeon Grammar & Kitbash Studio';
  Width := 1060;
  Height := 700;
  Position := poMainFormCenter;
  Constraints.MinWidth := 900;
  Constraints.MinHeight := 600;

  BuildUi;

  InitPiece := nil;
  if ASelectedComponent is TCastleTransform then
    InitPiece := TCastleTransform(ASelectedComponent);
  RefreshSceneScan(InitPiece);
end;

procedure TModularSnapForm.BuildUi;
var
  PanelTop, PanelBottom, PanelBody, PanelLeft, PanelRight: TPanel;
  YPos: Integer;
  LblList, LblGrammar, LblPlan: TLabel;

  function MakeTopBtn(const ACaption: String; const ALeft, AWidth: Integer;
    const AOnClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := PanelTop;
    Result.Left := ALeft;
    Result.Top := 8;
    Result.Width := AWidth;
    Result.Height := 30;
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
  end;

  function AddLabeledEdit(const AParent: TWinControl; const ATitle: String;
    var ATop: Integer; const ADefault: String): TEdit;
  var
    Lbl: TLabel;
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := AParent;
    Lbl.Left := 10;
    Lbl.Top := ATop + 4;
    Lbl.Caption := ATitle;

    Result := TEdit.Create(Self);
    Result.Parent := AParent;
    Result.Left := 170;
    Result.Top := ATop;
    Result.Width := 142;
    Result.Text := ADefault;
    Inc(ATop, 28);
  end;

begin
  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 46;
  PanelTop.BevelOuter := bvNone;

  ButtonSpawnHall := MakeTopBtn('+ Entry Hall', 8, 108, @ButtonSpawnHallClick);
  ButtonSpawnCorridor := MakeTopBtn('+ Corridor', 120, 100, @ButtonSpawnCorridorClick);
  ButtonSpawnCorner := MakeTopBtn('+ Corner L', 224, 100, @ButtonSpawnCornerClick);
  ButtonSpawnCross := MakeTopBtn('+ 4-Way Cross', 328, 114, @ButtonSpawnCrossClick);
  ButtonSpawnChamber := MakeTopBtn('+ Chamber', 446, 100, @ButtonSpawnChamberClick);
  ButtonSnapSelected := MakeTopBtn('Snap Piece -> Nearest Socket', 552, 204, @ButtonSnapSelectedClick);
  ButtonCopyMarkdown := MakeTopBtn('Copy Report', 762, 112, @ButtonCopyMarkdownClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.Left := 12;
  LabelStatus.Top := 12;
  LabelStatus.Caption := 'Spawn modular rooms/corridors with auto-opposing 180-deg doorway snapping or generate a seeded dungeon.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Anchors := [akTop, akRight];
  ButtonClose.Left := Width - 104;
  ButtonClose.Top := 6;
  ButtonClose.Width := 90;
  ButtonClose.Height := 30;
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 326;
  PanelLeft.BevelOuter := bvLowered;

  LblList := TLabel.Create(Self);
  LblList.Parent := PanelLeft;
  LblList.Left := 10;
  LblList.Top := 8;
  LblList.Caption := 'Modular Pieces in Scene:';

  ListBoxPieces := TListBox.Create(Self);
  ListBoxPieces.Parent := PanelLeft;
  ListBoxPieces.Left := 10;
  ListBoxPieces.Top := 28;
  ListBoxPieces.Width := 302;
  ListBoxPieces.Height := 150;
  ListBoxPieces.OnClick := @ListBoxPiecesClick;

  LblGrammar := TLabel.Create(Self);
  LblGrammar.Parent := PanelLeft;
  LblGrammar.Left := 10;
  LblGrammar.Top := 188;
  LblGrammar.Caption := 'Seeded PCG Dungeon Grammar Generator:';

  YPos := 210;
  EditTargetCount := AddLabeledEdit(PanelLeft, 'Target Room Count:', YPos, '8');
  EditSeed := AddLabeledEdit(PanelLeft, 'Random Seed:', YPos, '1337');

  ButtonGenerateDungeon := TButton.Create(Self);
  ButtonGenerateDungeon.Parent := PanelLeft;
  ButtonGenerateDungeon.Left := 10;
  ButtonGenerateDungeon.Top := YPos + 4;
  ButtonGenerateDungeon.Width := 184;
  ButtonGenerateDungeon.Height := 32;
  ButtonGenerateDungeon.Caption := 'Generate Seeded Dungeon';
  ButtonGenerateDungeon.OnClick := @ButtonGenerateDungeonClick;

  ButtonClearGenerated := TButton.Create(Self);
  ButtonClearGenerated.Parent := PanelLeft;
  ButtonClearGenerated.Left := 200;
  ButtonClearGenerated.Top := YPos + 4;
  ButtonClearGenerated.Width := 112;
  ButtonClearGenerated.Height := 32;
  ButtonClearGenerated.Caption := 'Clear PCG';
  ButtonClearGenerated.OnClick := @ButtonClearGeneratedClick;
  Inc(YPos, 46);

  MemoDiagnostics := TMemo.Create(Self);
  MemoDiagnostics.Parent := PanelLeft;
  MemoDiagnostics.Left := 10;
  MemoDiagnostics.Top := YPos;
  MemoDiagnostics.Width := 302;
  MemoDiagnostics.Height := PanelLeft.Height - YPos - 10;
  MemoDiagnostics.Anchors := [akTop, akLeft, akRight, akBottom];
  MemoDiagnostics.ReadOnly := true;
  MemoDiagnostics.ScrollBars := ssVertical;

  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := PanelBody;
  PanelRight.Align := alClient;
  PanelRight.BevelOuter := bvNone;

  LblPlan := TLabel.Create(Self);
  LblPlan.Parent := PanelRight;
  LblPlan.Left := 12;
  LblPlan.Top := 8;
  LblPlan.Caption := 'Top-Down XZ Modular Floorplan Blueprint (Emerald = Open Socket, Gold = Connected Doorway):';

  PaintBoxFloorplan := TPaintBox.Create(Self);
  PaintBoxFloorplan.Parent := PanelRight;
  PaintBoxFloorplan.Left := 12;
  PaintBoxFloorplan.Top := 28;
  PaintBoxFloorplan.Width := PanelRight.Width - 24;
  PaintBoxFloorplan.Height := PanelRight.Height - 40;
  PaintBoxFloorplan.Anchors := [akTop, akLeft, akRight, akBottom];
  PaintBoxFloorplan.OnPaint := @PaintBoxFloorplanPaint;
end;

function TModularSnapForm.ActivePiece: TCastleTransform;
var
  Idx: Integer;
begin
  Result := nil;
  Idx := ListBoxPieces.ItemIndex;
  if (Idx >= 0) and (Idx <= High(FSummary.Pieces)) then
    Result := FSummary.Pieces[Idx];
end;

procedure TModularSnapForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TModularSnapForm.RefreshSceneScan(const ASelectPiece: TCastleTransform);
var
  I, SelIdx: Integer;
  Beh: TCastleModularPieceBehavior;
begin
  FSummary := TModularSnapHelper.ScanModularPiecesAndSockets(FRootComponent);

  ListBoxPieces.Items.BeginUpdate;
  try
    ListBoxPieces.Items.Clear;
    SelIdx := -1;
    for I := 0 to High(FSummary.Pieces) do
    begin
      Beh := FSummary.Pieces[I].FindBehavior(TCastleModularPieceBehavior) as TCastleModularPieceBehavior;
      if Beh <> nil then
        ListBoxPieces.Items.Add(Format('%s  %s', [FSummary.Pieces[I].Name, Beh.PieceSummaryBadge]))
      else
        ListBoxPieces.Items.Add(FSummary.Pieces[I].Name);
      if FSummary.Pieces[I] = ASelectPiece then
        SelIdx := I;
    end;
    if (SelIdx < 0) and (Length(FSummary.Pieces) > 0) then
      SelIdx := 0;
    ListBoxPieces.ItemIndex := SelIdx;
  finally
    ListBoxPieces.Items.EndUpdate;
  end;

  MemoDiagnostics.Text := TModularSnapHelper.BuildMarkdownReport(FRootComponent);
  PaintBoxFloorplan.Invalidate;
end;

procedure TModularSnapForm.SpawnAndAutoSnapPiece(const AKind: TModularPieceKind;
  const ALabel: String);
var
  P: TCastleTransform;
  Snapped: Boolean;
begin
  P := TModularSnapHelper.CreateModularPieceInDesign(
    FRootComponent, FDesignOwner, AKind, FSpawnOrigin);
  if P = nil then
    Exit;
  Snapped := TModularSnapHelper.SnapPieceToNearestOpenSocket(P, FRootComponent, 80.0);
  NotifyModified('Spawn Modular Piece: ' + ALabel);
  RefreshSceneScan(P);
  if Snapped then
    LabelStatus.Caption := Format('Spawned "%s" and snapped flush onto nearest open doorway socket.', [P.Name])
  else
    LabelStatus.Caption := Format('Spawned anchor piece "%s" at (%.1f, %.1f, %.1f).',
      [P.Name, P.Translation.X, P.Translation.Y, P.Translation.Z]);
end;

procedure TModularSnapForm.ButtonSpawnHallClick(Sender: TObject);
begin
  SpawnAndAutoSnapPiece(mpkEntryHall, 'Entry Hall');
end;

procedure TModularSnapForm.ButtonSpawnCorridorClick(Sender: TObject);
begin
  SpawnAndAutoSnapPiece(mpkCorridorStraight, 'Straight Corridor');
end;

procedure TModularSnapForm.ButtonSpawnCornerClick(Sender: TObject);
begin
  SpawnAndAutoSnapPiece(mpkCornerTurnL, 'Corner Turn L');
end;

procedure TModularSnapForm.ButtonSpawnCrossClick(Sender: TObject);
begin
  SpawnAndAutoSnapPiece(mpkCrossJunction, '4-Way Cross Junction');
end;

procedure TModularSnapForm.ButtonSpawnChamberClick(Sender: TObject);
begin
  SpawnAndAutoSnapPiece(mpkTreasureChamber, 'Treasure Chamber');
end;

procedure TModularSnapForm.ButtonSnapSelectedClick(Sender: TObject);
var
  P: TCastleTransform;
begin
  P := ActivePiece;
  if (P = nil) and (FSelectedComponent is TCastleTransform) then
    P := TCastleTransform(FSelectedComponent);
  if P = nil then
    Exit;

  if TModularSnapHelper.SnapPieceToNearestOpenSocket(P, FRootComponent, 100.0) then
  begin
    NotifyModified('Snap Modular Piece ' + P.Name);
    RefreshSceneScan(P);
    LabelStatus.Caption := Format('Snapped "%s" onto nearest compatible open socket.', [P.Name]);
  end else
    LabelStatus.Caption := Format('No compatible unoccupied socket found for "%s".', [P.Name]);
end;

procedure TModularSnapForm.ButtonCopyMarkdownClick(Sender: TObject);
var
  Rep: String;
begin
  Rep := TModularSnapHelper.BuildMarkdownReport(FRootComponent);
  Clipboard.AsText := Rep;
  MemoDiagnostics.Text := Rep;
  LabelStatus.Caption := 'Copied Modular Socket & Dungeon Grammar report to clipboard.';
end;

procedure TModularSnapForm.ListBoxPiecesClick(Sender: TObject);
begin
  PaintBoxFloorplan.Invalidate;
end;

procedure TModularSnapForm.ButtonGenerateDungeonClick(Sender: TObject);
var
  Cnt, SeedVal, Placed: Integer;
begin
  Cnt := StrToIntDef(EditTargetCount.Text, 8);
  SeedVal := StrToIntDef(EditSeed.Text, 1337);
  Placed := TModularSnapHelper.GenerateSeededDungeonLayout(
    FRootComponent, FDesignOwner, Cnt, SeedVal);
  NotifyModified(Format('Generate Seeded Modular Dungeon (%d rooms, seed %d)', [Placed, SeedVal]));
  RefreshSceneScan(nil);
  LabelStatus.Caption := Format('Generated %d connected zero-overlap modular rooms (Seed=%d).',
    [Placed, SeedVal]);
end;

procedure TModularSnapForm.ButtonClearGeneratedClick(Sender: TObject);
var
  Removed: Integer;
begin
  Removed := TModularSnapHelper.ClearGeneratedDungeonPieces(FRootComponent);
  NotifyModified('Clear Generated Modular Dungeon');
  RefreshSceneScan(nil);
  LabelStatus.Caption := Format('Cleared %d generated dungeon piece(s).', [Removed]);
end;

procedure TModularSnapForm.PaintBoxFloorplanPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, I: Integer;
  TotalBox, B: TBox3D;
  Beh: TCastleModularPieceBehavior;
  SpanX, SpanZ, ScalePx, CX, CZ: Single;
  X0, Z0, X1, Z1, SX, SZ, TipX, TipZ: Integer;
  SPos, SDir, SUp: TVector3;

  function WorldXToPx(const WX: Single): Integer;
  begin
    Result := (W div 2) + Round((WX - CX) * ScalePx);
  end;

  function WorldZToPx(const WZ: Single): Integer;
  begin
    Result := (H div 2) + Round((WZ - CZ) * ScalePx);
  end;

begin
  Cv := PaintBoxFloorplan.Canvas;
  W := PaintBoxFloorplan.Width;
  H := PaintBoxFloorplan.Height;
  Cv.Brush.Color := RGBToColor(16, 20, 28);
  Cv.FillRect(0, 0, W, H);

  if Length(FSummary.Pieces) = 0 then
  begin
    Cv.Font.Color := clSilver;
    Cv.TextOut(20, H div 2 - 8,
      'Click "Generate Seeded Dungeon" or "+ Entry Hall" above to preview the 2D XZ modular blueprint.');
    Exit;
  end;

  TotalBox := TBox3D.Empty;
  for I := 0 to High(FSummary.Pieces) do
  begin
    Beh := FSummary.Pieces[I].FindBehavior(TCastleModularPieceBehavior) as TCastleModularPieceBehavior;
    if Beh <> nil then
      TotalBox.Include(Beh.ComputeHierarchyWorldBox);
  end;

  if TotalBox.IsEmpty then
    TotalBox := Box3D(Vector3(-10, 0, -10), Vector3(10, 4, 10));

  CX := TotalBox.Center.X;
  CZ := TotalBox.Center.Z;
  SpanX := Max(12.0, TotalBox.SizeX + 6.0);
  SpanZ := Max(12.0, TotalBox.SizeZ + 6.0);
  ScalePx := Min((W - 48) / SpanX, (H - 48) / SpanZ);

  { 1. Draw modular room footprints }
  for I := 0 to High(FSummary.Pieces) do
  begin
    Beh := FSummary.Pieces[I].FindBehavior(TCastleModularPieceBehavior) as TCastleModularPieceBehavior;
    if Beh = nil then
      Continue;
    B := Beh.ComputeHierarchyWorldBox;
    X0 := WorldXToPx(B.Data[0].X);
    Z0 := WorldZToPx(B.Data[0].Z);
    X1 := WorldXToPx(B.Data[1].X);
    Z1 := WorldZToPx(B.Data[1].Z);

    if FSummary.Pieces[I] = ActivePiece then
    begin
      Cv.Brush.Color := RGBToColor(52, 82, 128);
      Cv.Pen.Color := RGBToColor(120, 210, 255);
      Cv.Pen.Width := 2;
    end else
    begin
      Cv.Brush.Color := RGBToColor(34, 48, 68);
      Cv.Pen.Color := RGBToColor(95, 125, 165);
      Cv.Pen.Width := 1;
    end;
    Cv.Rectangle(X0, Z0, X1, Z1);

    Cv.Brush.Style := bsClear;
    Cv.Font.Color := clWhite;
    Cv.TextOut(X0 + 4, Z0 + 4, FSummary.Pieces[I].Name);
    Cv.Brush.Style := bsSolid;
  end;

  { 2. Draw sockets & outward direction ticks }
  for I := 0 to High(FSummary.Sockets) do
  begin
    FSummary.Sockets[I].GetHierarchyWorldFrame(SPos, SDir, SUp);
    SX := WorldXToPx(SPos.X);
    SZ := WorldZToPx(SPos.Z);
    TipX := WorldXToPx(SPos.X + SDir.X * 1.1);
    TipZ := WorldZToPx(SPos.Z + SDir.Z * 1.1);

    if FSummary.Sockets[I].Occupied then
    begin
      Cv.Pen.Color := RGBToColor(255, 205, 65);
      Cv.Brush.Color := RGBToColor(255, 205, 65);
    end else
    begin
      Cv.Pen.Color := RGBToColor(65, 235, 155);
      Cv.Brush.Color := RGBToColor(65, 235, 155);
    end;
    Cv.Pen.Width := 2;
    Cv.Line(SX, SZ, TipX, TipZ);
    Cv.Ellipse(SX - 4, SZ - 4, SX + 4, SZ + 4);
  end;
end;

procedure TModularSnapForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
