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

{ Interactive Virtual Camera Priority Blending, Spline Dolly Rail, Deadzone
  Composer & Trauma-Squared Perlin Shake Studio (@link(TVirtualCameraForm))
  (Phase 312). }
unit FormVirtualCamera;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  Forms, Controls, StdCtrls, ExtCtrls, Graphics, Clipbrd,
  CastleVectors, CastleUtils, CastleTransform,
  CastleVirtualCamera, ToolVirtualCamera;

type
  TVirtualCameraModifiedCallback = procedure(const AComment: String) of object;
  TVirtualCameraRefreshViewportCallback = procedure of object;

  TVirtualCameraForm = class(TForm)
  strict private
    FDesignRoot: TComponent;
    FDesignOwner: TComponent;
    FOnModified: TVirtualCameraModifiedCallback;
    FOnRefreshViewport: TVirtualCameraRefreshViewportCallback;

    FReport: TVirtualCameraAuditReport;

    LblHeader: TLabel;
    ListVCams: TListBox;
    EditPriority: TEdit;
    EditFov: TEdit;
    EditDollyT: TEdit;
    ComboBlendCurve: TComboBox;
    PaintHud: TPaintBox;
    MemoDiag: TMemo;

    procedure BuildUi;
    function CurrentVCam: TCastleVirtualCamera;
    function CurrentBrain: TCastleVirtualCameraBrain;
    procedure RefreshAll;
    procedure SyncInspectorFromSelection;
    procedure NotifyChanged(const AComment: String);

    procedure ListVCamsClick(Sender: TObject);
    procedure BtnEnsureBrainClick(Sender: TObject);
    procedure BtnSpawnEstablishingClick(Sender: TObject);
    procedure BtnSpawnThirdPersonClick(Sender: TObject);
    procedure BtnSpawnDollyRailClick(Sender: TObject);
    procedure BtnToggleActiveRigClick(Sender: TObject);
    procedure BtnApplyRigParamsClick(Sender: TObject);
    procedure BtnTriggerTraumaClick(Sender: TObject);
    procedure BtnStepDirectorClick(Sender: TObject);
    procedure BtnCopyMarkdownClick(Sender: TObject);
    procedure BtnCloseClick(Sender: TObject);
    procedure ComboBlendCurveChange(Sender: TObject);
    procedure PaintHudPaint(Sender: TObject);
  public
    constructor CreateStudio(AOwner: TComponent;
      const ADesignRoot, ADesignOwner: TComponent;
      const AOnModified: TVirtualCameraModifiedCallback;
      const AOnRefreshViewport: TVirtualCameraRefreshViewportCallback);
    destructor Destroy; override;
  end;

implementation

constructor TVirtualCameraForm.CreateStudio(AOwner: TComponent;
  const ADesignRoot, ADesignOwner: TComponent;
  const AOnModified: TVirtualCameraModifiedCallback;
  const AOnRefreshViewport: TVirtualCameraRefreshViewportCallback);
begin
  inherited CreateNew(AOwner, 0);
  FDesignRoot := ADesignRoot;
  FDesignOwner := ADesignOwner;
  FOnModified := AOnModified;
  FOnRefreshViewport := AOnRefreshViewport;

  Caption := 'Virtual Camera Priority Blending, Dolly Rail, Deadzone & Trauma Shake Studio';
  Width := 1120;
  Height := 700;
  Position := poMainFormCenter;

  BuildUi;
  RefreshAll;
end;

destructor TVirtualCameraForm.Destroy;
begin
  FreeAndNil(FReport);
  inherited;
end;

procedure TVirtualCameraForm.BuildUi;
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
  PanelTop.Height := 74;
  PanelTop.BevelOuter := bvNone;

  LblHeader := TLabel.Create(Self);
  LblHeader.Parent := PanelTop;
  LblHeader.Left := 12;
  LblHeader.Top := 8;
  LblHeader.Font.Style := [fsBold];
  LblHeader.Caption := 'Virtual Camera Director Studio — Priority Cut/Blend, Dolly Rail & Trauma Shake';

  RowTop := TPanel.Create(Self);
  RowTop.Parent := PanelTop;
  RowTop.SetBounds(8, 30, 1100, 38);
  RowTop.BevelOuter := bvNone;

  MakeBtn(RowTop, '+ Ensure Camera Brain', 4, 4, 168, @BtnEnsureBrainClick);
  MakeBtn(RowTop, '+ Establishing VCam', 178, 4, 156, @BtnSpawnEstablishingClick);
  MakeBtn(RowTop, '+ 3rd-Person Follow VCam', 340, 4, 184, @BtnSpawnThirdPersonClick);
  MakeBtn(RowTop, '+ Spline Dolly VCam', 530, 4, 162, @BtnSpawnDollyRailClick);
  MakeBtn(RowTop, '+0.6 Trauma Shake!', 698, 4, 152, @BtnTriggerTraumaClick);
  MakeBtn(RowTop, 'Step Director (+0.1s)', 856, 4, 168, @BtnStepDirectorClick);

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 42;
  PanelBottom.BevelOuter := bvNone;

  MakeBtn(PanelBottom, 'Copy Markdown Report', 12, 6, 190, @BtnCopyMarkdownClick);
  BtnClose := MakeBtn(PanelBottom, 'Close', 990, 6, 110, @BtnCloseClick);
  BtnClose.Anchors := [akTop, akRight];

  PanelBody := TPanel.Create(Self);
  PanelBody.Parent := Self;
  PanelBody.Align := alClient;
  PanelBody.BevelOuter := bvNone;

  PanelLeft := TPanel.Create(Self);
  PanelLeft.Parent := PanelBody;
  PanelLeft.Align := alLeft;
  PanelLeft.Width := 370;
  PanelLeft.BevelOuter := bvNone;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 8, 320, 18);
  Lbl.Font.Style := [fsBold];
  Lbl.Caption := 'Virtual Camera Rigs (Arbitrated by Priority):';

  ListVCams := TListBox.Create(Self);
  ListVCams.Parent := PanelLeft;
  ListVCams.SetBounds(10, 28, 346, 230);
  ListVCams.OnClick := @ListVCamsClick;

  MakeBtn(PanelLeft, 'Toggle ActiveRig ON / OFF', 10, 266, 346, @BtnToggleActiveRigClick);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 308, 120, 18);
  Lbl.Caption := 'Rig Priority:';

  EditPriority := TEdit.Create(Self);
  EditPriority.Parent := PanelLeft;
  EditPriority.SetBounds(150, 304, 206, 26);
  EditPriority.Text := '10';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 344, 130, 18);
  Lbl.Caption := 'Field of View (°):';

  EditFov := TEdit.Create(Self);
  EditFov.Parent := PanelLeft;
  EditFov.SetBounds(150, 340, 206, 26);
  EditFov.Text := '55.0';

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 380, 130, 18);
  Lbl.Caption := 'Dolly Rail T [0..1]:';

  EditDollyT := TEdit.Create(Self);
  EditDollyT.Parent := PanelLeft;
  EditDollyT.SetBounds(150, 376, 206, 26);
  EditDollyT.Text := '0.00';

  MakeBtn(PanelLeft, 'Apply Priority / FOV / Dolly T', 10, 414, 346, @BtnApplyRigParamsClick);

  Lbl := TLabel.Create(Self);
  Lbl.Parent := PanelLeft;
  Lbl.SetBounds(10, 458, 135, 18);
  Lbl.Caption := 'Brain Blend Curve:';

  ComboBlendCurve := TComboBox.Create(Self);
  ComboBlendCurve.Parent := PanelLeft;
  ComboBlendCurve.SetBounds(150, 454, 206, 26);
  ComboBlendCurve.Style := csDropDownList;
  ComboBlendCurve.Items.Add('Hard Cut');
  ComboBlendCurve.Items.Add('Linear');
  ComboBlendCurve.Items.Add('SmoothStep');
  ComboBlendCurve.Items.Add('EaseInOutCubic');
  ComboBlendCurve.ItemIndex := 2;
  ComboBlendCurve.OnChange := @ComboBlendCurveChange;

  PanelCenter := TPanel.Create(Self);
  PanelCenter.Parent := PanelBody;
  PanelCenter.Align := alClient;
  PanelCenter.BevelOuter := bvNone;

  PaintHud := TPaintBox.Create(Self);
  PaintHud.Parent := PanelCenter;
  PaintHud.Align := alTop;
  PaintHud.Height := 320;
  PaintHud.OnPaint := @PaintHudPaint;

  MemoDiag := TMemo.Create(Self);
  MemoDiag.Parent := PanelCenter;
  MemoDiag.Align := alClient;
  MemoDiag.ReadOnly := True;
  MemoDiag.ScrollBars := ssAutoBoth;
  MemoDiag.Font.Name := 'Monospace';
end;

function TVirtualCameraForm.CurrentVCam: TCastleVirtualCamera;
var
  Idx: Integer;
begin
  Result := nil;
  if (FReport = nil) or (Length(FReport.VCams) = 0) then
    Exit;
  Idx := ListVCams.ItemIndex;
  if (Idx >= 0) and (Idx < Length(FReport.VCams)) then
    Result := FReport.VCams[Idx];
end;

function TVirtualCameraForm.CurrentBrain: TCastleVirtualCameraBrain;
begin
  if (FReport <> nil) and (Length(FReport.Brains) > 0) then
    Result := FReport.Brains[0]
  else
    Result := nil;
end;

procedure TVirtualCameraForm.RefreshAll;
var
  PrevVCam: TCastleVirtualCamera;
  I, TargetIdx: Integer;
  WinStr: String;
  B: TCastleVirtualCameraBrain;
begin
  PrevVCam := CurrentVCam;
  FreeAndNil(FReport);
  FReport := TVirtualCameraHelper.ScanDesign(FDesignRoot, FDesignOwner);

  ListVCams.Items.BeginUpdate;
  try
    ListVCams.Items.Clear;
    TargetIdx := 0;
    for I := 0 to High(FReport.VCams) do
    begin
      ListVCams.Items.Add(Format('%s %s%s',
        [FReport.VCams[I].Name, FReport.VCams[I].VCamSummaryBadge,
         specialize IfThen<String>(FReport.VCams[I] = FReport.WinningVCam, ' ★ LIVE', '')]));
      if FReport.VCams[I] = PrevVCam then
        TargetIdx := I;
    end;
    if ListVCams.Items.Count > 0 then
      ListVCams.ItemIndex := TargetIdx;
  finally
    ListVCams.Items.EndUpdate;
  end;

  if FReport.WinningVCam <> nil then
    WinStr := FReport.WinningVCam.Name
  else
    WinStr := 'None';

  LblHeader.Caption := Format(
    'Virtual Camera Studio — %d Rig(s) (%d Active) | %d Brain(s) | Winning Rig: %s',
    [Length(FReport.VCams), FReport.ActiveRigCount, Length(FReport.Brains), WinStr]);

  B := CurrentBrain;
  if B <> nil then
    ComboBlendCurve.ItemIndex := Ord(B.BlendCurve);

  SyncInspectorFromSelection;
  MemoDiag.Lines.Text := TVirtualCameraHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
  PaintHud.Invalidate;
end;

procedure TVirtualCameraForm.SyncInspectorFromSelection;
var
  V: TCastleVirtualCamera;
begin
  V := CurrentVCam;
  if V = nil then
    Exit;
  EditPriority.Text := IntToStr(V.Priority);
  EditFov.Text := FormatDot('%.1f', [V.FieldOfViewDeg]);
  EditDollyT.Text := FormatDot('%.2f', [V.DollyNormalizedT]);
end;

procedure TVirtualCameraForm.NotifyChanged(const AComment: String);
begin
  if Assigned(FOnModified) then
    FOnModified(AComment);
  if Assigned(FOnRefreshViewport) then
    FOnRefreshViewport();
  RefreshAll;
end;

procedure TVirtualCameraForm.ListVCamsClick(Sender: TObject);
begin
  SyncInspectorFromSelection;
  PaintHud.Invalidate;
end;

procedure TVirtualCameraForm.BtnEnsureBrainClick(Sender: TObject);
begin
  TVirtualCameraHelper.EnsureBrainOnViewportCamera(FDesignRoot, FDesignOwner, 1.0);
  NotifyChanged('Ensure Virtual Camera Director Brain on Viewport Camera');
end;

procedure TVirtualCameraForm.BtnSpawnEstablishingClick(Sender: TObject);
begin
  TVirtualCameraHelper.EnsureBrainOnViewportCamera(FDesignRoot, FDesignOwner, 1.0);
  TVirtualCameraHelper.SpawnFixedEstablishingVCam(
    FDesignRoot, FDesignOwner, Vector3(-10.0, 6.0, 12.0), nil, 10, 'VCamEstablishing');
  NotifyChanged('Spawn Establishing Virtual Camera Rig');
end;

procedure TVirtualCameraForm.BtnSpawnThirdPersonClick(Sender: TObject);
begin
  TVirtualCameraHelper.EnsureBrainOnViewportCamera(FDesignRoot, FDesignOwner, 1.0);
  TVirtualCameraHelper.SpawnThirdPersonFollowVCam(
    FDesignRoot, FDesignOwner, nil, 20, 'VCamThirdPerson');
  NotifyChanged('Spawn Third-Person Follow Virtual Camera Rig');
end;

procedure TVirtualCameraForm.BtnSpawnDollyRailClick(Sender: TObject);
begin
  TVirtualCameraHelper.EnsureBrainOnViewportCamera(FDesignRoot, FDesignOwner, 1.0);
  TVirtualCameraHelper.SpawnSplineDollyVCam(
    FDesignRoot, FDesignOwner, nil, 30, 'VCamDollyRail');
  NotifyChanged('Spawn Spline Dolly Rail Virtual Camera Rig');
end;

procedure TVirtualCameraForm.BtnToggleActiveRigClick(Sender: TObject);
var
  V: TCastleVirtualCamera;
begin
  V := CurrentVCam;
  if V = nil then
    Exit;
  V.ActiveRig := not V.ActiveRig;
  TVirtualCameraHelper.StepAllCameraBrains(FDesignRoot, FDesignOwner, 0.0);
  NotifyChanged('Toggle Virtual Camera ActiveRig ' + V.Name);
end;

procedure TVirtualCameraForm.BtnApplyRigParamsClick(Sender: TObject);
var
  V: TCastleVirtualCamera;
begin
  V := CurrentVCam;
  if V = nil then
    Exit;
  V.Priority := StrToIntDef(Trim(EditPriority.Text), V.Priority);
  V.FieldOfViewDeg := StrToFloatDefDot(Trim(EditFov.Text), V.FieldOfViewDeg);
  V.DollyNormalizedT := StrToFloatDefDot(Trim(EditDollyT.Text), V.DollyNormalizedT);
  TVirtualCameraHelper.StepAllCameraBrains(FDesignRoot, FDesignOwner, 0.0);
  NotifyChanged('Update Virtual Camera Rig Parameters');
end;

procedure TVirtualCameraForm.BtnTriggerTraumaClick(Sender: TObject);
begin
  TVirtualCameraHelper.EnsureBrainOnViewportCamera(FDesignRoot, FDesignOwner, 1.0);
  TVirtualCameraHelper.TriggerTraumaOnAllBrains(FDesignRoot, FDesignOwner, 0.6);
  TVirtualCameraHelper.StepAllCameraBrains(FDesignRoot, FDesignOwner, 0.05);
  NotifyChanged('Trigger Virtual Camera Perlin Trauma Shake');
end;

procedure TVirtualCameraForm.BtnStepDirectorClick(Sender: TObject);
begin
  TVirtualCameraHelper.StepAllCameraBrains(FDesignRoot, FDesignOwner, 0.1);
  NotifyChanged('Step Virtual Camera Director (+0.1s)');
end;

procedure TVirtualCameraForm.ComboBlendCurveChange(Sender: TObject);
var
  B: TCastleVirtualCameraBrain;
begin
  B := CurrentBrain;
  if (B = nil) or (ComboBlendCurve.ItemIndex < 0) then
    Exit;
  B.BlendCurve := TVirtualCameraBlendCurve(ComboBlendCurve.ItemIndex);
  NotifyChanged('Change Virtual Camera Blend Curve');
end;

procedure TVirtualCameraForm.BtnCopyMarkdownClick(Sender: TObject);
begin
  Clipboard.AsText := TVirtualCameraHelper.BuildMarkdownReport(FDesignRoot, FDesignOwner);
end;

procedure TVirtualCameraForm.BtnCloseClick(Sender: TObject);
begin
  Close;
end;

procedure TVirtualCameraForm.PaintHudPaint(Sender: TObject);
var
  C: TCanvas;
  W, H, FrameW, FrameH, CX, CY, DzW, DzH, BarW, TraumaW, ShakeW, I, PX, PY: Integer;
  V: TCastleVirtualCamera;
  B: TCastleVirtualCameraBrain;
  TraumaVal, FovDeg: Single;
begin
  C := PaintHud.Canvas;
  W := PaintHud.Width;
  H := PaintHud.Height;

  C.Brush.Color := RGBToColor(20, 24, 32);
  C.FillRect(0, 0, W, H);

  V := CurrentVCam;
  if V = nil then
    V := FReport.WinningVCam;
  B := CurrentBrain;

  if V <> nil then
    FovDeg := Max(15.0, V.FieldOfViewDeg)
  else
    FovDeg := 55.0;

  { Left panel: Screen-Space Deadzone & Rule-of-Thirds Viewfinder }
  FrameW := Min(380, (W div 2) - 24);
  FrameH := Round(FrameW * 9.0 / 16.0);
  CX := 20 + FrameW div 2;
  CY := 38 + FrameH div 2;

  C.Pen.Color := RGBToColor(70, 90, 120);
  C.Brush.Color := RGBToColor(14, 17, 23);
  C.Rectangle(CX - FrameW div 2, CY - FrameH div 2, CX + FrameW div 2, CY + FrameH div 2);

  { Rule of thirds }
  C.Pen.Color := RGBToColor(42, 52, 68);
  C.Line(CX - FrameW div 6, CY - FrameH div 2, CX - FrameW div 6, CY + FrameH div 2);
  C.Line(CX + FrameW div 6, CY - FrameH div 2, CX + FrameW div 6, CY + FrameH div 2);
  C.Line(CX - FrameW div 2, CY - FrameH div 6, CX + FrameW div 2, CY - FrameH div 6);
  C.Line(CX - FrameW div 2, CY + FrameH div 6, CX + FrameW div 2, CY + FrameH div 6);

  { Deadzone rectangle }
  if V <> nil then
  begin
    DzW := Max(14, Round(FrameW * (V.DeadzoneWidthDeg / FovDeg)));
    DzH := Max(10, Round(FrameH * (V.DeadzoneHeightDeg / (FovDeg * 0.5625))));
  end else
  begin
    DzW := 76;
    DzH := 52;
  end;

  C.Pen.Color := RGBToColor(72, 214, 152);
  C.Pen.Width := 2;
  C.Brush.Style := bsClear;
  C.Rectangle(CX - DzW div 2, CY - DzH div 2, CX + DzW div 2, CY + DzH div 2);
  C.Pen.Width := 1;

  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(220, 232, 248);
  C.TextOut(20, 12, Format('Deadzone Aim Composer Viewfinder (FOV %.1f°)', [FovDeg]));

  { Right panel: Trauma vs Trauma^2 Shake Envelope & Perlin Waveform }
  if B <> nil then
    TraumaVal := B.Trauma
  else
    TraumaVal := 0.0;

  BarW := Max(120, W - (FrameW + 64));
  C.Font.Color := RGBToColor(220, 232, 248);
  C.TextOut(FrameW + 44, 12, Format('Trauma-Squared Perlin 3D Shake (Trauma = %.2f | ShakeAmp = %.2f)',
    [TraumaVal, TraumaVal * TraumaVal]));

  TraumaW := Round(BarW * Clamped(TraumaVal, 0.0, 1.0));
  ShakeW := Round(BarW * Clamped(TraumaVal * TraumaVal, 0.0, 1.0));

  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(38, 44, 58);
  C.Rectangle(FrameW + 44, 42, FrameW + 44 + BarW, 62);
  C.Brush.Color := RGBToColor(245, 178, 66);
  C.FillRect(FrameW + 44, 42, FrameW + 44 + TraumaW, 62);

  C.Brush.Color := RGBToColor(38, 44, 58);
  C.Rectangle(FrameW + 44, 72, FrameW + 44 + BarW, 92);
  C.Brush.Color := RGBToColor(242, 92, 92);
  C.FillRect(FrameW + 44, 72, FrameW + 44 + ShakeW, 92);

  { Perlin 1D waveform preview }
  C.Pen.Color := RGBToColor(96, 188, 255);
  for I := 0 to BarW - 1 do
  begin
    PX := FrameW + 44 + I;
    PY := 175 - Round(55.0 * SampleCameraPerlin1D(I * 0.06, 101));
    if I = 0 then
      C.MoveTo(PX, PY)
    else
      C.LineTo(PX, PY);
  end;
end;

end.
