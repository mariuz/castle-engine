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

{ Interactive CSG / Boolean Greybox Architecture & Procedural Room/Arch/Stair
  Mesh Modeler Studio (@link(TCsgStudioForm)) featuring 1-click architectural
  presets, ordered Union/Subtract/Intersect brush stack editing, live Top-Down
  XZ + Side Z-Y blueprint cross-section visualization, triplanar UV & collider
  sync controls, and Markdown report export (Phase 309). }
unit FormCsgStudio;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Spin, Graphics, Clipbrd,
  CastleVectors, CastleTransform, CastleUtils,
  CastleCsgModeler, ToolCsgStudio;

type
  TCsgStudioModifiedCallback = procedure(const AComment: String) of object;
  TCsgStudioRefreshViewportCallback = procedure of object;

  TCsgStudioForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FSelectedTransform: TCastleTransform;
    FSpawnPos: TVector3;
    FOnModified: TCsgStudioModifiedCallback;
    FOnRefreshViewport: TCsgStudioRefreshViewportCallback;

    FReport: TCsgStudioAuditReport;
    FSyncingUi: Boolean;

    LblHeader: TLabel;
    ListModelers: TListBox;
    ListBrushes: TListBox;
    PaintBlueprint: TPaintBox;

    EditBrushId: TEdit;
    CheckBrushEnabled: TCheckBox;
    ComboOp: TComboBox;
    ComboShape: TComboBox;
    SpinCenterX, SpinCenterY, SpinCenterZ: TFloatSpinEdit;
    SpinSizeX, SpinSizeY, SpinSizeZ: TFloatSpinEdit;
    SpinYawDeg: TFloatSpinEdit;
    SpinSegments: TSpinEdit;
    SpinUvScale: TFloatSpinEdit;
    CheckCollider: TCheckBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function CurrentModeler: TCastleCsgModeler;
    function SelectedBrushIndex: Integer;
    procedure RefreshAll;
    procedure RefreshBrushList;
    procedure PopulateInspector;
    procedure NotifyChanged(const AComment: String);

    procedure ListModelersClick(Sender: TObject);
    procedure ListBrushesClick(Sender: TObject);
    procedure BtnSpawnHollowRoomClick(Sender: TObject);
    procedure BtnSpawnVaultCrossClick(Sender: TObject);
    procedure BtnSpawnMezzanineClick(Sender: TObject);
    procedure BtnSpawnCloisterClick(Sender: TObject);
    procedure BtnAddUnionBoxClick(Sender: TObject);
    procedure BtnSubArchDoorClick(Sender: TObject);
    procedure BtnAddStairwellClick(Sender: TObject);
    procedure BtnAddRampClick(Sender: TObject);
    procedure BtnMoveUpClick(Sender: TObject);
    procedure BtnMoveDownClick(Sender: TObject);
    procedure BtnDeleteBrushClick(Sender: TObject);
    procedure BtnApplyBrushClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure PaintBlueprintPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const ASelectedTransform: TCastleTransform;
      const ASpawnPos: TVector3;
      const AOnModified: TCsgStudioModifiedCallback;
      const AOnRefreshViewport: TCsgStudioRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TCsgStudioForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const ASelectedTransform: TCastleTransform;
  const ASpawnPos: TVector3;
  const AOnModified: TCsgStudioModifiedCallback;
  const AOnRefreshViewport: TCsgStudioRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FSelectedTransform := ASelectedTransform;
  FSpawnPos := ASpawnPos;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'CSG / Boolean Greybox Architecture & Procedural Mesh Modeler Studio';
  Width := 1120;
  Height := 720;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TCsgStudioForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TCsgStudioForm.BuildUi;
var
  PanelTop, PanelBody, PanelLeft, PanelCenter, PanelRight, PanelBottom: TPanel;
  RowPresets, RowBrushActions: TPanel;
  BtnRoom, BtnCross, BtnMezz, BtnCloister: TButton;
  BtnAddBox, BtnCarveArch, BtnAddStairs, BtnAddRamp: TButton;
  BtnUp, BtnDown, BtnDel, BtnApply, BtnCopyMd, BtnClose: TButton;
  Y: Integer;

  function MakeBtn(AParent: TWinControl; const ACaption: String;
    const ALeft, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.Left := ALeft;
    Result.Top := 6;
    Result.Width := AWidth;
    Result.Height := 28;
    Result.OnClick := AClick;
  end;

  procedure AddFloatRow(AParent: TWinControl; const ALabel: String;
    out ASpin: TFloatSpinEdit; const AMin, AMax, AStep, ADef: Double);
  var
    L: TLabel;
  begin
    L := TLabel.Create(Self);
    L.Parent := AParent;
    L.Left := 10;
    L.Top := Y + 4;
    L.Caption := ALabel;

    ASpin := TFloatSpinEdit.Create(Self);
    ASpin.Parent := AParent;
    ASpin.Left := 142;
    ASpin.Top := Y;
    ASpin.Width := 136;
    ASpin.MinValue := AMin;
    ASpin.MaxValue := AMax;
    ASpin.Increment := AStep;
    ASpin.DecimalPlaces := 2;
    ASpin.Value := ADef;
    Inc(Y, 28);
  end;

var
  Lbl: TLabel;
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
  LblHeader.Caption := 'CSG Boolean Modeler — Spawn Architectural Presets or Stack Union / Subtract / Intersect Brushes';

  RowPresets := TPanel.Create(Self);
  RowPresets.Parent := PanelTop;
  RowPresets.Left := 8;
  RowPresets.Top := 30;
  RowPresets.Width := 1096;
  RowPresets.Height := 38;
  RowPresets.BevelOuter := bvNone;

  BtnRoom := MakeBtn(RowPresets, '+ Hollow Room + Arch', 4, 170, @BtnSpawnHollowRoomClick);
  BtnCross := MakeBtn(RowPresets, '+ Vaulted Cross Hall', 180, 170, @BtnSpawnVaultCrossClick);
  BtnMezz := MakeBtn(RowPresets, '+ Mezzanine + Stairs', 356, 170, @BtnSpawnMezzanineClick);
  BtnCloister := MakeBtn(RowPresets, '+ Courtyard Cloister', 532, 170, @BtnSpawnCloisterClick);
  if (BtnRoom = nil) or (BtnCross = nil) or (BtnMezz = nil) or (BtnCloister = nil) then ;

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  BtnCopyMd := MakeBtn(PanelBottom, 'Copy Markdown Report', 12, 190, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 990, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];
  if BtnCopyMd = nil then ;

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  { Left panel: Modeler list + Brush stack }
  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 300;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.Left := 10;
  Lbl.Top := 6;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'CSG Modeler Nodes in Scene:';

  ListModelers := TListBox.Create(Self);
  ListModelers.Parent := PanelLeft;
  ListModelers.Left := 10;
  ListModelers.Top := 26;
  ListModelers.Width := 280;
  ListModelers.Height := 130;
  ListModelers.OnClick := @ListModelersClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.Left := 10;
  Lbl.Top := 164;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Ordered Boolean Brush Stack:';

  ListBrushes := TListBox.Create(Self);
  ListBrushes.Parent := PanelLeft;
  ListBrushes.Left := 10;
  ListBrushes.Top := 184;
  ListBrushes.Width := 280;
  ListBrushes.Height := 260;
  ListBrushes.OnClick := @ListBrushesClick;

  RowBrushActions := TPanel.Create(Self);
  RowBrushActions.Parent := PanelLeft;
  RowBrushActions.Left := 10;
  RowBrushActions.Top := 450;
  RowBrushActions.Width := 280;
  RowBrushActions.Height := 140;
  RowBrushActions.BevelOuter := bvNone;

  BtnAddBox := MakeBtn(RowBrushActions, '+ Union Box', 0, 136, @BtnAddUnionBoxClick);
  BtnCarveArch := MakeBtn(RowBrushActions, '- Carve Arch Door', 142, 136, @BtnSubArchDoorClick);

  BtnAddStairs := TButton.Create(Self);
  BtnAddStairs.Parent := RowBrushActions;
  BtnAddStairs.Caption := '+ Add Stairwell';
  BtnAddStairs.SetBounds(0, 38, 136, 28);
  BtnAddStairs.OnClick := @BtnAddStairwellClick;

  BtnAddRamp := TButton.Create(Self);
  BtnAddRamp.Parent := RowBrushActions;
  BtnAddRamp.Caption := '+ Add Ramp Wedge';
  BtnAddRamp.SetBounds(142, 38, 136, 28);
  BtnAddRamp.OnClick := @BtnAddRampClick;

  BtnUp := TButton.Create(Self);
  BtnUp.Parent := RowBrushActions;
  BtnUp.Caption := 'Up';
  BtnUp.SetBounds(0, 72, 86, 28);
  BtnUp.OnClick := @BtnMoveUpClick;

  BtnDown := TButton.Create(Self);
  BtnDown.Parent := RowBrushActions;
  BtnDown.Caption := 'Down';
  BtnDown.SetBounds(94, 72, 86, 28);
  BtnDown.OnClick := @BtnMoveDownClick;

  BtnDel := TButton.Create(Self);
  BtnDel.Parent := RowBrushActions;
  BtnDel.Caption := 'Delete';
  BtnDel.SetBounds(188, 72, 90, 28);
  BtnDel.OnClick := @BtnDeleteBrushClick;
  if (BtnAddBox = nil) or (BtnCarveArch = nil) then ;

  { Right panel: Brush & Modeler Inspector }
  PanelRight := TPanel.Create(Self);
  PanelRight.Parent := PanelBody;
  PanelRight.Align := alRight;
  PanelRight.Width := 296;
  PanelRight.BevelOuter := bvNone;

  Y := 8;
  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.Left := 10;
  Lbl.Top := Y;
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Selected Brush & Mesh Inspector';
  Inc(Y, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.Left := 10;
  Lbl.Top := Y + 4;
  Lbl.Caption := 'Brush ID:';
  EditBrushId := TEdit.Create(Self);
  EditBrushId.Parent := PanelRight;
  EditBrushId.SetBounds(142, Y, 136, 24);
  Inc(Y, 28);

  CheckBrushEnabled := TCheckBox.Create(Self);
  CheckBrushEnabled.Parent := PanelRight;
  CheckBrushEnabled.Left := 10;
  CheckBrushEnabled.Top := Y;
  CheckBrushEnabled.Caption := 'Brush Enabled in Stack';
  CheckBrushEnabled.Checked := True;
  Inc(Y, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.Left := 10;
  Lbl.Top := Y + 4;
  Lbl.Caption := 'Boolean Op:';
  ComboOp := TComboBox.Create(Self);
  ComboOp.Parent := PanelRight;
  ComboOp.Style := csDropDownList;
  ComboOp.SetBounds(142, Y, 136, 24);
  ComboOp.Items.Add('Union (+ Solid)');
  ComboOp.Items.Add('Subtract (- Carve)');
  ComboOp.Items.Add('Intersect (& Overlap)');
  ComboOp.ItemIndex := 0;
  Inc(Y, 28);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.Left := 10;
  Lbl.Top := Y + 4;
  Lbl.Caption := 'Brush Shape:';
  ComboShape := TComboBox.Create(Self);
  ComboShape.Parent := PanelRight;
  ComboShape.Style := csDropDownList;
  ComboShape.SetBounds(142, Y, 136, 24);
  ComboShape.Items.Add('Box');
  ComboShape.Items.Add('Cylinder');
  ComboShape.Items.Add('ArchCorridor');
  ComboShape.Items.Add('RampWedge');
  ComboShape.Items.Add('Stairwell');
  ComboShape.ItemIndex := 0;
  Inc(Y, 28);

  AddFloatRow(PanelRight, 'Center X (m):', SpinCenterX, -500.0, 500.0, 0.25, 0.0);
  AddFloatRow(PanelRight, 'Center Y (m):', SpinCenterY, -500.0, 500.0, 0.25, 1.5);
  AddFloatRow(PanelRight, 'Center Z (m):', SpinCenterZ, -500.0, 500.0, 0.25, 0.0);
  AddFloatRow(PanelRight, 'Size X (m):', SpinSizeX, 0.1, 200.0, 0.25, 4.0);
  AddFloatRow(PanelRight, 'Size Y (m):', SpinSizeY, 0.1, 200.0, 0.25, 3.0);
  AddFloatRow(PanelRight, 'Size Z (m):', SpinSizeZ, 0.1, 200.0, 0.25, 4.0);
  AddFloatRow(PanelRight, 'Yaw Angle (deg):', SpinYawDeg, -360.0, 360.0, 15.0, 0.0);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelRight;
  Lbl.Left := 10;
  Lbl.Top := Y + 4;
  Lbl.Caption := 'Segments / Steps:';
  SpinSegments := TSpinEdit.Create(Self);
  SpinSegments.Parent := PanelRight;
  SpinSegments.SetBounds(142, Y, 136, 24);
  SpinSegments.MinValue := 2;
  SpinSegments.MaxValue := 32;
  SpinSegments.Value := 8;
  Inc(Y, 28);

  AddFloatRow(PanelRight, 'Triplanar UV (/m):', SpinUvScale, 0.05, 10.0, 0.05, 0.5);

  CheckCollider := TCheckBox.Create(Self);
  CheckCollider.Parent := PanelRight;
  CheckCollider.Left := 10;
  CheckCollider.Top := Y;
  CheckCollider.Caption := 'Sync Triangle Octree Collider';
  CheckCollider.Checked := True;
  Inc(Y, 26);

  BtnApply := TButton.Create(Self);
  BtnApply.Parent := PanelRight;
  BtnApply.SetBounds(10, Y, 268, 32);
  BtnApply.Caption := 'Apply Brush & Rebuild CSG Mesh';
  BtnApply.OnClick := @BtnApplyBrushClick;

  { Center panel: Blueprint visualizer + diagnostics }
  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintBlueprint := TPaintBox.Create(Self);
  PaintBlueprint.Parent := PanelCenter;
  PaintBlueprint.Align := alTop;
  PaintBlueprint.Height := 390;
  PaintBlueprint.OnPaint := @PaintBlueprintPaint;

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelCenter;
  MemoDiag.Align := alClient;
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;
  MemoDiag.Font.Name := 'Monospace';
end;

function TCsgStudioForm.CurrentModeler: TCastleCsgModeler;
var
  Idx: Integer;
begin
  Result := nil;
  if (FReport = nil) or (Length(FReport.Modelers) = 0) then
    Exit;
  Idx := ListModelers.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.Modelers)) then
    Result := FReport.Modelers[Idx];
end;

function TCsgStudioForm.SelectedBrushIndex: Integer;
var
  M: TCastleCsgModeler;
begin
  Result := -1;
  M := CurrentModeler;
  if M = nil then
    Exit;
  if (ListBrushes.ItemIndex >= 0) and (ListBrushes.ItemIndex < M.Brushes.Count) then
    Result := ListBrushes.ItemIndex;
end;

procedure TCsgStudioForm.RefreshAll;
var
  PrevModeler: TCastleCsgModeler;
  I, TargetIdx: Integer;
begin
  PrevModeler := CurrentModeler;
  if (PrevModeler = nil) and (FSelectedTransform is TCastleCsgModeler) then
    PrevModeler := TCastleCsgModeler(FSelectedTransform);

  FreeAndNil(FReport);
  FReport := TCsgStudioHelper.ScanDesign(FDesignRoot, FDesignOwner);

  ListModelers.Items.BeginUpdate;
  try
    ListModelers.Items.Clear;
    TargetIdx := 0;
    for I := 0 to High(FReport.Modelers) do
    begin
      ListModelers.Items.Add(Format('%s %s',
        [FReport.Modelers[I].Name, FReport.Modelers[I].CsgSummaryBadge]));
      if FReport.Modelers[I] = PrevModeler then
        TargetIdx := I;
    end;
    if ListModelers.Items.Count > 0 then
      ListModelers.ItemIndex := TargetIdx;
  finally
    ListModelers.Items.EndUpdate;
  end;

  LblHeader.Caption := Format(
    'CSG Boolean Modeler — %d Modeler(s) | %d Brushes | %d Tris | %.1f m^3 Total Solid Volume',
    [Length(FReport.Modelers), FReport.TotalBrushCount,
     FReport.TotalOutputTriangles, FReport.TotalVolumeCubicMeters]);

  RefreshBrushList;
  MemoDiag.Lines.Text := TCsgStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintBlueprint.Invalidate;
end;

procedure TCsgStudioForm.RefreshBrushList;
var
  M: TCastleCsgModeler;
  I, PrevIdx: Integer;
  B: TCsgBrushItem;
  OpTag: String;
begin
  PrevIdx := ListBrushes.ItemIndex;
  ListBrushes.Items.BeginUpdate;
  try
    ListBrushes.Items.Clear;
    M := CurrentModeler;
    if M <> nil then
    begin
      for I := 0 to M.Brushes.Count - 1 do
      begin
        B := M.Brushes[I];
        case B.Operation of
          cboUnion:     OpTag := '+Union';
          cboSubtract:  OpTag := '-Sub';
          cboIntersect: OpTag := '&Int';
        end;
        ListBrushes.Items.Add(Format('%d. [%s] %s (%s %.1fx%.1fx%.1fm)%s',
          [I + 1, OpTag, B.BrushId, CsgShapeToString(B.Shape),
           B.Size.X, B.Size.Y, B.Size.Z,
            specialize IfThen<String>(B.Enabled, '', ' [OFF]')]));
      end;
      if ListBrushes.Items.Count > 0 then
        ListBrushes.ItemIndex := Clamped(Max(0, PrevIdx), 0, ListBrushes.Items.Count - 1);
    end;
  finally
    ListBrushes.Items.EndUpdate;
  end;
  PopulateInspector;
end;

procedure TCsgStudioForm.PopulateInspector;
var
  M: TCastleCsgModeler;
  Idx: Integer;
  B: TCsgBrushItem;
begin
  FSyncingUi := True;
  try
    M := CurrentModeler;
    if M <> nil then
    begin
      SpinUvScale.Value := M.UvTilingScale;
      CheckCollider.Checked := M.GenerateCollider;
    end;
    Idx := SelectedBrushIndex;
    if (M <> nil) and (Idx >= 0) then
    begin
      B := M.Brushes[Idx];
      EditBrushId.Text := B.BrushId;
      CheckBrushEnabled.Checked := B.Enabled;
      ComboOp.ItemIndex := Ord(B.Operation);
      ComboShape.ItemIndex := Ord(B.Shape);
      SpinCenterX.Value := B.Center.X;
      SpinCenterY.Value := B.Center.Y;
      SpinCenterZ.Value := B.Center.Z;
      SpinSizeX.Value := B.Size.X;
      SpinSizeY.Value := B.Size.Y;
      SpinSizeZ.Value := B.Size.Z;
      SpinYawDeg.Value := B.YawDeg;
      SpinSegments.Value := B.Segments;
    end;
  finally
    FSyncingUi := False;
  end;
end;

procedure TCsgStudioForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TCsgStudioForm.ListModelersClick(Sender: TObject);
begin
  RefreshBrushList;
  PaintBlueprint.Invalidate;
end;

procedure TCsgStudioForm.ListBrushesClick(Sender: TObject);
begin
  PopulateInspector;
  PaintBlueprint.Invalidate;
end;

procedure TCsgStudioForm.BtnSpawnHollowRoomClick(Sender: TObject);
begin
  FSelectedTransform := TCsgStudioHelper.SpawnCsgModeler(
    FDesignRoot, FDesignOwner, capHollowRoomWithArchDoorway, FSpawnPos);
  NotifyChanged('Spawn CSG Hollow Room + Arch Doorway');
end;

procedure TCsgStudioForm.BtnSpawnVaultCrossClick(Sender: TObject);
begin
  FSelectedTransform := TCsgStudioHelper.SpawnCsgModeler(
    FDesignRoot, FDesignOwner, capVaultedCrossHallway, FSpawnPos);
  NotifyChanged('Spawn CSG Vaulted Cross Hallway');
end;

procedure TCsgStudioForm.BtnSpawnMezzanineClick(Sender: TObject);
begin
  FSelectedTransform := TCsgStudioHelper.SpawnCsgModeler(
    FDesignRoot, FDesignOwner, capMezzanineRampAndStairs, FSpawnPos);
  NotifyChanged('Spawn CSG Mezzanine + Stairwell + Ramp');
end;

procedure TCsgStudioForm.BtnSpawnCloisterClick(Sender: TObject);
begin
  FSelectedTransform := TCsgStudioHelper.SpawnCsgModeler(
    FDesignRoot, FDesignOwner, capPillaredCourtyardCloister, FSpawnPos);
  NotifyChanged('Spawn CSG Pillared Courtyard Cloister');
end;

procedure TCsgStudioForm.BtnAddUnionBoxClick(Sender: TObject);
var
  M: TCastleCsgModeler;
begin
  M := CurrentModeler;
  if M = nil then
    M := TCsgStudioHelper.SpawnCsgModeler(FDesignRoot, FDesignOwner, capCustom, FSpawnPos);
  if M = nil then
    Exit;
  TCsgStudioHelper.AddArchitecturalBrush(M,
    Format('Block%d', [M.Brushes.Count + 1]),
    cboUnion, cbsBox, Vector3(0.0, 1.5, 0.0), Vector3(4.0, 3.0, 4.0));
  ListBrushes.ItemIndex := M.Brushes.Count - 1;
  NotifyChanged('Add CSG Union Box Brush');
end;

procedure TCsgStudioForm.BtnSubArchDoorClick(Sender: TObject);
var
  M: TCastleCsgModeler;
begin
  M := CurrentModeler;
  if M = nil then
    Exit;
  TCsgStudioHelper.AddArchitecturalBrush(M,
    Format('ArchDoor%d', [M.Brushes.Count + 1]),
    cboSubtract, cbsArchCorridor, Vector3(0.0, 1.5, 4.5), Vector3(2.4, 2.6, 2.0), 0.0, 8);
  ListBrushes.ItemIndex := M.Brushes.Count - 1;
  NotifyChanged('Add CSG Subtractive Arch Doorway Brush');
end;

procedure TCsgStudioForm.BtnAddStairwellClick(Sender: TObject);
var
  M: TCastleCsgModeler;
begin
  M := CurrentModeler;
  if M = nil then
    Exit;
  TCsgStudioHelper.AddArchitecturalBrush(M,
    Format('Stairwell%d', [M.Brushes.Count + 1]),
    cboUnion, cbsStairwell, Vector3(0.0, 1.0, 2.0), Vector3(2.4, 2.0, 4.0), 0.0, 8);
  ListBrushes.ItemIndex := M.Brushes.Count - 1;
  NotifyChanged('Add CSG Stairwell Brush');
end;

procedure TCsgStudioForm.BtnAddRampClick(Sender: TObject);
var
  M: TCastleCsgModeler;
begin
  M := CurrentModeler;
  if M = nil then
    Exit;
  TCsgStudioHelper.AddArchitecturalBrush(M,
    Format('Ramp%d', [M.Brushes.Count + 1]),
    cboUnion, cbsRampWedge, Vector3(0.0, 1.0, 2.0), Vector3(2.4, 2.0, 4.0), 0.0, 8);
  ListBrushes.ItemIndex := M.Brushes.Count - 1;
  NotifyChanged('Add CSG Ramp Wedge Brush');
end;

procedure TCsgStudioForm.BtnMoveUpClick(Sender: TObject);
var
  M: TCastleCsgModeler;
  Idx: Integer;
begin
  M := CurrentModeler;
  Idx := SelectedBrushIndex;
  if (M <> nil) and (Idx > 0) then
  begin
    M.MoveBrush(Idx, Idx - 1);
    ListBrushes.ItemIndex := Idx - 1;
    NotifyChanged('Move CSG Brush Up');
  end;
end;

procedure TCsgStudioForm.BtnMoveDownClick(Sender: TObject);
var
  M: TCastleCsgModeler;
  Idx: Integer;
begin
  M := CurrentModeler;
  Idx := SelectedBrushIndex;
  if (M <> nil) and (Idx >= 0) and (Idx < M.Brushes.Count - 1) then
  begin
    M.MoveBrush(Idx, Idx + 1);
    ListBrushes.ItemIndex := Idx + 1;
    NotifyChanged('Move CSG Brush Down');
  end;
end;

procedure TCsgStudioForm.BtnDeleteBrushClick(Sender: TObject);
var
  M: TCastleCsgModeler;
  Idx: Integer;
begin
  M := CurrentModeler;
  Idx := SelectedBrushIndex;
  if (M <> nil) and (Idx >= 0) then
  begin
    M.DeleteBrush(Idx);
    NotifyChanged('Delete CSG Brush');
  end;
end;

procedure TCsgStudioForm.BtnApplyBrushClick(Sender: TObject);
var
  M: TCastleCsgModeler;
  Idx: Integer;
  B: TCsgBrushItem;
begin
  if FSyncingUi then
    Exit;
  M := CurrentModeler;
  if M = nil then
    Exit;

  M.UvTilingScale := SpinUvScale.Value;
  M.GenerateCollider := CheckCollider.Checked;

  Idx := SelectedBrushIndex;
  if Idx >= 0 then
  begin
    B := M.Brushes[Idx];
    B.BrushId := Trim(EditBrushId.Text);
    if B.BrushId = '' then
      B.BrushId := Format('Brush%d', [Idx + 1]);
    B.Enabled := CheckBrushEnabled.Checked;
    B.Operation := TCsgBooleanOperation(Clamped(ComboOp.ItemIndex, 0, Ord(High(TCsgBooleanOperation))));
    B.Shape := TCsgBrushShape(Clamped(ComboShape.ItemIndex, 0, Ord(High(TCsgBrushShape))));
    B.Center := Vector3(SpinCenterX.Value, SpinCenterY.Value, SpinCenterZ.Value);
    B.Size := Vector3(SpinSizeX.Value, SpinSizeY.Value, SpinSizeZ.Value);
    B.YawDeg := SpinYawDeg.Value;
    B.Segments := SpinSegments.Value;
    M.UpdateBrush(Idx, B);
  end else
    M.RebuildMesh;

  NotifyChanged('Update CSG Brush Parameters');
end;

procedure TCsgStudioForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TCsgStudioHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TCsgStudioForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TCsgStudioForm.PaintBlueprintPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, HalfW, I, SelIdx: Integer;
  M: TCastleCsgModeler;
  B: TCsgBrushItem;
  ScalePx, CXTop, CZTop, CZSide, CYSide: Single;
  R: TRect;
  Col: TColor;
begin
  C := PaintBlueprint.Canvas;
  W := PaintBlueprint.Width;
  H := PaintBlueprint.Height;
  HalfW := W div 2;

  C.Brush.Color := RGBToColor(24, 28, 34);
  C.FillRect(0, 0, W, H);

  C.Pen.Color := RGBToColor(58, 66, 78);
  C.Pen.Style := psSolid;
  C.Line(HalfW, 0, HalfW, H);

  C.Font.Color := RGBToColor(210, 222, 238);
  C.Brush.Style := bsClear;
  C.TextOut(10, 8, 'Top-Down Blueprint (X-Z Plane)');
  C.TextOut(HalfW + 10, 8, 'Side Elevation (Z-Y Cross-Section)');

  M := CurrentModeler;
  if M = nil then
  begin
    C.TextOut(16, H div 2 - 10, 'Click "+ Hollow Room + Arch" above to spawn a CSG Greybox Modeler.');
    Exit;
  end;

  ScalePx := Min(HalfW, H) / 18.0;
  CXTop := HalfW * 0.5;
  CZTop := H * 0.54;
  CZSide := HalfW + HalfW * 0.5;
  CYSide := H * 0.78;

  { Reference axes }
  C.Pen.Color := RGBToColor(48, 56, 68);
  C.Line(8, Round(CZTop), HalfW - 8, Round(CZTop));
  C.Line(Round(CXTop), 28, Round(CXTop), H - 8);
  C.Line(HalfW + 8, Round(CYSide), W - 8, Round(CYSide));

  SelIdx := SelectedBrushIndex;
  for I := 0 to M.Brushes.Count - 1 do
  begin
    B := M.Brushes[I];
    if not B.Enabled then
      Continue;

    case B.Operation of
      cboUnion:     Col := RGBToColor(68, 208, 152);
      cboSubtract:  Col := RGBToColor(242, 110, 96);
      cboIntersect: Col := RGBToColor(96, 182, 248);
    end;

    C.Pen.Color := Col;
    if I = SelIdx then
      C.Pen.Width := 3
    else
      C.Pen.Width := 1;
    if B.Operation = cboSubtract then
      C.Pen.Style := psDash
    else
      C.Pen.Style := psSolid;
    C.Brush.Style := bsClear;

    { Top-Down XZ footprint }
    R.Left := Round(CXTop + (B.Center.X - B.Size.X * 0.5) * ScalePx);
    R.Right := Round(CXTop + (B.Center.X + B.Size.X * 0.5) * ScalePx);
    R.Top := Round(CZTop + (B.Center.Z - B.Size.Z * 0.5) * ScalePx);
    R.Bottom := Round(CZTop + (B.Center.Z + B.Size.Z * 0.5) * ScalePx);
    if B.Shape = cbsCylinder then
      C.Ellipse(R)
    else
      C.Rectangle(R);

    { Side ZY elevation }
    R.Left := Round(CZSide + (B.Center.Z - B.Size.Z * 0.5) * ScalePx);
    R.Right := Round(CZSide + (B.Center.Z + B.Size.Z * 0.5) * ScalePx);
    R.Top := Round(CYSide - (B.Center.Y + B.Size.Y * 0.5) * ScalePx);
    R.Bottom := Round(CYSide - (B.Center.Y - B.Size.Y * 0.5) * ScalePx);
    C.Rectangle(R);
  end;

  C.Pen.Width := 1;
  C.Pen.Style := psSolid;
  C.Font.Color := RGBToColor(168, 232, 196);
  C.TextOut(10, H - 24, Format('%s | Tris: %d | Verts: %d | Volume: %.2f m^3',
    [M.Name, M.OutputTriangleCount, M.OutputVertexCount, M.OutputVolumeCubicMeters]));
end;

end.
