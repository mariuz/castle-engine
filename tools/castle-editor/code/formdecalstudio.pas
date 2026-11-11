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

{ Interactive Projected Surface Decals & Weathering Stamp Studio
  (@link(TDecalStudioForm))
  (Phase 298 — UE 6.0 UDecalComponent & Mesh Decals Parity). }
unit FormDecalStudio;

{$I castleconf.inc}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Graphics,
  Dialogs, Clipbrd,
  CastleVectors, CastleColors, CastleUtils, CastleTransform,
  CastleDecalProjector, ToolDecalStudio;

type
  TDecalStudioModifiedCallback = procedure (const UndoComment: String) of object;
  TDecalStudioRefreshViewportCallback = procedure of object;

  TDecalStudioForm = class(TForm)
  private
    FRootComponent: TComponent;
    FDesignOwner: TComponent;
    FSelectedComponent: TComponent;
    FWorld: TCastleAbstractRootTransform;
    FCamPos: TVector3;
    FCamDir: TVector3;
    FOnModified: TDecalStudioModifiedCallback;
    FOnRefreshViewport: TDecalStudioRefreshViewportCallback;

    FDecals: TDecalProjectorArray;

    ButtonStampPuddle: TButton;
    ButtonStampScorch: TButton;
    ButtonStampBullet: TButton;
    ButtonStampMoss: TButton;
    ButtonStampHazard: TButton;
    ButtonStampRune: TButton;
    ButtonReconformAll: TButton;
    ButtonCopyMarkdown: TButton;

    ListBoxDecals: TListBox;
    ComboPreset: TComboBox;
    ComboBlendStyle: TComboBox;
    EditExtX: TEdit;
    EditExtY: TEdit;
    EditExtZ: TEdit;
    EditOpacity: TEdit;
    EditRoughness: TEdit;
    EditNormalCutoff: TEdit;
    EditSortOrder: TEdit;
    EditGridRes: TEdit;
    EditTextureUrl: TEdit;
    CheckProjectWorld: TCheckBox;
    ButtonApplyProps: TButton;

    PaintBoxPreview: TPaintBox;
    MemoAudit: TMemo;

    LabelStatus: TLabel;
    ButtonClose: TButton;

    procedure BuildUi;
    function ActiveDecal: TCastleDecalProjector;
    procedure RefreshDecalList(const ASelectDecal: TCastleDecalProjector = nil);
    procedure LoadActiveDecalIntoControls;
    procedure NotifyModified(const AComment: String);
    procedure StampPreset(const APreset: TDecalPreset; const ALabel: String);

    procedure ButtonStampPuddleClick(Sender: TObject);
    procedure ButtonStampScorchClick(Sender: TObject);
    procedure ButtonStampBulletClick(Sender: TObject);
    procedure ButtonStampMossClick(Sender: TObject);
    procedure ButtonStampHazardClick(Sender: TObject);
    procedure ButtonStampRuneClick(Sender: TObject);
    procedure ButtonReconformAllClick(Sender: TObject);
    procedure ButtonCopyMarkdownClick(Sender: TObject);

    procedure ListBoxDecalsClick(Sender: TObject);
    procedure ButtonApplyPropsClick(Sender: TObject);
    procedure PaintBoxPreviewPaint(Sender: TObject);
    procedure ButtonCloseClick(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
      const AWorld: TCastleAbstractRootTransform;
      const ACamPos, ACamDir: TVector3;
      const AOnModified: TDecalStudioModifiedCallback;
      const AOnRefreshViewport: TDecalStudioRefreshViewportCallback);
  end;

implementation

constructor TDecalStudioForm.CreateStudio(AOwner: TComponent;
  const ARootComponent, ADesignOwner, ASelectedComponent: TComponent;
  const AWorld: TCastleAbstractRootTransform;
  const ACamPos, ACamDir: TVector3;
  const AOnModified: TDecalStudioModifiedCallback;
  const AOnRefreshViewport: TDecalStudioRefreshViewportCallback);
var
  InitialDecal: TCastleDecalProjector;
begin
  inherited CreateNew(AOwner, 1);
  FRootComponent := ARootComponent;
  FDesignOwner := ADesignOwner;
  FSelectedComponent := ASelectedComponent;
  FWorld := AWorld;
  FCamPos := ACamPos;
  FCamDir := ACamDir;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  BuildUi;

  if FSelectedComponent is TCastleDecalProjector then
    InitialDecal := TCastleDecalProjector(FSelectedComponent)
  else
    InitialDecal := nil;
  RefreshDecalList(InitialDecal);
end;

procedure TDecalStudioForm.BuildUi;
var
  PanelTop, PanelBottom, PanelLeft, PanelClient, PanelPreviewWrap: TPanel;
  Lbl: TLabel;
begin
  Caption := 'Projected Surface Decals & Weathering Stamp Studio (UE 6.0 UDecalComponent Parity)';
  Width := 1120;
  Height := 690;
  Position := poMainFormCenter;
  Constraints.MinWidth := 960;
  Constraints.MinHeight := 590;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 44;
  PanelTop.BevelOuter := bvNone;

  ButtonStampPuddle := TButton.Create(Self);
  ButtonStampPuddle.Parent := PanelTop;
  ButtonStampPuddle.SetBounds(8, 8, 108, 28);
  ButtonStampPuddle.Caption := '+ Wet Puddle';
  ButtonStampPuddle.OnClick := @ButtonStampPuddleClick;

  ButtonStampScorch := TButton.Create(Self);
  ButtonStampScorch.Parent := PanelTop;
  ButtonStampScorch.SetBounds(120, 8, 112, 28);
  ButtonStampScorch.Caption := '+ Scorch Mark';
  ButtonStampScorch.OnClick := @ButtonStampScorchClick;

  ButtonStampBullet := TButton.Create(Self);
  ButtonStampBullet.Parent := PanelTop;
  ButtonStampBullet.SetBounds(236, 8, 116, 28);
  ButtonStampBullet.Caption := '+ Bullet Impact';
  ButtonStampBullet.OnClick := @ButtonStampBulletClick;

  ButtonStampMoss := TButton.Create(Self);
  ButtonStampMoss.Parent := PanelTop;
  ButtonStampMoss.SetBounds(356, 8, 110, 28);
  ButtonStampMoss.Caption := '+ Moss Patch';
  ButtonStampMoss.OnClick := @ButtonStampMossClick;

  ButtonStampHazard := TButton.Create(Self);
  ButtonStampHazard.Parent := PanelTop;
  ButtonStampHazard.SetBounds(470, 8, 116, 28);
  ButtonStampHazard.Caption := '+ Hazard Stripe';
  ButtonStampHazard.OnClick := @ButtonStampHazardClick;

  ButtonStampRune := TButton.Create(Self);
  ButtonStampRune.Parent := PanelTop;
  ButtonStampRune.SetBounds(590, 8, 108, 28);
  ButtonStampRune.Caption := '+ Magic Rune';
  ButtonStampRune.OnClick := @ButtonStampRuneClick;

  ButtonReconformAll := TButton.Create(Self);
  ButtonReconformAll.Parent := PanelTop;
  ButtonReconformAll.SetBounds(706, 8, 140, 28);
  ButtonReconformAll.Caption := 'Re-Conform All';
  ButtonReconformAll.OnClick := @ButtonReconformAllClick;

  ButtonCopyMarkdown := TButton.Create(Self);
  ButtonCopyMarkdown.Parent := PanelTop;
  ButtonCopyMarkdown.SetBounds(852, 8, 158, 28);
  ButtonCopyMarkdown.Caption := 'Copy Markdown Report';
  ButtonCopyMarkdown.OnClick := @ButtonCopyMarkdownClick;

  { Bottom Status Bar }
  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 40;
  PanelBottom.BevelOuter := bvNone;

  LabelStatus := TLabel.Create(Self);
  LabelStatus.Parent := PanelBottom;
  LabelStatus.SetBounds(12, 12, 900, 18);
  LabelStatus.Caption := 'Stamp buttons raycast along the 3D camera view to align decals flush onto hit floors, walls, or ramps.';

  ButtonClose := TButton.Create(Self);
  ButtonClose.Parent := PanelBottom;
  ButtonClose.Anchors := [akTop, akRight];
  ButtonClose.SetBounds(1010, 6, 96, 28);
  ButtonClose.Caption := 'Close';
  ButtonClose.OnClick := @ButtonCloseClick;

  { Left Decal List & Inspector }
  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := Self;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 340;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 6, 300, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Decal Projectors (Sorted by SortOrder)';

  ListBoxDecals := TListBox.Create(Self);
  ListBoxDecals.Parent := PanelLeft;
  ListBoxDecals.SetBounds(10, 26, 320, 165);
  ListBoxDecals.OnClick := @ListBoxDecalsClick;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 200, 80, 18);
  Lbl.Caption := 'Preset:';

  ComboPreset := TComboBox.Create(Self);
  ComboPreset.Parent := PanelLeft;
  ComboPreset.SetBounds(110, 196, 220, 24);
  ComboPreset.Style := csDropDownList;
  ComboPreset.Items.Add('Custom');
  ComboPreset.Items.Add('Wet Puddle');
  ComboPreset.Items.Add('Scorch Mark');
  ComboPreset.Items.Add('Bullet Impact');
  ComboPreset.Items.Add('Moss Growth');
  ComboPreset.Items.Add('Hazard Stripe');
  ComboPreset.Items.Add('Magic Rune');

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 230, 96, 18);
  Lbl.Caption := 'Blend Style:';

  ComboBlendStyle := TComboBox.Create(Self);
  ComboBlendStyle.Parent := PanelLeft;
  ComboBlendStyle.SetBounds(110, 226, 220, 24);
  ComboBlendStyle.Style := csDropDownList;
  ComboBlendStyle.Items.Add('Alpha Blend');
  ComboBlendStyle.Items.Add('Additive Glow');
  ComboBlendStyle.Items.Add('Multiply Stain');

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 262, 98, 18);
  Lbl.Caption := 'Box X / Y / Z (m):';

  EditExtX := TEdit.Create(Self);
  EditExtX.Parent := PanelLeft;
  EditExtX.SetBounds(110, 258, 68, 24);

  EditExtY := TEdit.Create(Self);
  EditExtY.Parent := PanelLeft;
  EditExtY.SetBounds(186, 258, 68, 24);

  EditExtZ := TEdit.Create(Self);
  EditExtZ.Parent := PanelLeft;
  EditExtZ.SetBounds(262, 258, 68, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 294, 96, 18);
  Lbl.Caption := 'Opacity / Rough:';

  EditOpacity := TEdit.Create(Self);
  EditOpacity.Parent := PanelLeft;
  EditOpacity.SetBounds(110, 290, 104, 24);

  EditRoughness := TEdit.Create(Self);
  EditRoughness.Parent := PanelLeft;
  EditRoughness.SetBounds(226, 290, 104, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 326, 110, 18);
  Lbl.Caption := 'Cutoff° / Sort / Grid:';

  EditNormalCutoff := TEdit.Create(Self);
  EditNormalCutoff.Parent := PanelLeft;
  EditNormalCutoff.SetBounds(130, 322, 62, 24);

  EditSortOrder := TEdit.Create(Self);
  EditSortOrder.Parent := PanelLeft;
  EditSortOrder.SetBounds(200, 322, 60, 24);

  EditGridRes := TEdit.Create(Self);
  EditGridRes.Parent := PanelLeft;
  EditGridRes.SetBounds(268, 322, 62, 24);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 356, 260, 18);
  Lbl.Caption := 'Optional Texture URL (castle-data:/...):';

  EditTextureUrl := TEdit.Create(Self);
  EditTextureUrl.Parent := PanelLeft;
  EditTextureUrl.SetBounds(10, 376, 320, 24);

  CheckProjectWorld := TCheckBox.Create(Self);
  CheckProjectWorld.Parent := PanelLeft;
  CheckProjectWorld.SetBounds(10, 406, 320, 22);
  CheckProjectWorld.Caption := 'Conform Mesh to World Geometry (-Y Raycast)';

  ButtonApplyProps := TButton.Create(Self);
  ButtonApplyProps.Parent := PanelLeft;
  ButtonApplyProps.SetBounds(10, 434, 320, 30);
  ButtonApplyProps.Caption := 'Apply Decal Settings & Re-Conform';
  ButtonApplyProps.OnClick := @ButtonApplyPropsClick;

  { Right Stamp Preview + Diagnostics }
  PanelClient := TPanel.Create(Self);
  PanelClient.Parent := Self;
  PanelClient.Align := alClient;
  PanelClient.BevelOuter := bvNone;

  MemoAudit := TMemo.Create(Self);
  MemoAudit.Parent := PanelClient;
  MemoAudit.Align := alBottom;
  MemoAudit.Height := 160;
  MemoAudit.ReadOnly := true;
  MemoAudit.ScrollBars := ssVertical;

  PanelPreviewWrap := TPanel.Create(Self);
  PanelPreviewWrap.Parent := PanelClient;
  PanelPreviewWrap.Align := alClient;
  PanelPreviewWrap.BevelOuter := bvLowered;

  PaintBoxPreview := TPaintBox.Create(Self);
  PaintBoxPreview.Parent := PanelPreviewWrap;
  PaintBoxPreview.Align := alClient;
  PaintBoxPreview.OnPaint := @PaintBoxPreviewPaint;
end;

function TDecalStudioForm.ActiveDecal: TCastleDecalProjector;
var
  Idx: Integer;
begin
  Idx := ListBoxDecals.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FDecals)) then
    Result := FDecals[Idx]
  else
    Result := nil;
end;

procedure TDecalStudioForm.RefreshDecalList(
  const ASelectDecal: TCastleDecalProjector);
var
  Sum: TDecalStudioSummary;
  I, SelIdx: Integer;
begin
  Sum := TDecalStudioHelper.ScanDecals(FRootComponent);
  FDecals := Sum.Decals;

  ListBoxDecals.Items.BeginUpdate;
  try
    ListBoxDecals.Items.Clear;
    SelIdx := -1;
    for I := 0 to High(FDecals) do
    begin
      ListBoxDecals.Items.Add(Format('[#%d] %s  (%s, %d tri)', [
        FDecals[I].SortOrder,
        FDecals[I].Name,
        DecalPresetToString(FDecals[I].Preset),
        FDecals[I].ProjectedTriangleCount]));
      if FDecals[I] = ASelectDecal then
        SelIdx := I;
    end;
    if (SelIdx < 0) and (Length(FDecals) > 0) then
      SelIdx := 0;
    ListBoxDecals.ItemIndex := SelIdx;
  finally
    ListBoxDecals.Items.EndUpdate;
  end;

  MemoAudit.Lines.Text := TDecalStudioHelper.FormatDecalStudioMarkdown(FRootComponent);
  LoadActiveDecalIntoControls;
  LabelStatus.Caption := Format(
    'Decals: %d | Conformal Triangles: %d | Empty Projectors: %d',
    [Sum.DecalCount, Sum.TotalProjectedTriangles, Sum.EmptyProjectionCount]);
end;

procedure TDecalStudioForm.LoadActiveDecalIntoControls;
var
  D: TCastleDecalProjector;
begin
  D := ActiveDecal;
  if D = nil then
  begin
    PaintBoxPreview.Invalidate;
    Exit;
  end;

  ComboPreset.ItemIndex := Ord(D.Preset);
  ComboBlendStyle.ItemIndex := Ord(D.BlendStyle);
  EditExtX.Text := FormatFloat('0.##', D.BoxExtents.X);
  EditExtY.Text := FormatFloat('0.##', D.BoxExtents.Y);
  EditExtZ.Text := FormatFloat('0.##', D.BoxExtents.Z);
  EditOpacity.Text := FormatFloat('0.##', D.Opacity);
  EditRoughness.Text := FormatFloat('0.##', D.Roughness);
  EditNormalCutoff.Text := FormatFloat('0.#', D.NormalAngleCutoffDeg);
  EditSortOrder.Text := IntToStr(D.SortOrder);
  EditGridRes.Text := IntToStr(D.GridResolution);
  EditTextureUrl.Text := D.TextureUrl;
  CheckProjectWorld.Checked := D.ProjectToWorldGeometry;
  PaintBoxPreview.Invalidate;
end;

procedure TDecalStudioForm.NotifyModified(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
end;

procedure TDecalStudioForm.StampPreset(const APreset: TDecalPreset;
  const ALabel: String);
var
  D: TCastleDecalProjector;
  FallbackPos: TVector3;
begin
  D := nil;
  if FWorld <> nil then
    D := TDecalStudioHelper.StampDecalAlongRay(
      FRootComponent, FDesignOwner, FWorld, FCamPos, FCamDir, APreset);
  if D = nil then
  begin
    FallbackPos := FCamPos + FCamDir * 5.0;
    D := TDecalStudioHelper.CreateDecalInDesign(
      FRootComponent, FDesignOwner, APreset, FallbackPos, Vector3(0.0, 1.0, 0.0));
  end;
  if D <> nil then
  begin
    NotifyModified('Stamp ' + ALabel + ' Decal');
    RefreshDecalList(D);
  end;
end;

procedure TDecalStudioForm.ButtonStampPuddleClick(Sender: TObject);
begin
  StampPreset(dpPuddleWet, 'Wet Puddle');
end;

procedure TDecalStudioForm.ButtonStampScorchClick(Sender: TObject);
begin
  StampPreset(dpScorchMark, 'Scorch Mark');
end;

procedure TDecalStudioForm.ButtonStampBulletClick(Sender: TObject);
begin
  StampPreset(dpBulletImpact, 'Bullet Impact');
end;

procedure TDecalStudioForm.ButtonStampMossClick(Sender: TObject);
begin
  StampPreset(dpMossGrowth, 'Moss Growth');
end;

procedure TDecalStudioForm.ButtonStampHazardClick(Sender: TObject);
begin
  StampPreset(dpHazardStripe, 'Hazard Stripe');
end;

procedure TDecalStudioForm.ButtonStampRuneClick(Sender: TObject);
begin
  StampPreset(dpMagicRune, 'Magic Rune');
end;

procedure TDecalStudioForm.ButtonReconformAllClick(Sender: TObject);
var
  Tris: Integer;
begin
  Tris := TDecalStudioHelper.ConformAllDecalsInHierarchy(FRootComponent);
  NotifyModified('Re-Conform All Decals');
  RefreshDecalList(ActiveDecal);
  LabelStatus.Caption := Format('Re-projected all decals onto world geometry (%d triangles).', [Tris]);
end;

procedure TDecalStudioForm.ButtonCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TDecalStudioHelper.FormatDecalStudioMarkdown(FRootComponent);
  LabelStatus.Caption := 'Copied Decal Studio Markdown report to clipboard.';
end;

procedure TDecalStudioForm.ListBoxDecalsClick(Sender: TObject);
begin
  LoadActiveDecalIntoControls;
end;

procedure TDecalStudioForm.ButtonApplyPropsClick(Sender: TObject);
var
  D: TCastleDecalProjector;
  NewPreset: TDecalPreset;
begin
  D := ActiveDecal;
  if D = nil then
    Exit;
  NewPreset := TDecalPreset(Clamped(ComboPreset.ItemIndex, 0, Ord(High(TDecalPreset))));
  if NewPreset <> D.Preset then
    D.Preset := NewPreset;
  D.BlendStyle := TDecalBlendStyle(Clamped(ComboBlendStyle.ItemIndex, 0, Ord(High(TDecalBlendStyle))));
  D.BoxExtents := Vector3(
    StrToFloatDefDot(EditExtX.Text, D.BoxExtents.X),
    StrToFloatDefDot(EditExtY.Text, D.BoxExtents.Y),
    StrToFloatDefDot(EditExtZ.Text, D.BoxExtents.Z));
  D.Opacity := StrToFloatDefDot(EditOpacity.Text, D.Opacity);
  D.Roughness := StrToFloatDefDot(EditRoughness.Text, D.Roughness);
  D.NormalAngleCutoffDeg := StrToFloatDefDot(EditNormalCutoff.Text, D.NormalAngleCutoffDeg);
  D.SortOrder := StrToIntDef(EditSortOrder.Text, D.SortOrder);
  D.GridResolution := StrToIntDef(EditGridRes.Text, D.GridResolution);
  D.TextureUrl := Trim(EditTextureUrl.Text);
  D.ProjectToWorldGeometry := CheckProjectWorld.Checked;
  D.ConformAndRebuildMesh;
  NotifyModified('Update Decal Projector Properties');
  RefreshDecalList(D);
end;

procedure TDecalStudioForm.PaintBoxPreviewPaint(Sender: TObject);
const
  GridCells = 36;
var
  C: TCanvas;
  W, H, Side, OffX, OffY, IX, IY, CellW, CellH: Integer;
  D: TCastleDecalProjector;
  Col: TCastleColor;
  CheckerBg, R8, G8, B8: Byte;
  Alpha, CutRad: Single;
  ConeX, ConeY, ConeR: Integer;
begin
  C := PaintBoxPreview.Canvas;
  W := PaintBoxPreview.Width;
  H := PaintBoxPreview.Height;

  C.Brush.Color := $00201C18;
  C.FillRect(0, 0, W, H);

  D := ActiveDecal;
  if D = nil then
  begin
    C.Font.Color := $00D0D0D0;
    C.Brush.Style := bsClear;
    C.TextOut(20, 20, 'Click "+ Wet Puddle", "+ Scorch Mark", or "+ Magic Rune" above to stamp a decal.');
    Exit;
  end;

  Side := Max(80, Min(W - 220, H - 40));
  OffX := 24;
  OffY := (H - Side) div 2;
  CellW := Max(2, Side div GridCells);
  CellH := Max(2, Side div GridCells);

  for IY := 0 to GridCells - 1 do
    for IX := 0 to GridCells - 1 do
    begin
      if ((IX + IY) and 1) = 0 then
        CheckerBg := 58
      else
        CheckerBg := 40;
      Col := D.EvaluateProceduralSample((IX + 0.5) / GridCells, (IY + 0.5) / GridCells);
      Alpha := Col.W;
      R8 := Round(Clamped(CheckerBg * (1.0 - Alpha) + Col.X * 255.0 * Alpha, 0.0, 255.0));
      G8 := Round(Clamped(CheckerBg * (1.0 - Alpha) + Col.Y * 255.0 * Alpha, 0.0, 255.0));
      B8 := Round(Clamped(CheckerBg * (1.0 - Alpha) + Col.Z * 255.0 * Alpha, 0.0, 255.0));
      C.Brush.Color := RGBToColor(R8, G8, B8);
      C.FillRect(
        OffX + Round((IX / GridCells) * Side),
        OffY + Round((IY / GridCells) * Side),
        OffX + Round(((IX + 1) / GridCells) * Side) + CellW - CellW,
        OffY + Round(((IY + 1) / GridCells) * Side) + CellH - CellH);
    end;

  C.Brush.Style := bsClear;
  C.Pen.Color := $00FFE066;
  C.Pen.Width := 2;
  C.Rectangle(OffX, OffY, OffX + Side, OffY + Side);

  { Grazing Normal Cutoff Cone Indicator on the right }
  ConeX := OffX + Side + 100;
  ConeY := H div 2 + 20;
  ConeR := 68;
  CutRad := DegToRad(Clamped(D.NormalAngleCutoffDeg, 5.0, 90.0));
  C.Pen.Color := $0055FF88;
  C.MoveTo(ConeX, ConeY);
  C.LineTo(ConeX - Round(Sin(CutRad) * ConeR), ConeY - Round(Cos(CutRad) * ConeR));
  C.MoveTo(ConeX, ConeY);
  C.LineTo(ConeX + Round(Sin(CutRad) * ConeR), ConeY - Round(Cos(CutRad) * ConeR));
  C.Font.Color := $00F0F0F0;
  C.TextOut(OffX + Side + 24, OffY + 8, Format('Normal Cutoff: %.0f°', [D.NormalAngleCutoffDeg]));
  C.TextOut(OffX + Side + 24, OffY + 30, Format('Accepted Cells: %d', [D.LastAcceptedCellCount]));
  C.TextOut(OffX + Side + 24, OffY + 50, Format('Angle-Rejected: %d', [D.LastRejectedAngleCellCount]));
  C.TextOut(OffX + Side + 24, OffY + 70, Format('Triangles: %d', [D.ProjectedTriangleCount]));
end;

procedure TDecalStudioForm.ButtonCloseClick(Sender: TObject);
begin
  Close;
end;

end.
